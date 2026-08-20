extends Node


func _ready() -> void:
	var document := MapEditorTypes.new_map("resize_regression", 990120, "Resize Regression", Vector2i(64, 64))
	var resize_asset_id := ""
	for asset: Dictionary in MapAssetCatalogService.all_assets():
		var footprint: Array = asset.get("footprint_tiles", [0, 0])
		if bool(asset.get("placeable", false)) and str(asset.get("asset_type", "")) != "ground_brush" and mini(int(footprint[0]), int(footprint[1])) >= 2:
			resize_asset_id = str(asset.get("asset_id", ""))
			break
	assert(not resize_asset_id.is_empty(), "需要一个可缩放且非地面的地图素材")
	var placed := MapEditorInstanceService.create_instance(document, resize_asset_id, "building", Vector2i(20, 20))
	assert(placed.ok, str(placed.get("errors", [])))
	var instance_id := str(placed.instance.instance_id)
	var located := MapEditorInstanceService._locate(document, instance_id)
	assert(located.ok)
	var instance: Dictionary = located.instance
	instance["instance_base_scale"] = 0.40
	instance["instance_base_footprint_tiles"] = [4, 4]
	instance["footprint_tiles"] = [4, 4]
	instance["occupancy_footprint_tiles"] = [4, 4]
	instance["visual_footprint_tiles"] = [4, 4]
	instance["collision_policy"] = "solid_footprint"
	instance["collision_footprint_tiles"] = [4, 4]
	instance["scale"] = [0.40, 0.40]
	instance["offset_px"] = [13, -21]
	MapEditorInstanceService._located_replace(document, located, instance)
	var before: Dictionary = MapEditorInstanceService._locate(document, instance_id).instance.duplicate(true)
	var before_walkability := MapEditorCollisionService.build_walkability(document)
	assert(is_equal_approx(MapEditorInstanceService.stepped_visual_scale(0.40, 0.40, -1), 0.36))
	assert(MapEditorInstanceService.footprint_for_visual_scale([4, 4], 0.40, 0.36) == [4, 4])
	var fake_asset := {
		"footprint_tiles": [4, 4],
		"collision_footprint_tiles": [4, 4],
		"collision_policy": "solid_footprint",
		"approved_scale": 0.40,
		"logical_scale_level": 0,
	}
	var fake_base := fake_asset.duplicate(true)
	var asset_shrink := MapEditorApp.build_asset_resize_draft(fake_asset, fake_base, 2)
	assert(is_equal_approx(float(asset_shrink.approved_scale), 0.36), "素材菜单第一次缩小必须让图片变小")
	assert(asset_shrink.footprint_tiles == [4, 4])
	assert(asset_shrink.collision_footprint_tiles == [4, 4])

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
	assert(is_equal_approx(float(resized.instance.scale[0]), 0.36))
	assert(is_equal_approx(float(resized.instance.scale[0]), float(resized.instance.scale[1])), "视觉缩放必须等比")
	assert(resized.instance.footprint_tiles == [4, 4], "10% 缩放后整数占地保持 4x4")
	assert(resized.instance.collision_footprint_tiles == [4, 4], "占地未变时碰撞整数格不变")
	var after_walkability := MapEditorCollisionService.build_walkability(document)
	assert(after_walkability.blocked_count == before_walkability.blocked_count, "占地未变时碰撞范围不变")

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

	# ============================================================
	# P0: Legacy instance — two consecutive grows
	#
	# Legacy instance without instance_base_scale and
	# instance_base_footprint_tiles.
	#
	# Catalog base scale = B, catalog base footprint = BASE_FP.
	# Current scale = B * 0.50.
	#
	# First grow:  0.50B → 0.60B
	#   instance_base_scale          == B
	#   instance_base_footprint_tiles == BASE_FP
	#
	# Second grow: 0.60B → 0.70B
	#   instance_base_scale          == B    (still stable)
	#   instance_base_footprint_tiles == BASE_FP  (still stable)
	# ============================================================
	var p0_placed := MapEditorInstanceService.create_instance(
		document, resize_asset_id, "building", Vector2i(30, 20)
	)
	assert(p0_placed.ok, str(p0_placed.get("errors", [])))
	var p0_id := str(p0_placed.instance.instance_id)
	var p0_located := MapEditorInstanceService._locate(document, p0_id)
	assert(p0_located.ok)
	var p0_inst: Dictionary = p0_located.instance
	p0_inst.erase("instance_base_scale")
	p0_inst.erase("instance_base_footprint_tiles")
	var p0_asset := MapAssetCatalogService.find_asset(str(p0_placed.instance.asset_id))
	var p0_B := float(p0_asset.get("approved_scale", 1.0))
	var p0_BASE_FP: Array = p0_asset.get(
		"base_footprint_tiles",
		p0_asset.get("footprint_tiles", [1, 1])
	)
	var p0_current_scale := p0_B * 0.50

	var p0_CURRENT_FP: Array = (
		MapEditorInstanceService.footprint_for_visual_scale(
			p0_BASE_FP,
			p0_B,
			p0_current_scale
		)
	)

	assert(
		p0_CURRENT_FP != p0_BASE_FP,
		"P0 test must simulate a legacy instance whose current footprint is already smaller than its catalog base footprint"
	)

	p0_inst["scale"] = [
		p0_current_scale,
		p0_current_scale,
	]

	p0_inst["footprint_tiles"] = (
		p0_CURRENT_FP.duplicate()
	)

	p0_inst["occupancy_footprint_tiles"] = (
		p0_CURRENT_FP.duplicate()
	)

	p0_inst["visual_footprint_tiles"] = (
		p0_CURRENT_FP.duplicate()
	)

	p0_inst["collision_policy"] = "none"
	p0_inst["collision_footprint_tiles"] = [0, 0]

	p0_inst["instance_custom_scale"] = true
	MapEditorInstanceService._located_replace(document, p0_located, p0_inst)

	# First grow: 0.50B → 0.60B
	var p0_first := MapEditorInstanceService.resize_instance(
		document, p0_id, 1
	)
	assert(p0_first.ok, "P0 first grow: " + str(p0_first.get("errors", [])))
	assert(
		p0_first.instance.has("instance_base_scale"),
		"P0: instance_base_scale must be persisted after first grow"
	)
	assert(
		is_equal_approx(float(p0_first.instance.instance_base_scale), p0_B),
		"P0: first grow — instance_base_scale must be catalog B (" + str(p0_B) + "), got " + str(p0_first.instance.instance_base_scale)
	)
	assert(
		p0_first.instance.instance_base_footprint_tiles == p0_BASE_FP,
		"P0: first grow — instance_base_footprint_tiles must be catalog BASE_FP (" + str(p0_BASE_FP) + "), got " + str(p0_first.instance.instance_base_footprint_tiles)
	)

	# Second grow: 0.60B → 0.70B
	var p0_second := MapEditorInstanceService.resize_instance(
		document, p0_id, 1
	)
	assert(p0_second.ok, "P0 second grow: " + str(p0_second.get("errors", [])))
	assert(
		is_equal_approx(float(p0_second.instance.instance_base_scale), p0_B),
		"P0: second grow — instance_base_scale must still be catalog B (" + str(p0_B) + "), got " + str(p0_second.instance.instance_base_scale)
	)
	assert(
		p0_second.instance.instance_base_footprint_tiles == p0_BASE_FP,
		"P0: second grow — instance_base_footprint_tiles must still be catalog BASE_FP (" + str(p0_BASE_FP) + "), got " + str(p0_second.instance.instance_base_footprint_tiles)
	)
	print("P0_LEGACY_BASE_PASS")

	# ============================================================
	# P1: foot_tile asset — threshold crossing 2×2 → 3×3
	#
	# BEFORE:  base_scale=1.0, instance_base_footprint_tiles=[2,2],
	#          scale=[1.20,1.20], footprint_tiles=[2,2], tile=[32,32]
	#
	# AFTER ONE GROW: scale=[1.30,1.30], footprint_tiles=[3,3]
	#
	# footprint_bottom_vertex_v1 rule:
	#   new_tile = old_tile - (new_fp - old_fp)
	#            = [32,32] - [1,1] = [31,31]
	#   offset unchanged
	#
	# Visual foot: tile_to_ground_px(tile + fp) + offset
	# must be preserved.
	# ============================================================
	var p1_asset_id := ""
	for p1_candidate: Dictionary in MapAssetCatalogService.all_assets():
		var p1_fp: Array = p1_candidate.get("footprint_tiles", [0, 0])
		if (
			str(p1_candidate.get("anchor_mode", "")) == "foot_tile"
			and bool(p1_candidate.get("placeable", false))
			and str(p1_candidate.get("asset_type", "")) != "ground_brush"
			and mini(int(p1_fp[0]), int(p1_fp[1])) >= 2
		):
			p1_asset_id = str(p1_candidate.get("asset_id", ""))
			break
	assert(
		not p1_asset_id.is_empty(),
		"P1: need a placeable foot_tile asset from the catalog"
	)

	var p1_placed := MapEditorInstanceService.create_instance(
		document, p1_asset_id, "decoration", Vector2i(32, 32)
	)
	assert(p1_placed.ok, str(p1_placed.get("errors", [])))
	var p1_id := str(p1_placed.instance.instance_id)
	var p1_located := MapEditorInstanceService._locate(document, p1_id)
	assert(p1_located.ok)
	var p1_inst: Dictionary = p1_located.instance
	p1_inst["instance_base_footprint_tiles"] = [2, 2]
	p1_inst["instance_base_scale"] = 1.0
	p1_inst["scale"] = [1.20, 1.20]
	p1_inst["footprint_tiles"] = [2, 2]
	p1_inst["tile"] = [32, 32]
	p1_inst["tile_anchor"] = [32, 32]
	p1_inst["offset_px"] = [0, 0]
	MapEditorInstanceService._located_replace(document, p1_located, p1_inst)

	var p1_before_tile := Vector2i(32, 32)
	var p1_before_fp := Vector2i(2, 2)
	var p1_before_offset := Vector2(0, 0)
	var p1_before_bottom := MapEditorCoordinate.tile_to_ground_px(
		Vector2(
			float(p1_before_tile.x) + float(p1_before_fp.x),
			float(p1_before_tile.y) + float(p1_before_fp.y)
		),
		Vector2i(64, 64)
	) + p1_before_offset

	# One grow: 1.20 → 1.30, fp 2×2 → 3×3
	var p1_resized := MapEditorInstanceService.resize_instance(
		document, p1_id, 1
	)
	assert(p1_resized.ok, "P1: " + str(p1_resized.get("errors", [])))
	assert(
		is_equal_approx(float(p1_resized.instance.scale[0]), 1.30),
		"P1: scale must be 1.30, got " + str(p1_resized.instance.scale[0])
	)
	assert(
		p1_resized.instance.footprint_tiles == [3, 3],
		"P1: footprint must grow to [3,3], got " + str(p1_resized.instance.footprint_tiles)
	)
	assert(
		p1_resized.instance.tile == [31, 31],
		"P1: tile must be [31,31] (bottom vertex), got " + str(p1_resized.instance.tile)
	)
	assert(
		is_equal_approx(float(p1_resized.instance.offset_px[0]), 0.0)
		and is_equal_approx(float(p1_resized.instance.offset_px[1]), 0.0),
		"P1: offset must stay unchanged [0,0], got " + str(p1_resized.instance.offset_px)
	)

	var p1_after_tile := Vector2i(31, 31)
	var p1_after_fp := Vector2i(3, 3)
	var p1_after_offset := Vector2(0, 0)
	var p1_after_bottom := MapEditorCoordinate.tile_to_ground_px(
		Vector2(
			float(p1_after_tile.x) + float(p1_after_fp.x),
			float(p1_after_tile.y) + float(p1_after_fp.y)
		),
		Vector2i(64, 64)
	) + p1_after_offset

	assert(
		p1_after_bottom.is_equal_approx(p1_before_bottom),
		"P1: visual foot must not jump when integer footprint changes. Before: " + str(p1_before_bottom) + ", After: " + str(p1_after_bottom)
	)
	print("P1_FOOT_TILE_ANCHOR_PASS")

	print("MSE_INSTANCE_RESIZE_REGRESSION_PASS")
	get_tree().quit(0)
