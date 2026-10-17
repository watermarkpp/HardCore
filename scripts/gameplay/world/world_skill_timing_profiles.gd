extends RefCounted

var _profiles: Dictionary
var _professions: RefCounted
var _owner := OS.get_thread_caller_id()

func _init(published_profiles: Dictionary, professions: RefCounted) -> void:
	_profiles = published_profiles
	_professions = professions

func profile(skill: String) -> Dictionary:
	if OS.get_thread_caller_id() != _owner: return {}
	# Original Registry.profile returns a fresh mutable record on every call.
	return _profiles.get(skill_id(skill), {}).duplicate(true)

func skill_id(skill: String) -> String:
	if OS.get_thread_caller_id() != _owner: return ""
	return _professions.skill_id(skill)
