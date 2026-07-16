extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.level = 12
	PlayerState.recalculate_stats()
	PlayerState.add_gold(500)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.change_zone("比奇城")
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud._toggle_profession()
