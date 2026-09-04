extends Node

const LootRuntimeScript := preload(
	"res://scripts/layers/runtime/loot_runtime_service.gd"
)


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "DPV2 authorities failed: %s" % GameData.load_error)
	assert(GameData.is_dpv2_direct_baseline_loaded())
	_test_direct_authority_and_gate()
	_test_global_scale_contract()
	_test_production_roll_is_direct_and_full_slot()
	_test_non_loot_and_zero_slot_profiles_fail_closed_without_fallback()
	print(
		"DPV2_DROP_RUNTIME_POLICY_PASS: direct_v2=1 profiles=156 "
		+ "runtime_allowed=153 enabled=144 explicit_non_loot=9 runtime_disabled=3 "
		+ "compiled_enabled_slots=6809 pre_overflow_rng=6809 ground_limit=9"
	)
	get_tree().quit(0)


func _test_direct_authority_and_gate() -> void:
	var baseline: Dictionary = GameData.dpv2_direct_baseline
	assert(str(baseline.get("authority_id", "")) == "dpv2.direct_baseline.v2")
	assert(str(baseline.get("identity_key", "")) == "canonical_monster_id")
	assert(bool(baseline.get("production_active", false)))
	assert(str(baseline.get("production_runtime", "")) == "V2_DIRECT_BASELINE")
	var policy: Dictionary = baseline.get("probability_policy", {})
	assert(
		str(policy.get("effective_probability", ""))
			== "min(1, base_numerator * scale_num / (base_denominator * scale_den))"
	)
	assert(not bool(policy.get("role_factor_participates", true)))
	assert(not bool(policy.get("tier_denominator_participates", true)))
	assert(bool(policy.get("all_slots_rng_before_overflow", false)))
	assert(int(policy.get("post_rng_ground_slot_limit", -1)) == 9)
	var gate: Dictionary = GameData.dpv2_source_slot_gate()
	assert(str(gate.get("authority", "")) == "dpv2.direct_baseline.v2")
	assert(int(gate.get("compiled_slots", -1)) == 6809)
	assert(int(gate.get("drop_enabled_source_slots", -1)) == 6809)
	assert(int(gate.get("drop_disabled_source_slots", -1)) == 2781)
	assert(int(gate.get("explicit_non_loot_source_rows", -1)) == 223)
	assert(int(gate.get("retired_source_rows", -1)) == 2558)
	assert(int(gate.get("runtime_allowed_monsters", -1)) == 153)
	assert(int(gate.get("drop_enabled_monsters", -1)) == 144)
	assert(int(gate.get("explicit_non_loot_monsters", -1)) == 9)
	assert(int(gate.get("runtime_disabled_monsters", -1)) == 3)
	assert(int(gate.get("maximum_ground_slots", -1)) == 9)


func _test_global_scale_contract() -> void:
	var global_authority: Dictionary = GameData.dpv2_global_drop_rate_authority
	assert(str(global_authority.get("status", "")) == "PRODUCTION_ACTIVE_DIRECT_BASELINE")
	var contract: Dictionary = global_authority.get("probability_contract", {})
	assert(str(contract.get("arithmetic", "")) == "exact_positive_rational")
	assert(str(contract.get("base_probability_source", "")) == "dpv2_direct_baseline_v2")
	assert(not bool(contract.get("role_factor_participates", true)))
	assert(not bool(contract.get("tier_denominator_participates", true)))
	assert(bool(global_authority.get("activation", {}).get("fallback_forbidden", false)))
	var scale := GameData.dpv2_active_global_drop_rate()
	assert(str(scale.get("preset", "")) == "1x")
	assert(int(scale.get("numerator", -1)) == 1)
	assert(int(scale.get("denominator", -1)) == 1)


func _test_production_roll_is_direct_and_full_slot() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260828
	var direct_profile := GameData.dpv2_direct_profile(76)
	var direct_slots: Array = direct_profile.get("slots", [])
	var roll: Dictionary = service.roll_monster_drops(76, rng)
	assert(str(roll.get("contract_id", "")) == "monster.loot.dpv2_direct_baseline.v2")
	assert(str(roll.get("runtime_authority", {}).get("authority_id", "")) == "dpv2.direct_baseline.v2")
	assert(bool(roll.get("configured", false)), str(roll))
	assert(int(roll.get("source_entry_count", -1)) == direct_slots.size())
	assert(int(roll.get("resolution_attempted_count", -1)) == direct_slots.size())
	assert(int(roll.get("reward_resolved_enabled_slots", -1)) == direct_slots.size())
	assert(int(roll.get("probability_resolved_enabled_slots", -1)) == direct_slots.size())
	assert(int(roll.get("rng_eligible_slots", -1)) == direct_slots.size())
	assert(int(roll.get("rng_roll_count", -1)) == direct_slots.size())
	assert(bool(roll.get("all_resolved_slots_rng", false)))
	assert(bool(roll.get("all_enabled_resolved_slots_rng_before_overflow", false)))
	assert(int(roll.get("ground_output_count", 0)) <= 9)
	assert(
		int(roll.get("ground_output_count", 0))
			+ int(roll.get("overflow_discarded_count", 0))
		== int(roll.get("successful_roll_count", -1))
	)
	for raw_attempt: Variant in roll.get("attempts", []):
		assert(raw_attempt is Dictionary)
		var attempt: Dictionary = raw_attempt
		assert(str(attempt.get("slot_uid", "")).begins_with("dpv2.direct.m76."))
		assert(attempt.has("canonical_item_id"))
		assert(attempt.has("base_numerator"))
		assert(attempt.has("base_denominator"))
		assert(attempt.has("global_scale"))
		assert(attempt.has("final_probability"))
		assert(attempt.has("draw"))
		assert(attempt.has("draw_success"))
		assert(attempt.has("overflow"))
		assert(attempt.has("protected_overflow"))
		assert(attempt.has("baseline_origin"))
		assert(attempt.has("source_provenance_id"))


func _test_non_loot_and_zero_slot_profiles_fail_closed_without_fallback() -> void:
	var service := LootRuntimeScript.new()
	var rng := RandomNumberGenerator.new()
	var non_loot := service.roll_monster_drops(145, rng)
	assert(bool(non_loot.get("configured", false)))
	assert(str(non_loot.get("reason", "")) == "drop_disabled")
	assert(int(non_loot.get("rng_roll_count", -1)) == 0)
	var zero_slot := service.roll_monster_drops(33, rng)
	assert(bool(zero_slot.get("configured", false)))
	assert(str(zero_slot.get("reason", "")) == "drop_disabled")
	assert(int(zero_slot.get("source_entry_count", -1)) == 0)
	assert(int(zero_slot.get("rng_roll_count", -1)) == 0)
	var unknown := service.roll_monster_drops(999999, rng)
	assert(str(unknown.get("reason", "")) == "dpv2_direct_profile_unresolved")
