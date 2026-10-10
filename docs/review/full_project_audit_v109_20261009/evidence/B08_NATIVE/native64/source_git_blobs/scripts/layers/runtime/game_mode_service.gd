extends Node

const PATH := "res://assets/data/game_modes.json"
var modes: Dictionary = {}
var active_mode := "classic_176"


func _ready() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		modes = parsed.get("modes", {})
		active_mode = str(parsed.get("defaultMode", "classic_176"))
	# Android data loading is admitted by StartupLoading after the intro.
	if ContentLayers.is_loaded() and GameData.is_loaded():
		ensure_initial_mode()


func ensure_initial_mode() -> bool:
	return apply_mode(active_mode)


func prepare_mode_configuration(mode_id: String, later_override: Variant = null) -> Dictionary:
	if not modes.has(mode_id):
		return {"success": false, "error": "unknown_game_mode"}
	if later_override != null and not later_override is bool:
		return {"success": false, "error": "invalid_later_content_override"}
	var enabled: Array = modes[mode_id].get("enabledPackages", [])
	var requested: Dictionary = {}
	for package_id: String in ContentLayers.enabled_expansions:
		requested[package_id] = package_id in enabled
	for package_id: Variant in enabled:
		if not requested.has(package_id):
			return {"success": false, "error": "unknown_mode_content_package"}
	if later_override != null:
		requested["later_176_content"] = later_override
	var content := ContentLayers.prepare_expansion_configuration(requested)
	if content == null:
		return {"success": false, "error": ContentLayers.last_expansion_error}
	return {"success": true, "mode_id": mode_id,
		"later_content_enabled": bool(requested.get("later_176_content", false)), "content": content}


func apply_prepared_mode_configuration(prepared: Dictionary) -> bool:
	if not bool(prepared.get("success", false)):
		return false
	return ContentLayers.apply_prepared_expansion_configuration(
		prepared.content, Callable(self, "_commit_mode_fields").bind(
			str(prepared.mode_id), bool(prepared.later_content_enabled)))


func _commit_mode_fields(mode_id: String, later_enabled: bool) -> void:
	active_mode = mode_id
	if is_instance_valid(PlayerState):
		PlayerState.game_mode_id = mode_id
		PlayerState.later_content_enabled = later_enabled


func apply_mode(mode_id: String, later_override: Variant = null) -> bool:
	return apply_prepared_mode_configuration(prepare_mode_configuration(mode_id, later_override))


func mode() -> Dictionary:
	return modes.get(active_mode, {}).duplicate(true)
