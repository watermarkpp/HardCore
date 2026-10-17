extends RefCounted

## Original scheduler job owners are weak. Each job keeps the resolver of its
## original world weakly; a later world cannot reinterpret an old canonical ID.
var _owner := OS.get_thread_caller_id()
var _current: WeakRef
var _world: WeakRef

class JobLink:
	extends RefCounted
	var owner: WeakRef
	var resolver: WeakRef
	var runtime_id: int
class JobTarget:
	extends RefCounted
	var link: JobLink
	func actual() -> Object: return link.owner.get_ref()

func owner_thread_id() -> int: return _owner
func bind_world(world: RefCounted, access: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or world.owner_thread_id() != _owner or access.owner_thread_id() != _owner: return false
	if _world != null and _world.get_ref() != null: return false
	_current = weakref(access)
	_world = weakref(world)
	return true
func release_world(world: RefCounted) -> bool:
	if _world == null or not is_same(_world.get_ref(), world): return false
	_current = null
	_world = null
	return true
func _source(value: Object) -> RefCounted:
	assert(OS.get_thread_caller_id() == _owner)
	return value.link.resolver.get_ref() if value is JobTarget else (_current.get_ref() if _current != null else null)
func _value(value: Object) -> Object: return value.actual() if value is JobTarget else value
func present(value: Object) -> bool:
	var access := _source(value)
	return access != null and _value(value) != null and access.present(_value(value))
func runtime_id(value: Object) -> int:
	if value is JobTarget: return value.link.runtime_id
	var access := _source(value)
	assert(access != null and access.present(value))
	return access.runtime_id(value)
func capture(value: Object) -> RefCounted:
	var access := _source(value)
	assert(access != null and access.present(value))
	var link := JobLink.new()
	link.owner = weakref(value)
	link.resolver = weakref(access)
	link.runtime_id = access.runtime_id(value)
	return link
func resolve(link: RefCounted) -> Object:
	if not link is JobLink or link.owner.get_ref() == null or link.resolver.get_ref() == null: return null
	var value := JobTarget.new()
	value.link = link
	return value if present(value) else null
func queued(value: Object) -> bool: return _source(value).queued(_value(value))
func invoke(value: Object, arguments: Array) -> Variant: return _source(value).invoke(_value(value), arguments)
