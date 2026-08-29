extends Node


const V15_CATALOG_PATH := "res://assets/data/assets/map_v15_batch_asset_catalog.json"
const ReviewTool := preload("res://tools/map_assets/manual_footprint_review.gd")


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var assets := MapAssetCatalogService.all_assets()
	var by_id := {}
	for asset: Dictionary in assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(not by_id.has(asset_id), "duplicate asset_id: %s" % asset_id)
		by_id[asset_id] = asset

	var v15_catalog := _read_json(V15_CATALOG_PATH)
	var v15_assets: Array = v15_catalog.get("assets", [])
	assert(v15_assets.size() == 174)
	for raw: Dictionary in v15_assets:
		var asset_id := str(raw.get("asset_id", ""))
		assert(not by_id.has(asset_id), "legacy V1.5 asset leaked into all_assets: %s" % asset_id)
		var effective := MapAssetCatalogService.find_asset(asset_id)
		assert(not effective.is_empty(), "legacy V1.5 asset is no longer resolvable: %s" % asset_id)
		assert(
			bool(effective.get("resolved_from_tracked_staging", false)),
			"%s did not resolve to its tracked staging image" % asset_id
		)
		assert(
			FileAccess.file_exists("res://" + str(effective.get("image", ""))),
			"%s resolved image is missing" % asset_id
		)

	assert(ReviewTool.DEFAULT_FILTER == 1)

	print(
		"MSE_MATERIAL_FOOTPRINT_CATALOG_VISIBILITY_PASS "
		+ "formal_catalog=%d legacy_v15_hidden=%d default_filter=all"
		% [assets.size(), v15_assets.size()]
	)
	get_tree().quit(0)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	assert(file != null, "missing JSON: %s" % path)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "invalid JSON: %s" % path)
	return parsed
