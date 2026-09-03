extends Node

const SELL_CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/shop_sell_contract.json"
const UI_LAYOUT_CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"

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
	var buy_requests: Array = []
	panel.sell_quotes_requested.connect(func(items: Array) -> void: quote_batches.append(items))
	panel.sell_requested.connect(func(request: Dictionary) -> void: sell_requests.append(request))
	panel.buy_requested.connect(func(request: Dictionary) -> void: buy_requests.append(request))
	var buy_content_updates_before_open := panel._goods_card_content_update_count
	panel.open_for("测试商店", STOCK)
	assert(panel.goods_buttons.is_empty() and panel._goods_card_content_update_count == buy_content_updates_before_open, "购买报价到达前提前绑定商品卡内容")
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(STOCK))
	assert(panel._goods_card_content_update_count == buy_content_updates_before_open + STOCK.size(), "一次购买报价没有恰好绑定 stock.size 个卡片内容")
	var medicine_context := GameData.merchant_context("medicine")
	panel.open_for("空库存药剂商", [], medicine_context)
	assert(
		str(panel._active_merchant_context().get("merchant_id", ""))
		== str(medicine_context.get("merchant_id", "")),
		"空库存商店必须使用显式 merchant_context"
	)
	# The NPC-provided context must survive an empty/filtered stock and reach
	# the authoritative PlayerState quote path for every shop category.
	var saved_inventory := PlayerState.inventory.duplicate(true)
	PlayerState.inventory = [{"name": "匕首", "count": 1, "instance_id": "shop-context-dagger"}]
	for context_key: String in ["general", "books", "medicine"]:
		var context := GameData.merchant_context(context_key)
		panel.open_for("上下文测试", GameData.merchant_stock(context_key), context)
		panel._set_trade_mode("sell")
		assert(not quote_batches.is_empty() and not quote_batches[-1].is_empty(), "%s 没有发出出售报价请求" % context_key)
		var context_quotes := PlayerState.shop_sell_quotes(quote_batches[-1])
		var context_quote: Dictionary = context_quotes.get("instance:shop-context-dagger", {})
		assert(bool(context_quote.get("sellable", false)), "%s NPC 上下文下匕首出售报价无效" % context_key)
		assert(int(context_quote.get("unit_price", 0)) > 0, "%s NPC 上下文下匕首没有出售价格" % context_key)
		panel.set_sell_quotes(context_quotes)
		panel._select_sell_item(0)
		assert(not panel.sell_quantity_button.disabled, "%s NPC 下出售按钮未因有效装备报价启用" % context_key)
	PlayerState.inventory = saved_inventory
	panel.open_for("测试商店", STOCK)
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(STOCK))
	await get_tree().process_frame
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "购买页签没有保持持久选中")
	assert(panel.sell_tab_button.theme_type_variation == "GothicShopTradeTabGemButton", "未选中的出售页签错误高亮")
	assert(panel.buy_button.get_theme_font_size("font_size") == panel.sell_quantity_button.get_theme_font_size("font_size"), "购买与出售操作按钮字号不一致")
	assert(panel.buy_button.get_theme_font_size("font_size") == panel.repair_button.get_theme_font_size("font_size"), "购买与维修操作按钮字号不一致")
	var repair_gold_before := PlayerState.gold
	panel._repair_all()
	assert(PlayerState.gold == repair_gold_before, "无需维修时错误扣除了金币")
	assert(panel.repair_button.get_meta("gothic_feedback_state", "") == "busy", "维修忙碌反馈没有完整保留一个渲染帧")
	await get_tree().process_frame
	assert(panel.repair_button.get_meta("gothic_feedback_state", "") == "failure", "无需维修时错误显示成功反馈")
	assert(panel.size == Vector2(1080, 620), "商店没有使用横屏安全尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "商店没有复用公共哥特外框")
	assert(panel.gold_label.position.y >= 20.0 and panel.gold_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "商店金币文字仍然贴近装饰框上沿")
	assert(panel.detail_label.position.x >= 24.0 and panel.detail_label.position.y >= 60.0, "商品详情文字没有避开装饰框安全内边距")
	assert(panel.detail_label.get_meta("calibration_runtime_text", false), "商店动态详情文字会被旧校准文案覆盖")
	assert(panel.goods_grid.columns == 2 and panel.goods_buttons.size() == STOCK.size(), "商品没有使用两列双格卡布局")
	var buy_card_creation_count := panel._goods_card_creation_count
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(STOCK))
	assert(panel._goods_card_creation_count == buy_card_creation_count, "购买报价刷新重复创建商品卡")
	assert(panel._buy_quotes_by_index.size() == STOCK.size(), "购买报价没有建立 stock_index 常数时间索引")
	var goods_scroll := panel.get_node("GoodsPanel/GoodsScroll") as ScrollContainer
	assert(goods_scroll.get_theme_stylebox("panel") is StyleBoxEmpty, "出售商品阵列外仍保留多余细框")
	assert(not panel.item_list.visible and panel.item_list.item_count == STOCK.size(), "商店兼容选择列表异常")
	for card: Button in panel.goods_buttons:
		assert(card.size == Vector2(286, 72), "双格商品卡比例错误")
		assert(card.has_node("ItemName") and card.has_node("Price"), "双格商品卡缺少名称或价格区域")
		assert(card.get_theme_stylebox("normal") is StyleBoxFlat, "购买商品卡没有使用背包格清晰代码边框")
	panel._select_shop_item(0)
	assert(panel.item_list.get_selected_items() == PackedInt32Array([0]), "商品卡选择没有同步购买逻辑")
	assert(panel.goods_buttons[0].theme_type_variation == "GothicComponentSelectedShopCard", "选中商品没有公共高亮状态")
	assert("匕首" in panel.detail_label.text, "商品详情没有响应卡片选择")
	var gold_before := PlayerState.gold
	var buy_quote := panel._buy_quote_for_index(0)
	panel._buy_selected()
	assert(buy_requests.size() == 1 and panel.buy_button.disabled, "购买提交后没有立即锁定按钮")
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "busy", "购买请求没有进入事务忙碌反馈")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "购买事务错误清除了购买页签选中")
	var buy_result := PlayerState.buy_shop_item(buy_requests[-1], STOCK)
	panel.apply_buy_result(buy_result)
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "busy", "购买结果在同一帧覆盖了忙碌反馈")
	await get_tree().process_frame
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "success", "购买成功没有进入一秒成功反馈")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "购买完成错误清除了购买页签选中")
	assert(PlayerState.gold == gold_before - int(buy_quote.get("unit_price", 0)) and PlayerState.has_item("匕首"), "商品卡购买闭环失败")
	assert(panel._selected_buy_index == 0 and panel.item_list.get_selected_items() == PackedInt32Array([0]), "购买刷新报价后丢失当前商品选择")
	assert(panel.goods_buttons[0].theme_type_variation == "GothicComponentSelectedShopCard", "购买刷新报价后丢失商品卡高亮")
	await get_tree().create_timer(0.25).timeout
	assert(not panel.buy_button.disabled, "购买短冷却结束后按钮没有恢复")
	var second_quote := panel._buy_quote_for_index(0)
	panel._buy_selected()
	assert(buy_requests.size() == 2 and panel.buy_button.disabled, "购买冷却结束后无法再次提交")
	var second_result := PlayerState.buy_shop_item(buy_requests[-1], STOCK)
	panel.apply_buy_result(second_result)
	assert(panel._selected_buy_index == 0 and panel.item_list.get_selected_items() == PackedInt32Array([0]), "第二次购买后丢失当前商品选择")
	await get_tree().create_timer(0.25).timeout
	var official_potion_stock := GameData.merchant_stock("medicine")
	panel.open_for("药剂商", official_potion_stock, GameData.merchant_context("medicine"))
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(official_potion_stock))
	panel._select_shop_item(0)
	assert("持续恢复生命：" in panel.detail_label.text and "点/秒" in panel.detail_label.text, "药水详情没有显示玩法层实际持续恢复速度")
	assert("生命总恢复：30点" in panel.detail_label.text and "攻击：" not in panel.detail_label.text, "药水详情没有显示主库恢复总量")
	var official_weapon_stock := GameData.merchant_stock("starter_gear")
	panel.open_for("铁匠", official_weapon_stock, GameData.merchant_context("starter_gear"))
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(official_weapon_stock))
	for official_weapon_index in range(official_weapon_stock.size()):
		panel._select_shop_item(official_weapon_index)
		assert(
			"类别：" in panel.detail_label.text
			and "重量：" in panel.detail_label.text
			and "耐久上限：" in panel.detail_label.text
			and "攻击" in panel.detail_label.text
			and "魔法" in panel.detail_label.text
			and "道术" in panel.detail_label.text
			and "防御" in panel.detail_label.text
			and "魔防" in panel.detail_label.text
			and "穿戴要求：" in panel.detail_label.text
			and "equipment.attribute" not in panel.detail_label.text
			and "confidence" not in panel.detail_label.text,
			"正式武器详情没有完整解析玩家可读属性",
		)
	panel.open_for("测试商店", STOCK, GameData.merchant_context("general"))
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(STOCK))
	PlayerState.inventory.insert(1, {})
	panel._set_trade_mode("sell")
	assert(panel.sell_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "出售页签没有保持持久选中")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabGemButton", "切到出售后购买页签仍保持高亮")
	assert(panel.get_node_or_null("DetailPanel/SellOneButton") == null, "已退役 SellOneButton 仍存在")
	assert("UI不会自行计算" not in panel.detail_label.text and "玩法层报价" not in panel.detail_label.text, "出售页仍显示无意义的内部报价备注")
	assert(panel.sell_quantity_button.name == "SellQuantityButton" and panel.sell_quantity_button.text == "出售", "出售按钮文案或唯一稳定节点错误")
	assert(panel.buy_button.size == panel.repair_button.size and panel.buy_button.size == Vector2(270, 51), "购买页两个操作按钮没有统一为出售按钮规格")
	assert(panel.buy_button.get_meta("calibration_layout_revision", 0) == 1 and panel.repair_button.get_meta("calibration_layout_revision", 0) == 1, "购买页按钮没有退役旧尺寸校准")
	assert(panel.sell_quantity_button.get_meta("calibration_text_revision", 0) == 1, "出售按钮文案版本元数据缺失")
	assert(not quote_batches.is_empty() and quote_batches[-1].size() == PlayerState.inventory_occupied_count(), "出售页没有跳过空洞并保持绝对背包索引报价")
	assert(panel.goods_buttons.is_empty(), "出售页请求报价前不应提前构建物品卡片")
	assert(panel.sell_quantity_button.disabled, "没有报价时出售按钮没有禁用")
	var quotes := {}
	for inventory_index in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[inventory_index] if PlayerState.inventory[inventory_index] is Dictionary else {}
		if record.is_empty():
			continue
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
	var synchronous_sell_quotes := [false]
	panel.sell_quotes_requested.connect(func(items: Array) -> void:
		if bool(synchronous_sell_quotes[0]):
			panel.set_sell_quotes(PlayerState.shop_sell_quotes(items))
	)
	var sell_content_updates_before_signal := panel._goods_card_content_update_count
	synchronous_sell_quotes[0] = true
	PlayerState.inventory_changed.emit()
	await get_tree().process_frame
	synchronous_sell_quotes[0] = false
	assert(
		panel._goods_card_content_update_count - sell_content_updates_before_signal == PlayerState.inventory_occupied_count(),
		"一次出售库存刷新没有恰好绑定 occupied_count 个卡片内容"
	)
	assert(panel.goods_buttons.size() == PlayerState.inventory_occupied_count(), "同步出售报价回调绑定的新卡被再次清空")
	var sell_content_updates_before_success := panel._goods_card_content_update_count
	synchronous_sell_quotes[0] = true
	panel.apply_sell_result({"success": true, "message": "测试出售完成且结果不携带报价"})
	synchronous_sell_quotes[0] = false
	assert(
		panel._goods_card_content_update_count - sell_content_updates_before_success == PlayerState.inventory_occupied_count(),
		"出售成功无返回报价路径重复绑定卡片内容"
	)
	assert(panel.goods_buttons.size() == PlayerState.inventory_occupied_count(), "出售成功同步报价回调绑定的新卡被再次清空")
	panel.set_sell_quotes(quotes)
	var sell_card_creation_count := panel._goods_card_creation_count
	var sell_refresh_before: Dictionary = panel.debug_operation_counters()
	panel.set_sell_quotes(quotes)
	var sell_refresh_after: Dictionary = panel.debug_operation_counters()
	assert(panel._goods_card_creation_count == sell_card_creation_count, "出售报价刷新重复创建商品卡")
	assert(
		int(sell_refresh_after.get("sell_structure_bind_count", 0))
			== int(sell_refresh_before.get("sell_structure_bind_count", 0)),
		"相同背包结构的报价刷新不应重新绑定出售卡片结构",
	)
	assert(
		int(sell_refresh_after.get("sell_quote_patch_count", 0))
			== int(sell_refresh_before.get("sell_quote_patch_count", 0)) + 1,
		"相同背包结构的报价刷新必须走局部报价更新",
	)
	assert(
		int(sell_refresh_after.get("goods_card_visibility_change_count", 0))
			== int(sell_refresh_before.get("goods_card_visibility_change_count", 0))
			and int(sell_refresh_after.get("goods_card_content_update_count", 0))
			== int(sell_refresh_before.get("goods_card_content_update_count", 0))
			and int(sell_refresh_after.get("sell_catalog_lookup_count", 0))
			== int(sell_refresh_before.get("sell_catalog_lookup_count", 0))
			and int(sell_refresh_after.get("sell_texture_lookup_count", 0))
			== int(sell_refresh_before.get("sell_texture_lookup_count", 0)),
		"报价局部更新不应触发布局、内容绑定或 GameData/纹理查表",
	)
	var stable_sell_card_count := panel.goods_buttons.size()
	var visibility_before_structure_change: Dictionary = panel.debug_operation_counters()
	PlayerState.inventory.append({"name": "太阳水", "count": 1, "instance_id": "shop-structure-probe"})
	panel.set_sell_quotes(quotes)
	assert(panel.goods_buttons.size() == stable_sell_card_count + 1, "出售背包结构增加后没有只追加一张活动卡")
	PlayerState.inventory.pop_back()
	panel.set_sell_quotes(quotes)
	var visibility_after_structure_change: Dictionary = panel.debug_operation_counters()
	assert(panel.goods_buttons.size() == stable_sell_card_count, "出售背包结构恢复后活动卡数量错误")
	assert(
		int(visibility_after_structure_change.get("goods_card_visibility_change_count", 0))
			== int(visibility_before_structure_change.get("goods_card_visibility_change_count", 0)) + 2,
		"出售卡片池结构增减没有只变更新增/移除卡片的可见性",
	)
	for card: Button in panel.goods_buttons:
		assert(not _record_at(int(card.get_meta("inventory_index", -1))).is_empty(), "出售卡错误映射到背包空洞")
	for card: Button in panel.goods_buttons:
		assert(card.get_theme_stylebox("normal") is StyleBoxFlat, "出售商品卡没有使用背包格清晰代码边框")
		assert(card.has_node("Price"), "可出售商品卡缺少单件售价")
	var safe_indices: Array[int] = []
	var risky_index := -1
	for inventory_index in range(PlayerState.inventory.size()):
		if not PlayerState.inventory[inventory_index] is Dictionary or (PlayerState.inventory[inventory_index] as Dictionary).is_empty():
			continue
		if str(PlayerState.inventory[inventory_index].get("name", "")) == "古铜戒指":
			risky_index = inventory_index
		else:
			safe_indices.append(inventory_index)
	assert(safe_indices.size() >= 2 and risky_index >= 0, "出售测试缺少两个普通物品和一个高风险物品")
	panel._select_sell_item(risky_index)
	assert(panel.goods_buttons.filter(func(card: Button) -> bool: return int(card.get_meta("inventory_index", -1)) == risky_index)[0].theme_type_variation == "GothicComponentSelectedShopCard", "装备商品卡选中后没有背包格高亮")
	assert("攻击" in panel.detail_label.text and "防御" in panel.detail_label.text and "穿戴要求" in panel.detail_label.text, "出售装备详情没有展示玩家属性")
	panel._select_sell_item(risky_index)
	var deselected_risky_card: Button = panel.goods_buttons.filter(func(card: Button) -> bool: return int(card.get_meta("inventory_index", -1)) == risky_index)[0]
	assert(not deselected_risky_card.button_pressed, "取消选择后仍保留按钮按下状态")
	assert(deselected_risky_card.theme_type_variation == "GothicComponentShopCard", "取消选择后仍保留高亮边框样式")
	assert(not deselected_risky_card.has_focus(), "取消选择后焦点边框没有释放")

	assert(panel.sell_quantity_row.get_node_or_null("DecreaseQuantity/QuantityDecoration") == null, "减号按钮不应恢复旧角饰")
	assert(panel.sell_quantity_row.get_node_or_null("IncreaseQuantity/QuantityDecoration") == null, "加号按钮不应恢复旧角饰")
	assert(
		panel.sell_quantity_row.get_node("DecreaseQuantity").theme_type_variation == "GothicShopSellQuantityPlainButton"
		and panel.sell_quantity_row.get_node("IncreaseQuantity").theme_type_variation == "GothicShopSellQuantityPlainButton",
		"数量按钮没有保留已验收的无宝石框"
	)
	var bg := panel.sell_quantity_row.get_node("QuantityCenterBackground") as Panel
	assert(Rect2(Vector2.ZERO, panel.sell_quantity_row.size).encloses(Rect2(bg.position, bg.size)), "中心背景越出数量行")
	assert(Rect2(Vector2.ZERO, panel.sell_quantity_row.size).encloses(Rect2(panel.sell_quantity_label.position, panel.sell_quantity_label.size)), "数量标签越出数量行")
	var decrease := panel.sell_quantity_row.get_node("DecreaseQuantity") as Button
	var increase := panel.sell_quantity_row.get_node("IncreaseQuantity") as Button
	var layout_contract: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(UI_LAYOUT_CONTRACT))
	var sell_nodes: Dictionary = layout_contract["profiles"]["shop_sell"]["nodes"]
	for saved_path: String in ["DetailPanel/SellQuantityRow/DecreaseQuantity", "DetailPanel/SellQuantityRow/IncreaseQuantity"]:
		var saved_rect: Array = sell_nodes[saved_path]["logicalRect"]
		var actual := panel.get_node(saved_path) as Control
		assert(actual.position.is_equal_approx(Vector2(float(saved_rect[0]), float(saved_rect[1]))) and actual.size.is_equal_approx(Vector2(float(saved_rect[2]), float(saved_rect[3]))), "出售数量按钮必须与正式校准合同一致")
	# The accepted calibration lets the ornamental center background tuck slightly
	# under the +/- frames. Their independent hit rectangles must remain separate.
	assert(not decrease.get_global_rect().intersects(increase.get_global_rect()), "数量减号与加号点击区不应重叠")

	var row_global := panel.sell_quantity_row.get_global_rect()
	assert(row_global.encloses(bg.get_global_rect()) and row_global.encloses(panel.sell_quantity_label.get_global_rect()))
	assert(decrease.size.is_equal_approx(Vector2(58, 46)) and increase.size.is_equal_approx(Vector2(58, 46)))
	assert(row_global.encloses(decrease.get_global_rect()) and row_global.encloses(increase.get_global_rect()))
	assert(decrease.position.x >= 0.0 and row_global.size.x - (increase.position.x + increase.size.x) >= 0.0)
	assert(Rect2(Vector2.ZERO, bg.size).encloses(Rect2(panel.sell_quantity_label.position - bg.position, panel.sell_quantity_label.size)))
	assert(decrease.text.is_empty() and increase.text.is_empty())
	var modal_surface := panel.get_node("ModalSurface") as Control
	var goods_frame := panel.get_node("GoodsPanel") as Control
	var detail_frame := panel.get_node("DetailPanel") as Control
	var outer_surface := panel.get_node("ModalSurface") as Control
	var goods_decoration := panel.get_node("GoodsPanel/GoodsPanelDecoration") as Control
	var goods_surface := panel.get_node("GoodsPanel/GoodsPanelDecoration/GoodsPanelFill") as Control
	var goods_visual_frame := panel.get_node("GoodsPanel/GoodsPanelDecoration/GoodsPanelFrame") as Control
	var detail_decoration := panel.get_node("DetailPanel/DetailPanelDecoration") as Control
	var detail_surface := panel.get_node("DetailPanel/DetailPanelDecoration/DetailPanelFill") as Control
	var detail_visual_frame := panel.get_node("DetailPanel/DetailPanelDecoration/DetailPanelFrame") as Control
	assert(outer_surface.get_global_rect().end.y <= panel.get_global_rect().end.y - 32.0)
	assert(outer_surface.position.x >= 40.0 and outer_surface.position.y >= 40.0)
	assert(panel.size.x - (outer_surface.position.x + outer_surface.size.x) >= 40.0 and panel.size.y - (outer_surface.position.y + outer_surface.size.y) >= 40.0)
	assert(outer_surface.get_global_rect().encloses(goods_frame.get_global_rect()) and outer_surface.get_global_rect().encloses(detail_frame.get_global_rect()))
	assert(goods_frame.get_global_rect().end.y <= panel.get_global_rect().end.y - 60.0 and detail_frame.get_global_rect().end.y <= panel.get_global_rect().end.y - 60.0)
	assert(goods_decoration.get_global_rect().size.x > 0.0 and goods_decoration.get_global_rect().size.y > 0.0 and detail_decoration.get_global_rect().size.x > 0.0 and detail_decoration.get_global_rect().size.y > 0.0)
	assert(goods_surface.get_global_rect().size.x > 0.0 and goods_visual_frame.get_global_rect().size.x > 0.0)
	assert(detail_surface.get_global_rect().size.x > 0.0 and detail_visual_frame.get_global_rect().size.x > 0.0)
	assert(goods_surface.get_meta("calibration_internal_visual", false) and detail_surface.get_meta("calibration_internal_visual", false))
	assert(goods_visual_frame.theme_type_variation == "GothicInsetFrame" and detail_visual_frame.theme_type_variation == "GothicInsetFrame")
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
	assert(absf(decrease.get_global_rect().get_center().y - increase.get_global_rect().get_center().y) <= 1.0)
	assert(modal_surface.get_global_rect().encloses(goods_frame.get_global_rect()) and modal_surface.get_global_rect().encloses(detail_frame.get_global_rect()))
	panel._select_sell_item(safe_indices[0])
	assert(decrease.disabled and not increase.disabled, "堆叠物品初始数量边界错误")
	increase.button_down.emit()
	assert(int(panel._sell_quantities.get(safe_indices[0], 0)) == 2, "第一个物品的独立数量未生效")
	assert(not panel._quantity_hold_timer.is_stopped() and is_equal_approx(panel._quantity_hold_timer.wait_time, panel.QUANTITY_HOLD_INITIAL_DELAY), "按住加号没有启动首段长按等待")
	panel._on_quantity_hold_timeout()
	assert(increase.disabled and panel._quantity_hold_timer.is_stopped(), "长按加号没有持续运行到最大数量后停止")
	assert(panel._quantity_hold_interval < panel.QUANTITY_HOLD_INITIAL_DELAY, "数量长按没有进入加速阶段")
	increase.button_up.emit()
	decrease.button_down.emit()
	assert(int(panel._sell_quantities.get(safe_indices[0], 0)) == 2, "减号按下没有立即减少数量")
	decrease.button_up.emit()
	panel._change_sell_quantity(-99)
	assert(decrease.disabled, "回到1时减少按钮未禁用")
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
	var blocked_card: Button = panel.goods_buttons.filter(
		func(card: Button) -> bool:
			return int(card.get_meta("inventory_index", -1)) == risky_index
	)[0] as Button
	var blocked_price := blocked_card.get_node_or_null("Price") as Label
	assert(blocked_price == null or not blocked_price.visible, "不可出售原因不应显示在物品列表")
	panel._select_sell_item(risky_index)
	assert(decrease.disabled and increase.disabled, "不可售/count1物品数量按钮未禁用")
	assert(panel._selected_sell_indices.size() == 2, "点击不可售物品破坏了已有多选")
	assert(not panel.sell_quantity_button.disabled, "查看不可售物品错误禁用了已有批量出售")
	panel.set_sell_quotes(quotes)
	panel._sell_quantities[safe_indices[0]] = 2
	panel._sell_quantities[safe_indices[1]] = 1

	sell_requests.clear()
	panel._request_selected_quantity()
	assert(sell_requests.size() == 1 and sell_requests[0].get("batch", null) is Array, "批量出售没有一次提交batch")
	var batch_requests: Array = sell_requests[0].get("batch", [])
	assert(batch_requests.size() == 2, "批量出售没有包含全部选中物品")
	var amounts_by_index := {
		int(batch_requests[0].get("inventory_index", -1)): int(batch_requests[0].get("amount", 0)),
		int(batch_requests[1].get("inventory_index", -1)): int(batch_requests[1].get("amount", 0)),
	}
	assert(int(amounts_by_index.get(safe_indices[0], 0)) == 2, "批量出售丢失第一个物品的独立数量")
	assert(int(amounts_by_index.get(safe_indices[1], 0)) == 1, "批量出售错误复用了其他物品数量")
	panel.apply_sell_result({"success": true, "message": "批量全部完成", "quotes": quotes})
	assert(not panel._batch_sell_active and panel._batch_sell_queue.is_empty(), "批量完成后队列没有清空")
	assert(panel._selected_sell_indices.is_empty() and panel.sell_quantity_button.disabled, "批量完成后选择状态没有清空")
	assert("批量全部完成" in panel.detail_label.text, "最终成功消息被提交提示覆盖")

	panel.set_sell_quotes(quotes)
	panel._select_sell_item(safe_indices[0])
	panel._select_sell_item(safe_indices[1])
	sell_requests.clear()
	panel._request_sell()
	assert(sell_requests.size() == 1 and sell_requests[0].get("batch", null) is Array, "失败路径没有提交batch请求")
	panel.apply_sell_result({"success": false, "message": "测试失败停止", "quotes": quotes})
	assert(not panel._batch_sell_active and panel._batch_sell_queue.is_empty(), "批量失败后队列仍在活动")
	assert(panel._selected_sell_indices.is_empty() and "测试失败停止" in panel.detail_label.text, "批量失败后状态或消息没有收口")

	panel.set_sell_quotes(quotes)
	panel._select_sell_item(safe_indices[0])
	panel._select_sell_item(risky_index)
	sell_requests.clear()
	panel._request_sell()
	assert(not panel._pending_sell_request.is_empty() and sell_requests.is_empty(), "高风险批量没有在提交前进入二次确认")
	assert(panel.sell_confirmation.visible, "高风险出售没有打开公共确认组件")
	assert(panel.sell_confirmation.get_meta("stable_id", "") == "ui.confirmation.dialog", "商店没有复用公共确认组件")
	assert(panel.sell_confirmation.current_request.action_id == "shop.sell.risky_item", "商店确认操作 ID 错误")
	panel.sell_confirmation.cancel_button.pressed.emit()
	assert(panel._pending_sell_request.is_empty() and panel._batch_sell_queue.is_empty() and sell_requests.is_empty(), "取消高风险批量后仍保留待处理交易")
	panel._request_sell()
	panel.sell_confirmation.confirm_button.pressed.emit()
	assert(sell_requests.size() == 1 and sell_requests[0].get("batch", null) is Array, "确认后没有一次提交风险批量")
	assert((sell_requests[0].get("batch", []) as Array).size() == 2, "风险批量缺少选中物品")
	panel.apply_sell_result({"success": true, "message": "风险批量完成", "quotes": quotes})
	assert(panel._selected_sell_indices.is_empty() and not panel._batch_sell_active, "风险批量完成后状态没有清空")
	print("SHOP_GOTHIC_UI_PASS：单击多选/取消、独立数量、降序批量、失败停止、风险确认与镜像布局均正常")
	get_tree().quit(0)


func _record_at(index: int) -> Dictionary:
	if index < 0 or index >= PlayerState.inventory.size():
		return {}
	var record: Variant = PlayerState.inventory[index]
	return record if record is Dictionary and not (record as Dictionary).is_empty() else {}
