extends RefCounted
var _budget: RefCounted
var _scope: RefCounted
func _init(budget: RefCounted, scope: RefCounted) -> void:
	_budget = budget
	_scope = scope
func mark_pending(category: String, pending: bool, runnable: bool) -> void:
	_budget.mark_pending(category, pending, runnable, true, _scope)
func begin(category: String, necessary: bool) -> int: return _budget.begin(category, necessary)
func end(token: int) -> void: _budget.end(token)
func release(category: String) -> void: _budget.mark_pending(category, false)
