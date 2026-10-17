extends RefCounted
## Aggregate storage for the original Enemy model, Handle and native motion.
var model: RefCounted
var handle: Object
var ports: RefCounted
var motion: RefCounted
var _core: WeakRef
var _native: Object
var _registry: WeakRef
var _closed := false
func _init(core: RefCounted, actor: RefCounted, record: Object, actor_ports: RefCounted, native_motion: RefCounted) -> void:
	_core = weakref(core)
	model = actor
	handle = record
	ports = actor_ports
	motion = native_motion
	_native = core.native_world
	_registry = weakref(core.registry)
func healthy() -> bool: return not _closed and not ports.faulted()
func step_physics(delta: float) -> bool:
	if not healthy(): return false
	model._physics_process(delta)
	return healthy()
func flush_facts() -> bool: return ports.flush_facts()
func leave_world() -> bool: return handle.set_world_membership(false)
func final_retire() -> bool:
	if _closed: return true
	if not ports.flush_facts(): return false
	var id: int = handle.get_instance_id()
	if not _core.get_ref().enemy_exit_at_original_checkpoint(self): return false
	_core.get_ref().release_enemy_links_at_original_final_free(model)
	if not _native.retire_actor(id) or not _registry.get_ref().retire_runtime_actor(id): return false
	_core.get_ref().forget_actor_at_original_final_free(id)
	motion.detach()
	_closed = true
	handle = null
	_native = null
	return true
