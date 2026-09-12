extends Node
## REAL ShopPanel, real quotes. Short layout/lifecycle regression, NOT latency.
const Shop := preload("res://scripts/shop_panel.gd")
const Names := preload("res://scripts/ui_item_name_style.gd")
const Space := preload("res://scripts/ui_shop_detail_space.gd")
const Bounds := preload("res://scripts/ui_style_visual_bounds.gd")
var panel
var merchant: Dictionary = {}
var failures: Array[String] = []
var checks := 0
var finished := false
var started := 0
func _ready() -> void:
	started = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.test_mode = true
	_run.call_deferred()
func _process(_delta: float) -> void:
	if not finished and Time.get_ticks_msec() - started > 40000:
		failures.append("SESSION_WATCHDOG")
		finish()
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures.append(label)
func frames(n: int = 3) -> void:
	for i in range(n):
		await get_tree().process_frame
func buy_quotes(stock: Array) -> void:
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(stock, merchant))
func sell_quotes(requests: Array) -> void:
	panel.set_sell_quotes(PlayerState.shop_sell_quotes(requests))
func inspect(expected_name: String, expected_body: String, item: Dictionary, instance: Dictionary) -> void:
	var view = panel.item_detail_presenter
	var snapshot: Dictionary = view.debug_layout_snapshot()
	var caption: Label = panel.get_node("DetailPanel/DetailTitle")
	check(view.debug_layout_valid(), expected_name + " invalid layout")
	check(view.is_visible_in_tree() and view.modulate.a > 0.99, "detail invisible")
	check(not caption.visible, "duplicate section caption")
	check(view.title_label.is_visible_in_tree() and view.title_label.text == expected_name, "item title lost")
	check(view.detail_label.text == expected_body, "body lost/rewritten")
	check(view.title_label.get_theme_color("font_color") == Names.describe(item, instance)["color"], "rarity color changed")
	check(not view.detail_label.scroll_active and not view.detail_label.get_v_scroll_bar().is_visible_in_tree(), "scrollbar")
	check(float(view.detail_label.get_content_height()) <= view.detail_label.size.y, "body overflow")
	check(view.title_label.get_theme_font_size("font_size") == 20 and view.detail_label.get_theme_font_size("normal_font_size") == 14, "fonts changed")
	check(float(snapshot["margin"]) == 18.0 and float(snapshot["title_gap"]) == 12.0, "spacing compressed")
	# Independent opening from the locked frame artwork, not planner.region.
	var dec: Control = panel.get_node("DetailPanel/DetailPanelDecoration")
	var opening: Rect2 = Space.rect_in(panel, dec, Rect2(Vector2(31, 26), dec.size - Vector2(62, 52)))
	var actual := Rect2(view.position, view.size)
	var scale: Vector2 = Space.screen_scale(panel)
	check(scale.x > 0.0 and scale.y > 0.0, "invalid scale")
	var gaps: Array[float] = [
		(actual.position.x - opening.position.x) * scale.x,
		(opening.end.x - actual.end.x) * scale.x,
		(actual.position.y - opening.position.y) * scale.y,
		(opening.end.y - actual.end.y) * scale.y,
	]
	for gap: float in gaps:
		check(gap >= 30.0 - 0.05, "frame clearance below 30px")
	for action: Variant in [panel.buy_button, panel.repair_button, panel.sell_quantity_row, panel.sell_quantity_button]:
		if action is Control and action.is_visible_in_tree():
			var bounds: Dictionary = Bounds.control_bounds(action)
			check(bool(bounds.get("ok", false)), "action bounds invalid")
			if bool(bounds.get("ok", false)):
				var drawn: Rect2 = Space.rect_in(panel, action, bounds["rect"])
				check((drawn.position.y - actual.end.y) * scale.y >= 32.0 - 0.05, "action clearance below 32px")
	check(view.size.x <= 1.3 * view.size.y + 0.5, "overly flat rectangle")
func _run() -> void:
	if not GameData.ensure_loaded():
		failures.append("DATA_MISSING"); finish(); return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 1000000
	PlayerState.recalculate_stats(false)
	for stock_key: String in ["medicine", "general"]:
		merchant = GameData.merchant_context(stock_key)
		panel = Shop.new()
		panel.buy_quotes_requested.connect(buy_quotes)
		panel.sell_quotes_requested.connect(sell_quotes)
		add_child(panel)
		await frames(6)
		var caption: Label = panel.get_node("DetailPanel/DetailTitle")
		var caption_geometry := Rect2(caption.position, caption.size)
		var caption_text := caption.text
		for name_text: String in ["木剑", "匕首", "超级金创药", "超级魔法药", "铂金戒指"]:
			var item: Dictionary = GameData.get_item_record(name_text)
			check(not item.is_empty(), "item missing: " + name_text)
			if item.is_empty(): continue
			var entry: Dictionary = {"name": name_text, "pack_count": 1, "merchant_context": merchant.duplicate(true), "merchant_id": merchant.get("merchant_id", "")}
			var canonical := int(Names.canonical_id(item))
			if canonical > 0: entry["item_id"] = canonical
			panel.open_for("R3.3标题与留白验收", [entry], merchant)
			await frames(6)
			var quote: Dictionary = panel._buy_quote_for_index(0)
			check(not quote.is_empty(), "buy quote missing")
			var quantity := maxi(1, int(quote.get("pack_count", 1)))
			var price_line := "[color=#d3a763]价格：%d金币 × %d，共%d金币[/color]" % [int(quote.get("unit_price", 0)), quantity, int(quote.get("total_price", 0))] if bool(quote.get("valid", false)) else "[color=#b8a58a]%s[/color]" % str(quote.get("reason", "等待玩法价格报价"))
			var expected_buy: String = price_line + "\n\n" + panel._buy_item_detail(name_text, item, entry)
			panel.item_list.select(0)
			panel._on_item_selected(0)
			await frames()
			inspect(name_text, expected_buy, item, {})
			panel._ui_dismiss_selection()
			check(not panel.item_detail_presenter.visible and caption.visible, "clear did not restore idle heading")
			PlayerState.inventory = []
			var received: Dictionary = PlayerState.add_item(name_text, 1)
			check(bool(received.get("success", false)) and PlayerState.inventory.size() == 1, "sell fixture missing")
			if PlayerState.inventory.size() != 1: continue
			panel._set_trade_mode("sell")
			await frames(6)
			panel._request_sell_quotes()
			var instance: Dictionary = PlayerState.inventory[0]
			var sell_quote: Dictionary = panel._sell_quotes.get(panel.sell_quote_key(0, instance), {})
			check(not sell_quote.is_empty(), "sell quote missing")
			var expected_sell: String = panel._sell_item_detail(instance, item, sell_quote)
			panel._select_sell_item(0)
			await frames()
			inspect(name_text, expected_sell, item, instance)
			var snapshot: Dictionary = panel.item_detail_presenter.debug_layout_snapshot()
			var layouts := int(snapshot.get("layouts", 0))
			await frames(8)
			check(int(panel.item_detail_presenter.debug_layout_snapshot().get("layouts", 0)) <= layouts + 1, "layout does not settle")
			panel.hide()
			await frames()
			panel.show()
			await frames()
			check(not panel.item_detail_presenter.visible, "stale selection after reopening")
			check(caption.visible and caption.text == caption_text, "empty-state heading not restored")
			check(Rect2(caption.position, caption.size).is_equal_approx(caption_geometry), "caption calibration moved")
		panel.queue_free()
		await frames(2)
	finish()
func finish() -> void:
	if finished: return
	finished = true
	for error: String in failures:
		push_error("R33_HEADER_SESSION " + error)
	print("R33_HEADER_SESSION_%s checks=%d" % ["PASS" if failures.is_empty() else "FAIL", checks])
	get_tree().quit(0 if failures.is_empty() else 1)
