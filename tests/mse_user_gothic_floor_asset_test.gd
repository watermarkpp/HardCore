extends Node


const CATALOG_PATH := "res://assets/data/assets/map_user_gothic_floor_asset_catalog.json"
const PALETTE_PATH := "地面/灰绿石砖（用户素材）"
const EXPECTED_HASHES := {
	"mse.ground.user_gothic_floor.01": "d366d62cb452ebca899b1cf756b623160cc7305ab4c086875e2f04a980e8e8d5",
	"mse.ground.user_gothic_floor.02": "72de4bc2449d32437cdf0e6d1e9048aca3771bda1bae9c9d40ae8a10cbc7298c",
	"mse.ground.user_gothic_floor.03": "475f4133aee8788685103cbab21c9074df444a4716bf7b600db23a499d64df3b",
	"mse.ground.user_gothic_floor.04": "92aefcd4376b101a3e0c06916f61a2e4b9b24960d51fd402352212c72dd4a1cf",
	"mse.ground.user_gothic_floor.05": "5d664d87ac94721423e9820b86a06771bd08662e1bc743edfb05681eafb070f5",
	"mse.ground.user_gothic_floor.06": "68620ac8876f90fbd3eae031fad3caecbd60cdf22dee6dac733a3428c7f3859b",
}


func _ready() -> void:
	var file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(file != null)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	var catalog := parsed as Dictionary
	assert(str(catalog.get("package_id", "")) == "mse_user_gothic_floor_6_v1")
	assert(int(catalog.get("asset_count", 0)) == 6)
	assert(str(catalog.get("classification", "")) == PALETTE_PATH)
	var assets: Array = catalog.get("assets", [])
	assert(assets.size() == 6)
	assert(MapAssetCatalogService.validate_catalog().is_empty())
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(EXPECTED_HASHES.has(asset_id), asset_id)
		assert(str(asset.get("palette_path", "")) == PALETTE_PATH)
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)
		assert(FileAccess.get_sha256(image_path) == str(EXPECTED_HASHES[asset_id]), image_path)
		var image := Image.load_from_file(ProjectSettings.globalize_path(image_path))
		assert(image != null and image.get_size() == Vector2i(64, 32), image_path)
		assert(image.detect_alpha() != Image.ALPHA_NONE, image_path)
		assert(not MapAssetCatalogService.find_asset(asset_id).is_empty(), asset_id)
		var normalized := MapEditorGroundService.normalized_ground_image(asset_id)
		assert(normalized != null and normalized.get_size() == Vector2i(64, 32), asset_id)
	print("MSE_USER_GOTHIC_FLOOR_ASSET_PASS assets=6 palette=%s" % PALETTE_PATH)
	get_tree().quit(0)
