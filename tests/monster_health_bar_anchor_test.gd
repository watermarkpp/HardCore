extends Node


const FINAL_ART_CASES := [
	{"monster_id": 31, "boss": false},
	{"monster_id": 76, "boss": true},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2(2000, 0)

	for sample: Dictionary in FINAL_ART_CASES:
		var monster_id := int(sample.monster_id)
		var enemy := EnemyActor.new()
		enemy.setup({
			"monsterId": monster_id,
			"name": "health_bar_anchor_%d" % monster_id,
			"hp": 100,
			"attackMin": 1,
			"attackMax": 2,
		}, player, bool(sample.boss))
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame

		var visual: MonsterVisual = enemy.get_node("MonsterVisual")
		var sprite: Sprite2D = visual.get_node("BodySprite")
		assert(visual.uses_final_art(), "monsterId=%d did not load final client art" % monster_id)
		var expected_y := visual.position.y + sprite.position.y - MonsterVisual.HEALTH_BAR_FRAME_MARGIN
		var fixed_y := enemy.health_bar_anchor_y()
		assert(is_equal_approx(fixed_y, expected_y), "monsterId=%d health bar is not anchored above the final frame" % monster_id)

		var states := ["idle", "walk", "attack", "hit", "death"]
		for state: String in states:
			enemy.facing = Vector2.RIGHT
			enemy.movement_facing = Vector2.RIGHT
			enemy.velocity = Vector2.RIGHT * 50.0 if state == "walk" else Vector2.ZERO
			if state == "attack":
				visual.play_attack(0.5)
			elif state == "hit":
				visual._attack_remaining = 0.0
				visual.play_hit(0.5)
			elif state == "death":
				visual.play_death(0.5)
			visual._process(0.05)
			assert(is_equal_approx(enemy.health_bar_anchor_y(), fixed_y), "monsterId=%d %s moved the health bar anchor" % [monster_id, state])
		enemy.queue_free()
		await get_tree().process_frame

	var fallback := EnemyActor.new()
	fallback.setup({"monsterId": -999, "name": "fallback_anchor", "hp": 10}, player, false)
	add_child(fallback)
	fallback.set_physics_process(false)
	await get_tree().process_frame
	assert(not fallback.visual.uses_final_art(), "fallback fixture unexpectedly resolved final art")
	assert(is_equal_approx(fallback.health_bar_anchor_y(), -40.0), "procedural fallback health bar position changed")

	print("MONSTER_HEALTH_BAR_ANCHOR_PASS final art uses a fixed frame-top anchor across all animation states")
	get_tree().quit(0)
