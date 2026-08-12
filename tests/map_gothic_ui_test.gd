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
	var expected_tree_width := 650.0 * 1598.0 / 2664.0
	assert(absf(tree_scroll.size.x - expected_tree_width) <= 2.0, "世界树宽度必须按1598×720逻辑空间换算为650设备像素；actual=%s expected=%s" % [tree_scroll.size.x, expected_tree_width])
	assert(tree_scroll.position.x >= 0.0 and tree_scroll.position.y >= 0.0 and tree_scroll.size.y > 0.0, "世界树滚动区必须为有效矩形")
	assert(panel.world_tree_container.custom_minimum_size.x <= tree_scroll.size.x, "世界树内容最小宽度不应反向撑大滚动区")
	assert(tree_frame.size.x > 0.0 and tree_frame.size.y > 0.0, "二级装饰框必须保持有效几何")
	assert(tree_scroll.get_meta("calibration_layout_revision") == 2, "世界树布局版本错误")
	var expected_regions: Dictionary = {}
	for map_value: Variant in GameData.get_available_maps(false):
		if map_value is Dictionary:
			expected_regions[str(map_value.get("region", ""))] = true
	var actual_regions: Dictionary = {}
	for node_value: Variant in panel.world_tree_nodes:
		var node_data: Dictionary = node_value
		assert(int(node_data.get("depth", -1)) == 0, "中间目录只能包含大地图region节点")
		assert(node_data.get("regions", []).size() == 1, "大地图节点必须精确对应一个region")
		assert(node_data.get("map_groups", []).is_empty() and node_data.get("map_ids", []).is_empty() and node_data.get("name_terms", []).is_empty(), "中间目录不得包含地图组或具体地图过滤")
		actual_regions[str(node_data.get("regions", [""])[0])] = true
	assert(actual_regions.size() == expected_regions.size(), "目录 region 数量与正式数据不一致")
	for expected_region: Variant in expected_regions.keys():
		assert(actual_regions.has(expected_region), "目录缺少正式 region：%s" % expected_region)
	var all_group_labels: Dictionary = {}
	for map_value: Variant in GameData.get_available_maps(false):
		if map_value is Dictionary:
			all_group_labels[str(map_value.get("mapGroup", ""))] = true
	for node_value: Variant in panel.world_tree_nodes:
		assert(not all_group_labels.has(str((node_value as Dictionary).get("label", ""))), "内部mapGroup被错误提升为大地图按钮")
	assert(not panel.world_tree_container.find_child("*地表*", true, false), "中间目录不得出现地表/入口分支")
	var expected_bich_ids: Array[int] = []
	for map_value: Variant in GameData.get_available_maps(false):
		if map_value is Dictionary and str(map_value.get("region", "")) == "比奇地区":
			expected_bich_ids.append(int(map_value.get("mapId", -1)))
	var actual_bich_ids: Array[int] = []
	for map_data: Dictionary in panel.map_entries:
		actual_bich_ids.append(int(map_data.get("mapId", -1)))
	expected_bich_ids.sort()
	actual_bich_ids.sort()
	assert(actual_bich_ids == expected_bich_ids and panel._selected_map_id == int(panel.map_entries[0].get("mapId", -1)), "默认比奇左侧必须显示该大区全部实际地图并选择首图")
	assert(not panel.map_name_label.text.is_empty() and not panel.detail_label.text.contains("请选择地图"), "默认地图详情未同步")
	var player_text_forbidden := ["资料ID", "运行时ID", "可信度", "版本：", "地图组", "source", "mapGroup", "地表/入口"]
	var visible_detail := panel.detail_label.text
	for forbidden: String in player_text_forbidden:
		assert(not forbidden in visible_detail, "区域信息泄露内部字段：%s" % forbidden)
	for card: Button in panel.map_buttons:
		var subtitle := card.get_node("MapSubtitle") as Label
		assert(not "ID" in subtitle.text and not "地区" in subtitle.text and not "地表/入口" in subtitle.text, "左侧地图卡泄露编号或内部分类")
	var bich_detail := panel._detail_base_text
	for expected_text: String in ["地图说明：", "营地：有安全营地", "常见怪物：", "首领：", "出口："]:
		assert(expected_text in bich_detail, "比奇省玩家说明缺少真实游玩信息：%s" % expected_text)
	var bich_content := panel._player_map_content(4)
	var checked_monsters := 0
	for spawn: Variant in bich_content.get("spawns", []):
		if spawn is Dictionary:
			var expected_monster := str(spawn.get("display_name", spawn.get("name", ""))).strip_edges()
			if not expected_monster.is_empty():
				assert(expected_monster in bich_detail, "比奇省说明缺少正式怪物：%s" % expected_monster)
				checked_monsters += 1
				if checked_monsters >= 3:
					break
	assert(checked_monsters > 0, "比奇省正式怪物数据为空")
	assert("兽人古墓一层" in bich_detail and "沃玛森林" in bich_detail, "比奇省出口未显示真实目的地")
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
	assert((panel.world_node_buttons["cangyue_island"] as Button).position.x == panel.WORLD_TREE_SIDE_GUTTER, "苍月岛装饰框左侧出现异常突出")
	var total_maps := GameData.get_available_maps(true).size()
	for node_id: Variant in panel.world_node_buttons.keys():
		panel._select_world_node(str(node_id))
		assert(panel.map_entries.size() > 0 and panel.map_entries.size() < total_maps, "节点筛选为空或回退全量")
		var filter_node := panel._world_node(str(node_id))
		var region_name := str(filter_node.get("regions", [""])[0])
		var expected_ids: Array[int] = []
		for map_value: Variant in GameData.get_available_maps(false):
			if map_value is Dictionary and str(map_value.get("region", "")) == region_name:
				expected_ids.append(int(map_value.get("mapId", -1)))
		var actual_ids: Array[int] = []
		for map_data: Dictionary in panel.map_entries:
			assert(panel._node_matches_map(filter_node, map_data), "节点列表含不匹配地图")
			assert(str(map_data.get("region", "")) == region_name, "左侧地图混入其他大区")
			actual_ids.append(int(map_data.get("mapId", -1)))
		expected_ids.sort()
		actual_ids.sort()
		assert(actual_ids == expected_ids, "左侧没有精确显示当前大区的全部地图")
		assert(panel._selected_map_id == int(panel.map_entries[0].get("mapId", -1)) and not panel.map_name_label.text.is_empty(), "切换大区后首图详情未自动同步")

	var requested_batches: Array = []
	panel.teleport_availability_requested.connect(
		func(map_ids: Array) -> void: requested_batches.append(map_ids.duplicate())
	)
	panel._select_world_node("cangyue_island")
	await get_tree().process_frame
	assert(panel._selected_world_node_id == "cangyue_island", "点击苍月大地图节点后没有选中该节点")
	assert(not requested_batches.is_empty() and COW_TEMPLE_FLOOR_ONE_ID in requested_batches.back(), "苍月区域没有请求其牛魔寺庙子地图传送规则")

	var cow_names: Array[String] = []
	for map_data: Dictionary in panel.map_entries:
		if str(map_data.get("mapGroup", "")) == "牛魔寺庙":
			cow_names.append(str(map_data.get("name", "")))
	assert("牛魔寺庙一层" in cow_names and "牛魔寺庙大厅" in cow_names, "苍月区域列表缺少牛魔寺庙楼层或大厅")
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
