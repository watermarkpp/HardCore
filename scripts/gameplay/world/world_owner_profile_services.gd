extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/gameplay/profile/profile_model.gd")
var _owner := OS.get_thread_caller_id()
var _target: WeakRef
func _init(target: RefCounted) -> void:
	assert(_owner != OS.get_main_thread_id())
	_target = weakref(target)
func owner_thread_id() -> int: return _owner
func _get(field: StringName) -> Variant:
	var source_script: Script=Source
	var constants: Dictionary=source_script.get_script_constant_map()
	return constants[String(field)] if constants.has(String(field)) else _target.get_ref().get(field)
func _set(field: StringName, value: Variant) -> bool:
	_target.get_ref().set(field, value)
	return true
