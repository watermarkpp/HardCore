extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)
const LootPickupScript := preload("res://scripts/loot_pickup.gd")

const FEMALE_TO_MALE_DROP_NAMES := {
	117: "布衣(男)",
	119: "轻型盔甲(男)",
	121: "中型盔甲(男)",
	123: "重盔甲(男)",
	125: "魔法长袍(男)",
	127: "灵魂战衣(男)",
	129: "战神盔甲(男)",
	131: "恶魔长袍(男)",
	133: "幽灵战衣(男)",
	141: "天魔神甲",
	143: "法神披风",
	145: "天尊道袍",
}


func _ready() -> void:
	assert(GameData.ensure_loaded(), GameData.load_error)
	var service := LootRuntimeScript.new()
	_test_female_equipment_output(service)
	_test_stable_item_identity_and_ground_descriptor(service)
	_test_small_monster_probability(service)
	_test_elite_boss_solar_probability(service)
	_test_corpse_king_boost_consumption(service)
	_test_all_runtime_drop_identities(service)
	_test_prewarm_uses_output_identity(service)
	_test_lean_runtime_cache_stays_hot(service)
	print("LOOT_RUNTIME_ITEM_POLICY_PASS female_pairs=12 small_monster=ordinary")
	get_tree().quit(0)


func _test_all_runtime_drop_identities(service: Node) -> void:
	var checked := {}
	var failures: Array[String] = []
	for monster: Dictionary in GameData.monsters:
		var monster_id := GameData.canonical_monster_id(monster.get("monster_id", -1))
		var profile := GameData.dpv2_direct_profile(monster_id)
		for slot: Dictionary in profile.get("slots", []):
			var reward: Dictionary = service._lean_reward(slot)
			if not bool(reward.get("ok", false)) or str(reward.get("kind", "")) == "gold":
				continue
			var item_id := int(slot.get("canonical_item_id", -1))
			var output_name := str(reward.get("item_name", ""))
			var key := "%d:%s" % [item_id, output_name]
			if checked.has(key):
				continue
			checked[key] = true
			var record: Dictionary = service._drop_output_item_record(item_id, output_name)
			if str(record.get("identity_status", "")) != "resolved":
				failures.append("monster=%d %s" % [monster_id, key])
	assert(checked.size() > 0, "runtime drop identity sweep did not inspect any items")
	assert(failures.is_empty(), "unresolved runtime drop identities: %s" % [failures])
	print("ALL_RUNTIME_DROP_IDENTITIES_PASS unique=%d" % checked.size())


func _test_female_equipment_output(service: Node) -> void:
	for source_id: int in FEMALE_TO_MALE_DROP_NAMES:
		var expected_name := str(FEMALE_TO_MALE_DROP_NAMES[source_id])
		assert(
			service._drop_output_item_name(source_id, "female-source") == expected_name,
			"female drop replacement failed: %d" % source_id,
		)
		var target := GameData.get_item_record(expected_name)
		assert(not target.is_empty(), "male drop target missing: %s" % expected_name)
		assert(str(target.get("kind", "")) == "equipment", str(target))
	assert(service._drop_output_item_name(116, "布衣(男)") == "布衣(男)")


func _test_stable_item_identity_and_ground_descriptor(service: Node) -> void:
	var potion_record: Dictionary = service._drop_output_item_record(
		910013,
		"疾风药水",
	)
	assert(str(potion_record.get("identity_status", "")) == "resolved", str(potion_record))
	assert(int(potion_record.get("item_id", -1)) == 910013, str(potion_record))
	assert(int(potion_record.get("canonical_item_id", -1)) == 910013)
	assert(str(potion_record.get("canonical_name", "")) == "疾风药水")
	assert(str(potion_record.get("item_name", "")) == "疾风药水")
	assert(int(potion_record.get("output_item_id", -1)) == 910013)
	var potion_output: Dictionary = potion_record.get("output_record", {})
	var potion_art: Dictionary = potion_output.get("art", {})
	var potion_ground_icon: Dictionary = potion_art.get("groundIcon", {})
	assert(
		str(potion_ground_icon.get("path", "")).ends_with("DnItems_00420.png"),
		str(potion_output),
	)
	var potion_descriptor := LootPickupScript.ground_visual_descriptor_for_record(
		potion_record,
	)
	assert(str(potion_descriptor.get("path", "")).ends_with("DnItems_00420.png"))
	var pickup := LootPickupScript.new()
	pickup.setup_item_record(potion_record, null)
	assert(pickup.item_id == 910013)
	assert(pickup.item_record.get("canonical_item_id", -1) == 910013)
	assert(pickup.item_name == "疾风药水")
	pickup.free()

	var female_record: Dictionary = service._drop_output_item_record(
		117,
		"布衣(女)",
	)
	assert(str(female_record.get("identity_status", "")) == "resolved", str(female_record))
	assert(int(female_record.get("item_id", -1)) == 116)
	assert(int(female_record.get("source_item_id", -1)) == 117)
	assert(int(female_record.get("canonical_item_id", -1)) == 116)
	assert(str(female_record.get("canonical_name", "")) == "布衣(男)")
	assert(str(female_record.get("source_canonical_name", "")) == "布衣(女)")
	assert(str(female_record.get("item_name", "")) == "布衣(男)")
	assert(int(female_record.get("output_item_id", -1)) == 116)
	var female_pickup := LootPickupScript.new()
	female_pickup.setup_item_record(female_record, null)
	assert(female_pickup.item_id == 116, str(female_pickup.item_record))
	assert(female_pickup.item_name == "布衣(男)")
	female_pickup.free()

	# Unknown labels remain name-compatible but cannot synthesize a stable ID.
	var unresolved: Dictionary = service._drop_output_item_record(910013, "疾风药水-猜测")
	assert(str(unresolved.get("identity_status", "")) == "unresolved")
	assert(int(unresolved.get("item_id", -1)) == -1)
	assert(str(unresolved.get("item_name", "")) == "疾风药水-猜测")


func _test_small_monster_probability(service: Node) -> void:
	assert(GameData.canonical_monster_classification(19) == "ordinary")
	assert(GameData.canonical_monster_classification(31) == "elite")
	assert(GameData.canonical_monster_classification(76) == "boss")
	var equipment_probability := {
		"canonical_item_id": 116,
		"final_numerator": 1,
		"final_denominator": 20,
		"final_probability": 0.05,
	}
	var equipment_adjusted: Dictionary = service._apply_small_monster_probability_policy(
		equipment_probability,
		"ordinary",
	)
	assert(int(equipment_adjusted.final_numerator) == 1)
	assert(int(equipment_adjusted.final_denominator) == 60)
	assert(int(equipment_adjusted.small_monster_denominator_multiplier) == 3)
	assert(int(equipment_probability.final_denominator) == 20)

	var shenshui_probability := {
		"canonical_item_id": 910001,
		"final_numerator": 1,
		"final_denominator": 20,
		"final_probability": 0.05,
	}
	var shenshui_adjusted: Dictionary = service._apply_small_monster_probability_policy(
		shenshui_probability,
		"ordinary",
	)
	assert(int(shenshui_adjusted.final_denominator) == 120)
	assert(int(shenshui_adjusted.small_monster_denominator_multiplier) == 6)

	var elite_unchanged: Dictionary = service._apply_small_monster_probability_policy(
		equipment_probability,
		"elite",
	)
	var boss_unchanged: Dictionary = service._apply_small_monster_probability_policy(
		shenshui_probability,
		"boss",
	)
	assert(elite_unchanged == equipment_probability)
	assert(boss_unchanged == shenshui_probability)

	var ordinary_gold := {
		"canonical_item_id": -1,
		"final_numerator": 1,
		"final_denominator": 4,
		"final_probability": 0.25,
	}
	assert(
		service._apply_small_monster_probability_policy(ordinary_gold, "ordinary")
		== ordinary_gold
	)

	var rng := RandomNumberGenerator.new()
	rng.seed = 19003176
	var ordinary_roll: Dictionary = service.roll_monster_drops(19, rng)
	assert(bool(ordinary_roll.get("configured", false)), str(ordinary_roll))
	for attempt: Dictionary in ordinary_roll.get("attempts", []):
		var attempt_item_id := int(attempt.get("canonical_item_id", -1))
		if attempt_item_id in [910001, 910003, 910004]:
			assert(int(attempt.get("small_monster_denominator_multiplier", 1)) == 6)
		elif GameData.canonical_item_kind(attempt_item_id) == "equipment":
			assert(int(attempt.get("small_monster_denominator_multiplier", 1)) == 3)

	rng.seed = 76001931
	var boss_roll: Dictionary = service.roll_monster_drops(76, rng)
	assert(bool(boss_roll.get("configured", false)), str(boss_roll))
	for attempt: Dictionary in boss_roll.get("attempts", []):
		var item_id := int(attempt.get("canonical_item_id", -1))
		if item_id in [920014, 920016]:
			assert(int(attempt.get("elite_boss_solar_denominator_multiplier", 1)) == 2)
		else:
			assert(int(attempt.get("drop_denominator_multiplier", 1)) == 1)


func _test_elite_boss_solar_probability(service: Node) -> void:
	for classification: String in ["elite", "boss"]:
		for item_id: int in [920014, 920016]:
			var source := {
				"canonical_item_id": item_id,
				"final_numerator": 1,
				"final_denominator": 4,
				"final_probability": 0.25,
			}
			var adjusted: Dictionary = service._apply_drop_probability_policy(
				source,
				classification,
			)
			assert(int(adjusted.final_numerator) == 1)
			assert(int(adjusted.final_denominator) == 8)
			assert(
				int(adjusted.elite_boss_solar_denominator_multiplier) == 2
			)
			assert(int(source.final_denominator) == 4)

	var ordinary_solar := {
		"canonical_item_id": 920014,
		"final_numerator": 1,
		"final_denominator": 4,
		"final_probability": 0.25,
	}
	assert(
		service._apply_drop_probability_policy(ordinary_solar, "ordinary")
		== ordinary_solar
	)
	var boss_other_item := {
		"canonical_item_id": 116,
		"final_numerator": 1,
		"final_denominator": 4,
		"final_probability": 0.25,
	}
	assert(
		service._apply_drop_probability_policy(boss_other_item, "boss")
		== boss_other_item
	)


func _test_corpse_king_boost_consumption(service: Node) -> void:
	# ID 89 is the exact canonical 尸王 profile.  The direct/effective tables
	# retain base 1/1000 and the human-frozen x25 boost as effective 1/40.
	var profile: Dictionary = GameData.dpv2_direct_profile(89)
	var target_slot: Dictionary = {}
	for raw_slot: Variant in profile.get("slots", []):
		if raw_slot is Dictionary and int(raw_slot.get("canonical_item_id", -1)) == 230:
			target_slot = raw_slot
			break
	assert(not target_slot.is_empty(), str(profile))
	var slot_uid := str(target_slot.get("slot_uid", ""))
	var effective := GameData.dpv2_effective_slot_probability(89, slot_uid)
	assert(bool(effective.get("ok", false)), str(effective))
	assert(int(effective.get("base_numerator", 0)) == 1)
	assert(int(effective.get("base_denominator", 0)) == 1000)
	assert(int(effective.get("boost_multiplier_numerator", 0)) == 25)
	assert(int(effective.get("boost_multiplier_denominator", 0)) == 1)
	assert(int(effective.get("effective_numerator", 0)) == 1)
	assert(int(effective.get("effective_denominator", 0)) == 40)
	assert(int(effective.get("final_denominator", 0)) == 40)
	var expected_item_ids := [920043, 920008, 920004, 920011, 920051, 920009, 920036, 230]
	var resolved_identity_count := 0
	for raw_identity_slot: Variant in profile.get("slots", []):
		if not raw_identity_slot is Dictionary:
			continue
		var identity_slot: Dictionary = raw_identity_slot
		var identity_reward := GameData.dpv2_direct_resolve_slot_reward(identity_slot)
		assert(bool(identity_reward.get("ok", false)), str(identity_reward))
		var identity_item_id := int(identity_slot.get("canonical_item_id", -1))
		var item_record: Dictionary = service._drop_output_item_record(
			identity_item_id,
			str(identity_reward.get("item_name", "")),
		)
		assert(str(item_record.get("identity_status", "")) == "resolved", str(item_record))
		assert(int(item_record.get("item_id", -1)) > 0, str(item_record))
		assert(int(item_record.get("source_item_id", -1)) == identity_item_id)
		assert(expected_item_ids.has(identity_item_id))
		resolved_identity_count += 1
	assert(resolved_identity_count == expected_item_ids.size())
	var single_zero_probability := 1.0
	var enabled_slot_count := 0
	for raw_enabled_slot: Variant in profile.get("slots", []):
		if not raw_enabled_slot is Dictionary:
			continue
		var enabled_probability := GameData.dpv2_effective_slot_probability(
			89,
			str(raw_enabled_slot.get("slot_uid", "")),
		)
		assert(bool(enabled_probability.get("ok", false)), str(enabled_probability))
		var enabled_numerator := int(enabled_probability.get("final_numerator", 0))
		var enabled_denominator := int(enabled_probability.get("final_denominator", 0))
		assert(enabled_numerator > 0 and enabled_denominator >= enabled_numerator)
		single_zero_probability *= 1.0 - float(enabled_numerator) / float(enabled_denominator)
		enabled_slot_count += 1
	assert(enabled_slot_count == 8)
	var ten_zero_probability := pow(single_zero_probability, 10.0)
	# All eight ID89 enabled rows are independently attempted. This is the
	# probability evidence for ten zero-drop kills; it does not turn ten trials
	# into a deterministic failure signal.
	assert(abs(single_zero_probability - 0.8374190763043114) < 0.000000001)
	assert(abs(ten_zero_probability - 0.16960103507654997) < 0.000000001)

	var rng := RandomNumberGenerator.new()
	rng.seed = 8900901
	var boosted_successes := 0
	var all_zero_rolls := 0
	var any_drop_rolls := 0
	for _index: int in range(512):
		var roll: Dictionary = service.roll_monster_drops(89, rng, true)
		assert(bool(roll.get("configured", false)), str(roll))
		if int(roll.get("successful_roll_count", 0)) == 0:
			all_zero_rolls += 1
		else:
			any_drop_rolls += 1
		var item_records: Variant = roll.get("item_records", [])
		var legacy_items: Variant = roll.get("items", [])
		assert(item_records is Array)
		assert(legacy_items is Array)
		assert((item_records as Array).size() == (legacy_items as Array).size())
		var found_target_attempt := false
		for attempt: Dictionary in roll.get("attempts", []):
			if int(attempt.get("canonical_item_id", -1)) != 230:
				continue
			found_target_attempt = true
			assert(int(attempt.get("base_denominator", 0)) == 1000)
			assert(int(attempt.get("boost_multiplier_numerator", 0)) == 25)
			assert(int(attempt.get("effective_denominator", 0)) == 40)
			assert(int(attempt.get("final_denominator", 0)) == 40)
			assert(int(attempt.get("draw", 0)) >= 1)
			assert(int(attempt.get("draw", 0)) <= 40)
			if bool(attempt.get("draw_success", false)):
				boosted_successes += 1
		assert(found_target_attempt, str(roll.get("attempts", [])))
	assert(boosted_successes > 0, "fixed seed never consumed corpse-king x25 effective chance")
	assert(all_zero_rolls > 0 and any_drop_rolls > 0)
	var fixed_seed_stats := "CORPSE_KING_DROP_FIXED_SEED_STATS seed=8900901 rolls=512 all_zero=%d any_drop=%d item230_success=%d" % [
		all_zero_rolls,
		any_drop_rolls,
		boosted_successes,
	]
	print(fixed_seed_stats)


func _test_prewarm_uses_output_identity(service: Node) -> void:
	var names: Array[String] = service.possible_item_names_for_monster_ids([19])
	assert(names.has("布衣(男)"), str(names))
	assert(not names.has("布衣(女)"), str(names))


func _test_lean_runtime_cache_stays_hot(service: Node) -> void:
	service.clear_runtime_resolution_cache_for_test()
	service.possible_item_names_for_monster_ids([19])
	var warmed: Dictionary = service.runtime_resolution_cache_debug_snapshot()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026090317
	for _index: int in range(512):
		var roll: Dictionary = service.roll_monster_drops(19, rng, false)
		assert(bool(roll.get("configured", false)), str(roll))
	var after: Dictionary = service.runtime_resolution_cache_debug_snapshot()
	assert(after.get("misses", {}) == warmed.get("misses", {}), str(after))
	assert(int(after.get("profile_count", 0)) == int(warmed.get("profile_count", -1)))
	assert(int(after.get("probability_count", 0)) == int(warmed.get("probability_count", -1)))
	assert(int(after.get("reward_count", 0)) == int(warmed.get("reward_count", -1)))
