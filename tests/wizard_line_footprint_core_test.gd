extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_six_frames_and_angle_samples()
	_verify_twenty_repeated_casts()
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
	var plan := CasterSkillRuntime.resolve(skill_id, {
		"skill_level": 3,
		"caster_level": 40,
		"owner_level": 40,
		"target_level": 20,
		"target_max_hp": 500,
		"magic_stat_roll": 30,
		"random_0_to_10": 0,
	})
	plan["canonical_geometry_contract"] = (
		SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
	)
	plan["geometry_origin_screen_px"] = Vector2.ZERO
	plan["geometry_grid_cells"] = []
	plan["geometry_screen_points_px"] = screen_points_px
	plan["skill_footprint_snapshot"] = strip.skill_footprint_snapshot
	return plan
