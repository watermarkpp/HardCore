extends Control

const OUTPUT_PATH := "res://outputs/visual_acceptance/map/map_world_tree_cow_temple_v2.png"
const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")
const COW_TEMPLE_FLOOR_ONE_ID := 3246


func _ready() -> void:
	_build_background()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := MapPanel.new()
	panel.name = "MapPanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	panel._select_world_node("cow_temple")
	panel.set_teleport_availability({
		COW_TEMPLE_FLOOR_ONE_ID: {
			"enabled": true,
			"destination_map_id": COW_TEMPLE_FLOOR_ONE_ID,
			"arrival_anchor_id": "cow_temple.floor1.exit",
			"destination_label": "牛魔寺庙一层出口",
			"reason": "",
			"rule_id": "preview.cow_temple.floor1",
		},
	})
	var floor_one_index := panel._index_for_map_id(COW_TEMPLE_FLOOR_ONE_ID)
	assert(floor_one_index >= 0, "牛魔寺庙一层没有出现在视觉样板")
	panel._select_map(floor_one_index)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存世界地图树哥特样板")
	print("MAP_GOTHIC_PREVIEW_CAPTURE_PASS output=%s" % OUTPUT_PATH)
	get_tree().quit(0)


func _build_background() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var dim := ColorRect.new()
	dim.name = "ModalDim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.008, 0.006, 0.005, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
