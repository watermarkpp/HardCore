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
	for mid: int in [73, 74, 75, 76, 89, 90, 91, 135, 141, 198, 199, 225, 235, 236, 237, 238, 239, 240]:
		var result: Dictionary = service.roll_monster_drops(mid, rng, true)
		_check(str(result.get("reason", "")) == "", "roll must resolve: %d" % mid)
		_check(int(result.get("canonical_monster_id", -1)) == mid, "exact monster identity")
		_check(int(result.get("ground_output_count", 0)) <= 9, "nine-slot cap")
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
		var selected: Dictionary = service.call("_select_ground_rewards", candidates, rng, 9)
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
