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
	_test_equipment_displaces_ordinary_rewards()
	_test_protected_overflow_is_randomized()
	_test_all_resolved_source_slots_reach_rng()
	_test_non_loot_is_not_a_zero_factor_role()
	print(
		"DPV2_DROP_RUNTIME_POLICY_PASS: items=233 monsters=156 "
		+ "slots=7032 ground_limit=9 global=1x full_rng=1"
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


func _test_all_resolved_source_slots_reach_rng() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026082702
	var roll := LootRuntimeScript.new().roll_monster_drops(76, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("source_entry_count", 0)) == 33)
	assert(int(roll.get("resolved_entry_count", 0)) == 33, str(roll))
	assert(int(roll.get("rng_roll_count", 0)) == 33, str(roll))
	assert(bool(roll.get("all_resolved_slots_rng", false)), str(roll))
	assert(int(roll.get("ground_output_count", 0)) <= 9)

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


func _test_non_loot_is_not_a_zero_factor_role() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026082704
	var roll := LootRuntimeScript.new().roll_monster_drops(59, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(str(roll.get("reason", "")) == "drop_disabled")
	assert(int(roll.get("rng_roll_count", -1)) == 0)
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
