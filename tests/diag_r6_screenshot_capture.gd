extends Node

## R6.1 real-panel screenshot capture fixture (diagnostic, untracked).
## One panel per shot, real rendering, seeded selections so the docked detail
## window and rarity name colors are visible. Saves PNGs under R6_SHOT_DIR.

var shot_dir := ""

func _ready() -> void:
	PlayerState.test_mode = true
	_run.call_deferred()

func _snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := shot_dir + "/" + name + ".png"
	image.save_png(path)
	print("R6_SHOT saved=", name, " size=", image.get_size())

func _clear(node: Node) -> void:
	remove_child(node)
	node.queue_free()
	await get_tree().process_frame

func _run() -> void:
	if not GameData.ensure_loaded():
		push_error("R6_SHOT data not loaded")
		get_tree().quit(1)
		return
	shot_dir = OS.get_environment("R6_SHOT_DIR")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(shot_dir))
	# Seed bag items spanning rarity tiers (Woma bright gold + Zuma dark gold).
	var seeded: Array[String] = []
	for item_name: String in ["幽灵项链", "生命项链", "绿色项链", "恶魔铃铛", "木剑", "铁剑"]:
		var result := PlayerState.add_item(item_name, 1)
		if bool(result.get("success", false)):
			seeded.append(item_name)
	print("R6_SHOT seeded=", seeded)
	# 1) Inventory with a selected Woma item -> docked detail + rarity color.
	var InventoryScript := load("res://scripts/inventory_panel.gd")
	var inventory: Panel = InventoryScript.new()
	add_child(inventory)
	await get_tree().process_frame
	await get_tree().process_frame
	inventory.call("_select_inventory_item", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("01_inventory_docked_detail_woma")
	await _clear(inventory)
	# 2) Shop buy mode with named stock + selected row -> detail beside buttons.
	var ShopScript := load("res://scripts/shop_panel.gd")
	var shop: Panel = ShopScript.new()
	add_child(shop)
	await get_tree().process_frame
	var stock: Array = []
	for item_name: String in ["幽灵项链", "生命项链", "绿色项链", "木剑"]:
		stock.append({"name": item_name, "item_id": item_name, "count": 1})
	shop.call("open_for", "比奇省商人", stock, {"mode": "sell"})
	await get_tree().process_frame
	shop.call("_on_item_selected", 0)
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("02_shop_buy_detail")
	await _clear(shop)
	# 3) System menu settings page (audio rows with short sliders).
	var MenuScript := load("res://scripts/system_menu_panel.gd")
	var menu: Control = MenuScript.new()
	add_child(menu)
	await get_tree().process_frame
	menu.call("open_menu")
	await get_tree().process_frame
	await _snap("03_system_menu_main")
	menu.call("show_settings_page")
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("04_system_menu_settings_audio")
	await _clear(menu)
	# 4) Warehouse panel.
	var WarehouseScript := load("res://scripts/warehouse_panel.gd")
	var warehouse: Panel = WarehouseScript.new()
	add_child(warehouse)
	await get_tree().process_frame
	if warehouse.has_method("open_panel"):
		warehouse.call("open_panel")
	await get_tree().process_frame
	await get_tree().process_frame
	await _snap("05_warehouse_real")
	print("R6_SHOT_DONE dir=", shot_dir)
	get_tree().quit(0)
