extends Node
## The actual Main phase listener does IO/receipt routing only. No Main Profile
## gameplay, second clock or source Model is held by this Node.
var _transport: WeakRef
func configure_main(transport: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _transport!=null or is_inside_tree(): return false
	_transport=weakref(transport);process_mode=Node.PROCESS_MODE_ALWAYS
	return true
func _process(_delta: float) -> void:
	if _transport!=null and _transport.get_ref()!=null: _transport.get_ref().service_actual_original_Main_phase(self)
func _exit_tree() -> void:
	if _transport!=null and _transport.get_ref()!=null: _transport.get_ref().original_main_transport_listener_exit(self)
