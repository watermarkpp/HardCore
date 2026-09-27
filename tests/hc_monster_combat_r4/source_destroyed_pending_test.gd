extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real owner destruction while the source-owned 600ms pending still exists.
## A transient tree exit is a separate control: it is not destruction.
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	Observer.recording_enabled = true
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.position = _ground_to_screen(Vector2(16, 16))
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 100000
	player.current_hp = player.max_hp
	for action: String in ["free", "queue_free"]:
		Observer.reset()
		var actor := _spawn(79, Vector2(14, 16))
		var id := actor.get_instance_id()
		actor.set_physics_process(true)
		var deadline := Time.get_ticks_msec() + 2200
		while Observer.deliveries.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
		_check(Observer.admissions.size() == 1 and Observer.deliveries.size() == 1 and actor._pending_attack_time > 0, action + ":no_real_frozen_pending")
		var hp_before := player.current_hp
		if action == "free":
			actor.free()
		else:
			actor.queue_free()
		await get_tree().process_frame
		await get_tree().create_timer(0.85).timeout
		_check(not is_instance_valid(actor), action + ":owner_not_actually_destroyed")
		var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, id, Observer.deliveries, Observer.overflowed)
		_check(audit.failures.is_empty(), action + ":" + str(audit.failures))
		_check(player.current_hp == hp_before and Observer.events.is_empty(), action + ":destroyed_owner_hit_applied")
		_check(Observer.terminal_events.size() == 1 and Observer.terminal_events[0].terminal_kind == "rejected", action + ":no_unique_actual_cancellation")
		rows.append({"case": action, "admissions": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	# Leaving the tree alone must not fabricate a destruction terminal.
	Observer.reset()
	var returning := _spawn(79, Vector2(14, 16))
	var returning_id := returning.get_instance_id()
	returning.set_physics_process(true)
	var return_deadline := Time.get_ticks_msec() + 2200
	while Observer.deliveries.is_empty() and Time.get_ticks_msec() < return_deadline:
		await get_tree().physics_frame
	_check(Observer.admissions.size() == 1 and Observer.deliveries.size() == 1 and returning._pending_attack_time > 0, "transient_exit:no_real_pending")
	var runtime_id := returning.spatial_actor_runtime_id
	var ground_before := _screen_to_ground(returning.global_position)
	remove_child(returning)
	_check(is_instance_valid(returning) and Observer.terminal_events.is_empty(), "transient_exit:premature_terminal")
	add_child(returning)
	returning.configure_spatial_index(index, runtime_id)
	index.register(runtime_id, MAP_ID, ground_before, returning.combat_radius_gu, runtime_id, returning)
	returning.set_physics_process(true)
	await get_tree().create_timer(0.85).timeout
	returning.set_physics_process(false)
	var return_audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, returning_id, Observer.deliveries, Observer.overflowed)
	_check(return_audit.failures.is_empty(), "transient_exit:" + str(return_audit.failures))
	_check(Observer.admissions.size() == 1 and Observer.events.size() + Observer.terminal_events.size() == 1, "transient_exit:not_one_real_result")
	for terminal: Dictionary in Observer.terminal_events:
		_check(str(terminal.get("rejection_reason", "")) != "SOURCE_DESTROYED", "transient_exit:destruction_forged")
	rows.append({"case": "transient_exit_return", "admissions": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": return_audit})
	returning.free()
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/r4_source_destroyed.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	player.queue_free()
	await get_tree().process_frame
	print("R4_SOURCE_DESTROYED_PASS" if failures.is_empty() else "R4_SOURCE_DESTROYED_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
