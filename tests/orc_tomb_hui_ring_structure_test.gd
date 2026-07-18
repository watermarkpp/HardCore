extends Node

const DOCUMENT_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const STRUCTURE_ID := "orc_tomb_1.hui_ring.v1"


func _ready() -> void:
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(str(document.get("map_id", "")) == "orc_tomb_1")
	var ground := MapEditorGroundService.initialize(document)
	assert(ground.ok, str(ground.get("errors", [])))
	assert(MapEditorGroundService.tile_overrides(ground.state).size() == 38 * 38)
	var structure: Dictionary = document.design.get("dungeon_structure", {})
	assert(str(structure.get("structure_id", "")) == STRUCTURE_ID)
	assert(str(structure.get("kind", "")) == "hui_ring")
	assert(str(structure.get("collision_authority", "")) == "manual_by_user")

	var walls: Array[Dictionary] = []
	var occupied := {}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) != STRUCTURE_ID:
			continue
		walls.append(instance)
		assert(str(instance.get("asset_id", "")).begins_with("orc_tomb_wall_"))
		assert(str(instance.get("collision_policy", "")) == "none")
		assert((instance.get("collision_cells", []) as Array).is_empty())
		var tile: Array = instance.get("tile", [0, 0])
		var footprint: Array = instance.get("footprint_tiles", [1, 1])
		for y in range(int(tile[1]), int(tile[1]) + int(footprint[1])):
			for x in range(int(tile[0]), int(tile[0]) + int(footprint[0])):
				var key := "%d,%d" % [x, y]
				assert(not occupied.has(key), "overlapping_wall_cell:%s" % key)
				occupied[key] = true
	assert(walls.size() == 54)
	assert(occupied.size() == 176)
	assert(_has_wall(walls, "orc_tomb_wall_door_x_open_v01", Vector2i(18, 34), "outer_entrance"))
	assert(_has_wall(walls, "orc_tomb_wall_door_x_open_v01", Vector2i(18, 12), "inner_entrance"))
	_assert_ring_cells(occupied, Rect2i(3, 3, 32, 32))
	_assert_ring_cells(occupied, Rect2i(12, 12, 14, 14))
	print("ORC_TOMB_HUI_RING_STRUCTURE_PASS walls=%d occupied=%d" % [walls.size(), occupied.size()])
	get_tree().quit(0)


func _has_wall(walls: Array[Dictionary], asset_id: String, tile: Vector2i, role: String) -> bool:
	for wall: Dictionary in walls:
		var raw_tile: Array = wall.get("tile", [0, 0])
		if str(wall.get("asset_id", "")) == asset_id \
				and Vector2i(int(raw_tile[0]), int(raw_tile[1])) == tile \
				and str(wall.get("structure_role", "")) == role:
			return true
	return false


func _assert_ring_cells(occupied: Dictionary, bounds: Rect2i) -> void:
	for x in range(bounds.position.x, bounds.end.x):
		assert(occupied.has("%d,%d" % [x, bounds.position.y]))
		assert(occupied.has("%d,%d" % [x, bounds.end.y - 1]))
	for y in range(bounds.position.y, bounds.end.y):
		assert(occupied.has("%d,%d" % [bounds.position.x, y]))
		assert(occupied.has("%d,%d" % [bounds.end.x - 1, y]))
