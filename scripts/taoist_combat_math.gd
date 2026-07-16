class_name TaoistCombatMath
extends RefCounted

const RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"
const MAX_SKILL_LEVEL := 3

static var _rules_cache: Dictionary = {}


static func clamp_skill_level(level_value: int) -> int:
	return clampi(level_value, 0, MAX_SKILL_LEVEL)


static func classic_get_power(power_roll: int, def_power_roll: int, level_value: int, train_level := 3) -> int:
	return WizardCombatMath.classic_get_power(power_roll, def_power_roll, level_value, train_level)


static func classic_get_power13(input_power: int, def_power_roll: int, level_value: int, train_level := 3) -> int:
	return WizardCombatMath.classic_get_power13(input_power, def_power_roll, level_value, train_level)


static func damage_with_rolls(skill_id: String, spiritual_stat_roll: int, level_value: int, magic_power_roll: int, def_power_roll: int) -> int:
	var train_level := int(_skill_rule(skill_id).get("train_level", 3))
	return maxi(1, spiritual_stat_roll + classic_get_power(magic_power_roll, def_power_roll, level_value, train_level))


static func damage(skill_id: String, spiritual_stat_roll: int, level_value: int) -> int:
	var rule := _skill_rule(skill_id)
	return damage_with_rolls(skill_id, spiritual_stat_roll, level_value, int(rule.get("magic_power_base", 0)), int(rule.get("power_base", 0)))


static func healing_with_rolls(skill_id: String, spiritual_stat_roll: int, level_value: int, magic_power_roll: int, def_power_roll: int) -> int:
	var train_level := int(_skill_rule(skill_id).get("train_level", 3))
	return maxi(1, classic_get_power(magic_power_roll, def_power_roll, level_value, train_level) + spiritual_stat_roll * 2)


static func healing(skill_id: String, spiritual_stat_roll: int, level_value: int) -> int:
	var rule := _skill_rule(skill_id)
	return healing_with_rolls(skill_id, spiritual_stat_roll, level_value, int(rule.get("magic_power_base", 0)), int(rule.get("power_base", 0)))


static func poison_power(level_value: int, spiritual_stat_roll: int, green_poison := true) -> int:
	var rule := _skill_rule("taoist.poison")
	var base := 40 if green_poison else 30
	return classic_get_power13(base, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3))) + spiritual_stat_roll * 2


static func poison_duration(level_value: int, power: int) -> int:
	return roundi(float(clamp_skill_level(level_value)) / 3.0 * (float(power) / 20.0))


static func status_duration(skill_id: String, level_value: int, spiritual_stat_roll: int) -> int:
	var rule := _skill_rule(skill_id)
	var base := 40 if skill_id == "taoist.entrapment" else 30
	return classic_get_power13(base, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3))) + spiritual_stat_roll * 3


static func buff_power(skill_id: String, level_value: int, spiritual_stat_roll: int) -> int:
	var rule := _skill_rule(skill_id)
	return classic_get_power13(60, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3))) + spiritual_stat_roll * 10


static func revelation_duration(level_value: int, spiritual_stat_roll: int) -> int:
	var rule := _skill_rule("taoist.revelation")
	return classic_get_power13(spiritual_stat_roll * 2 + 30, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3)))


static func revelation_succeeds(level_value: int, random_0_to_5: int) -> bool:
	return random_0_to_5 <= clamp_skill_level(level_value) + 3


static func summon_profile(skill_id: String, skill_level_value: int, owner_level: int, spiritual_power: int) -> Dictionary:
	var level := clamp_skill_level(skill_level_value)
	var rule := _skill_rule(skill_id)
	var divine_beast := skill_id == "taoist.summon_divine_beast"
	var safe_owner_level := maxi(1, owner_level)
	var safe_spiritual := maxi(1, spiritual_power)
	var hp := (100 + safe_owner_level * 6 + level * 40) if divine_beast else (50 + safe_owner_level * 4 + level * 25)
	var attack_min := maxi(1, int(safe_spiritual * (0.55 if divine_beast else 0.35)) + level * 2)
	var attack_max := maxi(attack_min, int(safe_spiritual * (1.05 if divine_beast else 0.75)) + level * 3)
	return {
		"skill_id": skill_id,
		"skill_level": level,
		"summon_level": level,
		"summon_exp_level": level,
		"summon_count": int(rule.get("default_count", 1)),
		"amulet_cost": int(rule.get("amulet_cost", 0)),
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
		"lifetime_seconds": float(_level_value(rule.get("lifetime_seconds_by_level", [864000]), level)),
		"leash_range": float(rule.get("leash_range", 560.0)),
		"teleport_range": float(rule.get("teleport_range", 900.0)),
		"reject_when_owner_has_slave": bool(rule.get("reject_when_owner_has_slave", true)),
		"recall_existing_on_create_failure": bool(rule.get("recall_existing_on_create_failure", false)),
		"owner_death_rule": "expire",
		"combat_stats_status": "project_adapter_C_candidate",
		"confidence": str(rule.get("confidence", "B/C")),
		"formula_id": "%s.classic_magic_pas.summon.v2" % skill_id,
	}


static func profile_overrides(skill_id: String, level_value: int) -> Dictionary:
	var rule := _skill_rule(skill_id)
	if rule.is_empty():
		return {}
	var level := clamp_skill_level(level_value)
	var result := {
		"skill_level": level,
		"formula_id": "%s.classic_magic_pas.v2" % skill_id,
		"formula_source": "source.original_gameofmir.server_suite/M2Server/Magic.pas/TaoistCombatMath",
		"formula_group": str(rule.get("formula_group", "classic_special")),
		"confidence": str(rule.get("confidence", "B/C")),
		"source_status": str(rule.get("source_status", "classic_rule_with_crystal_value_candidate")),
	}
	for key: String in rule.keys():
		if key.ends_with("_by_level") and rule[key] is Array:
			result[key.trim_suffix("_by_level")] = _level_value(rule[key], level)
	for key: String in ["source_anchor", "service_spell_id", "attack_type", "duration_formula", "buff_power_formula", "area_radius_cells", "leash_range", "teleport_range", "amulet_cost"]:
		if rule.has(key):
			result[key] = rule[key]
	return result


static func _skill_rule(skill_id: String) -> Dictionary:
	return _rules().get("taoist", {}).get("skills", {}).get(skill_id, {})


static func _rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_rules_cache = parsed if parsed is Dictionary else {}
	return _rules_cache


static func _level_value(values: Array, level: int) -> Variant:
	return values[mini(level, values.size() - 1)] if not values.is_empty() else null
