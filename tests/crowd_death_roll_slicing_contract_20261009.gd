extends Node

const GameRootScript := preload("res://scripts/game_root.gd")
const SpatialIndexScript := preload("res://scripts/runtime_combat_spatial_index.gd")
const LootRuntimeScript := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const HistoricalLootScript := preload("res://tests/helpers/loot_runtime_pre_slice_20261009.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")

class FixtureGameRoot extends GameRootScript:
	func _begin_initial_world_bootstrap() -> void:
		return

const TEST_IDS := [64, 135, 224, 160, 124]
const SLICE_SIZES := [1, 3, 6, 9, 12]

const DEATH_ORDER := [64, 135, 224, 160, 124, 224, 64, 160, 135, 124]
const SEEDS := [20261009, 20261010, 0x6D3A9E17]
const MAP_ID := 5317
const GENERATION := 11
const QUEUE_MONSTER_ID := 34
const NATURAL_DRAIN_MAX_FRAMES := 1200

var _failures: Array[String] = []
var _checks := 0
var _rows: Array[Dictionary] = []
var _queue_rows: Array[Dictionary] = []
var _first_pair: Dictionary = {}
var _legacy_service
var _current_service: Node = LootRuntimeScript.new()
var _game: Node

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_run()

func _expect(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures.append(message)

func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng

func _legacy_roll(service, monster_id: int, seed_value: int, include_audit: bool) -> Dictionary:
	var rng := _rng(seed_value)
	var result: Dictionary = service.roll_monster_drops(monster_id, rng, include_audit)
	result["_final_rng_state"] = rng.state
	return result

func _production_full(monster_id: int, seed_value: int, include_audit: bool) -> Dictionary:
	var rng := _rng(seed_value)
	var result: Dictionary = _current_service.roll_monster_drops(monster_id, rng, include_audit)
	result["_final_rng_state"] = rng.state
	return result

func _production_sliced(monster_id: int, seed_value: int, slice_size: int, include_audit: bool) -> Dictionary:
	var rng := _rng(seed_value)
	var job: Dictionary = _current_service.begin_monster_drop_roll_job(monster_id, rng, include_audit)
	var calls := 0
	while not bool(job.get("done", false)) and calls < 10000:
		job = _current_service.advance_monster_drop_roll_job(job, slice_size)
		calls += 1
	_expect(bool(job.get("done", false)), "id=%d slice=%d job did not finish" % [monster_id, slice_size])
	var result: Dictionary = (job.get("result", {}) as Dictionary).duplicate(true)
	result["_final_rng_state"] = rng.state
	result["_advance_calls"] = calls
	return result

func _without_probe_fields(value: Dictionary) -> Dictionary:
	var result := value.duplicate(true)
	result.erase("_final_rng_state")
	result.erase("_advance_calls")
	return result

func _stream_rolls(service, seed_value: int, historical: bool, slice_size := 1) -> Dictionary:
	var rng := _rng(seed_value)
	var outputs: Array[Dictionary] = []
	for monster_id: int in DEATH_ORDER:
		if historical:
			outputs.append(service.roll_monster_drops(monster_id, rng, false))
		else:
			var job: Dictionary = service.begin_monster_drop_roll_job(monster_id, rng, false)
			var guard := 0
			while not bool(job.get("done", false)) and guard < 10000:
				job = service.advance_monster_drop_roll_job(job, slice_size)
				guard += 1
			_expect(bool(job.get("done", false)), "shared stream job did not finish id=%d" % monster_id)
			outputs.append((job.get("result", {}) as Dictionary).duplicate(true))
	return {"results": outputs, "rng_state": rng.state}

func _run_roll_contract() -> void:
	_expect(GameData.is_dpv2_direct_baseline_loaded(), "GameData DPV2 direct baseline is not ready")
	for monster_id: int in TEST_IDS:
		_expect(GameData.canonical_monster_id(monster_id) > 0, "canonical monster id is unresolved: %d" % monster_id)
	_legacy_service = HistoricalLootScript.new()
	add_child(_legacy_service)
	for seed_value: int in SEEDS:
		for death_index: int in range(DEATH_ORDER.size()):
			var monster_id := int(DEATH_ORDER[death_index])
			var stream_seed := seed_value + death_index * 7919
			var historical := _legacy_roll(_legacy_service, monster_id, stream_seed, false)
			var current := _production_full(monster_id, stream_seed, false)
			if _first_pair.is_empty():
				_first_pair = {"historical": historical, "current": current}
			_expect(
				_without_probe_fields(historical) == _without_probe_fields(current),
				"historical/current full dictionary mismatch id=%d seed=%d" % [monster_id, stream_seed],
			)
			_expect(
				int(historical.get("_final_rng_state", -1)) == int(current.get("_final_rng_state", -2)),
				"historical/current final RNG mismatch id=%d seed=%d" % [monster_id, stream_seed],
			)
			for slice_size: int in SLICE_SIZES:
				var sliced := _production_sliced(monster_id, stream_seed, slice_size, false)
				_expect(
					_without_probe_fields(current) == _without_probe_fields(sliced),
					"current/sliced dictionary mismatch id=%d seed=%d slice=%d" % [monster_id, stream_seed, slice_size],
				)
				_expect(
					int(current.get("_final_rng_state", -1)) == int(sliced.get("_final_rng_state", -2)),
					"current/sliced final RNG mismatch id=%d seed=%d slice=%d" % [monster_id, stream_seed, slice_size],
				)
				_rows.append({
					"monster_id": monster_id,
					"seed": stream_seed,
					"slice_size": slice_size,
					"final_rng_state": int(sliced.get("_final_rng_state", -1)),
					"advance_calls": int(sliced.get("_advance_calls", 0)),
					"schema_keys": sliced.keys(),
				})
		var historical_stream := _stream_rolls(_legacy_service, seed_value, true)
		var current_stream := _stream_rolls(_current_service, seed_value, false, 1)
		var sliced_stream := _stream_rolls(_current_service, seed_value, false, 3)
		_expect(historical_stream.get("results", []) == current_stream.get("results", []), "shared RNG historical/current stream mismatch seed=%d" % seed_value)
		_expect(current_stream.get("results", []) == sliced_stream.get("results", []), "shared RNG current/sliced stream mismatch seed=%d" % seed_value)
		_expect(int(historical_stream.get("rng_state", -1)) == int(current_stream.get("rng_state", -2)), "shared RNG historical/current final state mismatch seed=%d" % seed_value)
		_expect(int(current_stream.get("rng_state", -1)) == int(sliced_stream.get("rng_state", -2)), "shared RNG current/sliced final state mismatch seed=%d" % seed_value)

	# Audit mode is part of the full result schema and must remain resumable.
	var audit_id: int = int(TEST_IDS[0])
	var audit_seed: int = int(SEEDS[0])
	var audited_historical := _legacy_roll(_legacy_service, audit_id, audit_seed, true)
	var audited_full := _production_full(audit_id, audit_seed, true)
	var audited_sliced := _production_sliced(audit_id, audit_seed, 6, true)
	_expect(_without_probe_fields(audited_historical) == _without_probe_fields(audited_full), "historical/current audited result must match")
	_expect(
		_without_probe_fields(audited_full) == _without_probe_fields(audited_sliced),
		"audit dictionary mismatch id=%d seed=%d" % [audit_id, audit_seed],
	)
	_expect(
		int(audited_full.get("_final_rng_state", -1)) == int(audited_sliced.get("_final_rng_state", -2)),
		"audit RNG mismatch id=%d seed=%d" % [audit_id, audit_seed],
	)

func _reset_game(seed_value: int) -> Node:
	if is_instance_valid(_game):
		_game.free()
	_game = load("res://scenes/main.tscn").instantiate()
	add_child(_game)
	for _frame: int in 1200:
		await get_tree().process_frame
		if not _game._world_bootstrap_in_progress and not _game._map_transition_in_progress:
			break
	_expect(_game.gameplay_input_is_enabled(), "formal world bootstrap must complete before death queue fixture")
	_game.set_process(false)
	_game.set_physics_process(false)
	_game._rng.seed = seed_value
	for actor: Node in get_tree().get_nodes_in_group("enemies"):
		actor.set_process(false)
		actor.set_physics_process(false)
	if _game._loot_pickup_runtime_manager != null:
		_game._loot_pickup_runtime_manager.set_process(false)
	if is_instance_valid(_game.player):
		_game.player.set_process(false)
		_game.player.set_physics_process(false)
	_game._enemy_death_flush_queued = true
	return _game

func _queue_real_death(game: Node, monster_id: int, index: int) -> void:
	var enemy := EnemyActor.new()
	var canonical := GameData.get_monster_by_id(monster_id)
	enemy.setup(canonical, null, false)
	enemy.configure_runtime_map_projection(game.current_map_id, Callable(game, "_canonical_ground_gu_to_screen_px"), Callable(game, "_canonical_screen_px_to_ground_gu"))
	enemy.configure_terrain_navigation_context(game._monster_terrain_navigation_context)
	enemy.global_position = game._canonical_ground_gu_to_screen_px(Vector2(38.5 + index % 6, 13.5 + index / 6))
	enemy.set_meta("respawn_enabled", false)
	enemy.set_meta("spawn_position", enemy.global_position)
	enemy.set_meta("zone_generation", game._zone_generation)
	game.add_child(enemy)
	enemy.set_process(false)
	enemy.set_physics_process(false)
	game._on_enemy_died(enemy, canonical)
	enemy.free()

func _natural_drain(game: Node, max_frames: int) -> Dictionary:
	var pending: Array[int] = []
	var terminal_counts: Array[int] = []
	var frames := 0
	var max_frame_usec := 0
	var started_usec := Time.get_ticks_usec()
	game.set_process(true)
	while not game._pending_enemy_deaths.is_empty() and frames < max_frames:
		var frame_started_usec := Time.get_ticks_usec()
		await get_tree().process_frame
		await get_tree().physics_frame
		# GameRoot._process owns the single formal queue pump; do not call it again here.
		var frame_elapsed_usec := Time.get_ticks_usec() - frame_started_usec
		max_frame_usec = maxi(max_frame_usec, frame_elapsed_usec)
		pending.append(game._pending_enemy_deaths.size())
		terminal_counts.append(game._enemy_death_terminal_jobs.size())
		frames += 1
	game.set_process(false)
	return {"frames": frames, "pending": pending, "terminal_counts": terminal_counts, "complete": game._pending_enemy_deaths.is_empty(), "elapsed_usec": Time.get_ticks_usec() - started_usec, "max_frame_usec": max_frame_usec}

func _run_queue_contract() -> void:
	var queue_source_slot_count := GameData.get_dpv2_direct_slots(QUEUE_MONSTER_ID).size()
	var queue_ground_slot_limit := GameData.dpv2_ground_slot_limit_for_monster(QUEUE_MONSTER_ID)
	var game: Node = await _reset_game(44001)
	_expect(game.has_method("set_death_roll_quantum_slicing_for_test"), "GameRoot slicing switch unavailable")
	_expect(game.set_death_roll_quantum_slicing_for_test(true), "slicing switch rejected test mode")
	for index: int in range(30):
		_queue_real_death(game, QUEUE_MONSTER_ID, index)
	_expect(game._pending_enemy_deaths.size() == 30, "simultaneous death queue did not retain 30 entries")
	FrameBudget.configure_for_tests(1000000, func() -> int: return Engine.get_process_frames(), func() -> int: return Time.get_ticks_usec())
	game._pump_enemy_death_work_queue()
	var first_epoch: int = game._death_optional_pump_frame
	var first_work := FrameBudget.snapshot()
	var first_scopes := int(first_work.get("categories", {}).get(game._death_budget_category, {}).get("scopes", 0))
	_expect(first_epoch == Engine.get_process_frames(), "first actual death slice consumes this process epoch")
	for _duplicate: int in 3:
		game._pump_enemy_death_work_queue()
	var repeat_work := FrameBudget.snapshot()
	var repeat_scopes := int(repeat_work.get("categories", {}).get(game._death_budget_category, {}).get("scopes", 0))
	_expect(repeat_scopes == first_scopes, "deferred/process/repeated pumps cannot grant death work twice in one frame")
	_expect(int(repeat_work.get("open_scopes", -1)) == 0, "duplicate death pump leaves no frame scope")
	_queue_rows.append({"same_frame_initial_scopes": first_scopes, "same_frame_repeated_scopes": repeat_scopes, "same_frame_process_epoch": first_epoch})
	FrameBudget.reset_test_configuration()
	var initial_keys: Array[String] = []
	for death: Dictionary in game._pending_enemy_deaths:
		initial_keys.append(str(death.get("death_key", "")))
	var simultaneous_drain := await _natural_drain(game, NATURAL_DRAIN_MAX_FRAMES)
	_expect(game._pending_enemy_deaths.is_empty(), "sliced queue did not drain")
	_expect(game._enemy_death_terminal_jobs.size() == 30, "sliced queue terminal count was not exactly once")
	var seen := {}
	for death: Dictionary in game._enemy_death_terminal_jobs:
		var key := str(death.get("death_key", ""))
		seen[key] = int(seen.get(key, 0)) + 1
		_expect(str(death.get("state", "")) == "COMMITTED", "simultaneous death was not committed")
	for key: String in initial_keys:
		_expect(int(seen.get(key, 0)) == 1, "death key was not settled exactly once: %s" % key)
	_queue_rows.append({"simultaneous": 30, "natural_drain": simultaneous_drain, "terminal": game._enemy_death_terminal_jobs.size(), "unique_keys": seen.size(), "source_slot_count": queue_source_slot_count, "ground_slot_limit": queue_ground_slot_limit, "natural_drain_max_frames": NATURAL_DRAIN_MAX_FRAMES})

	# A real one-microsecond budget leaves work pending; clearing the test
	# limits then resumes the same queue across later process frames.
	game = await _reset_game(44002)
	game.set_death_roll_quantum_slicing_for_test(true)
	for index: int in range(4):
		_queue_real_death(game, QUEUE_MONSTER_ID, index)
	_expect(game.set_death_drop_work_limits_for_test(1, 1, 1), "budget denial setup rejected")
	var before_denial: int = int(game._pending_enemy_deaths.size())
	var denied_phase := await _natural_drain(game, 2)
	var pending_after_denial: int = int(game._pending_enemy_deaths.size())
	_expect(pending_after_denial > 0 and pending_after_denial <= before_denial, "budget denial did not preserve pending queue")
	_expect(int(denied_phase.get("frames", 0)) > 0, "budget denial did not observe a real frame")
	game.clear_death_drop_work_limits_for_test()
	_expect(game._death_roll_quantum_slicing_enabled, "restoring work allowance cannot disable slicing")
	var recovered_phase := await _natural_drain(game, NATURAL_DRAIN_MAX_FRAMES)
	_expect(bool(recovered_phase.get("complete", false)), "restored budget did not naturally drain queue")
	_expect(game._pending_enemy_deaths.is_empty(), "restored budget left pending queue")
	_expect(game._enemy_death_terminal_jobs.size() == 4, "natural budget drain duplicated or lost terminal jobs")
	_queue_rows.append({"budget_denial_pending_before": before_denial, "denied_phase": denied_phase, "pending_after_denial": pending_after_denial, "recovered_phase": recovered_phase, "terminal_after_recovery": game._enemy_death_terminal_jobs.size(), "forced_drain_is_cleanup_only": false, "natural_recovery": true})

	# Generation/map cleanup is the production cancellation boundary.
	game = await _reset_game(44003)
	game.set_death_roll_quantum_slicing_for_test(true)
	_queue_real_death(game, QUEUE_MONSTER_ID, 0)
	_expect(not game._pending_enemy_deaths.is_empty(), "cleanup fixture did not queue death")
	game._zone_generation += 1
	game._cancel_pending_enemy_deaths_for_generation_change()
	_expect(game._pending_enemy_deaths.is_empty(), "generation cleanup left stale death queued")
	_expect(game._enemy_death_terminal_jobs.size() == 1, "cleanup did not retain cancellation receipt")
	_expect(str(game._enemy_death_terminal_jobs[0].get("state", "")) == "CANCELLED", "cleanup receipt was not CANCELLED")
	_queue_rows.append({"cleanup_pending": game._pending_enemy_deaths.size(), "cleanup_terminal": game._enemy_death_terminal_jobs.size(), "cleanup_state": game._enemy_death_terminal_jobs[0].get("state", "")})

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	if not bool(_current_service.get("_sheet_authority").valid):
		printerr("HC_TEST_FAIL formal drop authority unavailable: ", _current_service.get("_sheet_authority").load_error)
		get_tree().quit(1)
		return
	RuntimeDiagnostics.set_device_lab_performance_enabled(true)
	RuntimeDiagnostics.reset_performance_window()
	_run_roll_contract()
	await _run_queue_contract()
	var result := {
		"status": "PASS" if _failures.is_empty() else "FAIL",
		"failures": _failures,
		"checks": _checks,
		"contract": "historical_vs_current_unsliced_vs_current_sliced",
		"monster_ids": TEST_IDS,
		"death_order": DEATH_ORDER,
		"slice_sizes": SLICE_SIZES,
		"seeds": SEEDS,
		"rows": _rows,
		"queue_rows": _queue_rows,
		"first_pair": _first_pair,
		"queue_integration_status": "IMPLEMENTED",
		"historical_preimage_sha256": "12174C23B169C039B41ABD66FD15E9698B57A76F975AD0BA4D9175E7523E5796",
		"historical_helper_sha256": FileAccess.get_sha256("res://tests/helpers/loot_runtime_pre_slice_20261009.gd"),
		"game_root_source_sha256": FileAccess.get_sha256("res://scripts/game_root.gd"),
		"loot_runtime_source_sha256": FileAccess.get_sha256("res://scripts/layers/runtime/loot_runtime_service.gd"),
		"test_source_sha256": FileAccess.get_sha256("res://tests/crowd_death_roll_slicing_contract_20261009.gd"),
	}
	var file := FileAccess.open("res://outputs/test_logs/crowd_death_roll_slicing_contract_20261009.json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result, "\t"))
		file.close()
	if is_instance_valid(_game):
		_game.free()
	if is_instance_valid(_legacy_service):
		_legacy_service.free()
	if is_instance_valid(_current_service):
		_current_service.free()
	if _failures.is_empty():
		print("CROWD_DEATH_ROLL_SLICING_CONTRACT_PASS checks=%d queue=IMPLEMENTED" % _checks)
	else:
		printerr("CROWD_DEATH_ROLL_SLICING_CONTRACT_FAIL ", JSON.stringify(_failures))
	get_tree().quit(0 if _failures.is_empty() else 1)

