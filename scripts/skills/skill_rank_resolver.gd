class_name SkillRankResolver
extends RefCounted

## Single rank-resolution entry point for the canonical skill plan chain.
## Base ranks 0..3 come verbatim from skills_source_of_truth_v1.json (zero
## change); effective ranks above 3 are extended per
## skills.rank_extension.v2 semantics. There is no gameplay level cap: the
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
	# No generic last-delta extrapolation is allowed in V2. Individual
	# extension modes own their formulas; all other fields freeze at rank 3.
	return array[base_max]


static func mode_for(skill_id: String) -> String:
	return Policy.mode_for(skill_id)


static func can_extend(skill_id: String) -> bool:
	return Policy.can_extend(skill_id)


static func formula_rank(rank_value: Variant) -> int:
	return mini(safe_effective_rank(rank_value), base_rank_max())


static func more_multiplier(rank_value: Variant) -> float:
	return pow(1.1, maxi(0, safe_effective_rank(rank_value) - base_rank_max()))


static func skeleton_count(rank_value: Variant) -> int:
	var extra := maxi(0, safe_effective_rank(rank_value) - base_rank_max())
	return mini(1 + floori(float(extra) / 2.0), Policy.skeleton_count_cap())


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
	return formula_rank(rank_value)


static func capped_probability(raw_probability: float) -> float:
	return clampf(raw_probability, 0.0, Policy.max_probability())


static func capped_damage_reduction(raw_reduction: float) -> float:
	return clampf(raw_reduction, 0.0, Policy.max_damage_reduction())


static func capped_roll_bound(raw_bound: int, roll_space: int) -> int:
	## Caps a `random < bound` condition so its probability never exceeds 1.0.
	return clampi(raw_bound, 0, maxi(0, roll_space))


static func denominator_min(raw_value: int) -> int:
	return maxi(Policy.denominator_floor(), raw_value)
