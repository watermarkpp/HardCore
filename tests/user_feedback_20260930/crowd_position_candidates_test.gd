extends "res://tests/hc_monster_combat_r4/d3_boundary_runtime_test.gd"

const PositionPolicy := preload("res://scripts/monster_crowd_attack_position_policy.gd")

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	player = PlayerCharacter.new()
	player.set_meta("runtime_map_id", MAP_ID)
	player.set_meta("zone_generation", 1)
	player.global_position = _ground_to_screen(CENTER)
	add_child(player)
	player.set_physics_process(false)
	var actor := _spawn(89, Vector2(17.4929, 16.29991))
	# The corner body has yielded enough of the axial entrance; the fixture
	# does not declare a station free when the neighbor's body covers it.
	var peer := _spawn(89, Vector2(17.5072, 17.5072))
	for item in [actor, peer]:
		item._leave_background_deep_sleep()
		item.set_physics_process(false)
	var before := actor.global_position
	var rng := actor._rng.state
	var timer := actor._attack_timer
	var parent := actor._attack_logic_serial
	var goal := actor._hc_crowd_position_goal(player)
	_check(goal.is_finite(), "formal large body was excluded from crowded station candidates")
	_check(goal.x > CENTER.x and goal.y == CENTER.y and goal.x < CENTER.x + 1.0, "skewed east front did not choose an inward axial station")
	_check(actor.global_position == before and actor._rng.state == rng and actor._attack_timer == timer and actor._attack_logic_serial == parent, "candidate selection changed movement or attack state")
	actor.set_combat_position(_ground_to_screen(CENTER + Vector2(3, -2)), &"crowd_detour_fixture_origin")
	var detour_goal := actor._hc_crowd_position_goal(player)
	_check(detour_goal == goal, "a lawful outer detour lost the existing vacant station target")
	# A corner waiting just outside reach is already physically at its
	# navigation station; another rear actor must use a different entrance.
	var waiting := CENTER + Vector2(1, -1) * (1.0 + 2.0 * PositionPolicy.margin_gu(peer) + GU.EPSILON_GU)
	peer.set_combat_position(_ground_to_screen(waiting), &"corner_wait_fixture")
	peer.target = player
	peer._hc_surround_anchor = CENTER
	peer._hc_surround_slot = 7
	peer._hc_surround_goal = waiting
	_check(peer._hc_access(player) == "OUT_OF_RANGE", "waiting fixture is not outside formal reach")
	_check(not PositionPolicy.available(actor, player, waiting, [peer]), "arrived corner wait station was offered to another rear actor")
	peer._hc_surround_goal = CENTER + Vector2(-1, -1) * (waiting.x - CENTER.x)
	_check(PositionPolicy.available(actor, player, waiting, [peer]), "a transient rear overlap was treated as a settled front station")
	for item in [actor, peer]:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
	await _transient_front_destination_case()
	await _near_station_contender_case()
	player.free()
	print("CROWD_POSITION_CANDIDATES_", "PASS" if failures.is_empty() else "FAIL", " goal=", goal, " ", failures)
	get_tree().quit(0 if failures.is_empty() else 1)

func _transient_front_destination_case() -> void:
	await get_tree().physics_frame
	var probe := _spawn(89, CENTER + Vector2(3, 0))
	var axis := PositionPolicy.axis_distance(probe, probe._target_combat_radius_gu(player))
	var waiting := 1.0 + 2.0 * PositionPolicy.margin_gu(probe) + GU.EPSILON_GU
	index.unregister(probe.spatial_actor_runtime_id)
	probe.free()
	var actors: Array[EnemyActor] = []
	for slot: int in [0, 1, 2, 3, 5, 6, 7]:
		var offset: Vector2 = PositionPolicy.DIRECTIONS[slot] * (axis if slot < 4 else 1.0)
		if slot == 0: offset = Vector2(0.874, 0.1503)
		if slot == 7: offset = Vector2(waiting, -waiting)
		var item := _spawn(89, CENTER + offset)
		item._leave_background_deep_sleep()
		item.target = player
		item.set_combat_position(_ground_to_screen(CENTER + offset), &"yield_fixture_native_trace_position")
		item._hc_surround_anchor = CENTER
		item._hc_surround_slot = slot
		item._hc_surround_goal = CENTER + offset if slot != 0 else CENTER + Vector2(axis, 0)
		actors.append(item)
	var rear := _spawn(89, CENTER + Vector2(1.875, 0.125))
	rear._leave_background_deep_sleep()
	rear.target = player
	actors.append(rear)
	var goal := rear._hc_crowd_position_goal(player)
	_check(rear._hc_surround_slot == 4 and goal.is_finite(), "a front aligning to east permanently denied the empty southeast destination")
	var born := _spawn(89, CENTER + Vector2(-1.8, 1.8))
	born._leave_background_deep_sleep()
	born.target = player
	actors.append(born)
	born._hc_crowd_position_goal(player)
	_check(player.get_meta("hc_crowd_position_candidates", {}).get("nodes", []).has(born), "same-frame newly registered crowd body was missing from station candidates")
	for item in actors:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()

func _near_station_contender_case() -> void:
	# Native repeat 3: seven front stations are occupied. A nearer rear body
	# covers NE while a farther body still owns that goal. Neither can move:
	# the farther body blocks selection and the nearer one blocks locomotion.
	await get_tree().physics_frame
	var anchor := Vector2(16.625, 16.375)
	player.global_position = _ground_to_screen(anchor)
	var positions := [Vector2(15.625, 15.375), Vector2(15.69622, 16.375),
		Vector2(16.625, 15.44622), Vector2(17.55378, 16.375),
		Vector2(17.625, 17.375), Vector2(16.625, 17.30378), Vector2(15.625, 17.375)]
	var slots := [6, 2, 3, 0, 4, 1, 5]
	var actors: Array[EnemyActor] = []
	for i in positions.size():
		var item := _spawn(89, positions[i])
		item._leave_background_deep_sleep()
		item.target = player
		item.set_combat_position(_ground_to_screen(positions[i]), &"native_station_contender_front")
		item._hc_surround_anchor = anchor
		item._hc_surround_slot = slots[i]
		item._hc_surround_goal = positions[i]
		actors.append(item)
	var farther := _spawn(89, Vector2(17.46169, 14.5))
	var nearer := _spawn(89, Vector2(18.04179, 15.5))
	for item in [farther, nearer]:
		item._leave_background_deep_sleep()
		item.target = player
		actors.append(item)
	farther._hc_crowd_position_goal(player)
	farther._hc_surround_slot = 7
	farther._hc_surround_goal = anchor + Vector2(1, -1)
	var goal := nearer._hc_crowd_position_goal(player)
	_check(nearer._hc_surround_slot == 7 and goal == anchor + Vector2(1, -1), "farther transient goal trapped the body already covering the only vacant station")
	farther._hc_crowd_position_goal(player)
	_check(farther._hc_surround_slot == -1, "farther body retained a station physically covered by a nearer contender")
	for item in actors:
		index.unregister(item.spatial_actor_runtime_id)
		item.free()
