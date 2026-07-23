extends Node


const SAMPLE_CASES := [
	{"monster_id": 24, "boss": false, "kind": "small_grounded"},
	{"monster_id": 46, "boss": false, "kind": "slender_grounded"},
	{"monster_id": 127, "boss": false, "kind": "flying"},
	{"monster_id": 168, "boss": false, "kind": "hover"},
	{"monster_id": 76, "boss": true, "kind": "large_boss"},
	{"monster_id": 180, "boss": true, "kind": "wide_boss"},
	{"monster_id": 195, "boss": true, "kind": "stationary_boss"},
]
const LIVE_ACTIONS := ["idle", "walk", "attack", "hit", "death"]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var manifest := MonsterVisual._ground_contact_manifest()
	assert(manifest.get("contract", "") == MonsterVisual.GROUND_CONTACT_CONTRACT)
	assert(int(manifest.get("summary", {}).get("monsterCount", 0)) == 214)
	assert(int(manifest.get("summary", {}).get("requiredDirections", 0)) == 8)

	var player := PlayerCharacter.new()
	player.global_position = Vector2.ZERO
	add_child(player)
	player.set_physics_process(false)

	for sample: Dictionary in SAMPLE_CASES:
		var monster_id := int(sample.monster_id)
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(monster_id), player, bool(sample.boss))
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
		assert(fixed_radii.x >= 8.0 and fixed_radii.y >= 3.0, "monsterId=%d ring radii invalid" % monster_id)
		if str(sample.kind) == "flying" or str(sample.kind) == "hover":
			assert(
				not visual.visual_foot_offset().is_equal_approx(visual.ground_contact_offset()),
				"monsterId=%d airborne body was not separated from ground projection" % monster_id,
			)
		elif str(sample.kind).contains("grounded"):
			assert(
				visual.visual_foot_offset().is_equal_approx(visual.ground_contact_offset()),
				"monsterId=%d grounded foot and projection diverged" % monster_id,
			)

		for action_name: String in LIVE_ACTIONS:
			var frame_count := MonsterAnimationPolicy.frame_count(visual.active_resources, StringName(action_name))
			for direction in range(8):
				visual.current_state = action_name
				visual.current_direction = direction
				for frame in range(frame_count):
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
		enemy.queue_free()
		await get_tree().process_frame

	print("MONSTER_GROUND_CONTACT_RUNTIME_PASS grounded/slender/flying/hover/large/boss keep per-ID center and ellipse across all actions/directions/frames")
	get_tree().quit(0)
