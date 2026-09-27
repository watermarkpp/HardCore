extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

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
	for reason: String in ["disabled", "control", "death"]:
		Observer.reset()
		var actor := _spawn(79, Vector2(14, 16))
		var id := actor.get_instance_id()
		actor.set_physics_process(true)
		var deadline := Time.get_ticks_msec() + 2200
		while Observer.deliveries.is_empty() and Time.get_ticks_msec() < deadline:
			await get_tree().physics_frame
		_check(Observer.admissions.size() == 1 and Observer.deliveries.size() == 1 and actor._pending_attack_time > 0, reason + ":no_real_pending")
		var hp_before := player.current_hp
		match reason:
			"disabled":
				actor.combat_enabled = false
			"control":
				actor.apply_control(0.5)
			"death":
				actor.take_damage(actor.max_hp + 1, player)
		actor.set_physics_process(true)
		await get_tree().create_timer(0.65).timeout
		var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, id, Observer.deliveries, Observer.overflowed)
		_check(audit.failures.is_empty(), reason + ":" + str(audit.failures))
		_check(player.current_hp == hp_before, reason + ":cancelled_hit_changed_hp")
		_check(Observer.terminal_events.size() == 1 and Observer.terminal_events[0].terminal_kind == "rejected", reason + ":not_one_real_rejection")
		rows.append({"case": reason, "admissions": Observer.admissions.duplicate(true), "events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
		if is_instance_valid(actor):
			index.unregister(actor.spatial_actor_runtime_id)
			actor.free()
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/r4_cancelled_release.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	player.queue_free()
	await get_tree().process_frame
	print("R4_CANCELLED_RELEASE_PASS" if failures.is_empty() else "R4_CANCELLED_RELEASE_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
