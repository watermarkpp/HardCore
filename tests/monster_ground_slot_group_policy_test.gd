extends Node

const LootRuntime := preload("res://scripts/layers/runtime/loot_runtime_service.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData must load before monster ground-slot policy test")
	assert(GameData.canonical_monster_classification(19) == "ordinary", "fixture 19 must be canonical ordinary")
	assert(GameData.canonical_monster_classification(73) == "elite", "fixture 73 must be canonical elite")
	assert(GameData.canonical_monster_classification(76) == "boss", "fixture 76 must be canonical boss")
	assert(GameData.dpv2_ground_slot_limit_for_monster(19) == 6, "ordinary monsters must retain six ground slots")
	assert(GameData.dpv2_ground_slot_limit_for_monster(73) == 9, "elite monsters must retain nine ground slots")
	assert(GameData.dpv2_ground_slot_limit_for_monster(76) == 12, "bosses must retain twelve ground slots")
	assert(GameData.dpv2_ground_slot_limit_for_monster(999999) == 0, "unknown monster must fail closed")
	var service := LootRuntime.new()
	var candidates: Array = []
	for index in 2:
		candidates.append({"slot_uid": "protected-%d" % index, "policy": {"protected_drop": true, "overflow_priority": 400}})
	for index in 8:
		candidates.append({"slot_uid": "ordinary-%d" % index, "policy": {"protected_drop": false, "overflow_priority": 0}})
	var selection: Dictionary = service.call("_select_ground_rewards", candidates, RandomNumberGenerator.new(), 6)
	assert(selection.selected.size() == 6, "ordinary group cap must be applied after all RNG successes")
	assert(selection.protected_discarded_count == 0, "protected overflow must retain priority within the cap")
	for fixture: Dictionary in [
		{"id": 19, "classification": "ordinary", "cap": 6},
		{"id": 73, "classification": "elite", "cap": 9},
		{"id": 76, "classification": "boss", "cap": 12},
	]:
		var audit_rng := RandomNumberGenerator.new()
		var lean_rng := RandomNumberGenerator.new()
		audit_rng.seed = 20261007 + int(fixture.id)
		lean_rng.seed = audit_rng.seed
		var audit: Dictionary = service.roll_monster_drops(int(fixture.id), audit_rng, true)
		var lean: Dictionary = service.roll_monster_drops(int(fixture.id), lean_rng, false)
		var profile: Dictionary = service._sheet_authority.profile(int(fixture.id))
		var profile_slots: Array = profile.get("slots", [])
		assert(str(audit.get("reason", "")).is_empty() and str(lean.get("reason", "")).is_empty())
		assert(int(audit.get("rng_roll_count", 0)) == profile_slots.size())
		assert(int(lean.get("rng_roll_count", 0)) == profile_slots.size())
		assert(audit_rng.state == lean_rng.state, "audit/lean RNG drift for real %s" % fixture.classification)
		assert(audit.items == lean.items and audit.item_records == lean.item_records and audit.gold_drops == lean.gold_drops)
		assert(audit.ground_slot_group == lean.ground_slot_group)
		assert(str(audit.ground_slot_group.classification) == fixture.classification)
		assert(int(audit.ground_slot_group.ground_slot_limit) == fixture.cap)
		assert(int(audit.ground_output_count) <= fixture.cap)
		assert(audit.ground_output_plus_discarded_equals_successful)
	service.free()
	print("MONSTER_GROUND_SLOT_GROUP_POLICY_PASS ordinary=6 elite=9 boss=12 unknown=0")
	get_tree().quit(0)
