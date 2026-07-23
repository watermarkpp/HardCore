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
	assert(game.current_map_id == 4, "camera fixture did not enter the runtime Bich map")
	var camera: Camera2D = game.get("_world_camera") as Camera2D
	assert(camera != null and camera.name == "WorldCamera")
	var runtime := MapEditorRuntimeBridge.load_map(game.current_map_id)
	var raw_size: Array = runtime.design.design_size
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var boundary := MapEditorRuntimeCollisionGeometryService.map_inner_boundary_world(
		design_size
	)
	game.player.global_position = boundary[1] + Vector2(900.0, -700.0)
	game._update_world_camera_constraint()
	var verification := CameraConstraint.constrain_center(
		design_size,
		game.get_viewport().get_visible_rect().size * 0.5,
		camera.zoom,
		camera.global_position
	)
	assert(verification.ok, "GameRoot camera did not resolve a legal center")
	assert(CameraConstraint.viewport_inside_boundary(verification),
		"GameRoot camera still exposes the two-layer off-map edge")
	assert(not camera.global_position.is_equal_approx(game.player.global_position),
		"GameRoot left Camera2D centred on an exterior player position")
	assert(
		camera.zoom.x >= ArtSpec.CAMERA_ZOOM - 0.001
		and is_equal_approx(camera.zoom.x, camera.zoom.y),
		"GameRoot camera zoom is invalid: %s / base=%s" % [
			camera.zoom, ArtSpec.CAMERA_ZOOM,
		]
	)
	print("GAME_ROOT_DIAMOND_CAMERA_CONSTRAINT_PASS runtime camera clamps viewport inside map diamond")
	get_tree().quit(0)
