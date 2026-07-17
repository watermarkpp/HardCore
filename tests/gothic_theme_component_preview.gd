extends Node

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")
const WORLD_TEXTURE := preload("res://assets/ui/gothic_preview/world_scene_clean.png")

var stage: Control


func _ready() -> void:
	_build_preview()
	if OS.get_environment("GOTHIC_THEME_CAPTURE") == "1":
		_capture.call_deferred()


func _build_preview() -> void:
	var background := TextureRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.texture = WORLD_TEXTURE
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.modulate = Color(0.34, 0.31, 0.29, 1.0)
	add_child(background)

	stage = Control.new()
	stage.name = "GothicThemeComponentPreview"
	stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage.theme = GothicUIThemeScript.build()
	add_child(stage)

	_add_panel("ModalSurface", Rect2(36, 18, 1208, 684), "GothicModalSurface")
	_add_panel("ModalFrame", Rect2(36, 18, 1208, 684), "GothicModalFrame")
	_add_panel("TitleBar", Rect2(88, 44, 1104, 84), "GothicTitleBar")
	_add_label("公共哥特 Theme · 组件样板 V1", Rect2(120, 58, 1040, 50), 27, Color("f1d3a1"), HORIZONTAL_ALIGNMENT_CENTER)

	var tab_names := ["背包", "商店", "任务", "技能"]
	for index in range(tab_names.size()):
		var tab := _add_button(tab_names[index], Rect2(122 + index * 166, 139, 152, 54), "GothicComponentTabButton")
		if index == 1:
			tab.theme_type_variation = "GothicComponentSelectedButton"
	_add_label("所有中文均由 Godot 实时排版；框体负责材质与状态。", Rect2(800, 147, 365, 38), 14, Color("b9a88e"), HORIZONTAL_ALIGNMENT_RIGHT)

	_build_button_sample()
	_build_slot_sample()
	_build_shop_sample()

	var close_button := _add_button("×", Rect2(1154, 32, 70, 70), "GothicComponentCloseButton")
	close_button.add_theme_font_size_override("font_size", 29)


func _build_button_sample() -> void:
	_add_panel("ButtonSampleSurface", Rect2(74, 210, 330, 444), "GothicModalSurface")
	_add_panel("ButtonSampleFrame", Rect2(74, 210, 330, 444), "GothicInsetFrame")
	_add_label("按钮与状态", Rect2(104, 230, 270, 34), 20, Color("e8c88f"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_button("普通按钮", Rect2(104, 282, 270, 62), "GothicComponentButton")
	_add_button("高亮 / 已选择", Rect2(104, 358, 270, 62), "GothicComponentSelectedButton")
	var disabled := _add_button("禁用状态", Rect2(104, 434, 270, 62), "GothicComponentButton")
	disabled.disabled = true
	_add_button("危险操作", Rect2(104, 510, 270, 62), "GothicComponentSelectedButton")
	_add_label("统一 56px 以上触控高度", Rect2(104, 590, 270, 28), 14, Color("aa967b"), HORIZONTAL_ALIGNMENT_CENTER)


func _build_slot_sample() -> void:
	_add_panel("SlotSampleSurface", Rect2(420, 210, 350, 444), "GothicModalSurface")
	_add_panel("SlotSampleFrame", Rect2(420, 210, 350, 444), "GothicInsetFrame")
	_add_label("插槽 / 分页 / 详情框", Rect2(446, 230, 298, 34), 20, Color("e8c88f"), HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(6):
		var slot := _add_button(str(index + 1), Rect2(451 + (index % 3) * 94, 282 + (index / 3) * 112, 82, 96), "GothicComponentSlotButton")
		slot.add_theme_font_size_override("font_size", 15)
	_add_panel("MiniTab", Rect2(454, 518, 282, 52), "GothicTabFrame")
	_add_label("物品说明 / 属性比较", Rect2(470, 527, 250, 32), 16, Color("d9c19a"), HORIZONTAL_ALIGNMENT_CENTER)
	_add_label("角饰固定，中心区域安全拉伸", Rect2(448, 590, 294, 26), 14, Color("aa967b"), HORIZONTAL_ALIGNMENT_CENTER)


func _build_shop_sample() -> void:
	_add_panel("ShopSampleSurface", Rect2(786, 210, 420, 444), "GothicModalSurface")
	_add_panel("ShopSampleFrame", Rect2(786, 210, 420, 444), "GothicInsetFrame")
	_add_label("双格商品卡 / 列表", Rect2(816, 230, 360, 34), 20, Color("e8c88f"), HORIZONTAL_ALIGNMENT_CENTER)
	for index in range(3):
		var card := _add_button("", Rect2(816, 278 + index * 100, 360, 91), "GothicComponentShopCard")
		var icon := ColorRect.new()
		icon.position = Vector2(28, 21)
		icon.size = Vector2(48, 48)
		icon.color = [Color("7e2730"), Color("264d78"), Color("80632d")][index]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(icon)
		var name_label := Label.new()
		name_label.position = Vector2(118, 17)
		name_label.size = Vector2(218, 30)
		name_label.text = ["金创药（中量）", "魔法药（中量）", "回城卷"][index]
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(name_label)
		var price_label := Label.new()
		price_label.position = Vector2(118, 49)
		price_label.size = Vector2(218, 25)
		price_label.text = ["300 金币", "350 金币", "1000 金币"][index]
		price_label.add_theme_font_size_override("font_size", 13)
		price_label.add_theme_color_override("font_color", Color("b99a67"))
		price_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(price_label)
	_add_button("购买", Rect2(816, 580, 172, 56), "GothicComponentSelectedButton")
	_add_button("关闭", Rect2(1004, 580, 172, 56), "GothicComponentButton")


func _add_panel(node_name: String, rect: Rect2, variation: StringName) -> Panel:
	var panel := Panel.new()
	panel.name = node_name
	panel.position = rect.position
	panel.size = rect.size
	panel.theme_type_variation = variation
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(panel)
	return panel


func _add_button(text_value: String, rect: Rect2, variation: StringName) -> Button:
	var button := Button.new()
	button.text = text_value
	button.position = rect.position
	button.size = rect.size
	button.theme_type_variation = variation
	button.add_theme_font_size_override("font_size", 17)
	stage.add_child(button)
	return button


func _add_label(text_value: String, rect: Rect2, font_size: int, color: Color, alignment: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = rect.position
	label.size = rect.size
	label.horizontal_alignment = alignment
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(label)
	return label


func _capture() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var output_dir := ProjectSettings.globalize_path("res://outputs/visual_acceptance/gothic_theme")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("gothic_theme_component_sample_v1.png")
	assert(get_viewport().get_texture().get_image().save_png(output_path) == OK)
	print("GOTHIC_THEME_COMPONENT_CAPTURE_PASS output=%s" % output_path)
	get_tree().quit(0)
