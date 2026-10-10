extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Shop := preload("res://scripts/shop_panel.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var proof := Proof.new()
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.gold = 0
	PlayerState.add_item("木剑")
	PlayerState.add_item("古铜戒指")
	var panel := Shop.new()
	add_child(panel)
	await get_tree().process_frame
	var quote_batches: Array = []
	var requests: Array = []
	panel.sell_quotes_requested.connect(func(items: Array) -> void:
		quote_batches.append(items)
		panel.set_sell_quotes(PlayerState.shop_sell_quotes(items))
	)
	panel.sell_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	panel.open_for("测试商人", [], GameData.merchant_context("general"))
	panel._set_trade_mode("sell")
	await get_tree().process_frame
	proof.record(not quote_batches.is_empty() and not panel._sell_quotes.is_empty(), "owner quote refresh populates the sell page")
	panel._select_sell_item(0)
	panel._select_sell_item(1)
	panel._request_sell()
	var request: Dictionary = requests[-1] if not requests.is_empty() else {}
	var batch: Array = request.get("batch", [])
	var inventory_before := PlayerState.inventory.duplicate(true)
	PlayerState.gold = PlayerState.PLAYER_GOLD_CAP
	var rejected := PlayerState.sell_inventory_items(batch)
	proof.record(
		not bool(rejected.get("success", true))
		and rejected.get("quotes", null) is Dictionary
		and (rejected.get("quotes", {}) as Dictionary).is_empty(),
		"real owner batch rejects at gold cap with empty quotes"
	)
	proof.record(PlayerState.inventory == inventory_before and PlayerState.gold == PlayerState.PLAYER_GOLD_CAP, "rejected owner transaction preserves inventory and gold")
	panel.apply_sell_result(rejected)
	var quote_key := panel.sell_quote_key(0, PlayerState.inventory[0])
	proof.record(
		not panel._sell_quotes.is_empty()
		and panel._sell_quotes.has(quote_key)
		and panel.goods_buttons.size() == 2,
		"empty failure quotes preserve current owner quotes and sell cards"
	)
	PlayerState.gold = 0
	panel._select_sell_item(0)
	panel._select_sell_item(1)
	requests.clear()
	panel._request_sell()
	var valid_request: Dictionary = requests[-1] if not requests.is_empty() else {}
	var valid_batch: Array = valid_request.get("batch", [])
	var accepted := PlayerState.sell_inventory_items(valid_batch)
	proof.record(bool(accepted.get("success", false)), "same owner batch can complete a later legal sale")
	proof.record(PlayerState.inventory.is_empty() and PlayerState.gold > 0, "legal batch sale mutates owner atomically")
	panel.apply_sell_result(accepted)
	proof.record(panel._selected_sell_indices.is_empty() and panel.sell_quantity_button.disabled, "successful sale clears selection through normal UI path")
	var failures := proof.records.filter(func(item: Dictionary) -> bool: return not bool(item.get("passed", false))).size()
	var receipt_ok: bool = proof.write_receipt("v109_shop_failed_empty_quotes_contract_test", proof.records.size(), failures)
	print("V109_SHOP_FAILED_EMPTY_QUOTES_%s" % ("PASS" if receipt_ok else "FAIL"))
	get_tree().quit(0 if receipt_ok else 1)
