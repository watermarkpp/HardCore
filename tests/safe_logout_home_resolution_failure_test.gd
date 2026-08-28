extends Node

var _captured_error_reason := ""


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	var original_profile_directory := PlayerState.profile_directory
	var original_profile_index_path := PlayerState.profile_index_path
	var sandbox_id := "%d_%d" % [
		int(Time.get_unix_time_from_system()), OS.get_process_id()
	]
	var sandbox_root := (
		"user://safe_logout_home_resolution_failure/%s" % sandbox_id
	)
	PlayerState.profile_directory = sandbox_root.path_join("characters")
	PlayerState.profile_index_path = sandbox_root.path_join("profiles.json")
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PlayerState.profile_directory)
	)
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var create_result := PlayerState.create_character(
		"Q0B失败测试", "战士", "男"
	)
	assert(
		create_result.is_empty(),
		"isolated test character must be created: %s" % create_result
	)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	# Establish a valid prior safe-logout record.
	assert(
		PlayerState.save_safe_logout(910001, Vector2(100.0, 120.0), Vector2(1.0, 1.0)),
		"prior safe-logout record must be saved"
	)
	var player_position_before: Vector2 = game.player.global_position

	# Force every formal Home source to be invalid (test hook).
	game._test_force_home_failure = true
	var result: Dictionary = game._prepare_safe_logout()
	assert(
		not bool(result.get("success", true)),
		"prepare_safe_logout must fail when Home resolution fails"
	)
	assert(
		not bool(result.get("save_performed", true)),
		"no save may be performed when Home resolution fails"
	)
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"valid prior safe-logout position must not be overwritten"
	)
	assert(PlayerState.saved_map_id == 910001, "valid prior map must not change")
	assert(
		PlayerState.saved_position != Vector2.ZERO,
		"Vector2.ZERO must never be written"
	)
	assert(
		game.player.global_position == player_position_before,
		"player position must stay unchanged"
	)
	game.queue_free()
	PlayerState.profile_directory = original_profile_directory
	PlayerState.profile_index_path = original_profile_index_path
	print("SAFE_LOGOUT_HOME_RESOLUTION_FAILURE_TEST_PASS")
	get_tree().quit(0)
