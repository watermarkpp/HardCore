extends Node
var failures: Array[String] = []
var checks := 0
func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()
func _run() -> void:
	assert(GameData.ensure_loaded(), "real data required")
	if not GameData.has_method("_ui_l1_get_item_price_record_slow"):
		push_error("UI_L1_PRICE_RED: original always-maintain path has no fast path")
		get_tree().quit(1)
		return
	var saved: Dictionary = {}
	for key: String in ["_price_by_name", "_price_by_item_id", "_price_by_service_index", "equipment_price_candidates"]:
		saved[key] = (GameData.get(key) as Dictionary).duplicate(true)
	for entry: Variant in GameData.item_catalog:
		if not entry is Dictionary:
			continue
		for identity: Variant in [entry, str(entry.get("name", ""))]:
			var original: Dictionary = GameData._ui_l1_get_item_price_record_slow(identity)
			var candidate: Dictionary = GameData.get_item_price_record(identity)
			expect(original == candidate, "exact price record parity, including provenance")
			if not candidate.is_empty():
				candidate["base_price"] = -123
				expect(GameData.get_item_price_record(identity) == original, "caller mutation never changes indexed price")
	var chosen_id := -1
	for key: Variant in GameData._price_by_item_id:
		chosen_id = int(key)
		break
	assert(chosen_id >= 0, "nonempty real price index required")
	var maintenance_before: int = GameData._ui_l1_price_maintenance_count
	for i in 100:
		GameData.get_item_price_record({"item_id": chosen_id})
	expect(GameData._ui_l1_price_maintenance_count == maintenance_before, "100 resolved ID reads must do zero overlay maintenance")
	# Missing stronger service ID may NOT reuse a weaker existing item hit.
	maintenance_before = GameData._ui_l1_price_maintenance_count
	GameData.get_item_price_record({"service_index": 2147483646, "item_id": chosen_id})
	expect(GameData._ui_l1_price_maintenance_count == maintenance_before + 1, "missing stronger identity executes original maintenance")
	# Clearing/rebuilding the index is observed immediately; no independent cache.
	GameData._price_by_name.clear()
	maintenance_before = GameData._ui_l1_price_maintenance_count
	GameData.get_item_price_record({"item_id": chosen_id})
	expect(GameData._ui_l1_price_maintenance_count == maintenance_before + 1, "cleared index rebuild is not hidden by cache")
	# A newly introduced row uses the original first-wins overlay path.
	GameData.equipment_price_candidates = {"records": [{"name": "UIL1_SYNTHETIC_PRICE", "price": 123, "kind": "consumable", "serviceIndex": 2147483000}]}
	var newly_loaded: Dictionary = GameData.get_item_price_record({"service_index": 2147483000})
	expect(not newly_loaded.is_empty() and int(newly_loaded.get("base_price", 0)) == 123, "new candidate remains discoverable")
	GameData.equipment_price_candidates = {"records": [{"name": "UIL1_SYNTHETIC_PRICE_2", "price": 124, "kind": "consumable", "serviceIndex": 2147483001}]}
	expect(not GameData.get_item_price_record({"service_index": 2147483001}).is_empty(), "same-size candidate replacement remains discoverable")
	for key: String in saved:
		GameData.set(key, saved[key])
	var quote_rows_checked := 0
	for stock_key: String in ["general", "medicine", "starter_gear", "books"]:
		var stock: Array = GameData.merchant_stock(stock_key)
		var context: Dictionary = GameData.merchant_context(stock_key)
		var serial := 701
		var all_quotes: Array = PlayerState._build_shop_buy_quotes(stock, context, serial)
		for index in range(stock.size()):
			if not stock[index] is Dictionary:
				continue
			var expected: Dictionary = {}
			for quote: Dictionary in all_quotes:
				if int(quote.get("stock_index", -1)) == index:
					expected = quote
			var before_rows: int = PlayerState._ui_l1_buy_quote_rows
			var single: Array = PlayerState._build_shop_buy_quotes(stock, context, serial, index)
			expect(single.size() == 1 and single[0] == expected, "single-row quote equals full quote byte-for-field including quote_id")
			expect(PlayerState._ui_l1_buy_quote_rows == before_rows + 1, "validation plans exactly one requested row")
			quote_rows_checked += 1
	expect(quote_rows_checked > 0, "nonzero real merchant coverage")
	expect(PlayerState._build_shop_buy_quotes([], {}, 1, 0).is_empty(), "invalid row fails closed")
	for failure: String in failures:
		push_error("UI_L1_PRICE " + failure)
	print("UI_L1_PRICE_%s checks=%d merchant_rows=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, quote_rows_checked, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
