extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := MapPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	await get_tree().process_frame
	assert(panel.size == Vector2(1160, 650), "地图面板没有使用既定横屏底板尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "地图面板没有复用公共哥特外框")
	assert(panel.get_node("MapListPanel").theme_type_variation == "GothicInsetFrame", "地图列表没有复用公共内框")
	assert(panel.get_node("MapPreviewPanel").theme_type_variation == "GothicInsetFrame", "地图预览没有复用公共内框")
	assert(panel.get_node("MapDetailPanel").theme_type_variation == "GothicInsetFrame", "地图资料没有复用公共内框")
	assert(panel.search_box.theme_type_variation == "GothicSearchField", "地图搜索没有使用公共哥特输入框")
	assert(panel.later_toggle.theme_type_variation == "GothicContentToggle", "后期内容开关没有使用公共哥特样式")
	assert(panel.map_entries.size() == 129 and panel.map_buttons.size() == 129, "地图目录默认筛选或自定义地图卡数量错误")
	assert(not panel.map_list.visible and panel.map_list.item_count == 129, "地图兼容选择列表异常")
	panel.search_box.text = "沃玛寺庙"
	panel.refresh()
	var selected_index := -1
	for index in range(panel.map_entries.size()):
		if int(panel.map_entries[index].get("mapId", -1)) == 315:
			selected_index = index
			break
	assert(selected_index >= 0, "地图搜索没有找到沃玛寺庙核心地图")
	panel._select_map(selected_index)
	assert(panel._selected_map_id == 315 and panel.map_list.get_selected_items() == PackedInt32Array([selected_index]), "自定义地图卡没有同步现有地图选择接口")
	assert("沃玛寺庙" in panel.map_name_label.text and "资料ID：315\n运行时ID：315" in panel.detail_label.text, "地图详情没有规范显示真实地图资料ID")
	assert(not panel.route_preview.content.is_empty() and panel.route_preview.content.get("portals", []).size() >= 1, "地图预览没有读取运行时门点数据")
	assert(not panel.target_button.disabled and not panel.travel_button.disabled, "选择地图后目标与前往按钮没有启用")
	var target_ids: Array[int] = []
	var travel_ids: Array[int] = []
	panel.map_target_requested.connect(func(map_id: int) -> void: target_ids.append(map_id))
	panel.map_selected.connect(func(map_id: int) -> void: travel_ids.append(map_id))
	panel._target_selected()
	assert(target_ids == [315] and panel.target_button.text == "已设为目标", "设为目标没有发送稳定地图ID")
	panel.show()
	panel._travel_selected()
	assert(travel_ids == [315] and not panel.visible, "前往按钮没有保留地图选择信号")
	panel.search_box.text = ""
	panel.later_toggle.button_pressed = true
	await get_tree().process_frame
	assert(PlayerState.later_content_enabled and panel.map_entries.size() == 142, "后期内容开关没有保留129/142地图筛选")
	print("MAP_GOTHIC_UI_PASS：三栏底板、公共Theme、129/142目录、运行门点、目标与前往接口均正常")
	get_tree().quit(0)
