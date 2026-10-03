extends Node

const Observer := preload("res://scripts/damage_ledger_observer.gd")
const Verifier := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")
const Fault := preload("res://tests/hc_monster_combat_r4/damage_write_fault_fixture.gd")
const FrameObservation := preload("res://tests/hc_monster_combat_r4/bounded_frame_observation.gd")
var game: Node
var player: PlayerCharacter
var enemy: EnemyActor
var all_lost_only := false

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var boot_deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < boot_deadline:
		await get_tree().process_frame
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	var results: Dictionary = {}
	var cases: Array = ["all_damage_lost"] if all_lost_only else ["positive_control", "real_reduction", "lost_damage_substituted", "duplicate_apply", "nested_unknown", "nested_foreign", "legal_reject", "cross_life_reject", "legal_miss"]
	for name: String in cases:
		results[name] = await _case(name)
		print("ATTR_CASE ", name, " -> ", results[name].failures)
	Observer.recording_enabled = false
	player.test_damage_write_hook = Callable()
	var failed := false
	for result: Dictionary in results.values():
		failed = failed or not result.failures.is_empty()
	var path := "res://outputs/test_logs/r4_counterexamples%s.json" % ("_all_lost" if all_lost_only else "")
	FileAccess.open(path, FileAccess.WRITE).store_string(JSON.stringify(results, "  "))
	if failed:
		printerr("R4_ATTR_COUNTEREXAMPLES_FAIL ", path)
	else:
		print("R4_ATTR_ALL_LOST_PASS" if all_lost_only else "R4_ATTR_COUNTEREXAMPLES_PASS")
	get_tree().quit(1 if failed else 0)

func _case(name: String) -> Dictionary:
	var failures: Array = []
	player.current_hp = player.max_hp
	player.defense_min = 3 if name == "real_reduction" else 0
	player.defense_max = player.defense_min
	PlayerState.computed_stats["anti_magic_points"] = 10 if name == "legal_miss" else 0
	var fixture: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
	player.global_position = fixture
	game._set_player_world_position(fixture)
	Observer.recording_enabled = true
	Observer.reset()
	enemy = game._spawn_enemy(GameData.get_monster_by_id(76 if name == "legal_miss" else 24), fixture + Vector2(30.0, 0.0), false, -1.0, {"respawn_enabled": false, "spawn_slot_id": "test:r4-attribution"})
	if enemy == null:
		return {"failures": ["spawn_failed"]}
	var source_id := enemy.get_instance_id()
	var fault := Fault.new()
	fault.mode = name
	fault.source_id = source_id
	fault.target_id = player.get_instance_id()
	player.test_damage_write_hook = fault.write_count
	var starts: Array = []
	var n := 20 if all_lost_only else 2
	# Only all_lost_only has the explicit user90s exception. Preserve every
	# ordinary counterexample's16s window and the20-real-write assertions.
	var deadline := 87000 if all_lost_only else Time.get_ticks_msec() + 16000
	var frame_observation := FrameObservation.new() if all_lost_only else null
	if frame_observation != null: frame_observation.begin()
	var rejection_injections := [0]
	if name in ["legal_reject", "cross_life_reject"]:
		enemy.test_attack_admission_hook = func(record: Dictionary) -> void:
			if rejection_injections[0] > 0 or int(record.target_id) != player.get_instance_id():
				return
			rejection_injections[0] += 1
			if name == "legal_reject":
				player.global_position = fixture + Vector2(300.0, 0.0)
			else:
				if not player.begin_combat_transition("r4-lifecycle-counterexample") or not player.finish_combat_transition("r4-lifecycle-counterexample"):
					failures.append("real_lifecycle_transition_failed")
	while Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
		if frame_observation != null: frame_observation.record_frame()
		starts = []
		for admission: Dictionary in Observer.admissions:
			if int(admission.source_instance_id) == source_id:
				starts.append(admission)
		if rejection_injections[0] > 0 and not starts.is_empty() and enemy._hc_settled_seq >= int(starts[0].seq):
			player.global_position = fixture
		if starts.size() >= n and enemy._hc_settled_seq >= int(starts.back().seq):
			break
	var audit := Verifier.audit_releases(starts, Observer.events, Observer.terminal_events, source_id, Observer.deliveries, Observer.overflowed)
	var ledger := Verifier.verdict(Observer.events, Observer.terminal_events, source_id)
	if starts.size() < n:
		failures.append("insufficient_natural_starts=%d expected=%d" % [starts.size(), n])
	var expected_fail := name in ["lost_damage_substituted", "duplicate_apply", "all_damage_lost"]
	if expected_fail:
		if fault.injected != (n if all_lost_only else 1):
			failures.append("fault_did_not_reach_exact_real_write count=%d" % fault.injected)
		var reason := "duplicate_apply" if name == "duplicate_apply" else "release_missing_terminal"
		var matching := 0
		for f: String in audit.failures:
			if f.begins_with(reason):
				matching += 1
		if matching != (n if all_lost_only else 1):
			failures.append("verifier_wrong_failure_count=%d expected=%d" % [matching, n if all_lost_only else 1])
		if all_lost_only and not ledger.under_test_mutations.is_empty():
			failures.append("all_lost_has_actual_debit")
	else:
		failures.append_array(audit.failures)
	if name == "real_reduction":
		for e: Dictionary in ledger.under_test_mutations:
			if int(e.actual_hp_delta) != maxi(1, int(e.source.raw_roll) - 3):
				failures.append("reduction_not_real")
		if ledger.under_test_mutations.size() != n:
			failures.append("reduction_samples_missing")
	if name in ["lost_damage_substituted", "nested_unknown", "nested_foreign"]:
		if fault.foreign_writes != 1:
			failures.append("nested_real_writer_missing")
		var rows: Array = ledger.unknown_mutations if name == "nested_unknown" else ledger.foreign_mutations
		var found := false
		for row: Dictionary in rows:
			if int(row.physics_tick) == int(fault.facts[0].physics_tick) and int(row.actual_hp_delta) == int(fault.facts[0].amount):
				found = true
		if not found:
			failures.append("same_tick_same_amount_replacement_not_applied")
	if name in ["legal_miss", "legal_reject", "cross_life_reject"]:
		var found := false
		for terminal: Dictionary in Observer.terminal_events:
			if int(terminal.source.get("source_instance_id", -1)) == source_id:
				found = true
		if not found:
			failures.append("real_terminal_branch_not_reached")
	var result := {"starts": starts.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "raw_events": Observer.events.duplicate(true), "terminal_events": Observer.terminal_events.duplicate(true), "audit": audit, "fault_facts": fault.facts, "failures": failures}
	if frame_observation != null:
		result["frame_observation"] = frame_observation.snapshot()
		if frame_observation.overflowed: failures.append("frame_observation_overflow")
	player.test_damage_write_hook = Callable()
	enemy.free()
	return result
