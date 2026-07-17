class_name CasterSkillBehavior
extends RefCounted

const RULES_PATH := "res://assets/data/vanilla_176/profession_combat_rules.json"

static var _rules_cache: Dictionary = {}


static func resolve(skill_id: String, context: Dictionary) -> Dictionary:
	var stable_id := ProfessionRules.skill_id(skill_id)
	var level := clampi(int(context.get("skill_level", 0)), 0, 3)
	match stable_id:
		"wizard.repulsion_ring": return _repulsion(level, context)
		"wizard.temptation_light": return _temptation(level, context)
		"wizard.teleport": return _teleport(level, context)
		"wizard.magic_shield": return _magic_shield(level, context)
		"wizard.holy_word": return _holy_word(level, context)
		"taoist.poison": return _poison(level, context)
		"taoist.invisibility", "taoist.mass_invisibility": return _invisibility(stable_id, level, context)
		"taoist.magic_defense", "taoist.defense": return _defense(stable_id, level, context)
		"taoist.revelation": return _revelation(level, context)
		"taoist.entrapment": return _entrapment(level, context)
		"taoist.summon_skeleton", "taoist.summon_divine_beast": return _summon(stable_id, level, context)
	return {"skill_id": stable_id, "success": false, "failure_reason": "unsupported_behavior"}


static func _base(skill_id: String, operation: String, level: int) -> Dictionary:
	var rule := _rule(skill_id)
	var source_paths := ["M2Server/Magic.pas"]
	if skill_id == "wizard.magic_shield":
		source_paths.append("M2Server/ObjBase.pas")
	return {
		"skill_id": skill_id,
		"operation": operation,
		"skill_level": level,
		"formula_source": "source.original_gameofmir.server_suite",
		"source_priority": {"lane": "server_rules", "tier": "primary", "order": 0, "weight": 100},
		"source_original_paths": source_paths,
		"source_anchor": str(rule.get("source_anchor", "")),
		"source_status": str(rule.get("source_status", "classic_rule_with_crystal_value_candidate")),
		"confidence": str(rule.get("confidence", "B/C")),
		"behavior_contract": "caster_skill_behavior.v1",
		"success": true,
	}


static func _repulsion(level: int, context: Dictionary) -> Dictionary:
	var caster_level := int(context.get("caster_level", 1))
	var target_level := int(context.get("target_level", 1))
	var random_roll := int(context.get("random_0_to_19", 19))
	var success := WizardCombatMath.repulsion_succeeds(level, caster_level, target_level, random_roll)
	var result := _base("wizard.repulsion_ring", "knockback", level)
	result.success = success
	result.push_cells = WizardCombatMath.repulsion_push_cells(level, int(context.get("random_0_or_1", 0))) if success else 0
	result.push_distance = int(result.push_cells) * int(context.get("cell_size", 48))
	result.failure_reason = "" if success else "level_random_gate"
	return result


static func _temptation(level: int, context: Dictionary) -> Dictionary:
	var result := _base("wizard.temptation_light", "tame_monster", level)
	var rule := _rule("wizard.temptation_light")
	var caster_level := int(context.get("caster_level", 1))
	var target_level := int(context.get("target_level", 1))
	var target_hp := maxi(1, int(context.get("target_max_hp", 1)))
	var outer_bound := maxi(1, 4 - level)
	var hp_rate := int(rule.get("target_hp_rate", 1000))
	var hp_difficulty := int(target_hp / maxi(1, hp_rate))
	hp_difficulty = 2 if hp_difficulty <= 2 else hp_difficulty * 2
	var gates := [
		[not bool(context.get("target_is_player", false)), "player_target"],
		[int(context.get("outer_random", outer_bound - 1)) == 0, "initial_random_gate"],
		[int(context.get("coin_random", 1)) == 0, "coin_random_gate"],
		[target_level <= caster_level + int(rule.get("target_level_margin", 2)), "caster_level_gate"],
		[int(context.get("level_random", caster_level)) + level * 5 > target_level + int(rule.get("target_level_difficulty", 10)), "target_level_random_gate"],
		[not bool(context.get("target_no_tame", false)), "no_tame_target"],
		[not bool(context.get("target_is_undead", false)), "undead_target"],
		[target_level <= int(rule.get("max_target_level", 60)), "target_level_limit"],
		[int(context.get("owner_slave_count", 0)) < int(rule.get("max_slave_count", 5)), "slave_count_limit"],
		[not bool(context.get("target_master_is_caster", false)), "already_owned_target"],
		[int(context.get("hp_random", hp_difficulty - 1)) == 0, "target_hp_random_gate"],
	]
	for gate: Array in gates:
		if not bool(gate[0]):
			result.success = false
			result.failure_reason = str(gate[1])
			result.hp_random_bound = hp_difficulty
			return result
	var random_minutes := clampi(int(context.get("mutiny_random_minutes", 0)), 0, maxi(0, caster_level - 1))
	result.mutiny_minutes = random_minutes + 60 * int(caster_level / 10) + (level << 2) * 5
	result.duration_seconds = int(result.mutiny_minutes) * 60
	result.summon_level = level
	result.walk_speed_cap_ms = 1500 - level * 200
	result.hit_interval_cap_ms = 2000 - level * 200
	result.mark_no_tame = true
	result.previous_owner_hp_divisor_on_reassign = 10
	result.hp_random_bound = hp_difficulty
	result.failure_reason = ""
	return result


static func _teleport(level: int, context: Dictionary) -> Dictionary:
	var result := _base("wizard.teleport", "random_home_map_move", level)
	result.success = WizardCombatMath.teleport_succeeds(level, int(context.get("random_0_to_10", 10)))
	result.failure_reason = "" if result.success else "random_gate"
	return result


static func _magic_shield(level: int, context: Dictionary) -> Dictionary:
	var result := _base("wizard.magic_shield", "magic_shield", level)
	var shield_seconds := WizardCombatMath.shield_power(level, int(context.get("magic_stat_roll", 0)))
	result.duration_seconds = shield_seconds
	result.damage_remaining_ratio = float(level + 2) * 0.08
	result.damage_reduction = 1.0 - float(result.damage_remaining_ratio)
	result.reject_when_active = true
	return result


static func _holy_word(level: int, context: Dictionary) -> Dictionary:
	var result := _base("wizard.holy_word", "execute_undead", level)
	result.success = WizardCombatMath.holy_word_succeeds(level, int(context.get("caster_level", 1)), int(context.get("target_level", 1)), int(context.get("random_0_to_99", 99)), bool(context.get("target_is_undead", false)))
	result.failure_reason = "" if result.success else "undead_level_random_gate"
	return result


static func _poison(level: int, context: Dictionary) -> Dictionary:
	var green := str(context.get("poison_type", "green")) != "red"
	var power := TaoistCombatMath.poison_power(level, int(context.get("spiritual_stat_roll", 0)), green)
	var result := _base("taoist.poison", "poison_health" if green else "poison_armor", level)
	var anti_poison_bound := maxi(1, int(context.get("target_anti_poison", 0)) + 7)
	result.success = int(context.get("anti_poison_random", 0)) <= 6
	result.failure_reason = "" if result.success else "anti_poison_gate"
	result.anti_poison_random_bound = anti_poison_bound
	result.power = power
	result.duration_seconds = TaoistCombatMath.poison_duration(level, power) if result.success else 0
	result.apply_delay_seconds = 1.0
	result.green_damage_interval_seconds = 2.5
	result.red_armor_rate_tenths = 12
	result.amulet_or_poison_cost = 1
	return result


static func _invisibility(skill_id: String, level: int, context: Dictionary) -> Dictionary:
	var result := _base(skill_id, "stealth_area" if skill_id.ends_with("mass_invisibility") else "stealth", level)
	result.duration_seconds = TaoistCombatMath.status_duration(skill_id, level, int(context.get("spiritual_stat_roll", 0)))
	result.area_radius_cells = 1 if skill_id.ends_with("mass_invisibility") else 0
	result.amulet_cost = 1
	return result


static func _defense(skill_id: String, level: int, context: Dictionary) -> Dictionary:
	var result := _base(skill_id, "magic_defense_buff" if skill_id.ends_with("magic_defense") else "physical_defense_buff", level)
	result.buff_power = TaoistCombatMath.buff_power(skill_id, level, int(context.get("spiritual_stat_roll", 0)))
	result.duration_seconds = int(result.buff_power)
	result.area_radius_cells = 3
	result.amulet_cost = 1
	return result


static func _revelation(level: int, context: Dictionary) -> Dictionary:
	var result := _base("taoist.revelation", "show_target_health", level)
	result.success = TaoistCombatMath.revelation_succeeds(level, int(context.get("random_0_to_5", 5)))
	result.duration_seconds = TaoistCombatMath.revelation_duration(level, int(context.get("spiritual_stat_roll", 0))) if result.success else 0
	result.failure_reason = "" if result.success else "random_gate"
	return result


static func _entrapment(level: int, context: Dictionary) -> Dictionary:
	var result := _base("taoist.entrapment", "root_ring", level)
	result.duration_seconds = TaoistCombatMath.status_duration("taoist.entrapment", level, int(context.get("spiritual_stat_roll", 0)))
	result.ring_event_count = 8
	result.amulet_cost = 1
	return result


static func _summon(skill_id: String, level: int, context: Dictionary) -> Dictionary:
	var result := _base(skill_id, "summon", level)
	result.merge(TaoistCombatMath.summon_profile(skill_id, level, int(context.get("owner_level", 1)), int(context.get("spiritual_stat_roll", 1))), true)
	return result


static func _rule(skill_id: String) -> Dictionary:
	var profession := "wizard" if skill_id.begins_with("wizard.") else "taoist"
	return _rules().get(profession, {}).get("skills", {}).get(skill_id, {})


static func _rules() -> Dictionary:
	if not _rules_cache.is_empty():
		return _rules_cache
	var file := FileAccess.open(RULES_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_rules_cache = parsed if parsed is Dictionary else {}
	return _rules_cache
