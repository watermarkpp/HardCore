extends Node

const Fixture := preload("res://tests/f05_settlement_display_separation_test.gd")
const StageFixture := preload("res://tests/helpers/ordered_json_stage_fixture.gd")
const FrameBudgetScript := preload(
	"res://scripts/layers/runtime/execution/frame_budget.gd"
)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	var game: Node = Fixture.FixtureGame.new()
	game.current_map_id = 5317
	game._zone_generation = 11
	add_child(game)
	game.set_process(false)
	game.set_physics_process(false)
	game.player.set_physics_process(false)
	game._loot_pickup_runtime_manager.set_process(false)
	game._enemy_death_flush_queued = true
	PlayerState.set_process(false)
	var root := "user://f03_native_death_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	PlayerState.profile_directory = root.path_join("characters")
	PlayerState.profile_index_path = root.path_join("profiles.json")
	PlayerState.active_profile_id = "native"
	PlayerState.test_mode = false
	PlayerState.level = 50
	PlayerState.recalculate_stats(false)
	assert(PlayerState.save_game(false))
	var canonical := GameData.get_monster_by_id(64)
	var reward: int = int(game._build_enemy_death_runtime_snapshot(canonical).experience)
	var rng_before: int = game._rng.state
	_queue(game, canonical, "cancelled")
	await _await_prepared_settlement(game)
	assert(game._pending_enemy_deaths[0].state == "PERSISTING")
	assert(PlayerState._death_event_sequence == 0 and PlayerState.experience == 0)
	assert(PlayerState.world_monster_respawn_state.entries.is_empty())
	var cancelled: Dictionary = game._prepared_enemy_death_settlement.plan
	assert(cancelled.writer.result(true).success)
	game._zone_generation += 1
	game._cancel_pending_enemy_deaths_for_generation_change()
	assert(game._pending_enemy_deaths.is_empty() and cancelled.completed and not cancelled.completion.success)
	assert(PlayerState._death_event_sequence == 0 and PlayerState.experience == 0 and game._rng.state == rng_before)
	_queue(game, canonical, "committing")
	await _await_prepared_settlement(game)
	var committing: Dictionary = game._prepared_enemy_death_settlement.plan
	await _start_promotion(committing)
	assert(PlayerState.experience == 0 and PlayerState.world_monster_respawn_state.entries.is_empty())
	game._zone_generation += 1
	game._cancel_pending_enemy_deaths_for_generation_change()
	assert(PlayerState._death_event_sequence == 1 and PlayerState.experience == reward)
	assert(PlayerState.world_monster_respawn_state.entries.size() == 1)
	assert(game._pending_enemy_deaths.is_empty() and game._rng.state == rng_before)
	# A real root exit consumes an accepted request. It must not mark a future
	# as "no progress" or leave its worker/callback holding a deleted root.
	_queue(game, canonical, "exiting")
	await _await_prepared_settlement(game)
	var exiting: Dictionary = game._prepared_enemy_death_settlement.plan
	assert(exiting.writer.result(true).success)
	# The third death has only reached the durable receipt boundary.  Teardown
	# must not start a new drop roll after the GameRoot is freed; complete drop
	# planning/materialization is covered by real safe-logout and natural-death
	# queue contracts, not by this receipt-lifecycle fixture.
	var drop_roll_count_before_free: int = int(
		RuntimeDiagnostics.performance_counter(&"drop_roll_count")
	)
	assert(drop_roll_count_before_free == 0)
	_write_f03_diagnostic("before_free", exiting, game)
	game.free()
	_write_f03_diagnostic("after_free", exiting, null)
	assert(exiting.completed and exiting.completion.success)
	assert(PlayerState._death_event_sequence == 2 and PlayerState.experience == reward * 2)
	assert(PlayerState.world_monster_respawn_state.entries.size() == 2)
	assert(PlayerState.finish_prepared_death_settlement(exiting).success and PlayerState.experience == reward * 2)
	assert(RuntimeDiagnostics.performance_counter(&"drop_roll_count") == drop_roll_count_before_free)
	assert(PlayerState._json_persistence.pending_count() == 0)
	PlayerState.load_save()
	assert(PlayerState.last_load_result.success and PlayerState._death_event_sequence == 2)
	assert(PlayerState.experience == reward * 2 and PlayerState.world_monster_respawn_state.entries.size() == 2)
	PlayerState.test_mode = true
	PlayerState.set_process(true)
	await get_tree().process_frame
	print("F03_NATIVE_DEATH_LIFECYCLE_PASS")
	get_tree().quit(0)


func _write_f03_diagnostic(stage: String, plan: Dictionary, game: Node) -> void:
	var game_alive := is_instance_valid(game)
	var payload: Dictionary = {
		"test": "f03_native_death_lifecycle",
		"stage": stage,
		"game_alive": game_alive,
		"plan_completed": bool(plan.get("completed", false)),
		"plan_completion": (plan.get("completion", {}) as Dictionary).duplicate(true),
		"transaction_result": (plan.get("transaction_result", {}) as Dictionary).duplicate(true),
		"pending_count": int(PlayerState._json_persistence.pending_count()),
		"death_event_sequence": int(PlayerState._death_event_sequence),
		"experience": int(PlayerState.experience),
		"rng_state": int(game._rng.state) if game_alive else -1,
		"drop_roll_count": int(RuntimeDiagnostics.performance_counter(&"drop_roll_count")),
		"frame_budget": FrameBudgetScript.snapshot(),
		"runtime_diagnostics": RuntimeDiagnostics.performance_counters(),
	}
	if game_alive:
		payload["pending"] = _f03_pending_snapshot(game)
		payload["terminal"] = _f03_terminal_snapshot(game)
	else:
		payload["pending"] = {"count": -1, "entries": []}
		payload["terminal"] = {"count": -1, "entries": []}
	var directory := "user://f03_native_death_diagnostics"
	var result := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if result != OK and result != ERR_ALREADY_EXISTS:
		print("F03_NATIVE_DEATH_DIAGNOSTIC_WRITE_FAIL result=%d" % result)
		return
	var path := "%s/%s_%d_%d.json" % [directory, stage, Time.get_ticks_usec(), OS.get_process_id()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		print("F03_NATIVE_DEATH_DIAGNOSTIC_WRITE_FAIL path=%s" % path)
		return
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	print("F03_NATIVE_DEATH_DIAGNOSTIC path=%s" % path)


func _f03_pending_snapshot(game: Node) -> Dictionary:
	var entries: Array[Dictionary] = []
	for raw: Variant in game._pending_enemy_deaths:
		if not raw is Dictionary:
			continue
		var death: Dictionary = raw
		entries.append({
			"state": str(death.get("state", "")),
			"sequence": int(death.get("sequence", -1)),
			"retry_count": int(death.get("retry_count", 0)),
			"retry_at_msec": int(death.get("retry_at_msec", 0)),
			"drop_roll_count": int(death.get("drop_roll_count", 0)),
			"remaining_request_count": int(death.get("remaining_request_count", 0)),
		})
	return {"count": game._pending_enemy_deaths.size(), "entries": entries}


func _f03_terminal_snapshot(game: Node) -> Dictionary:
	var entries: Array[Dictionary] = []
	for raw: Variant in game._enemy_death_terminal_jobs:
		if not raw is Dictionary:
			continue
		var death: Dictionary = raw
		entries.append({
			"state": str(death.get("state", "")),
			"sequence": int(death.get("sequence", -1)),
			"reward_status": str(death.get("reward_status", "")),
			"last_error": str(death.get("last_error", "")),
			"drop_roll_count": int(death.get("drop_roll_count", 0)),
		})
	return {
		"count": game._enemy_death_terminal_jobs.size(),
		"total_count": int(game._enemy_death_terminal_total_count),
		"entries": entries,
	}

func _start_promotion(plan: Dictionary) -> void:
	assert(plan.writer.result(true).success)
	await StageFixture.await_durable_promotion(PlayerState._json_persistence, plan.writer.job,
		PlayerState.finish_prepared_death_settlement.bind(plan), get_tree())
	assert(not plan.completed)

func _await_prepared_settlement(game: Node) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	# The preceding real save can consume this outer iteration's whole budget.
	# Observe admission across native frames rather than assuming the first poll.
	while game._prepared_enemy_death_settlement.is_empty():
		assert(Time.get_ticks_msec() < deadline, "death preparation did not receive an actual fair turn")
		assert(not game._pending_enemy_deaths.is_empty())
		game._pump_enemy_death_work_queue()
		if game._prepared_enemy_death_settlement.is_empty():
			await get_tree().process_frame
	assert(game._pending_enemy_deaths[0].state == "PERSISTING")

func _queue(game: Node, canonical: Dictionary, slot: String) -> void:
	var enemy := EnemyActor.new()
	enemy.global_position = Vector2(5000, 5000)
	enemy.set_meta("respawn_enabled", true)
	enemy.set_meta("respawn_seconds", 480.0)
	enemy.set_meta("death_runtime_snapshot", game._build_enemy_death_runtime_snapshot(canonical))
	enemy.set_meta("death_origin", {"captured": true, "map_id": game.current_map_id,
		"generation": game._zone_generation, "death_position": enemy.global_position,
		"spawn_position": enemy.global_position, "spawn_context": {"respawn_runtime_map_id": 5317,
			"spawn_slot_id": slot, "respawn_policy_id": "normal_cave"}})
	game._on_enemy_died(enemy, canonical)
	enemy.free()
