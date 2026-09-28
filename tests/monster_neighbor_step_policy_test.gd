extends Node

const NeighborPolicy := preload("res://scripts/monster_neighbor_step_policy.gd")

var _checks := 0


func _ready() -> void:
	_test_quantization_and_centers()
	_test_eight_unique_neighbors()
	_test_direction_and_distance_mapping()
	_test_one_event_and_pure_position_boundary()
	_test_invalid_neighbors_fail_closed()
	await _test_fractional_actor_displacement()
	print("MONSTER_NEIGHBOR_STEP_POLICY_PASS checks=%d" % _checks)
	get_tree().quit(0)


func _test_fractional_actor_displacement() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for mid: int in [18, 24]:
		for neighbor: Vector2i in NeighborPolicy.allowed_neighbors():
			var actor := EnemyActor.new()
			actor.setup(GameData.get_monster_by_id(mid), null, false)
			actor.move_speed_gu_per_sec = 3.0
			actor.set_meta("safe_zones", [])
			add_child(actor)
			actor.set_physics_process(false)
			var origin := Vector2(10.23, 10.37)
			actor.global_position = GroundUnitSpace.ground_delta_gu_to_screen_delta_px(origin)
			assert(actor._begin_autonomous_step_without_cadence(Vector2(neighbor), 1.0, false, &"direction_probe"))
			var destination := actor._movement_step_target_ground_gu
			var frames := 0
			while actor._movement_step_active and frames < 180:
				await get_tree().physics_frame
				var before := actor.global_position
				actor._advance_autonomous_step(1.0 / 60.0)
				var motion := GroundUnitSpace.screen_delta_px_to_ground_delta_gu(actor.global_position - before)
				assert(motion.length() <= actor.move_speed_gu_per_sec / 60.0 + 0.0001, "corner transition must not teleport or increase speed")
				if motion.length() > 0.00002:
					var unit := motion.normalized().abs()
					assert(unit.x < 0.002 or unit.y < 0.002 or absf(unit.x - unit.y) < 0.002,
						"monster %d has non-eight-way displacement from fractional origin: %s" % [mid, motion])
				frames += 1
			assert(not actor._movement_step_active, "eight-way route must finish without oscillation")
			assert(GroundUnitSpace.screen_delta_px_to_ground_delta_gu(actor.global_position).distance_to(destination) < 0.001,
				"eight-way movement must preserve the selected exact endpoint")
			actor.free()
			_checks += 1


func _test_quantization_and_centers() -> void:
	var cases: Array = [
		[Vector2(3.2, 4.9), Vector2i(3, 4), Vector2(3.5, 4.5)],
		[Vector2.ZERO, Vector2i.ZERO, Vector2(0.5, 0.5)],
		[Vector2(-0.1, -1.0), Vector2i(-1, -1), Vector2(-0.5, -0.5)],
		[Vector2(-1.0, 2.0), Vector2i(-1, 2), Vector2(-0.5, 2.5)],
		[Vector2(1.0, 2.999), Vector2i(1, 2), Vector2(1.5, 2.5)],
	]
	for quantization_case: Array in cases:
		var position: Vector2 = quantization_case[0]
		var expected_cell: Vector2i = quantization_case[1]
		var expected_center: Vector2 = quantization_case[2]
		assert(NeighborPolicy.temporary_cell(position) == expected_cell)
		assert(NeighborPolicy.cell_center_ground_gu(expected_cell) == expected_center)
		var built := NeighborPolicy.build_neighbor_step(position, Vector2i.RIGHT)
		assert(built.valid and built.temporary_cell == expected_cell)
		assert(built.cell_center_ground_gu == expected_center)
		_checks += 4


func _test_eight_unique_neighbors() -> void:
	var neighbors := NeighborPolicy.allowed_neighbors()
	assert(neighbors.size() == 8)
	var keys: Dictionary = {}
	for neighbor: Vector2i in neighbors:
		assert(NeighborPolicy.is_valid_neighbor(neighbor))
		var key := "%d,%d" % [neighbor.x, neighbor.y]
		assert(not keys.has(key), "neighbor deltas must be unique")
		keys[key] = true
	assert(keys.size() == 8)
	assert(not keys.has("0,0"))
	_checks += 18


func _test_direction_and_distance_mapping() -> void:
	for neighbor: Vector2i in NeighborPolicy.allowed_neighbors():
		var direction := NeighborPolicy.desired_ground_direction(neighbor)
		assert(direction.length() > 0.99999 and direction.length() < 1.00001)
		assert(direction.is_equal_approx(Vector2(neighbor).normalized()))
		var distance := NeighborPolicy.neighbor_distance_gu(neighbor)
		var diagonal := neighbor.x != 0 and neighbor.y != 0
		var expected_distance := NeighborPolicy.DIAGONAL_NEIGHBOR_DISTANCE_GU if diagonal else NeighborPolicy.AXIS_NEIGHBOR_DISTANCE_GU
		assert(is_equal_approx(distance, expected_distance))
		assert(NeighborPolicy.neighbor_for_desired_ground_direction(direction) == neighbor)
		assert(NeighborPolicy.neighbor_from_desired_ground_direction(direction) == neighbor)
		_checks += 5

	assert(NeighborPolicy.neighbor_for_desired_ground_direction(Vector2.ZERO) == Vector2i.ZERO)
	assert(NeighborPolicy.neighbor_for_desired_ground_direction(Vector2(INF, 1.0)) == Vector2i.ZERO)
	assert(NeighborPolicy.neighbor_for_desired_ground_direction(Vector2(-0.01, 100.0)) == Vector2i(0, 1))
	assert(NeighborPolicy.neighbor_for_desired_ground_direction(Vector2(100.0, -0.01)) == Vector2i(1, 0))
	_test_stable_axis_sectors()
	_checks += 4


func _test_stable_axis_sectors() -> void:
	var cases: Array = [
		[Vector2(1.0, 0.01), Vector2i(1, 0)],
		[Vector2(1.0, -0.01), Vector2i(1, 0)],
		[Vector2(-1.0, 0.01), Vector2i(-1, 0)],
		[Vector2(-1.0, -0.01), Vector2i(-1, 0)],
		[Vector2(0.01, 1.0), Vector2i(0, 1)],
		[Vector2(-0.01, 1.0), Vector2i(0, 1)],
		[Vector2(0.01, -1.0), Vector2i(0, -1)],
		[Vector2(-0.01, -1.0), Vector2i(0, -1)],
		[Vector2(1.0, 0.5), Vector2i(1, 1)],
		[Vector2(-1.0, 0.5), Vector2i(-1, 1)],
		[Vector2(1.0, -0.5), Vector2i(1, -1)],
		[Vector2(-1.0, -0.5), Vector2i(-1, -1)],
	]
	for quantization_case: Array in cases:
		assert(
			NeighborPolicy.neighbor_for_desired_ground_direction(
				quantization_case[0]
			) == quantization_case[1],
			"eight-way sector must stay stable for %s" % quantization_case[0],
		)
		_checks += 1


func _test_one_event_and_pure_position_boundary() -> void:
	var origin := Vector2(10.2, -4.8)
	var axis := NeighborPolicy.build_neighbor_step(origin, Vector2i.RIGHT)
	assert(axis.valid)
	assert(axis.target_ground_gu == Vector2(11.5, -4.5))
	assert(axis.displacement_ground_gu == Vector2(1.0, 0.0))
	assert(is_equal_approx(axis.distance_gu, 1.0))
	assert(axis.movement_events == NeighborPolicy.MOVEMENT_EVENTS_PER_NEIGHBOR)

	var diagonal := NeighborPolicy.build_step(origin, Vector2i(-1, -1))
	assert(diagonal.valid)
	assert(diagonal.target_ground_gu == Vector2(9.5, -5.5))
	assert(diagonal.displacement_ground_gu == Vector2(-1.0, -1.0))
	assert(is_equal_approx(diagonal.distance_gu, sqrt(2.0)))
	assert(diagonal.movement_events == 1)

	# No previous call may affect a later position: position is never stored.
	var second_position := NeighborPolicy.build_neighbor_step(Vector2(0.1, 0.1), Vector2i.UP)
	assert(second_position.temporary_cell == Vector2i.ZERO)
	assert(second_position.target_ground_gu == Vector2(0.5, -0.5))
	_checks += 12


func _test_invalid_neighbors_fail_closed() -> void:
	assert(not NeighborPolicy.is_valid_neighbor(Vector2i.ZERO))
	assert(not NeighborPolicy.is_valid_neighbor(Vector2i(2, 0)))
	assert(not NeighborPolicy.is_valid_neighbor(Vector2i(0, -2)))
	assert(not NeighborPolicy.is_valid_neighbor(Vector2.ZERO))
	assert(NeighborPolicy.desired_ground_direction(Vector2i.ZERO) == Vector2.ZERO)
	assert(NeighborPolicy.neighbor_distance_gu(Vector2i.ZERO) < 0.0)
	var invalid := NeighborPolicy.build_neighbor_step(Vector2.ZERO, Vector2i.ZERO)
	assert(not invalid.valid and invalid.movement_events == 0)
	var invalid_position := NeighborPolicy.build_neighbor_step(Vector2(INF, 0.0), Vector2i.RIGHT)
	assert(not invalid_position.valid and invalid_position.movement_events == 0)
	_checks += 8
