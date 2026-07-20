extends Node


const FAMILY_ID := "wooma_temple_gothic_stone_u0"
const OUTPUT_PATH := "res://outputs/test/wooma_temple_wall_ring_review.png"


func _ready() -> void:
	print("MSE_WOOMA_TEMPLE_WALL_VISUAL_CAPTURE_BEGIN")
	MapAssetCatalogService.invalidate_cache()
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
	assert(str(applied.plan.get("corner_join_mode", "")) == "straight_overlap")

	var topology_counts := {}
	for instance: Dictionary in MapEditorInstanceService.all_instances(document):
		var asset := MapAssetCatalogService.find_asset(str(instance.asset_id))
		var topology := str(asset.get("topology", ""))
		topology_counts[topology] = int(topology_counts.get(topology, 0)) + 1
	assert(topology_counts.size() == 1)
	assert(topology_counts.has("straight"))

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
		"MSE_WOOMA_TEMPLE_WALL_VISUAL_CAPTURE_PASS straight_modules=",
		int(topology_counts.straight),
		" corners=0 pillars=0 output=",
		ProjectSettings.globalize_path(OUTPUT_PATH)
	)
	get_tree().quit(0)
