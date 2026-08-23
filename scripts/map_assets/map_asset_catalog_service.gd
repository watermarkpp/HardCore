class_name MapAssetCatalogService
extends RefCounted

const CATALOG_PATH := "res://assets/data/assets/map_asset_catalog.json"
const IMPORT_CATALOG_PATH := "res://assets/data/assets/map_asset_import_catalog.json"
const V15_CATALOG_PATH := "res://assets/data/assets/map_v15_batch_asset_catalog.json"
const EXTENSION_CATALOG_PATHS := [
	"res://assets/data/assets/map_object_asset_catalog.json",
	"res://assets/data/assets/map_terrain_asset_catalog.json",
	"res://assets/data/assets/map_cave_dungeon_asset_catalog.json",
	"res://assets/data/assets/map_exit_asset_catalog.json",
	"res://assets/data/assets/map_deep_forest_asset_catalog.json",
	"res://assets/data/assets/map_ground_graffiti_asset_catalog.json",
	"res://assets/data/assets/map_new_carpet_asset_catalog.json",
	"res://assets/data/assets/map_new_ground_pillar_throne_asset_catalog.json",
	"res://assets/data/assets/map_new_throne_asset_catalog.json",
	"res://assets/data/assets/map_wooma_temple_wall_asset_catalog.json",
	"res://assets/data/assets/map_wooma_temple_warm_wall_asset_catalog.json",
	"res://assets/data/assets/map_chiyue_valley_wall_asset_catalog.json",
	"res://assets/data/assets/map_user_gothic_floor_asset_catalog.json",
	"res://assets/data/assets/map_stone_tomb_floor_asset_catalog.json",
	"res://assets/data/assets/map_xzsc_cage_asset_catalog.json",
	"res://assets/data/assets/map_xzsc_sculpture_asset_catalog.json",
	"res://assets/data/assets/map_chain_roadblock_asset_catalog.json",
	"res://assets/data/assets/map_small_decoration_asset_catalog.json",
]
const ManualCollisionPolicy := preload("res://scripts/map_assets/map_asset_manual_collision_policy.gd")
const PlacementAnchorPolicy := preload("res://scripts/map_assets/map_asset_placement_anchor_policy.gd")
static var _catalog_cache: Dictionary = {}
static var _asset_index: Dictionary = {}
static var _normalized_ground_by_source_sha: Dictionary = {}
static var _legacy_ground_index: Dictionary = {}
static var _v15_asset_index: Dictionary = {}


static func load_catalog() -> Dictionary:
	if not _catalog_cache.is_empty():
		return _catalog_cache
	var catalog := _read_catalog(CATALOG_PATH)
	if catalog.is_empty():
		return {}
	_ensure_normalized_ground_index()
	_ensure_v15_asset_index()
	var effective_assets: Array = []
	_asset_index.clear()
	for asset: Dictionary in _raw_assets():
		var effective := MapAssetCalibrationService.effective_asset(_canonical_editor_asset(asset))
		# Ground geometry remains canonical after calibration, while an explicit
		# user-saved wall calibration is allowed to replace the visual-only
		# family default.
		effective = _canonical_ground_asset(effective)
		# Imported foot-tile props store the visible bottom point as anchor_px.
		# The editor positions instances from the centre of their logical
		# footprint, so convert only the placement anchor to that coordinate
		# system. Keep anchor_px untouched as the user's calibration source.
		effective = PlacementAnchorPolicy.apply_to_asset(effective)
		effective_assets.append(effective)
		_asset_index[str(effective.get("asset_id", ""))] = effective
	catalog["assets"] = effective_assets
	catalog["extension_catalogs"] = EXTENSION_CATALOG_PATHS.duplicate()
	_catalog_cache = catalog
	return catalog


static func invalidate_cache() -> void:
	_catalog_cache.clear()
	_asset_index.clear()
	_normalized_ground_by_source_sha.clear()
	_legacy_ground_index.clear()
	_v15_asset_index.clear()


static func all_assets() -> Array:
	return load_catalog().get("assets", [])


static func find_asset(asset_id: String) -> Dictionary:
	load_catalog()
	var asset: Dictionary = _asset_index.get(
		asset_id,
		_v15_asset_index.get(asset_id, _legacy_ground_index.get(asset_id, {}))
	)
	return asset.duplicate(true) if not asset.is_empty() else {}


static func find_base_asset(asset_id: String) -> Dictionary:
	for asset: Dictionary in _raw_assets():
		if str(asset.get("asset_id", "")) == asset_id:
			return _canonical_editor_asset(asset).duplicate(true)
	_ensure_v15_asset_index()
	var v15: Dictionary = _v15_asset_index.get(asset_id, {})
	if not v15.is_empty():
		return v15.duplicate(true)
	_ensure_normalized_ground_index()
	var legacy: Dictionary = _legacy_ground_index.get(asset_id, {})
	return legacy.duplicate(true) if not legacy.is_empty() else {}


static func _ensure_normalized_ground_index() -> void:
	if not _legacy_ground_index.is_empty():
		return
	var catalog := _read_catalog(IMPORT_CATALOG_PATH)
	for imported: Dictionary in catalog.get("imports", []):
		if str(imported.get("status", "")) != "calibrated":
			continue
		var asset_id := str(imported.get("asset_id", ""))
		var output_path := str(imported.get("output_path", ""))
		var source_sha := str(imported.get("source_sha256", ""))
		if asset_id.is_empty() or output_path.is_empty() or source_sha.is_empty():
			continue
		var normalized := {
			"asset_id": asset_id,
			"display_name": asset_id,
			"asset_type": "ground_brush",
			"category": "ground",
			"object_class": "ground",
			"theme": "ancient_gothic",
			"image": output_path,
			"thumbnail": output_path,
			"canvas_size": [64, 32],
			"image_size": [64, 32],
			"logical_bounds_px": [0, 0, 64, 32],
			"visible_bounds_px": [0, 0, 64, 32],
			"anchor_px": [32, 16],
			"placement_anchor_px": [32, 16],
			"anchor_tile": [0, 0],
			"anchor_mode": "tile_center",
			"footprint_tiles": [1, 1],
			"visual_footprint_tiles": [1, 1],
			"occupancy_footprint_tiles": [1, 1],
			"base_footprint_tiles": [1, 1],
			"collision_footprint_tiles": [0, 0],
			"tile_size": [64, 32],
			"approved_scale": 1.0,
			"logical_scale_level": 0,
			"collision_policy": "none",
			"collision_profile_id": "none_visual",
			"navigation_policy": "ignore",
			"occlusion": false,
			"content_layer": "personal_expansion",
			"placeable": true,
			"calibration_status": "placeable",
			"normalization": str(imported.get("normalization", "alpha_tip_perspective_to_64x32")),
			"diamond_inner_coverage": float(imported.get("diamond_inner_coverage", 1.0)),
			"source_sha256": source_sha,
		}
		_legacy_ground_index[asset_id] = normalized
		_normalized_ground_by_source_sha[source_sha] = normalized


static func _ensure_v15_asset_index() -> void:
	if not _v15_asset_index.is_empty():
		return
	var catalog := _read_catalog(V15_CATALOG_PATH)
	for asset: Dictionary in catalog.get("assets", []):
		var asset_id := str(asset.get("asset_id", ""))
		if asset_id.is_empty():
			continue
		_v15_asset_index[asset_id] = _canonical_editor_asset(asset)


static func _canonical_ground_asset(asset: Dictionary) -> Dictionary:
	if str(asset.get("asset_type", "")) != "ground_brush":
		return asset
	_ensure_normalized_ground_index()
	var normalized: Dictionary = _normalized_ground_by_source_sha.get(str(asset.get("source_sha256", "")), {})
	var result := asset.duplicate(true)
	var canonical_geometry := {
		"canvas_size": [64, 32],
		"image_size": [64, 32],
		"logical_bounds_px": [0, 0, 64, 32],
		"visible_bounds_px": [0, 0, 64, 32],
		"anchor_px": [32, 16],
		"placement_anchor_px": [32, 16],
		"anchor_tile": [0, 0],
		"anchor_mode": "tile_center",
		"footprint_tiles": [1, 1],
		"visual_footprint_tiles": [1, 1],
		"occupancy_footprint_tiles": [1, 1],
		"base_footprint_tiles": [1, 1],
		"collision_footprint_tiles": [0, 0],
		"tile_size": [64, 32],
		"approved_scale": 1.0,
		"logical_scale_level": 0,
		"collision_policy": "none",
		"collision_profile_id": "none_visual",
		"navigation_policy": "ignore",
		"occlusion": false,
	}
	for key: String in canonical_geometry:
		result[key] = canonical_geometry[key]
	if normalized.is_empty():
		result["normalization"] = "runtime_alpha_bounds_to_64x32_diamond_mask"
		result["diamond_inner_coverage"] = 1.0
		return result
	for key: String in [
		"image", "thumbnail", "normalization", "diamond_inner_coverage",
	]:
		result[key] = normalized[key]
	result["normalized_ground_asset_id"] = str(normalized.get("asset_id", ""))
	return result


static func _canonical_editor_asset(asset: Dictionary) -> Dictionary:
	return ManualCollisionPolicy.apply_to_asset(_canonical_ground_asset(_resolve_tracked_staging_image(asset)))


static func _resolve_tracked_staging_image(asset: Dictionary) -> Dictionary:
	var image_path := str(asset.get("image", ""))
	if image_path.is_empty() or FileAccess.file_exists("res://" + image_path):
		return asset
	var raw_import_path := str(asset.get("raw_import_path", ""))
	var raw_prefix := "assets/raw_import/map_editor_batches_v1_5/"
	if not raw_import_path.begins_with(raw_prefix):
		return asset
	var relative_batch_directory := raw_import_path.trim_prefix(raw_prefix).get_base_dir()
	var candidate := (
		"assets/art/maps/_staging/v1_5/"
		+ relative_batch_directory
		+ "/editor_canvas/"
		+ image_path.get_file()
	)
	if not FileAccess.file_exists("res://" + candidate):
		return asset
	var resolved := asset.duplicate(true)
	resolved["image"] = candidate
	resolved["thumbnail"] = candidate
	resolved["resolved_from_tracked_staging"] = true
	return resolved


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
