class_name MapPanel
extends Panel

signal map_selected(map_id: int)
signal closed

var search_box: LineEdit
var later_toggle: CheckButton
var map_list: ItemList
var detail_label: Label
var count_label: Label
var map_entries: Array = []


func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -440
	offset_top = -310
	offset_right = 440
	offset_bottom = 310
	z_index = 75
	mouse_filter = Control.MOUSE_FILTER_STOP
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.045, 0.035, 0.03, 0.985)
	style.border_color = Color(0.58, 0.40, 0.21)
	style.set_border_width_all(3)
	add_theme_stylebox_override("panel", style)

	var title := Label.new()
	title.text = "玛法地图目录"
	title.position = Vector2(28, 20)
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_color_override("font_color", Color(0.96, 0.76, 0.42))
	add_child(title)

	search_box = LineEdit.new()
	search_box.placeholder_text = "搜索地图、地区或地图组"
	search_box.position = Vector2(28, 68)
	search_box.size = Vector2(410, 46)
	search_box.text_changed.connect(func(_value: String) -> void: refresh())
	add_child(search_box)

	later_toggle = CheckButton.new()
	later_toggle.text = "启用1.76后期追加内容"
	later_toggle.position = Vector2(470, 68)
	later_toggle.size = Vector2(350, 46)
	later_toggle.toggled.connect(_on_later_toggled)
	add_child(later_toggle)

	map_list = ItemList.new()
	map_list.position = Vector2(28, 130)
	map_list.size = Vector2(410, 390)
	map_list.item_selected.connect(_show_selected)
	map_list.item_activated.connect(func(_index: int) -> void: _travel_selected())
	add_child(map_list)

	detail_label = Label.new()
	detail_label.position = Vector2(470, 140)
	detail_label.size = Vector2(365, 290)
	detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_label.add_theme_font_size_override("font_size", 18)
	add_child(detail_label)

	count_label = Label.new()
	count_label.position = Vector2(28, 535)
	count_label.size = Vector2(410, 34)
	count_label.add_theme_color_override("font_color", Color(0.75, 0.68, 0.58))
	add_child(count_label)

	var travel_button := Button.new()
	travel_button.text = "进入地图"
	travel_button.position = Vector2(470, 455)
	travel_button.size = Vector2(170, 58)
	travel_button.pressed.connect(_travel_selected)
	add_child(travel_button)

	var close_button := Button.new()
	close_button.text = "关闭"
	close_button.position = Vector2(660, 455)
	close_button.size = Vector2(170, 58)
	close_button.pressed.connect(_close)
	add_child(close_button)


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
	count_label.text = "显示 %d / 数据库 %d 张地图" % [map_entries.size(), GameData.maps.size()]
	detail_label.text = "选择地图查看资料。\n\n当前阶段：未完成地形考据的地图使用程序临时场景，不计入最终复刻完成数。"


func _show_selected(index: int) -> void:
	if index < 0 or index >= map_entries.size():
		return
	var map_data: Dictionary = map_entries[index]
	var bosses := GameData.get_bosses_for_map(map_data)
	var boss_names: Array[String] = []
	for boss: Variant in bosses:
		boss_names.append(str(boss.get("name", "Boss")))
	detail_label.text = "%s（资料ID %s｜运行时ID %d）\n地区：%s\n地图组：%s\n版本：%s\n默认启用：%s\n资料状态：%s\n可信度：%s\n关联Boss：%s\n\n运行时状态：程序临时场景" % [
		map_data.get("name", ""), str(map_data.get("sourceMapId", map_data.get("mapId", -1))), int(map_data.get("mapId", -1)), map_data.get("region", ""), map_data.get("mapGroup", ""),
		map_data.get("versionTag", ""), "是" if bool(map_data.get("availabilityDefault", true)) else "否",
		map_data.get("recordStatus", ""), map_data.get("confidence", ""), "、".join(boss_names) if not boss_names.is_empty() else "暂无可靠关联",
	]


func _travel_selected() -> void:
	var selected := map_list.get_selected_items()
	if selected.is_empty() or selected[0] >= map_entries.size():
		detail_label.text = "请先选择地图。"
		return
	var map_id := int(map_entries[selected[0]].get("mapId", -1))
	if map_id != -1:
		map_selected.emit(map_id)
		hide()


func _on_later_toggled(enabled: bool) -> void:
	PlayerState.set_later_content_enabled(enabled)
	refresh()


func _close() -> void:
	hide()
	closed.emit()
