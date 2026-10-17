extends RefCounted

var modes: Dictionary
var active_mode: String
var _features: RefCounted
var _profile: WeakRef
var _thread := OS.get_thread_caller_id()

func _init(published: Dictionary, features: RefCounted, profile: RefCounted) -> void:
	assert(OS.get_thread_caller_id() != OS.get_main_thread_id())
	modes = published.modes
	active_mode = str(published.active_mode)
	_features = features
	_profile = weakref(profile)

func _assert_owner() -> void:
	assert(OS.get_thread_caller_id() == _thread and _profile.get_ref() != null)

func prepare_mode_configuration(mode_id: String, later_override: Variant = null) -> Dictionary:
	_assert_owner()
	if not modes.has(mode_id):
		return {"success": false, "error": "unknown_game_mode"}
	if later_override != null and not later_override is bool:
		return {"success": false, "error": "invalid_later_content_override"}
	var enabled: Array = modes[mode_id].get("enabledPackages", [])
	var requested: Dictionary = {}
	for package_id: String in _features.enabled_expansions:
		requested[package_id] = package_id in enabled
	for package_id: Variant in enabled:
		if not requested.has(package_id):
			return {"success": false, "error": "unknown_mode_content_package"}
	if later_override != null:
		requested["later_176_content"] = later_override
	var content: RefCounted = _features.prepare_expansion_configuration(requested)
	if content == null:
		return {"success": false, "error": _features.last_expansion_error}
	return {"success": true, "mode_id": mode_id,
		"later_content_enabled": bool(requested.get("later_176_content", false)), "content": content}

func apply_prepared_mode_configuration(prepared: Dictionary) -> bool:
	_assert_owner()
	if not bool(prepared.get("success", false)):
		return false
	return _features.apply_prepared_expansion_configuration(
		prepared.content, Callable(self, "_commit_mode_fields").bind(
			str(prepared.mode_id), bool(prepared.later_content_enabled)))

func _commit_mode_fields(mode_id: String, later_enabled: bool) -> void:
	active_mode = mode_id
	var profile: RefCounted = _profile.get_ref()
	assert(profile != null)
	profile.game_mode_id = mode_id
	profile.later_content_enabled = later_enabled

func apply_mode(mode_id: String, later_override: Variant = null) -> bool:
	return apply_prepared_mode_configuration(prepare_mode_configuration(mode_id, later_override))

func mode() -> Dictionary:
	_assert_owner()
	return modes.get(active_mode, {}).duplicate(true)
