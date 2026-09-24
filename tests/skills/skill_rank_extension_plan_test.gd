extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const PlanContract := preload("res://scripts/skills/skill_execution_plan_contract.gd")
const LegacyAdapter := preload("res://scripts/skills/legacy_skill_adapter.gd")
const WarriorMath := preload("res://scripts/warrior_combat_math.gd")
const WizardMath := preload("res://scripts/wizard_combat_math.gd")
const TaoistMath := preload("res://scripts/taoist_combat_math.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)

	# Cast request accepts effective ranks above 3; only absurd input is capped.
	var request_rank5 := Request.create(
		"wizard.lightning",
		5,
		40,
		Vector2i.ZERO,
		Vector2i.DOWN,
		_context(),
		_resources(),
		7
	)
	assert(Request.validate(request_rank5).valid)
	assert(request_rank5.rank == 5)
	var request_rank1000 := Request.create("wizard.lightning", 1000, 40)
	assert(Request.validate(request_rank1000).valid)
	assert(request_rank1000.rank == 1000)
	var request_absurd := Request.create("wizard.lightning", 1000001, 40)
	assert(Request.validate(request_absurd).valid)
	assert(request_absurd.rank == 1000000)
	assert(
		not Request.validate({
			"contract_id": Request.CONTRACT_ID,
			"skill_id": "wizard.lightning",
			"rank": 1000001,
		}).valid
	)

	# Legacy adapter is a source view only: rank >3 returns no legacy record
	# and never gates or truncates the runtime effective rank.
	assert(LegacyAdapter.get_skill("wizard.lightning", 4).is_empty())
	assert(int(LegacyAdapter.get_skill("wizard.lightning", 3).get("skillLevel", -1)) == 3)
	assert(_plan("wizard.lightning", 4).accepted)

	# Rank 4+ strengthens effects, but resources stay at rank 3.
	assert(ResourceService.quote(Loader.skill("wizard.lightning"), 3, {"mana": 100, "materials": {}}).mp_cost == 15)
	assert(ResourceService.quote(Loader.skill("wizard.lightning"), 4, {"mana": 100, "materials": {}}).mp_cost == 15)
	assert(ResourceService.quote(Loader.skill("wizard.lightning"), 5, {"mana": 100, "materials": {}}).mp_cost == 15)

	# Cross-profession representative rank4/rank5 growth.
	assert(is_equal_approx(float(_plan("warrior.fire_sword", 4).effects[0].damage_multiplier), 2.86))
	assert(is_equal_approx(float(_plan("warrior.fire_sword", 5).effects[0].damage_multiplier), 3.146))
	var slaying5 := Router.resolve_warrior_melee_modifiers({
		"body_mode": "normal",
		"basic_sword_learned": true,
		"basic_sword_rank": 3,
		"slaying_learned": true,
		"slaying_rank": 5,
		"valid_melee_swing": true,
		"slaying_proc_roll": 0,
	})
	assert(slaying5.slaying_proc and slaying5.slaying_proc_denominator == 0)
	assert(slaying5.flat_damage_bonus_after_body_formula == 12)
	assert(slaying5.flat_accuracy_bonus == 14)
	assert(slaying5.proficiency_events.is_empty())
	assert(int(_plan("warrior.basic_swordsmanship", 4).effects[0].value) == 12)
	assert(int(_plan("warrior.basic_swordsmanship", 5).effects[0].value) == 15)
	assert(int(_plan("taoist.spiritual_warfare", 4).effects[0].value) == 11)
	assert(int(_plan("taoist.spiritual_warfare", 5).effects[0].value) == 14)
	assert(is_equal_approx(float(_plan("warrior.thrusting", 4).effects[0].multiplier), float(_plan("warrior.thrusting", 3).effects[0].multiplier) * 1.1))
	assert(is_equal_approx(float(_plan("warrior.thrusting", 4).effects[1].multiplier), float(_plan("warrior.thrusting", 3).effects[1].multiplier) * 1.1))
	var lightning3 := _plan("wizard.lightning", 3)
	var lightning5 := _plan("wizard.lightning", 5)
	assert(int(lightning5.effects[0].raw_power) > int(lightning3.effects[0].raw_power))
	for skill_id: String in ["wizard.fireball", "wizard.hellfire", "wizard.great_fireball", "wizard.exploding_flame", "wizard.fire_wall", "wizard.laser", "wizard.hell_lightning", "wizard.ice_storm"]:
		var rank3 := _plan(skill_id, 3)
		var rank4 := _plan(skill_id, 4)
		assert(rank3.accepted and rank4.accepted, skill_id)
		assert(int(rank4.effects[0].raw_power) == roundi(float(rank3.effects[0].raw_power) * 1.1), skill_id)
		assert(rank4.resource_quote.mp_cost == rank3.resource_quote.mp_cost, skill_id)
	assert(int(lightning5.effects[0].raw_power_after_race) == roundi(float(lightning3.effects[0].raw_power_after_race) * 1.21))
	var talisman3 := _plan("taoist.soul_fire_talisman", 3)
	var talisman4 := _plan("taoist.soul_fire_talisman", 4)
	assert(int(talisman4.effects[0].raw_power) == roundi(float(talisman3.effects[0].raw_power) * 1.1))
	var heal_context := _context()
	heal_context["hostile"] = false
	var heal3 := _plan_with_context("taoist.healing", 3, heal_context)
	var heal4 := _plan_with_context("taoist.healing", 4, heal_context)
	assert(heal3.accepted and heal4.accepted)
	assert(int(heal4.effects[0].raw_heal) == roundi(float(heal3.effects[0].raw_heal) * 1.1))
	assert(heal4.resource_quote.mp_cost == heal3.resource_quote.mp_cost)
	var mass_heal3 := _plan_with_context("taoist.mass_healing", 3, heal_context)
	var mass_heal4 := _plan_with_context("taoist.mass_healing", 4, heal_context)
	assert(mass_heal3.accepted and mass_heal4.accepted)
	assert(int(mass_heal4.effects[0].raw_heal_per_target) == roundi(float(mass_heal3.effects[0].raw_heal_per_target) * 1.1))
	for skill_id: String in ["warrior.wild_rush", "wizard.repulsion_ring", "wizard.temptation_light", "wizard.teleport", "wizard.magic_shield", "wizard.holy_word", "taoist.invisibility", "taoist.mass_invisibility", "taoist.magic_defense", "taoist.defense", "taoist.revelation", "taoist.entrapment"]:
		var base := _plan(skill_id, 3)
		var injected := _plan(skill_id, 5)
		assert(base.accepted == injected.accepted, skill_id)
		assert(base.get("reason", "") == injected.get("reason", ""), skill_id)
		assert(base.get("effects", []) == injected.get("effects", []), skill_id)
		assert(int(base.get("resource_quote", {}).get("mp_cost", 0)) == int(injected.get("resource_quote", {}).get("mp_cost", 0)), skill_id)
	assert(is_equal_approx(float(_plan("wizard.magic_shield", 4).effects[0].damage_reduction), 0.6))
	assert(is_equal_approx(float(_plan("wizard.magic_shield", 5).effects[0].damage_reduction), 0.6))
	assert(int(_plan("taoist.poison", 5).effects[0].duration_seconds) == 30)
	var summon5 := _plan("taoist.summon_skeleton", 5)
	assert(int(summon5.effects[0].initial_pet_level) == 3)
	assert(int(summon5.effects[0].group_limit) == 2)
	assert(int(summon5.effects[0].max_pet_level) == 7)
	var summon100 := _plan("taoist.summon_divine_beast", 100)
	assert(int(summon100.effects[0].initial_pet_level) == 3)
	assert(int(summon100.effects[0].max_pet_level) == 7)

	# Probability-style success fields cap at 1.0.
	assert(is_equal_approx(float(_plan("wizard.teleport", 5).effects[0].success_probability), 10.0 / 11.0))
	assert(is_equal_approx(float(_plan("taoist.revelation", 5).effects[0].success_probability), 1.0))

	# Combat-math safety boundaries.
	assert(WarriorMath.slaying_proc_cycle(3) == 4)
	assert(WarriorMath.slaying_proc_cycle(5) == 4)
	assert(WarriorMath.slaying_proc_cycle(1000) == 4)
	assert(is_equal_approx(WarriorMath.slaying_proc_probability(5), 0.35))
	assert(is_equal_approx(WarriorMath.fire_sword_multiplier(3), 2.6))
	assert(is_equal_approx(WarriorMath.fire_sword_multiplier(5), 3.146))
	assert(WizardMath.teleport_succeeds(5, 10))
	assert(not WizardMath.teleport_succeeds(1, 10))
	assert(WizardMath.classic_get_power(8, 0, 3) == 8)
	assert(TaoistMath.maximum_summon_pet_level(3) == 7)
	assert(TaoistMath.maximum_summon_pet_level(5) == 7)
	assert(TaoistMath.maximum_summon_pet_level(1000) == 7)
	assert(TaoistMath.poison_duration(3, 40) == 2)

	# 0..3 regression exacts through the canonical resource/runtime chain.
	assert(ResourceService.quote(Loader.skill("wizard.fireball"), 3, {"mana": 100, "materials": {}}).mp_cost == 9)
	assert(ResourceService.quote(Loader.skill("wizard.lightning"), 0, {"mana": 100, "materials": {}}).mp_cost == 9)
	assert(is_equal_approx(float(_plan("warrior.thrusting", 3).effects[1].multiplier), 1.0))

	# Canonical plan freezes effective rank and effect snapshot.
	var shield_request5 := Request.create(
		"wizard.magic_shield",
		5,
		40,
		Vector2i.ZERO,
		Vector2i.DOWN,
		_context(),
		_resources(),
		11
	)
	var plan5 := Router.build_canonical_plan(shield_request5, {})
	assert(bool(plan5.get("rejection", {}).get("accepted", false)))
	assert(int(plan5.get("effective_rank", -1)) == 3)
	var hash5 := str(plan5.get("plan_hash", ""))
	var plan5_actions := PlanContract._canonicalize(plan5.get("gameplay_actions", []))
	var shield_request3 := shield_request5.duplicate(true)
	shield_request3["rank"] = 3
	var plan3 := Router.build_canonical_plan(shield_request3, {})
	assert(bool(plan3.get("rejection", {}).get("accepted", false)))
	assert(int(plan3.get("effective_rank", -1)) == 3)
	assert(plan5_actions == PlanContract._canonicalize(plan3.get("gameplay_actions", [])))
	assert(str(plan5.get("plan_hash", "")) == hash5)
	assert(PlanContract.verify_immutable(plan5, hash5).valid)
	# Mutating the original request after the plan is built changes nothing.
	shield_request5["rank"] = 3
	assert(str(plan5.get("plan_hash", "")) == hash5)
	assert(int(plan5.get("effective_rank", -1)) == 3)

	print(
		"SKILL_RANK_EXTENSION_PLAN_PASS: typed rank>3 effects, rank3 resources, "
		+ "excluded skills frozen and immutable canonical plans"
	)
	get_tree().quit()


func _plan(skill_id: String, rank: int) -> Dictionary:
	return _plan_with_context(skill_id, rank, _context())


func _plan_with_context(skill_id: String, rank: int, context: Dictionary) -> Dictionary:
	return Router._plan(Request.create(
		skill_id,
		rank,
		40,
		Vector2i.ZERO,
		Vector2i.RIGHT,
		context,
		_resources(),
		31
	))


func _context() -> Dictionary:
	return {
		"has_target": true,
		"line_of_sight": true,
		"hostile": true,
		"friendly": false,
		"target_tile": Vector2i(8, 8),
		"target_level": 1,
		"target_is_boss": false,
		"target_immovable": false,
		"target_is_monster": true,
		"target_is_undead": true,
		"target_tameable": true,
		"target_max_hp": 200,
		"target_is_living": true,
		"current_pet_count": 0,
		"forced_temptation_outcome": "tamed",
		"force_proc": true,
		"force_success": true,
		"valid_melee_swing": true,
		"eligible_target_count": 4,
		"charge_consumed": true,
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"destination_tile": Vector2i(12, 12),
		"targets": [{"level": 1, "hostile_monster": true, "force_success": true}],
		"actual_hp_missing": 100,
		"friendly_missing_hp": [100],
		"friendly_targets": [{"level": 35}],
		"affected_friendly_count": 1,
		"primary_stat_roll": 10,
		"spawn_tile_valid": true,
		"has_main_pet": false,
	}


func _resources() -> Dictionary:
	return {
		"mana": 9999,
		"materials": {
			"amulet": 999,
			"grey_powder": 999,
			"yellow_powder": 999,
		},
		"selected_material": "grey_powder",
	}
