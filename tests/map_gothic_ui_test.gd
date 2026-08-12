extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/world_map_teleport_contract.json"
const UI_LAYOUT_CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"
const COW_TEMPLE_FLOOR_ONE_ID := 3246
const COW_TEMPLE_FLOOR_TWO_ID := 3247


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var contract_text := FileAccess.get_file_as_string(CONTRACT_PATH)
	var contract: Variant = JSON.parse_string(contract_text)
	assert(contract is Dictionary, "世界地图传送契约无法解析")
	assert(contract.get("contractId", "") == "ui.map.teleport.v1", "世界地图传送契约 ID 不稳定")
	assert("UI never decides" in str(contract.get("policy", "")), "传送开放规则不应由 UI 决定")

	var panel := MapPanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	await get_tree().process_frame

	assert(panel.size == Vector2(1160, 650), "地图面板没有使用既定横屏底板尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "地图面板没有复用公共哥特外框")
	assert(panel.get_node("MapListPanel").theme_type_variation == "GothicInsetFrame", "地图列表没有复用公共内框")
	assert(panel.get_node("MapPreviewPanel").theme_type_variation == "GothicInsetFrame", "世界地图树没有复用公共内框")
	assert(panel.get_node("MapDetailPanel").theme_type_variation == "GothicInsetFrame", "地图资料没有复用公共内框")
	assert(panel.search_box == null and panel.later_toggle == null and panel.count_label == null, "Search/Later/Count 控件必须删除")
	var map_scroll := panel.get_node("MapListPanel/MapListScroll") as ScrollContainer
	var layout_contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT_CONTRACT))
	var saved_scroll: Array = layout_contract["profiles"]["map"]["nodes"]["MapListPanel/MapListScroll"]["logicalRect"]
	assert(map_scroll.position.is_equal_approx(Vector2(float(saved_scroll[0]), float(saved_scroll[1]))) and map_scroll.size.is_equal_approx(Vector2(float(saved_scroll[2]), float(saved_scroll[3]))), "MapListScroll 几何必须与正式校准合同一致")
	assert(map_scroll.get_meta("calibration_layout_dependencies") == ["MapListPanel/SearchBox", "MapListPanel/LaterContentToggle", "MapListPanel/CountLabel"], "滚动区依赖元数据错误")
	assert(panel._selected_world_node_id == "bich_province" and panel.map_entries.size() < 129, "默认必须是首个过滤大区")
	var hint := panel.get_node("MapPreviewPanel/WorldTreeHint") as Label
	assert(hint.position.x >= 0.0 and hint.position.y >= 0.0 and hint.size.x > 0.0 and hint.size.y >= 18.0, "世界树提示必须为有效矩形")
	var tree_scroll := panel.get_node("MapPreviewPanel/WorldTreeScroll") as ScrollContainer
	var tree_frame := panel.get_node("MapPreviewPanel/MapListV3Frame") as Control
	assert(tree_frame.get_index() < tree_scroll.get_index() and tree_frame.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	var tree_decoration := tree_frame.get_node("MapListV3FrameDecoration") as Control
	var tree_fill := tree_decoration.get_node("MapListV3FrameFill") as GothicFrameFill
	var tree_frame_panel := tree_decoration.get_node("MapListV3FrameFrame") as Panel
	assert(tree_fill.shape_mode == GothicFrameFill.ShapeMode.V3_INNER and tree_fill.mouse_filter == Control.MOUSE_FILTER_IGNORE and tree_frame_panel.mouse_filter == Control.MOUSE_FILTER_IGNORE)
	assert(tree_scroll.position.x >= 0.0 and tree_scroll.position.y >= 0.0 and tree_scroll.size.x > 0.0 and tree_scroll.size.y > 0.0, "世界树滚动区必须为有效矩形")
	assert(tree_scroll.get_meta("calibration_layout_revision") == 1, "世界树布局版本错误")
	var expected_pairs: Dictionary = {}
	var expected_regions: Dictionary = {}
	for map_value: Variant in GameData.get_available_maps(false):
		if map_value is Dictionary:
			expected_regions[str(map_value.get("region", ""))] = true
			expected_pairs["%s|%s" % [map_value.get("region", ""), map_value.get("mapGroup", "")]] = true
	var actual_pairs: Dictionary = {}
	var actual_regions: Dictionary = {}
	for node_value: Variant in panel.world_tree_nodes:
		var node_data: Dictionary = node_value
		var node_depth := int(node_data.get("depth", -1))
		assert(node_depth in [0, 1], "运行时目录出现非法深度")
		if node_depth == 0:
			actual_regions[str(node_data.get("regions", [""])[0])] = true
		elif node_depth == 1:
			actual_pairs["%s|%s" % [node_data.get("regions", [""])[0], node_data.get("map_groups", [""])[0]]] = true
	assert(actual_regions.size() == expected_regions.size(), "目录 region 数量与正式数据不一致")
	for expected_region: Variant in expected_regions.keys():
		assert(actual_regions.has(expected_region), "目录缺少正式 region：%s" % expected_region)
	assert(actual_pairs.size() == expected_pairs.size(), "目录 group 集合与正式数据不一致")
	for expected_pair: Variant in expected_pairs.keys():
		assert(actual_pairs.has(expected_pair), "目录缺少正式 region/group：%s" % expected_pair)
	var bich_groups: Array[String] = []
	for node_value: Variant in panel.world_tree_nodes:
		var node_data: Dictionary = node_value
		if int(node_data.get("depth", -1)) == 1 and node_data.get("regions", [""])[0] == "比奇地区":
			bich_groups.append(str(node_data.get("label", "")))
	assert(bich_groups.size() == 4 and bich_groups.has("地表/入口") and bich_groups.has("兽人古墓") and bich_groups.has("天然洞穴") and bich_groups.has("比奇矿区"), "比奇子组目录不完整")
	assert(panel.map_entries.size() == 19 and panel._selected_map_id == int(panel.map_entries[0].get("mapId", -1)), "比奇区域应为19图并自动选择首图")
	assert(not panel.map_name_label.text.is_empty() and not panel.detail_label.text.contains("请选择地图"), "默认地图详情未同步")
	var node_ids: Dictionary = {}
	for node_value: Variant in panel.world_tree_nodes:
		var node_data: Dictionary = node_value
		var node_id := str(node_data.get("node_id", ""))
		assert(not node_ids.has(node_id), "目录节点 ID 重复")
		node_ids[node_id] = true
	assert(panel.world_node_buttons.size() == node_ids.size(), "世界树按钮 ID 冲突")
	for button_value: Variant in panel.world_node_buttons.values():
		assert(not str((button_value as Button).name).contains("@"), "世界树出现自动节点名")
	assert(panel.world_tree_container.get_theme_constant("separation") == 7, "世界地图节点间距没有与左侧地图卡保持一致")
	assert(not panel.world_node_buttons.has("mafa_world"), "世界根节点不应可选")
	var reference_world_button := panel.world_node_buttons["bich_province"] as Button
	for world_button_value: Variant in panel.world_node_buttons.values():
		var world_button := world_button_value as Button
		assert(world_button.position == reference_world_button.position, "世界地图节点装饰框左边缘不一致")
		assert(world_button.size == reference_world_button.size, "世界地图节点装饰框尺寸不一致")
		assert(world_button.alignment == HORIZONTAL_ALIGNMENT_CENTER, "世界地图名称没有相对装饰框水平居中")
	assert((panel.world_node_buttons["cangyue_island"] as Button).position.x == 12.0, "苍月岛装饰框左侧出现异常突出")
	var total_maps := GameData.get_available_maps(true).size()
	for node_id: Variant in panel.world_node_buttons.keys():
		panel._select_world_node(str(node_id))
		assert(panel.map_entries.size() > 0 and panel.map_entries.size() < total_maps, "节点筛选为空或回退全量")
		var filter_node := panel._world_node(str(node_id))
		for map_data: Dictionary in panel.map_entries:
			assert(panel._node_matches_map(filter_node, map_data), "节点列表含不匹配地图")

	var requested_batches: Array = []
	panel.teleport_availability_requested.connect(
		func(map_ids: Array) -> void: requested_batches.append(map_ids.duplicate())
	)
	panel._select_world_node("cow_temple")
	await get_tree().process_frame
	assert(panel._selected_world_node_id == "cow_temple", "点击牛魔寺庙大地图节点后没有选中该节点")
	assert(panel.map_entries.size() == 8 and panel.map_buttons.size() == 8 and panel._selected_map_id == int(panel.map_entries[0].get("mapId", -1)), "牛魔寺庙应为8图并自动选择首图")
	assert(not requested_batches.is_empty() and COW_TEMPLE_FLOOR_ONE_ID in requested_batches.back(), "牛魔寺庙子地图没有请求传送开放规则")

	var cow_names: Array[String] = []
	for map_data: Dictionary in panel.map_entries:
		assert(str(map_data.get("mapGroup", "")) == "牛魔寺庙", "牛魔寺庙列表混入了其他地图组")
		cow_names.append(str(map_data.get("name", "")))
	assert("牛魔寺庙一层" in cow_names and "牛魔寺庙大厅" in cow_names, "牛魔寺庙列表缺少楼层或大厅")
	var first_paths: Array[String] = []
	for card: Button in panel.map_buttons:
		assert(card.name == "MapCard_%d" % int(card.get_meta("map_id", -1)), "地图卡节点名不稳定")
		first_paths.append(str(card.get_path()))
	panel.refresh()
	var second_paths: Array[String] = []
	for card: Button in panel.map_buttons:
		assert(card.name == "MapCard_%d" % int(card.get_meta("map_id", -1)), "刷新后地图卡节点名不稳定")
		second_paths.append(str(card.get_path()))
	assert(first_paths == second_paths, "连续刷新地图卡路径不稳定")

	var first_card := panel.map_buttons[0]
	var card_name := first_card.get_node("MapName") as Label
	var card_subtitle := first_card.get_node("MapSubtitle") as Label
	assert(card_name.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "地图名称没有居中")
	assert(card_subtitle.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "地图副标题没有居中")
	assert(card_subtitle.position.y - (card_name.position.y + card_name.size.y) <= 2.0, "地图卡两行文字间距过大")
	assert(card_subtitle.position.y + card_subtitle.size.y < panel.MAP_CARD_SIZE.y, "地图卡文字越过装饰框")

	var floor_one_index := panel._index_for_map_id(COW_TEMPLE_FLOOR_ONE_ID)
	assert(floor_one_index >= 0, "牛魔寺庙一层没有出现在子地图列表")
	panel._select_map(floor_one_index)
	assert(panel.teleport_button.disabled and panel.teleport_button.text == "传送未开放", "没有玩法规则时 UI 必须保持传送关闭")

	panel.set_teleport_availability({
		COW_TEMPLE_FLOOR_ONE_ID: {
			"enabled": true,
			"destination_map_id": COW_TEMPLE_FLOOR_ONE_ID,
			"arrival_anchor_id": "cow_temple.floor1.exit",
			"destination_label": "牛魔寺庙一层出口",
			"reason": "",
			"rule_id": "test.cow_temple.floor1",
		},
	})
	assert(not panel.teleport_button.disabled and panel.teleport_button.text == "传送", "开放牛魔寺庙一层后传送按钮没有点亮")
	assert("牛魔寺庙一层出口" in panel.detail_label.text, "地图详情没有显示传送落点")

	var teleport_requests: Array[Dictionary] = []
	var travel_ids: Array[int] = []
	panel.teleport_requested.connect(func(request: Dictionary) -> void: teleport_requests.append(request))
	panel.map_selected.connect(func(map_id: int) -> void: travel_ids.append(map_id))
	panel._teleport_selected()
	assert(teleport_requests.size() == 1, "传送按钮没有发出结构化传送请求")
	assert(teleport_requests[0].get("selected_map_id", -1) == COW_TEMPLE_FLOOR_ONE_ID, "传送请求没有保留选中的牛魔寺庙一层")
	assert(teleport_requests[0].get("destination_map_id", -1) == COW_TEMPLE_FLOOR_ONE_ID, "传送请求目的地图错误")
	assert(teleport_requests[0].get("arrival_anchor_id", "") == "cow_temple.floor1.exit", "传送请求没有携带一层出口锚点")
	assert(travel_ids == [COW_TEMPLE_FLOOR_ONE_ID] and not panel.visible, "兼容地图选择信号或关闭面板行为异常")

	panel.show()
	var floor_two_index := panel._index_for_map_id(COW_TEMPLE_FLOOR_TWO_ID)
	panel._select_map(floor_two_index)
	assert(panel.teleport_button.disabled, "没有开放规则的牛魔寺庙二层不应允许传送")

	PlayerState.set_later_content_enabled(true)
	panel.refresh()
	await get_tree().process_frame
	assert(PlayerState.later_content_enabled and panel.map_entries.size() < 142, "后期状态过滤异常")
	print("MAP_GOTHIC_UI_PASS：世界地图树、牛魔寺庙 8 图筛选、单传送按钮与落点契约均正常")
	get_tree().quit(0)
