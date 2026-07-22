extends SceneTree

const DOCUMENT_PATH := "res://map_editor_workspace/orc_tomb_1/orc_tomb_1.editor.json"
const STRUCTURE_ID := "orc_tomb_1.hui_ring.v1"
const WALL_FAMILY_ID := "orc_tomb_rough_stone_u0"
const WALL_PREFIX := "orc_tomb_wall_"

var _variant_cursor := 0


func _init() -> void:
	print("ORC_TOMB_1_HUI_RING_STAGE load_document")
	var loaded := MapEditorLoadService.load_document(DOCUMENT_PATH)
	assert(loaded.ok, str(loaded.get("errors", [])))
	var document: Dictionary = loaded.document
	assert(str(document.get("map_id", "")) == "orc_tomb_1")
	var design_size: Array = document.design.design_size
	assert(Vector2i(int(design_size[0]), int(design_size[1])) == Vector2i(38, 38))
	print("ORC_TOMB_1_HUI_RING_STAGE verify_ground")
	var ground := MapEditorGroundService.initialize(document)
	assert(ground.ok, str(ground.get("errors", [])))
	assert(MapEditorGroundService.tile_overrides(ground.state).size() == 38 * 38, "orc_tomb_1_ground_not_complete")

	print("ORC_TOMB_1_HUI_RING_STAGE outer_ring")
	_remove_previous_structure(document)
	# Outer ring: three-tile entrance on the front/south x-axis wall.
	_place_corner(document, Vector2i(3, 3), "outer_nw", "outer_ring")
	_place_corner(document, Vector2i(34, 3), "outer_ne", "outer_ring")
	_place_corner(document, Vector2i(34, 34), "outer_se", "outer_ring")
	_place_corner(document, Vector2i(3, 34), "outer_sw", "outer_ring")
	_place_span(document, "x", 3, 4, 30, "outer_ring")
	_place_span(document, "x", 34, 4, 14, "outer_ring")
	_place_door(document, "x", Vector2i(18, 34), "outer_entrance")
	_place_span(document, "x", 34, 21, 13, "outer_ring")
	_place_span(document, "y", 3, 4, 30, "outer_ring")
	_place_span(document, "y", 34, 4, 30, "outer_ring")

	# Inner ring: entrance faces the rear/north wall so the route must circle
	# through the corridor before entering the central chamber.
	print("ORC_TOMB_1_HUI_RING_STAGE inner_ring")
	_place_corner(document, Vector2i(12, 12), "inner_nw", "inner_ring")
	_place_corner(document, Vector2i(25, 12), "inner_ne", "inner_ring")
	_place_corner(document, Vector2i(25, 25), "inner_se", "inner_ring")
	_place_corner(document, Vector2i(12, 25), "inner_sw", "inner_ring")
	_place_span(document, "x", 12, 13, 5, "inner_ring")
	_place_door(document, "x", Vector2i(18, 12), "inner_entrance")
	_place_span(document, "x", 12, 21, 4, "inner_ring")
	_place_span(document, "x", 25, 13, 12, "inner_ring")
	_place_span(document, "y", 12, 13, 12, "inner_ring")
	_place_span(document, "y", 25, 13, 12, "inner_ring")

	print("ORC_TOMB_1_HUI_RING_STAGE sort_and_save")
	var terrain_entries: Array = document.layers.terrain_base
	terrain_entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return _sort_key(a) < _sort_key(b)
	)
	document.layers.terrain_base = terrain_entries
	document.editor_meta["revision"] = int(document.editor_meta.get("revision", 1)) + 1
	document.editor_meta["milestone"] = "ORC-TOMB-1-HUI-RING-V1"
	document.editor_meta["structure_id"] = STRUCTURE_ID
	document.editor_meta["structure_policy"] = "visual_walls_only_manual_collision_and_decoration"
	document.design["dungeon_structure"] = {
		"structure_id": STRUCTURE_ID,
		"kind": "hui_ring",
		"wall_family_id": WALL_FAMILY_ID,
		"outer_bounds": [3, 3, 32, 32],
		"inner_bounds": [12, 12, 14, 14],
		"outer_entrance_tiles": [18, 34, 3, 1],
		"inner_entrance_tiles": [18, 12, 3, 1],
		"collision_authority": "manual_by_user",
	}
	var save := MapEditorSaveService.save_document(document, DOCUMENT_PATH)
	assert(save.ok, str(save.get("errors", [])))
	var structure_count := 0
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) == STRUCTURE_ID:
			structure_count += 1
	assert(structure_count == 54, "unexpected_structure_instance_count:%d" % structure_count)
	assert(MapEditorCollisionService.build_walkability(document).blocked_count == 0, "visual_structure_must_not_generate_collision")
	print("ORC_TOMB_1_HUI_RING_PASS structure=%s walls=%d path=%s" % [STRUCTURE_ID, structure_count, save.path])
	quit()


func _remove_previous_structure(document: Dictionary) -> void:
	for layer_name: String in document.layers:
		var kept: Array = []
		for entry: Dictionary in document.layers[layer_name]:
			if str(entry.get("structure_id", "")) != STRUCTURE_ID:
				kept.append(entry)
		document.layers[layer_name] = kept


func _place_corner(document: Dictionary, tile: Vector2i, orientation: String, structure_role: String) -> void:
	_place_visual_wall(document, WALL_PREFIX + orientation + "_v01", tile, structure_role)


func _place_door(document: Dictionary, axis: String, tile: Vector2i, structure_role: String) -> void:
	_place_visual_wall(document, WALL_PREFIX + "door_%s_open_v01" % axis, tile, structure_role)


func _place_span(document: Dictionary, axis: String, fixed: int, start: int, length: int, structure_role: String) -> void:
	var cursor := start
	for module_length: int in _decompose_span(length):
		var variant := 1
		if module_length >= 3:
			variant = 1 + posmod(_variant_cursor, 3)
			_variant_cursor += 1
		var asset_id := WALL_PREFIX + "straight_%s_l%d_v%02d" % [axis, module_length, variant]
		var tile := Vector2i(cursor, fixed) if axis == "x" else Vector2i(fixed, cursor)
		_place_visual_wall(document, asset_id, tile, structure_role)
		cursor += module_length
	assert(cursor == start + length)


func _decompose_span(length: int) -> Array[int]:
	var best: Array[int] = []
	var best_score := 1_000_000
	for l4 in range(length / 4 + 1):
		for l3 in range(length / 3 + 1):
			for l2 in range(length / 2 + 1):
				for l1 in range(length + 1):
					if l4 * 4 + l3 * 3 + l2 * 2 + l1 != length:
						continue
					var count := l4 + l3 + l2 + l1
					var score := count * 1000 + l1 * 100 + l2 * 10 - l4 * 2 - l3
					if score >= best_score:
						continue
					best_score = score
					best = []
					for unused in l4:
						best.append(4)
					for unused in l3:
						best.append(3)
					for unused in l2:
						best.append(2)
					for unused in l1:
						best.append(1)
	assert(not best.is_empty(), "cannot_decompose_wall_span:%d" % length)
	return best


func _place_visual_wall(document: Dictionary, asset_id: String, tile: Vector2i, structure_role: String) -> void:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	assert(not asset.is_empty(), "wall_asset_missing:%s" % asset_id)
	assert(str(asset.get("wall_family_id", "")) == WALL_FAMILY_ID)
	var placed := MapEditorInstanceService.create_instance(document, asset_id, "terrain", tile, "terrain_base")
	assert(placed.ok, "%s@%s:%s" % [asset_id, tile, placed.get("errors", [])])
	var entries: Array = document.layers.terrain_base
	var instance: Dictionary = entries.back()
	assert(str(instance.get("instance_id", "")) == str(placed.instance.instance_id))
	instance["structure_id"] = STRUCTURE_ID
	instance["structure_role"] = structure_role
	instance["generated_by"] = "build_orc_tomb_1_hui_ring.gd"
	instance["scene_intent"] = "dungeon_wall_visual_structure"
	instance["collision_policy"] = "none"
	instance["collision_profile_id"] = "none_visual"
	instance["collision_footprint_tiles"] = [0, 0]
	instance["collision_cells"] = []
	instance["navigation_policy"] = "ignore"
	instance["manual_collision_expected"] = true
	entries[entries.size() - 1] = instance
	document.layers.terrain_base = entries


func _sort_key(instance: Dictionary) -> int:
	var tile: Array = instance.get("tile", [0, 0])
	var footprint: Array = instance.get("footprint_tiles", [1, 1])
	var front_x := int(tile[0]) + int(footprint[0]) - 1
	var front_y := int(tile[1]) + int(footprint[1]) - 1
	return (front_x + front_y) * 1000 + front_x
