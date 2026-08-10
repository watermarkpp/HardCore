extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Visual := preload("res://scripts/warrior_melee_visual_effect.gd")

const TARGET_RADIUS_GU := 0.25
const MAP_ID := 4
const ORIGIN_GROUND_GU := Vector2(19.92, 46.40)
const ISO_ORIGIN_SCREEN_PX := Vector2(743.0, 381.0)


func _ready() -> void:
	assert(
		Visual.VISUAL_CONTRACT_ID
		== "skills.warrior.melee.target_aligned_visual.v1"
	)
	_verify_fail_closed_without_valid_snapshot()
	await _verify_release_visual_fades_and_frees()
	for mode: String in [
		Geometry.SKILL_NORMAL,
		Geometry.SKILL_FIRE,
		Geometry.SKILL_HALF_MOON,
		Geometry.SKILL_THRUST,
	]:
		_verify_three_layers_same_snapshot_source(mode)
	_verify_half_moon_single_node_per_release()
	_verify_thrust_eight_direction_iso_lengths_and_client_alignment()
	_verify_thrust_continuous_angle_client_alignment()
	print(
		"WARRIOR_TARGET_ALIGNED_VISUAL_EFFECT_PASS: three translucent layers "
		+ "consume the exact release snapshot, descriptor is machine-checkable "
		+ "and invalid snapshots fail closed"
	)
	get_tree().quit(0)


func _verify_thrust_eight_direction_iso_lengths_and_client_alignment() -> void:
	var expected_lengths_px := [
		56.568542,
		89.442719,
		113.137085,
		89.442719,
		56.568542,
		89.442719,
		113.137085,
		89.442719,
	]
	var coordinate_context := _iso_absolute_context()
	for direction_index: int in range(8):
		var axis_ground_gu := Geometry.canonical_ground_direction_gu(
			direction_index
		)
		var target_ground_gu := ORIGIN_GROUND_GU + axis_ground_gu * 2.0
		var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
			_release_geometry(target_ground_gu),
			Geometry.SKILL_THRUST,
			coordinate_context
		)
		assert(bool(plan.get("target_axis_eligible", false)))
		var snapshot := plan.get("skill_footprint_snapshot") as Dictionary
		assert(is_equal_approx(float(snapshot.get("effect_length_gu", 0.0)), 2.5))
		assert(is_equal_approx(float(snapshot.get("effect_width_gu", 0.0)), 1.0))
		assert(absf(
			float(snapshot.get("axis_screen_length_px", 0.0))
			- expected_lengths_px[direction_index]
		) <= 0.001)
		var anchor_screen_px := _iso_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
		var effect: Variant = Visual.create_visual(
			snapshot,
			Geometry.SKILL_THRUST,
			{},
			coordinate_context,
			anchor_screen_px
		)
		assert(effect != null)
		assert(effect.scale == Vector2.ONE and is_zero_approx(effect.rotation))
		assert(effect.global_position == anchor_screen_px)
		var layer_polygons: Array[PackedVector2Array] = (
			effect.layer_polygons_screen_offset_px()
		)
		assert(layer_polygons.size() == Visual.LAYER_COUNT)
		var outer_start := (
			layer_polygons[0][0] + layer_polygons[0][3]
		) * 0.5
		var outer_end := (
			layer_polygons[0][1] + layer_polygons[0][2]
		) * 0.5
		assert(outer_start.distance_to(Vector2(snapshot.get(
			"axis_start_screen_offset_px", Vector2.ZERO
		))) <= Visual.POLYGON_VERTEX_TOLERANCE_PX)
		assert(outer_end.distance_to(Vector2(snapshot.get(
			"axis_screen_offset_px", Vector2.ZERO
		))) <= Visual.POLYGON_VERTEX_TOLERANCE_PX)
		assert(absf(
			outer_start.distance_to(outer_end)
			- expected_lengths_px[direction_index]
		) <= 0.001)
		for layer_polygon: PackedVector2Array in layer_polygons:
			assert(((layer_polygon[0] + layer_polygon[3]) * 0.5).distance_to(
				outer_start
			) <= Visual.POLYGON_VERTEX_TOLERANCE_PX)
			assert(((layer_polygon[1] + layer_polygon[2]) * 0.5).distance_to(
				outer_end
			) <= Visual.POLYGON_VERTEX_TOLERANCE_PX)
		var source_row := posmod(direction_index + 4, 8)
		var frozen_snapshot := snapshot.duplicate(true)
		var frozen_outer := Snapshot.projected_polygon_screen_offset_px(snapshot)
		var alignment := Visual.thrust_client_effect_alignment_descriptor(
			snapshot,
			source_row,
			coordinate_context
		)
		assert(not alignment.is_empty())
		assert(snapshot == frozen_snapshot)
		assert(
			Snapshot.projected_polygon_screen_offset_px(snapshot)
			== frozen_outer
		)
		assert(bool(alignment.get("same_snapshot_source", false)))
		assert(str(alignment.get("snapshot_id", "")) == str(
			snapshot.get("snapshot_id", "")
		))
		_verify_thrust_forward_fit_and_native_cross_axis(
			source_row,
			alignment
		)
		assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
			plan,
			ORIGIN_GROUND_GU + axis_ground_gu * 1.5,
			0.0,
			coordinate_context
		) == 1)
		assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
			plan,
			ORIGIN_GROUND_GU + axis_ground_gu * 1.501,
			0.0,
			coordinate_context
		) == 2)
		assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
			plan,
			ORIGIN_GROUND_GU + axis_ground_gu * 1.60,
			0.25,
			coordinate_context
		) == 1, "a monster footprint crossing 1.5 GU must remain primary-first")
		assert(Geometry.target_aligned_thrust_slot_for_plan_gu(
			plan,
			ORIGIN_GROUND_GU + axis_ground_gu * 1.751,
			0.25,
			coordinate_context
		) == 2, "a monster footprint fully beyond 1.5 GU must enter slot 2")
		effect.free()


func _verify_thrust_forward_fit_and_native_cross_axis(
	source_row: int,
	alignment: Dictionary
) -> void:
	assert(
		str(alignment.get("cross_axis_scale_policy", ""))
		== Visual.THRUST_CLIENT_EFFECT_CROSS_AXIS_SCALE_POLICY
	)
	var basis := Transform2D(
		Vector2(alignment.get("basis_x_screen_px", Vector2.RIGHT)),
		Vector2(alignment.get("basis_y_screen_px", Vector2.DOWN)),
		Vector2(alignment.get("origin_screen_offset_px", Vector2.ZERO))
	)
	var target_start := Vector2(alignment.get(
		"target_start_center_screen_offset_px", Vector2.ZERO
	))
	var target_end := Vector2(alignment.get(
		"target_end_center_screen_offset_px", Vector2.ZERO
	))
	var bounds: Vector4 = alignment.get(
		"source_bounds_ground_basis", Vector4.ZERO
	)
	var source_direction_index := posmod(source_row + 4, 8)
	var source_direction := Geometry.canonical_ground_direction_gu(
		source_direction_index
	)
	var source_side := Vector2(-source_direction.y, source_direction.x)
	var source_side_screen := (
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(source_side)
	)
	assert(source_side_screen.length() > 0.001)
	assert(Vector2(alignment.get(
		"native_source_side_screen_px", Vector2.ZERO
	)).distance_to(source_side_screen) <= 0.000001)
	var source_origin := Vector2(alignment.get(
		"source_origin_px", Vector2.ZERO
	))
	var source_side_center := (bounds.z + bounds.w) * 0.5
	var source_start_center := (
		source_origin
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			source_direction * bounds.x + source_side * source_side_center
		)
	)
	var source_end_center := (
		source_origin
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			source_direction * bounds.y + source_side * source_side_center
		)
	)
	assert((basis * source_start_center).distance_to(target_start) <= 0.01)
	assert((basis * source_end_center).distance_to(target_end) <= 0.01)
	var source_cross_min := (
		source_origin
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			source_direction * bounds.x + source_side * bounds.z
		)
	)
	var source_cross_max := (
		source_origin
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			source_direction * bounds.x + source_side * bounds.w
		)
	)
	var native_cross_span := source_cross_max - source_cross_min
	var transformed_cross_span := (
		basis * source_cross_max - basis * source_cross_min
	)
	assert(native_cross_span.length() > 0.001)
	assert(transformed_cross_span.distance_to(native_cross_span) <= 0.01)


func _verify_thrust_continuous_angle_client_alignment() -> void:
	var coordinate_context := _iso_absolute_context()
	for sample_index: int in range(144):
		var axis_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 144.0
		)
		var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
			_release_geometry(ORIGIN_GROUND_GU + axis_ground_gu * 2.0),
			Geometry.SKILL_THRUST,
			coordinate_context
		)
		var snapshot := plan.get("skill_footprint_snapshot") as Dictionary
		var visual_direction_index := int(plan.get("visual_direction_index", -1))
		var source_row := posmod(visual_direction_index + 4, 8)
		var alignment := Visual.thrust_client_effect_alignment_descriptor(
			snapshot,
			source_row,
			coordinate_context
		)
		assert(not alignment.is_empty())
		_verify_thrust_forward_fit_and_native_cross_axis(
			source_row,
			alignment
		)


func _verify_fail_closed_without_valid_snapshot() -> void:
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	assert(Visual.create_visual(
		{},
		Geometry.SKILL_NORMAL,
		{},
		coordinate_context,
		Vector2.ZERO
	) == null)
	assert(Visual.fail_closed_reason({}, coordinate_context) == "missing_snapshot")
	var valid_snapshot := _snapshot_for_mode(Geometry.SKILL_NORMAL)
	var invalid_snapshot := valid_snapshot.duplicate(true)
	invalid_snapshot.erase("coordinate_space")
	assert(Visual.create_visual(
		invalid_snapshot,
		Geometry.SKILL_NORMAL,
		{},
		coordinate_context,
		Vector2.ZERO
	) == null)
	assert(
		Visual.fail_closed_reason(invalid_snapshot, coordinate_context)
		== "invalid_snapshot"
	)
	var raw := Visual.new()
	raw.setup({}, Geometry.SKILL_NORMAL, {}, coordinate_context, Vector2.ZERO)
	assert(raw.get_child_count() == 0)
	assert(not raw.visible)
	assert(raw.rejection_reason == "missing_snapshot")
	raw.free()


func _verify_three_layers_same_snapshot_source(mode: String) -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(23.0))
	var target_ground_gu := ORIGIN_GROUND_GU + axis_ground_gu * 1.2
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(target_ground_gu),
		mode,
		coordinate_context
	)
	assert(bool(plan.get("target_axis_eligible", false)))
	var snapshot := plan.get("skill_footprint_snapshot") as Dictionary
	var effect: Variant = Visual.create_visual(
		snapshot,
		mode,
		{"hit_any": true},
		coordinate_context,
		_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
	)
	assert(effect != null)
	assert(effect.visual_ready())
	assert(effect.get_child_count() == Visual.LAYER_COUNT)
	var children: Array = effect.get_children()
	var outer := children[0] as Polygon2D
	assert(outer != null)
	assert(
		str(outer.get_meta("target_aligned_visual_layer_role", ""))
		== Visual.LAYER_ROLE_OUTER
	)
	var expected_polygon := Snapshot.projected_polygon_screen_offset_px(
		snapshot
	)
	assert(expected_polygon.size() == outer.polygon.size())
	for point_index: int in range(outer.polygon.size()):
		assert(
			outer.polygon[point_index].distance_to(
				expected_polygon[point_index]
			) <= Visual.POLYGON_VERTEX_TOLERANCE_PX
		)
	var descriptor: Dictionary = effect.presentation_descriptor()
	assert(bool(descriptor.get("same_snapshot_source", false)))
	assert(str(descriptor.get("snapshot_id", "")) == str(
		snapshot.get("snapshot_id", "")
	))
	assert(str(descriptor.get("mode", "")) == mode)
	assert(
		str(descriptor.get("geometry_contract_id", ""))
		== Geometry.TARGET_ALIGNED_CONTINUOUS_RELEASE_CONTRACT_ID
	)
	var layer_specs: Array = descriptor.get("layer_specs", [])
	assert(layer_specs.size() == Visual.LAYER_COUNT)
	for layer_index: int in range(Visual.LAYER_COUNT):
		var spec: Dictionary = layer_specs[layer_index]
		assert(
			str(spec.get("role", ""))
			== Visual.LAYER_ROLES[layer_index]
		)
		assert(
			is_equal_approx(
				float(spec.get("alpha", 0.0)),
				Visual.LAYER_ALPHAS[layer_index]
			)
		)
		assert(
			is_equal_approx(
				float(spec.get("scale", 0.0)),
				Visual.LAYER_SCALES[layer_index]
			)
		)
		var color := spec.get("color", Color.BLACK) as Color
		assert(is_equal_approx(color.a, Visual.LAYER_ALPHAS[layer_index]))
		var layer := children[layer_index] as Polygon2D
		assert(layer != null)
		assert(layer.polygon.size() >= 3)
		assert(is_equal_approx(
			float(layer.get_meta("target_aligned_visual_layer_scale", -1.0)),
			Visual.LAYER_SCALES[layer_index]
		))
	for layer_index: int in range(1, Visual.LAYER_COUNT):
		assert(
			Visual.LAYER_ALPHAS[layer_index]
			> Visual.LAYER_ALPHAS[layer_index - 1]
		)
	effect.free()


func _verify_half_moon_single_node_per_release() -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(7.0))
	var target_ground_gu := ORIGIN_GROUND_GU + axis_ground_gu * 1.2
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(target_ground_gu),
		Geometry.SKILL_HALF_MOON,
		coordinate_context
	)
	var snapshot := plan.get("skill_footprint_snapshot") as Dictionary
	var effect: Variant = Visual.create_visual(
		snapshot,
		Geometry.SKILL_HALF_MOON,
		{"hit_any": true, "target_count": 99},
		coordinate_context,
		_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
	)
	assert(effect != null)
	assert(effect.get_child_count() == Visual.LAYER_COUNT)
	var descriptor: Dictionary = effect.presentation_descriptor()
	var hit_info: Dictionary = descriptor.get("hit_info", {})
	assert(int(hit_info.get("target_count", 0)) == 99)
	assert(bool(hit_info.get("hit_any", false)))
	effect.free()


func _verify_release_visual_fades_and_frees() -> void:
	var axis_ground_gu := Vector2.from_angle(deg_to_rad(17.0))
	var target_ground_gu := ORIGIN_GROUND_GU + axis_ground_gu * 1.2
	var coordinate_context := _absolute_context(ORIGIN_GROUND_GU)
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(target_ground_gu),
		Geometry.SKILL_NORMAL,
		coordinate_context
	)
	var effect: Variant = Visual.create_visual(
		plan.get("skill_footprint_snapshot") as Dictionary,
		Geometry.SKILL_NORMAL,
		{},
		coordinate_context,
		_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
	)
	assert(effect != null)
	var host := Node2D.new()
	add_child(host)
	host.add_child(effect)
	assert(effect.is_inside_tree())
	await get_tree().create_timer(
		Visual.RELEASE_VISUAL_LIFETIME_SEC + 0.10
	).timeout
	assert(not is_instance_valid(effect))
	host.queue_free()


func _snapshot_for_mode(mode: String) -> Dictionary:
	var plan := Geometry.target_aligned_melee_release_plan_ground_gu(
		_release_geometry(
			ORIGIN_GROUND_GU + Vector2(1.0, 1.0).normalized() * 1.2
		),
		mode,
		_absolute_context(ORIGIN_GROUND_GU)
	)
	return plan.get("skill_footprint_snapshot") as Dictionary


func _release_geometry(
	locked_target_ground_gu: Vector2
) -> Dictionary:
	var delta_ground_gu := locked_target_ground_gu - ORIGIN_GROUND_GU
	return {
		"origin_ground_gu": ORIGIN_GROUND_GU,
		"locked_target_ground_gu_at_release": locked_target_ground_gu,
		"locked_target_valid_at_release": true,
		"locked_target_instance_id": 9001,
		"live_locked_target_direction_ground_gu": (
			delta_ground_gu.normalized()
			if delta_ground_gu.length_squared()
			> Geometry.EPSILON * Geometry.EPSILON
			else Vector2.ZERO
		),
		"direction_index": Geometry.direction_index_for_ground_delta_gu(
			delta_ground_gu
		),
		"release_id": "target_aligned_visual_test_release",
	}


func _absolute_context(origin_ground_gu: Vector2) -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		MAP_ID,
		origin_ground_gu,
		origin_ground_gu,
		Callable(self, "_ground_gu_to_screen_px")
	)


func _iso_absolute_context() -> Dictionary:
	return Snapshot.make_absolute_runtime_context(
		MAP_ID,
		ORIGIN_GROUND_GU,
		ORIGIN_GROUND_GU,
		Callable(self, "_iso_ground_gu_to_screen_px")
	)


func _iso_ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return (
		ISO_ORIGIN_SCREEN_PX
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			ground_gu - ORIGIN_GROUND_GU
		)
	)


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return Vector2(ground_gu.x * 64.0, ground_gu.y * 32.0)
