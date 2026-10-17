extends RefCounted

## Nonphysical actor aggregate. Never creates a native actor, RID or motion port.
var _owner := OS.get_thread_caller_id()
var model: RefCounted
var handle: Object
var ports: RefCounted
var _registry: WeakRef
var _scope: RefCounted
var _closed := false
var _retirement_accepted := false
func _init(p_model: RefCounted,p_handle: Object,p_ports: RefCounted,registry: RefCounted,scope: RefCounted) -> void:
	model=p_model; handle=p_handle; ports=p_ports; _registry=weakref(registry); _scope=scope
func healthy() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	return not _closed and not ports.faulted()
func flush_facts() -> bool: return healthy() and ports.flush_facts()
func leave_world() -> bool:
	return healthy() and handle.set_world_membership(false)
func final_retire() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	if _closed: return true
	if not _scope.exit_callbacks_complete or _scope.inside_world: return false
	if not _retirement_accepted:
		if not ports.retire_visual_at_original_free(model): return false
		_retirement_accepted=true
	if not _registry.get_ref().retire_runtime_actor(handle.get_instance_id()): return false
	_closed=true; handle=null
	return true
