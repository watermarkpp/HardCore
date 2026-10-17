extends RefCounted

## Same-source owner-local service. One instance per S owner, shared by actors.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var deps: Dictionary
var actors: Object

func configure_owner(bindings: Dictionary, actor_access: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		push_error("Enemy shared service configured twice or from another owner")
		return false
	if actor_access == null or actor_access is Node or actor_access is Resource or not actor_access.has_method("owner_thread_id") or actor_access.owner_thread_id() != _owner_thread:
		push_error("Enemy shared service requires owner-local actor access")
		return false
	actors = actor_access
	deps = {"Engine": bindings.get("Engine"), "Time": bindings.get("Time"), "FrameBudget": bindings.get("FrameBudget")}
	if not deps.get("Engine") is Object or deps.Engine is Node or deps.Engine is Resource or not deps.Engine.has_method("owner_thread_id") or deps.Engine.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: Engine")
		return false
	if not deps.Engine.has_method("get_physics_frames"):
		push_error("Enemy dependency method missing: Engine.get_physics_frames")
		return false
	if not deps.Engine.has_method("get_process_frames"):
		push_error("Enemy dependency method missing: Engine.get_process_frames")
		return false
	if not deps.get("Time") is Object or deps.Time is Node or deps.Time is Resource or not deps.Time.has_method("owner_thread_id") or deps.Time.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: Time")
		return false
	if not deps.Time.has_method("get_ticks_usec"):
		push_error("Enemy dependency method missing: Time.get_ticks_usec")
		return false
	if not deps.get("FrameBudget") is Object or deps.FrameBudget is Node or deps.FrameBudget is Resource or not deps.FrameBudget.has_method("owner_thread_id") or deps.FrameBudget.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: FrameBudget")
		return false
	if not deps.FrameBudget.has_method("begin"):
		push_error("Enemy dependency method missing: FrameBudget.begin")
		return false
	if not deps.FrameBudget.has_method("begin_progress"):
		push_error("Enemy dependency method missing: FrameBudget.begin_progress")
		return false
	if not deps.FrameBudget.has_method("end"):
		push_error("Enemy dependency method missing: FrameBudget.end")
		return false
	if not deps.FrameBudget.has_method("last_denial_record"):
		push_error("Enemy dependency method missing: FrameBudget.last_denial_record")
		return false
	if not deps.FrameBudget.has_method("mark_pending"):
		push_error("Enemy dependency method missing: FrameBudget.mark_pending")
		return false
	if not deps.FrameBudget.has_method("mark_progress_pending"):
		push_error("Enemy dependency method missing: FrameBudget.mark_progress_pending")
		return false
	if not deps.FrameBudget.has_method("progress_partition_enabled"):
		push_error("Enemy dependency method missing: FrameBudget.progress_partition_enabled")
		return false
	if not deps.FrameBudget.has_method("remaining_progress_usec"):
		push_error("Enemy dependency method missing: FrameBudget.remaining_progress_usec")
		return false
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner_thread


## Shared admission for deferrable decisions, not gameplay/action permission.
## FIFO stores weak identities only; actors retain all route/position/HP state.
const CATEGORY := "monster_decisions"
const MAX_OWNERS_PER_EPOCH := 5
var _epoch = -1
var _queue: Array[int] = []
var _requests: Dictionary = {}
var _serviced: Dictionary = {}
var _turns: Dictionary = {}
var _active_tokens: Dictionary = {}
var _admitted = 0
var _max_wait_frames = 0
var _max_epoch_owners = 0
var _previous_epoch = -1
var _previous_owner_ids: Array = []

# Pursuit process budget: separate from the legacy physics-epoch observation
# ledger above. It admits at most five distinct owners per process epoch while
# retaining the first weak-identity request age.
const PURSUIT_PROCESS_CATEGORY := "monster_pursuit_process"
const PURSUIT_PROCESS_MAX_OWNERS := 5
const PURSUIT_PROCESS_MAINTENANCE_MAX := 8
var _p_process_epoch = -1
var _p_queue: Array = []
var _p_requests: Dictionary = {}
var _p_slots: Dictionary = {}
var _p_serviced: Dictionary = {}
var _p_denied: Dictionary = {}
var _p_active: Dictionary = {}
var _p_borrowed: Dictionary = {}
var _p_next_token = 2000000000
var _p_next_borrowed = -1
var _p_grants = 0
var _p_nested_served = 0
var _p_fifo_denied = 0
var _p_budget_denied = 0
var _p_unrunnable_denied = 0
var _p_frame_fairness_denied = 0
var _p_frame_unrunnable_denied = 0
var _p_max_wait = 0
var _p_queue_peak = 0
var _p_epoch_owner_max = 0
var _p_epoch_reserved_max = 0
var _p_cancelled = 0
var _p_last_denial = ""
var _p_wait_usec_total = 0
var _p_wait_usec_max = 0
var _p_scope_usec_total = 0
var _p_atomic_overrun_usec = 0
var _p_cancel_reasons: Dictionary = {}
var _p_frame_reason_epoch = -1
var _p_frame_denial_reason = ""
var _p_maintenance_epoch = -1
var _p_maintenance_used = 0
var _p_maintenance_skipped = 0
var _p_validated: Dictionary = {}
var _p_trace_enabled = false
var _p_denial_trace: Array[Dictionary] = []
var _d_queue: Array[int] = []
var _d_requests: Dictionary = {}
var _d_next_token = 3000000000
var _d_active_token = 0
var _d_active_consumed = false
var _d_active_completed = false
var _d_batch_epoch = -1
var _d_epoch_served: Dictionary = {}
var _d_dispatches = 0
var _d_dispatch_calls = 0
var _d_dispatch_usec_total = 0
var _d_dispatch_samples: Array[Dictionary] = []
var _d_dispatch_samples_truncated = false
var _d_frame_budget_scopes = 0
var _d_grants = 0
var _d_denied_budget = 0
var _d_denied_fairness = 0
var _d_denied_unrunnable = 0
var _d_cancelled = 0
var _d_post_invalid = 0
var _d_queue_peak = 0
var _d_wait_usec_total = 0
var _d_wait_usec_max = 0
var _d_atomic_overrun_usec = 0
var _d_maintenance_used = 0
var _d_maintenance_skipped = 0
var _d_enabled = false
var _d_process_owner: RefCounted = null

func configure_pursuit_dispatch_enabled(enabled: bool) -> void:
	_d_enabled = enabled
	_p_refresh_pending()

func pursuit_dispatch_enabled() -> bool:
	return _d_enabled

func bind_pursuit_dispatch_process_owner(owner: Object) -> void:
	var previous: Object = actors.resolve(_d_process_owner) as Object if _d_process_owner != null else null
	if previous != owner:
		_d_process_owner = actors.capture(owner) if actors.present(owner) else null
	_p_refresh_pending()

func _dispatch_pending_owner() -> Object:
	var process_owner: Object = actors.resolve(_d_process_owner) as Object if _d_process_owner != null else null
	if actors.present(process_owner) and actors.inside(process_owner):
		return process_owner
	return null

func _dispatch_pending_runnable(owner: Object) -> bool:
	return _d_enabled and actors.present(owner) and actors.inside(owner) and actors.can_process(owner) and actors.process_enabled(owner)

func _d_refresh_pending() -> void:
	_p_refresh_pending()

func _sync_epoch() -> void:
	var current = deps.Engine.get_physics_frames()
	if current != _epoch:
		assert(_active_tokens.is_empty(), "monster decision scope crossed physics epoch")
		_previous_epoch = _epoch
		_previous_owner_ids = _serviced.keys()
		_epoch = current
		_serviced.clear()
		_turns.clear()

func _sync_pursuit_epoch() -> bool:
	var current: int = deps.Engine.get_process_frames()
	if current == _p_process_epoch:
		return true
	assert(_p_active.is_empty() and _p_borrowed.is_empty(), "pursuit process scope crossed process epoch")
	if not _p_active.is_empty() or not _p_borrowed.is_empty():
		return false
	_p_process_epoch = current
	_p_serviced.clear()
	_p_slots.clear()
	_p_denied.clear()
	_p_last_denial = ""
	_p_frame_reason_epoch = -1
	_p_frame_denial_reason = ""
	_p_maintenance_epoch = current
	_p_maintenance_used = 0
	_p_validated.clear()
	_d_batch_epoch = -1
	_d_epoch_served.clear()
	return true

func _p_valid(owner: Object, scope: Array, caller: Object = null) -> bool:
	if not actors.present(owner) or not actors.inside(owner) or actors.queued(owner) or not actors.can_process(owner) or scope.is_empty():
		return false
	if scope.size() >= 8 and (not bool(scope[6]) or not bool(scope[7])):
		return false
	if owner != caller and not actors.physics_enabled(owner):
		return false
	var method: String = "_hc_pursuit_budget_scope" if actors.supports(owner, "_hc_pursuit_budget_scope") else "_hc_decision_scope"
	return actors.supports(owner, method) and actors.invoke(owner, [method]) == scope

func _p_kind_runnable(owner: Object, kind: StringName) -> bool:
	if kind == &"owner_window":
		return actors.supports(owner, "_hc_owner_optional_budget_runnable") and bool(actors.invoke(owner, ["_hc_owner_optional_budget_runnable"]))
	if not actors.supports(owner, "_hc_pursuit_budget_kind_runnable"):
		return true
	return bool(actors.invoke(owner, ["_hc_pursuit_budget_kind_runnable", kind]))

func _p_owner_window_scope_valid(owner: Object, scope: Array, caller: Object = null) -> bool:
	if not actors.present(owner) or not actors.inside(owner) or actors.queued(owner) or not actors.can_process(owner) or scope.size() < 8:
		return false
	if owner != caller and not actors.physics_enabled(owner):
		return false
	return actors.supports(owner, "_hc_owner_optional_budget_scope_valid") and bool(actors.invoke(owner, ["_hc_owner_optional_budget_scope_valid", scope]))

func _p_entry_reason(entry: Dictionary, owner: Object, caller: Object = null) -> String:
	if entry.is_empty():
		return "identity"
	var kinds: Dictionary = entry.get("kinds", {})
	for raw_kind: Variant in kinds:
		var kind = StringName(str(raw_kind))
		var scope_valid = _p_owner_window_scope_valid(owner, entry.scope, caller) if kind == &"owner_window" else _p_valid(owner, entry.scope, caller)
		if scope_valid and _p_kind_runnable(owner, kind):
			return ""
	return "identity" if not _p_owner_window_scope_valid(owner, entry.scope, caller) and kinds.has("owner_window") else "not_serviceable"

func _p_cached_entry_runnable(entry: Dictionary, owner: Object, caller: Object = null) -> bool:
	if entry.is_empty() or not actors.present(owner) or actors.queued(owner) or not actors.inside(owner) or not actors.can_process(owner):
		return false
	if owner != caller and not actors.physics_enabled(owner):
		return false
	var kinds: Dictionary = entry.get("kinds", {})
	for raw_kind: Variant in kinds:
		if _p_kind_runnable(owner, StringName(str(raw_kind))):
			return true
	return false

func _p_remove_entry(id: int, reason: String) -> void:
	_p_requests.erase(id)
	_p_queue.erase(id)
	_p_slots.erase(id)
	_p_validated.erase(id)
	_p_cancelled += 1
	_p_cancel_reasons[reason] = int(_p_cancel_reasons.get(reason, 0)) + 1

func _p_maintenance_take() -> bool:
	if _p_maintenance_epoch != _p_process_epoch:
		_p_maintenance_epoch = _p_process_epoch
		_p_maintenance_used = 0
	if _p_maintenance_used >= PURSUIT_PROCESS_MAINTENANCE_MAX:
		_p_maintenance_skipped += 1
		return false
	_p_maintenance_used += 1
	return true

func _p_capture_frame_denial() -> void:
	_p_frame_reason_epoch = _p_process_epoch
	var record: Dictionary = deps.FrameBudget.last_denial_record(PURSUIT_PROCESS_CATEGORY)
	_p_frame_denial_reason = str(record.get("reason", ""))
	if _p_frame_denial_reason.is_empty():
		_p_frame_denial_reason = "unknown"
	return

func configure_pursuit_process_trace(enabled: bool) -> void:
	_p_trace_enabled = enabled
	_p_denial_trace.clear()

func _p_optional_bool(owner: Object, property_name: String) -> Variant:
	var value: Variant = actors.read(owner, property_name)
	return value if value is bool else "MISSING"

func _p_optional_number(owner: Object, property_name: String) -> Variant:
	var value: Variant = actors.read(owner, property_name)
	return value if value is float or value is int else "MISSING"

func _p_append_denial_trace(owner: Object, kind: StringName, request_key: String) -> void:
	if not _p_trace_enabled:
		return
	var record: Dictionary = deps.FrameBudget.last_denial_record(PURSUIT_PROCESS_CATEGORY)
	var pending: Dictionary = _p_requests.get(actors.runtime_id(owner), {})
	var kinds: Dictionary = pending.get("kinds", {})
	var row: Dictionary = {
		"owner_id": actors.runtime_id(owner),
		"request_key": request_key,
		"kind": str(kind),
		"pending_kinds": kinds.keys(),
		"process_epoch": _p_process_epoch,
		"reason": str(record.get("reason", _p_frame_denial_reason)),
		"blocking_category": str(record.get("blocking_category", "")),
		"remaining_usec": int(record.get("remaining_usec", -1)),
		"own_service_epoch": int(record.get("own_service_epoch", -1)),
		"blocker_service_epoch": int(record.get("blocker_service_epoch", -1)),
	}
	if actors.present(owner):
		var target: Variant = actors.read(owner, "target")
		row["is_physics_processing"] = actors.physics_enabled(owner)
		row["is_processing"] = actors.process_enabled(owner)
		row["owner_state_applicable"] = actors.supports(owner, "_hc_life")
		row["active_leg"] = _p_optional_bool(owner, "_movement_step_active")
		row["attack_active"] = _p_optional_bool(owner, "_attack_action_active")
		row["target_id"] = actors.runtime_id(target) if actors.present(target) else 0
	_p_denial_trace.append(row)
	if _p_denial_trace.size() > 32:
		_p_denial_trace.pop_front()

func enqueue_dispatch(owner: Object, scope: Array, kind: StringName) -> void:
	if not actors.present(owner) or actors.queued(owner):
		return
	var id = actors.runtime_id(owner)
	var was_empty = _d_queue.is_empty()
	if not _d_requests.has(id):
		_d_requests[id] = {"owner": actors.capture(owner), "queued_usec": deps.Time.get_ticks_usec(),
			"queued_epoch": deps.Engine.get_process_frames(), "scope": scope.duplicate(), "kinds": {kind: true}}
		_d_queue.append(id)
		_d_queue_peak = maxi(_d_queue_peak, _d_queue.size())
	if was_empty and not _d_queue.is_empty():
		_p_refresh_pending()
	else:
		var entry: Dictionary = _d_requests[id]
		if not _p_scope_compatible(entry.get("scope", []), scope):
			# A changed target/life/map witness retires the old intent; do not
			# refresh its age under a new identity.
			_d_requests.erase(id)
			_d_queue.erase(id)
			_d_cancelled += 1
			_d_requests[id] = {"owner": actors.capture(owner), "queued_usec": deps.Time.get_ticks_usec(),
				"queued_epoch": deps.Engine.get_process_frames(), "scope": scope.duplicate(), "kinds": {kind: true}}
			_d_queue.append(id)
			_d_queue_peak = maxi(_d_queue_peak, _d_queue.size())
			return
		var kinds: Dictionary = entry.get("kinds", {})
		kinds[kind] = true
		entry["kinds"] = kinds
		_d_requests[id] = entry

func consume_dispatch_pursuit_turn(owner: Object, scope: Array, kind: StringName) -> int:
	if _d_active_token == 0 or _d_active_consumed or not actors.present(owner):
		return 0
	var lease: Dictionary = _p_active.get(_d_active_token, {})
	if lease.is_empty() or not bool(lease.get("dispatch", false)):
		return 0
	if int(lease.get("owner_id", 0)) != actors.runtime_id(owner):
		return 0
	if StringName(str(lease.get("kind", ""))) != kind:
		return 0
	if not scope.is_empty() and not _p_scope_compatible(lease.get("scope", []), scope):
		return 0
	_d_active_consumed = true
	_d_active_completed = false
	_p_next_borrowed -= 1
	_p_borrowed[_p_next_borrowed] = {"dispatch": true, "outer_token": _d_active_token,
		"owner_id": actors.runtime_id(owner), "kind": kind}
	return _p_next_borrowed

func dispatch_pursuit_turn_consumed() -> bool:
	return _d_active_token != 0 and _d_active_consumed

func _d_remove_kind(id: int, kind: StringName, reason: String) -> void:
	if not _d_requests.has(id):
		return
	var entry: Dictionary = _d_requests[id]
	var kinds: Dictionary = entry.get("kinds", {})
	kinds.erase(kind)
	if kinds.is_empty():
		_d_requests.erase(id)
		_d_queue.erase(id)
	else:
		entry["kinds"] = kinds
		_d_requests[id] = entry
	if not reason.is_empty():
		_d_cancelled += 1

func _d_remove_owner(id: int, _reason: String) -> void:
	if not _d_requests.has(id):
		return
	_d_requests.erase(id)
	_d_queue.erase(id)
	_d_cancelled += 1

func _d_record_dispatch_sample(started_usec: int, status: String, grants: int, queue_before: int, process_epoch: int) -> void:
	var elapsed = maxi(0, deps.Time.get_ticks_usec() - started_usec)
	_d_dispatch_calls += 1
	_d_dispatch_usec_total += elapsed
	_d_dispatch_samples.append({
		"process_epoch": process_epoch,
		"elapsed_usec": elapsed,
		"status": status,
		"grants": grants,
		"queue_before": queue_before,
		"queue_after": _d_queue.size(),
		"measurement_boundary": "entry_through_framebudget_end_before_sample_record",
	})
	if _d_dispatch_samples.size() > 2048:
		_d_dispatch_samples.pop_front()
		_d_dispatch_samples_truncated = true

func dispatch_pursuit_process_batch(process_owner: Object = null) -> Dictionary:
	if not _d_enabled:
		return {"status": "DISABLED", "grants": 0, "queue_length": _d_queue.size()}
	var batch_started_usec = deps.Time.get_ticks_usec()
	if actors.present(process_owner) and actors.inside(process_owner):
		var bound_owner: Object = actors.resolve(_d_process_owner) as Object if _d_process_owner != null else null
		if bound_owner != process_owner:
			_d_process_owner = actors.capture(process_owner)
	var batch_process_epoch = deps.Engine.get_process_frames()
	var queue_before = _d_queue.size()
	if not _sync_pursuit_epoch():
		_d_record_dispatch_sample(batch_started_usec, "EPOCH_BLOCKED", 0, queue_before, batch_process_epoch)
		return {"status": "EPOCH_BLOCKED", "grants": 0, "queue_length": _d_queue.size()}
	if _d_batch_epoch == batch_process_epoch:
		_d_record_dispatch_sample(batch_started_usec, "ALREADY_DISPATCHED", 0, queue_before, batch_process_epoch)
		return {"status": "ALREADY_DISPATCHED", "grants": 0, "queue_length": _d_queue.size()}
	if _d_queue.is_empty():
		_d_refresh_pending()
		_d_record_dispatch_sample(batch_started_usec, "IDLE", 0, queue_before, batch_process_epoch)
		return {"status": "IDLE", "grants": 0, "queue_length": _d_queue.size()}
	_d_batch_epoch = batch_process_epoch
	_d_epoch_served.clear()
	_d_dispatches += 1
	_d_refresh_pending()
	var frame_token = deps.FrameBudget.begin_progress(PURSUIT_PROCESS_CATEGORY)
	if frame_token == 0:
		var denial = deps.FrameBudget.last_denial_record(PURSUIT_PROCESS_CATEGORY)
		var denial_reason = str(denial.get("reason", "budget"))
		if denial_reason.to_lower().contains("fair"):
			_d_denied_fairness += 1
		elif denial_reason.to_lower().contains("unrunnable"):
			_d_denied_unrunnable += 1
		else:
			_d_denied_budget += 1
		_d_record_dispatch_sample(batch_started_usec, "FRAME_DENIED", 0, queue_before, batch_process_epoch)
		return {"status": "FRAME_DENIED", "grants": 0, "queue_length": _d_queue.size()}
	_d_frame_budget_scopes += 1
	var frame_scope_started_usec = deps.Time.get_ticks_usec()
	var frame_remaining_before = deps.FrameBudget.remaining_progress_usec()
	var grants = 0
	var considered = 0
	var visits = 0
	while considered < PURSUIT_PROCESS_MAX_OWNERS and visits < PURSUIT_PROCESS_MAINTENANCE_MAX and not _d_queue.is_empty():
		visits += 1
		if deps.FrameBudget.remaining_progress_usec() <= 0:
			break
		var id: int = int(_d_queue[0])
		var entry: Dictionary = _d_requests.get(id, {})
		if entry.is_empty():
			if not _p_maintenance_take():
				break
			_d_queue.pop_front()
			_d_cancelled += 1
			continue
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		if _d_epoch_served.has(id):
			_d_queue.push_back(_d_queue.pop_front())
			continue
		if not _p_maintenance_take():
			break
		var kinds: Dictionary = entry.get("kinds", {})
		var kind = StringName("observation") if kinds.has("observation") else (
			StringName(str(kinds.keys()[0])) if not kinds.is_empty() else StringName()
		)
		if not actors.present(owner) or actors.queued(owner) or not actors.inside(owner) or not actors.can_process(owner) or not actors.physics_enabled(owner):
			_d_remove_kind(id, kind, "identity")
			continue
		if not actors.supports(owner, "_hc_dispatch_pursuit_process"):
			_d_remove_kind(id, kind, "unsupported")
			continue
		var fresh_scope: Array = actors.invoke(owner, ["_hc_pursuit_budget_scope"]) if actors.supports(owner, "_hc_pursuit_budget_scope") else []
		if fresh_scope.is_empty() or not _p_scope_compatible(entry.get("scope", []), fresh_scope):
			_d_remove_owner(id, "identity")
			continue
		if not _p_kind_runnable(owner, kind):
			_d_remove_kind(id, kind, "not_serviceable")
			continue
		var queued_usec = int(entry.get("queued_usec", deps.Time.get_ticks_usec()))
		var wait_usec = maxi(0, deps.Time.get_ticks_usec() - queued_usec)
		_d_wait_usec_total += wait_usec
		_d_wait_usec_max = maxi(_d_wait_usec_max, wait_usec)
		_d_next_token += 1
		_d_active_token = _d_next_token
		_d_active_consumed = false
		_d_active_completed = false
		_p_active[_d_active_token] = {"dispatch": true, "owner_id": id, "kind": kind,
			"scope": fresh_scope, "started_usec": deps.Time.get_ticks_usec(), "remaining_before_usec": deps.FrameBudget.remaining_progress_usec()}
		var callback_result: bool = bool(actors.invoke(owner, ["_hc_dispatch_pursuit_process", kind]))
		var consumed = _d_active_consumed
		var completed = _d_active_completed
		assert(_p_borrowed.is_empty(), "dispatch callback leaked a borrowed pursuit handle")
		var post_valid = actors.present(owner) and not actors.queued(owner) and actors.supports(owner, "_hc_pursuit_budget_scope") and _p_scope_compatible(fresh_scope, actors.invoke(owner, ["_hc_pursuit_budget_scope"]))
		if not post_valid:
			_d_post_invalid += 1
			if completed:
				_d_requests.erase(id)
				_d_queue.erase(id)
				_d_cancelled += 1
				_d_epoch_served[id] = true
			else:
				# Identity is stale even when the callback never consumed its
				# admission; retire every kind for this owner rather than leaving
				# an unserviceable head in the FIFO.
				_d_remove_owner(id, "identity")
		if _p_active.has(_d_active_token):
			_p_active.erase(_d_active_token)
		_d_active_token = 0
		_d_active_consumed = false
		_d_active_completed = false
		if not post_valid:
			if consumed and completed:
				grants += 1
				_d_grants += 1
				_p_grants += 1
			break
		if consumed and completed:
			_d_remove_kind(id, kind, "")
			_d_epoch_served[id] = true
			grants += 1
			_d_grants += 1
			_p_grants += 1
		else:
			# The owner became ineligible between the cheap gate and callback.
			# Keep its original age for the next process opportunity.
			if not callback_result and actors.present(owner) and not actors.queued(owner) and not _p_kind_runnable(owner, kind):
				_d_remove_kind(id, kind, "not_serviceable")
			break
		considered += 1
	_d_atomic_overrun_usec += maxi(0, deps.Time.get_ticks_usec() - frame_scope_started_usec - frame_remaining_before)
	deps.FrameBudget.end(frame_token)
	_d_refresh_pending()
	_d_record_dispatch_sample(batch_started_usec, "SERVICED", grants, queue_before, batch_process_epoch)
	return {"status": "SERVICED", "grants": grants, "queue_length": _d_queue.size(),
		"maintenance_used": _p_maintenance_used, "maintenance_skipped": _p_maintenance_skipped}

func _p_scope_compatible(lease_scope: Array, requested_scope: Array) -> bool:
	# A process lease carries the full owner/target witness. Legacy observation
	# calls carry its six-field prefix; they may borrow while that prefix is
	# unchanged, without opening a second FrameBudget scope.
	if lease_scope.size() < requested_scope.size():
		return false
	for index in requested_scope.size():
		if lease_scope[index] != requested_scope[index]:
			return false
	return true

func _p_prune_front(caller: Object = null) -> void:
	while not _p_queue.is_empty():
		var id: int = int(_p_queue[0])
		var entry: Dictionary = _p_requests.get(id, {})
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		var cached: bool = _p_validated.has(id)
		if cached and _p_cached_entry_runnable(entry, owner, caller):
			break
		if not cached and not _p_maintenance_take():
			break
		var reason: String = "not_serviceable" if cached else _p_entry_reason(entry, owner, caller)
		if reason.is_empty():
			_p_validated[id] = true
			break
		_p_remove_entry(id, reason)
	_p_refresh_pending()

func _p_owner_count() -> int:
	var ids: Dictionary = {}
	for raw_id: Variant in _p_slots:
		ids[int(raw_id)] = true
	for raw_id: Variant in _p_serviced:
		ids[int(raw_id)] = true
	return ids.size()

func _p_fill_slots(caller: Object = null) -> void:
	var cursor: int = 0
	while cursor < _p_queue.size() and _p_owner_count() < PURSUIT_PROCESS_MAX_OWNERS:
		var id: int = int(_p_queue[cursor])
		var entry: Dictionary = _p_requests.get(id, {})
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		var cached: bool = _p_validated.has(id)
		if cached and _p_cached_entry_runnable(entry, owner, caller):
			_p_slots[id] = true
			_p_epoch_reserved_max = maxi(_p_epoch_reserved_max, _p_owner_count())
			cursor += 1
			continue
		if not cached and not _p_maintenance_take():
			break
		var reason: String = "not_serviceable" if cached else _p_entry_reason(entry, owner, caller)
		if not reason.is_empty():
			_p_remove_entry(id, reason)
			continue
		_p_validated[id] = true
		_p_slots[id] = true
		_p_epoch_reserved_max = maxi(_p_epoch_reserved_max, _p_owner_count())
		cursor += 1

func _p_refresh_pending() -> void:
	var owner: Object = null
	var runnable = false
	if not _p_queue.is_empty():
		var entry: Dictionary = _p_requests.get(_p_queue[0], {})
		owner = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		var background_service: bool = actors.present(owner) and actors.read(owner, "_background_maintenance_running") == true
		runnable = actors.present(owner) and actors.inside(owner) and actors.can_process(owner) and (
			actors.physics_enabled(owner) or background_service
		)
	elif not _d_queue.is_empty():
		owner = _dispatch_pending_owner()
		runnable = _dispatch_pending_runnable(owner)
	var background_owner: bool = actors.present(owner) and actors.read(owner, "_background_maintenance_running") == true
	var physics_owner: bool = not _p_queue.is_empty() and not background_owner
	deps.FrameBudget.mark_progress_pending(PURSUIT_PROCESS_CATEGORY, not _p_queue.is_empty() or not _d_queue.is_empty(), runnable, false, owner, physics_owner)

func begin_pursuit_turn(owner: Object, scope: Array, kind: StringName) -> int:
	if not _sync_pursuit_epoch():
		return 0
	if pursuit_turn_active(owner):
		# A second process outer scope is never admitted. Nested callers must use
		# borrow_pursuit_turn, which has a separate legacy-kind ledger.
		_p_last_denial = "ACTIVE"
		return 0
	var id: int = actors.runtime_id(owner)
	var request_key: String = "%d:%s" % [id, str(kind)]
	# A cold owner can become unrunnable after its request was queued (target
	# deletion, sleep transition, or scope identity change) without another
	# owner touching the FIFO. Prune that head before this caller is classified;
	# otherwise FrameBudget keeps reporting the stale head as the blocker for
	# several seconds while every later owner is fairly denied behind it.
	_p_prune_front(owner)
	if not _p_kind_runnable(owner, kind):
		_p_last_denial = "UNRUNNABLE"
		_p_unrunnable_denied += 1
		return 0
	var serviced_kinds: Dictionary = _p_serviced.get(id, {})
	if serviced_kinds.has(kind) or _p_denied.has(request_key):
		_p_last_denial = "FIFO"
		_p_fifo_denied += 1
		return 0
	if not _p_requests.has(id):
		_p_requests[id] = {"owner": actors.capture(owner), "scope": scope.duplicate(), "queued_epoch": _p_process_epoch,
			"queued_usec": deps.Time.get_ticks_usec(), "kinds": {kind: true}}
		_p_queue.append(id)
		_p_queue_peak = maxi(_p_queue_peak, _p_queue.size())
	else:
		# Stable repeated requests keep the already-validated witness and age.
		# Revalidation is required only when the actual scope changed.
		if _p_requests[id].scope != scope:
			_p_requests[id].scope = scope.duplicate()
			_p_validated.erase(id)
		var pending_kinds: Dictionary = _p_requests[id].get("kinds", {})
		pending_kinds[kind] = true
		_p_requests[id].kinds = pending_kinds
	_p_prune_front(owner)
	_p_fill_slots(owner)
	_p_refresh_pending()
	if not _p_slots.has(id):
		if not _p_kind_runnable(owner, kind):
			_p_denied[request_key] = true
			_p_last_denial = "UNRUNNABLE"
			_p_unrunnable_denied += 1
			return 0
		_p_denied[request_key] = true
		_p_last_denial = "FIFO"
		_p_fifo_denied += 1
		return 0
	# Reservations bound the number of distinct owners, but do not grant a
	# newer callback permission to overtake the oldest pending request. The
	# category may get only one pre-idle turn while other real work is due.
	# A reserved oldest-ready batch may run in actual node callback order.
	# Requiring only its head stranded the other four after their callbacks.
	# Legacy single-lane component tests retain the original ordering contract.
	if not deps.FrameBudget.progress_partition_enabled() and (_p_queue.is_empty() or int(_p_queue[0]) != id):
		_p_denied[request_key] = true
		_p_last_denial = "FIFO"
		_p_fifo_denied += 1
		return 0
	var remaining_before: int = deps.FrameBudget.remaining_progress_usec()
	var frame_token: int = deps.FrameBudget.begin_progress(PURSUIT_PROCESS_CATEGORY)
	if frame_token == 0:
		_p_capture_frame_denial()
		_p_append_denial_trace(owner, kind, request_key)
		_p_slots.erase(id)
		_p_denied[request_key] = true
		_p_last_denial = "FRAME_%s" % _p_frame_denial_reason
		if _p_frame_denial_reason == "fairness":
			_p_frame_fairness_denied += 1
		elif _p_frame_denial_reason == "unrunnable":
			_p_frame_unrunnable_denied += 1
		else:
			_p_budget_denied += 1
		_p_refresh_pending()
		return 0
	var queued_epoch: int = int(_p_requests[id].queued_epoch)
	var queued_usec: int = int(_p_requests[id].get("queued_usec", deps.Time.get_ticks_usec()))
	var pending_kinds: Dictionary = _p_requests[id].get("kinds", {})
	_p_slots.erase(id)
	var requested_kinds: Dictionary = _p_serviced.get(id, {})
	requested_kinds[kind] = true
	_p_serviced[id] = requested_kinds
	pending_kinds.erase(kind)
	if pending_kinds.is_empty():
		_p_queue.erase(id)
		_p_requests.erase(id)
	else:
		_p_requests[id].kinds = pending_kinds
	_p_refresh_pending()
	_p_max_wait = maxi(_p_max_wait, _p_process_epoch - queued_epoch)
	var wait_usec: int = maxi(0, deps.Time.get_ticks_usec() - queued_usec)
	_p_wait_usec_total += wait_usec
	_p_wait_usec_max = maxi(_p_wait_usec_max, wait_usec)
	_p_next_token += 1
	_p_active[_p_next_token] = {"frame_token": frame_token, "owner_id": id, "kind": kind,
		"kinds": {kind: true}, "borrowed_kinds": {},
		"scope": scope.duplicate(), "started_usec": deps.Time.get_ticks_usec(), "remaining_before_usec": remaining_before}
	_p_grants += 1
	_p_epoch_owner_max = maxi(_p_epoch_owner_max, _p_serviced.size())
	return _p_next_token

func pursuit_turn_kind(owner: Object, kind: StringName) -> int:
	return borrow_pursuit_turn(owner, [], kind)

func borrow_pursuit_turn(owner: Object, scope: Array, kind: StringName) -> int:
	var id: int = actors.runtime_id(owner)
	for token: int in _p_active:
		var lease: Dictionary = _p_active[token]
		if int(lease.owner_id) != id:
			continue
		if not scope.is_empty() and not _p_scope_compatible(lease.scope, scope):
			_p_last_denial = "IDENTITY"
			return 0
		var borrowed_kinds: Dictionary = lease.get("borrowed_kinds", {})
		if borrowed_kinds.has(kind):
			_p_last_denial = "BORROWED_KIND"
			return 0
		var process_kind: StringName = kind
		var consumes_process_kind = false
		if str(kind).begins_with("nested_process_"):
			process_kind = StringName(str(kind).trim_prefix("nested_process_"))
			var request: Dictionary = _p_requests.get(id, {})
			var pending: Dictionary = request.get("kinds", {})
			if not request.is_empty() and pending.has(process_kind):
				pending.erase(process_kind)
				consumes_process_kind = true
				if pending.is_empty():
					_p_requests.erase(id)
					_p_queue.erase(id)
				else:
					request.kinds = pending
					_p_requests[id] = request
				_p_refresh_pending()
		borrowed_kinds[kind] = true
		lease.borrowed_kinds = borrowed_kinds
		_p_active[token] = lease
		_p_next_borrowed -= 1
		_p_borrowed[_p_next_borrowed] = {"owner_id": id, "kind": kind,
			"process_kind": process_kind if consumes_process_kind else StringName(),
			"consumes_process_kind": consumes_process_kind}
		return _p_next_borrowed
	return 0

func suspend_pursuit_turn(token: int) -> bool:
	if not _p_active.has(token):
		return false
	var lease: Dictionary = _p_active[token]
	if bool(lease.get("dispatch", false)) or int(lease.get("frame_token", 0)) == 0:
		return true
	var elapsed: int = maxi(0, deps.Time.get_ticks_usec() - int(lease.get("started_usec", 0)))
	_p_scope_usec_total += elapsed
	_p_atomic_overrun_usec += maxi(0, elapsed - int(lease.get("remaining_before_usec", 0)))
	deps.FrameBudget.end(int(lease.frame_token))
	lease.frame_token = 0
	lease.started_usec = 0
	lease.suspended = true
	_p_active[token] = lease
	return true

func resume_pursuit_turn(token: int) -> bool:
	if not _p_active.has(token):
		return false
	var lease: Dictionary = _p_active[token]
	if bool(lease.get("dispatch", false)) or int(lease.get("frame_token", 0)) != 0:
		return true
	var frame_token: int = deps.FrameBudget.begin_progress(PURSUIT_PROCESS_CATEGORY)
	if frame_token == 0:
		_p_capture_frame_denial()
		_p_last_denial = "FRAME_%s" % _p_frame_denial_reason
		return false
	lease.frame_token = frame_token
	lease.started_usec = deps.Time.get_ticks_usec()
	lease.remaining_before_usec = deps.FrameBudget.remaining_progress_usec()
	lease.suspended = false
	_p_active[token] = lease
	return true

func end_pursuit_turn(token: int) -> void:
	if _p_borrowed.has(token):
		assert(token == _p_next_borrowed, "pursuit borrowed handles must close LIFO")
		if token != _p_next_borrowed:
			return
		var borrowed: Dictionary = _p_borrowed[token]
		_p_borrowed.erase(token)
		if bool(borrowed.get("dispatch", false)):
			_d_active_completed = true
			_p_next_borrowed += 1
			return
		_p_next_borrowed += 1
		if bool(borrowed.get("consumes_process_kind", false)):
			var owner_id: int = int(borrowed.get("owner_id", 0))
			var process_kind: StringName = borrowed.get("process_kind", StringName())
			var serviced: Dictionary = _p_serviced.get(owner_id, {})
			serviced[process_kind] = true
			_p_serviced[owner_id] = serviced
			_p_nested_served += 1
		return
	if not _p_active.has(token):
		return
	var lease: Dictionary = _p_active[token]
	if bool(lease.get("dispatch", false)):
		# The batch owns this outer lease. Enemy may close only its borrowed
		# callback handle; the dispatcher erases the lease after the callback.
		return
	_p_active.erase(token)
	var frame_token: int = int(lease.get("frame_token", 0))
	if frame_token != 0:
		var elapsed: int = maxi(0, deps.Time.get_ticks_usec() - int(lease.get("started_usec", 0)))
		_p_scope_usec_total += elapsed
		_p_atomic_overrun_usec += maxi(0, elapsed - int(lease.get("remaining_before_usec", 0)))
		deps.FrameBudget.end(frame_token)

func pursuit_turn_active(owner: Object) -> bool:
	var id: int = actors.runtime_id(owner)
	for token: int in _p_active:
		if int(_p_active[token].owner_id) == id:
			return true
	return false

func reset_pursuit_process_diagnostics() -> void:
	_p_grants = 0
	_p_nested_served = 0
	_p_fifo_denied = 0
	_p_budget_denied = 0
	_p_unrunnable_denied = 0
	_p_frame_fairness_denied = 0
	_p_frame_unrunnable_denied = 0
	_p_max_wait = 0
	_p_queue_peak = 0
	_p_epoch_owner_max = 0
	_p_epoch_reserved_max = 0
	_p_cancelled = 0
	_p_wait_usec_total = 0
	_p_wait_usec_max = 0
	_p_scope_usec_total = 0
	_p_atomic_overrun_usec = 0
	_p_last_denial = ""
	_p_frame_reason_epoch = -1
	_p_frame_denial_reason = ""
	_p_maintenance_skipped = 0
	_p_cancel_reasons = {}
	_d_dispatches = 0
	_d_dispatch_calls = 0
	_d_dispatch_usec_total = 0
	_d_dispatch_samples.clear()
	_d_dispatch_samples_truncated = false
	_d_frame_budget_scopes = 0
	_d_grants = 0
	_d_denied_budget = 0
	_d_denied_fairness = 0
	_d_denied_unrunnable = 0
	_d_cancelled = 0
	_d_post_invalid = 0
	_d_queue_peak = _d_queue.size()
	_d_wait_usec_total = 0
	_d_wait_usec_max = 0
	_d_atomic_overrun_usec = 0

func reset_pursuit_process_state() -> void:
	assert(_p_active.is_empty() and _p_borrowed.is_empty(), "cannot reset pursuit state with open scopes")
	_p_process_epoch = -1
	_p_queue.clear()
	_p_requests.clear()
	_p_slots.clear()
	_p_validated.clear()
	_p_serviced.clear()
	_p_denied.clear()
	_d_queue.clear()
	_d_requests.clear()
	_d_active_token = 0
	_d_active_consumed = false
	_d_active_completed = false
	_d_batch_epoch = -1
	_d_epoch_served.clear()
	_p_refresh_pending()

func pursuit_process_snapshot() -> Dictionary:
	_sync_pursuit_epoch()
	var queue_rows: Array[Dictionary] = []
	for id: int in _p_queue:
		var entry: Dictionary = _p_requests.get(id, {})
		var queued_usec: int = int(entry.get("queued_usec", deps.Time.get_ticks_usec()))
		var pending_kinds: Dictionary = entry.get("kinds", {})
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		var state: Dictionary = {}
		if actors.present(owner):
			var target: Variant = actors.read(owner, "target")
			var pending_attack: Variant = _p_optional_number(owner, "_pending_attack_time")
			var target_life: Variant = "MISSING"
			if actors.present(target) and actors.supports(owner, "_hc_life"):
				var raw_life: Variant = actors.invoke(owner, ["_hc_life", target])
				if raw_life is float or raw_life is int:
					target_life = raw_life
			state = {"is_physics_processing": actors.physics_enabled(owner),
				"is_processing": actors.process_enabled(owner),
				"owner_state_applicable": actors.supports(owner, "_hc_life"),
				"active_leg": _p_optional_bool(owner, "_movement_step_active"),
				"attack_active": _p_optional_bool(owner, "_attack_action_active"),
				"pending_attack": pending_attack if pending_attack is String else float(pending_attack) >= 0.0,
				"target_id": actors.runtime_id(target) if actors.present(target) else 0,
				"target_life": target_life,
				"clock_due_ms": _p_optional_number(owner, "_hc_next_observation_ms"),
				"owner_clock_s": _p_optional_number(owner, "_combat_action_time_s"),
				"owner_due_s": _p_optional_number(owner, "_owner_decision_next_time_s"),
				"retarget_remaining_s": _p_optional_number(owner, "_retarget_timer"),
				"passive_wake_pending": _p_optional_bool(owner, "_passive_wake_pending"),
				"background_sleeping": _p_optional_bool(owner, "_background_deep_sleeping"),
				"background_callback": _p_optional_bool(owner, "_background_maintenance_running"),
				"observed": _p_optional_bool(owner, "_hc_observed"),
				"owner_window_runnable": bool(actors.invoke(owner, ["_hc_owner_optional_budget_runnable"])) if actors.supports(owner, "_hc_owner_optional_budget_runnable") else "MISSING"}
		queue_rows.append({"owner_id": id, "queued_process_epoch": int(entry.get("queued_epoch", _p_process_epoch)),
			"wait_processes": _p_process_epoch - int(entry.get("queued_epoch", _p_process_epoch)),
			"wait_usec": maxi(0, deps.Time.get_ticks_usec() - queued_usec),
			"pending_kinds": pending_kinds.keys(), "state": state})
	var dispatch_rows: Array[Dictionary] = []
	var dispatch_max_wait_usec = 0
	var now_usec = deps.Time.get_ticks_usec()
	for id: int in _d_queue:
		var entry: Dictionary = _d_requests.get(id, {})
		if entry.is_empty():
			continue
		var wait_usec = maxi(0, now_usec - int(entry.get("queued_usec", now_usec)))
		dispatch_max_wait_usec = maxi(dispatch_max_wait_usec, wait_usec)
		if dispatch_rows.size() < 32:
			dispatch_rows.append({"owner_id": id, "queued_process_epoch": int(entry.get("queued_epoch", _p_process_epoch)),
				"wait_usec": wait_usec, "pending_kinds": entry.get("kinds", {}).keys()})
	return {"process_epoch": _p_process_epoch, "queue_length": _p_queue.size(),
		"queue": queue_rows, "grants": _p_grants, "fifo_denied": _p_fifo_denied,
		"budget_denied": _p_budget_denied, "frame_fairness_denied": _p_frame_fairness_denied,
		"frame_unrunnable_denied": _p_frame_unrunnable_denied,
		"nested_served": _p_nested_served, "last_denial": _p_last_denial,
		"frame_denial_reason": _p_frame_denial_reason,
		"unrunnable_denied": _p_unrunnable_denied,
		"maintenance_used": _p_maintenance_used,
		"maintenance_skipped": _p_maintenance_skipped,
		"trace_enabled": _p_trace_enabled,
		"denial_trace": _p_denial_trace.duplicate(true) if _p_trace_enabled else [],
		"max_wait_processes": _p_max_wait, "queue_peak": _p_queue_peak,
		"epoch_owner_max": _p_epoch_owner_max, "cancelled": _p_cancelled,
		"reserved_owner_max": _p_epoch_reserved_max,
		"cancel_reasons": _p_cancel_reasons.duplicate(),
		"wait_usec_total": _p_wait_usec_total, "wait_usec_max": _p_wait_usec_max,
		"scope_usec_total": _p_scope_usec_total,
		"atomic_quantum_overrun_usec": _p_atomic_overrun_usec,
		"open_turns": _p_active.size(), "open_borrowed": _p_borrowed.size(),
		"dispatch_queue_length": _d_queue.size(), "dispatch_queue_peak": _d_queue_peak,
		"dispatch_queue_rows": dispatch_rows, "dispatch_queue_max_wait_usec": dispatch_max_wait_usec,
		"dispatches": _d_dispatches, "dispatch_calls": _d_dispatch_calls,
		"dispatch_usec_total": _d_dispatch_usec_total,
		"dispatch_samples": _d_dispatch_samples.duplicate(true),
		"dispatch_samples_truncated": _d_dispatch_samples_truncated,
		"dispatch_frame_budget_scopes": _d_frame_budget_scopes,
		"dispatch_grants": _d_grants,
		"dispatch_denied_budget": _d_denied_budget, "dispatch_cancelled": _d_cancelled,
		"dispatch_denied_fairness": _d_denied_fairness, "dispatch_denied_unrunnable": _d_denied_unrunnable,
		"dispatch_post_invalid": _d_post_invalid,
		"dispatch_wait_usec_total": _d_wait_usec_total, "dispatch_wait_usec_max": _d_wait_usec_max,
		"dispatch_atomic_overrun_usec": _d_atomic_overrun_usec,
		"dispatch_maintenance_used": _p_maintenance_used,
		"dispatch_maintenance_skipped": _p_maintenance_skipped}

func pursuit_process_last_denial() -> String:
	return _p_last_denial

func _valid(owner: Object, scope: Array, caller: Object = null) -> bool:
	if not actors.present(owner) or not actors.inside(owner) or actors.queued(owner) or not actors.can_process(owner) or scope.is_empty():
		return false
	# Explicit synchronous fixture calls may drive a disabled actor; another
	# disabled actor must not reserve an otherwise unserviceable FIFO turn.
	if owner != caller and not actors.physics_enabled(owner):
		return false
	return actors.supports(owner, "_hc_decision_scope") and actors.invoke(owner, ["_hc_decision_scope"]) == scope

func _prune_front(caller: Object = null) -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _requests.get(_queue[0], {})
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		if not entry.is_empty() and _valid(owner, entry.scope, caller):
			break
		_requests.erase(_queue.pop_front())

func _refresh_pending() -> void:
	var owner: Object = null
	if not _queue.is_empty():
		owner = actors.resolve(_requests[_queue[0]].owner) as Object
	deps.FrameBudget.mark_pending(CATEGORY, not _queue.is_empty(), true, false, owner, true)

func _fill_turns(caller: Object = null) -> void:
	# Reserve only the oldest valid small batch. A dead/disabled/stale request
	# in the middle must not consume one of the five turns; stop once the
	# bounded batch is full instead of scanning the whole backlog every call.
	var cursor = 0
	while cursor < _queue.size() and _turns.size() < MAX_OWNERS_PER_EPOCH:
		var id = _queue[cursor]
		var entry: Dictionary = _requests.get(id, {})
		var owner: Object = actors.resolve(entry.owner) as Object if not entry.is_empty() else null
		var validation_caller: Object = caller if owner == caller and caller != null else null
		if entry.is_empty() or not _valid(owner, entry.scope, validation_caller):
			_requests.erase(id)
			_queue.remove_at(cursor)
			continue
		_turns[id] = true
		cursor += 1

func has_pending(owner_id: int) -> bool:
	return _requests.has(owner_id)

func has_dispatch_pending(owner_id: int) -> bool:
	return _d_requests.has(owner_id)

func begin(owner: Object, scope: Array, kind: StringName = &"observation") -> int:
	if owner != null and pursuit_turn_active(owner):
		return borrow_pursuit_turn(owner, scope, StringName("legacy_%s" % str(kind)))
	_sync_epoch()
	if kind not in [&"poll", &"observation", &"neighbor"] or not _valid(owner, scope, owner):
		return 0
	var id = actors.runtime_id(owner)
	if _serviced.has(id):
		# A quantum may poll, observe and choose one blocked neighbor once
		# each. A changed identity or repeat choice waits for the next epoch.
		if _serviced[id].scope != scope:
			if not _requests.has(id):
				_queue.append(id)
				_requests[id] = {"owner": actors.capture(owner), "scope": scope.duplicate(), "queued_epoch": _epoch}
			else:
				_requests[id].scope = scope.duplicate()
			_refresh_pending()
			return 0
		if _serviced[id].kinds.has(kind):
			return 0
	if not _serviced.has(id):
		if _requests.has(id):
			# Replacement changes identity scope, not original FIFO age/order.
			_requests[id].scope = scope.duplicate()
		else:
			_requests[id] = {"owner": actors.capture(owner), "scope": scope.duplicate(), "queued_epoch": _epoch}
			_queue.append(id)
		_prune_front(owner)
		_fill_turns(owner)
		_refresh_pending()
		if not _turns.has(id) or _serviced.size() >= MAX_OWNERS_PER_EPOCH:
			return 0
	# The oldest five turns are the bounded service obligation for this
	# physics epoch. Charge them through the shared budget, including an
	# overrun, instead of making basic pursuit compete with optional prefetch.
	# Observation and its resulting blocked-step choice finish as one owner's
	# quantum; a second budget denial here otherwise starves the route itself.
	var token = deps.FrameBudget.begin(CATEGORY, true)
	if token == 0:
		return 0
	if not _serviced.has(id):
		var entry: Dictionary = _requests[id]
		_max_wait_frames = maxi(_max_wait_frames, _epoch - int(entry.queued_epoch))
		_queue.erase(id)
		_requests.erase(id)
		_serviced[id] = {"scope": scope.duplicate(), "kinds": {}}
		_max_epoch_owners = maxi(_max_epoch_owners, _serviced.size())
		_refresh_pending()
	_serviced[id].kinds[kind] = true
	_active_tokens[token] = {"owner_id": id, "scope": scope.duplicate(), "kind": kind}
	_admitted += 1
	return token

func end(token: int) -> void:
	if _p_borrowed.has(token):
		end_pursuit_turn(token)
		return
	assert(_active_tokens.has(token), "unknown monster decision token")
	_active_tokens.erase(token)
	deps.FrameBudget.end(token)

func cancel(owner_id: int) -> void:
	var had_pending = _p_requests.has(owner_id) or _p_slots.has(owner_id)
	var had_dispatch_pending = _d_requests.has(owner_id)
	_requests.erase(owner_id)
	_queue.erase(owner_id)
	if not _serviced.has(owner_id):
		_turns.erase(owner_id)
	# Spent admission is never refunded within this epoch.
	_prune_front()
	_refresh_pending()
	_p_requests.erase(owner_id)
	_p_queue.erase(owner_id)
	_p_slots.erase(owner_id)
	if had_pending:
		_p_cancelled += 1
	_p_refresh_pending()
	if had_dispatch_pending:
		_d_requests.erase(owner_id)
		_d_queue.erase(owner_id)
		_d_cancelled += 1
		_p_refresh_pending()

func snapshot() -> Dictionary:
	_sync_epoch()
	_prune_front()
	_refresh_pending()
	var rows: Array[Dictionary] = []
	for id: int in _queue:
		var entry: Dictionary = _requests[id]
		rows.append({"owner_id": id, "queued_epoch": entry.queued_epoch, "wait_frames": _epoch - int(entry.queued_epoch), "scope": entry.scope.duplicate()})
	return {"epoch": _epoch, "queue_length": _queue.size(), "queue": rows,
		"serviced_owner_ids": _serviced.keys(), "previous_epoch": _previous_epoch, "previous_owner_ids": _previous_owner_ids.duplicate(),
		"actual_admitted_count": _admitted, "max_wait_frames": _max_wait_frames,
		"epoch_owner_count": _serviced.size(), "max_epoch_owner_count": _max_epoch_owners,
		"open_scopes": _active_tokens.size()}
