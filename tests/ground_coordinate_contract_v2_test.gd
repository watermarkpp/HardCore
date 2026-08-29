extends Node

const Coordinate := preload("res://scripts/map_editor/map_editor_coordinate.gd")
const CollisionGeometry := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const GroundService := preload("res://scripts/map_editor/map_editor_ground_service.gd")

const DESIGN_SIZE := Vector2i(80, 80)
const CHUNK_SIZE := Vector2i(1024, 1024)


func _ready() -> void:
	_assert_ground_canvas()
	_assert_boundary()
	_assert_cell_runtime_collision_alignment()
	_assert_operation_repartition()
	_assert_editor_save_reload_roundtrip()
	print(
		"GROUND_COORDINATE_CONTRACT_V2_PASS contract=%s origin=%s image=%s center=%s"
		% [
			Coordinate.GROUND_COORDINATE_CONTRACT_ID,
			Coordinate.origin_px(DESIGN_SIZE),
			Coordinate.ground_image_size(DESIGN_SIZE),
			Coordinate.ground_pixel_center(DESIGN_SIZE),
		]
	)
	get_tree().quit(0)


func _assert_ground_canvas() -> void:
	assert(Coordinate.GROUND_COORDINATE_CONTRACT_ID == "isometric_cell_center_64x32_v2")
	assert(Coordinate.origin_px(DESIGN_SIZE).is_equal_approx(Vector2(2560, 0)))
	assert(Coordinate.ground_image_size(DESIGN_SIZE) == Vector2i(5120, 2560))
	assert(Coordinate.ground_pixel_center(DESIGN_SIZE).is_equal_approx(Vector2(2560, 1264)))
	var first := Coordinate.cell_texture_rect_ground_px(Vector2(0, 0), DESIGN_SIZE)
	var last := Coordinate.cell_texture_rect_ground_px(Vector2(79, 79), DESIGN_SIZE)
	assert(first.position.is_equal_approx(Vector2(2528, 0)))
	assert(last.position.is_equal_approx(Vector2(2528, 2528)))
	assert(last.end.y == 2560.0)


func _assert_boundary() -> void:
	var boundary := CollisionGeometry.map_inner_boundary_tile_polygon(DESIGN_SIZE)
	assert(boundary == PackedVector2Array([
		Vector2(0, 0), Vector2(80, 0), Vector2(80, 80), Vector2(0, 80)
	]))
	assert(not CollisionGeometry.visible_ground_contains_tile(Vector2(-0.5, -0.5), DESIGN_SIZE))
	assert(CollisionGeometry.visible_ground_contains_tile(Vector2.ZERO, DESIGN_SIZE))
	assert(not CollisionGeometry.visible_ground_contains_tile(Vector2(80, 0), DESIGN_SIZE))
	var world_boundary := CollisionGeometry.map_inner_boundary_world(DESIGN_SIZE)
	assert(world_boundary[0].is_equal_approx(Vector2(0, -1264)))
	assert(world_boundary[2].is_equal_approx(Vector2(0, 1296)))


func _assert_cell_runtime_collision_alignment() -> void:
	for cell: Vector2i in [Vector2i(0, 0), Vector2i(79, 79)]:
		var ground_center_world := (
			Coordinate.cell_center_to_ground_px(cell, DESIGN_SIZE)
			- Coordinate.ground_pixel_center(DESIGN_SIZE)
		)
		var runtime_center := Coordinate.grid_cell_to_screen_position_px(Vector2(cell), DESIGN_SIZE)
		var collision_center := CollisionGeometry.cell_center_world(cell, DESIGN_SIZE)
		var polygon := CollisionGeometry.cell_polygon_world(cell, DESIGN_SIZE)
		var polygon_center := Vector2.ZERO
		for point: Vector2 in polygon:
			polygon_center += point
		polygon_center /= float(polygon.size())
		assert(ground_center_world.is_equal_approx(runtime_center))
		assert(runtime_center.is_equal_approx(collision_center))
		assert(collision_center.is_equal_approx(polygon_center))


func _assert_operation_repartition() -> void:
	var moved_operation := {"op": "paint_tile", "tile": [0, 62], "asset_id": "ground.test"}
	var retained_operation := {"op": "erase_tile", "tile": [79, 79]}
	var state := {"operations_by_chunk": {"c_0_1": [moved_operation], "c_2_2": [retained_operation]}}
	assert(GroundService._repartition_operations_by_chunk(state, DESIGN_SIZE, CHUNK_SIZE))
	var operations: Dictionary = state.operations_by_chunk
	assert(operations.has("c_0_0") and operations.has("c_2_2"))
	assert((operations["c_0_0"] as Array)[0] == moved_operation)
	assert((operations["c_2_2"] as Array)[0] == retained_operation)
	assert(GroundService.tile_overrides(state).has("0,62"))
	assert(not GroundService.tile_overrides(state).has("79,79"))


func _assert_editor_save_reload_roundtrip() -> void:
	var document := MapEditorTypes.new_map(
		"ground_v2_roundtrip",
		990184,
		"Ground V2 Roundtrip",
		Vector2i(4, 4),
	)
	var test_root := "user://ground_v2_roundtrip_%s" % Time.get_ticks_usec()
	document.editor_meta.workspace = test_root
	var paint := GroundService.record_tile_paint(
		document,
		Vector2i(1, 1),
		"ground.dark_grass.001",
	)
	assert(paint.ok, str(paint.get("errors", [])))
	var save_path := test_root.path_join("ground_v2_roundtrip.editor.json")
	var saved := MapEditorSaveService.save_document(document, save_path)
	assert(saved.ok, str(saved.get("errors", [])))
	var loaded := MapEditorLoadService.load_document(save_path, false)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var reopened_document: Dictionary = loaded.document
	var reopened := GroundService.initialize(reopened_document)
	assert(reopened.ok, str(reopened.get("errors", [])))
	assert(
		reopened_document.ground.origin_px == [128.0, 0.0],
		"editor reload restored the legacy half-cell origin",
	)
	assert(
		reopened_document.ground.coordinate_contract_id
		== Coordinate.GROUND_COORDINATE_CONTRACT_ID,
	)
	assert(
		str(reopened.manifest.coordinate_contract_id)
		== Coordinate.GROUND_COORDINATE_CONTRACT_ID,
	)
	assert(
		str(reopened.state.coordinate_contract_id)
		== Coordinate.GROUND_COORDINATE_CONTRACT_ID,
	)
	assert(
		GroundService.tile_overrides(reopened.state).get("1,1", "")
		== "ground.dark_grass.001",
		"edited ground tile was lost across editor save/reload",
	)
