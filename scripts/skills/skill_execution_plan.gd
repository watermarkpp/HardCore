class_name SkillExecutionPlan
extends RefCounted

## Q3-A/Q3-B/Q3-C: public canonical plan facade. The pure contract logic lives
## in SkillExecutionPlanContract (no router dependency). The FORMAL production
## entry is SkillRuntimeRouter.build_canonical_plan; this facade only forwards
## plan/result construction, hashing, verification and sentinel diagnostics.

const Contract := preload(
	"res://scripts/skills/skill_execution_plan_contract.gd"
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
