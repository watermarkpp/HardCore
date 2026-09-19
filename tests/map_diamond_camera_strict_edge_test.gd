extends Node

## R14-CAM-R2 BLACK-BUDGET REGION camera contract (user work order
## 2026-09-19, review of 7c2631d3), superseding the R14-CAM-R1 per-axis
## anchor box whose box boundary was not an iso-black surface and whose
## camera-to-strict distance did not bound the player-to-camera distance.
##   STEP 1 = zero-black ideal position (strict constrained solve,
##         unchanged math, still the reference solver and cache carrier).
##   STEP 2 = the fixed black-budget region guard: camera == player while
##         black(player) <= B (the unlock threshold event happens EXACTLY
##         when the centered view reaches the budget), then the camera is
##         the nearest point of the fixed convex budget region K_B
##         (intersected with the player display visibility box). No glide
##         ramp, no dynamic zoom; the frozen window caps only size the
##         budget. The early C1.5 unlock stays rejected by device ruling.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const VIEWPORT_HALF := Vector2(1332.0, 600.0)
const VIEWPORT_SIZE := VIEWPORT_HALF * 2.0
const FIXED_ZOOM := Vector2.ONE * 1.06
const FEASIBLE_SIZE := Vector2i(200, 200)
const PARITY_ITERATIONS := 10000


func _max_offset_px() -> Vector2:
	return CameraConstraint.visibility_max_offset_px(VIEWPORT_SIZE, FIXED_ZOOM)


var _raw_points: Array[Vector2] = []
var _raw_normals: Array[Vector2] = []
var _world_half := Vector2.ZERO


func _raw_deficit_px(point: Vector2) -> float:
	## Worst raw-map-diamond violation of the point (positive = outside).
	var worst := -INF
	for index in _raw_points.size():
		var margin := _raw_normals[index].dot(point - _raw_points[index])
		worst = maxf(worst, -margin)
	return worst


func _player_inside_map(point: Vector2) -> bool:
	return _raw_deficit_px(point) <= 0.01


func _camera_black_px(camera_center: Vector2) -> float:
	## The black exposure of a camera center: the worst eroded deficit over
	## the map edges (the viewport support added back on every edge).
	var worst := -INF
	for index in _raw_points.size():
		var normal := _raw_normals[index]
		var support := (
			absf(normal.x) * _world_half.x + absf(normal.y) * _world_half.y
		)
		var deficit := (
			normal.dot(_raw_points[index]) + support
			- normal.dot(camera_center)
		)
		worst = maxf(worst, deficit)
	return worst


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var boundary := CollisionGeometry.map_inner_boundary_world(FEASIBLE_SIZE)
	var centroid := Vector2.ZERO
	for point: Vector2 in boundary:
		centroid += point
	centroid /= float(boundary.size())

	# ===== STEP 1: the zero-black ideal solver (unchanged math) =====
	var ideal := CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, centroid
	)
	assert(
		ideal.is_equal_approx(centroid),
		"map-center ideal must equal the player"
	)
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	]
	for direction: Vector2 in directions:
		var half_span := 0.0
		for point: Vector2 in boundary:
			half_span = maxf(
				half_span, absf((point - centroid).dot(direction))
			)
		var clamped_once := false
		var previous_delta := -1.0
		for step: int in range(1, 13):
			var desired := (
				centroid + direction * (half_span * 1.5 * float(step) / 12.0)
			)
			var ideal_center := CameraConstraint.resolve_strict_follow_cached(
				FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
			)
			var delta := ideal_center.distance_to(desired)
			if delta > 0.01:
				clamped_once = true
			if previous_delta >= 0.0:
				assert(
					delta >= previous_delta - 0.01,
					"ideal delta must not shrink while the player walks out"
				)
			previous_delta = delta
		assert(clamped_once, "the ideal must clamp on the %s edge" % str(direction))
	for corner: Vector2 in boundary:
		var ideal_center := CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, corner
		)
		var offset_fraction := (
			Vector2(
				absf(ideal_center.x - corner.x),
				absf(ideal_center.y - corner.y)
			)
			* FIXED_ZOOM
			/ VIEWPORT_SIZE
		)
		assert(
			maxf(offset_fraction.x, offset_fraction.y) > 0.14,
			"the ideal must not retain any central band at corners"
		)

	# ===== STEP 2: the black-budget region guard (R14-CAM-R2) =====
	# The _raw_* geometry doubles as this test's INDEPENDENT black-depth
	# metric (the worst viewport overreach normal depth in world px) -
	# expected values are recomputed here, never produced by the guard.
	_raw_points.clear()
	_raw_normals.clear()
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		_raw_points.append(boundary[edge_index])
		_raw_normals.append(Vector2(-edge.y, edge.x).normalized())
	_world_half = Vector2(
		VIEWPORT_HALF.x / FIXED_ZOOM.x, VIEWPORT_HALF.y / FIXED_ZOOM.y
	)
	var test_base := maxf(0.0, _camera_black_px(centroid))
	var test_window := _max_offset_px() / FIXED_ZOOM
	var test_allowance := -INF
	for index: int in _raw_points.size():
		var normal := _raw_normals[index]
		test_allowance = maxf(
			test_allowance,
			absf(normal.x) * test_window.x
				+ absf(normal.y) * test_window.y
		)
	var test_cap := test_base + test_allowance
	# 1) center: guard is a no-op, camera == player.
	var guarded := CameraConstraint.apply_player_visibility_guard(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, centroid, Vector3.ZERO
	)
	assert(guarded.is_equal_approx(centroid), "center guard must be a no-op")
	# 2) center-lock walk: the player sits EXACTLY at the camera center
	# while the centered black depth is below the budget - including past
	# the zero-black anchor, where the superseded C1.5 guard already
	# glided. Once the centered black reaches the budget (the unlock
	# threshold event) the camera clamps into the fixed black-budget
	# region: the clamped camera black stays at the budget, and the guard
	# offset never overshoots the excursion (abs on BOTH axes - the
	# previous run compared an already-zoomed delta against a world-unit
	# window and left negative offsets unabs'd).
	var conflict_seen := 0
	for direction: Vector2 in directions:
		var half_span := 0.0
		for point: Vector2 in boundary:
			half_span = maxf(
				half_span, absf((point - centroid).dot(direction))
			)
		var unlock_seen := false
		var centered_past_anchor := false
		for step: int in range(1, 49):
			var desired := (
				centroid + direction * (half_span * 2.0 * float(step) / 48.0)
			)
			var ideal_center := CameraConstraint.resolve_strict_follow_cached(
				FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
			)
			var final_center := CameraConstraint.apply_player_visibility_guard(
				FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired, Vector3.ZERO
			)
			var centered_black := _camera_black_px(desired)
			var player_offset_px := (desired - final_center) * FIXED_ZOOM
			var player_delta_px := (desired - ideal_center) * FIXED_ZOOM
			assert(
				absf(player_offset_px.x) <= absf(player_delta_px.x) + 0.01
				and absf(player_offset_px.y) <= absf(player_delta_px.y) + 0.01,
				"the guard offset must not overshoot the excursion at %s" % desired
			)
			if centered_black <= test_cap - 0.5:
				assert(
					final_center.distance_to(desired) <= 0.001,
					"the camera must hold the player centered below the budget at %s (black %.2f vs cap %.2f)"
					% [desired, centered_black, test_cap]
				)
				if ideal_center.distance_to(desired) > 0.01:
					centered_past_anchor = true
			else:
				unlock_seen = true
				var clamped_black := _camera_black_px(final_center)
				var conflict: Dictionary = (
					CameraConstraint.last_visibility_conflict()
				)
				if conflict.is_empty():
					assert(
						clamped_black <= test_cap + 0.05,
						"the clamped camera must not exceed the budget at %s: %.3f vs %.3f"
						% [desired, clamped_black, test_cap]
					)
				else:
					# Degenerate far-out-of-map ladder probe: the player is
					# beyond the walkable region so far that even the K_B
					# nearest point would leave the (extent-zero) display
					# box - visibility wins by ruling, the black exceeds the
					# budget by the disclosed minimum, and the foot stays
					# inside the box.
					conflict_seen += 1
					assert(
						absf(desired.x - final_center.x)
							<= _world_half.x + 0.01
						and absf(desired.y - final_center.y)
							<= _world_half.y + 0.01,
						"the conflict fallback must keep the foot inside the display box at %s"
						% desired
					)
		assert(
			unlock_seen,
			"the walk must reach the unlock threshold on %s" % str(direction)
		)
		assert(
			centered_past_anchor,
			"the camera must stay centered past the zero-black anchor on %s"
			% str(direction)
		)
	# 3) threshold-crossing continuity (AUTO-SOLVED): the previous 1px scan
	# walked a hand-picked range (2560..2959) that never reached the unlock
	# (~5600 here), so it never crossed the branch. Bisect the unlock
	# threshold along +x, then walk single world px from below the
	# threshold to well past it: steps stay 1:1, the camera never recedes,
	# and the projection stays non-expansive across the unlock.
	var walk_direction := Vector2.RIGHT
	var bisect_lo := 0.0
	var bisect_hi := 0.0
	for point: Vector2 in boundary:
		bisect_hi = maxf(
			bisect_hi, absf((point - centroid).dot(walk_direction))
		)
	for _round in 60:
		var mid := (bisect_lo + bisect_hi) * 0.5
		var probe := centroid + walk_direction * mid
		var probe_camera := CameraConstraint.apply_player_visibility_guard(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, probe, Vector3.ZERO
		)
		if probe_camera.distance_to(probe) <= 1e-7:
			bisect_lo = mid
		else:
			bisect_hi = mid
	assert(
		absf(_camera_black_px(centroid + walk_direction * bisect_lo) - test_cap) <= 0.05,
		"the auto-solved unlock threshold must sit at the budget: %.3f vs %.3f"
		% [
			_camera_black_px(centroid + walk_direction * bisect_lo),
			test_cap,
		]
	)
	var walk_start := centroid + walk_direction * (bisect_lo - 2.0)
	var previous_final := Vector2.INF
	var previous_desired := Vector2.INF
	for step: int in range(0, 400):
		var desired := walk_start + walk_direction * float(step)
		var final_center := CameraConstraint.apply_player_visibility_guard(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired, Vector3.ZERO
		)
		if not previous_final.is_equal_approx(Vector2.INF):
			assert(
				final_center.distance_to(previous_final)
					<= desired.distance_to(previous_desired) + 1e-6,
				"the guard projection must be non-expansive at step %d" % step
			)
			assert(
				(final_center - previous_final).dot(walk_direction) >= -1e-6,
				"the camera must never recede while the player advances at step %d"
				% step
			)
		previous_final = final_center
		previous_desired = desired

	# ===== cache: single slot, value-compared, no per-frame rebuild =====
	CameraConstraint.clear_strict_cache()
	for _call in range(3):
		CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, centroid
		)
		CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, boundary[0]
		)
	assert(
		CameraConstraint.strict_cache_build_count() == 1,
		"repeated identical inputs must reuse the cached constraint geometry"
	)
	CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF * 1.1, FIXED_ZOOM, centroid
	)
	assert(
		CameraConstraint.strict_cache_build_count() == 2,
		"a viewport change must rebuild the cache once"
	)
	CameraConstraint.resolve_strict_follow_cached(
		Vector2i(201, 201), VIEWPORT_HALF, FIXED_ZOOM, centroid
	)
	assert(
		CameraConstraint.strict_cache_build_count() == 3,
		"a map size change must rebuild the cache once"
	)

	# ===== parity gate: >=10000 probes, without further cache rebuilds =====
	# Re-seat the single slot on the parity configuration first: the slot
	# currently holds the 201x201 entry, so one warm-up call is expected.
	CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, centroid
	)
	var builds_before_parity := CameraConstraint.strict_cache_build_count()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var span := float(FEASIBLE_SIZE.x) * 32.0
	for iteration: int in PARITY_ITERATIONS:
		var desired := Vector2(
			centroid.x + rng.randf_range(-span, span),
			centroid.y + rng.randf_range(-span, span)
		)
		var cached_center := CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
		)
		var reference: Dictionary = CameraConstraint.constrain_center(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
		)
		assert(
			Vector2(reference.get("center", Vector2.INF)).distance_to(
				cached_center
			) <= 0.0001,
			"cached solver diverged from the reference at %s" % desired
		)
	assert(
		CameraConstraint.strict_cache_build_count() == builds_before_parity,
		"the parity loop must not rebuild the constraint geometry"
	)

	# ===== source discipline gates =====
	var service_source := FileAccess.get_file_as_string(
		"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
	)
	assert(
		not service_source.contains("resolve_soft_follow")
		and not service_source.contains("tanh(")
		and not service_source.contains("recommended_zoom")
		and not service_source.contains("edge_pressure"),
		"the camera service must not retain the soft-follow path"
	)
	var game_root_source := FileAccess.get_file_as_string(
		"res://scripts/game_root.gd"
	)
	assert(
		not game_root_source.contains("resolve_soft_follow")
		and not game_root_source.contains("recommended_zoom")
		and game_root_source.contains("apply_player_visibility_guard"),
		"GameRoot must compose the strict ideal with the visibility guard"
	)
	print(
		"MAP_DIAMOND_CAMERA_STRICT_EDGE_PASS parity=%d guard_margin=%.2f cache_builds=%d budget=%.6f visibility_conflict_probes=%d"
		% [
			PARITY_ITERATIONS,
			CameraConstraint.PLAYER_VISIBLE_SCREEN_MARGIN,
			CameraConstraint.strict_cache_build_count(),
			test_cap,
			conflict_seen,
		]
	)
	get_tree().quit(0)
