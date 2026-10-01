extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"
const Neighbor := preload("res://scripts/monster_neighbor_step_policy.gd")
const LAYOUT := [
	{"position": Vector2(15.625, 15.375), "slot": 6, "goal": Vector2(15.625, 15.375)},
	{"position": Vector2(18.49977, 14.51487), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(19.5, 15.52422), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(14.5, 16.12387), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(16.34517, 14.40483), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(15.69622, 16.375), "slot": 2, "goal": Vector2(15.69622, 16.375)},
	{"position": Vector2(17.5, 14.77515), "slot": 7, "goal": Vector2(17.625, 15.375)},
	{"position": Vector2(19.5003, 14.50958), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(15.01593, 13.9841), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(16.5, 13.09817), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(16.625, 15.44622), "slot": 3, "goal": Vector2(16.625, 15.44622)},
	{"position": Vector2(18.26904, 15.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(20.74997, 16.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(20.73432, 15.49921), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(21.75173, 16.49824), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(17.55378, 16.37506), "slot": 0, "goal": Vector2(17.55378, 16.375)},
	{"position": Vector2(17.625, 17.375), "slot": 4, "goal": Vector2(17.625, 17.375)},
	{"position": Vector2(18.64996, 16.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(20.50142, 19.49865), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(18.01119, 13.50001), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(16.625, 17.30378), "slot": 1, "goal": Vector2(16.625, 17.30378)},
	{"position": Vector2(17.49802, 18.49198), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(19.74444, 16.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(21.12349, 17.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(19.49902, 19.5), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(15.625, 17.375), "slot": 5, "goal": Vector2(15.625, 17.375)},
	{"position": Vector2(15.49222, 18.49995), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(18.5, 18.48505), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(16.5, 19.5569), "slot": -1, "goal": Vector2.INF},
	{"position": Vector2(19.50176, 18.49499), "slot": -1, "goal": Vector2.INF}
]
func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var anchor := Vector2(16.625, 16.375)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(anchor)
	add_child(player)
	player.set_physics_process(false)
	var actors: Array[EnemyActor] = []
	for record: Dictionary in LAYOUT:
		var item := _spawn(89, record.position)
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
		item.target = player
		item.set_combat_position(_ground_to_screen(record.position), &"recorded_native_exact_position")
		item._hc_surround_scope = [MAP_ID, 1, item._hc_life(item), player.get_instance_id(), item._hc_life(player)]
		item._hc_surround_anchor = anchor
		item._hc_surround_slot = record.slot
		item._hc_surround_goal = record.goal
		actors.append(item)
	await get_tree().physics_frame
	var actor := actors[11]
	var current := actor.spatial_index_position()
	_check(current.distance_to(LAYOUT[11].position) <= GU.EPSILON_GU, "spawn grounding changed the recorded native geometry")
	var witness := current + Vector2(0.01, 0.01)
	_check(actor._hc_motion_clear(current, witness), "recorded jam has no lawful whole fractional exit leg")
	_check(actor._hc_point_walkable(witness), "recorded fractional exit has no legal terrain footprint")
	actor._hc_sync_navigation()
	actor._hc_known_target_id = player.get_instance_id()
	actor._hc_known_ground = anchor
	actor._hc_observed = true
	actor._hc_owned_movement_call = true
	var rng := actor._rng.state
	var timer := actor._attack_timer
	var starts := actor._hc_starts
	var neighbor := actor._hc_neighbor(current, player, Vector2i(-1, 1))
	var leg := actor._hc_step_override
	_check(neighbor != Vector2i.ZERO and leg.is_finite(), "all cell-centre flanks rejected a proved lawful fractional exit")
	if neighbor != Vector2i.ZERO and leg.is_finite():
		_check(Neighbor.motion_follows_direction(leg - current, Vector2(neighbor)), "fractional exit broke eight-way source heading")
		_check(actor._hc_motion_clear(current, leg), "fractional escape proposal crosses a live body core")
		_check(actor._hc_point_walkable(leg), "fractional escape proposal leaves legal terrain")
	_check(actor.spatial_index_position() == current and actor._rng.state == rng and actor._attack_timer == timer and actor._hc_starts == starts, "navigation candidate spent gameplay state")
	var waiting_goal := actor._hc_crowd_position_goal(player)
	_check(waiting_goal.is_finite(), "unassigned rear still pursues through a nearer station owner")
	if waiting_goal.is_finite():
		_check(maxf(absf(waiting_goal.x - anchor.x), absf(waiting_goal.y - anchor.y)) > maxf(absf(current.x - anchor.x), absf(current.y - anchor.y)), "unassigned rear does not clear the occupied inner row")
	for item in actors:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	player.free()
	print("CROWD_FRACTIONAL_ESCAPE_", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)
