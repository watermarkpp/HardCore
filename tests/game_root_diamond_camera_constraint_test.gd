extends Node

## C1 CAMERA-EDGE (user ruling 2026-09-16): the gameplay camera follows the
## player with ONE global view height (ArtSpec.CAMERA_ZOOM) and a STRICT
## map-edge constraint from constrain_center():
##   map center  -> camera == player (normal follow)
##   map edge    -> camera stops at the last legal center, the player keeps
##                  walking and may leave the screen center, minimizing the
##                  black area shown outside the map
##   everywhere  -> zoom is exactly ArtSpec.CAMERA_ZOOM; no dynamic zoom
## The former 14% tanh central band (player_priority_soft_edge_v1) is gone:
## at boundary corners the player/camera offset fraction must EXCEED the old
## 0.14 cap instead of being clamped to it.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)


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
	var probes: Array[Vector2] = [centroid]
	for point: Vector2 in boundary:
		probes.append(point)
	for edge_index: int in boundary.size():
		var next_index := (edge_index + 1) % boundary.size()
		probes.append((boundary[edge_index] + boundary[next_index]) * 0.5)
	var viewport_size := game.get_viewport().get_visible_rect().size
	var maximum_corner_offset_fraction := 0.0
	for probe: Vector2 in probes:
		game.player.global_position = probe
		game._update_world_camera_constraint(2.0)
		# The one global view height, exactly, at every edge position.
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.y, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.x, camera.zoom.y),
			"GameRoot camera zoom must stay exactly the fixed view height: %s"
			% camera.zoom
		)
		# Production center must equal the strict reference solve.
		var strict: Dictionary = CameraConstraint.constrain_center(
			design_size, viewport_size * 0.5, camera.zoom, probe
		)
		assert(
			Vector2(strict.get("center", Vector2.INF)).distance_to(
				camera.global_position
			) <= 0.01,
			"camera center must be the strict constrained center at %s: %s vs %s"
			% [probe, camera.global_position, strict.get("center")]
		)
		if bool(strict.get("ok", false)):
			assert(
				CameraConstraint.viewport_inside_boundary(strict),
				"viewport must respect the map boundary half-planes at %s" % probe
			)
		# Corner offsets must be able to exceed the removed 14% central band.
		var offset_fraction: Vector2 = (
			Vector2(
				absf(camera.global_position.x - probe.x),
				absf(camera.global_position.y - probe.y)
			)
			* camera.zoom
			/ viewport_size
		)
		maximum_corner_offset_fraction = maxf(
			maximum_corner_offset_fraction,
			maxf(offset_fraction.x, offset_fraction.y)
		)
	assert(
		maximum_corner_offset_fraction > 0.14,
		"strict edge follow must let the player leave the removed 14%% "
		+ "central band; max offset fraction %f"
		% maximum_corner_offset_fraction
	)
	# Map center: the camera equals the player exactly.
	game.player.global_position = centroid
	game._update_world_camera_constraint(2.0)
	assert(
		camera.global_position.is_equal_approx(centroid),
		"map-center follow must keep the camera on the player"
	)
	# Walking past the boundary keeps the camera clamped while the player/camera
	# delta grows: the follow is unlocked at the edge, not band-limited.
	var corner: Vector2 = boundary[0]
	var outward := (corner - centroid).normalized()
	var previous_delta := -1.0
	for step: int in range(1, 6):
		game.player.global_position = corner + outward * (60.0 * float(step))
		game._update_world_camera_constraint(2.0)
		var delta := camera.global_position.distance_to(game.player.global_position)
		assert(
			delta > previous_delta,
			"player/camera offset must keep growing past the map edge (step %d)"
			% step
		)
		previous_delta = delta
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM),
			"edge walking must never change the view height"
		)
	# C1 discipline guard: the removed soft-follow machinery must be gone.
	var game_root_source := (
		FileAccess.get_file_as_string("res://scripts/game_root.gd")
	)
	assert(
		not game_root_source.contains("resolve_soft_follow")
		and not game_root_source.contains("recommended_zoom")
		and not game_root_source.contains("tanh("),
		"GameRoot must not retain the soft-follow / dynamic zoom path"
	)
	print(
		"GAME_ROOT_DIAMOND_CAMERA_CONSTRAINT_PASS "
		+ "strict edge follow, fixed zoom %0.2f, max corner offset fraction %0.3f"
		% [ArtSpec.CAMERA_ZOOM, maximum_corner_offset_fraction]
	)
	get_tree().quit(0)
