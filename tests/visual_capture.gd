extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for item_name in ["木剑", "布衣", "金创药(小量)", "裁决之杖"]:
		PlayerState.add_item(item_name)
	PlayerState.equip_inventory_index(0)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud._toggle_inventory()

