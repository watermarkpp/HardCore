class_name WorldSpatialRules
extends RefCounted

# One collision contract for every runtime actor.  These values are bit masks,
# not the editor's one-based layer numbers.
const WORLD_LAYER := 1
const PLAYER_LAYER := 2
const ENEMY_LAYER := 4

const WORLD_MASK := WORLD_LAYER
const PLAYER_MASK := WORLD_LAYER | ENEMY_LAYER
const ENEMY_MASK := WORLD_LAYER | PLAYER_LAYER | ENEMY_LAYER


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
	for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
		if bool(provider.call("is_environment_point_blocked", position + direction * sample_radius)):
			return true
	return false
