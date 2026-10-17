extends RefCounted

## Only the main compatibility adapter holds this weak Node reference. No copy
## of its fields is cached: direct legacy writes remain visible immediately.
var _source: WeakRef
var _owner := OS.get_thread_caller_id()

func _init(source: Node) -> void:
	if _owner != OS.get_main_thread_id() or source == null: return
	_source = weakref(source)

func read_field(name: String) -> Variant:
	if _owner != OS.get_thread_caller_id(): return null
	var source: Node = _source.get_ref() if _source != null else null
	return source.get(name) if source != null else null

func write_field(name: String, value: Variant) -> void:
	if _owner != OS.get_thread_caller_id(): return
	var source: Node = _source.get_ref() if _source != null else null
	if source != null: source.set(name, value)
