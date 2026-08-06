extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B1门点测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game._test_force_home_failure = true
	# A target with no matching portal plus invalid Home must yield no result.
	var portal_result: Vector2 = game._bich_portal_screen_position_px_to(9999)
	assert(
		portal_result == Vector2.INF,
		"portal lookup must return an explicit no-result sentinel, not the current position"
	)
	assert(
		portal_result != Vector2(321.0, 654.0),
		"portal lookup must never return the current player position"
	)

	game.queue_free()
	print("PORTAL_HOME_LOOKUP_FAILURE_TEST_PASS")
	get_tree().quit(0)
