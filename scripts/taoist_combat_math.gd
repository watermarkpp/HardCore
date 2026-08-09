class_name TaoistCombatMath
extends RefCounted

const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const SkillRankResolverScript := preload(
	"res://scripts/skills/skill_rank_resolver.gd"
)

const RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"
const SUMMON_BASELINE_PATH := "res://assets/data/vanilla_176/taoist_summon_baseline.json"
## Base data max rank; effective cast rank extends via skills.rank_extension.v1.
const MAX_SKILL_LEVEL := 3

static var _rules_cache: Dictionary = {}
static var _summon_baseline_cache: Dictionary = {}


static func clamp_skill_level(level_value: int) -> int:
	return SkillRankResolverScript.safe_effective_rank(level_value)


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
	return WizardCombatMath.classic_round(float(clamp_skill_level(level_value)) / 3.0 * (float(power) / 20.0))


static func anti_poison_random_bound(target_anti_poison: int) -> int:
	return maxi(1, target_anti_poison + 7)


static func poison_succeeds(target_anti_poison: int, random_roll: int) -> bool:
	return random_roll >= 0 and random_roll < anti_poison_random_bound(target_anti_poison) and random_roll <= 6


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
	return random_0_to_5 <= mini(
		5,
		clamp_skill_level(level_value) + 3
	)


static func summon_profile(skill_id: String, skill_level_value: int, owner_level: int, spiritual_power: int) -> Dictionary:
	var level := SkillRankResolverScript.summon_pet_level(skill_level_value)
	var rule := _skill_rule(skill_id)
	var summon_id := "divine_beast" if skill_id == "taoist.summon_divine_beast" else "skeleton"
	var divine_beast := summon_id == "divine_beast"
	var template := summon_template(summon_id)
	var stats := summon_stats(summon_id, level)
	var attack_interval_ms := effective_summon_attack_interval_ms(summon_id, level)
	var move_interval_ms := effective_summon_move_interval_ms(summon_id, level)
	# Retain the legacy parameters so old callers remain source-compatible. The
	# verified database baseline deliberately does not scale with owner stats.
	var _ignored_owner_level := owner_level
	var _ignored_spiritual_power := spiritual_power
	return {
		"skill_id": skill_id,
		"skill_level": level,
		"summon_level": level,
		"summon_exp_level": level,
		"summon_count": int(rule.get("default_count", 1)),
		"amulet_cost": 0,
		"summon_id": summon_id,
		"display_name": str(template.get("display_name", "神兽" if summon_id == "divine_beast" else "变异骷髅")),
		"attack_type": str(template.get("attack_type", rule.get("attack_type", "physical"))),
		"max_hp": int(stats.get("max_hp", 1)),
		"attack_min": int(stats.get("dc_min", 1)),
		"attack_max": int(stats.get("dc_max", 1)),
		"ac_min": int(stats.get("ac_min", 0)),
		"ac_max": int(stats.get("ac_max", 0)),
		"mac_min": int(stats.get("mac_min", 0)),
		"mac_max": int(stats.get("mac_max", 0)),
		"accuracy": int(stats.get("accuracy", 1)),
		"agility": int(stats.get("agility", 1)),
		"monster_level": int(template.get("monster_level", 1)),
		"max_pet_level": maximum_summon_pet_level(level),
		"pet_growth_exp": 0,
		"move_interval_ms": move_interval_ms,
		"attack_interval_ms": attack_interval_ms,
		"move_speed_gu_per_sec": 1000.0 / float(maxi(1, move_interval_ms)),
		"attack_range_gu": CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(72.0 if divine_beast else 48.0),
		"attack_interval": float(attack_interval_ms) / 1000.0,
		"aggro_radius_gu": CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(380.0 if divine_beast else 330.0),
		"lifetime_seconds": float(_level_value(rule.get("lifetime_seconds_by_level", [864000]), level)),
		"leash_range_gu": CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(float(rule.get("leash_range", 560.0))),
		"teleport_range_gu": CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(float(rule.get("teleport_range", 900.0))),
		"reject_when_owner_has_slave": bool(rule.get("reject_when_owner_has_slave", true)),
		"recall_existing_on_create_failure": bool(rule.get("recall_existing_on_create_failure", false)),
		"owner_death_rule": "expire",
		"combat_stats_status": "ORIGINAL_DATABASE_BINARY_VERIFIED",
		"confidence": "A",
		"formula_id": "%s.original_database_binary_verified.summon.v3" % skill_id,
		"growth_contract_id": str(_summon_baseline().get("contract_id", "")),
	}


static func maximum_summon_pet_level(skill_rank: int) -> int:
	## Existing summon combat level cap stays at 7 for every effective rank.
	return mini(7, 1 + 2 * clamp_skill_level(skill_rank))


static func summon_template(summon_id: String) -> Dictionary:
	var templates: Dictionary = _summon_baseline().get("templates", {})
	var value: Variant = templates.get(summon_id, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


static func summon_stats(summon_id: String, pet_level: int) -> Dictionary:
	var template := summon_template(summon_id)
	var base: Dictionary = template.get("base_stats", {})
	var level := clampi(pet_level, 0, 7)
	var hp_growth := WizardCombatMath.classic_round(
		(float(level) * 0.1 + 0.3) * float(base.get("hp", 1))
	) * level
	var dc_growth := WizardCombatMath.classic_round(
		(float(level) * 0.1 + 0.3) * 3.0 * float(level)
	)
	return {
		"pet_level": level,
		"max_hp": int(base.get("hp", 1)) + hp_growth,
		"dc_min": int(base.get("dc_min", 1)),
		"dc_max": int(base.get("dc_max", 1)) + dc_growth,
		"ac_min": int(base.get("ac_min", 0)),
		"ac_max": int(base.get("ac_max", 0)),
		"mac_min": int(base.get("mac_min", 0)),
		"mac_max": int(base.get("mac_max", 0)),
		"accuracy": int(base.get("accuracy", 1)),
		"agility": int(base.get("agility", 1)),
	}


static func summon_growth_threshold(summon_id: String, current_pet_level: int) -> int:
	var template := summon_template(summon_id)
	var growth: Dictionary = _summon_baseline().get("growth_contract", {})
	var extras: Array = growth.get("level_extra", [0, 0, 50, 100, 200, 300, 600, 1200])
	var index := clampi(current_pet_level, 0, maxi(0, extras.size() - 1))
	var extra := int(extras[index]) if not extras.is_empty() else 0
	return 15 * int(template.get("monster_level", 1)) + 100 + extra


static func effective_summon_attack_interval_ms(summon_id: String, skill_rank: int) -> int:
	return _summon_timing_value(summon_id, "attack_interval", skill_rank, 1500)


static func effective_summon_move_interval_ms(summon_id: String, skill_rank: int) -> int:
	return _summon_timing_value(summon_id, "move_interval", skill_rank, 1500)


static func summon_name_color_index(pet_level: int) -> int:
	var growth: Dictionary = _summon_baseline().get("growth_contract", {})
	var colors: Array = growth.get("name_color_palette_indices", [])
	if colors.is_empty():
		return 255
	return int(colors[clampi(pet_level, 0, colors.size() - 1)])


static func summon_baseline_contract_id() -> String:
	return str(_summon_baseline().get("contract_id", ""))


static func clear_cache_for_tests() -> void:
	_rules_cache = {}
	_summon_baseline_cache = {}


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
			var semantic := SkillRankResolverScript.SEMANTIC_LINEAR
			if (
				key.contains("cooldown")
				or key.contains("lifetime")
			):
				semantic = SkillRankResolverScript.SEMANTIC_TIMING_CONSTANT
			result[key.trim_suffix("_by_level")] = (
				SkillRankResolverScript.value(rule[key], level, semantic)
			)
	for key: String in ["source_anchor", "service_spell_id", "attack_type", "duration_formula", "apply_delay_ms", "buff_power_formula", "area_radius_cells", "leash_range", "teleport_range", "amulet_cost"]:
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


static func _summon_baseline() -> Dictionary:
	if not _summon_baseline_cache.is_empty():
		return _summon_baseline_cache
	var file := FileAccess.open(SUMMON_BASELINE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_summon_baseline_cache = parsed if parsed is Dictionary else {}
	return _summon_baseline_cache


static func _summon_timing_value(
	summon_id: String,
	timing_key: String,
	skill_rank: int,
	fallback_ms: int
) -> int:
	var template := summon_template(summon_id)
	var timing: Dictionary = template.get("effective_timing_ms_by_skill_rank", {})
	var values: Variant = timing.get(timing_key, [])
	if not values is Array or values.is_empty():
		return fallback_ms
	## Pet timing is timing semantics: constant at the base-max rank values.
	return SkillRankResolverScript.timing_int(values, skill_rank)


static func _level_value(values: Array, level: int) -> Variant:
	return values[mini(level, values.size() - 1)] if not values.is_empty() else null
