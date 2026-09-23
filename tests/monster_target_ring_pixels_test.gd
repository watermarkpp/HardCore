extends Node

var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _check(value: bool, message: String) -> void:
	if not value:
		failures.append(message)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	MonsterVisual.set_synchronous_loading_for_tests(true)
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/monster_target_ring_profiles.json"))
	_check(data.get("contract") == "monster.target_ring.posture_scale.v1", "formal ring posture contract")
	_check(is_equal_approx(data.crawling_scale, 1.3) and is_equal_approx(data.default_scale, 1.0), "user-approved 30 percent radius only")
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/runtime/monster_animation_catalog.json"))
	var verified := 0
	var enlarged := 0
	var unchanged := 0
	var seen := {}
	for row: Dictionary in catalog.monsters:
		var key := str(int(row.monster_id))
		seen[key] = true
		var enemy := EnemyActor.new()
		enemy.setup(GameData.get_monster_by_id(int(key)), null, false)
		add_child(enemy)
		enemy.set_physics_process(false)
		enemy.set_targeted(true)
		var physics_radius := enemy.collision_radius_px
		var base := enemy.ground_footprint_indicator_radii()
		var scale := 1.3 if data.crawling_monsters.has(key) else 1.0
		var expected := base * scale
		if scale > 1.0:
			enlarged += 1
		else:
			unchanged += 1
			_check(enemy.visual._selection_ring_direction_offsets.is_empty(), "non-crawler has no offset configuration: " + key)
		var foot := enemy.visual.target_ring_local_position()
		var anchor := enemy.visual.sprite.position
		for direction in range(8):
			enemy.facing = Vector2.from_angle(direction * TAU / 8.0)
			enemy.visual._process(0.0)
			var actual_row := enemy.visual.current_direction
			var values: Array = data.direction_offsets_px.get(key, {}).get(str(actual_row), [0, 0])
			var offset := Vector2(values[0], values[1])
			if scale == 1.0:
				_check(offset.is_zero_approx() and enemy.visual.selection_ring_direction_offset().is_zero_approx(), "non-crawler retains original center in every direction: " + key)
			if int(key) in [118,120,121,122,123,170]:
				_check(offset == (Vector2.ZERO if actual_row == 4 else Vector2(0, 10)), "long spider/pincer preserves S, offsets other seven directions")
			if actual_row == 4:
				_check(offset.is_zero_approx(), "all saved S feet unchanged")
			_check(enemy.ground_indicator_radii().is_equal_approx(expected), "fixed posture radius %s/%d" % [key, actual_row])
			_check(enemy.visual.selection_ring_local_position().is_equal_approx(foot + offset), "reviewed long-body selection offset %s/%d" % [key, actual_row])
			_check(enemy.visual.target_ring_local_position().is_equal_approx(foot) and enemy.visual.sprite.position.is_equal_approx(anchor), "calibrated foot/art unchanged %s/%d" % [key, actual_row])
			_check(is_equal_approx(enemy.collision_radius_px, physics_radius) and enemy.ground_footprint_indicator_radii().is_equal_approx(base), "physics and shadow footprint unchanged %s/%d" % [key, actual_row])
		enemy.queue_free()
		verified += 1
		await get_tree().process_frame
	for key: String in data.crawling_monsters:
		_check(seen.has(key), "reviewed crawling ID exists: " + key)
	for key: String in data.direction_offsets_px:
		_check(data.crawling_monsters.has(key), "direction offsets cannot include non-crawlers: " + key)
	var offset_ids: Array = data.direction_offsets_px.keys().map(func(key: String)->int:return int(key))
	offset_ids.sort()
	_check(offset_ids == [92,94,110,118,120,121,122,123,170], "only reviewed elongated crawling bodies receive directional offsets")
	_check(not data.crawling_monsters.has("64") and data.crawling_monsters.has("170") and data.crawling_monsters.has("172"), "standing Woma unchanged; broad spiders enlarged")
	_check(verified == GameData.monsters.size() and enlarged == 33 and unchanged == 123, "all 156 monsters; 33 crawling and 123 unchanged identities covered")
	for failure in failures.slice(0, 12):
		push_error(failure)
	print("MONSTER_TARGET_RING_PIXELS_%s monsters=%d enlarged=%d unchanged=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", verified, enlarged, unchanged, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
