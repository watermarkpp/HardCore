class_name MapDiamondCameraConstraintService
extends RefCounted

const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const CONTRACT_ID := "map_diamond_camera_center_constraint_v2"
const SOFT_FOLLOW_MODE_ID := "player_priority_soft_edge_v1"
const EDGE_SKIRT_CONTRACT_ID := "map_runtime_nonwalkable_edge_skirt_v1"
const PROJECTION_ITERATIONS := 32
const EPSILON := 0.01
const DEFAULT_PLAYER_SCREEN_OFFSET_FRACTION := 0.14
const MIN_PLAYER_SCREEN_OFFSET_FRACTION := 0.12
const MAX_PLAYER_SCREEN_OFFSET_FRACTION := 0.15
const DEFAULT_MAXIMUM_ZOOM := 1.16


static func resolve_soft_follow(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	base_zoom: Vector2,
	player_center: Vector2,
	maximum_zoom := DEFAULT_MAXIMUM_ZOOM,
	player_screen_offset_fraction := DEFAULT_PLAYER_SCREEN_OFFSET_FRACTION
) -> Dictionary:
	var safe_base_zoom := Vector2(
		maxf(absf(base_zoom.x), 0.0001),
		maxf(absf(base_zoom.y), 0.0001)
	)
	var offset_fraction := clampf(
		player_screen_offset_fraction,
		MIN_PLAYER_SCREEN_OFFSET_FRACTION,
		MAX_PLAYER_SCREEN_OFFSET_FRACTION
	)
	var maximum_zoom_value := maxf(
		maxf(safe_base_zoom.x, safe_base_zoom.y),
		maximum_zoom
	)
	var maximum_offset_pixels := (
		viewport_half_pixels * 2.0 * offset_fraction
	)
	var strict_at_base := constrain_center(
		design_size, viewport_half_pixels, safe_base_zoom, player_center
	)
	var base_strict_center := Vector2(
		strict_at_base.get("center", player_center)
	)
	var base_strict_offset_pixels := Vector2(
		absf(base_strict_center.x - player_center.x) * safe_base_zoom.x,
		absf(base_strict_center.y - player_center.y) * safe_base_zoom.y
	)
	var raw_pressure := maxf(
		base_strict_offset_pixels.x / maxf(maximum_offset_pixels.x, EPSILON),
		base_strict_offset_pixels.y / maxf(maximum_offset_pixels.y, EPSILON)
	)
	# Exponential pressure and cubic smoothing keep both the zoom target and
	# its first derivative continuous when the actor enters an edge region.
	var edge_pressure := 1.0 - exp(-maxf(0.0, raw_pressure))
	var zoom_blend := (
		edge_pressure * edge_pressure * (3.0 - 2.0 * edge_pressure)
	)
	var recommended_zoom_value := lerpf(
		maxf(safe_base_zoom.x, safe_base_zoom.y),
		maximum_zoom_value,
		zoom_blend
	)
	var recommended_zoom := Vector2.ONE * recommended_zoom_value
	var strict := constrain_center(
		design_size, viewport_half_pixels, recommended_zoom, player_center
	)
	var strict_center := Vector2(strict.get("center", player_center))
	var maximum_offset_world := Vector2(
		maximum_offset_pixels.x / recommended_zoom.x,
		maximum_offset_pixels.y / recommended_zoom.y
	)
	var strict_delta := strict_center - player_center
	# tanh is a continuous saturating clamp. It retains the strict solution as
	# the reference direction while guaranteeing that the actor never leaves
	# the central 72% x 72% screen region (14% maximum offset per axis).
	var soft_delta := Vector2(
		_soft_saturate(strict_delta.x, maximum_offset_world.x),
		_soft_saturate(strict_delta.y, maximum_offset_world.y)
	)
	var soft_center := player_center + soft_delta
	var player_screen_offset_pixels := Vector2(
		absf(soft_delta.x) * recommended_zoom.x,
		absf(soft_delta.y) * recommended_zoom.y
	)
	var world_half_extents := Vector2(
		absf(viewport_half_pixels.x) / recommended_zoom.x,
		absf(viewport_half_pixels.y) / recommended_zoom.y
	)
	var boundary := CollisionGeometry.map_inner_boundary_world(design_size)
	var exposure := _exposure_metrics(
		boundary, soft_center, world_half_extents
	)
	return {
		"contract_id": CONTRACT_ID,
		"mode_id": SOFT_FOLLOW_MODE_ID,
		"edge_skirt_contract_id": EDGE_SKIRT_CONTRACT_ID,
		"ok": true,
		"center": soft_center,
		"player_center": player_center,
		"strict_center": strict_center,
		"strict_ok": bool(strict.get("ok", false)),
		"strict_reference": strict,
		"recommended_zoom": recommended_zoom,
		"edge_pressure": edge_pressure,
		"maximum_player_screen_offset_pixels": maximum_offset_pixels,
		"player_screen_offset_pixels": player_screen_offset_pixels,
		"player_screen_offset_fraction": offset_fraction,
		"world_half_extents": world_half_extents,
		"outside_depth_world": float(exposure.outside_depth_world),
		"required_guard_band_world": float(
			exposure.required_guard_band_world
		),
		"boundary": boundary,
	}


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


static func _soft_saturate(value: float, limit: float) -> float:
	if limit <= EPSILON:
		return 0.0
	return limit * tanh(value / limit)


static func _exposure_metrics(
	boundary: PackedVector2Array,
	center: Vector2,
	world_half_extents: Vector2
) -> Dictionary:
	var boundary_bounds := Rect2(boundary[0], Vector2.ZERO)
	for point: Vector2 in boundary:
		boundary_bounds = boundary_bounds.expand(point)
	var viewport_points := viewport_corners(center, world_half_extents)
	var outside_depth_world := 0.0
	var required_guard_band_world := 0.0
	var boundary_constraints := _inward_constraints(
		boundary, Vector2.ZERO
	)
	for point: Vector2 in viewport_points:
		for constraint: Dictionary in boundary_constraints:
			outside_depth_world = maxf(
				outside_depth_world, -_margin(point, constraint)
			)
		required_guard_band_world = maxf(
			required_guard_band_world,
			maxf(
				maxf(
					boundary_bounds.position.x - point.x,
					point.x - boundary_bounds.end.x
				),
				maxf(
					boundary_bounds.position.y - point.y,
					point.y - boundary_bounds.end.y
				)
			)
		)
	return {
		"outside_depth_world": maxf(0.0, outside_depth_world),
		"required_guard_band_world": maxf(
			0.0, required_guard_band_world
		),
	}


static func _centroid(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in polygon:
		result += point
	return result / float(maxi(1, polygon.size()))
