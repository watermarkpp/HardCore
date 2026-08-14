extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")
const PricingServiceScript = preload("res://scripts/pricing_service.gd")


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _run() -> void:
	var file := FileAccess.open("res://assets/data/equipment_durability_rules.json", FileAccess.READ)
	assert(file != null, "装备耐久规则来源表缺失")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary, "装备耐久规则来源表格式错误")
	assert(source.adopted.get("zeroDurability", "") == "装备保留在原槽，属性失效", "耐久归零策略错误")
	assert(not bool(source.adopted.get("specialRepair", true)), "项目仍错误保留特殊修理")
	assert(source.explicitOverrides.size() == 3, "服务端规则覆盖项没有完整记录")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "木剑穿戴失败")
	var weapon: Dictionary = PlayerState.equipment["武器"]
	var instance_id := str(weapon.get("instance_id", ""))
	var maximum := int(weapon.get("max_durability", 0))
	var attack_with_weapon := int(PlayerState.computed_stats.get("attack_max", 0))
	assert(maximum > 0 and attack_with_weapon > 5, "测试装备没有有效属性或耐久")

	PlayerState.damage_equipment_durability("武器", maximum)
	assert(not PlayerState.equipment["武器"].is_empty(), "耐久归零后装备被删除")
	assert(str(PlayerState.equipment["武器"].get("instance_id", "")) == instance_id, "耐久归零后装备实例被替换")
	assert(int(PlayerState.equipment["武器"].get("durability", -1)) == 0, "装备耐久没有归零")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == 5, "零耐久装备仍提供属性")

	var blacksmith_context := GameData.merchant_context("starter_gear")
	assert(PricingServiceScript.merchant_supports_full_equipment_repair(blacksmith_context))
	var item := GameData.get_item("木剑")
	var expected_cost := EquipmentRulesScript.repair_cost(item, 0, maximum)
	assert(expected_cost > 0 and PlayerState.repair_cost(blacksmith_context) == expected_cost, "服务端比例维修价格没有接入")
	PlayerState.gold = expected_cost - 1
	var partial_message := PlayerState.repair_all_equipment(blacksmith_context)
	assert(partial_message.begins_with("金币不足，已优先维修"), "金币不足时未执行武器优先的部分维修")
	assert(
		int(weapon.get("durability_raw", -1)) > 0
		and int(weapon.get("durability_raw", -1)) < int(weapon.get("max_durability_raw", 0)),
		"余额不足时部分维修raw量错误"
	)
	assert(PlayerState.gold >= 0 and PlayerState.gold < expected_cost - 1, "部分维修扣费错误")
	assert(int(weapon.get("max_durability", -1)) == maximum, "部分维修错误降低最大耐久")

	PlayerState.gold = PlayerState.repair_cost(blacksmith_context)
	assert(PlayerState.repair_all_equipment(blacksmith_context).begins_with("全部装备维修完成"), "唯一维修功能执行失败")
	assert(PlayerState.gold == 0, "维修扣费错误")
	assert(
		int(weapon.get("durability_raw", -1)) == int(weapon.get("max_durability_raw", 0))
		and int(weapon.get("durability", -1)) == maximum
		and int(weapon.get("max_durability", -1)) == maximum,
		"维修没有恢复原最大耐久"
	)
	assert(str(weapon.get("instance_id", "")) == instance_id, "维修改变了装备实例")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == attack_with_weapon, "维修后装备属性没有恢复")

	var shop := ShopPanel.new()
	add_child(shop)
	await get_tree().process_frame
	shop.open_for("比奇铁匠", GameData.merchant_stock("starter_gear"))
	assert(shop.repair_button.text == "装备无需维修", "商店维修按钮初始预览错误")
	PlayerState.damage_equipment_durability("武器", 1)
	assert("金币" in shop.repair_button.text and str(PlayerState.repair_cost(blacksmith_context)) in shop.repair_button.text, "商店没有显示唯一维修价格预览")

	_verify_batch_all_equipment_contract(blacksmith_context)

	print("EQUIPMENT_DURABILITY_POLICY_PASS：零耐久保留且零属性、唯一维修、价格预览和原最大耐久恢复正常")
	get_tree().quit(0)


func _verify_batch_all_equipment_contract(blacksmith_context: Dictionary) -> void:
	var expected_priority := ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指", "圣物", "徽章"]
	assert(PricingServiceScript.repair_batch_slot_order() == expected_priority)
	assert(str(PricingServiceScript.policy().get("repair", {}).get("contractId", "")) == "gameplay.repair.batch_all_equipment.v1")

	# Full repair: every occupied classic equipment slot is quoted in stable slot
	# order. A full-durability necklace is deliberately skipped.
	_install_batch_fixture(false, "项链")
	var necklace_before: Dictionary = PlayerState.equipment["项链"].duplicate(true)
	var plan := PlayerState._repair_plan(blacksmith_context)
	assert(PlayerState.equipment["项链"] == necklace_before, "维修预览不得改写装备实例")
	var expected_quoted_slots := ["武器", "衣服", "头盔", "左手镯", "右手镯", "左戒指", "右戒指"]
	assert(bool(plan.get("valid", false)) and plan.get("slots", []) == expected_quoted_slots)
	var entries: Array = plan.get("entries", [])
	assert(entries.size() == expected_quoted_slots.size())
	var summed_quote_cost := 0
	for index in range(entries.size()):
		var entry: Dictionary = entries[index]
		var quote: Dictionary = entry.get("quote", {})
		assert(str(entry.get("slot", "")) == expected_quoted_slots[index])
		assert(bool(quote.get("valid", false)))
		assert(str(quote.get("formula_snapshot", {}).get("repair_contract_id", "")) == "gameplay.repair.batch_all_equipment.v1")
		summed_quote_cost += int(quote.get("total_price", 0))
	assert(summed_quote_cost > 0 and PlayerState.repair_cost(blacksmith_context) == summed_quote_cost)
	PlayerState.gold = summed_quote_cost + 37
	var full_result := PlayerState.repair_all_equipment(blacksmith_context)
	assert(full_result.begins_with("全部装备维修完成"))
	assert(PlayerState.gold == 37, "全修没有精确扣除逐槽报价总和")
	for slot: String in expected_quoted_slots:
		var equipped: Dictionary = PlayerState.equipment[slot]
		assert(int(equipped.get("durability_raw", -1)) == int(equipped.get("max_durability_raw", 0)), "%s没有修满" % slot)
	assert(PlayerState.equipment["项链"] == necklace_before, "满耐久装备不应进入报价或被改写")

	# Insufficient gold: fully repair the weapon first, then spend the exact
	# remainder on the largest affordable raw delta of the clothing slot.
	_install_batch_fixture(true)
	var partial_plan := PlayerState._repair_plan(blacksmith_context)
	assert(partial_plan.get("slots", []).slice(0, 4) == ["武器", "衣服", "头盔", "项链"])
	var partial_entries: Array = partial_plan.get("entries", [])
	var weapon_entry: Dictionary = partial_entries[0]
	var weapon_quote: Dictionary = weapon_entry.get("quote", {})
	var weapon_full_cost := int(weapon_quote.get("total_price", 0))
	var raw_before := _raw_durability_snapshot()
	PlayerState.gold = weapon_full_cost + 1
	var gold_before := PlayerState.gold
	var partial_result := PlayerState.repair_all_equipment(blacksmith_context)
	assert(partial_result.begins_with("金币不足，已优先维修"))
	assert(int(PlayerState.equipment["武器"].get("durability_raw", 0)) == int(PlayerState.equipment["武器"].get("max_durability_raw", 0)), "金币不足时没有优先修满武器")
	assert(int(PlayerState.equipment["衣服"].get("durability_raw", 0)) > int(raw_before.get("衣服", 0)), "武器后没有按稳定顺序部分维修衣服")
	for untouched_slot: String in ["头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"]:
		assert(int(PlayerState.equipment[untouched_slot].get("durability_raw", 0)) == int(raw_before.get(untouched_slot, -1)), "余额耗尽后仍越序维修%s" % untouched_slot)
	var clothing_delta := int(PlayerState.equipment["衣服"].get("durability_raw", 0)) - int(raw_before.get("衣服", 0))
	var clothing_before: Dictionary = PlayerState.equipment["衣服"].duplicate(true)
	clothing_before["durability_raw"] = int(raw_before.get("衣服", 0))
	var clothing_quote := PricingServiceScript.quote_repair_raw_delta(
		GameData.get_item_price_record("布衣(男)"),
		GameData.get_item_record("布衣(男)"),
		clothing_before,
		clothing_delta,
		blacksmith_context
	)
	assert(int(clothing_quote.get("total_price", 0)) == 1)
	assert(gold_before - PlayerState.gold == weapon_full_cost + int(clothing_quote.get("total_price", 0)), "部分维修扣款不等于实际逐槽修复报价")

	# One failed save rolls back every repaired slot and the complete gold debit.
	_install_batch_fixture(true)
	var rollback_equipment := PlayerState.equipment.duplicate(true)
	PlayerState.gold = PlayerState.repair_cost(blacksmith_context)
	var rollback_gold := PlayerState.gold
	PlayerState._test_force_atomic_write_failure = true
	var rollback_result := PlayerState.repair_all_equipment(blacksmith_context)
	PlayerState._test_force_atomic_write_failure = false
	assert(rollback_result.begins_with("维修存档失败"))
	assert(PlayerState.equipment == rollback_equipment and PlayerState.gold == rollback_gold, "维修保存失败没有原子回滚耐久和金币")

	# No context, grocery context, and a forged non-authoritative merchant are
	# all denied. Source [Types] no longer limits the authoritative blacksmith.
	var denied_equipment := PlayerState.equipment.duplicate(true)
	var denied_gold := PlayerState.gold
	assert(PlayerState.repair_cost() == 0 and PlayerState.repair_all_equipment().begins_with("该商人不提供维修服务"))
	var grocery_context := GameData.merchant_context("general")
	assert(PlayerState.repair_cost(grocery_context) == 0 and PlayerState.repair_all_equipment(grocery_context).begins_with("该商人不提供维修服务"))
	var forged_context := {"merchant_id": "merchant.test.forged", "supports_repair": true, "types": [1, 2, 4, 5, 6, 7]}
	assert(PlayerState.repair_cost(forged_context) == 0 and PlayerState.repair_all_equipment(forged_context).begins_with("该商人不提供维修服务"))
	assert(PlayerState.equipment == denied_equipment and PlayerState.gold == denied_gold, "非铁匠维修请求改变了状态")
	for slot: String in ["衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"]:
		var equipped: Dictionary = PlayerState.equipment[slot]
		var item_name := str(equipped.get("name", ""))
		var quote := PricingServiceScript.quote_repair(
			GameData.get_item_price_record(item_name), GameData.get_item_record(item_name), equipped, blacksmith_context
		)
		assert(bool(quote.get("valid", false)), "铁匠[Types]错误阻止维修%s" % slot)


func _install_batch_fixture(damage_every_slot: bool, full_slot := "") -> void:
	PlayerState.reset_progress(false)
	PlayerState.level = 50
	PlayerState.gender = "男"
	var item_by_slot := {
		"武器": "木剑",
		"衣服": "布衣(男)",
		"头盔": "青铜头盔",
		"项链": "金项链",
		"左手镯": "铁手镯",
		"右手镯": "铁手镯",
		"左戒指": "古铜戒指",
		"右戒指": "古铜戒指",
	}
	for slot: String in item_by_slot:
		var item_name := str(item_by_slot[slot])
		var instance: Dictionary = PlayerState._make_item_instance(item_name, GameData.get_item_record(item_name))
		assert(not instance.is_empty(), "批量维修测试装备不存在: %s" % item_name)
		instance["instance_id"] = "repair-batch:%s" % slot
		var maximum_raw := int(instance.get("max_durability_raw", 0))
		assert(maximum_raw > 0)
		instance["durability_raw"] = maximum_raw if slot == full_slot else maxi(0, int(maximum_raw / 4))
		PlayerState._sync_durability_compatibility_fields(instance)
		PlayerState.equipment[slot] = instance
	PlayerState.recalculate_stats(false)
	if not damage_every_slot and full_slot.is_empty():
		assert(false, "批量维修fixture必须指定满耐久槽或启用全槽损耗")


func _raw_durability_snapshot() -> Dictionary:
	var result := {}
	for slot: String in PlayerState.EQUIPMENT_SLOTS:
		var equipped: Variant = PlayerState.equipment.get(slot, {})
		if equipped is Dictionary and not equipped.is_empty():
			result[slot] = int(equipped.get("durability_raw", 0))
	return result
