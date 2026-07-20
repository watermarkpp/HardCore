extends Node

const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const CATALOG_PATH := "res://assets/data/assets/map_wooma_temple_wall_asset_catalog.json"


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var parsed := _read_catalog()
	var assets: Array = parsed.get("assets", [])
	assert(assets.size() == 42)
	assert(parsed.get("wall_family_ids", []) == [FAMILY_ID])
	assert(str(parsed.get("collision_authority", "")) == "manual_by_user")

	var ids := {}
	var topology_counts := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not ids.has(asset_id), "duplicate asset id: %s" % asset_id)
		ids[asset_id] = true
		assert(str(asset.get("wall_family_id", "")) == FAMILY_ID)
		assert(
			str(asset.get("visual_profile_id", ""))
			== "wooma_temple_monumental_wall_v2"
		)
		assert(
			str(asset.get("placement_preview_mode", ""))
			== "image_and_footprint"
		)
		assert(str(asset.get("asset_type", "")) == "wall_module")
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("collision_policy", "")) == "none")
		assert(asset.get("collision_cells", []) == [])
		var collision_footprint: Array = asset.get("collision_footprint_tiles", [])
		assert(
			collision_footprint.size() == 2
			and int(collision_footprint[0]) == 0
			and int(collision_footprint[1]) == 0
		)
		assert(str(asset.get("navigation_policy", "")) == "ignore")
		assert(bool(asset.get("manual_collision_expected", false)))
		assert(str(asset.get("collision_authority", "")) == "manual_by_user")
		assert(str(asset.get("palette_path", "")).begins_with(
			"洞穴与地下城/墙体模块/沃玛寺庙墙体/"
		))
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), "%s missing image" % asset_id)
		var texture := load(image_path) as Texture2D
		assert(texture != null, "%s invalid texture" % asset_id)
		var image := texture.get_image()
		assert(image != null and not image.is_empty(), "%s invalid image" % asset_id)
		assert(image.detect_alpha() != Image.ALPHA_NONE, "%s missing alpha" % asset_id)
		var used_rect := image.get_used_rect()
		var selection_bounds: Array = asset.get("selection_bounds_px", [])
		assert(selection_bounds.size() == 4)
		assert(
			int(selection_bounds[0]) == used_rect.position.x
			and int(selection_bounds[1]) == used_rect.position.y
			and int(selection_bounds[2]) == used_rect.size.x
			and int(selection_bounds[3]) == used_rect.size.y
		)
		var topology := str(asset.get("topology", ""))
		topology_counts[topology] = int(topology_counts.get(topology, 0)) + 1
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "%s not loaded by catalog service" % asset_id)
		assert(str(effective.get("collision_policy", "")) == "none")
		var effective_footprint: Array = effective.get("collision_footprint_tiles", [])
		assert(
			effective_footprint.size() == 2
			and int(effective_footprint[0]) == 0
			and int(effective_footprint[1]) == 0
		)

	assert(topology_counts == {
		"broken_adapter": 4,
		"door_adapter": 4,
		"end_cap": 4,
		"inner_corner": 4,
		"outer_corner": 4,
		"seam_cover": 6,
		"straight": 16,
	})
	_assert_family_menu()
	_assert_segmented_straight()
	_assert_monumental_geometry(assets)
	_assert_saved_instance_profile_refresh()
	_assert_four_directional_corners(assets)
	_assert_adaptive_corner_copy_offsets()
	_assert_corner_occlusion_order()
	_assert_closed_loop()
	print("MSE_WOOMA_TEMPLE_WALL_PACK_PASS assets=42 closed_loop=12x10")
	get_tree().quit(0)


func _read_catalog() -> Dictionary:
	assert(FileAccess.file_exists(CATALOG_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	return parsed


func _assert_family_menu() -> void:
	var found := false
	for family: Dictionary in MapEditorWallLoopService.available_families():
		if str(family.get("wall_family_id", "")) != FAMILY_ID:
			continue
		found = true
		assert(str(family.get("display_name", "")) == "沃玛寺庙哥特旧石墙")
	assert(found, "Wooma Temple wall family missing from editor menu")


func _assert_segmented_straight() -> void:
	var wall := MapAssetCatalogService.find_asset("wooma_temple_wall_straight_x_l4_v01")
	assert(not wall.is_empty())
	assert(str(wall.get("render_mode", "")) == "segmented")
	assert((wall.get("render_parts", []) as Array).size() == 4)
	var document := MapEditorTypes.new_map(
		"wooma_temple_segment_test",
		990310,
		"Wooma Temple Segment",
		Vector2i(24, 24)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		str(wall.asset_id),
		"terrain",
		Vector2i(4, 4),
		"terrain_base"
	)
	assert(placed.ok, str(placed.get("errors", [])))
	var commands := MapEditorCanvasPreview.instance_draw_commands(
		placed.instance,
		wall,
		0,
		0
	)
	assert(commands.size() == 4)
	var sort_tiles := {}
	for command: Dictionary in commands:
		var tile: Vector2i = command.sort_tile
		sort_tiles["%d,%d" % [tile.x, tile.y]] = true
	for x in range(4, 8):
		assert(sort_tiles.has("%d,4" % x))


func _assert_monumental_geometry(assets: Array) -> void:
	for asset: Dictionary in assets:
		var topology := str(asset.get("topology", ""))
		var anchor: Array = asset.get("placement_anchor_px", [])
		if topology not in ["straight", "door_adapter", "broken_adapter"]:
			assert(anchor.size() == 2 and int(anchor[1]) == 192)
			continue
		assert(anchor.size() == 2 and int(anchor[1]) == 176)
		var length := int(asset.get("length_tiles", 1))
		var image_size: Array = asset.get("image_size", [])
		assert(
			int(image_size[0]) == 32 * length + 64
			and int(image_size[1]) == 208 + 16 * length
		)
		var start_seam: Array = asset.get("start_seam_px", [])
		var end_seam: Array = asset.get("end_seam_px", [])
		assert(int(start_seam[1]) - int(anchor[1]) == 8)
		assert(int(end_seam[1]) - int(start_seam[1]) == 16 * length)


func _assert_saved_instance_profile_refresh() -> void:
	var asset := MapAssetCatalogService.find_asset(
		"wooma_temple_wall_straight_x_l4_v03"
	)
	assert(not asset.is_empty())
	var legacy_instance := {
		"asset_id": str(asset.get("asset_id", "")),
		"anchor_px": [48, 96],
		"placement_anchor_px": [48, 96],
		"scale": [1.0, 1.0],
	}
	MapEditorInstanceProfileService.refresh_from_asset(legacy_instance, asset)
	var refreshed_anchor: Array = legacy_instance.get("anchor_px", [])
	var refreshed_placement: Array = legacy_instance.get(
		"placement_anchor_px",
		[]
	)
	assert(
		int(refreshed_anchor[0]) == 48
		and int(refreshed_anchor[1]) == 176
	)
	assert(
		int(refreshed_placement[0]) == 48
		and int(refreshed_placement[1]) == 176
	)
	var refreshed_scale: Array = legacy_instance.get("scale", [])
	assert(
		is_equal_approx(float(refreshed_scale[0]), 1.0)
		and is_equal_approx(float(refreshed_scale[1]), 1.0)
	)


func _assert_four_directional_corners(assets: Array) -> void:
	var corners := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		if asset_id in [
			"wooma_temple_wall_outer_nw_v01",
			"wooma_temple_wall_outer_ne_v01",
			"wooma_temple_wall_outer_se_v01",
			"wooma_temple_wall_outer_sw_v01",
		]:
			corners[asset_id] = asset
	assert(corners.size() == 4)
	var expected_bottom_by_id := {
		"wooma_temple_wall_outer_nw_v01": 216,
		"wooma_temple_wall_outer_ne_v01": 216,
		"wooma_temple_wall_outer_se_v01": 216,
		"wooma_temple_wall_outer_sw_v01": 216,
	}
	var expected_left_by_id := {
		"wooma_temple_wall_outer_nw_v01": 32,
		"wooma_temple_wall_outer_ne_v01": 32,
		"wooma_temple_wall_outer_se_v01": 32,
		"wooma_temple_wall_outer_sw_v01": 32,
	}
	var reference_size := Vector2i.ZERO
	for asset_id: String in corners:
		var asset: Dictionary = corners[asset_id]
		var texture := load("res://" + str(asset.get("image", ""))) as Texture2D
		assert(texture != null)
		var image := texture.get_image()
		assert(image != null and not image.is_empty())
		var used_rect := image.get_used_rect()
		assert(used_rect.size.x == 96 and used_rect.size.y == 200)
		assert(used_rect.position.x == int(expected_left_by_id[asset_id]))
		assert(used_rect.end.y == int(expected_bottom_by_id[asset_id]))
		if reference_size == Vector2i.ZERO:
			reference_size = used_rect.size
		else:
			assert(used_rect.size == reference_size)


func _assert_adaptive_corner_copy_offsets() -> void:
	var document := MapEditorTypes.new_map(
		"wooma_corner_copy_test",
		990312,
		"Wooma Corner Copy",
		Vector2i(44, 44)
	)
	var asset_id := "wooma_temple_wall_inner_ne_v01"
	var bottom := MapEditorInstanceService.create_instance(
		document,
		asset_id,
		"terrain",
		Vector2i(43, 43),
		"terrain_base"
	)
	assert(bottom.ok)
	assert(
		str(bottom.instance.asset_id)
		== "wooma_temple_wall_inner_nw_v01"
	)
	assert(bottom.instance.offset_px == [0, -8])
	assert(str(bottom.instance.adaptive_corner_zone) == "max_max")

	var top := MapEditorInstanceService.duplicate_instance_snapshot(
		document,
		bottom.instance,
		Vector2i(0, 0)
	)
	assert(top.ok)
	assert(
		str(top.instance.asset_id)
		== "wooma_temple_wall_inner_se_v01"
	)
	assert(top.instance.offset_px == [0, 8])
	assert(str(top.instance.adaptive_corner_zone) == "min_min")
	assert(top.instance.adaptive_corner_sort_tile_offset == [2, 1])
	var top_commands := MapEditorCanvasPreview.instance_draw_commands(
		top.instance,
		MapAssetCatalogService.find_asset(asset_id)
	)
	assert(top_commands.size() == 1)
	assert(top_commands[0].sort_tile == Vector2i(2, 1))

	var moved := MapEditorInstanceService.move_instance(
		document,
		str(top.instance.instance_id),
		Vector2i(0, 43)
	)
	assert(moved.ok)
	assert(str(moved.instance.asset_id) == asset_id)
	assert(moved.instance.offset_px == [-16, 0])
	assert(str(moved.instance.adaptive_corner_zone) == "min_max")
	assert(moved.instance.adaptive_corner_sort_tile_offset == [2, 1])
	assert(moved.instance.tile_anchor == [0, 43])

	var right := MapEditorInstanceService.duplicate_instance_snapshot(
		document,
		bottom.instance,
		Vector2i(43, 0)
	)
	assert(right.ok)
	assert(
		str(right.instance.asset_id)
		== "wooma_temple_wall_inner_sw_v01"
	)
	assert(right.instance.offset_px == [16, 0])
	assert(str(right.instance.adaptive_corner_zone) == "max_min")
	assert(right.instance.adaptive_corner_sort_tile_offset == [0, 0])

	moved.instance["offset_px"] = [5, 7]
	var custom_move := MapEditorInstanceService.move_instance(
		document,
		str(moved.instance.instance_id),
		Vector2i(43, 0)
	)
	assert(custom_move.ok)
	assert(custom_move.instance.offset_px == [5, 7])


func _assert_corner_occlusion_order() -> void:
	var layer := 0
	var wall_before := {
		"sort_tile": Vector2i(42, 0),
		"layer_index": layer,
		"image_pass": 1,
		"part_order": 0,
		"sequence": 0,
	}
	var right_corner := {
		"sort_tile": Vector2i(43, 0),
		"layer_index": layer,
		"image_pass": 1,
		"part_order": 0,
		"sequence": 1,
	}
	var wall_after := {
		"sort_tile": Vector2i(43, 1),
		"layer_index": layer,
		"image_pass": 1,
		"part_order": 0,
		"sequence": 2,
	}
	assert(MapEditorCanvasPreview._draw_command_less(wall_before, right_corner))
	assert(MapEditorCanvasPreview._draw_command_less(right_corner, wall_after))

	var left_wall_before := wall_before.duplicate()
	left_wall_before.sort_tile = Vector2i(0, 42)
	var left_corner := right_corner.duplicate()
	left_corner.sort_tile = Vector2i(0, 43)
	var left_wall_after := wall_after.duplicate()
	left_wall_after.sort_tile = Vector2i(1, 43)
	assert(
		MapEditorCanvasPreview._draw_command_less(
			left_wall_before,
			left_corner
		)
	)
	assert(
		MapEditorCanvasPreview._draw_command_less(
			left_corner,
			left_wall_after
		)
	)


func _assert_closed_loop() -> void:
	var document := MapEditorTypes.new_map(
		"wooma_temple_loop_test",
		990311,
		"Wooma Temple Loop",
		Vector2i(24, 24)
	)
	var bounds := Rect2i(3, 4, 12, 10)
	var applied := MapEditorWallLoopService.apply_closed_rectangle(
		document,
		FAMILY_ID,
		bounds,
		"outer_corner",
		"terrain_base",
		true,
		"test.wooma_temple.closed_loop"
	)
	assert(applied.ok, str(applied.get("errors", [])))
	var validation := MapEditorWallLoopService.validate_closed_rectangle(
		document,
		FAMILY_ID,
		bounds,
		str(applied.structure_id)
	)
	assert(validation.ok, str(validation.get("errors", [])))
	assert(int(validation.perimeter_cell_count) == 2 * 12 + 2 * (10 - 2))
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		if str(instance.get("structure_id", "")) != str(applied.structure_id):
			continue
		assert(str(instance.get("collision_policy", "")) == "none")
		assert(instance.get("collision_cells", []) == [])
		assert(instance.get("collision_footprint_tiles", []) == [0, 0])
		assert(str(instance.get("collision_authority", "")) == "manual_by_user")
