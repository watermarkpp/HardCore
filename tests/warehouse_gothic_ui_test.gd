extends Node

const CalibrationOverlayScript := preload("res://scripts/ui_layout_calibration_overlay.gd")
const AdaptiveButtonStyleBoxScript := preload("res://scripts/adaptive_button_style_box.gd")


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
	var refresh_before_first_open := panel._refresh_execution_count
	panel.open_panel()
	await get_tree().process_frame
	assert(panel._refresh_execution_count == refresh_before_first_open, "仓库首次打开重复刷新 ready 已完成的数据")
	panel.hide()
	PlayerState.inventory_changed.emit()
	assert(panel._refresh_pending and panel._refresh_execution_count == refresh_before_first_open, "隐藏仓库没有延迟库存刷新")
	panel.open_panel()
	assert(panel._refresh_execution_count == refresh_before_first_open + 1, "仓库 pending 打开未恰好刷新一次")
	await get_tree().process_frame
	assert(panel._refresh_execution_count == refresh_before_first_open + 1, "仓库 pending 打开后 deferred 又重复刷新")
	var bag_cell_zero := panel.bag_grid.get_child(0)
	var stash_cell_zero := panel.stash_grid.get_child(0)
	var created_cells := panel._grid_cell_creation_count
	panel.refresh()
	assert(created_cells == 200 and panel._grid_cell_creation_count == created_cells, "仓库刷新重复创建固定格节点")
	assert(panel.bag_grid.get_child(0) == bag_cell_zero and panel.stash_grid.get_child(0) == stash_cell_zero, "仓库刷新替换了固定格节点")
	assert(panel._layout_apply_count == 1, "仓库重复打开或刷新重复应用布局")
	assert(panel.size == Vector2(1164, 660), "仓库没有使用既定横屏布局尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "仓库没有使用公共哥特外框")
	assert(panel.get_node("StashSection").position.x < panel.get_node("BagSection").position.x, "仓库必须位于左侧、人物背包位于右侧")
	for retired_decoration_path: String in [
		"StashSection/StashSectionDecoration",
		"TransferSection/TransferSectionDecoration",
		"BagSection/BagSectionDecoration",
	]:
		assert(panel.get_node_or_null(retired_decoration_path) == null, "%s 不应再生成自动二级框" % retired_decoration_path)
		assert(retired_decoration_path in panel.get_meta("calibration_retired_paths", []), "%s 未加入校准退役路径" % retired_decoration_path)
	assert(panel.bag_grid.columns == 6 and panel.stash_grid.columns == 6, "仓库与人物背包没有按要求减少为 6 列")
	for side_name: String in ["Stash", "Bag"]:
		var frame := panel.get_node("%sSection/%sGridV3Frame" % [side_name, side_name]) as Control
		assert(frame != null and frame.mouse_filter == Control.MOUSE_FILTER_IGNORE, "%s 二级框缺失或阻挡操作" % side_name)
		assert(frame.get_node("%sGridV3FrameDecoration/%sGridV3FrameFill" % [side_name, side_name]) != null, "%s 二级框没有代码填充" % side_name)
		assert(frame.get_node("%sGridV3FrameDecoration/%sGridV3FrameFrame" % [side_name, side_name]) != null, "%s 二级框缺少边框层" % side_name)
	assert(panel.bag_grid.get_child_count() == 100, "人物背包没有保留 100 格")
	assert(panel.stash_grid.get_child_count() == 100, "仓库当前页没有显示 100 格")
	assert(panel.get_node("BagSection/BagPagingHint").text == "首屏 30 格　·　下拉查看 31–100 格", "人物背包分页说明没有同步 6 列首屏")
	assert(panel.get_node("StashSection/StashPagingHint").text == "每页 100 格　·　下拉查看本页后 70 格", "仓库分页说明没有同步 6 列首屏")
	assert(panel.get_node("BagSection/BagScroll").size == WarehousePanel.GRID_SCROLL_RECT.size, "人物背包滚动区没有避开二级框内圈")
	assert(panel.get_node("StashSection/StashScroll").size == WarehousePanel.GRID_SCROLL_RECT.size, "仓库滚动区没有避开二级框内圈")
	assert(is_equal_approx(WarehousePanel.GRID_SCROLL_RECT.size.x, WarehousePanel.GRID_CONTENT_WIDTH + WarehousePanel.GRID_SCROLLBAR_WIDTH), "滚动区没有按六列内容宽加滚动条精确计算")
	assert(panel.get_node("BagSection/BagScroll/BagGrid") == panel.bag_grid, "人物背包网格稳定路径被中间容器破坏")
	assert(panel.get_node("StashSection/StashScroll/StashGrid") == panel.stash_grid, "仓库网格稳定路径被中间容器破坏")
	assert(is_equal_approx(panel.bag_grid.custom_minimum_size.x, 341.0), "人物背包并非真实六列内容宽")
	assert(is_equal_approx(panel.stash_grid.custom_minimum_size.x, 341.0), "仓库并非真实六列内容宽")
	for grid in [panel.bag_grid, panel.stash_grid]:
		var scroll := (grid as GridContainer).get_parent() as ScrollContainer
		var first := (grid as GridContainer).get_child(0) as Control
		var sixth := (grid as GridContainer).get_child(5) as Control
		var seventh := (grid as GridContainer).get_child(6) as Control
		var visible_left := scroll.get_global_rect().position.x
		var visible_right := scroll.get_v_scroll_bar().get_global_rect().position.x if scroll.get_v_scroll_bar().visible else scroll.get_global_rect().end.x
		assert(scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "六列网格错误启用了水平滚动")
		assert(scroll.get_theme_stylebox("panel") is StyleBoxEmpty, "六列网格外错误保留了额外细框")
		assert(scroll.get_h_scroll_bar().max_value <= scroll.get_h_scroll_bar().page + 0.5, "六列网格产生了隐藏的水平溢出")
		assert(is_equal_approx(first.position.y, sixth.position.y), "六列中的第六格没有留在首行")
		assert(seventh.position.y > sixth.position.y, "第七格没有真实换到下一行")
		assert(is_equal_approx(seventh.position.x, first.position.x), "第七格没有从下一行首列开始")
		assert(sixth.position.x + sixth.size.x <= WarehousePanel.GRID_CONTENT_WIDTH + 0.5, "第六格越过六列内容边界")
		assert(first.get_global_rect().position.x >= visible_left - 0.5, "首列被左侧裁切")
		assert(sixth.get_global_rect().end.x <= visible_right + 0.5, "第六列被滚动条或右侧裁切")
		assert(is_equal_approx(first.get_global_rect().position.x, visible_left), "六列网格左侧留出了半列或非数学空隙")
		assert(is_equal_approx(sixth.get_global_rect().end.x, visible_left + WarehousePanel.GRID_CONTENT_WIDTH), "六列网格没有严格结束在第六列边界")
	var initial_bag_positions: Array[Vector2] = []
	for index in range(30):
		initial_bag_positions.append((panel.bag_grid.get_child(index) as Control).position)
	panel.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	panel._stabilize_grid_layout()
	await get_tree().process_frame
	for index in range(30):
		assert((panel.bag_grid.get_child(index) as Control).position == initial_bag_positions[index], "刷新后背包格子位置漂移：%d" % index)
	for scroll_path in ["StashSection/StashScroll", "BagSection/BagScroll"]:
		var stabilized_scroll := panel.get_node(scroll_path) as ScrollContainer
		assert(stabilized_scroll.size == WarehousePanel.GRID_SCROLL_RECT.size, "profile apply 后六列滚动区被旧存档宽度覆盖：%s" % scroll_path)
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
	for button in [panel.previous_page_button, panel.next_page_button]:
		assert((button as Button).size.y == WarehousePanel.THIN_BUTTON_HEIGHT, "仓库按钮未统一为细按钮：%s" % button.name)
		assert((button as Button).alignment == HORIZONTAL_ALIGNMENT_CENTER, "仓库按钮文字未数学居中：%s" % button.name)
		assert((button as Button).theme_type_variation == &"GothicWarehouseThinButton", "仓库按钮未使用最终最薄按钮：%s" % button.name)
		for state in [&"normal", &"pressed"]:
			var warehouse_style := panel.theme.get_stylebox(state, &"GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
			_assert_plain_warehouse_frame(warehouse_style, "%s.%s" % [button.name, state])
		var warehouse_disabled := panel.theme.get_stylebox(&"disabled", &"GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
		var warehouse_normal := panel.theme.get_stylebox(&"normal", &"GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
		assert(warehouse_disabled.square_texture.resource_path == warehouse_normal.square_texture.resource_path, "仓库禁用按钮错误使用银色方形边框")
		assert(warehouse_disabled.shortwide_texture.resource_path == warehouse_normal.shortwide_texture.resource_path, "仓库禁用按钮错误使用银色短宽边框")
		assert(warehouse_disabled.widesmall_texture.resource_path == warehouse_normal.widesmall_texture.resource_path, "仓库禁用按钮错误使用银色超薄边框")
	for button in [panel.deposit_button, panel.withdraw_button, panel.get_node("TransferSection/SortStashButton")]:
		assert((button as Button).size.y == WarehousePanel.THIN_BUTTON_HEIGHT, "仓库执行按钮未统一为细按钮：%s" % button.name)
		assert((button as Button).alignment == HORIZONTAL_ALIGNMENT_CENTER, "仓库执行按钮文字未数学居中：%s" % button.name)
		assert((button as Button).theme_type_variation == &"GothicWarehouseActionPlainButton", "仓库执行按钮仍在使用旧普通按钮逻辑：%s" % button.name)
		assert((button as Button).get_theme_font_size("font_size") == GothicUITheme.BUTTON_ACTION_FONT_SIZE, "仓库执行按钮字号未统一：%s" % button.name)
		var action_normal := panel.theme.get_stylebox(&"normal", &"GothicWarehouseActionPlainButton") as AdaptiveButtonStyleBoxScript
		var action_pressed := panel.theme.get_stylebox(&"pressed", &"GothicWarehouseActionPlainButton") as AdaptiveButtonStyleBoxScript
		var action_disabled := panel.theme.get_stylebox(&"disabled", &"GothicWarehouseActionPlainButton") as AdaptiveButtonStyleBoxScript
		_assert_plain_warehouse_frame(action_normal, "%s.normal" % button.name)
		assert(action_normal.fill_color.is_equal_approx(GothicUITheme.BUTTON_ACTION_IDLE_FILL), "仓库执行按钮空闲态不是淡咖啡：%s" % button.name)
		assert(action_pressed.fill_color.is_equal_approx(GothicUITheme.BUTTON_PRESS_FILL), "仓库执行按钮按下/忙碌态不是暗红：%s" % button.name)
		assert(action_disabled.fill_color.is_equal_approx(GothicUITheme.BUTTON_ACTION_DISABLED_FILL), "仓库执行按钮禁用态不是灰色：%s" % button.name)
	var page_normal := panel.theme.get_stylebox(&"normal", &"GothicWarehouseThinButton") as AdaptiveButtonStyleBoxScript
	assert(not page_normal.fill_color.is_equal_approx(GothicUITheme.BUTTON_ACTION_IDLE_FILL), "仓库翻页按钮错误套用了执行按钮语义")
	var page_group_center := (panel.previous_page_button.position.x + panel.next_page_button.position.x + panel.next_page_button.size.x) * 0.5
	assert(is_equal_approx(page_group_center, 246.0), "翻页按钮和页码没有作为整体居中")
	assert(panel.previous_page_button.disabled and not panel.next_page_button.disabled, "仓库第一页翻页按钮状态错误")
	assert(panel.deposit_button.disabled and panel.withdraw_button.disabled, "未选择物品时转移按钮不应启用")

	var bag_count := PlayerState.inventory_occupied_count()
	var bag_shape_before := PlayerState.inventory.size()
	var stash_count := panel._warehouse_occupied_count()
	var deposited_names := [
		str(PlayerState.inventory[0].get("name", "")),
		str(PlayerState.inventory[1].get("name", "")),
	]
	panel._select_item("bag", 0)
	panel._select_item("bag", 1)
	assert(panel.selected_bag_indices.size() == 2 and panel.selected_bag_indices.has(0) and panel.selected_bag_indices.has(1), "人物背包同侧不能同时选择两个物品")
	assert(panel.selected_stash_indices.is_empty() and panel.selected_bag_index == 1, "人物背包多选的兼容焦点或跨侧状态错误")
	assert((panel._bag_cells[0].get_node("ItemButton") as Button).theme_type_variation == &"GothicComponentSelectedSlotButton", "人物背包第一个多选框没有保留")
	assert((panel._bag_cells[1].get_node("ItemButton") as Button).theme_type_variation == &"GothicComponentSelectedSlotButton", "人物背包第二个多选框没有显示")
	assert(panel.bag_list.get_selected_items().size() == 2, "兼容列表没有镜像人物背包多选")
	assert(panel.transfer_detail_label.text == "已选择 2 件背包物品", "中间转移栏没有显示人物背包多选数量")
	panel._select_item("bag", 0)
	assert(panel.selected_bag_indices.size() == 1 and panel.selected_bag_indices.has(1), "再次点击人物背包格没有取消单个选择")
	panel._select_item("bag", 0)
	panel._select_item("stash", 0)
	panel._select_item("stash", 1)
	assert(panel.selected_bag_indices.is_empty() and panel.selected_stash_indices.size() == 2, "切到仓库侧没有清空人物背包多选")
	assert((panel._bag_cells[0].get_node("ItemButton") as Button).theme_type_variation == &"GothicComponentSlotButton", "切到仓库侧后人物背包仍残留选中框")
	panel._select_item("bag", 0)
	panel._select_item("bag", 1)
	assert(panel.selected_stash_indices.is_empty() and panel.selected_bag_indices.size() == 2, "切回人物背包侧没有清空仓库多选")
	assert(not panel.deposit_button.disabled and panel.withdraw_button.disabled, "选择人物背包物品后存入按钮状态错误")
	panel._change_warehouse_page(1)
	assert(panel.warehouse_page == 1 and panel.warehouse_page_label.text == "第 2/5 页", "仓库无法切换到第二页")
	assert(panel.stash_grid.get_child_count() == 100, "仓库第二页没有保持 100 格")
	assert(panel.selected_bag_indices.size() == 2 and not panel.deposit_button.disabled, "切换仓库页错误清除了人物背包批次")
	var refresh_before_deposit := panel._refresh_execution_count
	panel._deposit()
	assert(panel.deposit_button.get_meta("gothic_feedback_state", "") == "busy", "批量存入没有保留一帧暗红忙碌态")
	assert(panel._refresh_execution_count == refresh_before_deposit + 1, "批量存仓没有恰好执行一次 UI 刷新")
	assert(panel._last_transfer_batch_result == {"operation": "deposit", "requested": 2, "transferred": 2, "remaining": 0, "complete": true, "failure_message": ""}, "批量存入结果合同错误")
	await get_tree().process_frame
	assert(panel.deposit_button.get_meta("gothic_feedback_state", "") == "success", "批量存入完成后没有进入结果态")
	assert(panel._refresh_execution_count == refresh_before_deposit + 1, "批量存仓信号的 deferred refresh 重复执行")
	assert(PlayerState.inventory_occupied_count() == bag_count - 2, "批量存入后人物背包占用数量错误")
	assert(PlayerState.inventory.size() == bag_shape_before and PlayerState.inventory[0].is_empty() and PlayerState.inventory[1].is_empty(), "批量存入没有保留两个原绝对槽空洞")
	assert(panel._warehouse_occupied_count() == stash_count + 2, "批量存入后个人仓库数量错误")
	assert(panel.warehouse_page == 1, "存入物品后不应跳离当前选择的仓库页")
	assert(str(panel._warehouse_record(100).get("name", "")) == deposited_names[0] and str(panel._warehouse_record(101).get("name", "")) == deposited_names[1], "两个物品没有按稳定顺序存入当前仓库页")
	assert(panel._warehouse_record(2).is_empty(), "存入第二页时不应占用第一页空格")
	assert(panel.selected_bag_indices.is_empty() and panel.selected_bag_index == -1, "批量存入成功后仍保留已转移选择")

	panel._select_item("stash", 100)
	panel._select_item("stash", 101)
	assert(panel.selected_bag_indices.is_empty() and panel.selected_stash_indices.size() == 2, "仓库同侧不能同时选择两个物品")
	assert(panel.deposit_button.disabled and not panel.withdraw_button.disabled, "选择仓库物品后取出按钮状态错误")
	var refresh_before_withdraw := panel._refresh_execution_count
	panel._withdraw()
	assert(panel.withdraw_button.get_meta("gothic_feedback_state", "") == "busy", "批量取出没有保留一帧暗红忙碌态")
	assert(panel._refresh_execution_count == refresh_before_withdraw + 1, "批量取仓没有恰好执行一次 UI 刷新")
	assert(panel._last_transfer_batch_result == {"operation": "withdraw", "requested": 2, "transferred": 2, "remaining": 0, "complete": true, "failure_message": ""}, "批量取出结果合同错误")
	await get_tree().process_frame
	assert(panel.withdraw_button.get_meta("gothic_feedback_state", "") == "success", "批量取出完成后没有进入结果态")
	assert(panel._refresh_execution_count == refresh_before_withdraw + 1, "批量取仓信号的 deferred refresh 重复执行")
	assert(PlayerState.inventory_occupied_count() == bag_count, "取出后人物背包占用数量错误")
	assert(str(PlayerState.inventory[0].get("name", "")) == deposited_names[0] and str(PlayerState.inventory[1].get("name", "")) == deposited_names[1], "批量取出没有按稳定顺序填回空槽")
	assert(panel._warehouse_occupied_count() == stash_count, "取出后个人仓库数量错误")
	assert(panel._warehouse_record(100).is_empty() and panel._warehouse_record(101).is_empty(), "批量取出后当前页两个物品格没有清空")

	# Best-effort batch semantics: every successful slot is committed by the
	# existing atomic single-slot authority. Stop at first capacity failure and
	# retain all untransferred selections for a safe retry.
	PlayerState.inventory = [
		{"name": "太阳水", "count": 1, "batch_id": "first"},
		{"name": "匕首", "count": 1, "batch_id": "second"},
	]
	PlayerState.warehouse_inventory = []
	for index in range(WarehousePanel.WAREHOUSE_PAGE_CAPACITY - 1):
		PlayerState.warehouse_inventory.append({"name": "太阳水", "count": 1, "warehouse_fill": index})
	panel.warehouse_page = 0
	panel.refresh()
	panel._select_item("bag", 0)
	panel._select_item("bag", 1)
	panel._deposit()
	assert(panel._last_transfer_batch_result.get("requested") == 2 and panel._last_transfer_batch_result.get("transferred") == 1 and panel._last_transfer_batch_result.get("remaining") == 1 and not panel._last_transfer_batch_result.get("complete"), "仓库容量不足时没有返回明确部分成功结果")
	assert(PlayerState.inventory[0].is_empty() and str(PlayerState.inventory[1].get("batch_id", "")) == "second", "部分存入破坏了未转移背包槽")
	assert(str(PlayerState.warehouse_inventory[99].get("batch_id", "")) == "first", "部分存入的已成功项没有进入唯一空仓库槽")
	assert(panel.selected_bag_indices.size() == 1 and panel.selected_bag_indices.has(1), "部分存入没有只保留未转移项的选中态")
	await get_tree().process_frame
	assert(panel.deposit_button.get_meta("gothic_feedback_state", "") == "failure", "部分存入没有显示未完成结果态")

	PlayerState.inventory.clear()
	for index in range(WarehousePanel.BAG_CAPACITY):
		PlayerState.inventory.append({"name": "匕首", "count": 1, "capacity_test_index": index})
	PlayerState.warehouse_inventory[0] = {"name": "匕首", "count": 1, "warehouse_capacity_guard": true}
	panel._select_item("stash", 0)
	var warehouse_before_full_withdraw := PlayerState.warehouse_inventory.duplicate(true)
	assert(panel.withdraw_button.disabled, "背包满 100 格时取出按钮仍可用")
	assert("背包已满" in panel.transfer_detail_label.text, "满背包没有显示明确取出失败原因")
	panel._withdraw()
	assert(PlayerState.inventory.size() == WarehousePanel.BAG_CAPACITY, "满背包取出突破了 100 格上限")
	assert(PlayerState.warehouse_inventory == warehouse_before_full_withdraw, "满背包取出删除或改写了仓库物品")
	assert(panel._last_transfer_batch_result.get("transferred") == 0 and panel._last_transfer_batch_result.get("remaining") == 1 and panel.selected_stash_indices.has(0), "满背包失败没有保留仓库选择供重试")

	var sort_requests := [0]
	panel.warehouse_sort_requested.connect(func() -> void: sort_requests[0] += 1)
	panel.get_node("TransferSection/SortStashButton").pressed.emit()
	assert(sort_requests[0] == 1, "整理按钮没有只向玩法层发出请求")
	assert(panel.sort_button.get_meta("gothic_feedback_state", "") == "busy", "整理按钮没有进入暗红忙碌态")
	panel.apply_sort_result({"success": true, "message": "仓库已整理"})
	assert(panel.transfer_detail_label.text == "仓库已整理", "玩法层整理结果没有回填仓库面板")
	assert(panel.selected_stash_indices.is_empty() and panel.selected_stash_index == -1, "整理成功后仍保留指向旧槽位的仓库选择")
	await get_tree().process_frame
	assert(panel.sort_button.get_meta("gothic_feedback_state", "") == "success", "整理完成后没有进入结果态")
	await get_tree().create_timer(1.05).timeout
	assert(not panel.sort_button.has_meta("gothic_feedback_state"), "整理结果结束后没有回到淡咖啡空闲态")
	var sort_idle := panel.sort_button.get_theme_stylebox("normal") as AdaptiveButtonStyleBoxScript
	assert(sort_idle.fill_color.is_equal_approx(GothicUITheme.BUTTON_ACTION_IDLE_FILL), "整理完成后的空闲背景不是淡咖啡")

	# 用校准器真实加载仓库输出，防止在 Scroll 与 Grid 之间插入容器后
	# 旧的稳定节点路径全部失配。测试数据与校准工作台保持一致。
	panel.queue_free()
	await get_tree().process_frame
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.add_item("强效太阳水", 82)
	PlayerState.add_item("魔法药(中量)", 94)
	PlayerState.add_item("金创药(小量)", 25)
	PlayerState.warehouse_inventory = [{"name": "魔法药(小量)", "count": 23}]
	var calibrated_panel := WarehousePanel.new()
	add_child(calibrated_panel)
	await get_tree().process_frame
	var overlay := CalibrationOverlayScript.new()
	add_child(overlay)
	await get_tree().process_frame
	var inventory_before_calibration := PlayerState.inventory.duplicate(true)
	var warehouse_before_calibration := PlayerState.warehouse_inventory.duplicate(true)
	overlay.edit_panel(calibrated_panel, "warehouse")
	await overlay.profile_loaded
	assert("缺失 0" in overlay.status_label.text, "仓库校准存档仍有稳定路径缺失：%s" % overlay.status_label.text)
	assert("偏差 0" in overlay.status_label.text, "仓库校准存档加载后仍有几何偏差：%s" % overlay.status_label.text)
	assert(PlayerState.inventory == inventory_before_calibration, "校准存档加载意外修改了人物背包数据")
	assert(PlayerState.warehouse_inventory == warehouse_before_calibration, "校准存档加载意外修改了仓库数据")
	for grid in [calibrated_panel.stash_grid, calibrated_panel.bag_grid]:
		var first_cell := (grid as GridContainer).get_child(0) as Control
		var sixth_cell := (grid as GridContainer).get_child(5) as Control
		var seventh_cell := (grid as GridContainer).get_child(6) as Control
		for cell in [first_cell, sixth_cell, seventh_cell]:
			var item_button := cell.get_node("ItemButton") as Button
			assert(item_button.position == Vector2.ZERO and item_button.size == WarehousePanel.ITEM_CELL_SIZE, "旧八列校准数据覆盖了动态物品按钮局部矩形：%s" % item_button.get_path())
		assert(first_cell.position.y == sixth_cell.position.y, "校准载入后首行不足六格")
		assert(seventh_cell.position.y > sixth_cell.position.y and seventh_cell.position.x == first_cell.position.x, "校准载入后第七格没有换到第二行")
	assert(calibrated_panel.previous_page_button.disabled and calibrated_panel.deposit_button.disabled and calibrated_panel.withdraw_button.disabled, "仓库初始禁用按钮逻辑被视觉修复改变")
	print("WAREHOUSE_GOTHIC_UI_PASS：同侧多选、跨侧互斥、批量部分失败、执行按钮状态与既有布局均正常")
	get_tree().quit(0)


func _assert_plain_warehouse_frame(style: AdaptiveButtonStyleBox, context: String) -> void:
	assert(style != null, "仓库无宝石框样式缺失：%s" % context)
	for texture: Texture2D in [style.square_texture, style.shortwide_texture, style.widesmall_texture]:
		assert(texture is AtlasTexture, "仓库无宝石框没有使用精确 Atlas 裁切：%s" % context)
		var atlas := texture as AtlasTexture
		assert(atlas.region == Rect2(1, 5, 106, 48), "仓库无宝石框裁切区域变化：%s" % context)
		assert(atlas.atlas.resource_path.ends_with("/plain_108x60.png"), "仓库按钮不再复用既有无宝石素材：%s" % context)
