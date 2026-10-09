class_name NoPlanFailureAuditSink20261009
extends RefCounted

var _owner_id := 0
var _calls: Array[Dictionary] = []
var _active: Dictionary = {}

func _init(owner_id: int = 0) -> void:
	_owner_id = owner_id

func begin_call(owner_id: int, current: Vector2, blocked_id: int, blocked_self: Vector2, blocked_target: Vector2, known: Vector2) -> void:
	var key := str(_calls.size())
	_active[key] = {"owner_id": owner_id, "current": [current.x, current.y], "blocked_id": blocked_id,
		"blocked_self": [blocked_self.x, blocked_self.y], "blocked_target": [blocked_target.x, blocked_target.y],
		"known": [known.x, known.y], "events": [], "wait": [], "postretry": [], "budget": [],
		"chooser_success": false, "complete_failure": false, "target_only_invalidation": false,
		"known_live_differences": [], "elapsed_usec": -1}

func event(kind: StringName, values: Array = []) -> void:
	if _active.is_empty():
		return
	var key: String = _active.keys().back()
	var call: Dictionary = _active[key]
	var row := {"kind": str(kind), "values": values.duplicate(true)}
	call.events.append(row)
	var event_counts: Dictionary = call.get("event_counts", {})
	event_counts[str(kind)] = int(event_counts.get(str(kind), 0)) + 1
	call.event_counts = event_counts
	if str(kind) == "wait_entry":
		call.wait.append(row)
	elif str(kind).begins_with("postretry"):
		call.postretry.append(row)
	elif str(kind).begins_with("budget"):
		call.budget.append(row)
	if str(kind) == "chooser_enter":
		call.chooser_entered = true
	if str(kind) == "chooser_success":
		call.chooser_success = true
	if str(kind) == "complete_failure":
		call.complete_failure = true
	if str(kind) == "target_only_invalidation":
		call.target_only_invalidation = true
	if str(kind) == "known_live_difference":
		call.known_live_differences.append(values.duplicate(true))
	_active[key] = call

func end_call(result: Vector2i, elapsed: int) -> void:
	if _active.is_empty():
		return
	var key: String = _active.keys().back()
	var call: Dictionary = _active[key]
	call.result = [result.x, result.y]
	call.elapsed_usec = elapsed
	_calls.append(call)
	_active.erase(key)

func clear() -> void:
	_calls.clear()
	_active.clear()

func snapshot() -> Dictionary:
	var counts := {"calls": _calls.size(), "wait": 0, "postretry": 0, "budget": 0,
		"chooser_entered": 0, "chooser_success": 0, "complete_failure": 0, "target_only_invalidation": 0,
		"known_live_difference": 0, "elapsed_usec": 0}
	for call: Dictionary in _calls:
		counts.wait += call.wait.size()
		counts.postretry += call.postretry.size()
		counts.budget += call.budget.size()
		counts.chooser_entered += int(call.get("event_counts", {}).get("chooser_enter", 0))
		counts.chooser_success += 1 if bool(call.get("chooser_success", false)) else 0
		counts.complete_failure += 1 if bool(call.get("complete_failure", false)) else 0
		counts.target_only_invalidation += 1 if bool(call.get("target_only_invalidation", false)) else 0
		counts.known_live_difference += call.known_live_differences.size()
		counts.elapsed_usec += maxi(0, int(call.get("elapsed_usec", -1)))
	return {"owner_id": _owner_id, "counts": counts, "calls": _calls.duplicate(true), "active": _active.duplicate(true)}
