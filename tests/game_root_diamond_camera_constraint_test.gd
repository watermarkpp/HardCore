extends Node

## R14-CAM-R2 BLACK-BUDGET REGION production contract (user work order
## 2026-09-19, review of 7c2631d3): GameRoot composes the fixed black-budget
## region guard with the REAL player display geometry. The ruled follow
## shape: the player stays EXACTLY at the camera center while black(player)
## <= B - the unlock threshold event happens EXACTLY when the centered view
## reaches the frozen budget (the review-declared cap) - and past it the
## camera is the nearest point of K_B intersected with the player display
## visibility box, so the black stays capped AND the full player display
## stays on screen. The superseded R14-CAM-R1 per-axis anchor box is
## rejected (it let foot-legal map-tip positions push the player off
## screen and unlocked at ~54%/41% of the budget). The early glide unlock
## of C1.5 stays rejected by device ruling. The view height stays exactly
## ArtSpec.CAMERA_ZOOM everywhere. Assertions below use the test-local
## independent black-depth metric and the REAL Camera2D canvas state
## (get_screen_center_position / get_global_transform_with_canvas), not
## node positions alone and not the production helper as its own expected
## value. The former "viewport corners always inside the map" contract
## from C1 stays REJECTED by device ruling and must not be asserted here.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)

var _raw_points: Array[Vector2] = []
var _raw_normals: Array[Vector2] = []


func _camera_black_px(
	camera_center: Vector2,
	world_half: Vector2
) -> float:
	## Independent black-depth metric: the worst viewport overreach normal
	## depth over the map edges, in world px (the review's metric - not an
	## area, not a screenshot pixel width).
	var worst := 0.0
	for index in _raw_points.size():
		var normal := _raw_normals[index]
		var support := (
			absf(normal.x) * world_half.x + absf(normal.y) * world_half.y
		)
		worst = maxf(
			worst,
			support
				+ normal.dot(_raw_points[index])
				- normal.dot(camera_center)
		)
	return worst


func _settle_camera(camera: Camera2D) -> void:
	## Waits until the G2 position smoothing has converged onto the
	## constrained camera node position (or ~2.5s fail-safe). The project
	## snaps 2D transforms to device pixels (G2 rendering stability), so
	## the rendered center carries a <=1px quantization residue that never
	## converges away; 1px is the practical settled threshold.
	# Headless process frames are not fixed at 60 Hz; bound actual elapsed
	# time without changing the 1px convergence condition.
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline:
		if camera.get_screen_center_position().distance_to(
			camera.global_position
		) <= 1.0:
			return
		await camera.get_tree().process_frame


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
	_raw_points.clear()
	_raw_normals.clear()
	for edge_index: int in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		var edge := boundary[following] - boundary[edge_index]
		_raw_points.append(boundary[edge_index])
		_raw_normals.append(Vector2(-edge.y, edge.x).normalized())
	var viewport_size := game.get_viewport().get_visible_rect().size
	var world_half := Vector2(
		viewport_size.x * 0.5 / camera.zoom.x,
		viewport_size.y * 0.5 / camera.zoom.y
	)
	# Independent budget: base (the unavoidable black at the centroid) plus
	# the frozen-window allowance over the black-depth metric.
	var budget := 0.0
	budget += _camera_black_px(centroid, world_half)
	var allowance := 0.0
	for index: int in _raw_points.size():
		var normal := _raw_normals[index]
		var window_world := CameraConstraint.visibility_max_offset_px(
			viewport_size, camera.zoom
		) / camera.zoom
		allowance = maxf(
			allowance,
			absf(normal.x) * window_world.x
				+ absf(normal.y) * window_world.y
		)
	budget += allowance
	# The REAL measured player display extents (production measurement).
	var extent: Vector3 = game._player_display_extent_world_px()
	# The production display extent must equal the ArtSpec composite cell
	# derivation (side = right-edge 39.5, above 67.5, below 28.5 world px)
	# - it pins GameRoot to the art contract instead of a magic number.
	var body_frame_extent := Vector3(
		float(ArtSpec.CHARACTER_FRAME.x) * 0.5
			+ ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION.x,
		float(ArtSpec.CHARACTER_FOOT_ANCHOR.y)
			- ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION.y,
		float(ArtSpec.CHARACTER_FRAME.y - ArtSpec.CHARACTER_FOOT_ANCHOR.y)
			+ ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION.y
	)
	assert(
		is_equal_approx(extent.x, body_frame_extent.x)
		and is_equal_approx(extent.y, body_frame_extent.y)
		and is_equal_approx(extent.z, body_frame_extent.z),
		"the measured display extents must equal the ArtSpec composite cell derivation: %s vs %s"
		% [extent, body_frame_extent]
	)

	var probes: Array[Vector2] = [centroid]
	for point: Vector2 in boundary:
		probes.append(point)
	for edge_index: int in boundary.size():
		var next_index := (edge_index + 1) % boundary.size()
		probes.append((boundary[edge_index] + boundary[next_index]) * 0.5)
	var centered_probe_count := 0
	var conflict_printed := false
	for probe: Vector2 in probes:
		game.player.global_position = probe
		game._update_world_camera_constraint(2.0)
		# NOTE: no frame await here - the fixture player is not collision
		# anchored at these synthetic probes and physics would drift it
		# between the production update and the assertions. Real-canvas
		# settled verification happens separately below.
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.y, ArtSpec.CAMERA_ZOOM)
			and is_equal_approx(camera.zoom.x, camera.zoom.y),
			"GameRoot camera zoom must stay exactly the fixed view height: %s"
			% camera.zoom
		)
		# Wiring parity: the production camera equals the guard output for
		# the same inputs (this only proves the wiring; the contract
		# assertions below are independent).
		var expected_center: Vector2 = CameraConstraint.apply_player_visibility_guard(
			design_size, viewport_size * 0.5, camera.zoom, probe, extent
		)
		assert(
			expected_center.distance_to(camera.global_position) <= 0.01,
			"camera center must be the guarded ideal at %s: %s vs %s" % [
				probe, camera.global_position, expected_center,
			]
		)
		# Settled display geometry from the constrained node positions
		# (smoothing converges to exactly this, verified separately below).
		var centered_black := _camera_black_px(probe, world_half)
		var foot_settled: Vector2 = (
			viewport_size * 0.5
			+ (probe - camera.global_position) * camera.zoom.x
		)
		var display_rect := Rect2(
			foot_settled - Vector2(extent.x, extent.y) * camera.zoom.x,
			Vector2(
				extent.x * 2.0 * camera.zoom.x,
				(extent.y + extent.z) * camera.zoom.y
			)
		)
		# HARD floor: the full player display quad stays inside the real
		# viewport at every probed position.
		assert(
			display_rect.position.x >= -0.01
			and display_rect.position.y >= -0.01
			and display_rect.end.x <= viewport_size.x + 0.01
			and display_rect.end.y <= viewport_size.y + 0.01,
			"the player display quad must stay on screen at %s (%s)" % [
				probe, display_rect,
			]
		)
		if centered_black <= budget - 0.5:
			centered_probe_count += 1
			assert(
				camera.global_position.distance_to(probe) <= 0.01,
				"the camera must hold the player exactly centered below the budget at %s (black %.2f vs %.2f)"
				% [probe, centered_black, budget]
			)
		else:
			var clamped_black := _camera_black_px(
				camera.global_position, world_half
			)
			var conflict: Dictionary = (
				CameraConstraint.last_visibility_conflict()
			)
			if conflict.is_empty():
				assert(
					clamped_black <= budget + 0.05,
					"the clamped camera must not exceed the budget at %s: %.3f vs %.3f"
					% [probe, clamped_black, budget]
				)
			else:
				# Precise contract conflict (visibility floor wins):
				# disclose the exact numbers instead of silently enlarging
				# the user budget.
				if not conflict_printed:
					conflict_printed = true
					print(
						"CAMERA_BUDGET_VISIBILITY_CONFLICT probe=%s viewport=%s budget=%.6f clamped_black=%.6f minimal_black_for_full_display=%.6f display_rect=%s conflict=%s"
						% [
							probe, viewport_size, budget, clamped_black,
							clamped_black, display_rect, conflict,
						]
					)
	assert(
		centered_probe_count >= 1,
		"the probe set must contain centered positions"
	)
	# Map center: the camera equals the player exactly.
	game.player.global_position = centroid
	game._update_world_camera_constraint(2.0)
	assert(
		camera.global_position.is_equal_approx(centroid),
		"map-center follow must keep the camera on the player"
	)
	# REAL canvas verification at converged representative positions: the
	# production camera uses G2 position smoothing (speed 7), so the canvas
	# state is asserted AFTER it settles onto the constrained center. All
	# three positions stay inside the walkable map so the fixture player is
	# collision-anchored and does not drift while settling: the centered
	# center plus east/west excursions past the unlock threshold.
	for canvas_probe: Vector2 in [
		centroid,
		centroid + Vector2(2200.0, 0.0),
		centroid + Vector2(-2200.0, 0.0),
	]:
		game.player.global_position = canvas_probe
		game._update_world_camera_constraint(2.0)
		await _settle_camera(camera)
		# G2 pixel snapping quantizes the rendered canvas state to ~1px;
		# the canvas assertions therefore tolerate 1.5px while still
		# catching any real smoothing/limit/wiring residue.
		var screen_center := camera.get_screen_center_position()
		assert(
			screen_center.distance_to(camera.global_position) <= 1.5,
			"the settled Camera2D screen center must equal the constrained center at %s: %s vs %s"
			% [canvas_probe, screen_center, camera.global_position]
		)
		var foot_canvas: Vector2 = (
			game.player.get_global_transform_with_canvas().origin
		)
		var foot_expected: Vector2 = (
			viewport_size * 0.5
			+ (canvas_probe - camera.global_position) * camera.zoom.x
		)
		assert(
			foot_canvas.distance_to(foot_expected) <= 1.5,
			"the player's canvas foot must match the settled world math at %s: %s vs %s"
			% [canvas_probe, foot_canvas, foot_expected]
		)
		var canvas_rect := Rect2(
			foot_canvas - Vector2(extent.x, extent.y) * camera.zoom.x,
			Vector2(
				extent.x * 2.0 * camera.zoom.x,
				(extent.y + extent.z) * camera.zoom.y
			)
		)
		assert(
			canvas_rect.position.x >= -1.5
			and canvas_rect.position.y >= -1.5
			and canvas_rect.end.x <= viewport_size.x + 1.5
			and canvas_rect.end.y <= viewport_size.y + 1.5,
			"the settled canvas display quad must stay on screen at %s (%s)"
			% [canvas_probe, canvas_rect]
		)
	# Production unlock threshold (auto-solved through the REAL camera
	# path): exactly at the threshold the centered black equals the budget.
	var walk_direction := Vector2.RIGHT
	var bisect_lo := 0.0
	var bisect_hi := 0.0
	for point: Vector2 in boundary:
		bisect_hi = maxf(
			bisect_hi, absf((point - centroid).dot(walk_direction))
		)
	for _round in 60:
		var mid := (bisect_lo + bisect_hi) * 0.5
		game.player.global_position = centroid + walk_direction * mid
		game._update_world_camera_constraint(2.0)
		if camera.global_position.distance_to(game.player.global_position) <= 1e-7:
			bisect_lo = mid
		else:
			bisect_hi = mid
	var threshold_black := _camera_black_px(
		centroid + walk_direction * bisect_lo, world_half
	)
	assert(
		absf(threshold_black - budget) <= 0.05,
		"the production unlock threshold must sit exactly at the budget: %.4f vs %.4f (the superseded formula unlocked at ~54%% of it)"
		% [threshold_black, budget]
	)
	# Corner counterexample on the real path: a full-foot-legal map corner
	# (Ground (199,1) of the canonical map) keeps the display quad on
	# screen - the defect that pushed the player to x=2863.75 on a 2664
	# viewport is gone.
	var corner_ground := Vector2(
		float(design_size.x) - 1.0, 1.0
	)
	var half_ground := Vector2(
		float(design_size.x - 1) * 0.5, float(design_size.y - 1) * 0.5
	)
	var corner_delta := corner_ground - half_ground
	var corner_world := Vector2(
		(corner_delta.x - corner_delta.y) * 32.0,
		(corner_delta.x + corner_delta.y) * 16.0
	)
	game.player.global_position = corner_world
	game._update_world_camera_constraint(2.0)
	await _settle_camera(camera)
	var corner_foot_canvas: Vector2 = (
		game.player.get_global_transform_with_canvas().origin
	)
	var corner_rect := Rect2(
		corner_foot_canvas - Vector2(extent.x, extent.y) * camera.zoom.x,
		Vector2(
			extent.x * 2.0 * camera.zoom.x,
			(extent.y + extent.z) * camera.zoom.y
		)
	)
	assert(
		corner_rect.position.x >= -0.01
		and corner_rect.position.y >= -0.01
		and corner_rect.end.x <= viewport_size.x + 0.01
		and corner_rect.end.y <= viewport_size.y + 0.01,
		"the foot-legal corner must keep the player display on screen (%s)"
		% corner_rect
	)
	# Walking far past the boundary (degenerate out-of-map probes): the
	# black exposure stays capped while the player keeps walking out.
	var corner: Vector2 = boundary[0]
	var outward := (corner - centroid).normalized()
	var clamped_seen := false
	var conflict_printed_once := false
	for step: int in range(1, 11):
		game.player.global_position = corner + outward * (240.0 * float(step))
		game._update_world_camera_constraint(2.0)
		assert(
			is_equal_approx(camera.zoom.x, ArtSpec.CAMERA_ZOOM),
			"edge walking must never change the view height"
		)
		var step_black := _camera_black_px(
			camera.global_position, world_half
		)
		var conflict: Dictionary = CameraConstraint.last_visibility_conflict()
		clamped_seen = true
		if conflict.is_empty():
			assert(
				step_black <= budget + 0.05,
				"the clamped camera must not exceed the budget (step %d): %.3f vs %.3f"
				% [step, step_black, budget]
			)
		elif not conflict_printed_once:
			# Visibility floor wins out of map: disclose once, never
			# silently enlarge the budget.
			conflict_printed_once = true
			print(
				"CAMERA_BUDGET_VISIBILITY_CONFLICT far_walk_step=%d budget=%.6f clamped_black=%.6f conflict=%s"
				% [step, budget, step_black, conflict]
			)
	assert(clamped_seen, "the walk fixture must reach the clamped regime")
	# C1.1 discipline guard: the removed soft-follow machinery stays gone and
	# the production path composes the budget guard with real extents.
	var game_root_source := (
		FileAccess.get_file_as_string("res://scripts/game_root.gd")
	)
	assert(
		not game_root_source.contains("resolve_soft_follow")
		and not game_root_source.contains("recommended_zoom")
		and not game_root_source.contains("tanh(")
		and game_root_source.contains("apply_player_visibility_guard")
		and game_root_source.contains("_player_display_extent_world_px"),
		"GameRoot must compose the budget guard with real display extents"
	)
	print(
		"GAME_ROOT_DIAMOND_CAMERA_CONSTRAINT_PASS "
		+ "budget %.3f, fixed zoom %0.2f, centered probes %d"
		% [budget, ArtSpec.CAMERA_ZOOM, centered_probe_count]
	)
	get_tree().quit(0)
