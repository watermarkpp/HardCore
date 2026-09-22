extends Node

## R14-CAM-R2 BLACK-BUDGET REGION independent contract test (user work
## order 2026-09-19, review of 7c2631d3).
##
## Independence rules honoured here:
## - Expected camera values for the eight corner counterexamples come from
##   the independent review package (camera_reference.py /
##   camera_counterexamples.json, revision 7c2631d3) - they are NOT produced
##   by the production helper under test.
## - The black-depth metric, the budget, the unlock threshold and the screen
##   positions are recomputed inside this test from first principles (map
##   boundary, inward normals, viewport supports, frozen window) - never by
##   reading production internals.
## - The player display extents are derived from the real ArtSpec visual
##   constants (the actual 64x96 character frame, its foot anchor and the
##   approved visual composite offset), not from an invented body constant.

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const ArtSpec := preload("res://scripts/art_spec.gd")

const ZOOM := 1.06
## Real display geometry of the persistent player visual (world px, relative
## to the approved ground foot point): the body frame quad of the visual
## composite = visual.position + (-CHARACTER_FOOT_ANCHOR) with the
## CHARACTER_FRAME size, measured against the logical foot (0,0).
const DISPLAY_EXTENT := Vector3(39.5, 67.5, 28.5)
## Counterexample rows from the review package camera_counterexamples.json:
## [viewport, ground_gu, player_world, reference_camera, reference_screen,
##  declared_cap_world]
const COUNTEREXAMPLES := [
	[
		Vector2(2664, 1200), Vector2(199, 1), Vector2(6336, 16),
		Vector2(5639.018867924529, 16.0),
		Vector2(2070.799999999999, 600.0),
		727.9287255960447,
	],
	[
		Vector2(2664, 1200), Vector2(1, 1), Vector2(0, -3152),
		Vector2(0.0, -2803.509433962264),
		Vector2(1332.0, 230.6),
		727.9287255960447,
	],
	[
		Vector2(2664, 1200), Vector2(1, 199), Vector2(-6336, 16),
		Vector2(-5639.018867924529, 16.0),
		Vector2(593.2, 600.0),
		727.9287255960447,
	],
	[
		Vector2(2664, 1200), Vector2(199, 199), Vector2(0, 3184),
		Vector2(0.0, 2835.5094339622647),
		Vector2(1332.0, 969.4),
		727.9287255960447,
	],
	[
		Vector2(1598, 720), Vector2(199, 1), Vector2(6336, 16),
		Vector2(5789.867924528304, 16.0),
		Vector2(1377.9, 360.0),
		368.0061611422578,
	],
	[
		Vector2(1598, 720), Vector2(1, 1), Vector2(0, -3152),
		Vector2(0.0, -2878.9339622641514),
		Vector2(799.0, 70.55),
		368.0061611422578,
	],
	[
		Vector2(1598, 720), Vector2(1, 199), Vector2(-6336, 16),
		Vector2(-5789.867924528304, 16.0),
		Vector2(220.1, 360.0),
		368.0061611422578,
	],
	[
		Vector2(1598, 720), Vector2(199, 199), Vector2(0, 3184),
		Vector2(0.0, 2910.933962264152),
		Vector2(799.0, 649.45),
		368.0061611422578,
	],
]


func _ready() -> void:
	_run.call_deferred()


func _make_frame(
	size: Vector2i,
	viewport: Vector2,
	zoom_value := ZOOM
) -> Dictionary:
	## Independent frame model: map boundary, inward normals, viewport
	## supports, frozen window (0.35 fraction / six vertical cells), the
	## unavoidable base black at the centroid and the black budget.
	var boundary := CollisionGeometry.map_inner_boundary_world(size)
	var points: Array[Vector2] = []
	var normals: Array[Vector2] = []
	for index in boundary.size():
		var following := (index + 1) % boundary.size()
		var edge := boundary[following] - boundary[index]
		normals.append(Vector2(-edge.y, edge.x).normalized())
		points.append(boundary[index])
	var zoom := Vector2.ONE * zoom_value
	var half := Vector2(
		viewport.x * 0.5 / zoom.x, viewport.y * 0.5 / zoom.y
	)
	var supports: Array[float] = []
	for normal: Vector2 in normals:
		supports.append(
			absf(normal.x) * half.x + absf(normal.y) * half.y
		)
	var window := Vector2(
		minf(
			0.35 * viewport.x,
			maxf(0.0, viewport.x * 0.5 - 192.0 * zoom.x)
		) / zoom.x,
		minf(
			0.35 * viewport.y,
			maxf(0.0, viewport.y * 0.5 - 192.0 * zoom.y)
		) / zoom.y
	)
	var center := Vector2.ZERO
	for point: Vector2 in points:
		center += point
	center /= float(points.size())
	var base := 0.0
	for index in points.size():
		base = maxf(
			base,
			supports[index] - normals[index].dot(center - points[index])
		)
	var allowance := 0.0
	for index in points.size():
		allowance = maxf(
			allowance,
			absf(normals[index].x) * window.x
				+ absf(normals[index].y) * window.y
		)
	return {
		"size": size,
		"viewport": viewport,
		"viewport_half": viewport * 0.5,
		"zoom": zoom,
		"points": points,
		"normals": normals,
		"supports": supports,
		"half": half,
		"window": window,
		"center": center,
		"base": base,
		"cap": base + allowance,
	}


func _black(frame: Dictionary, c: Vector2) -> float:
	var worst := 0.0
	var points: Array[Vector2] = frame["points"]
	var normals: Array[Vector2] = frame["normals"]
	var supports: Array[float] = frame["supports"]
	for index in points.size():
		worst = maxf(
			worst,
			supports[index] - normals[index].dot(c - points[index])
		)
	return worst


func _screen(frame: Dictionary, player: Vector2, camera: Vector2) -> Vector2:
	return frame["viewport"] * 0.5 + (player - camera) * frame["zoom"]


func _guard(frame: Dictionary, player: Vector2, extent := Vector3.ZERO) -> Vector2:
	return CameraConstraint.apply_player_visibility_guard(
		frame["size"],
		frame["viewport_half"],
		frame["zoom"],
		player,
		extent
	)


func _foot_legal(frame: Dictionary, ground: Vector2) -> bool:
	## Full 18x9 world px foot ellipse inside the map (16-point sample).
	var points: Array[Vector2] = frame["points"]
	var normals: Array[Vector2] = frame["normals"]
	var center_world := _ground_to_world(ground, frame["size"])
	for sample in 16:
		var angle := TAU * float(sample) / 16.0
		var offset := Vector2(
			18.0 * cos(angle), 9.0 * sin(angle)
		)
		for index in points.size():
			if normals[index].dot(
				center_world + offset - points[index]
			) < -0.01:
				return false
	return true


func _ground_to_world(ground: Vector2, size: Vector2i) -> Vector2:
	var dx := ground.x - float(size.x - 1) * 0.5
	var dy := ground.y - float(size.y - 1) * 0.5
	return Vector2((dx - dy) * 32.0, (dx + dy) * 16.0)


func _first_unlock_distance(frame: Dictionary, direction: Vector2) -> Dictionary:
	## Auto-solved unlock threshold by bisection: the first excursion from
	## the map centroid where the guard stops returning the player exactly.
	## Returns {"centered": largest still-centered excursion,
	##           "unlocked": smallest already-unlocked excursion}.
	var center: Vector2 = frame["center"]
	var extent := 0.0
	for point: Vector2 in frame["points"]:
		extent = maxf(extent, absf((point - center).dot(direction)))
	var lo := 0.0
	var hi := extent
	for _round in 60:
		var mid := (lo + hi) * 0.5
		var probe := center + direction * mid
		if _guard(frame, probe).distance_to(probe) <= 1e-7:
			lo = mid
		else:
			hi = mid
	return {"centered": lo, "unlocked": hi}


func _display_rect_in_viewport(
	frame: Dictionary, player: Vector2, camera: Vector2
) -> Rect2:
	## Player display quad in viewport px (foot at the logical foot point).
	var foot_screen := _screen(frame, player, camera)
	return Rect2(
		foot_screen - Vector2(DISPLAY_EXTENT.x, DISPLAY_EXTENT.y)
			* frame["zoom"].x,
		Vector2(
			DISPLAY_EXTENT.x * 2.0,
			(DISPLAY_EXTENT.y + DISPLAY_EXTENT.z) * frame["zoom"].y
		)
	)


func _run() -> void:
	CameraConstraint.clear_visibility_conflict()
	# 1) The eight review-package corner counterexamples: the production
	# guard must reproduce the independent reference camera, keep the
	# black exposure exactly at the declared budget and keep the player
	# inside the viewport (the legacy formula violated all three).
	for row: Array in COUNTEREXAMPLES:
		var frame := _make_frame(
			Vector2i(200, 200), row[0]
		)
		var player: Vector2 = row[2]
		var reference_camera: Vector2 = row[3]
		var reference_screen: Vector2 = row[4]
		var budget: float = row[5]
		assert(
			absf(float(frame["cap"]) - budget) <= 0.05,
			"the test model budget must match the review package at %s" % row[0]
		)
		var camera := _guard(frame, player)
		assert(
			camera.distance_to(reference_camera) <= 0.05,
			"camera must match the independent reference at %s: %s vs %s"
			% [row[1], camera, reference_camera]
		)
		assert(
			absf(_black(frame, camera) - budget) <= 0.05,
			"clamped black must equal the declared budget at %s: %s vs %s"
			% [row[1], _black(frame, camera), budget]
		)
		var screen := _screen(frame, player, camera)
		assert(
			screen.distance_to(reference_screen) <= 0.05,
			"player screen position must match the reference at %s" % row[1]
		)
		assert(
			screen.x >= -1e-6 and screen.y >= -1e-6
			and screen.x <= frame["viewport"].x + 1e-6
			and screen.y <= frame["viewport"].y + 1e-6,
			"the legal player must stay on screen at %s (%s)" % [row[1], screen]
		)
	# 2) With the REAL display extents the eight corners keep the full
	# display quad inside the viewport (the player never goes off screen).
	for row: Array in COUNTEREXAMPLES:
		var frame := _make_frame(
			Vector2i(200, 200), row[0]
		)
		var player: Vector2 = row[2]
		assert(
			_foot_legal(frame, row[1]),
			"the counterexample ground position must be foot legal"
		)
		CameraConstraint.clear_visibility_conflict()
		var camera := _guard(frame, player, DISPLAY_EXTENT)
		var rect := _display_rect_in_viewport(frame, player, camera)
		assert(
			rect.position.x >= -1e-6 and rect.position.y >= -1e-6
			and rect.end.x <= frame["viewport"].x + 1e-6
			and rect.end.y <= frame["viewport"].y + 1e-6,
			"the full player display must stay inside the viewport at %s (%s)"
			% [row[1], rect]
		)
	# 3) Unlock threshold: auto-solved by bisection along all four axis
	# directions; exactly at the threshold the centered black equals the
	# budget (no early unlock, no late unlock), and just inside it the
	# player is still exactly centered.
	for viewport in [Vector2(2664, 1200), Vector2(1598, 720)]:
		var frame := _make_frame(Vector2i(200, 200), viewport)
		for direction in [
			Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN
		]:
			var threshold: Dictionary = _first_unlock_distance(
				frame, direction
			)
			var unlocked_probe: Vector2 = (
				frame["center"]
				+ direction * float(threshold["unlocked"])
			)
			assert(
				absf(
					_black(frame, unlocked_probe) - float(frame["cap"])
				) <= 0.02,
				"the unlock threshold must sit exactly at the budget: %s vs %s"
				% [_black(frame, unlocked_probe), frame["cap"]]
			)
			assert(
				_guard(frame, unlocked_probe).distance_to(unlocked_probe)
					> 1e-7,
				"the guard must be unlocked at the threshold"
			)
			var inside: Vector2 = (
				frame["center"]
				+ direction * (float(threshold["centered"]) - 0.5)
			)
			assert(
				_guard(frame, inside).distance_to(inside) <= 1e-9,
				"the guard must still be centered just inside the threshold"
			)
	# 4) Non-expansive continuity across the threshold: a 1px walk from
	# just inside to well past the unlock never moves the camera more than
	# the player moved, and walking back re-centers the player.
	for viewport in [Vector2(2664, 1200), Vector2(1598, 720)]:
		var frame := _make_frame(Vector2i(200, 200), viewport)
		var direction := Vector2.RIGHT
		var threshold: float = float(
			_first_unlock_distance(frame, direction)["unlocked"]
		)
		var previous_player: Vector2 = frame["center"] + direction * (threshold - 2.0)
		var previous_camera: Vector2 = _guard(frame, previous_player)
		for step in range(1, 401):
			var player: Vector2 = previous_player + direction
			var camera: Vector2 = _guard(frame, player)
			assert(
				camera.distance_to(previous_camera)
					<= player.distance_to(previous_player) + 1e-6,
				"the guard projection must be non-expansive (step %d)" % step
			)
			previous_player = player
			previous_camera = camera
		for back_step in range(1, 401):
			var player: Vector2 = previous_player - direction
			var camera: Vector2 = _guard(frame, player)
			assert(
				camera.distance_to(previous_camera)
					<= player.distance_to(previous_player) + 1e-6,
				"the guard projection must be non-expansive walking back"
			)
			previous_player = player
			previous_camera = camera
		assert(
			previous_camera.distance_to(previous_player) <= 1e-9,
			"walking back inside the budget must re-center the player"
		)
	# 5) Infeasible small map: the unavoidable base black is part of the
	# budget, the guard stays sane and the conflict stays empty at the
	# centroid region with the real display extents.
	var small_frame := _make_frame(Vector2i(24, 16), Vector2(2664, 1200))
	assert(
		float(small_frame["base"]) > 0.0,
		"the 24x16 map must be infeasible (nonzero base black)"
	)
	var small_center: Vector2 = small_frame["center"]
	assert(
		_guard(small_frame, small_center, DISPLAY_EXTENT).distance_to(
			small_center
		) <= 1e-9,
		"the centroid of an infeasible map must stay exactly centered"
	)
	assert(
		CameraConstraint.last_visibility_conflict().is_empty(),
		"the infeasible-map centroid must not trigger a visibility conflict"
	)
	var small_hi := 0.0
	for point: Vector2 in small_frame["points"]:
		small_hi = maxf(
			small_hi, absf((point - small_center).dot(Vector2.RIGHT))
		)
	var small_far := small_center + Vector2.RIGHT * (small_hi + 400.0)
	var small_camera := _guard(small_frame, small_far, DISPLAY_EXTENT)
	assert(
		_black(small_frame, small_camera)
			<= float(small_frame["cap"]) + 0.05,
		"the infeasible-map camera must stay inside the budget region"
	)
	# 6) Non-square map: the budget threshold and the capped clamp hold on
	# a rotated/non-square diamond too.
	var tall_frame := _make_frame(Vector2i(140, 90), Vector2(2664, 1200))
	var tall_threshold: float = float(
		_first_unlock_distance(tall_frame, Vector2.RIGHT)["unlocked"]
	)
	var tall_probe: Vector2 = tall_frame["center"] + Vector2.RIGHT * tall_threshold
	assert(
		absf(_black(tall_frame, tall_probe) - float(tall_frame["cap"])) <= 0.02,
		"the non-square map unlock must sit exactly at its budget"
	)
	var tall_far: Vector2 = tall_frame["center"] + Vector2.RIGHT * (tall_threshold + 500.0)
	var tall_camera := _guard(tall_frame, tall_far, DISPLAY_EXTENT)
	assert(
		_black(tall_frame, tall_camera) <= float(tall_frame["cap"]) + 0.05,
		"the non-square map camera must keep the black capped"
	)
	var tall_screen := _screen(tall_frame, tall_far, tall_camera)
	assert(
		tall_screen.x <= tall_frame["viewport"].x + 1e-6,
		"the non-square map must keep the player on screen (%s)" % tall_screen
	)
	# 7) Cache discipline: repeated guard calls must not rebuild the shared
	# frame cache (the budget region is prebuilt once per frame). One
	# warm-up call seats the slot for this frame first.
	var build_frame := _make_frame(Vector2i(200, 200), Vector2(2664, 1200))
	_guard(
		build_frame,
		build_frame["center"] + Vector2.RIGHT * 3000.0,
		DISPLAY_EXTENT
	)
	var builds_before: int = CameraConstraint.strict_cache_build_count()
	for repeat in 1000:
		_guard(
			build_frame,
			build_frame["center"] + Vector2.RIGHT * 3000.0,
			DISPLAY_EXTENT
		)
	assert(
		CameraConstraint.strict_cache_build_count() == builds_before,
		"guard calls must not rebuild the frame cache"
	)
	# 8) Source gate: the production path composes the guard with the real
	# display extent measurement.
	var game_root_source := (
		FileAccess.get_file_as_string("res://scripts/game_root.gd")
	)
	assert(
		game_root_source.contains("apply_player_visibility_guard")
		and game_root_source.contains("_player_display_extent_world_px"),
		"GameRoot must compose the budget guard with real display extents"
	)
	print(
		"CAMERA_BLACK_BUDGET_REGION_PASS counterexamples=%d viewports=2 cap_2664=%.6f cap_1598=%.6f"
		% [
			COUNTEREXAMPLES.size(),
			_make_frame(Vector2i(200, 200), Vector2(2664, 1200))["cap"],
			_make_frame(Vector2i(200, 200), Vector2(1598, 720))["cap"],
		]
	)
	get_tree().quit(0)
