extends Node

const MONSTER_ID := 76
const WORLD_READY_FRAMES := 1800
const DEATH_WAIT_FRAMES := 1800
const RNG_SEED := 20261009
const FrameBudgetScript := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const RECEIPT_DIR := "res://outputs/wake_drop_v108_repair_20261009/natural_process"

var _game: Node
var _diagnostic_samples: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = false
	PlayerState.reset_progress(false)
	var creation_result := PlayerState.create_character(
		"NaturalDrop%06d" % (Time.get_ticks_msec() % 1000000),
		"战士",
		"男",
	)
	assert(creation_result.is_empty(), "isolated PlayerState character creation failed: %s" % creation_result)
	var created_profile_id: String = PlayerState.active_profile_id
	assert(not created_profile_id.is_empty(), "formal character creation did not publish a profile id")
	# Character creation writes the profile, while select_character is the formal
	# activation boundary that loads the world-clock baseline used by deaths.
	var activated: bool = PlayerState.select_character(created_profile_id)
	assert(activated, "formal character activation failed: %s" % PlayerState.last_load_result)
	assert(
		PlayerState._world_clock_snapshot_sequence >= 0,
		"formal activation did not load a world-clock baseline: %s" % PlayerState.last_load_result,
	)
	var preview_rng := RandomNumberGenerator.new()
	preview_rng.seed = RNG_SEED
	var preview: Dictionary = LootRuntime.roll_monster_drops(MONSTER_ID, preview_rng, true)
	assert(bool(preview.get("configured", false)), "known producing profile is not configured: %s" % preview)
	assert(
		(not (preview.get("items", []) as Array).is_empty())
		or not (preview.get("gold_drops", []) as Array).is_empty(),
		"fixed-seed producing profile returned no reward: %s" % preview
	)

	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	var ready := false
	for _frame: int in range(WORLD_READY_FRAMES):
		await get_tree().process_frame
		if (
			not bool(_game._world_bootstrap_in_progress)
			and not bool(_game._map_transition_in_progress)
			and _game._world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.READY
		):
			ready = true
			break
	assert(ready, "main bootstrap did not reach READY")
	assert(_game.is_processing(), "natural process path is disabled")
	assert(is_instance_valid(_game.player), "production player is unavailable")
	assert(is_instance_valid(_game._loot_pickup_runtime_manager), "production loot manager is unavailable")
	assert(_game._loot_pickup_runtime_manager.is_processing(), "production loot manager process is disabled")

	_game._rng.seed = RNG_SEED
	var canonical: Dictionary = GameData.get_monster_by_id(MONSTER_ID)
	assert(not canonical.is_empty(), "known producing monster is missing")
	var enemy := EnemyActor.new()
	enemy.setup(canonical, _game.player, str(canonical.get("classification", "")) == "boss")
	enemy.configure_runtime_map_projection(
		_game.current_map_id,
		Callable(_game, "_canonical_ground_gu_to_screen_px"),
		Callable(_game, "_canonical_screen_px_to_ground_gu"),
	)
	var death_position: Vector2 = _game._canonical_ground_gu_to_screen_px(Vector2(38.5, 13.5))
	assert(death_position.is_finite(), "formal death anchor projection is unavailable")
	enemy.global_position = death_position
	enemy.set_meta("spawn_serial", 9910109)
	enemy.set_meta("spawn_position", death_position)
	enemy.set_meta("zone_generation", _game._zone_generation)
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("respawn_seconds", -1.0)
	enemy.set_meta("spawn_context", {})
	_game.add_child(enemy)
	enemy.died.connect(_game._on_enemy_died)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.current_hp = 1
	enemy.take_damage(1)

	assert(enemy._death_pending, "production Enemy did not enter death_pending")
	var terminal: Dictionary = {}
	for _frame: int in range(DEATH_WAIT_FRAMES):
		await get_tree().process_frame
		terminal = _latest_terminal_death()
		if _frame % 60 == 0:
			_diagnostic_samples.append(_diagnostic_sample(_frame))
		if str(terminal.get("state", "")) == "COMMITTED":
			break
	_write_receipt({
		"status": "OBSERVED_COMMITTED" if str(terminal.get("state", "")) == "COMMITTED" else "FAIL",
		"test_mode": PlayerState.test_mode,
		"terminal": terminal,
		"manager": _game._loot_pickup_runtime_manager.diagnostics_snapshot(),
		"frame_budget": FrameBudgetScript.snapshot(),
		"diagnostic_samples": _diagnostic_samples,
		"death_pending": _safe_pending_deaths(),
		"prepared_settlement": _prepared_settlement_snapshot(),
		"player_background_death": _background_death_snapshot(),
		"persistence": _persistence_snapshot(),
		"pipeline_running": bool(_game._enemy_death_pipeline_running),
		"process_state": _process_state_snapshot(),
		"player_state": {
			"active_profile_id": PlayerState.active_profile_id,
			"world_clock_generation": PlayerState._world_clock_generation,
			"world_clock_snapshot_sequence": PlayerState._world_clock_snapshot_sequence,
			"last_load_result": PlayerState.last_load_result,
		},
	})
	if str(terminal.get("state", "")) != "COMMITTED":
		printerr("DEATH_NATURAL_PROCESS_REPAIR_FAIL ", JSON.stringify(terminal))
		_game.queue_free()
		await get_tree().process_frame
		get_tree().quit(1)
		return
	assert(
		str(terminal.get("state", "")) == "COMMITTED",
		"natural death queue did not commit: %s budget=%s" % [terminal, FrameBudgetScript.snapshot()],
	)
	assert(str(terminal.get("reward_status", "")) == "committed", "death committed without reward: %s" % terminal)
	assert(int(terminal.get("materialized_node_count", 0)) > 0, "natural death produced no ground node: %s" % terminal)
	var manager_snapshot: Dictionary = _game._loot_pickup_runtime_manager.diagnostics_snapshot()
	assert(int(manager_snapshot.get("manager_registration_check_count", 0)) > 0, "loot manager performed no natural registration check")
	assert(int(manager_snapshot.get("registered_pickup_count", 0)) > 0, "natural ground node was not registered")

	var logout: Dictionary = _game._prepare_safe_logout()
	assert(bool(logout.get("success", false)), "safe logout failed after natural committed death: %s terminal=%s" % [logout, terminal])
	assert(_game._last_death_logout_failure.is_empty(), "logout failure ledger was populated: %s" % _game._last_death_logout_failure)
	_write_receipt({
		"status": "PASS",
		"test_mode": PlayerState.test_mode,
		"terminal": terminal,
		"manager": manager_snapshot,
		"frame_budget": FrameBudgetScript.snapshot(),
		"logout": logout,
		"wait_frames": DEATH_WAIT_FRAMES,
	})
	print("DEATH_NATURAL_PROCESS_REPAIR_PASS")
	_game.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)


func _latest_terminal_death() -> Dictionary:
	if not is_instance_valid(_game) or _game._enemy_death_terminal_jobs.is_empty():
		return {}
	return (_game._enemy_death_terminal_jobs[-1] as Dictionary).duplicate(true)


func _safe_pending_deaths() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw: Variant in _game._pending_enemy_deaths:
		if raw is Dictionary:
			result.append((raw as Dictionary).duplicate(true))
	return result


func _job_snapshot(job: Object) -> Dictionary:
	if job == null:
		return {}
	var response: Variant = job.get("response")
	var preparation: Variant = job.get("preparation")
	return {
		"task_id": int(job.get("_task_id")),
		"stage_complete": bool(job.call("is_stage_complete")),
		"response_finished": bool(response.get("finished", false)) if response is Dictionary else false,
		"response_reason": str(response.get("reason", "")) if response is Dictionary else "",
		"preparation_finished": bool(preparation.get("finished", false)) if preparation is Dictionary else false,
		"path": str(job.get("path")),
	}


func _persistence_snapshot() -> Dictionary:
	var service: Object = PlayerState._json_persistence
	var work: Dictionary = service.call("work_snapshot")
	var entries: Array[Dictionary] = []
	var queue: Variant = service.get("_queue")
	if queue is Array:
		for raw: Variant in queue:
			if not raw is Dictionary:
				continue
			var entry: Dictionary = raw
			var job: Object = entry.get("job") as Object
			entries.append({
				"phase": str(entry.get("phase", "")),
				"allow_promotion": bool(entry.get("allow_promotion", false)),
				"guard_valid": bool(entry.get("guard", Callable()).is_valid()),
				"job": _job_snapshot(job),
			})
	work["entries"] = entries
	return work


func _prepared_settlement_snapshot() -> Dictionary:
	var prepared: Dictionary = _game._prepared_enemy_death_settlement
	if prepared.is_empty():
		return {}
	var plan: Dictionary = prepared.get("plan", {}) as Dictionary
	var writer: Object = plan.get("writer") as Object
	var writer_job: Object = writer.get("job") as Object if writer != null else null
	return {
		"batch_size": (prepared.get("batch", []) as Array).size(),
		"plan_completed": bool(plan.get("completed", false)),
		"completion": (plan.get("completion", {}) as Dictionary).duplicate(true),
		"writer": {"path": str(writer.get("path")), "job": _job_snapshot(writer_job)} if writer != null else {},
	}


func _background_death_snapshot() -> Dictionary:
	var background: Dictionary = PlayerState._background_death
	if background.is_empty():
		return {}
	var writer: Object = background.get("writer") as Object
	var writer_job: Object = writer.get("job") as Object if writer != null else null
	return {
		"completed": bool(background.get("completed", false)),
		"completion": (background.get("completion", {}) as Dictionary).duplicate(true),
		"writer": {"path": str(writer.get("path")), "job": _job_snapshot(writer_job)} if writer != null else {},
	}


func _process_state_snapshot() -> Dictionary:
	return {
		"game_inside_tree": _game.is_inside_tree(),
		"game_can_process": _game.can_process(),
		"game_is_processing": _game.is_processing(),
		"player_can_process": PlayerState.can_process(),
		"player_is_processing": PlayerState.is_processing(),
		"manager_can_process": _game._loot_pickup_runtime_manager.can_process(),
		"manager_is_processing": _game._loot_pickup_runtime_manager.is_processing(),
	}


func _diagnostic_sample(frame: int) -> Dictionary:
	return {
		"frame": frame,
		"terminal_count": _game._enemy_death_terminal_jobs.size(),
		"pending_count": _game._pending_enemy_deaths.size(),
		"death_budget": FrameBudgetScript.snapshot(),
		"death_pending": _safe_pending_deaths(),
		"prepared_settlement": _prepared_settlement_snapshot(),
		"player_background_death": _background_death_snapshot(),
		"persistence": _persistence_snapshot(),
		"pipeline_running": bool(_game._enemy_death_pipeline_running),
		"process_state": _process_state_snapshot(),
	}


func _write_receipt(receipt: Dictionary) -> void:
	var directory_result := DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path(RECEIPT_DIR)
	)
	assert(directory_result == OK or directory_result == ERR_ALREADY_EXISTS, "receipt directory unavailable")
	var path := "%s/receipt_%d_%d.json" % [RECEIPT_DIR, Time.get_ticks_usec(), OS.get_process_id()]
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	assert(file != null, "receipt file unavailable: %s" % path)
	file.store_string(JSON.stringify(receipt, "\t"))
	file.close()
