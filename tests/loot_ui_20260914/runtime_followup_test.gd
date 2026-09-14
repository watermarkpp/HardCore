extends Node
const Service := preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const Names := preload("res://scripts/ui_item_name_style.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded())
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var service := Service.new()
	var profile := service._production_profile(76)
	var old := service._user_balance.extend_profile(GameData.dpv2_direct_profile(76),76)
	assert(profile.slots.slice(0, old.slots.size()) == old.slots)
	assert(profile.slots.size() == old.slots.size() + 1)
	for slot: Dictionary in old.slots:
		var expected := service._user_balance.apply(service._apply_drop_probability_policy(GameData.dpv2_effective_slot_probability(76,slot.slot_uid),GameData.canonical_monster_classification(76)),slot.slot_uid,76)
		assert(service._production_probability(76,slot.slot_uid) == expected, "existing probability changed")
	var reference := service._production_probability(76,"dpv2.direct.m76.slot_029")
	var fate := service._production_probability(76,"dpv2.user.v81.m76.fate_blade")
	assert(fate.ok and fate.canonical_item_id == 110)
	assert(reference.final_numerator == 1 and reference.final_denominator == 16)
	assert(fate.final_numerator == 1 and fate.final_denominator == 24)
	var rng := RandomNumberGenerator.new()
	rng.seed = 8100
	var found := false
	var fate_record: Dictionary = {}
	for i in range(150):
		var before := rng.state
		var audit := service.roll_monster_drops(76,rng,true)
		rng.state = before
		var lean := service.roll_monster_drops(76,rng,false)
		assert(audit.reason.is_empty() and lean.reason.is_empty(), str(audit.rejected_entries) + str(lean.rejected_entries))
		assert(audit.items == lean.items and audit.gold_drops == lean.gold_drops)
		for item: Dictionary in audit.item_records:
			if int(item.get("output_item_id", -1)) == 110:
				found = true
				fate_record = item
	assert(found, "new Fate Blade must reach real materialized rewards")
	var instance_record := PlayerState.create_drop_item_instance(fate_record, "v81-real-fate")
	assert(instance_record.identity_status == "resolved" and not instance_record.item_instance.is_empty())
	var received := PlayerState.receive_loot_batch_partial([instance_record])
	assert(received.success_count == 1 and PlayerState.item_count("命运之刃") == 1)
	for stage: String in ["base", "effective", "selected", "final"]:
		assert(int(fate[stage + "_numerator"]) * int(reference[stage + "_denominator"]) * 3 == int(fate[stage + "_denominator"]) * int(reference[stage + "_numerator"]) * 2)
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.production
	var original_enabled: bool = production.enabled
	production.enabled = false
	var unboosted_reference := service._production_probability(76, "dpv2.direct.m76.slot_029")
	var unboosted_fate := service._production_probability(76, "dpv2.user.v81.m76.fate_blade")
	assert(unboosted_fate.ok and unboosted_fate.final_numerator * unboosted_reference.final_denominator * 3 == unboosted_fate.final_denominator * unboosted_reference.final_numerator * 2)
	production.enabled = original_enabled
	for id in [228,229,230,231,244,245,246,247,248,249]:
		assert(Names.describe({"item_id":id}).group == "wooma")
		assert(LootPreferences.filter_threshold_for_item(id) == 2)
	assert(Names.describe({"item_id":110}).group == "zuma")
	assert(LootPreferences.filter_threshold_for_item(110) == 0)
	service.free()
	print("RUNTIME_FOLLOWUP_V81_PASS reference=1/16 fate=1/24 old_slots_unchanged=108 sets=10")
	get_tree().quit()
