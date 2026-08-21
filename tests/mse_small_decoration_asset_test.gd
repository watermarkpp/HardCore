extends Node


const CATALOG_PATH := "res://assets/data/assets/map_small_decoration_asset_catalog.json"
const REVIEW_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
const PACKAGE_ID := "mse_small_decoration_pack_20260822_v1"
const PALETTE_PATH := "装饰物1/小装饰物"
const ALPHA_THRESHOLD := 8
const PADDING_PX := 8
const TILE_SIZE := [64, 32]


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


func _alpha_bbox(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y: int in image.get_height():
		for x: int in image.get_width():
			if image.get_pixel(x, y).a * 255.0 < ALPHA_THRESHOLD:
				continue
			min_x = mini(min_x, x)
			min_y = mini(min_y, y)
			max_x = maxi(max_x, x)
			max_y = maxi(max_y, y)
	if max_x < 0:
		return Rect2i(-1, -1, 0, 0)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)


func _bounds_array(rect: Rect2i) -> Array[int]:
	return [rect.position.x, rect.position.y, rect.size.x, rect.size.y]


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array and (actual as Array).size() == expected.size(), label)
	for index: int in expected.size():
		assert(int((actual as Array)[index]) == int(expected[index]), label)


func _assert_transparent_border(image: Image, asset_id: String) -> void:
	for y: int in image.get_height():
		for x: int in image.get_width():
			if x < PADDING_PX or y < PADDING_PX or x >= image.get_width() - PADDING_PX or y >= image.get_height() - PADDING_PX:
				assert(image.get_pixel(x, y).a == 0.0, asset_id + ":nontransparent_padding")


func _assert_raw_asset(raw: Dictionary, asset_id: String) -> void:
	assert(str(raw.get("display_name", "")) == "小装饰物 " + asset_id.get_slice(".", 2), asset_id + ":display")
	assert(str(raw.get("asset_type", "")) == "small_prop", asset_id + ":asset_type")
	assert(str(raw.get("category", "")) == "visual_detail", asset_id + ":category")
	assert(str(raw.get("object_class", "")) == "decoration", asset_id + ":object_class")
	assert(str(raw.get("default_object_role", "")) == "decoration", asset_id + ":role")
	assert(str(raw.get("palette_path", "")) == PALETTE_PATH, asset_id + ":palette")
	assert(bool(raw.get("placeable", false)), asset_id + ":placeable")
	assert(str(raw.get("calibration_status", "")) == "placeable", asset_id + ":calibration")
	assert(bool(raw.get("geometry_pending_manual", false)), asset_id + ":manual_geometry")
	assert(str(raw.get("collision_policy", "")) == "none", asset_id + ":collision_policy")
	assert(str(raw.get("collision_profile_id", "")) == "none_visual", asset_id + ":collision_profile")
	assert(str(raw.get("navigation_policy", "")) == "ignore", asset_id + ":navigation")
	assert(bool(raw.get("manual_collision_expected", false)), asset_id + ":manual_collision")
	_assert_int_array(raw.get("collision_footprint_tiles", []), [0, 0], asset_id + ":collision_footprint")
	assert((raw.get("collision_cells", []) as Array).is_empty(), asset_id + ":collision_cells")
	assert((raw.get("placement_clearance_cells", []) as Array).is_empty(), asset_id + ":clearance")
	_assert_int_array(raw.get("tile_size", []), TILE_SIZE, asset_id + ":tile_size")
	var visible: Array = raw.get("visible_bounds_px", [])
	_assert_int_array(raw.get("selection_bounds_px", []), visible, asset_id + ":selection")
	var expected_footprint := [
		(int(visible[2]) + 63) / 64,
		(int(visible[3]) + 63) / 64,
	]
	for field: String in ["footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "base_footprint_tiles"]:
		_assert_int_array(raw.get(field, []), expected_footprint, asset_id + ":" + field)
	var processing: Dictionary = raw.get("processing", {})
	assert(str(processing.get("pipeline", "")) == "alpha_grid_tight_bbox_rgba_preserve_v1", asset_id + ":pipeline")
	assert(int(processing.get("alpha_threshold", 0)) == ALPHA_THRESHOLD, asset_id + ":threshold")
	assert(int(processing.get("padding_px", 0)) == PADDING_PX, asset_id + ":padding")
	assert(bool(processing.get("rgba_pixels_preserved", false)), asset_id + ":rgba_contract")
	assert(str(raw.get("source_sha256", "")).length() == 64, asset_id + ":source_sha")
	assert(str(raw.get("output_sha256", "")).length() == 64, asset_id + ":output_sha")
	var image_path := "res://" + str(raw.get("image", ""))
	assert(FileAccess.file_exists(image_path), asset_id + ":missing_image")
	var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
	assert(image != null and not image.is_empty(), asset_id + ":invalid_image")
	assert(image.detect_alpha() != Image.ALPHA_NONE, asset_id + ":missing_alpha")
	_assert_int_array(raw.get("canvas_size", []), [image.get_width(), image.get_height()], asset_id + ":canvas_size")
	var visible_rect := Rect2i(int(visible[0]), int(visible[1]), int(visible[2]), int(visible[3]))
	assert(_alpha_bbox(image) == visible_rect, asset_id + ":alpha_bbox")
	_assert_int_array(_bounds_array(image.get_used_rect()), visible, asset_id + ":used_rect")
	_assert_transparent_border(image, asset_id)


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var pack_catalog := _read_json(CATALOG_PATH)
	assert(str(pack_catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(pack_catalog.get("classification", "")) == PALETTE_PATH)
	assert(str(pack_catalog.get("palette_path", "")) == PALETTE_PATH)
	assert(int(pack_catalog.get("source_count", 0)) == 6)
	_assert_int_array(pack_catalog.get("grid", []), [2, 4], "grid")
	_assert_int_array(pack_catalog.get("cell_size_px", []), [362, 543], "cell_size")
	assert(int(pack_catalog.get("asset_count", 0)) == 48)
	var pack_assets: Array = pack_catalog.get("assets", [])
	assert(pack_assets.size() == 48)
	var raw_ids := {}
	var raw_images := {}
	for index: int in 48:
		var asset_id := "mse.small_decor.%03d" % (index + 1)
		var raw: Dictionary = pack_assets[index]
		assert(str(raw.get("asset_id", "")) == asset_id, asset_id + ":row_major_order")
		assert(not raw_ids.has(asset_id), asset_id + ":duplicate_id")
		raw_ids[asset_id] = true
		var image_path := str(raw.get("image", ""))
		assert(not raw_images.has(image_path), asset_id + ":duplicate_image")
		raw_images[image_path] = true
		_assert_raw_asset(raw, asset_id)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id + ":missing_effective")
		assert(bool(effective.get("placeable", false)), asset_id + ":effective_placeable")
		assert(str(effective.get("palette_path", "")) == PALETTE_PATH, asset_id + ":effective_palette")
		assert(str(effective.get("category", "")) == "visual_detail", asset_id + ":effective_category")
		assert(str(effective.get("object_class", "")) == "decoration", asset_id + ":effective_object_class")
		assert(str(effective.get("collision_policy", "")) == "none", asset_id + ":effective_collision")
		_assert_int_array(effective.get("collision_footprint_tiles", []), [0, 0], asset_id + ":effective_collision_footprint")

	var effective_pack_ids := {}
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		if str(asset.get("package_id", "")) != PACKAGE_ID:
			continue
		var asset_id := str(asset.get("asset_id", ""))
		assert(not effective_pack_ids.has(asset_id), asset_id + ":effective_duplicate")
		effective_pack_ids[asset_id] = true
	assert(effective_pack_ids.size() == 48, "effective_pack_count")
	for asset_id: String in raw_ids:
		assert(effective_pack_ids.has(asset_id), asset_id + ":effective_missing")

	var review := _read_json(REVIEW_PATH)
	var review_items: Dictionary = review.get("items", {})
	for asset_id: String in raw_ids:
		assert(not review_items.has(asset_id), asset_id + ":unexpected_review_state")

	print("MSE_SMALL_DECORATION_ASSET_PASS assets=48 effective=48 grid=2x4 collision=none review=0")
	get_tree().quit(0)
