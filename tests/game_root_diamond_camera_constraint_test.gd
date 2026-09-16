extends Node

## C1.2 CAMERA-EDGE-V2 production contract (user ruling 2026-09-16, GPT
## audit): GameRoot composes the zero-black ideal center (strict constrained
## solve) with the player visibility guard. The hard constraint is that the
## player stays inside the visibility window of every screen axis - at
## least 15% from every edge (central 70%) and never closer than two ground
## cells; minimizing the black area outside the map is the optimization
## goal, NOT a hard zero-black contract. The view height stays exactly
## ArtSpec.CAMERA_ZOOM everywhere. The former "viewport corners always
## inside the map" contract from C1 is REJECTED by device ruling and must
## not be asserted here.

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
		# HARD CONSTRAINT: the player is always inside the visibility window.
		var player_offset_px := Vector2(
			absf(probe.x - camera.global_position.x) * camera.zoom.x,
			absf(probe.y - camera.global_position.y) * camera.zoom.y
		)
		assert(
			player_offset_px.x <= max_offset_px.x + 0.01
			and player_offset_px.y <= max_offset_px.y + 0.01,
			"the player left the visibility window at %s: %s" % [
				probe, player_offset_px,
			]
		)
		# GOAL: zero black whenever possible, minimum black otherwise.
		var player_delta_px := (probe - ideal_center) * camera.zoom
		if (
			absf(player_delta_px.x) <= max_offset_px.x + 0.01
			and absf(player_delta_px.y) <= max_offset_px.y + 0.01
		):
			zero_black_probe_count += 1
			assert(
				camera.global_position.is_equal_approx(ideal_center),
				"inside the visibility window the camera must stay on the zero-black ideal at %s"
				% probe
			)
		else:
			var excess_px := Vector2(
				maxf(0.0, absf(player_delta_px.x) - max_offset_px.x),
				maxf(0.0, absf(player_delta_px.y) - max_offset_px.y)
			)
			var camera_refollow_px := Vector2(
				absf(camera.global_position.x - ideal_center.x) * camera.zoom.x,
				absf(camera.global_position.y - ideal_center.y) * camera.zoom.y
			)
			assert(
				Vector2(
					absf(camera_refollow_px.x - excess_px.x),
					absf(camera_refollow_px.y - excess_px.y)
				).length() <= 0.02,
				"the camera must re-follow by exactly the excess (minimum black) at %s"
				% probe
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
	# Walking far past the boundary: the player stays pinned inside the
	# visibility window and the saturated camera follows 1:1 with the player.
	var corner: Vector2 = boundary[0]
	var outward := (corner - centroid).normalized()
	var previous_camera := Vector2.INF
	var previous_player := Vector2.INF
	var previous_saturated_x := false
	var previous_saturated_y := false
	var saturated := false
	for step: int in range(1, 11):
		game.player.global_position = corner + outward * (240.0 * float(step))
		game._update_world_camera_constraint(2.0)
		var player_offset_px := Vector2(
			absf(game.player.global_position.x - camera.global_position.x)
			* camera.zoom.x,
			absf(game.player.global_position.y - camera.global_position.y)
			* camera.zoom.y
		)
		assert(
			player_offset_px.x <= max_offset_px.x + 0.01
			and player_offset_px.y <= max_offset_px.y + 0.01,
			"the player must never leave the visibility window (step %d)" % step
		)
		var saturated_x := player_offset_px.x >= max_offset_px.x - 0.01
		var saturated_y := player_offset_px.y >= max_offset_px.y - 0.01
		if saturated_x or saturated_y:
			saturated = true
			if not previous_camera.is_equal_approx(Vector2.INF):
				var camera_delta: Vector2 = (
					camera.global_position - previous_camera
				)
				var player_delta: Vector2 = (
					game.player.global_position - previous_player
				)
				# A 1:1 follow holds on an axis only while BOTH steps are
				# saturated on that axis; the transition step legitimately
				# closes the accumulated gap in one move.
				if saturated_x and previous_saturated_x:
					assert(
						absf(camera_delta.x - player_delta.x) <= 0.01,
						"a saturated X guard must follow the player 1:1 (step %d)"
						% step
					)
				if saturated_y and previous_saturated_y:
					assert(
						absf(camera_delta.y - player_delta.y) <= 0.01,
						"a saturated Y guard must follow the player 1:1 (step %d)"
						% step
					)
		previous_saturated_x = saturated_x
		previous_saturated_y = saturated_y
		previous_camera = camera.global_position
		previous_player = game.player.global_position
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM),
			"edge walking must never change the view height"
		)
	assert(saturated, "the walk fixture must reach the guard-saturated regime")
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
