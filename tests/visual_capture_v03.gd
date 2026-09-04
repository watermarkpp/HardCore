extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 35
	PlayerState.add_gold(1200)
	for skill_name in ["基本剑术", "攻杀剑术", "半月弯刀", "烈火剑法"]:
		PlayerState.add_item(skill_name)
		PlayerState.learn_skill(skill_name)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.change_zone("比奇城")
	await get_tree().process_frame
	await get_tree().process_frame
	game.hud.open_skill_trainer("强化商人")
