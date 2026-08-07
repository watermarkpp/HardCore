extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_six_frames_and_angle_samples()
	_verify_twenty_repeated_casts()
	_verify_debug_overlay_is_explicit_and_reports_zero_error()
	_verify_runtime_has_no_image_readback()
	print(
		"WIZARD_LINE_FOOTPRINT_CORE_PASS: 5x1/8x1 GU damage and projected "
		+ "visual cores share one immutable snapshot"
	)
	get_tree().quit(0)


func _verify_six_frames_and_angle_samples() -> void:
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		var effect_length_gu := 5.0 if skill_id == "wizard.hellfire" else 8.0
		for sample_index: int in range(16):
			var plan := _line_plan(skill_id, effect_length_gu, sample_index)
			var snapshot: Dictionary = plan.skill_footprint_snapshot
			var expected_polygon_px := (
				Snapshot.projected_polygon_screen_offset_px(snapshot)
			)
			var effect := CasterSkillRuntime.create_visual(
				plan,
				Vector2.ZERO,
				(snapshot.axis_screen_offset_px as Vector2).normalized()
			)
			assert(effect != null)
			add_child(effect)
			assert(effect.formal_core_polygon_screen_offset_px() == expected_polygon_px)
			assert(effect._formal_core_polygon != null)
			assert(effect._formal_core_glow_layers.size() == 2)
			assert(
				effect.get_meta("formal_line_visual_core_contract", "")
				== CasterSkillVisualEffect.FORMAL_LINE_VISUAL_CORE_CONTRACT_ID
			)
			assert(not effect._sprites.is_empty())
			for raw_sprite: Sprite2D in effect._sprites:
				var expected_decoration_alpha := (
					CasterSkillVisualEffect.HELLFIRE_DECORATION_ALPHA
					if skill_id == "wizard.hellfire"
					else CasterSkillVisualEffect.LASER_DECORATION_ALPHA
				)
				assert(is_equal_approx(
					raw_sprite.modulate.a,
					expected_decoration_alpha
				))
				assert(raw_sprite.get_meta("formal_boundary_role", "")
					== "decoration_only")
			var primary_sprite := (
				effect._sprites[0] as CasterSkillAnimationPlayer
			)
			assert(primary_sprite.frame_count() == 6)
			for frame_index: int in range(6):
				assert(primary_sprite.set_manual_frame(frame_index))
				assert(
					effect.formal_core_polygon_screen_offset_px()
					== expected_polygon_px
				)
			effect.free()


func _verify_twenty_repeated_casts() -> void:
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		var effect_length_gu := 5.0 if skill_id == "wizard.hellfire" else 8.0
		var baseline_plan := _line_plan(skill_id, effect_length_gu, 7, "baseline")
		var expected_polygon_px := (
			Snapshot.projected_polygon_screen_offset_px(
				baseline_plan.skill_footprint_snapshot
			)
		)
		for repetition: int in range(20):
			var plan := _line_plan(
				skill_id,
				effect_length_gu,
				7,
				"repeat_%02d" % repetition
			)
			var effect := CasterSkillRuntime.create_visual(
				plan,
				Vector2.ZERO,
				(plan.skill_footprint_snapshot.axis_screen_offset_px as Vector2)
				.normalized()
			)
			assert(effect != null)
			add_child(effect)
			assert(effect.formal_core_polygon_screen_offset_px() == expected_polygon_px)
			effect.free()


func _verify_runtime_has_no_image_readback() -> void:
	for script_path: String in [
		"res://scripts/caster_skill_animation_player.gd",
		"res://scripts/caster_skill_visual_effect.gd",
	]:
		var source := FileAccess.get_file_as_string(script_path)
		assert(not source.contains("get_image("))
		assert(not source.contains("get_pixel("))


func _verify_debug_overlay_is_explicit_and_reports_zero_error() -> void:
	var production_plan := _line_plan("wizard.laser", 8.0, 5, "production")
	var direction_screen_px := (
		production_plan.skill_footprint_snapshot.axis_screen_offset_px as Vector2
	).normalized()
	var production_effect := CasterSkillRuntime.create_visual(
		production_plan,
		Vector2.ZERO,
		direction_screen_px
	)
	assert(production_effect != null)
	add_child(production_effect)
	assert(not production_effect.debug_skill_visual_geometry)
	assert(production_effect._debug_geometry_overlay == null)
	assert(production_effect._debug_geometry_lines.is_empty())
	assert(not production_effect.has_meta("snapshot_id"))
	var production_core_px := (
		production_effect.formal_core_polygon_screen_offset_px()
	)

	var debug_plan := _line_plan("wizard.laser", 8.0, 5, "debug")
	debug_plan["debug_skill_visual_geometry"] = true
	var debug_effect := CasterSkillRuntime.create_visual(
		debug_plan,
		Vector2.ZERO,
		direction_screen_px
	)
	assert(debug_effect != null)
	add_child(debug_effect)
	assert(debug_effect.debug_skill_visual_geometry)
	assert(debug_effect._debug_geometry_overlay != null)
	assert(debug_effect._debug_geometry_lines.size() == 4)
	assert(debug_effect.formal_core_polygon_screen_offset_px() == production_core_px)
	var metadata := debug_effect.skill_visual_geometry_debug_metadata()
	var snapshot: Dictionary = debug_plan.skill_footprint_snapshot
	assert(metadata.contract_id
		== CasterSkillVisualEffect.DEBUG_SKILL_VISUAL_GEOMETRY_CONTRACT_ID)
	assert(metadata.snapshot_id == snapshot.snapshot_id)
	assert(metadata.skill_id == snapshot.skill_id)
	assert(metadata.release_id == snapshot.release_id)
	assert(is_zero_approx(float(metadata.maximum_corner_error_px)))
	var corner_errors: PackedFloat32Array = (
		metadata.expected_actual_corner_error_px
	)
	assert(corner_errors.size() == 4)
	for error_px: float in corner_errors:
		assert(is_zero_approx(error_px))
	assert(debug_effect.get_meta("snapshot_id", "") == snapshot.snapshot_id)
	assert(debug_effect.get_meta("skill_id", "") == snapshot.skill_id)
	assert(debug_effect.get_meta("release_id", "") == snapshot.release_id)
	production_effect.free()
	debug_effect.free()


func _line_plan(
	skill_id: String,
	effect_length_gu: float,
	sample_index: int,
	release_suffix := "angle"
) -> Dictionary:
	var direction_ground_gu := Vector2.from_angle(
		TAU * float(sample_index) / 16.0
	)
	var strip := SpellGeometry.continuous_line_strip_ground_gu(
		Vector2.ZERO,
		direction_ground_gu,
		Vector2.RIGHT,
		effect_length_gu,
		1.0,
		skill_id,
		"core_%s_%02d_%s" % [skill_id, sample_index, release_suffix]
	)
	var screen_points_px := SpellGeometry.continuous_line_screen_points_px(
		strip,
		func(point_ground_gu: Vector2) -> Vector2:
			return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
				point_ground_gu
			)
	)
	# Q3-C: legacy the legacy resolver was removed; create_visual reads
	# the role from the frozen plan's registry profile.
	var plan := {
		"success": true,
		"skill_id": skill_id,
		"operation": "canonical_visual_only",
		"visual": CasterSkillVisualRegistry.profile(skill_id),
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
	}
	plan["canonical_geometry_contract"] = (
		SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
	)
	plan["geometry_origin_screen_px"] = Vector2.ZERO
	plan["geometry_grid_cells"] = []
	plan["geometry_screen_points_px"] = screen_points_px
	plan["skill_footprint_snapshot"] = strip.skill_footprint_snapshot
	return plan
