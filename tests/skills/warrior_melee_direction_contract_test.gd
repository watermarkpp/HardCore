extends Node

const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Diagnostic := preload("res://scripts/skills/warrior_melee_diagnostic.gd")
const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const ArtSpec := preload("res://scripts/art_spec.gd")


func _ready() -> void:
	_test_exact_eight_direction_round_trip()
	_test_tile_space_quantization_boundaries()
	_test_phone_failure_coordinate_regression()
	_test_all_warrior_mode_direction_contracts()
	print("WARRIOR_MELEE_DIRECTION_CONTRACT_PASS: 64x32 tile-space facing and phone regression")
	get_tree().quit()


func _test_exact_eight_direction_round_trip() -> void:
	assert(
		DirectionSpace.CONTRACT_ID
		== "gameplay.professions.combat_direction_space.ground_gu_8dir.v3"
	)
	assert(Geometry.DIRECTION_SPACE_CONTRACT_ID == DirectionSpace.CONTRACT_ID)
	for direction_index in range(8):
		var grid_step := Vector2(DirectionSpace.canonical_grid_step(direction_index))
		var screen_delta_px := DirectionSpace.ground_delta_gu_to_screen_delta_px(grid_step)
		var round_trip_gu := DirectionSpace.screen_delta_px_to_ground_delta_gu(screen_delta_px)
		assert(round_trip_gu.is_equal_approx(grid_step))
		assert(
			DirectionSpace.direction_index_for_ground_delta_gu(grid_step)
			== direction_index
		)
		assert(DirectionSpace.direction_index_for_screen_delta_px(screen_delta_px) == direction_index)
		assert(Geometry.direction_index_for_ground_delta_gu(grid_step) == direction_index)
		var projected_direction := DirectionSpace.projected_screen_direction_px(direction_index)
		assert(ArtSpec.direction_index(projected_direction) == direction_index)
		var resolved := DirectionSpace.resolve_screen_delta_px(screen_delta_px)
		assert(resolved.contract_id == DirectionSpace.CONTRACT_ID)
		assert(resolved.direction_index == direction_index)
		assert(resolved.visual_direction_index == direction_index)
		assert(resolved.canonical_grid_step == Vector2i(grid_step))
		assert(resolved.projected_screen_direction_px.is_equal_approx(projected_direction))


func _test_tile_space_quantization_boundaries() -> void:
	# Boundary between SE(index 7) and S(index 0) is 22.5 degrees in tile
	# space. Values immediately on either side must choose different sectors.
	var below_boundary := Vector2.from_angle(deg_to_rad(22.49))
	var above_boundary := Vector2.from_angle(deg_to_rad(22.51))
	assert(DirectionSpace.direction_index_for_ground_delta_gu(below_boundary) == 7)
	assert(DirectionSpace.direction_index_for_ground_delta_gu(above_boundary) == 0)
	for quarter_turn in range(4):
		var rotation := float(quarter_turn) * PI / 2.0
		var expected_below := posmod(7 + quarter_turn * 2, 8)
		var expected_above := posmod(quarter_turn * 2, 8)
		assert(
			DirectionSpace.direction_index_for_ground_delta_gu(
				below_boundary.rotated(rotation)
			) == expected_below
		)
		assert(
			DirectionSpace.direction_index_for_ground_delta_gu(
				above_boundary.rotated(rotation)
			) == expected_above
		)


func _test_phone_failure_coordinate_regression() -> void:
	var actor_tile := Vector2(19.92, 46.40)
	var target_tile := Vector2(19.37, 45.08)
	var measured_delta := target_tile - actor_tile
	assert(measured_delta.is_equal_approx(Vector2(-0.55, -1.32)))
	assert(Geometry.direction_index_for_ground_delta_gu(measured_delta) == 4)

	# The phone trace rounded the same sample to this delta. Keep it as an exact
	# regression because it previously selected screen direction 5 and rejected
	# thrust with lateral=0.56 (>0.50).
	var reported_delta := Vector2(-0.60, -1.20)
	var audit := Diagnostic.audit_ground_delta_gu(reported_delta)
	assert(audit.projected_screen_45_direction_index == 5)
	assert(audit.ground_space_45_direction_index == 4)
	assert(not audit.quantizers_match)
	assert(Geometry.direction_index_for_ground_delta_gu(reported_delta) == 4)
	var line := Geometry.line_coordinates(reported_delta, 4)
	assert(is_equal_approx(line.x, 1.2727922))
	assert(is_equal_approx(line.y, -0.4242641))
	assert(Geometry.thrust_slot(Vector2.ZERO, reported_delta, 4) == 1)

	var screen_delta_px := DirectionSpace.ground_delta_gu_to_screen_delta_px(reported_delta)
	assert(screen_delta_px.is_equal_approx(Vector2(19.2, -28.8)))
	var direction_result := DirectionSpace.resolve_screen_delta_px(screen_delta_px)
	assert(direction_result.direction_index == 4)
	assert(direction_result.canonical_grid_step == Vector2i(-1, -1))
	assert(direction_result.projected_screen_direction_px.is_equal_approx(Vector2.UP))
	assert(ArtSpec.direction_index(direction_result.projected_screen_direction_px) == 4)
	# Mir2 presentation mirrors direction rows; index 4 is the N visual and is
	# routed to the existing N source row 0 without changing presentation data.
	assert(ArtSpec.mir2_client_direction_row(direction_result.projected_screen_direction_px) == 0)

	var release := ReleaseGeometry.resolve(
		Vector2(100.0, 100.0),
		screen_delta_px,
		77,
		Vector2(-999.0, 999.0),
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	assert(release.direction_space_contract_id == DirectionSpace.CONTRACT_ID)
	assert(release.direction_index == 4)
	assert(release.visual_direction_index == 4)
	assert(release.direction_canonical_grid_step == Vector2i(-1, -1))
	assert(release.direction_screen_px.is_equal_approx(Vector2.UP))
	assert(release.direction_locked_for_action)


func _test_all_warrior_mode_direction_contracts() -> void:
	var origin := Vector2.ZERO
	var target := Vector2(-0.60, -1.20)
	var direction_index := Geometry.direction_index_for_ground_delta_gu(target - origin)
	assert(direction_index == 4)
	for mode: String in [Geometry.SKILL_NORMAL, Geometry.SKILL_FIRE]:
		assert(Geometry.is_single_target_in_reach(origin, target, mode))
		assert(Geometry.direction_index_for_ground_delta_gu(target - origin) == direction_index)
	assert(Geometry.is_in_half_moon_arc(origin, target, direction_index))
	assert(
		Geometry.half_moon_relative_sector(
			direction_index,
			Geometry.direction_index_for_ground_delta_gu(target - origin)
		) == 0
	)
	assert(Geometry.thrust_slot(origin, target, direction_index) == 1)

	# Existing range/width contracts remain exact; this fix changes only the
	# direction coordinate space.
	var forward_gu := Vector2(-1.0, -1.0).normalized()
	var side_gu := Vector2(-1.0, 1.0).normalized()
	assert(not Geometry.is_single_target_in_reach(
		origin, forward_gu * 1.5002, Geometry.SKILL_NORMAL
	))
	var lane_edge := forward_gu + side_gu * 0.5
	var outside_lane := forward_gu + side_gu * 0.5002
	assert(Geometry.thrust_slot(origin, lane_edge, 4) == 1)
	assert(Geometry.thrust_slot(origin, outside_lane, 4) == 0)
