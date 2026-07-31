class_name SkillRuntimeRouter
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillCastResultScript := preload("res://scripts/skills/skill_cast_result.gd")
const SkillTargetServiceScript := preload("res://scripts/skills/skill_target_service.gd")
const SkillResourceServiceScript := preload("res://scripts/skills/skill_resource_service.gd")
const SkillGeometryServiceScript := preload("res://scripts/skills/skill_geometry_service.gd")
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")
const WarriorRuntimeScript := preload("res://scripts/skills/runtimes/warrior_skill_runtime.gd")
const WizardRuntimeScript := preload("res://scripts/skills/runtimes/wizard_skill_runtime.gd")
const TaoistRuntimeScript := preload("res://scripts/skills/runtimes/taoist_skill_runtime.gd")

const RUNTIME_CONTRACT_ID := "skills.runtime_router.cn_mir2_176.v1"
const CANONICAL_PRODUCTION_DEFAULT := true
const WARRIOR_MELEE_MODIFIER_CONTRACT_ID := "gameplay.warrior.melee_modifiers.v1"


static func execute(request: Variant) -> Dictionary:
	var request_validation := SkillCastRequestScript.validate(request)
	if not bool(request_validation.get("valid", false)):
		return SkillCastResultScript.failure("", str(request_validation.get("reason", "invalid_request")))
	var skill_id := SkillDataLoaderScript.stable_skill_id(str(request.get("skill_id", "")))
	var definition := SkillDataLoaderScript.skill(skill_id)
	if definition.is_empty():
		return SkillCastResultScript.failure(skill_id, "unknown_skill")
	var target_validation := SkillTargetServiceScript.validate(
		definition,
		request.get("target_context", {})
	)
	if not bool(target_validation.get("valid", false)):
		return SkillCastResultScript.failure(skill_id, str(target_validation.get("reason", "invalid_target")))
	var resource_quote := SkillResourceServiceScript.quote(
		definition,
		int(request.get("rank", 0)),
		request.get("resource_context", {}),
		request.get("target_context", {})
	)
	if not bool(resource_quote.get("valid", false)):
		return SkillCastResultScript.failure(skill_id, str(resource_quote.get("reason", "insufficient_resource")))
	var rng := SkillRngScript.new(int(request.get("seed", 0)))
	var plan: Dictionary
	match str(definition.get("class", "")):
		"warrior":
			plan = WarriorRuntimeScript.execute(definition, request, rng)
		"wizard":
			plan = WizardRuntimeScript.execute(definition, request, rng)
		"taoist":
			plan = TaoistRuntimeScript.execute(definition, request, rng)
		_:
			return SkillCastResultScript.failure(skill_id, "unknown_profession")
	if not bool(plan.get("accepted", true)):
		return SkillCastResultScript.failure(skill_id, str(plan.get("reason", "runtime_rejected")))
	plan["timing"] = definition.get("timing", {}).duplicate(true)
	plan["geometry"] = definition.get("geometry", {}).duplicate(true)
	plan["target"] = definition.get("target", {}).duplicate(true)
	plan["resource"] = resource_quote.duplicate(true)
	plan["mechanics"] = definition.get("mechanics", {}).duplicate(true)
	plan["geometry_cells"] = SkillGeometryServiceScript.cells(
		definition,
		request.get("origin_tile", Vector2i.ZERO),
		request.get("facing", Vector2i.DOWN),
		request.get("target_context", {}).get("target_tile", Vector2i.ZERO)
	)
	var result := SkillCastResultScript.success(skill_id, plan)
	result["runtime_contract"] = RUNTIME_CONTRACT_ID
	result["source_ruleset_id"] = SkillDataLoaderScript.RULESET_ID
	result["resource_quote"] = resource_quote
	result["geometry_cells"] = plan.geometry_cells
	result["ignored_client_claims"] = {
		"damage": request.get("client_claimed_damage"),
		"success": request.get("client_claimed_success"),
	}
	return result


static func resolve_warrior_melee_modifiers(request: Dictionary) -> Dictionary:
	var valid_melee_swing := bool(request.get("valid_melee_swing", false))
	var body_mode := str(request.get("body_mode", "normal"))
	if body_mode not in ["normal", "thrust", "half_moon", "fire"]:
		body_mode = "normal"
	var basic_learned := bool(request.get("basic_sword_learned", false))
	var slaying_learned := bool(request.get("slaying_learned", false))
	var basic_rank := clampi(int(request.get("basic_sword_rank", 0)), 0, 3)
	var slaying_rank := clampi(int(request.get("slaying_rank", 0)), 0, 3)
	var rng := SkillRngScript.new(int(request.get("seed", 0)))
	var flat_dc_bonus := 0
	var flat_accuracy_bonus := 0
	var proficiency_events: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var slaying_proc := false
	var slaying_proc_roll_count := 0

	if basic_learned:
		var basic_definition := SkillDataLoaderScript.skill("warrior.basic_swordsmanship")
		var basic_plan := WarriorRuntimeScript.execute(
			basic_definition,
			{
				"rank": basic_rank,
				"target_context": {"valid_melee_swing": valid_melee_swing},
			},
			rng
		)
		for raw_effect: Variant in basic_plan.get("effects", []):
			if raw_effect is Dictionary:
				var effect: Dictionary = raw_effect
				effects.append(effect.duplicate(true))
				if str(effect.get("type", "")) == "passive_stat_modifier":
					flat_accuracy_bonus += int(effect.get("value", 0))
		var basic_event := str(basic_plan.get("proficiency_event", ""))
		if not basic_event.is_empty():
			proficiency_events.append({
				"skill_id": "warrior.basic_swordsmanship",
				"event": basic_event,
			})

	if slaying_learned and valid_melee_swing:
		slaying_proc_roll_count = 1
		var slaying_definition := SkillDataLoaderScript.skill("warrior.slaying_swordsmanship")
		var slaying_context := {
			"valid_melee_swing": true,
			"has_target": true,
			"force_proc": bool(request.get("force_slaying_proc", false)),
			"force_no_proc": bool(request.get("force_no_slaying_proc", false)),
		}
		var slaying_plan := WarriorRuntimeScript.execute(
			slaying_definition,
			{"rank": slaying_rank, "target_context": slaying_context},
			rng
		)
		for raw_effect: Variant in slaying_plan.get("effects", []):
			if not raw_effect is Dictionary:
				continue
			var effect: Dictionary = raw_effect
			effects.append(effect.duplicate(true))
			if str(effect.get("type", "")) != "melee_proc_modifier":
				continue
			slaying_proc = bool(effect.get("proc", false))
			if slaying_proc:
				flat_dc_bonus += int(effect.get("flat_dc_bonus", 0))
				flat_accuracy_bonus += int(effect.get("flat_accuracy_bonus", 0))
		var slaying_event := str(slaying_plan.get("proficiency_event", ""))
		if not slaying_event.is_empty():
			proficiency_events.append({
				"skill_id": "warrior.slaying_swordsmanship",
				"event": slaying_event,
			})

	return {
		"contract_id": WARRIOR_MELEE_MODIFIER_CONTRACT_ID,
		"source_ruleset_id": SkillDataLoaderScript.RULESET_ID,
		"valid_melee_swing": valid_melee_swing,
		"body_mode": body_mode,
		"flat_dc_bonus_before_body_formula": flat_dc_bonus,
		"flat_accuracy_bonus": flat_accuracy_bonus,
		"slaying_proc": slaying_proc,
		"slaying_proc_roll_count": slaying_proc_roll_count,
		"slaying_effect_skill_id": (
			"warrior.slaying_swordsmanship" if slaying_proc else ""
		),
		"modifier_order": [
			"base_damage",
			"flat_dc_bonus_before_body_formula",
			"selected_body_skill_formula",
		],
		"scope": "all_hits_of_selected_melee_action",
		"body_mode_agnostic": true,
		"effects": effects,
		"proficiency_events": proficiency_events,
	}


static func integration_descriptor() -> Dictionary:
	return {
		"runtime_contract": RUNTIME_CONTRACT_ID,
		"warrior_melee_modifier_contract": WARRIOR_MELEE_MODIFIER_CONTRACT_ID,
		"warrior_melee_modifier_entrypoint": "SkillRuntimeRouter.resolve_warrior_melee_modifiers",
		"production_default": CANONICAL_PRODUCTION_DEFAULT,
		"entrypoint": "SkillRuntimeRouter.execute",
		"request_contract": SkillCastRequestScript.CONTRACT_ID,
		"result_contract": SkillCastResultScript.CONTRACT_ID,
		"requires_integration_adapters": [
			"combat_resolution",
			"inventory_resources",
			"map_tile_geometry",
			"target_relations",
			"buff_runtime",
			"taoist_main_pet",
		],
	}
