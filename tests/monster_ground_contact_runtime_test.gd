extends Node


const SAMPLE_CASES := [
	{"monster_id": 24, "boss": false, "kind": "small"},
	{"monster_id": 47, "boss": false, "kind": "skeleton"},
	{"monster_id": 43, "boss": false, "kind": "bat"},
	{"monster_id": 76, "boss": true, "kind": "boss"},
]
const LIVE_ACTIONS := ["idle", "walk", "attack", "hit"]


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
		assert(not visual.ground_contact_offsets.is_empty(), "monsterId=%d has no ground contact profile" % monster_id)
		assert(not visual.ground_contact_offset().is_equal_approx(Vector2.ZERO), "monsterId=%d retained the universal visual origin" % monster_id)
		enemy.set_targeted(true)

		for action_name: String in LIVE_ACTIONS:
			var frame_count := MonsterAnimationPolicy.frame_count(visual.active_resources, StringName(action_name))
			for direction in range(8):
				visual.current_state = action_name
				visual.current_direction = direction
				var fixed_contact := visual.position + visual.ground_contact_offset()
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
						"monsterId=%d %s direction=%d frame=%d moved target ring" % [
							monster_id,
							action_name,
							direction,
							frame,
						]
					)
		enemy.queue_free()
		await get_tree().process_frame

	print("MONSTER_GROUND_CONTACT_RUNTIME_PASS small/skeleton/bat/boss use action-direction contacts without frame drift")
	get_tree().quit(0)
