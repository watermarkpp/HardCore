extends Node


# Main callback depth only. No new gameplay/IO owner or timer.
var _original_main_callback_ledger: Dictionary = {}


func save_active_character() -> void:
	_original_main_callback_ledger["save_active_character"] = int(_original_main_callback_ledger.get("save_active_character",0)) + 1
	_original_source_runtime_service_facade_save_active_character()
	_original_main_callback_ledger["save_active_character"] -= 1


func _original_source_runtime_service_facade_save_active_character() -> void:
	PlayerState.save_game()


func safe_logout_to_home(home_position: Vector2) -> bool:
	_original_main_callback_ledger["safe_logout_to_home"] = int(_original_main_callback_ledger.get("safe_logout_to_home",0)) + 1
	var original_result: Variant = _original_source_runtime_service_facade_safe_logout_to_home(home_position)
	_original_main_callback_ledger["safe_logout_to_home"] -= 1
	return original_result


func _original_source_runtime_service_facade_safe_logout_to_home(home_position: Vector2) -> bool:
	return PlayerState.save_safe_logout(GameData.service_home_runtime_map_id(false), home_position)


func content_status() -> Dictionary:
	return ContentLayers.architecture_status()


func set_expansion_enabled(package_id: String, enabled: bool) -> bool:
	_original_main_callback_ledger["set_expansion_enabled"] = int(_original_main_callback_ledger.get("set_expansion_enabled",0)) + 1
	var original_result: Variant = _original_source_runtime_service_facade_set_expansion_enabled(package_id,enabled)
	_original_main_callback_ledger["set_expansion_enabled"] -= 1
	return original_result


func _original_source_runtime_service_facade_set_expansion_enabled(package_id: String, enabled: bool) -> bool:
	if not ContentLayers.enabled_expansions.has(package_id) or ContentLayers.is_expansion_enabled(package_id) == enabled:
		return false
	if package_id == "later_176_content":
		return PlayerState.set_later_content_enabled(enabled)
	return ContentLayers.set_expansion_enabled(package_id, enabled)
