extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Diagnostic := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const WorldSpatialRules := preload("res://scripts/world_spatial_rules.gd")

const NORMAL_COMBAT_RADIUS_GU := 16.0 / (32.0 * sqrt(2.0))
const BOSS_COMBAT_RADIUS_GU := 28.0 / (32.0 * sqrt(2.0))
const SEPARATION := 0.002


func _ready() -> void:
	_test_contract_and_exact_physics_footprints()
	_test_thrust_lane_contact_all_directions()
	_test_thrust_primary_secondary_priority()
	_test_thrust_endpoint_contact_all_directions()
	_test_normal_fire_and_half_moon_contact_all_directions()
	_test_half_moon_primary_secondary_priority()
	_test_diagnostic_reports_point_and_footprint_results()
	_test_v53_angle_and_movement_snapshot_regression()
	print("WARRIOR_MELEE_FOOTPRINT_GEOMETRY_PASS: fixed attack areas intersect canonical monster footprints in all eight directions")
	get_tree().quit()


func _test_contract_and_exact_physics_footprints() -> void:
	assert(
		Geometry.FOOTPRINT_INTERSECTION_CONTRACT_ID
		== "gameplay.warrior.melee_footprint_intersection.ground_gu_sat.v2"
	)
	assert(Geometry.TARGET_FOOTPRINT_CONTRACT_ID == "world.actor_footprint.ground_circle_gu.v1")
	for radius_gu: float in [NORMAL_COMBAT_RADIUS_GU, BOSS_COMBAT_RADIUS_GU]:
		var polygon := Geometry.target_footprint_polygon_ground_gu(
			Vector2.ZERO,
			radius_gu
		)
		assert(polygon.size() == 16)
		var source_polygon := WorldSpatialRules.actor_footprint_ground_polygon_gu(
			radius_gu
		)
		for index in range(source_polygon.size()):
			assert(polygon[index].is_equal_approx(source_polygon[index]))
		var measured_radius := 0.0
		for point: Vector2 in polygon:
			measured_radius = maxf(measured_radius, point.length())
		assert(is_equal_approx(measured_radius, radius_gu))


func _test_thrust_lane_contact_all_directions() -> void:
	for radius: float in [NORMAL_COMBAT_RADIUS_GU, BOSS_COMBAT_RADIUS_GU]:
		for direction_index in range(8):
			var step := Vector2(Geometry.facing_tile_step(direction_index)).normalized()
			var side := Vector2(step.y, -step.x)
			var lateral_support := _line_support(radius, direction_index, false)
			for forward: float in [0.75, 2.5]:
				var touching_center := (
					step * forward
					+ side * (Geometry.THRUST_WIDTH_TILES * 0.5 + lateral_support)
				)
				assert(
					Geometry.thrust_slot(Vector2.ZERO, touching_center, direction_index) == 0,
					"old point test must remain outside the one-tile lane"
				)
				var expected_slot := 1 if forward <= Geometry.THRUST_PRIMARY_REACH_TILES else 2
				assert(
					Geometry.thrust_footprint_slot_gu(
						Vector2.ZERO,
						touching_center,
						radius,
						direction_index
					) == expected_slot,
					"touching footprint was rejected for direction %d" % direction_index
				)
				var separated_center := touching_center + side * SEPARATION
				assert(
					Geometry.thrust_footprint_slot_gu(
						Vector2.ZERO,
						separated_center,
						radius,
						direction_index
					) == 0,
					"fully separated footprint widened the thrust lane for direction %d" % direction_index
				)


func _test_thrust_primary_secondary_priority() -> void:
	for radius: float in [NORMAL_COMBAT_RADIUS_GU, BOSS_COMBAT_RADIUS_GU]:
		for direction_index in range(8):
			var step := Vector2(Geometry.facing_tile_step(direction_index)).normalized()
			var forward_support := _line_support(radius, direction_index, true)
			# Exact boundary contact belongs to the primary segment.
			var touching_boundary := step * (
				Geometry.THRUST_PRIMARY_REACH_TILES + forward_support
			)
			assert(Geometry.thrust_footprint_slot_gu(
				Vector2.ZERO,
				touching_boundary,
				radius,
				direction_index
			) == 1)
			# Once the complete body is beyond the boundary it belongs only to slot 2.
			assert(Geometry.thrust_footprint_slot_gu(
				Vector2.ZERO,
				touching_boundary + step * SEPARATION,
				radius,
				direction_index
			) == 2)


func _test_thrust_endpoint_contact_all_directions() -> void:
	for radius: float in [NORMAL_COMBAT_RADIUS_GU, BOSS_COMBAT_RADIUS_GU]:
		for direction_index in range(8):
			var step := Vector2(Geometry.facing_tile_step(direction_index)).normalized()
			var forward_support := _line_support(radius, direction_index, true)
			var touching_center := step * (
				Geometry.reach_tiles(Geometry.SKILL_THRUST) + forward_support
			)
			assert(Geometry.thrust_slot(Vector2.ZERO, touching_center, direction_index) == 0)
			assert(
				Geometry.thrust_footprint_slot_gu(
					Vector2.ZERO,
					touching_center,
					radius,
					direction_index
				) == 2
			)
			assert(
				Geometry.thrust_footprint_slot_gu(
					Vector2.ZERO,
					touching_center + step * SEPARATION,
					radius,
					direction_index
				) == 0
			)


func _test_normal_fire_and_half_moon_contact_all_directions() -> void:
	for radius: float in [NORMAL_COMBAT_RADIUS_GU, BOSS_COMBAT_RADIUS_GU]:
		for direction_index in range(8):
			var step := Vector2(Geometry.facing_tile_step(direction_index)).normalized()
			var forward_support := _line_support(radius, direction_index, true)
			for mode: String in [
				Geometry.SKILL_NORMAL,
				Geometry.SKILL_FIRE,
				Geometry.SKILL_HALF_MOON,
			]:
				var touching_center := step * (
					Geometry.reach_tiles(mode) + forward_support
				)
				assert(
					not Geometry.is_single_target_in_reach(
						Vector2.ZERO,
						touching_center,
						mode
					),
					"old centre-point range unexpectedly accepted the contact sample"
				)
				assert(
					Geometry.footprint_intersects_mode_gu(
						Vector2.ZERO,
						touching_center,
						radius,
						direction_index,
						mode
					),
					"footprint contact was rejected for %s direction %d" % [mode, direction_index]
				)
				assert(
					not Geometry.footprint_intersects_mode_gu(
						Vector2.ZERO,
						touching_center + step * SEPARATION,
						radius,
						direction_index,
						mode
					),
					"fully separated footprint expanded %s direction %d" % [mode, direction_index]
				)


func _test_half_moon_primary_secondary_priority() -> void:
	for attack_direction in range(8):
		var primary_step := Vector2(Geometry.facing_tile_step(attack_direction)).normalized()
		var side_step := Vector2(Geometry.facing_tile_step(posmod(attack_direction + 1, 8))).normalized()
		assert(
			Geometry.half_moon_footprint_relative_sector_gu(
				Vector2.ZERO,
				primary_step,
				NORMAL_COMBAT_RADIUS_GU,
				attack_direction
			) == 0
		)
		assert(
			Geometry.half_moon_footprint_relative_sector_gu(
				Vector2.ZERO,
				side_step * 1.25,
				NORMAL_COMBAT_RADIUS_GU,
				attack_direction
			) == 1
		)
		# The target body overlaps both adjacent sectors. Primary must win so the
		# integration layer cannot apply both primary and secondary multipliers.
		var boundary_angle := primary_step.angle() + PI / 8.0
		var straddling_center := Vector2.from_angle(boundary_angle) * 1.0
		assert(
			Geometry.footprint_intersects_direction_sector_gu(
				Vector2.ZERO,
				straddling_center,
				NORMAL_COMBAT_RADIUS_GU,
				attack_direction,
				Geometry.reach_tiles(Geometry.SKILL_HALF_MOON)
			)
		)
		assert(
			Geometry.footprint_intersects_direction_sector_gu(
				Vector2.ZERO,
				straddling_center,
				NORMAL_COMBAT_RADIUS_GU,
				posmod(attack_direction + 1, 8),
				Geometry.reach_tiles(Geometry.SKILL_HALF_MOON)
			)
		)
		assert(
			Geometry.half_moon_footprint_relative_sector_gu(
				Vector2.ZERO,
				straddling_center,
				NORMAL_COMBAT_RADIUS_GU,
				attack_direction
			) == 0
		)


func _test_diagnostic_reports_point_and_footprint_results() -> void:
	var direction_index := 7
	var step := Vector2(Geometry.facing_tile_step(direction_index)).normalized()
	var side := Vector2(step.y, -step.x)
	var lateral_support := _line_support(NORMAL_COMBAT_RADIUS_GU, direction_index, false)
	var target := step * 2.0 + side * (
		Geometry.THRUST_WIDTH_TILES * 0.5 + lateral_support
	)
	var report := Diagnostic.explain_footprint_candidate(
		Vector2.ZERO,
		target,
		NORMAL_COMBAT_RADIUS_GU,
		direction_index,
		Geometry.SKILL_THRUST
	)
	assert(report.contract_id == "diagnostic.warrior.melee_footprint_candidate.ground_gu.v2")
	assert(report.point_candidate_contract_id == Diagnostic.CONTRACT_ID)
	assert(report.point_result_code == Diagnostic.RESULT_OUTSIDE_ATTACK_LANE)
	assert(not report.point_accepted)
	assert(report.footprint_result_code == Diagnostic.RESULT_OK)
	assert(report.footprint_accepted and report.accepted)
	assert(report.point_thrust_slot == 0)
	assert(report.footprint_thrust_slot == 2)
	assert(report.target_combat_radius_gu == NORMAL_COMBAT_RADIUS_GU)
	assert(report.target_footprint_vertex_count == 16)
	assert(report.attack_region_polygon_count == 1)
	assert(report.footprint_intersection_contract_id == Geometry.FOOTPRINT_INTERSECTION_CONTRACT_ID)
	assert(report.target_footprint_contract_id == Geometry.TARGET_FOOTPRINT_CONTRACT_ID)
	_assert_json_safe(report)


func _test_v53_angle_and_movement_snapshot_regression() -> void:
	var reported_delta := Vector2(-0.60, -1.20)
	assert(Geometry.direction_index_for_tile_delta(reported_delta) == 4)
	assert(Geometry.thrust_slot(Vector2.ZERO, reported_delta, 4) == 1)
	assert(Geometry.thrust_footprint_slot_gu(
		Vector2.ZERO,
		reported_delta,
		NORMAL_COMBAT_RADIUS_GU,
		4
	) == 1)
	var input_world_direction := DirectionSpace.fractional_tile_delta_to_world_delta(
		reported_delta
	)
	var release := ReleaseGeometry.resolve(
		Vector2(200.0, -100.0),
		input_world_direction,
		77,
		Vector2(-999.0, 999.0),
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	assert(release.direction_locked_for_action)
	assert(release.direction_index == 4)
	assert(release.direction_canonical_tile_step == Vector2i(-1, -1))
	assert(release.direction_screen_px.is_equal_approx(Vector2.UP))


func _line_support(
	radius: float,
	direction_index: int,
	forward_axis: bool
) -> float:
	var support := 0.0
	for point: Vector2 in Geometry.target_footprint_polygon_ground_gu(
		Vector2.ZERO,
		radius
	):
		var coordinates := Geometry.line_coordinates(point, direction_index)
		support = maxf(support, absf(coordinates.x if forward_axis else coordinates.y))
	return support


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
