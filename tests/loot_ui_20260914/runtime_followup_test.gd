extends Node

const Service := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const LegacyProbability := preload("res://tests/helpers/legacy_drop_probability_policy.gd")
const Names := preload("res://scripts/ui_item_name_style.gd")
const COMPILED_PATH := "res://assets/data/drop/dpv2_user_loot_sheet_authority_v1.json"


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var legacy := LegacyProbability.new()
	assert(legacy.valid, "exact v80 historical dependencies must validate")
	_test_archived_v81_relationship(legacy)
	var service := Service.new()
	_test_current_sheet_probability(service)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100
	var found := false
	var fate_record: Dictionary = {}
	for i in range(150):
		var before := rng.state
		var audit: Dictionary = service.roll_monster_drops(76, rng, true)
		var audit_rng_state := rng.state
		rng.state = before
		var lean: Dictionary = service.roll_monster_drops(76, rng, false)
		assert(audit.reason.is_empty() and lean.reason.is_empty(), str(audit.rejected_entries) + str(lean.rejected_entries))
		assert(audit.items == lean.items and audit.gold_drops == lean.gold_drops)
		assert(audit.item_records == lean.item_records)
		assert(rng.state == audit_rng_state, "Fate Blade audit/lean RNG consumption diverged")
		for item: Dictionary in audit.item_records:
			if int(item.get("output_item_id", -1)) == 110:
				found = true
				fate_record = item
	assert(found, "Fate Blade must reach current compiled-table materialized rewards")
	var instance_record := PlayerState.create_drop_item_instance(fate_record, "v81-real-fate")
	assert(instance_record.identity_status == "resolved" and not instance_record.item_instance.is_empty())
	var received := PlayerState.receive_loot_batch_partial([instance_record])
	assert(received.success_count == 1 and PlayerState.item_count("命运之刃") == 1)
	for id in [228, 229, 230, 231, 244, 245, 246, 247, 248, 249]:
		assert(Names.describe({"item_id": id}).group == "wooma")
		assert(LootPreferences.filter_threshold_for_item(id) == 2)
	assert(Names.describe({"item_id": 110}).group == "zuma")
	assert(LootPreferences.filter_threshold_for_item(110) == 0)
	service.free()
	print("RUNTIME_FOLLOWUP_V81_PASS archive_reference=1/16 archive_fate=1/24 old_slots=108 production_reference=1/5 production_fate=1/15 sets=10")
	get_tree().quit()


func _test_archived_v81_relationship(legacy: RefCounted) -> void:
	var old: Dictionary = legacy.profile_v80(76)
	var profile: Dictionary = legacy.profile_v81(76)
	assert(old.slots.size() == 108)
	assert(profile.slots.slice(0, old.slots.size()) == old.slots)
	assert(profile.slots.size() == old.slots.size() + 1)
	for slot: Dictionary in old.slots:
		assert(legacy.probability_v81(76, str(slot.slot_uid)) == legacy.probability_v80(76, str(slot.slot_uid)), "v81 changed an existing archived slot")
	var reference: Dictionary = legacy.probability_v81(76, "dpv2.direct.m76.slot_029")
	var fate: Dictionary = legacy.probability_v81(76, "dpv2.user.v81.m76.fate_blade")
	assert(fate.ok and fate.canonical_item_id == 110)
	assert(reference.final_numerator == 1 and reference.final_denominator == 16)
	assert(fate.final_numerator == 1 and fate.final_denominator == 24)
	for stage: String in ["base", "effective", "selected", "final"]:
		assert(int(fate[stage + "_numerator"]) * int(reference[stage + "_denominator"]) * 3 == int(fate[stage + "_denominator"]) * int(reference[stage + "_numerator"]) * 2)
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.production
	var original_enabled: bool = production.enabled
	production.enabled = false
	var unboosted_reference: Dictionary = legacy.probability_v81(76, "dpv2.direct.m76.slot_029")
	var unboosted_fate: Dictionary = legacy.probability_v81(76, "dpv2.user.v81.m76.fate_blade")
	# Restore the shared historical switch before asserting the result.
	production.enabled = original_enabled
	assert(unboosted_fate.ok and unboosted_fate.final_numerator * unboosted_reference.final_denominator * 3 == unboosted_fate.final_denominator * unboosted_reference.final_numerator * 2)


func _test_current_sheet_probability(service: Node) -> void:
	var compiled: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(COMPILED_PATH))
	var expected_slots: Array = []
	for monster: Dictionary in compiled.monsters:
		if int(monster.monster_id) == 76:
			expected_slots = monster.slots
			break
	assert(not expected_slots.is_empty(), "current compiled m76 profile missing")
	var profile: Dictionary = service._production_profile(76)
	assert(profile.slots == expected_slots, "production must use exactly the compiled slots")
	for slot: Dictionary in expected_slots:
		var probability: Dictionary = service._production_probability(76, str(slot.slot_uid))
		assert(probability.ok)
		assert(int(probability.final_numerator) == int(slot.final_numerator), str(slot.slot_uid))
		assert(int(probability.final_denominator) == int(slot.final_denominator), str(slot.slot_uid))
	var reference: Dictionary = service._production_probability(76, "dpv2.direct.m76.slot_029")
	var fate: Dictionary = service._production_probability(76, "dpv2.user.v81.m76.fate_blade")
	assert(reference.ok and reference.final_numerator == 1 and reference.final_denominator == 5)
	assert(fate.ok and fate.canonical_item_id == 110 and fate.final_numerator == 1 and fate.final_denominator == 15)
	# A retired SPB toggle cannot alter production's compiled probability.
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.production
	var original_enabled: bool = production.enabled
	production.enabled = false
	var unchanged_reference: Dictionary = service._production_probability(76, "dpv2.direct.m76.slot_029")
	var unchanged_fate: Dictionary = service._production_probability(76, "dpv2.user.v81.m76.fate_blade")
	production.enabled = original_enabled
	assert(unchanged_reference == reference and unchanged_fate == fate)
