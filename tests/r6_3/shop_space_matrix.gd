extends Node
## Real ShopPanel + real pricing callbacks. Synthetic catalog offers extend layout
## coverage beyond actual merchant stock; this is NOT transaction/performance proof.
const Shop := preload("res://scripts/shop_panel.gd")
const Dock := preload("res://scripts/ui_item_detail_dock.gd")
const NameStyle := preload("res://scripts/ui_item_name_style.gd")
@export var offset := 0
@export var limit := 0
var failures: Array[String] = []
var rows: Array = []
var panel
var catalog_keys: Array[String] = []
var merchant: Dictionary = {}
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func frames(n := 3) -> void:
	for i in range(n):
		await get_tree().process_frame
func check(ok: bool, why: String) -> void:
	if not ok:
		failures.append(why)
func _buy_quotes(stock: Array) -> void:
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(stock, merchant))
func _sell_quotes(requests: Array) -> void:
	panel.set_sell_quotes(PlayerState.shop_sell_quotes(requests))
func identity(item: Dictionary, index: int) -> String:
	var id := NameStyle.canonical_id(item)
	if id > 0:
		return "item:%d:%d" % [id, index]
	var service := int(item.get("serviceIndex", item.get("service_index", -1)))
	if service >= 0:
		return "service:%d:%d" % [service, index]
	return "legacy-name:%s:%d" % [str(item.get("name", "")), index]
func inspect_row(key: String, domain: String, name_text: String, expected_body: String, quote: Dictionary) -> void:
	var v = panel.item_detail_presenter
	var before := failures.size()
	check(v != null, key + " presenter missing")
	if v == null:
		return
	var prefix := key + "|" + domain + "|"
	check(v.debug_layout_valid(), prefix + str(v.debug_layout_snapshot().get("error", "invalid")))
	check(v.is_visible_in_tree() and v.modulate.a > 0.99, prefix + "hidden/alpha")
	check(v.title_label.text == name_text, prefix + "title mismatch")
	check(v.detail_label.text == expected_body, prefix + "body not equal independent formatter input")
	check(not v.detail_label.scroll_active, prefix + "scroll enabled")
	check(not v.detail_label.get_v_scroll_bar().is_visible_in_tree(), prefix + "scrollbar visible")
	check(float(v.detail_label.get_content_height()) <= v.detail_label.size.y, prefix + "vertical overflow")
	check(float(v.detail_label.get_content_width()) <= v.detail_label.size.x + 1.0, prefix + "horizontal overflow")
	var actual := Rect2(v.position, v.size)
	var region: Rect2 = panel._ui_detail_region({}).get("region", Rect2())
	check(region.grow(0.1).encloses(actual), prefix + "outside safe reading region")
	# User explicitly permits modest landscape for buy/sell, not a fixed 1.12.
	check(v.size.x <= v.size.y * 1.3 + 0.5, prefix + "excessively flat shop rectangle")
	check(v.title_label.get_theme_font_size("font_size") == 20, prefix + "title font reduced")
	check(v.detail_label.get_theme_font_size("normal_font_size") == 14, prefix + "body font reduced")
	check(float(v.debug_layout_snapshot().get("margin", 0)) >= 16.0, prefix + "compressed padding")
	var dec := panel.get_node("DetailPanel/DetailPanelDecoration") as Control
	var inset := Vector4(31, 26, 31, 26) # frozen inset_frame_v3 opening, independent of production region
	var opening := Dock.transformed_rect(panel.get_global_transform_with_canvas().affine_inverse() * dec.get_global_transform_with_canvas(),
		Rect2(Vector2(inset.x, inset.y), dec.size - Vector2(inset.x+inset.z, inset.y+inset.w)))
	var screen: Transform2D = panel.get_viewport().get_screen_transform() * panel.get_global_transform_with_canvas()
	if DisplayServer.get_name() == "headless":
		screen = panel.get_global_transform_with_canvas()
	var sx := screen.x.length()
	var sy := screen.y.length()
	var gaps := [(actual.position.x-opening.position.x)*sx, (opening.end.x-actual.end.x)*sx,
		(actual.position.y-opening.position.y)*sy, (opening.end.y-actual.end.y)*sy]
	for gap: float in gaps:
		check(gap >= 30.0 - 0.05, prefix + "frame clearance below 30px: " + str(gaps))
	var action_gaps: Array = []
	for c: Variant in [panel.buy_button, panel.repair_button, panel.sell_quantity_row, panel.sell_quantity_button]:
		if c is Control and c.is_visible_in_tree():
			var bounds := Rect2(Vector2.ZERO, c.size)
			if c is BaseButton:
				for style_name: StringName in [&"normal", &"pressed", &"hover", &"disabled", &"focus"]:
					var style: StyleBox = c.get_theme_stylebox(style_name)
					if style != null:
						bounds = bounds.merge(style.get_draw_rect(Rect2(Vector2.ZERO, c.size)))
			var rt: Transform2D = panel.get_global_transform_with_canvas().affine_inverse() * c.get_global_transform_with_canvas()
			var drawn := Dock.transformed_rect(rt, bounds)
			var clearance := (drawn.position.y - actual.end.y) * sy
			action_gaps.append(clearance)
			check(clearance >= 32.0 - 0.05, prefix + "action clearance below 32px")

	for c: Variant in [panel.buy_button, panel.repair_button, panel.sell_quantity_row, panel.sell_quantity_button, panel.get_node_or_null("DetailPanel/DetailTitle")]:
		if c is Control and c.is_visible_in_tree():
			check(not actual.intersects(Dock.rect_in(panel, c)), prefix + "overlaps " + str(c.name))
	rows.append({"key": key, "domain": domain, "name": name_text, "body_bbcode": expected_body,
		"quote": quote, "density": v.debug_layout_snapshot().get("density", "legacy"),
		"rect": str(actual), "region": str(region), "content_h": v.detail_label.get_content_height(),
		"alpha": v.modulate.a, "pass": failures.size() == before,
		"frame_gaps": gaps, "action_gaps": action_gaps,
		"pixel_scope": "viewport_only" if DisplayServer.get_name() == "headless" else "screen"})
var shot_budget := 12
func capture(key: String, domain: String, name_text: String) -> void:
	var destination := OS.get_environment("HC_R3_SHOT_DIR")
	if destination.is_empty() or DisplayServer.get_name() == "headless" or shot_budget <= 0:
		return
	if name_text not in ["超级金创药", "超级魔法药", "龙牙", "赤血魔剑", "回城卷", "地狱火", "铂金戒指", "裁决之杖"]:
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	check(image != null and not image.is_empty(), "screenshot render target unavailable")
	if image == null or image.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(destination)
	var path := destination.path_join(domain + "_" + key.sha256_text().substr(0, 12) + ".png")
	check(image.save_png(path) == OK, "screenshot write failed")
	shot_budget -= 1

func _run() -> void:
	if not GameData.ensure_loaded():
		push_error("R3_SHOP_MATRIX_DATA_MISSING")
		get_tree().quit(1)
		return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 1000000
	PlayerState.recalculate_stats(false)
	merchant = GameData.merchant_context("general")
	check(not str(merchant.get("merchant_id", "")).is_empty(), "real merchant identity missing")
	panel = Shop.new()
	panel.buy_quotes_requested.connect(_buy_quotes)
	panel.sell_quotes_requested.connect(_sell_quotes)
	add_child(panel)
	await frames(6)
	# No positive-ID-only filter. Service-only books/potions stay in coverage.
	for i in range(GameData.item_catalog.size()):
		var raw: Variant = GameData.item_catalog[i]
		check(raw is Dictionary and not raw.is_empty(), "malformed catalog row %d" % i)
		if raw is Dictionary:
			catalog_keys.append(identity(raw, i))
	var stop := GameData.item_catalog.size() if limit <= 0 else mini(GameData.item_catalog.size(), offset + limit)
	check(offset >= 0 and offset < stop, "EMPTY_OR_INVALID_SHARD_NOT_PASS")
	for i in range(offset, stop):
		if not GameData.item_catalog[i] is Dictionary:
			continue
		var item: Dictionary = GameData.item_catalog[i]
		var key := identity(item, i)
		var item_name := str(item.get("name", ""))
		check(not item_name.is_empty(), key + " empty name")
		var entry := {"name": item_name, "pack_count": 1, "merchant_context": merchant.duplicate(true), "merchant_id": str(merchant.get("merchant_id", ""))}
		var canonical := NameStyle.canonical_id(item)
		if canonical > 0:
			entry["item_id"] = canonical # NEVER put a display name in item_id.
		panel.open_for("R3目录布局测试（真实报价）", [entry], merchant)
		await frames(6)
		var quote: Dictionary = panel._buy_quote_for_index(0)
		check(not quote.is_empty(), key + " buy quote missing")
		var quantity := maxi(1, int(quote.get("pack_count", quote.get("quantity", 1))))
		var price_line := "[color=#d3a763]价格：%d金币 × %d，共%d金币[/color]" % [int(quote.get("unit_price", 0)), quantity, int(quote.get("total_price", 0))] if bool(quote.get("valid", false)) else "[color=#b8a58a]%s[/color]" % str(quote.get("reason", "等待玩法价格报价"))
		var expected_buy: String = price_line + "\n\n" + panel._buy_item_detail(item_name, item, entry)
		panel.item_list.select(0)
		panel._on_item_selected(0)
		await frames()
		inspect_row(key, "buy", item_name, expected_buy, quote)
		await capture(key, "buy", item_name)
		panel._ui_dismiss_selection()
		PlayerState.inventory = [] # isolated test fixture setup only
		var received: Dictionary = PlayerState.add_item(item_name, 1)
		if str(item.get("kind", "")) == "currency":
			rows.append({"key": key, "domain": "sell", "status": "EXCLUDED_NON_INVENTORY_CURRENCY"})
			continue
		check(bool(received.get("success", false)) and PlayerState.inventory.size() == 1, key + " receive failed")
		if PlayerState.inventory.size() != 1:
			continue
		panel._set_trade_mode("sell")
		await frames(6) # queued inventory changes request REAL fresh quotes
		panel._request_sell_quotes()
		var instance: Dictionary = PlayerState.inventory[0]
		var quote_key: String = panel.sell_quote_key(0, instance)
		var sell_quote: Dictionary = panel._sell_quotes.get(quote_key, {})
		check(not sell_quote.is_empty(), key + " sell quote silently lost")
		var expected_sell: String = panel._sell_item_detail(instance, item, sell_quote)
		panel._select_sell_item(0)
		await frames()
		inspect_row(key, "sell", item_name, expected_sell, sell_quote)
		await capture(key, "sell", item_name)
		if bool(sell_quote.get("sellable", false)):
			check(panel._selected_sell_indices.has(0), key + " did not enter real sell selection")
		panel._ui_dismiss_selection()
	var f := FileAccess.open("user://r3_shop_matrix_%d_%d.json" % [offset, stop], FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"schema": "hc.r3.shop_matrix.v1", "offset": offset, "end": stop,
			"catalog_keys": catalog_keys, "rows": rows, "failures": failures}, "  "))
		f.close()
	else:
		failures.append("evidence write failed")
	for e: String in failures:
		push_error("R3_SHOP_MATRIX " + e)
	print("R3_SHOP_MATRIX_%s records=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", rows.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
