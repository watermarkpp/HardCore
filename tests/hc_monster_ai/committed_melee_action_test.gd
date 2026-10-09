extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real ordinary ID24 admission, the existing exact admission callback seam,
## and real physics/body-action clock. No timing/stat/pending writes. Current
## ordinary IDs settle immediately; the callback exercises movement/lifecycle
## between the accepted geometry and that same formal HP delivery.
func _run() -> void:
	if OS.get_environment("HARDCORE_FIRST_ATTACK_DIAGNOSTIC") == "ranged":
		await _run_ranged_diagnostic()
		return
	if OS.get_environment("HARDCORE_FIRST_ATTACK_DIAGNOSTIC") == "1":
		await _run_first_attack_diagnostic()
		return
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	Observer.recording_enabled = true
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	await _committed_case()
	_range_case()
	for change: String in ["combat_epoch", "generation"]:
		_lifecycle_case(change)
	Observer.recording_enabled = false
	FileAccess.open("res://outputs/test_logs/committed_melee_action.json", FileAccess.WRITE).store_string(JSON.stringify({"schema": "committed_melee_action_v2", "rows": rows, "failures": failures}, "  "))
	player.free()
	print("COMMITTED_MELEE_ACTION_PASS" if failures.is_empty() else "COMMITTED_MELEE_ACTION_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _committed_case() -> void:
	Observer.reset()
	var actor := _spawn(24, CENTER + Vector2(0.98, 0.98))
	var start := actor.global_position
	var hp_before := player.current_hp
	var frozen: Array = [{}]
	var wall: Array = [null]
	actor.test_attack_admission_hook = func(record: Dictionary) -> void:
		frozen[0] = record
		player.global_position = _ground_to_screen(CENTER + Vector2(5, 5))
		var body := StaticBody2D.new()
		body.collision_layer = WorldSpatialRules.WORLD_MASK
		body.collision_mask = 0
		body.position = _ground_to_screen(CENTER + Vector2(2, 2))
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 4.0
		shape.shape = circle
		body.add_child(shape)
		add_child(body)
		wall[0] = body
	var accepted := actor._hc_try_start(player)
	actor.test_attack_admission_hook = Callable()
	_check(accepted and actor._source176_ordinary_melee(), "ordinary real admission missing")
	_check(bool(frozen[0].get("ordinary_committed", false)) and frozen[0].has("admission_footprint"), "frozen admission missing")
	_check(player.current_hp < hp_before and Observer.deliveries.size() == 1 and Observer.events.size() == 1, "accepted hit lost after target moved")
	var hp_after := player.current_hp
	actor._hc_settle(actor._last_hc_release_record)
	_check(player.current_hp == hp_after and Observer.events.size() == 1, "duplicate committed settlement")
	actor.set_physics_process(true)
	var held_frames := 0
	for tick in range(180):
		await get_tree().physics_frame
		if not actor._attack_action_active:
			break
		held_frames += 1
		_check(actor.global_position == start, "pursuit resumed before action finished")
		_check(actor._last_hc_release_record.get("parent_action_id") == frozen[0].get("parent_action_id"), "parent action changed during animation")
	_check(held_frames > 0 and not actor._attack_action_active, "full action window not observed")
	wall[0].queue_free()
	var resumed := false
	for tick in range(240):
		await get_tree().physics_frame
		if actor.global_position.distance_to(start) > 0.01:
			resumed = true
			break
	actor.set_physics_process(false)
	_check(resumed, "pursuit did not resume after action finished")
	rows.append({"case": "ordinary_committed", "accepted": accepted, "held_frames": held_frames, "resumed": resumed, "hp_before": hp_before, "hp_after": hp_after, "admission": frozen[0], "events": Observer.events.duplicate(true)})
	_cleanup(actor)

func _range_case() -> void:
	Observer.reset()
	player.global_position = _ground_to_screen(CENTER)
	var actor := _spawn(24, CENTER + Vector2(1.2, 1.2))
	var hp_before := player.current_hp
	_check(not actor._hc_try_start(player) and actor._hc_last_reason == "OUT_OF_RANGE", "initial geometry gate bypassed")
	_check(actor._hc_starts == 0 and player.current_hp == hp_before, "rejected start consumed HP/action")
	rows.append({"case": "range", "reason": actor._hc_last_reason})
	_cleanup(actor)

func _lifecycle_case(change: String) -> void:
	Observer.reset()
	player.global_position = _ground_to_screen(CENTER)
	var actor := _spawn(24, CENTER + Vector2(0.98, 0.98))
	var hp_before := player.current_hp
	actor.test_attack_admission_hook = func(_record: Dictionary) -> void:
		if change == "combat_epoch":
			player.begin_combat_transition("committed-melee")
		else:
			player.set_meta("zone_generation", 2)
	_check(actor._hc_try_start(player), change + ":real admission missing")
	actor.test_attack_admission_hook = Callable()
	_check(player.current_hp == hp_before and Observer.events.is_empty() and Observer.terminal_events.size() == 1, change + ":stale delivery damaged")
	rows.append({"case": change, "hp_unchanged": player.current_hp == hp_before, "terminals": Observer.terminal_events.duplicate(true)})
	if change == "combat_epoch":
		player.finish_combat_transition("committed-melee")
	else:
		player.set_meta("zone_generation", 1)
	_cleanup(actor)

func _cleanup(actor: EnemyActor) -> void:
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()

## Natural owner clocks and real actor physics: no admission calls, cadence
## writes, cooldown writes or action-clock resets. This mode diagnoses the
## user's short in-range crossing separately from the committed-hit suite.
func _run_first_attack_diagnostic() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	for mid: int in [24, 110, 112, 116, 76, 143, 160, 238, 239]:
		await _first_attack_case(mid, false)
	for mid: int in [110, 76, 238, 239]:
		await _first_attack_case(mid, true)
	for posture: String in ["idle", "walk", "attack"]:
		await _natural_struck_case(posture)
	FileAccess.open("res://outputs/test_logs/first_attack_latency.json", FileAccess.WRITE).store_string(JSON.stringify({"schema": "natural_first_attack_latency_v1", "rows": rows, "failures": failures}, "  "))
	player.free()
	print("FIRST_ATTACK_LATENCY_PASS" if failures.is_empty() else "FIRST_ATTACK_LATENCY_FAIL " + str(failures))
	if failures.is_empty():
		print("COMMITTED_MELEE_ACTION_PASS")
	get_tree().quit(0 if failures.is_empty() else 1)

func _first_attack_case(mid: int, transient: bool) -> void:
	player.global_position = _ground_to_screen(CENTER + Vector2(3.0, 3.0))
	var actor := _spawn(mid, CENTER)
	actor.target = player
	actor._leave_background_deep_sleep()
	# The player enters before the next production callback. Stable diagonal
	# geometry stays outside the body contact band and inside 1GU box reach.
	player.global_position = _ground_to_screen(actor.spatial_index_position() + Vector2(0.98, 0.98))
	var start_tick := Engine.get_physics_frames()
	var start_game_time := actor._combat_action_time_s
	var start_hp := player.current_hp
	var start_cooldown := actor._attack_timer
	var access := actor._hc_access(player)
	var initially_dormant := actor.dormant
	var trace: Array = []
	actor.set_physics_process(true)
	var first_attack_ticks := -1
	for n in range(130):
		await get_tree().physics_frame
		await get_tree().process_frame
		trace.append({"ticks": Engine.get_physics_frames() - start_tick, "game_time_s": actor._combat_action_time_s,
			"reason": actor._hc_last_reason, "attack_timer_s": actor._attack_timer,
			"source_granted": actor._source176_decision_granted, "starts": actor._hc_starts,
			"movement_active": actor._movement_step_active})
		if actor._hc_starts > 0:
			# Render observation can follow multiple physics callbacks; retain
			# the producer's actual admission tick, not that observer's tick.
			first_attack_ticks = actor._hc_last_start_tick - start_tick
			break
		if transient:
			player.global_position = _ground_to_screen(CENTER + Vector2(3.0, 3.0))
			break
	var held_frames := 0
	if transient and actor._hc_starts > 0:
		var committed_position := actor.global_position
		player.global_position = _ground_to_screen(CENTER + Vector2(6.0, 6.0))
		while actor._attack_action_active and held_frames < 120:
			await get_tree().physics_frame
			await get_tree().process_frame
			if actor._attack_action_active:
				_check(actor.global_position == committed_position, "committed crossing attack moved before animation finished")
				_check(actor._hc_last_reason == "ATTACK_POSE_COMMIT", "committed crossing attack entered next AI plan mid=%d" % mid)
				held_frames += 1
		_check(held_frames > 0 and not actor._attack_action_active, "crossing attack body did not finish")
		_check(actor._hc_settlements == 1, "crossing attack not settled exactly once")
	actor.set_physics_process(false)
	_check(access == "CLEAR" or (initially_dormant and access == "ACTION_LOCKED"), "first attack fixture not CLEAR or authored wake mid=%d" % mid)
	_check(first_attack_ticks >= 0 and first_attack_ticks <= 1, "legal first attack deferred mid=%d transient=%s ticks=%d" % [mid, transient, first_attack_ticks])
	rows.append({"monster_id": mid, "transient_one_callback": transient, "initial_access": access,
		"delivery_kind": str(actor.attack_delivery_rule.get("kind", "")), "is_boss": actor.is_boss,
		"initial_attack_timer_s": start_cooldown, "initially_dormant": initially_dormant, "start_game_time_s": start_game_time, "held_frames": held_frames,
		"walk_interval_ms": actor._movement_cadence.walk_interval_ms,
		"walk_wait_ms": actor._movement_cadence.walk_wait_ms, "first_attack_ticks": first_attack_ticks,
		"hp_before": start_hp, "hp_after": player.current_hp, "trace": trace})
	_cleanup(actor)

func _run_ranged_diagnostic() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	add_child(player)
	player.set_physics_process(false)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	for mid: int in [220, 222, 224]:
		# Select the successful branch with a reproducible real RNG seed, as in
		# the existing target-magic fixture. Do not disable evasion or alter stats.
		var reference := RandomNumberGenerator.new()
		var successful_seed := 1
		while true:
			reference.seed = successful_seed
			if reference.randi_range(0, 9) == 9:
				break
			successful_seed += 1
		player._rng.seed = successful_seed
		player.global_position = _ground_to_screen(CENTER + Vector2(2.0, 0.0))
		var actor := _spawn(mid, CENTER)
		actor.target = player
		actor._leave_background_deep_sleep()
		var previous_hp := player.current_hp
		var admission_loss: Array = []
		actor.target_magic_requested.connect(func(_descriptor: Dictionary) -> void:
			admission_loss.append(previous_hp - player.current_hp))
		actor.set_physics_process(true)
		await get_tree().physics_frame
		await get_tree().process_frame
		actor.set_physics_process(false)
		_check(not admission_loss.is_empty() and int(admission_loss[0]) > 0, "locked magic did not settle at activation mid=%d" % mid)
		_check(actor._pending_attack_time < 0.0, "locked magic retained artificial damage delay mid=%d" % mid)
		rows.append({"monster_id": mid, "kind": str(actor.attack_delivery_rule.get("kind", "")), "admission_hp_loss": admission_loss,
			"pending_seconds": actor._pending_attack_time, "parent_action_id": actor._attack_logic_serial})
		_cleanup(actor)
	# A real projectile is the explicit exception: dispatch immediately,
	# keep flight time, and permit a moving victim to leave the frozen aim.
	player.global_position = _ground_to_screen(CENTER + Vector2(2.0, 0.0))
	var archer := _spawn(150, CENTER)
	archer.target = player
	archer._leave_background_deep_sleep()
	var hp_before_arrow := player.current_hp
	var arrow_tick := Engine.get_physics_frames()
	archer.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().process_frame
	_check(archer._attack_logic_serial == 1 and archer._last_body_action_commit_tick - arrow_tick == 1, "projectile dispatch waited extra decision")
	_check(player.current_hp == hp_before_arrow, "projectile flight was replaced by immediate HP")
	var archer_position := archer.global_position
	player.global_position = _ground_to_screen(CENTER + Vector2(8.0, 8.0))
	for n in range(100):
		await get_tree().physics_frame
		await get_tree().process_frame
		if archer._attack_action_active:
			_check(archer.global_position == archer_position and archer._hc_last_reason == "ATTACK_POSE_COMMIT", "projectile body planned before cast completed")
	archer.set_physics_process(false)
	_check(player.current_hp == hp_before_arrow, "flying projectile could not be dodged by leaving frozen aim")
	rows.append({"monster_id": 150, "kind": str(archer.attack_delivery_rule.get("kind", "")), "hp_before": hp_before_arrow,
		"hp_after_dodge": player.current_hp, "parent_action_id": archer._attack_logic_serial})
	_cleanup(archer)
	for mid: int in [124, 180, 195]:
		player.global_position = _ground_to_screen(CENTER + Vector2(2.0, 0.0))
		var area_actor := _spawn(mid, CENTER)
		area_actor.target = player
		area_actor._leave_background_deep_sleep()
		area_actor.set_physics_process(true)
		await get_tree().physics_frame
		await get_tree().process_frame
		_check(area_actor._attack_action_active, "area activation did not start body mid=%d" % mid)
		var settle_hp := player.current_hp
		player.global_position = _ground_to_screen(CENTER + Vector2(8.0, 8.0))
		for n in range(120):
			await get_tree().physics_frame
			await get_tree().process_frame
			if not area_actor._attack_action_active:
				break
		area_actor.set_physics_process(false)
		_check(player.current_hp == settle_hp, "area body repeated committed HP mid=%d" % mid)
		_check(area_actor._area_magic_warning <= 0.0 and area_actor._area_attack_warning <= 0.0 and area_actor._boss_warning <= 0.0,
			"area presentation clock paused during committed body mid=%d" % mid)
		rows.append({"monster_id": mid, "kind": str(area_actor.attack_delivery_rule.get("kind", "")), "area_magic_warning": area_actor._area_magic_warning,
			"area_attack_warning": area_actor._area_attack_warning, "boss_warning": area_actor._boss_warning})
		_cleanup(area_actor)
	FileAccess.open("res://outputs/test_logs/first_ranged_latency.json", FileAccess.WRITE).store_string(JSON.stringify({"rows": rows, "failures": failures}, "  "))
	player.free()
	print("COMMITTED_MELEE_ACTION_PASS" if failures.is_empty() else "FIRST_RANGED_LATENCY_FAIL " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)

func _natural_struck_case(posture: String) -> void:
	player.global_position = _ground_to_screen(CENTER + Vector2(3.0, 3.0))
	var actor := _spawn(110, CENTER)
	actor.target = player
	actor._leave_background_deep_sleep()
	if posture == "attack":
		player.global_position = _ground_to_screen(CENTER + Vector2(0.98, 0.98))
	if posture != "idle":
		actor.set_physics_process(true)
	for n in range(130):
		await get_tree().physics_frame
		await get_tree().process_frame
		var posture_ready := posture == "idle" or (actor._movement_step_active if posture == "walk" else actor._attack_action_active)
		if posture_ready and actor.visual.active_resources.has("hit"):
			break
	var before_hp := actor.current_hp
	var was_attack_active := actor._attack_action_active
	var was_step_active := actor._movement_step_active
	var paused_time_before := actor._struck_paused_time_s
	# Use the real positive resolved-damage entry. No synthetic textures or
	# manual visual starts: all animation advancement is the native process.
	actor.take_damage(1, player, {"damage_channel": "physical"})
	# Hit duration is owned by physics, including the initially idle actor.
	actor.set_physics_process(true)
	var pending_after_hit := actor.visual.pending_struck_count()
	_check(actor.current_hp == before_hp - 1, "struck HP commit missing posture=" + posture)
	if posture == "attack":
		_check(was_attack_active and actor._attack_action_active, "struck interrupted committed attack")
		player.global_position = _ground_to_screen(CENTER + Vector2(3.0, 3.0))
	if posture == "walk":
		_check(was_step_active and actor._movement_step_active, "struck cancelled real pursuit step")
	var hit_frames: Dictionary = {}
	var selected_real_hit_texture := false
	var trace: Array = []
	# A moving hit starts in place; an attacking hit follows the committed
	# action. Keep the authored observation window and real frame residency.
	var step_seconds := actor.spatial_index_position().distance_to(actor._movement_step_target_ground_gu) / actor.move_speed_gu_per_sec if actor._movement_step_active else 0.0
	var hit_seconds := float(actor.visual._canonical_struck_frame_count * preload("res://scripts/monster_struck_policy.gd").struck_frame_ms(actor.level)) / 1000.0
	var observation_ticks := int(ceil((step_seconds + actor._attack_action_duration_s + hit_seconds) * float(Engine.physics_ticks_per_second))) + 4
	for n in range(observation_ticks):
		await get_tree().physics_frame
		await get_tree().process_frame
		trace.append({"state": actor.visual.current_state, "frame": actor.visual.current_frame,
			"render_delta": actor.visual.get_process_delta_time(), "hit_remaining": actor.visual._hit_remaining,
			"hit_duration": actor.visual._hc_m30_hit_duration, "attack_remaining": actor.visual._attack_remaining,
			"starts": actor._hc_starts, "pending_struck": actor.visual.pending_struck_count()})
		if was_attack_active and actor._attack_action_active:
			_check(not actor.visual.is_struck_action_active(), "hit started before committed attack finished")
		if actor.visual.current_state == "hit":
			hit_frames[actor.visual.current_frame] = true
			selected_real_hit_texture = actor.visual.sprite.texture == actor.visual.active_resources.get("hit")
		if not hit_frames.is_empty() and actor.visual._hit_remaining <= 0.0 and actor.visual.pending_struck_count() == 0:
			break
	actor.set_physics_process(false)
	_check(hit_frames.size() >= 2 and selected_real_hit_texture, "real hit frames not presented posture=" + posture)
	var actual_pause_seconds := actor._struck_paused_time_s - paused_time_before
	_check(is_equal_approx(actual_pause_seconds, hit_seconds), "actual struck pause differs from authored animation posture=" + posture)
	rows.append({"case": "natural_struck", "posture": posture, "hp_before": before_hp, "hp_after": actor.current_hp,
		"authored_hit_seconds": hit_seconds, "actual_paused_seconds": actual_pause_seconds,
		"observation_ticks": observation_ticks, "remaining_step_seconds": step_seconds,
		"queued_after_hit": pending_after_hit, "real_hit_texture_selected": selected_real_hit_texture,
		"hit_frames": hit_frames.keys(), "trace": trace, "hit_texture_path": actor.visual.active_resources.get("hit").resource_path if actor.visual.active_resources.has("hit") else "MISSING"})
	_cleanup(actor)
