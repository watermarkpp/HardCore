extends Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.active_profile_id = "inventory_multiselect_test"
	PlayerState.add_item("太阳水", 2)
	PlayerState.add_item("木剑", 1)
	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	var sun := _index_of("太阳水")
	var scroll := _index_of("木剑")
	assert(sun >= 0 and scroll >= 0, "fixture inventory missing")
	panel._select_inventory_item(sun)
	panel._select_inventory_item(scroll)
	assert(panel.selected_inventory_indices.size() == 2, "single clicks should toggle multi-selection")
	panel._select_inventory_item(sun)
	assert(panel.selected_inventory_indices.size() == 1 and panel.selected_inventory_indices.has(scroll), "clicking selected cell should cancel it")
	var discard_result := PlayerState.destroy_inventory_indices([scroll])
	assert(bool(discard_result.get("success", false)) and int(discard_result.get("destroyed", 0)) == 1, "batch discard should remove exactly one stack")
	assert(_index_of("木剑") < 0 and PlayerState.item_count("太阳水") == 2, "discard targeted the wrong stack")
	PlayerState.inventory.append({"name": "太阳水", "count": 3})
	PlayerState.inventory.append({"name": "太阳水", "count": 4, "custom_instance_state": true})
	PlayerState.inventory.append("opaque legacy entry")
	var sort_result := PlayerState.sort_inventory_deterministic()
	assert(bool(sort_result.get("success", false)), "deterministic sort should succeed")
	assert(PlayerState.inventory.size() == 3 and PlayerState.item_count("太阳水") == 9, "ordinary stack merge should be deterministic without merging instance state")
	assert("opaque legacy entry" in PlayerState.inventory, "sorting must preserve opaque inventory entries")
	var migrated := PlayerState.migrate_equipment_slots({"武器": {"name": "木剑"}})
	assert(migrated.has("圣物") and migrated.has("徽章") and migrated["圣物"].is_empty() and migrated["徽章"].is_empty(), "legacy saves must gain empty relic and medal slots")
	assert(panel.get_node("EquipmentPanel/EquipmentHolder_圣物/EquipmentSlot_圣物") != null, "relic stable node missing")
	assert(panel.get_node("EquipmentPanel/EquipmentHolder_徽章/EquipmentSlot_徽章") != null, "medal stable node missing")
	print("INVENTORY_MULTISELECT_DISCARD_SORT_PASS")
	get_tree().quit(0)

func _index_of(name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == name:
			return index
	return -1
