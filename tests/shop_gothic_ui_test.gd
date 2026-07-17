extends Node

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
	PlayerState.reset_progress()
	PlayerState.gold = 1000
	var panel := ShopPanel.new()
	add_child(panel)
	await get_tree().process_frame
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
	print("SHOP_GOTHIC_UI_PASS：双格商品卡、原始图标、选择详情、购买与维修入口均正常")
	get_tree().quit(0)
