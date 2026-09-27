extends "res://tests/wizard_line_presentation_alignment_test.gd"

## The existing envelope test remains intact and runs separately. This case
## verifies only the user-approved drawable translation and directional sort.
func _ready() -> void:
	assert(Loader.reload_data().valid)
	var checked_frames := 0
	for angle_deg: float in BASE_ANGLES_DEG + MIRROR_ANGLES_DEG:
		var plan := _line_plan("wizard.laser", 8.0, angle_deg)
		var original_snapshot: Dictionary = plan.skill_footprint_snapshot.duplicate(true)
		var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
		var axis := endpoint.normalized()
		var effect := CasterSkillRuntime.create_visual(plan, Vector2.ZERO, axis)
		assert(effect != null)
		add_child(effect)
		assert(effect.global_position.is_equal_approx(Vector2.ZERO))
		assert(effect.z_index == 0 and effect.y_sort_enabled)
		assert(effect._skill_footprint_snapshot == original_snapshot)
		assert(plan.skill_footprint_snapshot == original_snapshot)
		assert(effect._sprites.size() == 1)
		var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
		assert(sprite != null and sprite.frame_count() == 6)
		assert(sprite.get_parent().name == "LaserChestVisual")
		var expected_sort_y := 0.01 if axis.y >= 0.0 else -0.01
		assert(absf(effect._visual_sort_proxy.global_position.y - expected_sort_y) < 0.001)
		assert(effect._formal_core_polygon != null)
		for polygon: Polygon2D in effect._formal_core_polygons:
			assert(polygon.global_position.distance_to(Vector2(0.0, -28.0)) < 0.02)
		for glow: Polygon2D in effect._formal_core_glow_layers:
			assert(glow.global_position.distance_to(Vector2(0.0, -28.0)) < 0.02)
		for frame_index: int in range(sprite.frame_count()):
			assert(sprite.set_manual_frame(frame_index))
			assert(sprite.global_position.distance_to(Vector2(0.0, -28.0)) < 0.02)
			var visible_axis := sprite.transform.basis_xform(sprite._source_axis_local).normalized()
			assert(absf(rad_to_deg(visible_axis.angle_to(axis))) <= MAX_AXIS_ERROR_DEG)
			checked_frames += 1
		effect.free()
	assert(checked_frames == 126)
	print("LASER_CHEST_TRANSLATION_PASS angles=21 frames=126 lift_px=28 range_unchanged=true")
	get_tree().quit(0)
