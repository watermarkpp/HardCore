class_name WizardCombatMath
extends RefCounted

const RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"
const MAX_SKILL_LEVEL := 3

static var _rules_cache: Dictionary = {}


static func clamp_skill_level(level_value: int) -> int:
	return clampi(level_value, 0, MAX_SKILL_LEVEL)


static func profile_overrides(skill_id: String, level_value: int) -> Dictionary:
	var rule := _skill_rule(skill_id)
	if rule.is_empty():
		return {}
	var level := clamp_skill_level(level_value)
	var result := {
		"skill_level": level,
		"formula_id": "%s.v1" % skill_id,
		"formula_source": "profession_combat_rules.json/WizardCombatMath",
		"confidence": str(rule.get("confidence", "B")),
		"source_status": str(rule.get("source_status", "runtime_candidate")),
	}
	for key: String in rule.keys():
		if not key.ends_with("_by_level") or not rule[key] is Array:
			continue
		var output_key := key.trim_suffix("_by_level")
		result[output_key] = _level_value(rule[key], level)
	for key: String in ["tick_interval", "execute_level_margin"]:
		if rule.has(key):
			result[key] = rule[key]
	return result


static func damage(skill_id: String, magic_power: int, level_value: int) -> int:
	var profile := profile_overrides(skill_id, level_value)
	return maxi(1, roundi(float(maxi(1, magic_power)) * float(profile.get("multiplier", 1.0))))


static func shield_damage_reduction(level_value: int) -> float:
	return float(profile_overrides("wizard.magic_shield", level_value).get("damage_reduction", 0.25))


static func shield_duration(level_value: int) -> float:
	return float(profile_overrides("wizard.magic_shield", level_value).get("status_duration", 8.0))


static func fire_wall_duration(level_value: int) -> float:
	return float(profile_overrides("wizard.fire_wall", level_value).get("status_duration", 4.0))


static func _skill_rule(skill_id: String) -> Dictionary:
	var root := _rules()
	return root.get("wizard", {}).get("skills", {}).get(skill_id, {})


static func _rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_rules_cache = parsed if parsed is Dictionary else {}
	return _rules_cache


static func _level_value(values: Array, level: int) -> Variant:
	return values[mini(level, values.size() - 1)] if not values.is_empty() else null
