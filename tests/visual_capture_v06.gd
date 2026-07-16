extends Node


func _ready() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("道士")
	PlayerState.level = 35
	PlayerState.recalculate_stats()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var target: EnemyActor
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and not node.is_boss:
			target = node
			break
	if target != null:
		target.global_position = game.player.global_position + Vector2(125, 0)
		target.apply_control(8.0)
	game.player.facing = Vector2.RIGHT
	game._on_player_skill("召唤骷髅", game.player.global_position, Vector2.RIGHT, 12)
	game._on_player_skill("施毒术", game.player.global_position, Vector2.RIGHT, 12)
	for frame in range(20):
		await get_tree().physics_frame
