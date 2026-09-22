extends Node

## Comparable CPU timings on real panels. Headless timings exclude GPU/display.
var rows: Array[Dictionary] = []
var hud: GameHUD

func frames(count: int = 4) -> void:
	for i in range(count):
		await get_tree().process_frame

func measure(label: String, action: Callable, repetitions: int = 16) -> void:
	var samples: Array[float] = []
	for i in range(repetitions):
		var begin := Time.get_ticks_usec()
		action.call()
		samples.append(float(Time.get_ticks_usec() - begin) / 1000.0)
		await frames(2)
	samples.sort()
	rows.append({"action": label, "samples": samples, "median_ms": samples[samples.size() / 2], "p95_ms": samples[mini(samples.size() - 1, ceili(samples.size() * 0.95) - 1)]})

func geometry() -> Dictionary:
	var p: ShopPanel = hud.shop_panel
	return {"buy_position": str(p.buy_button.position), "buy_size": str(p.buy_button.size), "repair_position": str(p.repair_button.position), "repair_size": str(p.repair_button.size)}

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func _run() -> void:
	if not GameData.ensure_loaded():
		get_tree().quit(1)
		return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 10000000
	var fixtures: Array = []
	for raw: Variant in GameData.item_catalog:
		if raw is Dictionary and str(raw.get("kind", "")) == "equipment":
			fixtures.append(raw)
	for count: int in [100]:
		PlayerState.inventory = []
		for i in range(count):
			var item: Dictionary = fixtures[i % fixtures.size()]
			PlayerState.inventory.append(PlayerState._make_item_instance(str(item.name), item, 700000 + i))
	PlayerState.warehouse_inventory = []
	for i in range(500):
		var item: Dictionary = fixtures[i % fixtures.size()]
		PlayerState.warehouse_inventory.append(PlayerState._make_item_instance(str(item.name), item, 800000 + i))
	PlayerState.recalculate_stats(false)
	hud = GameHUD.new()
	add_child(hud)
	await frames()
	for panel_name: String in ["inventory", "warehouse", "shop", "skill", "map", "quest", "death_revival"]:
		await measure(panel_name + ".construct", Callable(hud, "_ensure_" + panel_name + "_panel"), 1)
		await frames(12)
	for panel_name: String in ["skill", "map", "quest"]:
		var panel: Control = hud.get(panel_name + "_panel")
		if panel_name == "skill": panel.open_for("技能")
		elif panel_name == "quest": panel.open_for("任务")
		else: panel.open_panel()
		panel.show()
		await frames()
		await measure(panel_name + ".refresh", Callable(panel, "refresh"))
		await measure(panel_name + ".reopen", func() -> void: panel.hide(); panel.show())
		panel.hide()
	var original_profession := PlayerState.profession
	for profession: String in ["法师", "道士"]:
		PlayerState.profession = profession
		await measure("skill.open." + profession, func() -> void: hud.skill_panel.open_for("技能"))
		hud.skill_panel.hide()
	PlayerState.profession = original_profession
	var inv: InventoryPanel = hud.inventory_panel
	var stash: WarehousePanel = hud.warehouse_panel
	await measure("inventory.reopen", func() -> void: inv.hide(); inv.show())
	await measure("inventory.refresh.100", func() -> void: inv.refresh())
	await measure("inventory.equipment_slots", func() -> void: inv._refresh_equipment_slots())
	await measure("inventory.bag_grid", func() -> void: inv._refresh_bag_grid())
	await measure("inventory.catalog_lookup.100", func() -> void:
		for record: Dictionary in PlayerState.inventory: GameData.get_item_record(record)
	)
	var cached_item := GameData.get_item_record(PlayerState.inventory[0])
	await measure("inventory.texture_lookup.100", func() -> void:
		for i in range(100): UIItemTextureCache.texture_for(cached_item)
	)
	await measure("inventory.selection_style.100", func() -> void:
		for cell: Control in inv._bag_cells:
			UIItemSelectionVisual.apply(cell.get_child(0), false, &"GothicComponentSlotButton", &"GothicComponentSelectedSlotButton")
	)
	await measure("inventory.character_preview", func() -> void: inv.character_preview.refresh())
	await measure("inventory.select.100", func() -> void: inv._select_inventory_item(0); inv._ui_dismiss_selection())
	inv.hide()
	stash.show()
	await frames()
	await measure("warehouse.refresh.100+500", func() -> void: stash.refresh())
	await measure("warehouse.compatibility_list.500", func() -> void: stash._fill_compatibility_list(stash.stash_list, PlayerState.warehouse_inventory, {}))
	await measure("warehouse.grid.100", func() -> void: stash._fill_grid(stash.stash_grid, PlayerState.warehouse_inventory, 0, 100, "stash", {}))
	await measure("warehouse.selection_visuals", func() -> void: stash._refresh_transfer_selection_visuals())
	await measure("warehouse.reopen", func() -> void: stash.hide(); stash.show())
	stash.hide()
	var shop: ShopPanel = hud.shop_panel
	var merchant: Dictionary = {}
	var stock: Array = []
	for key: String in GameData.merchant_catalog.get("merchants", {}):
		var candidate := GameData.merchant_context(key)
		if bool(candidate.get("supports_repair", false)):
			merchant = candidate
			stock = GameData.merchant_stock(key)
			break
	shop.buy_quotes_requested.connect(func(items: Array) -> void: shop.set_buy_quotes(PlayerState.shop_buy_quotes(items, merchant)))
	shop.sell_quotes_requested.connect(func(items: Array) -> void: shop.set_sell_quotes(PlayerState.shop_sell_quotes(items)))
	shop.open_for("延迟测量", stock, merchant)
	await frames(6)
	var first_geometry := geometry()
	shop._set_trade_mode("sell")
	await frames(6)
	shop._set_trade_mode("buy")
	await frames(6)
	var switched_geometry := geometry()
	await measure("shop.select", func() -> void: shop._select_shop_item(0); shop._ui_dismiss_selection())
	await measure("shop.sell", func() -> void: shop._set_trade_mode("sell"))
	await measure("shop.quotes.100", func() -> void: shop._request_sell_quotes())
	var quote_requests: Array = []
	for i in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[i]
		quote_requests.append({"inventory_index": i, "item_name": record.name, "instance_id": record.get("instance_id", ""), "quote_key": "instance:" + str(record.get("instance_id", "")), "merchant_id": merchant.merchant_id, "merchant_stock_key": merchant.get("stock_key", "")})
	for component: String in ["catalog", "price_record", "merchant_context"]:
		await measure("shop.component." + component, func() -> void:
			var cache := PlayerState._new_shop_quote_lookup_cache()
			for request: Dictionary in quote_requests:
				if component == "merchant_context": PlayerState._shop_sell_merchant_context(request, cache)
				else: PlayerState.call("_shop_sell_" + component, str(request.item_name), cache)
		, 8)
	var rules := GameData.get_item_rules_record(PlayerState.inventory[0])
	var price := GameData.get_item_price_record(str(PlayerState.inventory[0].name))
	await measure("shop.component.pricing", func() -> void:
		for record: Dictionary in PlayerState.inventory:
			PricingService.quote_sell(price, rules, record, 1, merchant)
	, 8)
	await measure("shop.component.stringify", func() -> void:
		for record: Dictionary in PlayerState.inventory:
			JSON.stringify([merchant, record]).sha256_text()
	, 8)
	await measure("warehouse.bank_read", func() -> void: PlayerState.shared_gold_balance(), 8)
	await measure("shop.buy", func() -> void: shop._set_trade_mode("buy"))
	var report := {"scope": "headless_cpu_call", "inventory": 100, "warehouse": 500, "first_shop": first_geometry, "switched_shop": switched_geometry, "rows": rows}
	var copy_rows: Array[Dictionary] = []
	for item: Dictionary in GameData.item_catalog:
		copy_rows.append({"id": item.get("itemId", item.get("serviceIndex", -1)), "name": item.get("name", ""), "kind": item.get("kind", ""), "useEffect": item.get("useEffect", ""), "usable": item.get("usable", false), "description": item.get("description", ""), "body": ItemDetailPresenter.format_item(item)})
	var copy_file := FileAccess.open("res://outputs/test_logs/ui_player_copy_audit.json", FileAccess.WRITE)
	copy_file.store_string(JSON.stringify(copy_rows, "\t"))
	copy_file.close()
	var suffix := OS.get_environment("HC_UI_PROBE_LABEL")
	if suffix not in ["before", "after"]: suffix = "current"
	var path := "res://outputs/test_logs/ui_latency_" + suffix + ".json"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("UI_LATENCY_PROBE_PASS ", JSON.stringify(report))
	hud.queue_free()
	await frames()
	get_tree().quit()
