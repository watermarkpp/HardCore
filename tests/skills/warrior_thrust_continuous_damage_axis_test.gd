extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")

const TARGET_RADIUS_GU := 0.25


func _ready() -> void:
	_verify_all_eight_visual_axes_are_exactly_snapped()
	_verify_inclusive_range_and_width_thresholds()
	_verify_release_snapshot_is_reused_by_validation()
	print(
		"WARRIOR_THRUST_SNAPPED_DAMAGE_AXIS_PASS: eight long_hit visual axes "
		+ "own the immutable 2.5x1 GU damage snapshot"
	)
	get_tree().quit(0)


func _verify_all_eight_visual_axes_are_exactly_snapped() -> void:
	var origin_ground_gu := Vector2(19.92, 46.40)
	for visual_direction_index: int in range(8):
		var canonical_axis_ground_gu := Geometry.canonical_ground_direction_gu(
			visual_direction_index
		)
		# A live target near the edge of the same visual sector must not bend the
		# damage axis away from the eight-direction long_hit source animation.
		var off_axis_target_ground_gu := (
			origin_ground_gu
			+ canonical_axis_ground_gu.rotated(deg_to_rad(22.0)) * 2.4
		)
		var release_geometry := _locked_release_geometry(
			origin_ground_gu,
			off_axis_target_ground_gu,
			visual_direction_index,
			1000 + visual_direction_index
		)
		var plan := Geometry.thrust_damage_axis_plan_ground_gu(
			visual_direction_index,
			release_geometry
		)
		assert(
			plan.contract_id
			== Geometry.THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID
		)
		assert(not plan.uses_live_locked_target_axis)
		assert(plan.damage_axis_source == "canonical_visual_direction_snapped")
		assert((plan.damage_direction_ground_gu as Vector2).is_equal_approx(
			canonical_axis_ground_gu
		))
		var snapshot: Dictionary = plan.skill_footprint_snapshot
		assert(Snapshot.has_legacy_base_contract(snapshot))
		assert(snapshot.is_read_only())
		assert(snapshot.shape_type == Snapshot.SHAPE_DIRECTED_RECTANGLE)
		assert((snapshot.direction_ground_gu as Vector2).is_equal_approx(
			canonical_axis_ground_gu
		))
		assert(is_equal_approx(float(snapshot.effect_length_gu), 2.5))
		assert(is_equal_approx(float(snapshot.effect_width_gu), 1.0))


func _verify_inclusive_range_and_width_thresholds() -> void:
	var origin_ground_gu := Vector2.ZERO
	for visual_direction_index: int in range(8):
		var axis_ground_gu := Geometry.canonical_ground_direction_gu(
			visual_direction_index
		)
		var side_ground_gu := Vector2(-axis_ground_gu.y, axis_ground_gu.x)
		var plan := Geometry.thrust_damage_axis_plan_ground_gu(
			visual_direction_index,
			_locked_release_geometry(
				origin_ground_gu,
				origin_ground_gu + axis_ground_gu,
				visual_direction_index,
				2000 + visual_direction_index
			)
		)
		for lateral_center_gu: float in [0.749, 0.750]:
			assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
				origin_ground_gu,
				origin_ground_gu + axis_ground_gu * 2.0
				+ side_ground_gu * lateral_center_gu,
				TARGET_RADIUS_GU,
				plan
			) == 2)
		assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
			origin_ground_gu,
			origin_ground_gu + axis_ground_gu * 2.0 + side_ground_gu * 0.751,
			TARGET_RADIUS_GU,
			plan
		) == 0)
		for forward_center_gu: float in [2.749, 2.750]:
			assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
				origin_ground_gu,
				origin_ground_gu + axis_ground_gu * forward_center_gu,
				TARGET_RADIUS_GU,
				plan
			) == 2)
		assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
			origin_ground_gu,
			origin_ground_gu + axis_ground_gu * 2.751,
			TARGET_RADIUS_GU,
			plan
		) == 0)


func _verify_release_snapshot_is_reused_by_validation() -> void:
	var release_geometry := _locked_release_geometry(
		Vector2.ZERO,
		Vector2(0.0, 2.0),
		1,
		991
	)
	var plan := Geometry.thrust_damage_axis_plan_ground_gu(1, release_geometry)
	var snapshot: Dictionary = plan.skill_footprint_snapshot
	var polygon_before := Snapshot.ground_polygon_gu(snapshot)
	for repetition: int in range(20):
		assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
			Vector2.ZERO,
			(plan.damage_direction_ground_gu as Vector2) * 2.0,
			TARGET_RADIUS_GU,
			plan
		) == 2)
		assert(Snapshot.ground_polygon_gu(snapshot) == polygon_before)


func _locked_release_geometry(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	visual_direction_index: int,
	locked_target_instance_id: int
) -> Dictionary:
	var origin_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		origin_ground_gu
	)
	var target_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		target_ground_gu
	)
	var input_direction_screen_px := (
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			Geometry.canonical_ground_direction_gu(visual_direction_index)
		)
	)
	var release_geometry := ReleaseGeometry.resolve(
		origin_screen_px,
		input_direction_screen_px,
		locked_target_instance_id,
		target_screen_px,
		true,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
	release_geometry["release_id"] = "test_action_%d" % locked_target_instance_id
	return release_geometry
