class_name SkillExecutionPlan
extends RefCounted

## Q3-A/Q3-B: public canonical plan facade. The pure contract logic lives in
## SkillExecutionPlanContract (no router dependency). `build_plan` runs the
## legacy router (shadow / Q3-A tests); the FORMAL production entry is
## SkillRuntimeRouter.build_canonical_plan.

const Contract := preload(
	"res://scripts/skills/skill_execution_plan_contract.gd"
)
const SkillCastRequestScript := preload(
	"res://scripts/skills/skill_cast_request.gd"
)
const SkillDataLoaderScript := preload(
	"res://scripts/skills/skill_data_loader.gd"
)
const SkillRuntimeRouterScript := preload(
	"res://scripts/skills/skill_runtime_router.gd"
)

const CONTRACT_ID := Contract.CONTRACT_ID
const RESULT_CONTRACT_ID := Contract.RESULT_CONTRACT_ID
const REASON_ACCEPTED := Contract.REASON_ACCEPTED
const REASON_UNKNOWN_SKILL := Contract.REASON_UNKNOWN_SKILL
const REASON_INVALID_REQUEST := Contract.REASON_INVALID_REQUEST
const REASON_INVALID_TARGET := Contract.REASON_INVALID_TARGET
const REASON_INSUFFICIENT_RESOURCE := Contract.REASON_INSUFFICIENT_RESOURCE
const REASON_COOLDOWN := Contract.REASON_COOLDOWN
const REASON_INVALID_SNAPSHOT := Contract.REASON_INVALID_SNAPSHOT
const REASON_MAP_MISMATCH := Contract.REASON_MAP_MISMATCH
const REASON_RUNTIME_REJECTED := Contract.REASON_RUNTIME_REJECTED
const REASON_RESOURCE_COMMIT_FAILED := Contract.REASON_RESOURCE_COMMIT_FAILED


static func build_plan(request: Dictionary, context: Dictionary = {}) -> Dictionary:
	## Shadow / Q3-A-compat canonical plan builder: runs the real legacy router
	## and envelopes the result through the pure contract.
	var request_validation := SkillCastRequestScript.validate(request)
	if not bool(request_validation.get("valid", false)):
		return _rejection_plan(
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
		return _rejection_plan(skill_id, "unknown_skill", request, context)
	var legacy_result := SkillRuntimeRouterScript.execute(request)
	return Contract.build_canonical_plan(legacy_result, request, context)


static func build_canonical_plan(
	legacy_result: Dictionary,
	request: Dictionary,
	context: Dictionary = {}
) -> Dictionary:
	return Contract.build_canonical_plan(legacy_result, request, context)


static func build_result(
	plan: Dictionary,
	overrides: Dictionary = {}
) -> Dictionary:
	return Contract.build_result(plan, overrides)


static func plan_hash(plan: Dictionary) -> String:
	return Contract.plan_hash(plan)


static func verify_immutable(
	plan: Dictionary,
	hash_before: String
) -> Dictionary:
	return Contract.verify_immutable(plan, hash_before)


static func skill_execution_plan_diagnostics(plan: Dictionary) -> Dictionary:
	return Contract.skill_execution_plan_diagnostics(plan)


static func normalize_reason(reason: String) -> String:
	return Contract.normalize_reason(reason)


static func reset_sentinels_for_tests() -> void:
	Contract.reset_sentinels_for_tests()


static func sentinel_diagnostics() -> Dictionary:
	return Contract.sentinel_diagnostics()


static func _canonicalize(value: Variant) -> String:
	return Contract._canonicalize(value)


static func _rejection_plan(
	skill_id: String,
	reason: String,
	request: Dictionary,
	context: Dictionary
) -> Dictionary:
	var normalized := normalize_reason(reason)
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
		"contract": CONTRACT_ID,
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
		"snapshot_required": not Contract.NON_SPATIAL_SKILLS.has(skill_id),
		"non_spatial_reason": str(
			Contract.NON_SPATIAL_SKILLS.get(skill_id, "")
		),
		"geometry_cells": [],
		"gameplay_actions": [],
		"presentation_actions": [],
		"projectile_descriptors": [],
		"ground_effect_descriptors": [],
		"summon_descriptors": [],
		"rejection": {"accepted": false, "reason": normalized},
		"created_by": Contract.CANONICAL_PLANNER_ID,
		"legacy_planner": Contract.LEGACY_PLANNER_ID,
	}
