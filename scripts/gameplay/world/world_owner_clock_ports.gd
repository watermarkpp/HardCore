extends RefCounted

## Views of the existing Host ClockFrame; this object never advances a clock.
var _world: WeakRef
var _owner := OS.get_thread_caller_id()
var _settings: Dictionary
func _init(world: RefCounted, settings: Dictionary) -> void:
	_world = weakref(world)
	_settings = settings
func owner_thread_id() -> int: return _owner
func get_ticks_usec() -> int: return Time.get_ticks_usec()
func get_ticks_msec() -> int: return Time.get_ticks_msec()
func get_unix_time_from_system() -> float: return Time.get_unix_time_from_system()
func now_usec() -> int: return Time.get_ticks_usec()
func now_msec() -> int: return Time.get_ticks_msec()
func get_process_frames() -> int:
	return int(_world.get_ref().source_process_epoch())
func get_physics_frames() -> int:
	return int(_world.get_ref().source_physics_ordinal())
func get_setting(key: String, default: Variant = null) -> Variant:
	if not _settings.has(key):
		if key.begins_with("hardcore/") and _settings.get("__hardcore_source_settings_capture__") == {"contract_id":"hardcore.settings.complete_namespace.v1","prefix":"hardcore/"}: return default
		_world.get_ref().fault("project_setting_not_published", {"key": key})
		return default
	return _settings[key]
func tree_is_paused() -> bool: return _world.get_ref().profile_world_paused()
func create_timer(delay: float, always := true, physics := false, ignore_scale := false) -> RefCounted:
	return _world.get_ref().create_timer(delay, always, physics, ignore_scale)
