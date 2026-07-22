extends Node


const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const FINAL_ART_CASES := [
	{"monster_id": 28, "boss": false},
	{"monster_id": 46, "boss": false},
	{"monster_id": 31, "boss": false},
	{"monster_id": 76, "boss": true},
]
const DIRECTIONS := [
	Vector2.UP,
	Vector2(1, -1),
	Vector2.RIGHT,
	Vector2(1, 1),
	Vector2.DOWN,
	Vector2(-1, 1),
	Vector2.LEFT,
	Vector2(-1, -1),
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var camera := Camera2D.new()
	camera.zoom = Vector2(1.35, 1.35)
	camera.enabled = true
	add_child(camera)
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO

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
		var overhead: Variant = enemy.get_node("MonsterOverhead")
		assert(visual.uses_final_art(), "monsterId=%d did not load final client art" % monster_id)
		var expected_y := visual.position.y + sprite.position.y - MonsterVisual.HEALTH_BAR_FRAME_MARGIN
		var fixed_y := enemy.health_bar_anchor_y()
		var fixed_bar_global_y: float = overhead.bar_global_top_y()
		var fixed_name_global_bottom_y: float = overhead.name_global_bottom_y()
		var fixed_gap: float = fixed_bar_global_y - fixed_name_global_bottom_y
		var fixed_bar_canvas_y: float = (overhead.get_global_transform_with_canvas() * Vector2.ZERO).y
		var fixed_name_canvas_bottom_y: float = (enemy.name_label.get_global_transform_with_canvas() * Vector2(EnemyActor.NAME_LABEL_SIZE.x * 0.5, EnemyActor.NAME_LABEL_SIZE.y)).y
		var fixed_canvas_gap: float = fixed_bar_canvas_y - fixed_name_canvas_bottom_y
		assert(is_equal_approx(fixed_y, expected_y), "monsterId=%d health bar is not anchored above the complete animation cell" % monster_id)
		assert(fixed_name_global_bottom_y < fixed_bar_global_y, "monsterId=%d name is not above the health bar" % monster_id)
		assert(is_equal_approx(fixed_gap, EnemyActor.NAME_LABEL_HEALTH_BAR_GAP), "monsterId=%d name/bar fixed gap changed: %s" % [monster_id, fixed_gap])
		assert(fixed_name_canvas_bottom_y < fixed_bar_canvas_y, "monsterId=%d camera/viewport transform put name below bar" % monster_id)
		assert(is_equal_approx(fixed_canvas_gap, fixed_gap * camera.zoom.y), "monsterId=%d camera zoom changed the overhead gap contract: %s" % [monster_id, fixed_canvas_gap])
		assert(enemy.get_child(enemy.get_child_count() - 1) == overhead, "monsterId=%d overhead is not the final actor render layer" % monster_id)

		var states := ["idle", "walk", "attack", "hit", "death"]
		for state: String in states:
			var frame_count := MonsterAnimationPolicy.frame_count(visual.active_resources, StringName(state))
			for direction: Vector2 in DIRECTIONS:
				for frame_index in range(frame_count):
					_prepare_visual_sample(visual, enemy, state, direction, frame_index, frame_count)
					visual._process(0.0)
					assert(visual.current_direction == visual._direction_row(direction), "monsterId=%d %s did not sample direction=%s" % [monster_id, state, direction])
					assert(visual.current_frame == frame_index, "monsterId=%d %s did not sample frame=%d" % [monster_id, state, frame_index])
					assert(is_equal_approx(enemy.health_bar_anchor_y(), fixed_y), "monsterId=%d %s direction=%s frame=%d moved health bar" % [monster_id, state, direction, frame_index])
					assert(is_equal_approx(overhead.bar_global_top_y(), fixed_bar_global_y), "monsterId=%d %s direction=%s frame=%d moved real bar node" % [monster_id, state, direction, frame_index])
					assert(is_equal_approx(overhead.name_global_bottom_y(), fixed_name_global_bottom_y), "monsterId=%d %s direction=%s frame=%d moved real name node" % [monster_id, state, direction, frame_index])
					assert(overhead.name_global_bottom_y() < overhead.bar_global_top_y(), "monsterId=%d %s direction=%s frame=%d put name below bar" % [monster_id, state, direction, frame_index])
					assert(is_equal_approx(overhead.bar_global_top_y() - overhead.name_global_bottom_y(), fixed_gap), "monsterId=%d %s direction=%s frame=%d changed name/bar gap" % [monster_id, state, direction, frame_index])
					assert(is_equal_approx((overhead.get_global_transform_with_canvas() * Vector2.ZERO).y, fixed_bar_canvas_y), "monsterId=%d %s direction=%s frame=%d moved real bar after camera transform" % [monster_id, state, direction, frame_index])
					assert(is_equal_approx((enemy.name_label.get_global_transform_with_canvas() * Vector2(EnemyActor.NAME_LABEL_SIZE.x * 0.5, EnemyActor.NAME_LABEL_SIZE.y)).y, fixed_name_canvas_bottom_y), "monsterId=%d %s direction=%s frame=%d moved real name after camera transform" % [monster_id, state, direction, frame_index])
		enemy.queue_free()
		await get_tree().process_frame

	var fallback := EnemyActor.new()
	fallback.setup({"monsterId": -999, "name": "fallback_anchor", "hp": 10}, player, false)
	add_child(fallback)
	fallback.set_physics_process(false)
	await get_tree().process_frame
	assert(not fallback.visual.uses_final_art(), "fallback fixture unexpectedly resolved final art")
	assert(is_equal_approx(fallback.health_bar_anchor_y(), -40.0), "procedural fallback health bar position changed")

	assert(MonsterVisual.OVERHEAD_ANCHOR_CONTRACT == "monster.overhead_anchor.v3", "stable overhead anchor contract changed")
	assert(MonsterOverheadScript.LAYOUT_CONTRACT == "monster.overhead_layout.v3", "stable overhead layout contract changed")
	print("MONSTER_HEALTH_BAR_ANCHOR_PASS real name/bar nodes remain ordered above the full animation cell across every direction, action, and frame")
	get_tree().quit(0)


func _prepare_visual_sample(visual: MonsterVisual, enemy: EnemyActor, state: String, direction: Vector2, frame_index: int, frame_count: int) -> void:
	visual._attack_remaining = 0.0
	visual._hit_remaining = 0.0
	visual._death_remaining = 0.0
	enemy.facing = direction
	enemy.movement_facing = direction
	enemy.velocity = direction * 50.0 if state == "walk" else Vector2.ZERO
	visual._last_state = state
	if state in ["attack", "hit", "death"]:
		visual._action_duration = 1.0
		visual._elapsed = (float(frame_index) + 0.25) / float(maxi(1, frame_count))
		if state == "attack":
			visual._attack_remaining = 1.0
		elif state == "hit":
			visual._hit_remaining = 1.0
		else:
			visual._death_remaining = 1.0
	else:
		var fps := MonsterAnimationPolicy.loop_fps(StringName(state))
		visual._elapsed = (float(frame_index) + 0.25) / maxf(fps, 0.001)
