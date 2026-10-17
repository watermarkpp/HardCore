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
	deps = {"Engine": bindings.get("Engine"), "Time": bindings.get("Time"), "ProjectSettings": bindings.get("ProjectSettings"), "phase": bindings.get("phase")}
	if not deps.get("Engine") is Object or deps.Engine is Node or deps.Engine is Resource or not deps.Engine.has_method("owner_thread_id") or deps.Engine.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: Engine")
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
	if not deps.get("ProjectSettings") is Object or deps.ProjectSettings is Node or deps.ProjectSettings is Resource or not deps.ProjectSettings.has_method("owner_thread_id") or deps.ProjectSettings.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: ProjectSettings")
		return false
	if not deps.ProjectSettings.has_method("get_setting"):
		push_error("Enemy dependency method missing: ProjectSettings.get_setting")
		return false
	if not deps.get("phase") is Object or deps.phase is Node or deps.phase is Resource or not deps.phase.has_method("owner_thread_id") or deps.phase.owner_thread_id() != _owner_thread:
		push_error("Enemy service dependency missing/wrong owner: phase")
		return false
	if not deps.phase.has_method("tree_is_paused"):
		push_error("Enemy dependency method missing: phase.tree_is_paused")
		return false
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner_thread


## Main-thread accounting for deferrable work in one actual main-loop epoch.
## A scope is synchronous: callers must close it before returning or awaiting.
## Necessary work is always admitted and charged, including an overrun.
const DEFAULT_BUDGET_USEC := 1200 # Existing path/death cap; P0 must measure admission latency.
# Gameplay progress is not residual background capacity. Both lanes retain
# bounded admission; necessary work is always charged to the full ledger.
const DEFAULT_PROGRESS_BUDGET_USEC := 6000
const LANE_BACKGROUND := 0
const LANE_PROGRESS := 1
const LANE_NECESSARY := 2
var _partitioned = true
var _progress_limit_usec = DEFAULT_PROGRESS_BUDGET_USEC
var _lane_spent: Array[int] = [0, 0, 0]
var _limit_usec = DEFAULT_BUDGET_USEC
var _epoch = -1
var _spent_usec = 0
var _next_token = 0
var _stack: Array[Dictionary] = []
var _categories: Dictionary = {}
var _pending: Dictionary = {}
var _pending_sequence = 0
var _service_sequence = 0
var _epoch_provider = Callable()
var _clock_provider = Callable()

func _current_epoch() -> int:
	return int(_epoch_provider.call()) if _epoch_provider.is_valid() else deps.Engine.get_process_frames()

func _now_usec() -> int:
	return int(_clock_provider.call()) if _clock_provider.is_valid() else deps.Time.get_ticks_usec()

func _sync_epoch() -> bool:
	var current = _current_epoch()
	if current == _epoch:
		return true
	if not _stack.is_empty():
		assert(false, "frame-budget scope crossed an outer iteration; close before await")
		return false
	if _epoch < 0 and not _epoch_provider.is_valid():
		_limit_usec = maxi(1, int(deps.ProjectSettings.get_setting(
			"hardcore/performance/frame_optional_budget_usec", DEFAULT_BUDGET_USEC)))
		_progress_limit_usec = maxi(1, int(deps.ProjectSettings.get_setting(
			"hardcore/performance/frame_progress_budget_usec", DEFAULT_PROGRESS_BUDGET_USEC)))
	_epoch = current
	_spent_usec = 0
	_lane_spent = [0, 0, 0]
	_categories.clear()
	return true

func remaining_usec() -> int:
	if not _sync_epoch():
		return 0
	if _partitioned:
		return maxi(0, _limit_usec - _lane_spent[LANE_BACKGROUND] - _lane_inflight_usec(LANE_BACKGROUND))
	var inflight = 0 if _stack.is_empty() else maxi(0, _now_usec() - int(_stack[0].started_usec))
	return maxi(0, _limit_usec - _spent_usec - inflight)

func progress_partition_enabled() -> bool:
	return _partitioned

func remaining_progress_usec() -> int:
	if not _partitioned:
		return remaining_usec()
	if not _sync_epoch():
		return 0
	return maxi(0, _progress_limit_usec - _lane_spent[LANE_PROGRESS] - _lane_inflight_usec(LANE_PROGRESS))

func _lane_inflight_usec(lane: int) -> int:
	# Closed children are in lane_spent already. Remove both closed and live
	# children from each parent's wall time so cross-lane nesting is exact.
	var now = _now_usec()
	var total = 0
	for index: int in _stack.size():
		var item: Dictionary = _stack[index]
		if int(item.lane) != lane:
			continue
		var live_child = maxi(0, now - int(_stack[index + 1].started_usec)) if index + 1 < _stack.size() else 0
		total += maxi(0, now - int(item.started_usec) - int(item.child_usec) - live_child)
	return total

func mark_progress_pending(category: String, has_pending: bool, runnable := true, runs_when_paused := false, process_owner: Object = null, physics_owner := false) -> void:
	mark_pending(category, has_pending, runnable, runs_when_paused, process_owner, physics_owner)
	if _pending.has(category):
		_pending[category]["progress"] = true

func begin_progress(category: String) -> int:
	if not _partitioned:
		return begin(category)
	if _pending.has(category):
		_pending[category]["progress"] = true
	return _begin(category, false, LANE_PROGRESS)

func _category(name: String) -> Dictionary:
	if not _categories.has(name):
		_categories[name] = {"inclusive_usec": 0, "self_usec": 0, "maximum_quantum_usec": 0,
			"scopes": 0, "denied": 0, "necessary_scopes": 0,
			"denied_budget": 0, "denied_fairness": 0, "denied_unrunnable": 0, "last_denial": {}}
	return _categories[name]

func mark_pending(category: String, has_pending: bool, runnable := true, runs_when_paused := false, process_owner: Object = null, physics_owner := false) -> void:
	if not _sync_epoch():
		return
	if not has_pending:
		_pending.erase(category)
	elif not _pending.has(category):
		_pending_sequence += 1
		_pending[category] = {"pending_epoch": _epoch, "last_service_epoch": _epoch - 1,
			"sequence": _pending_sequence, "last_service_sequence": 0}
	if _pending.has(category):
		_pending[category]["runnable"] = runnable
		_pending[category]["runs_when_paused"] = runs_when_paused
		if process_owner != null:
			_pending[category]["process_owner"] = actors.capture(process_owner)
			_pending[category]["physics_owner"] = physics_owner
	# Repeated submissions/replacements preserve continuous service age.

func _eligible(item: Dictionary, is_calling_owner := false) -> bool:
	if not bool(item.get("runnable", true)):
		return false
	if deps.phase.tree_is_paused() and not bool(item.get("runs_when_paused", false)):
		return false
	# Explicit synchronous calls may drive a deliberately disabled fixture or
	# lifecycle owner. Other owners cannot reserve a turn while their actual
	# Node processing is disabled; no heartbeat or timer guesses its state.
	if not is_calling_owner and item.has("process_owner"):
		var owner: Object = actors.resolve(item.process_owner) as Object
		if not actors.present(owner) or actors.queued(owner) or not actors.inside(owner):
			return false
		if not actors.can_process(owner):
			return false # Includes inherited DISABLED ancestors, not just callback flags.
		if bool(item.get("physics_owner", false)):
			return actors.physics_enabled(owner)
		return actors.process_enabled(owner)
	return true

func _fair_blocker(category: String, lane := LANE_BACKGROUND) -> Variant:
	if not _pending.has(category) or not _stack.is_empty():
		return null
	return _fair_blocker_policy(category, lane, false)

func _fair_blocker_policy(category: String, lane: int, after_current_quantum: bool) -> Variant:
	# The existing admission policy and the read-only continuation query share
	# this body. Normal nested begin() keeps its original bypass above.
	if not _pending.has(category):
		return null
	var own: Dictionary = _pending[category]
	if not _eligible(own, true):
		return category
	var own_service_epoch: int = _epoch if after_current_quantum else int(own.last_service_epoch)
	var own_service_sequence: int = _service_sequence + 1 if after_current_quantum else int(own.last_service_sequence)
	for other: String in _pending:
		if other == category:
			continue
		var item: Dictionary = _pending[other]
		if _partitioned and bool(item.get("progress", false)) != (lane == LANE_PROGRESS):
			continue
		if not _eligible(item):
			continue
		# Every unserved runnable owner retains its oldest-first turn. Once
		# all eligible owners have been served in this actual epoch, a caller
		# may consume unused allowance without requiring another callback from
		# an owner whose callback opportunity already passed. Next epoch the
		# preserved service order again puts older owners before a prolific one.
		if int(item.last_service_epoch) == _epoch:
			continue
		if int(item.last_service_epoch) < own_service_epoch:
			return other
		if int(item.last_service_epoch) == own_service_epoch:
			if int(item.last_service_sequence) < own_service_sequence or (
				int(item.last_service_sequence) == own_service_sequence
				and int(item.sequence) < int(own.sequence)):
				return other
	return null

func _continuation_context_ready() -> bool:
	return _configured

func capture_continuation_scope() -> Dictionary:
	# Never sync/reset an epoch or admit a new scope while inspecting identity.
	# This API is deliberately limited to the existing outer polling scope.
	if OS.get_thread_caller_id() != _owner_thread or not _continuation_context_ready():
		return {}
	if _stack.size() != 1 or _epoch < 0 or _current_epoch() != _epoch:
		return {}
	var scope: Dictionary = _stack[0]
	var identity := {"contract_id":"hardcore.budget.scope_continuation.v1",
		"ledger_id":get_instance_id(), "owner_thread":_owner_thread, "epoch":_epoch,
		"token":int(scope.token), "category":str(scope.category), "lane":int(scope.lane),
		"necessary":bool(scope.necessary), "depth":1}
	identity.make_read_only()
	return identity

func continuation_scope_decision(identity: Dictionary) -> Dictionary:
	var current := capture_continuation_scope()
	if current.is_empty() or identity != current:
		return {"allowed":false, "reason":"scope", "blocking_category":""}
	if bool(current.necessary):
		return {"allowed":true, "reason":"", "blocking_category":""}
	# Dynamic dispatch is intentional: SourceSessionBudget subtracts its real
	# outstanding LIVE reservations from these SAME remaining-allowance methods.
	var lane := int(current.lane)
	var remaining: int = remaining_progress_usec() if lane == LANE_PROGRESS else remaining_usec()
	if remaining <= 0:
		return {"allowed":false, "reason":"budget", "blocking_category":"", "remaining_usec":remaining}
	var blocker: Variant = _fair_blocker_policy(str(current.category), lane, true)
	if blocker != null:
		return {"allowed":false, "reason":"unrunnable" if blocker == current.category else "fairness",
			"blocking_category":str(blocker), "remaining_usec":remaining}
	return {"allowed":true, "reason":"", "blocking_category":"", "remaining_usec":remaining}

func begin(category: String, necessary := false) -> int:
	return _begin(category, necessary, LANE_NECESSARY if necessary else LANE_BACKGROUND)

func _begin(category: String, necessary: bool, lane: int) -> int:
	assert(OS.get_thread_caller_id() == _owner_thread, "frame budget belongs to its S owner")
	if not _sync_epoch():
		return 0
	var counters = _category(category)
	if not necessary:
		var remaining = remaining_progress_usec() if lane == LANE_PROGRESS else remaining_usec()
		var blocker: Variant = null if remaining <= 0 else _fair_blocker(category, lane)
		if remaining <= 0 or blocker != null:
			var reason = "budget" if remaining <= 0 else ("unrunnable" if blocker == category else "fairness")
			counters.denied += 1
			counters["denied_" + reason] += 1
			# One scalar record per category/epoch; never a per-quantum log.
			counters.last_denial = {"reason": reason, "blocking_category": "" if blocker == null else str(blocker),
				"epoch": _epoch, "remaining_usec": remaining, "spent_usec": _spent_usec,
				"inflight_usec": 0 if _stack.is_empty() else maxi(0, _now_usec() - int(_stack[0].started_usec)),
				"own_service_epoch": _pending.get(category, {}).get("last_service_epoch", -1),
				"own_service_sequence": _pending.get(category, {}).get("last_service_sequence", -1),
				"blocker_service_epoch": _pending.get(blocker, {}).get("last_service_epoch", -1),
				"blocker_service_sequence": _pending.get(blocker, {}).get("last_service_sequence", -1)}
			return 0
	_next_token += 1
	_stack.append({"token": _next_token, "category": category, "started_usec": _now_usec(),
		"child_usec": 0, "necessary": necessary, "lane": lane})
	return _next_token

func last_denial_reason(category: String) -> String:
	if not _sync_epoch():
		return "unknown"
	var counters: Dictionary = _categories.get(category, {})
	var last: Dictionary = counters.get("last_denial", {})
	return str(last.get("reason", "")) if not last.is_empty() else ""

func last_denial_record(category: String) -> Dictionary:
	if not _sync_epoch():
		return {}
	var counters: Dictionary = _categories.get(category, {})
	var last: Dictionary = counters.get("last_denial", {})
	return last.duplicate() if not last.is_empty() else {}

func end(token: int) -> void:
	assert(_current_epoch() == _epoch, "frame-budget scope crossed an outer iteration")
	if _current_epoch() != _epoch:
		return
	assert(not _stack.is_empty() and int(_stack[-1].token) == token,
		"frame-budget scopes must close in LIFO order")
	if _stack.is_empty() or int(_stack[-1].token) != token:
		return
	var scope: Dictionary = _stack.pop_back()
	var elapsed = maxi(0, _now_usec() - int(scope.started_usec))
	var counters = _category(str(scope.category))
	_lane_spent[int(scope.lane)] += maxi(0, elapsed - int(scope.child_usec))
	counters.inclusive_usec += elapsed
	counters.self_usec += maxi(0, elapsed - int(scope.child_usec))
	counters.maximum_quantum_usec = maxi(int(counters.maximum_quantum_usec), elapsed)
	counters.scopes += 1
	if bool(scope.necessary):
		counters.necessary_scopes += 1
	if _stack.is_empty():
		_spent_usec += elapsed
		if _pending.has(scope.category):
			_service_sequence += 1
			_pending[scope.category].last_service_epoch = _epoch
			_pending[scope.category].last_service_sequence = _service_sequence
	else:
		_stack[-1].child_usec += elapsed

func deadline_usec(local_cap_usec: int) -> int:
	return _now_usec() + mini(maxi(0, local_cap_usec), remaining_usec())

func snapshot() -> Dictionary:
	_sync_epoch()
	var pending = {}
	for category: String in _pending:
		var item: Dictionary = _pending[category]
		pending[category] = {"pending_epoch": item.pending_epoch,
			"oldest_age_frames": maxi(0, _epoch - int(item.pending_epoch)),
			"service_age_frames": maxi(0, _epoch - int(item.last_service_epoch)),
			"runnable": _eligible(item), "runs_when_paused": item.get("runs_when_paused", false)}
	var inflight = 0 if _stack.is_empty() else maxi(0, _now_usec() - int(_stack[0].started_usec))
	return {"epoch": _epoch, "limit_usec": _limit_usec, "spent_usec": _spent_usec + inflight,
		"inflight_usec": inflight, "overrun_usec": maxi(0, _spent_usec + inflight - _limit_usec - (_progress_limit_usec if _partitioned else 0)),
		"partitioned": _partitioned, "progress_limit_usec": _progress_limit_usec,
		"background_spent_usec": _lane_spent[LANE_BACKGROUND] + _lane_inflight_usec(LANE_BACKGROUND),
		"necessary_spent_usec": _lane_spent[LANE_NECESSARY] + _lane_inflight_usec(LANE_NECESSARY),
		"progress_spent_usec": _lane_spent[LANE_PROGRESS] + _lane_inflight_usec(LANE_PROGRESS),
		"progress_overrun_usec": maxi(0, _lane_spent[LANE_PROGRESS] + _lane_inflight_usec(LANE_PROGRESS) - _progress_limit_usec),
		"categories": _categories.duplicate(true), "pending": pending, "open_scopes": _stack.size()}

func configure_for_tests(limit_usec: int, epoch_provider: Callable, clock_provider: Callable) -> void:
	assert(_stack.is_empty())
	# Existing component tests explicitly model the original one-lane policy.
	# New policy tests opt into partitioning through configure_progress_for_tests.
	_partitioned = false
	_progress_limit_usec = maxi(0, limit_usec)
	_lane_spent = [0, 0, 0]
	_limit_usec = maxi(0, limit_usec)
	_epoch_provider = epoch_provider
	_clock_provider = clock_provider
	_epoch = -1
	_spent_usec = 0
	_categories.clear()
	_pending.clear()
	_pending_sequence = 0
	_service_sequence = 0

func configure_progress_for_tests(limit_usec: int) -> void:
	assert(_stack.is_empty())
	_partitioned = true
	_progress_limit_usec = maxi(0, limit_usec)

func reset_test_configuration() -> void:
	assert(_stack.is_empty())
	_partitioned = true
	_lane_spent = [0, 0, 0]
	_progress_limit_usec = maxi(1, int(deps.ProjectSettings.get_setting(
		"hardcore/performance/frame_progress_budget_usec", DEFAULT_PROGRESS_BUDGET_USEC)))
	_epoch_provider = Callable()
	_clock_provider = Callable()
	_limit_usec = maxi(1, int(deps.ProjectSettings.get_setting(
		"hardcore/performance/frame_optional_budget_usec", DEFAULT_BUDGET_USEC)))
	_epoch = -1
	_spent_usec = 0
	_categories.clear()
	_pending.clear()
	_pending_sequence = 0
	_service_sequence = 0
