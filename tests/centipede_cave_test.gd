extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in RegionContent.CENTIPEDE_MAPS.keys():
		var source: Dictionary = RegionContent.CENTIPEDE_MAPS[map_id]
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "蜈蚣洞地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == source.get("targets", []).size(), "蜈蚣洞地图%d门点数量不符" % map_id)
	game.travel_to_map(1383)
	await get_tree().process_frame
	await get_tree().process_frame
	var dragon: EnemyActor
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.display_name == "触龙神":
			dragon = node
			break
	assert(dragon != null and dragon.move_speed == 0.0 and dragon.attack_range >= 200.0, "触龙神固定远程配置失效")
	dragon.global_position = game.player.global_position + Vector2(80, 0)
	dragon._attack_timer = 0.0
	dragon._physics_process(0.1)
	assert(game.player.poison_time > 0.0, "触龙神毒素攻击未生效")
	assert(float(dragon.get_meta("respawn_seconds", 0.0)) == 7200.0, "触龙神刷新候选值失效")
	assert(not GameData.get_drops_for_boss(120).is_empty() and not GameData.get_drops_for_boss(124).is_empty(), "邪恶钳虫或触龙神Boss掉落未接入")
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() == 59, "手工地图总数应为59")
	print("CENTIPEDE_CAVE_PASS：蜈蚣洞18图、空房间、邪恶钳虫、触龙神远程毒素与Boss掉落正常")
	get_tree().quit(0)
