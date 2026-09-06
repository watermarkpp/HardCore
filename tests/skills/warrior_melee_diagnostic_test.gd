extends Node

const Diagnostic := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")


func _ready() -> void:
	_test_direction_round_trip()
	_test_fractional_angle_quantization_audit()
	_test_normal_and_fire_boundaries()
	_test_thrust_lane_boundaries()
	_test_half_moon_arc_boundaries()
	_test_mirrors_canonical_geometry()
	_test_json_serialization()
	print("WARRIOR_MELEE_DIAGNOSTIC_PASS: structured reasons, eight directions and canonical boundaries")
	get_tree().quit()


func _test_direction_round_trip() -> void:
	var all_directions := Diagnostic.audit_all_directions()
	assert(all_directions.contract_id == "diagnostic.warrior.melee_direction_loop.v1")
	assert(all_directions.direction_count == 8)
	assert(all_directions.consistent)
	assert(
		all_directions.direction_space_contract_id
		== "gameplay.professions.combat_direction_space.ground_gu_8dir.v3"
	)
	for direction_index in range(8):
		var audit: Dictionary = all_directions.directions[direction_index]
		assert(audit.result_code == Diagnostic.RESULT_OK)
		assert(
			audit.direction_space_contract_id
			== "gameplay.professions.combat_direction_space.ground_gu_8dir.v3"
		)
		assert(audit.screen_direction_index == direction_index)
		assert(audit.world_direction_index == direction_index)
		assert(audit.projected_screen_direction_index == direction_index)
		assert(audit.round_trip_matches)
		var expected_step := Geometry.facing_tile_step(direction_index)
		assert(audit.canonical_grid_step.x == expected_step.x)
		assert(audit.canonical_grid_step.y == expected_step.y)


func _test_fractional_angle_quantization_audit() -> void:
	# Every exact canonical step is a closed direction in both coordinate
	# interpretations. This proves the disagreement is not an index-order bug.
	for direction_index in range(8):
		var delta := Vector2(Geometry.facing_tile_step(direction_index))
		var exact := Diagnostic.audit_ground_delta_gu(delta)
		assert(
			exact.contract_id
			== "diagnostic.warrior.melee_angle_quantization.v1"
		)
		assert(exact.has_direction)
		assert(exact.projected_screen_45_direction_index == direction_index)
		assert(exact.ground_space_45_direction_index == direction_index)
		assert(exact.quantizers_match)
		assert(exact.projected_screen_canonical_grid_step.x == int(delta.x))
		assert(exact.projected_screen_canonical_grid_step.y == int(delta.y))
		assert(exact.ground_space_canonical_grid_step.x == int(delta.x))
		assert(exact.ground_space_canonical_grid_step.y == int(delta.y))

	# Fractional deltas expose the actual policy difference: in a 2:1 screen
	# projection (1,0.5) appears closer to SE, while direct tile-space 45-degree
	# quantization classifies it as S.
	var asymmetric := Diagnostic.audit_ground_delta_gu(Vector2(1.0, 0.5))
	assert(asymmetric.projected_screen_45_direction_index == 7)
	assert(asymmetric.ground_space_45_direction_index == 0)
	assert(not asymmetric.quantizers_match)
	assert(asymmetric.projected_screen_canonical_grid_step.x == 1)
	assert(asymmetric.projected_screen_canonical_grid_step.y == 0)
	assert(asymmetric.ground_space_canonical_grid_step.x == 1)
	assert(asymmetric.ground_space_canonical_grid_step.y == 1)
	assert(is_equal_approx(asymmetric.projected_screen_vector_px.x, 16.0))
	assert(is_equal_approx(asymmetric.projected_screen_vector_px.y, 24.0))
	var normalized_length := sqrt(
		pow(float(asymmetric.projected_screen_direction_px.x), 2.0)
		+ pow(float(asymmetric.projected_screen_direction_px.y), 2.0)
	)
	assert(is_equal_approx(normalized_length, 1.0))

	var mirrored := Diagnostic.audit_ground_delta_gu(Vector2(0.5, 1.0))
	assert(mirrored.projected_screen_45_direction_index == 1)
	assert(mirrored.ground_space_45_direction_index == 0)
	assert(not mirrored.quantizers_match)


func _test_normal_and_fire_boundaries() -> void:
	var south_gu := Vector2(1.0, 1.0).normalized()
	for mode: String in [Geometry.SKILL_NORMAL, Geometry.SKILL_FIRE]:
		var accepted := Diagnostic.explain_candidate(
			Vector2.ZERO, south_gu * 2.0, 0, mode
		)
		assert(accepted.accepted and accepted.result_code == Diagnostic.RESULT_OK)
		assert(is_equal_approx(accepted.effective_reach_gu, 2.0))
		assert(accepted.maximum_targets == 1)
		assert(not accepted.unlimited_targets_within_geometry)
		var wrong_facing := Diagnostic.explain_candidate(
			Vector2.ZERO, Vector2(1.0, -1.0), 0, mode
		)
		assert(not wrong_facing.accepted)
		assert(wrong_facing.result_code == Diagnostic.RESULT_WRONG_FACING)
		var outside := Diagnostic.explain_candidate(
			Vector2.ZERO, south_gu * 2.0002, 0, mode
		)
		assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)
	var same_footpoint := Diagnostic.explain_candidate(
		Vector2(4.25, 7.5), Vector2(4.25, 7.5), 0, Geometry.SKILL_NORMAL
	)
	assert(same_footpoint.result_code == Diagnostic.RESULT_SAME_FOOTPOINT)
	assert(same_footpoint.target_direction_index == -1)


func _test_thrust_lane_boundaries() -> void:
	var south_gu := Vector2(1.0, 1.0).normalized()
	var side_gu := Vector2(1.0, -1.0).normalized()
	var primary := Diagnostic.explain_candidate(
		Vector2.ZERO, south_gu * 1.5, 0, Geometry.SKILL_THRUST
	)
	assert(primary.accepted and primary.thrust_slot == 1)
	assert(is_equal_approx(primary.effective_reach_gu, 3.0))
	assert(is_equal_approx(primary.attack_lane_width_gu, 1.0))
	assert(primary.maximum_targets == Geometry.UNLIMITED_TARGETS)
	assert(primary.unlimited_targets_within_geometry)
	var endpoint := Diagnostic.explain_candidate(
		Vector2.ZERO, south_gu * 3.0, 0, Geometry.SKILL_THRUST
	)
	assert(endpoint.accepted and endpoint.thrust_slot == 2)
	var outside_lane := Diagnostic.explain_candidate(
		Vector2.ZERO, south_gu * 1.0 + side_gu * 0.6, 0, Geometry.SKILL_THRUST
	)
	assert(outside_lane.result_code == Diagnostic.RESULT_OUTSIDE_ATTACK_LANE)
	var behind := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(-1.0, -1.0), 0, Geometry.SKILL_THRUST
	)
	assert(behind.result_code == Diagnostic.RESULT_WRONG_FACING)
	var outside := Diagnostic.explain_candidate(
		Vector2.ZERO, south_gu * 3.0002, 0, Geometry.SKILL_THRUST
	)
	assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)


func _test_half_moon_arc_boundaries() -> void:
	for attack_direction in range(8):
		for relative_sector: int in Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
			var target_direction := posmod(attack_direction + relative_sector, 8)
			var target := Vector2(Geometry.facing_tile_step(target_direction)).normalized() * 1.5
			var accepted := Diagnostic.explain_candidate(
				Vector2.ZERO, target, attack_direction, Geometry.SKILL_HALF_MOON
			)
			assert(accepted.result_code == Diagnostic.RESULT_OK)
			assert(accepted.maximum_targets == Geometry.UNLIMITED_TARGETS)
			assert(accepted.unlimited_targets_within_geometry)
	var rejected_target := Vector2(Geometry.facing_tile_step(4))
	var rejected := Diagnostic.explain_candidate(
		Vector2.ZERO, rejected_target, 0, Geometry.SKILL_HALF_MOON
	)
	assert(rejected.result_code == Diagnostic.RESULT_OUTSIDE_HALF_MOON_ARC)
	var outside := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(1.0, 1.0).normalized() * 2.0002, 0, Geometry.SKILL_HALF_MOON
	)
	assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)


func _test_mirrors_canonical_geometry() -> void:
	var sample_coordinates: Array[float] = [-3.0002, -1.5, -0.5, 0.0, 0.5, 1.5, 3.0002]
	for attack_direction in range(8):
		for x: float in sample_coordinates:
			for y: float in sample_coordinates:
				var target := Vector2(x, y)
				for mode: String in [
					Geometry.SKILL_NORMAL,
					Geometry.SKILL_FIRE,
					Geometry.SKILL_THRUST,
					Geometry.SKILL_HALF_MOON,
				]:
					var explained := Diagnostic.explain_candidate(
						Vector2.ZERO, target, attack_direction, mode
					)
					var expected := false
					match mode:
						Geometry.SKILL_THRUST:
							expected = Geometry.thrust_slot(
								Vector2.ZERO, target, attack_direction
							) > 0
						Geometry.SKILL_HALF_MOON:
							expected = Geometry.is_in_half_moon_arc(
								Vector2.ZERO, target, attack_direction
							)
						_:
							expected = (
								Geometry.is_single_target_in_reach(
									Vector2.ZERO, target, mode
								)
								and Geometry.direction_index_for_ground_delta_gu(target)
								== attack_direction
							)
					assert(explained.accepted == expected)


func _test_json_serialization() -> void:
	var report := {
		"candidate": Diagnostic.explain_candidate(
			Vector2(1.25, -4.5), Vector2(2.0, -3.75), 0, Geometry.SKILL_NORMAL
		),
		"direction_loop": Diagnostic.audit_all_directions(),
	}
	var encoded := JSON.stringify(report)
	assert(not encoded.is_empty())
	var decoded = JSON.parse_string(encoded)
	assert(decoded is Dictionary)
	assert(decoded.candidate.contract_id == "diagnostic.warrior.melee_candidate.ground_gu.v2")
	assert(decoded.direction_loop.direction_count == 8.0)
	_assert_json_safe(report)


func _assert_json_safe(value) -> void:
	if value is Dictionary:
		for key in value:
			assert(key is String)
			_assert_json_safe(value[key])
	elif value is Array:
		for item in value:
			_assert_json_safe(item)
	else:
		assert(value == null or value is bool or value is int or value is float or value is String)
