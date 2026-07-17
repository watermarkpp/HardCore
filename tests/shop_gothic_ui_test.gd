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
	panel._select_sell_item(0)
	assert(not panel.sell_one_button.disabled and "单件报价" in panel.detail_label.text, "有效玩法报价没有启用出售操作")
	panel._change_sell_quantity(1)
	panel._request_selected_quantity()
	assert(sell_requests.size() == 1 and int(sell_requests[0].get("amount", 0)) == 2, "出售指定数量没有提交稳定请求")
	var risky_index := -1
	for inventory_index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[inventory_index].get("name", "")) == "古铜戒指":
			risky_index = inventory_index
	assert(risky_index >= 0)
	panel._select_sell_item(risky_index)
	panel._request_sell(1)
	assert(not panel._pending_sell_request.is_empty() and sell_requests.size() == 1, "高风险装备没有进入二次确认")
	panel._confirm_pending_sell()
	assert(sell_requests.size() == 2 and "quote_id" in sell_requests[1], "确认后没有提交玩法层报价ID")
	print("SHOP_GOTHIC_UI_PASS：购买/出售分页、玩法报价、数量选择、风险确认、购买与维修入口均正常")
	get_tree().quit(0)
