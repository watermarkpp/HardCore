extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1副作用测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game._test_force_home_failure = true
	var map_before: int = game.current_map_id
	var position_before: Vector2 = game.player.global_position

	# Side-effect entry: change_zone bich branch must not start a wrong move.
	game._change_zone_immediate("比奇城")
	assert(game.current_map_id == map_before, "change_zone must not switch map")
	assert(
		game.player.global_position == position_before,
		"change_zone must not move the player"
	)
	assert(
		_captured_error_reason.contains("change_zone_bich"),
		"change_zone must report the home-resolution failure"
	)

	# Side-effect entry: service-home immediate must not clear/move anything.
	_captured_error_reason = ""
	game._travel_to_service_home_immediate(false, false)
	assert(game.current_map_id == map_before, "service home must not switch map")
	assert(
		game.player.global_position == position_before,
		"service home must not move the player"
	)
	assert(
		_captured_error_reason.contains("service_home_immediate"),
		"service home must report the home-resolution failure"
	)

	# Side-effect entry: load_zone must not write the current position as Home.
	_captured_error_reason = ""
	var map_data := GameData.get_map_by_id(4)
	game._load_zone(str(map_data.get("name", "比奇省")), false, map_data)
	assert(
		game.player.global_position == position_before,
		"load_zone must not use the current position as Home"
	)
	assert(
		game.player.global_position != Vector2.ZERO,
		"load_zone must not write Vector2.ZERO"
	)

	# Side-effect entry: camp spawn must not use the current position.
	_captured_error_reason = ""
	var enemies_before: int = get_tree().get_nodes_in_group("enemies").size()
	game._spawn_authored_map_content(
		RegionContent.get_map_content(game.current_map_id)
	)
	assert(
		get_tree().get_nodes_in_group("enemies").size() == enemies_before,
		"camp spawn must not spawn at the current player position"
	)

	game.queue_free()
	print("HOME_RESOLUTION_SIDE_EFFECT_GUARD_TEST_PASS")
	get_tree().quit(0)
