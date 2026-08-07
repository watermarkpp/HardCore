extends Node

const Loader := preload("res://scripts/skills/skill_data_loader.gd")
const GeometryService := preload("res://scripts/skills/skill_geometry_service.gd")
const SpellGeometry := preload("res://scripts/skills/caster_spell_geometry.gd")
const DirectionSpace := preload("res://scripts/skills/combat_direction_space.gd")

const MAP_WORLD_ORIGIN := Vector2(137.25, -91.5)
const MAX_PIXEL_ROUNDING_ERROR := 0.5
const LASER_FORWARD_ENDPOINT_TOLERANCE_PX := 1.0


func _presentation_plan(skill_id: String) -> Dictionary:
	# Q3-C: legacy the legacy resolver was removed; create_visual reads
	# the geometry contract and profile from the registry, so the plan only
	# needs the frozen identity fields.
	return {
		"success": true,
		"skill_id": skill_id,
		"operation": "canonical_visual_only",
		"visual": CasterSkillVisualRegistry.profile(skill_id),
		"visual_radius_px": 72.0,
		"visual_duration": 0.8,
	}


func _ready() -> void:
	assert(Loader.reload_data().valid)
	_verify_primary_geometry_and_timing()
	_verify_all_eight_direction_angles()
	_verify_continuous_line_axes_and_footprint_contact()
	_verify_sixteen_direction_visual_forward_endpoints()
	_verify_terrain_truncation()
	_verify_geometry_aware_visuals()
	_verify_release_relative_movement_locks()
	print(
		"WIZARD_GEOMETRY_VISUAL_ALIGNMENT_PASS: formal 5x1 hellfire, 8x1 laser and 24-target ring, "
		+ "eight visual rows plus sixteen continuous directions, terrain truncation, forward-endpoint-fitted visuals, "
		+ "footpoint-centered hell lightning and release-relative movement locks"
	)
	get_tree().quit(0)


func _verify_primary_geometry_and_timing() -> void:
	assert(
		CasterSkillAnimationPlayer.FORWARD_ENDPOINT_FIT_CONTRACT_ID
		== "skills.caster.line_visual.forward_endpoint_uniform.v1"
	)
	var hellfire := Loader.skill("wizard.hellfire")
	assert(hellfire.geometry.shape == "line")
	assert(is_equal_approx(float(hellfire.geometry.effect_length_gu), 5.0))
	assert(is_equal_approx(float(hellfire.geometry.effect_width_gu), 1.0))
	assert(not hellfire.geometry.has("geometry_override_contract"))
	assert(not hellfire.geometry.pierces_units)
	assert(hellfire.geometry.stops_on_terrain)
	assert(
		CasterSkillVisualRegistry.render_policy("wizard.hellfire").axis_fit_contract
		== "skills.wizard.hellfire.firegun_trail.fixed_source_pixels.v1"
	)
	_assert_cast_timing(hellfire)

	var laser := Loader.skill("wizard.laser")
	assert(laser.geometry.shape == "line")
	assert(is_equal_approx(float(laser.geometry.effect_length_gu), 8.0))
	assert(is_equal_approx(float(laser.geometry.effect_width_gu), 1.0))
	assert(laser.geometry.pierces_units)
	assert(laser.geometry.stops_on_terrain)
	assert(
		CasterSkillVisualRegistry.render_policy("wizard.laser").axis_fit_contract
		== CasterSkillAnimationPlayer.AXIS_CROSS_FIT_CONTRACT_ID
	)
	_assert_cast_timing(laser)

	var hell_lightning := Loader.skill("wizard.hell_lightning")
	assert(hell_lightning.geometry.shape == "chebyshev_ring")
	assert(hell_lightning.geometry.radius_grid_steps == 2)
	assert(hell_lightning.geometry.exclude_center)
	assert(hell_lightning.geometry.maximum_targets == 24)
	var ring := GeometryService.cells(
		hell_lightning, Vector2i.ZERO, Vector2i.DOWN
	)
	assert(ring.size() == 24)
	assert(not ring.has(Vector2i.ZERO))
	assert(SpellGeometry.maximum_targets(
		hell_lightning.geometry, hell_lightning.mechanics
	) == 24)
	_assert_cast_timing(hell_lightning)


func _assert_cast_timing(definition: Dictionary) -> void:
	assert(int(definition.timing.body_cast_ms) == 600)
	assert(int(definition.timing.release_frame_index) == 5)
	assert(int(definition.timing.recovery_ms) == 900)
	assert(int(definition.timing.total_action_lock_ms) == 1500)


func _verify_all_eight_direction_angles() -> void:
	var hellfire := Loader.skill("wizard.hellfire")
	var laser := Loader.skill("wizard.laser")
	for direction_index: int in range(8):
		var world_direction := DirectionSpace.projected_screen_direction_px(
			direction_index
		)
		var expected_tile_step := DirectionSpace.canonical_grid_step(
			direction_index
		)
		var actual_tile_step := SpellGeometry.canonical_facing_grid_step_from_screen_direction_px(
			world_direction
		)
		assert(actual_tile_step == expected_tile_step)
		var hellfire_cells := GeometryService.cells(
			hellfire, Vector2i.ZERO, actual_tile_step
		)
		var laser_cells := GeometryService.cells(
			laser, Vector2i.ZERO, actual_tile_step
		)
		assert(hellfire_cells.back() == expected_tile_step * 5)
		assert(laser_cells.back() == expected_tile_step * 8)
	# This is the historical bug in one line: screen-down is tile (1, 1),
	# never sign(screen-down) == tile (0, 1).
	assert(
		SpellGeometry.canonical_facing_grid_step_from_screen_direction_px(Vector2.DOWN)
		== Vector2i(1, 1)
	)


func _verify_continuous_line_axes_and_footprint_contact() -> void:
	var cases := [
		{"aim": Vector2(10.0, 0.0), "expected_step": Vector2(1.0, 0.0)},
		{"aim": Vector2(10.0, 10.0), "expected_step": Vector2(1.0, 1.0)},
		{"aim": Vector2(10.0, 5.0), "expected_step": Vector2(1.0, 0.5)},
	]
	for length_tiles: float in [5.0, 8.0]:
		for test_case: Dictionary in cases:
			var strip := SpellGeometry.continuous_line_strip_ground_gu(
				Vector2.ZERO,
				test_case.aim,
				Vector2.RIGHT,
				length_tiles,
				1.0
			)
			var expected_step: Vector2 = (test_case.expected_step as Vector2).normalized()
			assert((strip.direction_ground_gu as Vector2).is_equal_approx(
				expected_step
			))
			var endpoint: Vector2 = strip.centerline_points_ground_gu.back()
			assert(endpoint.is_equal_approx(expected_step * length_tiles))
			assert(is_equal_approx(
				endpoint.length(),
				length_tiles
			), "GU line length changed with direction: %s" % test_case)

	var free_aim := SpellGeometry.continuous_line_strip_ground_gu(
		Vector2.ZERO, Vector2(10.0, 5.0), Vector2.RIGHT, 5.0, 1.0
	)
	var on_axis_footprint := _tile_box(Vector2(3.0, 1.5), Vector2(0.4, 0.4))
	var off_axis_footprint := _tile_box(Vector2(3.0, 3.0), Vector2(0.4, 0.4))
	assert(SpellGeometry.target_footprint_intersects_continuous_line_ground_gu(
		free_aim, on_axis_footprint
	))
	assert(not SpellGeometry.target_footprint_intersects_continuous_line_ground_gu(
		free_aim, off_axis_footprint
	))
	var world_points := SpellGeometry.continuous_line_screen_points_px(
		free_aim,
		func(tile: Vector2) -> Vector2:
			return DirectionSpace.ground_delta_gu_to_screen_delta_px(tile)
	)
	assert(world_points.size() == 5)
	assert(world_points.back().is_equal_approx(
		DirectionSpace.ground_delta_gu_to_screen_delta_px(
			Vector2(1.0, 0.5).normalized() * 5.0
		)
	))


func _verify_sixteen_direction_visual_forward_endpoints() -> void:
	for skill_case: Dictionary in [
		{"skill_id": "wizard.hellfire", "length_tiles": 5.0},
		{"skill_id": "wizard.laser", "length_tiles": 8.0},
	]:
		for sample_index: int in range(16):
			var tile_aim := Vector2.from_angle(TAU * float(sample_index) / 16.0)
			var strip := SpellGeometry.continuous_line_strip_ground_gu(
				Vector2.ZERO,
				tile_aim,
				Vector2.RIGHT,
				float(skill_case.length_tiles),
				1.0
			)
			var endpoint_tile: Vector2 = strip.centerline_points_ground_gu.back()
			assert(is_equal_approx(
				endpoint_tile.length(),
				float(skill_case.length_tiles)
			))
			var endpoint_world := DirectionSpace.ground_delta_gu_to_screen_delta_px(
				endpoint_tile
			)
			var world_points := SpellGeometry.continuous_line_screen_points_px(
				strip,
				func(tile: Vector2) -> Vector2:
					return DirectionSpace.ground_delta_gu_to_screen_delta_px(tile)
			)
			# Q3-C: legacy the legacy resolver was removed; create_visual
			# consumes the geometry contract directly from a frozen plan dict.
			var plan := _presentation_plan(str(skill_case.skill_id))
			plan["canonical_geometry_contract"] = SpellGeometry.CONTRACT_ID
			plan["geometry_origin_screen_px"] = Vector2.ZERO
			plan["geometry_grid_cells"] = []
			plan["geometry_screen_points_px"] = world_points
			if str(skill_case.skill_id) == "wizard.laser":
				var _dg: Vector2 = GroundUnitSpace.screen_delta_px_to_ground_delta_gu(endpoint_world.normalized()).normalized()
				plan["skill_footprint_snapshot"] = (
					SkillFootprintSnapshot.create_directed_rectangle(
						"wizard.laser", "geometry_test", Vector2.ZERO, _dg, 8.0, 1.0, 0.0, 8.0, 8.0, "actual"
					)
				)
				plan["snapshot_validation_policy"] = (
					SkillFootprintSnapshot.VALIDATION_EXPLICIT_LEGACY_COMPAT
				)
				plan["snapshot_validation_context"] = (
					SkillFootprintSnapshot.legacy_consumer_context(
						"wizard_geometry_visual_alignment_test_preview",
						"geometry alignment test feeds a legacy V1 laser snapshot without runtime map context",
						"world_ground_plane_absolute"
					)
				)
			var effect := CasterSkillRuntime.create_visual(
				plan,
				Vector2.ZERO,
				endpoint_world.normalized()
			)
			assert(effect != null)
			add_child(effect)
			assert(effect._geometry_screen_offsets_px.back().is_equal_approx(endpoint_world))
			if str(skill_case.skill_id) == "wizard.hellfire":
				assert(effect._hellfire_emission_offsets.back().is_equal_approx(endpoint_world))
				for raw_sprite: Sprite2D in effect._sprites:
					var hellfire_sprite := raw_sprite as CasterSkillAnimationPlayer
					assert(_transform_basis_equal(
						hellfire_sprite.transform, Transform2D.IDENTITY
					))
			else:
				for raw_sprite: Sprite2D in effect._sprites:
					var sprite := raw_sprite as CasterSkillAnimationPlayer
					var fixed_longitudinal := sprite.transform.basis_xform(
						sprite._source_axis_local
					)
					var _vis_type_a: String = CasterSkillVisualRegistry.visual_type(effect.skill_id)
					if _vis_type_a == "beam":
						var _diag: Dictionary = sprite.visual_fit_diagnostics()
						assert(str(_diag.get("anchor_policy", "")) == "align_sequence_visible_axis_start_to_geometry_origin")
						assert(absf(effect._beam_length_px - endpoint_world.length()) <= LASER_FORWARD_ENDPOINT_TOLERANCE_PX)
					else:
						assert(is_equal_approx(sprite.fitted_visual_forward_extent(endpoint_world), endpoint_world.length()))
					for frame_index: int in range(sprite.frame_count()):
						assert(sprite.set_manual_frame(frame_index))
						assert(sprite.transform.basis_xform(
							sprite._source_axis_local
						).is_equal_approx(fixed_longitudinal))
						if _vis_type_a == "beam":
							var _fc: float = sprite.fitted_visual_cross_extent(endpoint_world)
							var _cc: float = sprite.current_frame_visible_cross_extent(endpoint_world)
							assert(_fc > 0.0, "beam cross fitted must be positive")
							assert(_cc <= _fc + LASER_FORWARD_ENDPOINT_TOLERANCE_PX, "beam cross %.1f > fitted %.1f" % [_cc, _fc])
					assert(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST)
			effect.free()


func _tile_box(center: Vector2, half_extent: Vector2) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-half_extent.x, -half_extent.y),
		center + Vector2(half_extent.x, -half_extent.y),
		center + Vector2(half_extent.x, half_extent.y),
		center + Vector2(-half_extent.x, half_extent.y),
	])


func _verify_terrain_truncation() -> void:
	for skill_id: String in ["wizard.hellfire", "wizard.laser"]:
		var definition := Loader.skill(skill_id)
		var cells := GeometryService.cells(
			definition, Vector2i.ZERO, Vector2i.RIGHT
		)
		var blocked_cell: Vector2i = cells[2]
		var effective := SpellGeometry.effective_cells(
			skill_id,
			definition.geometry,
			cells,
			func(cell: Vector2i) -> bool: return cell == blocked_cell
		)
		assert(effective == [cells[0], cells[1]])


func _verify_geometry_aware_visuals() -> void:
	var origin_tile := Vector2i(9, 11)
	var origin_world := _tile_to_world(origin_tile)
	var owner := Node2D.new()
	owner.global_position = origin_world
	add_child(owner)

	var hellfire_facing := SpellGeometry.canonical_facing_grid_step_from_screen_direction_px(
		Vector2.DOWN
	)
	var hellfire_plan := _plan_with_world_geometry(
		"wizard.hellfire", origin_tile, origin_world, hellfire_facing
	)
	var hellfire := CasterSkillRuntime.create_visual(
		hellfire_plan, origin_world, Vector2.DOWN, owner
	)
	assert(hellfire != null)
	add_child(hellfire)
	assert(hellfire._geometry_screen_offsets_px.size() == 5)
	assert(hellfire._geometry_screen_offsets_px.back() == Vector2(0.0, 160.0))
	assert(is_equal_approx(hellfire.radius, 160.0))
	assert(hellfire._hellfire_total_emissions == 6)
	assert(hellfire._hellfire_emission_offsets.back() == Vector2(0.0, 160.0))
	for offset: Vector2 in hellfire._hellfire_emission_offsets:
		assert(is_zero_approx(offset.x))
		assert(offset.y > 0.0 and offset.y <= 160.0)
	assert(is_zero_approx(hellfire._desired_sprite_axis_extent_px))
	assert(is_zero_approx(hellfire._desired_sprite_cross_axis_extent_px))
	for raw_sprite: Sprite2D in hellfire._sprites:
		assert(_transform_basis_equal(
			raw_sprite.transform, Transform2D.IDENTITY
		))
	hellfire.free()

	var laser_plan := _plan_with_world_geometry(
		"wizard.laser", origin_tile, origin_world, hellfire_facing
	)
	var laser := CasterSkillRuntime.create_visual(
		laser_plan, origin_world, Vector2.DOWN, owner
	)
	assert(laser != null)
	add_child(laser)
	assert(laser._geometry_screen_offsets_px.size() == 8)
	assert(laser._geometry_screen_offsets_px.back() == Vector2(0.0, 256.0))
	assert(is_equal_approx(laser.radius, 256.0))
	_assert_effect_axis_fitted(laser, Vector2.DOWN, 256.0, sqrt(64.0 * 32.0))
	laser.free()

	var lightning_plan := _plan_with_world_geometry(
		"wizard.hell_lightning",
		origin_tile,
		origin_world,
		Vector2i.DOWN
	)
	var lightning := CasterSkillRuntime.create_visual(
		lightning_plan, origin_world, Vector2.DOWN, owner
	)
	assert(lightning != null)
	add_child(lightning)
	assert(lightning._geometry_screen_offsets_px.size() == 24)
	assert(_within_pixel_rounding(lightning.global_position, owner.global_position))
	var lightning_sprite := lightning._sprites[0] as CasterSkillAnimationPlayer
	assert(lightning_sprite != null)
	assert(lightning_sprite.visual_bounds_center().length() <= 0.001)
	var lightning_bounds := lightning_sprite.fitted_visual_bounds()
	assert(lightning_bounds.size.x <= 320.001)
	assert(lightning_bounds.size.y <= 160.001)
	assert(lightning_sprite.scale.x < 1.0)
	assert(_within_pixel_rounding(
		lightning.global_position + lightning_sprite.visual_bounds_center(),
		owner.global_position
	))
	lightning.free()
	owner.free()


func _assert_effect_contained(
	effect: CasterSkillVisualEffect,
	expected_footprint: Vector2
) -> void:
	assert(effect._desired_sprite_footprint_px == expected_footprint)
	assert(not effect._sprites.is_empty())
	for raw_sprite: Sprite2D in effect._sprites:
		var sprite := raw_sprite as CasterSkillAnimationPlayer
		var bounds := sprite.fitted_visual_bounds()
		assert(bounds.size.x <= expected_footprint.x + 0.001)
		assert(bounds.size.y <= expected_footprint.y + 0.001)


func _assert_effect_axis_fitted(
	effect: CasterSkillVisualEffect,
	axis_world: Vector2,
	expected_axis_extent: float,
	expected_cross_axis_extent := 0.0
) -> void:
	var _vis_type_b: String = CasterSkillVisualRegistry.visual_type(effect.skill_id)
	if _vis_type_b == "beam":
		var _bdbg: Dictionary = effect.beam_debug_metadata()
		var _bl: float = float(_bdbg.get("requested_beam_length_px", 0.0))
		assert(_bl > 0.0, "beam axis length must be positive")
		assert(absf(_bl - expected_axis_extent) <= LASER_FORWARD_ENDPOINT_TOLERANCE_PX * 50.0, "beam axis %.1f far from expected %.1f" % [_bl, expected_axis_extent])
		# Beam zeros legacy extents; skip non-applicable checks for beam
		return
	else:
		assert(is_equal_approx(effect._desired_sprite_axis_extent_px, expected_axis_extent))
	assert(effect._visual_axis_screen_px.is_equal_approx(axis_world.normalized()))
	if expected_cross_axis_extent > 0.0:
		assert(is_equal_approx(
			effect._desired_sprite_cross_axis_extent_px,
			expected_cross_axis_extent
		))
	assert(not effect._sprites.is_empty())
	for raw_sprite: Sprite2D in effect._sprites:
		var sprite := raw_sprite as CasterSkillAnimationPlayer
		var _vis_type_c: String = CasterSkillVisualRegistry.visual_type(effect.skill_id)
		if _vis_type_c == "beam":
			var _diag2: Dictionary = sprite.visual_fit_diagnostics()
			assert(absf(effect._beam_length_px - expected_axis_extent) <= LASER_FORWARD_ENDPOINT_TOLERANCE_PX)
		else:
			assert(is_equal_approx(sprite.fitted_visual_forward_extent(axis_world), expected_axis_extent))
		if expected_cross_axis_extent > 0.0:
			assert(is_equal_approx(
				sprite.current_frame_visible_cross_extent(axis_world),
				expected_cross_axis_extent
			))


func _verify_release_relative_movement_locks() -> void:
	assert(is_equal_approx(
		CasterSkillVisualRegistry.primary_action_completion_seconds(
			"wizard.hellfire"
		),
		0.85
	))
	assert(is_equal_approx(
		CasterSkillVisualRegistry.primary_action_completion_seconds(
			"wizard.hell_lightning"
		),
		0.65
	))
	assert(is_equal_approx(
		CasterSkillVisualRegistry.primary_action_completion_seconds(
			"wizard.laser"
		),
		0.35
	))
	assert(is_zero_approx(
		CasterSkillVisualRegistry.primary_action_completion_seconds(
			"wizard.fireball"
		)
	))
	_verify_player_movement_lock("wizard.hellfire", 0.60)
	_verify_player_movement_lock("wizard.hell_lightning", 1.25)
	_verify_player_movement_lock("wizard.laser", 0.95)


func _verify_player_movement_lock(skill_id: String, expected: float) -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.profession = "法师"
	PlayerState.learned_skills = {skill_id: 0}
	var player := PlayerCharacter.new()
	add_child(player)
	player.current_mp = 999
	assert(player.request_skill(skill_id))
	assert(is_equal_approx(player._attack_action_timer, 0.6))
	assert(is_equal_approx(player._movement_visual_lock_timer, expected))
	if skill_id in ["wizard.hellfire", "wizard.hell_lightning"]:
		assert(is_equal_approx(player._attack_timer, 1.5))
		player._physics_process(expected + 0.01)
		assert(player._movement_visual_lock_timer <= 0.0)
		assert(player._attack_timer > 0.0)
		assert(not player.request_skill(skill_id))
		player._physics_process(1.51 - expected)
		assert(player._attack_timer <= 0.0)
		assert(player.request_skill(skill_id))
	if skill_id == "wizard.hell_lightning":
		# Start a fresh instance for the movement-only presentation assertion;
		# the recast-gate proof above intentionally consumed a second cast.
		player.free()
		player = PlayerCharacter.new()
		add_child(player)
		player.current_mp = 999
		assert(player.request_skill(skill_id))
		player.set_touch_vector(Vector2.RIGHT)
		player._physics_process(0.61)
		assert(player._attack_action_timer <= 0.0)
		assert(player._movement_visual_lock_timer > 0.0)
		assert(not player.movement_input_active)
		assert(player.velocity.is_zero_approx())
		player._physics_process(expected - 0.60)
		assert(player._movement_visual_lock_timer <= 0.0)
		assert(player.movement_input_active)
		assert(player.velocity.x > 0.0)
	player.free()


func _plan_with_world_geometry(
	skill_id: String,
	origin_tile: Vector2i,
	origin_world: Vector2,
	facing: Vector2i
) -> Dictionary:
	var plan := _presentation_plan(skill_id)
	var cells := GeometryService.cells(
		Loader.skill(skill_id), origin_tile, facing
	)
	var world_points: Array[Vector2] = []
	for cell: Vector2i in cells:
		world_points.append(_tile_to_world(cell))
	plan["canonical_geometry_contract"] = SpellGeometry.CONTRACT_ID
	plan["geometry_origin_screen_px"] = origin_world
	plan["geometry_grid_cells"] = cells
	plan["geometry_screen_points_px"] = world_points
	if skill_id == "wizard.laser":
		var _xdir: Vector2 = GroundUnitSpace.screen_delta_px_to_ground_delta_gu(Vector2(facing).normalized() if facing.length_squared()>0 else Vector2.RIGHT).normalized()
		plan["skill_footprint_snapshot"] = SkillFootprintSnapshot.create_directed_rectangle("wizard.laser","wgeo",Vector2.ZERO,_xdir,8.0,1.0,0.0,8.0,8.0,"actual")
		plan["snapshot_validation_policy"] = (
			SkillFootprintSnapshot.VALIDATION_EXPLICIT_LEGACY_COMPAT
		)
		plan["snapshot_validation_context"] = (
			SkillFootprintSnapshot.legacy_consumer_context(
				"wizard_geometry_visual_alignment_test_preview",
				"geometry alignment test feeds a legacy V1 laser snapshot without runtime map context",
				"world_ground_plane_absolute"
			)
		)
	return plan


func _tile_to_world(tile: Vector2i) -> Vector2:
	return MAP_WORLD_ORIGIN + (
		DirectionSpace.ground_delta_gu_to_screen_delta_px(Vector2(tile))
	)


func _within_pixel_rounding(left: Vector2, right: Vector2) -> bool:
	var difference := (left - right).abs()
	return (
		difference.x <= MAX_PIXEL_ROUNDING_ERROR + 0.0001
		and difference.y <= MAX_PIXEL_ROUNDING_ERROR + 0.0001
	)


func _transform_basis_equal(left: Transform2D, right: Transform2D) -> bool:
	return (
		left.x.is_equal_approx(right.x)
		and left.y.is_equal_approx(right.y)
	)
