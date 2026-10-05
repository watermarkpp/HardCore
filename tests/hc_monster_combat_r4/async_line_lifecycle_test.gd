extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real Race 88 line admission and its source-defined 600ms delayed dispatch.
## No direct settlement calls and no pending/cooldown/clock writes.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Observer.recording_enabled = true
	for change: String in ["positive", "target_epoch", "source_epoch", "target_free"]:
		await _case(change)
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/r4_async_line.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	print("R4_ASYNC_LINE_PASS" if failures.is_empty() else "R4_ASYNC_LINE_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _case(change: String) -> void:
	Observer.reset()
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.position = _ground_to_screen(Vector2(16, 16))
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 10000
	player.current_hp = player.max_hp
	var actor := _spawn(79, Vector2(14, 16))
	_check(str(actor.attack_delivery_rule.get("kind", "")) == "line_magic", change + ":not_line_family")
	actor.set_physics_process(true)
	var deadline := Time.get_ticks_msec() + 2200
	while Observer.deliveries.is_empty() and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(Observer.admissions.size() == 1 and Observer.deliveries.size() == 1 and actor._pending_attack_time > 0, change + ":no_actual_frozen_pending")
	var hp_before := player.current_hp
	match change:
		"target_epoch":
			_check(player.begin_combat_transition("async-r4") and player.finish_combat_transition("async-r4"), "target_epoch:transition_failed")
		"source_epoch":
			actor.set_meta("zone_generation", 2)
		"target_free":
			player.free()
	await get_tree().create_timer(0.85).timeout
	actor.set_physics_process(false)
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), change + ":audit=" + str(audit.failures))
	if change == "positive":
		_check(Observer.events.size() + Observer.terminal_events.size() == 1, "positive:missing_actual_result")
	else:
		_check(Observer.events.is_empty() and Observer.terminal_events.size() == 1, change + ":stale_delivery_not_rejected")
		_check(not is_instance_valid(player) or player.current_hp == hp_before, change + ":old_life_damage")
	rows.append({"case": change, "starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	if is_instance_valid(player):
		player.free()
	await get_tree().physics_frame
