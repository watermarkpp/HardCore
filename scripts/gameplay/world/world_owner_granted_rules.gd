extends RefCounted
## Borrowed view of the SAME original rule/model authority. No state copy.
const Source := preload("res://scripts/equipment_granted_skill_rules.gd")
var _owner := OS.get_thread_caller_id()
func owner_thread_id() -> int: return _owner
func _get(field: StringName) -> Variant:
	var script: Script = Source
	return script.get_script_constant_map().get(String(field), script.get(field))

func definition(skill_id: String) -> Dictionary:
	assert(OS.get_thread_caller_id() == _owner)
	return Source.definition(skill_id)
