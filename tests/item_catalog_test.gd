extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.item_catalog.size() >= 245, "统一物品目录数量不足")
	assert(GameData.unresolved_drop_item_names().is_empty(), "仍有掉落物无法解析")
	var counts := GameData.item_catalog_counts()
	assert(int(counts.get("equipment", 0)) == 175, "175件装备未全部进入目录")
	assert(GameData.get_item_kind("基本剑术") == "skill_book", "技能书分类错误")
	assert(GameData.get_item_kind("金币 1000") == "currency", "金币包分类错误")
	assert(GameData.get_item_kind("回城卷") == "scroll", "卷轴分类错误")
	assert(GameData.get_item_kind("沃玛号角") == "quest_item", "任务物品分类错误")

	PlayerState.add_item("金币 1000")
	assert(PlayerState.gold == 1000 and PlayerState.inventory.is_empty(), "金币掉落没有直接入账")
	PlayerState.add_item("金创药(小量)", 2)
	PlayerState.add_item("金创药(小量)", 3)
	assert(PlayerState.inventory.size() == 1 and int(PlayerState.inventory[0].get("count", 0)) == 5, "消耗品堆叠错误")
	PlayerState.add_item("木剑", 2)
	assert(PlayerState.inventory.size() == 3, "装备不应堆叠")
	var weapon_index := -1
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == "木剑":
			weapon_index = index
			break
	assert(weapon_index >= 0, "木剑实例未生成")
	var equipped_instance_id := str(PlayerState.inventory[weapon_index].get("instance_id", ""))
	assert(not equipped_instance_id.is_empty(), "木剑缺少实例身份")
	var equip_result := PlayerState.equip_inventory_index(weapon_index)
	assert(equip_result.begins_with("已装备"), "装备实例穿戴失败")
	assert(PlayerState.equipment["武器"] is Dictionary and PlayerState.equipment["武器"].get("name", "") == "木剑", "装备槽没有保存实例")
	assert(PlayerState.inventory_occupied_count() == 2, "穿戴后背包实际占用数量错误")
	assert(str(PlayerState.equipment["武器"].get("instance_id", "")) == equipped_instance_id)
	for record: Dictionary in PlayerState.inventory:
		assert(str(record.get("instance_id", "")) != equipped_instance_id, "穿戴后装备实例仍错误地留在背包")
	var weapon: Dictionary = PlayerState.equipment["武器"]
	var max_durability := int(weapon.get("max_durability", 1))
	PlayerState.damage_equipment_durability("武器", mini(2, max_durability))
	var blacksmith_context := GameData.merchant_context("starter_gear")
	var repair_cost := PlayerState.repair_cost(blacksmith_context)
	assert(repair_cost > 0, "耐久损耗没有产生维修费")
	var gold_before := PlayerState.gold
	var repair_result := PlayerState.repair_all_equipment(blacksmith_context)
	assert(repair_result.begins_with("全部装备维修完成"), "一键维修失败")
	assert(int(weapon.get("durability", 0)) == max_durability and PlayerState.gold == gold_before - repair_cost, "维修结果或扣费错误")

	print("ITEM_CATALOG_PASS：统一物品目录、3424掉落解析、堆叠、装备实例、金币和耐久维修正常")
	get_tree().quit(0)
