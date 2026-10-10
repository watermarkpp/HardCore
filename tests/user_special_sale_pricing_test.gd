extends Node

const BlackIronRules := preload("res://scripts/layers/rules/equipment_enhancement_black_iron.gd")
const RelicRules := preload("res://scripts/layers/rules/relic_synthesis_rules.gd")

const EXPECTED := {
	940010: 90000, 940011: 90000, 940012: 90000, 940013: 90000,
	940014: 90000, 940015: 90000, 940016: 90000, 940017: 90000,
	940018: 90000, 940019: 90000, 940020: 90000,
	950001: 100000,
	950101: 200000, 950102: 200000, 950103: 200000,
	950201: 200000, 950202: 200000, 950203: 200000,
	920032: 1000000,
}

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(GameData.ensure_loaded(), "formal catalog load failed")
	PlayerState.test_mode = true
	PlayerState.active_profile_id = "user_special_sale_pricing"
	PlayerState.profile_directory = "user://user_special_sale_pricing/characters"
	PlayerState.profile_index_path = "user://user_special_sale_pricing/profiles.json"
	PlayerState.reset_progress(false)
	var context := GameData.merchant_context("general")
	assert(not context.is_empty(), "general merchant context missing")
	for raw_id: Variant in EXPECTED.keys():
		var item_id := int(raw_id)
		var catalog := GameData.get_item_record({"item_id": item_id})
		assert(not catalog.is_empty(), "registered catalog item missing: %d" % item_id)
		var price_record := GameData.get_item_price_record({"item_id": item_id})
		if item_id == 920032:
			assert(price_record == GameData.get_item_price_record({"service_index": 871}), "item/service quote aliases must share the same owner")
			assert(price_record == GameData.get_item_price_record("祖玛头像"), "name import boundary must resolve the same owner")
		assert(int(price_record.get("base_price", 0)) == EXPECTED[item_id] * 2,
			"price authority base does not encode the requested half-price sale: %d owner_item=%s owner_service=%s name=%s" % [
				item_id, str(price_record.get("item_id", -1)), str(price_record.get("service_index", -1)), str(price_record.get("item_name", ""))
			])
		var instance := _instance_for(item_id, catalog)
		var direct := PricingService.quote_sell(price_record, catalog, instance, 1, context)
		assert(bool(direct.get("valid", false)) and int(direct.get("unit_price", 0)) == EXPECTED[item_id],
			"direct sell quote mismatch for %d price_kind=%s catalog_kind=%s prohibited=%s: %s" % [item_id, price_record.get("kind", ""), catalog.get("kind", ""), PricingService.policy().get("sell", {}).get("nonTradableKinds", []), direct])
	var protected_quests := 0
	for catalog: Dictionary in GameData.item_catalog:
		if str(catalog.get("kind", "")) != "quest_item" or GameData.item_entity_id(catalog) == "hc.item.920032":
			continue
		var price_record := GameData.get_item_price_record(catalog)
		if price_record.is_empty():
			continue
		var rejected := PricingService.quote_sell(price_record, catalog, catalog, 1, context)
		assert(not bool(rejected.get("valid", false)), "other quest items must retain their sale protection")
		protected_quests += 1
	assert(protected_quests > 0, "real non-target quest sale protection coverage missing")
	var head := GameData.get_item_record({"item_id": 920032})
	var bound_head := _instance_for(920032, head)
	bound_head["bound"] = true
	assert(not bool(PricingService.quote_sell(GameData.get_item_price_record(head), head, bound_head, 1, context).get("valid", false)), "bound protection must still apply to the exact exception")

	# Exercise the real PlayerState quote -> commit boundary for one item in
	# each special group. The normal save/rollback authority remains in charge.
	for item_id: int in [940010, 950001, 950101, 950201, 920032]:
		var catalog := GameData.get_item_record({"item_id": item_id})
		var instance := _instance_for(item_id, catalog)
		PlayerState.inventory = [instance]
		PlayerState.gold = 0
		var request := _sell_request(instance, context)
		var quote: Dictionary = PlayerState.shop_sell_quotes([request]).get(request.quote_key, {})
		assert(bool(quote.get("sellable", false)), "formal quote rejected %d: %s" % [item_id, quote])
		assert(int(quote.get("unit_price", 0)) == EXPECTED[item_id])
		request["quote_id"] = str(quote.get("quote_id", ""))
		var result := PlayerState.sell_inventory_item(request)
		assert(bool(result.get("success", false)), "formal commit rejected %d: %s" % [item_id, result])
		assert(PlayerState.inventory.all(func(record: Dictionary) -> bool: return record.is_empty()), "formal inventory normalization must not retain or duplicate the sold item")
		assert(PlayerState.gold == EXPECTED[item_id], "formal commit gold mismatch for %d" % item_id)
	print("USER_SPECIAL_SALE_PRICING_PASS: black_iron_11 fragment relic_3 badge_3 zuma_head quote_commit_5")
	get_tree().quit(0)


func _instance_for(item_id: int, catalog: Dictionary) -> Dictionary:
	var instance := catalog.duplicate(true)
	instance["item_id"] = item_id
	instance["instance_id"] = "user-sale-%d" % item_id
	instance["count"] = 1
	if item_id >= 950100:
		instance["durability"] = 1
		instance["max_durability"] = 1
	return instance


func _sell_request(instance: Dictionary, context: Dictionary) -> Dictionary:
	return {
		"quote_key": "instance:%s" % str(instance.get("instance_id", "")),
		"inventory_index": 0,
		"instance_id": str(instance.get("instance_id", "")),
		"item_name": str(instance.get("name", "")),
		"count": 1,
		"amount": 1,
		"merchant_id": str(context.get("merchant_id", "")),
		"merchant_stock_key": str(context.get("stock_key", "")),
	}
