extends Node

## R61-REV-02 real-panel matrix. One zone per scene instance (see the six
## .tscn wrappers). Iterates the real runtime catalog per-ID through the REAL
## panel selection path of its domain, checks every record with the LOCKED
## detail_visible_assertions.gd helper (colors, visibility, full text, no
## scrollbar, boundary, protected geometry), adds independent expanded-region
## boundary assertions, and writes one evidence row per record. Failures are
## recorded, never abort early; the scene exits non-zero when any row failed.

@export var zone := "inventory_bag"
# Optional id-window for zones whose one-time panel construction (e.g. the
# 188-card shop goods list) cannot fit the runner cap in a single scene; a
# split keeps full per-ID coverage across parts. [0, 0] = the whole range.
@export var id_from := 0
@export var id_to := 0

const Helper := preload("res://tests/r6_1_review/detail_visible_assertions.gd")
const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")

var failures: Array[String] = []
var rows: Array = []
var checked := 0
var panel: Control

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func settle(frames := 3) -> void:
	for unused in range(frames):
		await get_tree().process_frame

func _presenter() -> Control:
	return panel.get("item_detail_presenter") as Control

func _grids() -> Array:
	var grids := panel.find_children("*", "GridContainer", true, false)
	var scroll := panel.get_node_or_null("BagPanel/InventoryScroll")
	if scroll != null:
		grids.append(scroll)
	return grids

func _spec(context: Dictionary = {}) -> Dictionary:
	return panel.call("_ui_detail_region", context)

func _inspect(expected: Dictionary, record: Dictionary, body_source: String, context: Dictionary = {}) -> Array[String]:
	var view := _presenter()
	var spec: Dictionary = _spec(context)
	var allowed: Array[Rect2] = []
	var base_region: Rect2 = spec.get("region", Rect2())
	var expanded_region: Rect2 = spec.get("expanded_region", Rect2())
	allowed.append(base_region)
	if expanded_region.has_area():
		allowed.append(expanded_region)
	var protected: Array[Rect2] = Common.rects_of(panel, _grids())
	if view == null:
		return ["PRESENTER_MISSING"]
	var errors: Array[String] = Helper.inspect(
		panel, view, allowed, protected,
		str(expected.name), int(expected.item_id),
		expected.color, body_source,
	)
	# Independent expanded-region boundary check (not produced by the dock):
	# a used expansion must stay on the same horizontal side (x-range unchanged
	# against the base region). Viewport containment is enforced by the helper.
	var actual: Rect2 = Common.HelperRects.rect_in(panel, view)
	if expanded_region.has_area() and not base_region.grow(1.0).encloses(actual):
		if absf(actual.position.x - base_region.position.x) > 2.0 or absf(actual.end.x - base_region.end.x) > 2.0:
			errors.append("EXPANSION_CHANGED_HORIZONTAL_SIDE")
	# Per-record evidence row (order §3.1 fields).
	var snapshot: Dictionary = view.call("debug_layout_snapshot")
	rows.append({
		"zone": zone,
		"item_id": int(expected.item_id),
		"name": str(expected.name),
		"instance_id": str(record.get("instance_id", "")),
		"affix": Common.instance_affixes(record),
		"expected_group": str(expected.group),
		"expected_color": str(expected.color),
		"actual_color": str(snapshot.get("title_color", "")),
		"body_text": str(snapshot.get("body", "")),
		"detail_rect": str(snapshot.get("rect", "")),
		"title_rect": str(snapshot.get("title_rect", "")),
		"body_rect": str(snapshot.get("body_rect", "")),
		"body_content_height": float(snapshot.get("body_content_height", 0.0)),
		"alpha": float((view as CanvasItem).modulate.a),
		"scroll_active": bool(snapshot.get("scroll_active", false)),
		"allowed_region": str(base_region),
		"expanded_region": str(expanded_region),
		"protected_count": protected.size(),
		"errors": errors,
		"test_commit": "r61-r1-review",
	})
	return errors

func _record(zone_name: String, expected: Dictionary, record: Dictionary, errors: Array[String], seed_note: String) -> void:
	checked += 1
	var row: Dictionary = rows.back() if not rows.is_empty() else {}
	row["seed_note"] = seed_note
	row["ms"] = int(Time.get_ticks_msec() - _record_started_ms)
	print("R61_T zone=%s id=%d ms=%d" % [zone, int(expected.item_id), row["ms"]])
	_record_started_ms = Time.get_ticks_msec()
	row["seed_note"] = seed_note
	if not errors.is_empty():
		for error: String in errors:
			failures.append("%s|%s|%s" % [zone_name, str(expected.name), error])

func _run() -> void:
	if not Common.ensure_data():
		push_error("R61_MATRIX data not loaded")
		get_tree().quit(1)
		return
	# A level-1 warrior cannot even RECEIVE the heavy legendary gear (weight
	# contract). Raise the fixture character so every catalog id can enter the
	# real receive path; the weight/level rules themselves stay untouched.
	PlayerState.level = 60
	var expected_all: Array[Dictionary] = Common.expected_items()
	if id_to > 0:
		expected_all = expected_all.filter(func(e: Dictionary) -> bool: return int(e.item_id) >= id_from and int(e.item_id) <= id_to)
	var zone_tag := zone if id_to <= 0 else "%s_%d_%d" % [zone, id_from, id_to]
	print("R61_MATRIX zone=%s expected_ids=%d" % [zone_tag, expected_all.size()])
	match zone:
		"inventory_bag":
			await _run_inventory_bag(expected_all)
		"inventory_equipment":
			await _run_inventory_equipment(expected_all)
		"warehouse_stash":
			await _run_warehouse(expected_all, "stash")
		"warehouse_bag":
			await _run_warehouse(expected_all, "bag")
		"shop_buy":
			await _run_shop_buy(expected_all)
		"shop_sell":
			await _run_shop_sell(expected_all)
		_:
			push_error("R61_MATRIX unknown zone " + zone)
			get_tree().quit(1)
			return
	var out := FileAccess.open("user://r61_review_matrix_%s.json" % zone_tag, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"zone": zone_tag, "checked": checked, "failures": failures, "rows": rows}, "  ", false))
		out.close()
	for message: String in failures:
		push_error("R61_MATRIX " + zone + " " + message)
	print("R61_MATRIX_%s_%s checked=%d failures=%d" % [zone.to_upper(), "PASS" if failures.is_empty() else "FAIL", checked, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)

var showcase_budget := 0
var _record_started_ms := 0

func _showcase(expected: Dictionary) -> void:
	# §3.3 screenshots: strictly budgeted per zone (2 max) and only when a shot
	# directory is provided, so per-ID iteration stays inside the runner cap.
	var wanted := ["技能书", "回城卷", "药", "手镯", "头盔"]
	if showcase_budget <= 0 or OS.get_environment("R6_SHOT_DIR").is_empty():
		return
	for key: String in wanted:
		if str(expected.name).contains(key):
			await _snap("matrix_%s_showcase_%s_%d" % [zone, key, int(expected.item_id)])
			showcase_budget -= 1
			return

func _snap(name_value: String) -> void:
	# Headless runs have no render target: capturing there would abort the
	# coroutine and stall the whole matrix. §3.3 shots are taken by dedicated
	# windowed capture runs with R6_SHOT_DIR set; runner runs never snap.
	if DisplayServer.get_name() == "headless" or OS.get_environment("R6_SHOT_DIR").is_empty():
		print("R61_SHOT skipped=", name_value, " (headless or no shot dir)")
		return
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(OS.get_environment("R6_SHOT_DIR") + "/" + name_value + ".png")
	print("R61_SHOT saved=", name_value)

func _run_inventory_bag(expected_all: Array[Dictionary]) -> void:
	showcase_budget = 2
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	panel = InventoryScript.new()
	add_child(panel)
	await settle()
	for expected: Dictionary in expected_all:
		panel.call("_ui_dismiss_selection")
		var record: Dictionary = Common.seed_record(str(expected.name))
		if record.is_empty():
			checked += 1
			failures.append("inventory_bag|%s|SEED_RECEIVE_FAILED" % str(expected.name))
			continue
		panel.call("refresh")
		await settle(2)
		panel.call("_select_inventory_item", 0)
		await settle()
		var body_source: String = str(_presenter().get("detail_label").text if _presenter() != null else "")
		var errors := _inspect(expected, record, body_source)
		_record("inventory_bag", expected, record, errors, "add_item serial path")
		if _presenter() != null and is_instance_valid(_presenter()) and _presenter().visible:
			await _showcase(expected)
		PlayerState.inventory = []
	panel.call("_ui_dismiss_selection")
	panel.queue_free()
	await settle()

func _run_inventory_equipment(expected_all: Array[Dictionary]) -> void:
	showcase_budget = 2
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	panel = InventoryScript.new()
	add_child(panel)
	await settle()
	for expected: Dictionary in expected_all:
		panel.call("_ui_dismiss_selection")
		var record: Dictionary = Common.seed_record(str(expected.name))
		if record.is_empty():
			checked += 1
			failures.append("inventory_equipment|%s|SEED_RECEIVE_FAILED" % str(expected.name))
			continue
		var equip_result: Dictionary = PlayerState.call("equip_inventory_index_result", 0)
		if not bool(equip_result.get("success", false)):
			checked += 1
			rows.append({"zone": zone, "item_id": int(expected.item_id), "name": str(expected.name), "errors": ["BUSINESS_EXCLUSION_EQUIP_REJECTED"], "reason": str(equip_result.get("message", ""))})
			PlayerState.inventory = []
			panel.call("refresh")
			continue
		var slot := ""
		for key: Variant in PlayerState.equipment:
			var equipped: Variant = PlayerState.equipment[key]
			if equipped is Dictionary and str((equipped as Dictionary).get("instance_id", "")) == str(record.get("instance_id", "")):
				slot = str(key)
		if slot.is_empty():
			checked += 1
			failures.append("inventory_equipment|%s|EQUIP_SLOT_NOT_FOUND" % str(expected.name))
			PlayerState.inventory = []
			continue
		panel.call("refresh")
		await settle(2)
		panel.call("_select_equipment_slot", slot)
		await settle()
		var body_source: String = str(_presenter().get("detail_label").text if _presenter() != null else "")
		# Production equipment-zone placement contract: equipment region.
		var errors: Array[String] = _inspect(expected, record, body_source, {"presentation_zone": "equipment", "slot": slot})
		_record("inventory_equipment", expected, record, errors, "equip_inventory_index_result")
		if _presenter() != null and is_instance_valid(_presenter()) and _presenter().visible and errors.is_empty():
			await _showcase(expected)
		var unequip_message: String = PlayerState.call("unequip_slot", slot, 0)
		if not unequip_message.is_empty():
			PlayerState.inventory = []
		else:
			PlayerState.inventory = []
	panel.call("_ui_dismiss_selection")
	panel.queue_free()
	await settle()

func _run_warehouse(expected_all: Array[Dictionary], side: String) -> void:
	showcase_budget = 2
	var WarehouseScript := load("res://scripts/warehouse_panel.gd")
	panel = WarehouseScript.new()
	add_child(panel)
	await settle()
	if panel.has_method("open_panel"):
		panel.call("open_panel")
	await settle()
	for expected: Dictionary in expected_all:
		panel.call("_ui_dismiss_selection")
		var record: Dictionary = Common.seed_record(str(expected.name))
		if record.is_empty():
			checked += 1
			failures.append("%s|%s|SEED_RECEIVE_FAILED" % [zone, str(expected.name)])
			continue
		if side == "stash":
			PlayerState.warehouse_inventory = [record]
			PlayerState.inventory = []
		else:
			PlayerState.inventory = [record]
			PlayerState.warehouse_inventory = []
		await settle(2)
		panel.call("_select_item", side, 0)
		await settle()
		var body_source: String = str(_presenter().get("detail_label").text if _presenter() != null else "")
		# Warehouse sides own different dock regions (stash left / bag right).
		var errors: Array[String] = _inspect(expected, record, body_source, {"side": side})
		_record(zone, expected, record, errors, "warehouse " + side)
		if _presenter() != null and is_instance_valid(_presenter()) and _presenter().visible and errors.is_empty():
			await _showcase(expected)
		PlayerState.inventory = []
		PlayerState.warehouse_inventory = []
	panel.call("_ui_dismiss_selection")
	panel.queue_free()
	await settle()

func _run_shop_buy(expected_all: Array[Dictionary]) -> void:
	showcase_budget = 2
	var ShopScript := load("res://scripts/shop_panel.gd")
	panel = ShopScript.new()
	add_child(panel)
	await settle()
	var stock: Array = []
	var ids: Array[int] = []
	for expected: Dictionary in expected_all:
		stock.append({"name": str(expected.name), "item_id": str(expected.name), "count": 1})
		ids.append(int(expected.item_id))
	panel.call("open_for", "矩阵审查商店", stock, {"mode": "sell"})
	var quotes: Array = []
	for i: int in range(stock.size()):
		quotes.append({"stock_index": i, "valid": true, "unit_price": 1, "pack_count": 1, "total_price": 1, "reason": "r61-review quote fixture", "risk_flags": []})
	panel.call("set_buy_quotes", quotes)
	await settle(2)
	for i: int in range(expected_all.size()):
		var expected: Dictionary = expected_all[i]
		_record_started_ms = Time.get_ticks_msec()
		panel.call("_on_item_selected", i)
		await settle()
		var view := _presenter()
		if view == null:
			checked += 1
			failures.append("shop_buy|%s|PRESENTER_MISSING" % str(expected.name))
			continue
		var body_text := str(view.get("detail_label").text)
		# The accepted detail contract omits duplicate pricing from properties.
		# Verify the real quoted price remains on its corresponding goods card.
		var price_label := panel.goods_buttons[i].get_node("Price") as Label
		if price_label.text != "1 金币":
			failures.append("shop_buy|%s|CARD_QUOTE_PRICE_MISSING" % str(expected.name))
		if body_text.contains("价格：") or body_text.contains("售价"):
			failures.append("shop_buy|%s|DUPLICATE_DETAIL_PRICE" % str(expected.name))
		var spec: Dictionary = _spec()
		var allowed: Array[Rect2] = [spec.get("region", Rect2())]
		var expanded_region: Rect2 = spec.get("expanded_region", Rect2())
		if expanded_region.has_area():
			allowed.append(expanded_region)
		var protected: Array[Rect2] = Common.rects_of(panel, _grids_shop())
		var errors: Array[String] = Helper.inspect(panel, view, allowed, protected, str(expected.name), int(expected.item_id), expected.color, body_text)
		checked += 1
		var snapshot: Dictionary = view.call("debug_layout_snapshot")
		rows.append({
			"zone": zone, "item_id": int(expected.item_id), "name": str(expected.name),
			"expected_color": str(expected.color), "actual_color": str(snapshot.get("title_color", "")),
			"body_text": body_text, "detail_rect": str(snapshot.get("rect", "")),
			"body_content_height": float(snapshot.get("body_content_height", 0.0)),
			"alpha": float((view as CanvasItem).modulate.a), "scroll_active": bool(snapshot.get("scroll_active", false)),
			"errors": errors, "test_commit": "r61-r1-review",
		})
		for error: String in errors:
			failures.append("shop_buy|%s|%s" % [str(expected.name), error])
		print("R61_T zone=%s id=%d ms=%d" % [zone, int(expected.item_id), int(Time.get_ticks_msec() - _record_started_ms)])
		_record_started_ms = Time.get_ticks_msec()
		if errors.is_empty() and showcase_budget > 0 and (str(expected.name).contains("药") or str(expected.name).contains("书")):
			await _snap("matrix_shop_buy_%d" % int(expected.item_id))
			showcase_budget -= 1
	panel.call("_ui_dismiss_selection")
	panel.queue_free()
	await settle()

func _grids_shop() -> Array:
	return panel.find_children("*", "GridContainer", true, false)

func _run_shop_sell(expected_all: Array[Dictionary]) -> void:
	showcase_budget = 2
	var ShopScript := load("res://scripts/shop_panel.gd")
	panel = ShopScript.new()
	add_child(panel)
	await settle()
	panel.call("_set_trade_mode", "sell")
	await settle()
	for expected: Dictionary in expected_all:
		var record: Dictionary = Common.seed_record(str(expected.name))
		if record.is_empty():
			checked += 1
			failures.append("shop_sell|%s|SEED_RECEIVE_FAILED" % str(expected.name))
			continue
		var quotes: Dictionary = {}
		for i: int in range(PlayerState.inventory.size()):
			var inv_record: Dictionary = PlayerState.inventory[i]
			quotes[panel.call("sell_quote_key", i, inv_record)] = {
				"sellable": true, "unit_price": 1, "max_quantity": 1,
				"risk_flags": [], "reason": "r61-review quote fixture",
			}
		panel.call("set_sell_quotes", quotes)
		await settle(2)
		panel.call("_select_sell_item", 0)
		await settle()
		var view := _presenter()
		if view == null:
			checked += 1
			failures.append("shop_sell|%s|PRESENTER_MISSING" % str(expected.name))
			PlayerState.inventory = []
			continue
		var body_text := str(view.get("detail_label").text)
		var spec: Dictionary = _spec()
		var allowed: Array[Rect2] = [spec.get("region", Rect2())]
		var expanded_region: Rect2 = spec.get("expanded_region", Rect2())
		if expanded_region.has_area():
			allowed.append(expanded_region)
		var protected: Array[Rect2] = Common.rects_of(panel, _grids_shop())
		var errors: Array[String] = Helper.inspect(panel, view, allowed, protected, str(expected.name), int(expected.item_id), expected.color, body_text)
		checked += 1
		var snapshot: Dictionary = view.call("debug_layout_snapshot")
		rows.append({
			"zone": zone, "item_id": int(expected.item_id), "name": str(expected.name),
			"instance_id": str(record.get("instance_id", "")), "affix": Common.instance_affixes(record),
			"expected_color": str(expected.color), "actual_color": str(snapshot.get("title_color", "")),
			"body_text": body_text, "detail_rect": str(snapshot.get("rect", "")),
			"body_content_height": float(snapshot.get("body_content_height", 0.0)),
			"alpha": float((view as CanvasItem).modulate.a), "scroll_active": bool(snapshot.get("scroll_active", false)),
			"errors": errors, "test_commit": "r61-r1-review",
		})
		for error: String in errors:
			failures.append("shop_sell|%s|%s" % [str(expected.name), error])
		PlayerState.inventory = []
	panel.call("_ui_dismiss_selection")
	panel.queue_free()
	await settle()
