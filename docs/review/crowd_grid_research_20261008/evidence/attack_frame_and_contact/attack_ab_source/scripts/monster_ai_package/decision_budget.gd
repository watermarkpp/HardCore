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

static func _sync_epoch() -> void:
	var current := Engine.get_physics_frames()
	if current != _epoch:
		assert(_active_tokens.is_empty(), "monster decision scope crossed physics epoch")
		_previous_epoch = _epoch
		_previous_owner_ids = _serviced.keys()
		_epoch = current
		_serviced.clear()
		_turns.clear()

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
	assert(_active_tokens.has(token), "unknown monster decision token")
	_active_tokens.erase(token)
	FrameBudget.end(token)

static func cancel(owner_id: int) -> void:
	_requests.erase(owner_id)
	_queue.erase(owner_id)
	if not _serviced.has(owner_id):
		_turns.erase(owner_id)
	# Spent admission is never refunded within this epoch.
	_prune_front()
	_refresh_pending()

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
