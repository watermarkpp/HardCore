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
## C1.4 visibility guard tuning (user device screenshot ruling 2026-09-16):
## the user's counting unit is now pinned: ONE ground grid cell is 64x32
## world px, and VERTICAL distances are counted in the cell's 32-px vertical
## extent. The character is TWO vertical cells tall (2 x 32 = 64 world px,
## confirmed by the 2664x1200 device capture). Every user margin figure is
## in those vertical cells; the previous build used 4 x 64 = 256 world px,
## i.e. EIGHT user cells - double the agreed 4-cell ceiling, which is why
## the pinned head sat "at least six cells" (user counting) below the bar.
## Measured facts in user cells: the actual monster HP bar panel is ~2.7
## cells deep (87.7 world px, deeper than the 1.5-cell estimate), so
## never-covered needs bar 2.7 + body 2.0 ~= 4.7 cells. Ruling (user
## delegated, comfort first): margin = SIX user cells = 192 world px - the
## body top keeps a visible ~40 world px gap below the bar while the
## head-to-bar-top visual gap halves from ~6 to ~3.4 cells.
## Constant naming (remote review 2026-09-16, non-blocking cleanup): the
## margin is expressed in the user's VERTICAL grid cells (32 world px each)
## so the previous two-fold unit confusion (tile-width vs vertical cell)
## cannot recur. The user-accepted values are frozen: 0.15 fraction and
## six vertical cells = 192 world px. Do not retune without a new user
## device ruling.
const PLAYER_VISIBLE_SCREEN_MARGIN := 0.15
const PLAYER_MIN_VISIBLE_VERTICAL_CELL_COUNT := 6.0
const VERTICAL_CELL_WORLD_PX := 32.0


## C1/C1.1 CAMERA-EDGE (user ruling 2026-09-16, GPT audit): two-step edge
## follow. STEP 1 is the zero-black ideal position (strict solver below):
## where the camera should be if only minimizing the black area outside the
## map mattered. STEP 2 is the player visibility guard: the hard constraint
## is that the player stays comfortably visible; minimizing black is the
## OPTIMIZATION GOAL, not a hard zero-black contract. The camera re-follows
## the player by exactly the amount that exceeds the visibility window —
## and no more — so any black area shown is the minimum required to keep
## the player visible. No dynamic zoom exists anywhere in this path.
static var _cached_design_size := Vector2i.ZERO
static var _cached_viewport_half := Vector2.ZERO
static var _cached_zoom := Vector2.ZERO
static var _cached_entry: Dictionary = {}
static var _cache_valid := false
static var _strict_cache_builds := 0


static func clear_strict_cache() -> void:
	_cached_entry = {}
	_cache_valid = false
	_strict_cache_builds = 0


static func strict_cache_build_count() -> int:
	return _strict_cache_builds


static func resolve_strict_follow_cached(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2,
	desired_center: Vector2
) -> Vector2:
	## STEP 1: zero-black ideal center. Single-slot cache compared by plain
	## values (design size, viewport half, zoom): the hit path constructs no
	## String, Dictionary or Array — it only compares values and projects
	## over prebuilt flat arrays. Rebuilt only when the map, the viewport or
	## the zoom actually changes. The solve uses the exact projection math
	## of constrain_center(), so the result matches the reference solver.
	if (
		not _cache_valid
		or _cached_design_size != design_size
		or _cached_viewport_half != viewport_half_pixels
		or _cached_zoom != zoom
	):
		_cached_entry = _build_strict_entry(
			design_size, viewport_half_pixels, zoom
		)
		_cached_design_size = design_size
		_cached_viewport_half = viewport_half_pixels
		_cached_zoom = zoom
		_cache_valid = true
	var entry: Dictionary = _cached_entry
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


static func visibility_max_offset_px(
	viewport_size: Vector2,
	zoom: Vector2
) -> Vector2:
	## Single source of truth for the visibility window, per axis. BOTH
	## rules must hold, so the offset limit is the MIN of:
	##   comfort fraction: offset <= (0.5 - 15%) x viewport axis
	##   cell floor:       viewport/2 - offset >= 4 cells (screen px)
	## i.e. the player stays >= 15% AND >= 4 ground cells from every edge.
	## The previous build combined them with max(), which silently disabled
	## the cell floor (max() relaxes; only min() enforces both).
	var safe_zoom := Vector2(
		maxf(absf(zoom.x), 0.0001),
		maxf(absf(zoom.y), 0.0001)
	)
	var fraction_px := Vector2(
		maxf(0.0, 0.5 - PLAYER_VISIBLE_SCREEN_MARGIN)
		* maxf(viewport_size.x, 1.0),
		maxf(0.0, 0.5 - PLAYER_VISIBLE_SCREEN_MARGIN)
		* maxf(viewport_size.y, 1.0)
	)
	var ground_cell_floor_px := (
		PLAYER_MIN_VISIBLE_VERTICAL_CELL_COUNT
		* VERTICAL_CELL_WORLD_PX
	)
	var floor_offset_px := Vector2(
		maxf(
			0.0,
			maxf(viewport_size.x, 1.0) * 0.5
			- ground_cell_floor_px * safe_zoom.x
		),
		maxf(
			0.0,
			maxf(viewport_size.y, 1.0) * 0.5
			- ground_cell_floor_px * safe_zoom.y
		)
	)
	return Vector2(
		minf(fraction_px.x, floor_offset_px.x),
		minf(fraction_px.y, floor_offset_px.y)
	)


static func apply_player_visibility_guard(
	strict_center: Vector2,
	player_center: Vector2,
	zoom: Vector2,
	viewport_size: Vector2
) -> Vector2:
	## STEP 2: player visibility guard over the zero-black ideal center.
	## The player's screen offset from the ideal center is clamped to the
	## visibility window; the camera re-follows by exactly the excess. When
	## the player is inside the window the camera stays on the ideal center
	## (zero black). Pure value math: no allocation on the per-frame path.
	var safe_zoom := Vector2(
		maxf(absf(zoom.x), 0.0001),
		maxf(absf(zoom.y), 0.0001)
	)
	var max_offset_px := visibility_max_offset_px(viewport_size, safe_zoom)
	var player_delta_px := (player_center - strict_center) * safe_zoom
	var visible_delta_px := Vector2(
		clampf(player_delta_px.x, -max_offset_px.x, max_offset_px.x),
		clampf(player_delta_px.y, -max_offset_px.y, max_offset_px.y)
	)
	return player_center - visible_delta_px / safe_zoom


static func _build_strict_entry(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2
) -> Dictionary:
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
	return {
		"points": points,
		"normals": normals,
		"supports": supports,
		"centroid": centroid,
		"feasible": feasible,
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


static func _centroid(polygon: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in polygon:
		result += point
	return result / float(maxi(1, polygon.size()))
