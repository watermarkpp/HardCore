extends Node

const RuntimeBridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const CollisionGeometry := preload("res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd")


func _ready() -> void:
	for map_id: int in [4, 313, 217, 406]:
		var runtime := RuntimeBridge.load_map(map_id)
		assert(not runtime.is_empty(), "missing runtime map %d" % map_id)
		var raw_size: Array = runtime.design.design_size
		var size := Vector2i(int(raw_size[0]), int(raw_size[1]))
		var blocked: Array = runtime.collision.blocked_tiles
		assert(not blocked.is_empty(), "missing blocked cells %d" % map_id)
		var parts := str(blocked[0]).split(",")
		var cell := Vector2i(int(parts[0]), int(parts[1]))
		var center := CollisionGeometry.cell_center_world(cell, size)
		var old_vertex := MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(cell), size)
		assert(center - old_vertex == Vector2(0.0, 16.0), "cell center offset %d" % map_id)
		assert(CollisionGeometry.world_cell(center, size) == cell, "round trip %d" % map_id)
		var polygon := CollisionGeometry.cell_polygon_world(cell, size)
		assert(polygon.size() == 4)
		assert(polygon[0] == MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(cell), size))
		assert(polygon[2] == MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(cell + Vector2i.ONE), size))
	var synthetic_rect := [12, 14, 3, 2]
	var synthetic_size := Vector2i(80, 80)
	var rect_polygon := CollisionGeometry.rect_polygon_world(synthetic_rect, synthetic_size)
	assert(rect_polygon[0] == MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(12, 14), synthetic_size))
	assert(rect_polygon[2] == MapEditorCoordinate.ground_position_gu_to_screen_position_px(Vector2(15, 16), synthetic_size))
	assert(CollisionGeometry.tile_shape_contains_world(
		{"shape": "rect", "data": {"rect": synthetic_rect}},
		MapEditorCoordinate.grid_cell_to_screen_position_px(Vector2(13, 14), synthetic_size),
		synthetic_size
	))
	print("MAP_RUNTIME_CELL_COORDINATE_CONTRACT_PASS maps=4,313,217,406 offset_y=16")
	get_tree().quit(0)
