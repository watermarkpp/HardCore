extends Node

const Loot = preload("res://scripts/layers/runtime/loot_runtime_service.gd")
const LegacyDropPolicy = preload("res://tests/helpers/legacy_drop_probability_policy.gd")
var failed := false

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("DPV2_V5_FAIL: " + message)

func _run() -> void:
	_check(GameData.is_dpv2_direct_baseline_loaded(), "baseline must load")
	_check(GameData.dpv2_ground_slot_limit() == 15, "frozen baseline authority must retain historical fifteen-slot source cap")
	_check(GameData.is_dpv2_single_player_drop_boost_loaded(), "SPB must load: " + GameData.load_error)
	if failed:
		get_tree().quit(1)
		return
	var service := Loot.new()
	add_child(service)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	var old_enabled: bool = bool(GameData.dpv2_single_player_drop_boost.production.enabled)
	var historical_checked_slots := 0
	GameData.dpv2_single_player_drop_boost.production.enabled = false
	for profile: Dictionary in GameData.dpv2_direct_baseline.profiles:
		for slot: Dictionary in profile.slots:
			historical_checked_slots += 1
			var off: Dictionary = GameData.dpv2_effective_slot_probability(profile.canonical_monster_id, slot.slot_uid)
			_check(bool(off.get("ok", false)), "SPB off resolution")
			_check(int(off.get("final_numerator", 0)) * int(slot.base_denominator) == int(off.get("final_denominator", 0)) * int(slot.base_numerator), "SPB off base parity: " + str(slot.slot_uid))
	_check(historical_checked_slots == 7611, "complete frozen historical baseline census")
	GameData.dpv2_single_player_drop_boost.production.enabled = old_enabled
	service.clear_runtime_resolution_cache_for_test()
	var legacy := LegacyDropPolicy.new()
	_check(legacy.valid, "historical v80/v81 replay helper must remain sealed and valid")
	var historical_solar_slots := 0
	for profile: Dictionary in GameData.dpv2_direct_baseline.profiles:
		var historical_mid := int(profile.canonical_monster_id)
		for slot: Dictionary in profile.slots:
			var historical := legacy.probability_v81(historical_mid, str(slot.slot_uid))
			var item := int(slot.get("canonical_item_id", -1))
			var historical_classification: String = str(legacy._historical_classification_by_id.get(historical_mid, ""))
			if historical_classification in ["elite", "boss"] and item in [920014, 920016]:
				var base := GameData.dpv2_effective_slot_probability(historical_mid, str(slot.slot_uid))
				_check(bool(historical.get("ok", false)), "historical solar replay resolution: " + str(slot.slot_uid))
				var solar_stage: Dictionary = legacy._apply_drop_probability_policy(base, historical_classification)
				_check(int(solar_stage.final_numerator) * int(base.final_denominator) * 2 == int(base.final_numerator) * int(solar_stage.final_denominator), "historical solar denominator x2 before later sealed user balance: " + str(slot.slot_uid))
				var balanced_row: Dictionary = legacy.records.get(str(slot.slot_uid), {})
				var expected_numerator := int(solar_stage.final_numerator) if balanced_row.is_empty() else int(balanced_row.after[0])
				var expected_denominator := int(solar_stage.final_denominator) if balanced_row.is_empty() else int(balanced_row.after[1])
				_check(int(historical.final_numerator) == expected_numerator and int(historical.final_denominator) == expected_denominator, "complete historical final probability including sealed user balance: " + str(slot.slot_uid))
				historical_solar_slots += 1
	_check(historical_solar_slots > 0, "historical replay must cover solar-water cases")
	# Complete production census: the optimized path must roll every formal user
	# sheet slot with exactly the same RNG consumption, probability and retained
	# rewards as audit. The sealed 7611-row baseline was checked above as a
	# historical probability authority; it is not the active production slot set.
	var checked_slots := 0
	for raw_profile: Variant in service._sheet_authority.profiles_by_id.values():
		var profile: Dictionary = raw_profile
		var mid := int(profile.canonical_monster_id)
		var audited_rng := RandomNumberGenerator.new()
		var lean_rng := RandomNumberGenerator.new()
		audited_rng.seed = 20260913 + mid
		lean_rng.seed = audited_rng.seed
		var audited: Dictionary = service.roll_monster_drops(mid, audited_rng, true)
		var lean: Dictionary = service.roll_monster_drops(mid, lean_rng, false)
		var expected_cap := GameData.dpv2_ground_slot_limit_for_monster(mid)
		_check(str(audited.get("reason", "")) == "" and str(lean.get("reason", "")) == "", "full profile resolution: %d" % mid)
		_check(int(audited.rng_roll_count) == profile.slots.size() and int(lean.rng_roll_count) == profile.slots.size(), "every slot receives RNG before overflow: %d" % mid)
		_check(audited_rng.state == lean_rng.state and audited.items == lean.items and audited.gold_drops == lean.gold_drops, "lean/audit RNG and retained rewards: %d" % mid)
		_check(int(audited.ground_output_count) <= expected_cap and int(audited.ground_slot_group.ground_slot_limit) == expected_cap and bool(audited.ground_output_plus_discarded_equals_successful), "full profile group cap/accounting: %d" % mid)
		checked_slots += int(audited.rng_roll_count)
		for attempt: Dictionary in audited.attempts:
			var sheet_probability: Dictionary = service._sheet_authority.probability(mid, str(attempt.slot_uid))
			_check(bool(sheet_probability.get("ok", false)), "formal sheet probability resolution: " + str(attempt.slot_uid))
			_check(int(attempt.final_numerator) == int(sheet_probability.final_numerator) and int(attempt.final_denominator) == int(sheet_probability.final_denominator), "production must use sheet E probability exactly: " + str(attempt.slot_uid))
	_check(checked_slots == service._sheet_authority.slot_count and checked_slots == 6084, "complete user-sheet production census")
	print("DPV2_COMPLETE_CENSUS sheet_slots=%d historical_solar_slots=%d lean_audit_rng_parity=1 baseline_slots=7611 baseline_cap=15 grouped_caps=6/9/12" % [checked_slots, historical_solar_slots])
	for mid: int in [73, 74, 75, 76, 89, 90, 91, 135, 141, 198, 199, 225, 235, 236, 237, 238, 239, 240]:
		var prior_rng_state := rng.state
		var result: Dictionary = service.roll_monster_drops(mid, rng, true)
		var expected_cap := GameData.dpv2_ground_slot_limit_for_monster(mid)
		if mid in [75, 91, 199]:
			_check(service._sheet_authority.profile(mid).is_empty(), "exact retired historical monster has no formal sheet profile: %d" % mid)
			_check(str(result.get("reason", "")) == "dpv2_direct_profile_unresolved"
				and int(result.rng_roll_count) == 0 and rng.state == prior_rng_state
				and result.items.is_empty() and result.gold_drops.is_empty(),
				"retired historical monster must not fall back or consume drop RNG: %d" % mid)
		else:
			_check(str(result.get("reason", "")) == "", "roll must resolve: %d" % mid)
		_check(int(result.get("canonical_monster_id", -1)) == mid, "exact monster identity")
		_check(int(result.get("ground_output_count", 0)) <= expected_cap, "classification group cap")
		_check(int(result.get("ground_slot_group", {}).get("ground_slot_limit", 0)) == expected_cap, "receipt group cap")
		_check(bool(result.get("ground_output_plus_discarded_equals_successful", false)), "reward accounting")
		for attempt: Dictionary in result.get("attempts", []):
			var n := int(attempt.final_numerator)
			var d := int(attempt.final_denominator)
			_check(n >= 1 and n <= d, "valid inclusive RNG boundaries")
			_check(bool(attempt.draw_success) == (int(attempt.draw) <= n), "randi_range inclusive comparison")
	# Force every real slot to succeed; use actual production selector.
	for mid: int in [235, 236, 237, 238, 239, 240]:
		var candidates: Array = []
		var profile: Dictionary = GameData.dpv2_direct_profile(mid)
		var contract: Dictionary = GameData.dpv2_single_player_effective_probability.get("repair_v5_contract", {})
		var armor_by_monster: Dictionary = contract.get("armor_slot_by_monster", {})
		var target := str(armor_by_monster.get(str(mid), ""))
		_check(not target.is_empty(), "armor target UID must resolve by exact monster/item authority")
		# Historical all-success selector replay: this helper path validates the
		# sealed v80/v81 armor directive without claiming it is current sheet E.
		var probability: Dictionary = legacy.probability_v81(mid, target)
		_check(int(probability.get("final_numerator", 0)) == 1 and int(probability.get("final_denominator", 0)) == 60, "armor 1/60")
		for slot: Dictionary in profile.slots:
			candidates.append({"slot_uid": slot.slot_uid, "policy": slot, "reward": {}, "attempt": {}})
		var group_cap := GameData.dpv2_ground_slot_limit_for_monster(mid)
		var selected: Dictionary = service.call("_select_ground_rewards", candidates, rng, group_cap)
		_check((selected.selected as Array).size() == mini(group_cap, candidates.size()), "all-success overflow fills classification group slots")
		var retained := false
		for row: Dictionary in selected.selected:
			retained = retained or str(row.slot_uid) == target
		_check(retained, "target survives all-success overflow: " + target)
	# The functional census above is the scope of this regression. Performance
	# measurement belongs to the dedicated comparable-load harness and is not
	# part of this production correctness scene.
	service.free()
	# V5.0.3 user-authorized 4B fix: the repository runner's pass-marker
	# contract is the single token [A-Z0-9_]+_PASS; emit that exact token.
	print("DPV2_V5_RUNTIME_GATE_PASS" if not failed else "DPV2_V5_RUNTIME_GATE_FAIL")
	get_tree().quit(1 if failed else 0)
