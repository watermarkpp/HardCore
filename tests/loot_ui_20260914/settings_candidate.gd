extends "res://tests/ui_layout_calibration_workbench.gd"

## Review-only candidate. No runtime/manual profile is changed by this scene.
func _ready() -> void:
	await super._ready()
	await _show_panel(8)
	panel_picker.select(8)
	var panel: Control = game.get("_system_menu_panel")
	apply_candidate(panel)
	overlay.hide()
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var path := "res://outputs/ui_calibration/loot_ui_20260914/settings_candidate.png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert(get_viewport().get_texture().get_image().save_png(path) == OK)
	print("SETTINGS_CANDIDATE_READY ", path)

static func apply_candidate(panel: Control) -> void:
	var page: Control = panel.get("settings_page")
	var title_frame := page.get_node("SettingsPageTitleFrame") as Control
	title_frame.position.y = 66.0
	var title := title_frame.get_node("Title") as Label
	title.text = "游戏设置"
	title.show()
	title_frame.get_node("Subtitle").hide()
	page.get_node("MusicVolume").position.y = 148.0
	page.get_node("SFXVolume").position.y = 230.0
	var filter := page.get_node("LootFilter") as Control
	filter.position.y = 312.0
	filter.size.y = 100.0
	var caption := filter.get_node("Caption") as Label
	caption.position = Vector2(20, 12)
	caption.size = Vector2(316, 22)
	var slider := filter.get_node("Slider") as HSlider
	slider.position = Vector2(70, 36)
	slider.size = Vector2(216, 28)
	var index := 0
	for child in filter.get_children():
		if child is Label and child.name not in [&"Caption", &"Percent"]:
			child.position = Vector2(16 + index * 108, 68)
			child.size = Vector2(108, 20)
			child.add_theme_font_size_override("font_size", 11)
			index += 1
	panel.get("audio_save_note").hide()
	panel.get("settings_back_button").position = Vector2(72, 430)
	panel.get("settings_back_button").size = Vector2(356, 60)
