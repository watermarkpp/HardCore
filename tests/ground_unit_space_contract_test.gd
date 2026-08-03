extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_verify_projection_round_trip()
	_verify_equal_gu_length_in_32_directions()
	_verify_east_screen_example()
	_verify_euclidean_range()
	_verify_movement_and_path_costs()
	print("GROUND_UNIT_SPACE_CONTRACT_PASS: GU/GS/PX remain explicit across 32 directions")
	get_tree().quit(0)


func _verify_projection_round_trip() -> void:
	for sample: Vector2 in [
		Vector2.ZERO,
		Vector2.RIGHT,
		Vector2.DOWN,
		Vector2(1.0, 1.0),
		Vector2(2.75, -4.125),
		Vector2(-8.5, 3.25),
	]:
		var screen_delta_px := (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(sample)
		)
		var round_trip_gu := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_delta_px)
		)
		assert(round_trip_gu.is_equal_approx(sample), str([sample, round_trip_gu]))


func _verify_equal_gu_length_in_32_directions() -> void:
	for direction_index: int in range(32):
		var angle := TAU * float(direction_index) / 32.0
		var direction_ground := Vector2.from_angle(angle)
		var endpoint_ground_gu := GroundUnitSpaceScript.endpoint_ground_gu(
			Vector2(17.0, -9.0), direction_ground, 8.0
		)
		assert(is_equal_approx(
			GroundUnitSpaceScript.distance_gu(
				Vector2(17.0, -9.0), endpoint_ground_gu
			),
			8.0
		), str([direction_index, endpoint_ground_gu]))
		var screen_delta_px := (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground * 8.0
			)
		)
		var restored_ground_delta_gu := (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(screen_delta_px)
		)
		assert(is_equal_approx(restored_ground_delta_gu.length(), 8.0))


func _verify_east_screen_example() -> void:
	var east_ground_direction := Vector2(1.0, -1.0).normalized()
	var east_screen_delta_px := (
		GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			east_ground_direction * 8.0
		)
	)
	assert(is_zero_approx(east_screen_delta_px.y))
	assert(is_equal_approx(east_screen_delta_px.x, 256.0 * sqrt(2.0)))
	assert(is_equal_approx(east_screen_delta_px.length(), 362.03867))


func _verify_euclidean_range() -> void:
	assert(GroundUnitSpaceScript.is_within_range_gu(Vector2.ZERO, Vector2(6.0, 8.0), 10.0))
	assert(not GroundUnitSpaceScript.is_within_range_gu(Vector2.ZERO, Vector2(6.0, 8.01), 10.0))
	# A legacy Chebyshev square would accept this point at range 10. GU must not.
	assert(not GroundUnitSpaceScript.is_within_range_gu(Vector2.ZERO, Vector2(10.0, 10.0), 10.0))


func _verify_movement_and_path_costs() -> void:
	var expected_motion_gu := 3.25
	for direction_index: int in range(32):
		var direction_ground := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		)
		var motion_gu := GroundUnitSpaceScript.desired_ground_motion_gu(
			direction_ground, 6.5, 0.5
		)
		assert(is_equal_approx(motion_gu.length(), expected_motion_gu))
	assert(is_equal_approx(
		GroundUnitSpaceScript.path_step_cost_gu(Vector2i.RIGHT), 1.0
	))
	assert(is_equal_approx(
		GroundUnitSpaceScript.path_step_cost_gu(Vector2i(1, 1)), sqrt(2.0)
	))
