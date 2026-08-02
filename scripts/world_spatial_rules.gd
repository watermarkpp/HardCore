class_name WorldSpatialRules
extends RefCounted

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

# One collision contract for every runtime actor.  These values are bit masks,
# not the editor's one-based layer numbers.
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4

const WORLD_MASK := WORLD_LAYER
const PLAYER_MASK := WORLD_LAYER | ENEMY_LAYER
const ENEMY_MASK := WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER

const ACTOR_FOOTPRINT_CONTRACT_ID := "world.actor_footprint.iso_ellipse.v1"
const ACTOR_GROUND_FOOTPRINT_CONTRACT_ID := (
	"world.actor_footprint.ground_circle_gu.v1"
)
const ACTOR_FOOTPRINT_Y_RATIO := 0.5
const ACTOR_FOOTPRINT_SEGMENTS := 16
const SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU := (
	GroundUnitSpaceScript.HALF_TILE_SIZE_PX.x * sqrt(2.0)
)


static func point_inside_safe_zone(point: Vector2, zone: Dictionary) -> bool:
	var polygon: PackedVector2Array = zone.get("polygon", PackedVector2Array())
	if str(zone.get("shape", "circle")) == "polygon" and polygon.size() >= 3:
		return Geometry2D.is_point_in_polygon(point, polygon)
	return point.distance_to(zone.get("center", Vector2.ZERO)) <= float(zone.get("radius", 0.0))


static func point_inside_safe_zones(point: Vector2, zones: Array) -> bool:
	for zone: Variant in zones:
		if zone is Dictionary and point_inside_safe_zone(point, zone):
			return true
	return false


static func point_inside_safe_zone_ground_gu(
	point_ground_gu: Vector2,
	zone: Dictionary
) -> bool:
	var raw_polygon: Variant = zone.get(
		"polygon_ground_gu", PackedVector2Array()
	)
	var polygon_ground_gu := (
		raw_polygon as PackedVector2Array
		if raw_polygon is PackedVector2Array
		else PackedVector2Array(raw_polygon)
	)
	if (
		str(zone.get("shape", "circle")) == "polygon"
		and polygon_ground_gu.size() >= 3
	):
		return Geometry2D.is_point_in_polygon(
			point_ground_gu, polygon_ground_gu
		)
	var center_ground_gu: Vector2 = zone.get(
		"center_ground_gu", Vector2.ZERO
	)
	return GroundUnitSpaceScript.is_within_range_gu(
		center_ground_gu,
		point_ground_gu,
		float(zone.get("radius_gu", 0.0))
	)


static func point_inside_safe_zones_ground_gu(
	point_ground_gu: Vector2,
	zones: Array
) -> bool:
	for zone: Variant in zones:
		if (
			zone is Dictionary
			and point_inside_safe_zone_ground_gu(point_ground_gu, zone)
		):
			return true
	return false


static func project_outside_safe_zones(point: Vector2, zones: Array, padding := 0.0) -> Vector2:
	var projected := point
	for zone: Variant in zones:
		if not zone is Dictionary or not point_inside_safe_zone(projected, zone):
			continue
		# Runtime combat safe areas are circles.  Polygon support remains a
		# conservative fallback for imported maps, but never invents a second
		# gameplay radius.
		if str(zone.get("shape", "circle")) == "circle":
			var center: Vector2 = zone.get("center", Vector2.ZERO)
			var offset := projected - center
			var direction := offset.normalized() if offset.length_squared() > 0.0001 else Vector2.DOWN
			projected = center + direction * (float(zone.get("radius", 0.0)) + padding)
	return projected


static func project_outside_safe_zones_ground_gu(
	point_ground_gu: Vector2,
	zones: Array,
	padding_gu := 0.0
) -> Vector2:
	var projected_ground_gu := point_ground_gu
	for zone: Variant in zones:
		if (
			not zone is Dictionary
			or not point_inside_safe_zone_ground_gu(
				projected_ground_gu, zone
			)
		):
			continue
		if str(zone.get("shape", "circle")) != "circle":
			continue
		var center_ground_gu: Vector2 = zone.get(
			"center_ground_gu", Vector2.ZERO
		)
		var direction_ground := GroundUnitSpaceScript.normalized_ground_direction(
			center_ground_gu,
			projected_ground_gu
		)
		projected_ground_gu = GroundUnitSpaceScript.endpoint_ground_gu(
			center_ground_gu,
			direction_ground,
			maxf(0.0, float(zone.get("radius_gu", 0.0)))
			+ maxf(0.0, padding_gu)
		)
	return projected_ground_gu


static func environment_blocks_actor(provider: Node, position: Vector2, radius: float) -> bool:
	if not is_instance_valid(provider) or not provider.has_method("is_environment_point_blocked"):
		return false
	if bool(provider.call("is_environment_point_blocked", position)):
		return true
	# Physics remains authoritative for sliding.  These samples are the common
	# deterministic fallback used by both player and monsters when collision
	# chunks are rebuilt or a spawn/teleport bypasses move_and_slide().
	var sample_radius := maxf(0.0, radius - 1.0)
	if sample_radius <= 0.0:
		return false
	for offset: Vector2 in actor_footprint_polygon(sample_radius):
		if bool(provider.call("is_environment_point_blocked", position + offset)):
			return true
	return false


static func actor_footprint_radii(radius: float) -> Vector2:
	var horizontal := maxf(0.0, radius)
	return Vector2(horizontal, horizontal * ACTOR_FOOTPRINT_Y_RATIO)


static func actor_combat_radius_gu_from_screen_radius_px(
	screen_horizontal_radius_px: float
) -> float:
	return (
		maxf(0.0, screen_horizontal_radius_px)
		/ SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU
	)


static func actor_screen_radius_px_from_combat_radius_gu(
	combat_radius_gu: float
) -> float:
	return (
		maxf(0.0, combat_radius_gu)
		* SCREEN_HORIZONTAL_RADIUS_PX_PER_COMBAT_RADIUS_GU
	)


static func actor_footprint_ground_polygon_gu(
	combat_radius_gu: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var safe_radius_gu := maxf(0.0, combat_radius_gu)
	var count := maxi(8, segments)
	var points_ground_gu := PackedVector2Array()
	for index: int in range(count):
		var angle := TAU * float(index) / float(count)
		points_ground_gu.append(
			Vector2.from_angle(angle) * safe_radius_gu
		)
	return points_ground_gu


static func actor_footprint_screen_polygon_px_from_combat_radius_gu(
	combat_radius_gu: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var points_screen_px := PackedVector2Array()
	for point_ground_gu: Vector2 in actor_footprint_ground_polygon_gu(
		combat_radius_gu,
		segments
	):
		points_screen_px.append(
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				point_ground_gu
			)
		)
	return points_screen_px


static func actor_footprint_polygon(
	radius: float,
	segments := ACTOR_FOOTPRINT_SEGMENTS
) -> PackedVector2Array:
	var radii := actor_footprint_radii(radius)
	var count := maxi(8, segments)
	var points := PackedVector2Array()
	for index in range(count):
		var angle := TAU * float(index) / float(count)
		points.append(Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	return points


static func actor_footprint_shape(radius: float) -> ConvexPolygonShape2D:
	var shape := ConvexPolygonShape2D.new()
	shape.points = actor_footprint_polygon(radius)
	return shape
