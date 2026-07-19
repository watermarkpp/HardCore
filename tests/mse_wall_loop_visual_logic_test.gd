extends Node


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	for family_id: String in ["orc_tomb_rough_stone_u0", "cave_granite_u0"]:
		_assert_family_loop(family_id)
	_assert_segmented_wall_draw_contract()
	print("MSE_WALL_LOOP_VISUAL_LOGIC_PASS families=2 segmented_parts=4")
	get_tree().quit(0)


func _assert_family_loop(family_id: String) -> void:
	var document := MapEditorTypes.new_map(
		"wall_loop_%s" % family_id,
		990210,
		"Wall Loop",
		Vector2i(12, 11)
	)
	var bounds := Rect2i(1, 1, 9, 8)
	var applied: Dictionary = MapEditorWallLoopService.apply_closed_rectangle(
		document,
		family_id,
		bounds,
		"outer_corner",
		"terrain_base",
		true,
		"test.%s.closed_loop" % family_id
	)
	assert(applied.ok, str(applied.get("errors", [])))
	assert(int(applied.removed_count) == 0)
	var validation: Dictionary = MapEditorWallLoopService.validate_closed_rectangle(
		document,
		family_id,
		bounds,
		str(applied.structure_id)
	)
	assert(validation.ok, str(validation.get("errors", [])))
	assert(int(validation.perimeter_cell_count) == 2 * 9 + 2 * (8 - 2))
	var expected_corner_directions := {
		Vector2i(1, 1): ["iso_x_pos", "iso_y_pos"],
		Vector2i(9, 1): ["iso_x_neg", "iso_y_pos"],
		Vector2i(9, 8): ["iso_x_neg", "iso_y_neg"],
		Vector2i(1, 8): ["iso_x_pos", "iso_y_neg"],
	}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) != str(applied.structure_id):
			continue
		assert(str(instance.get("collision_policy", "")) == "none")
		assert(instance.get("collision_footprint_tiles", []) == [0, 0])
		assert(str(instance.get("navigation_policy", "")) == "ignore")
		var asset := MapAssetCatalogService.find_asset(str(instance.asset_id))
		if str(asset.get("topology", "")) != "outer_corner":
			continue
		var tile_raw: Array = instance.tile
		var tile := Vector2i(int(tile_raw[0]), int(tile_raw[1]))
		assert(expected_corner_directions.has(tile))
		var actual: Array[String] = []
		for connector: Dictionary in asset.get("connectors", []):
			actual.append(str(connector.direction))
		actual.sort()
		var expected: Array = expected_corner_directions[tile].duplicate()
		expected.sort()
		assert(actual == expected)


func _assert_segmented_wall_draw_contract() -> void:
	var asset := MapAssetCatalogService.find_asset("orc_tomb_wall_straight_x_l4_v01")
	assert(str(asset.get("render_mode", "")) == "segmented")
	var document := MapEditorTypes.new_map(
		"wall_segment_draw_test",
		990211,
		"Wall Segment Draw",
		Vector2i(16, 16)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		str(asset.asset_id),
		"terrain",
		Vector2i(4, 4),
		"terrain_base"
	)
	assert(placed.ok, str(placed.get("errors", [])))
	var commands := MapEditorCanvasPreview.instance_draw_commands(
		placed.instance,
		asset,
		0,
		0
	)
	assert(commands.size() == 12)
	var part_tiles := {}
	for command: Dictionary in commands:
		assert(not str(command.image_path).is_empty())
		var tile: Vector2i = command.sort_tile
		part_tiles["%d,%d" % [tile.x, tile.y]] = true
	assert(part_tiles.size() == 4)
	for x in range(4, 8):
		assert(part_tiles.has("%d,4" % x))
