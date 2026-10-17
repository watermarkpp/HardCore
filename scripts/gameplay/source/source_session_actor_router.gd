extends RefCounted

## Rebinds access, never actor identity/state. The sole ServiceActors keeps this
## router; world access and qualification are weak to avoid a Core cycle.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _access: WeakRef
var _world: WeakRef
func _init(session: RefCounted) -> void: _session = weakref(session)
func owner_thread_id() -> int: return _owner
func bind_world(world: RefCounted, access: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or (_world != null and _world.get_ref() != null): return false
	if world.owner_thread_id() != _owner or access.owner_thread_id() != _owner: return false
	_world = weakref(world)
	_access = weakref(access)
	return true
func release_world(world: RefCounted) -> bool:
	if _world == null or not is_same(_world.get_ref(), world): return false
	_world = null
	_access = null
	return true
func _actual() -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner)
	if _access == null or _access.get_ref() == null:
		_session.get_ref().fault("actor_access_without_live_world", {})
		assert(false, "nonactor service scopes must use registered ProcessLink")
	return _access.get_ref()
func canonical(value: Object) -> Object: return _actual().canonical(value)
func view(value: Object) -> Object: return _actual().view(value)
func capture(value: Object) -> RefCounted: return _actual().capture(value)
func resolve(value: RefCounted) -> Object: return _actual().resolve(value)
func is_present(value: Variant) -> bool: return _actual().is_present(value)
func read_property(value: Object, key: StringName) -> Variant: return _actual().read_property(value, key)
func supports(value: Object, method: StringName) -> bool: return _actual().supports(value, method)
func invoke_call(value: Object, method: StringName, args: Array) -> Variant: return _actual().invoke_call(value, method, args)
func actor_process_enabled(handle: Object) -> bool: return _world.get_ref().actor_process_enabled(handle)
func actor_is_character_body(handle: Object) -> bool: return _world.get_ref().actor_is_character_body(handle)
