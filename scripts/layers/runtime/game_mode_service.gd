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
	apply_mode(active_mode)


func apply_mode(mode_id: String) -> bool:
	if not modes.has(mode_id):
		return false
	active_mode = mode_id
	var enabled: Array = modes[mode_id].get("enabledPackages", [])
	var content_changed := false
	for package_id: String in ContentLayers.enabled_expansions:
		content_changed = ContentLayers.set_expansion_enabled(package_id, package_id in enabled) or content_changed
	if is_instance_valid(PlayerState):
		PlayerState.game_mode_id = mode_id
	if is_instance_valid(GameData) and (content_changed or GameData.maps.is_empty()):
		GameData.load_database()
	return true


func mode() -> Dictionary:
	return modes.get(active_mode, {}).duplicate(true)
