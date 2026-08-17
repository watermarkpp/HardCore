extends Node

const MapAssetCatalogService := preload("res://scripts/map_assets/map_asset_catalog_service.gd")
const CATALOG_PATH := "res://assets/data/assets/map_stone_tomb_floor_asset_catalog.json"
const PALETTE_PATH := "洞穴与地下城/地板/石墓石板"


func _ready() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(CATALOG_PATH))
	assert(parsed is Dictionary)
	var catalog: Dictionary = parsed
	assert(str(catalog.get("package_id", "")) == "mse_stone_tomb_floor_6_v1")
	assert(int(catalog.get("asset_count", 0)) == 6)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 6)
	MapAssetCatalogService.invalidate_cache()
	for index in range(6):
		var asset: Dictionary = assets[index]
		var expected_id := "mse.ground.stone_tomb_floor.%02d" % (index + 1)
		assert(str(asset.get("asset_id", "")) == expected_id)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		assert(str(asset.get("asset_type", "")) == "ground_brush")
		assert(asset.get("footprint_tiles", []) == [1.0, 1.0])
		assert(asset.get("collision_footprint_tiles", []) == [0.0, 0.0])
		assert(str(asset.get("variation_group_id", "")) == "mse.ground.stone_tomb_floor.v1")
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path))
		assert(FileAccess.get_sha256(image_path) == str(asset.get("output_sha256", "")))
		var image := Image.new()
		assert(image.load(ProjectSettings.globalize_path(image_path)) == OK)
		assert(image.get_size() == Vector2i(64, 32))
		assert(image.get_pixel(0, 0).a == 0.0)
		assert(image.get_pixel(63, 0).a == 0.0)
		assert(image.get_pixel(32, 16).a > 0.85)
		var effective := MapAssetCatalogService.find_asset(expected_id)
		assert(not effective.is_empty())
		assert(effective.get("footprint_tiles", []) == [1, 1])
		assert(str(effective.get("palette_path", "")) == PALETTE_PATH)
	print("MSE_STONE_TOMB_FLOOR_ASSET_PASS assets=6 footprint=1x1 palette=%s" % PALETTE_PATH)
	get_tree().quit()
