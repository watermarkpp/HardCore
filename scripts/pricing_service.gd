class_name PricingService
extends RefCounted

const CONTRACT_ID := "gameplay.pricing.authority.v1"
const POLICY_PATH := "res://assets/data/pricing_policy_v1.json"
const BPS_DENOMINATOR := 10000

static var _cached_policy: Dictionary = {}
static var _cached_policy_hash := ""


static func policy(force_reload := false) -> Dictionary:
	if force_reload or _cached_policy.is_empty():
		_cached_policy = _load_policy()
	return _cached_policy.duplicate(true)


static func policy_version(policy_override := {}) -> String:
	return str(_policy(policy_override).get("policyVersion", "invalid"))


static func adjusted_database_price(price_record: Dictionary, policy_override := {}) -> int:
	if maxi(0, int(price_record.get("base_price", 0))) <= 0:
		return 0
	return _adjusted_database_price_resolved(price_record, _policy(policy_override))


static func _adjusted_database_price_resolved(
	price_record: Dictionary, active: Dictionary
) -> int:
	var base_price := maxi(0, int(price_record.get("base_price", 0)))
	if base_price <= 0:
		return 0
	var modifiers: Dictionary = active.get("modifiers", {})
	var value := _apply_bps(base_price, int(modifiers.get("globalBps", BPS_DENOMINATOR)))
	var category := str(price_record.get("category", ""))
	value = _apply_bps(value, int((modifiers.get("categoryBps", {}) as Dictionary).get(category, BPS_DENOMINATOR)))
	var item_bps: Dictionary = modifiers.get("itemBps", {})
	var item_key := str(price_record.get("item_key", ""))
	var item_name := str(price_record.get("item_name", ""))
	value = _apply_bps(value, int(item_bps.get(item_key, item_bps.get(item_name, BPS_DENOMINATOR))))
	return maxi(0, value)


static func merchant_accepts_service_type(
	context: Dictionary, price_record: Dictionary
) -> bool:
	var merchant_id := str(context.get("merchant_id", ""))
	if merchant_id.is_empty():
		return true
	var service_type := int(price_record.get("service_type", -1))
	if service_type < 0:
		return false
	var raw_types: Variant = context.get("types", [])
	if not raw_types is Array:
		return false
	for raw_type: Variant in raw_types:
		if int(raw_type) == service_type:
			return true
	return false


static func merchant_accepts_sell_item(
	context: Dictionary, price_record: Dictionary, policy_override := {}
) -> bool:
	return _merchant_accepts_sell_item_resolved(
		context, price_record, _policy(policy_override)
	)


static func _merchant_accepts_sell_item_resolved(
	context: Dictionary, price_record: Dictionary, active: Dictionary
) -> bool:
	var sell_policy: Dictionary = active.get("sell", {})
	if str(sell_policy.get("merchantTypeGate", "source_types")) == "all_shop_merchants":
		# PlayerState still reconstructs and validates merchant_id at the
		# authority boundary.  This override only removes the source [Types]
		# category restriction from player-to-NPC selling; repair keeps it.
		return true
	return merchant_accepts_service_type(context, price_record)


static func merchant_supports_full_equipment_repair(
	context: Dictionary, policy_override := {}
) -> bool:
	if not bool(context.get("supports_repair", false)):
		return false
	var merchant_id := str(context.get("merchant_id", ""))
	if merchant_id.is_empty():
		return false
	var active := _policy(policy_override)
	var repair_policy: Dictionary = active.get("repair", {})
	var authorized_ids: Variant = repair_policy.get("authorizedFullEquipmentMerchantIds", [])
	if not authorized_ids is Array:
		return false
	for authorized_id: Variant in authorized_ids:
		if str(authorized_id) == merchant_id:
			return true
	return false


static func repair_batch_slot_order(policy_override := {}) -> Array[String]:
	var active := _policy(policy_override)
	var repair_policy: Dictionary = active.get("repair", {})
	var raw_slots: Variant = repair_policy.get("batchPrioritySlots", [])
	var slots: Array[String] = []
	if not raw_slots is Array:
		return slots
	for raw_slot: Variant in raw_slots:
		var slot := str(raw_slot)
		if slot.is_empty() or slot in slots:
			return []
		slots.append(slot)
	return slots


static func quote_buy(
	price_record: Dictionary,
	quantity := 1,
	context := {},
	policy_override := {}
) -> Dictionary:
	return _quote_buy_resolved(
		price_record, quantity, context, _policy(policy_override)
	)


static func quote_sell(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	quantity := 1,
	context := {},
	policy_override := {}
) -> Dictionary:
	var active := _policy(policy_override)
	var rejection := _quote_base("sell", price_record, quantity, active)
	var sell_policy: Dictionary = active.get("sell", {})
	if quantity <= 0:
		rejection["reason"] = "出售数量无效。"
		return rejection
	if not _merchant_accepts_sell_item_resolved(context, price_record, active):
		rejection["reason"] = "该商人不回收此类物品。"
		return rejection
	if str(price_record.get("kind", "unknown")) in sell_policy.get("nonTradableKinds", []):
		rejection["reason"] = "该物品不能出售。"
		return rejection
	if bool(sell_policy.get("rejectBoundItems", true)) and (
		bool(instance.get("bound", false)) or bool(instance.get("bind", false))
	):
		rejection["reason"] = "绑定物品不能出售。"
		return rejection
	var buy_basis := _quote_buy_resolved(price_record, 1, context, active)
	if not bool(buy_basis.get("valid", false)):
		rejection["reason"] = str(buy_basis.get("reason", "该物品无法估值。"))
		return rejection
	var instance_value := _instance_value(int(buy_basis.get("unit_price", 0)), catalog, instance)
	var sell_rate_bps := int(sell_policy.get("rateBps", 5000))
	var unit_price := _apply_bps(instance_value, sell_rate_bps)
	if instance_value > 0:
		unit_price = maxi(int(sell_policy.get("minimumPositivePrice", 1)), unit_price)
	return _complete_quote(rejection, unit_price, quantity, {
		"database_price": int(price_record.get("base_price", 0)),
		"merchant_unit_price": int(buy_basis.get("unit_price", 0)),
		"instance_value": instance_value,
		"sell_rate_bps": sell_rate_bps,
		"durability": int(instance.get("durability", instance.get("max_durability", 0))),
		"maximum_durability": int(instance.get("max_durability", catalog.get("maxDurability", 0))),
	})


static func _quote_buy_resolved(
	price_record: Dictionary,
	quantity: int,
	context: Dictionary,
	active: Dictionary,
) -> Dictionary:
	var rejection := _quote_base("buy", price_record, quantity, active)
	if quantity <= 0:
		rejection["reason"] = "购买数量无效。"
		return rejection
	var adjusted := _adjusted_database_price_resolved(price_record, active)
	if adjusted <= 0:
		rejection["reason"] = "该物品没有有效的主数据库价格。"
		return rejection
	var merchant: Dictionary = active.get("merchant", {})
	var markup_bps := int(context.get("stock_markup_bps", merchant.get("stockMarkupBps", 11000)))
	var merchant_rate_bps := int(context.get("merchant_rate_bps", merchant.get("defaultPriceRateBps", BPS_DENOMINATOR)))
	var unit_price := _apply_bps(_apply_bps(adjusted, markup_bps), merchant_rate_bps)
	if unit_price <= 0:
		rejection["reason"] = "商人物价倍率无效。"
		return rejection
	return _complete_quote(rejection, unit_price, quantity, {
		"database_price": int(price_record.get("base_price", 0)),
		"adjusted_database_price": adjusted,
		"stock_markup_bps": markup_bps,
		"merchant_rate_bps": merchant_rate_bps,
		"merchant_id": str(context.get("merchant_id", "")),
	})


static func quote_repair(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	context := {},
	policy_override := {}
) -> Dictionary:
	var active := _policy(policy_override)
	if instance.has("durability_raw") or instance.has("max_durability_raw"):
		var maximum_raw := maxi(1, int(instance.get(
			"max_durability_raw",
			maxi(1, int(instance.get("max_durability", catalog.get("maxDurability", 1)))) * 1000
		)))
		var current_raw := clampi(int(instance.get("durability_raw", maximum_raw)), 0, maximum_raw)
		return quote_repair_raw_delta(
			price_record, catalog, instance, maximum_raw - current_raw, context, active
		)
	var current := int(instance.get("durability", 0))
	var maximum := maxi(1, int(instance.get("max_durability", catalog.get("maxDurability", 1))))
	var missing := maximum - clampi(current, 0, maximum)
	return quote_repair_delta(price_record, catalog, instance, missing, context, active)


static func quote_repair_delta(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	repair_amount: int,
	context := {},
	policy_override := {}
) -> Dictionary:
	var maximum := maxi(1, int(instance.get("max_durability", catalog.get("maxDurability", 1))))
	var current := clampi(int(instance.get("durability", 0)), 0, maximum)
	var missing := maximum - current
	if missing <= 0:
		var active := _policy(policy_override)
		return _complete_quote(
			_quote_base("repair", price_record, 1, active), 0, 1,
			{"missing_durability": 0, "missing_durability_raw": 0}
		)
	var applied_amount := clampi(repair_amount, 0, missing)
	return quote_repair_raw_delta(
		price_record,
		catalog,
		instance,
		applied_amount * 1000,
		context,
		policy_override,
		current * 1000,
		maximum * 1000
	)


static func quote_repair_raw_delta(
	price_record: Dictionary,
	catalog: Dictionary,
	instance: Dictionary,
	repair_amount_raw: int,
	context := {},
	policy_override := {},
	current_raw_override := -1,
	maximum_raw_override := -1
) -> Dictionary:
	var active := _policy(policy_override)
	var result := _quote_base("repair", price_record, 1, active)
	if not bool(context.get("supports_repair", true)):
		result["reason"] = "该商人不提供维修服务。"
		return result
	var merchant_id := str(context.get("merchant_id", ""))
	if not merchant_id.is_empty() and not merchant_supports_full_equipment_repair(context, active):
		result["reason"] = "该商人不提供全装备维修服务。"
		return result
	var repair_policy: Dictionary = active.get("repair", {})
	var display_maximum := maxi(1, int(instance.get("max_durability", catalog.get("maxDurability", 1))))
	var maximum_raw := (
		maximum_raw_override
		if maximum_raw_override > 0
		else maxi(1, int(instance.get("max_durability_raw", display_maximum * 1000)))
	)
	var current_raw := (
		current_raw_override
		if current_raw_override >= 0
		else int(instance.get("durability_raw", int(instance.get("durability", 0)) * 1000))
	)
	current_raw = clampi(current_raw, 0, maximum_raw)
	var missing_raw := maximum_raw - current_raw
	if missing_raw <= 0:
		return _complete_quote(result, 0, 1, {
			"missing_durability": 0,
			"missing_durability_raw": 0,
		})
	var applied_raw := clampi(repair_amount_raw, 0, missing_raw)
	if applied_raw <= 0:
		result["reason"] = "修复量无效。"
		return result
	var buy_basis := quote_buy(price_record, 1, context, active)
	if not bool(buy_basis.get("valid", false)):
		result["reason"] = str(buy_basis.get("reason", "该物品无法估值。"))
		return result
	var user_item_price := _instance_value(int(buy_basis.get("unit_price", 0)), catalog, instance)
	var divisor := maxi(1, int((active.get("repair", {}) as Dictionary).get("priceDivisor", 3)))
	var one_third := int(user_item_price / divisor)
	var cost := _round_half_up_ratio(one_third, applied_raw, maximum_raw)
	cost = maxi(1, cost)
	return _complete_quote(result, cost, 1, {
		"repair_contract_id": str(repair_policy.get("contractId", "")),
		"repair_scope": "all_equipped_repairable_items",
		"merchant_id": merchant_id,
		"instance_value": user_item_price,
		"price_divisor": divisor,
		"missing_durability": int(ceil(float(missing_raw) / 1000.0)),
		"missing_durability_raw": missing_raw,
		"repair_amount": int(ceil(float(applied_raw) / 1000.0)),
		"repair_amount_raw": applied_raw,
		"target_durability": int(ceil(float(current_raw + applied_raw) / 1000.0)),
		"target_durability_raw": current_raw + applied_raw,
		"maximum_durability": int(ceil(float(maximum_raw) / 1000.0)),
		"maximum_durability_raw": maximum_raw,
		"preserve_maximum_durability": bool((active.get("repair", {}) as Dictionary).get("preserveMaximumDurability", true)),
	})


static func estimate_forge_materials(
	materials: Array,
	price_records: Dictionary,
	policy_override := {}
) -> Dictionary:
	var active := _policy(policy_override)
	var total := 0
	var lines: Array = []
	for raw_material: Variant in materials:
		if not raw_material is Dictionary:
			return {"valid": false, "reason": "锻造材料格式无效。", "total_value": 0}
		var material: Dictionary = raw_material
		var item_name := str(material.get("item_name", ""))
		var quantity := int(material.get("quantity", 0))
		var record: Dictionary = price_records.get(item_name, {})
		var unit_value := adjusted_database_price(record, active)
		if quantity <= 0 or unit_value <= 0:
			return {"valid": false, "reason": "锻造材料缺少有效价格：%s" % item_name, "total_value": 0}
		total += unit_value * quantity
		lines.append({"item_name": item_name, "quantity": quantity, "unit_value": unit_value})
	return {
		"valid": true,
		"contract_id": CONTRACT_ID,
		"policy_version": str(active.get("policyVersion", "")),
		"policy_hash": _policy_hash(active),
		"valuation_only": true,
		"materials": lines,
		"total_value": total,
	}


static func _instance_value(base_value: int, catalog: Dictionary, instance: Dictionary) -> int:
	if base_value <= 0:
		return 0
	if str(catalog.get("kind", "")) != "equipment" and not instance.has("max_durability"):
		return base_value
	var catalog_maximum := maxi(1, int(catalog.get("maxDurability", instance.get("max_durability", 1))))
	var uses_raw := instance.has("durability_raw") or instance.has("max_durability_raw")
	var unit_scale := 1000 if uses_raw else 1
	var catalog_maximum_units := catalog_maximum * unit_scale
	var instance_maximum := maxi(
		1,
		int(instance.get(
			"max_durability_raw" if uses_raw else "max_durability",
			catalog_maximum_units
		))
	)
	var current := clampi(
		int(instance.get(
			"durability_raw" if uses_raw else "durability",
			instance_maximum
		)),
		0,
		instance_maximum
	)
	var value := _round_half_up_ratio(
		base_value, instance_maximum, catalog_maximum_units
	)
	var service_bonus_points := maxi(0, int(instance.get("service_bonus_points", 0)))
	if service_bonus_points > 0:
		value = int(value / 5) * service_bonus_points
	var missing := instance_maximum - current
	var loss := _round_half_up_ratio(value, missing, instance_maximum * 2)
	return maxi(2, value - loss)


static func _quote_base(action: String, price_record: Dictionary, quantity: int, active: Dictionary) -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"policy_version": str(active.get("policyVersion", "invalid")),
		"policy_hash": _policy_hash(active),
		"action": action,
		"item_key": str(price_record.get("item_key", "")),
		"item_name": str(price_record.get("item_name", "")),
		"quantity": quantity,
		"currency_id": str(active.get("currencyId", "gold")),
		"valid": false,
		"unit_price": 0,
		"total_price": 0,
		"reason": "该物品没有有效的主数据库价格。",
		"formula_snapshot": {},
		"source": price_record.get("source", {}).duplicate(true),
	}


static func _complete_quote(result: Dictionary, unit_price: int, quantity: int, formula: Dictionary) -> Dictionary:
	result["valid"] = true
	result["unit_price"] = maxi(0, unit_price)
	result["total_price"] = maxi(0, unit_price) * quantity
	result["reason"] = ""
	result["formula_snapshot"] = formula
	return result


static func _apply_bps(value: int, bps: int) -> int:
	return _round_half_up_ratio(value, maxi(0, bps), BPS_DENOMINATOR)


static func _round_half_up_ratio(value: int, numerator: int, denominator: int) -> int:
	if denominator <= 0 or value <= 0 or numerator <= 0:
		return 0
	return int((value * numerator + int(denominator / 2)) / denominator)


static func _policy(policy_override: Variant) -> Dictionary:
	if policy_override is Dictionary and not (policy_override as Dictionary).is_empty():
		return (policy_override as Dictionary).duplicate(true)
	return policy()


static func _load_policy() -> Dictionary:
	if not FileAccess.file_exists(POLICY_PATH):
		push_error("正式价格策略不存在：%s" % POLICY_PATH)
		return {}
	var policy_text := FileAccess.get_file_as_string(POLICY_PATH)
	var parsed: Variant = JSON.parse_string(policy_text)
	if not parsed is Dictionary or str(parsed.get("contractId", "")) != CONTRACT_ID:
		push_error("正式价格策略无效：%s" % POLICY_PATH)
		return {}
	_cached_policy_hash = policy_text.sha256_text()
	return (parsed as Dictionary).duplicate(true)


static func _policy_hash(active: Dictionary) -> String:
	if not _cached_policy_hash.is_empty() and active == _cached_policy:
		return _cached_policy_hash
	return JSON.stringify(active).sha256_text()
