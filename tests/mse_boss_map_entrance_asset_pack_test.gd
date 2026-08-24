extends Node


const CATALOG_PATH := "res://assets/data/assets/map_boss_entrance_asset_catalog.json"
const EXIT_CATALOG_PATH := "res://assets/data/assets/map_exit_asset_catalog.json"
const PACKAGE_ID := "user_boss_map_entrance_pack_20260823_v1"
const PALETTE_PATH := "装饰物1/地图出入口"
const NORMALIZATION := "alpha_trim_resize_448x320_pad4_v1"
const OLD_EXIT_CATALOG_SHA256 := "2bfd9417be925ee1b7a93101101768c8f6438a6d90c7ddb1fc80f8e9b9d2c1ad"
const ALPHA_THRESHOLD := 16


const EXPECTED := {
	"user.boss_entrance.20260823.confusion_hall": {
		"name": "困惑殿堂入口",
		"file": "boss_entrance_confusion_hall.png",
		"source_sha256": "a7b72dd3107f7b96899b836c0f11f83b585d7f1d88f070905c69abc676620c45",
		"output_sha256": "53f2b1bdf44b7f66f265fefa7dec654aacffa4205d0bfc0e2ada42f1aaa203ba",
		"image_size": [456, 235],
		"visible": [6, 6, 445, 222],
		"anchor": [228, 227],
		"footprint": [7, 7],
	},
	"user.boss_entrance.20260823.hellfire": {
		"name": "地狱烈焰入口",
		"file": "boss_entrance_hellfire.png",
		"source_sha256": "b8b82c8a1abafdc29053a9dc541b7e7b75b56f547bf7ab3d86016a424b540c13",
		"output_sha256": "6d045ea4a63c724c9064696899a44d84aa1340913da981d1b545e326b135cdce",
		"image_size": [456, 299],
		"visible": [10, 23, 441, 240],
		"anchor": [230, 262],
		"footprint": [7, 8],
	},
	"user.boss_entrance.20260823.fallen_graveyard": {
		"name": "堕落坟场入口",
		"file": "boss_entrance_fallen_graveyard.png",
		"source_sha256": "a62706b5cb7cb39db5f66ab7562cb49d09c1acd3590d4b142d34e40d44e9ff54",
		"output_sha256": "35afc019520206f6877561741b13326c4702107f6682ff611ce7910ee5f42e9a",
		"image_size": [456, 260],
		"visible": [5, 6, 445, 247],
		"anchor": [227, 252],
		"footprint": [7, 8],
	},
	"user.boss_entrance.20260823.death_temple": {
		"name": "死亡神殿入口",
		"file": "boss_entrance_death_temple.png",
		"source_sha256": "f744171a0a3e6ef233dab67ddf512c6acd85db7cdc136d4a30fc8b26c4aba7d7",
		"output_sha256": "a06ff115cd69ec8f043dbdb556054680f99aec62a21a9c59da3df828f75404d9",
		"image_size": [456, 233],
		"visible": [5, 7, 443, 214],
		"anchor": [226, 220],
		"footprint": [7, 7],
	},
	"user.boss_entrance.20260823.abyss_domain": {
		"name": "深渊魔域入口",
		"file": "boss_entrance_abyss_domain.png",
		"source_sha256": "eb374e13dbe15ecd458ba635b9b9b0ff0132afb80f870359db14d7d5e09e78bc",
		"output_sha256": "3c97dda1e30f3342f486986fe8cb07251bdaa16dc8ee987d45e872a2acfc5399",
		"image_size": [456, 230],
		"visible": [7, 24, 444, 188],
		"anchor": [229, 211],
		"footprint": [7, 6],
	},
	"user.boss_entrance.20260823.pincer_nest": {
		"name": "钳虫巢穴入口",
		"file": "boss_entrance_pincer_nest.png",
		"source_sha256": "93503b8a4d897b3ced4660cb6a42c4dc6ecaf0f09c1dd964453e6d58f42ca11d",
		"output_sha256": "3bf89e7c9c5bebbdca9eccbc22772d7af02b775e145a616787646b4af14e2517",
		"image_size": [456, 235],
		"visible": [4, 6, 448, 221],
		"anchor": [228, 226],
		"footprint": [7, 7],
	},
}


func _read_json(path: String) -> Dictionary:
	assert(FileAccess.file_exists(path), path)
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array and (actual as Array).size() == expected.size(), label)
	for index: int in expected.size():
		assert(int((actual as Array)[index]) == int(expected[index]), label)


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


func _assert_alpha_contract(image: Image, asset_id: String) -> void:
	var min_alpha := 1.0
	var max_alpha := 0.0
	for y: int in image.get_height():
		for x: int in image.get_width():
			var alpha := image.get_pixel(x, y).a
			min_alpha = minf(min_alpha, alpha)
			max_alpha = maxf(max_alpha, alpha)
	assert(is_zero_approx(min_alpha), asset_id + ":alpha_min")
	assert(max_alpha > 0.0, asset_id + ":alpha_max")
	for point: Vector2i in [
		Vector2i(0, 0),
		Vector2i(image.get_width() - 1, 0),
		Vector2i(0, image.get_height() - 1),
		Vector2i(image.get_width() - 1, image.get_height() - 1),
	]:
		assert(is_zero_approx(image.get_pixelv(point).a), asset_id + ":transparent_corner")
	for x: int in image.get_width():
		for y: int in range(4):
			assert(is_zero_approx(image.get_pixel(x, y).a), asset_id + ":top_padding")
			assert(
				is_zero_approx(image.get_pixel(x, image.get_height() - 1 - y).a),
				asset_id + ":bottom_padding"
			)
	for y: int in image.get_height():
		for x: int in range(4):
			assert(is_zero_approx(image.get_pixel(x, y).a), asset_id + ":left_padding")
			assert(
				is_zero_approx(image.get_pixel(image.get_width() - 1 - x, y).a),
				asset_id + ":right_padding"
			)


func _assert_pack_asset(asset_id: String, raw: Dictionary, expected: Dictionary) -> void:
	assert(str(raw.get("asset_id", "")) == asset_id, asset_id)
	assert(str(raw.get("display_name", "")) == str(expected["name"]), asset_id + ":name")
	assert(str(raw.get("asset_type", "")) == "large_prop", asset_id + ":type")
	assert(str(raw.get("category", "")) == "map_entrance", asset_id + ":category")
	assert(str(raw.get("object_class", "")) == "map_entrance", asset_id + ":object_class")
	assert(str(raw.get("theme", "")) == "user_palette", asset_id + ":theme")
	assert(str(raw.get("palette_path", "")) == PALETTE_PATH, asset_id + ":palette")
	assert(str(raw.get("semantic_role", "")) == "map_portal", asset_id + ":semantic_role")
	assert(bool(raw.get("trigger_on_enter", false)), asset_id + ":trigger")
	assert(str(raw.get("default_layer", "")) == "object_base", asset_id + ":layer")
	assert(str(raw.get("default_object_role", "")) == "terrain", asset_id + ":role")
	assert(str(raw.get("content_layer", "")) == "personal_expansion", asset_id + ":content_layer")
	assert(bool(raw.get("placeable", false)), asset_id + ":placeable")
	assert(str(raw.get("calibration_status", "")) == "placeable", asset_id + ":calibration")
	assert(str(raw.get("normalization", "")) == NORMALIZATION, asset_id + ":normalization")
	assert(str(raw.get("processing", {}).get("pipeline", "")) == NORMALIZATION, asset_id + ":pipeline")
	assert(str(raw.get("source_sha256", "")) == str(expected["source_sha256"]), asset_id + ":source_sha")
	assert(str(raw.get("output_sha256", "")) == str(expected["output_sha256"]), asset_id + ":output_sha")
	assert(str(raw.get("source_sha256", "")).length() == 64, asset_id + ":source_sha_length")
	assert(str(raw.get("output_sha256", "")).length() == 64, asset_id + ":output_sha_length")
	for field: String in [
		"anchor_px", "placement_anchor_px", "door_anchor_px",
	]:
		_assert_int_array(raw.get(field, []), expected["anchor"], asset_id + ":" + field)
	for field: String in [
		"footprint_tiles", "visual_footprint_tiles",
		"occupancy_footprint_tiles", "base_footprint_tiles",
	]:
		_assert_int_array(raw.get(field, []), expected["footprint"], asset_id + ":" + field)
	_assert_int_array(raw.get("image_size", []), expected["image_size"], asset_id + ":image_size")
	_assert_int_array(raw.get("canvas_size", []), expected["image_size"], asset_id + ":canvas_size")
	_assert_int_array(raw.get("visible_bounds_px", []), expected["visible"], asset_id + ":visible_bounds")
	_assert_int_array(raw.get("selection_bounds_px", []), expected["visible"], asset_id + ":selection_bounds")
	_assert_int_array(raw.get("collision_footprint_tiles", []), [0, 0], asset_id + ":collision_footprint")
	assert((raw.get("collision_cells", []) as Array).is_empty(), asset_id + ":collision_cells")
	assert((raw.get("placement_clearance_cells", []) as Array).is_empty(), asset_id + ":placement_clearance_cells")
	assert(str(raw.get("collision_policy", "")) == "none", asset_id + ":collision_policy")
	assert(str(raw.get("collision_profile_id", "")) == "none_visual", asset_id + ":collision_profile")
	assert(str(raw.get("navigation_policy", "")) == "ignore", asset_id + ":navigation")
	assert(not bool(raw.get("manual_collision_expected", true)), asset_id + ":manual_collision")
	assert(str(raw.get("map_collision_override", "")) == "default", asset_id + ":map_collision_override")
	assert(str(raw.get("collision_authority", "")) == "manual_by_user", asset_id + ":collision_authority")
	assert(not bool(raw.get("occlusion", true)), asset_id + ":occlusion")
	assert(bool(raw.get("allows_edge_clipping", false)), asset_id + ":edge_clipping")
	assert(not bool(raw.get("requires_runtime_rotation", true)), asset_id + ":rotation")
	assert(not bool(raw.get("allow_flip", true)), asset_id + ":flip")

	var image_path := "res://" + str(raw.get("image", ""))
	assert(str(raw.get("thumbnail", "")) == str(raw.get("image", "")), asset_id + ":thumbnail")
	assert(FileAccess.file_exists(image_path), asset_id + ":missing_image")
	var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
	assert(image != null and not image.is_empty(), asset_id + ":invalid_image")
	assert(image.detect_alpha() != Image.ALPHA_NONE, asset_id + ":missing_alpha")
	assert(FileAccess.get_sha256(image_path) == str(expected["output_sha256"]), asset_id + ":file_sha")
	_assert_alpha_contract(image, asset_id)
	var expected_visible: Array = expected["visible"]
	var visible_rect := Rect2i(
		int(expected_visible[0]), int(expected_visible[1]),
		int(expected_visible[2]), int(expected_visible[3])
	)
	assert(_alpha_bbox(image) == visible_rect, asset_id + ":alpha_bbox")
	assert(
		int(ceil(float(expected_visible[2]) / 64.0)) == int(expected["footprint"][0])
		and int(ceil(float(expected_visible[3]) / 32.0)) == int(expected["footprint"][1]),
		asset_id + ":footprint_formula"
	)


func _ready() -> void:
	var catalog := _read_json(CATALOG_PATH)
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(str(catalog.get("palette_path", "")) == PALETTE_PATH)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	assert(str(catalog.get("normalization", "")) == NORMALIZATION)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == EXPECTED.size())
	assert(int(catalog.get("asset_count", 0)) == EXPECTED.size())
	var ids := {}
	for raw: Dictionary in assets:
		var asset_id := str(raw.get("asset_id", ""))
		assert(EXPECTED.has(asset_id), asset_id + ":unexpected_id")
		assert(not ids.has(asset_id), asset_id + ":duplicate_id")
		ids[asset_id] = true
		_assert_pack_asset(asset_id, raw, EXPECTED[asset_id])
	assert(ids.size() == EXPECTED.size())

	assert(
		FileAccess.get_sha256(EXIT_CATALOG_PATH) == OLD_EXIT_CATALOG_SHA256,
		"legacy map exit catalog changed"
	)
	MapAssetCatalogService.invalidate_cache()
	for asset_id: String in EXPECTED.keys():
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id + ":service_find_asset")
		assert(str(effective.get("asset_id", "")) == asset_id, asset_id + ":service_id")
		_assert_int_array(effective.get("anchor_px", []), EXPECTED[asset_id]["anchor"], asset_id + ":effective_anchor")
		assert(bool(effective.get("placeable", false)), asset_id + ":effective_placeable")
		assert(str(effective.get("collision_policy", "")) == "none", asset_id + ":effective_collision")
		assert(str(effective.get("semantic_role", "")) == "map_portal", asset_id + ":effective_semantic")
		assert(bool(effective.get("trigger_on_enter", false)), asset_id + ":effective_trigger")
		assert(str(effective.get("placement_anchor_policy_id", "")) == "footprint_bottom_vertex_v1", asset_id + ":placement_policy")
	var catalog_errors := MapAssetCatalogService.validate_catalog()
	assert(catalog_errors.is_empty(), "catalog_errors=" + str(catalog_errors))

	var document := MapEditorTypes.new_map(
		"boss_map_entrance_asset_pack_test",
		990124,
		"Boss Map Entrance Asset Pack Test",
		Vector2i(64, 64)
	)
	var placed := MapEditorInstanceService.create_instance(
		document,
		"user.boss_entrance.20260823.confusion_hall",
		"terrain",
		Vector2i(20, 20)
	)
	assert(bool(placed.get("ok", false)), str(placed.get("errors", [])))
	var instance: Dictionary = placed.get("instance", {})
	assert(str(instance.get("collision_policy", "")) == "none")
	_assert_int_array(instance.get("collision_footprint_tiles", []), [0, 0], "instance:collision_footprint")
	assert((instance.get("collision_cells", []) as Array).is_empty(), "instance:collision_cells")

	print(
		"USER_BOSS_MAP_ENTRANCE_ASSET_PACK_PASS "
		+ "assets=6 alpha=6 category=map_entrance portal=6 collision=none"
	)
	get_tree().quit(0)
