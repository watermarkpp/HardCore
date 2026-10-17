extends RefCounted
## Exact original GameRoot death queue arithmetic/order. This module owns no
## Profile/HP/save ledger. Shared state reads/writes route into one RootFields.
var _world_ref: WeakRef
var _world: RefCounted:
	get: return _world_ref.get_ref() if _world_ref != null else null
var _fields: RefCounted
var _ports_ref: WeakRef
var _ports: RefCounted:
	get: return _ports_ref.get_ref() if _ports_ref != null else null
var FrameBudget: Object:
	get: return _ports.required_owner_service(&"FrameBudget")
var CombatDiagnosticLogScript: Object:
	get: return _ports.required_owner_service(&"CombatDiagnosticLogScript")
var MonsterRespawnPolicyScript: Object:
	get: return _ports.required_owner_service(&"MonsterRespawnPolicyScript")
const DEATH_DROP_WORK_BUDGET_USEC := 1200

const DEATH_JOBS_MAX_PER_FRAME := 4

const DROP_NODES_MAX_PER_FRAME := 1

const DEATH_QUEUE_MAX_RETRIES := 3

const DEATH_QUEUE_RETRY_DELAY_MSEC := 100

const DEATH_TERMINAL_LEDGER_MAX := 64

const DEATH_STATE_QUEUED := "QUEUED"

const DEATH_STATE_PERSISTING := "PERSISTING"

var WorldClockDeltaScript: Object:
	get: return _ports.required_owner_service(&"WorldClockDeltaScript")
const DEATH_STATE_SETTLING := "SETTLING"

const DEATH_STATE_PLANNED := "PLANNED"

const DEATH_STATE_MATERIALIZING := "MATERIALIZING"

const DEATH_STATE_COMMITTED := "COMMITTED"

const DEATH_STATE_RETRY := "RETRY"

const DEATH_STATE_FAILED := "FAILED"

const DEATH_STATE_CANCELLED := "CANCELLED"

var _death_budget_category: Variant:
	get: return _fields.read_source_field(&"_death_budget_category")
	set(value): _fields.write_source_field(&"_death_budget_category", value)
var hud: Variant:
	get: return _fields.read_source_field(&"hud")
	set(value): _fields.write_source_field(&"hud", value)
var current_map_id: Variant:
	get: return _fields.read_source_field(&"current_map_id")
	set(value): _fields.write_source_field(&"current_map_id", value)
var _zone_generation: Variant:
	get: return _fields.read_source_field(&"_zone_generation")
	set(value): _fields.write_source_field(&"_zone_generation", value)
var _rng: Variant:
	get: return _fields.read_source_field(&"_rng")
	set(value): _fields.write_source_field(&"_rng", value)
var _pending_enemy_deaths: Variant:
	get: return _fields.read_source_field(&"_pending_enemy_deaths")
	set(value): _fields.write_source_field(&"_pending_enemy_deaths", value)
var _prepared_enemy_death_settlement: Variant:
	get: return _fields.read_source_field(&"_prepared_enemy_death_settlement")
	set(value): _fields.write_source_field(&"_prepared_enemy_death_settlement", value)
var _enemy_death_pipeline_running: Variant:
	get: return _fields.read_source_field(&"_enemy_death_pipeline_running")
	set(value): _fields.write_source_field(&"_enemy_death_pipeline_running", value)
var _enemy_death_target_refresh_pending: Variant:
	get: return _fields.read_source_field(&"_enemy_death_target_refresh_pending")
	set(value): _fields.write_source_field(&"_enemy_death_target_refresh_pending", value)
var _enemy_death_terminal_jobs: Variant:
	get: return _fields.read_source_field(&"_enemy_death_terminal_jobs")
	set(value): _fields.write_source_field(&"_enemy_death_terminal_jobs", value)
var _enemy_death_terminal_total_count: Variant:
	get: return _fields.read_source_field(&"_enemy_death_terminal_total_count")
	set(value): _fields.write_source_field(&"_enemy_death_terminal_total_count", value)
var _last_death_logout_failure: Variant:
	get: return _fields.read_source_field(&"_last_death_logout_failure")
	set(value): _fields.write_source_field(&"_last_death_logout_failure", value)
var _death_settled_jobs_last_batch: Variant:
	get: return _fields.read_source_field(&"_death_settled_jobs_last_batch")
	set(value): _fields.write_source_field(&"_death_settled_jobs_last_batch", value)
var _death_drop_work_budget_usec_override: Variant:
	get: return _fields.read_source_field(&"_death_drop_work_budget_usec_override")
	set(value): _fields.write_source_field(&"_death_drop_work_budget_usec_override", value)
var _last_drop_node_frame: Variant:
	get: return _fields.read_source_field(&"_last_drop_node_frame")
	set(value): _fields.write_source_field(&"_last_drop_node_frame", value)
var _death_jobs_max_per_frame_override: Variant:
	get: return _fields.read_source_field(&"_death_jobs_max_per_frame_override")
	set(value): _fields.write_source_field(&"_death_jobs_max_per_frame_override", value)
var _drop_nodes_max_per_frame_override: Variant:
	get: return _fields.read_source_field(&"_drop_nodes_max_per_frame_override")
	set(value): _fields.write_source_field(&"_drop_nodes_max_per_frame_override", value)
var _death_roll_quantum_slicing_enabled: Variant:
	get: return _fields.read_source_field(&"_death_roll_quantum_slicing_enabled")
	set(value): _fields.write_source_field(&"_death_roll_quantum_slicing_enabled", value)
var _death_optional_pump_frame: Variant:
	get: return _fields.read_source_field(&"_death_optional_pump_frame")
	set(value): _fields.write_source_field(&"_death_optional_pump_frame", value)
var _test_force_loot_materialization_failure_count: Variant:
	get: return _fields.read_source_field(&"_test_force_loot_materialization_failure_count")
	set(value): _fields.write_source_field(&"_test_force_loot_materialization_failure_count", value)
var _loot_legacy_reference_fallback_test_enabled: Variant:
	get: return _fields.read_source_field(&"_loot_legacy_reference_fallback_test_enabled")
	set(value): _fields.write_source_field(&"_loot_legacy_reference_fallback_test_enabled", value)
var _drop_instance_session_key: Variant:
	get: return _fields.read_source_field(&"_drop_instance_session_key")
	set(value): _fields.write_source_field(&"_drop_instance_session_key", value)

const REQUIRED_BOUNDARIES := ["_materialize_enemy_death_nodes", "_refresh_target_highlights", "_respawn_later", "_update_target_hud", "source_hud_is_present", "required_owner_service"]
func configure_owner(world: RefCounted, fields: RefCounted, ports: RefCounted) -> bool:
	if _world != null or OS.get_thread_caller_id() == OS.get_main_thread_id(): return false
	for method: String in REQUIRED_BOUNDARIES:
		if not ports.has_method(method): return false
	_world_ref = weakref(world)
	_fields = fields
	_ports_ref = weakref(ports)
	return true

func _pump_enemy_death_work_queue(force_synchronous := false) -> bool:
	if _enemy_death_pipeline_running:
		return false
	_enemy_death_pipeline_running = true
	# Already accepted settlement receipts and reference cleanup are necessary.
	# They share accounting, but cannot be rejected by optional-work exhaustion.
	var receipt_token: int = _world.frame_budget.begin("death_receipt", true)
	var progressed := _poll_prepared_enemy_death_settlement(force_synchronous)
	if _enemy_death_target_refresh_pending:
		_enemy_death_target_refresh_pending = false
		_world.diagnostics.increment_performance_counter(&"death_target_refresh_count")
		if _world.is_inside_world():
			_ports._refresh_target_highlights()
			if _ports.source_hud_is_present():
				_ports._update_target_hud()
		progressed = true
	_compact_enemy_death_queue()
	_world.frame_budget.end(receipt_token)
	_refresh_death_budget_owner()
	if not _pending_enemy_deaths.is_empty():
		var process_frame: int = _world.clock_ports.get_process_frames()
		var optional_allowed: bool = force_synchronous or _death_optional_pump_frame != process_frame
		if optional_allowed:
			var token: int = _world.frame_budget.begin(_death_budget_category, force_synchronous)
			if token > 0:
				var optional_progressed := _advance_enemy_death_work_slice(force_synchronous, false)
				progressed = optional_progressed or progressed
				if optional_progressed and not force_synchronous:
					_death_optional_pump_frame = process_frame
				_world.frame_budget.end(token)
	_enemy_death_pipeline_running = false
	_refresh_death_budget_owner()
	return progressed



func _refresh_death_budget_owner() -> void:
	var runnable: bool = not _pending_enemy_deaths.is_empty()
	if runnable:
		var head: Dictionary = _pending_enemy_deaths[0]
		runnable = str(head.get("state", "")) != DEATH_STATE_PERSISTING
		if str(head.get("state", "")) == DEATH_STATE_RETRY:
			runnable = _death_retry_ready(head)
	_world.frame_budget.mark_pending(_death_budget_category, not _pending_enemy_deaths.is_empty(), runnable, false, _world.original_source_scope("game_root"))



func _advance_enemy_death_work_slice(force_synchronous: bool, progressed: bool) -> bool:
	# Scheduling is production behavior, independent of diagnostic sampling.
	# Diagnostic timers return zero when disabled (the normal gameplay case).
	var slice_started_usec: int = _world.clock_ports.get_ticks_usec()
	var budget_usec := _death_drop_work_budget_usec()
	if not force_synchronous:
		budget_usec = mini(budget_usec, _world.frame_budget.remaining_usec())
	var jobs_limit := _death_jobs_max_per_frame()
	var nodes_limit := _drop_nodes_max_per_frame()
	if not force_synchronous and not _world.profile.test_mode:
		# Keep large reward bursts off one render frame, even if a project override is higher.
		nodes_limit = mini(nodes_limit, 1)
	if force_synchronous:
		budget_usec = 2147483647
		jobs_limit = 2147483647
		nodes_limit = 2147483647
	if _pending_enemy_deaths.is_empty():
		return progressed
	var jobs_processed: int = _death_settled_jobs_last_batch
	var nodes_processed := 0
	var unsettled_index := _first_unsettled_death_index()
	if unsettled_index >= 0 and str(_pending_enemy_deaths[unsettled_index].get("state", "")) == DEATH_STATE_RETRY:
		var retry_item: Dictionary = _pending_enemy_deaths[unsettled_index]
		if force_synchronous or _death_retry_ready(retry_item):
			retry_item["retry_at_msec"] = 0
			_set_enemy_death_state(retry_item, DEATH_STATE_QUEUED)
			progressed = true
	if unsettled_index >= 0 and str(_pending_enemy_deaths[unsettled_index].get("state", "")) == DEATH_STATE_QUEUED:
		if (
			(force_synchronous or _death_retry_ready(_pending_enemy_deaths[unsettled_index]))
			and (
				force_synchronous
				or _world.clock_ports.get_ticks_usec() - slice_started_usec < budget_usec
			)
		):
			# Settlement and display consume one canonical queue independently.
			# Reserve one work slot for an older display so new deaths cannot starve it.
			var display_reserved := 1 if unsettled_index > 0 and not force_synchronous else 0
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed - display_reserved, force_synchronous or _world.profile.test_mode):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
	while not _pending_enemy_deaths.is_empty():
		if (
			not force_synchronous
			and _world.clock_ports.get_ticks_usec() - slice_started_usec >= budget_usec
		):
			break
		var death: Dictionary = _pending_enemy_deaths[0]
		var state := str(death.get("state", ""))
		if state in [DEATH_STATE_FAILED, DEATH_STATE_CANCELLED, DEATH_STATE_COMMITTED]:
			_compact_enemy_death_queue()
			progressed = true
			continue
		if state == DEATH_STATE_RETRY:
			if not force_synchronous and not _death_retry_ready(death):
				break
			death["retry_at_msec"] = 0
			_set_enemy_death_state(death, DEATH_STATE_QUEUED)
			progressed = true
			continue
		if state == DEATH_STATE_QUEUED:
			if not force_synchronous and not _death_retry_ready(death):
				break
			if jobs_processed >= jobs_limit:
				break
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed, force_synchronous or _world.profile.test_mode):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
				continue
			break
		if state == DEATH_STATE_PERSISTING:
			break # A real file receipt is pending; no reward roll or display yet.
		if state == DEATH_STATE_SETTLING:
			if jobs_processed >= jobs_limit:
				break
			jobs_processed += 1
			if _plan_enemy_death_item(death, slice_started_usec, budget_usec):
				progressed = true
				continue
			break
		if state == DEATH_STATE_PLANNED:
			if jobs_processed >= jobs_limit:
				break
			_set_enemy_death_state(death, DEATH_STATE_MATERIALIZING)
			jobs_processed += 1
			progressed = true
		elif state == DEATH_STATE_MATERIALIZING:
			if jobs_processed >= jobs_limit:
				break
			if not force_synchronous and not _death_retry_ready(death):
				break
			jobs_processed += 1
		if (
			not force_synchronous
			and not _world.profile.test_mode
			and int(death.get("remaining_request_count", 0)) > 0
			and _world.clock_ports.get_process_frames() - _last_drop_node_frame < 2
		):
			break
		var materialization: Dictionary = _ports._materialize_enemy_death_nodes(
			death,
			slice_started_usec,
			budget_usec,
			nodes_limit - nodes_processed,
			force_synchronous,
		)
		nodes_processed += int(materialization.get("nodes", 0))
		if bool(materialization.get("progressed", false)):
			progressed = true
		if bool(materialization.get("complete", false)):
			if str(death.get("state", "")) == DEATH_STATE_MATERIALIZING:
				_commit_enemy_death_item(death)
			elif str(death.get("state", "")) == DEATH_STATE_FAILED:
				# The XP/quest/respawn transaction already committed before node
				# materialization. A terminal node failure must not strand a valid
				# respawn, but it must never retry or duplicate a reward node.
				_schedule_queued_enemy_respawn(death)
			progressed = true
			_compact_enemy_death_queue()
			continue
		break
	if progressed:
		_world.diagnostics.increment_performance_counter(&"death_work_frames")
		_world.diagnostics.increment_performance_counter(&"drop_work_frames")
	_world.diagnostics.record_performance_max(
		&"death_jobs_per_frame_max", float(jobs_processed)
	)
	_world.diagnostics.record_performance_max(
		&"drop_nodes_per_frame_max", float(nodes_processed)
	)
	return progressed



func _death_drop_work_budget_usec() -> int:
	if _death_drop_work_budget_usec_override >= 0:
		return maxi(1, _death_drop_work_budget_usec_override)
	return maxi(
		1,
		int(_world.clock_ports.get_setting(
			"hardcore/performance/death_drop_work_budget_usec",
			DEATH_DROP_WORK_BUDGET_USEC,
		)),
	)



func _death_jobs_max_per_frame() -> int:
	if _death_jobs_max_per_frame_override >= 0:
		return maxi(1, _death_jobs_max_per_frame_override)
	return maxi(
		1,
		int(_world.clock_ports.get_setting(
			"hardcore/performance/death_jobs_max_per_frame",
			DEATH_JOBS_MAX_PER_FRAME,
		)),
	)



func _drop_nodes_max_per_frame() -> int:
	if _drop_nodes_max_per_frame_override >= 0:
		return maxi(1, _drop_nodes_max_per_frame_override)
	return maxi(
		1,
		int(_world.clock_ports.get_setting(
			"hardcore/performance/drop_nodes_max_per_frame",
			DROP_NODES_MAX_PER_FRAME,
		)),
	)



func set_death_drop_work_limits_for_test(
	budget_usec: int,
	jobs_per_frame: int,
	nodes_per_frame: int,
) -> bool:
	if not _world.profile.test_mode:
		return false
	_death_drop_work_budget_usec_override = budget_usec
	_death_jobs_max_per_frame_override = jobs_per_frame
	_drop_nodes_max_per_frame_override = nodes_per_frame
	return true



func clear_death_drop_work_limits_for_test() -> void:
	_death_drop_work_budget_usec_override = -1
	_death_jobs_max_per_frame_override = -1
	_drop_nodes_max_per_frame_override = -1


func set_death_roll_quantum_slicing_for_test(enabled: bool) -> bool:
	if not _world.profile.test_mode:
		return false
	_death_roll_quantum_slicing_enabled = enabled
	return true



func set_loot_materialization_failure_count_for_test(count: int) -> bool:
	if not _world.profile.test_mode:
		return false
	_test_force_loot_materialization_failure_count = maxi(0, count)
	return true



func set_loot_legacy_reference_fallback_for_test(enabled: bool) -> bool:
	if enabled and not _world.profile.test_mode:
		return false
	_loot_legacy_reference_fallback_test_enabled = enabled
	return true



func death_work_queue_snapshot() -> Dictionary:
	var oldest_age_usec := 0
	var maximum_completion_latency_usec := 0
	for death: Dictionary in _pending_enemy_deaths:
		oldest_age_usec = maxi(oldest_age_usec, _world.clock_ports.get_ticks_usec() - int(death.get("queued_at_usec", _world.clock_ports.get_ticks_usec())))
	for death: Dictionary in _enemy_death_terminal_jobs:
		maximum_completion_latency_usec = maxi(maximum_completion_latency_usec,
			int(death.get("completion_latency_usec", 0)))
	return {
		"oldest_age_usec": oldest_age_usec,
		"maximum_completion_latency_usec": maximum_completion_latency_usec,
		"pending": _pending_enemy_deaths.duplicate(true),
		"terminal": _enemy_death_terminal_jobs.duplicate(true),
		"terminal_count": _enemy_death_terminal_total_count,
		"terminal_ledger_limit": DEATH_TERMINAL_LEDGER_MAX,
	}



func _death_retry_ready(death: Dictionary) -> bool:
	return _world.clock_ports.get_ticks_msec() >= int(death.get("retry_at_msec", 0))



func _set_enemy_death_state(death: Dictionary, next_state: String) -> void:
	var previous := str(death.get("state", ""))
	if previous == next_state:
		return
	death["state"] = next_state
	_world.diagnostics.increment_performance_counter(
		&"death_queue_state_transitions"
	)



func _compact_enemy_death_queue() -> void:
	if _pending_enemy_deaths.is_empty():
		return
	var retained: Array[Dictionary] = []
	for death: Dictionary in _pending_enemy_deaths:
		var state := str(death.get("state", ""))
		if state in [DEATH_STATE_FAILED, DEATH_STATE_CANCELLED, DEATH_STATE_COMMITTED]:
			death["completion_latency_usec"] = maxi(0,
				_world.clock_ports.get_ticks_usec() - int(death.get("queued_at_usec", _world.clock_ports.get_ticks_usec())))
			if state == DEATH_STATE_FAILED and _last_death_logout_failure.is_empty():
				_last_death_logout_failure = {
					"success": false,
					"save_performed": false,
					"reason": "safe_logout_death_queue_failed",
					"death_key": str(death.get("death_key", "")),
					"death_error": str(death.get("last_error", "")),
				}
			_enemy_death_terminal_total_count += 1
			if _enemy_death_terminal_jobs.size() >= DEATH_TERMINAL_LEDGER_MAX:
				_enemy_death_terminal_jobs.pop_front()
			_enemy_death_terminal_jobs.append(death.duplicate(true))
		else:
			retained.append(death)
	_pending_enemy_deaths = retained



func _death_origin_matches_current(death: Dictionary) -> bool:
	return (
		bool(death.get("origin_captured", false))
		and
		int(death.get("origin_map_id", -1)) == current_map_id
		and int(death.get("origin_generation", -1)) == _zone_generation
	)



func _cancel_pending_enemy_deaths_for_generation_change() -> void:
	if not _prepared_enemy_death_settlement.is_empty():
		_prepared_enemy_death_settlement.plan.writer.cancel()
		_poll_prepared_enemy_death_settlement(true)
	if _pending_enemy_deaths.is_empty():
		return
	for death: Dictionary in _pending_enemy_deaths:
		if (
			bool(death.get("origin_captured", false))
			and int(death.get("origin_generation", -1)) == _zone_generation
			and int(death.get("origin_map_id", -1)) == current_map_id
		):
			continue
		death["last_error"] = "origin_map_generation_changed_before_settlement"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		_world.diagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
	_compact_enemy_death_queue()




func _first_unsettled_death_index() -> int:
	for index: int in range(_pending_enemy_deaths.size()):
		if str(_pending_enemy_deaths[index].get("state", "")) in [DEATH_STATE_QUEUED, DEATH_STATE_RETRY, DEATH_STATE_PERSISTING]:
			return index
	return -1



func _death_settlement_origins_valid(batch: Array[Dictionary]) -> bool:
	for death: Dictionary in batch:
		if not _death_origin_matches_current(death):
			return false
	return true



func _poll_prepared_enemy_death_settlement(wait := false) -> bool:
	_death_settled_jobs_last_batch = 0
	if _prepared_enemy_death_settlement.is_empty():
		return false
	var cohort: Dictionary = _prepared_enemy_death_settlement
	var settlement: Dictionary = _world.profile.finish_prepared_death_settlement(cohort.plan, wait)
	if bool(settlement.get("pending", false)):
		return false
	_prepared_enemy_death_settlement = {}
	_death_settled_jobs_last_batch = (cohort.batch as Array).size()
	var started_usec: int = _world.diagnostics.timing_start()
	_finish_enemy_death_settlement_batch(cohort.batch, settlement)
	_world.diagnostics.record_timing_usec(&"death_settlement_usec", started_usec)
	return true



func _settle_pending_enemy_death_batch(
	max_deaths := DEATH_JOBS_MAX_PER_FRAME,
	force_synchronous := true,
) -> bool:
	_death_settled_jobs_last_batch = 0
	if not _prepared_enemy_death_settlement.is_empty():
		return false
	if _pending_enemy_deaths.is_empty():
		return false
	if max_deaths <= 0:
		return false
	var unsettled_index := _first_unsettled_death_index()
	if unsettled_index < 0:
		return false
	var first: Dictionary = _pending_enemy_deaths[unsettled_index]
	if str(first.get("state", "")) != DEATH_STATE_QUEUED:
		return false
	if not _death_retry_ready(first):
		return false
	# Reject stale/unidentified deaths before touching PlayerState.  This guard
	# is intentionally before the batched save so an old actor can never grant
	# XP, quest progress, respawn state, or a drop after a map transition.
	if not _death_origin_matches_current(first):
		first["last_error"] = (
			"origin_map_generation_mismatch_before_settlement"
			if bool(first.get("origin_captured", false))
			else "death_origin_missing"
		)
		_set_enemy_death_state(first, DEATH_STATE_CANCELLED)
		_death_settled_jobs_last_batch = 1
		_world.diagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return true
	var batch: Array[Dictionary] = []
	for death_index: int in range(unsettled_index, _pending_enemy_deaths.size()):
		var death: Dictionary = _pending_enemy_deaths[death_index]
		if batch.size() >= max_deaths:
			break
		if str(death.get("state", "")) != DEATH_STATE_QUEUED:
			break
		if not _death_retry_ready(death):
			break
		if not _death_origin_matches_current(death):
			break
		_set_enemy_death_state(death, DEATH_STATE_SETTLING)
		batch.append(death)
	if batch.is_empty():
		return false
	_death_settled_jobs_last_batch = batch.size()
	_world.diagnostics.increment_performance_counter(&"death_batch_count")
	_world.diagnostics.record_performance_max(
		&"death_batch_size_max", float(batch.size())
	)
	var oldest_queued_usec := int(batch[0].get("queued_at_usec", 0))
	_world.diagnostics.record_performance_max(
		&"drop_queue_oldest_age_ms",
		float(_world.diagnostics.timing_elapsed_usec(oldest_queued_usec)) / 1000.0,
	)
	var settlements: Array = []
	var respawn_state_before: Dictionary = (
		_world.profile.world_clock_mutation_snapshot() if force_synchronous else {}
	)
	var world_upserts: Dictionary = {}
	for death: Dictionary in batch:
		var respawn_preparation := _prepare_queued_enemy_respawn(death, force_synchronous)
		if respawn_preparation.has("world_entry"):
			world_upserts[str(respawn_preparation.world_key)] = respawn_preparation.world_entry
		death["respawn_preparation"] = respawn_preparation
		var respawn: Dictionary = death.get("respawn", {})
		respawn["preparation"] = respawn_preparation
		death["respawn"] = respawn
		settlements.append({
			"monster_name": str(death.get("monster_name", "")),
			"experience": int(death.get("experience", 0)),
		})
	var settlement_started_usec: int = _world.diagnostics.timing_start()
	if not force_synchronous:
		var plan: Dictionary = _world.profile.prepare_death_settlement(settlements, world_upserts, _death_settlement_origins_valid.bind(batch))
		if bool(plan.get("pending", false)) and not plan.has("writer"):
			for death: Dictionary in batch:
				_set_enemy_death_state(death, DEATH_STATE_QUEUED)
			_death_settled_jobs_last_batch = 0
			return false
		if plan.has("immediate"):
			_finish_enemy_death_settlement_batch(batch, plan.immediate)
			return true
		for death: Dictionary in batch:
			_set_enemy_death_state(death, DEATH_STATE_PERSISTING)
		_prepared_enemy_death_settlement = {"batch": batch, "plan": plan}
		_world.diagnostics.record_timing_usec(&"death_prepare_usec", settlement_started_usec)
		return true
	var settlement: Dictionary = _world.profile.record_kills_and_experience_batch(
		settlements,
		true,
	)
	_world.diagnostics.record_timing_usec(
		&"death_settlement_usec", settlement_started_usec
	)
	_finish_enemy_death_settlement_batch(batch, settlement, respawn_state_before)
	return true



func _finish_enemy_death_settlement_batch(batch: Array[Dictionary], settlement: Dictionary, respawn_state_before: Dictionary = {}) -> void:
	if bool(settlement.get("success", false)) and not bool(settlement.get("active_state_applied", true)):
		for death: Dictionary in batch:
			death["transaction_result"] = settlement.duplicate(true)
			death["last_error"] = "settlement_saved_for_inactive_role"
			_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		_compact_enemy_death_queue()
		return
	if not bool(settlement.get("success", false)):
		# Respawn state, quest progress and experience are one save boundary. A
		# failed save restores the pre-attempt state, and the death item remains
		# observable for retry/terminal handling; no drop roll is performed.
		if not respawn_state_before.is_empty():
			_world.profile.restore_world_clock_mutation(respawn_state_before)
		for death: Dictionary in batch:
			death["transaction_result"] = settlement.duplicate(true)
			death["last_error"] = str(settlement.get("reason", "save_failed"))
			death["retry_count"] = int(death.get("retry_count", 0)) + 1
			if int(death["retry_count"]) >= DEATH_QUEUE_MAX_RETRIES:
				_set_enemy_death_state(death, DEATH_STATE_FAILED)
				_world.diagnostics.increment_performance_counter(
					&"death_queue_failed_count"
				)
			else:
				death["retry_at_msec"] = (
					_world.clock_ports.get_ticks_msec() + DEATH_QUEUE_RETRY_DELAY_MSEC
				)
				_set_enemy_death_state(death, DEATH_STATE_RETRY)
				_world.diagnostics.increment_performance_counter(
					&"death_queue_retry_count"
				)
		_compact_enemy_death_queue()
		return
	for death: Dictionary in batch:
		death["transaction_result"] = settlement.duplicate(true)
		# The durable receipt closes PERSISTING. Resume reward planning through
		# the same stage used by synchronous settlement, without settling twice.
		_set_enemy_death_state(death, DEATH_STATE_SETTLING)
	return



func _plan_enemy_death_item(death: Dictionary, slice_started_usec := 0, budget_usec := 0) -> bool:
	if not _death_origin_matches_current(death):
		death["last_error"] = "origin_map_generation_mismatch_before_roll"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		_world.diagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return true
	var started_usec: int = _world.diagnostics.timing_start()
	var monster_id := int(death.get("monster_id", -1))
	var drop_roll: Dictionary
	if _death_roll_quantum_slicing_enabled:
		var resumable: Dictionary = death.get("drop_roll_job", {})
		if resumable.is_empty():
			_world.diagnostics.increment_performance_counter(&"drop_roll_count")
			resumable = LootRuntime.begin_monster_drop_roll_job(monster_id, _rng, false)
		var advanced := LootRuntime.advance_monster_drop_roll_job(resumable, 1)
		# A source row is a small resumable quantum, not a whole death job.
		# Use the admitted slice's existing wall budget for further quanta;
		# retain the cursor as soon as that budget is spent. RNG order is unchanged.
		while (
			not bool(advanced.get("done", false))
			and budget_usec > 0
			and _world.clock_ports.get_ticks_usec() - slice_started_usec < budget_usec
		):
			advanced = LootRuntime.advance_monster_drop_roll_job(advanced, 1)
		if not bool(advanced.get("done", false)):
			death["drop_roll_job"] = advanced
			_world.diagnostics.increment_performance_counter(&"drop_roll_slice_count")
			_world.diagnostics.record_timing_usec(&"drop_roll_usec", started_usec)
			return true
		drop_roll = advanced.get("result", {})
		death.erase("drop_roll_job")
	else:
		_world.diagnostics.increment_performance_counter(&"drop_roll_count")
		drop_roll = LootRuntime.roll_monster_drops(monster_id, _rng, false)
	var death_position: Vector2 = death.get("death_position", Vector2.ZERO)
	var requests: Array[Dictionary] = []
	var raw_items: Variant = drop_roll.get("items", [])
	var identity_records: Array = drop_roll.get("item_records", [])
	if raw_items is Array:
		for item_index in range(raw_items.size()):
			var item_name := str(raw_items[item_index])
			var identity_record: Dictionary = (
				identity_records[item_index]
				if item_index < identity_records.size() and identity_records[item_index] is Dictionary
				else {}
			)
			identity_record = _world.profile.create_drop_item_instance(
				identity_record,
				"%s:%s:item:%d" % [_drop_instance_session_key, str(death.get("death_key", "")), item_index],
			)
			requests.append({
				"item_name": item_name,
				"item_record": identity_record,
				"position": death_position + Vector2(
					_rng.randf_range(-34, 34),
					_rng.randf_range(-18, 18)
				),
			})
	var raw_gold_drops: Variant = drop_roll.get("gold_drops", [])
	if raw_gold_drops is Array:
		for raw_gold: Variant in raw_gold_drops:
			var amount := int(raw_gold)
			if amount > 0:
				requests.append({
					"gold_amount": amount,
					"position": death_position + Vector2(
						_rng.randf_range(-34, 34),
						_rng.randf_range(-18, 18)
					),
				})
	var overflow_discarded_count := int(
		drop_roll.get("overflow_discarded_count", 0)
	)
	if overflow_discarded_count > 0:
		var overflow_telemetry := LootRuntime.record_overflow_telemetry(
			monster_id,
			drop_roll
		)
		if (
			not overflow_telemetry.is_empty()
			and CombatDiagnosticLogScript.capture_enabled()
		):
			CombatDiagnosticLogScript.record({
				"event": "loot_overflow_discarded",
				"monster_id": int(overflow_telemetry.get("monster_id", monster_id)),
				"successful_roll_count": int(
					overflow_telemetry.get("successful_roll_count", 0)
				),
				"ground_output_count": int(
					overflow_telemetry.get("ground_output_count", 0)
				),
				"overflow_discarded_count": int(
					overflow_telemetry.get("overflow_discarded_count", 0)
				),
				"protected_overflow_count": int(
					overflow_telemetry.get("protected_overflow_count", 0)
				),
			})
	death["drop_plan"] = {
		"roll": drop_roll.duplicate(true),
		"requests": requests,
		"next_request_index": 0,
		"item_count": raw_items.size() if raw_items is Array else 0,
		"gold_drop_count": raw_gold_drops.size() if raw_gold_drops is Array else 0,
		"materialized": false,
	}
	death["remaining_requests"] = requests.duplicate(true)
	death["remaining_request_count"] = requests.size()
	death["reward_status"] = "planned"
	death["materialized_node_index"] = 0
	death["materialized_node_count"] = 0
	death["materialization_retry_count"] = 0
	_set_enemy_death_state(death, DEATH_STATE_PLANNED)
	_world.diagnostics.increment_performance_counter(
		&"drop_request_count", requests.size()
	)
	_world.diagnostics.record_timing_usec(&"drop_roll_usec", started_usec)
	return true



func _commit_enemy_death_item(death: Dictionary) -> void:
	_schedule_queued_enemy_respawn(death)
	death["reward_status"] = "committed"
	_set_enemy_death_state(death, DEATH_STATE_COMMITTED)
	_world.diagnostics.increment_performance_counter(
		&"death_queue_committed_count"
	)
	# AOE window probe: first committed death closes the first-engagement
	# window. Diagnostics only.
	AoeEngagementWindow.on_enemy_death_committed()



func _schedule_queued_enemy_respawn(death: Dictionary) -> void:
	if bool(death.get("respawn_scheduled", false)):
		return
	var preparation: Dictionary = death.get("respawn_preparation", {})
	if preparation.is_empty() or not bool(preparation.get("valid", false)):
		return
	if not bool(preparation.get("enabled", false)):
		return
	var canonical_monster: Dictionary = death.get("canonical_monster", {})
	var respawn: Dictionary = death.get("respawn", {})
	var spawn_context: Dictionary = preparation.get(
		"spawn_context", respawn.get("spawn_context", {})
	)
	var world_entry: Dictionary = preparation.get("world_entry", {})
	var remaining_seconds := maxf(
		0.0,
		float(world_entry.get("respawn_at_unix", 0.0)) - _world.clock_ports.get_unix_time_from_system()
	)
	_ports._respawn_later(
		canonical_monster,
		death.get("spawn_position", death.get("death_position", Vector2.ZERO)),
		bool(respawn.get("was_boss", death.get("was_boss", false))),
		remaining_seconds,
		int(death.get("origin_generation", _zone_generation)),
		spawn_context,
	)
	death["respawn_scheduled"] = true



func _resolve_queued_enemy_death(
	death: Dictionary,
	_spread_across_frames := false,
) -> Dictionary:
	# Compatibility helper retained for focused tests/tools.  Production uses
	# _pump_enemy_death_work_queue so scheduling and state transitions remain
	# observable and budgeted.
	var started_usec: int = _world.diagnostics.timing_start()
	if not death.has("origin_map_id"):
		# Compatibility callers must provide a frozen origin explicitly.  Never
		# manufacture one from the current world here, since this helper may be
		# invoked after a delayed death signal.
		death["origin_map_id"] = -1
		death["origin_generation"] = -1
		death["origin_captured"] = false
	if str(death.get("state", "")) == "":
		death["state"] = DEATH_STATE_SETTLING
	var raw_plan: Variant = death.get("drop_plan", {})
	if not raw_plan is Dictionary or (raw_plan as Dictionary).is_empty():
		_plan_enemy_death_item(death)
	if str(death.get("state", "")) == DEATH_STATE_PLANNED:
		_set_enemy_death_state(death, DEATH_STATE_MATERIALIZING)
	var result: Dictionary = _ports._materialize_enemy_death_nodes(
		death,
		_world.diagnostics.timing_start(),
		2147483647,
		2147483647,
		true,
	)
	if bool(result.get("complete", false)) and str(death.get("state", "")) == DEATH_STATE_MATERIALIZING:
		_commit_enemy_death_item(death)
	return {
		"monster_id": int(death.get("monster_id", -1)),
		"item_count": int((death.get("drop_plan", {}) as Dictionary).get("item_count", 0)),
		"gold_drop_count": int((death.get("drop_plan", {}) as Dictionary).get("gold_drop_count", 0)),
		"respawn_scheduled": bool(death.get("respawn_scheduled", false)),
		"state": str(death.get("state", "")),
		"reason": str(death.get("last_error", "")),
		"total_ms": float(_world.diagnostics.timing_elapsed_usec(started_usec)) / 1000.0,
	}



func _prepare_queued_enemy_respawn(death: Dictionary, apply_world := true) -> Dictionary:
	if not bool(death.get("respawn_enabled", true)):
		return {"valid": true, "enabled": false}
	var monster_id := int(death.get("monster_id", -1))
	var canonical_monster: Dictionary = death.get("canonical_monster", {})
	var spawn_context: Dictionary = (
		(death.get("spawn_context", {}) as Dictionary).duplicate(true)
	)
	var spawn_classification := str(
		canonical_monster.get("spawn_classification", "")
	)
	var policy: Dictionary = MonsterRespawnPolicyScript.resolve(
		str(spawn_context.get("respawn_policy_id", "")),
		str(canonical_monster.get("classification", "")),
		float(death.get("configured_respawn", -1.0)),
		spawn_classification
	)
	if not bool(policy.get("valid", false)):
		push_error(
			"Monster death respawn policy rejected monster_id=%d reason=%s"
			% [monster_id, str(policy.get("reason", "invalid_policy"))]
		)
		return {"valid": false, "reason": "invalid_respawn_policy"}
	var respawn_wait_seconds := float(policy.get("seconds", 0.0))
	var respawn_runtime_map_id := int(
		spawn_context.get("respawn_runtime_map_id", current_map_id)
	)
	var spawn_slot_id := str(spawn_context.get("spawn_slot_id", ""))
	var world_entry := {"runtime_map_id": respawn_runtime_map_id, "spawn_slot_id": spawn_slot_id.strip_edges(),
		"monster_id": monster_id, "policy_id": str(policy.get("policy_id", "")),
		"respawn_at_unix": _world.clock_ports.get_unix_time_from_system() + respawn_wait_seconds}
	var world_key := "%d|%s" % [respawn_runtime_map_id, spawn_slot_id.strip_edges()]
	var respawn_marked: bool = (
		_world.profile.mark_monster_respawn_dead(respawn_runtime_map_id, spawn_slot_id, monster_id,
			str(policy.get("policy_id", "")), float(world_entry.respawn_at_unix))
		if apply_world else WorldClockDeltaScript.valid_world_entry(world_key, world_entry)
	)
	if not respawn_marked:
		push_error(
			"Monster respawn state rejected unstable slot monster_id=%d map_id=%d slot=%s"
			% [monster_id, respawn_runtime_map_id, spawn_slot_id]
		)
		return {"valid": false, "reason": "unstable_respawn_slot"}
	if apply_world:
		_world.diagnostics.increment_performance_counter(&"respawn_state_updates")
	spawn_context["respawn_policy_id"] = str(policy.get("policy_id", ""))
	spawn_context["spawn_classification"] = spawn_classification
	spawn_context["respawn_base_seconds"] = respawn_wait_seconds
	spawn_context["respawn_random_seconds"] = 0.0
	return {
		"valid": true,
		"enabled": true,
		"wait_seconds": respawn_wait_seconds,
		"spawn_context": spawn_context,
		"world_key": world_key,
		"world_entry": world_entry,
	}



func owner_thread_id() -> int: return _world.owner_thread_id()
