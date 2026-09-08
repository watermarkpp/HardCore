extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)
const LootPickupScript := preload("res://scripts/loot_pickup.gd")
const V505_SOURCE_AUTHORITY_PATH := (
	"res://assets/data/drop/dpv2_21cq_verified_profile_authority_v1.json"
)

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


func _v505_source_record(monster_id: int) -> Dictionary:
	assert(
		FileAccess.file_exists(V505_SOURCE_AUTHORITY_PATH),
		"V505 source authority missing"
	)
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(V505_SOURCE_AUTHORITY_PATH)
	)
	assert(parsed is Dictionary, "V505 source authority invalid JSON")
	var authority: Dictionary = parsed as Dictionary
	assert(
		str(authority.get("schema", ""))
		== "hardcore.dpv2.21cq_verified_profile_authority.v1",
		"V505 source authority schema drifted"
	)
	for raw_record: Variant in authority.get("records", []):
		if (
			raw_record is Dictionary
			and int((raw_record as Dictionary).get("canonical_monster_id", -1))
			== monster_id
		):
			return (raw_record as Dictionary).duplicate(true)
	return {}


func _test_corpse_king_boost_consumption(service: Node) -> void:
	# V505 adopts the exact frozen 21CQ full profile for canonical ID89 尸王.
	# Validate the source-driven profile and runtime boost consumption rather
	# than the retired fixed eight-slot fixture.
	var source_record := _v505_source_record(89)
	assert(
		str(source_record.get("source_status", "")) == "FULL_21CQ_VERIFIED",
		"ID89 corpse king must be FULL_21CQ_VERIFIED"
	)
	var profile: Dictionary = GameData.dpv2_direct_profile(89)
	var slots: Array = profile.get("slots", [])
	var source_rows: Array = source_record.get("source_rows", [])
	var expected_source_rows := int(source_record.get("source_row_count", -1))
	assert(expected_source_rows > 0, str(source_record))
	assert(slots.size() == expected_source_rows, str(profile))
	assert(source_rows.size() == expected_source_rows, str(source_record))

	var contract: Dictionary = GameData.dpv2_single_player_effective_probability.get(
		"repair_v5_contract", {}
	)
	var book_ids := {}
	for raw_book_id: Variant in contract.get("book_item_ids", []):
		book_ids[int(raw_book_id)] = true
	assert(not book_ids.is_empty(), "V505 book contract is empty")

	var effective_by_uid := {}
	for raw_effective: Variant in GameData.dpv2_single_player_effective_probability.get(
		"records", []
	):
		if not raw_effective is Dictionary:
			continue
		var effective_record: Dictionary = raw_effective
		if int(effective_record.get("canonical_monster_id", -1)) != 89:
			continue
		effective_by_uid[str(effective_record.get("slot_uid", ""))] = effective_record
	assert(effective_by_uid.size() == slots.size(), "ID89 effective ledger/profile count drift")

	var item_identity_count := 0
	var gold_reward_count := 0
	var corpse_book_slot_count := 0
	var single_zero_probability := 1.0
	for raw_slot: Variant in slots:
		assert(raw_slot is Dictionary)
		var slot: Dictionary = raw_slot
		var slot_uid := str(slot.get("slot_uid", ""))
		assert(not slot_uid.is_empty())
		var reward := GameData.dpv2_direct_resolve_slot_reward(slot)
		assert(bool(reward.get("ok", false)), str(reward))

		var probability := GameData.dpv2_effective_slot_probability(89, slot_uid)
		assert(bool(probability.get("ok", false)), str(probability))
		var final_n := int(probability.get("final_numerator", 0))
		var final_d := int(probability.get("final_denominator", 0))
		assert(final_n > 0 and final_d >= final_n, str(probability))
		single_zero_probability *= 1.0 - float(final_n) / float(final_d)

		var ledger_value: Variant = effective_by_uid.get(slot_uid, {})
		assert(ledger_value is Dictionary and not (ledger_value as Dictionary).is_empty())
		var ledger: Dictionary = ledger_value as Dictionary

		if str(reward.get("kind", "")) == "gold":
			gold_reward_count += 1
			assert(slot.has("gold_amount"))
			assert(int(reward.get("gold_amount", -1)) == int(slot.get("gold_amount", -2)))
			continue

		var item_id := int(slot.get("canonical_item_id", -1))
		assert(item_id > 0, str(slot))
		var item_record: Dictionary = service._drop_output_item_record(
			item_id,
			str(reward.get("item_name", "")),
		)
		assert(str(item_record.get("identity_status", "")) == "resolved", str(item_record))
		assert(int(item_record.get("item_id", -1)) > 0, str(item_record))
		assert(int(item_record.get("source_item_id", -1)) == item_id)
		item_identity_count += 1

		if not book_ids.has(item_id):
			continue
		assert(
			str(ledger.get("repair_v5_rule", "")) == "BOOK_ELITE_BOSS",
			str(ledger)
		)
		var base_n := int(slot.get("base_numerator", 0))
		var base_d := int(slot.get("base_denominator", 0))
		assert(base_n > 0 and base_d >= base_n)
		var expected_n := base_n
		var expected_d := base_d
		if base_n * 20 < base_d:
			expected_n = base_n * 25
			expected_d = base_d
			if expected_n * 20 > expected_d:
				expected_n = 1
				expected_d = 20
		assert(
			final_n * expected_d == expected_n * final_d,
			"ID89 book effective ratio drift: %s" % str(ledger)
		)
		corpse_book_slot_count += 1

	assert(item_identity_count > 0, "ID89 V505 profile resolved no item identities")
	assert(corpse_book_slot_count > 0, "ID89 V505 profile has no source-gated book slot")
	assert(single_zero_probability >= 0.0 and single_zero_probability < 1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 8900901
	var saw_book_attempt := false
	for _index: int in range(64):
		var roll: Dictionary = service.roll_monster_drops(89, rng, true)
		assert(bool(roll.get("configured", false)), str(roll))
		var attempts: Array = roll.get("attempts", [])
		assert(attempts.size() == slots.size(), "ID89 runtime skipped V505 source slots")
		for attempt: Dictionary in attempts:
			var attempt_item_id := int(attempt.get("canonical_item_id", -1))
			if not book_ids.has(attempt_item_id):
				continue
			saw_book_attempt = true
			var attempt_uid := str(attempt.get("slot_uid", ""))
			var expected := GameData.dpv2_effective_slot_probability(89, attempt_uid)
			assert(bool(expected.get("ok", false)), str(expected))
			assert(
				int(attempt.get("final_numerator", 0))
				== int(expected.get("final_numerator", -1))
			)
			assert(
				int(attempt.get("final_denominator", 0))
				== int(expected.get("final_denominator", -1))
			)
	assert(saw_book_attempt, "ID89 runtime never attempted a V505 book slot")
	print(
		"CORPSE_KING_V505_SOURCE_CONTRACT_PASS "
		+ "slots=%d items=%d gold=%d book_slots=%d zero_probability=%f"
		% [
			slots.size(),
			item_identity_count,
			gold_reward_count,
			corpse_book_slot_count,
			single_zero_probability,
		]
	)


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
