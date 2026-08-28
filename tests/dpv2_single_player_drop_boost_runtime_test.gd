extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "SPB authorities failed: %s" % GameData.load_error)
	assert(GameData.is_dpv2_direct_baseline_loaded())
	assert(GameData.is_dpv2_single_player_drop_boost_loaded())
	_test_authority_and_complete_ledger()
	_test_exact_formula_samples()
	_test_real_slot_policies()
	_test_gold_amount_overlay()
	_test_disabled_parity_and_single_global_scale()
	_test_enabled_non_1x_and_missing_row_fail_before_rng()
	_test_production_service_uses_effective_probability()
	_test_overflow_contract_is_unchanged()
	print(
		"DPV2_SINGLE_PLAYER_DROP_BOOST_RUNTIME_PASS: records=6809 "
		+ "auto=4546 common=1357 gold=128 boss=324 unclassified=454 "
		+ "candidate_common=1597 candidate_gold=134 candidate_unclassified=490 "
		+ "ceiling=2203 disabled_mismatch=0 rng_before_overflow=1 ground_limit=9"
	)
	get_tree().quit(0)


func _test_authority_and_complete_ledger() -> void:
	var authority: Dictionary = GameData.dpv2_single_player_drop_boost
	var classification: Dictionary = GameData.dpv2_single_player_item_boost_classification
	var effective: Dictionary = GameData.dpv2_single_player_effective_probability
	assert(str(authority.get("schema", "")) == "hardcore.dpv2.single_player_drop_boost.v1")
	assert(
		str(classification.get("schema", ""))
			== "hardcore.dpv2.single_player_item_boost_classification.v1"
	)
	assert(bool(classification.get("production_active", false)))
	assert(str(classification.get("identity_key", "")) == "canonical_item_id")
	var classification_records: Array = classification.get("records", [])
	assert(classification_records.size() == 233)
	var classification_counts: Dictionary = {}
	var classified_ids: Dictionary = {}
	for raw_classification: Variant in classification_records:
		var classification_record: Dictionary = raw_classification
		var item_id := int(classification_record.get("canonical_item_id", -1))
		var classification_name := str(classification_record.get("classification", ""))
		assert(item_id > 0 and not classified_ids.has(item_id))
		assert(bool(classification_record.get("human_frozen", false)))
		assert(not str(classification_record.get("reason", "")).is_empty())
		assert(not (classification_record.get("evidence", []) as Array).is_empty())
		classified_ids[item_id] = true
		classification_counts[classification_name] = (
			int(classification_counts.get(classification_name, 0)) + 1
		)
	assert(classified_ids.size() == 233)
	assert(classification_counts == {
		"EQUIPMENT": 167,
		"RARE_FUNCTIONAL_CONSUMABLE": 14,
		"COMMON_RECOVERY": 10,
		"BYPASS_UNCLASSIFIED": 42,
	})
	assert(str(effective.get("schema", "")) == "hardcore.dpv2.single_player_effective_probability.v1")
	var production: Dictionary = authority.get("production", {})
	assert(bool(production.get("enabled", false)))
	var multiplier: Dictionary = production.get("boost_multiplier", {})
	var ceiling: Dictionary = production.get("auto_boost_ceiling", {})
	var gold_multiplier: Dictionary = production.get("gold_amount_multiplier", {})
	assert(int(multiplier.get("numerator", 0)) == 25)
	assert(int(multiplier.get("denominator", 0)) == 1)
	assert(int(ceiling.get("numerator", 0)) == 1)
	assert(int(ceiling.get("denominator", 0)) == 20)
	assert(int(gold_multiplier.get("numerator", 0)) == 10)
	assert(int(gold_multiplier.get("denominator", 0)) == 1)
	assert(str(production.get("required_global_drop_rate_preset", "")) == "1x")
	var records: Array = effective.get("records", [])
	assert(records.size() == 6809)
	var uids: Dictionary = {}
	for raw_record: Variant in records:
		assert(raw_record is Dictionary)
		var record: Dictionary = raw_record
		var uid := str(record.get("slot_uid", ""))
		assert(not uid.is_empty() and not uids.has(uid))
		uids[uid] = true
		var direct := GameData.dpv2_direct_slot(uid)
		assert(not direct.is_empty())
		assert(int(record.get("canonical_monster_id", -1)) == int(direct.get("canonical_monster_id", -2)))
		for field: String in [
			"base_numerator", "base_denominator", "source_provenance_id",
			"protected_drop", "overflow_priority", "baseline_origin",
			"canonical_item_id", "gold_amount",
		]:
			assert(record.has(field) == direct.has(field), "%s:%s" % [uid, field])
			if record.has(field):
				assert(record.get(field) == direct.get(field), "%s:%s" % [uid, field])
	assert(uids.size() == 6809)
	var summary: Dictionary = effective.get("summary", {})
	var expected_policy_counts := {
		"AUTO_BOOST": 4546,
		"BYPASS_COMMON_RECOVERY": 1357,
		"BYPASS_GOLD": 128,
		"BYPASS_NEW_ARMOR_BOSS": 324,
		"BYPASS_UNCLASSIFIED": 454,
	}
	var policy_counts: Dictionary = summary.get("effective_policy_counts", {})
	for key: String in expected_policy_counts:
		assert(int(policy_counts.get(key, -1)) == int(expected_policy_counts[key]))
	assert(int(summary.get("ceiling_applied_slots", -1)) == 2203)
	assert(int(summary.get("disabled_counterfactual_mismatch", -1)) == 0)
	assert(int(summary.get("base_mirror_mismatch", -1)) == 0)
	assert(int(summary.get("probability_decreases", -1)) == 0)
	assert(int(summary.get("ceiling_violations", -1)) == 0)
	assert(int(summary.get("boost_formula_mismatch", -1)) == 0)
	assert(int(summary.get("duplicate_slot_collapse", -1)) == 0)


func _test_exact_formula_samples() -> void:
	var samples := [
		[10, 1, 10], [20, 1, 20], [30, 1, 20], [50, 1, 20],
		[100, 1, 20], [200, 1, 20], [500, 1, 20], [1000, 1, 40],
		[2000, 1, 80], [5000, 1, 200], [6000, 1, 240],
		[10000, 1, 400], [30000, 1, 1200], [100000, 1, 4000],
	]
	for sample: Array in samples:
		var result := GameData.dpv2_single_player_boost_formula(1, int(sample[0]), true)
		assert(bool(result.get("ok", false)), str(result))
		assert(
			Vector2i(int(result.get("numerator", 0)), int(result.get("denominator", 0)))
				== Vector2i(int(sample[1]), int(sample[2])),
			"sample 1/%d produced %s" % [int(sample[0]), str(result)],
		)
	var bypass := GameData.dpv2_single_player_boost_formula(1, 5000, false)
	assert(Vector2i(bypass.numerator, bypass.denominator) == Vector2i(1, 5000))


func _test_real_slot_policies() -> void:
	_assert_probability(135, "dpv2.direct.m135.slot_124", 1, 5000, 1, 200, "AUTO_BOOST")
	_assert_probability(21, "dpv2.direct.m21.slot_002", 1, 20, 1, 20, "BYPASS_COMMON_RECOVERY")
	_assert_probability(21, "dpv2.direct.m21.slot_003", 1, 30, 1, 30, "BYPASS_COMMON_RECOVERY")
	_assert_probability(28, "dpv2.direct.m28.slot_004", 1, 100, 1, 100, "BYPASS_COMMON_RECOVERY")
	_assert_probability(19, "dpv2.direct.m19.slot_001", 1, 4, 1, 4, "BYPASS_GOLD")
	_assert_probability(92, "dpv2.direct.m92.slot_001", 1, 6000, 1, 240, "AUTO_BOOST")
	_assert_probability(43, "dpv2.direct.m43.slot_004", 1, 100, 1, 100, "BYPASS_UNCLASSIFIED")
	var war_god_oil_slots := [
		[92, "dpv2.direct.m92.slot_002", 6000, 240],
		[94, "dpv2.direct.m94.slot_002", 6000, 240],
		[110, "dpv2.direct.m110.slot_023", 4800, 192],
		[112, "dpv2.direct.m112.slot_003", 4800, 192],
		[114, "dpv2.direct.m114.slot_004", 4800, 192],
		[118, "dpv2.direct.m118.slot_003", 4800, 192],
		[129, "dpv2.direct.m129.slot_005", 4800, 192],
		[132, "dpv2.direct.m132.slot_005", 4800, 192],
		[138, "dpv2.direct.m138.slot_003", 1800, 72],
	]
	for sample: Array in war_god_oil_slots:
		_assert_probability(
			int(sample[0]), str(sample[1]), 1, int(sample[2]), 1, int(sample[3]),
			"AUTO_BOOST"
		)
		var matching_records: Array = GameData.dpv2_single_player_effective_probability.get("records", []).filter(
			func(row: Variant) -> bool:
				return row is Dictionary and str(row.get("slot_uid", "")) == str(sample[1])
		)
		assert(matching_records.size() == 1)
		assert(int((matching_records[0] as Dictionary).get("canonical_item_id", -1)) == 920019)
		assert(not bool((matching_records[0] as Dictionary).get("ceiling_applied", true)))
	var boss_counts: Dictionary = {}
	for raw_record: Variant in GameData.dpv2_single_player_effective_probability.get("records", []):
		var record: Dictionary = raw_record
		var monster_id := int(record.get("canonical_monster_id", -1))
		if monster_id < 235 or monster_id > 240:
			continue
		boss_counts[monster_id] = int(boss_counts.get(monster_id, 0)) + 1
		var probability := GameData.dpv2_effective_slot_probability(
			monster_id, str(record.get("slot_uid", ""))
		)
		assert(bool(probability.get("ok", false)), str(probability))
		assert(str(probability.get("boost_policy", "")) == "BYPASS_NEW_ARMOR_BOSS")
		assert(
			Vector2i(probability.final_numerator, probability.final_denominator)
				== Vector2i(record.base_numerator, record.base_denominator)
		)
	for monster_id: int in range(235, 241):
		assert(int(boss_counts.get(monster_id, 0)) == 54)


func _test_disabled_parity_and_single_global_scale() -> void:
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.get("production", {})
	var original_enabled: Variant = production.get("enabled", null)
	var original_preset := str(GameData.dpv2_global_drop_rate_authority.get("active_preset", ""))
	production["enabled"] = false
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "1x"
	var parity_count := 0
	for raw_record: Variant in GameData.dpv2_single_player_effective_probability.get("records", []):
		var record: Dictionary = raw_record
		var probability := GameData.dpv2_effective_slot_probability(
			int(record.get("canonical_monster_id", -1)),
			str(record.get("slot_uid", "")),
		)
		assert(bool(probability.get("ok", false)), str(probability))
		assert(not bool(probability.get("spb_enabled", true)))
		assert(str(probability.get("spb_selected_source", "")) == "base")
		assert(
			Vector2i(probability.final_numerator, probability.final_denominator)
				== Vector2i(record.base_numerator, record.base_denominator)
		)
		parity_count += 1
	assert(parity_count == 6809)
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "0.5x"
	var half := GameData.dpv2_effective_slot_probability(135, "dpv2.direct.m135.slot_124")
	assert(Vector2i(half.final_numerator, half.final_denominator) == Vector2i(1, 10000))
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "2x"
	var double := GameData.dpv2_effective_slot_probability(135, "dpv2.direct.m135.slot_124")
	assert(Vector2i(double.final_numerator, double.final_denominator) == Vector2i(1, 2500))
	production["enabled"] = original_enabled
	GameData.dpv2_global_drop_rate_authority["active_preset"] = original_preset


func _test_gold_amount_overlay() -> void:
	var production: Dictionary = GameData.dpv2_single_player_drop_boost.get("production", {})
	var original_enabled: Variant = production.get("enabled", null)
	var gold_records: Array = []
	for raw_record: Variant in GameData.dpv2_single_player_effective_probability.get("records", []):
		var record: Dictionary = raw_record
		if str(record.get("reward_kind", "")) != "GOLD":
			assert(not record.has("base_gold_amount"))
			assert(not record.has("effective_gold_amount"))
			continue
		gold_records.append(record)
		assert(int(record.get("base_gold_amount", 0)) == int(record.get("gold_amount", -1)))
		assert(int(record.get("effective_gold_amount", 0)) == int(record.get("gold_amount", -1)) * 10)
		var probability := GameData.dpv2_effective_slot_probability(
			int(record.get("canonical_monster_id", -1)),
			str(record.get("slot_uid", "")),
		)
		assert(bool(probability.get("ok", false)), str(probability))
		assert(Vector2i(probability.base_numerator, probability.base_denominator) == Vector2i(record.base_numerator, record.base_denominator))
		assert(Vector2i(probability.effective_numerator, probability.effective_denominator) == Vector2i(record.base_numerator, record.base_denominator))
		assert(int(probability.get("base_gold_amount", 0)) == int(record.gold_amount))
		assert(int(probability.get("effective_gold_amount", 0)) == int(record.gold_amount) * 10)
		assert(int(probability.get("final_gold_amount", 0)) == int(record.gold_amount) * 10)
	assert(gold_records.size() == 134)
	production["enabled"] = false
	for raw_record: Variant in gold_records:
		var record: Dictionary = raw_record
		var disabled := GameData.dpv2_effective_slot_probability(
			int(record.get("canonical_monster_id", -1)),
			str(record.get("slot_uid", "")),
		)
		assert(bool(disabled.get("ok", false)), str(disabled))
		assert(int(disabled.get("final_gold_amount", 0)) == int(record.gold_amount))
	production["enabled"] = original_enabled
	_assert_service_gold_amount(30000)
	production["enabled"] = false
	_assert_service_gold_amount(3000)
	production["enabled"] = original_enabled


func _test_enabled_non_1x_and_missing_row_fail_before_rng() -> void:
	var service := LootRuntimeScript.new()
	var original_preset := str(GameData.dpv2_global_drop_rate_authority.get("active_preset", ""))
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "2x"
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var state_before := rng.state
	var rejected := service.roll_monster_drops(135, rng)
	assert(str(rejected.get("reason", "")) == "spb_effective_probability_fail_closed")
	assert(int(rejected.get("rng_roll_count", -1)) == 0)
	assert(rng.state == state_before)
	assert(not (rejected.get("rejected_entries", []) as Array).is_empty())
	assert(str(rejected.rejected_entries[0].reason) == "spb_enabled_requires_global_1x")
	GameData.dpv2_global_drop_rate_authority["active_preset"] = original_preset

	var index: Dictionary = GameData.get("_dpv2_spb_effective_by_uid")
	var uid := "dpv2.direct.m135.slot_124"
	var saved: Dictionary = index.get(uid, {}).duplicate(true)
	assert(not saved.is_empty())
	index.erase(uid)
	GameData.set("_dpv2_spb_effective_by_uid", index)
	var missing_rng := RandomNumberGenerator.new()
	missing_rng.seed = 135124
	var missing_state := missing_rng.state
	var missing := service.roll_monster_drops(135, missing_rng)
	assert(str(missing.get("reason", "")) == "spb_effective_probability_fail_closed")
	assert(int(missing.get("rng_roll_count", -1)) == 0)
	assert(missing_rng.state == missing_state)
	var missing_rejections: Array = missing.get("rejected_entries", [])
	assert(not missing_rejections.is_empty())
	var found_unresolved := false
	for raw_rejection: Variant in missing_rejections:
		if (
			raw_rejection is Dictionary
			and str(raw_rejection.get("reason", ""))
				== "spb_effective_probability_unresolved"
		):
			found_unresolved = true
	assert(found_unresolved)
	index[uid] = saved
	GameData.set("_dpv2_spb_effective_by_uid", index)


func _test_production_service_uses_effective_probability() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 135124
	var profile := GameData.dpv2_direct_profile(135)
	var slots: Array = profile.get("slots", [])
	var roll := service.roll_monster_drops(135, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("rng_roll_count", -1)) == slots.size())
	assert(bool(roll.get("all_enabled_resolved_slots_rng_before_overflow", false)))
	var attempt := _find_attempt(roll.get("attempts", []), "dpv2.direct.m135.slot_124")
	assert(not attempt.is_empty())
	assert(Vector2i(attempt.base_numerator, attempt.base_denominator) == Vector2i(1, 5000))
	assert(Vector2i(attempt.effective_numerator, attempt.effective_denominator) == Vector2i(1, 200))
	assert(Vector2i(attempt.final_numerator, attempt.final_denominator) == Vector2i(1, 200))
	assert(str(attempt.get("boost_policy", "")) == "AUTO_BOOST")
	assert(str(attempt.get("global_preset", "")) == "1x")
	assert(int(attempt.get("global_scale_numerator", 0)) == 1)
	assert(int(attempt.get("global_scale_denominator", 0)) == 1)


func _test_overflow_contract_is_unchanged() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 31
	var roll := service.roll_monster_drops(31, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(bool(roll.get("all_enabled_resolved_slots_rng_before_overflow", false)))
	assert(int(roll.get("ground_output_count", 0)) <= 9)
	assert(
		int(roll.get("ground_output_count", 0))
			+ int(roll.get("overflow_discarded_count", 0))
			== int(roll.get("successful_roll_count", -1))
	)


func _assert_probability(
	monster_id: int,
	uid: String,
	base_numerator: int,
	base_denominator: int,
	effective_numerator: int,
	effective_denominator: int,
	policy: String
) -> void:
	var result := GameData.dpv2_effective_slot_probability(monster_id, uid)
	assert(bool(result.get("ok", false)), str(result))
	assert(Vector2i(result.base_numerator, result.base_denominator) == Vector2i(base_numerator, base_denominator))
	assert(Vector2i(result.effective_numerator, result.effective_denominator) == Vector2i(effective_numerator, effective_denominator))
	assert(Vector2i(result.final_numerator, result.final_denominator) == Vector2i(effective_numerator, effective_denominator))
	assert(str(result.get("boost_policy", "")) == policy)


func _find_attempt(attempts: Array, uid: String) -> Dictionary:
	for raw_attempt: Variant in attempts:
		if raw_attempt is Dictionary and str(raw_attempt.get("slot_uid", "")) == uid:
			return raw_attempt
	return {}


func _assert_service_gold_amount(expected_amount: int) -> void:
	var found := false
	for seed: int in range(128):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var roll := LootRuntimeScript.new().roll_monster_drops(226, rng)
		var gold_drops: Array = roll.get("gold_drops", [])
		if not gold_drops.is_empty():
			assert(gold_drops == [expected_amount], str(roll))
			var attempt: Dictionary = (roll.get("attempts", []) as Array)[0]
			assert(int(attempt.get("base_gold_amount", 0)) == 3000)
			assert(int(attempt.get("effective_gold_amount", 0)) == 30000)
			assert(int(attempt.get("final_gold_amount", 0)) == expected_amount)
			found = true
			break
	assert(found)
