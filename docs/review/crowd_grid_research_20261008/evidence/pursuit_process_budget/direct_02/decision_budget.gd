extends RefCounted

## Shared admission for deferrable decisions, not gameplay/action permission.
## FIFO stores weak identities only; actors retain all route/position/HP state.
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const CATEGORY := "monster_decisions"
const MAX_OWNERS_PER_EPOCH := 5
static var _epoch := -1
static var _queue: Array[int] = []
static var _requests: Dictionary = {}
static var _serviced: Dictionary = {}
static var _turns: Dictionary = {}
static var _active_tokens: Dictionary = {}
static var _admitted := 0
static var _max_wait_frames := 0
static var _max_epoch_owners := 0
static var _previous_epoch := -1
static var _previous_owner_ids: Array = []

# Pursuit process budget: separate from the legacy physics-epoch observation
# ledger above. It admits at most five distinct owners per process epoch while
# retaining the first weak-identity request age.
const PURSUIT_PROCESS_CATEGORY := "monster_pursuit_process"
const PURSUIT_PROCESS_MAX_OWNERS := 5
static var _p_process_epoch := -1
static var _p_queue: Array = []
static var _p_requests: Dictionary = {}
static var _p_slots: Dictionary = {}
static var _p_serviced: Dictionary = {}
static var _p_denied: Dictionary = {}
static var _p_active: Dictionary = {}
static var _p_borrowed: Dictionary = {}
static var _p_next_token := 2000000000
static var _p_next_borrowed := -1
static var _p_grants := 0
static var _p_fifo_denied := 0
static var _p_budget_denied := 0
static var _p_max_wait := 0
static var _p_queue_peak := 0
static var _p_epoch_owner_max := 0
static var _p_epoch_reserved_max := 0
static var _p_cancelled := 0
static var _p_last_denial := ""
static var _p_wait_usec_total := 0
static var _p_wait_usec_max := 0
static var _p_scope_usec_total := 0
static var _p_atomic_overrun_usec := 0

static func _sync_epoch() -> void:
	var current := Engine.get_physics_frames()
	if current != _epoch:
		assert(_active_tokens.is_empty(), "monster decision scope crossed physics epoch")
		_previous_epoch = _epoch
		_previous_owner_ids = _serviced.keys()
		_epoch = current
		_serviced.clear()
		_turns.clear()

static func _sync_pursuit_epoch() -> bool:
	var current: int = Engine.get_process_frames()
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
	return true

static func _p_valid(owner: Node, scope: Array, caller: Node = null) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion() or not owner.can_process() or scope.is_empty():
		return false
	if scope.size() >= 8 and (not bool(scope[6]) or not bool(scope[7])):
		return false
	if owner != caller and not owner.is_physics_processing():
		return false
	var method: String = "_hc_pursuit_budget_scope" if owner.has_method("_hc_pursuit_budget_scope") else "_hc_decision_scope"
	return owner.has_method(method) and owner.call(method) == scope

static func _p_scope_compatible(lease_scope: Array, requested_scope: Array) -> bool:
	# A process lease carries the full owner/target witness. Legacy observation
	# calls carry its six-field prefix; they may borrow while that prefix is
	# unchanged, without opening a second FrameBudget scope.
	if lease_scope.size() < requested_scope.size():
		return false
	for index in requested_scope.size():
		if lease_scope[index] != requested_scope[index]:
			return false
	return true

static func _p_prune_front(caller: Node = null) -> void:
	while not _p_queue.is_empty():
		var id: int = int(_p_queue[0])
		var entry: Dictionary = _p_requests.get(id, {})
		var owner: Node = entry.owner.get_ref() as Node if not entry.is_empty() else null
		if not entry.is_empty() and _p_valid(owner, entry.scope, caller):
			break
		_p_requests.erase(id)
		_p_queue.pop_front()
		_p_slots.erase(id)
		_p_cancelled += 1
	_p_refresh_pending()

static func _p_owner_count() -> int:
	var ids: Dictionary = {}
	for raw_id: Variant in _p_slots:
		ids[int(raw_id)] = true
	for raw_id: Variant in _p_serviced:
		ids[int(raw_id)] = true
	return ids.size()

static func _p_fill_slots(caller: Node = null) -> void:
	var cursor: int = 0
	while cursor < _p_queue.size() and _p_owner_count() < PURSUIT_PROCESS_MAX_OWNERS:
		var id: int = int(_p_queue[cursor])
		var entry: Dictionary = _p_requests.get(id, {})
		var owner: Node = entry.owner.get_ref() as Node if not entry.is_empty() else null
		if entry.is_empty() or not _p_valid(owner, entry.scope, caller):
			_p_requests.erase(id)
			_p_queue.remove_at(cursor)
			_p_slots.erase(id)
			_p_cancelled += 1
			continue
		_p_slots[id] = true
		_p_epoch_reserved_max = maxi(_p_epoch_reserved_max, _p_owner_count())
		cursor += 1

static func _p_refresh_pending() -> void:
	var owner: Node = null
	if not _p_queue.is_empty():
		var entry: Dictionary = _p_requests.get(_p_queue[0], {})
		owner = entry.owner.get_ref() as Node if not entry.is_empty() else null
	FrameBudget.mark_pending(PURSUIT_PROCESS_CATEGORY, not _p_queue.is_empty(), true, false, owner, true)

static func begin_pursuit_turn(owner: Node, scope: Array, kind: StringName) -> int:
	if not _sync_pursuit_epoch():
		return 0
	if pursuit_turn_active(owner):
		# A second process outer scope is never admitted. Nested callers must use
		# borrow_pursuit_turn, which has a separate legacy-kind ledger.
		_p_last_denial = "ACTIVE"
		return 0
	var id: int = owner.get_instance_id()
	var request_key: String = "%d:%s" % [id, str(kind)]
	var serviced_kinds: Dictionary = _p_serviced.get(id, {})
	if serviced_kinds.has(kind) or _p_denied.has(request_key):
		_p_last_denial = "FIFO"
		_p_fifo_denied += 1
		return 0
	if not _p_requests.has(id):
		_p_requests[id] = {"owner": weakref(owner), "scope": scope.duplicate(), "queued_epoch": _p_process_epoch,
			"queued_usec": Time.get_ticks_usec(), "kinds": {kind: true}}
		_p_queue.append(id)
		_p_queue_peak = maxi(_p_queue_peak, _p_queue.size())
	else:
		_p_requests[id].scope = scope.duplicate()
		var pending_kinds: Dictionary = _p_requests[id].get("kinds", {})
		pending_kinds[kind] = true
		_p_requests[id].kinds = pending_kinds
	_p_prune_front(owner)
	_p_fill_slots(owner)
	_p_refresh_pending()
	if not _p_slots.has(id):
		_p_denied[request_key] = true
		_p_last_denial = "FIFO"
		_p_fifo_denied += 1
		return 0
	var remaining_before: int = FrameBudget.remaining_usec()
	var frame_token: int = FrameBudget.begin(PURSUIT_PROCESS_CATEGORY, false)
	if frame_token == 0:
		_p_slots.erase(id)
		_p_denied[request_key] = true
		_p_last_denial = "BUDGET"
		_p_budget_denied += 1
		_p_refresh_pending()
		return 0
	var queued_epoch: int = int(_p_requests[id].queued_epoch)
	var queued_usec: int = int(_p_requests[id].get("queued_usec", Time.get_ticks_usec()))
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
	var wait_usec: int = maxi(0, Time.get_ticks_usec() - queued_usec)
	_p_wait_usec_total += wait_usec
	_p_wait_usec_max = maxi(_p_wait_usec_max, wait_usec)
	_p_next_token += 1
	_p_active[_p_next_token] = {"frame_token": frame_token, "owner_id": id, "kind": kind,
		"kinds": {kind: true}, "borrowed_kinds": {},
		"scope": scope.duplicate(), "started_usec": Time.get_ticks_usec(), "remaining_before_usec": remaining_before}
	_p_grants += 1
	_p_epoch_owner_max = maxi(_p_epoch_owner_max, _p_serviced.size())
	return _p_next_token

static func pursuit_turn_kind(owner: Node, kind: StringName) -> int:
	return borrow_pursuit_turn(owner, [], kind)

static func borrow_pursuit_turn(owner: Node, scope: Array, kind: StringName) -> int:
	var id: int = owner.get_instance_id()
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
		borrowed_kinds[kind] = true
		lease.borrowed_kinds = borrowed_kinds
		_p_active[token] = lease
		_p_next_borrowed -= 1
		_p_borrowed[_p_next_borrowed] = {"owner_id": id, "kind": kind}
		return _p_next_borrowed
	return 0

static func end_pursuit_turn(token: int) -> void:
	if _p_borrowed.has(token):
		_p_borrowed.erase(token)
		return
	if not _p_active.has(token):
		return
	var lease: Dictionary = _p_active[token]
	_p_active.erase(token)
	var elapsed: int = maxi(0, Time.get_ticks_usec() - int(lease.get("started_usec", 0)))
	_p_scope_usec_total += elapsed
	_p_atomic_overrun_usec += maxi(0, elapsed - int(lease.get("remaining_before_usec", 0)))
	FrameBudget.end(int(lease.frame_token))

static func pursuit_turn_active(owner: Node) -> bool:
	var id: int = owner.get_instance_id()
	for token: int in _p_active:
		if int(_p_active[token].owner_id) == id:
			return true
	return false

static func reset_pursuit_process_diagnostics() -> void:
	_p_grants = 0
	_p_fifo_denied = 0
	_p_budget_denied = 0
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

static func reset_pursuit_process_state() -> void:
	assert(_p_active.is_empty() and _p_borrowed.is_empty(), "cannot reset pursuit state with open scopes")
	_p_process_epoch = -1
	_p_queue.clear()
	_p_requests.clear()
	_p_slots.clear()
	_p_serviced.clear()
	_p_denied.clear()
	_p_refresh_pending()

static func pursuit_process_snapshot() -> Dictionary:
	_sync_pursuit_epoch()
	var queue_rows: Array[Dictionary] = []
	for id: int in _p_queue:
		var entry: Dictionary = _p_requests.get(id, {})
		var queued_usec: int = int(entry.get("queued_usec", Time.get_ticks_usec()))
		var pending_kinds: Dictionary = entry.get("kinds", {})
		queue_rows.append({"owner_id": id, "queued_process_epoch": int(entry.get("queued_epoch", _p_process_epoch)),
			"wait_processes": _p_process_epoch - int(entry.get("queued_epoch", _p_process_epoch)),
			"wait_usec": maxi(0, Time.get_ticks_usec() - queued_usec),
			"pending_kinds": pending_kinds.keys()})
	return {"process_epoch": _p_process_epoch, "queue_length": _p_queue.size(),
		"queue": queue_rows, "grants": _p_grants, "fifo_denied": _p_fifo_denied,
		"budget_denied": _p_budget_denied, "last_denial": _p_last_denial,
		"max_wait_processes": _p_max_wait, "queue_peak": _p_queue_peak,
		"epoch_owner_max": _p_epoch_owner_max, "cancelled": _p_cancelled,
		"reserved_owner_max": _p_epoch_reserved_max,
		"wait_usec_total": _p_wait_usec_total, "wait_usec_max": _p_wait_usec_max,
		"scope_usec_total": _p_scope_usec_total,
		"atomic_quantum_overrun_usec": _p_atomic_overrun_usec,
		"open_turns": _p_active.size(), "open_borrowed": _p_borrowed.size()}

static func pursuit_process_last_denial() -> String:
	return _p_last_denial

static func _valid(owner: Node, scope: Array, caller: Node = null) -> bool:
	if not is_instance_valid(owner) or not owner.is_inside_tree() or owner.is_queued_for_deletion() or not owner.can_process() or scope.is_empty():
		return false
	# Explicit synchronous fixture calls may drive a disabled actor; another
	# disabled actor must not reserve an otherwise unserviceable FIFO turn.
	if owner != caller and not owner.is_physics_processing():
		return false
	return owner.has_method("_hc_decision_scope") and owner.call("_hc_decision_scope") == scope

static func _prune_front(caller: Node = null) -> void:
	while not _queue.is_empty():
		var entry: Dictionary = _requests.get(_queue[0], {})
		var owner: Node = entry.owner.get_ref() as Node if not entry.is_empty() else null
		if not entry.is_empty() and _valid(owner, entry.scope, caller):
			break
		_requests.erase(_queue.pop_front())

static func _refresh_pending() -> void:
	var owner: Node = null
	if not _queue.is_empty():
		owner = _requests[_queue[0]].owner.get_ref() as Node
	FrameBudget.mark_pending(CATEGORY, not _queue.is_empty(), true, false, owner, true)

static func _fill_turns(caller: Node = null) -> void:
	# Reserve only the oldest valid small batch. A dead/disabled/stale request
	# in the middle must not consume one of the five turns; stop once the
	# bounded batch is full instead of scanning the whole backlog every call.
	var cursor := 0
	while cursor < _queue.size() and _turns.size() < MAX_OWNERS_PER_EPOCH:
		var id := _queue[cursor]
		var entry: Dictionary = _requests.get(id, {})
		var owner: Node = entry.owner.get_ref() as Node if not entry.is_empty() else null
		var validation_caller: Node = caller if owner == caller and caller != null else null
		if entry.is_empty() or not _valid(owner, entry.scope, validation_caller):
			_requests.erase(id)
			_queue.remove_at(cursor)
			continue
		_turns[id] = true
		cursor += 1

static func has_pending(owner_id: int) -> bool:
	return _requests.has(owner_id)

static func begin(owner: Node, scope: Array, kind: StringName = &"observation") -> int:
	if owner != null and pursuit_turn_active(owner):
		return borrow_pursuit_turn(owner, scope, StringName("legacy_%s" % str(kind)))
	_sync_epoch()
	if kind not in [&"poll", &"observation", &"neighbor"] or not _valid(owner, scope, owner):
		return 0
	var id := owner.get_instance_id()
	if _serviced.has(id):
		# A quantum may poll, observe and choose one blocked neighbor once
		# each. A changed identity or repeat choice waits for the next epoch.
		if _serviced[id].scope != scope:
			if not _requests.has(id):
				_queue.append(id)
				_requests[id] = {"owner": weakref(owner), "scope": scope.duplicate(), "queued_epoch": _epoch}
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
			_requests[id] = {"owner": weakref(owner), "scope": scope.duplicate(), "queued_epoch": _epoch}
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
	var token := FrameBudget.begin(CATEGORY, true)
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

static func end(token: int) -> void:
	if _p_borrowed.has(token):
		_p_borrowed.erase(token)
		return
	assert(_active_tokens.has(token), "unknown monster decision token")
	_active_tokens.erase(token)
	FrameBudget.end(token)

static func cancel(owner_id: int) -> void:
	var had_pending := _p_requests.has(owner_id) or _p_slots.has(owner_id)
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

static func snapshot() -> Dictionary:
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
