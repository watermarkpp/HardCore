extends Node

const PROFILE_PHYSICAL := Vector2(2664, 1200)
const PROFILE_SAFE_LEFT_PX := 121.0
const PROFILE_SAFE_RIGHT_PX := 129.0

func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.inventory = []
	PlayerState.add_item("强效太阳水", 82)
	PlayerState.add_item("魔法药(中量)", 94)
	PlayerState.add_item("金创药(小量)", 25)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	var viewport := get_viewport()
	var logical := viewport.get_visible_rect().size
	var hud: Node = game.get("hud") as Node
	assert(hud != null, "formal main scene did not create GameHUD")
	var safe_left := PROFILE_SAFE_LEFT_PX / PROFILE_PHYSICAL.x * logical.x
	var safe_right := PROFILE_SAFE_RIGHT_PX / PROFILE_PHYSICAL.x * logical.x
	var safe_root := hud.get_node_or_null("MobileSafeRoot") as Control
	assert(safe_root != null, "formal main scene HUD is missing MobileSafeRoot")
	safe_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	safe_root.position = Vector2(safe_left, 0.0)
	safe_root.size = logical - Vector2(safe_left + safe_right, 0.0)
	hud.call("open_shop", "比奇武器店", [])
	await get_tree().process_frame
	await get_tree().process_frame
	var shop: Node = hud.get("shop_panel") as Node
	assert(shop != null and shop.visible, "formal HUD did not open ShopPanel")
	var quote_items: Array = []
	for index in range(PlayerState.inventory.size()):
		var record: Dictionary = PlayerState.inventory[index]
		quote_items.append({
			"quote_key": shop.call("sell_quote_key", index, record),
			"inventory_index": index,
			"instance_id": str(record.get("instance_id", "")),
			"item_name": str(record.get("name", "")),
			"count": int(record.get("count", 1)),
		})
	shop.call("set_sell_quotes", PlayerState.shop_sell_quotes(quote_items))
	shop.get("sell_tab_button").pressed.emit()
	await get_tree().process_frame
	shop.call("_select_sell_item", 0)
	shop.call("_change_sell_quantity", 2)
	shop.call("_select_sell_item", 1)
	shop.call("_change_sell_quantity", 4)
	await get_tree().process_frame
	var image := viewport.get_texture().get_image()
	var output_dir := ProjectSettings.globalize_path("res://outputs/android_device")
	DirAccess.make_dir_recursive_absolute(output_dir)
	var output_path := output_dir.path_join("local_main_shop_sell_device_profile.png")
	assert(image.save_png(output_path) == OK, "unable to save formal shop sell capture")
	var selected := shop.get("_selected_sell_indices") as Dictionary
	var quantities := shop.get("_sell_quantities") as Dictionary
	var geometry := {
		"profile": "HardCore.android.device_ui.v1",
		"source": "res://scenes/main.tscn",
		"mode": "sell",
		"physical_size": [int(PROFILE_PHYSICAL.x), int(PROFILE_PHYSICAL.y)],
		"logical_viewport": [logical.x, logical.y],
		"safe_pixels": {"left": PROFILE_SAFE_LEFT_PX, "right": PROFILE_SAFE_RIGHT_PX, "top": 0.0, "bottom": 0.0},
		"safe_logical": {"left": safe_left, "right": safe_right},
		"safe_root_rect": [safe_root.position.x, safe_root.position.y, safe_root.size.x, safe_root.size.y],
		"selected_indices": selected.keys(),
		"quantities": quantities,
		"capture": output_path,
	}
	var geometry_path := output_dir.path_join("local_main_shop_sell_device_profile.json")
	FileAccess.open(geometry_path, FileAccess.WRITE).store_string(JSON.stringify(geometry, "  "))
	print("FORMAL_MAIN_SHOP_SELL_DEVICE_PROFILE_PASS capture=%s geometry=%s selected=%s quantities=%s" % [output_path, geometry_path, selected.keys(), quantities])
	get_tree().quit(0)
