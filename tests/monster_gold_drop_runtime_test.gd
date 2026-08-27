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

	# The production roll uses the same direct slot and keeps gold separate from
	# item output. At least one deterministic seed must produce 30 gold.
	var hit := false
	for seed: int in range(4096):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var roll := LootRuntimeScript.new().roll_monster_drops(19, rng)
		if int(roll.get("resolved_entry_count", 0)) > 0:
			var gold_drops: Array = roll.get("gold_drops", [])
			if gold_drops.has(30):
				hit = true
				break
	assert(hit, "no deterministic seed produced the ID 19 gold roll")

	# The NON_LOOT profile is not an RNG table, even though its historical source
	# record contains a gold reward.
	var profile_226 := GameData.dpv2_direct_profile(226)
	assert(not bool(profile_226.get("drop_enabled", true)), "ID 226 must be NON_LOOT")
	assert((profile_226.get("slots", []) as Array).is_empty(), "ID 226 must have no direct slots")
	var rng_non_loot := RandomNumberGenerator.new()
	rng_non_loot.seed = 226
	var non_loot := LootRuntimeScript.new().roll_monster_drops(226, rng_non_loot)
	assert(bool(non_loot.get("configured", false)))
	assert(str(non_loot.get("reason", "")) == "drop_disabled")
	assert((non_loot.get("gold_drops", []) as Array).is_empty())
	assert(int(non_loot.get("rng_roll_count", -1)) == 0)
	assert((non_loot.get("attempts", []) as Array).is_empty())

	print("MONSTER_GOLD_DROP_RUNTIME_PASS: direct_gold_19=30 direct_probability=1/4 non_loot_226=1")
	get_tree().quit(0)
