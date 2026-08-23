extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.create_character("Q0B守卫测试", "战士", "男")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	PlayerState.save_safe_logout(4, Vector2(100.0, 120.0), Vector2(1.0, 1.0))
	game._test_force_home_failure = true
	var map_before: int = game.current_map_id
	var scene_before: Node = get_tree().current_scene

	game._return_to_character_select()
	# The safe-logout record must be preserved by the failed flow itself; assert
	# before the next _process frame because the live world-location updater
	# writes the player position into the same fields every frame.
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"existing safe-logout record must be preserved"
	)
	await get_tree().process_frame
	await get_tree().process_frame

	assert(
		get_tree().current_scene == scene_before,
		"failed safe logout must not switch to character select"
	)
	assert(
		is_instance_valid(game.player),
		"world must not be torn down on failed safe logout"
	)
	assert(game.current_map_id == map_before, "map must stay unchanged")
	var diagnostic: Dictionary = game.get_meta(
		"safe_logout_failure_diagnostic", {}
	)
	assert(
		str(diagnostic.get("action", "")) == "return_to_character_select",
		"failure diagnostic must record the guarded action"
	)
	assert(
		_captured_error_reason.begins_with("return_to_character_select"),
		"failure must be reported through the injected capture reporter"
	)

	game.queue_free()
	print("SAFE_LOGOUT_CHARACTER_SELECT_GUARD_TEST_PASS")
	get_tree().quit(0)
