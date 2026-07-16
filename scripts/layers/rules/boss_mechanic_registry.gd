extends Node

const PATH := "res://assets/data/rules/boss_skill_library.json"
var data: Dictionary = {}


func _ready() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	data = parsed if parsed is Dictionary else {}


func profile(boss_key: Variant) -> Dictionary:
	var stable_key := str(int(boss_key)) if boss_key is int or (boss_key is String and boss_key.is_valid_int()) else ""
	if not stable_key.is_empty():
		var canonical: Variant = data.get("bossProfilesByMonsterId", {}).get(stable_key, {})
		if canonical is Dictionary and not canonical.is_empty():
			return canonical.duplicate(true)
	var legacy_name := str(boss_key)
	var legacy_id := str(int(data.get("legacyNameToMonsterId", {}).get(legacy_name, -1)))
	var by_legacy_id: Variant = data.get("bossProfilesByMonsterId", {}).get(legacy_id, {})
	if by_legacy_id is Dictionary and not by_legacy_id.is_empty():
		return by_legacy_id.duplicate(true)
	return data.get("bossProfiles", {}).get(legacy_name, {}).duplicate(true)


func skill(skill_id: String) -> Dictionary:
	return data.get("skills", {}).get(skill_id, {}).duplicate(true)
