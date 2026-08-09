extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const Request := preload("res://scripts/skills/skill_cast_request.gd")
const Router := preload("res://scripts/skills/skill_runtime_router.gd")
const ResourceService := preload("res://scripts/skills/skill_resource_service.gd")
const PlanContract := preload("res://scripts/skills/skill_execution_plan_contract.gd")
const Policy := preload("res://scripts/skills/taoist_support_policy.gd")
const Formula := preload("res://scripts/skills/formulas/mir2_skill_formula.gd")
const Rng := preload("res://scripts/skills/skill_rng.gd")

const DUAL_DEFENSE_CONTRACT_ID := "skills.taoist.dual_defense_cast.v1"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(Loader.reload_data().valid)
	_verify_dual_quote_single_transaction()
	_verify_dual_quote_invalid_partner()
	_verify_dual_runtime_plan()
	_verify_canonical_plan_survival()
	_verify_canonical_support_metadata_survival()
	_verify_single_learned_plan_unchanged()
	print(
		"TAOIST_DUAL_DEFENSE_CONTRACT_PASS: one quote transaction, per-rank "
		+ "durations/effects, canonical metadata survival"
	)
	get_tree().quit(0)


func _verify_dual_quote_single_transaction() -> void:
	var defense := Loader.skill("taoist.defense")
	var resources := {"mana": 999, "materials": {}}
	var dual_context := {
		"dual_defense_context": {
			"partner_skill_id": "taoist.magic_defense",
			"partner_rank": 7,
		},
	}
	## defense rank 5 = 8 + (8-6)*2 = 12; magic_defense rank 7 =
	## 8 + (8-6)*4 = 16. Sum must be one quote.
	var quote := ResourceService.quote(defense, 5, resources, dual_context)
	assert(quote.valid)
	assert(quote.mp_cost == 28)
	assert(quote.dual_defense)
	assert(quote.combined_cast_contract_id == DUAL_DEFENSE_CONTRACT_ID)
	assert(quote.combined_skill_ids == ["taoist.magic_defense", "taoist.defense"])
	assert(quote.mp_components.size() == 2)
	assert(quote.mp_components[0].skill_id == "taoist.magic_defense")
	assert(quote.mp_components[0].rank == 7 and quote.mp_components[0].mp_cost == 16)
	assert(quote.mp_components[1].skill_id == "taoist.defense")
	assert(quote.mp_components[1].rank == 5 and quote.mp_components[1].mp_cost == 12)
	var committed := ResourceService.committed_context(resources, quote)
	assert(committed.mana == 999 - 28)
	var insufficient := ResourceService.quote(
		defense,
		5,
		{"mana": 27, "materials": {}},
		dual_context
	)
	assert(not insufficient.valid and insufficient.reason == "insufficient_mana")
	assert(insufficient.mp_cost == 28)


func _verify_dual_quote_invalid_partner() -> void:
	var defense := Loader.skill("taoist.defense")
	var resources := {"mana": 999, "materials": {}}
	var bogus := ResourceService.quote(
		defense,
		5,
		resources,
		{
			"dual_defense_context": {
				"partner_skill_id": "taoist.nonexistent",
				"partner_rank": 3,
			},
		}
	)
	assert(not bogus.valid and bogus.reason == "unknown_skill")
	assert(bogus.mp_cost == 0)
	var same_skill := ResourceService.quote(
		defense,
		5,
		resources,
		{
			"dual_defense_context": {
				"partner_skill_id": "taoist.defense",
				"partner_rank": 3,
			},
		}
	)
	assert(not same_skill.valid)
	assert(same_skill.reason == "invalid_combined_defense_partner")


func _verify_dual_runtime_plan() -> void:
	var context := _dual_context()
	var plan := _plan("taoist.defense", context, 5)
	assert(plan.accepted and plan.effect_success)
	assert(plan.effects.size() == 2)
	var mac_effect: Dictionary = plan.effects[0]
	var ac_effect: Dictionary = plan.effects[1]
	assert(mac_effect.stat == "MAC" and ac_effect.stat == "AC")
	assert(mac_effect.skill_id == "taoist.magic_defense")
	assert(mac_effect.rank == 7)
	assert(mac_effect.buff_id == "buff.taoist.soul_shield_mac")
	assert(ac_effect.skill_id == "taoist.defense")
	assert(ac_effect.rank == 5)
	assert(ac_effect.buff_id == "buff.taoist.blessed_armour_ac")
	assert(mac_effect.value == 5 and ac_effect.value == 5)
	assert(mac_effect.affected_count == 2 and ac_effect.affected_count == 2)
	assert(mac_effect.target_instance_ids.has(55) and mac_effect.target_instance_ids.has(101))
	assert(mac_effect.combined_defense)
	assert(ac_effect.combined_cast_contract_id == DUAL_DEFENSE_CONTRACT_ID)
	assert(plan.combined_skill_ids == ["taoist.magic_defense", "taoist.defense"])
	assert(plan.combined_cast_contract_id == DUAL_DEFENSE_CONTRACT_ID)
	var quote: Dictionary = plan.resource_quote
	assert(quote.mp_cost == 28 and quote.dual_defense)
	assert(quote.mp_components.size() == 2)
	var geometry: Dictionary = plan.support_area_geometry
	assert(geometry.shape == "chebyshev_area" and geometry.cell_count == 49)
	assert(geometry.affected_count == 2)
	assert(plan.geometry_cells.size() == 49)

	## Per-skill durations: MAC uses magic_defense's effective rank, AC uses
	## defense's effective rank, in a fixed MAC-then-AC order regardless of
	## which skill was clicked.
	var seed_rng := Rng.new(31)
	var expected_mac_duration := _expected_duration(seed_rng, 7, 4)
	var expected_ac_duration := _expected_duration(seed_rng, 5, 4)
	assert(expected_mac_duration != expected_ac_duration)
	assert(mac_effect.duration_seconds == expected_mac_duration)
	assert(ac_effect.duration_seconds == expected_ac_duration)

	var clicked_mac_context := _dual_context()
	clicked_mac_context["dual_defense_context"] = {
		"partner_skill_id": "taoist.defense",
		"partner_rank": 5,
	}
	var clicked_mac_plan := _plan("taoist.magic_defense", clicked_mac_context, 7)
	assert(clicked_mac_plan.accepted)
	assert(clicked_mac_plan.effects[0].stat == "MAC")
	assert(clicked_mac_plan.effects[0].rank == 7)
	assert(clicked_mac_plan.effects[0].duration_seconds == expected_mac_duration)
	assert(clicked_mac_plan.effects[1].stat == "AC")
	assert(clicked_mac_plan.effects[1].rank == 5)
	assert(clicked_mac_plan.effects[1].duration_seconds == expected_ac_duration)


func _verify_canonical_plan_survival() -> void:
	var request := _request("taoist.defense", _dual_context(), 5)
	var plan := Router.build_canonical_plan(request, {})
	var rejection: Dictionary = plan.get("rejection", {})
	assert(bool(rejection.get("accepted", false)))
	assert(plan.combined_skill_ids == ["taoist.magic_defense", "taoist.defense"])
	assert(plan.combined_cast_contract_id == DUAL_DEFENSE_CONTRACT_ID)
	var resource_cost: Dictionary = plan.resource_cost
	assert(resource_cost.mp_cost == 28)
	assert(resource_cost.mp_components.size() == 2)
	assert(resource_cost.mp_components[0].rank == 7)
	assert(resource_cost.mp_components[1].rank == 5)
	assert(resource_cost.combined_cast_contract_id == DUAL_DEFENSE_CONTRACT_ID)
	var hash_before := str(plan.get("plan_hash", ""))
	assert(PlanContract.verify_immutable(plan, hash_before).valid)


func _verify_canonical_support_metadata_survival() -> void:
	var dual_request := _request("taoist.defense", _dual_context(), 5)
	var dual_plan := Router.build_canonical_plan(dual_request, {})
	assert(
		dual_plan.support_area_geometry is Dictionary
		and not dual_plan.support_area_geometry.is_empty()
	)
	assert(dual_plan.support_area_geometry.shape == "chebyshev_area")
	assert(dual_plan.support_area_geometry.cell_count == 49)
	assert(not dual_plan.has("support_targeting"))
	assert(PlanContract.verify_immutable(dual_plan, dual_plan.plan_hash).valid)

	var heal_context := {
		"has_target": false,
		"line_of_sight": true,
		"friendly": true,
		"hostile": false,
		"caster_ground_position_gu": Vector2(0, 0),
		"primary_stat_roll": 8,
		"friendly_candidates": [
			Policy.make_candidate(55, true, 40, 100, Vector2(0, 0), 40),
			Policy.make_candidate(101, false, 5, 100, Vector2(1, 0), 7),
		],
	}
	var heal_request := Request.create(
		"taoist.healing",
		3,
		40,
		Vector2i.ZERO,
		Vector2i.DOWN,
		heal_context,
		{"mana": 999, "materials": {}},
		23
	)
	var fallback_target := Node2D.new()
	var heal_plan := Router.build_canonical_plan(
		heal_request,
		{
			"runtime_map_id": -1,
			"fallback_target_actor": fallback_target,
		}
	)
	assert(bool(heal_plan.get("rejection", {}).get("accepted", false)))
	assert(
		heal_plan.support_targeting is Dictionary
		and not heal_plan.support_targeting.is_empty()
	)
	assert(heal_plan.support_targeting.contract_id == Policy.CONTRACT_ID)
	assert(int(heal_plan.support_targeting.selected.instance_id) == 101)
	assert(not heal_plan.has("support_area_geometry"))
	assert(PlanContract.verify_immutable(heal_plan, heal_plan.plan_hash).valid)
	fallback_target.free()


func _verify_single_learned_plan_unchanged() -> void:
	## Legacy single-skill path: no candidate contract, no dual context.
	var single_context := {
		"has_target": true,
		"line_of_sight": true,
		"friendly": true,
		"hostile": false,
		"target_tile": Vector2i(0, 0),
		"primary_stat_roll": 4,
		"friendly_targets": [
			{"level": 35, "target_instance_id": 55},
		],
	}
	var legacy_single := _plan("taoist.defense", single_context, 3)
	assert(legacy_single.accepted and legacy_single.effects.size() == 1)
	assert(not legacy_single.has("combined_skill_ids"))
	assert(not legacy_single.has("combined_cast_contract_id"))
	assert(not legacy_single.has("support_targeting"))
	assert(not legacy_single.has("support_area_geometry"))
	assert(legacy_single.resource_quote.mp_cost == 8)
	var request := _request("taoist.defense", single_context, 3)
	var canonical := Router.build_canonical_plan(request, {})
	assert(not canonical.has("combined_skill_ids"))
	assert(not canonical.has("combined_cast_contract_id"))
	assert(not canonical.has("support_targeting"))
	assert(not canonical.has("support_area_geometry"))
	assert(int(canonical.get("resource_cost", {}).get("mp_cost", 0)) == 8)


func _dual_context() -> Dictionary:
	return {
		"has_target": true,
		"line_of_sight": true,
		"friendly": true,
		"hostile": false,
		"target_tile": Vector2i(0, 0),
		"caster_ground_position_gu": Vector2(0, 0),
		"primary_stat_roll": 4,
		"friendly_candidates": [
			Policy.make_candidate(55, true, 100, 100, Vector2(0, 0), 35),
			Policy.make_candidate(101, false, 100, 100, Vector2(0, 1), 7),
		],
		"dual_defense_context": {
			"partner_skill_id": "taoist.magic_defense",
			"partner_rank": 7,
		},
	}


func _expected_duration(rng: RefCounted, rank: int, sc_roll: int) -> int:
	return maxi(
		1,
		int(floor(float(Formula.get_power13(rng, rank, 60) + 10 * sc_roll) / 10.0))
	)


func _plan(skill_id: String, context: Dictionary, rank: int) -> Dictionary:
	return Router._plan(_request(skill_id, context, rank))


func _request(skill_id: String, context: Dictionary, rank: int) -> Dictionary:
	return Request.create(
		skill_id,
		rank,
		40,
		Vector2i.ZERO,
		Vector2i.DOWN,
		context,
		{"mana": 999, "materials": {}},
		31
	)
