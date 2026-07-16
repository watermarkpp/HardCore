extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 35
	PlayerState.add_gold(1800)
	PlayerState.add_item("木剑")
	PlayerState.equip_inventory_index(0)
	var weapon: Dictionary = PlayerState.equipment["武器"]
	weapon["durability"] = maxi(1, int(weapon.get("max_durability", 2)) - 2)
	PlayerState.add_item("金创药(小量)", 5)
	PlayerState.add_item("基本剑术")
	PlayerState.add_item("回城卷", 2)
	PlayerState.add_item("沃玛号角")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud._toggle_inventory()
	game.hud.inventory_panel.item_list.select(1)
	game.hud.inventory_panel._on_item_selected(1)
