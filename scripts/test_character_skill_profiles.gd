class_name TestCharacterSkillProfiles
extends RefCounted

const DATA_PATH := "res://assets/data/vanilla_176/test_character_skill_profiles.json"
const CONTRACT_ID := "test.characters.full_skills.v1"
const EQUIPMENT_TIERS: Array[String] = ["woma", "zuma", "chiyue"]

static var _data_cache: Dictionary = {}


static func profile_for_profession(profession_name_or_id: String) -> Dictionary:
	var profession_id := ProfessionRules.profession_id(profession_name_or_id)
	var data := _data()
	var template: Dictionary = data.get("templates", {}).get(profession_id, {})
	if template.is_empty():
		return {}
	var learned_skills := {}
	var learned_skill_ids := {}
	var skill_level := int(data.get("skill_level", 3))
	for skill_id: Variant in template.get("skill_ids", []):
		var stable_id := str(skill_id)
		var display_name := ProfessionRules.skill_display_name(stable_id)
		if display_name.is_empty():
			return {}
		learned_skills[display_name] = skill_level
		learned_skill_ids[stable_id] = skill_level
	var quick_slots: Array[String] = []
	var quick_slot_ids: Array[String] = []
	for skill_id: Variant in template.get("quick_slot_ids", []):
		var stable_id := str(skill_id)
		var display_name := ProfessionRules.skill_display_name(stable_id)
		if display_name.is_empty():
			return {}
		quick_slot_ids.append(stable_id)
		quick_slots.append(display_name)
	return {
		"contract_id": str(data.get("contract_id", "")),
		"template_id": str(template.get("template_id", "")),
		"profession_id": profession_id,
		"profession": ProfessionRules.profession_display_name(profession_id),
		"skill_level": skill_level,
		"minimum_character_level": int(data.get("minimum_character_level", 40)),
		"learned_skills": learned_skills,
		"learned_skill_ids": learned_skill_ids,
		"quick_slots": quick_slots,
		"quick_slot_ids": quick_slot_ids,
		"runtime_defaults": template.get("runtime_defaults", {}).duplicate(true),
		"equipment_tiers": EQUIPMENT_TIERS.duplicate(),
	}


static func profile_for_character(profession_name_or_id: String, equipment_tier: String) -> Dictionary:
	if equipment_tier not in EQUIPMENT_TIERS:
		return {}
	var profile := profile_for_profession(profession_name_or_id)
	if profile.is_empty():
		return profile
	profile["equipment_tier"] = equipment_tier
	profile["character_profile_id"] = "test.character.%s.%s.v1" % [profile.profession_id, equipment_tier]
	return profile


static func _data() -> Dictionary:
	if not _data_cache.is_empty():
		return _data_cache
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_data_cache = parsed if parsed is Dictionary else {}
	return _data_cache
