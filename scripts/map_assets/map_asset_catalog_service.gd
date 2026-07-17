class_name MapAssetCatalogService
extends RefCounted

const CATALOG_PATH := "res://assets/data/assets/map_asset_catalog.json"
const EXTENSION_CATALOG_PATHS := [
	"res://assets/data/assets/map_object_asset_catalog.json",
	"res://assets/data/assets/map_terrain_asset_catalog.json",
	"res://assets/data/assets/map_cave_dungeon_asset_catalog.json",
]
static var _catalog_cache: Dictionary = {}


static func load_catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache.duplicate(true)
	var catalog := _read_catalog(CATALOG_PATH)
	if catalog.is_empty():
		return {}
	var effective_assets: Array = []
	for asset: Dictionary in _raw_assets():
		effective_assets.append(MapAssetCalibrationService.effective_asset(asset))
	catalog["assets"] = effective_assets
	catalog["extension_catalogs"] = EXTENSION_CATALOG_PATHS.duplicate()
	_catalog_cache = catalog.duplicate(true)
	return catalog


static func invalidate_cache() -> void:
	_catalog_cache.clear()


static func all_assets() -> Array:
	return load_catalog().get("assets", [])


static func find_asset(asset_id: String) -> Dictionary:
	for asset: Dictionary in all_assets():
		if str(asset.get("asset_id", "")) == asset_id:
			return asset.duplicate(true)
	return {}


static func find_base_asset(asset_id: String) -> Dictionary:
	for asset: Dictionary in _raw_assets():
		if str(asset.get("asset_id", "")) == asset_id:
			return asset.duplicate(true)
	return {}


static func _raw_assets() -> Array:
	var assets: Array = []
	for path: String in [CATALOG_PATH] + EXTENSION_CATALOG_PATHS:
		var catalog := _read_catalog(path)
		for asset: Dictionary in catalog.get("assets", []):
			assets.append(asset)
	return assets


static func _read_catalog(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func palette_assets(region := "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for asset: Dictionary in all_assets():
		if not bool(asset.get("placeable", false)):
			continue
		if not region.is_empty() and str(asset.get("theme", "")) not in [region, "shared", "ancient_gothic"]:
			continue
		result.append(asset)
	return result


static func validate_catalog() -> Array[String]:
	var errors: Array[String] = []
	var ids := {}
	for asset: Dictionary in all_assets():
		var asset_id := str(asset.get("asset_id", ""))
		if asset_id.is_empty() or ids.has(asset_id):
			errors.append("duplicate_or_missing_asset_id:%s" % asset_id)
		ids[asset_id] = true
		for field: String in ["display_name", "asset_type", "category", "theme", "anchor_px", "anchor_tile", "anchor_mode", "footprint_tiles", "tile_size", "collision_policy", "navigation_policy", "content_layer", "calibration_status", "placeable", "source_sha256", "output_sha256"]:
			if not asset.has(field):
				errors.append("%s:missing_%s" % [asset_id, field])
		if bool(asset.get("placeable", false)) and str(asset.get("calibration_status", "")) != "placeable":
			errors.append("%s:uncalibrated_placeable_asset" % asset_id)
	return errors
