extends Node


func _ready() -> void:
	var repulsion := CasterSkillBehavior.resolve("wizard.repulsion_ring", {
		"skill_level": 3, "caster_level": 30, "target_level": 28,
		"random_0_to_19": 16, "random_0_or_1": 1,
	})
	assert(repulsion.success and repulsion.push_distance_gu == 4.0)
	assert(not repulsion.has("push_cells") and not repulsion.has("push_distance"))
	var repulsion_fail := CasterSkillBehavior.resolve("wizard.repulsion_ring", {
		"skill_level": 3, "caster_level": 30, "target_level": 28, "random_0_to_19": 17,
	})
	assert(not repulsion_fail.success and repulsion_fail.failure_reason == "level_random_gate")

	var temptation := CasterSkillBehavior.resolve("wizard.temptation_light", {
		"skill_level": 3, "caster_level": 30, "target_level": 28, "target_max_hp": 1500,
		"outer_random": 0, "coin_random": 0, "level_random": 40, "hp_random": 0,
		"mutiny_random_minutes": 10, "owner_slave_count": 0,
	})
	assert(temptation.success and temptation.mutiny_minutes == 250 and temptation.duration_seconds == 15000)
	assert(temptation.walk_speed_cap_ms == 900 and temptation.hit_interval_cap_ms == 1400)
	assert(temptation.summon_level == 3 and temptation.mark_no_tame and temptation.previous_owner_hp_divisor_on_reassign == 10)
	assert(temptation.source_priority.tier == "primary" and temptation.source_original_paths == ["M2Server/Magic.pas"])
	var undead_temptation := CasterSkillBehavior.resolve("wizard.temptation_light", {
		"skill_level": 3, "caster_level": 30, "target_level": 28, "target_max_hp": 1500,
		"outer_random": 0, "coin_random": 0, "level_random": 40, "hp_random": 0,
		"target_is_undead": true,
	})
	assert(not undead_temptation.success and undead_temptation.failure_reason == "undead_target")
	var owned_temptation := CasterSkillBehavior.resolve("wizard.temptation_light", {
		"skill_level": 3, "caster_level": 30, "target_level": 28, "target_max_hp": 1500,
		"outer_random": 0, "coin_random": 0, "level_random": 40, "hp_random": 0,
		"target_master_is_caster": true,
	})
	assert(not owned_temptation.success and owned_temptation.failure_reason == "already_owned_target")

	var teleport := CasterSkillBehavior.resolve("wizard.teleport", {"skill_level": 2, "random_0_to_10": 7})
	assert(teleport.success and teleport.operation == "random_home_map_move")
	var shield := CasterSkillBehavior.resolve("wizard.magic_shield", {"skill_level": 3, "magic_stat_roll": 30})
	assert(shield.duration_seconds == 45 and is_equal_approx(shield.damage_remaining_ratio, 0.4))
	assert(is_equal_approx(shield.damage_reduction, 0.6) and shield.reject_when_active)
	assert(shield.source_original_paths == ["M2Server/Magic.pas", "M2Server/ObjBase.pas"])
	var holy_word := CasterSkillBehavior.resolve("wizard.holy_word", {
		"skill_level": 3, "caster_level": 40, "target_level": 35,
		"random_0_to_99": 40, "target_is_undead": true,
	})
	assert(holy_word.success and holy_word.operation == "execute_undead")

	var green_poison := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3, "spiritual_stat_roll": 30, "poison_type": "green",
	})
	var red_poison := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3, "spiritual_stat_roll": 30, "poison_type": "red",
	})
	assert(green_poison.operation == "poison_health" and green_poison.power == 100 and green_poison.duration_seconds == 5)
	assert(red_poison.operation == "poison_armor" and red_poison.power == 90 and red_poison.duration_seconds == 4)
	assert(green_poison.apply_delay_seconds == 1.0 and green_poison.green_damage_interval_seconds == 2.5)
	assert(red_poison.red_armor_rate_tenths == 12)
	var resisted_poison := CasterSkillBehavior.resolve("taoist.poison", {
		"skill_level": 3, "spiritual_stat_roll": 30, "poison_type": "green",
		"target_anti_poison": 5, "anti_poison_random": 7,
	})
	assert(not resisted_poison.success and resisted_poison.failure_reason == "anti_poison_gate" and resisted_poison.duration_seconds == 0)

	var invisibility := CasterSkillBehavior.resolve("taoist.invisibility", {"skill_level": 3, "spiritual_stat_roll": 20})
	var mass_invisibility := CasterSkillBehavior.resolve("taoist.mass_invisibility", {"skill_level": 3, "spiritual_stat_roll": 20})
	assert(invisibility.duration_seconds == 90 and invisibility.area_radius_cells == 0)
	assert(mass_invisibility.duration_seconds == 90 and mass_invisibility.area_radius_cells == 1)
	var magic_defense := CasterSkillBehavior.resolve("taoist.magic_defense", {"skill_level": 3, "spiritual_stat_roll": 20})
	var defense := CasterSkillBehavior.resolve("taoist.defense", {"skill_level": 3, "spiritual_stat_roll": 20})
	assert(magic_defense.operation == "magic_defense_buff" and magic_defense.buff_power == 260)
	assert(defense.operation == "physical_defense_buff" and defense.duration_seconds == 260)

	var revelation := CasterSkillBehavior.resolve("taoist.revelation", {"skill_level": 0, "spiritual_stat_roll": 20, "random_0_to_5": 3})
	assert(revelation.success and revelation.duration_seconds == 35)
	var entrapment := CasterSkillBehavior.resolve("taoist.entrapment", {"skill_level": 3, "spiritual_stat_roll": 20})
	assert(entrapment.duration_seconds == 100 and entrapment.ring_event_count == 8)
	var summon := CasterSkillBehavior.resolve("taoist.summon_divine_beast", {"skill_level": 3, "owner_level": 35, "spiritual_stat_roll": 30})
	assert(summon.operation == "summon" and summon.lifetime_seconds == 864000.0 and summon.amulet_cost == 5)

	var unsupported := CasterSkillBehavior.resolve("wizard.fireball", {})
	assert(not unsupported.success and unsupported.failure_reason == "unsupported_behavior")
	print("CASTER_SKILL_BEHAVIOR_PASS: 14 special stable-ID behavior contracts loaded")
	get_tree().quit(0)
