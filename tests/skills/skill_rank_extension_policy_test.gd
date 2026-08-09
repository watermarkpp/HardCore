extends Node

const Policy := preload("res://scripts/skills/skill_rank_extension_policy.gd")
const Resolver := preload("res://scripts/skills/skill_rank_resolver.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	Policy.clear_cache_for_tests()
	var validation := Policy.validation()
	assert(validation.valid, "extension policy invalid: %s" % [validation.errors])
	assert(Policy.CONTRACT_ID == "skills.rank_extension.v1")
	assert(Policy.base_rank_max() == 3)
	# Technical cap is anti-abuse only and far above any achievable effective
	# rank; it must not read like a gameplay level cap.
	assert(Policy.technical_effective_rank_cap() == 1000000)
	assert(is_equal_approx(Policy.max_probability(), 1.0))
	assert(is_equal_approx(Policy.max_damage_reduction(), 0.75))
	assert(Policy.denominator_floor() == 2)
	assert(Policy.summon_pet_level_cap() == 7)

	# Ordinary high ranks are not truncated.
	assert(Resolver.safe_effective_rank(-7) == 0)
	assert(Resolver.safe_effective_rank(0) == 0)
	assert(Resolver.safe_effective_rank(3) == 3)
	assert(Resolver.safe_effective_rank(1000) == 1000)
	assert(Resolver.safe_effective_rank(999999) == 999999)
	assert(Resolver.safe_effective_rank(1000000) == 1000000)
	assert(Resolver.safe_effective_rank(1000001) == 1000000)

	# 0..3 regression: every by-rank array and MP table is returned verbatim.
	for skill_id: String in Loader.skill_ids():
		var definition := Loader.skill(skill_id)
		var mechanics: Dictionary = definition.get("mechanics", {})
		for key: String in mechanics:
			var values: Variant = mechanics.get(key)
			if not values is Array or (values as Array).size() != 4:
				continue
			for rank in range(4):
				assert(
					Resolver.value(values, rank, Resolver.SEMANTIC_LINEAR)
					== values[rank],
					"rank %d changed for %s.%s" % [rank, skill_id, key]
				)
		var mp_costs: Array = definition.get("mp_cost_by_rank", [])
		for rank in range(4):
			assert(Resolver.linear_int(mp_costs, rank) == int(mp_costs[rank]))

	# Linear last-delta growth for damage/fixed/MP-style fields.
	assert(Resolver.linear_int([9, 11, 13, 15], 4) == 17)
	assert(Resolver.linear_int([9, 11, 13, 15], 5) == 19)
	assert(Resolver.linear_float([1.4, 1.8, 2.2, 2.6], 4) == 3.0)
	assert(is_equal_approx(Resolver.linear_float([1.4, 1.8, 2.2, 2.6], 5), 3.4))
	assert(Resolver.linear_int([0, 3, 6, 9], 1000) == 3000)

	# Probability fields cap at 1.0.
	assert(is_equal_approx(Resolver.probability([0.1, 0.2, 0.3, 0.4], 4), 0.5))
	assert(is_equal_approx(Resolver.capped_probability(1.09), 1.0))
	assert(Resolver.capped_roll_bound(12, 11) == 11)
	assert(Resolver.capped_roll_bound(1000000, 11) == 11)
	assert(Resolver.capped_roll_bound(-5, 11) == 0)

	# Damage reduction caps at the policy maximum.
	assert(is_equal_approx(Resolver.damage_reduction([0.15, 0.3, 0.45, 0.6], 4), 0.75))
	assert(is_equal_approx(Resolver.damage_reduction([0.15, 0.3, 0.45, 0.6], 5), 0.75))
	assert(is_equal_approx(Resolver.capped_damage_reduction(0.9), 0.75))

	# Proc denominator stops decreasing at 2.
	assert(Resolver.denominator([7, 6, 5, 4], 4) == 3)
	assert(Resolver.denominator([7, 6, 5, 4], 5) == 2)
	assert(Resolver.denominator([7, 6, 5, 4], 1000) == 2)
	assert(Resolver.denominator_min(1) == 2)

	# Summon combat level cap stays 7.
	assert(Resolver.summon_pet_level(3) == 3)
	assert(Resolver.summon_pet_level(4) == 4)
	assert(Resolver.summon_pet_level(7) == 7)
	assert(Resolver.summon_pet_level(1000) == 7)

	# Timing stays constant at the base-max values.
	assert(Resolver.timing_int([1500, 1400, 1300, 1200], 1000) == 1200)
	assert(Resolver.timing_rank(1000) == 3)
	assert(Resolver.timing_rank(0) == 0)

	print(
		"SKILL_RANK_EXTENSION_POLICY_PASS: contract v1, technical cap 1,000,000, "
		+ "0..3 verbatim, linear MP/damage growth, probability/reduction/denominator/"
		+ "summon caps, timing constant"
	)
	get_tree().quit()
