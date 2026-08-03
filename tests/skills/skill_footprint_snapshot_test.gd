extends Node

const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")
const WorldSpatialRules := preload("res://scripts/world_spatial_rules.gd")


func _ready() -> void:
	_verify_extensible_shape_classification()
	_verify_directed_rectangle_projection_at_angles()
	_verify_start_offset_projection_and_length()
	_verify_point_and_monster_radius_boundaries()
	_verify_common_shape_builders_and_footprint_contact()
	print(
		"SKILL_FOOTPRINT_SNAPSHOT_PASS: immutable ground-GU rectangles, sectors, "
		+ "circles, swept capsules and target footprints share derived PX projection"
	)
	get_tree().quit(0)


func _verify_extensible_shape_classification() -> void:
	for shape_type: String in Snapshot.SUPPORTED_SHAPE_TYPES:
		var classification := Snapshot.shape_classification(shape_type)
		assert(classification.supported_by_projection_api)
		assert(classification.damage_space == "ground_gu")
		assert(not classification.screen_px_damage_allowed)
		assert(classification.snapshot_builder_available)
	assert(Snapshot.SHAPE_SECTOR_ARC == "sector_arc")
	assert(Snapshot.SHAPE_CIRCLE == "circle")
	assert(Snapshot.SHAPE_SWEPT_CAPSULE_PATH == "swept_capsule_path")
	assert(Snapshot.SHAPE_TARGET_FOOTPRINT == "target_footprint")
	assert(Snapshot.SHAPE_CELL_UNION == "cell_union")


func _verify_directed_rectangle_projection_at_angles() -> void:
	var origin_ground_gu := Vector2(14.25, -8.75)
	# 144 samples exercise 2.5-degree increments; this includes every 5-degree
	# sample while covering projection behavior between the source art sectors.
	for sample_index: int in range(144):
		var direction_ground_gu := Vector2.from_angle(
			TAU * float(sample_index) / 144.0
		)
		var baseline := Snapshot.create_directed_rectangle(
			"test.directed_rectangle",
			"angle_%02d_baseline" % sample_index,
			origin_ground_gu,
			direction_ground_gu,
			8.0,
			1.0
		)
		assert(Snapshot.is_valid(baseline))
		assert(baseline.is_read_only())
		assert(baseline.shape_type == Snapshot.SHAPE_DIRECTED_RECTANGLE)
		assert(baseline.skill_id == "test.directed_rectangle")
		assert(baseline.release_id == "angle_%02d_baseline" % sample_index)
		assert(is_equal_approx(float(baseline.effect_length_gu), 8.0))
		assert(is_equal_approx(float(baseline.effect_width_gu), 1.0))
		assert((baseline.direction_ground_gu as Vector2).is_equal_approx(
			direction_ground_gu.normalized()
		))
		var polygon_ground_gu := Snapshot.ground_polygon_gu(baseline)
		var polygon_screen_offset_px := (
			Snapshot.projected_polygon_screen_offset_px(baseline)
		)
		assert(polygon_ground_gu.size() == 4)
		assert(polygon_screen_offset_px.size() == 4)
		for point_index: int in range(4):
			assert(polygon_screen_offset_px[point_index].is_equal_approx(
				GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
					polygon_ground_gu[point_index] - origin_ground_gu
				)
			))
		assert((baseline.axis_screen_offset_px as Vector2).is_equal_approx(
			GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu.normalized() * 8.0
			)
		))
		for repetition: int in range(20):
			var repeated := Snapshot.create_directed_rectangle(
				"test.directed_rectangle",
				"angle_%02d_repeat_%02d" % [sample_index, repetition],
				origin_ground_gu,
				direction_ground_gu,
				8.0,
				1.0
			)
			assert(Snapshot.ground_polygon_gu(repeated) == polygon_ground_gu)
			assert(
				Snapshot.projected_polygon_screen_offset_px(repeated)
				== polygon_screen_offset_px
			)


func _verify_start_offset_projection_and_length() -> void:
	var origin_ground_gu := Vector2(-3.25, 9.5)
	var direction_ground_gu := Vector2(0.3, -0.8).normalized()
	var snapshot := Snapshot.create_directed_rectangle(
		"test.directed_rectangle",
		"start_offset",
		origin_ground_gu,
		direction_ground_gu,
		5.0,
		1.0,
		0.5
	)
	assert(is_equal_approx(float(snapshot.start_offset_gu), 0.5))
	assert((snapshot.start_ground_gu as Vector2).is_equal_approx(
		origin_ground_gu + direction_ground_gu * 0.5
	))
	assert((snapshot.end_ground_gu as Vector2).is_equal_approx(
		origin_ground_gu + direction_ground_gu * 5.5
	))
	assert((snapshot.axis_start_screen_offset_px as Vector2).is_equal_approx(
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			direction_ground_gu * 0.5
		)
	))
	assert((snapshot.axis_screen_offset_px as Vector2).is_equal_approx(
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			direction_ground_gu * 5.5
		)
	))
	assert(is_equal_approx(
		float(snapshot.axis_screen_length_px),
		GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			direction_ground_gu * 5.0
		).length()
	))


func _verify_point_and_monster_radius_boundaries() -> void:
	var snapshot := Snapshot.create_directed_rectangle(
		"test.directed_rectangle",
		"boundaries",
		Vector2.ZERO,
		Vector2.RIGHT,
		8.0,
		1.0
	)
	for point_lateral_gu: float in [0.49, 0.50]:
		assert(Snapshot.intersects_target_polygon_ground_gu(
			snapshot,
			_target_polygon_ground_gu(Vector2(4.0, point_lateral_gu), 0.0)
		))
	assert(not Snapshot.intersects_target_polygon_ground_gu(
		snapshot,
		_target_polygon_ground_gu(Vector2(4.0, 0.51), 0.0)
	))

	for monster_radius_gu: float in [0.25, 0.33, 0.50]:
		var lateral_boundary_gu := 0.5 + monster_radius_gu
		for monster_lateral_gu: float in [
			lateral_boundary_gu - 0.001,
			lateral_boundary_gu,
		]:
			assert(Snapshot.intersects_target_polygon_ground_gu(
				snapshot,
				_target_polygon_ground_gu(
					Vector2(4.0, monster_lateral_gu), monster_radius_gu
				)
			))
		assert(not Snapshot.intersects_target_polygon_ground_gu(
			snapshot,
			_target_polygon_ground_gu(
				Vector2(4.0, lateral_boundary_gu + 0.001),
				monster_radius_gu
			)
		))
		var forward_boundary_gu := 8.0 + monster_radius_gu
		for monster_forward_gu: float in [
			forward_boundary_gu - 0.001,
			forward_boundary_gu,
		]:
			assert(Snapshot.intersects_target_polygon_ground_gu(
				snapshot,
				_target_polygon_ground_gu(
					Vector2(monster_forward_gu, 0.0), monster_radius_gu
				)
			))
		assert(not Snapshot.intersects_target_polygon_ground_gu(
			snapshot,
			_target_polygon_ground_gu(
				Vector2(forward_boundary_gu + 0.001, 0.0),
				monster_radius_gu
			)
		))
	for lateral_gu: float in [0.749, 0.750]:
		assert(Snapshot.intersects_target_combat_footprint_ground_gu(
			snapshot, Vector2(4.0, lateral_gu), 0.25
		))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		snapshot, Vector2(4.0, 0.751), 0.25
	))


func _verify_common_shape_builders_and_footprint_contact() -> void:
	var sector := Snapshot.create_sector_arc(
		"warrior.normal_attack",
		"sector_release",
		Vector2.ZERO,
		Vector2.RIGHT,
		1.5,
		PI / 8.0
	)
	_assert_projected_snapshot(sector, Snapshot.SHAPE_SECTOR_ARC)
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		sector, Vector2(1.45, 0.0), 0.10
	))
	for forward_gu: float in [1.599, 1.600]:
		assert(Snapshot.intersects_target_combat_footprint_ground_gu(
			sector, Vector2(forward_gu, 0.0), 0.10
		))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		sector, Vector2(1.601, 0.0), 0.10
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		sector, Vector2(0.0, 1.45), 0.10
	))

	var circle := Snapshot.create_circle(
		"wizard.hell_lightning",
		"circle_release",
		Vector2(2.0, -3.0),
		2.0
	)
	_assert_projected_snapshot(circle, Snapshot.SHAPE_CIRCLE)
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		circle, Vector2(4.249, -3.0), 0.25
	))
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		circle, Vector2(4.25, -3.0), 0.25
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		circle, Vector2(4.251, -3.0), 0.25
	))

	var capsule := Snapshot.create_swept_capsule_path(
		"wizard.fireball",
		"projectile_release",
		Vector2.ZERO,
		Vector2(3.0, 0.0),
		0.20
	)
	_assert_projected_snapshot(
		capsule, Snapshot.SHAPE_SWEPT_CAPSULE_PATH
	)
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		capsule, Vector2(1.5, 0.499), 0.30
	))
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		capsule, Vector2(1.5, 0.50), 0.30
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		capsule, Vector2(1.5, 0.501), 0.30
	))

	var target_footprint := Snapshot.create_target_footprint(
		"wizard.lightning",
		"target_release",
		Vector2(-2.0, 5.0),
		0.33,
		12345
	)
	_assert_projected_snapshot(
		target_footprint, Snapshot.SHAPE_TARGET_FOOTPRINT
	)
	assert(int(target_footprint.target_instance_id) == 12345)
	assert(
		target_footprint.target_footprint_contract_id
		== WorldSpatialRules.ACTOR_GROUND_FOOTPRINT_CONTRACT_ID
	)
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		target_footprint, Vector2(-1.341, 5.0), 0.33
	))
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		target_footprint, Vector2(-1.34, 5.0), 0.33
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		target_footprint, Vector2(-1.339, 5.0), 0.33
	))

	var cell_union := Snapshot.create_cell_union(
		"wizard.fire_wall",
		"cell_union_release",
		Vector2(0.25, -0.125),
		[Vector2i(0, 0), Vector2i(2, 0)]
	)
	assert(Snapshot.is_valid(cell_union))
	assert(cell_union.is_read_only())
	assert(cell_union.shape_type == Snapshot.SHAPE_CELL_UNION)
	var union_polygons_ground_gu := Snapshot.ground_polygons_gu(cell_union)
	var union_polygons_screen_offset_px := (
		Snapshot.projected_polygons_screen_offset_px(cell_union)
	)
	assert(union_polygons_ground_gu.size() == 2)
	assert(union_polygons_screen_offset_px.size() == 2)
	for polygon_index: int in range(2):
		assert(union_polygons_ground_gu[polygon_index].size() == 4)
		for corner_index: int in range(4):
			assert(
				union_polygons_screen_offset_px[polygon_index][corner_index]
				.is_equal_approx(
					GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
						union_polygons_ground_gu[polygon_index][corner_index]
						- Vector2(0.25, -0.125)
					)
				)
			)
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		cell_union, Vector2(0.599, 0.0), 0.10
	))
	assert(Snapshot.intersects_target_combat_footprint_ground_gu(
		cell_union, Vector2(0.60, 0.0), 0.10
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		cell_union, Vector2(0.601, 0.0), 0.10
	))
	assert(not Snapshot.intersects_target_combat_footprint_ground_gu(
		cell_union, Vector2(1.0, 0.0), 0.10
	))


func _assert_projected_snapshot(
	snapshot: Dictionary,
	expected_shape_type: String
) -> void:
	assert(Snapshot.is_valid(snapshot))
	assert(snapshot.is_read_only())
	assert(str(snapshot.shape_type) == expected_shape_type)
	var polygon_ground_gu := Snapshot.ground_polygon_gu(snapshot)
	var polygon_screen_offset_px := (
		Snapshot.projected_polygon_screen_offset_px(snapshot)
	)
	assert(polygon_ground_gu.size() >= 3)
	assert(polygon_ground_gu.size() == polygon_screen_offset_px.size())
	var origin_ground_gu: Vector2 = snapshot.origin_ground_gu
	for index: int in range(polygon_ground_gu.size()):
		assert(polygon_screen_offset_px[index].is_equal_approx(
			GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
				polygon_ground_gu[index] - origin_ground_gu
			)
		))


func _target_polygon_ground_gu(
	center_ground_gu: Vector2,
	radius_gu: float
) -> PackedVector2Array:
	var polygon_ground_gu := PackedVector2Array()
	for offset_ground_gu: Vector2 in (
		WorldSpatialRules.actor_footprint_ground_polygon_gu(radius_gu)
	):
		polygon_ground_gu.append(center_ground_gu + offset_ground_gu)
	return polygon_ground_gu
