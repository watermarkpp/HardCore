extends Node

const ReleaseGeometry := preload("res://scripts/skills/combat_release_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const MeleeGeometry := preload("res://scripts/skills/warrior_melee_geometry.gd")

const TARGET_COMBAT_RADIUS_GU := 0.25


func _ready() -> void:
	_verify_continuous_lines_share_release_visual_and_damage_axis()
	_verify_thrust_far_segment_uses_release_footpoint()
	print(
		"COMBAT_FAR_ENDPOINT_ALIGNMENT_PASS: release footpoint, visual centerline, "
		+ "damage strip and melee footprint agree at formal far endpoints"
	)
	get_tree().quit(0)


func _verify_continuous_lines_share_release_visual_and_damage_axis() -> void:
	var origin_ground_gu := Vector2(19.92, 46.40)
	var origin_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		origin_ground_gu
	)
	for sample_index: int in range(16):
		var expected_direction_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 16.0
		)
		for skill_case: Dictionary in [
			{"skill_id": "wizard.hellfire", "length_gu": 5.0, "distance_gu": 4.5},
			{"skill_id": "wizard.laser", "length_gu": 8.0, "distance_gu": 7.5},
		]:
			var target_ground_gu := (
				origin_ground_gu
				+ expected_direction_ground_gu * float(skill_case.distance_gu)
			)
			var target_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
				target_ground_gu
			)
			# Deliberately supply the wrong input direction: a tracked line must use
			# the selected monster's live release-frame footpoint instead.
			var release := ReleaseGeometry.resolve(
				origin_screen_px,
				Vector2.LEFT,
				77,
				target_screen_px,
				true,
				true
			)
			assert((release.origin_ground_gu as Vector2).is_equal_approx(origin_ground_gu))
			assert((release.direction_ground_gu as Vector2).is_equal_approx(
				expected_direction_ground_gu
			))
			var strip := SpellGeometry.continuous_line_strip_ground_gu(
				release.origin_ground_gu,
				release.origin_ground_gu + release.direction_ground_gu,
				release.direction_screen_px,
				float(skill_case.length_gu),
				1.0
			)
			var relative_target := target_ground_gu - Vector2(strip.origin_ground_gu)
			var forward_gu := relative_target.dot(Vector2(strip.direction_ground_gu))
			var side_ground_gu := Vector2(
				-Vector2(strip.direction_ground_gu).y,
				Vector2(strip.direction_ground_gu).x
			)
			var lateral_gu := relative_target.dot(side_ground_gu)
			var remaining_to_end_gu := (
				Vector2(strip.strip_end_ground_gu) - target_ground_gu
			).dot(Vector2(strip.direction_ground_gu))
			var footprint := SpellGeometry.actor_footprint_polygon_ground_gu(
				target_ground_gu,
				TARGET_COMBAT_RADIUS_GU
			)
			assert(SpellGeometry.target_footprint_intersects_continuous_line_ground_gu(
				strip,
				footprint
			))
			var visual_points := SpellGeometry.continuous_line_screen_points_px(
				strip,
				func(point_ground_gu: Vector2) -> Vector2:
					return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
						point_ground_gu
					)
			)
			assert(not visual_points.is_empty())
			assert(visual_points.back().is_equal_approx(
				GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
					strip.strip_end_ground_gu
				)
			))
			assert(is_equal_approx(forward_gu, float(skill_case.distance_gu)))
			assert(is_zero_approx(lateral_gu))
			assert(is_equal_approx(
				remaining_to_end_gu,
				float(skill_case.length_gu) - float(skill_case.distance_gu)
			))


func _verify_thrust_far_segment_uses_release_footpoint() -> void:
	var origin_ground_gu := Vector2(19.92, 46.40)
	var origin_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		origin_ground_gu
	)
	for direction_index: int in range(8):
		var direction_ground_gu := MeleeGeometry.canonical_ground_direction_gu(
			direction_index
		)
		var direction_screen_px := DirectionSpace.ground_delta_gu_to_screen_delta_px(
			direction_ground_gu
		)
		for distance_gu: float in [2.0, 2.4]:
			var target_ground_gu := origin_ground_gu + direction_ground_gu * distance_gu
			var target_screen_px := GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
				target_ground_gu
			)
			var release := ReleaseGeometry.resolve(
				origin_screen_px,
				direction_screen_px,
				88,
				target_screen_px,
				true,
				true,
				ReleaseGeometry.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION
			)
			assert(release.direction_index == direction_index)
			assert((release.origin_ground_gu as Vector2).is_equal_approx(origin_ground_gu))
			assert(MeleeGeometry.thrust_footprint_slot_gu(
				release.origin_ground_gu,
				target_ground_gu,
				TARGET_COMBAT_RADIUS_GU,
				direction_index
			) == 2)
