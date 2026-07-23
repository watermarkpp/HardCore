extends Node


const LIVE_ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const EXHAUSTIVE_FRAME_IDS := [
	18,
	43,
	76,
	89,
	110,
	124,
	127,
	141,
	168,
	180,
	182,
	195,
	224,
	241,
]
const BOSS_ROOT_OFFSET_IDS := [76, 180, 195, 224]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest := MonsterVisual._ground_contact_manifest()
	assert(manifest.get("contract", "") == MonsterVisual.GROUND_CONTACT_CONTRACT)
	assert(int(manifest.get("summary", {}).get("monsterCount", 0)) == 214)
	assert(int(manifest.get("summary", {}).get("requiredDirections", 0)) == 8)
	var entries: Dictionary = manifest.get("entriesByMonsterId", {})
	assert(entries.size() == 214)
	var catalog_file := FileAccess.open(
		"res://assets/data/runtime/monster_animation_catalog.json",
		FileAccess.READ,
	)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text()) if catalog_file != null else null
	assert(catalog is Dictionary)
	var rows: Array = catalog.get("monsters", [])
	assert(rows.size() == 214)

	var player := PlayerCharacter.new()
	player.global_position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)

	var verified_count := 0
	for row: Dictionary in rows:
		var monster_id := int(row.monster_id)
		var monster_key := str(monster_id)
		assert(entries.has(monster_key), "monsterId=%d runtime calibration missing" % monster_id)
		var entry: Dictionary = entries[monster_key]
		var monster_data := GameData.get_monster_by_id(monster_id)
		assert(not monster_data.is_empty(), "monsterId=%d gameplay data missing" % monster_id)
		var enemy := EnemyActor.new()
		enemy.setup(monster_data, player, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		var visual: MonsterVisual = enemy.visual
		var sprite: Sprite2D = visual.sprite
		assert(visual.uses_final_art(), "monsterId=%d did not activate final art" % monster_id)
		assert(not visual.ground_contact_profile.is_empty(), "monsterId=%d has no ground projection profile" % monster_id)
		assert(
			visual.ground_projection_strategy() in ["grounded", "flying", "hover"],
			"monsterId=%d has no projection strategy" % monster_id,
		)
		enemy.set_targeted(true)
		var fixed_contact := enemy.ground_indicator_center()
		var fixed_radii := enemy.ground_indicator_radii()
		var expected_offset := _vector2(entry.ringCenterOffset)
		var expected_radii := _vector2(entry.ringEllipseRadii)
		var expected_contact := visual.position + expected_offset
		assert(
			fixed_contact.is_equal_approx(expected_contact),
			"monsterId=%d runtime chain must be MonsterVisual.position + ringCenterOffset" % monster_id,
		)
		assert(
			visual.ground_contact_offset().is_equal_approx(expected_offset),
			"monsterId=%d runtime profile changed reviewed center" % monster_id,
		)
		assert(
			fixed_radii.is_equal_approx(expected_radii),
			"monsterId=%d runtime profile changed reviewed ellipse" % monster_id,
		)
		assert(
			absf(float(entry.ringVerticalSquash) - fixed_radii.y / fixed_radii.x) <= 0.0001,
			"monsterId=%d runtime ellipse changed reviewed squash" % monster_id,
		)
		if visual.ground_projection_strategy() in ["flying", "hover"]:
			assert(
				not visual.visual_foot_offset().is_equal_approx(visual.ground_contact_offset()),
				"monsterId=%d airborne body was not separated from ground projection" % monster_id,
			)

		for action_name: String in LIVE_ACTIONS:
			var frame_count := MonsterAnimationPolicy.frame_count(visual.active_resources, StringName(action_name))
			for direction in range(8):
				visual.current_state = action_name
				visual.current_direction = direction
				var frames := (
					range(frame_count)
					if monster_id in EXHAUSTIVE_FRAME_IDS
					else _representative_frames(frame_count)
				)
				for frame: int in frames:
					visual.current_frame = frame
					sprite.texture = visual.active_resources[action_name]
					sprite.region_rect = Rect2(
						frame * visual.frame_size.x,
						direction * visual.frame_size.y,
						visual.frame_size.x,
						visual.frame_size.y,
					)
					assert(
						enemy.ground_indicator_center().is_equal_approx(fixed_contact),
						"monsterId=%d %s direction=%d frame=%d moved ring center" % [
							monster_id,
							action_name,
							direction,
							frame,
						]
					)
					assert(
						enemy.ground_indicator_radii().is_equal_approx(fixed_radii),
						"monsterId=%d %s direction=%d frame=%d changed ring radii" % [
							monster_id,
							action_name,
							direction,
							frame,
						],
					)
					assert(
						enemy.ground_indicator_center().is_equal_approx(
							visual.position + visual.ground_contact_offset(),
						),
						"monsterId=%d %s direction=%d frame=%d duplicated or lost an origin offset" % [
							monster_id,
							action_name,
							direction,
							frame,
						],
					)
		enemy.queue_free()
		await get_tree().process_frame
		verified_count += 1

	assert(verified_count == 214)
	for monster_id: int in BOSS_ROOT_OFFSET_IDS:
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, true)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame
		var entry: Dictionary = entries[str(monster_id)]
		assert(enemy.visual.uses_final_art(), "boss monsterId=%d final art missing" % monster_id)
		assert(enemy.visual.position.is_equal_approx(Vector2(0.0, 6.0)))
		assert(
			enemy.ground_indicator_center().is_equal_approx(
				enemy.visual.position + _vector2(entry.ringCenterOffset),
			),
			"boss monsterId=%d lost the Boss visual-root offset" % monster_id,
		)
		enemy.queue_free()
		await get_tree().process_frame
	print("MONSTER_GROUND_CONTACT_RUNTIME_PASS 214 per-ID rings keep reviewed center/ellipse across five actions, eight directions and representative frames")
	get_tree().quit(0)


func _vector2(values: Array) -> Vector2:
	assert(values.size() == 2)
	return Vector2(float(values[0]), float(values[1]))


func _representative_frames(frame_count: int) -> Array[int]:
	assert(frame_count > 0)
	var frames: Array[int] = [0]
	var middle := floori(float(frame_count) / 2.0)
	if not frames.has(middle):
		frames.append(middle)
	var last := frame_count - 1
	if not frames.has(last):
		frames.append(last)
	return frames
