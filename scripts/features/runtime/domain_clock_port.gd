extends RefCounted

## Root supplies the same accumulated H simulation time as the old TimeDomains
## authority, rounded once. No new local accumulator or advance operation.
var _thread := OS.get_thread_caller_id()
var _owner: WeakRef
func _init(owner: RefCounted) -> void:
	assert(owner != null)
	_owner = weakref(owner)
func simulation_usec() -> int:
	assert(OS.get_thread_caller_id() == _thread)
	return _owner.get_ref().call("feature_simulation_usec")
