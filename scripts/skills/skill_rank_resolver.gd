class_name SkillRankResolver
extends RefCounted

## Single rank-resolution entry point for the canonical skill plan chain.
## Base ranks 0..3 come verbatim from skills_source_of_truth_v1.json (zero
## change); effective ranks above 3 are extended per
## skills.rank_extension.v1 semantics. There is no gameplay level cap: the
## only upper bound is the policy's technical anti-abuse sanity cap.

const Policy := preload("res://scripts/skills/skill_rank_extension_policy.gd")

const SEMANTIC_LINEAR := "linear"
const SEMANTIC_PROBABILITY := "probability"
const SEMANTIC_DAMAGE_REDUCTION := "damage_reduction"
const SEMANTIC_DENOMINATOR := "denominator"
const SEMANTIC_SUMMON_PET_LEVEL := "summon_pet_level"
const SEMANTIC_TIMING_CONSTANT := "timing_constant"


static func base_rank_max() -> int:
	return Policy.base_rank_max()


static func technical_effective_rank_cap() -> int:
	return Policy.technical_effective_rank_cap()


static func safe_effective_rank(rank_value: Variant) -> int:
	var raw := int(rank_value)
	if raw < 0:
		return 0
	return mini(raw, Policy.technical_effective_rank_cap())


static func timing_rank(rank_value: Variant) -> int:
	## Timing/cast sequencing never changes with effective level.
	return mini(safe_effective_rank(rank_value), Policy.base_rank_max())


static func value(values: Variant, rank_value: Variant, semantic: String) -> Variant:
	var rank := safe_effective_rank(rank_value)
	if not values is Array or (values as Array).is_empty():
		return null
	var array := values as Array
	if rank < array.size():
		return array[rank]
	var base_max := array.size() - 1
	var last: Variant = array[base_max]
	var previous: Variant = array[maxi(0, base_max - 1)]
	if semantic == SEMANTIC_TIMING_CONSTANT:
		return last
	var extended: Variant = _linear_extend(last, previous, rank - base_max)
	match semantic:
		SEMANTIC_PROBABILITY:
			return clampf(float(extended), 0.0, Policy.max_probability())
		SEMANTIC_DAMAGE_REDUCTION:
			return clampf(float(extended), 0.0, Policy.max_damage_reduction())
		SEMANTIC_DENOMINATOR:
			return maxi(Policy.denominator_floor(), int(extended))
		SEMANTIC_SUMMON_PET_LEVEL:
			return clampi(int(extended), 0, Policy.summon_pet_level_cap())
		_:
			return extended


static func linear_int(values: Variant, rank_value: Variant) -> int:
	return int(value(values, rank_value, SEMANTIC_LINEAR))


static func linear_float(values: Variant, rank_value: Variant) -> float:
	return float(value(values, rank_value, SEMANTIC_LINEAR))


static func timing_int(values: Variant, rank_value: Variant) -> int:
	return int(value(values, rank_value, SEMANTIC_TIMING_CONSTANT))


static func timing_float(values: Variant, rank_value: Variant) -> float:
	return float(value(values, rank_value, SEMANTIC_TIMING_CONSTANT))


static func denominator(values: Variant, rank_value: Variant) -> int:
	return int(value(values, rank_value, SEMANTIC_DENOMINATOR))


static func damage_reduction(values: Variant, rank_value: Variant) -> float:
	return float(value(values, rank_value, SEMANTIC_DAMAGE_REDUCTION))


static func probability(values: Variant, rank_value: Variant) -> float:
	return float(value(values, rank_value, SEMANTIC_PROBABILITY))


static func summon_pet_level(rank_value: Variant) -> int:
	return clampi(safe_effective_rank(rank_value), 0, Policy.summon_pet_level_cap())


static func capped_probability(raw_probability: float) -> float:
	return clampf(raw_probability, 0.0, Policy.max_probability())


static func capped_damage_reduction(raw_reduction: float) -> float:
	return clampf(raw_reduction, 0.0, Policy.max_damage_reduction())


static func capped_roll_bound(raw_bound: int, roll_space: int) -> int:
	## Caps a `random < bound` condition so its probability never exceeds 1.0.
	return clampi(raw_bound, 0, maxi(0, roll_space))


static func denominator_min(raw_value: int) -> int:
	return maxi(Policy.denominator_floor(), raw_value)


static func _linear_extend(last: Variant, previous: Variant, steps: int) -> Variant:
	var last_f := float(last)
	var previous_f := float(previous)
	var extended_f := last_f + (last_f - previous_f) * float(steps)
	if typeof(last) == TYPE_INT and typeof(previous) == TYPE_INT:
		return roundi(extended_f)
	return extended_f
