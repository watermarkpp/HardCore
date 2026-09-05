extends Node

var _captured_error_reason := ""
var _saved_persistence: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	_configure_isolated_persistence("existing_state_preservation")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var create_result := PlayerState.create_character("Q0B保留测试", "战士", "男")
	assert(create_result.is_empty(), "isolated character creation failed: %s" % create_result)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	var expected_position := Vector2(100.0, 120.0)
	var expected_ground := Vector2(1.0, 1.0)
	var home_map_id := GameData.service_home_runtime_map_id(false)
	assert(home_map_id >= 0, "formal service Home map must resolve")
	assert(
		PlayerState.save_safe_logout(home_map_id, expected_position, expected_ground),
		"prior record must be saved"
	)
	var map_before := PlayerState.saved_map_id
	var position_before := PlayerState.saved_position
	var ground_before := PlayerState.saved_ground_position_gu
	var ground_valid_before := PlayerState.saved_ground_position_gu_valid

	game._test_force_home_failure = true
	var result: Dictionary = game._prepare_safe_logout()
	assert(
		not bool(result.get("success", true)),
		"prepare must fail on invalid Home"
	)

	# Every field of the existing valid record must be preserved field-by-field.
	assert(PlayerState.saved_map_id == map_before, "map_id must stay unchanged")
	assert(
		PlayerState.saved_position == position_before,
		"position must stay unchanged"
	)
	assert(
		PlayerState.saved_position == expected_position
		and PlayerState.saved_position != Vector2.ZERO,
		"position must remain the valid non-zero record"
	)
	assert(
		PlayerState.saved_ground_position_gu == ground_before,
		"ground position must stay unchanged"
	)
	assert(
		PlayerState.saved_ground_position_gu_valid == ground_valid_before,
		"ground validity flag must stay unchanged"
	)

	game.queue_free()
	_restore_persistence()
	print("SAFE_LOGOUT_EXISTING_STATE_PRESERVATION_TEST_PASS")
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
