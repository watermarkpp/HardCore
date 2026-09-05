extends Node


func map_content(map_id: int) -> Dictionary:
	return WorldContent.map_content(map_id)


func spawn_rules(map_id: int) -> Dictionary:
	# Combat identity is not a geometry concern.  RegionContent filters every
	# row through canonical monster_id/runtime closure and drops legacy name or
	# camelCase identities before this service can expose spawn rules.
	var content := RegionContent.get_map_content(map_id)
	return {"spawns": content.get("spawns", []), "bosses": content.get("bosses", [])}


func quest(quest_id: String) -> Dictionary:
	return GameData.get_bich_quest(quest_id)


func equipment(item_name: String) -> Dictionary:
	return GameData.get_item_record(item_name)


func skill(skill_name: String, level: int) -> Dictionary:
	return GameData.get_skill(skill_name, level)


func save() -> bool:
	return PlayerState.save_game()
