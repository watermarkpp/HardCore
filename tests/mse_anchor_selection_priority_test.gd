extends Node


func _ready() -> void:
	MapAssetCatalogService.invalidate_cache()
	var document := MapEditorTypes.new_map(
		"anchor_selection_priority",
		990212,
		"Anchor Selection Priority",
		Vector2i(38, 38)
	)
	var small := MapEditorInstanceService.create_instance(
		document,
		"cave_dungeon.brazier_01",
		"decoration",
		Vector2i(12, 10),
		"object_base"
	)
	assert(small.ok, str(small.get("errors", [])))
	var wall := MapEditorInstanceService.create_instance(
		document,
		"orc_tomb_wall_straight_x_l4_v01",
		"terrain",
		Vector2i(10, 10),
		"object_base"
	)
	assert(wall.ok, str(wall.get("errors", [])))
	var preview := MapEditorCanvasPreview.new()
	add_child(preview)
	preview.set_document(document)
	preview._draw_offset = Vector2.ZERO
	preview._draw_scale = 1.0
	var small_asset := MapAssetCatalogService.find_asset(str(small.instance.asset_id))
	var small_texture := preview._texture_for_asset(str(small.instance.asset_id))
	assert(small_texture != null)
	var small_geometry := MapEditorCanvasPreview.instance_visual_geometry(
		small.instance,
		Vector2i(38, 38),
		Vector2.ZERO,
		1.0,
		small_texture.get_size(),
		small_asset
	)
	var wall_asset := MapAssetCatalogService.find_asset(str(wall.instance.asset_id))
	var wall_texture := preview._texture_for_asset(str(wall.instance.asset_id))
	assert(wall_texture != null)
	var wall_geometry := MapEditorCanvasPreview.instance_visual_geometry(
		wall.instance,
		Vector2i(38, 38),
		Vector2.ZERO,
		1.0,
		wall_texture.get_size(),
		wall_asset
	)
	var click_position: Vector2 = small_geometry.center
	assert((wall_geometry.rect as Rect2).grow(4.0).has_point(click_position))
	assert(preview._hit_selectable(click_position) == str(small.instance.instance_id))
	print(
		"MSE_ANCHOR_SELECTION_PRIORITY_PASS small=%s wall=%s"
		% [small.instance.instance_id, wall.instance.instance_id]
	)
	get_tree().quit(0)
