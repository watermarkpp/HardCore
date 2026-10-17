extends RefCounted

## Original SceneTree group insertion order. Queueing free does not remove a
## member; original remove_from_group/exit does. No eligibility is cached here.
var _owner := OS.get_thread_caller_id()
var _registry: WeakRef
var _groups: Dictionary = {}
func _init(registry: RefCounted) -> void: _registry = weakref(registry)
func add(handle: Object, group: StringName) -> bool:
	assert(OS.get_thread_caller_id() == _owner)
	var id := handle.get_instance_id()
	if _registry.get_ref().resolve_runtime_actor(id) != handle: return false
	if not _groups.has(group): _groups[group] = [] as Array[int]
	if not _groups[group].has(id): _groups[group].append(id)
	return true
func remove(id: int, group: StringName) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	if _groups.has(group): _groups[group].erase(id)
func remove_all(id: int) -> void:
	for group: StringName in _groups: remove(id, group)
func contains(id: int, group: StringName) -> bool:
	return _groups.has(group) and _groups[group].has(id)
func ordered(group: StringName) -> Array[Object]:
	assert(OS.get_thread_caller_id() == _owner)
	var result: Array[Object] = []
	if not _groups.has(group): return result
	for id: int in _groups[group]:
		var handle: Object = _registry.get_ref().resolve_runtime_actor(id)
		if handle != null and handle.runtime_object_is_present(): result.append(handle)
	return result
