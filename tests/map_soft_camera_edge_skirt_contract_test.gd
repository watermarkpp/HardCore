extends Node

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const DEVICE_VIEWPORT_HALF := Vector2(1332.0, 600.0)
const BASE_ZOOM := Vector2.ONE * 1.06
const MAXIMUM_ZOOM := 1.16
const OFFSET_FRACTION := 0.14
const GUARD_BAND_WORLD := 1536.0


func _ready() -> void:
	_verify_map(Vector2i(80, 80), true)
	_verify_map(Vector2i(38, 38), false)
	_verify_continuous_edge_pressure()
	await _verify_runtime_skirt()
	print(
		(
			"MAP_SOFT_CAMERA_EDGE_SKIRT_PASS contract=%s mode=%s "
			+ "viewport=2664x1200 offset=14%% zoom=1.06..1.16"
		)
		% [
			CameraConstraint.CONTRACT_ID,
			CameraConstraint.SOFT_FOLLOW_MODE_ID,
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
		var result := CameraConstraint.resolve_soft_follow(
			size,
			DEVICE_VIEWPORT_HALF,
			BASE_ZOOM,
			player_center,
			MAXIMUM_ZOOM,
			OFFSET_FRACTION
		)
		assert(str(result.contract_id) == CameraConstraint.CONTRACT_ID)
		assert(str(result.mode_id) == CameraConstraint.SOFT_FOLLOW_MODE_ID)
		assert(
			str(result.edge_skirt_contract_id)
			== CameraConstraint.EDGE_SKIRT_CONTRACT_ID
		)
		var zoom: Vector2 = result.recommended_zoom
		assert(
			zoom.x >= BASE_ZOOM.x - 0.0001
			and zoom.x <= MAXIMUM_ZOOM + 0.0001
			and is_equal_approx(zoom.x, zoom.y),
			"zoom outside contract for %s at %s: %s" % [
				size, player_center, zoom,
			]
		)
		var offset: Vector2 = result.player_screen_offset_pixels
		var maximum_offset: Vector2 = (
			result.maximum_player_screen_offset_pixels
		)
		assert(
			offset.x <= maximum_offset.x + 0.01
			and offset.y <= maximum_offset.y + 0.01,
			"player screen offset exceeded 14%% for %s at %s: %s/%s" % [
				size, player_center, offset, maximum_offset,
			]
		)
		assert(
			float(result.required_guard_band_world)
			<= GUARD_BAND_WORLD + 0.01,
			"edge exposure exceeds packaged skirt for %s at %s: %s" % [
				size, player_center, result.required_guard_band_world,
			]
		)
		if player_center.is_equal_approx(centroid):
			assert(Vector2(result.center).is_equal_approx(player_center))
			assert(float(result.edge_pressure) <= 0.0001)


func _verify_continuous_edge_pressure() -> void:
	var size := Vector2i(80, 80)
	var boundary := CollisionGeometry.map_inner_boundary_world(size)
	var centroid := _centroid(boundary)
	var target := boundary[1]
	var previous_center := centroid
	var previous_zoom := BASE_ZOOM.x
	for step in range(1, 65):
		var player_center := centroid.lerp(target, float(step) / 64.0)
		var result := CameraConstraint.resolve_soft_follow(
			size, DEVICE_VIEWPORT_HALF, BASE_ZOOM, player_center
		)
		var center: Vector2 = result.center
		var zoom := float(Vector2(result.recommended_zoom).x)
		assert(
			center.distance_to(previous_center) < 58.0,
			"soft camera target jumped at edge-pressure step %d" % step
		)
		assert(
			zoom + 0.0001 >= previous_zoom,
			"recommended zoom moved backward under rising edge pressure"
		)
		previous_center = center
		previous_zoom = zoom


func _verify_runtime_skirt() -> void:
	var background := WorldBackground.new()
	add_child(background)
	background.set_zone_data("比奇省", {"mapId": 4, "name": "比奇省"})
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
	var boundary := CollisionGeometry.map_inner_boundary_world(
		Vector2i(80, 80)
	)
	var guard_bounds := Rect2(guard.polygon[0], Vector2.ZERO)
	for point: Vector2 in guard.polygon:
		guard_bounds = guard_bounds.expand(point)
	for player_center: Vector2 in boundary:
		var result := CameraConstraint.resolve_soft_follow(
			Vector2i(80, 80),
			DEVICE_VIEWPORT_HALF,
			BASE_ZOOM,
			player_center
		)
		for corner: Vector2 in CameraConstraint.viewport_corners(
			Vector2(result.center), Vector2(result.world_half_extents)
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
