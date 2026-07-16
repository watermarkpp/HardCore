extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("stage3_ghost_test", 991003, "Stage3 Ghost Test", Vector2i(64, 64))
	var valid := MapEditorPlacementValidator.validate(document, "ground.dark_grass.001", Vector2i(63, 63))
	assert(valid.ok and valid.level == "ok")
	var invalid := MapEditorPlacementValidator.validate(document, "ground.dark_grass.001", Vector2i(64, 0))
	assert(not invalid.ok and "footprint_out_of_bounds" in invalid.errors)
	var missing := MapEditorPlacementValidator.validate(document, "missing.asset", Vector2i(1, 1))
	assert(not missing.ok and "asset_not_found" in missing.errors)
	var ghost := MapEditorGhostPreview.build(document, "ground.dark_grass.001", Vector2i(3, 4))
	assert(ghost.validation.ok and ghost.polygon_ground_px.size() == 4)
	assert(ghost.polygon_ground_px[0] == MapEditorCoordinate.tile_to_ground_px(Vector2(3, 4), Vector2i(64, 64)))
	var base := MapAssetCatalogService.find_base_asset("ground.dark_grass.001")
	var valid_draft := {"anchor_px": [31, 15], "footprint_tiles": [1, 1], "collision_policy": "none", "occlusion": true, "placeable": true, "calibration_status": "placeable"}
	assert(MapAssetCalibrationService.validate_draft(base, valid_draft).is_empty())
	var invalid_draft := valid_draft.duplicate(true); invalid_draft.footprint_tiles = [2, 1]
	assert("ground_footprint_requires_new_normalized_image" in MapAssetCalibrationService.validate_draft(base, invalid_draft))
	var override_path := "user://mse_stage3_override_%s.json" % Time.get_ticks_usec()
	var saved := MapAssetCalibrationService.save_override("ground.dark_grass.001", valid_draft, override_path)
	assert(saved.ok, str(saved.get("errors", [])))
	var effective := MapAssetCalibrationService.effective_asset(base, override_path)
	assert(Vector2i(int(effective.anchor_px[0]), int(effective.anchor_px[1])) == Vector2i(31, 15) and effective.occlusion and effective.content_layer == "personal_expansion")
	print("MSE_STAGE3_CALIBRATION_GHOST_PASS")
	get_tree().quit(0)
