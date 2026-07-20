extends Node


const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const OUTPUT_PATH := "res://outputs/test/wooma_temple_wall_ring_review.png"


func _ready() -> void:
	print("MSE_WOOMA_TEMPLE_WALL_VISUAL_CAPTURE_BEGIN")
	var document := MapEditorTypes.new_map(
		"wooma_temple_wall_visual_review",
		990313,
		"Wooma Temple Wall Visual Review",
		Vector2i(24, 24)
	)
	var bounds := Rect2i(3, 4, 12, 10)
	var applied := MapEditorWallLoopService.apply_closed_rectangle(
		document,
		FAMILY_ID,
		bounds,
		"outer_corner",
		"terrain_base",
		true,
		"test.wooma_temple.visual_review"
	)
	assert(applied.ok, str(applied.get("errors", [])))

	var corners: Array[Dictionary] = []
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var asset := MapAssetCatalogService.find_asset(
			str(instance.get("asset_id", ""))
		)
		if str(asset.get("topology", "")) not in [
			"inner_corner",
			"outer_corner",
		]:
			continue
		corners.append({
			"tile": instance.get("tile", []),
			"asset_id": str(instance.get("asset_id", "")),
			"orientation": str(asset.get("corner_orientation", "")),
			"offset_px": instance.get("offset_px", []),
			"sort_offset": instance.get(
				"adaptive_corner_sort_tile_offset",
				[]
			),
		})
	assert(corners.size() == 4)

	var canvas := MapEditorCanvasPreview.new()
	canvas.size = Vector2(1600, 900)
	canvas.show_grid = false
	canvas.set_interaction_mode("select")
	canvas.set_document(document)
	add_child(canvas)
	for _frame in range(4):
		await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(
		ProjectSettings.globalize_path("res://outputs/test")
	)
	var image := get_viewport().get_texture().get_image()
	assert(image.save_png(OUTPUT_PATH) == OK)
	print(
		"MSE_WOOMA_TEMPLE_WALL_VISUAL_CAPTURE_PASS corners=",
		JSON.stringify(corners),
		" output=",
		ProjectSettings.globalize_path(OUTPUT_PATH)
	)
	get_tree().quit(0)
