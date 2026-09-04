extends Node

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")


func _ready() -> void:
	_verify_actor_footprint_round_trip()
	_verify_ground_safe_zone_is_direction_invariant()
	_verify_ground_safe_zone_projection()
	print("WORLD_SPATIAL_GROUND_UNIT_PASS: ground radii and safe zones preserve the accepted PX footprint")
	get_tree().quit(0)


func _verify_actor_footprint_round_trip() -> void:
	for screen_radius_px: float in [8.0, 16.0, 18.0, 28.0]:
		var combat_radius_gu := (
			WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px(
				screen_radius_px
			)
		)
		assert(is_equal_approx(
			WorldSpatialRules.actor_screen_radius_px_from_combat_radius_gu(
				combat_radius_gu
			),
			screen_radius_px
		))
		var projected := (
			WorldSpatialRules.actor_footprint_screen_polygon_px_from_combat_radius_gu(
				combat_radius_gu,
				64
			)
		)
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for point_px: Vector2 in projected:
			minimum = minimum.min(point_px)
			maximum = maximum.max(point_px)
		var radii_px := (maximum - minimum) * 0.5
		assert(is_equal_approx(radii_px.x, screen_radius_px))
		assert(is_equal_approx(
			radii_px.y,
			screen_radius_px * WorldSpatialRules.ACTOR_FOOTPRINT_Y_RATIO
		))


func _verify_ground_safe_zone_is_direction_invariant() -> void:
	var zone := {
		"shape": "circle",
		"center_ground_gu": Vector2(20.0, 30.0),
		"radius_gu": 9.0,
	}
	for direction_index: int in range(32):
		var direction_ground := Vector2.from_angle(
			TAU * float(direction_index) / 32.0
		)
		assert(WorldSpatialRules.point_inside_safe_zone_ground_gu(
			zone.center_ground_gu + direction_ground * 9.0,
			zone
		))
		assert(not WorldSpatialRules.point_inside_safe_zone_ground_gu(
			zone.center_ground_gu + direction_ground * 9.01,
			zone
		))


func _verify_ground_safe_zone_projection() -> void:
	var zone := {
		"shape": "circle",
		"center_ground_gu": Vector2(4.0, -3.0),
		"radius_gu": 3.0,
	}
	var projected := WorldSpatialRules.project_outside_safe_zones_ground_gu(
		Vector2(4.0, -3.0),
		[zone],
		0.5
	)
	assert(is_equal_approx(
		GroundUnitSpaceScript.distance_gu(zone.center_ground_gu, projected),
		3.5
	))
