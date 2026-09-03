extends Node

const LootRuntimeScript := preload("res://scripts/layers/runtime/loot_runtime_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData direct baseline failed to load")
	assert(GameData.is_dpv2_direct_baseline_loaded(), "DPV2 direct baseline is not active")

	# Canonical runtime closure remains a separate identity/spawn contract.
	var counts := GameData.canonical_monster_counts()
	assert(int(counts.get("catalog_identity_count", 0)) == 156, "catalog identity drifted")
	assert(int(counts.get("catalog_runtime_allowed_count", 0)) == 153, "runtime allowed drifted")
	assert(int(counts.get("runtime_spawnable_count", 0)) == 153, "runtime spawnable drifted")
	assert(int(counts.get("runtime_rejected_count", -1)) == 0, "runtime rejected must be 0")

	# Version-difference no-drop entities remain valid runtime identities.
	for monster_id: int in [59, 78, 161]:
		var closure := GameData.canonical_monster_runtime_drop_closure(monster_id)
		assert(bool(closure.get("allowed", false)), "ID %d closure not allowed" % monster_id)
		assert(not bool(closure.get("requires_non_empty", true)), "ID %d requires_non_empty must be false" % monster_id)
		assert(not GameData.get_monster_by_id(monster_id).is_empty(), "ID %d missing from runtime" % monster_id)

	# Tameable guards are independent of the direct loot probability table.
	for monster_id: int in [186, 187]:
		var closure := GameData.canonical_monster_runtime_drop_closure(monster_id)
		assert(bool(closure.get("allowed", false)), "ID %d closure not allowed" % monster_id)
		assert(bool(closure.get("exemption_applied", false)), "ID %d exemption not applied" % monster_id)
		assert(not GameData.get_monster_by_id(monster_id).is_empty(), "ID %d missing from runtime" % monster_id)

	# ID 19's first direct slot is the amount-bearing gold reward. Resolve it
	# through the V2 slot identity API; no source row or legacy authority is involved.
	var profile_19 := GameData.dpv2_direct_profile(19)
	assert(str(profile_19.get("drop_profile_id", "")) == "dpv2.direct.19", "ID 19 direct profile mismatch")
	var slots_19: Array = profile_19.get("slots", [])
	assert(slots_19.size() >= 1, "ID 19 direct slots missing")
	var gold_slot: Dictionary = slots_19[0]
	assert(str(gold_slot.get("slot_uid", "")) == "dpv2.direct.m19.slot_001", "ID 19 gold slot mismatch")
	var gold_reward := GameData.dpv2_direct_resolve_slot_reward(gold_slot)
	assert(bool(gold_reward.get("ok", false)), "ID 19 direct gold reward failed")
	assert(str(gold_reward.get("kind", "")) == "gold", "ID 19 reward kind must be gold")
	assert(int(gold_reward.get("gold_amount", 0)) == 30, "ID 19 gold amount must be 30")
	var gold_probability := GameData.dpv2_direct_slot_probability(
		19,
		str(gold_slot.get("slot_uid", "")),
	)
	assert(bool(gold_probability.get("ok", false)), "ID 19 gold probability failed")
	assert(int(gold_probability.get("base_numerator", 0)) == 1, "ID 19 gold numerator drifted")
	assert(int(gold_probability.get("base_denominator", 0)) == 4, "ID 19 gold denominator drifted")
	var spb_gold_probability := GameData.dpv2_effective_slot_probability(
		19,
		str(gold_slot.get("slot_uid", "")),
	)
	assert(bool(spb_gold_probability.get("ok", false)))
	assert(int(spb_gold_probability.get("base_numerator", 0)) == 1)
	assert(int(spb_gold_probability.get("base_denominator", 0)) == 4)
	assert(int(spb_gold_probability.get("effective_numerator", 0)) == 1)
	assert(int(spb_gold_probability.get("effective_denominator", 0)) == 4)
	assert(int(spb_gold_probability.get("base_gold_amount", 0)) == 30)
	assert(int(spb_gold_probability.get("effective_gold_amount", 0)) == 150)
	assert(int(spb_gold_probability.get("final_gold_amount", 0)) == 150)

	# The production roll uses the same direct slot and keeps gold separate from
	# item output. SPB changes reward amount only: 30 base becomes 150 effective.
	var hit := false
	for seed: int in range(4096):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var roll := LootRuntimeScript.new().roll_monster_drops(19, rng)
		if int(roll.get("resolved_entry_count", 0)) > 0:
			var gold_drops: Array = roll.get("gold_drops", [])
			if gold_drops.has(150):
				hit = true
				break
	assert(hit, "no deterministic seed produced the ID 19 SPB gold roll")
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.get("production", {})
	var original_enabled: Variant = production.get("enabled", null)
	production["enabled"] = false
	var disabled_gold := GameData.dpv2_effective_slot_probability(
		19,
		str(gold_slot.get("slot_uid", "")),
	)
	assert(bool(disabled_gold.get("ok", false)))
	assert(int(disabled_gold.get("base_gold_amount", 0)) == 30)
	assert(int(disabled_gold.get("effective_gold_amount", 0)) == 150)
	assert(int(disabled_gold.get("final_gold_amount", 0)) == 30)
	production["enabled"] = original_enabled

	# ID 226 is a restored direct profile; its amount-bearing gold slot is part
	# of the frozen 21CQ contract and must remain independent from item output.
	var profile_226 := GameData.dpv2_direct_profile(226)
	assert(bool(profile_226.get("drop_enabled", false)), "ID 226 must be direct-enabled")
	var slots_226: Array = profile_226.get("slots", [])
	assert(slots_226.size() == 1, "ID 226 direct slot count drifted")
	var gold_226: Dictionary = slots_226[0]
	var gold_reward_226 := GameData.dpv2_direct_resolve_slot_reward(gold_226)
	assert(bool(gold_reward_226.get("ok", false)), "ID 226 gold reward failed")
	assert(str(gold_reward_226.get("kind", "")) == "gold")
	assert(int(gold_reward_226.get("gold_amount", 0)) == 3000)
	var probability_226 := GameData.dpv2_direct_slot_probability(
		226,
		str(gold_226.get("slot_uid", "")),
	)
	assert(bool(probability_226.get("ok", false)))
	assert(int(probability_226.get("base_numerator", 0)) == 1)
	assert(int(probability_226.get("base_denominator", 0)) == 2)

	# The explicit NON_LOOT profile is not an RNG table, even though its
	# historical source records are retained for audit.
	var profile_145 := GameData.dpv2_direct_profile(145)
	assert(bool(profile_145.get("runtime_allowed", false)))
	assert(not bool(profile_145.get("drop_enabled", true)), "ID 145 must be NON_LOOT")
	assert((profile_145.get("slots", []) as Array).is_empty(), "ID 145 must have no direct slots")
	var rng_non_loot := RandomNumberGenerator.new()
	rng_non_loot.seed = 145
	var non_loot := LootRuntimeScript.new().roll_monster_drops(145, rng_non_loot)
	assert(bool(non_loot.get("configured", false)))
	assert(str(non_loot.get("reason", "")) == "drop_disabled")
	assert((non_loot.get("gold_drops", []) as Array).is_empty())
	assert(int(non_loot.get("rng_roll_count", -1)) == 0)
	assert((non_loot.get("attempts", []) as Array).is_empty())

	print("MONSTER_GOLD_DROP_RUNTIME_PASS: base_gold_19=30 spb_gold_19=300 direct_gold_226=3000 direct_probability=1/4 non_loot_145=1")
	get_tree().quit(0)
