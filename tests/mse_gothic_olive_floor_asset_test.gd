extends Node


const CATALOG_PATH := "res://assets/data/assets/map_gothic_olive_floor_asset_catalog.json"
const PACKAGE_ID := "mse_gothic_olive_floor_5_v1"
const PALETTE_PATH := "地面/灰绿石砖（四向无缝）"
const REMOVED_ASSET_ID := "mse.ground.gothic_olive.seamless.04"
const REMOVED_IMAGE_PATH := (
	"res://assets/art/maps/_shared/user_palette/ground/gothic_olive_seamless/"
	+ "gothic_olive_floor_04.png"
)
const EXPECTED_OUTPUT_HASHES := {
	"mse.ground.gothic_olive.seamless.01": "8997436140c55be3a1ac714df1543b9aa9501967223cc816d634872aa4a3a89d",
	"mse.ground.gothic_olive.seamless.02": "17bf7011d1dffea11e052460fa6e392f809811b31ce85c8cfa7ab20497540b22",
	"mse.ground.gothic_olive.seamless.03": "1cecf4811bff4fcef5193a3ec0ec3d8e4261dd5174e1fe91767d1702ff35ff9d",
	"mse.ground.gothic_olive.seamless.05": "810fbaec89bb63fd508c0628677c9365cc5eb6cd5fbc7b84fa57dd56e0940f3b",
	"mse.ground.gothic_olive.seamless.06": "3a068662ecb961378ca342780175ff7b98190669c8606ceb4d58a7f162345dbf",
}
const WALL_TARGET_RGB := Vector3(91.7, 95.7, 73.7)


func _ready() -> void:
	assert(FileAccess.file_exists(CATALOG_PATH))
	assert(not FileAccess.file_exists(REMOVED_IMAGE_PATH))
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	var catalog := parsed as Dictionary
	assert(str(catalog.get("package_id", "")) == PACKAGE_ID)
	assert(int(catalog.get("source_count", 0)) == 5)
	assert(int(catalog.get("asset_count", 0)) == 5)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	assert(str(catalog.get("edge_contract", "")) == "mutually_compatible_nw_ne_se_sw_v1")

	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 5)
	for asset: Dictionary in assets:
		assert(str(asset.get("asset_id", "")) != REMOVED_ASSET_ID)
	assert(MapAssetCatalogService.find_asset(REMOVED_ASSET_ID).is_empty())
	var catalog_errors := MapAssetCatalogService.validate_catalog()
	assert(catalog_errors.is_empty(), str(catalog_errors))

	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(EXPECTED_OUTPUT_HASHES.has(asset_id), asset_id)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		assert(str(asset.get("asset_type", "")) == "ground_brush")
		assert(str(asset.get("terrain_type", "")) == "gothic_olive_stone_cell")
		_assert_int_pair(asset.get("footprint_tiles", []), Vector2i(1, 1), asset_id)
		_assert_int_pair(asset.get("tile_size", []), Vector2i(64, 32), asset_id)
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("calibration_status", "")) == "placeable")
		assert(str(asset.get("output_sha256", "")) == str(EXPECTED_OUTPUT_HASHES[asset_id]))
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		assert(FileAccess.get_sha256(image_path) == str(EXPECTED_OUTPUT_HASHES[asset_id]), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and not image.is_empty(), image_path)
		assert(image.get_size() == Vector2i(64, 32), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		_assert_wall_color_match(image, image_path)
		_assert_inner_diamond_coverage(image, image_path)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), asset_id)
		_assert_int_pair(effective.get("canvas_size", []), Vector2i(64, 32), asset_id)
		_assert_int_pair(effective.get("anchor_px", []), Vector2i(32, 16), asset_id)
		assert(preview._texture_for_asset(asset_id) != null, asset_id)
		var normalized := MapEditorGroundService.normalized_ground_image(asset_id)
		assert(normalized != null and normalized.get_size() == Vector2i(64, 32), asset_id)

	print("MSE_GOTHIC_OLIVE_FLOOR_ASSET_PASS assets=5 removed=04 tile=64x32 palette=%s" % PALETTE_PATH)
	get_tree().quit(0)


func _assert_int_pair(value: Variant, expected: Vector2i, context: String) -> void:
	assert(value is Array and value.size() == 2, context)
	assert(Vector2i(int(value[0]), int(value[1])) == expected, context)


func _assert_wall_color_match(image: Image, image_path: String) -> void:
	var total := Vector3.ZERO
	var count := 0
	for y in image.get_height():
		for x in image.get_width():
			var pixel := image.get_pixel(x, y)
			if pixel.a < 0.5:
				continue
			total += Vector3(pixel.r, pixel.g, pixel.b) * 255.0
			count += 1
	assert(count > 800, image_path)
	var mean := total / float(count)
	assert(absf(mean.x - WALL_TARGET_RGB.x) <= 4.0, "%s red=%f" % [image_path, mean.x])
	assert(absf(mean.y - WALL_TARGET_RGB.y) <= 4.0, "%s green=%f" % [image_path, mean.y])
	assert(absf(mean.z - WALL_TARGET_RGB.z) <= 4.0, "%s blue=%f" % [image_path, mean.z])


func _assert_inner_diamond_coverage(image: Image, image_path: String) -> void:
	var covered := 0
	var expected := 0
	for y in image.get_height():
		for x in image.get_width():
			var distance := (
				absf((float(x) + 0.5 - 32.0) / 32.0)
				+ absf((float(y) + 0.5 - 16.0) / 16.0)
			)
			if distance > 0.90:
				continue
			expected += 1
			if image.get_pixel(x, y).a >= 0.98:
				covered += 1
	assert(expected > 0)
	assert(float(covered) / float(expected) >= 0.995, image_path)
