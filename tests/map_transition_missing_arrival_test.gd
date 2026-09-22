extends Node

const MAX_READY_WAIT_FRAMES := 1800

var _captured_error_reason := ""
var _saved_persistence: Dictionary = {}


func _ready() -> void:
	_run.call_deferred()


func _capture_safe_logout_error(action: StringName, reason: String) -> void:
	_captured_error_reason = "%s:%s" % [str(action), reason]


func _run() -> void:
	_configure_isolated_persistence("map_transition_missing_arrival")
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var create_result := PlayerState.create_character("Q0B1落点测试", "战士", "男")
	assert(create_result.is_empty(), "isolated character creation failed: %s" % create_result)
	assert(PlayerState.save_game(), "initial isolated profile save must succeed")
	var service_home_map_id := GameData.service_home_runtime_map_id(false)
	assert(service_home_map_id >= 0, "formal service Home map must resolve")
	assert(
		MapEditorRuntimeBridge.is_formal_playable(service_home_map_id),
		"formal service Home map must be playable"
	)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	assert(
		await _wait_for_world_ready(game, service_home_map_id),
		"initial formal Home world must reach READY"
	)
	game.set_safe_logout_error_reporter(
		Callable(self, "_capture_safe_logout_error")
	)

	var source_map_data := _formal_non_home_map(service_home_map_id)
	var source_map_id := int(source_map_data.get("mapId", -1))
	var source_operation := Callable(
		game, "_travel_to_map_immediate"
	).bind(source_map_id)
	assert(
		game._begin_map_transition(source_operation, source_map_id),
		"formal non-Home fixture transition must start"
	)
	assert(
		await _wait_for_world_ready(game, source_map_id),
		"formal non-Home fixture transition must reach READY"
	)
	assert(game.current_map_id == source_map_id, "fixture source map mismatch")
	assert(
		int(game.current_map_data.get("mapId", -1)) == source_map_id,
		"fixture source map data mismatch"
	)
	assert(
		not MapEditorRuntimeBridge.load_map(source_map_id).is_empty(),
		"fixture source runtime map must be loaded from formal authority"
	)
	assert(
		game._world_bootstrap_coordinator.stage
		== WorldBootstrapCoordinator.Stage.READY,
		"fixture source coordinator must remain READY"
	)

	game.player.global_position = Vector2(321.0, 654.0)
	game._test_force_home_failure = true
	var map_before: int = game.current_map_id
	var position_before: Vector2 = game.player.global_position
	assert(map_before != service_home_map_id, "fixture must bypass same-map early return")

	# The production arrival gate must reject the formal service Home target.
	var arrival: Dictionary = game._pipeline_arrival_position(service_home_map_id)
	assert(
		not bool(arrival.get("valid", true)),
		"pipeline arrival must be invalid when Home cannot resolve"
	)

	# The production pipeline gate must fail the transition and record the
	# diagnostic instead of entering READY.
	_captured_error_reason = ""
	var pipeline_ok: bool = await game._run_world_build_pipeline(
		service_home_map_id, "q0b1_test"
	)
	assert(
		not pipeline_ok,
		"world build pipeline must fail without a target arrival"
	)
	assert(
		game._world_bootstrap_coordinator.stage
		== WorldBootstrapCoordinator.Stage.FAILED,
		"coordinator must reach FAILED"
	)
	var pipeline_diagnostic: Dictionary = game.get_meta(
		"home_resolution_failure_diagnostic", {}
	)
	assert(
		str(pipeline_diagnostic.get("action", "")) == "world_pipeline_arrival",
		"pipeline arrival failure must be recorded"
	)

	# Sync travel to the formal service Home with no arrival must not switch maps.
	_captured_error_reason = ""
	var travelled: bool = game._travel_to_map_immediate(service_home_map_id)
	assert(not travelled, "service Home travel must fail without a Home")
	assert(game.current_map_id == map_before, "map must stay unchanged")
	assert(
		game.player.global_position == position_before,
		"player must not be placed from the current position"
	)
	assert(
		not game._map_transition_in_progress,
		"no transition may be in progress"
	)
	# A resolved Home must retain the existing route-arrival contract.
	game._test_force_home_failure = false
	var expected_arrival: Vector2 = game.route_arrival_position(service_home_map_id, map_before)
	assert(expected_arrival.is_finite(), "normal Home route must provide a finite arrival")
	assert(game._travel_to_map_immediate(service_home_map_id), "resolved Home travel must succeed")
	assert(game.current_map_id == service_home_map_id)
	assert(game.player.global_position.is_equal_approx(expected_arrival), "normal Home route arrival changed")

	game.queue_free()
	_restore_persistence()
	print("MAP_TRANSITION_MISSING_ARRIVAL_TEST_PASS")
	get_tree().quit(0)


func _wait_for_world_ready(game: Node, expected_map_id: int) -> bool:
	for _frame: int in range(MAX_READY_WAIT_FRAMES):
		if (
			not bool(game._map_transition_in_progress)
			and game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.READY
			and int(game.current_map_id) == expected_map_id
		):
			return true
		if (
			game._world_bootstrap_coordinator.stage
			== WorldBootstrapCoordinator.Stage.FAILED
		):
			return false
		await get_tree().process_frame
	return false


func _formal_non_home_map(service_home_map_id: int) -> Dictionary:
	var selected: Dictionary = {}
	var selected_map_id := -1
	for raw_map: Variant in GameData.get_available_maps(false):
		if not raw_map is Dictionary:
			continue
		var map_data := raw_map as Dictionary
		var map_id := int(map_data.get("mapId", -1))
		if (
			map_id < 0
			or map_id == service_home_map_id
			or not MapEditorRuntimeBridge.is_formal_playable(map_id)
		):
			continue
		if selected_map_id < 0 or map_id < selected_map_id:
			selected = map_data.duplicate(true)
			selected_map_id = map_id
	assert(
		not selected.is_empty(),
		"fixture requires a formal playable non-Home source map"
	)
	return selected


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
