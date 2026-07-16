extends Node

const PATH := "res://assets/data/rules/boss_skill_library.json"
var data: Dictionary = {}


func _ready() -> void:
	var file := FileAccess.open(PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	data = parsed if parsed is Dictionary else {}


func profile(boss_id: String) -> Dictionary:
	return data.get("bossProfiles", {}).get(boss_id, {}).duplicate(true)


func skill(skill_id: String) -> Dictionary:
	return data.get("skills", {}).get(skill_id, {}).duplicate(true)
