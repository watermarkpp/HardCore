extends Node


func _ready() -> void:
	var catalog_path := "res://assets/data/assets/map_cave_dungeon_asset_catalog.json"
	assert(FileAccess.file_exists(catalog_path))
	var file := FileAccess.open(catalog_path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary)
	var extension_assets: Array = parsed.get("assets", [])
	assert(extension_assets.size() == 165)
	var wall_count := 0
	var sheet_count := 0
	var first_straight_wall: Dictionary = {}
	for asset: Dictionary in extension_assets:
		var asset_id := str(asset.get("asset_id", ""))
		assert(not asset_id.is_empty())
		assert(str(asset.get("palette_path", "")).begins_with("洞穴与地下城/"))
		assert(bool(asset.get("placeable", false)))
		assert(str(asset.get("calibration_status", "")) == "placeable")
		var image_path := "res://" + str(asset.get("image", ""))
		assert(FileAccess.file_exists(image_path), "%s missing image" % asset_id)
		var anchor: Array = asset.get("anchor_px", [])
		var image_size: Array = asset.get("image_size", [])
		assert(anchor.size() == 2 and image_size.size() == 2)
		assert(int(anchor[0]) >= 0 and int(anchor[0]) <= int(image_size[0]))
		assert(int(anchor[1]) >= 0 and int(anchor[1]) <= int(image_size[1]))
		if str(asset.get("asset_type", "")) == "wall_module":
			wall_count += 1
			if str(asset.get("topology", "")) == "straight" and int(asset.get("length_tiles", 0)) == 4 and first_straight_wall.is_empty():
				first_straight_wall = asset
		else:
			sheet_count += 1
	assert(wall_count == 84)
	assert(sheet_count == 81)
	assert(not first_straight_wall.is_empty())
	assert(MapAssetCatalogService.find_asset(str(first_straight_wall.asset_id)).asset_id == first_straight_wall.asset_id)
	assert(MapAssetCatalogService.find_base_asset(str(first_straight_wall.asset_id)).asset_id == first_straight_wall.asset_id)

	var document := MapEditorTypes.new_map("cave_dungeon_import_test", 990160, "Cave Dungeon Import", Vector2i(64, 64))
	var placed := MapEditorInstanceService.create_instance(document, str(first_straight_wall.asset_id), "terrain", Vector2i(20, 20), "terrain_base")
	assert(placed.ok, str(placed.get("errors", [])))
	assert(str(placed.instance.collision_policy) == "wall_cells_generated")
	assert(not (placed.instance.collision_cells as Array).is_empty())
	var before := MapEditorCollisionService.build_walkability(document)
	assert(before.blocked_count == (placed.instance.collision_cells as Array).size())
	var resized := MapEditorInstanceService.resize_instance(document, str(placed.instance.instance_id), -1)
	assert(resized.ok, str(resized.get("errors", [])))
	var after := MapEditorCollisionService.build_walkability(document)
	assert(after.blocked_count < before.blocked_count)
	assert(resized.instance.footprint_tiles == resized.instance.collision_footprint_tiles)

	var pillar_asset := MapAssetCatalogService.find_asset("cave_dungeon.rock_pillar_01")
	assert(not pillar_asset.is_empty())
	var pillar_document := MapEditorTypes.new_map("cave_prop_resize_test", 990161, "Cave Prop Resize", Vector2i(64, 64))
	var pillar := MapEditorInstanceService.create_instance(pillar_document, str(pillar_asset.asset_id), "terrain", Vector2i(24, 24))
	assert(pillar.ok, str(pillar.get("errors", [])))
	var pillar_scale_before := float(pillar.instance.scale[0])
	var pillar_before := MapEditorCollisionService.build_walkability(pillar_document)
	var pillar_resized := MapEditorInstanceService.resize_instance(pillar_document, str(pillar.instance.instance_id), -1)
	assert(pillar_resized.ok, str(pillar_resized.get("errors", [])))
	var pillar_after := MapEditorCollisionService.build_walkability(pillar_document)
	assert(float(pillar_resized.instance.scale[0]) < pillar_scale_before)
	assert(pillar_after.blocked_count < pillar_before.blocked_count)

	print("MSE_CAVE_DUNGEON_ASSET_IMPORT_PASS assets=%d walls=%d sheets=%d" % [extension_assets.size(), wall_count, sheet_count])
	get_tree().quit(0)
