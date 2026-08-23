extends SceneTree

const ThemeScript := preload("res://scripts/gothic_ui_theme.gd")

func _init() -> void:
	var root := Control.new()
	root.size = Vector2(900, 700)
	root.theme = ThemeScript.build()
	root.modulate = Color.WHITE
	var viewport := SubViewport.new()
	viewport.size = Vector2i(900, 700)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(viewport)
	viewport.add_child(root)
	var background := ColorRect.new()
	background.color = Color("14110f")
	background.size = root.size
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(background)
	var title := Label.new()
	title.text = "Gothic v4 按钮规格预览"
	title.position = Vector2(24, 18)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.add_theme_font_size_override("font_size", 22)
	root.add_child(title)
	var specs := [["短按钮", Vector2(24, 75), Vector2(120,48)], ["紧凑按钮", Vector2(170,75), Vector2(160,48)], ["标准操作按钮", Vector2(24,155), Vector2(260,56)], ["宽按钮与较长文字", Vector2(24,245), Vector2(440,56)]]
	for row in specs:
		_add_button(root, row[0], row[1], row[2], false, false)
	_add_button(root, "按下状态", Vector2(500,155), Vector2(260,56), true, false)
	_add_button(root, "禁用状态", Vector2(500,245), Vector2(260,56), false, true)
	var frame := Panel.new()
	frame.position = Vector2(520, 350)
	frame.size = Vector2(340, 220)
	frame.theme_type_variation = "GothicInsetFrame"
	root.add_child(frame)
	var inside := Label.new()
	inside.text = "二级装饰框\n内容安全区域"
	inside.position = Vector2(100, 92)
	inside.add_theme_color_override("font_color", Color.WHITE)
	frame.add_child(inside)
	await process_frame
	await process_frame
	await process_frame
	var image := viewport.get_texture().get_image()
	image.save_png("outputs/ui_preview_gothic_button_family_v4.png")
	print("GOTHIC_BUTTON_FAMILY_PREVIEW_PASS path=outputs/ui_preview_gothic_button_family_v4.png")
	quit()

func _add_button(root: Control, label: String, pos: Vector2, button_size: Vector2, pressed: bool, disabled: bool) -> void:
	var button := Button.new()
	button.text = label
	button.position = pos
	button.size = button_size
	button.theme_type_variation = "GothicComponentButton"
	button.toggle_mode = pressed
	button.disabled = disabled
	button.set_pressed_no_signal(pressed)
	root.add_child(button)
