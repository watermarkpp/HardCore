extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 22
	PlayerState.recalculate_stats()
	PlayerState.add_item("回城卷", 2)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	game.travel_to_map(218)
	await get_tree().process_frame
	await get_tree().process_frame
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			node.global_position = game.player.global_position + Vector2(230, 25)
			node.apply_control(8.0)
			break
