extends Node

const PricingServiceScript := preload("res://scripts/pricing_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress(false)
	var wood := GameData.get_item_price_record("木剑")
	var potion := GameData.get_item_price_record("金创药(小量)")
	assert(int(wood.get("base_price", 0)) == 50 and str(wood.get("item_key", "")) == "service:221")
	assert(int(potion.get("base_price", 0)) == 40 and str(potion.get("source", {}).get("distribution", "")) == "server.crystal.cjlaaa")
	var general_stock := GameData.merchant_stock("general")
	var weapon_stock := GameData.merchant_stock("starter_gear")
	var book_stock := GameData.merchant_stock("books")
	var medicine_stock := GameData.merchant_stock("medicine")
	assert(str(general_stock[0].get("name", "")) == "随机传送卷")
	assert(not general_stock.any(func(entry: Dictionary) -> bool: return str(entry.get("name", "")) in ["蜡烛", "火把", "护身符"]))
	assert(str(weapon_stock[0].get("name", "")) == "木剑")
	assert(str(book_stock[0].get("name", "")) == "基本剑术")
	assert(not medicine_stock.is_empty() and str(medicine_stock[0].get("name", "")) == "金疮药(小量)")
	assert(medicine_stock.all(func(entry: Dictionary) -> bool: return int(entry.get("pack_count", 0)) == 1))
	assert(str(medicine_stock[0].get("merchant_id", "")) == "merchant.server.crystal.cjlaaa.29")
	var bich_content := MapEditorRuntimeBridge.game_content_for_map(4)
	var pharmacist_rows: Array = (bich_content.get("npcs", []) as Array).filter(
		func(entry: Dictionary) -> bool:
			return str(entry.get("npc_id", "")) == "npc.expansion.bich_pharmacist"
	)
	assert(pharmacist_rows.size() == 1 and str((pharmacist_rows[0] as Dictionary).get("stock", "")) == "medicine", "比奇药剂商没有绑定主库药店货单")
	assert(str(general_stock[0].get("merchant_id", "")) == "merchant.server.crystal.cjlaaa.33")
	assert(not bool(GameData.merchant_context("general").get("supports_repair", true)))
	assert(bool(GameData.merchant_context("starter_gear").get("supports_repair", false)))
	assert(GameData.merchant_context("starter_gear").get("types", []) == [1, 14])
	var buy := PricingServiceScript.quote_buy(wood)
	assert(bool(buy.get("valid", false)) and int(buy.get("unit_price", 0)) == 55)
	var full_instance := {"name": "木剑", "durability": 4, "max_durability": 4, "instance_id": "pricing-full"}
	var sell := PricingServiceScript.quote_sell(wood, GameData.get_item_record("木剑"), full_instance)
	assert(bool(sell.get("valid", false)) and int(sell.get("unit_price", 0)) == 28)
	var starter_context := GameData.merchant_context("starter_gear")
	var general_context := GameData.merchant_context("general")
	var accepted_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, starter_context
	)
	var cross_merchant_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, general_context
	)
	assert(bool(accepted_sell.get("valid", false)), "主库Types允许的武器没有出售报价")
	assert(bool(cross_merchant_sell.get("valid", false)), "项目统一回收规则没有允许杂货商回收武器")
	var rated_context := starter_context.duplicate(true)
	rated_context["merchant_id"] = "merchant.test.rate"
	rated_context["merchant_rate_bps"] = 13000
	var rated_sell := PricingServiceScript.quote_sell(
		wood, GameData.get_item_record("木剑"), full_instance, 1, rated_context
	)
	assert(
		bool(rated_sell.get("valid", false))
		and int(rated_sell.get("unit_price", 0)) == 36,
		"Merchant Rate没有进入出售权威报价"
	)
	var half_instance := full_instance.duplicate(true)
	half_instance["durability"] = 2
	var half_sell := PricingServiceScript.quote_sell(wood, GameData.get_item_record("木剑"), half_instance)
	assert(int(half_sell.get("unit_price", 0)) < int(sell.get("unit_price", 0)))
	var repair := PricingServiceScript.quote_repair(wood, GameData.get_item_record("木剑"), {"durability": 0, "max_durability": 4})
	assert(bool(repair.get("valid", false)) and int(repair.get("total_price", 0)) == 9)
	var blacksmith_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		GameData.merchant_context("starter_gear")
	)
	assert(bool(blacksmith_repair.get("valid", false)) and int(blacksmith_repair.get("total_price", 0)) == 9)
	var grocery_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		GameData.merchant_context("general")
	)
	assert(not bool(grocery_repair.get("valid", true)))
	var wrong_type_repair_context := starter_context.duplicate(true)
	wrong_type_repair_context["merchant_id"] = "merchant.test.wrong_type"
	wrong_type_repair_context["types"] = [13]
	var wrong_type_repair := PricingServiceScript.quote_repair(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		wrong_type_repair_context
	)
	assert(not bool(wrong_type_repair.get("valid", true)), "主库Types不允许的装备仍可维修")
	var partial_repair := PricingServiceScript.quote_repair_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		1,
		GameData.merchant_context("starter_gear")
	)
	var larger_partial_repair := PricingServiceScript.quote_repair_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 0, "max_durability": 4},
		2,
		GameData.merchant_context("starter_gear")
	)
	var raw_repair := PricingServiceScript.quote_repair_raw_delta(
		wood,
		GameData.get_item_record("木剑"),
		{"durability": 4, "max_durability": 4, "durability_raw": 3998, "max_durability_raw": 4000},
		2
	)
	assert(
		raw_repair.valid
		and int(raw_repair.formula_snapshot.repair_amount_raw) == 2
		and int(raw_repair.formula_snapshot.target_durability_raw) == 4000,
		"不足1显示点的raw耐久没有进入维修报价"
	)
	assert(bool(partial_repair.get("valid", false)) and int(partial_repair.get("total_price", 0)) >= 1)
	assert(int(larger_partial_repair.get("total_price", 0)) >= int(partial_repair.get("total_price", 0)))
	assert(int(blacksmith_repair.get("total_price", 0)) >= int(larger_partial_repair.get("total_price", 0)))
	assert(int(partial_repair.get("formula_snapshot", {}).get("repair_amount", 0)) == 1)
	assert(int(partial_repair.get("formula_snapshot", {}).get("target_durability", 0)) == 1)
	assert(bool(partial_repair.get("formula_snapshot", {}).get("preserve_maximum_durability", false)))

	var custom := PricingServiceScript.policy()
	custom["policyVersion"] = "test.multiplier"
	custom["modifiers"]["globalBps"] = 13000
	custom["modifiers"]["categoryBps"] = {"武器": 7000}
	custom["modifiers"]["itemBps"] = {"service:221": 7000}
	assert(PricingServiceScript.adjusted_database_price(wood, custom) == 32)
	var forge := PricingServiceScript.estimate_forge_materials(
		[{"item_name": "木剑", "quantity": 2}], {"木剑": wood}, custom
	)
	assert(bool(forge.get("valid", false)) and int(forge.get("total_value", 0)) == 64)

	var stock := [{"name": "木剑", "description": "主库定价测试"}]
	PlayerState.gold = 100
	var quotes := PlayerState.shop_buy_quotes(stock)
	assert(quotes.size() == 1 and int(quotes[0].get("unit_price", 0)) == 55)
	var request := {"stock_index": 0, "quote_id": quotes[0].get("quote_id", ""), "quantity": 1}
	var buy_result := PlayerState.buy_shop_item(request, stock)
	assert(bool(buy_result.get("success", false)) and PlayerState.gold == 45 and PlayerState.has_item("木剑"))
	var inventory_after := PlayerState.inventory.duplicate(true)
	var replay := PlayerState.buy_shop_item(request, stock)
	assert(not bool(replay.get("success", false)) and PlayerState.gold == 45 and PlayerState.inventory == inventory_after)
	var tampered := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": "tampered", "quantity": 1}, stock)
	assert(not bool(tampered.get("success", false)) and PlayerState.gold == 45 and PlayerState.inventory == inventory_after)
	PlayerState.gold = 1
	var poor_quotes := PlayerState.shop_buy_quotes(stock)
	var poor_before := PlayerState.inventory.duplicate(true)
	var poor := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": poor_quotes[0].get("quote_id", ""), "quantity": 1}, stock)
	assert(not bool(poor.get("success", false)) and PlayerState.gold == 1 and PlayerState.inventory == poor_before)
	PlayerState.gold = 100
	var renewed_quotes := PlayerState.shop_buy_quotes(stock)
	assert(str(renewed_quotes[0].get("quote_id", "")) != str(quotes[0].get("quote_id", "")))
	var second_buy := PlayerState.buy_shop_item({"stock_index": 0, "quote_id": renewed_quotes[0].get("quote_id", ""), "quantity": 1}, stock)
	assert(bool(second_buy.get("success", false)) and PlayerState.item_count("木剑") == 2)

	var pack_stock := [{"name": "随机传送卷", "pack_count": 20}]
	PlayerState.gold = 100000
	var pack_quotes := PlayerState.shop_buy_quotes(pack_stock)
	assert(int(pack_quotes[0].get("quantity", 0)) == 20)
	assert(int(pack_quotes[0].get("total_price", 0)) == int(pack_quotes[0].get("unit_price", 0)) * 20)

	print("PRICING_AUTHORITY_PASS：主库价格、倍率、买卖事务、维修与锻造估值正常")
	get_tree().quit(0)
