extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")

const BASE_ANGLES_DEG: Array[float] = [
	0.0, 11.0, 13.0, 22.5, 27.0, 30.0, 38.0, 45.0,
	53.0, 60.0, 67.5, 71.0, 80.0, 90.0, 103.0, 147.0,
]
const MIRROR_ANGLES_DEG: Array[float] = [191.0, 210.0, 233.0, 260.0, 327.0]
const MAX_AXIS_ERROR_DEG := 1.0
const MAX_GROUND_ERROR_GU := 0.10
const EPSILON_PX := 0.02


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_hellfire_arbitrary_angle_anchor_alignment()
	_verify_laser_arbitrary_angle_visible_envelope_alignment()
	print(
		"WIZARD_LINE_PRESENTATION_ALIGNMENT_PASS: canonical arbitrary-angle "
		+ "Hellfire anchors and Laser visible alpha envelopes aligned"
	)
	get_tree().quit(0)


func _verify_hellfire_arbitrary_angle_anchor_alignment() -> void:
	for angle_deg: float in BASE_ANGLES_DEG + MIRROR_ANGLES_DEG:
		var plan := _line_plan("wizard.hellfire", 5.0, angle_deg)
		var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
		var effect := CasterSkillRuntime.create_visual(
			plan, Vector2.ZERO, endpoint.normalized()
		)
		assert(effect != null)
		add_child(effect)
		assert(effect._hellfire_emission_offsets.size() > 0)
		assert(effect._hellfire_emission_offsets.back().is_equal_approx(endpoint))
		assert(effect._sprites.size() > 0)
		var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
		assert(sprite != null)
		assert(sprite._anchor_policy == "center_sequence_bounds_on_geometry_origin")
		for frame_index: int in range(sprite.frame_count()):
			assert(sprite.set_manual_frame(frame_index))
			var center_screen_px := _visible_envelope_center_screen_px(sprite)
			var ground_error := (
				GroundUnitSpace.screen_delta_px_to_ground_delta_gu(center_screen_px)
			)
			var ground_axis := Vector2.from_angle(deg_to_rad(angle_deg))
			var ground_cross := Vector2(-ground_axis.y, ground_axis.x)
			var longitudinal_gu := absf(ground_error.dot(ground_axis))
			var lateral_gu := absf(ground_error.dot(ground_cross))
			_print_evidence(
				"wizard.hellfire", angle_deg, frame_index, 0.0,
				longitudinal_gu, longitudinal_gu, lateral_gu
			)
			assert(longitudinal_gu <= MAX_GROUND_ERROR_GU)
			assert(lateral_gu <= MAX_GROUND_ERROR_GU)
		effect.free()


func _verify_laser_arbitrary_angle_visible_envelope_alignment() -> void:
	for angle_deg: float in BASE_ANGLES_DEG + MIRROR_ANGLES_DEG:
		var plan := _line_plan("wizard.laser", 8.0, angle_deg)
		var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
		var target_axis := endpoint.normalized()
		var target_cross := Vector2(-target_axis.y, target_axis.x)
		var effect := CasterSkillRuntime.create_visual(
			plan, Vector2.ZERO, target_axis
		)
		assert(effect != null)
		add_child(effect)
		assert(effect._sprites.size() == 1)
		var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
		assert(sprite != null)
		for frame_index: int in range(sprite.frame_count()):
			assert(sprite.set_manual_frame(frame_index))
			var visible := _visible_projection_intervals(
				sprite, target_axis, target_cross
			)
			var transformed_source_axis := sprite.transform.basis_xform(
				sprite._source_axis_local
			).normalized()
			var axis_error_deg := absf(rad_to_deg(
				transformed_source_axis.angle_to(target_axis)
			))
			var start_error_px := absf(float(visible.axis_minimum))
			var end_error_px := absf(
				float(visible.axis_maximum) - endpoint.length()
			)
			var cross_center_px := 0.5 * (
				float(visible.cross_minimum) + float(visible.cross_maximum)
			)
			var start_error_gu := _screen_axis_error_to_ground_gu(
				target_axis, start_error_px
			)
			var end_error_gu := _screen_axis_error_to_ground_gu(
				target_axis, end_error_px
			)
			var lateral_error_gu := _screen_axis_error_to_ground_gu(
				target_cross, absf(cross_center_px)
			)
			_print_evidence(
				"wizard.laser", angle_deg, frame_index, axis_error_deg,
				start_error_gu, end_error_gu, lateral_error_gu
			)
			assert(axis_error_deg <= MAX_AXIS_ERROR_DEG)
			assert(start_error_gu <= MAX_GROUND_ERROR_GU)
			assert(end_error_gu <= MAX_GROUND_ERROR_GU)
			assert(lateral_error_gu <= MAX_GROUND_ERROR_GU)
			assert(start_error_px <= EPSILON_PX)
			assert(end_error_px <= EPSILON_PX)
		effect.free()


func _visible_envelope_center_screen_px(
	sprite: CasterSkillAnimationPlayer
) -> Vector2:
	var image := sprite.texture.get_image()
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	var half_texture := Vector2(
		float(image.get_width()) * 0.5,
		float(image.get_height()) * 0.5
	)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var local_center := (
				sprite.offset
				+ Vector2(float(x) + 0.5, float(y) + 0.5)
				- half_texture
			)
			var screen_center := sprite.transform.basis_xform(local_center)
			minimum = minimum.min(screen_center)
			maximum = maximum.max(screen_center)
	assert(is_finite(minimum.x) and is_finite(maximum.x))
	return 0.5 * (minimum + maximum)


func _visible_projection_intervals(
	sprite: CasterSkillAnimationPlayer,
	axis: Vector2,
	cross: Vector2
) -> Dictionary:
	var image := sprite.texture.get_image()
	var axis_minimum := INF
	var axis_maximum := -INF
	var cross_minimum := INF
	var cross_maximum := -INF
	var half_texture := Vector2(
		float(image.get_width()) * 0.5,
		float(image.get_height()) * 0.5
	)
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var local_center := (
				sprite.offset
				+ Vector2(float(x) + 0.5, float(y) + 0.5)
				- half_texture
			)
			var screen_center := sprite.transform.basis_xform(local_center)
			var axis_projection := screen_center.dot(axis)
			var cross_projection := screen_center.dot(cross)
			axis_minimum = minf(axis_minimum, axis_projection)
			axis_maximum = maxf(axis_maximum, axis_projection)
			cross_minimum = minf(cross_minimum, cross_projection)
			cross_maximum = maxf(cross_maximum, cross_projection)
	assert(is_finite(axis_minimum) and is_finite(axis_maximum))
	var axis_support := 0.5 * (
		absf(sprite.transform.x.dot(axis))
		+ absf(sprite.transform.y.dot(axis))
	)
	var cross_support := 0.5 * (
		absf(sprite.transform.x.dot(cross))
		+ absf(sprite.transform.y.dot(cross))
	)
	return {
		"axis_minimum": axis_minimum - axis_support,
		"axis_maximum": axis_maximum + axis_support,
		"cross_minimum": cross_minimum - cross_support,
		"cross_maximum": cross_maximum + cross_support,
	}


func _screen_axis_error_to_ground_gu(
	screen_axis: Vector2,
	error_px: float
) -> float:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
		screen_axis.normalized() * error_px
	).length()


func _print_evidence(
	skill_id: String,
	angle_deg: float,
	frame_index: int,
	axis_error_deg: float,
	start_error_gu: float,
	end_error_gu: float,
	lateral_error_gu: float
) -> void:
	var evidence_line := (
		"WIZARD_LINE_PRESENTATION_SAMPLE skill=%s angle_deg=%.1f frame=%d "
		+ "axis_error_deg=%.6f start_error_gu=%.6f end_error_gu=%.6f "
		+ "lateral_error_gu=%.6f"
	) % [
			skill_id, angle_deg, frame_index, axis_error_deg,
			start_error_gu, end_error_gu, lateral_error_gu,
	]
	print(evidence_line)


func _line_plan(
	skill_id: String,
	length_tiles: float,
	angle_deg: float
) -> Dictionary:
	var ground_aim := Vector2.from_angle(deg_to_rad(angle_deg))
	var release_id := "presentation_%s_%s" % [
		skill_id, str(angle_deg).replace(".", "_")
	]
	var coordinate_context := Snapshot.make_absolute_runtime_context(
		9201,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)
	var strip := SpellGeometry.continuous_line_strip_ground_gu(
		Vector2.ZERO,
		ground_aim,
		Vector2.RIGHT,
		length_tiles,
		1.0,
		skill_id,
		release_id,
		length_tiles,
		length_tiles,
		"",
		coordinate_context
	)
	var world_points := SpellGeometry.continuous_line_screen_points_px(
		strip,
		func(tile: Vector2) -> Vector2:
			return DirectionSpace.ground_delta_gu_to_screen_delta_px(tile)
	)
	var plan := {
		"contract": "skill_execution_plan.v1",
		"release_id": release_id,
		"skill_id": skill_id,
		"canonical_snapshot": strip.skill_footprint_snapshot,
		"success": true,
		"operation": "canonical_visual_only",
		"visual": CasterSkillVisualRegistry.profile(skill_id),
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
		"gameplay_actions": [],
		"projectile_descriptors": [],
		"ground_effect_descriptors": [],
		"summon_descriptors": [],
		"canonical_geometry_contract": (
			SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
		),
		"geometry_origin_screen_px": Vector2.ZERO,
		"geometry_grid_cells": [],
		"geometry_screen_points_px": world_points,
		"skill_footprint_snapshot": strip.skill_footprint_snapshot,
		"snapshot_validation_context": coordinate_context,
	}
	plan["presentation_actions"] = [{
		"type": "visual",
		"skill_id": skill_id,
		"role": CasterSkillVisualRegistry.ROLE_LINE_EFFECT,
		"phase": "",
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
		"canonical_geometry_contract": (
			SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
		),
		"geometry_origin_screen_px": Vector2.ZERO,
		"target_position_screen_px": Vector2.ZERO,
		"geometry_grid_cells": [],
		"geometry_screen_points_px": world_points,
		"ground_gu_to_screen_position_px": Callable(),
		"snapshot_validation_context": coordinate_context,
	}]
	return plan


func _ground_to_screen(value: Vector2) -> Vector2:
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(value)
