extends Node


func _ready() -> void:
	var preview := MapEditorCanvasPreview.new()
	preview.size = Vector2(800, 600)
	add_child(preview)
	preview.set_document(MapEditorTypes.new_map("normal_place_input", 990010, "Normal Place", Vector2i(32, 32)))
	preview.activate_normal_placement("v1_5.a001_01")
	await get_tree().process_frame
	preview._draw()
	var received: Array = []
	preview.paint_requested.connect(func(tile: Vector2i, asset_id: String): received.append([tile, asset_id]))
	var design_size := Vector2i(32, 32)
	var position := preview._draw_offset + MapEditorCoordinate.tile_to_ground_px(Vector2(8, 8), design_size) * preview._draw_scale
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.pressed = true
	preview._gui_input(event)
	assert(received.size() == 1)
	assert(received[0][0] == Vector2i(8, 8) and received[0][1] == "v1_5.a001_01")
	print("MSE_NORMAL_PLACEMENT_INPUT_PASS")
	get_tree().quit()
