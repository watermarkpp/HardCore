extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")

const VISUAL_DIRECTION_INDEX := 7
const TARGET_RADIUS_GU := 0.25
const SAME_SECTOR_OFFSET_RADIANS := deg_to_rad(22.0)


func _ready() -> void:
	_verify_near_far_same_angle_regression()
	_verify_all_visual_directions_and_sector_boundaries()
	_verify_invalid_or_missing_lock_falls_back()
	_verify_formal_range_and_width_are_unchanged()
	print(
		"WARRIOR_THRUST_CONTINUOUS_DAMAGE_AXIS_PASS: same-sector locked target "
		+ "uses one continuous 2.5x1 GU band; visual direction and fallbacks stay 8-way"
	)
	get_tree().quit(0)


func _verify_near_far_same_angle_regression() -> void:
	var origin_ground_gu := Vector2(19.92, 46.40)
	var canonical_axis := Geometry.canonical_ground_direction_gu(
		VISUAL_DIRECTION_INDEX
	)
	var live_axis := canonical_axis.rotated(SAME_SECTOR_OFFSET_RADIANS)
	assert(
		DirectionSpace.direction_index_for_ground_delta_gu(live_axis)
		== VISUAL_DIRECTION_INDEX
	)
	var near_target_ground_gu := origin_ground_gu + live_axis * 1.0
	var far_target_ground_gu := origin_ground_gu + live_axis * 2.4
	var side := Vector2(-canonical_axis.y, canonical_axis.x)
	assert(is_equal_approx(
		(near_target_ground_gu - origin_ground_gu).dot(side),
		sin(SAME_SECTOR_OFFSET_RADIANS)
	))
	assert(is_equal_approx(
		(far_target_ground_gu - origin_ground_gu).dot(side),
		2.4 * sin(SAME_SECTOR_OFFSET_RADIANS)
	))
	# The old eight-way centreline still touches the near footprint but loses the
	# same locked target at 2.4 GU because lateral error grows with distance.
	assert(Geometry.thrust_footprint_slot_gu(
		origin_ground_gu,
		near_target_ground_gu,
		TARGET_RADIUS_GU,
		VISUAL_DIRECTION_INDEX
	) == 1)
	assert(Geometry.thrust_footprint_slot_gu(
		origin_ground_gu,
		far_target_ground_gu,
		TARGET_RADIUS_GU,
		VISUAL_DIRECTION_INDEX
	) == 0)

	var release_geometry := _locked_release_geometry(
		origin_ground_gu,
		far_target_ground_gu,
		VISUAL_DIRECTION_INDEX,
		991,
		true
	)
	assert(release_geometry.direction_index == VISUAL_DIRECTION_INDEX)
	assert(release_geometry.visual_direction_index == VISUAL_DIRECTION_INDEX)
	assert(
		release_geometry.live_locked_target_axis_contract_id
		== ReleaseGeometry.LIVE_LOCKED_TARGET_AXIS_CONTRACT_ID
	)
	assert((release_geometry.live_locked_target_direction_ground_gu as Vector2)
		.is_equal_approx(live_axis))
	var plan := Geometry.thrust_damage_axis_plan_ground_gu(
		VISUAL_DIRECTION_INDEX,
		release_geometry
	)
	assert(
		plan.contract_id
		== Geometry.THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID
	)
	assert(plan.uses_live_locked_target_axis)
	assert(plan.damage_axis_source == "live_locked_target_same_visual_sector")
	assert((plan.damage_direction_ground_gu as Vector2).is_equal_approx(live_axis))
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		origin_ground_gu,
		near_target_ground_gu,
		TARGET_RADIUS_GU,
		plan
	) == 1)
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		origin_ground_gu,
		far_target_ground_gu,
		TARGET_RADIUS_GU,
		plan
	) == 2)

	# The plan is action-wide, not a special-case hit for the locked monster.
	# Every other candidate is tested against the same continuous strip.
	var non_locked_first_segment := origin_ground_gu + live_axis * 1.2
	var non_locked_second_segment := origin_ground_gu + live_axis * 2.0
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		origin_ground_gu,
		non_locked_first_segment,
		TARGET_RADIUS_GU,
		plan
	) == 1)
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		origin_ground_gu,
		non_locked_second_segment,
		TARGET_RADIUS_GU,
		plan
	) == 2)
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		origin_ground_gu,
		origin_ground_gu + canonical_axis * 2.4,
		TARGET_RADIUS_GU,
		plan
	) == 0)


func _verify_all_visual_directions_and_sector_boundaries() -> void:
	var origin_ground_gu := Vector2(-7.25, 13.75)
	for visual_direction_index: int in range(8):
		var canonical_axis := Geometry.canonical_ground_direction_gu(
			visual_direction_index
		)
		var same_sector_axis := canonical_axis.rotated(deg_to_rad(22.0))
		var crossed_sector_axis := canonical_axis.rotated(deg_to_rad(23.0))
		assert(
			DirectionSpace.direction_index_for_ground_delta_gu(same_sector_axis)
			== visual_direction_index
		)
		assert(
			DirectionSpace.direction_index_for_ground_delta_gu(crossed_sector_axis)
			!= visual_direction_index
		)
		var same_sector_release := _locked_release_geometry(
			origin_ground_gu,
			origin_ground_gu + same_sector_axis * 2.4,
			visual_direction_index,
			1000 + visual_direction_index,
			true
		)
		var same_sector_plan := Geometry.thrust_damage_axis_plan_ground_gu(
			visual_direction_index,
			same_sector_release
		)
		assert(same_sector_plan.visual_direction_index == visual_direction_index)
		assert(same_sector_plan.uses_live_locked_target_axis)
		assert((same_sector_plan.damage_direction_ground_gu as Vector2)
			.is_equal_approx(same_sector_axis))

		var crossed_release := _locked_release_geometry(
			origin_ground_gu,
			origin_ground_gu + crossed_sector_axis * 2.4,
			visual_direction_index,
			2000 + visual_direction_index,
			true
		)
		var crossed_plan := Geometry.thrust_damage_axis_plan_ground_gu(
			visual_direction_index,
			crossed_release
		)
		assert(not crossed_plan.uses_live_locked_target_axis)
		assert(crossed_plan.fallback_reason == "locked_target_crossed_visual_direction")
		assert((crossed_plan.damage_direction_ground_gu as Vector2)
			.is_equal_approx(canonical_axis))


func _verify_invalid_or_missing_lock_falls_back() -> void:
	var origin_ground_gu := Vector2.ZERO
	var canonical_axis := Geometry.canonical_ground_direction_gu(
		VISUAL_DIRECTION_INDEX
	)
	var no_lock_release := _locked_release_geometry(
		origin_ground_gu,
		Vector2.ZERO,
		VISUAL_DIRECTION_INDEX,
		0,
		false
	)
	var no_lock_plan := Geometry.thrust_damage_axis_plan_ground_gu(
		VISUAL_DIRECTION_INDEX,
		no_lock_release
	)
	assert(not no_lock_plan.uses_live_locked_target_axis)
	assert(no_lock_plan.fallback_reason == "no_valid_locked_target_axis")
	assert((no_lock_plan.damage_direction_ground_gu as Vector2)
		.is_equal_approx(canonical_axis))

	var invalid_lock_release := _locked_release_geometry(
		origin_ground_gu,
		origin_ground_gu + canonical_axis.rotated(deg_to_rad(20.0)) * 2.4,
		VISUAL_DIRECTION_INDEX,
		77,
		false
	)
	var invalid_lock_plan := Geometry.thrust_damage_axis_plan_ground_gu(
		VISUAL_DIRECTION_INDEX,
		invalid_lock_release
	)
	assert(not invalid_lock_plan.uses_live_locked_target_axis)
	assert((invalid_lock_plan.damage_direction_ground_gu as Vector2)
		.is_equal_approx(canonical_axis))


func _verify_formal_range_and_width_are_unchanged() -> void:
	var release_geometry := _locked_release_geometry(
		Vector2.ZERO,
		Vector2.from_angle(SAME_SECTOR_OFFSET_RADIANS) * 2.4,
		VISUAL_DIRECTION_INDEX,
		500,
		true
	)
	var plan := Geometry.thrust_damage_axis_plan_ground_gu(
		VISUAL_DIRECTION_INDEX,
		release_geometry
	)
	assert(is_equal_approx(float(plan.effect_length_gu), 2.5))
	assert(is_equal_approx(float(plan.effect_width_gu), 1.0))
	assert(is_equal_approx(float(plan.primary_segment_end_gu), 1.5))
	var axis: Vector2 = plan.damage_direction_ground_gu
	var side := Vector2(-axis.y, axis.x)
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		Vector2.ZERO,
		axis * 2.751,
		TARGET_RADIUS_GU,
		plan
	) == 0)
	assert(Geometry.thrust_footprint_slot_for_axis_plan_gu(
		Vector2.ZERO,
		axis * 1.0 + side * 0.751,
		TARGET_RADIUS_GU,
		plan
	) == 0)


func _locked_release_geometry(
	origin_ground_gu: Vector2,
	target_ground_gu: Vector2,
	visual_direction_index: int,
	locked_target_instance_id: int,
	locked_target_valid: bool
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
	return ReleaseGeometry.resolve(
		origin_screen_px,
		input_direction_screen_px,
		locked_target_instance_id,
		target_screen_px,
		locked_target_valid,
		true,
		ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
	)
