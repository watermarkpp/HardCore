class_name MapEditorCommandStack
extends RefCounted

var history_limit := 50
var _undo_stack: Array[Dictionary] = []
var _redo_stack: Array[Dictionary] = []


func execute(command: Dictionary) -> bool:
	var do_action: Callable = command.get("do", Callable())
	var undo_action: Callable = command.get("undo", Callable())
	if not do_action.is_valid() or not undo_action.is_valid():
		return false
	do_action.call()
	_undo_stack.append(command)
	if _undo_stack.size() > history_limit:
		_undo_stack.pop_front()
	_redo_stack.clear()
	return true


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	var command: Dictionary = _undo_stack.pop_back()
	var undo_action: Callable = command.get("undo", Callable())
	undo_action.call()
	_redo_stack.append(command)
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	var command: Dictionary = _redo_stack.pop_back()
	var do_action: Callable = command.get("do", Callable())
	do_action.call()
	_undo_stack.append(command)
	return true


func clear() -> void:
	_undo_stack.clear()
	_redo_stack.clear()


func can_undo() -> bool:
	return not _undo_stack.is_empty()


func can_redo() -> bool:
	return not _redo_stack.is_empty()
