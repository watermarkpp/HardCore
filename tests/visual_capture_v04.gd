extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 7
	PlayerState.add_gold(260)
	PlayerState.add_item("金创药(小量)", 3)
	PlayerState.add_item("魔法药(小量)", 2)
	PlayerState.accept_quest("beginner_gear")
	PlayerState.record_kill("稻草人")
	PlayerState.record_kill("稻草人")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.change_zone("比奇城")
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud.open_quest("比奇老兵")

