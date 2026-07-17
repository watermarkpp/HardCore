class_name MapPanel
extends Panel

const GothicUIThemeScript := preload("res://scripts/gothic_ui_theme.gd")

signal map_selected(map_id: int)
signal map_target_requested(map_id: int)
signal closed

const PANEL_SIZE := Vector2(1160, 650)
const MAP_CARD_SIZE := Vector2(226, 58)


class RoutePreview:
	extends Control

	var map_data: Dictionary = {}
	var content: Dictionary = {}


	func set_map_content(new_map_data: Dictionary, new_content: Dictionary) -> void:
		map_data = new_map_data.duplicate(true)
		content = new_content.duplicate(true)
		queue_redraw()


	func clear_map_content() -> void:
		map_data.clear()
		content.clear()
		queue_redraw()


	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color("090807"), true)
		draw_rect(Rect2(Vector2(1, 1), size - Vector2(2, 2)), Color("6a4d2f"), false, 2.0)
		var plot := Rect2(22, 20, size.x - 44.0, size.y - 62.0)
		for x_index in range(1, 6):
			var x := plot.position.x + plot.size.x * float(x_index) / 6.0
			draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), Color(0.48, 0.36, 0.23, 0.12), 1.0)
		for y_index in range(1, 4):
			var y := plot.position.y + plot.size.y * float(y_index) / 4.0
			draw_line(Vector2(plot.position.x, y), Vector2(plot.end.x, y), Color(0.48, 0.36, 0.23, 0.12), 1.0)
		if map_data.is_empty():
			draw_string(ThemeDB.fallback_font, Vector2(132, size.y * 0.5), "选择地图查看运行数据", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("a99479"))
			return
		var markers := _marker_records()
		var projected: Array[Dictionary] = _project_markers(markers, plot)
		var center := plot.get_center()
		draw_circle(center, 10.0, Color("27150c"))
		draw_arc(center, 12.0, 0.0, TAU, 32, Color("d2a05e"), 2.0)
		for marker: Dictionary in projected:
			if str(marker.get("kind", "")) == "portal":
				draw_line(center, marker.get("point", center), Color(0.65, 0.43, 0.20, 0.48), 2.0)
		for marker: Dictionary in projected:
			var point: Vector2 = marker.get("point", center)
			var kind := str(marker.get("kind", "spawn"))
			var color := {
				"portal": Color("d8a14b"),
				"npc": Color("d9c58a"),
				"boss": Color("b73c35"),
				"spawn": Color("805d3d"),
			}.get(kind, Color("805d3d")) as Color
			var radius := 7.0 if kind == "portal" else (6.0 if kind == "boss" else 4.0)
			draw_circle(point, radius, Color("100c09"))
			draw_arc(point, radius, 0.0, TAU, 20, color, 2.0)
			if kind == "portal":
				draw_line(point + Vector2(-5, 0), point + Vector2(5, 0), color, 1.0)
				draw_line(point + Vector2(0, -5), point + Vector2(0, 5), color, 1.0)
		var map_name := str(map_data.get("name", "未命名地图"))
		var footer := "%s　·　门点%d　NPC%d　怪物点%d　Boss%d" % [
			map_name,
			content.get("portals", []).size(),
			content.get("npcs", []).size(),
			content.get("spawns", []).size(),
			content.get("bosses", []).size(),
		]
		draw_string(ThemeDB.fallback_font, Vector2(22, size.y - 18), footer, HORIZONTAL_ALIGNMENT_LEFT, size.x - 44.0, 14, Color("c5a878"))


	func _marker_records() -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for group: String in ["portals", "npcs", "bosses", "spawns"]:
			var kind: String = str({"portals": "portal", "npcs": "npc", "bosses": "boss", "spawns": "spawn"}[group])
			for value: Variant in content.get(group, []):
				if value is Dictionary and value.has("position"):
					result.append({"kind": kind, "position": Vector2(value.get("position", Vector2.ZERO))})
					if result.size() >= 36:
						return result
		return result


	func _project_markers(markers: Array[Dictionary], plot: Rect2) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		if markers.is_empty():
			return result
		var minimum := Vector2(INF, INF)
		var maximum := Vector2(-INF, -INF)
		for marker: Dictionary in markers:
			var point: Vector2 = marker.get("position", Vector2.ZERO)
			minimum.x = minf(minimum.x, point.x)
			minimum.y = minf(minimum.y, point.y)
			maximum.x = maxf(maximum.x, point.x)
			maximum.y = maxf(maximum.y, point.y)
		var span := maximum - minimum
		span.x = maxf(span.x, 1.0)
		span.y = maxf(span.y, 1.0)
		for marker: Dictionary in markers:
			var point: Vector2 = marker.get("position", Vector2.ZERO)
			var normalized := (point - minimum) / span
			result.append({
				"kind": marker.get("kind", "spawn"),
				"point": plot.position + Vector2(normalized.x * plot.size.x, normalized.y * plot.size.y),
			})
		return result


var search_box: LineEdit
var later_toggle: CheckButton
var map_list: ItemList
var map_list_container: VBoxContainer
var detail_label: RichTextLabel
var count_label: Label
var map_name_label: Label
var preview_caption: Label
var route_preview: RoutePreview
var travel_button: Button
var target_button: Button
var map_entries: Array = []
var map_buttons: Array[Button] = []
var _selected_map_id := -1


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER)
	offset_left = -PANEL_SIZE.x * 0.5
	offset_top = -PANEL_SIZE.y * 0.5
	offset_right = PANEL_SIZE.x * 0.5
	offset_bottom = PANEL_SIZE.y * 0.5
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = GothicUIThemeScript.build()
	theme_type_variation = "GothicModalFrame"
	_build_modal_surface()
	_build_header()
	_build_map_list_section()
	_build_map_preview_section()
	_build_map_detail_section()
	_build_compatibility_list()
	refresh()


func _build_modal_surface() -> void:
	var surface := Panel.new()
	surface.name = "ModalSurface"
	surface.position = Vector2(18, 24)
	surface.size = Vector2(1124, 604)
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)


func _build_header() -> void:
	var title_frame := Panel.new()
	title_frame.name = "TitleFrame"
	title_frame.position = Vector2(350, 4)
	title_frame.size = Vector2(460, 64)
	title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_frame.theme_type_variation = "GothicTitleBar"
	add_child(title_frame)
	var title := Label.new()
	title.name = "TitleLabel"
	title.text = "世界地图"
	title.position = Vector2(30, 15)
	title.size = Vector2(400, 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("f1cc88"))
	title_frame.add_child(title)
	var close_button := Button.new()
	close_button.name = "CloseButton"
	close_button.text = "×"
	close_button.position = Vector2(1080, 8)
	close_button.size = Vector2(56, 56)
	close_button.theme_type_variation = "GothicComponentCloseButton"
	close_button.add_theme_font_size_override("font_size", 24)
	close_button.tooltip_text = "关闭"
	close_button.pressed.connect(_close)
	add_child(close_button)


func _build_map_list_section() -> void:
	var panel := _framed_section("MapListPanel", Rect2(20, 76, 270, 548))
	panel.add_child(_section_title("地图列表", 270))
	search_box = LineEdit.new()
	search_box.name = "SearchBox"
	search_box.placeholder_text = "搜索地图、地区或地图组"
	search_box.position = Vector2(18, 54)
	search_box.size = Vector2(234, 50)
	search_box.theme_type_variation = "GothicSearchField"
	search_box.text_changed.connect(func(_value: String) -> void: refresh())
	panel.add_child(search_box)
	later_toggle = CheckButton.new()
	later_toggle.name = "LaterContentToggle"
	later_toggle.text = "显示1.76后期地图"
	later_toggle.position = Vector2(18, 112)
	later_toggle.size = Vector2(234, 44)
	later_toggle.theme_type_variation = "GothicContentToggle"
	later_toggle.toggled.connect(_on_later_toggled)
	panel.add_child(later_toggle)
	var scroll := ScrollContainer.new()
	scroll.name = "MapListScroll"
	scroll.position = Vector2(18, 164)
	scroll.size = Vector2(234, 326)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	panel.add_child(scroll)
	map_list_container = VBoxContainer.new()
	map_list_container.name = "MapCards"
	map_list_container.custom_minimum_size = Vector2(226, 0)
	map_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_list_container.add_theme_constant_override("separation", 7)
	scroll.add_child(map_list_container)
	count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.position = Vector2(18, 500)
	count_label.size = Vector2(234, 24)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.theme_type_variation = "GothicMutedLabel"
	panel.add_child(count_label)


func _build_map_preview_section() -> void:
	var panel := _framed_section("MapPreviewPanel", Rect2(302, 76, 520, 548))
	panel.add_child(_section_title("地图预览与门点", 520))
	route_preview = RoutePreview.new()
	route_preview.name = "RoutePreview"
	route_preview.position = Vector2(24, 58)
	route_preview.size = Vector2(472, 400)
	route_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(route_preview)
	preview_caption = Label.new()
	preview_caption.name = "PreviewCaption"
	preview_caption.text = "运行数据投影 · 不替代原始地图地形"
	preview_caption.position = Vector2(24, 470)
	preview_caption.size = Vector2(472, 28)
	preview_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	preview_caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	preview_caption.theme_type_variation = "GothicMutedLabel"
	panel.add_child(preview_caption)
	var legend := Label.new()
	legend.name = "MarkerLegend"
	legend.text = "金：门点　骨白：NPC　暗红：Boss　棕：怪物点"
	legend.position = Vector2(24, 500)
	legend.size = Vector2(472, 24)
	legend.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	legend.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	legend.theme_type_variation = "GothicMutedLabel"
	panel.add_child(legend)


func _build_map_detail_section() -> void:
	var panel := _framed_section("MapDetailPanel", Rect2(834, 76, 306, 548))
	panel.add_child(_section_title("区域信息", 306))
	map_name_label = Label.new()
	map_name_label.name = "MapName"
	map_name_label.position = Vector2(24, 58)
	map_name_label.size = Vector2(258, 36)
	map_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	map_name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	map_name_label.add_theme_font_size_override("font_size", 21)
	map_name_label.add_theme_color_override("font_color", Color("f2c783"))
	panel.add_child(map_name_label)
	detail_label = RichTextLabel.new()
	detail_label.name = "MapDetail"
	detail_label.position = Vector2(24, 104)
	detail_label.size = Vector2(258, 330)
	detail_label.bbcode_enabled = true
	detail_label.fit_content = false
	detail_label.scroll_active = true
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.theme_type_variation = "GothicDetailText"
	detail_label.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(detail_label)
	target_button = Button.new()
	target_button.name = "TargetButton"
	target_button.text = "设为目标"
	target_button.position = Vector2(20, 452)
	target_button.size = Vector2(128, 54)
	target_button.theme_type_variation = "GothicComponentButton"
	target_button.add_theme_font_size_override("font_size", 16)
	target_button.disabled = true
	target_button.pressed.connect(_target_selected)
	panel.add_child(target_button)
	travel_button = Button.new()
	travel_button.name = "TravelButton"
	travel_button.text = "前往"
	travel_button.position = Vector2(158, 452)
	travel_button.size = Vector2(128, 54)
	travel_button.theme_type_variation = "GothicComponentSelectedButton"
	travel_button.add_theme_font_size_override("font_size", 17)
	travel_button.disabled = true
	travel_button.pressed.connect(_travel_selected)
	panel.add_child(travel_button)


func _build_compatibility_list() -> void:
	map_list = ItemList.new()
	map_list.name = "CompatibilityMapList"
	map_list.visible = false
	map_list.item_selected.connect(_show_selected)
	map_list.item_activated.connect(func(_index: int) -> void: _travel_selected())
	add_child(map_list)


func open_panel() -> void:
	later_toggle.set_pressed_no_signal(PlayerState.later_content_enabled)
	refresh()
	show()


func refresh() -> void:
	if map_list == null:
		return
	map_entries.clear()
	map_list.clear()
	var query := search_box.text.strip_edges().to_lower()
	for map_data: Variant in GameData.get_available_maps(PlayerState.later_content_enabled):
		if not map_data is Dictionary:
			continue
		var searchable := "%s %s %s" % [map_data.get("name", ""), map_data.get("region", ""), map_data.get("mapGroup", "")]
		if not query.is_empty() and query not in searchable.to_lower():
			continue
		map_entries.append(map_data)
		var later_marker := "［后期］" if str(map_data.get("versionTag", "")).begins_with("1.76后期") else ""
		map_list.add_item("%s%s　%s" % [later_marker, map_data.get("name", "未命名"), map_data.get("mapGroup", "")])
	_rebuild_map_cards()
	count_label.text = "显示 %d / 数据库 %d 张" % [map_entries.size(), GameData.maps.size()]
	var selected_index := _index_for_map_id(_selected_map_id)
	if selected_index >= 0:
		map_list.select(selected_index)
		_show_selected(selected_index)
	else:
		_selected_map_id = -1
		map_name_label.text = "请选择地图"
		detail_label.text = "[color=#a99479]从左侧目录选择区域，查看地图资料、门点、NPC、怪物与Boss运行数据。[/color]"
		route_preview.clear_map_content()
		target_button.disabled = true
		travel_button.disabled = true


func _rebuild_map_cards() -> void:
	for child: Node in map_list_container.get_children():
		child.queue_free()
	map_buttons.clear()
	for index in range(map_entries.size()):
		var map_data: Dictionary = map_entries[index]
		var button := Button.new()
		button.name = "MapCard_%d" % int(map_data.get("mapId", -1))
		button.custom_minimum_size = MAP_CARD_SIZE
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.text = ""
		button.set_pressed_no_signal(int(map_data.get("mapId", -1)) == _selected_map_id)
		button.theme_type_variation = "GothicComponentSelectedButton" if int(map_data.get("mapId", -1)) == _selected_map_id else "GothicComponentButton"
		button.pressed.connect(_select_map.bind(index))
		button.set_meta("map_id", int(map_data.get("mapId", -1)))
		var name_label := Label.new()
		name_label.name = "MapName"
		name_label.text = str(map_data.get("name", "未命名"))
		name_label.position = Vector2(16, 6)
		name_label.size = Vector2(194, 26)
		name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name_label.add_theme_font_size_override("font_size", 16)
		button.add_child(name_label)
		var group_label := Label.new()
		group_label.name = "MapGroup"
		var later_marker := "后期 · " if str(map_data.get("versionTag", "")).begins_with("1.76后期") else ""
		group_label.text = "%s%s" % [later_marker, map_data.get("mapGroup", map_data.get("region", "未分类"))]
		group_label.position = Vector2(16, 32)
		group_label.size = Vector2(194, 20)
		group_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		group_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		group_label.add_theme_font_size_override("font_size", 13)
		group_label.add_theme_color_override("font_color", Color("c5a878"))
		button.add_child(group_label)
		map_list_container.add_child(button)
		map_buttons.append(button)


func _select_map(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	map_list.select(index)
	_show_selected(index)


func _show_selected(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	var map_data: Dictionary = map_entries[index]
	_selected_map_id = int(map_data.get("mapId", -1))
	for button_index in range(map_buttons.size()):
		var button := map_buttons[button_index]
		var selected := button_index == index
		button.set_pressed_no_signal(selected)
		button.theme_type_variation = "GothicComponentSelectedButton" if selected else "GothicComponentButton"
	var content := RegionContent.get_map_content(_selected_map_id)
	var bosses := GameData.get_bosses_for_map(map_data)
	var boss_names: Array[String] = []
	for boss: Variant in bosses:
		var boss_name := str(boss.get("name", "Boss"))
		if not boss_names.has(boss_name):
			boss_names.append(boss_name)
	for boss: Variant in content.get("bosses", []):
		if boss is Dictionary and not boss_names.has(str(boss.get("name", "Boss"))):
			boss_names.append(str(boss.get("name", "Boss")))
	map_name_label.text = str(map_data.get("name", "未命名地图"))
	detail_label.text = "[color=#d8c8ae]地区：%s\n地图组：%s\n版本：%s\n\n资料ID：%s\n运行时ID：%d\n资料状态：%s\n可信度：%s\n\n门点：%d　NPC：%d\n怪物点：%d\n关联Boss：%s[/color]" % [
		map_data.get("region", "未分类"),
		map_data.get("mapGroup", "未分类"),
		map_data.get("versionTag", "未标注"),
		_source_id_label(map_data.get("sourceMapId", map_data.get("mapId", -1))),
		_selected_map_id,
		map_data.get("recordStatus", content.get("status", "未标注")),
		map_data.get("confidence", "?"),
		content.get("portals", []).size(),
		content.get("npcs", []).size(),
		content.get("spawns", []).size(),
		"、".join(boss_names) if not boss_names.is_empty() else "暂无可靠关联",
	]
	route_preview.set_map_content(map_data, content)
	target_button.disabled = false
	travel_button.disabled = false


func _travel_selected() -> void:
	var selected := map_list.get_selected_items()
	if selected.is_empty() or selected[0] >= map_entries.size():
		detail_label.text = "[color=#c98970]请先选择地图。[/color]"
		return
	var map_id := int(map_entries[selected[0]].get("mapId", -1))
	if map_id != -1:
		map_selected.emit(map_id)
		hide()


func _target_selected() -> void:
	if _selected_map_id > 0:
		map_target_requested.emit(_selected_map_id)
		target_button.text = "已设为目标"


func _on_later_toggled(enabled: bool) -> void:
	PlayerState.set_later_content_enabled(enabled)
	refresh()


func _index_for_map_id(map_id: int) -> int:
	for index in range(map_entries.size()):
		if int(map_entries[index].get("mapId", -1)) == map_id:
			return index
	return -1


func _source_id_label(value: Variant) -> String:
	if value is float and is_equal_approx(float(value), roundf(float(value))):
		return str(int(value))
	return str(value)


func _framed_section(node_name: String, rect: Rect2) -> Panel:
	var surface := Panel.new()
	surface.name = "%sSurface" % node_name
	surface.position = rect.position
	surface.size = rect.size
	surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.theme_type_variation = "GothicModalSurface"
	add_child(surface)
	var frame := Panel.new()
	frame.name = node_name
	frame.position = rect.position
	frame.size = rect.size
	frame.theme_type_variation = "GothicInsetFrame"
	add_child(frame)
	return frame


func _section_title(text_value: String, section_width: float) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = Vector2(24, 18)
	label.size = Vector2(section_width - 48.0, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.theme_type_variation = "GothicSectionTitle"
	return label


func _close() -> void:
	hide()
	closed.emit()
