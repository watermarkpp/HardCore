extends Node

const Geometry := preload("res://scripts/skills/warrior_melee_geometry.gd")
const Snapshot := preload("res://scripts/skills/skill_footprint_snapshot.gd")


func _ready() -> void:
	_verify_melee_release_shapes_in_all_directions()
	_verify_target_footprint_boundary_contact()
	_verify_wild_rush_swept_path()
	print(
		"WARRIOR_RELEASE_FOOTPRINT_SNAPSHOT_PASS: normal, fire, half-moon, "
		+ "thrust and wild-rush retain one immutable ground-GU release footprint"
	)
	get_tree().quit(0)


func _verify_melee_release_shapes_in_all_directions() -> void:
	var origin_ground_gu := Vector2(8.25, -3.75)
	for direction_index: int in range(8):
		for mode: String in [Geometry.SKILL_NORMAL, Geometry.SKILL_FIRE]:
			var snapshot := Geometry.attack_release_footprint_snapshot_ground_gu(
				"warrior.%s" % mode,
				"%s_%d" % [mode, direction_index],
				origin_ground_gu,
				direction_index,
				mode
			)
			_assert_snapshot(snapshot, Snapshot.SHAPE_SECTOR_ARC)
			assert(is_equal_approx(float(snapshot.radius_gu), 1.5))
			assert(is_equal_approx(float(snapshot.half_angle_radians), PI / 8.0))
			assert(
				(snapshot.direction_ground_gu as Vector2).is_equal_approx(
					Geometry.canonical_ground_direction_gu(direction_index)
				)
			)

		var half_moon := Geometry.attack_release_footprint_snapshot_ground_gu(
			"warrior.half_moon",
			"half_moon_%d" % direction_index,
			origin_ground_gu,
			direction_index,
			Geometry.SKILL_HALF_MOON
		)
		_assert_snapshot(half_moon, Snapshot.SHAPE_SECTOR_ARC)
		assert(is_equal_approx(float(half_moon.radius_gu), 1.5))
		assert(is_equal_approx(float(half_moon.half_angle_radians), PI / 2.0))
		assert(
			(half_moon.direction_ground_gu as Vector2).is_equal_approx(
				Geometry.canonical_ground_direction_gu(direction_index).rotated(
					PI / 8.0
				)
			)
		)

		var thrust := Geometry.attack_release_footprint_snapshot_ground_gu(
			"warrior.thrusting",
			"thrust_%d" % direction_index,
			origin_ground_gu,
			direction_index,
			Geometry.SKILL_THRUST
		)
		_assert_snapshot(thrust, Snapshot.SHAPE_DIRECTED_RECTANGLE)
		assert(is_equal_approx(float(thrust.effect_length_gu), 2.5))
		assert(is_equal_approx(float(thrust.effect_width_gu), 1.0))
		var plan := Geometry.thrust_damage_axis_plan_ground_gu(
			direction_index,
			{
				"release_id": "thrust_%d" % direction_index,
				"origin_ground_gu": origin_ground_gu,
			}
		)
		assert(plan.skill_footprint_snapshot == thrust)


func _verify_target_footprint_boundary_contact() -> void:
	var origin_ground_gu := Vector2.ZERO
	var target_radius_gu := 0.25
	for direction_index: int in range(8):
		var direction_ground_gu := Geometry.canonical_ground_direction_gu(
			direction_index
		)
		var normal := Geometry.attack_release_footprint_snapshot_ground_gu(
			"warrior.normal_attack",
			"normal_boundary_%d" % direction_index,
			origin_ground_gu,
			direction_index,
			Geometry.SKILL_NORMAL
		)
		assert(Geometry.release_snapshot_intersects_target_footprint_ground_gu(
			normal,
			direction_ground_gu * (1.5 + target_radius_gu),
			target_radius_gu
		))
		assert(not Geometry.release_snapshot_intersects_target_footprint_ground_gu(
			normal,
			direction_ground_gu * (1.5 + target_radius_gu + 0.001),
			target_radius_gu
		))


func _verify_wild_rush_swept_path() -> void:
	var snapshot := Geometry.wild_rush_release_footprint_snapshot_ground_gu(
		"wild_rush_release_42",
		Vector2(1.0, 2.0),
		Vector2(4.0, 2.0),
		0.30
	)
	_assert_snapshot(snapshot, Snapshot.SHAPE_SWEPT_CAPSULE_PATH)
	assert(snapshot.skill_id == "warrior.wild_rush")
	assert(snapshot.release_id == "wild_rush_release_42")
	assert(is_equal_approx(float(snapshot.effect_length_gu), 3.0))
	assert(is_equal_approx(float(snapshot.path_radius_gu), 0.30))
	assert(Geometry.release_snapshot_intersects_target_footprint_ground_gu(
		snapshot, Vector2(2.5, 2.50), 0.20
	))
	assert(not Geometry.release_snapshot_intersects_target_footprint_ground_gu(
		snapshot, Vector2(2.5, 2.501), 0.20
	))


func _assert_snapshot(snapshot: Dictionary, shape_type: String) -> void:
	assert(Snapshot.has_legacy_base_contract(snapshot))
	assert(snapshot.is_read_only())
	assert(snapshot.shape_type == shape_type)
	assert(snapshot.damage_space == "ground_gu")
	assert(snapshot.visual_space == "screen_px_derived_only")
	assert(not str(snapshot.release_id).is_empty())
