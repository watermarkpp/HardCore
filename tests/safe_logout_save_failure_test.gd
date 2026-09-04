extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B保存失败测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	PlayerState.save_safe_logout(4, Vector2(100.0, 120.0), Vector2(1.0, 1.0))

	# Home resolves (no hook), but the active profile is gone so the save fails.
	PlayerState.active_profile_id = ""
	var result: Dictionary = game._prepare_safe_logout()
	assert(
		not bool(result.get("success", true)),
		"prepare_safe_logout must fail when the save fails"
	)
	assert(
		str(result.get("reason", "")) == "safe_logout_save_failed",
		"save failure must report safe_logout_save_failed"
	)
	assert(
		not bool(result.get("save_performed", true)),
		"save_performed must be false"
	)

	var scene_before: Node = get_tree().current_scene
	game._return_to_character_select()
	await get_tree().process_frame
	assert(
		get_tree().current_scene == scene_before,
		"failed save must not switch to character select"
	)
	game._exit_game()
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"existing record must survive save failure"
	)
	assert(
		_captured_error_reason.contains("safe_logout_save_failed"),
		"save failure must be reported through the injected capture reporter"
	)

	game.queue_free()
	print("SAFE_LOGOUT_SAVE_FAILURE_TEST_PASS")
	get_tree().quit(0)
