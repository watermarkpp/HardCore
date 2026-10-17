extends RefCounted
## S narrow adapter to the existing actual Loading Feature primitive endpoint.
## It shares that endpoint's sole budget/sourceSite/sequence/prefix, no new timer.
var _thread:=OS.get_thread_caller_id()
var _primitives: WeakRef
func owner_thread_id() -> int: return _thread
func bind_original_source_endpoint(primitives: RefCounted) -> bool:
	if OS.get_thread_caller_id()!=_thread or _primitives!=null or primitives.owner_thread_id()!=_thread or not primitives.has_method("_exchange"): return false
	_primitives=weakref(primitives)
	return true
func _call(operation: String, arguments: Array) -> Dictionary:
	assert(OS.get_thread_caller_id()==_thread and _primitives!=null and _primitives.get_ref()!=null)
	var result: Variant=_primitives.get_ref()._exchange("source_admission_"+operation,arguments)
	assert(result is Dictionary,"actual Main admission receipt required")
	return result
func verify_original_unselected_startup_source(boot: Dictionary) -> Dictionary: return _call("unselected",[boot])
func prepare_original_profile_source_handoff(state: Dictionary,receipt: Dictionary,lease_owner: Dictionary) -> Dictionary: return _call("prepare",[state,receipt,lease_owner])
func commit_original_profile_source_handoff(prepared: Dictionary,adopted: Dictionary) -> Dictionary: return _call("commit",[prepared,adopted])
func abort_original_profile_source_handoff(receipt: Dictionary) -> Dictionary: return _call("abort",[receipt])
func verify_original_loading_boundary(site: Dictionary) -> Dictionary: return _call("loading",[site])
func verify_actual_loading_pinned_closure(closure: Dictionary) -> Dictionary: return _call("pins",[closure])
func release_original_loading_pins(closure_id: int) -> bool: return _call("release_pins",[closure_id]).get("success")==true
