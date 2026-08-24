extends Node

const LootRuntimeScript := preload("res://scripts/layers/runtime/loot_runtime_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData canonical catalog failed to load")

	# A. Canonical runtime closure must be fully closed: 156 / 153 / 153 / 0.
	var counts := GameData.canonical_monster_counts()
	assert(int(counts.get("catalog_identity_count", 0)) == 156, "catalog identity drifted")
	assert(int(counts.get("catalog_runtime_allowed_count", 0)) == 153, "runtime allowed drifted")
	assert(int(counts.get("runtime_spawnable_count", 0)) == 153, "runtime spawnable drifted")
	assert(int(counts.get("runtime_rejected_count", -1)) == 0, "runtime rejected must be 0")

	# B. version_difference no-drop entities: canonical policy says
	#    hostile_requires_non_empty=false, so they must be allowed.
	for monster_id: int in [59, 78, 161]:
		var closure := GameData.canonical_monster_runtime_drop_closure(monster_id)
		assert(bool(closure.get("allowed", false)), "ID %d closure not allowed" % monster_id)
		assert(not bool(closure.get("requires_non_empty", true)), "ID %d requires_non_empty must be false" % monster_id)
		assert(not GameData.get_monster_by_id(monster_id).is_empty(), "ID %d missing from runtime" % monster_id)

	# C. Tameable guards: exemption must be applied and they must be allowed.
	for monster_id: int in [186, 187]:
		var closure := GameData.canonical_monster_runtime_drop_closure(monster_id)
		assert(bool(closure.get("allowed", false)), "ID %d closure not allowed" % monster_id)
		assert(bool(closure.get("exemption_applied", false)), "ID %d exemption not applied" % monster_id)
		assert(not GameData.get_monster_by_id(monster_id).is_empty(), "ID %d missing from runtime" % monster_id)

	# D. Chest 226: gold-only canonical reward must close the drop gate.
	var closure_226 := GameData.canonical_monster_runtime_drop_closure(226)
	assert(bool(closure_226.get("allowed", false)), "ID 226 closure not allowed")
	assert(int(closure_226.get("resolved_non_gold_count", -1)) == 0, "ID 226 resolved non-gold must be 0")
	assert(int(closure_226.get("resolved_gold_count", -1)) == 1, "ID 226 resolved gold must be 1")
	assert(int(closure_226.get("resolved_reward_count", -1)) == 1, "ID 226 resolved reward must be 1")
	assert(not GameData.get_monster_by_id(226).is_empty(), "ID 226 missing from runtime")

	# E. ID226 unique gold row resolves through the unified reward resolver.
	var entry_226 := GameData.get_monster_by_id(226)
	assert(not entry_226.is_empty(), "ID 226 runtime entry missing")
	var profile_226 := GameData.get_canonical_monster_drop_profile(226)
	assert(not profile_226.is_empty(), "ID 226 drop profile missing")
	var rows_226: Array = profile_226.get("entries", [])
	assert(rows_226.size() == 1, "ID 226 must have exactly one drop row")
	var reward := GameData.resolve_canonical_drop_reward(rows_226[0])
	assert(bool(reward.get("ok", false)), "ID 226 gold reward failed")
	assert(str(reward.get("kind", "")) == "gold", "ID 226 reward kind must be gold")
	assert(str(reward.get("item_name", "")) == "金币", "ID 226 reward item_name must be 金币")
	assert(int(reward.get("gold_amount", 0)) == 3000, "ID 226 gold amount must be 3000")

	# F. LootRuntime must roll the gold row on a hit (1/2), never reject it.
	var hit := false
	for seed: int in range(64):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var roll := LootRuntimeScript.new().roll_monster_drops(226, rng, 6)
		if int(roll.get("resolved_entry_count", 0)) == 1:
			var gold_drops: Array = roll.get("gold_drops", [])
			if gold_drops.size() == 1 and int(gold_drops[0]) == 3000:
				hit = true
				break
	assert(hit, "no deterministic seed produced the ID 226 gold roll")
	# Sanity: the gold row must never appear in rejected_entries.
	var rng_final := RandomNumberGenerator.new()
	rng_final.seed = 0
	var roll_final := LootRuntimeScript.new().roll_monster_drops(226, rng_final, 6)
	for rejected: Variant in roll_final.get("rejected_entries", []):
		assert(not (rejected is Dictionary and int(rejected.get("line_number", -1)) == 1), "ID 226 gold row was rejected")

	print("MONSTER_GOLD_DROP_RUNTIME_PASS: identity=156 allowed=153 spawnable=153 rejected=0 gold_226=3000")
	get_tree().quit(0)
