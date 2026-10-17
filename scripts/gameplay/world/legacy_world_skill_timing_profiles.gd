extends RefCounted

## Used only by the original M visual registry API, never passed to S.
var _registry: WeakRef
var _owner := OS.get_thread_caller_id()

func _init() -> void:
	assert(_owner == OS.get_main_thread_id())
	_registry = weakref(load("res://scripts/caster_skill_visual_registry.gd"))

func profile(skill: String) -> Dictionary:
	if OS.get_thread_caller_id() != _owner: return {}
	return _registry.get_ref().call("profile", skill)

func skill_id(skill: String) -> String:
	if OS.get_thread_caller_id() != _owner: return ""
	return ProfessionRules.skill_id(skill)
