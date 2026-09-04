extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B退出测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	PlayerState.save_safe_logout(4, Vector2(100.0, 120.0), Vector2(1.0, 1.0))

	# Case 1: Home resolution failure must not quit the game.
	game._test_force_home_failure = true
	game._exit_game()
	assert(
		not get_tree().auto_accept_quit,
		"exit guard must keep the process alive"
	)
	var diagnostic: Dictionary = game.get_meta(
		"safe_logout_failure_diagnostic", {}
	)
	assert(
		str(diagnostic.get("action", "")) == "exit_game",
		"failure diagnostic must record exit_game"
	)

	# Case 2: save failure with a valid Home must also not quit.
	game._test_force_home_failure = false
	PlayerState.active_profile_id = ""
	var save_result: Dictionary = game._prepare_safe_logout()
	assert(
		not bool(save_result.get("success", true))
		and str(save_result.get("reason", "")) == "safe_logout_save_failed",
		"save failure must return an explicit failure"
	)
	game._exit_game()
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"existing record must survive a failed save path"
	)
	assert(
		_captured_error_reason.contains("exit_game"),
		"failure must be reported through the injected capture reporter"
	)

	game.queue_free()
	print("SAFE_LOGOUT_EXIT_GUARD_TEST_PASS")
	get_tree().quit(0)
