extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for item_name: String in ["太阳水", "匕首", "布衣(男)", "古铜戒指", "木剑", "黑铁头盔"]:
		PlayerState.add_item(item_name)
	PlayerState.warehouse_inventory = [
		PlayerState.inventory.pop_back(),
		PlayerState.inventory.pop_back(),
	]
	var panel := WarehousePanel.new()
	add_child(panel)
	await get_tree().process_frame
	panel.open_panel()
	await get_tree().process_frame

	assert(panel.size == Vector2(1164, 660), "仓库没有使用既定横屏布局尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "仓库没有使用公共哥特外框")
	assert(panel.get_node("StashSection").position.x < panel.get_node("BagSection").position.x, "仓库必须位于左侧、人物背包位于右侧")
	assert(panel.get_node("StashSection").theme_type_variation == "GothicInsetFrame", "个人仓库没有使用公共内框")
	assert(panel.get_node("TransferSection").theme_type_variation == "GothicInsetFrame", "转移栏没有使用公共内框")
	assert(panel.get_node("BagSection").theme_type_variation == "GothicInsetFrame", "人物背包没有使用公共内框")
	assert(panel.bag_grid.columns == 6 and panel.stash_grid.columns == 6, "仓库与人物背包没有按要求减少为 6 列")
	for side_name: String in ["Stash", "Bag"]:
		var frame := panel.get_node("%sSection/%sGridV3Frame" % [side_name, side_name]) as Control
		assert(frame != null and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s 二级框缺失或阻挡操作" % side_name)
		assert(frame.get_node("%sGridV3FrameDecoration/%sGridV3FrameFill" % [side_name, side_name]) != null, "%s 二级框没有代码填充" % side_name)
		assert(frame.get_node("%sGridV3FrameDecoration/%sGridV3FrameFrame" % [side_name, side_name]) != null, "%s 二级框缺少边框层" % side_name)
	assert(panel.bag_grid.get_child_count() == 100, "人物背包没有保留 100 格")
	assert(panel.stash_grid.get_child_count() == 100, "仓库当前页没有显示 100 格")
	assert(panel.get_node("BagSection/BagScroll").size == WarehousePanel.GRID_SCROLL_RECT.size, "人物背包滚动区没有避开二级框内圈")
	assert(panel.get_node("StashSection/StashScroll").size == WarehousePanel.GRID_SCROLL_RECT.size, "仓库滚动区没有避开二级框内圈")
	var initial_bag_positions: Array[Vector2] = []
	for index in range(30):
		initial_bag_positions.append((panel.bag_grid.get_child(index) as Control).position)
	panel.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	for index in range(30):
		assert((panel.bag_grid.get_child(index) as Control).position == initial_bag_positions[index], "刷新后背包格子位置漂移：%d" % index)
	assert(panel.warehouse_page_label.text == "第 1/5 页", "仓库底部页码错误")
	assert(panel.previous_page_button.position.y == panel.warehouse_page_label.position.y, "上一页按钮与页码没有在同一水平线上")
	assert(panel.next_page_button.position.y == panel.warehouse_page_label.position.y, "下一页按钮与页码没有在同一水平线上")
	assert(
		panel.previous_page_button.size.y == WarehousePanel.THIN_BUTTON_HEIGHT,
		"上一页按钮与页码高度不一致：%s/%s" % [panel.previous_page_button.size.y, panel.warehouse_page_label.size.y]
	)
	assert(
		panel.next_page_button.size.y == WarehousePanel.THIN_BUTTON_HEIGHT,
		"下一页按钮与页码高度不一致：%s/%s" % [panel.next_page_button.size.y, panel.warehouse_page_label.size.y]
	)
	assert(panel.previous_page_button.size.x >= 96.0 and panel.next_page_button.size.x >= 96.0, "翻页按钮宽度不足，九宫格图框会被裁切")
	for button in [panel.previous_page_button, panel.next_page_button, panel.deposit_button, panel.withdraw_button, panel.get_node("TransferSection/SortStashButton")]:
		assert((button as Button).size.y == WarehousePanel.THIN_BUTTON_HEIGHT, "仓库按钮未统一为细按钮：%s" % button.name)
		assert((button as Button).alignment == HORIZONTAL_ALIGNMENT_CENTER, "仓库按钮文字未数学居中：%s" % button.name)
	var page_group_center := (panel.previous_page_button.position.x + panel.next_page_button.position.x + panel.next_page_button.size.x) * 0.5
	assert(is_equal_approx(page_group_center, 246.0), "翻页按钮和页码没有作为整体居中")
	assert(panel.previous_page_button.disabled and not panel.next_page_button.disabled, "仓库第一页翻页按钮状态错误")
	panel._change_warehouse_page(1)
	assert(panel.warehouse_page == 1 and panel.warehouse_page_label.text == "第 2/5 页", "仓库无法切换到第二页")
	assert(panel.stash_grid.get_child_count() == 100, "仓库第二页没有保持 100 格")
	assert(panel.deposit_button.disabled and panel.withdraw_button.disabled, "未选择物品时转移按钮不应启用")

	var bag_count := PlayerState.inventory.size()
	var stash_count := panel._warehouse_occupied_count()
	var deposited_name := str(PlayerState.inventory[0].get("name", ""))
	panel._select_item("bag", 0)
	assert(not panel.deposit_button.disabled and panel.withdraw_button.disabled, "选择人物背包物品后存入按钮状态错误")
	assert(panel.transfer_detail_label.text == str(PlayerState.inventory[0].get("name", "")), "中间转移栏没有显示选中物品")
	panel._deposit()
	assert(PlayerState.inventory.size() == bag_count - 1, "存入后人物背包数量错误")
	assert(panel._warehouse_occupied_count() == stash_count + 1, "存入后个人仓库数量错误")
	assert(panel.warehouse_page == 1, "存入物品后不应跳离当前选择的仓库页")
	assert(str(panel._warehouse_record(100).get("name", "")) == deposited_name, "物品没有存入当前选择的仓库第二页")
	assert(panel._warehouse_record(2).is_empty(), "存入第二页时不应占用第一页空格")

	panel._select_item("stash", 100)
	assert(panel.deposit_button.disabled and not panel.withdraw_button.disabled, "选择仓库物品后取出按钮状态错误")
	panel._withdraw()
	assert(PlayerState.inventory.size() == bag_count, "取出后人物背包数量错误")
	assert(panel._warehouse_occupied_count() == stash_count, "取出后个人仓库数量错误")
	assert(panel._warehouse_record(100).is_empty(), "取出后当前页物品格没有清空")

	PlayerState.inventory.clear()
	for index in range(WarehousePanel.BAG_CAPACITY):
		PlayerState.inventory.append({"name": "太阳水", "count": 1, "capacity_test_index": index})
	panel._select_item("stash", 0)
	var warehouse_before_full_withdraw := PlayerState.warehouse_inventory.duplicate(true)
	assert(panel.withdraw_button.disabled, "背包满 100 格时取出按钮仍可用")
	assert(panel.transfer_detail_label.text == "背包已满，无法取出", "满背包没有显示明确取出失败原因")
	panel._withdraw()
	assert(PlayerState.inventory.size() == WarehousePanel.BAG_CAPACITY, "满背包取出突破了 100 格上限")
	assert(PlayerState.warehouse_inventory == warehouse_before_full_withdraw, "满背包取出删除或改写了仓库物品")

	var sort_requests := [0]
	panel.warehouse_sort_requested.connect(func() -> void: sort_requests[0] += 1)
	panel.get_node("TransferSection/SortStashButton").pressed.emit()
	assert(sort_requests[0] == 1, "整理按钮没有只向玩法层发出请求")
	panel.apply_sort_result({"success": true, "message": "仓库已整理"})
	assert(panel.transfer_detail_label.text == "仓库已整理", "玩法层整理结果没有回填仓库面板")
	print("WAREHOUSE_GOTHIC_UI_PASS：左仓库、右背包、8列100格与5页页码均正常")
	get_tree().quit(0)
