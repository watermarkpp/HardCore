extends RefCounted
var _owner := OS.get_thread_caller_id()
var _core: WeakRef
func _init(core: RefCounted) -> void: _core=weakref(core)
func owner_thread_id() -> int: return _owner
func record(trace: Dictionary) -> void: _core.get_ref().emit_original_main_event(&"original_loot_trace",[trace])
func write_trace(trace: Dictionary) -> void: record(trace)
