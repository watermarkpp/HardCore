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
	var manual_manifest := MonsterVisual._manual_alignment_manifest()
	assert(
		manual_manifest.get("contract", "")
		== "monster.ground_alignment.manual.v1"
	)
	var manual_entries: Dictionary = manual_manifest.get(
		"entriesByMonsterId", {}
	)
	assert(manual_entries.size() == 212)
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
		var final_shadow := visual.ground_shadow_layout_snapshot()
		assert(final_shadow.mode == "authored_cast_with_contact_core")
		assert(final_shadow.owner == "monster_visual")
		assert(bool(final_shadow.draw_contact_core))
		assert(final_shadow.contact_center_local.is_equal_approx(fixed_contact))
		assert(final_shadow.ring_center_local.is_equal_approx(fixed_contact))
		assert(final_shadow.radii.is_equal_approx(fixed_radii))
		var saved_resources := visual.active_resources
		var saved_authored_flag := visual._has_authored_client_art
		visual.active_resources = {}
		visual._has_authored_client_art = false
		var fallback_shadow := visual.ground_shadow_layout_snapshot()
		assert(fallback_shadow.mode == "procedural_fallback")
		assert(fallback_shadow.owner == "enemy")
		assert(not bool(fallback_shadow.draw_contact_core))
		visual.active_resources = saved_resources
		visual._has_authored_client_art = saved_authored_flag
		var expected_projection_offset := _vector2(entry.ringCenterOffset)
		var expected_radii := (
			WorldSpatialRules.actor_footprint_radii_px(enemy.collision_radius_px)
			* EnemyActor.TARGET_RING_FOOTPRINT_SCALE
		)
		var manual_entry: Dictionary = manual_entries.get(monster_key, {})
		var expected_root := (
			_vector2(manual_entry.runtimeVisualOrigin)
			+ _vector2(manual_entry.visualRootOffset)
			+ _manual_replay_displacement(enemy)
			if not manual_entry.is_empty()
			else Vector2(0.0, 4.0) + _vector2(entry.visualRootOffset)
		)
		var expected_visual_foot_offset := (
			(
				_vector2(manual_entry.visualFootOffset)
				- _manual_replay_displacement(enemy)
			)
			if not manual_entry.is_empty()
			else _vector2(entry.visualFootOffset)
		)
		var expected_runtime_projection_offset := (
			expected_projection_offset
			- _manual_replay_displacement(enemy)
			if (
				not manual_entry.is_empty()
				and visual.ground_projection_strategy() in ["flying", "hover"]
			)
			else expected_projection_offset
		)
		var replay_displacement := (
			visual.manual_alignment_replay_displacement()
		)
		assert(
			replay_displacement.is_equal_approx(
				_manual_replay_displacement(enemy)
				if not manual_entry.is_empty()
				else Vector2.ZERO
			),
			"monsterId=%d manual replay displacement is not collision-derived"
			% monster_id,
		)
		if not manual_entry.is_empty():
			assert(
				is_zero_approx(replay_displacement.x)
				and replay_displacement.y > 0.0,
				"monsterId=%d manual replay displacement must be S-only"
				% monster_id,
			)
		assert(
			visual.position.is_equal_approx(expected_root),
			"monsterId=%d runtime visual root did not apply the user alignment exactly once"
			% monster_id,
		)
		assert(
			visual.visual_root_offset().is_equal_approx(
				_vector2(entry.visualRootOffset)
			),
			"monsterId=%d runtime profile changed the user visual root offset"
			% monster_id,
		)
		var expected_contact := (
			visual.position + expected_runtime_projection_offset
			if visual.ground_projection_strategy() in ["flying", "hover"]
			else expected_root + expected_visual_foot_offset
		)
		assert(
			fixed_contact.is_equal_approx(expected_contact),
			"monsterId=%d ring center left the canonical targeting coordinate" % monster_id,
		)
		assert(
			visual.ground_contact_offset().is_equal_approx(
				expected_runtime_projection_offset
			),
			"monsterId=%d runtime projection did not normalize the authored S displacement"
			% monster_id,
		)
		if visual.ground_projection_strategy() == "grounded":
			assert(
				expected_contact.is_zero_approx(),
				"monsterId=%d complete manual origin did not resolve to the canonical foot"
				% monster_id,
			)
		assert(
			fixed_radii.is_equal_approx(expected_radii),
			"monsterId=%d target ring is not the enlarged physics footprint"
			% monster_id,
		)
		assert(
			absf(fixed_radii.y / fixed_radii.x - 0.5) <= 0.0001,
			"monsterId=%d target ring lost the 2:1 footprint ratio"
			% monster_id,
		)
		if monster_id in [97, 98]:
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
					var frame_shadow := visual.ground_shadow_layout_snapshot()
					assert(frame_shadow.contact_center_local.is_equal_approx(fixed_contact))
					assert(frame_shadow.radii.is_equal_approx(fixed_radii))
					assert(
						enemy.ground_indicator_center().is_equal_approx(
							visual.target_ring_position(Vector2.ZERO),
						),
						"monsterId=%d %s direction=%d frame=%d duplicated or lost a targeting origin offset" % [
							monster_id,
							action_name,
							direction,
							frame,
						],
					)
					assert(
						(
							visual.position
							+ visual.target_ring_local_position()
						).is_equal_approx(
							enemy.ground_indicator_center()
						),
						"monsterId=%d %s direction=%d frame=%d visual-owned ring diverged from target point" % [
							monster_id,
							action_name,
							direction,
							frame,
						],
					)
		if visual.ground_projection_strategy() == "grounded":
			var original_visual_position := visual.position
			var original_sprite_position := sprite.position
			var visual_delta := Vector2(13.5, -17.25)
			visual.position += visual_delta
			sprite.position += Vector2(-9.0, 11.0)
			assert(
				enemy.ground_indicator_center().is_equal_approx(
					fixed_contact + visual_delta
				),
				"monsterId=%d grounded ring did not follow the reviewed visual foot"
				% monster_id,
			)
			assert(
				enemy.ground_indicator_center().is_equal_approx(
					visual.ground_contact_position(Vector2.ZERO)
				),
				"monsterId=%d target ring and reviewed foot use different coordinates"
				% monster_id,
			)
			visual.position = original_visual_position
			sprite.position = original_sprite_position
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
		var manual_entry: Dictionary = manual_entries.get(
			str(monster_id), {}
		)
		var expected_root := (
			_vector2(manual_entry.runtimeVisualOrigin)
			+ _vector2(manual_entry.visualRootOffset)
			+ _manual_replay_displacement(enemy)
			if not manual_entry.is_empty()
			else Vector2(0.0, 6.0) + _vector2(entry.visualRootOffset)
		)
		assert(enemy.visual.uses_final_art(), "boss monsterId=%d final art missing" % monster_id)
		assert(
			enemy.visual.position.is_equal_approx(
				expected_root
			)
		)
		assert(
			enemy.ground_indicator_center().is_equal_approx(
				Vector2.ZERO,
			),
			"boss monsterId=%d grounded target ring inherited the Boss visual-root offset"
			% monster_id,
		)
		enemy.queue_free()
		await get_tree().process_frame
	print("MONSTER_GROUND_CONTACT_RUNTIME_PASS 212 manual origins replay exactly, grounded rings follow the reviewed foot, airborne rings keep authored projection, and all rings use 1.25x physics footprints")
	get_tree().quit(0)


func _vector2(values: Array) -> Vector2:
	assert(values.size() == 2)
	return Vector2(float(values[0]), float(values[1]))


func _manual_replay_displacement(enemy: EnemyActor) -> Vector2:
	return Vector2.DOWN * (
		enemy.collision_radius_px
		+ ArtSpec.PLAYER_COLLISION_RADIUS_PX
		+ MonsterVisual.MANUAL_ALIGNMENT_SPAWN_GAP
	) / MonsterVisual.MANUAL_ALIGNMENT_PREVIEW_ZOOM


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
