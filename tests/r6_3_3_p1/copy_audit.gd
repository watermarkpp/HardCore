extends Node
## Diagnostic only. Captures actual formatter input BEFORE any layout failure
## replaces the label with an error message. Does not accept a layout failure.
const Shop := preload("res://scripts/shop_panel.gd")
const Formatter := preload("res://scripts/item_detail_presenter.gd")
const Rules := preload("res://scripts/equipment_rules.gd")
const COPY_PATH := "res://scripts/ui_item_player_copy.gd"
var panel
var merchant: Dictionary = {}
var cases: Array[Dictionary] = []
var audit_rows: Array[Dictionary] = []
var errors: Array[String] = []
var finished := false
var started := 0
var copy_script: Script
func _ready() -> void:
	started = Time.get_ticks_msec()
	process_mode = Node.PROCESS_MODE_ALWAYS
	PlayerState.test_mode = true
	if ResourceLoader.exists(COPY_PATH):
		copy_script = load(COPY_PATH)
	_run.call_deferred()
func _process(_dt: float) -> void:
	if not finished and Time.get_ticks_msec() - started > 40000:
		errors.append("CAPTURE_WATCHDOG")
		finish()
func frames(count: int = 3) -> void:
	for _i in range(count):
		await get_tree().process_frame
func buys(stock: Array) -> void:
	panel.set_buy_quotes(PlayerState.shop_buy_quotes(stock, merchant))
func sells(requests: Array) -> void:
	panel.set_sell_quotes(PlayerState.shop_sell_quotes(requests))
func plain(text: String) -> String:
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = text
	var result := label.get_parsed_text()
	label.free()
	return result
func ascii_lines(text: String) -> Array[String]:
	var result: Array[String] = []
	for line: String in plain(text).split("\n", false):
		for i in range(line.length()):
			var c := line.unicode_at(i)
			if (c >= 65 and c <= 90) or (c >= 97 and c <= 122):
				result.append(line)
				break
	return result
func clean(text: String) -> String:
	if copy_script == null:
		return text
	return str(copy_script.call("description", text))
func record_case(stock_key: String, domain: String, name_text: String, item: Dictionary, instance: Dictionary, body: String, quote: Dictionary) -> void:
	var view = panel.item_detail_presenter
	var snapshot: Dictionary = view.debug_layout_snapshot()
	cases.append({
		"merchant": stock_key, "domain": domain, "item_name": name_text,
		"item_id": item.get("itemId", item.get("item_id", null)),
		"instance_id": instance.get("instance_id", ""),
		"raw_description": item.get("description", null), "raw_tooltip": item.get("toolTip", null),
		"legacy_requirement_with_audit": Rules.requirement_label(item),
		"actual_player_requirement": panel._player_requirement_label(item),
		"source_body_bbcode_before_layout": body,
		"source_body_plain_before_layout": plain(body), "ascii_lines": ascii_lines(body),
		"known_metadata_cleanup_would_change_this_body": null if copy_script == null else clean(body) != body,
		"known_metadata_cleaned_body_for_diagnosis_only": clean(body),
		"actual_body_after_layout": view.detail_label.text,
		"quote": quote, "risk_display": panel._sell_risk_text(quote),
		"valid": view.debug_layout_valid(), "snapshot": snapshot,
	})
func _run() -> void:
	if not GameData.ensure_loaded():
		errors.append("DATA_NOT_LOADED"); finish(); return
	PlayerState.reset_progress(false)
	PlayerState.level = 60
	PlayerState.gold = 1000000
	PlayerState.recalculate_stats(false)
	# All runtime catalogue rows are audited; English itself is NOT a defect.
	for index in range(GameData.item_catalog.size()):
		var raw: Variant = GameData.item_catalog[index]
		if not raw is Dictionary:
			errors.append("CATALOG_ROW_NOT_DICTIONARY:%d" % index)
			continue
		var item: Dictionary = raw
		var body := Formatter.format_item(item)
		var desc: Variant = item.get("description", null)
		audit_rows.append({"index": index, "item_id": item.get("itemId", item.get("item_id", null)),
			"service_index": item.get("serviceIndex", null), "name": item.get("name", ""), "kind": item.get("kind", ""),
			"description": desc, "toolTip": item.get("toolTip", null),
			"source": item.get("source", null), "attribute_review": item.get("attributeReview", null),
			"body": body, "ascii_lines": ascii_lines(body)})
	for stock_key: String in ["medicine", "general"]:
		merchant = GameData.merchant_context(stock_key)
		panel = Shop.new()
		panel.buy_quotes_requested.connect(buys)
		panel.sell_quotes_requested.connect(sells)
		add_child(panel)
		await frames(6)
		# This suppression is diagnostic-only. The source body and failure are
		# captured explicitly. Original acceptance tests are NEVER changed.
		panel.item_detail_presenter._test_suppress_expected_layout_error = true
		for name_text: String in ["铂金戒指", "木剑"]:
			var item: Dictionary = GameData.get_item_record(name_text)
			if item.is_empty():
				errors.append("FOCUS_ITEM_MISSING:" + name_text)
				continue
			var entry := {"name": name_text, "pack_count": 1, "merchant_context": merchant.duplicate(true), "merchant_id": merchant.get("merchant_id", "")}
			if int(item.get("itemId", 0)) > 0:
				entry["item_id"] = int(item.itemId)
			panel.open_for("物品文案诊断", [entry], merchant)
			await frames(6)
			var buy_quote: Dictionary = panel._buy_quote_for_index(0)
			if buy_quote.is_empty():
				errors.append("BUY_QUOTE_MISSING:" + name_text)
			var n := maxi(1, int(buy_quote.get("pack_count", buy_quote.get("quantity", 1))))
			var price_line := "[color=#d3a763]价格：%d金币 × %d，共%d金币[/color]" % [int(buy_quote.get("unit_price", 0)), n, int(buy_quote.get("total_price", 0))]
			if not bool(buy_quote.get("valid", false)):
				price_line = "[color=#b8a58a]%s[/color]" % str(buy_quote.get("reason", "等待玩法价格报价"))
			var buy_body: String = price_line + "\n\n" + panel._buy_item_detail(name_text, item, entry)
			panel.item_list.select(0)
			panel._on_item_selected(0)
			await frames()
			record_case(stock_key, "buy", name_text, item, {}, buy_body, buy_quote)
			panel._ui_dismiss_selection()
			PlayerState.inventory = [] # Disposable test fixture, never a user save.
			var received: Dictionary = PlayerState.add_item(name_text, 1)
			if not bool(received.get("success", false)) or PlayerState.inventory.size() != 1:
				errors.append("RECEIVE_FAILED:" + name_text)
				continue
			panel._set_trade_mode("sell")
			await frames(6)
			panel._request_sell_quotes()
			var instance: Dictionary = PlayerState.inventory[0]
			var sell_quote: Dictionary = panel._sell_quotes.get(panel.sell_quote_key(0, instance), {})
			if sell_quote.is_empty():
				errors.append("SELL_QUOTE_MISSING:" + name_text)
			var sell_body: String = panel._sell_item_detail(instance, item, sell_quote)
			panel._select_sell_item(0)
			await frames()
			record_case(stock_key, "sell", name_text, item, instance, sell_body, sell_quote)
			panel._ui_dismiss_selection()
		panel.queue_free()
		await frames(2)
	finish()
func finish() -> void:
	if finished: return
	finished = true
	if cases.size() != 8:
		errors.append("FOCUS_ROWS_INCOMPLETE")
	var source_hashes: Dictionary = {}
	for path: String in ["scripts/shop_panel.gd", "scripts/item_detail_presenter.gd", "scripts/item_detail_docked_presenter.gd", "scripts/ui_shop_detail_space.gd", "scripts/equipment_rules.gd", "scripts/player_state.gd", "scripts/game_data.gd", "tests/r6_3_3_p1/copy_audit.gd"]:
		source_hashes[path] = FileAccess.get_sha256("res://" + path)
		if str(source_hashes[path]).is_empty():
			errors.append("SOURCE_HASH_MISSING:" + path)
	if copy_script != null:
		source_hashes["scripts/ui_item_player_copy.gd"] = FileAccess.get_sha256(COPY_PATH)
	var output := {"schema": "hc.r33p1.copy_audit.v1", "phase": OS.get_environment("HC_R33_P1_PHASE"),
		"source_hashes": source_hashes, "project_root": ProjectSettings.globalize_path("res://"), "engine": Engine.get_version_info(),
		"frame_scope": "diagnostic_viewport_not_device", "cleanup_script_present": copy_script != null,
		"catalog_count": GameData.item_catalog.size(), "catalog_rows": audit_rows, "focus": cases,
		"errors": errors, "status": "CAPTURE_COMPLETE_NOT_LAYOUT_ACCEPTANCE" if errors.is_empty() else "INCOMPLETE_CAPTURE"}
	var file := FileAccess.open("user://r33_p1_copy_audit.json", FileAccess.WRITE)
	if file == null:
		errors.append("OUTPUT_FAILED")
	else:
		file.store_string(JSON.stringify(output, "  "))
		file.close()
	for error: String in errors:
		push_error("R33_P1_AUDIT " + error)
	print("R33_P1_AUDIT_CAPTURE_COMPLETE" if errors.is_empty() else "R33_P1_AUDIT_INCOMPLETE")
	get_tree().quit(0 if errors.is_empty() else 1)
