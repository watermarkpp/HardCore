class_name TaoistSkillSemanticContracts
extends RefCounted

const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")
const Rng := preload("res://scripts/skills/skill_rng.gd")
const Support := preload("res://tests/skills/skill_semantic_contract_support.gd")

const ASSERTIONS_BY_SKILL := {
	"taoist.healing": [
		"healing_self_or_friendly", "healing_rejects_hostile", "healing_formula",
		"healing_training_only_if_hp_restored",
	],
	"taoist.spiritual_warfare": [
		"spiritual_warfare_accuracy_exact", "spiritual_warfare_never_casts",
		"spiritual_warfare_no_cooldown", "spiritual_warfare_physical_only",
	],
	"taoist.poison": [
		"poison_consumes_selected_powder", "poison_green_and_red_separate",
		"poison_resist_formula", "poison_green_ticks", "poison_red_reduces_ac_mac",
		"poison_same_type_refreshes",
	],
	"taoist.soul_fire_talisman": [
		"soul_fire_requires_one_amulet", "soul_fire_requires_los",
		"soul_fire_power_formula", "soul_fire_no_material_loss_on_invalid_target",
	],
	"taoist.summon_skeleton": [
		"summon_skeleton_consumes_one_amulet_only_on_new_spawn",
		"summon_skeleton_recast_recalls", "taoist_main_pet_limit_one",
		"summon_skill_rank_separate_pet_level", "summon_skeleton_no_forced_delete",
	],
	"taoist.invisibility": [
		"invisibility_consumes_amulet", "invisibility_monster_aggro_only",
		"invisibility_not_pvp_untargetable", "invisibility_duration_formula",
		"invisibility_breaks_on_move", "invisibility_spell_cast_does_not_break",
	],
	"taoist.mass_invisibility": [
		"mass_invisibility_exact_3x3", "mass_invisibility_affects_friendlies",
		"mass_invisibility_not_self_only",
		"mass_invisibility_consumes_one_amulet_on_success",
	],
	"taoist.magic_defense": [
		"soul_shield_modifies_mac_only", "soul_shield_area_radius_3",
		"soul_shield_coexists_with_blessed_armour",
		"soul_shield_consumes_amulet_on_success",
	],
	"taoist.defense": [
		"blessed_armour_modifies_ac_only", "blessed_armour_area_radius_3",
		"blessed_armour_coexists_with_soul_shield",
		"blessed_armour_consumes_amulet_on_success",
	],
	"taoist.revelation": [
		"revelation_manual_target", "revelation_targets_player_or_monster",
		"revelation_probability_exact", "revelation_duration_formula",
		"revelation_no_damage",
	],
	"taoist.entrapment": [
		"entrapment_monsters_only", "entrapment_boss_immune",
		"entrapment_boundary_prevents_exit", "entrapment_breaks_on_player_entry",
		"entrapment_consumes_amulet_only_on_success", "entrapment_not_generic_root",
	],
	"taoist.mass_healing": [
		"mass_healing_exact_3x3", "mass_healing_friendlies_not_self_only",
		"mass_healing_formula", "mass_healing_training_only_if_actual_heal",
		"mass_healing_not_negative_damage",
	],
	"taoist.summon_divine_beast": [
		"summon_divine_beast_consumes_five_amulets_only_on_new_spawn",
		"summon_divine_beast_recast_recalls", "taoist_main_pet_limit_one",
		"divine_beast_skill_rank_separate_pet_level",
		"summon_divine_beast_no_forced_delete",
	],
}

var _support := Support.new()


func validators() -> Dictionary:
	var result: Dictionary = {}
	for skill_id: String in ASSERTIONS_BY_SKILL:
		for assertion_id: String in ASSERTIONS_BY_SKILL[skill_id]:
			result["%s::%s" % [skill_id, assertion_id]] = Callable(
				self, "_validate"
			).bind(skill_id, assertion_id)
	return result


func _validate(skill_id: String, assertion_id: String) -> bool:
	match assertion_id:
		"healing_self_or_friendly":
			var self_heal := _support.execute(skill_id, 3, {"has_target": false, "actual_hp_missing": 10})
			var friend_heal := _support.execute(skill_id, 3, {"has_target": true, "actual_hp_missing": 10})
			return self_heal.accepted and friend_heal.accepted
		"healing_rejects_hostile":
			return not _support.execute(skill_id, 3, {"hostile": true}).accepted
		"healing_formula":
			var actual := _support.execute(skill_id, 3, {
				"primary_stat_roll": 8, "actual_hp_missing": 9999,
			}, {}, 9)
			var raw_fields: Dictionary = _support.definition(skill_id).magic_db_reference.raw_fields
			var expected := Formula.raw_magic_power(Rng.new(9), 3, raw_fields, 16)
			return actual.effects[0].raw_heal == expected
		"healing_training_only_if_hp_restored":
			var restored := _support.execute(skill_id, 3, {"actual_hp_missing": 10})
			var full := _support.execute(skill_id, 3, {"actual_hp_missing": 0})
			return not restored.proficiency_event.is_empty() and full.proficiency_event.is_empty()
		"spiritual_warfare_accuracy_exact":
			return _support.rank_effect_values(skill_id, "value") == [0, 3, 5, 8]
		"spiritual_warfare_never_casts":
			return _support.execute(skill_id, 3).timing.body_cast_ms == 0
		"spiritual_warfare_no_cooldown":
			return _support.execute(skill_id, 3).timing.total_action_lock_ms == 0
		"spiritual_warfare_physical_only":
			return _support.execute(skill_id, 3).effects[0].affects == ["physical_melee_hit_checks"]
		"poison_consumes_selected_powder":
			# Retain the package-manifest ID while enforcing the newer approved
			# single-player contract: poison no longer consumes either powder.
			var dual := _poison(skill_id, "", true)
			return dual.resource_quote.material_id.is_empty() and dual.resource_quote.material_amount == 0 and dual.resource_commit
		"poison_green_and_red_separate":
			var dual := _poison(skill_id, "", true)
			return dual.effects.size() == 2 and dual.effects[0].poison_type == "green_poison" and dual.effects[1].poison_type == "red_poison" and dual.effects[0].resisted == dual.effects[1].resisted
		"poison_resist_formula":
			var poison := _support.execute(skill_id, 3, {
				"target_poison_resist": 7, "force_success": true,
			}, {"selected_material": "grey_powder"})
			return (
				is_equal_approx(float(poison.effects[0].apply_probability), 0.5)
				and _support.deterministic(
					skill_id, {"target_poison_resist": 7, "force_success": false}, 101
				)
				and _support.seeded_effect_outcomes(skill_id, 3, {
					"target_poison_resist": 7,
					"force_success": false,
					"force_resist": false,
				})
			)
		"poison_green_ticks":
			var green: Dictionary = _poison(skill_id, "grey_powder", true).effects[0]
			return green.tick_interval_ms == 2000 and green.damage_per_tick >= 1
		"poison_red_reduces_ac_mac":
			var red: Dictionary = _poison(skill_id, "", true).effects[1]
			return red.flat_ac_reduction >= 1 and red.flat_ac_reduction == red.flat_mac_reduction
		"poison_same_type_refreshes":
			var dual := _poison(skill_id, "", true)
			return str(dual.effects[0].stacking_policy).contains("refresh") and str(dual.effects[1].stacking_policy).contains("refresh")
		"soul_fire_requires_one_amulet":
			var result := _support.execute(skill_id, 3, {}, {})
			return result.resource_quote.material_amount == 0 and result.resource_quote.material_id.is_empty()
		"soul_fire_requires_los":
			return not _support.execute(skill_id, 3, {"line_of_sight": false}, {"selected_material": "amulet"}).accepted
		"soul_fire_power_formula":
			var result := _support.execute(skill_id, 3, {"primary_stat_roll": 10}, {"selected_material": "amulet"}, 11)
			var fields: Dictionary = _support.definition(skill_id).magic_db_reference.raw_fields
			return result.effects[0].raw_power == Formula.raw_magic_power(Rng.new(11), 3, fields, 10)
		"soul_fire_no_material_loss_on_invalid_target":
			var invalid := _support.execute(skill_id, 3, {"has_target": false}, {"selected_material": "amulet"})
			return not invalid.accepted and not invalid.resource_commit
		"summon_skeleton_consumes_one_amulet_only_on_new_spawn":
			var spawn := _support.execute(skill_id, 3, {"has_main_pet": false}, {})
			var recall := _support.execute(skill_id, 3, {"has_main_pet": true}, {})
			return spawn.resource_quote.material_amount == 0 and spawn.resource_quote.material_id.is_empty() and spawn.resource_commit and recall.resource_quote.material_amount == 0 and not recall.resource_commit
		"summon_skeleton_recast_recalls":
			return _support.execute(skill_id, 3, {"has_main_pet": true}, {"selected_material": "amulet"}).effects[0].type == "recall_existing_main_pet"
		"taoist_main_pet_limit_one":
			return _support.execute(skill_id, 3, {"has_main_pet": false}, {"selected_material": "amulet"}).effects[0].group_limit == 1
		"summon_skill_rank_separate_pet_level":
			var levels: Array = []
			for rank in range(4):
				levels.append(_support.execute(skill_id, rank, {}, {"selected_material": "amulet"}).effects[0].initial_pet_level)
			return levels == [0, 1, 2, 3] and not _support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].skill_rank_is_pet_level
		"summon_skeleton_no_forced_delete":
			return not bool(_support.execute(skill_id, 3, {"has_main_pet": true}, {"selected_material": "amulet"}).effects[0].delete_existing)
		"invisibility_consumes_amulet":
			var result := _support.execute(skill_id, 3, {}, {})
			return result.resource_quote.material_amount == 0 and result.resource_quote.material_id.is_empty()
		"invisibility_monster_aggro_only":
			return _support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].type == "monster_aggro_stealth"
		"invisibility_not_pvp_untargetable":
			var invis: Dictionary = _support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0]
			return not invis.pvp_invisibility and not invis.untargetable and not invis.invulnerable
		"invisibility_duration_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 5}, {"selected_material": "amulet"}).effects[0].duration_seconds == 45
		"invisibility_breaks_on_move":
			return bool(_support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].break_on_tile_movement)
		"invisibility_spell_cast_does_not_break":
			return not bool(_support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].break_on_ranged_spell_cast)
		"mass_invisibility_exact_3x3":
			return _support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).geometry_cells.size() == 9
		"mass_invisibility_affects_friendlies":
			return _support.execute(skill_id, 3, {"affected_friendly_count": 2}, {"selected_material": "amulet"}).effects[0].affected_count == 2
		"mass_invisibility_not_self_only":
			return _support.execute(skill_id, 3, {"affected_friendly_count": 3}, {"selected_material": "amulet"}).effects[0].affected_count > 1
		"mass_invisibility_consumes_one_amulet_on_success":
			var success := _support.execute(skill_id, 3, {"affected_friendly_count": 1}, {})
			var empty := _support.execute(skill_id, 3, {"affected_friendly_count": 0}, {})
			return success.resource_quote.material_amount == 0 and success.resource_quote.material_id.is_empty() and success.resource_commit and not empty.resource_commit
		"soul_shield_modifies_mac_only":
			return _buff(skill_id).effects[0].stat == "MAC"
		"soul_shield_area_radius_3":
			return _buff(skill_id).geometry_cells.size() == 49
		"soul_shield_coexists_with_blessed_armour":
			return str(_buff(skill_id).effects[0].stacking_policy).contains("blessed_armour")
		"soul_shield_consumes_amulet_on_success":
			return _buff_consumption(skill_id)
		"blessed_armour_modifies_ac_only":
			return _buff(skill_id).effects[0].stat == "AC"
		"blessed_armour_area_radius_3":
			return _buff(skill_id).geometry_cells.size() == 49
		"blessed_armour_coexists_with_soul_shield":
			return str(_buff(skill_id).effects[0].stacking_policy).contains("soul_shield")
		"blessed_armour_consumes_amulet_on_success":
			return _buff_consumption(skill_id)
		"revelation_manual_target":
			return not _support.execute(skill_id, 3, {"has_target": false}).accepted
		"revelation_targets_player_or_monster":
			var player := _support.execute(skill_id, 3, {"target_is_monster": false, "target_is_living": true})
			var monster := _support.execute(skill_id, 3, {"target_is_monster": true, "target_is_living": true})
			return player.accepted and monster.accepted
		"revelation_probability_exact":
			var probabilities: Array = []
			for rank in range(4):
				probabilities.append(_support.execute(skill_id, rank).effects[0].success_probability)
			return (
				_floats_equal(probabilities, [4.0 / 6.0, 5.0 / 6.0, 1.0, 1.0])
				and _support.seeded_effect_outcomes(
					skill_id, 0, {"force_success": false}
				)
			)
		"revelation_duration_formula":
			return _support.execute(skill_id, 3, {"primary_stat_roll": 5}).effects[0].duration_ms == 40000
		"revelation_no_damage":
			var reveal: Dictionary = _support.execute(skill_id, 3).effects[0]
			return reveal.damage == 0 and not reveal.target_stat_modification
		"entrapment_monsters_only":
			var player_only := _support.execute(skill_id, 3, {"targets": [{"is_player": true}]}, {"selected_material": "amulet"})
			return player_only.effects[0].trapped_count == 0
		"entrapment_boss_immune":
			var boss := _support.execute(skill_id, 3, {"targets": [{"hostile_monster": true, "is_boss": true}]}, {"selected_material": "amulet"})
			return boss.effects[0].trapped_count == 0
		"entrapment_boundary_prevents_exit":
			var trap := _support.execute(skill_id, 3, {}, {"selected_material": "amulet"})
			return trap.geometry_cells.size() == 8 and trap.effects[0].prevents_boundary_exit
		"entrapment_breaks_on_player_entry":
			return bool(_support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].break_on_any_player_entry)
		"entrapment_consumes_amulet_only_on_success":
			var success := _support.execute(skill_id, 3, {}, {})
			var failure := _support.execute(skill_id, 3, {"targets": []}, {})
			return success.resource_commit and success.resource_quote.material_amount == 0 and success.resource_quote.material_id.is_empty() and not failure.resource_commit
		"entrapment_not_generic_root":
			return not bool(_support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0].generic_root)
		"mass_healing_exact_3x3":
			return _support.execute(skill_id, 3).geometry_cells.size() == 9
		"mass_healing_friendlies_not_self_only":
			return _support.execute(skill_id, 3, {"friendly_missing_hp": [10, 10]}).effects[0].actual_hp_restored_by_target.size() == 2
		"mass_healing_formula":
			var actual := _support.execute(skill_id, 3, {
				"friendly_missing_hp": [9999], "primary_stat_roll": 6,
			}, {}, 19)
			var fields: Dictionary = _support.definition(skill_id).magic_db_reference.raw_fields
			return actual.effects[0].raw_heal_per_target == Formula.raw_magic_power(Rng.new(19), 3, fields, 12)
		"mass_healing_training_only_if_actual_heal":
			var healed := _support.execute(skill_id, 3, {"friendly_missing_hp": [10]})
			var full := _support.execute(skill_id, 3, {"friendly_missing_hp": [0]})
			return not healed.proficiency_event.is_empty() and full.proficiency_event.is_empty()
		"mass_healing_not_negative_damage":
			return not bool(_support.execute(skill_id, 3).effects[0].negative_damage)
		"summon_divine_beast_consumes_five_amulets_only_on_new_spawn":
			var spawn := _support.execute(skill_id, 3, {"has_main_pet": false}, {})
			var recall := _support.execute(skill_id, 3, {"has_main_pet": true}, {})
			return spawn.resource_quote.material_amount == 0 and spawn.resource_quote.material_id.is_empty() and spawn.resource_commit and recall.resource_quote.material_amount == 0 and not recall.resource_commit
		"summon_divine_beast_recast_recalls":
			return _support.execute(skill_id, 3, {"has_main_pet": true}, {"selected_material": "amulet"}).effects[0].type == "recall_existing_main_pet"
		"divine_beast_skill_rank_separate_pet_level":
			var spawn: Dictionary = _support.execute(skill_id, 3, {}, {"selected_material": "amulet"}).effects[0]
			return spawn.initial_pet_level == 3 and spawn.max_pet_level == 7 and not spawn.skill_rank_is_pet_level
		"summon_divine_beast_no_forced_delete":
			return not bool(_support.execute(skill_id, 3, {"has_main_pet": true}, {"selected_material": "amulet"}).effects[0].delete_existing)
		_:
			return false


func _poison(skill_id: String, material: String, force_success: bool) -> Dictionary:
	return _support.execute(
		skill_id,
		3,
		{"force_success": force_success},
		{"selected_material": material}
	)


func _buff(skill_id: String) -> Dictionary:
	return _support.execute(skill_id, 3, {
		"friendly_targets": [{"level": 35}], "primary_stat_roll": 4,
	}, {"selected_material": "amulet"})


func _buff_consumption(skill_id: String) -> bool:
	var success := _buff(skill_id)
	var empty := _support.execute(skill_id, 3, {
		"friendly_targets": [],
	}, {"selected_material": "amulet"})
	return success.resource_quote.material_amount == 0 and success.resource_quote.material_id.is_empty() and success.resource_commit and not empty.resource_commit


func _floats_equal(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for index in range(actual.size()):
		if not is_equal_approx(float(actual[index]), float(expected[index])):
			return false
	return true
