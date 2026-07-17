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
	assert(panel.bag_grid.columns == 8 and panel.stash_grid.columns == 8, "仓库与人物背包没有复用 8 列方格")
	assert(panel.bag_grid.get_child_count() == 100, "人物背包没有保留 100 格")
	assert(panel.stash_grid.get_child_count() == 100, "仓库当前页没有显示 100 格")
	assert(panel.get_node("BagSection/BagScroll").size.y == 340.0, "人物背包首屏没有显示 40 格")
	assert(panel.get_node("StashSection/StashScroll").size.y == 340.0, "仓库首屏没有显示当前页前 40 格")
	assert(panel.warehouse_page_label.text == "第 1/5 页", "仓库底部页码错误")
	assert(panel.previous_page_button.disabled and not panel.next_page_button.disabled, "仓库第一页翻页按钮状态错误")
	panel._change_warehouse_page(1)
	assert(panel.warehouse_page == 1 and panel.warehouse_page_label.text == "第 2/5 页", "仓库无法切换到第二页")
	assert(panel.stash_grid.get_child_count() == 100, "仓库第二页没有保持 100 格")
	panel._change_warehouse_page(-1)
	assert(panel.warehouse_page == 0 and panel.warehouse_page_label.text == "第 1/5 页", "仓库无法返回第一页")
	assert(panel.deposit_button.disabled and panel.withdraw_button.disabled, "未选择物品时转移按钮不应启用")

	var bag_count := PlayerState.inventory.size()
	var stash_count := PlayerState.warehouse_inventory.size()
	panel._select_item("bag", 0)
	assert(not panel.deposit_button.disabled and panel.withdraw_button.disabled, "选择人物背包物品后存入按钮状态错误")
	assert(panel.transfer_detail_label.text == str(PlayerState.inventory[0].get("name", "")), "中间转移栏没有显示选中物品")
	panel._deposit()
	assert(PlayerState.inventory.size() == bag_count - 1, "存入后人物背包数量错误")
	assert(PlayerState.warehouse_inventory.size() == stash_count + 1, "存入后个人仓库数量错误")

	panel._select_item("stash", 0)
	assert(panel.deposit_button.disabled and not panel.withdraw_button.disabled, "选择仓库物品后取出按钮状态错误")
	panel._withdraw()
	assert(PlayerState.inventory.size() == bag_count, "取出后人物背包数量错误")
	assert(PlayerState.warehouse_inventory.size() == stash_count, "取出后个人仓库数量错误")

	var sort_requests := [0]
	panel.warehouse_sort_requested.connect(func() -> void: sort_requests[0] += 1)
	panel.get_node("TransferSection/SortStashButton").pressed.emit()
	assert(sort_requests[0] == 1, "整理按钮没有只向玩法层发出请求")
	print("WAREHOUSE_GOTHIC_UI_PASS：左仓库、右背包、8列100格与5页页码均正常")
	get_tree().quit(0)
