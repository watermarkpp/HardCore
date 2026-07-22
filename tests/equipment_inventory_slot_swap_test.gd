extends Node


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()

	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "初始武器穿戴失败")
	var old_weapon: Dictionary = PlayerState.equipment["武器"]
	old_weapon["durability"] = 1
	var old_weapon_id := str(old_weapon.get("instance_id", ""))
	assert(not old_weapon_id.is_empty(), "初始武器缺少稳定实例ID")

	PlayerState.add_item("金创药(小量)", 2)
	PlayerState.add_item("匕首")
	PlayerState.add_item("回城卷", 2)
	var replacement_index := _inventory_index("匕首")
	assert(replacement_index == 1, "测试替换武器没有位于背包中间格")
	var replacement_id := str(PlayerState.inventory[replacement_index].get("instance_id", ""))
	var inventory_before: Array = PlayerState.inventory.duplicate(true)
	var size_before := PlayerState.inventory.size()

	assert(PlayerState.equip_inventory_index(replacement_index).begins_with("已装备"), "中间格武器替换失败")
	assert(PlayerState.inventory.size() == size_before, "替换装备改变了背包格数")
	assert(str(PlayerState.equipment["武器"].get("instance_id", "")) == replacement_id, "新武器没有进入装备槽")
	assert(str(PlayerState.inventory[replacement_index].get("instance_id", "")) == old_weapon_id, "旧武器没有直接回填新武器原背包格")
	assert(int(PlayerState.inventory[replacement_index].get("durability", 0)) == 1, "旧武器回填时丢失实例耐久")
	for index in range(PlayerState.inventory.size()):
		if index == replacement_index:
			continue
		assert(JSON.stringify(PlayerState.inventory[index]) == JSON.stringify(inventory_before[index]), "替换装备改动了无关背包格%d" % index)

	print("EQUIPMENT_INVENTORY_SLOT_SWAP_PASS：换装按原背包格互换，其他格位及实例状态不变")
	get_tree().quit(0)
