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

	var equipped_snapshot: Dictionary = PlayerState.equipment["武器"].duplicate(true)
	var rejected: Dictionary = PlayerState.unequip_to_inventory_slot("武器", replacement_index)
	assert(not rejected.success, "occupied destination must reject without replacing its item")
	var selected_slot := 25
	var moved: Dictionary = PlayerState.unequip_to_inventory_slot("武器", selected_slot)
	assert(moved.success and int(moved.destination.slot) == selected_slot)
	assert(PlayerState.inventory[selected_slot] == equipped_snapshot, "selected empty slot must receive complete instance")
	var reequipped: Dictionary = PlayerState.equip_inventory_index_result(selected_slot, "武器")
	assert(reequipped.success and str(reequipped.instance_id) == replacement_id)
	var before_failed_inventory: Array = PlayerState.inventory.duplicate(true)
	var before_failed_equipment: Dictionary = PlayerState.equipment.duplicate(true)
	var before_failed_cursor: Dictionary = PlayerState.equip_cycle_cursor.duplicate(true)
	PlayerState._test_force_atomic_write_failure = true
	var failed: Dictionary = PlayerState.unequip_to_inventory_slot("武器", selected_slot)
	PlayerState._test_force_atomic_write_failure = false
	assert(not failed.success and str(failed.reason) == "save_failed")
	assert(PlayerState.inventory == before_failed_inventory and PlayerState.equipment == before_failed_equipment)
	assert(PlayerState.equip_cycle_cursor == before_failed_cursor)
	print("EQUIPMENT_INVENTORY_SLOT_SWAP_PASS：换装、指定空格卸装、完整实例和保存失败回滚")
	get_tree().quit(0)
