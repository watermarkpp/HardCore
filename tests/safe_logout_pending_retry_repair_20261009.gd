extends Node

const FrameBudgetScript := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const LootRuntimeScript := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const MONSTER_ID := 76
const RNG_SEED := 20261009
const WORLD_READY_FRAMES := 1800
const RECEIPT_WAIT_FRAMES := 900
const RECEIPT_DIR := "res://outputs/wake_drop_v108_review_followup_20261009/direct11_logout_identity"

var _game: Node
var _failures: Array[String] = []
var _checks := 0
var _reentrant_logout: Dictionary = {}
var _reentry_seen := false


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# Functional counter observation only; this fixture is not a performance
	# comparison.  Production counters remain disabled outside the test.
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	PlayerState.test_mode = false
	PlayerState.reset_progress(false)
	var creation_result := PlayerState.create_character(
		"LogoutPending%06d" % (Time.get_ticks_msec() % 1000000),
		"战士",
		"男",
	)
	_expect(creation_result.is_empty(), "formal character creation failed: %s" % creation_result)
	if not creation_result.is_empty():
		_finish()
		return
	var profile_id: String = PlayerState.active_profile_id
	_expect(not profile_id.is_empty(), "formal character creation did not publish profile id")
	_expect(PlayerState.select_character(profile_id), "formal character activation failed: %s" % PlayerState.last_load_result)
	_expect(PlayerState._world_clock_snapshot_sequence >= 0, "formal activation has no world-clock baseline")
	if not _failures.is_empty():
		_finish()
		return

	var preview_rng := RandomNumberGenerator.new()
	preview_rng.seed = RNG_SEED
	var preview_service: Variant = LootRuntimeScript.new()
	var preview: Dictionary = preview_service.roll_monster_drops(MONSTER_ID, preview_rng, true)
	preview_service.free()
	_expect(bool(preview.get("configured", false)), "producing monster profile unavailable: %s" % preview)
	_expect(
		not (preview.get("items", []) as Array).is_empty()
		or not (preview.get("gold_drops", []) as Array).is_empty(),
		"fixed seed produced no reward profile: %s" % preview,
	)

	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var ready := await _wait_for_world_ready()
	_expect(ready, "main bootstrap did not reach READY")
	_expect(is_instance_valid(_game.player), "production player is unavailable")
	if not _failures.is_empty():
		_finish()
		return

	_game._rng.seed = RNG_SEED
	var canonical: Dictionary = GameData.get_monster_by_id(MONSTER_ID)
	var death_snapshot: Dictionary = _game._build_enemy_death_runtime_snapshot(canonical)
	var expected_reward_plan: Dictionary = PlayerState._plan_kill_rewards([{
		"monster_name": str(death_snapshot.get("canonical_name", "")),
		"experience": int(death_snapshot.get("experience", 0)),
	}])
	_game.set_process(false)
	_expect(not PlayerState.profile_changed.is_connected(_on_reentrant_profile_changed), "reentry callback unexpectedly pre-connected")
	PlayerState.profile_changed.connect(_on_reentrant_profile_changed)
	var enemy := _make_enemy()
	_expect(is_instance_valid(enemy), "formal death fixture enemy unavailable")
	if is_instance_valid(enemy):
		enemy.current_hp = 1
		enemy.take_damage(1)

	var xp_before_death: int = PlayerState.experience
	var level_before_death: int = PlayerState.level
	var sequence_before_death: int = PlayerState._death_event_sequence
	var roll_count_before_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_roll_count"))
	var materialized_count_before_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count"))
	var terminal_count_before_success: int = _game._enemy_death_terminal_total_count
	var second_logout: Dictionary = _game._prepare_safe_logout()
	var terminal := _latest_terminal()
	_expect(_reentry_seen, "profile_changed did not observe real settlement reentry")
	_expect(not bool(_reentrant_logout.get("success", false)), "reentrant safe logout unexpectedly succeeded")
	_expect(str(_reentrant_logout.get("reason", "")) == "safe_logout_death_queue_pending", "reentrant logout returned wrong reason: %s" % _reentrant_logout)
	_expect(_game._last_death_logout_failure.is_empty(), "reentrant pending was latched as terminal failure")
	_expect(bool(second_logout.get("success", false)), "outer safe logout did not complete: %s" % second_logout)
	_expect(_game._pending_enemy_deaths.is_empty(), "second safe logout left death queue pending")
	_expect(str(terminal.get("state", "")) == "COMMITTED", "death did not commit exactly once: %s" % terminal)
	_expect(str(terminal.get("reward_status", "")) == "committed", "committed death has no reward status")
	_expect(int(terminal.get("materialized_node_count", 0)) > 0, "committed death materialized no ground reward")
	_expect(PlayerState._death_event_sequence == sequence_before_death + 1, "death receipt sequence was not applied once")
	_expect(PlayerState.level == int(expected_reward_plan.get("level_after", level_before_death)), "death receipt level does not match formal reward plan")
	_expect(PlayerState.experience == int(expected_reward_plan.get("experience_after", xp_before_death)), "death receipt remaining XP does not match formal reward plan")
	var terminal_transaction: Dictionary = terminal.get("transaction_result", {}) as Dictionary
	_expect(int(terminal_transaction.get("experience_gained", -1)) == int(expected_reward_plan.get("experience_gained", -1)), "receipt experience_gained differs from formal reward plan")
	_expect(PlayerState._json_persistence.pending_count() == 0, "safe logout left persistence pending")
	_expect(_game._last_death_logout_failure.is_empty(), "successful retry left terminal failure latch")
	var roll_count_after_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_roll_count"))
	var materialized_count_after_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count"))
	_expect(roll_count_after_success - roll_count_before_success == 1, "successful death did not create exactly one drop roll")
	_expect(materialized_count_after_success - materialized_count_before_success == int(terminal.get("materialized_node_count", 0)), "drop node counter disagrees with terminal materialization")
	_expect(_game._enemy_death_terminal_total_count == terminal_count_before_success + 1, "successful death added more than one terminal record")

	var xp_after_success: int = PlayerState.experience
	var sequence_after_success: int = PlayerState._death_event_sequence
	var roll_after_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_roll_count"))
	var nodes_after_success: int = int(RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count"))
	var terminals_after_success: int = _game._enemy_death_terminal_total_count
	var third_logout: Dictionary = _game._prepare_safe_logout()
	_expect(bool(third_logout.get("success", false)), "third safe logout did not remain idempotent: %s" % third_logout)
	_expect(PlayerState.experience == xp_after_success, "third safe logout changed XP")
	_expect(PlayerState._death_event_sequence == sequence_after_success, "third safe logout changed death sequence")
	_expect(int(RuntimeDiagnostics.performance_counter(&"drop_roll_count")) == roll_after_success, "third safe logout rerolled drops")
	_expect(int(RuntimeDiagnostics.performance_counter(&"drop_node_spawn_count")) == nodes_after_success, "third safe logout rematerialized drops")
	_expect(_game._enemy_death_terminal_total_count == terminals_after_success, "third safe logout added a terminal record")

	# Exercise the permanent failure gate through the real profile baseline
	# guard.  This is a second death and does not mutate the successful receipt.
	var blocked_enemy := _make_enemy()
	blocked_enemy.current_hp = 1
	blocked_enemy.take_damage(1)
	PlayerState._save_blocked_profile_id = PlayerState.active_profile_id
	var blocked_logout: Dictionary = _game._prepare_safe_logout()
	_expect(not bool(blocked_logout.get("success", true)), "blocked profile failure was allowed to logout")
	_expect(str(blocked_logout.get("reason", "")) == "safe_logout_death_queue_failed", "blocked profile returned wrong terminal failure: %s" % blocked_logout)
	_expect(not _game._last_death_logout_failure.is_empty(), "real failed settlement did not latch logout failure")
	PlayerState._save_blocked_profile_id = ""
	var fourth_logout: Dictionary = _game._prepare_safe_logout()
	_expect(not bool(fourth_logout.get("success", true)), "clearing profile block incorrectly bypassed terminal failure latch")
	_expect(
		str(fourth_logout.get("reason", "")) == "safe_logout_death_queue_failed",
		"latched terminal failure changed reason after profile unblock: %s" % fourth_logout,
	)
	_expect(not _game._last_death_logout_failure.is_empty(), "terminal failure latch was cleared by a later logout")

	_write_receipt({
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"failures": _failures.duplicate(),
		"checks": _checks,
		"reentry_seen": _reentry_seen,
		"reentrant_logout": _reentrant_logout,
		"second_logout": second_logout,
		"third_logout": third_logout,
		"blocked_logout": blocked_logout,
		"fourth_logout": fourth_logout,
		"terminal": terminal,
		"queue_after_second_logout": _queue_snapshot(),
		"persistence_pending": PlayerState._json_persistence.pending_count(),
		"expected_reward_plan": expected_reward_plan,
		"level_before": level_before_death,
		"level_after": PlayerState.level,
		"death_event_sequence_before": sequence_before_death,
		"death_event_sequence_after": PlayerState._death_event_sequence,
		"experience_before": xp_before_death,
		"experience_after": PlayerState.experience,
		"drop_roll_delta": roll_count_after_success - roll_count_before_success,
		"drop_node_delta": materialized_count_after_success - materialized_count_before_success,
		"profile_save": PlayerState.last_save_result,
		"frame_budget": FrameBudgetScript.snapshot(),
		"runtime_diagnostics": RuntimeDiagnostics.performance_counters(),
		"pre_teardown_refcounted": _capture_refcounted_members(),
		"pre_teardown_enemy_refcounted": _capture_enemy_refcounted(enemy, blocked_enemy),
	})
	_finish()


func _on_reentrant_profile_changed() -> void:
	if not is_instance_valid(_game) or not bool(_game._enemy_death_pipeline_running):
		return
	if _game._pending_enemy_deaths.is_empty():
		return
	_reentry_seen = true
	_reentrant_logout = _game._prepare_safe_logout()


func _make_enemy() -> EnemyActor:
	var canonical: Dictionary = GameData.get_monster_by_id(MONSTER_ID)
	_expect(not canonical.is_empty(), "known producing monster is missing")
	var enemy := EnemyActor.new()
	enemy.setup(canonical, _game.player, str(canonical.get("classification", "")) == "boss")
	enemy.configure_runtime_map_projection(
		_game.current_map_id,
		Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	var death_position: Vector2 = _game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	_expect(death_position.is_finite(), "formal death anchor projection unavailable")
	enemy.global_position = death_position
	enemy.set_meta("spawn_serial", 9910209)
	enemy.set_meta("spawn_position", death_position)
	enemy.set_meta("zone_generation", _game._zone_generation)
	enemy.set_meta("death_runtime_snapshot", _game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_context", {})
	_game.add_child(enemy)
	enemy.died.connect(_game._on_enemy_died)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	return enemy


func _wait_for_world_ready() -> bool:
	for _frame: int in range(WORLD_READY_FRAMES):
		await get_tree().process_frame
		if (
			not bool(_game._world_bootstrap_in_progress)
			and not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY
		):
			return true
	return false


func _queue_snapshot() -> Dictionary:
	var by_state: Dictionary = {}
	var entries: Array[Dictionary] = []
	for raw: Variant in _game._pending_enemy_deaths:
		if not raw is Dictionary:
			continue
		var death: Dictionary = raw
		var state := str(death.get("state", ""))
		by_state[state] = int(by_state.get(state, 0)) + 1
		entries.append({
			"state": state,
			"sequence": int(death.get("sequence", -1)),
			"retry_count": int(death.get("retry_count", 0)),
			"drop_roll_count": int(death.get("drop_roll_count", 0)),
			"remaining_request_count": int(death.get("remaining_request_count", 0)),
		})
	return {"count": _game._pending_enemy_deaths.size(), "by_state": by_state, "entries": entries}


func _latest_terminal() -> Dictionary:
	if _game._enemy_death_terminal_jobs.is_empty():
		return {}
	return (_game._enemy_death_terminal_jobs[-1] as Dictionary).duplicate(true)


func _capture_refcounted_members() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var game_members := [
		"_world_context", "_time_domains", "_world_bootstrap_coordinator",
		"_feature_target_bound", "_feature_effect_runtime", "_combat_spatial_index",
		"_combat_target_query_service", "_combat_target_query_service_index",
		"_loot_pickup_runtime_manager", "_audio_runtime_service", "_streaming_coordinator",
	]
	for member_name: String in game_members:
		_capture_refcounted_entry(entries, "GameRoot.%s" % member_name, _game.get(member_name))
	if is_instance_valid(_game.get("_loot_pickup_runtime_manager")):
		var manager: Variant = _game.get("_loot_pickup_runtime_manager")
		_capture_refcounted_entry(entries, "LootPickupRuntimeManager._spatial_index", manager.get("_spatial_index"))

	for member_name: String in [
		"_feature_loadout", "_item_transaction_port", "_skill_progression",
		"_clock_cleanup_worker", "_json_persistence", "_world_json_persistence",
		"_enhancement_service", "_relic_synthesis_service",
	]:
		_capture_refcounted_entry(entries, "PlayerState.%s" % member_name, PlayerState.get(member_name))

	_capture_refcounted_entry(entries, "LootRuntime.autoload", LootRuntime)
	_capture_refcounted_entry(entries, "LootRuntime._user_additions", LootRuntime.get("_user_additions"))
	_capture_refcounted_entry(entries, "LootRuntime._sheet_authority", LootRuntime.get("_sheet_authority"))
	_capture_refcounted_entry(entries, "GameData.autoload", GameData)
	return entries


func _capture_refcounted_entry(entries: Array[Dictionary], label: String, value: Variant) -> void:
	if value == null or not value is Object or not is_instance_valid(value):
		return
	var object: Object = value
	var script_value: Variant = object.get_script()
	var script_path := str(script_value.resource_path) if script_value is Script else ""
	entries.append({
		"label": label,
		# Object IDs exceed JSON's exact IEEE-754 integer range. Preserve the
		# signed decimal spelling so verbose ObjectDB IDs can be matched exactly.
		"instance_id": str(object.get_instance_id()),
		"class": object.get_class(),
		"script_path": script_path,
		"refcounted": value is RefCounted,
	})


func _capture_enemy_refcounted(entries_a: Variant, entries_b: Variant) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for pair: Array in [["successful", entries_a], ["blocked", entries_b]]:
		var actor: Variant = pair[1]
		if actor == null or not actor is Object or not is_instance_valid(actor):
			continue
		for member_name: String in [
			"_feature_capabilities", "_natural_regen", "_movement_cadence",
			"_target_acquisition_policy", "_entrapment_controller", "_hc_polygon_pursuit",
		]:
			_capture_refcounted_entry(entries, "EnemyActor.%s.%s" % [pair[0], member_name], actor.get(member_name))
	return entries


func _write_receipt(receipt: Dictionary) -> void:
	var directory_result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(RECEIPT_DIR))
	if directory_result != OK and directory_result != ERR_ALREADY_EXISTS:
		print("SAFE_LOGOUT_PENDING_RECEIPT_WRITE_FAIL result=%d" % directory_result)
		return
	var path := "%s/receipt_%d_%d.json" % [RECEIPT_DIR, Time.get_ticks_usec(), OS.get_process_id()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("SAFE_LOGOUT_PENDING_RECEIPT_WRITE_FAIL path=%s" % path)
		return
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()
	print("SAFE_LOGOUT_PENDING_RECEIPT path=%s" % path)


func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if PlayerState.profile_changed.is_connected(_on_reentrant_profile_changed):
		PlayerState.profile_changed.disconnect(_on_reentrant_profile_changed)
	if is_instance_valid(_game):
		_game.queue_free()
	PlayerState.set_process(true)
	PlayerState.test_mode = true
	RuntimeDiagnostics.set_device_lab_performance_enabled(false)
	await get_tree().process_frame
	if _failures.is_empty():
		print("SAFE_LOGOUT_PENDING_RETRY_REPAIR_PASS checks=%d" % _checks)
		get_tree().quit(0)
		return
	printerr("SAFE_LOGOUT_PENDING_RETRY_REPAIR_FAIL checks=%d failures=%s" % [_checks, "; ".join(_failures)])
	get_tree().quit(1)
