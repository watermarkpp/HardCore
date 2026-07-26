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
const CANONICAL_PRODUCTION_DEFAULT := false


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
		request.get("resource_context", {})
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


static func integration_descriptor() -> Dictionary:
	return {
		"runtime_contract": RUNTIME_CONTRACT_ID,
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
