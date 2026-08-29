extends Node


const CATALOG_PATH := "res://assets/data/assets/map_small_decoration_asset_catalog.json"
const PACKAGE_ID := "mse_small_decoration_pack_20260822_v1"
const PALETTE_PATH := "装饰物1/小装饰物"
const ALPHA_THRESHOLD := 8
const PADDING_PX := 8
const TILE_SIZE := [64, 32]
const REPAIR_PIPELINE := "alpha_component_seed_ownership_repair_v1"
const REPAIR_EXPECTED := {
	"mse.small_decor.005": {
		"source_bounds": [27, 612, 363, 379],
		"source_alpha_bbox": [27, 69, 363, 379],
		"visible": [8, 8, 363, 379],
		"canvas": [379, 395],
		"anchor": [189, 386],
		"footprint": [6, 6],
		"seed": [181, 814],
		"output_sha256": "25bce32b7a83cae94fd8a74edf3eb339a2f1eef36ecf605e836e55aa3d234d13",
	},
	"mse.small_decor.006": {
		"source_bounds": [417, 725, 305, 241],
		"source_alpha_bbox": [55, 182, 305, 241],
		"visible": [8, 8, 305, 241],
		"canvas": [321, 257],
		"anchor": [160, 248],
		"footprint": [5, 4],
		"seed": [543, 814],
		"output_sha256": "34292cf0150bb4d1e72fea4d29fc5373872fe4c2aa2179f7c8f13f8e86deb9b6",
	},
	"mse.small_decor.007": {
		"source_bounds": [831, 646, 154, 330],
		"source_alpha_bbox": [107, 103, 154, 330],
		"visible": [8, 8, 154, 330],
		"canvas": [170, 346],
		"anchor": [85, 337],
		"footprint": [3, 6],
		"seed": [905, 814],
		"output_sha256": "0ca5dc6d9612cc1c08fa72a9b77917323e57bdc8d240778738205fb968ef2e45",
	},
	"mse.small_decor.009": {
		"source_bounds": [65, 53, 233, 428],
		"source_alpha_bbox": [65, 53, 233, 428],
		"visible": [8, 8, 233, 428],
		"canvas": [249, 444],
		"anchor": [124, 435],
		"footprint": [4, 7],
		"seed": [181, 271],
		"output_sha256": "0339add67eaf2b6cb941f335271dd22ba225e07fe5985ae791d2417551400f4a",
	},
	"mse.small_decor.010": {
		"source_bounds": [452, 23, 156, 449],
		"source_alpha_bbox": [90, 23, 156, 449],
		"visible": [8, 8, 156, 449],
		"canvas": [172, 465],
		"anchor": [86, 456],
		"footprint": [3, 8],
		"seed": [543, 271],
		"output_sha256": "3ed7be7a110779cc87ba65895ae8a73b4b4f554a54eabd4f0a19a2f74a5e443b",
	},
	"mse.small_decor.019": {
		"source_bounds": [754, 189, 277, 284],
		"source_alpha_bbox": [30, 189, 277, 284],
		"visible": [8, 8, 277, 284],
		"canvas": [293, 300],
		"anchor": [146, 291],
		"footprint": [5, 5],
		"seed": [905, 271],
		"output_sha256": "1bc9b10547399e56c5d7ba712c24c9dc3cb82b33a46243839221d290aaa0c6f8",
	},
}


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
	var repair: Dictionary = REPAIR_EXPECTED.get(asset_id, {})
	if not repair.is_empty():
		_assert_int_array(raw.get("source_bounds_px", []), repair["source_bounds"], asset_id + ":source_bounds")
		_assert_int_array(raw.get("source_alpha_bbox_px", []), repair["source_alpha_bbox"], asset_id + ":source_alpha_bbox")
		_assert_int_array(raw.get("visible_bounds_px", []), repair["visible"], asset_id + ":visible_bounds")
		_assert_int_array(raw.get("canvas_size", []), repair["canvas"], asset_id + ":canvas")
		_assert_int_array(raw.get("anchor_px", []), repair["anchor"], asset_id + ":anchor")
		assert(str(raw.get("output_sha256", "")) == str(repair["output_sha256"]), asset_id + ":output_sha")
	var expected_footprint: Array = [
		(int(visible[2]) + 63) / 64,
		(int(visible[3]) + 63) / 64,
	]
	if not repair.is_empty():
		expected_footprint = repair["footprint"]
	for field: String in ["footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "base_footprint_tiles"]:
		_assert_int_array(raw.get(field, []), expected_footprint, asset_id + ":" + field)
	var processing: Dictionary = raw.get("processing", {})
	var expected_pipeline := REPAIR_PIPELINE if not repair.is_empty() else "alpha_grid_tight_bbox_rgba_preserve_v1"
	assert(str(processing.get("pipeline", "")) == expected_pipeline, asset_id + ":pipeline")
	assert(int(processing.get("alpha_threshold", 0)) == ALPHA_THRESHOLD, asset_id + ":threshold")
	assert(int(processing.get("padding_px", 0)) == PADDING_PX, asset_id + ":padding")
	assert(bool(processing.get("rgba_pixels_preserved", false)), asset_id + ":rgba_contract")
	if not repair.is_empty():
		var ownership: Dictionary = processing.get("ownership", {})
		_assert_int_array(ownership.get("seed_px", []), repair["seed"], asset_id + ":ownership_seed")
		assert(str(ownership.get("method", "")) == "alpha_component_seed_ownership_v1", asset_id + ":ownership_method")
		assert(bool(ownership.get("whole_component_to_seed", false)), asset_id + ":ownership_whole_component")
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

	print("MSE_SMALL_DECORATION_ASSET_PASS assets=48 effective=48 grid=2x4 collision=none review=external_authority")
	get_tree().quit(0)
