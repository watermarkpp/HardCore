extends RefCounted

## Diagnostic-only nested CPU accounting. It owns no gameplay state.
static var armed := false
static var active := false
static var _stack: Array[Dictionary] = []
static var _totals: Dictionary = {}

static func start_window() -> void:
	if not armed:
		return
	_stack.clear()
	_totals.clear()
	active = true

static func begin(label: StringName) -> bool:
	if not active:
		return false
	_stack.append({"label":label,"start":Time.get_ticks_usec(),"children":0})
	return true

static func end(token: bool) -> void:
	if not token:
		return
	var elapsed_end := Time.get_ticks_usec()
	var frame: Dictionary = _stack.pop_back()
	var duration := elapsed_end - int(frame.start)
	var label: StringName = frame.label
	var record: Dictionary = _totals.get(label, {"calls":0,"inclusive_usec":0,"exclusive_usec":0})
	record.calls = int(record.calls) + 1
	record.inclusive_usec = int(record.inclusive_usec) + duration
	record.exclusive_usec = int(record.exclusive_usec) + duration - int(frame.children)
	_totals[label] = record
	if not _stack.is_empty():
		_stack.back().children = int(_stack.back().children) + duration

static func stop_window() -> Dictionary:
	active = false
	return {"segments":_totals.duplicate(true),"open_segments":_stack.size(),
		"scope":"instrumented v107 CPU diagnostic, not uninstrumented performance acceptance",
		"exclusive_definition":"inclusive minus instrumented nested children; uninstrumented work remains inside nearest parent"}
