extends Node

const Diagnostic := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")


func _ready() -> void:
	_test_direction_round_trip()
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
	for direction_index in range(8):
		var audit: Dictionary = all_directions.directions[direction_index]
		assert(audit.result_code == Diagnostic.RESULT_OK)
		assert(audit.screen_direction_index == direction_index)
		assert(audit.world_direction_index == direction_index)
		assert(audit.projected_screen_direction_index == direction_index)
		assert(audit.round_trip_matches)
		var expected_step := Geometry.facing_tile_step(direction_index)
		assert(audit.canonical_tile_step.x == expected_step.x)
		assert(audit.canonical_tile_step.y == expected_step.y)


func _test_normal_and_fire_boundaries() -> void:
	for mode: String in [Geometry.SKILL_NORMAL, Geometry.SKILL_FIRE]:
		var accepted := Diagnostic.explain_candidate(
			Vector2.ZERO, Vector2(1.5, 1.5), 0, mode
		)
		assert(accepted.accepted and accepted.result_code == Diagnostic.RESULT_OK)
		assert(is_equal_approx(accepted.effective_reach_tiles, 1.5))
		assert(accepted.maximum_targets == 1)
		assert(not accepted.unlimited_targets_within_geometry)
		var wrong_facing := Diagnostic.explain_candidate(
			Vector2.ZERO, Vector2(1.0, -1.0), 0, mode
		)
		assert(not wrong_facing.accepted)
		assert(wrong_facing.result_code == Diagnostic.RESULT_WRONG_FACING)
		var outside := Diagnostic.explain_candidate(
			Vector2.ZERO, Vector2(1.5002, 1.5002), 0, mode
		)
		assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)
	var same_footpoint := Diagnostic.explain_candidate(
		Vector2(4.25, 7.5), Vector2(4.25, 7.5), 0, Geometry.SKILL_NORMAL
	)
	assert(same_footpoint.result_code == Diagnostic.RESULT_SAME_FOOTPOINT)
	assert(same_footpoint.target_direction_index == -1)


func _test_thrust_lane_boundaries() -> void:
	var primary := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(1.5, 1.5), 0, Geometry.SKILL_THRUST
	)
	assert(primary.accepted and primary.thrust_slot == 1)
	assert(is_equal_approx(primary.effective_reach_tiles, 2.5))
	assert(is_equal_approx(primary.attack_lane_width_tiles, 1.0))
	assert(primary.maximum_targets == Geometry.UNLIMITED_TARGETS)
	assert(primary.unlimited_targets_within_geometry)
	var endpoint := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(2.5, 2.5), 0, Geometry.SKILL_THRUST
	)
	assert(endpoint.accepted and endpoint.thrust_slot == 2)
	var outside_lane := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(1.6, 0.4), 0, Geometry.SKILL_THRUST
	)
	assert(outside_lane.result_code == Diagnostic.RESULT_OUTSIDE_ATTACK_LANE)
	var behind := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(-1.0, -1.0), 0, Geometry.SKILL_THRUST
	)
	assert(behind.result_code == Diagnostic.RESULT_WRONG_FACING)
	var outside := Diagnostic.explain_candidate(
		Vector2.ZERO, Vector2(2.5002, 2.5002), 0, Geometry.SKILL_THRUST
	)
	assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)


func _test_half_moon_arc_boundaries() -> void:
	for attack_direction in range(8):
		for relative_sector: int in Geometry.HALF_MOON_RELATIVE_DIRECTION_OFFSETS:
			var target_direction := posmod(attack_direction + relative_sector, 8)
			var target := Vector2(Geometry.facing_tile_step(target_direction)) * 1.5
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
		Vector2.ZERO, Vector2(1.5002, 1.5002), 0, Geometry.SKILL_HALF_MOON
	)
	assert(outside.result_code == Diagnostic.RESULT_OUT_OF_RANGE)


func _test_mirrors_canonical_geometry() -> void:
	var sample_coordinates: Array[float] = [-2.5002, -1.5, -0.5, 0.0, 0.5, 1.5, 2.5002]
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
								and Geometry.direction_index_for_tile_delta(target)
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
	assert(decoded.candidate.contract_id == "diagnostic.warrior.melee_candidate.v1")
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
