extends Node

const CATALOG_PATH := "res://assets/data/runtime/canonical_monster_catalog.json"
const EXPECTED_SOURCE_PROFILE_COUNT := 156
const EXPECTED_SOURCE_ROW_COUNT := 7032
const EXPECTED_ENABLED_SOURCE_ROW_COUNT := 5995
const EXPECTED_NON_LOOT_SOURCE_ROW_COUNT := 1037
const EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT := 1
const EXPECTED_RUNTIME_PROFILE_COUNT := 156
const EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT := 131
const EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT := 25
const EXPECTED_RUNTIME_SLOT_COUNT := 5995


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(
		GameData.ensure_loaded(),
		"GameData failed to load: %s" % GameData.load_error
	)
	assert(GameData.is_dpv2_direct_baseline_loaded())
	assert(LootRuntime.has_method("_chance_denominator"))
	_test_exact_canonical_id_join()
	_test_dual_view_counts()
	_test_malformed_provenance_correction()
	_test_direct_roll_and_non_loot_gate()
	print(
		"MONSTER_DROP_P1A_RUNTIME_CONTRACT_PASS: "
		+ "source=156/7032/5995/1037/1 "
		+ "compiled=156/131/25/5995 "
		+ "direct_id_join=canonical_monster_id"
	)
	get_tree().quit(0)


func _load_catalog() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(CATALOG_PATH)
	)
	assert(parsed is Dictionary, "canonical catalog is not an object")
	return parsed


func _catalog_profile_to_id(catalog: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var entries_value: Variant = catalog.get("entries_by_id", {})
	assert(entries_value is Dictionary)
	for raw_id: Variant in (entries_value as Dictionary).keys():
		var entry_value: Variant = (entries_value as Dictionary).get(
			raw_id,
			{}
		)
		assert(entry_value is Dictionary)
		var entry: Dictionary = entry_value
		var canonical_id := int(raw_id)
		assert(int(entry.get("monster_id", -1)) == canonical_id)
		var source_profile_id := str(entry.get("drop_profile_id", ""))
		assert(not source_profile_id.is_empty())
		assert(not result.has(source_profile_id))
		result[source_profile_id] = canonical_id
	return result


func _test_exact_canonical_id_join() -> void:
	var catalog := _load_catalog()
	var profile_map := _catalog_profile_to_id(catalog)
	assert(int(profile_map.get("drop.18", -1)) == 18)
	var direct := GameData.dpv2_direct_profile(18)
	assert(not direct.is_empty())
	assert(int(direct.get("canonical_monster_id", -1)) == 18)
	assert(str(direct.get("drop_profile_id", "")) == "dpv2.direct.18")
	assert(str(profile_map.get("drop.18", "")) == "18")
	assert(str(direct.get("drop_profile_id", "")) != "drop.18")
	assert(GameData.dpv2_direct_profile(999999).is_empty())


func _test_dual_view_counts() -> void:
	var catalog := _load_catalog()
	var source_profiles_value: Variant = catalog.get("drop_profiles", {})
	assert(source_profiles_value is Dictionary)
	var source_profiles: Dictionary = source_profiles_value
	assert(source_profiles.size() == EXPECTED_SOURCE_PROFILE_COUNT)
	var profile_map := _catalog_profile_to_id(catalog)

	var source_rows := 0
	var enabled_source_rows := 0
	var disabled_source_rows := 0
	var malformed_source_rows := 0
	for raw_profile_id: Variant in source_profiles.keys():
		var source_profile_id := str(raw_profile_id)
		var source_profile_value: Variant = source_profiles.get(
			source_profile_id,
			{}
		)
		assert(source_profile_value is Dictionary)
		var source_profile: Dictionary = source_profile_value
		var entries_value: Variant = source_profile.get("entries", [])
		assert(entries_value is Array)
		var entries: Array = entries_value
		var canonical_id := int(profile_map.get(source_profile_id, -1))
		assert(canonical_id > 0)
		var direct := GameData.dpv2_direct_profile(canonical_id)
		assert(not direct.is_empty())
		var enabled := bool(direct.get("drop_enabled", false))
		var direct_slots: Array = direct.get("slots", [])
		assert(enabled or direct_slots.is_empty())
		assert(not enabled or direct_slots.size() == entries.size())
		for ordinal: int in range(entries.size()):
			var entry: Dictionary = entries[ordinal]
			source_rows += 1
			if int(LootRuntime.call(
				"_chance_denominator",
				str(entry.get("chance", ""))
			)) > 0:
				pass
			else:
				malformed_source_rows += 1
			if not enabled:
				disabled_source_rows += 1
				continue
			enabled_source_rows += 1
			var slot: Dictionary = direct_slots[ordinal]
			assert(str(slot.get("slot_uid", "")).begins_with(
				"dpv2.direct.m%d." % canonical_id
			))
			assert(bool(GameData.dpv2_direct_resolve_slot_reward(slot).get(
				"ok",
				false
			)))
			assert(bool(GameData.dpv2_direct_slot_probability(
				canonical_id,
				str(slot.get("slot_uid", ""))
			).get("ok", false)))

	assert(source_rows == EXPECTED_SOURCE_ROW_COUNT)
	assert(enabled_source_rows == EXPECTED_ENABLED_SOURCE_ROW_COUNT)
	assert(disabled_source_rows == EXPECTED_NON_LOOT_SOURCE_ROW_COUNT)
	assert(
		malformed_source_rows
			== EXPECTED_MALFORMED_SOURCE_PROVENANCE_COUNT
	)

	var baseline: Dictionary = GameData.dpv2_direct_baseline
	var baseline_profiles: Array = baseline.get("profiles", [])
	assert(baseline_profiles.size() == EXPECTED_RUNTIME_PROFILE_COUNT)
	var enabled_profiles := 0
	var non_loot_profiles := 0
	var compiled_slots := 0
	var origin_counts := {}
	for raw_profile: Variant in baseline_profiles:
		assert(raw_profile is Dictionary)
		var profile: Dictionary = raw_profile
		if bool(profile.get("drop_enabled", false)):
			enabled_profiles += 1
		else:
			non_loot_profiles += 1
		var slots: Array = profile.get("slots", [])
		compiled_slots += slots.size()
		if bool(profile.get("drop_enabled", false)):
			var origin := str(profile.get("baseline_origin", ""))
			origin_counts[origin] = int(origin_counts.get(origin, 0)) \
				+ slots.size()
	assert(enabled_profiles == EXPECTED_RUNTIME_ENABLED_PROFILE_COUNT)
	assert(non_loot_profiles == EXPECTED_RUNTIME_NON_LOOT_PROFILE_COUNT)
	assert(compiled_slots == EXPECTED_RUNTIME_SLOT_COUNT)
	assert(int(origin_counts.get("LEGACY_21CQ_MONITEMS", 0)) == 5926)
	assert(int(origin_counts.get("PROJECT_EXTENSION", 0)) == 69)


func _test_malformed_provenance_correction() -> void:
	var catalog := _load_catalog()
	var source_profiles: Dictionary = catalog.get("drop_profiles", {})
	var anomaly: Dictionary = source_profiles.get("drop.168", {})
	var entries: Array = anomaly.get("entries", [])
	assert(entries.size() > 19)
	var source_row: Dictionary = entries[19]
	assert(int(source_row.get("line_number", -1)) == 20)
	assert(str(source_row.get("slot_index", "")) == "slot_020")
	assert(str(source_row.get("chance", "")) == "1/00")
	assert(str(source_row.get("raw_text", "")) == "1/00 灵魂战衣(男)")
	assert(int(LootRuntime.call(
		"_chance_denominator",
		str(source_row.get("chance", ""))
	)) < 0)

	var direct := GameData.dpv2_direct_profile(168)
	var direct_slot: Dictionary = (direct.get("slots", []) as Array)[19]
	assert(str(direct_slot.get("source_provenance_id", "")) \
		== "dpv2.source.m168.slot_020")
	assert(int(direct_slot.get("base_numerator", -1)) == 1)
	assert(int(direct_slot.get("base_denominator", -1)) == 2800)
	var probability := GameData.dpv2_direct_slot_probability(
		168,
		str(direct_slot.get("slot_uid", ""))
	)
	assert(bool(probability.get("ok", false)), str(probability))
	assert(int(probability.get("final_numerator", -1)) == 1)
	assert(int(probability.get("final_denominator", -1)) == 2800)


func _test_direct_roll_and_non_loot_gate() -> void:
	var service := LootRuntime
	var non_loot_rng := RandomNumberGenerator.new()
	non_loot_rng.seed = 226
	var non_loot := service.roll_monster_drops(226, non_loot_rng)
	assert(bool(non_loot.get("configured", false)))
	assert(str(non_loot.get("reason", "")) == "drop_disabled")
	assert(int(non_loot.get("rng_roll_count", -1)) == 0)
	assert((non_loot.get("attempts", []) as Array).is_empty())

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var direct_profile := GameData.dpv2_direct_profile(31)
	var direct_slots: Array = direct_profile.get("slots", [])
	var roll := service.roll_monster_drops(31, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("source_entry_count", -1)) == direct_slots.size())
	assert(int(roll.get("resolution_attempted_count", -1)) == direct_slots.size())
	assert(int(roll.get("reward_resolved_enabled_slots", -1)) \
		== direct_slots.size())
	assert(int(roll.get("probability_resolved_enabled_slots", -1)) \
		== direct_slots.size())
	assert(int(roll.get("rng_eligible_slots", -1)) == direct_slots.size())
	assert(int(roll.get("rng_roll_count", -1)) == direct_slots.size())
	assert(bool(roll.get("all_resolved_slots_rng", false)))
	assert(bool(roll.get(
		"all_enabled_resolved_slots_rng_before_overflow",
		false
	)))
	assert(int(roll.get("ground_output_count", 0)) <= 9)
	assert(
		int(roll.get("ground_output_count", 0))
			+ int(roll.get("overflow_discarded_count", 0))
		== int(roll.get("successful_roll_count", -1))
	)
	var attempts: Array = roll.get("attempts", [])
	assert(attempts.size() == direct_slots.size())
	var seen_slots := {}
	for raw_attempt: Variant in attempts:
		assert(raw_attempt is Dictionary)
		var attempt: Dictionary = raw_attempt
		var slot_uid := str(attempt.get("slot_uid", ""))
		assert(not seen_slots.has(slot_uid))
		seen_slots[slot_uid] = true
		for field: String in [
			"canonical_item_id",
			"base_numerator",
			"base_denominator",
			"base_probability",
			"global_scale",
			"final_probability",
			"draw",
			"draw_success",
			"overflow",
			"protected_overflow",
			"baseline_origin",
			"source_provenance_id",
		]:
			assert(attempt.has(field), "%s absent: %s" % [field, attempt])
	var debug: Array = roll.get("debug", [])
	var slot_attempts: Array = roll.get("slot_attempts", [])
	assert(debug == attempts)
	assert(slot_attempts == attempts)
