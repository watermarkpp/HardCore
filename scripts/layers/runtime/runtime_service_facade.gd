extends Node


func save_active_character() -> void:
	PlayerState.save_game()


func safe_logout_to_home(home_position: Vector2) -> bool:
	return PlayerState.save_safe_logout(GameData.service_home_runtime_map_id(false), home_position)


func content_status() -> Dictionary:
	return ContentLayers.architecture_status()


func set_expansion_enabled(package_id: String, enabled: bool) -> bool:
	var changed := ContentLayers.set_expansion_enabled(package_id, enabled)
	if changed and package_id == "later_176_content":
		PlayerState.set_later_content_enabled(enabled)
	elif changed:
		GameData.load_database()
	return changed
