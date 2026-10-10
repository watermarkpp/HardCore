extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Ordinary melee boundary fixture for the production adjacent-step pursuit
## contract. It observes the real actor, admission, physics and spatial index;
## it does not require the retired target-relative crowd chooser.
class DecisionProbe extends EnemyActor:
	var crowd_calls := 0
	func _hc_crowd_position_goal(hit_target: Node2D) -> Vector2:
		crowd_calls += 1
		return super._hc_crowd_position_goal(hit_target)

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	player.max_hp = 1000000
	player.current_hp = player.max_hp
	add_child(player)
	player.set_physics_process(false)

	var contact := _spawn_probe(24, CENTER + Vector2(0.8, 0.0))
	contact.target = player
	contact._leave_background_deep_sleep()
	contact.set_physics_process(false)
	var started := contact._hc_try_start(player)
	_check(started and contact._attack_timer > 0.0, "formal ordinary attack did not start")
	contact.set_physics_process(true)
	var deadline := Time.get_ticks_msec() + 2000
	while contact._pending_attack_time >= 0.0 and Time.get_ticks_msec() < deadline:
		await get_tree().physics_frame
	contact.set_physics_process(false)
	_check(contact._pending_attack_time < 0.0 and contact._attack_timer > 0.0, "attack release did not complete")
	var contact_before := contact.global_position
	player.global_position = _ground_to_screen(CENTER + Vector2(0.12, 0.0))
	contact._hc_tick_melee(1.0 / 60.0, 1.0 / 60.0)
	_check(contact.global_position == contact_before and contact.crowd_calls == 0, "legal cooldown contact moved or invoked crowd chooser")
	# Real continuous player input into the live native body must not make a
	# legally engaged ordinary monster sidestep or replan its station.
	player.set_touch_vector(_ground_to_screen(Vector2.RIGHT).normalized())
	player.set_physics_process(true)
	contact.set_physics_process(true)
	var push_input_ticks := 0
	for tick in range(120):
		await get_tree().physics_frame
		if player.movement_input_active:
			push_input_ticks += 1
		_check(contact.global_position.distance_to(contact_before) <= 0.001, "player push input displaced legal stationary attacker")
	player.set_touch_vector(Vector2.ZERO)
	player.set_physics_process(false)
	contact.set_physics_process(false)
	_check(push_input_ticks > 0 and contact.crowd_calls == 0, "real player push input was not exercised or triggered crowd selection")
	player.global_position = _ground_to_screen(CENTER + Vector2(4.0, 0.0))
	contact.set_physics_process(true)
	for tick in range(240):
		await get_tree().physics_frame
		if contact.global_position != contact_before:
			break
	contact.set_physics_process(false)
	_check(contact.global_position != contact_before, "stationary attacker did not resume pursuit after actual reach exit")
	player.global_position = _ground_to_screen(CENTER + Vector2(0.12, 0.0))
	index.unregister(contact.spatial_actor_runtime_id)
	contact.free()

	var pursuer := _spawn_probe(24, CENTER + Vector2(4.0, 0.0))
	pursuer.target = player
	pursuer.set_physics_process(true)
	var start_ground := pursuer.spatial_index_position()
	var max_component := 0.0
	var moved := false
	for tick in range(240):
		if tick == 12: player.global_position = _ground_to_screen(CENTER + Vector2(0.2, 0.05))
		await get_tree().physics_frame
		var current := pursuer.spatial_index_position()
		var delta := current - start_ground
		if delta.length_squared() > GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU: moved = true
		if pursuer._movement_step_active:
			var leg := pursuer._movement_step_target_ground_gu - current
			max_component = maxf(max_component, maxf(absf(leg.x), absf(leg.y)))
		start_ground = current
	pursuer.set_physics_process(false)
	_check(moved, "distant ordinary actor did not begin natural pursuit")
	_check(max_component <= 1.0001, "ordinary pursuit short leg exceeded one ground component: %.4f" % max_component)
	_check(pursuer.crowd_calls == 0, "ordinary pursuit invoked retired crowd chooser")

	var blocked := _spawn_probe(24, CENTER + Vector2(4.0, 2.0))
	blocked.target = player
	blocked._hc_owned_movement_call = true
	var began := blocked._begin_autonomous_step_without_cadence(Vector2.LEFT, 1.0, false, &"pursuit", player)
	_check(began and blocked._movement_step_active, "real blocked-step fixture did not commit")
	var current_ground := blocked.spatial_index_position()
	var direction := (blocked._movement_step_target_ground_gu - current_ground).normalized()
	var predicted := current_ground + direction * blocked.move_speed_gu_per_sec / 60.0
	var body := _spawn(24, predicted)
	body.target = player
	body.set_physics_process(false)
	var blocked_before := blocked.global_position
	blocked._advance_autonomous_step(1.0 / 60.0, 1.0 / 60.0)
	_check(blocked.global_position == blocked_before and not blocked._movement_step_active, "real body collision let committed step pass through")
	index.unregister(body.spatial_actor_runtime_id)
	body.free()

	player.global_position = _ground_to_screen(CENTER + Vector2(8.0, 0.0))
	var before_reengage := pursuer.global_position
	pursuer.set_physics_process(true)
	for tick in range(240):
		await get_tree().physics_frame
		if pursuer.global_position != before_reengage: break
	pursuer.set_physics_process(false)
	_check(pursuer.global_position != before_reengage or pursuer._movement_step_active, "out-of-range target did not resume pursuit")
	_check(pursuer.crowd_calls == 0, "ordinary reengagement invoked retired crowd chooser")

	index.unregister(blocked.spatial_actor_runtime_id)
	blocked.free()
	index.unregister(pursuer.spatial_actor_runtime_id)
	pursuer.free()
	player.free()
	print("CROWD_DECISION_BOUNDARY_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _spawn_probe(mid: int, position: Vector2) -> DecisionProbe:
	serial += 1
	var actor := DecisionProbe.new()
	actor.setup(GameData.get_monster_by_id(mid), player, false)
	actor.set_meta("safe_zones", [])
	actor.set_meta("zone_generation", 1)
	actor.configure_runtime_map_projection(MAP_ID, _ground_to_screen, _screen_to_ground)
	actor.configure_terrain_navigation_context(Terrain.build(MAP_ID))
	actor.configure_spatial_index(index, serial)
	actor.set_combat_position(_ground_to_screen(position), &"decision_boundary_probe")
	actor.set_meta("spawn_position", actor.global_position)
	add_child(actor)
	actor.set_physics_process(false)
	index.register(serial, MAP_ID, position, actor.combat_radius_gu, serial, actor)
	actor.set_combat_position(_ground_to_screen(position), &"decision_boundary_final_position")
	return actor
