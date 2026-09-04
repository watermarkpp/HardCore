extends Node


const CATALOG_PATH := "res://assets/data/assets/map_chain_roadblock_asset_catalog.json"
const REVIEW_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
const OVERRIDES_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_overrides.json"
const PACKAGE_ID := "mse_chain_roadblock_pack_20260822_v1"
const PALETTE_PATH := "装饰物1/路障"
const RETIRED_PALETTE_PATH := "装饰物1/路障/新增"
const ALPHA_THRESHOLD := 8

const EXPECTED := {
	"mse.roadblock.chain_fence.01": {
		"visible": [4, 4, 72, 455], "anchor": [40, 458], "footprint": [2, 8],
		"source_bounds": [178, 1, 72, 455],
	},
	"mse.roadblock.chain_fence.02": {
		"visible": [4, 4, 267, 433], "anchor": [137, 436], "footprint": [5, 7],
		"source_bounds": [518, 0, 267, 433],
	},
	"mse.roadblock.chain_fence.03": {
		"visible": [4, 4, 368, 266], "anchor": [188, 269], "footprint": [6, 5],
		"source_bounds": [924, 85, 368, 266],
	},
	"mse.roadblock.chain_fence.04": {
		"visible": [4, 4, 268, 413], "anchor": [138, 416], "footprint": [5, 7],
		"source_bounds": [1423, 18, 268, 413],
	},
	"mse.roadblock.chain_fence.05": {
		"visible": [4, 4, 73, 437], "anchor": [40, 440], "footprint": [2, 7],
		"source_bounds": [63, 39, 73, 437],
	},
	"mse.roadblock.chain_fence.06": {
		"visible": [4, 4, 327, 426], "anchor": [167, 429], "footprint": [6, 7],
		"source_bounds": [383, 32, 327, 426],
	},
	"mse.roadblock.chain_fence.07": {
		"visible": [4, 4, 387, 269], "anchor": [197, 272], "footprint": [7, 5],
		"source_bounds": [764, 114, 387, 269],
	},
	"mse.roadblock.chain_fence.08": {
		"visible": [4, 4, 307, 431], "anchor": [157, 434], "footprint": [5, 7],
		"source_bounds": [1210, 44, 307, 431],
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


func _assert_no_retired_references(value: Variant, label: String) -> void:
	if value is Dictionary:
		for key: Variant in (value as Dictionary).keys():
			_assert_no_retired_references(key, label)
			_assert_no_retired_references((value as Dictionary)[key], label)
	elif value is Array:
		for item: Variant in value as Array:
			_assert_no_retired_references(item, label)
	elif value is String:
		assert(not (value as String).contains(RETIRED_PALETTE_PATH), label + ":retired_palette_path")
		assert(not (value as String).contains("/barricades/新增/"), label + ":retired_image_path")


func _assert_pack_asset(asset_id: String, expected: Dictionary) -> void:
	var asset := MapAssetCatalogService.find_asset(asset_id)
	assert(not asset.is_empty(), asset_id + ":missing_effective_asset")
	assert(str(asset.get("display_name", "")) == "铁链路障 " + asset_id.get_slice(".", 3), asset_id)
	assert(str(asset.get("category", "")) == "obstacle", asset_id)
	assert(str(asset.get("object_class", "")) == "obstacle", asset_id)
	assert(str(asset.get("palette_path", "")) == PALETTE_PATH, asset_id)
	assert(bool(asset.get("placeable", false)), asset_id)
	assert(str(asset.get("calibration_status", "")) == "placeable", asset_id)
	assert(bool(asset.get("geometry_pending_manual", false)), asset_id)
	assert(str(asset.get("collision_policy", "")) == "none", asset_id)
	assert(str(asset.get("collision_profile_id", "")) == "none_visual", asset_id)
	_assert_int_array(asset.get("collision_footprint_tiles", []), [0, 0], asset_id + ":collision_footprint")
	assert(str(asset.get("navigation_policy", "")) == "ignore", asset_id)
	assert((asset.get("collision_cells", []) as Array).is_empty(), asset_id)
	assert((asset.get("placement_clearance_cells", []) as Array).is_empty(), asset_id)
	_assert_int_array(asset.get("visible_bounds_px", []), expected["visible"], asset_id + ":visible")
	_assert_int_array(asset.get("selection_bounds_px", []), expected["visible"], asset_id + ":selection")
	_assert_int_array(asset.get("anchor_px", []), expected["anchor"], asset_id + ":anchor")
	for field: String in [
		"footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles",
		"base_footprint_tiles",
	]:
		_assert_int_array(asset.get(field, []), expected["footprint"], asset_id + ":" + field)
	_assert_int_array(asset.get("source_bounds_px", []), expected["source_bounds"], asset_id + ":source_bounds")
	var image_path := "res://" + str(asset.get("image", ""))
	assert(FileAccess.file_exists(image_path), asset_id + ":missing_image")
	var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
	assert(image != null and not image.is_empty(), asset_id + ":invalid_image")
	assert(image.detect_alpha() != Image.ALPHA_NONE, asset_id + ":missing_alpha")
	var visible_rect := Rect2i(
		int(expected["visible"][0]), int(expected["visible"][1]),
		int(expected["visible"][2]), int(expected["visible"][3])
	)
	assert(_alpha_bbox(image) == visible_rect, asset_id + ":alpha_bbox")
	assert(_bounds_array(image.get_used_rect()) == expected["visible"], asset_id + ":used_rect")
	var processing: Dictionary = asset.get("processing", {})
	assert(str(processing.get("pipeline", "")) == "alpha_x_run_bbox_rgba_preserve_v1", asset_id + ":pipeline")
	assert(bool(processing.get("rgba_pixels_preserved", false)), asset_id + ":rgba_contract")


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var pack_catalog := _read_json(CATALOG_PATH)
	assert(str(pack_catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(pack_catalog.get("classification", "")) == PALETTE_PATH)
	assert(int(pack_catalog.get("asset_count", 0)) == 8)
	var pack_assets: Array = pack_catalog.get("assets", [])
	assert(pack_assets.size() == 8)
	var ids := {}
	for raw: Dictionary in pack_assets:
		var asset_id := str(raw.get("asset_id", ""))
		assert(EXPECTED.has(asset_id), asset_id)
		assert(not ids.has(asset_id), asset_id)
		ids[asset_id] = true
		_assert_pack_asset(asset_id, EXPECTED[asset_id])
	assert(ids.size() == EXPECTED.size())

	var root_roadblocks := 0
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var palette_path := str(asset.get("palette_path", ""))
		assert(palette_path != RETIRED_PALETTE_PATH, str(asset.get("asset_id", "")))
	var main_catalog := _read_json("res://assets/data/assets/map_asset_catalog.json")
	_assert_no_retired_references(main_catalog, "main_catalog")
	for asset: Dictionary in main_catalog.get("assets", []):
		if str(asset.get("palette_path", "")) == PALETTE_PATH:
			root_roadblocks += 1
	assert(root_roadblocks == 8)

	var review := _read_json(REVIEW_PATH)
	var overrides := _read_json(OVERRIDES_PATH)
	_assert_no_retired_references(review, "review_state")
	_assert_no_retired_references(overrides, "overrides")
	for retired_id: String in [
		"user.cdb4723a9c62ec77", "user.106a7ef48783c39c", "user.69da6325a585a3e0",
		"user.db9da430f78824ce", "user.d13b5d379a608d11", "user.1440243e9c564a2c",
		"user.3b48b3e78b5788ca", "user.ca658345cec84700", "user.1d7b8837430a143d",
		"user.39806a640e9d78ac", "user.e84e9a0084dd7443", "user.1f6f6db0df32911f",
		"user.3819e1bac3f136bc", "user.4013bce08dc0b07e", "user.37e2f534312b82a9",
		"user.5ff97372f9668ca",
	]:
		assert(not (review.get("items", {}) as Dictionary).has(retired_id), retired_id + ":review")
		assert(not (overrides.get("overrides", {}) as Dictionary).has(retired_id), retired_id + ":override")

	print("MSE_CHAIN_ROADBLOCK_ASSET_PASS assets=8 root_roadblocks=8 retired_new=0 collision=none")
	get_tree().quit(0)
