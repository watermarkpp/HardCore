extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var expected := {1197: Vector2i(0, 2), 1198: Vector2i(4, 2), 1199: Vector2i(4, 3), 1200: Vector2i(6, 2), 1201: Vector2i(7, 2), 1202: Vector2i(7, 2), 1203: Vector2i(10, 4), 1232: Vector2i(6, 2), 1233: Vector2i(5, 2), 1234: Vector2i(4, 1)}
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in expected.keys():
		assert(RegionContent.has_map(map_id), "石墓区域包缺少地图%d" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var target: Vector2i = expected[map_id]
		assert(get_tree().get_nodes_in_group("enemies").size() == target.x, "石墓地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == target.y, "石墓地图%d门点数量不符" % map_id)
	assert(not GameData.get_drops_for_boss(135).is_empty(), "白野猪Boss掉落未接入")
	assert(not GameData.get_drops_for_boss(143).is_empty(), "石墓尸王Boss掉落未接入")
	game.travel_to_map(1233)
	await get_tree().process_frame
	await get_tree().process_frame
	var corpse_king_found := false
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss and node.display_name == "石墓尸王":
			corpse_king_found = float(node.get_meta("respawn_seconds", 0.0)) == 7200.0
	assert(corpse_king_found, "石墓七层尸王刷新配置失效")
	var moth := EnemyActor.new()
	moth.setup(GameData.get_monster("楔蛾"), game.player, false)
	moth.global_position = game.player.global_position
	add_child(moth)
	moth._physics_process(0.1)
	assert(game.player.control_time > 0.0, "楔蛾麻痹效果未生效")
	moth.queue_free()
	assert(RegionContent.MAPS.size() == 41, "手工地图总数应为41")
	print("STONE_TOMB_PASS：石墓入口至七层、石墓阵、桃源之门、白野猪、尸王和楔蛾麻痹正常")
	get_tree().quit(0)
