extends Node

## R14-CAM-R1 CAMERA-EDGE center-lock contract (user device ruling
## 2026-09-19): the camera has ONE hard constraint and ONE ruled follow
## shape.
##   Hard: the player stays inside the visibility window of every screen
##         axis - at least 15% from every edge (central 70%) and never
##         closer than two ground cells.
##   Shape: the player stays EXACTLY at the camera center while walking
##         toward the map edge; the black exposure grows 1:1 with the
##         excursion. The camera only clamps (the unlock threshold event)
##         once the centered view exposes the same maximum black area the
##         superseded C1.5 progressive follow converged to at the walkable
##         edge (support + ride reserve projected on the violated edge).
##         The early glide unlock of C1.5 is rejected by device ruling.
## STEP 1 = zero-black ideal position (strict constrained solve, unchanged
## math; it still anchors the ride direction). STEP 2 = center-lock
## visibility guard: camera == player until player+ride leaves the raw map
## diamond, then the camera clamps with the black capped at the frozen
## maximum, and a fail-soft cap keeps the player inside the hard window.
## The frozen window caps and the fixed zoom are unchanged. No dynamic
## zoom exists.

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

	# ===== STEP 2: the center-lock visibility guard (R14-CAM-R1) =====
	# Reference geometry for the raw map diamond (no viewport erosion).
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
	# 1) center: guard is a no-op, camera == player.
	var guarded := CameraConstraint.apply_player_visibility_guard(
		centroid, centroid, FIXED_ZOOM, VIEWPORT_SIZE
	)
	assert(guarded.is_equal_approx(centroid), "center guard must be a no-op")
	# 2) center-lock walk: for every direction, while the player's
	# excursion beyond the zero-black anchor stays inside the frozen
	# visibility window (per axis), the player sits EXACTLY at the camera
	# center - including positions well past the zero-black anchor, where
	# the superseded C1.5 guard already glided. Past the unlock the camera
	# clamps to anchor +/- window per axis and the black exposure stays
	# capped at the frozen maximum while the player keeps walking.
	for direction: Vector2 in directions:
		var half_span := 0.0
		for point: Vector2 in boundary:
			half_span = maxf(
				half_span, absf((point - centroid).dot(direction))
			)
		var window_world := _max_offset_px() / FIXED_ZOOM
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
				ideal_center, desired, FIXED_ZOOM, VIEWPORT_SIZE
			)
			var delta_px := (desired - ideal_center) * FIXED_ZOOM
			var player_offset_px := (desired - final_center) * FIXED_ZOOM
			# The guard offset never exceeds the player's own excursion
			# beyond the anchor (the camera never lags more than the player
			# has walked past the zero-black anchor).
			assert(
				player_offset_px.x <= absf(delta_px.x) + 0.01
				and player_offset_px.y <= absf(delta_px.y) + 0.01,
				"the guard offset must not overshoot the excursion at %s" % desired
			)
			if (
				absf(delta_px.x) <= window_world.x + 0.01
				and absf(delta_px.y) <= window_world.y + 0.01
			):
				assert(
					final_center.distance_to(desired) <= 0.001,
					"the camera must hold the player exactly centered before the black cap at %s" % desired
				)
				if ideal_center.distance_to(desired) > 0.01:
					centered_past_anchor = true
			else:
				unlock_seen = true
				# EXACT clamp shape: camera == player clamped into the
				# anchor +/- window box.
				var expected_final := Vector2(
					clampf(
						desired.x,
						ideal_center.x - window_world.x,
						ideal_center.x + window_world.x
					),
					clampf(
						desired.y,
						ideal_center.y - window_world.y,
						ideal_center.y + window_world.y
					)
				)
				assert(
					final_center.distance_to(expected_final) <= 0.01,
					"past the unlock the camera must clamp to the anchor window box: %s vs %s"
					% [final_center, expected_final]
				)
				if _player_inside_map(desired):
					# The frozen maximum: the camera sits at most window_world
					# beyond the zero-black anchor, so its worst eroded
					# deficit stays under the anchor's own base deficit plus
					# max_k(|n_k.x|*wx + |n_k.y|*wy). The base term is <= 0
					# on feasible maps and only covers the unavoidable
					# infeasible-map black.
					var black := _camera_black_px(final_center)
					var base_black := _camera_black_px(ideal_center)
					var frozen_cap := -INF
					for index: int in _raw_points.size():
						var normal := _raw_normals[index]
						frozen_cap = maxf(
							frozen_cap,
							absf(normal.x) * window_world.x
								+ absf(normal.y) * window_world.y
						)
					assert(
						black <= base_black + frozen_cap + 0.05,
						"the capped black must stay inside the frozen maximum: %s vs %s"
						% [black, base_black + frozen_cap]
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
	# 4) transition continuity and direction: 1px world steps across the
	# strict/guard boundary must never jump and the camera must never
	# recede while the player advances.
	var walk_direction := Vector2.RIGHT
	var walk_half_span := 0.0
	for point: Vector2 in boundary:
		walk_half_span = maxf(
			walk_half_span, absf((point - centroid).dot(walk_direction))
		)
	var previous_final := Vector2.INF
	for step: int in range(0, 400):
		var desired := centroid + walk_direction * (
			walk_half_span * 0.4 + float(step)
		)
		var ideal_center := CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
		)
		var final_center := CameraConstraint.apply_player_visibility_guard(
			ideal_center, desired, FIXED_ZOOM, VIEWPORT_SIZE
		)
		if not previous_final.is_equal_approx(Vector2.INF):
			assert(
				final_center.distance_to(previous_final) < 3.0,
				"the strict/guard transition must not jump at step %d" % step
			)
			assert(
				(final_center.x - previous_final.x) >= -0.001,
				"the camera must never recede while the player advances at step %d"
				% step
			)
		previous_final = final_center

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
		"MAP_DIAMOND_CAMERA_STRICT_EDGE_PASS parity=%d guard_margin=%.2f cache_builds=%d"
		% [
			PARITY_ITERATIONS,
			CameraConstraint.PLAYER_VISIBLE_SCREEN_MARGIN,
			CameraConstraint.strict_cache_build_count(),
		]
	)
	get_tree().quit(0)
