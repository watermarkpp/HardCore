extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var inventory := InventoryPanel.new()
	var skills := SkillPanel.new()
	var warehouse := WarehousePanel.new()
	var shop := ShopPanel.new()
	add_child(inventory)
	add_child(skills)
	add_child(warehouse)
	add_child(shop)
	await get_tree().process_frame
	shop._set_trade_mode("sell")
	for panel: Control in [inventory, skills, warehouse, shop]:
		panel.hide()
	var inventory_before: int = inventory._refresh_execution_count
	var skills_before: int = skills._refresh_execution_count
	var warehouse_before: int = warehouse._refresh_execution_count
	var shop_before: int = shop._inventory_refresh_execution_count
	PlayerState.inventory_changed.emit()
	assert(inventory._refresh_execution_count == inventory_before)
	assert(skills._refresh_execution_count == skills_before)
	assert(warehouse._refresh_execution_count == warehouse_before)
	assert(shop._inventory_refresh_execution_count == shop_before)
	assert(inventory._refresh_pending and skills._refresh_pending)
	assert(warehouse._refresh_pending and shop._inventory_refresh_pending)
	inventory.show()
	skills.show()
	warehouse.show()
	shop.show()
	assert(inventory._refresh_execution_count == inventory_before + 1)
	assert(skills._refresh_execution_count == skills_before + 1)
	assert(warehouse._refresh_execution_count == warehouse_before + 1)
	assert(shop._inventory_refresh_execution_count == shop_before + 1)
	assert(not inventory._refresh_pending and not skills._refresh_pending)
	assert(not warehouse._refresh_pending and not shop._inventory_refresh_pending)
	var visible_inventory_before := inventory._refresh_execution_count
	var visible_skills_before := skills._refresh_execution_count
	var visible_warehouse_before := warehouse._refresh_execution_count
	var visible_shop_before := shop._inventory_refresh_execution_count
	for _burst_index in range(4):
		PlayerState.inventory_changed.emit()
	assert(inventory._refresh_execution_count == visible_inventory_before, "背包信号 burst 在同帧重复刷新")
	assert(skills._refresh_execution_count == visible_skills_before, "技能面板信号 burst 在同帧重复刷新")
	assert(warehouse._refresh_execution_count == visible_warehouse_before, "仓库信号 burst 在同帧重复刷新")
	assert(shop._inventory_refresh_execution_count == visible_shop_before, "商店信号 burst 在同帧重复刷新")
	await get_tree().process_frame
	assert(inventory._refresh_execution_count == visible_inventory_before + 1, "背包信号 burst 未合并为一次刷新")
	assert(skills._refresh_execution_count == visible_skills_before + 1, "技能面板信号 burst 未合并为一次刷新")
	assert(warehouse._refresh_execution_count == visible_warehouse_before + 1, "仓库信号 burst 未合并为一次刷新")
	assert(shop._inventory_refresh_execution_count == visible_shop_before + 1, "商店信号 burst 未合并为一次刷新")
	print("HIDDEN_INVENTORY_REFRESH_PASS: hidden pickup rebuilds=0, visible refreshes=1")
	get_tree().quit(0)
