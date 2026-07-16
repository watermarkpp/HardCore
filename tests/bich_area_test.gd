extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for map_id in [4, 217, 218, 221]:
		assert(RegionContent.has_map(map_id), "比奇区域包缺少地图%d" % map_id)
	var bich_spawn_names: Array[String] = []
	for spawn: Dictionary in RegionContent.MAPS[4]["spawns"]:
		bich_spawn_names.append(str(spawn.get("name", "")))
	assert("森林雪人" in bich_spawn_names and "食人花" in bich_spawn_names, "正式比奇刷怪表缺少森林雪人或食人花")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.travel_to_map(217)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_zone == "兽人古墓一层", "未进入兽人古墓一层")
	assert(get_tree().get_nodes_in_group("enemies").size() == 5, "一层手工怪物配置不符")
	assert(_boss_count() == 0, "一层不应刷新骷髅精灵")
	assert(get_tree().get_nodes_in_group("interactable").size() == 2, "一层双向门点不完整")

	game.travel_to_map(218)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemies").size() == 8, "二层怪物与Boss数量不符")
	assert(_boss_count() == 1, "二层应刷新一只骷髅精灵")
	var boss := _first_boss()
	assert(boss != null and float(boss.get_meta("respawn_seconds", 0.0)) == 3600.0, "骷髅精灵60分钟刷新规则失效")

	game.travel_to_map(221)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemies").size() == 8 and _boss_count() == 1, "三层高密度怪物或Boss不完整")
	PlayerState.add_item("回城卷")
	var scroll_index := PlayerState.inventory.size() - 1
	assert(PlayerState.use_inventory_index(scroll_index).begins_with("使用"), "回城卷无法使用")
	await get_tree().process_frame
	assert(game.current_zone == "比奇省" and game.current_map_id == 4, "回城卷没有返回服务端HomeMap=0对应的比奇省")

	print("BICH_AREA_PASS：比奇五怪阵容、兽人古墓三层、双层Boss、60分钟刷新、门点与回城卷正常")
	get_tree().quit(0)


func _boss_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			count += 1
	return count


func _first_boss() -> EnemyActor:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			return node
	return null
