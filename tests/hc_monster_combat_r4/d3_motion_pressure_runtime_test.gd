extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real input, Actor physics, damage commits and pause. No clock/cooldown writes.
const CombatRuntime := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
var runtime: Node
var rng := RandomNumberGenerator.new()

func _run() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	player = PlayerCharacter.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	runtime = CombatRuntime.new()
	add_child(runtime)
	rng.seed = 271927
	Observer.recording_enabled = true
	for mid: int in [24, 76, 238, 239]:
		await _motion_pressure(mid)
	await _real_pause_and_late_draw()
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/r4_d3_motion_pressure.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	player.queue_free()
	runtime.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
	print("R4_D3_MOTION_PRESSURE_PASS" if failures.is_empty() else "R4_D3_MOTION_PRESSURE_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _motion_pressure(mid: int) -> void:
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = _ground_to_screen(CENTER)
	Observer.reset()
	var actor := _spawn(mid, CENTER + Vector2(1.4, 0.0))
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor.max_hp = 1000000
	actor.current_hp = actor.max_hp
	var admissions: Array = []
	actor.test_attack_admission_hook = func(record: Dictionary) -> void:
		var distance := _screen_to_ground(actor.global_position - player.global_position).length()
		admissions.append({"release_id": record.release_id, "distance_gu": distance,
			"body_action_id": actor._attack_logic_serial, "physics_tick": Engine.get_physics_frames()})
		_check(distance <= 1.5 + GU.EPSILON_GU, "%d:moving_admission_outside_range" % mid)
	actor.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	# Establish one real reachable action before the faster player motion and
	# sustained DIRECT pressure. No clock/cadence/cooldown rewrite.
	var initial_admission_deadline := actor._combat_action_time_s + 4.0
	while actor._hc_starts==0 and actor._combat_action_time_s<initial_admission_deadline:
		await get_tree().physics_frame
	var motion_gu := 0.0
	var pressure_debits := 0
	var actual_struck_requests := 0
	var phases: Array = []
	var active_body_checks := 0
	for phase: String in ["lateral", "orbit", "pressure"]:
		var deadline := Time.get_ticks_msec() + (5000 if phase == "pressure" else 1500)
		var starts_before := actor._hc_starts
		var frame := 0
		while Time.get_ticks_msec() < deadline:
			if phase == "lateral":
				player.set_touch_vector(_ground_to_screen(Vector2(0, 1 if frame < 45 else -1)).normalized())
			elif phase == "orbit":
				var relative := _screen_to_ground(player.global_position - actor.global_position)
				var tangent := Vector2(-relative.y, relative.x).normalized()
				var correction := relative.normalized() * (1.15 - relative.length())
				player.set_touch_vector(_ground_to_screen(tangent + correction).normalized())
			else:
				player.set_touch_vector(Vector2.ZERO)
				if frame % 30 == 0:
					var hp_before := actor.current_hp
					var kind := CombatRuntime.EnemyMagicDeliveryKind.MAGSTRUCK_MINE if frame % 60 == 0 else CombatRuntime.EnemyMagicDeliveryKind.DIRECT_MAGSTRUCK
					var skill := "wizard.fire_wall" if frame % 60 == 0 else "wizard.exploding_flame"
					var result: Dictionary = runtime.apply_enemy_direct_spell_damage(actor, skill, 80, player, rng, Callable(), 9, {}, kind)
					if bool(result.get("success", false)):
						pressure_debits += hp_before - actor.current_hp
						actual_struck_requests += 1
			if actor.visual.current_attack_action_id() > 0:
				active_body_checks += 1
				_check(actor.visual.current_attack_action_id() == actor._attack_logic_serial, "%d:moving_body_parent_mismatch" % mid)
				_check(actor._audio_attack_sequence == actor._attack_logic_serial, "%d:moving_audio_parent_mismatch" % mid)
			var before := player.global_position
			await get_tree().physics_frame
			motion_gu += _screen_to_ground(player.global_position - before).length()
			frame += 1
		if phase == "pressure":
			# source176 Task 2 (docs/02 D1/D2): direct-magic postponement now
			# gates melee starts too, so sustained spell pressure legitimately
			# starves new starts. The R4 deadlock guard stays: zero starts is
			# acceptable only while a magic postponement floor is active; a
			# genuine deadlock (no starts, no postponement) still fails.
			_check(
				actor._hc_starts > starts_before
				or actor._movement_cadence.direct_magic_walk_floor_ms > 0,
				"%d:pressure_prevented_all_starts" % mid,
			)
		phases.append({"phase": phase, "frames": frame, "new_starts": actor._hc_starts - starts_before})
	player.set_touch_vector(Vector2.ZERO)
	# Let already accepted deferred results finish on actual physics frames.
	await get_tree().create_timer(0.65).timeout
	actor.set_physics_process(false)
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(not admissions.is_empty(), "%d:no_real_start" % mid)
	_check(active_body_checks > 0, "%d:body_never_active" % mid)
	_check(motion_gu > 0.1, "%d:real_player_motion_missing" % mid)
	_check(pressure_debits > 0 and actual_struck_requests > 0, "%d:pressure_did_not_commit_damage" % mid)
	_check(audit.failures.is_empty(), "%d:moving_or_struck_results=%s" % [mid, audit.failures])
	rows.append({"monster_id": mid, "motion_gu": motion_gu, "pressure_hp_delta": pressure_debits,
		"actual_struck_requests": actual_struck_requests, "active_body_checks": active_body_checks, "phases": phases, "admission_positions": admissions,
		"starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true),
		"events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	await get_tree().physics_frame

func _real_pause_and_late_draw() -> void:
	Observer.reset()
	player.set_touch_vector(Vector2.ZERO)
	player.global_position = _ground_to_screen(CENTER)
	var actor := _spawn(24, CENTER + Vector2(0.98, 0.0))
	actor.process_mode = Node.PROCESS_MODE_PAUSABLE
	actor.visual.set_process(false)
	actor.set_physics_process(true)
	# Let spawn grounding settle, then anchor the player relative to the
	# actor's real position so the first decision grant finds an adjacent
	# target (docs/02 E L-inf box).
	await get_tree().physics_frame
	player.global_position = actor.global_position + (
		_ground_to_screen(CENTER + Vector2(0.98, 0.0)) - _ground_to_screen(CENTER)
	)
	# The legitimate first source interval is paid by native actor ticks.
	var deadline := Time.get_ticks_msec() + 4000
	while actor._hc_starts == 0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	_check(actor._hc_starts > 0, "pause:no_real_admission")
	var clock_before := actor._combat_action_time_s
	var action_before := actor.visual.current_attack_action_id()
	get_tree().paused = true
	for frame in range(12):
		await get_tree().process_frame
	_check(actor._combat_action_time_s == clock_before, "pause:combat_clock_advanced")
	_check(actor.visual.current_attack_action_id() == action_before, "pause:action_changed")
	get_tree().paused = false
	await get_tree().create_timer(0.7).timeout
	_check(actor.visual.current_attack_action_id() == -1, "late_draw:expired_action_visible")
	_check(not actor.visual.attack_frame_phase_reached(), "late_draw:expired_strike_phase_visible")
	actor.visual.set_process(true)
	await get_tree().process_frame
	_check(actor.visual.current_attack_action_id() == -1, "late_draw:draw_restarted_expired_action")
	var audit := Verifier.audit_releases(Observer.admissions, Observer.events, Observer.terminal_events, actor.get_instance_id(), Observer.deliveries, Observer.overflowed)
	_check(audit.failures.is_empty(), "pause:settlement=" + str(audit.failures))
	rows.append({"case": "real_pause_late_draw", "clock_before_pause": clock_before, "action_before_pause": action_before,
		"starts": Observer.admissions.duplicate(true), "deliveries": Observer.deliveries.duplicate(true),
		"events": Observer.events.duplicate(true), "terminals": Observer.terminal_events.duplicate(true), "audit": audit})
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
