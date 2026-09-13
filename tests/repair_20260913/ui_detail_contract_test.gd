extends Node

const Formatter := preload("res://scripts/item_detail_presenter.gd")
const Space := preload("res://scripts/ui_shop_detail_space.gd")
var failures: Array[String] = []
var shop: ShopPanel
var merchant: Dictionary = {}

func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)

func frames(n: int = 5) -> void:
	for i in range(n): await get_tree().process_frame

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func action_rects() -> Array:
	return [shop.buy_button.get_rect(), shop.repair_button.get_rect()]

func _run() -> void:
	if not GameData.ensure_loaded(): get_tree().quit(1); return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 1000000
	for raw: Dictionary in GameData.item_catalog:
		var item := GameData.get_item_record(raw)
		var body := Formatter.format_item(item)
		for pair: Array in [["攻击", "attackMin", "attackMax"], ["魔法", "magicMin", "magicMax"], ["道术", "taoMin", "taoMax"], ["防御", "defenseMin", "defenseMax"], ["魔防", "mdefMin", "mdefMax"]]:
			var a := int(Formatter._value(item.get(pair[1])))
			var b := int(Formatter._value(item.get(pair[2])))
			if a == 0 and b == 0: check(not body.contains(str(pair[0]) + " 0-0") and not body.contains(str(pair[0]) + " —"), str(item.get("name")) + " empty stat")
		check(not body.contains("等级0"), "empty level requirement")
		# The icon-only path and the defensive public-copy API retain exact identity.
		var art: Dictionary = item.get("art", {})
		var icon: Variant = art.get("inventoryIcon", {})
		var expected := str(icon.get("path", "")) if icon is Dictionary else str(icon)
		check(GameData.get_item_art_path(raw) == expected, "icon projection identity")
		var rules := GameData.get_item_rules_record(raw)
		var expected_rules := item.duplicate(true)
		expected_rules.erase("art")
		check(rules == expected_rules, "rule projection changed gameplay fields")
		item["name"] = "test-only mutation"
		check(str(GameData.get_item_record(raw).get("name", "")) != "test-only mutation", "catalog copy leaked")
	check(Formatter._stat_line({"attackMin": 0, "attackMax": 1, "magicMin": 1, "magicMax": 0}) == "攻击 0-1　魔法 1-0", "nonzero endpoints must survive")
	var example := Formatter.format_item({"kind": "equipment"}, {"modifiers": [{"stat": "magic_defense_max", "value": 2}, {"stat": "internal_debug_field", "value": 5}]})
	check(example.contains("魔防上限") and not example.contains("magic_defense") and not example.contains("internal_debug"), "internal stat names visible")
	shop = ShopPanel.new()
	shop.hide()
	shop.buy_quotes_requested.connect(func(stock: Array) -> void: shop.set_buy_quotes(PlayerState.shop_buy_quotes(stock, merchant)))
	shop.sell_quotes_requested.connect(func(items: Array) -> void: shop.set_sell_quotes(PlayerState.shop_sell_quotes(items)))
	add_child(shop)
	await frames()
	for key: String in GameData.merchant_catalog.get("merchants", {}):
		merchant = GameData.merchant_context(key)
		if not bool(merchant.get("supports_repair", false)): continue
		shop.open_for("铁匠", GameData.merchant_stock(key), merchant)
		var first := action_rects()
		check(shop.buy_button.get_rect().is_equal_approx(Rect2(47, 318, 270, 51)), "buy differs from approved v72 calibration")
		check(shop.repair_button.get_rect().is_equal_approx(Rect2(47, 381, 270, 51)), "repair differs from approved v72 calibration")
		await frames()
		check(first == action_rects(), "first open action geometry changes after frames")
		shop._set_trade_mode("sell")
		await frames()
		shop._set_trade_mode("buy")
		await frames()
		check(first == action_rects(), "first open differs from buy-sell-buy")
		break
	merchant = GameData.merchant_context("general")
	var scroll := GameData.get_item_record("回城卷")
	check(not scroll.is_empty(), "scroll catalog missing")
	shop.open_for("杂货商", [{"name": str(scroll.name), "pack_count": 1, "merchant_context": merchant}], merchant)
	await frames()
	shop._select_shop_item(0)
	await frames()
	# Link markup is intentionally new; all player-visible copy must still be
	# identical to the shared formatter used by inventory and warehouse.
	var body: String = shop.detail_label.get_parsed_text()
	check(body == Formatter.format_item(scroll), "shop formatter diverges from bag")
	check(body.contains("双击使用") and body.contains("城镇") and not body.contains("穿戴要求") and not body.contains("价格") and not body.contains("攻击"), "scroll contains equipment or pricing copy")
	var caption: Label = shop.get_node("DetailPanel/DetailTitle")
	check(caption.is_visible_in_tree() and caption.text == "商品详情", "section heading disappears")
	var view = shop.item_detail_presenter
	var spec: Dictionary = Space.region(shop)
	check(Rect2(view.position, view.size).position.y >= Space.rect_in(shop, caption).end.y, "detail overlaps section heading")
	check(shop.buy_button.get_rect().is_equal_approx(Rect2(47, 318, 270, 51)), "selection moved calibrated action")
	var long_body := ""
	for i in range(80): long_body += "物品说明第%d行，滚动查看剩余内容。\n" % i
	view.show_text("长说明物品", long_body, {"presentation_zone": "shop"})
	await frames()
	check(view.debug_layout_valid(), "long description layout invalid")
	check(view.detail_label.text == long_body and view.detail_label.scroll_active, "overflow body lost or cannot scroll")
	check(not view.detail_label.get_v_scroll_bar().is_visible_in_tree(), "visible detail scrollbar")
	var point: Vector2 = view.detail_label.get_global_transform_with_canvas() * (view.detail_label.size * 0.5)
	var press := InputEventScreenTouch.new()
	press.index = 0; press.position = point; press.pressed = true
	get_viewport().push_input(press, true)
	var drag := InputEventScreenDrag.new()
	drag.index = 0; drag.position = point - Vector2(0, 60); drag.relative = Vector2(0, -60)
	get_viewport().push_input(drag, true)
	press.pressed = false; press.position = drag.position
	get_viewport().push_input(press, true)
	await frames()
	check(view.detail_label.get_v_scroll_bar().value > 0.0, "real touch drag did not scroll")
	check(not view.detail_label.get_v_scroll_bar().is_visible_in_tree() and caption.visible, "drag exposed scrollbar or removed caption")
	shop.queue_free()
	await frames()
	for failure in failures: push_error(failure)
	print("UI_DETAIL_CONTRACT_%s failures=%d" % ["PASS" if failures.is_empty() else "FAIL", failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
