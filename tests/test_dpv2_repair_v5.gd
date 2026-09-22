extends Node

const Loot = preload("res://scripts/layers/runtime/loot_runtime_service.gd")
var failed := false

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, message: String) -> void:
	if not ok:
		failed = true
		push_error("DPV2_V5_FAIL: " + message)

func _run() -> void:
	_check(GameData.is_dpv2_direct_baseline_loaded(), "baseline must load")
	_check(GameData.dpv2_ground_slot_limit() == 15, "production authority must enable fifteen slots")
	_check(GameData.is_dpv2_single_player_drop_boost_loaded(), "SPB must load: " + GameData.load_error)
	if failed:
		get_tree().quit(1)
		return
	var service := Loot.new()
	add_child(service)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260907
	var old_enabled: bool = bool(GameData.dpv2_single_player_drop_boost.production.enabled)
	GameData.dpv2_single_player_drop_boost.production.enabled = false
	for profile: Dictionary in GameData.dpv2_direct_baseline.profiles:
		for slot: Dictionary in profile.slots:
			var off: Dictionary = GameData.dpv2_effective_slot_probability(profile.canonical_monster_id, slot.slot_uid)
			_check(bool(off.get("ok", false)), "SPB off resolution")
			_check(int(off.get("final_numerator", 0)) * int(slot.base_denominator) == int(off.get("final_denominator", 0)) * int(slot.base_numerator), "SPB off base parity: " + str(slot.slot_uid))
	GameData.dpv2_single_player_drop_boost.production.enabled = old_enabled
	service.clear_runtime_resolution_cache_for_test()
	# Complete production census: the optimized path must roll every slot with
	# exactly the same RNG consumption, probability and retained rewards as audit.
	var checked_slots := 0
	var potion_slots := 0
	for profile: Dictionary in GameData.dpv2_direct_baseline.profiles:
		if not bool(profile.drop_enabled):
			continue
		var mid := int(profile.canonical_monster_id)
		var audited_rng := RandomNumberGenerator.new()
		var lean_rng := RandomNumberGenerator.new()
		audited_rng.seed = 20260913 + mid
		lean_rng.seed = audited_rng.seed
		var audited: Dictionary = service.roll_monster_drops(mid, audited_rng, true)
		var lean: Dictionary = service.roll_monster_drops(mid, lean_rng, false)
		_check(str(audited.get("reason", "")) == "" and str(lean.get("reason", "")) == "", "full profile resolution: %d" % mid)
		_check(int(audited.rng_roll_count) == profile.slots.size() and int(lean.rng_roll_count) == profile.slots.size(), "every slot receives RNG before overflow: %d" % mid)
		_check(audited_rng.state == lean_rng.state and audited.items == lean.items and audited.gold_drops == lean.gold_drops, "lean/audit RNG and retained rewards: %d" % mid)
		_check(int(audited.ground_output_count) <= 15 and bool(audited.ground_output_plus_discarded_equals_successful), "full profile cap/accounting: %d" % mid)
		checked_slots += int(audited.rng_roll_count)
		for attempt: Dictionary in audited.attempts:
			var item := int(attempt.get("canonical_item_id", -1))
			var mc := GameData.canonical_monster_classification(mid)
			if mc in ["elite", "boss"] and item in [920014, 920016]:
				var probability: Dictionary = GameData.dpv2_effective_slot_probability(mid, str(attempt.slot_uid))
				_check(int(attempt.final_numerator) * int(probability.final_denominator) * 2 == int(probability.final_numerator) * int(attempt.final_denominator), "preserved solar-water denominator x2: " + str(attempt.slot_uid))
				potion_slots += 1
	_check(checked_slots == 7611 and potion_slots > 0, "complete 7611-slot production census with solar-water cases")
	print("DPV2_COMPLETE_CENSUS slots=%d solar_slots=%d lean_audit_rng_parity=1 cap=15" % [checked_slots, potion_slots])
	for mid: int in [73, 74, 75, 76, 89, 90, 91, 135, 141, 198, 199, 225, 235, 236, 237, 238, 239, 240]:
		var result: Dictionary = service.roll_monster_drops(mid, rng, true)
		_check(str(result.get("reason", "")) == "", "roll must resolve: %d" % mid)
		_check(int(result.get("canonical_monster_id", -1)) == mid, "exact monster identity")
		_check(int(result.get("ground_output_count", 0)) <= 15, "fifteen-slot cap")
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
		var probability: Dictionary = GameData.dpv2_effective_slot_probability(mid, target)
		_check(int(probability.get("final_numerator", 0)) == 1 and int(probability.get("final_denominator", 0)) == 60, "armor 1/60")
		for slot: Dictionary in profile.slots:
			candidates.append({"slot_uid": slot.slot_uid, "policy": slot, "reward": {}, "attempt": {}})
		var selected: Dictionary = service.call("_select_ground_rewards", candidates, rng, GameData.dpv2_ground_slot_limit())
		_check((selected.selected as Array).size() == mini(15, candidates.size()), "all-success overflow fills fifteen slots")
		var retained := false
		for row: Dictionary in selected.selected:
			retained = retained or str(row.slot_uid) == target
		_check(retained, "target survives all-success overflow: " + target)
	# Actual service CPU burst timing; this is NOT a node-spawn/frame/APK test.
	for count: int in [10, 20, 50]:
		var started := Time.get_ticks_usec()
		for index: int in range(count):
			service.roll_monster_drops(141, rng, false)
		print("DPV2_V5_SERVICE_BURST count=%d usec=%d scope=roll_and_select_only" % [count, Time.get_ticks_usec() - started])
	service.queue_free()
	# V5.0.3 user-authorized 4B fix: the repository runner's pass-marker
	# contract is the single token [A-Z0-9_]+_PASS; emit that exact token.
	print("DPV2_V5_RUNTIME_GATE_PASS" if not failed else "DPV2_V5_RUNTIME_GATE_FAIL")
	get_tree().quit(1 if failed else 0)
