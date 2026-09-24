class_name SkillRankExtensionPolicy
extends RefCounted

## Machine-checkable policy for extending skill ranks above the frozen
## 0..3 base ranks (skills_source_of_truth_v1.json). This file is the single
## authority for extension semantics; gameplay code must not use generic
## array-index clamps to mask field meaning.

const POLICY_PATH := "res://assets/data/vanilla_176/skill_rank_extension_policy.json"
const CONTRACT_ID := "skills.rank_extension.v2"
const MODES := ["DAMAGE_MORE", "HEAL_MORE", "PASSIVE_BASIC_ACCURACY", "PASSIVE_SLAYING", "PASSIVE_SPIRITUAL_WARFARE", "POISON_NATIVE_FORMULA", "SUMMON_SKELETON_COUNT", "SUMMON_DIVINE_DAMAGE_MORE", "EXCLUDED"]

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
	if not is_equal_approx(float(parsed.get("more_per_extra_rank", 0.0)), 1.1):
		errors.append("more_per_extra_rank")
	if int(parsed.get("skeleton_count_technical_cap", 0)) != 8:
		errors.append("skeleton_count_technical_cap")
	var modes: Variant = parsed.get("modes", {})
	if not modes is Dictionary:
		errors.append("modes")
	else:
		var seen := {}
		for mode: String in (modes as Dictionary):
			if mode not in MODES:
				errors.append("unknown_mode:" + mode)
		for mode: String in MODES:
			var ids: Variant = (modes as Dictionary).get(mode, null)
			if not ids is Array:
				errors.append("missing_mode:" + mode)
				continue
			for id: Variant in ids:
				if str(id).is_empty():
					errors.append("empty_skill_id")
				if seen.has(str(id)):
					errors.append("duplicate_skill:" + str(id))
				seen[str(id)] = true
		if seen.size() != 33:
			errors.append("skill_count")
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
	return 1.0


static func max_damage_reduction() -> float:
	return 0.75


static func denominator_floor() -> int:
	return 2


static func summon_pet_level_cap() -> int:
	return 7


static func mode_for(skill_id: String) -> String:
	var modes: Dictionary = policy().get("modes", {})
	for mode: String in modes:
		if modes[mode] is Array and (modes[mode] as Array).has(skill_id):
			return mode
	return ""


static func can_extend(skill_id: String) -> bool:
	var mode := mode_for(skill_id)
	return not mode.is_empty() and mode != "EXCLUDED"


static func skeleton_count_cap() -> int:
	return int(policy().get("skeleton_count_technical_cap", 8))


static func clear_cache_for_tests() -> void:
	_policy.clear()
	_validation.clear()
