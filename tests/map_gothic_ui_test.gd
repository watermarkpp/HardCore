extends Node

const CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/world_map_teleport_contract.json"
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
	assert(panel.search_box.theme_type_variation == "GothicSearchField", "地图搜索没有使用公共哥特输入框")
	assert(panel.later_toggle.theme_type_variation == "GothicContentToggle", "后期内容开关没有使用公共哥特样式")
	assert(panel.map_entries.size() == 129 and panel.map_buttons.size() == 129, "世界根节点默认地图数量错误")
	assert(not panel.map_list.visible and panel.map_list.item_count == 129, "地图兼容选择列表异常")
	assert(panel.world_tree_container.get_theme_constant("separation") == 7, "世界地图节点间距没有与左侧地图卡保持一致")
	var reference_world_button := panel.world_node_buttons["mafa_world"] as Button
	for world_button_value: Variant in panel.world_node_buttons.values():
		var world_button := world_button_value as Button
		assert(world_button.position == reference_world_button.position, "世界地图节点装饰框左边缘不一致")
		assert(world_button.size == reference_world_button.size, "世界地图节点装饰框尺寸不一致")
		assert(world_button.alignment == HORIZONTAL_ALIGNMENT_CENTER, "世界地图名称没有相对装饰框水平居中")
	assert((panel.world_node_buttons["cangyue_island"] as Button).position.x == 12.0, "苍月岛装饰框左侧出现异常突出")

	var requested_batches: Array = []
	panel.teleport_availability_requested.connect(
		func(map_ids: Array) -> void: requested_batches.append(map_ids.duplicate())
	)
	panel._select_world_node("cow_temple")
	await get_tree().process_frame
	assert(panel._selected_world_node_id == "cow_temple", "点击牛魔寺庙大地图节点后没有选中该节点")
	assert(panel.map_entries.size() == 8 and panel.map_buttons.size() == 8, "牛魔寺庙节点应展示入口、一至六层和大厅共 8 张地图")
	assert(not requested_batches.is_empty() and COW_TEMPLE_FLOOR_ONE_ID in requested_batches.back(), "牛魔寺庙子地图没有请求传送开放规则")

	var cow_names: Array[String] = []
	for map_data: Dictionary in panel.map_entries:
		assert(str(map_data.get("mapGroup", "")) == "牛魔寺庙", "牛魔寺庙列表混入了其他地图组")
		cow_names.append(str(map_data.get("name", "")))
	assert("牛魔寺庙一层" in cow_names and "牛魔寺庙大厅" in cow_names, "牛魔寺庙列表缺少楼层或大厅")

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

	panel._select_world_node("mafa_world")
	panel.later_toggle.button_pressed = true
	await get_tree().process_frame
	assert(PlayerState.later_content_enabled and panel.map_entries.size() == 142, "后期内容开关没有保留 129/142 地图筛选")
	print("MAP_GOTHIC_UI_PASS：世界地图树、牛魔寺庙 8 图筛选、单传送按钮与落点契约均正常")
	get_tree().quit(0)
