extends Control

const OUTPUT_PATH := "res://outputs/visual_acceptance/warehouse/warehouse_gothic_sample_v1.png"
const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")


func _ready() -> void:
	_build_background()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for item_name: String in [
		"太阳水", "匕首", "布衣(男)", "古铜戒指", "木剑", "黑铁头盔",
		"绿色项链", "骑士手镯", "力量戒指", "裁决之杖",
	]:
		PlayerState.add_item(item_name)
	PlayerState.warehouse_inventory = [
		PlayerState.inventory.pop_back(),
		PlayerState.inventory.pop_back(),
		PlayerState.inventory.pop_back(),
		PlayerState.inventory.pop_back(),
	]
	var panel := WarehousePanel.new()
	panel.name = "WarehousePanel"
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	panel._select_item("bag", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path(OUTPUT_PATH.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	assert(error == OK, "无法保存仓库哥特样板")
	print("WAREHOUSE_GOTHIC_PREVIEW_CAPTURE_PASS output=%s" % OUTPUT_PATH)
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
