extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var expected := {
		248: Vector2i(4, 2), 249: Vector2i(4, 1), 401: Vector2i(5, 3),
		402: Vector2i(2, 2), 403: Vector2i(2, 2), 404: Vector2i(6, 4), 405: Vector2i(0, 2),
		406: Vector2i(6, 2), 407: Vector2i(2, 2), 408: Vector2i(7, 3), 409: Vector2i(2, 2),
		410: Vector2i(7, 2), 411: Vector2i(2, 2), 412: Vector2i(9, 2), 1578: Vector2i(4, 1),
	}
	for map_id: int in expected.keys():
		assert(RegionContent.has_map(map_id), "洞穴/矿区区域包缺少地图%d" % map_id)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in expected.keys():
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var target: Vector2i = expected[map_id]
		assert(get_tree().get_nodes_in_group("enemies").size() == target.x, "地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == target.y, "地图%d门点数量不符" % map_id)
	game.travel_to_map(1578)
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			boss_count += 1
			assert(float(node.get_meta("respawn_seconds", 0.0)) == 1800.0, "尸王刷新配置失效")
	assert(boss_count == 2, "尸王殿应生成两个尸王刷新位")
	assert(not GameData.get_drops_for_boss(89).is_empty(), "尸王Boss掉落没有接入3424槽")
	print("MINE_AREA_PASS：天然洞穴、401—412完整矿区链、尸王殿、僵尸掉落与双尸王正常")
	get_tree().quit(0)
