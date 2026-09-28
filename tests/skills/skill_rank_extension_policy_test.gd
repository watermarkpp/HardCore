extends Node

const Policy := preload("res://scripts/skills/skill_rank_extension_policy.gd")
const Resolver := preload("res://scripts/skills/skill_rank_resolver.gd")
const Loader := preload("res://scripts/skills/skill_data_loader.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	Policy.clear_cache_for_tests()
	var validation := Policy.validation()
	assert(validation.valid, "extension policy invalid: %s" % [validation.errors])
	assert(Policy.CONTRACT_ID == "skills.rank_extension.v2")
	assert(Policy.skeleton_count_cap() == 8)
	var classified := {}
	var expected_modes := {
		"DAMAGE_MORE": ["warrior.thrusting", "warrior.half_moon", "warrior.fire_sword", "wizard.fireball", "wizard.hellfire", "wizard.lightning", "wizard.great_fireball", "wizard.exploding_flame", "wizard.fire_wall", "wizard.laser", "wizard.hell_lightning", "wizard.ice_storm", "taoist.soul_fire_talisman"],
		"HEAL_MORE": ["taoist.healing", "taoist.mass_healing"],
		"PASSIVE_BASIC_ACCURACY": ["warrior.basic_swordsmanship"],
		"PASSIVE_SLAYING": ["warrior.slaying_swordsmanship"],
		"PASSIVE_SPIRITUAL_WARFARE": ["taoist.spiritual_warfare"],
		"POISON_NATIVE_FORMULA": ["taoist.poison"],
		"SUMMON_SKELETON_COUNT": ["taoist.summon_skeleton"],
		"SUMMON_DIVINE_DAMAGE_MORE": ["taoist.summon_divine_beast"],
		"EXCLUDED": ["warrior.wild_rush", "wizard.repulsion_ring", "wizard.temptation_light", "wizard.teleport", "wizard.magic_shield", "wizard.holy_word", "taoist.invisibility", "taoist.mass_invisibility", "taoist.magic_defense", "taoist.defense", "taoist.revelation", "taoist.entrapment"],
	}
	for skill_id: String in Loader.skill_ids():
		var mode := Policy.mode_for(skill_id)
		assert(not mode.is_empty(), "unclassified: %s" % skill_id)
		assert((expected_modes.get(mode, []) as Array).has(skill_id), "wrong mode: %s %s" % [skill_id, mode])
		classified[skill_id] = true
	assert(classified.size() == 33)
	for mode: String in expected_modes:
		for skill_id: String in expected_modes[mode]:
			assert(classified.has(skill_id), "missing source skill: %s" % skill_id)
	assert(Policy.mode_for("wizard.magic_shield") == "EXCLUDED")
	assert(not Policy.can_extend("wizard.magic_shield"))
	assert(Policy.can_extend("taoist.summon_skeleton"))
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

	# All generic fields freeze; only named extension modes may grow.
	assert(Resolver.linear_int([9, 11, 13, 15], 4) == 15)
	assert(Resolver.linear_int([9, 11, 13, 15], 5) == 15)
	assert(is_equal_approx(Resolver.linear_float([1.4, 1.8, 2.2, 2.6], 5), 2.6))
	assert(is_equal_approx(Resolver.more_multiplier(4), 1.1))
	assert(is_equal_approx(Resolver.more_multiplier(5), 1.21))
	assert(Resolver.skeleton_count(3) == 1 and Resolver.skeleton_count(4) == 1)
	assert(Resolver.skeleton_count(5) == 2 and Resolver.skeleton_count(7) == 3)
	assert(Resolver.skeleton_count(17) == 8 and Resolver.skeleton_count(1000) == 8)

	# Probability fields cap at 1.0.
	assert(is_equal_approx(Resolver.probability([0.1, 0.2, 0.3, 0.4], 4), 0.4))
	assert(is_equal_approx(Resolver.capped_probability(1.09), 1.0))
	assert(Resolver.capped_roll_bound(12, 11) == 11)
	assert(Resolver.capped_roll_bound(1000000, 11) == 11)
	assert(Resolver.capped_roll_bound(-5, 11) == 0)

	# Damage reduction caps at the policy maximum.
	assert(is_equal_approx(Resolver.damage_reduction([0.15, 0.3, 0.45, 0.6], 4), 0.6))
	assert(is_equal_approx(Resolver.damage_reduction([0.15, 0.3, 0.45, 0.6], 5), 0.6))
	assert(is_equal_approx(Resolver.capped_damage_reduction(0.9), 0.75))

	# Proc denominator stops decreasing at 2.
	assert(Resolver.denominator([7, 6, 5, 4], 4) == 4)
	assert(Resolver.denominator([7, 6, 5, 4], 5) == 4)
	assert(Resolver.denominator([7, 6, 5, 4], 1000) == 4)
	assert(Resolver.denominator_min(1) == 2)

	# Summon combat level cap stays 7.
	assert(Resolver.summon_pet_level(3) == 3)
	assert(Resolver.summon_pet_level(4) == 3)
	assert(Resolver.summon_pet_level(7) == 3)
	assert(Resolver.summon_pet_level(1000) == 3)

	# Timing stays constant at the base-max values.
	assert(Resolver.timing_int([1500, 1400, 1300, 1200], 1000) == 1200)
	assert(Resolver.timing_rank(1000) == 3)
	assert(Resolver.timing_rank(0) == 0)

	print(
		"SKILL_RANK_EXTENSION_POLICY_PASS: contract v2, 33 classified, "
		+ "0..3 verbatim, typed More and summon count, generic fields frozen"
	)
	get_tree().quit()
