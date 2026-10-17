extends RefCounted

## Legacy main owner adapter. Simulation supplies its own owner-local budget;
## this adapter never crosses the owner boundary.
const FrameBudget = preload("res://scripts/layers/runtime/execution/frame_budget.gd")
var _owner = WeakRef.new()

func configure(owner: Node) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	_owner = weakref(owner)

func mark_pending(category: String, pending: bool, runnable: bool) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	FrameBudget.mark_pending(category, pending, runnable, true, _owner.get_ref() as Node)

func begin(category: String, necessary: bool) -> int:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return 0
	return FrameBudget.begin(category, necessary)

func end(token: int) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	FrameBudget.end(token)

func release(category: String) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return
	FrameBudget.mark_pending(category, false)