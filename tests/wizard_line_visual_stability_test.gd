extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_hellfire_fixed_source_pixels()
	_verify_laser_target_distance_direction_and_replay_stability()
	_verify_east_west_no_extra_stretch()
	print(
		"WIZARD_LINE_VISUAL_STABILITY_PASS: hellfire fixed source nodes, "
		+ "laser 16-way fixed 8x1 longitudinal envelope, 96 alpha-normalized "
		+ "cross envelopes, target-distance independence and geometry binding"
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
			effect._geometry_screen_offsets_px.back()
		))
		assert(is_zero_approx(effect._desired_sprite_axis_extent_px))
		assert(is_zero_approx(effect._desired_sprite_cross_axis_extent_px))
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
			plan.geometry_screen_points_px as Array
		).back()
		var aim_axis := endpoint.normalized()
		var close_effect := _visual_from_cast_nodes(
			plan, aim_axis * 24.0, aim_axis, owner
		)
		assert(close_effect != null)
		add_child(close_effect)
		var close_sprite := close_effect._sprites[0] as CasterSkillAnimationPlayer
		assert(close_sprite != null)
		assert(close_sprite.frame_count() == 6 and not close_sprite._loop)
		close_sprite.set_manual_frame(0)
		# FREEZE-G0: the beam visual is geometry-binding driven. Its length must
		# bind to the canonical snapshot's projected endpoint (never the legacy
		# fixed/fallback extent), and its rendered cross extent must stay
		# positive and direction-consistent with the iso projection.
		assert(is_equal_approx(
			float(close_effect.get("_beam_length_px")),
			endpoint.length()
		))
		assert(
			close_sprite.current_frame_visible_cross_extent(aim_axis) > 0.0,
			"beam rendered cross extent must stay positive"
		)
		var expected_transform := close_sprite.transform
		var expected_bounds := close_sprite.fitted_visual_bounds()
		assert(
			absf(
				close_sprite.fitted_visual_forward_extent(aim_axis)
				- endpoint.length()
			) <= 3.0,
			"beam fitted forward extent must reach the projected endpoint"
		)

		# Target distance is deliberately changed by two orders of magnitude while
		# the authoritative 8x1 geometry remains identical.
		var far_effect := _visual_from_cast_nodes(
			plan, aim_axis * 2400.0, aim_axis, owner
		)
		assert(far_effect != null)
		add_child(far_effect)
		var far_sprite := far_effect._sprites[0] as CasterSkillAnimationPlayer
		far_sprite.set_manual_frame(0)
		assert(far_sprite.transform.is_equal_approx(expected_transform))
		_assert_rect_equal(far_sprite.fitted_visual_bounds(), expected_bounds)
		# FREEZE-G0: the frozen laser visual profile ships with
		# single_active.enabled=false, so a new beam coexists with the previous
		# one. The single-active mechanism itself is covered by
		# beam_single_active_test (which injects the enabled profile).
		assert(close_effect.visible)

		# All six primary frames retain the exact snapshot axis and visible
		# endpoint. Their per-frame source bases and scales may differ because the
		# formal alpha envelope, not the transparent rectangle, is calibrated.
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
			).normalized().is_equal_approx(aim_axis))
			assert(absf(
				far_sprite.fitted_visual_forward_extent(aim_axis)
				- endpoint.length()
			) <= 0.01)
			assert(
				far_sprite.current_frame_visible_cross_extent(aim_axis) > 0.0,
				"beam frame cross extent must stay positive"
			)
			var forward_interval := _texture_visible_forward_interval(
				far_sprite,
				aim_axis
			)
			assert(float(forward_interval.maximum) <= endpoint.length() + 0.01)
			assert(
				float(forward_interval.minimum) >= -1.0,
				"beam must not extend backward behind the geometry origin"
			)
			if frame_index == far_sprite.frame_count() - 1:
				assert(
					endpoint.length() - float(forward_interval.maximum) <= 18.0
				)
				_verify_named_direction_forward_fact(
					sample_index,
					far_sprite.direction_index,
					endpoint,
					endpoint.length(),
					forward_interval
				)
		# FREEZE-G0: the beam is geometry-binding driven; replaying the binding
		# parameters (axis + projected length) must reproduce the same transform.
		var beam_axis_screen_px: Vector2 = far_effect.get("_beam_axis_screen_px")
		var beam_length_px := maxf(0.001, float(far_effect.get("_beam_length_px")))
		assert(far_sprite.configure(
			"wizard.laser",
			beam_axis_screen_px,
			0.0,
			null,
			"",
			Vector2.ZERO,
			beam_length_px,
			beam_axis_screen_px,
			0.0,
			{"anchor_policy": "align_sequence_visible_axis_start_to_geometry_origin"}
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


func _texture_visible_forward_interval(
	sprite: CasterSkillAnimationPlayer,
	forward_axis: Vector2
) -> Dictionary:
	var image := sprite.texture.get_image()
	var minimum := INF
	var maximum := -INF
	var normalized_axis := forward_axis.normalized()
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
			var projection := sprite.transform.basis_xform(
				local_center
			).dot(normalized_axis)
			minimum = minf(minimum, projection)
			maximum = maxf(maximum, projection)
	assert(is_finite(minimum) and is_finite(maximum))
	var pixel_support := 0.5 * (
		absf(sprite.transform.x.dot(normalized_axis))
		+ absf(sprite.transform.y.dot(normalized_axis))
	)
	return {
		"minimum": minimum - pixel_support,
		"maximum": maximum + pixel_support,
	}


func _verify_named_direction_forward_fact(
	sample_index: int,
	_source_direction_index: int,
	endpoint: Vector2,
	endpoint_length: float,
	forward_interval: Dictionary
) -> void:
	var direction_ground_gu := Vector2.from_angle(
		TAU * float(sample_index) / 16.0
	)
	var expected_endpoint_px := DirectionSpace.ground_delta_gu_to_screen_delta_px(
		direction_ground_gu * 8.0
	)
	assert(endpoint.is_equal_approx(expected_endpoint_px))
	assert(is_equal_approx(endpoint_length, expected_endpoint_px.length()))
	# These values intentionally differ by projected direction: 8 GU is about
	# 362.04 PX east/west, 181.02 PX north/south, and 286.22 PX on ground axes.
	# Reintroducing 512/256 would restore the old 8-GS direction imbalance.
	assert(float(forward_interval.maximum) <= endpoint_length + 0.01)


func _verify_east_west_no_extra_stretch() -> void:
	# FREEZE-G0 (section 17): E and W must project exactly to the iso mapping of
	# the 8 GU ground length (about 362.04 px), never the historical 512/256
	# fixed extents, with no extra forward or backward stretch.
	for sample_index: int in [6, 14]:  # W and E
		var plan := _line_plan("wizard.laser", 8.0, sample_index)
		var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
		var direction_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 16.0
		)
		var expected_endpoint_px := (
			DirectionSpace.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu * 8.0
			)
		)
		assert(
			endpoint.is_equal_approx(expected_endpoint_px),
			"E/W endpoint must equal the iso projection of 8 GU"
		)
		var effect := _create_line_effect(
			"wizard.laser",
			8.0,
			sample_index,
			endpoint * 100.0
		)
		assert(effect != null)
		add_child(effect)
		assert(
			is_equal_approx(float(effect.get("_beam_length_px")), endpoint.length()),
			"E/W beam must bind to the projected 8 GU endpoint"
		)
		var sprite := effect._sprites[0] as CasterSkillAnimationPlayer
		var forward_interval := _texture_visible_forward_interval(
			sprite,
			endpoint.normalized()
		)
		assert(
			float(forward_interval.maximum) <= endpoint.length() + 0.01,
			"E/W beam must not extend beyond the projected endpoint"
		)
		assert(
			float(forward_interval.minimum) >= -1.0,
			"E/W beam must not extend backward behind the origin"
		)
		effect.free()


func _visual_from_cast_nodes(
	plan: Dictionary,
	target_position: Vector2,
	direction: Vector2,
	owner: PlayerCharacter
) -> CasterSkillVisualEffect:
	var nodes := CasterSkillRuntime.create_cast_nodes_from_canonical_plan(
		plan,
		Vector2.ZERO,
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
	var endpoint: Vector2 = (plan.geometry_screen_points_px as Array).back()
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
	# FREEZE-G0: the canonical snapshot is runtime-map-absolute and STRICT_V2.
	# Without this context the beam visual falls back to a fixed extent instead
	# of binding to the projected geometry.
	var coordinate_context := Snapshot.make_absolute_runtime_context(
		9001,
		Vector2.ZERO,
		Vector2.ZERO,
		Callable(self, "_ground_to_screen")
	)
	var strip := SpellGeometry.continuous_line_strip_ground_gu(
		Vector2.ZERO,
		tile_aim,
		Vector2.RIGHT,
		length_tiles,
		1.0,
		skill_id,
		"stability_%s_%02d" % [skill_id, sample_index],
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
	# Q3-C: legacy the legacy resolver was removed; the line plan is a
	# frozen canonical-shaped presentation plan.
	var plan := {
		"contract": "skill_execution_plan.v1",
		"release_id": "stability_%s_%02d" % [skill_id, sample_index],
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
	}
	# Exercise the exact wire ID emitted by GameRoot. It carries continuous GU
	# screen points and must not fall back to native/radius-sized visuals.
	plan["canonical_geometry_contract"] = (
		SpellGeometry.GAME_ROOT_SCREEN_POINT_CONTRACT_ID
	)
	plan["geometry_origin_screen_px"] = Vector2.ZERO
	plan["geometry_grid_cells"] = []
	plan["geometry_screen_points_px"] = world_points
	plan["skill_footprint_snapshot"] = strip.skill_footprint_snapshot
	plan["snapshot_validation_context"] = coordinate_context
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


func _assert_rect_equal(left: Rect2, right: Rect2) -> void:
	assert(left.position.is_equal_approx(right.position))
	assert(left.size.is_equal_approx(right.size))


func _transform_basis_equal(left: Transform2D, right: Transform2D) -> bool:
	return (
		left.x.is_equal_approx(right.x)
		and left.y.is_equal_approx(right.y)
	)
