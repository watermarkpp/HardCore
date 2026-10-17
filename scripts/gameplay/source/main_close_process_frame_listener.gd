extends Node
## Actual Main SceneTree callback, persistent across current_scene removal.
## No timer and no S gameplay/actor callbacks. PROCESS_MODE_ALWAYS is genuine.
var _producer: WeakRef
func configure_main(producer: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _producer!=null or producer==null or is_inside_tree(): return false
	_producer=weakref(producer)
	process_mode=Node.PROCESS_MODE_ALWAYS
	return true
func _process(delta: float) -> void:
	if _producer==null or _producer.get_ref()==null: return
	_producer.get_ref().record_actual_original_process_frame(self,delta)
func _exit_tree() -> void:
	if _producer!=null and _producer.get_ref()!=null: _producer.get_ref().original_listener_exit(self)
