extends Node


func _ready() -> void:
	_run.call_deferred()


func _find_inventory_instance(instance_id: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("instance_id", "")) == instance_id:
			return index
	return -1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	assert(PlayerState.EQUIPMENT_SLOTS == ["武器", "衣服", "头盔", "项链", "左手镯", "右手镯", "左戒指", "右戒指"], "1.76八装备槽顺序错误")

	PlayerState.add_item("古铜戒指", 3)
	var first_id := str(PlayerState.inventory[0].get("instance_id", ""))
	var second_id := str(PlayerState.inventory[1].get("instance_id", ""))
	var third_id := str(PlayerState.inventory[2].get("instance_id", ""))
	var attack_before := int(PlayerState.computed_stats.get("attack_max", 0))
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(first_id)).begins_with("已装备"), "第一枚戒指穿戴失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == first_id and PlayerState.equipment["右戒指"].is_empty(), "第一枚戒指没有进入左槽")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(second_id)).begins_with("已装备"), "第二枚戒指穿戴失败")
	assert(str(PlayerState.equipment["右戒指"].get("instance_id", "")) == second_id, "第二枚戒指没有进入右槽")
	assert(int(PlayerState.computed_stats.get("attack_max", 0)) == attack_before + 2, "双戒指属性没有分别计入")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(third_id)).begins_with("已装备"), "第三枚戒指替换失败")
	assert(str(PlayerState.equipment["左戒指"].get("instance_id", "")) == third_id, "双槽已满时没有确定性替换左戒指")
	assert(_find_inventory_instance(first_id) >= 0 and str(PlayerState.equipment["右戒指"].get("instance_id", "")) == second_id, "被替换戒指或右戒指实例丢失")

	PlayerState.add_item("铁手镯", 2)
	var bracelet_a := str(PlayerState.inventory[-2].get("instance_id", ""))
	var bracelet_b := str(PlayerState.inventory[-1].get("instance_id", ""))
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_a)).begins_with("已装备"), "左手镯穿戴失败")
	assert(PlayerState.equip_inventory_index(_find_inventory_instance(bracelet_b)).begins_with("已装备"), "右手镯穿戴失败")
	assert(str(PlayerState.equipment["左手镯"].get("instance_id", "")) == bracelet_a, "左手镯槽错误")
	assert(str(PlayerState.equipment["右手镯"].get("instance_id", "")) == bracelet_b, "右手镯槽错误")

	PlayerState.equipment["左戒指"]["durability"] = 1
	PlayerState.equipment["右戒指"]["durability"] = 2
	var dual_repair_cost := PlayerState.repair_cost()
	assert(dual_repair_cost > 0, "双戒指耐久没有进入修理价格")
	PlayerState.gold = dual_repair_cost
	assert(PlayerState.repair_all_equipment().begins_with("全部装备维修完成"), "双槽装备修理失败")
	assert(PlayerState.gold == 0, "双槽修理扣费错误")

	var right_id := str(PlayerState.equipment["右戒指"].get("instance_id", ""))
	assert(PlayerState.unequip_slot("右戒指").begins_with("已卸下"), "指定右戒指槽卸下失败")
	assert(PlayerState.equipment["右戒指"].is_empty() and _find_inventory_instance(right_id) >= 0, "右戒指卸下后实例丢失")

	var legacy_bracelet := {"name": "铁手镯", "durability": 2, "max_durability": 4, "instance_id": "legacy_bracelet"}
	var legacy_ring := {"name": "古铜戒指", "durability": 3, "max_durability": 5, "instance_id": "legacy_ring"}
	var migrated := PlayerState.migrate_equipment_slots({"武器": "木剑", "手镯": legacy_bracelet, "戒指": legacy_ring})
	assert(migrated.size() == 8 and not migrated.has("手镯") and not migrated.has("戒指"), "旧存档没有迁移为八槽结构")
	assert(str(migrated["左手镯"].get("instance_id", "")) == "legacy_bracelet" and migrated["右手镯"].is_empty(), "旧手镯实例迁移错误")
	assert(str(migrated["左戒指"].get("instance_id", "")) == "legacy_ring" and migrated["右戒指"].is_empty(), "旧戒指实例迁移错误")
	assert(str(migrated["武器"].get("name", "")) == "木剑", "旧字符串装备兼容迁移失败")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert(panel.equipment_slot_picker.item_count == 8, "装备面板没有提供八槽选择")
	assert("左手镯" in panel.equipment_label.text and "右戒指" in panel.equipment_label.text, "装备面板没有显示左右槽")

	print("EQUIPMENT_SLOT_MIGRATION_PASS：双手镯、双戒指、确定性替换、属性修理、指定卸下和v02迁移正常")
	get_tree().quit(0)
