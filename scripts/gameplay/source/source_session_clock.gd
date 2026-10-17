extends RefCounted
## Views only the actual Host clock and actual wall; does not emit a timer.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _host: Object
var _settings: Dictionary
func _init(session: RefCounted, host: Object, settings: Dictionary) -> void:
	_session = weakref(session)
	_host = host
	_settings = settings
func owner_thread_id() -> int: return _owner
func get_ticks_usec() -> int: return Time.get_ticks_usec()
func get_ticks_msec() -> int: return Time.get_ticks_msec()
func get_unix_time_from_system() -> float: return Time.get_unix_time_from_system()
func now_usec() -> int: return Time.get_ticks_usec()
func now_msec() -> int: return Time.get_ticks_msec()
func get_process_frames() -> int:
	var frame: Dictionary = _host.current_clock_frame()
	assert(frame.get("source_process_frame") is int)
	return frame.source_process_frame
func get_physics_frames() -> int:
	var frame: Dictionary = _host.current_clock_frame()
	assert(frame.get("source_physics_frame") is int)
	return frame.source_physics_frame
func get_setting(key: String, _default: Variant = null) -> Variant:
	if not _settings.has(key):
		if key.begins_with("hardcore/") and _settings.get("__hardcore_source_settings_capture__") == {"contract_id":"hardcore.settings.complete_namespace.v1","prefix":"hardcore/"}: return _default
		_session.get_ref().fault("source_setting_not_published", {"key": key})
		assert(false, "source setting publication required")
	return _settings[key]
func tree_is_paused() -> bool: return _session.get_ref().profile_world_paused()
