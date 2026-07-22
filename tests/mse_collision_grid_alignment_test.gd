extends Node


func _ready() -> void:
	var design_size := Vector2i(38, 38)
	var document := MapEditorTypes.new_map(
		"collision_grid_alignment",
		990181,
		"Collision Grid Alignment",
		design_size
	)
	var preview := MapEditorCanvasPreview.new()
	preview.custom_minimum_size = Vector2(960, 720)
	preview.size = Vector2(960, 720)
	add_child(preview)
	preview.set_document(document)
	await get_tree().process_frame
	await get_tree().process_frame

	for tile: Vector2i in [
		Vector2i.ZERO,
		Vector2i(1, 1),
		Vector2i(17, 23),
		Vector2i(37, 37),
	]:
		var ground_polygon := MapEditorCoordinate.cell_polygon_ground_px(tile, design_size)
		var expected_center := MapEditorCoordinate.cell_center_to_ground_px(tile, design_size)
		var polygon_center := Vector2.ZERO
		for point: Vector2 in ground_polygon:
			polygon_center += point
		polygon_center /= float(ground_polygon.size())
		assert(polygon_center.is_equal_approx(expected_center))
		var screen_center := preview._draw_offset + expected_center * preview._draw_scale
		assert(preview.screen_to_tile(screen_center) == tile)
		var screen_polygon := MapEditorCanvasPreview._cell_polygon_screen(
			tile,
			design_size,
			preview._draw_offset,
			preview._draw_scale
		)
		for index in ground_polygon.size():
			assert(
				screen_polygon[index].is_equal_approx(
					preview._draw_offset + ground_polygon[index] * preview._draw_scale
				)
			)

	var received_cells: Array[Vector2i] = []
	preview.manual_collision_tile_clicked.connect(
		func(tile: Vector2i) -> void: received_cells.append(tile)
	)
	preview.set_interaction_mode("manual_collision")
	preview.set_manual_collision_draft("cell", Vector2i(-1, -1), [])
	var target_cell := Vector2i(12, 14)
	_click(
		preview,
		preview._draw_offset
		+ MapEditorCoordinate.cell_center_to_ground_px(target_cell, design_size)
		* preview._draw_scale
	)
	assert(received_cells == [target_cell])
	assert(MapEditorCollisionService.paint_collision_cell(document, target_cell).ok)
	var walkability := MapEditorCollisionService.build_walkability(document)
	assert(walkability.blocked_tiles.has("12,14"))
	assert(not walkability.blocked_tiles.has("11,13"))

	preview.set_manual_collision_draft("polygon", Vector2i(-1, -1), [])
	var target_vertex := Vector2i(8, 9)
	var vertex_screen := (
		preview._draw_offset
		+ MapEditorCoordinate.tile_to_ground_px(target_vertex, design_size)
		* preview._draw_scale
	)
	assert(preview.screen_to_grid_vertex(vertex_screen) == target_vertex)
	_click(preview, vertex_screen)
	assert(received_cells[-1] == target_vertex)

	var instance := {
		"instance_id": "inst_collision_alignment",
		"tile": [20, 21],
		"footprint_tiles": [3, 3],
		"collision_footprint_tiles": [1, 1],
		"collision_policy": "solid_footprint",
	}
	document.layers.object_base.append(instance)
	assert(MapEditorCollisionService._collision_origin(instance) == Vector2i(21, 22))
	walkability = MapEditorCollisionService.build_walkability(document)
	assert(walkability.blocked_tiles.has("21,22"))
	assert(not walkability.blocked_tiles.has("20,21"))

	print("MSE_COLLISION_GRID_ALIGNMENT_PASS cells=4 polygon_vertex=8,9 instance=21,22")
	get_tree().quit(0)


func _click(preview: MapEditorCanvasPreview, position: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = position
	preview._gui_input(event)
