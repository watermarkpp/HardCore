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

## C1.5 PROGRESSIVE FOLLOW (user device ruling 2026-09-16): SUPERSEDED.
## R14-CAM-R1 CENTER-LOCK UNTIL MAX BLACK (user ruling 2026-09-19): ruled
## the follow shape but its per-axis anchor box `clamp(player, strict +/- w)`
## is SUPERSEDED by R14-CAM-R2 after independent review of 7c2631d3: the
## box constrained the camera-to-strict distance, not the player-to-camera
## distance, so full-foot-legal map-tip positions pushed the player off
## screen (e.g. Ground (199,1) on a 200x200 map at 2664x1200 showed the
## player at x=2863.75), and the first unlock happened at only ~54%/41% of
## the declared black budget (strict is recomputed per player, so the box
## boundary is not an iso-black surface).
## R14-CAM-R2 BLACK-BUDGET REGION (review + user work order 2026-09-19):
## the maximum black exposure becomes a FIXED convex camera-center region
##   K_B = { c | for every map edge i:  n_i . (c - v_i) >= s_i - B }
## with the frozen budget
##   B = base + allowance
##     base      = max(0, max_i b_i(map centroid)) - the unavoidable black
##                 on maps too small for a zero-black solve; fixed by the
##                 frame, never follows the player;
##     allowance = max_i(|n_ix| w_x + |n_iy| w_y) - the frozen visibility
##                 window mirrored onto the black-DEPTH metric (max viewport
##                 overreach normal depth, world px), exactly the cap
##                 declared by 7c2631d3: 727.928726 world px at 2664x1200
##                 and 368.006161 at 1598x720 on the 200x200 map.
## Follow shape: camera = player while black(player) <= B - the unlock
## threshold event happens EXACTLY when the centered view reaches the
## budget (the K_B boundary is the iso-black surface black = B). Past it
## camera = the nearest point of K_B intersected with the player display
## visibility box V (the player's full display bounds stay inside the
## viewport). V is centered on the player, so it can never trigger or
## delay the unlock; it only constrains the post-unlock camera. If K_B and
## V have no intersection the visibility floor wins (the player never goes
## off screen) and the conflict is recorded for the caller via
## last_visibility_conflict(). Exact metric projection (unique nearest
## point, continuous, non-expansive), no glide ramp, no dynamic zoom.
## PROGRESSIVE_TRACK_FRACTION stays only as historical tuning context.
const PROGRESSIVE_TRACK_FRACTION := 0.6


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
## R14-CAM-R2: last K_B-vs-visibility conflict (empty when none). Set only
## when a fully visible camera cannot stay inside the black-budget region;
## production keeps the player visible in that case. Read via
## last_visibility_conflict(); tests clear it via clear_visibility_conflict().
static var _last_visibility_conflict: Dictionary = {}
## Reused clip scratch (main-thread camera path only; never grown beyond
## 8 vertices for a <=4-edge map region). No per-frame allocation.
static var _clip_scratch_a: Array[Vector2] = []
static var _clip_scratch_b: Array[Vector2] = []


static func last_visibility_conflict() -> Dictionary:
	return _last_visibility_conflict


static func clear_visibility_conflict() -> void:
	_last_visibility_conflict = {}


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
	## The same shared entry also carries the R14-CAM-R2 black-budget
	## region (cap + prebuilt K_B vertices).
	var entry := _ensure_entry(design_size, viewport_half_pixels, zoom)
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


static func _ensure_entry(
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2
) -> Dictionary:
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
	return _cached_entry


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
	design_size: Vector2i,
	viewport_half_pixels: Vector2,
	zoom: Vector2,
	player_center: Vector2,
	display_extent_px := Vector3.ZERO
) -> Vector2:
	## STEP 2 (R14-CAM-R2 black-budget region, see the header ruling):
	##   camera = player                            while black(player) <= B
	##   camera = nearest point of K_B ∩ V(player)  otherwise
	## K_B is the fixed black-budget region prebuilt in the shared cache;
	## V is the player display visibility box (world px, centered on the
	## player): the camera must keep the full display extent
	## (x = sideways half extent, y = above-foot, z = below-foot) inside
	## the viewport. V never triggers or delays the unlock (the player is
	## always inside its own box); it only constrains the post-unlock
	## camera. display_extent_px defaults to zero (foot-point visibility,
	## the review model's assumption); production passes the real measured
	## actor display geometry. Pure value math: no per-frame allocation
	## (reused clip scratch), exact metric projection.
	if (
		not is_finite(player_center.x)
		or not is_finite(player_center.y)
	):
		_last_visibility_conflict = {
			"reason": "non_finite_player_center",
			"player_center": player_center,
		}
		return _ensure_entry(
			design_size, viewport_half_pixels, zoom
		)["centroid"]
	if (
		not is_finite(viewport_half_pixels.x)
		or not is_finite(viewport_half_pixels.y)
		or not is_finite(zoom.x)
		or not is_finite(zoom.y)
		or zoom.x == 0.0
		or zoom.y == 0.0
		or design_size.x <= 0
		or design_size.y <= 0
	):
		# Degenerate frame: fail soft to ruled follow (the camera tracks
		# the player) and record the invalid input explicitly.
		_last_visibility_conflict = {
			"reason": "degenerate_viewport_or_zoom",
			"design_size": design_size,
			"viewport_half_pixels": viewport_half_pixels,
			"zoom": zoom,
		}
		return player_center
	var entry := _ensure_entry(design_size, viewport_half_pixels, zoom)
	var budget: float = entry["cap"]
	if _entry_black(entry, player_center) <= budget + 1e-9:
		_last_visibility_conflict = {}
		return player_center
	var half: Vector2 = entry["world_half"]
	var margin_x := maxf(0.0, half.x - display_extent_px.x)
	var margin_up := maxf(0.0, half.y - display_extent_px.y)
	var margin_down := maxf(0.0, half.y - display_extent_px.z)
	var kb_vertices: Array[Vector2] = entry["kb_vertices"]
	var clipped := _clip_to_visibility_box(
		kb_vertices, player_center, margin_x, margin_up, margin_down
	)
	if clipped.is_empty():
		# Visibility floor wins: the player never leaves the screen. Start
		# from the nearest black-budget point and pull it into the display
		# box per axis (the minimum-drift fully visible camera), recording
		# the exact contract conflict for the caller/report.
		var budget_point := _nearest_polygon_point(
			kb_vertices, player_center
		)
		_last_visibility_conflict = {
			"reason": "budget_region_and_display_box_disjoint",
			"player_center": player_center,
			"budget_world": budget,
			"display_extent_px": display_extent_px,
			"nearest_budget_point": budget_point,
			"camera": Vector2(
				clampf(
					budget_point.x,
					player_center.x - margin_x,
					player_center.x + margin_x
				),
				clampf(
					budget_point.y,
					player_center.y - margin_down,
					player_center.y + margin_up
				)
			),
		}
		return _last_visibility_conflict["camera"]
	_last_visibility_conflict = {}
	return _nearest_polygon_point(clipped, player_center)


static func _entry_black(entry: Dictionary, point: Vector2) -> float:
	## Black-depth metric (world px): the largest viewport overreach normal
	## depth over all map edges, 0 when the whole viewport is inside. The
	## unlock threshold is exactly black(player) = cap.
	var points: Array[Vector2] = entry["points"]
	var normals: Array[Vector2] = entry["normals"]
	var supports: Array[float] = entry["supports"]
	var worst := 0.0
	for index in points.size():
		var deficit := (
			supports[index]
			- normals[index].dot(point - points[index])
		)
		worst = maxf(worst, deficit)
	return worst


static func _clip_to_visibility_box(
	polygon: Array[Vector2],
	player_center: Vector2,
	margin_x: float,
	margin_up: float,
	margin_down: float
) -> Array[Vector2]:
	## Clips the prebuilt K_B polygon by the four display-box half-planes
	## (Sutherland-Hodgman, fixed <=8 vertices, reused scratch arrays).
	## Fast path: when every vertex already satisfies every plane the
	## cached polygon is returned untouched.
	var lower_x := player_center.x - margin_x
	var upper_x := player_center.x + margin_x
	var lower_y := player_center.y - margin_down
	var upper_y := player_center.y + margin_up
	var needs_clip := false
	for vertex: Vector2 in polygon:
		if (
			vertex.x < lower_x
			or vertex.x > upper_x
			or vertex.y < lower_y
			or vertex.y > upper_y
		):
			needs_clip = true
			break
	if not needs_clip:
		return polygon
	_clip_scratch_a.clear()
	_clip_scratch_a.append_array(polygon)
	_clip_scratch_a = _clip_halfplane(_clip_scratch_a, Vector2.RIGHT, lower_x)
	_clip_scratch_a = _clip_halfplane(_clip_scratch_a, Vector2.LEFT, -upper_x)
	_clip_scratch_a = _clip_halfplane(_clip_scratch_a, Vector2.DOWN, lower_y)
	_clip_scratch_a = _clip_halfplane(_clip_scratch_a, Vector2.UP, -upper_y)
	return _clip_scratch_a


static func _clip_halfplane(
	polygon: Array[Vector2],
	plane_normal: Vector2,
	plane_offset: float
) -> Array[Vector2]:
	## Keeps the polygon points with plane_normal . c >= plane_offset.
	var result := _clip_scratch_b
	result.clear()
	for index in polygon.size():
		var current := polygon[index]
		var following := polygon[(index + 1) % polygon.size()]
		var current_inside := plane_normal.dot(current) >= plane_offset
		var following_inside := plane_normal.dot(following) >= plane_offset
		if current_inside:
			result.append(current)
		if current_inside != following_inside:
			var edge := following - current
			var denom := plane_normal.dot(edge)
			var t := 0.0
			if absf(denom) >= 1e-12:
				t = clampf(
					(plane_offset - plane_normal.dot(current)) / denom,
					0.0,
					1.0
				)
			result.append(current + edge * t)
	_clip_scratch_b = _clip_scratch_a
	_clip_scratch_a = result
	return result


static func _nearest_polygon_point(
	polygon: Array[Vector2],
	point: Vector2
) -> Vector2:
	## Exact nearest point on a convex polygon (segment projections over
	## all edges; a segment or single-point degeneracy falls out naturally).
	if polygon.is_empty():
		return point
	if polygon.size() == 1:
		return polygon[0]
	var best_point := polygon[0]
	var best_distance := INF
	for index in polygon.size():
		var edge_start := polygon[index]
		var edge_end := polygon[(index + 1) % polygon.size()]
		var edge := edge_end - edge_start
		var square := edge.length_squared()
		var t := 0.0
		if square > 1e-20:
			t = clampf((point - edge_start).dot(edge) / square, 0.0, 1.0)
		var candidate := edge_start + edge * t
		var distance := candidate.distance_squared_to(point)
		if distance < best_distance:
			best_distance = distance
			best_point = candidate
	return best_point


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
	# R14-CAM-R2 black-budget region (fixed by the frame, never follows the
	# player): base = the unavoidable black at the centroid; allowance = the
	# frozen visibility window mirrored onto the black-depth metric.
	var base_black := 0.0
	for index in points.size():
		base_black = maxf(
			base_black,
			supports[index]
				- normals[index].dot(centroid - points[index])
		)
	var window_world := (
		visibility_max_offset_px(
			viewport_half_pixels * 2.0, safe_zoom
		) / safe_zoom
	)
	var allowance := 0.0
	for index in points.size():
		allowance = maxf(
			allowance,
			absf(normals[index].x) * window_world.x
				+ absf(normals[index].y) * window_world.y
		)
	var budget := base_black + allowance
	var kb_vertices := _kb_halfplane_vertices(
		points, normals, supports, budget
	)
	if kb_vertices.is_empty():
		# The budget region always contains the centroid (budget >=
		# black(centroid)); an empty vertex set can only come from a
		# degenerate float frame - fall back to the centroid point so the
		# guard stays defined.
		kb_vertices = [centroid]
	_strict_cache_builds += 1
	return {
		"points": points,
		"normals": normals,
		"supports": supports,
		"centroid": centroid,
		"feasible": feasible,
		"world_half": world_half_extents,
		"base_black": base_black,
		"window_world": window_world,
		"cap": budget,
		"kb_vertices": kb_vertices,
	}


static func _kb_halfplane_vertices(
	points: Array[Vector2],
	normals: Array[Vector2],
	supports: Array[float],
	budget: float
) -> Array[Vector2]:
	## Prebuilt convex intersection of the black-budget half-planes
	## { c | n_i . c >= n_i . v_i + s_i - B } (port of the review's
	## capped_region(): all pairwise line intersections that satisfy every
	## half-plane, then a convex hull). Fixed cost at cache-build time only.
	var offsets: Array[float] = []
	for index in points.size():
		offsets.append(
			normals[index].dot(points[index])
				+ supports[index]
				- budget
		)
	var candidates: Array[Vector2] = []
	for i in points.size():
		for j in range(i + 1, points.size()):
			var det := _cross(normals[i], normals[j])
			if absf(det) < 1e-12:
				continue
			var candidate := Vector2(
				(offsets[i] * normals[j].y - normals[i].y * offsets[j]) / det,
				(normals[i].x * offsets[j] - offsets[i] * normals[j].x) / det
			)
			var inside := true
			# Float32 Cramer noise: at offset magnitude ~2500 world px the
			# solved candidate's own-plane residual is ~1e-4 (float64 in the
			# review model allowed 1e-7). The vertex placement error stays
			# <= 1e-3 world px - far below any camera-perceptible scale -
			# while a tight tolerance would wrongly reject true vertices
			# and collapse the budget region.
			var inside_tolerance := 1e-3
			for k in points.size():
				if normals[k].dot(candidate) < offsets[k] - inside_tolerance:
					inside = false
					break
			if inside:
				candidates.append(candidate)
	return _convex_hull(candidates)


static func _convex_hull(points: Array[Vector2]) -> Array[Vector2]:
	if points.size() <= 2:
		return points.duplicate()
	var sorted_points := points.duplicate()
	sorted_points.sort()
	var lower: Array[Vector2] = []
	for point: Vector2 in sorted_points:
		while (
			lower.size() >= 2
			and _cross(lower[lower.size() - 1] - lower[lower.size() - 2], point - lower[lower.size() - 1]) <= 1e-9
		):
			lower.pop_back()
		lower.append(point)
	var upper: Array[Vector2] = []
	for index in range(sorted_points.size() - 1, -1, -1):
		var point: Vector2 = sorted_points[index]
		while (
			upper.size() >= 2
			and _cross(upper[upper.size() - 1] - upper[upper.size() - 2], point - upper[upper.size() - 1]) <= 1e-9
		):
			upper.pop_back()
		upper.append(point)
	var result: Array[Vector2] = []
	for index in lower.size() - 1:
		result.append(lower[index])
	for index in upper.size() - 1:
		result.append(upper[index])
	return result


static func _cross(a: Vector2, b: Vector2) -> float:
	return a.x * b.y - a.y * b.x


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
