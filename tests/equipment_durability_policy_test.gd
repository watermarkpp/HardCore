extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")


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

	var item := GameData.get_item("木剑")
	var expected_cost := EquipmentRulesScript.repair_cost(item, 0, maximum)
	assert(expected_cost > 0 and PlayerState.repair_cost() == expected_cost, "服务端比例维修价格没有接入")
	PlayerState.gold = expected_cost - 1
	assert(PlayerState.repair_all_equipment() == "维修需要%d金币" % expected_cost, "金币不足时维修结果错误")
	assert(int(weapon.get("durability", -1)) == 0 and int(weapon.get("max_durability", -1)) == maximum, "维修失败却改变了耐久")

	PlayerState.gold = expected_cost
	assert(PlayerState.repair_all_equipment().begins_with("全部装备维修完成"), "唯一维修功能执行失败")
	assert(PlayerState.gold == 0, "维修扣费错误")
	assert(int(weapon.get("durability", -1)) == maximum and int(weapon.get("max_durability", -1)) == maximum, "维修没有恢复原最大耐久")
	assert(str(weapon.get("instance_id", "")) == instance_id, "维修改变了装备实例")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == attack_with_weapon, "维修后装备属性没有恢复")

	var shop := ShopPanel.new()
	add_child(shop)
	await get_tree().process_frame
	assert(shop.repair_button.text == "装备无需维修", "商店维修按钮初始预览错误")
	PlayerState.damage_equipment_durability("武器", 1)
	assert("金币" in shop.repair_button.text and str(PlayerState.repair_cost()) in shop.repair_button.text, "商店没有显示唯一维修价格预览")

	print("EQUIPMENT_DURABILITY_POLICY_PASS：零耐久保留且零属性、唯一维修、价格预览和原最大耐久恢复正常")
	get_tree().quit(0)
