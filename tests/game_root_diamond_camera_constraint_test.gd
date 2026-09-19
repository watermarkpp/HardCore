extends Node

## R14-CAM-R1 CAMERA-EDGE center-lock production contract (user device
## ruling 2026-09-19): GameRoot composes the zero-black ideal center
## (strict constrained solve) with the center-lock player visibility
## guard. The ruled follow shape: the player stays EXACTLY at the camera
## center while walking toward the map edge - the camera only clamps (the
## unlock threshold event) once the centered view exposes the configured
## maximum black area, i.e. the same frozen visibility window mirrored
## onto the camera's zero-black excursion (anchor +/- window per axis).
## After the unlock the player drifts off center bounded by the walkable
## geometry; on extreme map tips that drift can sit tighter than the
## superseded C1.4 six-cell comfort floor - the 2026-09-19 ruling
## prioritizes center-lock and the black cap. The early glide unlock of
## C1.5 is rejected by device ruling. The view height stays exactly
## ArtSpec.CAMERA_ZOOM everywhere. The former "viewport corners always
## inside the map" contract from C1 is REJECTED by device ruling and must
## not be asserted here.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)

var _raw_points: Array[Vector2] = []
var _raw_normals: Array[Vector2] = []


func _raw_deficit_px(point: Vector2) -> float:
	## Worst raw-map-diamond violation of the point (positive = outside).
	var worst := -INF
	for index in _raw_points.size():
		var margin := _raw_normals[index].dot(point - _raw_points[index])
		worst = maxf(worst, -margin)
	return worst


func _camera_black_px(
	camera_center: Vector2,
	world_half: Vector2
) -> float:
	## The black exposure of a camera center: the worst eroded deficit over
	## the map edges (the viewport support added back on every edge).
	var worst := -INF
	for index in _raw_points.size():
		var normal := _raw_normals[index]
		var support := (
			absf(normal.x) * world_half.x + absf(normal.y) * world_half.y
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
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == 910001, "camera fixture did not enter canonical Bich runtime")
	var camera: Camera2D = game.get("_world_camera") as Camera2D
	assert(camera != null and camera.name == "WorldCamera")
	assert(camera.get_parent() == game, "WorldCamera must not be parented to Player")
	var player_position_before_parent_probe: Vector2 = game.player.global_position
	var camera_global_before_parent_probe: Vector2 = camera.global_position
	game.player.global_position += Vector2(17.0, 11.0)
	assert(
		camera.global_position.is_equal_approx(camera_global_before_parent_probe),
		"WorldCamera inherited Player motion before its explicit constraint update"
	)
	game.player.global_position = player_position_before_parent_probe
	var runtime := MapEditorRuntimeBridge.load_map(game.current_map_id)
	var raw_size: Array = runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var boundary := MapEditorRuntimeCollisionGeometryService.map_inner_boundary_world(
		design_size
	)
	var centroid := Vector2.ZERO
	for point: Vector2 in boundary:
		centroid += point
	centroid /= float(boundary.size())
	# R14-CAM-R1 reference frames: the raw map diamond (no viewport
	# erosion) used to pin the center-lock phase and the black cap.
	_raw_points.clear()
	_raw_normals.clear()
	for edge_index: int in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		_raw_points.append(boundary[edge_index])
		_raw_normals.append(Vector2(-edge.y, edge.x).normalized())
	var probes: Array[Vector2] = [centroid]
	for point: Vector2 in boundary:
		probes.append(point)
	for edge_index: int in boundary.size():
		var next_index := (edge_index + 1) % boundary.size()
		probes.append((boundary[edge_index] + boundary[next_index]) * 0.5)
	var viewport_size := game.get_viewport().get_visible_rect().size
	var max_offset_px := CameraConstraint.visibility_max_offset_px(
		viewport_size, camera.zoom
	)
	var zero_black_probe_count := 0
	for probe: Vector2 in probes:
		game.player.global_position = probe
		game._update_world_camera_constraint(2.0)
		# The one global view height, exactly, at every position.
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.y, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.x, camera.zoom.y),
			"GameRoot camera zoom must stay exactly the fixed view height: %s"
			% camera.zoom
		)
		# Production center == strict ideal composed with the guard.
		var strict: Dictionary = CameraConstraint.constrain_center(
			design_size, viewport_size * 0.5, camera.zoom, probe
		)
		var ideal_center := Vector2(strict.get("center", Vector2.INF))
		var expected_center := CameraConstraint.apply_player_visibility_guard(
			ideal_center, probe, camera.zoom, viewport_size
		)
		assert(
			expected_center.distance_to(camera.global_position) <= 0.01,
			"camera center must be the guarded ideal at %s: %s vs %s" % [
				probe, camera.global_position, expected_center,
			]
		)
		# R14-CAM-R1: the guard offset never exceeds the player's own
		# excursion beyond the anchor (the camera never lags more than the
		# player has walked past the zero-black anchor).
		var player_offset_px := Vector2(
			absf(probe.x - camera.global_position.x) * camera.zoom.x,
			absf(probe.y - camera.global_position.y) * camera.zoom.y
		)
		var player_delta_px := (probe - ideal_center) * camera.zoom
		assert(
			player_offset_px.x <= absf(player_delta_px.x) + 0.01
			and player_offset_px.y <= absf(player_delta_px.y) + 0.01,
			"the guard offset must not overshoot the excursion at %s" % probe
		)
		# GOAL: center-lock follow (R14-CAM-R1 user device ruling). While
		# the player's excursion beyond the zero-black anchor stays inside
		# the frozen visibility window (per axis), the camera holds the
		# player EXACTLY centered - including positions past the zero-black
		# anchor. Once the clamp engages, the black exposure stays capped
		# at the frozen maximum.
		if (
			absf(player_delta_px.x) <= max_offset_px.x + 0.01
			and absf(player_delta_px.y) <= max_offset_px.y + 0.01
		):
			zero_black_probe_count += 1
			assert(
				camera.global_position.distance_to(probe) <= 0.01,
				"the camera must hold the player exactly centered before the black cap at %s"
				% probe
			)
		else:
			var window_world := max_offset_px / camera.zoom
			var world_half := Vector2(
				viewport_size.x * 0.5 / camera.zoom.x,
				viewport_size.y * 0.5 / camera.zoom.y
			)
			var black_px := _camera_black_px(
				camera.global_position, world_half
			)
			var base_black_px := _camera_black_px(ideal_center, world_half)
			var frozen_cap_px := -INF
			for index: int in _raw_points.size():
				var normal := _raw_normals[index]
				frozen_cap_px = maxf(
					frozen_cap_px,
					absf(normal.x) * window_world.x
						+ absf(normal.y) * window_world.y
				)
			assert(
				black_px <= base_black_px + frozen_cap_px + 0.05,
				"the clamped camera must not exceed the frozen black cap at %s: %s vs %s"
				% [probe, black_px, base_black_px + frozen_cap_px]
			)
	assert(
		zero_black_probe_count >= 1,
		"the probe set must contain zero-black positions"
	)
	# Map center: the camera equals the player exactly.
	game.player.global_position = centroid
	game._update_world_camera_constraint(2.0)
	assert(
		camera.global_position.is_equal_approx(centroid),
		"map-center follow must keep the camera on the player"
	)
	# Walking far past the boundary (degenerate out-of-map probes): the
	# camera stays completely fixed once clamped and the black exposure
	# stays capped while the player keeps walking out.
	var corner: Vector2 = boundary[0]
	var outward := (corner - centroid).normalized()
	var clamped_center := Vector2.INF
	var window_world_far := max_offset_px / camera.zoom
	var world_half_far := Vector2(
		viewport_size.x * 0.5 / camera.zoom.x,
		viewport_size.y * 0.5 / camera.zoom.y
	)
	for step: int in range(1, 11):
		game.player.global_position = corner + outward * (240.0 * float(step))
		game._update_world_camera_constraint(2.0)
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM),
			"edge walking must never change the view height"
		)
		var probe_delta_px := Vector2(
			(game.player.global_position.x - camera.global_position.x)
			* camera.zoom.x,
			(game.player.global_position.y - camera.global_position.y)
			* camera.zoom.y
		)
		if (
			absf(probe_delta_px.x) <= max_offset_px.x + 0.01
			and absf(probe_delta_px.y) <= max_offset_px.y + 0.01
		):
			assert(
				camera.global_position.distance_to(
					game.player.global_position
				) <= 0.01,
				"the camera must hold the player centered while locked (step %d)" % step
			)
			continue
		if clamped_center.is_equal_approx(Vector2.INF):
			clamped_center = camera.global_position
		# NOTE: no recede/fixed assertion here - far-out probes leave the
		# walkable map, where extra production logic may act on the camera;
		# the user ruling (2026-09-19) covers in-map walking only. The
		# binding post-unlock property is the frozen black cap below.
		var strict_far: Dictionary = CameraConstraint.constrain_center(
			design_size, viewport_size * 0.5, camera.zoom,
			game.player.global_position
		)
		var black_px := _camera_black_px(
			camera.global_position, world_half_far
		)
		var base_black_px := _camera_black_px(
			Vector2(strict_far.get("center", Vector2.INF)), world_half_far
		)
		var frozen_cap_px := -INF
		for index: int in _raw_points.size():
			var normal := _raw_normals[index]
			frozen_cap_px = maxf(
				frozen_cap_px,
				absf(normal.x) * window_world_far.x
					+ absf(normal.y) * window_world_far.y
			)
		assert(
			black_px <= base_black_px + frozen_cap_px + 0.05,
			"the clamped camera must not exceed the frozen black cap (step %d): %s vs %s"
			% [step, black_px, base_black_px + frozen_cap_px]
		)
	assert(
		not clamped_center.is_equal_approx(Vector2.INF),
		"the walk fixture must reach the clamped regime"
	)
	# C1.1 discipline guard: the removed soft-follow machinery stays gone and
	# the production path composes both steps.
	var game_root_source := (
		FileAccess.get_file_as_string("res://scripts/game_root.gd")
	)
	assert(
		not game_root_source.contains("resolve_soft_follow")
		and not game_root_source.contains("recommended_zoom")
		and not game_root_source.contains("tanh(")
		and game_root_source.contains("apply_player_visibility_guard"),
		"GameRoot must compose the strict ideal with the visibility guard"
	)
	print(
		"GAME_ROOT_DIAMOND_CAMERA_CONSTRAINT_PASS "
		+ "guarded edge follow, fixed zoom %0.2f, visibility margin %.2f, zero-black probes %d"
		% [
			ArtSpec.CAMERA_ZOOM,
			CameraConstraint.PLAYER_VISIBLE_SCREEN_MARGIN,
			zero_black_probe_count,
		]
	)
	get_tree().quit(0)
