extends Node

const Cache := preload("res://scripts/ui_item_texture_cache.gd")
const Loot := preload("res://scripts/loot_pickup.gd")


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	PlayerState.reset_progress(false)
	var ids := [950001, 950101, 950102, 950103, 950201, 950202, 950203]
	for id in range(940010, 940021):
		ids.append(id)
	ids.append_array([81, 239]) # Old equipment must retain native pixel size.
	PlayerState.inventory = []
	for id in ids:
		var record := GameData.get_item_record({"item_id": id})
		PlayerState.inventory.append({"item_id": id, "name": str(record.name), "count": 1})
	PlayerState.warehouse_inventory = PlayerState.inventory.duplicate(true)
	var shop := ShopPanel.new()
	var bag := InventoryPanel.new()
	var bank := WarehousePanel.new()
	var bench := EnhancementPanel.new()
	for panel in [shop, bag, bank, bench]:
		add_child(panel)
	while not bag._bag_cells_ready or not bank._grid_cells_ready or not bench._bag_cells_ready:
		await get_tree().process_frame
	shop._set_trade_mode("sell")
	shop.set_sell_quotes({})
	bag.refresh()
	bank.refresh()
	assert(shop.goods_buttons.size() == ids.size())
	for index in ids.size():
		var stack: Dictionary = PlayerState.inventory[index]
		var texture := Cache.texture_for_item(stack)
		var custom := int(ids[index]) >= 950000
		var bound := 32.0 if custom else maxf(texture.get_width(), texture.get_height())
		_check_icon(shop.goods_buttons[index].get_node("ItemIcon"), bound, "sell", ids[index])
		_check_icon(bag._bag_cells[index].get_node("ItemButton/CenteredPixelIcon"), bound, "bag", ids[index])
		_check_icon(bank._bag_cells[index].get_node("ItemButton/CenteredPixelIcon"), bound, "warehouse_bag", ids[index])
		_check_icon(bank._stash_cells[index].get_node("ItemButton/CenteredPixelIcon"), bound, "warehouse", ids[index])
		if custom and int(ids[index]) != 950001:
			var slot := "圣物" if int(ids[index]) < 950200 else "徽章"
			PlayerState.equipment[slot] = stack
			bag._refresh_equipment_slots()
			_check_icon(bag.equipment_buttons[slot].get_node("CenteredPixelIcon"), bound, "equipped", ids[index])
		for mode in ["forge", "synthesis"]:
			if mode == "forge": PlayerState.forge_tray[4] = stack
			else: PlayerState.synthesis_tray[4] = stack
			bench._set_mode(mode)
			bench._refresh_forge_information()
			_check_icon(bench.forge_slots[4].get_node("CenteredPixelIcon"), bound, mode, ids[index])
		var drop := Loot.new()
		drop.setup_item_record({"item_id": ids[index], "output_item_id": ids[index],
			"item_name": stack.name, "output_record": GameData.get_item_record(stack)}, null)
		add_child(drop)
		assert(drop.icon_sprite != null)
		var ground_size: Vector2 = drop.icon_sprite.texture.get_size() * drop.icon_sprite.scale
		var ground_bound := 36.0 if custom else maxf(drop.icon_sprite.texture.get_width(), drop.icon_sprite.texture.get_height())
		assert(ground_size.x <= ground_bound + 0.01 and ground_size.y <= ground_bound + 0.01,
			"oversized ground icon %d: %s" % [ids[index], ground_size])
		print("ICON_SURFACE_ITEM id=%d ui=%s ground=%s" % [ids[index], shop.goods_buttons[index].get_node("ItemIcon").size, ground_size])
		drop.free()
	for panel in [shop, bag, bank, bench]:
		panel.queue_free()
	await get_tree().process_frame
	print("NEW_ITEM_ICON_SURFACES_PASS new_items=18 legacy_controls=2 surfaces=7")
	get_tree().quit(0)


func _check_icon(icon: TextureRect, bound: float, surface: String, id: int) -> void:
	assert(icon.texture != null and icon.visible)
	assert(icon.size.x > 0 and icon.size.y > 0)
	assert(icon.size.x <= bound + 0.01 and icon.size.y <= bound + 0.01,
		"oversized %s icon %d: %s" % [surface, id, icon.size])
