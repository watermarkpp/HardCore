extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/art_spec.gd")
var _owner := OS.get_thread_caller_id()
func owner_thread_id() -> int: return _owner
func _get(field: StringName) -> Variant:
	var source_script: Script=Source
	return source_script.get_script_constant_map().get(String(field), source_script.get(field))

func direction_index(direction: Vector2) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.direction_index(direction)

func mir2_client_direction_row(direction: Vector2) -> int:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.mir2_client_direction_row(direction)
