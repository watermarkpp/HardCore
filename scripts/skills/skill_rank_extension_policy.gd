class_name SkillRankExtensionPolicy
extends RefCounted

## Machine-checkable policy for extending skill ranks above the frozen
## 0..3 base ranks (skills_source_of_truth_v1.json). This file is the single
## authority for extension semantics; gameplay code must not use generic
## array-index clamps to mask field meaning.

const POLICY_PATH := "res://assets/data/vanilla_176/skill_rank_extension_policy.json"
const CONTRACT_ID := "skills.rank_extension.v1"

static var _policy: Dictionary = {}
static var _validation: Dictionary = {}


static func policy() -> Dictionary:
	if _policy.is_empty():
		var file := FileAccess.open(
			POLICY_PATH,
			FileAccess.READ
		) if FileAccess.file_exists(POLICY_PATH) else null
		var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
		_policy = parsed if parsed is Dictionary else {}
		_validation = validate_policy(_policy)
		if not bool(_validation.get("valid", false)):
			push_error(
				"技能等级扩展策略无效：%s"
				% "; ".join(_validation.get("errors", []))
			)
	return _policy


static func validation() -> Dictionary:
	policy()
	return _validation.duplicate(true)


static func validate_policy(value: Variant) -> Dictionary:
	var errors: Array[String] = []
	if not value is Dictionary:
		return {"valid": false, "errors": ["policy_not_dictionary"]}
	var parsed := value as Dictionary
	if str(parsed.get("contract_id", "")) != CONTRACT_ID:
		errors.append("contract_id")
	var base_rank: Dictionary = parsed.get("base_rank", {})
	if int(base_rank.get("min", -1)) != 0 or int(base_rank.get("max", -1)) != 3:
		errors.append("base_rank_bounds")
	if int(parsed.get("technical_effective_rank_cap", -1)) != 1000000:
		errors.append("technical_effective_rank_cap")
	var semantics: Dictionary = parsed.get("semantics", {})
	var probability_cap: Dictionary = semantics.get("probability_cap", {})
	if not is_equal_approx(float(probability_cap.get("max", -1.0)), 1.0):
		errors.append("probability_cap")
	var reduction_cap: Dictionary = semantics.get("damage_reduction_cap", {})
	if not is_equal_approx(float(reduction_cap.get("max", -1.0)), 0.75):
		errors.append("damage_reduction_cap")
	var denominator_floor: Dictionary = semantics.get("denominator_floor", {})
	if int(denominator_floor.get("min", -1)) != 2:
		errors.append("denominator_floor")
	var summon_cap: Dictionary = semantics.get("summon_pet_level_cap", {})
	if int(summon_cap.get("max", -1)) != 7:
		errors.append("summon_pet_level_cap")
	if not semantics.has("linear_extrapolation_last_delta"):
		errors.append("linear_extrapolation_last_delta")
	if not semantics.has("timing_constant"):
		errors.append("timing_constant")
	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"contract_id": str(parsed.get("contract_id", "")),
	}


static func base_rank_max() -> int:
	return int(policy().get("base_rank", {}).get("max", 3))


static func technical_effective_rank_cap() -> int:
	return int(policy().get("technical_effective_rank_cap", 1000000))


static func max_probability() -> float:
	return float(
		policy().get("semantics", {}).get("probability_cap", {}).get("max", 1.0)
	)


static func max_damage_reduction() -> float:
	return float(
		policy()
		.get("semantics", {})
		.get("damage_reduction_cap", {})
		.get("max", 0.75)
	)


static func denominator_floor() -> int:
	return int(
		policy().get("semantics", {}).get("denominator_floor", {}).get("min", 2)
	)


static func summon_pet_level_cap() -> int:
	return int(
		policy()
		.get("semantics", {})
		.get("summon_pet_level_cap", {})
		.get("max", 7)
	)


static func clear_cache_for_tests() -> void:
	_policy.clear()
	_validation.clear()
