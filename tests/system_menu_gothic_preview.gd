extends Control

const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_reference.png")
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")
const MAIN_OUTPUT := "res://outputs/visual_acceptance/system_menu/system_menu_gothic_v1.png"
const SETTINGS_OUTPUT := "res://outputs/visual_acceptance/system_menu/system_settings_audio_v1.png"


func _ready() -> void:
	var world := TextureRect.new()
	world.name = "WorldBackdrop"
	world.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	world.texture = WORLD_TEXTURE
	world.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	world.stretch_mode = TextureRect.STRETCH_SCALE
	world.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(world)
	var menu: Control = SystemMenuPanelScript.new()
	menu.name = "SystemMenu"
	add_child(menu)
	await get_tree().process_frame
	await get_tree().process_frame
	_save_viewport(MAIN_OUTPUT)
	menu.show_settings_page()
	menu.set_audio_settings(true, false)
	await get_tree().process_frame
	_save_viewport(SETTINGS_OUTPUT)
	print("SYSTEM_MENU_GOTHIC_PREVIEW_CAPTURE_PASS main=%s settings=%s" % [MAIN_OUTPUT, SETTINGS_OUTPUT])
	get_tree().quit(0)


func _save_viewport(path: String) -> void:
	var output_dir := ProjectSettings.globalize_path(path.get_base_dir())
	DirAccess.make_dir_recursive_absolute(output_dir)
	var error := get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path(path))
	assert(error == OK, "无法保存系统菜单哥特样板：%s" % path)
