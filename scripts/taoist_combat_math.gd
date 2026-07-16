class_name TaoistCombatMath
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
		"formula_source": "profession_combat_rules.json/TaoistCombatMath",
		"confidence": str(rule.get("confidence", "B")),
		"source_status": str(rule.get("source_status", "runtime_candidate")),
	}
	for key: String in rule.keys():
		if not key.ends_with("_by_level") or not rule[key] is Array:
			continue
		result[key.trim_suffix("_by_level")] = _level_value(rule[key], level)
	for key: String in ["tick_interval", "attack_type", "leash_range", "teleport_range"]:
		if rule.has(key):
			result[key] = rule[key]
	return result


static func damage(skill_id: String, tao_power: int, level_value: int) -> int:
	var profile := profile_overrides(skill_id, level_value)
	return maxi(1, roundi(float(maxi(1, tao_power)) * float(profile.get("multiplier", 1.0))))


static func healing(skill_id: String, tao_power: int, level_value: int) -> int:
	var profile := profile_overrides(skill_id, level_value)
	return maxi(1, roundi(float(maxi(1, tao_power)) * float(profile.get("multiplier", 1.0))) + int(profile.get("flat_power", 0)))


static func summon_profile(skill_id: String, skill_level: int, owner_level: int, tao_power: int) -> Dictionary:
	var level := clamp_skill_level(skill_level)
	var rule := profile_overrides(skill_id, level)
	var divine_beast := skill_id == "taoist.summon_divine_beast"
	var safe_owner_level := maxi(1, owner_level)
	var safe_tao := maxi(1, tao_power)
	var hp := (100 + safe_owner_level * 6 + level * 40) if divine_beast else (50 + safe_owner_level * 4 + level * 25)
	var attack_min := maxi(1, int(safe_tao * (0.55 if divine_beast else 0.35)) + level * 2)
	var attack_max := maxi(attack_min, int(safe_tao * (1.05 if divine_beast else 0.75)) + level * 3)
	return {
		"skill_id": skill_id,
		"skill_level": level,
		"summon_id": "divine_beast" if divine_beast else "skeleton",
		"display_name": "神兽" if divine_beast else "骷髅",
		"attack_type": str(rule.get("attack_type", "fire" if divine_beast else "physical")),
		"max_hp": hp,
		"attack_min": attack_min,
		"attack_max": attack_max,
		"move_speed": 155.0 if divine_beast else 135.0,
		"attack_range": 72.0 if divine_beast else 48.0,
		"attack_interval": 1.0 if divine_beast else 1.25,
		"aggro_radius": 380.0 if divine_beast else 330.0,
		"lifetime_seconds": float(rule.get("lifetime_seconds", 300 if divine_beast else 180)),
		"leash_range": float(rule.get("leash_range", 560.0)),
		"teleport_range": float(rule.get("teleport_range", 900.0)),
		"confidence": str(rule.get("confidence", "C")),
		"formula_id": "%s.summon.v1" % skill_id,
	}


static func _skill_rule(skill_id: String) -> Dictionary:
	var root := _rules()
	return root.get("taoist", {}).get("skills", {}).get(skill_id, {})


static func _rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_rules_cache = parsed if parsed is Dictionary else {}
	return _rules_cache


static func _level_value(values: Array, level: int) -> Variant:
	return values[mini(level, values.size() - 1)] if not values.is_empty() else null
