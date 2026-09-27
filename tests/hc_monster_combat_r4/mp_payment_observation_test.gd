extends Node

const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Verifier := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")
var failures: Array = []

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var player := PlayerCharacter.new()
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000
	player.defense_min = 0
	player.defense_max = 0
	PlayerState.computed_special_effects = {"magic_shield": {"test_input": true}}
	Observer.recording_enabled = true
	var cases: Array = []
	for initial_mp: int in [50, 10]:
		Observer.reset()
		player.current_hp = 1000
		player.current_mp = initial_mp
		var start := {"source_instance_id": 12, "source_life": 1, "parent_action_id": 1,
			"release_id": "fixed-mp-input", "target_id": player.get_instance_id(), "target_life": player.combat_epoch,
			"target_generation": -1, "map_id": 9001, "generation": 1}
		var child := {"source_instance_id": 12, "source_life": 1, "parent_action_id": 1,
			"release_id": "fixed-mp-input", "admission_release_id": "fixed-mp-input", "child_effect_id": "physical",
			"victim_instance_id": player.get_instance_id(), "victim_life": player.combat_epoch,
			"victim_generation": -1, "runtime_map_id": 9001, "zone_generation": 1}
		# Independent known input: 20 physical with AC0 costs 30 MP; when only
		# 10 MP exists the unpaid 20 MP produces round(20/1.5)=13 HP damage.
		player.take_damage(20, false, {}, false, child)
		var expected_hp := 1000 if initial_mp == 50 else 987
		var expected_mp := 20 if initial_mp == 50 else 0
		if player.current_hp != expected_hp or player.current_mp != expected_mp:
			failures.append("fixed_input_damage_or_payment_wrong mp=%d" % initial_mp)
		var results: Array = Observer.events + Observer.terminal_events
		if results.size() != 1 or int(results[0].get("mp_before", -1)) != initial_mp or int(results[0].get("mp_after", -1)) != expected_mp:
			failures.append("actual_mp_payment_not_observed mp=%d" % initial_mp)
		var audit := Verifier.audit_releases([start], Observer.events, Observer.terminal_events, 12, [child])
		failures.append_array(audit.failures)
		cases.append({"initial_mp": initial_mp, "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	Observer.recording_enabled = false
	PlayerState.computed_special_effects.clear()
	FileAccess.open("res://outputs/test_logs/r4_mp_payment.json", FileAccess.WRITE).store_string(JSON.stringify({"cases": cases, "failures": failures}, "  "))
	player.free()
	if failures.is_empty():
		print("R4_MP_PAYMENT_OBSERVATION_PASS")
	else:
		printerr("R4_MP_PAYMENT_OBSERVATION_FAIL ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
