extends Node

var _captured_error_reason := ""
var _saved_persistence: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	_configure_isolated_persistence("exit_guard")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var create_result := PlayerState.create_character("Q0B退出测试", "战士", "男")
	assert(create_result.is_empty(), "isolated character creation failed: %s" % create_result)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	var home_map_id := GameData.service_home_runtime_map_id(false)
	assert(home_map_id >= 0, "formal service Home map must resolve")
	assert(
		PlayerState.save_safe_logout(
			home_map_id, Vector2(100.0, 120.0), Vector2(1.0, 1.0)
		),
		"existing safe-logout fixture record must be saved"
	)

	# Case 1: Drive the real paused menu signal into _exit_game. Home
	# resolution failure must keep the menu visible with an in-layer message.
	game.call("_show_system_menu")
	assert(get_tree().paused, "opening the real system menu must pause the world")
	assert(game._system_menu_panel.visible, "real system menu must be visible")
	game._test_force_home_failure = true
	game._system_menu_panel.call("_request_save_exit")
	assert(
		not get_tree().auto_accept_quit,
		"exit guard must keep the process alive"
	)
	assert(
		get_tree().paused,
		"Home failure must retain the pause boundary for retry"
	)
	assert(
		game._system_menu_panel.save_exit_failure_label.is_visible_in_tree()
			and not game._system_menu_panel.save_exit_failure_label.text.is_empty(),
		"Home failure must be visible in the paused menu layer"
	)
	var diagnostic: Dictionary = game.get_meta(
		"safe_logout_failure_diagnostic", {}
	)
	assert(
		str(diagnostic.get("action", "")) == "exit_game",
		"failure diagnostic must record exit_game"
	)
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"Home failure must not overwrite the existing save"
	)
	game._system_menu_panel.call("_request_continue")
	assert(not get_tree().paused, "Continue must close the menu and release pause")

	# Case 2: save failure with a valid Home must follow the same real signal
	# path and leave the existing record intact.
	game._test_force_home_failure = false
	game.call("_show_system_menu")
	assert(get_tree().paused, "retry menu must reacquire the pause boundary")
	PlayerState.active_profile_id = ""
	game._system_menu_panel.call("_request_save_exit")
	assert(
		PlayerState.saved_position == Vector2(100.0, 120.0),
		"existing record must survive a failed save path"
	)
	assert(
		get_tree().paused
			and game._system_menu_panel.save_exit_failure_label.is_visible_in_tree()
			and not game._system_menu_panel.save_exit_failure_label.text.is_empty(),
		"save failure must remain visible in the paused menu layer"
	)
	var save_diagnostic: Dictionary = game.get_meta(
		"safe_logout_failure_diagnostic", {}
	)
	assert(
		str(save_diagnostic.get("reason", "")) == "safe_logout_save_failed",
		"save failure must retain the explicit failure reason"
	)
	assert(
		_captured_error_reason.contains("exit_game"),
		"failure must be reported through the injected capture reporter"
	)
	game._system_menu_panel.call("_request_continue")
	assert(not get_tree().paused, "Continue must close the failed-save menu")

	game.queue_free()
	_restore_persistence()
	print("SAFE_LOGOUT_EXIT_GUARD_TEST_PASS")
	get_tree().quit(0)


func _configure_isolated_persistence(case_name: String) -> void:
	_saved_persistence = {
		"profile_directory": PlayerState.profile_directory,
		"profile_index_path": PlayerState.profile_index_path,
		"shared_warehouse_path": PlayerState.shared_warehouse_path,
		"transaction_path": PlayerState.shared_warehouse_transaction_log_path,
		"test_mode": PlayerState.test_mode,
		"active_profile_id": PlayerState.active_profile_id,
		"warehouse_inventory": PlayerState.warehouse_inventory.duplicate(true),
		"shared_initialized": PlayerState._shared_warehouse_initialized,
		"warehouse_locked": PlayerState._warehouse_transaction_locked,
		"persistence_in_progress": PlayerState._persistence_transaction_in_progress,
		"save_blocked_profile_id": PlayerState._save_blocked_profile_id,
		"save_blocked_reason": PlayerState._save_blocked_reason,
	}
	var sandbox_root := "user://safe_logout_%s/%d_%d" % [
		case_name, Time.get_ticks_usec(), OS.get_process_id()
	]
	PlayerState.profile_directory = sandbox_root.path_join("characters")
	PlayerState.profile_index_path = sandbox_root.path_join("profiles.json")
	PlayerState.shared_warehouse_path = sandbox_root.path_join("shared.json")
	PlayerState.shared_warehouse_transaction_log_path = sandbox_root.path_join(
		"shared.transaction.json"
	)
	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(PlayerState.profile_directory)
	)
	PlayerState.active_profile_id = ""
	PlayerState.warehouse_inventory = []
	PlayerState._shared_warehouse_initialized = false
	PlayerState._warehouse_transaction_locked = false
	PlayerState._persistence_transaction_in_progress = false
	PlayerState._save_blocked_profile_id = ""
	PlayerState._save_blocked_reason = ""


func _restore_persistence() -> void:
	PlayerState.profile_directory = str(_saved_persistence.profile_directory)
	PlayerState.profile_index_path = str(_saved_persistence.profile_index_path)
	PlayerState.shared_warehouse_path = str(_saved_persistence.shared_warehouse_path)
	PlayerState.shared_warehouse_transaction_log_path = str(
		_saved_persistence.transaction_path
	)
	PlayerState.test_mode = bool(_saved_persistence.test_mode)
	PlayerState.active_profile_id = str(_saved_persistence.active_profile_id)
	PlayerState.warehouse_inventory = (
		_saved_persistence.warehouse_inventory as Array
	).duplicate(true)
	PlayerState._shared_warehouse_initialized = bool(_saved_persistence.shared_initialized)
	PlayerState._warehouse_transaction_locked = bool(_saved_persistence.warehouse_locked)
	PlayerState._persistence_transaction_in_progress = bool(
		_saved_persistence.persistence_in_progress
	)
	PlayerState._save_blocked_profile_id = str(
		_saved_persistence.save_blocked_profile_id
	)
	PlayerState._save_blocked_reason = str(_saved_persistence.save_blocked_reason)
