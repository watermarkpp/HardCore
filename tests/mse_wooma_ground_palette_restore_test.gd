extends Node


const CATALOG_PATH := (
	"res://assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json"
)
const GROUND_PREFIX := "mse.new_ground.stone_platform."
const RESTORED_GROUND_IDS := [
	"mse.new_ground.stone_platform.07",
	"mse.new_ground.stone_platform.08",
	"mse.new_ground.stone_platform.09",
	"mse.new_ground.stone_platform.10",
	"mse.new_ground.stone_platform.11",
	"mse.new_ground.stone_platform.12",
]
const FROZEN_DELETED_GROUND_IDS := [
	"mse.new_ground.stone_platform.01",
	"mse.new_ground.stone_platform.02",
	"mse.new_ground.stone_platform.03",
	"mse.new_ground.stone_platform.04",
	"mse.new_ground.stone_platform.05",
	"mse.new_ground.stone_platform.06",
]
const FROZEN_DELETED_GROUND_OVERRIDE := {
	"content_layer": "personal_expansion",
	"placeable": false,
}


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var overrides := MapAssetCalibrationService.load_overrides()
	var stored_overrides: Dictionary = overrides.get("overrides", {})

	for asset_id: String in FROZEN_DELETED_GROUND_IDS:
		assert(
			stored_overrides.get(asset_id, {}) == FROZEN_DELETED_GROUND_OVERRIDE,
			"frozen override changed: %s" % asset_id
		)

	var catalog_file := FileAccess.open(CATALOG_PATH, FileAccess.READ)
	assert(catalog_file != null)
	var catalog: Variant = JSON.parse_string(catalog_file.get_as_text())
	assert(catalog is Dictionary)
	var catalog_assets: Dictionary = {}
	for asset: Dictionary in catalog.get("assets", []):
		catalog_assets[str(asset.get("asset_id", ""))] = asset

	for asset_id: String in RESTORED_GROUND_IDS:
		assert(not stored_overrides.has(asset_id), "deletion override remains: %s" % asset_id)
		var base_asset: Dictionary = catalog_assets.get(asset_id, {})
		assert(not base_asset.is_empty(), "missing catalog asset: %s" % asset_id)
		assert(str(base_asset.get("asset_id", "")).begins_with(GROUND_PREFIX))

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "missing effective asset: %s" % asset_id)
		assert(bool(effective.get("placeable", false)), asset_id)
		assert(str(effective.get("calibration_status", "")) == "placeable", asset_id)
		assert(str(effective.get("palette_path", "")) == "地面/新增石板地面", asset_id)
		var image_path := "res://" + str(effective.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)

	print(
		"MSE_WOOMA_GROUND_PALETTE_RESTORE_PASS "
		+ "restored=6 frozen_deleted=6 images=6"
	)
	get_tree().quit(0)
