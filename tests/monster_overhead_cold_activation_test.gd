extends Node


const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const SAMPLE_MONSTER_IDS := [21, 24, 28, 76]
const ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const REQUIRED_BODY_MARGIN := 8.0
const ASYNC_DEADLINE_MSEC := 20000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.global_position = Vector2.ZERO

	for monster_id: int in SAMPLE_MONSTER_IDS:
		MonsterVisual.reset_client_resource_cache()
		MonsterVisual.set_synchronous_loading_for_tests(false)
		var enemy := EnemyActor.new()
		enemy.setup({
			"monsterId": monster_id,
			"name": "cold_overhead_%d" % monster_id,
			"hp": 100,
			"attackMin": 1,
			"attackMax": 2,
		}, player, monster_id == 76)
		add_child(enemy)
		enemy.set_physics_process(false)
		await get_tree().process_frame

		var initial_fallback_y: float = enemy.overhead.position.y
		assert(not enemy.visual.uses_final_art(), "monsterId=%d did not begin on the cold async path" % monster_id)
		var prefetch := MonsterVisual.begin_map_prefetch([monster_id])
		var deadline_msec := Time.get_ticks_msec() + ASYNC_DEADLINE_MSEC
		while not bool(prefetch.complete) and Time.get_ticks_msec() < deadline_msec:
			prefetch = MonsterVisual.poll_streaming()
			await get_tree().process_frame
		assert(bool(prefetch.complete) and int(prefetch.failed) == 0, "monsterId=%d async profile failed: %s" % [monster_id, prefetch])

		enemy.visual._resource_residency_timer = 0.0
		enemy.visual._process(0.13)
		assert(enemy.visual.uses_final_art(), "monsterId=%d cold profile never activated final art" % monster_id)
		assert(not is_equal_approx(enemy.overhead.position.y, initial_fallback_y), "monsterId=%d retained fallback overhead y=%s after final texture activation" % [monster_id, initial_fallback_y])
		assert(is_equal_approx(enemy.overhead.position.y, enemy.visual._fixed_health_bar_y), "monsterId=%d overhead did not adopt the final-art anchor" % monster_id)
		_assert_stable_body_anchor_after_cold_activation(enemy, monster_id)

		enemy.queue_free()
		await get_tree().process_frame
		MonsterVisual.release_map_pins()

	MonsterVisual.reset_client_resource_cache()
	print("MONSTER_OVERHEAD_COLD_ACTIVATION_PASS small/medium/large/boss async profiles adopt stable per-monster body crowns")
	get_tree().quit(0)


func _assert_stable_body_anchor_after_cold_activation(enemy: EnemyActor, monster_id: int) -> void:
	var visual: MonsterVisual = enemy.visual
	var sprite: Sprite2D = visual.sprite
	var mapping: Dictionary = visual._client_mapping_for(enemy.monster_data)
	assert(not mapping.is_empty(), "monsterId=%d has no client mapping" % monster_id)
	var frame_values: Array = mapping.get("frameSize", [])
	var frame_size := Vector2i(int(frame_values[0]), int(frame_values[1]))
	var fixed_anchor_y: float = enemy.overhead.position.y
	var bar_bottom_canvas_y: float = (
		enemy.overhead.get_global_transform_with_canvas()
		* Vector2(0.0, MonsterOverheadScript.HEALTH_BAR_HEIGHT)
	).y
	var stable_body_top: float = visual.stable_body_top()
	var stable_body_top_canvas_y: float = (
		sprite.get_global_transform_with_canvas() * Vector2(0.0, stable_body_top)
	).y
	assert(
		is_equal_approx(stable_body_top_canvas_y - bar_bottom_canvas_y, REQUIRED_BODY_MARGIN),
		"monsterId=%d cold anchor body gap changed" % monster_id
	)
	var sampled_frames := 0
	for action_name: String in ACTIONS:
		var action: Dictionary = mapping.get("actions", {}).get(action_name, {})
		var frame_count := int(action.get("framesPerDirection", 0))
		var image := Image.load_from_file(ProjectSettings.globalize_path(str(action.get("path", ""))))
		assert(image != null and not image.is_empty(), "monsterId=%d failed alpha fixture %s" % [monster_id, action_name])
		for direction in range(8):
			for frame_index in range(frame_count):
				var alpha_top := _frame_alpha_top(image, Rect2i(frame_index * frame_size.x, direction * frame_size.y, frame_size.x, frame_size.y))
				assert(alpha_top >= 0, "monsterId=%d %s direction=%d frame=%d is empty" % [monster_id, action_name, direction, frame_index])
				sprite.texture = visual.active_resources[action_name]
				sprite.region_rect = Rect2(frame_index * frame_size.x, direction * frame_size.y, frame_size.x, frame_size.y)
				assert(is_equal_approx(enemy.overhead.position.y, fixed_anchor_y), "monsterId=%d changed overhead anchor while sampling %s direction=%d frame=%d" % [monster_id, action_name, direction, frame_index])
				sampled_frames += 1
	assert(sampled_frames > 0, "monsterId=%d sampled no final-art frames" % monster_id)
	assert(enemy.overhead.name_global_bottom_y() < enemy.overhead.bar_global_top_y(), "monsterId=%d name is not above the health bar" % monster_id)


func _frame_alpha_top(image: Image, rect: Rect2i) -> int:
	for local_y in range(rect.size.y):
		for local_x in range(rect.size.x):
			if image.get_pixel(rect.position.x + local_x, rect.position.y + local_y).a > 0.0:
				return local_y
	return -1
