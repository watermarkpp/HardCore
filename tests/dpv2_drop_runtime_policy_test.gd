extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "DPV2 production authorities failed to load")
	assert(GameData.dpv2_ground_slot_limit() == 9)
	assert(GameData.dpv2_item_tier_authority.get("records", []).size() == 233)
	assert(GameData.dpv2_monster_role_authority.get("monsters", []).size() == 156)
	assert(
		GameData.dpv2_drop_runtime_authority.get(
			"item_overflow_records", []
		).size() == 233
	)
	assert(
		str(GameData.dpv2_active_global_drop_rate().get("preset", "")) == "1x"
	)
	_test_exact_probability_authority()
	_test_tier_driven_overflow_priority()
	_test_equipment_displaces_ordinary_rewards()
	_test_protected_overflow_is_randomized()
	_test_fitting_group_does_not_consume_shuffle_rng()
	_test_all_resolved_source_slots_reach_rng()
	_test_overflow_telemetry_is_overflow_only()
	_test_non_loot_is_not_a_zero_factor_role()
	print(
		"DPV2_DROP_RUNTIME_POLICY_PASS: items=233 monsters=156 "
		+ "slots=7032 enabled=5995 disabled=1037 "
		+ "pre_overflow_rng=5995 ground_limit=9 global=1x"
	)
	get_tree().quit(0)


func _test_exact_probability_authority() -> void:
	var potion_name := _first_item_name_for_tier("POTION_COMMON")
	assert(not potion_name.is_empty())
	var common := GameData.dpv2_resolve_reward_policy(18, {
		"kind": "item",
		"item_name": potion_name,
	})
	assert(bool(common.get("ok", false)), str(common))
	assert(int(common.get("probability_numerator", 0)) == 1)
	assert(int(common.get("probability_denominator", 0)) == 32)

	var boss_key_name := _first_item_name_for_tier("BOSS_KEY_ITEM")
	assert(not boss_key_name.is_empty())
	var endgame := GameData.dpv2_resolve_reward_policy(225, {
		"kind": "item",
		"item_name": boss_key_name,
	})
	assert(bool(endgame.get("ok", false)), str(endgame))
	assert(str(endgame.get("role", "")) == "ENDGAME_BOSS")
	assert(int(endgame.get("probability_numerator", 0)) == 1)
	assert(int(endgame.get("probability_denominator", 0)) == 2)

	var observed_presets := {}
	for raw: Variant in GameData.dpv2_global_drop_rate_authority.get(
		"presets", []
	):
		assert(raw is Dictionary)
		observed_presets[str(raw.get("preset", ""))] = Vector2i(
			int(raw.get("numerator", 0)),
			int(raw.get("denominator", 0))
		)
	assert(observed_presets == {
		"0.5x": Vector2i(1, 2),
		"0.8x": Vector2i(4, 5),
		"1x": Vector2i(1, 1),
		"1.5x": Vector2i(3, 2),
		"2x": Vector2i(2, 1),
	})


func _test_equipment_displaces_ordinary_rewards() -> void:
	var candidates: Array = []
	for index in range(5):
		candidates.append(_synthetic_candidate("equipment_%d" % index, 300, true))
	for index in range(10):
		candidates.append(_synthetic_candidate("potion_%d" % index, 100, false))
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026082701
	var selection := LootRuntimeScript.new()._select_ground_rewards(
		candidates, rng, 9
	)
	var selected: Array = selection.get("selected", [])
	assert(selected.size() == 9)
	var equipment_count := 0
	var ordinary_count := 0
	for raw: Variant in selected:
		var policy: Dictionary = raw.get("policy", {})
		if int(policy.get("overflow_priority", 0)) == 300:
			equipment_count += 1
		elif int(policy.get("overflow_priority", 0)) == 100:
			ordinary_count += 1
	assert(equipment_count == 5)
	assert(ordinary_count == 4)


func _test_tier_driven_overflow_priority() -> void:
	var gate := GameData.dpv2_source_slot_gate()
	assert(int(gate.get("canonical_source_slots", -1)) == 7032, str(gate))
	assert(int(gate.get("drop_enabled_source_slots", -1)) == 5995, str(gate))
	assert(int(gate.get("drop_disabled_source_slots", -1)) == 1037, str(gate))
	assert(
		int(gate.get("drop_enabled_source_slots", -1))
			+ int(gate.get("drop_disabled_source_slots", -1))
		== int(gate.get("canonical_source_slots", -2)),
		str(gate)
	)
	for key: String in [
		"reward_resolved_enabled_slots",
		"probability_resolved_enabled_slots",
		"rng_eligible_slots",
	]:
		assert(int(gate.get(key, -1)) == 5995, str(gate))
	assert(bool(gate.get(
		"all_enabled_resolved_slots_rng_before_overflow",
		false
	)), str(gate))
	assert(str(gate.get("overflow_stage", "")) == "after_all_probability_rolls")

	var boss_key := _assert_tier_policy("BOSS_KEY_ITEM", 400, true)
	var high_book := _assert_tier_policy("BOOK_HIGH", 300, true)
	var mid_book := _assert_tier_policy("BOOK_MID", 200, false)
	var low_book := _assert_tier_policy("BOOK_LOW", 200, false)
	var ordinary_equipment := _assert_tier_policy("EQUIP_LOW", 200, false)
	var ordinary_material := _assert_tier_policy("MONSTER_MATERIAL", 100, false)
	assert(int(boss_key.get("overflow_priority", 0)) > int(high_book.get("overflow_priority", 0)))
	assert(int(high_book.get("overflow_priority", 0)) > int(mid_book.get("overflow_priority", 0)))
	assert(int(mid_book.get("overflow_priority", 0)) == int(low_book.get("overflow_priority", 0)))
	assert(int(ordinary_equipment.get("overflow_priority", 0)) == 200)
	assert(int(ordinary_material.get("overflow_priority", 0)) == 100)
	assert(str(ordinary_equipment.get("tier", "")) == "EQUIP_LOW")
	assert(str(ordinary_material.get("tier", "")) == "MONSTER_MATERIAL")


func _assert_tier_policy(tier: String, expected_priority: int, expected_protected: bool) -> Dictionary:
	var item_name := _first_item_name_for_tier(tier)
	assert(not item_name.is_empty(), "missing tier %s" % tier)
	var policy := GameData.dpv2_resolve_reward_policy(225, {
		"kind": "item",
		"item_name": item_name,
	})
	assert(bool(policy.get("ok", false)), str(policy))
	assert(str(policy.get("tier", "")) == tier, str(policy))
	assert(int(policy.get("overflow_priority", 0)) == expected_priority, str(policy))
	assert(bool(policy.get("protected_drop", not expected_protected)) == expected_protected, str(policy))
	return policy


func _test_protected_overflow_is_randomized() -> void:
	var candidates: Array = []
	for index in range(10):
		candidates.append(_synthetic_candidate("equipment_%d" % index, 300, true))
	var discarded_names := {}
	for seed in range(128):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		var selection := LootRuntimeScript.new()._select_ground_rewards(
			candidates, rng, 9
		)
		assert(selection.get("selected", []).size() == 9)
		assert(selection.get("discarded", []).size() == 1)
		assert(int(selection.get("protected_discarded_count", 0)) == 1)
		var discarded: Dictionary = selection.get("discarded", [])[0]
		discarded_names[str(discarded.get("test_name", ""))] = true
	assert(
		discarded_names.size() == 10,
		"same-priority overflow retained source-order bias: %s" % discarded_names
	)


func _test_fitting_group_does_not_consume_shuffle_rng() -> void:
	var candidates: Array = []
	for index in range(2):
		candidates.append(_synthetic_candidate("fitting_%d" % index, 200, false))
	var expected_rng := RandomNumberGenerator.new()
	expected_rng.seed = 2026082705
	var expected_next := expected_rng.randi()
	var rng_without_shuffle := RandomNumberGenerator.new()
	rng_without_shuffle.seed = 2026082705
	var selected := LootRuntimeScript.new()._select_ground_rewards(
		candidates,
		rng_without_shuffle,
		9
	)
	assert(selected.get("discarded", []).is_empty(), str(selected))
	assert(rng_without_shuffle.randi() == expected_next)

	var boundary_candidates: Array = []
	for index in range(10):
		boundary_candidates.append(_synthetic_candidate("boundary_%d" % index, 200, false))
	var rng_boundary := RandomNumberGenerator.new()
	rng_boundary.seed = 2026082705
	LootRuntimeScript.new()._select_ground_rewards(
		boundary_candidates,
		rng_boundary,
		9
	)
	assert(rng_boundary.randi() != expected_next)


func _test_all_resolved_source_slots_reach_rng() -> void:
	var corpus_rng := RandomNumberGenerator.new()
	corpus_rng.seed = 2026082706
	var corpus_service := LootRuntimeScript.new()
	var enabled_monster_count := 0
	var enabled_source_slots := 0
	var reward_resolved_slots := 0
	var probability_resolved_slots := 0
	var rng_eligible_slots := 0
	var rng_roll_count := 0
	for raw_role: Variant in GameData.dpv2_monster_role_authority.get(
		"monsters", []
	):
		assert(raw_role is Dictionary)
		var role: Dictionary = raw_role
		if not bool(role.get("drop_enabled", false)):
			continue
		enabled_monster_count += 1
		var monster_id := int(role.get("canonical_monster_id", -1))
		var corpus_roll := corpus_service.roll_monster_drops(
			monster_id,
			corpus_rng
		)
		var source_count := int(corpus_roll.get("source_entry_count", 0))
		enabled_source_slots += source_count
		reward_resolved_slots += int(
			corpus_roll.get("reward_resolved_enabled_slots", 0)
		)
		probability_resolved_slots += int(
			corpus_roll.get("probability_resolved_enabled_slots", 0)
		)
		rng_eligible_slots += int(corpus_roll.get("rng_eligible_slots", 0))
		rng_roll_count += int(corpus_roll.get("rng_roll_count", 0))
		if source_count > 0:
			assert(bool(corpus_roll.get("configured", false)), str(corpus_roll))
			assert(
				source_count
					== int(corpus_roll.get("reward_resolved_enabled_slots", -1))
				and source_count
					== int(corpus_roll.get("probability_resolved_enabled_slots", -1))
				and source_count == int(corpus_roll.get("rng_eligible_slots", -1))
				and source_count == int(corpus_roll.get("rng_roll_count", -1)),
				"enabled monster did not roll every source slot before overflow: %s"
					% corpus_roll
			)
			assert(bool(corpus_roll.get(
				"all_enabled_resolved_slots_rng_before_overflow",
				false
			)), str(corpus_roll))
	assert(enabled_monster_count == 131)
	assert(enabled_source_slots == 5995)
	assert(reward_resolved_slots == 5995)
	assert(probability_resolved_slots == 5995)
	assert(rng_eligible_slots == 5995)
	assert(rng_roll_count == 5995)

	var rng := RandomNumberGenerator.new()
	rng.seed = 2026082702
	var roll := LootRuntimeScript.new().roll_monster_drops(76, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("source_entry_count", 0)) == 33)
	assert(int(roll.get("resolved_entry_count", 0)) == 33, str(roll))
	assert(int(roll.get("rng_roll_count", 0)) == 33, str(roll))
	assert(int(roll.get("reward_resolved_enabled_slots", 0)) == 33, str(roll))
	assert(int(roll.get("probability_resolved_enabled_slots", 0)) == 33, str(roll))
	assert(int(roll.get("rng_eligible_slots", 0)) == 33, str(roll))
	assert(bool(roll.get("all_resolved_slots_rng", false)), str(roll))
	assert(bool(roll.get(
		"all_enabled_resolved_slots_rng_before_overflow",
		false
	)), str(roll))
	assert(int(roll.get("ground_output_count", 0)) <= 9)
	assert(
		int(roll.get("ground_output_count", -1))
			+ int(roll.get("overflow_discarded_count", -2))
		== int(roll.get("successful_roll_count", -3)),
		str(roll)
	)

	var anomaly_rng := RandomNumberGenerator.new()
	anomaly_rng.seed = 2026082703
	var anomaly_roll := LootRuntimeScript.new().roll_monster_drops(168, anomaly_rng)
	for raw: Variant in anomaly_roll.get("rejected_entries", []):
		assert(
			not (
				int(raw.get("line_number", -1)) == 20
				and str(raw.get("reason", "")) == "chance_token_invalid"
			),
			"source 1/00 provenance incorrectly gated DPV2 RNG"
		)


func _test_overflow_telemetry_is_overflow_only() -> void:
	var service := LootRuntimeScript.new()
	service.clear_overflow_telemetry()
	var no_overflow := service.record_overflow_telemetry(76, {
		"overflow_discarded_count": 0,
		"successful_roll_count": 3,
		"ground_output_count": 3,
		"protected_overflow_count": 0,
	})
	assert(no_overflow.is_empty(), str(no_overflow))
	assert(service.overflow_telemetry_snapshot().is_empty())

	var first := service.record_overflow_telemetry(76, {
		"overflow_discarded_count": 2,
		"successful_roll_count": 11,
		"ground_output_count": 9,
		"protected_overflow_count": 1,
	})
	assert(int(first.get("monster_id", -1)) == 76, str(first))
	assert(int(first.get("successful_roll_count", 0)) == 11, str(first))
	assert(int(first.get("ground_output_count", 0)) == 9, str(first))
	assert(int(first.get("overflow_discarded_count", 0)) == 2, str(first))
	assert(int(first.get("protected_overflow_count", 0)) == 1, str(first))

	var second := service.record_overflow_telemetry(76, {
		"overflow_discarded_count": 1,
		"successful_roll_count": 10,
		"ground_output_count": 9,
		"protected_overflow_count": 0,
	})
	assert(int(second.get("death_count", 0)) == 2, str(second))
	assert(int(second.get("overflow_discarded_count", 0)) == 3, str(second))
	assert(int(second.get("protected_overflow_count", 0)) == 1, str(second))
	service.clear_overflow_telemetry()
	assert(service.overflow_telemetry_snapshot().is_empty())


func _test_non_loot_is_not_a_zero_factor_role() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026082704
	var roll := LootRuntimeScript.new().roll_monster_drops(59, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(str(roll.get("reason", "")) == "drop_disabled")
	assert(int(roll.get("rng_roll_count", -1)) == 0)
	assert(
		int(roll.get("drop_disabled_source_slots", 0))
			== int(roll.get("source_entry_count", -1)),
		str(roll)
	)
	var state := GameData.dpv2_monster_drop_state(59)
	assert(not bool(state.get("drop_enabled", true)))
	assert(state.get("drop_role", "sentinel") == null)
	assert(state.get("role_factor", "sentinel") == null)
	assert(str(state.get("reporting_label", "")) == "NON_LOOT")


func _first_item_name_for_tier(tier: String) -> String:
	for raw: Variant in GameData.dpv2_item_tier_authority.get("records", []):
		if raw is Dictionary and str(raw.get("tier", "")) == tier:
			return str(raw.get("canonical_name", ""))
	return ""


func _synthetic_candidate(
	test_name: String,
	priority: int,
	protected_drop: bool
) -> Dictionary:
	return {
		"test_name": test_name,
		"reward": {"kind": "item", "item_name": test_name},
		"policy": {
			"overflow_priority": priority,
			"protected_drop": protected_drop,
		},
	}
