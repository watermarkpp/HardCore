extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var center := CENTER + Vector2(4.0, 0.0)
	var actor := _spawn(64, center)
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor._leave_background_deep_sleep()
	actor.dormant = false
	actor.target = player
	actor._retarget_timer = 999.0
	var blockers: Array[EnemyActor] = []
	# Close every exit with the actual canonical footsole diameter. A fixed
	# 1.1 GU ring leaves these small bodies room to move and reverse, so it
	# does not prove the zero-displacement presentation contract.
	var body_spacing := 2.0 * actor.combat_radius_gu
	for offset in [Vector2(-1, -1), Vector2(0, -1), Vector2(1, -1), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1), Vector2(-1, 1), Vector2(-1, 0)]:
		var body := _spawn(64, center + offset * body_spacing)
		body._leave_background_deep_sleep()
		body.set_physics_process(false)
		blockers.append(body)
	await get_tree().physics_frame
	for body in blockers:
		_check(body.combat_radius_gu == actor.combat_radius_gu, "fixture body diameter mismatched")
		for other in blockers:
			if body != other:
				_check(body.spatial_index_position().distance_to(other.spatial_index_position()) >= body_spacing - GU.EPSILON_GU, "fixture blocker bodies overlap")
	for direction in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_check(not actor._hc_motion_clear(center, center + direction * 0.01), "fixture has a legal body exit")
	actor.set_physics_process(true)
	var blocked := 0
	var frames := {}
	var samples: Array = []
	var diagnostic_samples: Array = []
	for frame in 180:
		await get_tree().physics_frame
		await get_tree().process_frame
		_check(actor.spatial_index_position().distance_to(center) <= GU.EPSILON_GU, "closed body cage allowed continuing displacement")
		if frame % 15 == 0:
			diagnostic_samples.append({"frame":frame,"reason":actor._hc_last_reason,"pose":actor.visual.current_state,"pose_frame":actor.visual.current_frame,"intent":actor._locomotion_pose_intent,"session":actor._hc_pursuit_session,"actual_gu":str(actor.actual_ground_motion_gu)})
		if actor.actual_ground_motion_gu.length_squared() < 0.000000000001 and actor._hc_last_reason in ["FRONTLINE_BLOCKED", "MOTION_BLOCKED"]:
			blocked += 1
			frames[actor.visual.current_frame] = true
			_check(actor.visual.current_state == "walk", "native blocked pursuit displayed idle")
			if frame % 15 == 0: samples.append(actor.visual.hc_m30_motion_snapshot())
	_check(blocked >= 30, "fixture did not sustain real body-blocked pursuit")
	_check(frames.size() > 1, "blocked walk pose did not advance")
	_check(actor.visual.hc_m30_motion_snapshot().actual_distance_gu == 0.0, "blocked walk pose manufactured movement distance")
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = true
	await get_tree().process_frame
	var before := actor.visual.hc_m30_motion_snapshot()
	var clock_before: float = actor._combat_action_time_s
	await get_tree().create_timer(0.2, true).timeout
	_check(actor.visual.current_frame == int(before.frame), "engine pause advanced blocked animation")
	_check(is_equal_approx(actor._combat_action_time_s, clock_before), "pause changed action clock")
	get_tree().paused = false
	actor.apply_control(0.5)
	for _frame in 3:
		await get_tree().physics_frame
		await get_tree().process_frame
	_check(actor.visual.current_state == "idle", "control lock kept blocked locomotion active")
	FileAccess.open("res://outputs/test_logs/monster_blocked_locomotion.json", FileAccess.WRITE).store_string(JSON.stringify({"body_spacing_gu": body_spacing, "blocked_frames": blocked, "animation_frames": frames.keys(), "samples": samples, "diagnostic_samples": diagnostic_samples, "failures": failures}, "  "))
	for body in blockers:
		index.unregister(body.spatial_actor_runtime_id)
		body.queue_free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.set_physics_process(false)
	actor.queue_free()
	player.queue_free()
	await get_tree().process_frame
	print("MONSTER_BLOCKED_LOCOMOTION_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
