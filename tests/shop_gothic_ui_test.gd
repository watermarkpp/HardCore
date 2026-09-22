extends Node

const SELL_CONTRACT_PATH := "res://assets/ui/gothic_theme/v1/shop_sell_contract.json"
const UI_LAYOUT_CONTRACT := "res://assets/data/ui/manual_layout_overrides.json"
const UIOverrides := preload("res://scripts/ui_runtime_layout_overrides.gd")

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
	# The calibration profile transaction settles a few frames after the trade
	# mode switch that requested it (the context loop above applied shop_sell)
	# and replays captured `visible` state; the settled authority signal is the
	# profile-ready meta, so wait for it before adjudicating any detail layout.
	for _wait_frame in range(30):
		if UIOverrides.profile_is_ready(panel, "shop_sell"):
			break
		await get_tree().process_frame
	assert(UIOverrides.profile_is_ready(panel, "shop_sell"), "商店校准 profile 未能在有界帧内结算")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "购买页签没有保持持久选中")
	assert(panel.sell_tab_button.theme_type_variation == "GothicShopTradeTabGemButton", "未选中的出售页签错误高亮")
	assert(panel.buy_button.get_theme_font_size("font_size") == panel.sell_quantity_button.get_theme_font_size("font_size"), "购买与出售操作按钮字号不一致")
	assert(panel.buy_button.get_theme_font_size("font_size") == panel.repair_button.get_theme_font_size("font_size"), "购买与维修操作按钮字号不一致")
	var repair_gold_before := PlayerState.gold
	panel._repair_all()
	assert(PlayerState.gold == repair_gold_before, "无需维修时错误扣除了金币")
	assert(panel.repair_button.get_meta("gothic_feedback_state", "") == "failure", "同步维修结果没有立即呈现")
	await get_tree().process_frame
	assert(panel.repair_button.get_meta("gothic_feedback_state", "") == "failure", "无需维修时错误显示成功反馈")
	assert(panel.size == Vector2(1080, 620), "商店没有使用横屏安全尺寸")
	assert(panel.theme_type_variation == "GothicModalFrame", "商店没有复用公共哥特外框")
	assert(panel.gold_label.position.y >= 20.0 and panel.gold_label.vertical_alignment == VERTICAL_ALIGNMENT_CENTER, "商店金币文字仍然贴近装饰框上沿")
	var shop_safe_rect := panel.get_global_rect().grow(-18.0)
	assert(shop_safe_rect.encloses(panel.item_detail_presenter.get_global_rect()), "共享商品详情浮窗没有避开面板安全内边距：%s / %s" % [panel.item_detail_presenter.get_global_rect(), shop_safe_rect])
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
	# Ruling 6/20: the dagger detail must be adjudicated on the POST_SETTLE
	# production snapshot only. Wait for real layout stability (panel/grid
	# rects unchanged across frames), then assert the settled contract.
	var panel_rect := panel.get_global_rect()
	var grid_rect := panel.goods_grid.get_global_rect()
	var stable_frames := 0
	for _frame in range(120):
		await get_tree().process_frame
		if panel.get_global_rect() == panel_rect and panel.goods_grid.get_global_rect() == grid_rect:
			stable_frames += 1
			if stable_frames >= 3:
				break
		else:
			panel_rect = panel.get_global_rect()
			grid_rect = panel.goods_grid.get_global_rect()
			stable_frames = 0
	var settled: Dictionary = panel.item_detail_presenter.debug_layout_snapshot()
	var settled_spec: Dictionary = settled.get("space_spec", {})
	assert(bool(settled.get("valid", false)), "结算后匕首详情仍非有效布局：%s" % str(settled.get("error", "")))
	assert(not bool(settled.get("scroll_active", false)), "普通匕首详情结算后不允许滚动")
	assert(panel._trade_mode == "buy", "匕首详情结算时交易模式漂移")
	assert(panel.sell_quantity_button.visible == false and not panel.sell_quantity_button.is_visible_in_tree(), "校准回放复活了 BUY 模式的出售按钮")
	assert(panel.sell_quantity_row.visible == false, "校准回放复活了 BUY 模式的出售数量行")
	assert(panel.buy_button.visible and panel.buy_button.is_visible_in_tree(), "BUY 模式缺少购买按钮")
	assert(panel.item_detail_presenter.title_label.text == "匕首" and panel.item_detail_presenter.visible, "商品详情没有响应卡片选择")
	assert(panel.item_detail_presenter.title_label.get_theme_font_size("font_size") == 20, "详情标题没有使用正式 20 号字体")
	assert(panel.item_detail_presenter.detail_label.get_theme_font_size("normal_font_size") == 14, "详情正文没有使用正式 14 号字体")
	var detail_text: String = str(panel.item_detail_presenter.detail_label.text)
	for required_line: String in ["类别", "耐久", "攻击", "穿戴要求"]:
		assert(detail_text.contains(required_line), "匕首详情正文缺少 %s 行" % required_line)
	# Price belongs to the merchant quote/card, not the shared equipment body.
	var dagger_quote: Dictionary = panel._buy_quotes_by_index[0]
	assert(int(dagger_quote.total_price) > 0)
	assert(panel.goods_buttons[0].get_node("Price").text == "%d 金币" % int(dagger_quote.total_price), "匕首购买价未按正式报价显示")
	# Every visible action BUTTON must sit inside the frame opening (ruling 14).
	# The sell quantity row is a composite calibrated control whose frozen
	# internal child contract is asserted in the sell section below; its own
	# width is governed by that calibration, not by the button clamp.
	var opening_local: Rect2 = settled_spec.get("frame_opening", Rect2())
	assert(opening_local.has_area(), "结算快照缺少 frame_opening")
	var panel_to_global := panel.get_global_transform_with_canvas()
	var opening_global := Rect2(panel_to_global * opening_local.position, opening_local.size)
	var last_action_rect := Rect2()
	for action_name: String in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
		var action_value: Variant = panel.get(action_name)
		if action_value is Control and (action_value as Control).is_visible_in_tree():
			var action_rect := (action_value as Control).get_global_rect()
			if action_value is BaseButton:
				assert(opening_global.encloses(action_rect.grow(-1.0)), "%s 越出详情框内开孔：%s / %s" % [action_name, action_rect, opening_global])
			if last_action_rect.has_area():
				assert(not last_action_rect.intersects(action_rect), "操作按钮相互重叠")
			last_action_rect = action_rect
	# BUY → SELL → BUY cycle (ruling 21): mode/action state must round-trip and
	# the sell page must keep every stacked action inside the frame opening —
	# the stack fallback clamps restored calibration widths to the opening.
	panel._set_trade_mode("sell")
	assert(not panel.buy_button.visible and not panel.repair_button.visible, "SELL 模式仍显示购买/维修按钮")
	assert(panel.sell_quantity_row.visible and panel.sell_quantity_button.visible, "SELL 模式缺少出售数量行/按钮")
	panel.set_sell_quotes(PlayerState.shop_sell_quotes(quote_batches[-1]))
	panel._select_sell_item(0)
	for _sell_frame in range(60):
		await get_tree().process_frame
		var sell_snapshot: Dictionary = panel.item_detail_presenter.debug_layout_snapshot()
		if bool(sell_snapshot.get("valid", false)) or str(sell_snapshot.get("error", "")) == "NO_CONTENT":
			break
	var sell_settled: Dictionary = panel.item_detail_presenter.debug_layout_snapshot()
	var sell_spec: Dictionary = sell_settled.get("space_spec", {})
	var sell_opening: Rect2 = sell_spec.get("frame_opening", Rect2())
	assert(sell_opening.has_area(), "SELL 结算快照缺少 frame_opening")
	var sell_opening_global := Rect2(panel_to_global * sell_opening.position, sell_opening.size)
	var sell_last := Rect2()
	for action_name: String in ["buy_button", "repair_button", "sell_quantity_row", "sell_quantity_button"]:
		var sell_action: Variant = panel.get(action_name)
		if sell_action is Control and (sell_action as Control).is_visible_in_tree():
			var sell_rect := (sell_action as Control).get_global_rect()
			if sell_action is BaseButton:
				assert(sell_opening_global.encloses(sell_rect.grow(-1.0)), "SELL 模式 %s 越出内开孔：%s / %s" % [action_name, sell_rect, sell_opening_global])
			if sell_last.has_area():
				assert(not sell_last.intersects(sell_rect), "SELL 操作控件相互重叠")
			sell_last = sell_rect
	panel._set_trade_mode("buy")
	assert(panel.buy_button.visible and not panel.sell_quantity_button.visible and not panel.sell_quantity_row.visible, "BUY 回切未恢复第一组操作状态")
	assert(not panel.repair_button.visible, "无维修商人 BUY 回切不应显示维修按钮")
	panel._select_shop_item(0)
	assert(panel.item_detail_presenter.title_label.text == "匕首" and panel.item_detail_presenter.visible, "商品详情没有响应卡片选择")
	var gold_before := PlayerState.gold
	var buy_quote := panel._buy_quote_for_index(0)
	panel._buy_selected()
	assert(buy_requests.size() == 1 and panel.buy_button.disabled, "购买提交后没有立即锁定按钮")
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "busy", "购买请求没有进入事务忙碌反馈")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "购买事务错误清除了购买页签选中")
	var buy_result := PlayerState.buy_shop_item(buy_requests[-1], STOCK)
	panel.apply_buy_result(buy_result)
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "success", "正式购买结果没有立即替换等待反馈")
	await get_tree().process_frame
	assert(panel.buy_button.get_meta("gothic_feedback_state", "") == "success", "购买成功反馈没有保留到下一帧")
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
	var potion_profile := GameData.potion_recovery_profile(PlayerState.level, 30, 0, "delayed_restore")
	assert("持续恢复生命：每%.2f秒%d点" % [float(potion_profile.tick_interval_seconds), int(potion_profile.tick_amount)] in panel.detail_label.get_parsed_text(), "药水详情没有显示玩法层实际恢复节拍")
	assert("生命总恢复：30点" in panel.detail_label.get_parsed_text() and "攻击：" not in panel.detail_label.get_parsed_text(), "药水详情没有显示主库恢复总量")
	var official_weapon_stock := GameData.merchant_stock("starter_gear")
	panel.open_for("铁匠", official_weapon_stock, GameData.merchant_context("starter_gear"))
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(official_weapon_stock))
	for official_weapon_index in range(official_weapon_stock.size()):
		panel._select_shop_item(official_weapon_index)
		var item := GameData.get_item_record(str(official_weapon_stock[official_weapon_index].name))
		var body := panel.detail_label.get_parsed_text()
		assert("类别：" in body and "重量 %d" % int(item.weight) in body, "正式武器类别/重量未正确显示")
		assert("耐久：%d/%d" % [int(item.maxDurability), int(item.maxDurability)] in body, "正式武器耐久未正确显示")
		for stat: Array in [["攻击", "attackMin", "attackMax"], ["魔法", "magicMin", "magicMax"], ["道术", "taoMin", "taoMax"], ["防御", "defenseMin", "defenseMax"], ["魔防", "mdefMin", "mdefMax"]]:
			var minimum := 0 if item.get(stat[1]) == null else int(item[stat[1]])
			var maximum := 0 if item.get(stat[2]) == null else int(item[stat[2]])
			if minimum != 0 or maximum != 0:
				assert("%s %d-%d" % [stat[0], minimum, maximum] in body, "正式武器属性错误：%s" % stat[0])
			else:
				assert("%s 0-0" % stat[0] not in body, "紧凑详情不应显示零值属性")
		var requirement: Dictionary = preload("res://scripts/equipment_rules.gd").requirement_for(item)
		assert(("穿戴要求：" in body) == (int(requirement.get("value", 0)) > 0), "穿戴要求与正式属性不一致")
		assert("equipment.attribute" not in body and "confidence" not in body, "武器详情泄露内部字段")
	panel.open_for("测试商店", STOCK, GameData.merchant_context("general"))
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(STOCK))
	PlayerState.inventory.insert(1, {})
	panel._set_trade_mode("sell")
	assert(panel.sell_tab_button.theme_type_variation == "GothicShopTradeTabSelectedGemButton", "出售页签没有保持持久选中")
	assert(panel.buy_tab_button.theme_type_variation == "GothicShopTradeTabGemButton", "切到出售后购买页签仍保持高亮")
	assert(panel.get_node_or_null("DetailPanel/SellOneButton") == null, "已退役 SellOneButton 仍存在")
	assert("UI不会自行计算" not in panel.detail_label.get_parsed_text() and "玩法层报价" not in panel.detail_label.get_parsed_text(), "出售页仍显示无意义的内部报价备注")
	assert(panel.sell_quantity_button.name == "SellQuantityButton" and panel.sell_quantity_button.text == "出售", "出售按钮文案或唯一稳定节点错误")
	# Ruling 9: fixed 270x51 equality across modes was an implementation detail
	# of the pre-R3.3 calibration; the R3.3 space planner legitimately varies
	# action geometry per mode and region. Product constraints that remain:
	# action font parity (asserted above), calibration revision retired
	# (asserted below), and the settled opening/overlap/operability contract
	# asserted in the POST_SETTLE blocks of both trade modes.
	assert(panel.buy_button.get_theme_font_size("font_size") == panel.sell_quantity_button.get_theme_font_size("font_size"), "购买页操作按钮与出售按钮字号不一致")
	assert(panel.buy_button.get_meta("calibration_layout_revision", 0) == 1 and panel.repair_button.get_meta("calibration_layout_revision", 0) == 1, "购买页按钮没有退役旧尺寸校准")
	assert(panel.sell_quantity_button.get_meta("calibration_text_revision", 0) == 1, "出售按钮文案版本元数据缺失")
	assert(not quote_batches.is_empty() and quote_batches[-1].size() == PlayerState.inventory_occupied_count(), "出售页没有跳过空洞并保持绝对背包索引报价")
	assert(panel.goods_buttons.is_empty(), "出售页请求报价前不应提前构建物品卡片")
	assert(panel.sell_quantity_button.disabled, "没有报价时出售按钮没有禁用")
	PlayerState.test_shop_quote_debug_reset()
	var measured_sell_quotes := PlayerState.shop_sell_quotes(quote_batches[-1])
	var quote_debug: Dictionary = PlayerState.test_shop_quote_debug_snapshot()
	var unique_sell_names := {}
	for raw_sell_item: Variant in quote_batches[-1]:
		if raw_sell_item is Dictionary:
			unique_sell_names[str((raw_sell_item as Dictionary).get("item_name", ""))] = true
	assert(not measured_sell_quotes.is_empty(), "局部报价缓存测量没有返回出售报价")
	assert(int(quote_debug.get("merchant_context_lookups", 0)) == 1, "同一批次出售报价重复解析了商人上下文")
	assert(
		int(quote_debug.get("catalog_lookups", 0)) == unique_sell_names.size()
		and int(quote_debug.get("price_record_lookups", 0)) == unique_sell_names.size()
		and int(quote_debug.get("base_price_lookups", 0)) == unique_sell_names.size(),
		"出售报价批次没有使用局部物品/价格缓存：%s names=%s" % [quote_debug, unique_sell_names.keys()],
	)
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
	PlayerState.test_shop_quote_debug_reset()
	panel.debug_reset_operation_counters()
	PlayerState.test_mode = false
	PlayerState.shop_sell_quotes(quote_batches[-1])
	panel.set_sell_quotes(quotes)
	var production_quote_debug := PlayerState.test_shop_quote_debug_snapshot()
	var production_panel_debug := panel.debug_operation_counters()
	PlayerState.test_mode = true
	for quote_counter_value: Variant in production_quote_debug.values():
		assert(int(quote_counter_value) == 0, "正式运行仍在累计出售报价诊断计数")
	for panel_counter_value: Variant in production_panel_debug.values():
		assert(int(panel_counter_value) == 0, "正式运行仍在累计出售面板诊断计数")
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
		var sell_name := card.get_node("ItemName") as Label
		var sell_price := card.get_node("Price") as Label
		assert(sell_name.position.y == 11.0 and sell_price.position.y == 39.0, "可售卡片名称与价格没有使用双行安全位置")
		assert(sell_name.position.y + sell_name.size.y <= sell_price.position.y, "可售卡片名称与价格发生垂直重叠")
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
	var ring_item := GameData.get_item_record("古铜戒指")
	assert("攻击 %d-%d" % [int(ring_item.attackMin), int(ring_item.attackMax)] in panel.detail_label.get_parsed_text() and "穿戴要求" in panel.detail_label.get_parsed_text(), "出售装备详情没有展示正式攻击/穿戴要求")
	assert("防御 0-0" not in panel.detail_label.get_parsed_text(), "出售详情不应重复展示零值防御")
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
	assert((blocked_card.get_node("ItemName") as Label).position.y == 22.0, "不可售卡片隐藏价格后名称没有恢复单行居中")
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
	assert(panel._selected_sell_indices.is_empty() and panel.sell_quantity_button.disabled, "批量完成后选择状态没有清空")
	assert("批量全部完成" in panel.detail_label.get_parsed_text(), "最终成功消息被提交提示覆盖")

	panel.set_sell_quotes(quotes)
	panel._select_sell_item(safe_indices[0])
	panel._select_sell_item(safe_indices[1])
	sell_requests.clear()
	panel._request_sell()
	assert(sell_requests.size() == 1 and sell_requests[0].get("batch", null) is Array, "失败路径没有提交batch请求")
	panel.apply_sell_result({"success": false, "message": "测试失败停止", "quotes": quotes})
	assert(panel._selected_sell_indices.is_empty() and "测试失败停止" in panel.detail_label.get_parsed_text(), "批量失败后状态或消息没有收口")

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
	assert(panel._pending_sell_request.is_empty() and sell_requests.is_empty(), "取消高风险批量后仍保留待处理交易")
	panel._request_sell()
	panel.sell_confirmation.confirm_button.pressed.emit()
	assert(sell_requests.size() == 1 and sell_requests[0].get("batch", null) is Array, "确认后没有一次提交风险批量")
	assert((sell_requests[0].get("batch", []) as Array).size() == 2, "风险批量缺少选中物品")
	panel.apply_sell_result({"success": true, "message": "风险批量完成", "quotes": quotes})
	assert(panel._selected_sell_indices.is_empty(), "风险批量完成后状态没有清空")
	print("SHOP_GOTHIC_UI_PASS：单击多选/取消、独立数量、降序批量、失败停止、风险确认与镜像布局均正常")
	get_tree().quit(0)


func _record_at(index: int) -> Dictionary:
	if index < 0 or index >= PlayerState.inventory.size():
		return {}
	var record: Variant = PlayerState.inventory[index]
	return record if record is Dictionary and not (record as Dictionary).is_empty() else {}
