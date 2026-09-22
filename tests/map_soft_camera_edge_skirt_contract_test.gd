extends Node

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const MapEditorRuntimeBridge := preload(
	"res://scripts/layers/runtime/map_editor_runtime_bridge.gd"
)

const DEVICE_VIEWPORT_HALF := Vector2(1332.0, 600.0)
const BASE_ZOOM := Vector2.ONE * 1.06
const GUARD_BAND_WORLD := 1536.0


func _ready() -> void:
	_verify_map(Vector2i(80, 80), true)
	_verify_map(Vector2i(38, 38), false)
	_verify_edge_follow_continuity()
	await _verify_runtime_skirt()
	print(
		(
			"MAP_SOFT_CAMERA_EDGE_SKIRT_PASS contract=%s strict=%s "
			+ "viewport=2664x1200 zoom=1.06 fixed strict_edge_follow=v1"
		)
		% [
			CameraConstraint.CONTRACT_ID,
			CameraConstraint.STRICT_FOLLOW_CONTRACT_ID,
		]
	)
	get_tree().quit(0)


func _verify_map(size: Vector2i, include_all_corners: bool) -> void:
	var boundary := CollisionGeometry.map_inner_boundary_world(size)
	var centroid := _centroid(boundary)
	var probes: Array[Vector2] = [centroid]
	for edge_index in boundary.size():
		var following := (edge_index + 1) % boundary.size()
		probes.append((boundary[edge_index] + boundary[following]) * 0.5)
	if include_all_corners:
		for point: Vector2 in boundary:
			probes.append(point)
	for player_center: Vector2 in probes:
		# C1: the strict cached solver IS the contract; the reference
		# constrain_center solve must agree with it.
		var center := CameraConstraint.resolve_strict_follow_cached(
			size, DEVICE_VIEWPORT_HALF, BASE_ZOOM, player_center
		)
		var strict: Dictionary = CameraConstraint.constrain_center(
			size, DEVICE_VIEWPORT_HALF, BASE_ZOOM, player_center
		)
		assert(
			Vector2(strict.get("center", Vector2.INF)).distance_to(center)
			<= 0.01,
			"cached strict center must match the reference solver at %s/%s"
			% [size, player_center]
		)
		assert(
			str(strict.get("contract_id", ""))
			== CameraConstraint.CONTRACT_ID,
			"reference solve must carry the camera constraint contract"
		)
		if bool(strict.get("ok", false)):
			assert(
				CameraConstraint.viewport_inside_boundary(strict),
				"viewport corners must respect the boundary at %s/%s"
				% [size, player_center]
			)
		if player_center.is_equal_approx(centroid) and bool(
			strict.get("ok", false)
		):
			assert(
				center.is_equal_approx(player_center),
				"map-center follow must keep the camera on the player"
			)


func _verify_edge_follow_continuity() -> void:
	var size := Vector2i(80, 80)
	var boundary := CollisionGeometry.map_inner_boundary_world(size)
	var centroid := _centroid(boundary)
	var target := boundary[1]
	var previous_center := centroid
	for step in range(1, 65):
		var player_center := centroid.lerp(target, float(step) / 64.0)
		var center := CameraConstraint.resolve_strict_follow_cached(
			size, DEVICE_VIEWPORT_HALF, BASE_ZOOM, player_center
		)
		assert(
			center.distance_to(previous_center) < 58.0,
			"strict camera target jumped at edge-follow step %d" % step
		)
		previous_center = center


func _verify_runtime_skirt() -> void:
	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data(
		"比奇省",
		{"mapId": MapEditorRuntimeBridge.BICH_MAP_ID, "name": "比奇省"}
	)
	await get_tree().process_frame
	await get_tree().process_frame
	var guard: Polygon2D
	for child: Node in background.get_children():
		if bool(child.get_meta("editor_runtime_guard_band", false)):
			guard = child as Polygon2D
			break
	assert(guard != null, "runtime edge skirt was not created")
	assert(
		str(guard.get_meta("editor_runtime_edge_skirt_contract_id", ""))
		== CameraConstraint.EDGE_SKIRT_CONTRACT_ID
	)
	assert(bool(guard.get_meta("editor_runtime_guard_non_walkable", false)))
	assert(
		is_equal_approx(
			float(guard.get_meta("editor_runtime_guard_band_world", 0.0)),
			GUARD_BAND_WORLD
		)
	)
	var guard_material := guard.material as ShaderMaterial
	assert(guard_material != null, "Bich guard band must use a shader material")
	var guard_shader := guard_material.shader
	assert(guard_shader != null, "Bich guard band shader missing")
	assert(
		not guard_shader.code.contains("sin(")
		and not guard_shader.code.contains("terrain_hash")
		and not guard_shader.code.contains("edge_mark"),
		"Bich guard shader must not retain animated/hash variation or edge mark"
	)
	assert(
		guard_shader.code.contains("discard"),
		"Bich guard shader must discard the authored diamond interior"
	)
	var boundary := CollisionGeometry.map_inner_boundary_world(
		Vector2i(80, 80)
	)
	var guard_bounds := Rect2(guard.polygon[0], Vector2.ZERO)
	for point: Vector2 in guard.polygon:
		guard_bounds = guard_bounds.expand(point)
	for player_center: Vector2 in boundary:
		var center := CameraConstraint.resolve_strict_follow_cached(
			Vector2i(80, 80), DEVICE_VIEWPORT_HALF, BASE_ZOOM, player_center
		)
		var strict: Dictionary = CameraConstraint.constrain_center(
			Vector2i(80, 80),
			DEVICE_VIEWPORT_HALF,
			BASE_ZOOM,
			player_center
		)
		var world_half_extents := Vector2(
			strict.get("world_half_extents", Vector2.ZERO)
		)
		for corner: Vector2 in CameraConstraint.viewport_corners(
			center, world_half_extents
		):
			assert(
				guard_bounds.has_point(corner),
				"remaining exterior view is not covered by edge skirt: %s"
				% corner
			)


func _centroid(points: PackedVector2Array) -> Vector2:
	var result := Vector2.ZERO
	for point: Vector2 in points:
		result += point
	return result / float(points.size())
