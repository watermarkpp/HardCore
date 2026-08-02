extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_hellfire_fixed_source_pixels()
	_verify_laser_target_distance_direction_and_replay_stability()
	print(
		"WIZARD_LINE_VISUAL_STABILITY_PASS: hellfire fixed source nodes, "
		+ "laser 16-way fixed 8x1 longitudinal envelope, 96 alpha-normalized "
		+ "cross envelopes, target-distance independence and single active visual"
	)
	get_tree().quit(0)


func _verify_hellfire_fixed_source_pixels() -> void:
	for sample_index: int in range(16):
		var effect := _create_line_effect(
			"wizard.hellfire", 5.0, sample_index, Vector2(1400.0, -900.0)
		)
		assert(effect != null)
		add_child(effect)
		assert(effect._hellfire_emission_offsets.size() > 0)
		assert(effect._hellfire_emission_offsets.back().is_equal_approx(
			effect._geometry_world_offsets.back()
		))
		assert(is_zero_approx(effect._desired_sprite_axis_extent))
		assert(is_zero_approx(effect._desired_sprite_cross_axis_extent))
		for raw_sprite: Sprite2D in effect._sprites:
			var sprite := raw_sprite as CasterSkillAnimationPlayer
			assert(_transform_basis_equal(
				sprite.transform, Transform2D.IDENTITY
			))
		effect.free()


func _verify_laser_target_distance_direction_and_replay_stability() -> void:
	var owner := PlayerCharacter.new()
	add_child(owner)
	for sample_index: int in range(16):
		var plan := _line_plan("wizard.laser", 8.0, sample_index)
		var endpoint: Vector2 = (
			plan.geometry_world_points as Array
		).back()
		var aim_axis := endpoint.normalized()
		var close_effect := _visual_from_cast_nodes(
			plan, aim_axis * 24.0, aim_axis, owner
		)
		assert(close_effect != null)
		add_child(close_effect)
		var close_sprite := close_effect._sprites[0] as CasterSkillAnimationPlayer
		assert(close_sprite != null)
		var expected_transform := close_sprite.transform
		var expected_bounds := close_sprite.fitted_visual_bounds()
		assert(is_equal_approx(
			close_sprite.fitted_visual_forward_extent(aim_axis),
			endpoint.length()
		))
		assert(is_equal_approx(
			close_sprite.current_frame_visible_cross_extent(aim_axis),
			close_effect._desired_sprite_cross_axis_extent
		))

		# Target distance is deliberately changed by two orders of magnitude while
		# the authoritative 8x1 geometry remains identical.
		var far_effect := _visual_from_cast_nodes(
			plan, aim_axis * 2400.0, aim_axis, owner
		)
		assert(far_effect != null)
		add_child(far_effect)
		var far_sprite := far_effect._sprites[0] as CasterSkillAnimationPlayer
		assert(far_sprite.transform.is_equal_approx(expected_transform))
		_assert_rect_equal(far_sprite.fitted_visual_bounds(), expected_bounds)
		assert(not close_effect.visible)

		# All six primary frames retain one longitudinal transform. Their cross
		# scales differ only enough to normalize each formal alpha envelope.
		var expected_longitudinal := far_sprite.transform.basis_xform(
			far_sprite._source_axis_local
		)
		for frame_index: int in range(far_sprite.frame_count()):
			assert(far_sprite.set_manual_frame(frame_index))
			var declared_alpha_extent := float(
				far_sprite._frames[frame_index].get(
					"visible_cross_extent_pixels", 0.0
				)
			)
			assert(declared_alpha_extent > 0.0)
			assert(is_equal_approx(
				declared_alpha_extent,
				_texture_visible_cross_extent(
					far_sprite.texture,
					far_sprite._source_cross_axis_local
				),
			))
			assert(far_sprite.transform.basis_xform(
				far_sprite._source_axis_local
			).is_equal_approx(expected_longitudinal))
			assert(is_equal_approx(
				far_sprite.current_frame_visible_cross_extent(aim_axis),
				far_effect._desired_sprite_cross_axis_extent
			))
		assert(far_sprite.configure(
			"wizard.laser",
			aim_axis,
			far_effect._desired_sprite_extent,
			null,
			"",
			far_effect._desired_sprite_footprint,
			far_effect._desired_sprite_axis_extent,
			far_effect._visual_axis_world,
			far_effect._desired_sprite_cross_axis_extent
		))
		assert(far_sprite.transform.is_equal_approx(expected_transform))

		if is_instance_valid(close_effect):
			close_effect.free()
		if is_instance_valid(far_effect):
			far_effect.free()
	owner.free()


func _texture_visible_cross_extent(
	frame_texture: Texture2D,
	cross_axis: Vector2
) -> float:
	var image := frame_texture.get_image()
	var minimum := INF
	var maximum := -INF
	for y: int in range(image.get_height()):
		for x: int in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var projection := Vector2(
				float(x) + 0.5, float(y) + 0.5
			).dot(cross_axis)
			minimum = minf(minimum, projection)
			maximum = maxf(maximum, projection)
	assert(is_finite(minimum) and is_finite(maximum))
	return (
		maximum - minimum
		+ absf(cross_axis.x)
		+ absf(cross_axis.y)
	)


func _visual_from_cast_nodes(
	plan: Dictionary,
	target_position: Vector2,
	direction: Vector2,
	owner: PlayerCharacter
) -> CasterSkillVisualEffect:
	var nodes := CasterSkillRuntime.create_cast_nodes(
		plan,
		Vector2.ZERO,
		target_position,
		direction,
		Color.WHITE,
		null,
		owner
	)
	for node: Node2D in nodes:
		if node is CasterSkillVisualEffect:
			return node
	return null


func _create_line_effect(
	skill_id: String,
	length_tiles: float,
	sample_index: int,
	target_position: Vector2
) -> CasterSkillVisualEffect:
	var plan := _line_plan(skill_id, length_tiles, sample_index)
	var endpoint: Vector2 = (plan.geometry_world_points as Array).back()
	# create_visual intentionally has no target-position input. Keep this
	# parameter to document that an arbitrarily distant target cannot affect the
	# geometry-owned visual size.
	assert(target_position.length() > endpoint.length())
	return CasterSkillRuntime.create_visual(
		plan, Vector2.ZERO, endpoint.normalized()
	)


func _line_plan(
	skill_id: String,
	length_tiles: float,
	sample_index: int
) -> Dictionary:
	var tile_aim := Vector2.from_angle(TAU * float(sample_index) / 16.0)
	var strip := SpellGeometry.continuous_line_strip(
		Vector2.ZERO,
		tile_aim,
		Vector2.RIGHT,
		length_tiles,
		1.0
	)
	var world_points := SpellGeometry.continuous_line_world_points(
		strip,
		func(tile: Vector2) -> Vector2:
			return DirectionSpace.fractional_tile_delta_to_world_delta(tile)
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
	plan["canonical_geometry_contract"] = SpellGeometry.CONTRACT_ID
	plan["geometry_origin_world"] = Vector2.ZERO
	plan["geometry_tile_points"] = []
	plan["geometry_world_points"] = world_points
	return plan


func _assert_rect_equal(left: Rect2, right: Rect2) -> void:
	assert(left.position.is_equal_approx(right.position))
	assert(left.size.is_equal_approx(right.size))


func _transform_basis_equal(left: Transform2D, right: Transform2D) -> bool:
	return (
		left.x.is_equal_approx(right.x)
		and left.y.is_equal_approx(right.y)
	)
