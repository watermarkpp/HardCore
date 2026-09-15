class_name MapDiamondCameraConstraintService
extends RefCounted

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const CONTRACT_ID := "map_diamond_camera_center_constraint_v2"
const STRICT_FOLLOW_CONTRACT_ID := "map_diamond_camera_strict_edge_follow_v1"
const EDGE_SKIRT_CONTRACT_ID := "map_runtime_nonwalkable_edge_skirt_v1"
const PROJECTION_ITERATIONS := 32
const EPSILON := 0.01


## C1 CAMERA-EDGE (user ruling 2026-09-16): strict map-edge follow. The
## gameplay camera uses ONE global view height and its center is the
## CONSTRAINED legal center from constrain_center(): inside the map the
## camera equals the player; at the map edge the camera stops at the last
## legal center while the player keeps walking and may leave the screen
## center, minimizing the black area shown outside the map. The former
## player_priority_soft_edge_v1 behaviour (14% tanh central band, edge
## pressure, recommended-zoom blend) is removed by explicit ruling: no
## dynamic zoom exists anywhere in this path.
static var _strict_cache: Dictionary = {}
static var _strict_cache_builds := 0


static func clear_strict_cache() -> void:
	_strict_cache.clear()
	_strict_cache_builds = 0


static func strict_cache_build_count() -> int:
	return _strict_cache_builds


static func resolve_strict_follow_cached(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2,
	desired_center: Vector2
) -> Vector2:
	## Per-frame camera entry. The constraint geometry is cached per
	## (design_size, viewport, zoom) and the solve runs over flat arrays
	## with the exact projection math of constrain_center(), so the
	## returned center matches the reference solver and the per-frame
	## path allocates nothing (no boundary, no Dictionary, no Array).
	var entry: Dictionary = _strict_cache_entry(
		design_size, viewport_half_pixels, zoom
	)
	if not bool(entry["feasible"]):
		return entry["centroid"]
	var points: Array[Vector2] = entry["points"]
	var normals: Array[Vector2] = entry["normals"]
	var supports: Array[float] = entry["supports"]
	var result_center := desired_center
	for _iteration in PROJECTION_ITERATIONS:
		var changed := false
		for index in points.size():
			var margin := (
				normals[index].dot(result_center - points[index])
				- supports[index]
			)
			var deficit := -margin
			if deficit > EPSILON:
				result_center += normals[index] * deficit
				changed = true
		if not changed:
			break
	return result_center


static func _strict_cache_key(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2
) -> String:
	return "%s|%s|%s" % [design_size, viewport_half_pixels, zoom]


static func _strict_cache_entry(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2
) -> Dictionary:
	var key := _strict_cache_key(design_size, viewport_half_pixels, zoom)
	var cached: Variant = _strict_cache.get(key)
	if cached is Dictionary:
		return cached
	var boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	var safe_zoom := Vector2(
		maxf(absf(zoom.x), 0.0001),
		maxf(absf(zoom.y), 0.0001)
	)
	var world_half_extents := Vector2(
		absf(viewport_half_pixels.x) / safe_zoom.x,
		absf(viewport_half_pixels.y) / safe_zoom.y
	)
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	var supports: Array[float] = []
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		var inward := Vector2(-edge.y, edge.x).normalized()
		var viewport_support := (
			absf(inward.x) * world_half_extents.x
			+ absf(inward.y) * world_half_extents.y
		)
		points.append(boundary[edge_index])
		normals.append(inward)
		supports.append(viewport_support)
	var centroid := _centroid(boundary)
	var feasible := true
	for index in points.size():
		var margin := (
			normals[index].dot(centroid - points[index]) - supports[index]
		)
		if margin < -EPSILON:
			feasible = false
			break
	_strict_cache_builds += 1
	var entry: Dictionary = {
		"points": points,
		"normals": normals,
		"supports": supports,
		"centroid": centroid,
		"feasible": feasible,
	}
	_strict_cache[key] = entry
	return entry


static func constrain_center(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2,
	desired_center: Vector2
) -> Dictionary:
	var boundary := CollisionGeometry.map_inner_boundary_world(
		design_size
	)
	var safe_zoom := Vector2(maxf(absf(zoom.x), 0.0001), maxf(absf(zoom.y), 0.0001))
	var world_half_extents := Vector2(
		absf(viewport_half_pixels.x) / safe_zoom.x,
		absf(viewport_half_pixels.y) / safe_zoom.y
	)
	var constraints := _inward_constraints(boundary, world_half_extents)
	var centroid := _centroid(boundary)
	var feasible := true
	for constraint: Dictionary in constraints:
		if _margin(centroid, constraint) < -EPSILON:
			feasible = false
			break
	var result_center := desired_center
	if feasible:
		for _iteration in PROJECTION_ITERATIONS:
			var changed := false
			for constraint: Dictionary in constraints:
				var deficit := -_margin(result_center, constraint)
				if deficit > EPSILON:
					result_center += Vector2(constraint.normal) * deficit
					changed = true
			if not changed:
				break
	else:
		result_center = centroid
	var maximum_violation := 0.0
	for constraint: Dictionary in constraints:
		maximum_violation = maxf(
			maximum_violation, -_margin(result_center, constraint)
		)
	return {
		"contract_id": CONTRACT_ID,
		"ok": feasible and maximum_violation <= EPSILON,
		"center": result_center,
		"desired_center": desired_center,
		"world_half_extents": world_half_extents,
		"minimum_uniform_zoom": minimum_uniform_zoom(
			boundary, viewport_half_pixels
		),
		"maximum_violation": maxf(0.0, maximum_violation),
		"boundary": boundary,
	}


static func minimum_uniform_zoom(
	boundary: PackedVector2Array,
	viewport_half_pixels: Vector2
) -> float:
	var centroid := _centroid(boundary)
	var required := 0.0
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		var inward := Vector2(-edge.y, edge.x).normalized()
		var available := inward.dot(centroid - boundary[edge_index])
		if available <= EPSILON:
			return INF
		var pixel_support := (
			absf(inward.x) * absf(viewport_half_pixels.x)
			+ absf(inward.y) * absf(viewport_half_pixels.y)
		)
		required = maxf(required, pixel_support / available)
	return required


static func viewport_corners(
	center: Vector2,
	world_half_extents: Vector2
) -> PackedVector2Array:
	return PackedVector2Array([
		center + Vector2(-world_half_extents.x, -world_half_extents.y),
		center + Vector2(world_half_extents.x, -world_half_extents.y),
		center + Vector2(world_half_extents.x, world_half_extents.y),
		center + Vector2(-world_half_extents.x, world_half_extents.y),
	])


static func viewport_inside_boundary(result: Dictionary) -> bool:
	if not bool(result.get("ok", false)):
		return false
	var boundary: PackedVector2Array = result.get(
		"boundary", PackedVector2Array()
	)
	var center: Vector2 = result.get("center", Vector2.ZERO)
	var half_extents: Vector2 = result.get(
		"world_half_extents", Vector2.ZERO
	)
	for corner: Vector2 in viewport_corners(center, half_extents):
		if not Geometry2D.is_point_in_polygon(corner, boundary):
			# Geometry2D may classify an exact edge as outside. Accept it when all
			# contracted half-plane margins remain within numerical tolerance.
			for constraint: Dictionary in _inward_constraints(
				boundary, Vector2.ZERO
			):
				if _margin(corner, constraint) < -EPSILON:
					return false
	return true


static func _inward_constraints(
	boundary: PackedVector2Array,
	world_half_extents: Vector2
) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		var inward := Vector2(-edge.y, edge.x).normalized()
		var viewport_support := (
			absf(inward.x) * world_half_extents.x
			+ absf(inward.y) * world_half_extents.y
		)
		result.append({
			"point": boundary[edge_index],
			"normal": inward,
			"support": viewport_support,
		})
	return result


static func _margin(point: Vector2, constraint: Dictionary) -> float:
	return (
		Vector2(constraint.normal).dot(
			point - Vector2(constraint.point)
		)
		- float(constraint.support)
	)


static func _centroid(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in polygon:
		result += point
	return result / float(maxi(1, polygon.size()))
