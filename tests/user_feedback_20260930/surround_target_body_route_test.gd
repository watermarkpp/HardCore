extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"
const Step := preload("res://scripts/monster_source176/source_step_plan.gd")
const HC := preload("res://scripts/monster_ai_package/policy.gd")
const Positions := preload("res://scripts/monster_crowd_attack_position_policy.gd")
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var anchor := Vector2(40.5, 13.5)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(anchor)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn(19, Vector2(40.0035, 12.94157))
	actor._leave_background_deep_sleep()
	actor.set_physics_process(false)
	actor.target = player
	actor.set_combat_position(_ground_to_screen(Vector2(40.0035, 12.94157)), &"recorded_opposite_axis_position")
	actor._hc_sync_navigation()
	actor._hc_known_target_id = player.get_instance_id()
	actor._hc_known_ground = anchor
	actor._hc_observed = true
	actor._hc_owned_movement_call = true
	var goal := Positions.station(actor, anchor, actor._target_combat_radius_gu(player), 0)
	var current := actor.spatial_index_position()
	var crossing := Step.next_leg(current, goal, 1.0, GU.EPSILON_GU)
	_check(HC.core_crossed(current, crossing, anchor, actor.combat_radius_gu, actor._target_combat_radius_gu(player)), "recorded axis route does not cross the player's real body envelope")
	actor._hc_surround_goal = Vector2.INF
	_check(actor._hc_motion_clear(current, crossing), "ordinary approach contract was changed outside station alignment")
	actor._hc_surround_goal = goal
	var destinations := actor._hc_goal_points(goal)
	_check(destinations.size() == 1 and destinations.values()[0].distance_to(goal) <= GU.EPSILON_GU, "station navigation sampled an attack box around its destination")
	_check(not actor._hc_motion_clear(current, crossing), "station alignment accepted a leg through the player body")
	var neighbor := actor._hc_neighbor(current, player, Vector2i(1, 1))
	var leg := actor._hc_step_override
	_check(neighbor != Vector2i.ZERO and leg.is_finite(), "opposite-axis body had no legal detour")
	if neighbor != Vector2i.ZERO and leg.is_finite():
		_check(not HC.core_crossed(current, leg, anchor, actor.combat_radius_gu, actor._target_combat_radius_gu(player)), "opposite-axis detour still crossed the player")
	# The upper detour just outside the approach contact distance has a
	# lawful horizontal leg. Commit preserves navigation's exact endpoint.
	var detour_origin := Vector2(40.5751, 12.25)
	var detour_end := Vector2(41.5, 12.25)
	actor.set_combat_position(_ground_to_screen(detour_origin), &"recorded_tangential_detour")
	actor._hc_flank_anchor = goal
	actor._hc_flank_waypoint = detour_end
	_check(actor._source176_ordinary_melee(), "commit fixture is not source ordinary melee")
	_check(actor._hc_motion_clear(detour_origin, detour_end), "recorded tangential leg is not clear")
	var committed := actor._begin_autonomous_step_without_cadence(detour_end - detour_origin, 1.0, false, &"pursuit", player)
	_check(committed, "approved tangential leg did not commit")
	if committed:
		_check(actor._movement_step_target_ground_gu.distance_to(detour_end) <= GU.EPSILON_GU, "contact cap shortened an approved tangential station detour: " + str(actor._movement_step_target_ground_gu))
	actor._clear_autonomous_step_state()
	var peer := _spawn(19, Vector2(39.71766, 13.5))
	peer._leave_background_deep_sleep()
	peer.set_physics_process(false)
	peer.target = player
	var outer_origin := Vector2(39.0, 13.0)
	var outer_flank := Vector2(38.5, 12.5)
	actor.set_combat_position(_ground_to_screen(outer_origin), &"owned_outer_detour")
	actor._hc_surround_anchor = anchor
	actor._hc_surround_scope = [MAP_ID, 1, actor._hc_life(actor), player.get_instance_id(), actor._hc_life(player)]
	actor._hc_surround_slot = 0
	actor._hc_surround_goal = goal
	actor._hc_flank_anchor = goal
	actor._hc_flank_waypoint = outer_flank
	actor._hc_pursuit_session = true
	committed = actor._begin_autonomous_step_without_cadence(outer_flank - outer_origin, 1.0, false, &"pursuit", player)
	_check(committed, "lawful outward detour did not start")
	if committed:
		var endpoint := actor._movement_step_target_ground_gu
		actor._hc_tick_melee(0.0, 0.0)
		_check(actor._hc_surround_goal == goal and actor._hc_flank_waypoint == outer_flank, "valid outward detour changed its contact destination before completing the flank")
		_check(actor._movement_step_active and actor._movement_step_target_ground_gu == endpoint, "crowd selection cancelled a lawful committed outward segment")
		# A consumed waypoint provides no persistent ownership. The occupied
		# west axis still leaves this literal northwest corner nearest.
		actor._hc_flank_waypoint = actor.spatial_index_position()
		actor._hc_crowd_position_goal(player)
		_check(actor._hc_surround_slot == 6 and actor._hc_surround_goal.distance_to(anchor + Vector2(-1, -1)) <= GU.EPSILON_GU, "consumed outer detour retained a distant claim instead of the nearest free corner")
	index.unregister(peer.spatial_actor_runtime_id)
	peer.free()
	index.unregister(actor.spatial_actor_runtime_id)
	actor.free()
	# Native mixed-world failure: a large corner body prevents the direct
	# eastern route. Its apparently clear first prefix must not lead to a
	# held waypoint inside the player's occupied body.
	var frog := _spawn(19, Vector2(40.57475, 12.5))
	var corner_body := _spawn(238, Vector2(41.53104, 12.46896))
	for item in [frog, corner_body]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
		item.target = player
	frog.set_combat_position(_ground_to_screen(Vector2(40.57475, 12.5)), &"recorded_mixed_frog")
	corner_body.set_combat_position(_ground_to_screen(Vector2(41.53104, 12.46896)), &"recorded_mixed_corner")
	frog._hc_sync_navigation()
	frog._hc_known_target_id = player.get_instance_id()
	frog._hc_known_ground = anchor
	frog._hc_observed = true
	frog._hc_surround_goal = goal
	current = frog.spatial_index_position()
	neighbor = frog._hc_neighbor(current, player, Vector2i(1, 1))
	_check(neighbor != Vector2i.ZERO and frog._hc_flank_waypoint.is_finite(), "mixed corner obstruction has no legal alternate route")
	if frog._hc_flank_waypoint.is_finite():
		var radius := frog.combat_radius_gu + frog._target_combat_radius_gu(player)
		_check(frog._hc_flank_waypoint.distance_squared_to(anchor) >= radius * radius, "mixed route selected an unreachable waypoint inside the player")
	frog._hc_surround_anchor = anchor
	frog._hc_surround_scope = [MAP_ID, 1, frog._hc_life(frog), player.get_instance_id(), frog._hc_life(player)]
	frog._hc_surround_slot = 0
	var held_flank := frog._hc_flank_waypoint
	var nearby_goal := frog._hc_crowd_position_goal(player)
	_check(nearby_goal == goal and frog._hc_flank_waypoint == held_flank, "mixed-body detour restarted before its legal flank destination was reached")
	frog._hc_flank_waypoint = frog.spatial_index_position()
	nearby_goal = frog._hc_crowd_position_goal(player)
	_check(frog._hc_surround_slot == 3 and nearby_goal.distance_to(Positions.station(frog, anchor, frog._target_combat_radius_gu(player), 3)) <= GU.EPSILON_GU, "consumed mixed-body detour retained a distant station while its nearest actual entrance was free")
	for item in [frog, corner_body]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("SURROUND_TARGET_BODY_ROUTE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
