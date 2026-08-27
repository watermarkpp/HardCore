extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "GameData failed: %s" % GameData.load_error)
	assert(GameData.is_dpv2_direct_baseline_loaded())
	_test_loader_contract()
	_test_exact_id_profile_join()
	_test_direct_identity_resolution()
	_test_rational_probability()
	_test_ten_x_rational_probability()
	_test_independent_slot_rng_and_diagnostics()
	_test_fail_closed_without_direct_authority()
	_test_protected_overflow_selection()
	print(
		"DPV2_21CQ_DIRECT_RUNTIME_PASS: profiles=156 slots=5995 "
		+ "10x=1/20_to_1/2 clamp=1/1 "
		+ "direct_id_rng=independent protected_first cap=9"
	)
	get_tree().quit(0)


func _test_loader_contract() -> void:
	var baseline: Dictionary = GameData.dpv2_direct_baseline
	assert(
		str(baseline.get("schema", ""))
			== "hardcore.dpv2.direct_monster_drop_baseline.v2"
	)
	assert(str(baseline.get("identity_key", "")) == "canonical_monster_id")
	var profiles_value: Variant = baseline.get("profiles", [])
	assert(profiles_value is Array)
	assert((profiles_value as Array).size() == 156)
	var total_slots := 0
	for raw_profile: Variant in profiles_value:
		assert(raw_profile is Dictionary)
		var profile: Dictionary = raw_profile
		var slots: Variant = profile.get("slots", [])
		assert(slots is Array)
		total_slots += (slots as Array).size()
		for raw_slot: Variant in slots:
			assert(raw_slot is Dictionary)
			var slot: Dictionary = raw_slot
			for forbidden: String in [
				"chance", "source_rate", "item_name", "tier", "drop_role",
				"role", "role_factor", "factor",
			]:
				assert(not slot.has(forbidden), "%s in %s" % [forbidden, slot])
	assert(total_slots == 5995)
	var gate: Dictionary = GameData.dpv2_source_slot_gate()
	assert(str(gate.get("authority", "")) == "dpv2.direct_baseline.v2")
	assert(bool(gate.get("available", false)))
	assert(int(gate.get("compiled_slots", -1)) == 5995)
	assert(int(gate.get("maximum_ground_slots", -1)) == 9)
	assert(bool(gate.get("all_enabled_resolved_slots_rng_before_overflow", false)))


func _test_exact_id_profile_join() -> void:
	var direct := GameData.dpv2_direct_profile(18)
	assert(not direct.is_empty())
	assert(str(direct.get("drop_profile_id", "")) == "dpv2.direct.18")
	var catalog := GameData.get_canonical_monster_drop_profile(18)
	assert(str(catalog.get("drop_profile_id", "")) == "drop.18")
	assert(str(direct.get("drop_profile_id", "")) != str(catalog.get("drop_profile_id", "")))
	assert(int(direct.get("canonical_monster_id", -1)) == 18)
	assert(GameData.dpv2_direct_profile_slots(18).size() == 1)
	assert(GameData.dpv2_direct_profile(999999).is_empty())
	assert(GameData.dpv2_direct_slot("dpv2.direct.m18.slot_001").get(
		"canonical_monster_id", -1
	) == 18)


func _test_direct_identity_resolution() -> void:
	var all_slots := 0
	var resolved_items := 0
	var resolved_gold := 0
	for raw_profile: Variant in GameData.dpv2_direct_baseline.get("profiles", []):
		var profile: Dictionary = raw_profile
		for raw_slot: Variant in profile.get("slots", []):
			var slot: Dictionary = raw_slot
			var reward := GameData.dpv2_direct_resolve_slot_reward(slot)
			assert(bool(reward.get("ok", false)), str(reward))
			all_slots += 1
			if str(reward.get("kind", "")) == "gold":
				resolved_gold += 1
			else:
				resolved_items += 1
				assert(int(reward.get("canonical_item_id", -1)) > 0)
				assert(not str(reward.get("item_name", "")).is_empty())
	assert(all_slots == 5995)
	assert(resolved_items > 0)
	assert(resolved_gold > 0)
	var rejected := GameData.dpv2_direct_resolve_slot_reward({
		"canonical_item_id": 999999999,
	})
	assert(not bool(rejected.get("ok", false)))


func _test_rational_probability() -> void:
	var slot: Dictionary = GameData.dpv2_direct_slot(
		"dpv2.direct.m18.slot_001"
	)
	assert(int(slot.get("base_numerator", -1)) == 1)
	assert(int(slot.get("base_denominator", -1)) == 3)
	var original_preset := str(GameData.dpv2_global_drop_rate_authority.get(
		"active_preset", ""
	))
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "1x"
	var one_x := GameData.dpv2_direct_slot_probability(
		18, "dpv2.direct.m18.slot_001"
	)
	assert(bool(one_x.get("ok", false)), str(one_x))
	assert(int(one_x.get("final_numerator", -1)) == 1)
	assert(int(one_x.get("final_denominator", -1)) == 3)
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "0.5x"
	var half_x := GameData.dpv2_direct_slot_probability(
		18, "dpv2.direct.m18.slot_001"
	)
	assert(int(half_x.get("final_numerator", -1)) == 1)
	assert(int(half_x.get("final_denominator", -1)) == 6)
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "2x"
	var double_x := GameData.dpv2_direct_slot_probability(
		18, "dpv2.direct.m18.slot_001"
	)
	assert(int(double_x.get("final_numerator", -1)) == 2)
	assert(int(double_x.get("final_denominator", -1)) == 3)
	GameData.dpv2_global_drop_rate_authority["active_preset"] = "not-a-preset"
	var invalid_scale := GameData.dpv2_direct_slot_probability(
		18, "dpv2.direct.m18.slot_001"
	)
	assert(not bool(invalid_scale.get("ok", false)))
	GameData.dpv2_global_drop_rate_authority["active_preset"] = original_preset
	var clamped := GameData.dpv2_direct_slot_probability(
		30, "dpv2.direct.m30.slot_001"
	)
	assert(bool(clamped.get("ok", false)), str(clamped))
	assert(int(clamped.get("final_numerator", -1)) == 1)
	assert(int(clamped.get("final_denominator", -1)) == 1)


func _test_ten_x_rational_probability() -> void:
	# Inject 10x only in this test's in-memory authority view. The production
	# JSON remains unchanged; the private index is mirrored because GameData
	# validates presets into it once during startup.
	var authority: Dictionary = GameData.dpv2_global_drop_rate_authority
	var original_active := str(authority.get("active_preset", ""))
	var original_presets: Array = (authority.get("presets", []) as Array).duplicate(true)
	var had_index := GameData._dpv2_global_scale_by_preset.has("10x")
	var original_index: Variant = GameData._dpv2_global_scale_by_preset.get(
		"10x", Vector2i.ZERO
	)
	var temporary_presets := original_presets.duplicate(true)
	temporary_presets.append({"preset": "10x", "numerator": 10, "denominator": 1})
	authority["presets"] = temporary_presets
	authority["active_preset"] = "10x"
	GameData._dpv2_global_scale_by_preset["10x"] = Vector2i(10, 1)

	var ten_x := GameData.dpv2_direct_slot_probability(
		21, "dpv2.direct.m21.slot_002"
	)
	var clamp := GameData.dpv2_direct_slot_probability(
		18, "dpv2.direct.m18.slot_001"
	)
	var ten_x_ok := (
		bool(ten_x.get("ok", false))
		and int(ten_x.get("base_numerator", -1)) == 1
		and int(ten_x.get("base_denominator", -1)) == 20
		and int(ten_x.get("global_scale_numerator", -1)) == 10
		and int(ten_x.get("global_scale_denominator", -1)) == 1
		and int(ten_x.get("unreduced_final_numerator", -1)) == 10
		and int(ten_x.get("unreduced_final_denominator", -1)) == 20
		and int(ten_x.get("final_numerator", -1)) == 1
		and int(ten_x.get("final_denominator", -1)) == 2
		and is_equal_approx(float(ten_x.get("final_probability", -1.0)), 0.5)
	)
	var clamp_ok := (
		bool(clamp.get("ok", false))
		and int(clamp.get("base_numerator", -1)) == 1
		and int(clamp.get("base_denominator", -1)) == 3
		and int(clamp.get("final_numerator", -1)) == 1
		and int(clamp.get("final_denominator", -1)) == 1
		and is_equal_approx(float(clamp.get("final_probability", -1.0)), 1.0)
	)

	# Restore every mutated in-memory value before asserting, so a failed check
	# cannot poison the remaining tests in this scene.
	authority["presets"] = original_presets
	authority["active_preset"] = original_active
	if had_index:
		GameData._dpv2_global_scale_by_preset["10x"] = original_index
	else:
		GameData._dpv2_global_scale_by_preset.erase("10x")
	assert(ten_x_ok, str(ten_x))
	assert(clamp_ok, str(clamp))


func _test_independent_slot_rng_and_diagnostics() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var profile := GameData.dpv2_direct_profile(31)
	var slots: Array = profile.get("slots", [])
	var roll: Dictionary = service.roll_monster_drops(31, rng)
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("source_entry_count", -1)) == slots.size())
	assert(int(roll.get("resolution_attempted_count", -1)) == slots.size())
	assert(int(roll.get("reward_resolved_enabled_slots", -1)) == slots.size())
	assert(int(roll.get("probability_resolved_enabled_slots", -1)) == slots.size())
	assert(int(roll.get("rng_eligible_slots", -1)) == slots.size())
	assert(int(roll.get("rng_roll_count", -1)) == slots.size())
	assert(bool(roll.get("all_resolved_slots_rng", false)))
	assert(bool(roll.get("all_enabled_resolved_slots_rng_before_overflow", false)))
	assert(int(roll.get("ground_output_count", 0)) <= 9)
	assert(
		int(roll.get("ground_output_count", 0))
			+ int(roll.get("overflow_discarded_count", 0))
		== int(roll.get("successful_roll_count", -1))
	)
	var attempts: Array = roll.get("attempts", [])
	assert(attempts.size() == slots.size())
	var seen_slots := {}
	var seen_item_ids := {}
	for raw_attempt: Variant in attempts:
		assert(raw_attempt is Dictionary)
		var attempt: Dictionary = raw_attempt
		var slot_uid := str(attempt.get("slot_uid", ""))
		assert(not slot_uid.is_empty())
		assert(not seen_slots.has(slot_uid))
		seen_slots[slot_uid] = true
		for field: String in [
			"canonical_item_id", "base_numerator", "base_denominator",
			"base_probability", "global_scale", "final_probability",
			"draw", "draw_success", "overflow", "protected_drop",
			"protected_overflow", "baseline_origin", "source_provenance_id",
		]:
			assert(attempt.has(field), "%s absent: %s" % [field, attempt])
		if int(attempt.get("canonical_item_id", -1)) > 0:
			var item_id := int(attempt.get("canonical_item_id", -1))
			seen_item_ids[item_id] = int(seen_item_ids.get(item_id, 0)) + 1
	assert(seen_item_ids.values().any(func(count): return int(count) > 1))
	var debug: Array = roll.get("debug", [])
	var slot_attempts: Array = roll.get("slot_attempts", [])
	assert(debug.size() == attempts.size())
	assert(slot_attempts.size() == attempts.size())
	for index in range(attempts.size()):
		assert(debug[index] == attempts[index])
		assert(slot_attempts[index] == attempts[index])


func _test_fail_closed_without_direct_authority() -> void:
	var service := LootRuntimeScript.new()
	var original_loaded := GameData.dpv2_direct_baseline_loaded
	GameData.dpv2_direct_baseline_loaded = false
	var rng := RandomNumberGenerator.new()
	var roll := service.roll_monster_drops(31, rng)
	assert(str(roll.get("reason", "")) == "dpv2_direct_baseline_unavailable")
	assert((roll.get("attempts", []) as Array).is_empty())
	GameData.dpv2_direct_baseline_loaded = original_loaded


func _test_protected_overflow_selection() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var protected_candidate := {
		"slot_uid": "protected",
		"reward": {"kind": "item", "item_name": "protected"},
		"policy": {"protected_drop": true, "overflow_priority": 1},
		"attempt": {"slot_uid": "protected", "protected_drop": true},
	}
	var ordinary_candidate := {
		"slot_uid": "ordinary",
		"reward": {"kind": "item", "item_name": "ordinary"},
		"policy": {"protected_drop": false, "overflow_priority": 999},
		"attempt": {"slot_uid": "ordinary", "protected_drop": false},
	}
	var selection: Dictionary = service.call(
		"_select_ground_rewards",
		[ordinary_candidate, protected_candidate],
		rng,
		1,
	)
	assert((selection.get("selected", []) as Array).size() == 1)
	assert((selection.selected[0] as Dictionary).get("slot_uid", "") == "protected")
	assert((selection.get("discarded", []) as Array).size() == 1)
	assert(int(selection.get("protected_discarded_count", -1)) == 0)
	assert(str(protected_candidate.attempt.get("overflow", "")) == "selected")
	assert(str(ordinary_candidate.attempt.get("overflow", "")) == "discarded")

	var protected_a := protected_candidate.duplicate(true)
	protected_a.slot_uid = "protected_a"
	protected_a.attempt.slot_uid = "protected_a"
	var protected_b := protected_candidate.duplicate(true)
	protected_b.slot_uid = "protected_b"
	protected_b.attempt.slot_uid = "protected_b"
	var overflow: Dictionary = service.call(
		"_select_ground_rewards",
		[protected_a, protected_b],
		rng,
		1,
	)
	assert(int(overflow.get("protected_discarded_count", -1)) == 1)
	assert((overflow.get("discarded", []) as Array).size() == 1)
	assert(bool((overflow.discarded[0] as Dictionary).attempt.get(
		"protected_overflow", false
	)))
