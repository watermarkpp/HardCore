extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const Visual := preload("res://scripts/warrior_melee_visual_effect.gd")

const TARGET_RADIUS_GU := 0.25
const MAP_ID := 4
const ORIGIN_GROUND_GU := Vector2(19.92, 46.40)


func _ready() -> void:
	assert(
		Visual.VISUAL_CONTRACT_ID
		== "skills.warrior.melee.target_aligned_visual.v1"
	)
	_verify_fail_closed_without_valid_snapshot()
	for mode: String in [
		Geometry.SKILL_NORMAL,
		Geometry.SKILL_FIRE,
		Geometry.SKILL_HALF_MOON,
		Geometry.SKILL_THRUST,
	]:
		_verify_three_layers_same_snapshot_source(mode)
	_verify_half_moon_single_node_per_release()
	print(
		"WARRIOR_TARGET_ALIGNED_VISUAL_EFFECT_PASS: three translucent layers "
		+ "consume the exact release snapshot, descriptor is machine-checkable "
		+ "and invalid snapshots fail closed"
	)
	get_tree().quit(0)


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
	var effect := Visual.create_visual(
		snapshot,
		mode,
		{"hit_any": true},
		coordinate_context,
		_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
	)
	assert(effect != null)
	assert(effect.visual_ready())
	assert(effect.get_child_count() == Visual.LAYER_COUNT)
	var children := effect.get_children()
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
	var descriptor := effect.presentation_descriptor()
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
	var effect := Visual.create_visual(
		snapshot,
		Geometry.SKILL_HALF_MOON,
		{"hit_any": true, "target_count": 99},
		coordinate_context,
		_ground_gu_to_screen_px(ORIGIN_GROUND_GU)
	)
	assert(effect != null)
	assert(effect.get_child_count() == Visual.LAYER_COUNT)
	var descriptor := effect.presentation_descriptor()
	var hit_info: Dictionary = descriptor.get("hit_info", {})
	assert(int(hit_info.get("target_count", 0)) == 99)
	assert(bool(hit_info.get("hit_any", false)))
	effect.free()


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


func _ground_gu_to_screen_px(ground_gu: Vector2) -> Vector2:
	return Vector2(ground_gu.x * 64.0, ground_gu.y * 32.0)
