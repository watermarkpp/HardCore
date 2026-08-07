class_name SkillRuntimeRouter
extends RefCounted

const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillTargetServiceScript := preload("res://scripts/skills/skill_target_service.gd")
const SkillResourceServiceScript := preload("res://scripts/skills/skill_resource_service.gd")
const SkillGeometryServiceScript := preload("res://scripts/skills/skill_geometry_service.gd")
const SkillRngScript := preload("res://scripts/skills/skill_rng.gd")
const WarriorRuntimeScript := preload("res://scripts/skills/runtimes/warrior_skill_runtime.gd")
const WizardRuntimeScript := preload("res://scripts/skills/runtimes/wizard_skill_runtime.gd")
const TaoistRuntimeScript := preload("res://scripts/skills/runtimes/taoist_skill_runtime.gd")
const SkillExecutionPlanContractScript := preload(
	"res://scripts/skills/skill_execution_plan_contract.gd"
)

const RUNTIME_CONTRACT_ID := "skills.runtime_router.cn_mir2_176.v1"
const CANONICAL_PRODUCTION_DEFAULT := true
const WARRIOR_MELEE_MODIFIER_CONTRACT_ID := "gameplay.warrior.melee_modifiers.v2"


static func _plan(request: Variant) -> Dictionary:
	## Q3-C: the SINGLE planner baseline used by the canonical formal entry
	## build_canonical_plan(). Pure: no resource commits, no cooldown commits,
	## no node creation, no release snapshot building.
	var request_validation := SkillCastRequestScript.validate(request)
	if not bool(request_validation.get("valid", false)):
		return {
			"accepted": false,
			"effect_success": false,
			"resource_commit": false,
			"reason": str(
				request_validation.get("reason", "invalid_request")
			),
		}
	var skill_id := SkillDataLoaderScript.stable_skill_id(str(request.get("skill_id", "")))
	var definition := SkillDataLoaderScript.skill(skill_id)
	if definition.is_empty():
		return {
			"accepted": false,
			"effect_success": false,
			"resource_commit": false,
			"skill_id": skill_id,
			"reason": "unknown_skill",
		}
	var target_validation := SkillTargetServiceScript.validate(
		definition,
		request.get("target_context", {})
	)
	if not bool(target_validation.get("valid", false)):
		return {
			"accepted": false,
			"effect_success": false,
			"resource_commit": false,
			"skill_id": skill_id,
			"reason": str(
				target_validation.get("reason", "invalid_target")
			),
		}
	var resource_quote := SkillResourceServiceScript.quote(
		definition,
		int(request.get("rank", 0)),
		request.get("resource_context", {}),
		request.get("target_context", {})
	)
	if not bool(resource_quote.get("valid", false)):
		return {
			"accepted": false,
			"effect_success": false,
			"resource_commit": false,
			"skill_id": skill_id,
			"reason": str(
				resource_quote.get("reason", "insufficient_resource")
			),
		}
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
			return {
				"accepted": false,
				"effect_success": false,
				"resource_commit": false,
				"skill_id": skill_id,
				"reason": "unknown_profession",
			}
	plan["skill_id"] = skill_id
	if not bool(plan.get("accepted", true)):
		plan["effect_success"] = false
		plan["resource_commit"] = false
		plan["reason"] = str(plan.get("reason", "runtime_rejected"))
		return plan
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
	plan["resource_quote"] = resource_quote
	return plan


## Q3-B: the SINGLE formal planner entry. GameRoot calls ONLY this function to
## obtain the canonical plan; the legacy execute() above is no longer called by
## the formal production chain (kept for compatibility/shadow).
static func build_canonical_plan(
	request: Variant,
	context: Dictionary = {}
) -> Dictionary:
	var request_validation := SkillCastRequestScript.validate(request)
	if not bool(request_validation.get("valid", false)):
		return _canonical_rejection_plan(
			"",
			str(request_validation.get("reason", "invalid_request")),
			request,
			context
		)
	var skill_id := SkillDataLoaderScript.stable_skill_id(
		str(request.get("skill_id", ""))
	)
	var definition := SkillDataLoaderScript.skill(skill_id)
	if definition.is_empty():
		return _canonical_rejection_plan(
			skill_id,
			"unknown_skill",
			request,
			context
		)
	var legacy_result := _plan(request)
	return SkillExecutionPlanContractScript.build_canonical_plan(
		legacy_result,
		request,
		context
	)


static func _canonical_rejection_plan(
	skill_id: String,
	reason: String,
	request: Variant,
	context: Dictionary
) -> Dictionary:
	var normalized := SkillExecutionPlanContractScript.normalize_reason(reason)
	var release_id := str(
		context.get(
			"release_id",
			request.get("target_context", {}).get("release_id", "")
		)
	)
	if release_id.is_empty():
		release_id = "canonical:%s:%d" % [
			skill_id,
			int(request.get("seed", 0)),
		]
	return {
		"contract": SkillExecutionPlanContractScript.CONTRACT_ID,
		"plan_version": 1,
		"plan_id": "",
		"release_id": release_id,
		"skill_id": skill_id,
		"skill_definition_revision": "",
		"caster_runtime_id": int(context.get("caster_runtime_id", 0)),
		"target_runtime_id": int(context.get("target_runtime_id", 0)),
		"runtime_map_id": int(context.get("runtime_map_id", -1)),
		"input_mode": str(context.get("input_mode", "canonical")),
		"requested_direction": request.get("facing", Vector2i.DOWN),
		"resolved_direction": request.get("facing", Vector2i.DOWN),
		"lock_on_context": {},
		"resource_cost": {},
		"cooldown_contract": {},
		"canonical_snapshot": {},
		"snapshot_id": "",
		"snapshot_required": not SkillExecutionPlanContractScript.NON_SPATIAL_SKILLS.has(
			skill_id
		),
		"non_spatial_reason": str(
			SkillExecutionPlanContractScript.NON_SPATIAL_SKILLS.get(
				skill_id,
				""
			)
		),
		"geometry_cells": [],
		"gameplay_actions": [],
		"presentation_actions": [],
		"projectile_descriptors": [],
		"ground_effect_descriptors": [],
		"summon_descriptors": [],
		"rejection": {"accepted": false, "reason": normalized},
		"created_by": SkillExecutionPlanContractScript.CANONICAL_PLANNER_ID,
		"legacy_planner": SkillExecutionPlanContractScript.LEGACY_PLANNER_ID,
	}


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
	var flat_damage_bonus_after_body_formula := 0
	var flat_accuracy_bonus := 0
	var proficiency_events: Array[Dictionary] = []
	var effects: Array[Dictionary] = []
	var slaying_proc := false
	var slaying_proc_roll_count := 0
	var slaying_proc_denominator := 0
	var slaying_proc_roll := -1

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

	if slaying_learned:
		var slaying_definition := SkillDataLoaderScript.skill("warrior.slaying_swordsmanship")
		var mechanics: Dictionary = slaying_definition.get("mechanics", {})
		var accuracy_values: Array = mechanics.get("flat_accuracy_bonus_by_rank", [0, 1, 2, 3])
		var denominator_values: Array = mechanics.get("proc_denominator_by_rank", [7, 6, 5, 4])
		flat_accuracy_bonus += int(accuracy_values[slaying_rank])
		slaying_proc_denominator = int(denominator_values[slaying_rank])
		if valid_melee_swing:
			slaying_proc_roll_count = 1
			var slaying_context := {
				"valid_melee_swing": true,
				"has_target": true,
				"force_proc": bool(request.get("force_slaying_proc", false)),
				"force_no_proc": bool(request.get("force_no_slaying_proc", false)),
			}
			if request.has("slaying_proc_roll"):
				slaying_context["proc_roll"] = int(request.get("slaying_proc_roll", 0))
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
				slaying_proc_denominator = int(effect.get("proc_denominator", slaying_proc_denominator))
				slaying_proc_roll = int(effect.get("proc_roll", -1))
				if slaying_proc:
					flat_damage_bonus_after_body_formula = int(
						effect.get("flat_damage_bonus", 0)
					)
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
		"flat_damage_bonus_after_body_formula": flat_damage_bonus_after_body_formula,
		"flat_accuracy_bonus": flat_accuracy_bonus,
		"slaying_proc": slaying_proc,
		"slaying_proc_roll_count": slaying_proc_roll_count,
		"slaying_proc_denominator": slaying_proc_denominator,
		"slaying_proc_roll": slaying_proc_roll,
		"slaying_effect_skill_id": (
			"warrior.slaying_swordsmanship" if slaying_proc else ""
		),
		"modifier_order": [
			"base_damage",
			"selected_body_skill_formula",
			"flat_damage_bonus_after_body_formula",
		],
		"scope": "all_hits_of_selected_melee_action",
		"requires_one_call_per_action": true,
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
		"entrypoint": "SkillRuntimeRouter.build_canonical_plan",
		"request_contract": SkillCastRequestScript.CONTRACT_ID,
		"result_contract": "skill_execution_result.v1",
		"requires_integration_adapters": [
			"combat_resolution",
			"inventory_resources",
			"map_tile_geometry",
			"target_relations",
			"buff_runtime",
			"taoist_main_pet",
		],
	}
