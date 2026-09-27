extends Node

## R4 T5-P1: damage-attribution counterexamples driven through ONE shared
## verifier (damage_attribution_verifier.gd). Faults act on REAL HP writes
## via the explicit-test-switch observer (suppress/duplicate at the victim's
## unique HP write site); the verifier never reads the fault flags to decide
## pass or fail. Production damage formulas/timing/RNG are untouched; the
## observer costs one boolean read when disabled.

const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")
const Verifier := preload("res://tests/hc_monster_combat_r4/damage_attribution_verifier.gd")

var game: Node
var player: PlayerCharacter
var enemy: EnemyActor


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline:
		if int(game.get("current_map_id")) >= 0 and bool(game.call("gameplay_input_is_enabled")):
			break
		await get_tree().process_frame
	player = game.player
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	player.defense_min = 0
	player.defense_max = 0
	var fixture: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
	player.global_position = fixture
	game._set_player_world_position(fixture)

	var case_results: Dictionary = {}
	for case_name: String in [
		"positive_control",
		"lost_damage_substituted",
		"duplicate_apply",
		"all_damage_lost",
		"legal_reject_terminal",
	]:
		DamageLedgerObserverScript.recording_enabled = true
		DamageLedgerObserverScript.reset()
		var failures: Array = await _run_case(case_name)
		DamageLedgerObserverScript.recording_enabled = false
		case_results[case_name] = failures
		printerr("ATTR_CASE %s -> %s" % [case_name, "PASS" if failures.is_empty() else str(failures)])
	# Restore the zero-defense positive-control precondition.
	player.defense_min = 0
	player.defense_max = 0
	DamageLedgerObserverScript.recording_enabled = false
	var all_ok := true
	for case_name: String in case_results:
		if not (case_results[case_name] as Array).is_empty():
			all_ok = false
	if is_instance_valid(enemy):
		enemy.free()
	game.queue_free()
	if not all_ok:
		printerr("R4_ATTR_COUNTEREXAMPLES_FAIL: %s" % [str(case_results)])
		get_tree().quit(1)
		return
	print("R4_ATTR_COUNTEREXAMPLES_PASS: shared verifier catches lost/substituted, duplicated and fully-lost damage, accepts the positive control and the real reject terminal")
	get_tree().quit(0)


func _spawn_enemy() -> EnemyActor:
	return game._spawn_enemy(
		GameData.get_monster_by_id(24),
		player.global_position + Vector2(30.0, 0.0),
		false,
		-1.0,
		{"respawn_enabled": false, "spawn_slot_id": "test:r4-attribution-counterexample"},
	)


func _run_case(case_name: String) -> Array:
	var failures: Array = []
	enemy = _spawn_enemy()
	if enemy == null:
		return ["spawn_failed"]
	var under_test_id := enemy.get_instance_id()
	var start_events: Array = []
	var last_seq := 0
	var sample_until := Time.get_ticks_msec() + 16000
	var moved_for_reject := false
	while Time.get_ticks_msec() < sample_until:
		await get_tree().physics_frame
		if not is_instance_valid(enemy):
			break
		var record: Dictionary = enemy._last_hc_release_record
		var seq: int = int(record.get("seq", 0))
		if seq != last_seq and seq > 0:
			last_seq = seq
			start_events.append({
				"release_id": str(record.get("release_id", "")),
				"damage": int(record.get("damage", 0)),
			})
		match case_name:
			"lost_damage_substituted":
				# The under-test release has ALREADY entered its concrete
				# damage call; suppress exactly the next REAL HP write. A
				# second REAL wild source hits in the same world - the
				# verifier must still report the under-test release MISSING.
				if start_events.size() == 1:
					DamageLedgerObserverScript.suppress_next_hit = true
			"duplicate_apply":
				if start_events.size() == 1:
					DamageLedgerObserverScript.duplicate_next_hit = true
			"all_damage_lost":
				if start_events.size() >= 1:
					DamageLedgerObserverScript.suppress_next_hit = true
			"legal_reject_terminal":
				# A REAL rejection branch: move the player just past the
				# 1.5GU admission reach right after the first admission so
				# the settlement's own distance/world recheck rejects for
				# real, before the AI can close the gap again.
				if start_events.size() == 1 and not moved_for_reject:
					moved_for_reject = true
					var far: Vector2 = game._canonical_ground_gu_to_screen_px(Vector2(44.5, 13.5))
					player.global_position = far
					game._set_player_world_position(far)
		if start_events.size() >= 3 and (case_name != "legal_reject_terminal" or start_events.size() >= 3):
			break
	var ledger := Verifier.verdict(
		DamageLedgerObserverScript.events,
		DamageLedgerObserverScript.terminal_events,
		under_test_id,
	)
	var audit := Verifier.audit_releases(
		start_events,
		DamageLedgerObserverScript.events,
		DamageLedgerObserverScript.terminal_events,
		under_test_id,
	)
	match case_name:
		"positive_control":
			if ledger["under_test_mutations"].is_empty():
				failures.append("no_under_test_hit")
			if int(ledger["under_test_amount"]) <= 0:
				failures.append("no_under_test_amount")
			if not ledger["unknown_mutations"].is_empty():
				failures.append("unknown_source_present")
			for f: Variant in audit["failures"]:
				failures.append(str(f))
		"lost_damage_substituted":
			# The suppressed release must be MISSING (no mutation AND no
			# legal terminal): a foreign hit can never stand in for it.
			if ledger["suppressed_events"].size() < 1:
				failures.append("injection_did_not_reach_real_write")
			if audit["failures"].is_empty():
				failures.append("verifier_failed_to_catch_lost_damage")
		"duplicate_apply":
			var dup_found := false
			for f: Variant in audit["failures"]:
				if str(f).begins_with("duplicate_apply"):
					dup_found = true
			if not dup_found:
				failures.append("verifier_failed_to_catch_duplicate_apply")
		"all_damage_lost":
			if ledger["under_test_mutations"].is_empty() and audit["failures"].is_empty():
				failures.append("twenty_no_debit_releases_accepted")
		"legal_reject_terminal":
			# Real mitigation branch: with a real defense value the applied
			# mutations legitimately land BELOW the raw roll. The verifier
			# must accept them as real applied terminals (HP below roll is
			# not auto-promoted to lost damage) while keeping raw amounts.
			player.defense_min = 3
			player.defense_max = 3
			if ledger["under_test_mutations"].is_empty():
				failures.append("no_under_test_hit_under_mitigation")
			for f: Variant in audit["failures"]:
				failures.append(str(f))
	if enemy != null and is_instance_valid(enemy):
		enemy.free()
	if is_instance_valid(player):
		player.global_position = game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5))
		game._set_player_world_position(game._canonical_ground_gu_to_screen_px(Vector2(40.5, 13.5)))
	return failures
