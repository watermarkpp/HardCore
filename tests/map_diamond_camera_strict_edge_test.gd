extends Node

## C1 CAMERA-EDGE service contract (user ruling 2026-09-16):
##   1. map center: camera center == player center
##   2. four edges: the camera clamps at the legal center while the
##      player/camera delta keeps growing past the boundary
##   3. corners: the player may leave the screen center far beyond the
##      removed 14% central band
##   4. no dynamic zoom exists anywhere in the strict path
##   5. constraint geometry is cached per (design_size, viewport, zoom):
##      repeated per-frame calls must NOT rebuild boundary/constraints
##   plus the audit parity gate: the cached solver must match the strict
##   reference solver (constrain_center) over at least 10,000 probes.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const VIEWPORT_HALF := Vector2(1332.0, 600.0)
const FIXED_ZOOM := Vector2.ONE * 1.06
const FEASIBLE_SIZE := Vector2i(200, 200)
const PARITY_ITERATIONS := 10000


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var boundary := CollisionGeometry.map_inner_boundary_world(FEASIBLE_SIZE)
	var centroid := Vector2.ZERO
	for point: Vector2 in boundary:
		centroid += point
	centroid /= float(boundary.size())

	# 1) Map center: the camera equals the player.
	var center_result := CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, centroid
	)
	assert(
		center_result.is_equal_approx(centroid),
		"map-center follow must keep the camera on the player"
	)

	# 2) Four edges: clamped camera, growing player/camera delta.
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN,
	]
	for direction: Vector2 in directions:
		var half_span := 0.0
		for point: Vector2 in boundary:
			half_span = maxf(
				half_span, absf((point - centroid).dot(direction))
			)
		var previous_delta := -1.0
		var clamped_once := false
		for step: int in range(1, 13):
			var desired := (
				centroid
				+ direction * (half_span * 1.5 * float(step) / 12.0)
			)
			var camera_center := CameraConstraint.resolve_strict_follow_cached(
				FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
			)
			var delta := camera_center.distance_to(desired)
			if delta > 0.01:
				clamped_once = true
			if previous_delta >= 0.0:
				assert(
					delta >= previous_delta - 0.01,
					"edge delta must not shrink while the player walks out"
				)
			previous_delta = delta
		assert(
			clamped_once,
			"the camera must clamp on the %s edge" % str(direction)
		)

	# 3) Corners: offset fraction exceeds the removed 14% band.
	var maximum_offset_fraction := 0.0
	for corner: Vector2 in boundary:
		var camera_center := CameraConstraint.resolve_strict_follow_cached(
			FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, corner
		)
		var offset_fraction := (
			Vector2(
				absf(camera_center.x - corner.x),
				absf(camera_center.y - corner.y)
			)
			* FIXED_ZOOM
			/ (VIEWPORT_HALF * 2.0)
		)
		maximum_offset_fraction = maxf(
			maximum_offset_fraction, maxf(offset_fraction.x, offset_fraction.y)
		)
	assert(
		maximum_offset_fraction > 0.14,
		"corner offsets must exceed the removed 14%% band: %f"
		% maximum_offset_fraction
	)

	# 5) Cache: repeated calls must not rebuild the constraint geometry.
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
		FEASIBLE_SIZE,
		VIEWPORT_HALF * 1.1,
		FIXED_ZOOM,
		centroid
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

	# Parity gate: cached solver == strict reference solver over >=10000
	# probes, WITHOUT any further cache rebuilds (no per-call geometry).
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
			"cached solver diverged from the reference at %s: %s vs %s" % [
				desired, cached_center, reference.get("center"),
			]
		)
	assert(
		CameraConstraint.strict_cache_build_count() == builds_before_parity,
		"the parity loop must not rebuild the constraint geometry"
	)

	# 4) Static discipline: the soft-follow / dynamic zoom machinery is gone.
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
		and not game_root_source.contains("recommended_zoom"),
		"GameRoot must consume only the strict cached camera solver"
	)
	print(
		"MAP_DIAMOND_CAMERA_STRICT_EDGE_PASS parity=%d corner_offset=%.3f cache_builds=%d"
		% [
			PARITY_ITERATIONS,
			maximum_offset_fraction,
			CameraConstraint.strict_cache_build_count(),
		]
	)
	get_tree().quit(0)
