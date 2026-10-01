extends RefCounted

## Main-thread accounting for deferrable work in one actual main-loop epoch.
## A scope is synchronous: callers must close it before returning or awaiting.
## Necessary work is always admitted and charged, including an overrun.
const DEFAULT_BUDGET_USEC := 1200 # Existing path/death cap; P0 must measure admission latency.
static var _limit_usec := DEFAULT_BUDGET_USEC
static var _epoch := -1
static var _spent_usec := 0
static var _next_token := 0
static var _stack: Array[Dictionary] = []
static var _categories: Dictionary = {}
static var _pending: Dictionary = {}
static var _pending_sequence := 0
static var _service_sequence := 0
static var _epoch_provider := Callable()
static var _clock_provider := Callable()

static func _current_epoch() -> int:
	return int(_epoch_provider.call()) if _epoch_provider.is_valid() else Engine.get_process_frames()

static func _now_usec() -> int:
	return int(_clock_provider.call()) if _clock_provider.is_valid() else Time.get_ticks_usec()

static func _sync_epoch() -> bool:
	var current := _current_epoch()
	if current == _epoch:
		return true
	if not _stack.is_empty():
		assert(false, "frame-budget scope crossed an outer iteration; close before await")
		return false
	if _epoch < 0 and not _epoch_provider.is_valid():
		_limit_usec = maxi(1, int(ProjectSettings.get_setting(
			"hardcore/performance/frame_optional_budget_usec", DEFAULT_BUDGET_USEC)))
	_epoch = current
	_spent_usec = 0
	_categories.clear()
	return true

static func remaining_usec() -> int:
	if not _sync_epoch():
		return 0
	var inflight := 0 if _stack.is_empty() else maxi(0, _now_usec() - int(_stack[0].started_usec))
	return maxi(0, _limit_usec - _spent_usec - inflight)

static func _category(name: String) -> Dictionary:
	if not _categories.has(name):
		_categories[name] = {"inclusive_usec": 0, "self_usec": 0, "maximum_quantum_usec": 0,
			"scopes": 0, "denied": 0, "necessary_scopes": 0}
	return _categories[name]

static func mark_pending(category: String, has_pending: bool, runnable := true, runs_when_paused := false, process_owner: Node = null, physics_owner := false) -> void:
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
			_pending[category]["process_owner"] = weakref(process_owner)
			_pending[category]["physics_owner"] = physics_owner
	# Repeated submissions/replacements preserve continuous service age.

static func _eligible(item: Dictionary, is_calling_owner := false) -> bool:
	if not bool(item.get("runnable", true)):
		return false
	var tree := Engine.get_main_loop() as SceneTree
	if tree != null and tree.paused and not bool(item.get("runs_when_paused", false)):
		return false
	# Explicit synchronous calls may drive a deliberately disabled fixture or
	# lifecycle owner. Other owners cannot reserve a turn while their actual
	# Node processing is disabled; no heartbeat or timer guesses its state.
	if not is_calling_owner and item.has("process_owner"):
		var owner: Node = item.process_owner.get_ref() as Node
		if not is_instance_valid(owner) or owner.is_queued_for_deletion() or not owner.is_inside_tree():
			return false
		if not owner.can_process():
			return false # Includes inherited DISABLED ancestors, not just callback flags.
		if bool(item.get("physics_owner", false)):
			return owner.is_physics_processing()
		return owner.is_processing()
	return true

static func _fair_turn(category: String) -> bool:
	if not _pending.has(category) or not _stack.is_empty():
		return true
	var own: Dictionary = _pending[category]
	if not _eligible(own, true):
		return false
	for other: String in _pending:
		if other == category:
			continue
		var item: Dictionary = _pending[other]
		if not _eligible(item):
			continue
		if int(item.last_service_epoch) < int(own.last_service_epoch):
			return false
		if int(item.last_service_epoch) == int(own.last_service_epoch):
			if int(item.last_service_sequence) < int(own.last_service_sequence) or (
				int(item.last_service_sequence) == int(own.last_service_sequence)
				and int(item.sequence) < int(own.sequence)):
				return false
	return true

static func begin(category: String, necessary := false) -> int:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id(), "frame budget belongs to main")
	if not _sync_epoch():
		return 0
	var counters := _category(category)
	if not necessary and (remaining_usec() <= 0 or not _fair_turn(category)):
		counters.denied += 1
		return 0
	_next_token += 1
	_stack.append({"token": _next_token, "category": category, "started_usec": _now_usec(),
		"child_usec": 0, "necessary": necessary})
	return _next_token

static func end(token: int) -> void:
	assert(_current_epoch() == _epoch, "frame-budget scope crossed an outer iteration")
	if _current_epoch() != _epoch:
		return
	assert(not _stack.is_empty() and int(_stack[-1].token) == token,
		"frame-budget scopes must close in LIFO order")
	if _stack.is_empty() or int(_stack[-1].token) != token:
		return
	var scope: Dictionary = _stack.pop_back()
	var elapsed := maxi(0, _now_usec() - int(scope.started_usec))
	var counters := _category(str(scope.category))
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

static func deadline_usec(local_cap_usec: int) -> int:
	return _now_usec() + mini(maxi(0, local_cap_usec), remaining_usec())

static func snapshot() -> Dictionary:
	_sync_epoch()
	var pending := {}
	for category: String in _pending:
		var item: Dictionary = _pending[category]
		pending[category] = {"pending_epoch": item.pending_epoch,
			"oldest_age_frames": maxi(0, _epoch - int(item.pending_epoch)),
			"service_age_frames": maxi(0, _epoch - int(item.last_service_epoch)),
			"runnable": _eligible(item), "runs_when_paused": item.get("runs_when_paused", false)}
	var inflight := 0 if _stack.is_empty() else maxi(0, _now_usec() - int(_stack[0].started_usec))
	return {"epoch": _epoch, "limit_usec": _limit_usec, "spent_usec": _spent_usec + inflight,
		"inflight_usec": inflight, "overrun_usec": maxi(0, _spent_usec + inflight - _limit_usec),
		"categories": _categories.duplicate(true), "pending": pending, "open_scopes": _stack.size()}

static func configure_for_tests(limit_usec: int, epoch_provider: Callable, clock_provider: Callable) -> void:
	assert(_stack.is_empty())
	_limit_usec = maxi(0, limit_usec)
	_epoch_provider = epoch_provider
	_clock_provider = clock_provider
	_epoch = -1
	_spent_usec = 0
	_categories.clear()
	_pending.clear()
	_pending_sequence = 0
	_service_sequence = 0

static func reset_test_configuration() -> void:
	assert(_stack.is_empty())
	_epoch_provider = Callable()
	_clock_provider = Callable()
	_limit_usec = maxi(1, int(ProjectSettings.get_setting(
		"hardcore/performance/frame_optional_budget_usec", DEFAULT_BUDGET_USEC)))
	_epoch = -1
	_spent_usec = 0
	_categories.clear()
	_pending.clear()
	_pending_sequence = 0
	_service_sequence = 0
