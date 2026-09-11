extends Node

## §3.3 showcase capture for the R6.1-review evidence pack. Runs WINDOWED
## (no --headless, --resolution 1598x720, redirected APPDATA + --log-file by
## the invoking command) and saves one PNG per showcase scene into R6_SHOT_DIR.
## Every scene uses the real production panels and the real selection paths;
## the affixed equipment instance comes from the authoritative drop-rules
## factory with a recorded stable drop key. Also writes a JSON sidecar with
## the exact instance ids, affix records and drop keys used.

const Common := preload("res://tests/r6_1_review/real_panel_matrix_common.gd")

var shots: Array = []

func settle(frames := 3) -> void:
	for unused in range(frames):
		await get_tree().process_frame

func _snap(name_value: String, panel: Control, info: Dictionary = {}) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var dir := OS.get_environment("R6_SHOT_DIR")
	var path := dir + "/" + name_value + ".png"
	var error := image.save_png(path)
	print("R61_SHOT ", name_value, " -> ", path, " err=", error)
	var row := {"shot": name_value, "path": path}
	row.merge(info, true)
	shots.append(row)
	if panel != null:
		panel.call("_ui_dismiss_selection")

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.level = 60
	_run.call_deferred()

func _probe_diag() -> void:
	# One-shot structural probe: is the drop-instance factory returning an
	# invalid record (why) or generating instances whose roll simply misses?
	var sample: Dictionary = {}
	for value: Variant in GameData.item_catalog:
		if value is Dictionary and str((value as Dictionary).get("kind", "")) == "equipment":
			sample = value
			break
	var weapon_id := int(sample.get("itemId", -1))
	var identity_record: Dictionary = {"item_id": weapon_id, "canonical_item_id": weapon_id, "canonical_name": str(sample.get("name", "")), "source_item_id": weapon_id, "source_canonical_item_id": weapon_id, "source_canonical_name": str(sample.get("name", "")), "item_name": str(sample.get("name", "")), "name": str(sample.get("name", "")), "output_item_id": weapon_id, "output_record": sample.duplicate(true), "identity_status": "resolved"}
	var created: Dictionary = PlayerState.create_drop_item_instance(identity_record, "probe:key:0")
	var instance: Dictionary = created.get("item_instance", {})
	print("R61_PROBE id=%d instance_empty=%s invalid_reason=%s affix_applied=%s" % [weapon_id, str(instance.is_empty()), str(created.get("instance_invalid_reason", "")), str((instance.get("affix", {}) as Dictionary).get("applied", false))])

func _run() -> void:
	if not Common.ensure_data():
		get_tree().quit(1)
		return
	_probe_diag()
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	var ShopScript := load("res://scripts/shop_panel.gd")
	var WarehouseScript := load("res://scripts/warehouse_panel.gd")
	var SystemMenuScript := load("res://scripts/system_menu_panel.gd")

	# 1) Skill-book bag detail.
	var inventory: Control = InventoryScript.new()
	add_child(inventory)
	inventory.visible = true
	await settle()
	var book := Common.seed_record("治愈术")
	if book.is_empty():
		var books := ["治疗药水", "技能书"]
		for candidate: String in books:
			book = Common.seed_record(candidate)
			if not book.is_empty():
				break
	PlayerState.inventory = [book]
	inventory.call("refresh")
	await settle(2)
	inventory.call("_select_inventory_item", 0)
	await settle(2)
	await _snap("showcase_1_skillbook_bag_detail", inventory, {"item": str(book.get("name", "")), "instance_id": str(book.get("instance_id", ""))})

	# 2) Long-affix equipment-slot detail (authoritative drop-rules instance).
	# Build the resolved identity record exactly like the loot pipeline does,
	# then roll the 1/20 affix through create_drop_item_instance. Iterate the
	# real equipment catalog until the first legal affix rolls (some items have
	# no eligible stat mapping), recording the item and its stable drop key.
	var affixed := {}
	for value: Variant in GameData.item_catalog:
		if not value is Dictionary:
			continue
		var catalog: Dictionary = value
		if str(catalog.get("kind", "")) != "equipment":
			continue
		var weapon_id := int(catalog.get("itemId", -1))
		var identity_record: Dictionary = {
			"item_id": weapon_id,
			"canonical_item_id": weapon_id,
			"canonical_name": str(catalog.get("name", "")),
			"source_item_id": weapon_id,
			"source_canonical_item_id": weapon_id,
			"source_canonical_name": str(catalog.get("name", "")),
			"item_name": str(catalog.get("name", "")),
			"name": str(catalog.get("name", "")),
			"output_item_id": weapon_id,
			"output_record": catalog.duplicate(true),
			"identity_status": "resolved",
		}
		affixed = Common.affixed_drop_instance(identity_record, "r61-review-affix", 24)
		if not affixed.is_empty():
			break
	if affixed.is_empty():
		push_error("R61_SHOWCASE no affixed instance rolled")
	PlayerState.inventory = []
	if not affixed.is_empty():
		var instance: Dictionary = affixed.get("item_instance", {})
		var loot_result: Dictionary = PlayerState.call("receive_loot_batch_partial", [{
			"item_name": str(affixed.get("name", "")),
			"item_id": int(affixed.get("item_id", -1)),
			"item_instance": instance,
		}])
		var loot_outcomes: Array = loot_result.get("outcomes", [])
		if loot_outcomes.is_empty() or not bool((loot_outcomes[0] as Dictionary).get("success", false)):
			push_error("R61_SHOWCASE affixed loot intake rejected")
	var equip_result: Dictionary = PlayerState.call("equip_inventory_index_result", 0)
	var slot := ""
	var affixed_instance_id := str((affixed.get("item_instance", {}) as Dictionary).get("instance_id", ""))
	for key: Variant in PlayerState.equipment:
		var equipped: Variant = PlayerState.equipment[key]
		if equipped is Dictionary and str((equipped as Dictionary).get("instance_id", "")) == affixed_instance_id:
			slot = str(key)
	inventory.call("refresh")
	await settle(2)
	inventory.call("_select_equipment_slot", slot)
	await settle(2)
	await _snap("showcase_2_affixed_equipment_slot_detail", inventory, {"item": str(affixed.get("name", "")), "instance_id": affixed_instance_id, "modifiers": Common.instance_affixes(affixed.get("item_instance", {})), "drop_key": str(affixed.get("review_drop_key", ""))})
	inventory.call("_ui_dismiss_selection")
	inventory.queue_free()

	# 3) Warehouse selected detail (stash side). Seed the stash before the
	# panel opens so the initial grid fill shows the item.
	var warehouse: Control = WarehouseScript.new()
	add_child(warehouse)
	var stash_record := Common.seed_record("珊瑚戒指")
	PlayerState.warehouse_inventory = [stash_record]
	PlayerState.inventory = []
	if warehouse.has_method("open_panel"):
		warehouse.call("open_panel")
	await settle(3)
	await settle(1)
	warehouse.call("_select_item", "stash", 0)
	await settle(2)
	await _snap("showcase_3_warehouse_stash_selected_detail", warehouse, {"item": str(stash_record.get("name", "")), "instance_id": str(stash_record.get("instance_id", ""))})
	warehouse.call("_ui_dismiss_selection")
	warehouse.queue_free()

	# 4) Non-empty goods buy detail with real quote text.
	var shop: Control = ShopScript.new()
	add_child(shop)
	var stock: Array = []
	for expected: Dictionary in Common.expected_items():
		stock.append({"name": str(expected.name), "item_id": str(expected.name), "count": 1})
	shop.call("open_for", "审查展示商店", stock, {"mode": "sell"})
	var quotes: Array = []
	for i: int in range(stock.size()):
		quotes.append({"stock_index": i, "valid": true, "unit_price": 12, "pack_count": 3, "total_price": 36, "reason": "r61-review showcase quote", "risk_flags": []})
	shop.call("set_buy_quotes", quotes)
	await settle(2)
	shop.call("_on_item_selected", 0)
	await settle(2)
	await _snap("showcase_4_shop_buy_nonempty_quote_detail", shop, {"item": str(stock[0].get("name", ""))})

	# 5) Multi-color multi-select then cancel one in sell mode. Seed through
	# the real add_item path so the panel's inventory-changed signal rebuilds
	# the sell list (a direct array assignment bypasses it).
	PlayerState.inventory = []
	for name_value: String in ["木剑", "珊瑚戒指", "金创药(中量)", "井中月", "无极棍"]:
		Common.seed_record(name_value)
	var sell_quotes: Dictionary = {}
	for i: int in range(PlayerState.inventory.size()):
		var inv_record: Dictionary = PlayerState.inventory[i]
		sell_quotes[shop.call("sell_quote_key", i, inv_record)] = {"sellable": true, "unit_price": 5, "max_quantity": 1, "risk_flags": [], "reason": "r61-review showcase quote"}
	# The mode switch clears quotes and requests fresh ones; inject the
	# fixture quotes AFTER the switch (the matrix sell zone uses this order).
	shop.call("_set_trade_mode", "sell")
	shop.call("set_sell_quotes", sell_quotes)
	await settle(2)
	for i: int in range(PlayerState.inventory.size()):
		shop.call("_select_sell_item", i)
	await settle()
	shop.call("_select_sell_item", 0)  # cancel the first selection
	await settle(2)
	await _snap("showcase_5_shop_sell_multicolor_cancel_detail", shop, {"selected": PlayerState.inventory.map(func(r: Variant) -> String: return str((r as Dictionary).get("name", "")))})
	shop.call("_ui_dismiss_selection")
	shop.queue_free()
	PlayerState.inventory = []
	PlayerState.warehouse_inventory = []

	# 6) System menu settings page with both audio rows.
	var menu: Control = SystemMenuScript.new()
	add_child(menu)
	await settle()
	menu.call("open_menu")
	await settle()
	menu.call("show_settings_page")
	menu.call("set_audio_levels", 0.45, 0.72)
	await settle(3)
	await _snap("showcase_6_system_settings_audio_rows", null, {"music": 0.45, "sfx": 0.72})
	menu.queue_free()

	var out := FileAccess.open("user://r61_review_showcase_capture.json", FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify({"shots": shots}, "  ", false))
		out.close()
	print("R61_SHOWCASE_%s shots=%d" % ["DONE", shots.size()])
	get_tree().quit(0)
