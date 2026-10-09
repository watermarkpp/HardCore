extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

## Real production chooser/query lifecycle. Navigation state is arranged at
## its public owner boundary; no clocks, movement, HP or attack resets.
const Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn(24, CENTER + Vector2(1.4, 0.7))
	actor._leave_background_deep_sleep()
	actor.set_physics_process(false)
	actor.target = player
	actor._hc_sync_navigation()
	var far_goal := Positions.station(actor, CENTER, actor._target_combat_radius_gu(player), 2)
	_prepare_goal(actor, far_goal, 2)
	actor._hc_path_anchor = far_goal
	actor._hc_route = PackedVector2Array([CENTER + Vector2(1.4, 1.7), far_goal])
	actor._hc_route_index = 0
	var token := actor._hc_path_token
	var route := actor._hc_route.duplicate()
	var result := actor._hc_crowd_position_goal(player)
	_check(result == far_goal and actor._hc_route == route and actor._hc_path_token == token, "valid same-target detour was replaced or restarted")
	actor._hc_route_index = actor._hc_route.size()
	result = actor._hc_crowd_position_goal(player)
	_check(result.is_finite() and result != far_goal, "consumed route retained a stale distant contact goal")
	_prepare_goal(actor, far_goal, 2)
	actor._hc_route.clear()
	actor._hc_route_index = 0
	actor._hc_path_pending = true
	actor._hc_path_anchor = far_goal
	token = actor._hc_path_token
	result = actor._hc_crowd_position_goal(player)
	_check(result == far_goal and actor._hc_path_pending and actor._hc_path_token == token, "same-target pending detour was cancelled or resubmitted")
	actor._hc_path_pending = false
	_prepare_goal(actor, far_goal, 2)
	actor._hc_flank_anchor = far_goal
	actor._hc_flank_waypoint = actor.spatial_index_position() + Vector2(0, 1)
	result = actor._hc_crowd_position_goal(player)
	_check(result == far_goal and actor._hc_flank_waypoint.is_finite(), "valid contact-goal flank was discarded because it used the target anchor")
	actor._hc_flank_waypoint = actor.spatial_index_position()
	result = actor._hc_crowd_position_goal(player)
	_check(result.is_finite() and result != far_goal, "arrived flank retained a stale distant contact goal")
	_prepare_goal(actor, far_goal, 2)
	actor._hc_path_anchor = far_goal
	actor._hc_route = PackedVector2Array([CENTER + Vector2(1.4, 1.7), far_goal])
	actor._hc_route_index = 0
	var born := _spawn(24, far_goal)
	born._leave_background_deep_sleep()
	born.set_physics_process(false)
	born.target = player
	var frame := Engine.get_physics_frames()
	result = actor._hc_crowd_position_goal(player)
	_check(Engine.get_physics_frames() == frame, "route occupancy case advanced physics")
	_check(result != far_goal, "same-frame body occupancy retained an unreachable contact route")
	_check(not actor._hc_path_pending and actor._hc_route.is_empty(), "changed contact destination retained an obsolete navigation request")
	_prepare_goal(actor, far_goal, 2)
	actor._hc_flank_anchor = far_goal
	actor._hc_flank_waypoint = actor.spatial_index_position() + Vector2(0, 1)
	result = actor._hc_crowd_position_goal(player)
	_check(result != far_goal and not actor._hc_flank_waypoint.is_finite(), "same-frame contact occupancy retained an invalid flank")
	index.unregister(born.spatial_actor_runtime_id)
	born.free()
	var provider := CollisionRevision.new()
	add_child(provider)
	actor.environment_blocker = provider
	actor._hc_sync_navigation()
	_prepare_goal(actor, far_goal, 2)
	actor._hc_flank_anchor = far_goal
	actor._hc_flank_waypoint = actor.spatial_index_position() + Vector2(0, 1)
	provider.revision += 1
	result = actor._hc_crowd_position_goal(player)
	_check(result != far_goal and not actor._hc_flank_waypoint.is_finite(), "changed environment context retained an invalid old flank")
	provider.free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	player.free()
	print("CROWD_LOCAL_NAVIGATION_CONTRACT_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _prepare_goal(actor: EnemyActor, goal: Vector2, slot: int) -> void:
	actor._hc_surround_scope = [MAP_ID, 1, actor._hc_life(actor), player.get_instance_id(), actor._hc_life(player)]
	actor._hc_surround_anchor = CENTER
	actor._hc_surround_goal = goal
	actor._hc_surround_slot = slot
