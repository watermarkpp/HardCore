extends Node


func map_content(map_id: int) -> Dictionary:
	return WorldContent.map_content(map_id)


func spawn_rules(map_id: int) -> Dictionary:
	var content := map_content(map_id)
	return {"spawns": content.get("spawns", []), "bosses": content.get("bosses", [])}


func quest(quest_id: String) -> Dictionary:
	return GameData.get_bich_quest(quest_id)


func equipment(item_name: String) -> Dictionary:
	return GameData.get_item_record(item_name)


func skill(skill_name: String, level: int) -> Dictionary:
	return GameData.get_skill(skill_name, level)


func save() -> void:
	PlayerState.save_game()
