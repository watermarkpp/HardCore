extends RefCounted

## One interface into Root's ORIGINAL shared owner-local budget ledger. This
## port does not own a second budget, epoch, fairness queue or timer.
var _thread := OS.get_thread_caller_id()
var _owner: WeakRef
func _init(owner: RefCounted) -> void:
	assert(owner != null)
	_owner = weakref(owner)
func _owned() -> void: assert(OS.get_thread_caller_id() == _thread)
func mark_pending(category: String, pending: bool, runnable := true, runs_when_paused := false, _process_owner: Object = null, physics_owner := false) -> void:
	_owned()
	_owner.get_ref().call("feature_budget_mark_pending", category, pending, runnable, runs_when_paused, physics_owner)
func begin(category: String) -> int:
	_owned()
	return _owner.get_ref().call("feature_budget_begin", category)
func end(token: int) -> void:
	_owned()
	_owner.get_ref().call("feature_budget_end", token)
