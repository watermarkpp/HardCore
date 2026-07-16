class_name WizardCombatMath
extends RefCounted

const RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"
const MAX_SKILL_LEVEL := 3

static var _rules_cache: Dictionary = {}


static func clamp_skill_level(level_value: int) -> int:
	return clampi(level_value, 0, MAX_SKILL_LEVEL)


static func classic_get_power(power_roll: int, def_power_roll: int, level_value: int, train_level := 3) -> int:
	var divisor := maxi(1, train_level + 1)
	return roundi(float(power_roll) / float(divisor) * float(clamp_skill_level(level_value) + 1)) + def_power_roll


static func classic_get_power13(input_power: int, def_power_roll: int, level_value: int, train_level := 3) -> int:
	var divisor := maxi(1, train_level + 1)
	var fixed_third := float(input_power) / 3.0
	var scaled_part := float(input_power) - fixed_third
	return roundi(scaled_part / float(divisor) * float(clamp_skill_level(level_value) + 1) + fixed_third + float(def_power_roll))


static func damage_with_rolls(skill_id: String, stat_roll: int, level_value: int, magic_power_roll: int, def_power_roll: int, target_is_undead := false) -> int:
	var result := maxi(1, stat_roll + classic_get_power(magic_power_roll, def_power_roll, level_value, int(_skill_rule(skill_id).get("train_level", 3))))
	if skill_id == "wizard.lightning" and target_is_undead:
		result = roundi(float(result) * 1.5)
	elif skill_id == "wizard.hell_lightning" and not target_is_undead:
		result = maxi(1, int(result / 10))
	return result


# Compatibility entry point. Deterministic tests use the lower bound of the
# B/C MagicInfo candidate; combat runtimes can pass actual rolls above.
static func damage(skill_id: String, magic_stat_roll: int, level_value: int) -> int:
	var rule := _skill_rule(skill_id)
	return damage_with_rolls(skill_id, magic_stat_roll, level_value, int(rule.get("magic_power_base", 0)), int(rule.get("power_base", 0)))


static func fire_wall_duration(level_value: int, magic_stat_roll := 0) -> float:
	var rule := _skill_rule("wizard.fire_wall")
	return float(classic_get_power(10, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3))) + int(maxi(0, magic_stat_roll) / 2))


static func shield_power(level_value: int, magic_stat_roll: int) -> int:
	var rule := _skill_rule("wizard.magic_shield")
	return classic_get_power(magic_stat_roll + 15, int(rule.get("power_base", 0)), level_value, int(rule.get("train_level", 3)))


static func teleport_succeeds(level_value: int, random_0_to_10: int) -> bool:
	return random_0_to_10 < clamp_skill_level(level_value) * 2 + 4


static func repulsion_push_cells(level_value: int, random_0_or_1: int) -> int:
	return 1 + maxi(0, clamp_skill_level(level_value) - 1) + clampi(random_0_or_1, 0, 1)


static func repulsion_succeeds(level_value: int, caster_level: int, target_level: int, random_0_to_19: int) -> bool:
	return random_0_to_19 < 6 + clamp_skill_level(level_value) * 3 + caster_level - target_level


static func holy_word_succeeds(level_value: int, caster_level: int, target_level: int, random_0_to_99: int, target_is_undead: bool) -> bool:
	return target_is_undead and random_0_to_99 < clamp_skill_level(level_value) * 7 + 15 + caster_level - target_level


static func profile_overrides(skill_id: String, level_value: int) -> Dictionary:
	var rule := _skill_rule(skill_id)
	if rule.is_empty():
		return {}
	var level := clamp_skill_level(level_value)
	var result := {
		"skill_level": level,
		"formula_id": "%s.classic_magic_pas.v2" % skill_id,
		"formula_source": "source.original_gameofmir.server_suite/M2Server/Magic.pas/WizardCombatMath",
		"formula_group": str(rule.get("formula_group", "classic_special")),
		"confidence": str(rule.get("confidence", "B/C")),
		"source_status": str(rule.get("source_status", "classic_rule_with_crystal_value_candidate")),
	}
	for key: String in rule.keys():
		if key.ends_with("_by_level") and rule[key] is Array:
			result[key.trim_suffix("_by_level")] = _level_value(rule[key], level)
	for key: String in ["source_anchor", "service_spell_id", "shape", "duration_formula", "shield_power_formula", "success_formula", "undead_damage_multiplier", "living_damage_divisor"]:
		if rule.has(key):
			result[key] = rule[key]
	return result


static func _skill_rule(skill_id: String) -> Dictionary:
	return _rules().get("wizard", {}).get("skills", {}).get(skill_id, {})


static func _rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_rules_cache = parsed if parsed is Dictionary else {}
	return _rules_cache


static func _level_value(values: Array, level: int) -> Variant:
	return values[mini(level, values.size() - 1)] if not values.is_empty() else null
