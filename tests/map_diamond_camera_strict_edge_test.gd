extends Node

## C1.2 CAMERA-EDGE-V2 service contract (user ruling 2026-09-16, GPT audit):
## the camera has ONE hard constraint and ONE optimization goal.
##   Hard: the player stays inside the visibility window of every screen
##         axis - at least 15% from every edge (central 70%) and never
##         closer than two ground cells.
##   Goal: the black area outside the map is minimized, NOT forbidden.
## STEP 1 = zero-black ideal position (strict constrained solve, unchanged
## math). STEP 2 = player visibility guard re-following the player by
## exactly the excess over the visibility window, so any black area is the
## minimum required to keep the player comfortable. No dynamic zoom exists.

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

	# ===== STEP 2: the player visibility guard (the new contract) =====
	# 1) center: guard is a no-op, camera == player.
	var guarded := CameraConstraint.apply_player_visibility_guard(
		centroid, centroid, FIXED_ZOOM, VIEWPORT_SIZE
	)
	assert(guarded.is_equal_approx(centroid), "center guard must be a no-op")
	# 2) zero-black region: when the player is still inside the 10..90
	# window seen from the ideal center, the camera stays on the ideal.
	var zero_black_probe := Vector2.INF
	var saturated_probe := Vector2.INF
	for direction: Vector2 in directions:
		var half_span := 0.0
		for point: Vector2 in boundary:
			half_span = maxf(
				half_span, absf((point - centroid).dot(direction))
			)
		for step: int in range(1, 49):
			var desired := (
				centroid + direction * (half_span * 2.0 * float(step) / 48.0)
			)
			var ideal_center := CameraConstraint.resolve_strict_follow_cached(
				FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, desired
			)
			var delta_px := (desired - ideal_center) * FIXED_ZOOM
			if zero_black_probe.is_equal_approx(Vector2.INF):
				if ideal_center.distance_to(desired) > 0.01 and (
					absf(delta_px.x) < _max_offset_px().x * 0.6
					and absf(delta_px.y) < _max_offset_px().y * 0.6
				):
					zero_black_probe = desired
			if saturated_probe.is_equal_approx(Vector2.INF):
				if (
					absf(delta_px.x) > _max_offset_px().x * 1.5
					or absf(delta_px.y) > _max_offset_px().y * 1.5
				):
					saturated_probe = desired
	assert(
		not zero_black_probe.is_equal_approx(Vector2.INF),
		"fixture must contain a zero-black-but-clamped probe"
	)
	assert(
		not saturated_probe.is_equal_approx(Vector2.INF),
		"fixture must contain a guard-saturated probe"
	)
	var zero_black_ideal := CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, zero_black_probe
	)
	var zero_black_final := CameraConstraint.apply_player_visibility_guard(
		zero_black_ideal, zero_black_probe, FIXED_ZOOM, VIEWPORT_SIZE
	)
	assert(
		zero_black_final.is_equal_approx(zero_black_ideal),
		"inside the visibility window the camera must stay on the zero-black ideal"
	)
	# 3) saturated: the player is pinned on the 90% window edge and the
	# camera deviates from the ideal by exactly the excess — no more.
	var saturated_ideal := CameraConstraint.resolve_strict_follow_cached(
		FEASIBLE_SIZE, VIEWPORT_HALF, FIXED_ZOOM, saturated_probe
	)
	var saturated_final := CameraConstraint.apply_player_visibility_guard(
		saturated_ideal, saturated_probe, FIXED_ZOOM, VIEWPORT_SIZE
	)
	var player_offset_px := (
		Vector2(
			absf(saturated_probe.x - saturated_final.x),
			absf(saturated_probe.y - saturated_final.y)
		)
		* FIXED_ZOOM
	)
	assert(
		player_offset_px.x <= _max_offset_px().x + 0.01
		and player_offset_px.y <= _max_offset_px().y + 0.01,
		"the player must stay inside the visibility window: %s" % player_offset_px
	)
	var expected_excess_px := Vector2(
		maxf(
			0.0,
			absf((saturated_probe.x - saturated_ideal.x) * FIXED_ZOOM.x)
			- _max_offset_px().x
		),
		maxf(
			0.0,
			absf((saturated_probe.y - saturated_ideal.y) * FIXED_ZOOM.y)
			- _max_offset_px().y
		)
	)
	# The camera re-follow, measured from the ideal, must equal the excess
	# exactly: re-follow = |player - ideal| - clamped window = excess.
	var camera_refollow_px := (saturated_final - saturated_ideal) * FIXED_ZOOM
	assert(
		Vector2(
			absf(camera_refollow_px.x), absf(camera_refollow_px.y)
		).distance_to(expected_excess_px) <= 0.01,
		"the camera must re-follow by exactly the excess (minimum black): %s vs %s"
		% [camera_refollow_px, expected_excess_px]
	)
	# 4) transition continuity: 1px world steps across the strict/guard
	# boundary must never jump.
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
