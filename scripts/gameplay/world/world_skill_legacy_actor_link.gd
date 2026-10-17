extends RefCounted

## Main compatibility keeps the exact weak Node lifetime. It is never sent
## to S. The S counterpart is the registry ActorLink storage lease.
var _owner := OS.get_thread_caller_id()
var _actor: WeakRef

func _init(actor: Object) -> void:
	assert(_owner == OS.get_main_thread_id())
	_actor = weakref(actor)

func borrow_model() -> Object:
	assert(OS.get_thread_caller_id() == _owner)
	return _actor.get_ref() if _actor != null else null

func dispose() -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_actor = null
