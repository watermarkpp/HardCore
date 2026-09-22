extends Node

## Real ShopPanel function-level regression. Deliberately controlled quote fixtures.
## Does NOT claim to test real pricing authority, device touch or all item layouts.
## No buy/sell action is invoked. Use the project's isolated user:// runner only.
const ShopScript := preload("res://scripts/shop_panel.gd")
const Style := preload("res://scripts/ui_item_name_style.gd")
const GROUPS := ["default", "wooma", "zuma", "redmoon", "ultra_rare"]
var failures: Array[String] = []
var checks := 0
var rows: Array = []
var shop: Control
var fixtures: Dictionary = {}
var requests := {"buy": 0, "sell": 0}

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func settle() -> void:
	for unused in range(3):
		await get_tree().process_frame

func _collect_fixtures() -> bool:
	if not GameData.ensure_loaded() or not Style.ensure_loaded():
		failures.append("DATA_NOT_LOADED")
		return false
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(Style.DATA_PATH))
	if not data is Dictionary:
		failures.append("RARITY_DATA_INVALID")
		return false
	var mapping: Dictionary = data.get("records", {})
	var ids: Array[int] = []
	for key: Variant in mapping:
		ids.append(int(key))
	ids.sort()
	for item_id: int in ids:
		var group := str(mapping[str(item_id)].get("name_style", "default"))
		if not group in GROUPS or fixtures.has(group):
			continue
		var item: Dictionary = GameData.get_item_record(item_id)
		if item.is_empty() or str(item.get("kind", "")) != "equipment":
			continue
		if Style.canonical_id(item) != item_id:
			continue
		fixtures[group] = {
			"item_id": item_id, "name": Style.display_name(item), "count": 1,
			"instance_id": "r61-review:" + str(item_id),
		}
	for group: String in GROUPS:
		expect(fixtures.has(group), "mapped runtime equipment fixture exists: " + group)
	return fixtures.size() == GROUPS.size()

func _quotes() -> Dictionary:
	var result: Dictionary = {}
	for i in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[i]
		result[shop.sell_quote_key(i, record)] = {
			"sellable": true, "unit_price": 100 + i, "max_quantity": 1,
			"risk_flags": [], "reason": "review-only quote fixture",
		}
	return result

func _new_pair(a: String, b: String) -> void:
	shop._ui_dismiss_selection()
	PlayerState.inventory = [fixtures[a].duplicate(true), fixtures[b].duplicate(true)]
	shop.set_sell_quotes(_quotes())
	await settle()

func _assert_view_for(index: int, label: String) -> void:
	var record: Dictionary = PlayerState.inventory[index]
	var item: Dictionary = GameData.get_item_record(record)
	var expected: Dictionary = Style.describe(item, record)
	var view = shop.item_detail_presenter
	var actual: Dictionary = view.debug_layout_snapshot()
	var name_style: Dictionary = actual.get("name_style", {})
	expect(view.visible, label + ": detail exists")
	expect(str(actual.get("title", "")) == Style.display_name(item, record), label + ": title matches displayed record")
	expect(int(name_style.get("item_id", -1)) == int(record.item_id), label + ": rarity ID matches displayed record")
	expect(str(name_style.get("group", "")) == str(expected.group), label + ": rarity group matches displayed record")
	var actual_color: Color = view.title_label.get_theme_color("font_color")
	var expected_color: Color = expected.color
	expect(actual_color.is_equal_approx(expected_color), label + ": title color matches displayed record")
	for name_label: Label in [view.title_label, shop.goods_buttons[index].get_node("ItemName")]:
		expect(name_label.get_theme_color("font_color").is_equal_approx(expected_color), label + ": card and title share name color")
		if str(expected.group) == "ultra_rare":
			expect(name_label.get_theme_color("font_outline_color") == Color("B08A3E") and name_label.get_theme_constant("outline_size") == 2, label + ": rare red text has gold edge")
		else:
			expect(not name_label.has_theme_color_override("font_outline_color"), label + ": ordinary title/card clears rare edge")
	rows.append({"case": label, "expected_id": record.item_id, "actual_id": name_style.get("item_id", -1), "expected_group": expected.group, "actual_group": name_style.get("group", ""), "title": actual.get("title", "")})

func _run() -> void:
	var saved_inventory: Array = PlayerState.inventory.duplicate(true)
	var saved_gold: int = PlayerState.gold
	if not _collect_fixtures():
		_finish()
		return
	PlayerState.inventory = [fixtures.default.duplicate(true), fixtures.wooma.duplicate(true)]
	shop = ShopScript.new()
	add_child(shop)
	shop.buy_requested.connect(func(_request: Dictionary) -> void: requests["buy"] += 1)
	shop.sell_requested.connect(func(_request: Dictionary) -> void: requests["sell"] += 1)
	await settle()
	shop._set_trade_mode("sell")
	await settle()
	# All ordered pairs of the 5 styles; not just two same-color items.
	for a: String in GROUPS:
		for b: String in GROUPS:
			if a == b:
				continue
			await _new_pair(a, b)
			var before := JSON.stringify(PlayerState.inventory)
			shop._select_sell_item(0)
			_assert_view_for(0, a + "/" + b + ": select A")
			shop._select_sell_item(1)
			_assert_view_for(1, a + "/" + b + ": select B")
			shop._select_sell_item(1)
			expect(shop._selected_sell_index == 0, "cancel B keeps A selected")
			_assert_view_for(0, a + "/" + b + ": cancel B -> A")
			shop._select_sell_item(0)
			expect(shop._selected_sell_index == -1 and not shop.item_detail_presenter.visible, "empty selection hides item detail")
			expect(JSON.stringify(PlayerState.inventory) == before, "selection never mutates inventory")
	# When a remaining selection loses its quote, the waiting-quote branch must
	# still use that remaining item's ID, not the just-deselected item's ID.
	await _new_pair("wooma", "ultra_rare")
	shop._select_sell_item(0)
	shop._select_sell_item(1)
	shop._sell_quotes.erase(shop.sell_quote_key(0, PlayerState.inventory[0]))
	shop._select_sell_item(1)
	_assert_view_for(0, "missing remaining quote after cancel B")
	expect(shop.sell_quantity_button.disabled, "missing quote disables selling")
	# Non-sellable preview is intentionally the clicked record, NOT a replacement
	# of the existing sell selection. Never globally substitute every index.
	await _new_pair("default", "redmoon")
	shop._select_sell_item(0)
	var blocked_key: String = shop.sell_quote_key(1, PlayerState.inventory[1])
	shop._sell_quotes[blocked_key] = {"sellable": false, "reason": "review blocked", "max_quantity": 1}
	shop._select_sell_item(1)
	expect(shop._selected_sell_index == 0, "non-sellable preview retains existing sell selection")
	_assert_view_for(1, "non-sellable preview B while A remains selected")
	expect(requests.buy == 0 and requests.sell == 0, "selection never emits a trade action")
	expect(PlayerState.gold == saved_gold, "selection never changes gold")
	shop.queue_free()
	await settle()
	PlayerState.inventory = saved_inventory
	_finish()

func _finish() -> void:
	var out := FileAccess.open("user://r61_review_shop_selection_identity.json", FileAccess.WRITE)
	if out == null:
		failures.append("EVIDENCE_WRITE_FAILED")
	else:
		out.store_string(JSON.stringify({"checks": checks, "failures": failures, "rows": rows, "scope": "real_shop_function_level_with_controlled_quotes_not_device_input"}))
		out.close()
	for message: String in failures:
		push_error("R61_REVIEW_SHOP_IDENTITY: " + message)
	print("R61_REVIEW_SHOP_IDENTITY_%s checks=%d failures=%d" % ["PASS" if failures.is_empty() else "FAIL", checks, failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
