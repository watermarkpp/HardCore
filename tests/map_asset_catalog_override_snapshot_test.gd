extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var temp_path := "user://map_asset_catalog_override_snapshot_test.json"
	var payload := {
		"asset_schema_version": 2,
		"content_layer": "test",
		"overrides": {
			"asset.test": {
				"approved_scale": 1.25,
				"footprint_tiles": [3, 2],
			},
		},
	}
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	assert(file != null, "temporary override fixture must be writable")
	file.store_string(JSON.stringify(payload))
	file.close()

	var base_asset := {
		"asset_id": "asset.test",
		"approved_scale": 1.0,
		"footprint_tiles": [1, 1],
		"nested": {"preserved": true},
	}
	var direct := MapAssetCalibrationService.effective_asset(base_asset, temp_path)
	var snapshot_payload := MapAssetCalibrationService.load_overrides(temp_path)
	var from_snapshot := MapAssetCalibrationService.effective_asset_from_overrides(
		base_asset,
		snapshot_payload.get("overrides", {})
	)
	assert(direct == from_snapshot, "snapshot application must match the legacy public API")
	assert(float(from_snapshot.approved_scale) == 1.25)
	assert(int(from_snapshot.footprint_tiles[0]) == 3)
	assert(int(from_snapshot.footprint_tiles[1]) == 2)
	assert(bool(from_snapshot.nested.preserved), "unmodified nested fields must survive")

	MapAssetCatalogService.invalidate_cache()
	MapAssetCalibrationService.reset_load_overrides_call_count()
	var catalog := MapAssetCatalogService.load_catalog()
	assert(not catalog.is_empty(), "formal map asset catalog must load")
	assert(
		MapAssetCalibrationService.load_overrides_call_count() == 1,
		"one cold catalog load must parse calibration overrides exactly once"
	)
	MapAssetCatalogService.invalidate_cache()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(temp_path))

	print("MAP_ASSET_CATALOG_OVERRIDE_SNAPSHOT_PASS")
	get_tree().quit(0)
