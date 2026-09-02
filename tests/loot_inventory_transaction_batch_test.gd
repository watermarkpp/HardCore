extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	assert(GameData.ensure_loaded(), "catalog load failed")
	PlayerState.test_mode = true
	PlayerState._test_force_atomic_write_failure = false
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.gold = 0
	PlayerState.test_transaction_debug_reset()
	var stack_item := "金创药(小量)"
	assert(not GameData.get_item_record(stack_item).is_empty(), "deterministic stack item missing")
	var batch := []
	for index in range(32):
		batch.append({"item_name": stack_item})
	var result := PlayerState.receive_loot_batch_partial(batch)
	assert(result.success and result.success_count == 32, "pickup batch failed")
	assert(PlayerState.has_item(stack_item, 32), "pickup quantity incorrect")
	var counters := PlayerState.test_transaction_debug_snapshot()
	var loot_debug := PlayerState.loot_batch_debug_snapshot()
	assert(counters.commit_attempts == 1 and loot_debug.plan_scans == 1, "pickup was not one transaction")
	assert(loot_debug.occupied_scans == 1, "pickup repeated the fixed-slot occupied scan")
	assert(loot_debug.catalog_lookups == 1, "pickup repeated the catalog lookup for one item kind")
	assert(bool(PlayerState._last_runtime_commit_profile.get("profile_index_skipped", false)), "pickup rewrote the unrelated character index")
	var before := PlayerState.inventory.duplicate(true)
	var gold_before := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	var failed := PlayerState.receive_loot_batch_partial([{"item_name": stack_item}, {"gold": true, "amount": 10}])
	assert(not failed.success and PlayerState.inventory == before and PlayerState.gold == gold_before, "pickup save rollback failed")
	PlayerState._test_force_atomic_write_failure = false
	var merchant_keys: Array = (GameData.merchant_catalog.get("merchants", {}) as Dictionary).keys()
	assert(not merchant_keys.is_empty(), "merchant catalog missing")
	var merchant_context := GameData.merchant_context(str(merchant_keys[0]))
	var merchant_id := str(merchant_context.get("merchant_id", ""))
	var sell_name := ""
	for raw_offer: Variant in GameData.merchant_stock(str(merchant_keys[0])):
		if raw_offer is Dictionary:
			var candidate := str((raw_offer as Dictionary).get("name", ""))
			if not candidate.is_empty():
				sell_name = candidate
				break
	assert(not sell_name.is_empty(), "merchant has no deterministic stock item")
	PlayerState.inventory = [
		{"name": "太阳水", "count": 1, "guard": "head"},
		{"name": sell_name, "count": 1},
		{},
		{"name": sell_name, "count": 1},
		{"name": "太阳水", "count": 1, "guard": "tail"},
	]
	var sell_items := []
	var sell_indices := [1, 3]
	for index: int in sell_indices:
		var record: Dictionary = PlayerState.inventory[index]
		sell_items.append({"quote_key": "inventory:%d" % index, "inventory_index": index, "instance_id": "", "item_name": sell_name, "count": 1, "merchant_id": merchant_id, "merchant_stock_key": str(merchant_context.get("stock_key", merchant_keys[0]))})
	var quotes := PlayerState.shop_sell_quotes(sell_items)
	var requests := []
	for index: int in sell_indices:
		var quote: Dictionary = quotes["inventory:%d" % index]
		assert(bool(quote.get("sellable", false)), "merchant stock item unexpectedly not sellable")
		requests.append({"quote_key": "inventory:%d" % index, "quote_id": str(quote.get("quote_id", "")), "inventory_index": index, "instance_id": "", "item_name": sell_name, "amount": 1, "merchant_id": merchant_id})
	var sell_inventory_before := PlayerState.inventory.duplicate(true)
	var sell_gold_before := PlayerState.gold
	var consumed_before := PlayerState._consumed_shop_sell_quote_ids.duplicate(true)
	PlayerState.test_transaction_debug_reset()
	PlayerState._test_force_atomic_write_failure = true
	var sell_failed := PlayerState.sell_inventory_items(requests)
	var failed_counters := PlayerState.test_transaction_debug_snapshot()
	assert(not sell_failed.success and PlayerState.inventory == sell_inventory_before and PlayerState.gold == sell_gold_before and PlayerState._consumed_shop_sell_quote_ids == consumed_before, "sell save failure did not fully rollback")
	assert(failed_counters.commit_attempts == 1 and failed_counters.inventory_signals == 0 and failed_counters.profile_signals == 0, "failed sell emitted transaction signals")
	PlayerState._test_force_atomic_write_failure = false
	var stale_requests := requests.duplicate(true)
	(stale_requests[1] as Dictionary)["quote_id"] = "stale-quote"
	PlayerState.test_transaction_debug_reset()
	var stale_result := PlayerState.sell_inventory_items(stale_requests)
	var stale_counters := PlayerState.test_transaction_debug_snapshot()
	assert(not stale_result.success and stale_counters.commit_attempts == 0 and PlayerState.inventory == sell_inventory_before and PlayerState.gold == sell_gold_before, "stale quote partially changed sell transaction")
	PlayerState.test_transaction_debug_reset()
	var sold := PlayerState.sell_inventory_items(requests)
	var sold_counters := PlayerState.test_transaction_debug_snapshot()
	assert(sold.success and sold_counters.commit_attempts == 1 and sold_counters.inventory_signals == 1 and sold_counters.profile_signals == 1, "sell batch transaction/signal contract failed")
	assert(PlayerState.inventory.size() == 5 and PlayerState.inventory[1].is_empty() and PlayerState.inventory[3].is_empty(), "批量出售没有保留绝对槽空洞")
	assert(str(PlayerState.inventory[0].get("guard", "")) == "head" and str(PlayerState.inventory[4].get("guard", "")) == "tail", "批量出售移动了未售出物品")
	PlayerState.inventory = [
		{"name": "太阳水", "count": 1, "guard": "head"},
		{"name": sell_name, "count": 1, "instance_id": "single-sell-fixture"},
		{"name": "太阳水", "count": 1, "guard": "tail"},
	]
	var single_item := {"quote_key": "instance:single-sell-fixture", "inventory_index": 1, "instance_id": "single-sell-fixture", "item_name": sell_name, "count": 1, "merchant_id": merchant_id, "merchant_stock_key": str(merchant_context.get("stock_key", merchant_keys[0]))}
	var single_quote: Dictionary = PlayerState.shop_sell_quotes([single_item]).get("instance:single-sell-fixture", {})
	PlayerState.test_transaction_debug_reset()
	var single_sold := PlayerState.sell_inventory_item({"quote_key": "instance:single-sell-fixture", "quote_id": str(single_quote.get("quote_id", "")), "inventory_index": 1, "instance_id": "single-sell-fixture", "item_name": sell_name, "amount": 1, "merchant_id": merchant_id})
	var single_counters := PlayerState.test_transaction_debug_snapshot()
	assert(single_sold.success and single_counters.commit_attempts == 1 and single_counters.inventory_signals == 1 and single_counters.profile_signals == 1, "单项出售没有保持一次 commit/signal")
	assert(PlayerState.inventory.size() == 3 and PlayerState.inventory[1].is_empty() and str(PlayerState.inventory[2].get("guard", "")) == "tail", "单项出售移动了后续绝对槽")
	PlayerState.test_transaction_debug_reset()
	PlayerState.level = 1
	PlayerState.experience = 0
	var death := PlayerState.record_kill_and_experience("不存在的怪物", PlayerState.experience_to_next_level())
	assert(death.success and PlayerState.test_transaction_debug_snapshot().commit_attempts == 1, "death transaction failed")
	PlayerState.test_transaction_debug_reset()
	var death_before := [PlayerState.level, PlayerState.experience, PlayerState.computed_stats.duplicate(true)]
	PlayerState._test_force_atomic_write_failure = true
	var death_fail := PlayerState.record_kill_and_experience("不存在的怪物", 1)
	assert(not death_fail.success and PlayerState.level == death_before[0] and PlayerState.experience == death_before[1], "death rollback failed")
	PlayerState._test_force_atomic_write_failure = false
	print("LOOT_INVENTORY_TRANSACTION_BATCH_PASS")
	get_tree().quit(0)
