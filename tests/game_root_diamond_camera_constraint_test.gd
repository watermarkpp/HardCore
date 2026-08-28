extends Node

const CameraConstraint := preload(
	"res://scripts/map_editor/map_diamond_camera_constraint_service.gd"
)


func _ready() -> void:
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
	for edge_index in boundary.size():
		var next_index := (edge_index + 1) % boundary.size()
		probes.append((boundary[edge_index] + boundary[next_index]) * 0.5)
	var viewport_size := game.get_viewport().get_visible_rect().size
	var maximum_offset := viewport_size * (
		CameraConstraint.DEFAULT_PLAYER_SCREEN_OFFSET_FRACTION
	)
	for probe: Vector2 in probes:
		game.player.global_position = probe
		game._update_world_camera_constraint(2.0)
		var screen_offset := Vector2(
			absf(camera.global_position.x - probe.x) * camera.zoom.x,
			absf(camera.global_position.y - probe.y) * camera.zoom.y
		)
		assert(
			screen_offset.x <= maximum_offset.x + 0.1
			and screen_offset.y <= maximum_offset.y + 0.1,
			"player left the soft-follow screen band at %s: %s/%s" % [
				probe, screen_offset, maximum_offset,
			]
		)
		assert(
			camera.zoom.x >= ArtSpec.CAMERA_ZOOM - 0.001
			and camera.zoom.x
				<= CameraConstraint.DEFAULT_MAXIMUM_ZOOM + 0.001
			and is_equal_approx(camera.zoom.x, camera.zoom.y),
			"GameRoot camera zoom is invalid: %s" % camera.zoom
		)
		var verification := CameraConstraint.resolve_soft_follow(
			design_size, viewport_size * 0.5, camera.zoom, probe,
			camera.zoom.x
		)
		assert(
			str(verification.get("mode_id", ""))
			== CameraConstraint.SOFT_FOLLOW_MODE_ID
		)
		assert(
			str(verification.get("edge_skirt_contract_id", ""))
			== CameraConstraint.EDGE_SKIRT_CONTRACT_ID
		)
	assert(
		camera.global_position.distance_to(game.player.global_position)
		< viewport_size.length() * 0.15,
		"edge camera no longer prioritizes the player"
	)
	print(
		"GAME_ROOT_DIAMOND_CAMERA_CONSTRAINT_PASS "
		+ "player stays in center +/-14% band with smooth zoom and edge skirt"
	)
	get_tree().quit(0)
