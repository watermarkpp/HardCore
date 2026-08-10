extends Node

const SELL_CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/shop_sell_contract.json"

const STOCK := [
	{"name": "匕首", "price": 120, "description": "测试武器"},
	{"name": "布衣(男)", "price": 180, "description": "测试衣服"},
	{"name": "古铜戒指", "price": 240, "description": "测试戒指"},
	{"name": "太阳水", "price": 60, "description": "测试药品"},
]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	var contract: Variant = JSON.parse_string(FileAccess.get_file_as_string(SELL_CONTRACT_PATH))
	assert(contract is Dictionary and contract.get("contractId", "") == "ui.shop.sell.v1", "商店出售UI契约缺失")
	assert(contract.get("pricingPolicy", "").begins_with("UI never calculates"), "出售价格错误地由UI计算")
	PlayerState.reset_progress()
	PlayerState.gold = 1000
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(0).begins_with("已装备"))
	PlayerState.add_item("太阳水", 3)
	PlayerState.add_item("古铜戒指")
	var panel := ShopPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var quote_batches: Array = []
	var sell_requests: Array = []
	panel.sell_quotes_requested.connect(func(items: Array) -> void: quote_batches.append(items))
	panel.sell_requested.connect(func(request: Dictionary) -> void: sell_requests.append(request))
	panel.open_for("测试商店", STOCK)
	await get_tree().process_frame
	assert(panel.size == Vector2(1080, 620), "商店没有使用横屏安全尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "商店没有复用公共哥特外框")
	assert(panel.gold_label.position.y >= 20.0 and panel.gold_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "商店金币文字仍然贴近装饰框上沿")
	assert(panel.detail_label.position.x >= 24.0 and panel.detail_label.position.y >= 60.0, "商品详情文字没有避开装饰框安全内边距")
	assert(panel.goods_grid.columns == 2 and panel.goods_buttons.size() == STOCK.size(), "商品没有使用两列双格卡布局")
	assert(not panel.item_list.visible and panel.item_list.item_count == STOCK.size(), "商店兼容选择列表异常")
	for card: Button in panel.goods_buttons:
		assert(card.size == Vector2(286, 72), "双格商品卡比例错误")
		assert(card.has_node("ItemName") and card.has_node("Price"), "双格商品卡缺少名称或价格区域")
	panel._select_shop_item(0)
	assert(panel.item_list.get_selected_items() == PackedInt32Array([0]), "商品卡选择没有同步购买逻辑")
	assert(panel.goods_buttons[0].theme_type_variation == "GothicComponentSelectedShopCard", "选中商品没有公共高亮状态")
	assert("匕首" in panel.detail_label.text, "商品详情没有响应卡片选择")
	var gold_before := PlayerState.gold
	panel._buy_selected()
	assert(PlayerState.gold == gold_before - 120 and PlayerState.has_item("匕首"), "商品卡购买闭环失败")
	panel._set_trade_mode("sell")
	assert(not quote_batches.is_empty() and quote_batches[-1].size() == PlayerState.inventory.size(), "出售页没有向玩法层请求背包报价")
	assert(panel.goods_buttons.size() == PlayerState.inventory.size(), "出售页没有排除已穿戴装备或遗漏背包物品")
	assert(panel.sell_one_button.disabled and panel.sell_quantity_button.disabled, "没有报价时出售按钮没有禁用")
	var quotes := {}
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[inventory_index]
		var key := panel.sell_quote_key(inventory_index, record)
		var risky := str(record.get("name", "")) == "古铜戒指"
		quotes[key] = {
			"quote_id": "test-%d" % inventory_index,
			"sellable": true,
			"unit_price": 25 + inventory_index,
			"max_quantity": int(record.get("count", 1)),
			"requires_confirmation": risky,
			"risk_flags": ["high_value", "lucky"] if risky else [],
			"warning": "测试高风险物品",
		}
	panel.set_sell_quotes(quotes)
	var safe_indices: Array[int] = []
	var risky_index := -1
	for inventory_index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[inventory_index].get("name", "")) == "古铜戒指":
			risky_index = inventory_index
		else:
			safe_indices.append(inventory_index)
	assert(safe_indices.size() >= 2 and risky_index >= 0, "出售测试缺少两个普通物品和一个高风险物品")

	var dec := panel.sell_quantity_row.get_node("DecreaseQuantity/QuantityDecoration") as TextureRect
	var inc := panel.sell_quantity_row.get_node("IncreaseQuantity/QuantityDecoration") as TextureRect
	assert(dec != null and inc != null and not dec.flip_h and inc.flip_h, "数量装饰未真实镜像")
	assert(dec.show_behind_parent and inc.show_behind_parent, "数量装饰没有放在按钮文字后方")
	assert(
		panel.sell_quantity_row.get_node("DecreaseQuantity").theme_type_variation == "GothicTransparentButton"
		and panel.sell_quantity_row.get_node("IncreaseQuantity").theme_type_variation == "GothicTransparentButton",
		"数量按钮仍使用未镜像的不透明背景"
	)
	var bg := panel.sell_quantity_row.get_node("QuantityCenterBackground") as Panel
	assert(Rect2(Vector2.ZERO, panel.sell_quantity_row.size).encloses(Rect2(bg.position, bg.size)), "中心背景越出数量行")
	assert(Rect2(Vector2.ZERO, panel.sell_quantity_row.size).encloses(Rect2(panel.sell_quantity_label.position, panel.sell_quantity_label.size)), "数量标签越出数量行")
	var decrease := panel.sell_quantity_row.get_node("DecreaseQuantity") as Button
	var increase := panel.sell_quantity_row.get_node("IncreaseQuantity") as Button
	assert(bg.position.x - (decrease.position.x + decrease.size.x) >= 8.0, "中心背景与左按钮缺少安全间隙")
	assert(increase.position.x - (bg.position.x + bg.size.x) >= 8.0, "中心背景与右按钮缺少安全间隙")

	var row_global := panel.sell_quantity_row.get_global_rect()
	assert(row_global.encloses(bg.get_global_rect()) and row_global.encloses(panel.sell_quantity_label.get_global_rect()))
	assert(decrease.size == Vector2(58, 46) and increase.size == Vector2(58, 46))
	assert(row_global.encloses(decrease.get_global_rect()) and row_global.encloses(increase.get_global_rect()))
	assert(decrease.position.x >= 8.0 and row_global.size.x - (increase.position.x + increase.size.x) >= 8.0)
	assert(Rect2(Vector2.ZERO, bg.size).encloses(Rect2(panel.sell_quantity_label.position - bg.position, panel.sell_quantity_label.size)))
	assert(decrease.text.is_empty() and increase.text.is_empty())
	var modal_surface := panel.get_node("ModalSurface") as Control
	var goods_frame := panel.get_node("GoodsPanel") as Control
	var detail_frame := panel.get_node("DetailPanel") as Control
	var outer_surface := panel.get_node("ModalSurface") as Control
	var goods_surface := panel.get_node("GoodsPanelSurface") as Control
	var detail_surface := panel.get_node("DetailPanelSurface") as Control
	assert(outer_surface.get_global_rect().end.y <= panel.get_global_rect().end.y - 32.0)
	assert(goods_frame.get_global_rect().end.y <= panel.get_global_rect().end.y - 60.0 and detail_frame.get_global_rect().end.y <= panel.get_global_rect().end.y - 60.0)
	assert(goods_surface.position.x - goods_frame.position.x >= 10.0 and goods_frame.size.x - (goods_surface.position.x - goods_frame.position.x) - goods_surface.size.x >= 0.0)
	assert(detail_surface.position.x - detail_frame.position.x >= 10.0 and detail_frame.size.x - (detail_surface.position.x - detail_frame.position.x) - detail_surface.size.x >= 0.0)
	assert(absf(goods_frame.get_global_rect().end.y - detail_frame.get_global_rect().end.y) <= 1.0)
	var minus_bar := decrease.get_node("HorizontalBar") as ColorRect
	var plus_bar := increase.get_node("HorizontalBar") as ColorRect
	var plus_vertical := increase.get_node("VerticalBar") as ColorRect
	assert(minus_bar != null and plus_bar != null and plus_vertical != null)
	assert(minus_bar.size == plus_bar.size and minus_bar.color == plus_bar.color)
	assert(absf(minus_bar.get_global_rect().get_center().x - decrease.get_global_rect().get_center().x) <= 0.5)
	assert(absf(plus_bar.get_global_rect().get_center().x - increase.get_global_rect().get_center().x) <= 0.5)
	assert(absf(plus_vertical.get_global_rect().get_center().x - increase.get_global_rect().get_center().x) <= 0.5)
	assert(decrease.get_theme_font_size("font_size") == increase.get_theme_font_size("font_size"))
	assert(dec.get_meta("atlas_region", Rect2()).size == Vector2(58, 46) and inc.get_meta("atlas_region", Rect2()).size == Vector2(58, 46))
	assert(absf(decrease.get_global_rect().get_center().y - increase.get_global_rect().get_center().y) <= 1.0)
	assert(goods_frame.get_global_rect().end.y <= modal_surface.get_global_rect().end.y - 20.0 and detail_frame.get_global_rect().end.y <= modal_surface.get_global_rect().end.y - 20.0)
	panel._select_sell_item(safe_indices[0])
	panel._change_sell_quantity(1)
	assert(int(panel._sell_quantities.get(safe_indices[0], 0)) == 2, "第一个物品的独立数量未生效")
	panel._select_sell_item(safe_indices[1])
	assert(panel._selected_sell_indices.size() == 2, "单击两个卡片没有形成多选")
	assert(int(panel._sell_quantities.get(safe_indices[1], 0)) == 1, "第二个物品没有保持独立默认数量")
	panel._select_sell_item(safe_indices[1])
	assert(panel._selected_sell_indices.size() == 1, "再次点击未取消选择")
	panel._select_sell_item(safe_indices[1])
	panel.set_sell_quotes(quotes)
	assert(panel._selected_sell_indices.size() == 2, "报价刷新改变了选择集合")
	for card: Button in panel.goods_buttons:
		if int(card.get_meta("inventory_index", -1)) in safe_indices:
			assert(card.button_pressed and card.theme_type_variation == "GothicComponentSelectedShopCard", "报价刷新丢失卡片高亮")

	var blocked_quotes := quotes.duplicate(true)
	var blocked_record: Dictionary = PlayerState.inventory[risky_index]
	var blocked_key := panel.sell_quote_key(risky_index, blocked_record)
	var blocked_quote: Dictionary = blocked_quotes[blocked_key].duplicate(true)
	blocked_quote["sellable"] = false
	blocked_quote["reason"] = "测试不可出售"
	blocked_quotes[blocked_key] = blocked_quote
	panel.set_sell_quotes(blocked_quotes)
	panel._select_sell_item(risky_index)
	assert(panel._selected_sell_indices.size() == 2, "点击不可售物品破坏了已有多选")
	assert(not panel.sell_one_button.disabled and not panel.sell_quantity_button.disabled, "查看不可售物品错误禁用了已有批量出售")
	panel.set_sell_quotes(quotes)

	sell_requests.clear()
	panel._request_selected_quantity()
	assert(sell_requests.size() == 1 and panel._batch_sell_active, "批量出售没有先提交第一笔请求")
	assert(int(sell_requests[0].get("inventory_index", -1)) == maxi(safe_indices[0], safe_indices[1]), "批量出售没有按背包索引降序开始")
	panel.apply_sell_result({"success": true, "message": "第一笔成功", "quotes": quotes})
	assert(sell_requests.size() == 2, "第一笔成功后没有继续下一笔批量请求")
	assert(int(sell_requests[0].get("inventory_index", -1)) > int(sell_requests[1].get("inventory_index", -1)), "批量请求顺序不是严格降序")
	var amounts_by_index := {
		int(sell_requests[0].get("inventory_index", -1)): int(sell_requests[0].get("amount", 0)),
		int(sell_requests[1].get("inventory_index", -1)): int(sell_requests[1].get("amount", 0)),
	}
	assert(int(amounts_by_index.get(safe_indices[0], 0)) == 2, "批量出售丢失第一个物品的独立数量")
	assert(int(amounts_by_index.get(safe_indices[1], 0)) == 1, "批量出售错误复用了其他物品数量")
	panel.apply_sell_result({"success": true, "message": "批量全部完成", "quotes": quotes})
	assert(not panel._batch_sell_active and panel._batch_sell_queue.is_empty(), "批量完成后队列没有清空")
	assert(panel._selected_sell_indices.is_empty() and panel.sell_one_button.disabled, "批量完成后选择状态没有清空")
	assert("批量全部完成" in panel.detail_label.text, "最终成功消息被提交提示覆盖")

	panel.set_sell_quotes(quotes)
	panel._select_sell_item(safe_indices[0])
	panel._select_sell_item(safe_indices[1])
	sell_requests.clear()
	panel._request_sell(1)
	assert(sell_requests.size() == 1, "失败路径没有提交首笔请求")
	panel.apply_sell_result({"success": false, "message": "测试失败停止", "quotes": quotes})
	assert(sell_requests.size() == 1, "批量失败后仍提交了后续请求")
	assert(not panel._batch_sell_active and panel._batch_sell_queue.is_empty(), "批量失败后队列仍在活动")
	assert(panel._selected_sell_indices.is_empty() and "测试失败停止" in panel.detail_label.text, "批量失败后状态或消息没有收口")

	panel.set_sell_quotes(quotes)
	panel._select_sell_item(safe_indices[0])
	panel._select_sell_item(risky_index)
	sell_requests.clear()
	panel._request_sell(1)
	assert(not panel._pending_sell_request.is_empty() and sell_requests.is_empty(), "高风险批量没有在提交前进入二次确认")
	assert(panel.sell_confirmation.visible, "高风险出售没有打开公共确认组件")
	assert(panel.sell_confirmation.get_meta("stable_id", "") == "ui.confirmation.dialog", "商店没有复用公共确认组件")
	assert(panel.sell_confirmation.current_request.action_id == "shop.sell.risky_item", "商店确认操作 ID 错误")
	panel.sell_confirmation.cancel_button.pressed.emit()
	assert(panel._pending_sell_request.is_empty() and panel._batch_sell_queue.is_empty() and sell_requests.is_empty(), "取消高风险批量后仍保留待处理交易")
	panel._request_sell(1)
	panel.sell_confirmation.confirm_button.pressed.emit()
	assert(sell_requests.size() == 1 and "quote_id" in sell_requests[0], "确认后没有提交第一笔玩法层报价")
	panel.apply_sell_result({"success": true, "message": "风险批量第一笔成功", "quotes": quotes})
	assert(sell_requests.size() == 2, "风险批量第一笔成功后没有继续")
	assert(int(sell_requests[0].get("inventory_index", -1)) > int(sell_requests[1].get("inventory_index", -1)), "风险批量没有按背包索引降序")
	panel.apply_sell_result({"success": true, "message": "风险批量完成", "quotes": quotes})
	assert(panel._selected_sell_indices.is_empty() and not panel._batch_sell_active, "风险批量完成后状态没有清空")
	print("SHOP_GOTHIC_UI_PASS：单击多选/取消、独立数量、降序批量、失败停止、风险确认与镜像布局均正常")
	get_tree().quit(0)
