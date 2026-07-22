extends Node


func _ready() -> void:
	assert(IsoFootprintGeometry.logical_canvas_size(Vector2i(1, 1)) == Vector2i(64, 32))
	assert(IsoFootprintGeometry.logical_canvas_size(Vector2i(2, 2)) == Vector2i(128, 64))
	assert(IsoFootprintGeometry.logical_canvas_size(Vector2i(3, 1)) == Vector2i(128, 64))
	assert(IsoFootprintGeometry.logical_canvas_size(Vector2i(4, 2)) == Vector2i(192, 96))
	assert(IsoFootprintGeometry.logical_diamond(Vector2i(3, 1))[0] == Vector2(32, 0))
	assert(MapAssetCatalogService.validate_catalog().is_empty())
	var assets := MapAssetCatalogService.all_assets()
	assert(assets.size() >= 415)
	var ground_count := 0
	for asset: Dictionary in assets:
		if asset.get("asset_type", "") == "ground_brush":
			ground_count += 1
			var asset_id := str(asset.get("asset_id", ""))
			assert(Vector2i(int(asset.footprint_tiles[0]), int(asset.footprint_tiles[1])) == Vector2i.ONE, asset_id)
			assert(Vector2i(int(asset.tile_size[0]), int(asset.tile_size[1])) == Vector2i(64, 32), asset_id)
			assert(Vector2i(int(asset.canvas_size[0]), int(asset.canvas_size[1])) == Vector2i(64, 32), asset_id)
			assert(float(asset.diamond_inner_coverage) >= 0.995, asset_id)
			assert(asset.content_layer == "personal_expansion")
	assert(ground_count == 173, str(ground_count))
	var document := MapEditorTypes.new_map_from_catalog("sandbox_64", "quest_room", 990001, "64格沙盒")
	assert(document.layers.has("ground_base"))
	assert(document.layers.has("interactables") and document.layers.has("region_semantics"))
	assert(MapEditorTypes.validate_document(document).is_empty())
	print("MSE_R1_GATE_PASS")
	get_tree().quit(0)
