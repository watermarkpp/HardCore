extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	# The initial world bootstrap must exercise the production frame-paced
	# threaded prefetch path.  The test-mode shortcut uses a tight polling loop
	# that can starve Godot's main thread while texture resources finalize,
	# producing transient dummy-renderer RID errors in the full suite.
	PlayerState.test_mode = false
	PlayerState.reset_progress()
	for map_id in [4, 217, 218, 221]:
		assert(RegionContent.has_map(map_id), "比奇区域包缺少地图%d" % map_id)
	var bich_spawn_names: Array[String] = []
	for spawn: Dictionary in RegionContent.MAPS[4]["spawns"]:
		bich_spawn_names.append(str(spawn.get("name", "")))
	assert("森林雪人" in bich_spawn_names and "食人花" in bich_spawn_names, "正式比奇刷怪表缺少森林雪人或食人花")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	var bootstrap_deadline := Time.get_ticks_msec() + 15000
	while (
		(game._world_bootstrap_in_progress or game._map_transition_in_progress)
		and Time.get_ticks_msec() < bootstrap_deadline
	):
		await get_tree().process_frame
	assert(not game._world_bootstrap_in_progress, "初始世界加载未完成")
	assert(not game._map_transition_in_progress, "初始地图切换未完成")
	# Keep the remainder of the fixture's deterministic gameplay shortcuts.
	PlayerState.test_mode = true

	game.travel_to_map(217)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_zone == "兽人古墓一层", "未进入兽人古墓一层")
	assert(get_tree().get_nodes_in_group("enemies").size() == _runtime_enemy_count(217), "一层编辑器怪物配置未完整加载")
	assert(_boss_count() == MapEditorRuntimeBridge.game_content_for_map(217).bosses.size(), "一层Boss配置与编辑器运行时不一致")
	assert(_zone_portal_count() == MapEditorRuntimeBridge.game_content_for_map(217).portals.size(), "一层双向门点不完整")

	game.travel_to_map(218)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemies").size() == _runtime_enemy_count(218), "二层怪物与Boss数量不符")
	assert(_boss_count() == MapEditorRuntimeBridge.game_content_for_map(218).bosses.size(), "二层Boss配置与编辑器运行时不一致")
	var boss := _first_boss()
	assert(boss != null and float(boss.get_meta("respawn_seconds", 0.0)) == 3600.0, "骷髅精灵60分钟刷新规则失效")

	game.travel_to_map(221)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("enemies").size() == _runtime_enemy_count(221), "三层高密度怪物不完整")
	assert(_boss_count() == MapEditorRuntimeBridge.game_content_for_map(221).bosses.size(), "三层Boss点未按编辑器运行时完整加载")
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


func _runtime_enemy_count(map_id: int) -> int:
	var content := MapEditorRuntimeBridge.game_content_for_map(map_id)
	var count: int = content.get("bosses", []).size()
	for spawn: Dictionary in content.get("spawns", []):
		count += maxi(1, mini(
			int(spawn.get("count", 1)),
			int(spawn.get("max_alive", spawn.get("count", 1)))
		))
	return count


func _zone_portal_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal:
			count += 1
	return count


func _first_boss() -> EnemyActor:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			return node
	return null
