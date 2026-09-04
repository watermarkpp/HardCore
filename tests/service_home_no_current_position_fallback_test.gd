extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1回城测试", "战士", "男")
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
	var zone_content_before: int = get_tree().get_nodes_in_group("zone_content").size()

	var accepted: bool = game.travel_to_service_home(false, false)
	assert(
		not accepted,
		"travel_to_service_home must reject an invalid Home"
	)
	assert(
		not game._map_transition_in_progress,
		"no map transition may start"
	)
	assert(game.current_map_id == map_before, "map must stay unchanged")
	assert(
		game.player.global_position == position_before,
		"player must not move"
	)
	assert(
		get_tree().get_nodes_in_group("zone_content").size() == zone_content_before,
		"world must not be cleared"
	)
	assert(
		_captured_error_reason.contains("service_home"),
		"service-home failure must be reported"
	)

	game.queue_free()
	print("SERVICE_HOME_NO_CURRENT_POSITION_FALLBACK_TEST_PASS")
	get_tree().quit(0)
