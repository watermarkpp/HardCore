extends Node


const CATALOG_PATH := (
	"res://assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json"
)
const REVIEW_PATH := "res://assets/data/expansions/personal_expansion_001/map_asset_footprint_review_state.json"
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


func _assert_int_array(actual: Variant, expected: Array, label: String) -> void:
	assert(actual is Array and (actual as Array).size() == expected.size(), label)
	for index: int in expected.size():
		assert(int((actual as Array)[index]) == int(expected[index]), label)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, path)
	return parsed


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
	var review := _read_json(REVIEW_PATH)
	var review_items: Dictionary = review.get("items", {})

	for asset_id: String in RESTORED_GROUND_IDS:
		assert(not stored_overrides.has(asset_id), "deletion override remains: %s" % asset_id)
		var base_asset: Dictionary = catalog_assets.get(asset_id, {})
		assert(not base_asset.is_empty(), "missing catalog asset: %s" % asset_id)
		assert(str(base_asset.get("asset_id", "")).begins_with(GROUND_PREFIX))
		var review_item: Dictionary = review_items.get(asset_id, {})
		assert(review_item.size() == 8, "review contract fields: %s" % asset_id)
		assert(str(review_item.get("status", "")) == "verified", "review status: %s" % asset_id)
		assert(str(review_item.get("display_name", "")) == str(base_asset.get("display_name", "")), "review display: %s" % asset_id)
		assert(str(review_item.get("palette_path", "")) == str(base_asset.get("palette_path", "")), "review palette: %s" % asset_id)
		assert(str(review_item.get("image", "")) == str(base_asset.get("image", "")), "review image: %s" % asset_id)
		assert(str(review_item.get("source_sha256", "")) == str(base_asset.get("source_sha256", "")), "review source fingerprint: %s" % asset_id)
		assert(str(review_item.get("output_sha256", "")) == str(base_asset.get("output_sha256", "")), "review output fingerprint: %s" % asset_id)
		_assert_int_array(review_item.get("anchor_px", []), [32, 16], "review anchor: %s" % asset_id)
		_assert_int_array(review_item.get("footprint_tiles", []), [1, 1], "review footprint: %s" % asset_id)

		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "missing effective asset: %s" % asset_id)
		assert(str(effective.get("asset_type", "")) == "ground_brush", asset_id + ":asset_type")
		assert(str(effective.get("category", "")) == "ground", asset_id + ":category")
		assert(str(effective.get("object_class", "")) == "ground", asset_id + ":object_class")
		assert(str(effective.get("default_layer", "")) == "ground_base", asset_id + ":ground_layer")
		assert(str(effective.get("ground_brush_role", "")) == "base_tile", asset_id + ":ground_role")
		assert(bool(effective.get("paintable", false)), asset_id + ":paintable")
		assert(str(effective.get("anchor_mode", "")) == "tile_center", asset_id + ":anchor_mode")
		_assert_int_array(effective.get("canvas_size", []), [64, 32], asset_id + ":canvas_size")
		_assert_int_array(effective.get("image_size", []), [64, 32], asset_id + ":image_size")
		_assert_int_array(effective.get("anchor_px", []), [32, 16], asset_id + ":anchor")
		_assert_int_array(effective.get("placement_anchor_px", []), [32, 16], asset_id + ":placement_anchor")
		for field: String in ["footprint_tiles", "visual_footprint_tiles", "occupancy_footprint_tiles", "base_footprint_tiles"]:
			_assert_int_array(effective.get(field, []), [1, 1], asset_id + ":" + field)
		assert(bool(effective.get("placeable", false)), asset_id)
		assert(str(effective.get("calibration_status", "")) == "placeable", asset_id)
		assert(str(effective.get("palette_path", "")) == "地面/新增石板地面", asset_id)
		assert(str(effective.get("collision_policy", "")) == "none", asset_id + ":collision_policy")
		assert(str(effective.get("collision_profile_id", "")) == "none_visual", asset_id + ":collision_profile")
		assert(str(effective.get("navigation_policy", "")) == "ignore", asset_id + ":navigation")
		var image_path := "res://" + str(effective.get("image", ""))
		assert(FileAccess.file_exists(image_path), image_path)

	print(
		"MSE_WOOMA_GROUND_PALETTE_RESTORE_PASS "
		+ "restored=6 frozen_deleted=6 images=6"
	)
	get_tree().quit(0)
