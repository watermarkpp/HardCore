extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("resize_regression", 990120, "Resize Regression", Vector2i(64, 64))
	var resize_asset_id := ""
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var footprint: Array = asset.get("footprint_tiles", [0, 0])
		var collision: Array = asset.get("collision_footprint_tiles", [0, 0])
		if bool(asset.get("placeable", false)) and str(asset.get("asset_type", "")) != "ground_brush" \
				and mini(int(footprint[0]), int(footprint[1])) >= 3 \
				and mini(int(collision[0]), int(collision[1])) >= 3:
			resize_asset_id = str(asset.get("asset_id", ""))
			break
	assert(not resize_asset_id.is_empty(), "需要一个可缩放且带碰撞的地图素材")
	var placed := MapEditorInstanceService.create_instance(document, resize_asset_id, "building", Vector2i(20, 20))
	assert(placed.ok, str(placed.get("errors", [])))
	var instance_id := str(placed.instance.instance_id)
	var located := MapEditorInstanceService._locate(document, instance_id)
	assert(located.ok)
	var instance: Dictionary = located.instance
	instance["scale"] = [0.40, 0.40]
	instance["offset_px"] = [13, -21]
	MapEditorInstanceService._located_replace(document, located, instance)
	var before: Dictionary = MapEditorInstanceService._locate(document, instance_id).instance.duplicate(true)
	var before_walkability := MapEditorCollisionService.build_walkability(document)
	assert(MapEditorInstanceService.resized_visual_scale(Vector2(0.40, 0.40), [4, 4], [3, 3]).is_equal_approx(Vector2(0.30, 0.30)))
	var fake_asset := {
		"footprint_tiles": [4, 4],
		"collision_footprint_tiles": [4, 4],
		"collision_policy": "solid_footprint",
		"approved_scale": 0.40,
		"logical_scale_level": 0,
	}
	var fake_base := fake_asset.duplicate(true)
	var asset_shrink := MapEditorApp.build_asset_resize_draft(fake_asset, fake_base, 2)
	assert(asset_shrink.footprint_tiles == [3, 3])
	assert(is_equal_approx(float(asset_shrink.approved_scale), 0.30), "素材菜单第一次缩小也必须让图片变小")
	assert(asset_shrink.collision_footprint_tiles == [3, 3])

	var preview := MapEditorCanvasPreview.new()
	preview.size = Vector2(900, 700)
	add_child(preview)
	preview.set_document(document)
	preview._draw_offset = Vector2(120, 90)
	preview._draw_scale = 0.75
	var texture := preview._texture_for_asset(str(before.asset_id))
	assert(texture != null)
	var design_size := Vector2i(64, 64)
	var before_geometry := MapEditorCanvasPreview.instance_visual_geometry(
		before, design_size, preview._draw_offset, preview._draw_scale, texture.get_size(),
		MapAssetCatalogService.find_asset(str(before.asset_id))
	)

	var resized := MapEditorInstanceService.resize_instance(document, instance_id, -1)
	assert(resized.ok, str(resized.get("errors", [])))
	assert(float(resized.instance.scale[0]) < float(before.scale[0]), "第一次缩小必须让图片变小")
	assert(int(resized.instance.footprint_tiles[0]) < int(before.footprint_tiles[0]))
	assert(resized.instance.collision_footprint_tiles == resized.instance.footprint_tiles, "实体碰撞必须同步占地缩放")
	var after_walkability := MapEditorCollisionService.build_walkability(document)
	assert(after_walkability.blocked_count < before_walkability.blocked_count, "缩小后碰撞范围必须缩小")

	preview.set_document(document)
	preview.selected_selectable_id = instance_id
	var after_geometry := MapEditorCanvasPreview.instance_visual_geometry(
		resized.instance, design_size, preview._draw_offset, preview._draw_scale, texture.get_size(),
		MapAssetCatalogService.find_asset(str(resized.instance.asset_id))
	)
	assert(after_geometry.rect.size.x < before_geometry.rect.size.x)
	assert(after_geometry.rect.size.y < before_geometry.rect.size.y)
	var tile: Array = resized.instance.tile
	var footprint: Array = resized.instance.footprint_tiles
	var offset_px: Array = resized.instance.offset_px
	var foot := Vector2(float(tile[0]) + float(footprint[0]) * 0.5, float(tile[1]) + float(footprint[1]) * 0.5)
	var expected_center := preview._draw_offset + (
		MapEditorCoordinate.tile_to_ground_px(foot, design_size) + Vector2(float(offset_px[0]), float(offset_px[1]))
	) * preview._draw_scale
	assert(after_geometry.center.is_equal_approx(expected_center), "图片、选择框必须共用包含 offset_px 的中心")
	assert(preview._hit_selectable(after_geometry.rect.get_center()) == instance_id, "缩放后的选择框必须仍命中图片")

	print("MSE_INSTANCE_RESIZE_REGRESSION_PASS")
	get_tree().quit(0)
