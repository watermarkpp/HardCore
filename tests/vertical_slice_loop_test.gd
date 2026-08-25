extends Node



func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 22
	PlayerState.recalculate_stats()
	assert(PlayerState.accept_quest("bich_beginner_gear").begins_with("已接受"), "初级装备任务无法接受")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.travel_to_map(4)
	await _settle()
	assert(game.current_map_id == 4 and game.background.uses_bich_art(), "刷装路线没有从比奇省开始")
	_kill_three_strawmen(game)
	await get_tree().process_frame
	assert(PlayerState.quest_progress("bich_beginner_gear") == 3, "三只稻草人没有推进任务")

	_travel_via_portal(game, 217)
	await _settle()
	_assert_arrival(game, 217, game.route_arrival_position(217, 4))
	assert(game.background._editor_runtime_size == Vector2i(38, 38), "一层编辑器运行时碰撞未加载")
	_assert_editor_runtime_collision(game, 217)

	_travel_via_portal(game, 218)
	await _settle()
	_assert_arrival(game, 218, game.route_arrival_position(218, 217))

	_travel_via_portal(game, 221)
	await _settle()
	_assert_arrival(game, 221, game.route_arrival_position(221, 218))

	# 217、218、221 当前正式 runtime 尚未配置怪物或 Boss。
	# 怪物验收将在 Monster 数据、地图分布权威和正式布置完成后，
	# 由独立的 map_monster_placement_acceptance_test 负责。

	PlayerState.add_item("回城卷")
	var scroll_index := _inventory_index("回城卷")
	assert(scroll_index >= 0 and PlayerState.use_inventory_index(scroll_index).begins_with("使用"), "Boss后无法使用回城卷")
	await _settle()
	assert(game.current_zone == "比奇省" and game.current_map_id == 4, "回城卷没有返回服务端HomeMap=0对应的比奇省")
	var gold_before := PlayerState.gold
	assert(PlayerState.claim_quest("bich_beginner_gear").begins_with("已领取"), "回城后无法领取任务奖励")
	assert(PlayerState.gold == gold_before + 100 and PlayerState.has_item("布衣(男)"), "任务金币或布衣奖励缺失")
	var cloth_index := _inventory_index("布衣(男)")
	assert(cloth_index >= 0 and PlayerState.equip_inventory_index(cloth_index).begins_with("已装备"), "任务布衣无法穿戴")
	assert(str(PlayerState.equipment["衣服"].get("name", "")) == "布衣(男)", "布衣没有进入衣服装备槽")

	await _run_reentry_stability(game)
	print("VERTICAL_SLICE_LOOP_PASS：任务、三怪、三层门点、实碰撞、回城、装备与重复进图正常")
	get_tree().quit(0)


func _kill_three_strawmen(game: Node) -> void:
	var existing := get_tree().get_nodes_in_group("enemies")
	var data := GameData.get_monster_by_id(21)
	assert(
		not data.is_empty(),
		"稳定monster_id=21的稻草人运行时记录缺失"
	)
	for offset in [Vector2(-70, 0), Vector2(0, -70), Vector2(70, 0)]:
		game._spawn_enemy(data, game.player.global_position + offset, false, 120.0)
	var killed := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy not in existing and enemy is EnemyActor and enemy.display_name == "稻草人":
			assert(
				int(enemy.monster_data.get("monster_id", -1)) == 21,
				"稻草人actor没有保留canonical monster_id=21"
			)
			assert(
				not enemy.monster_data.has("monsterId"),
				"canonical EnemyActor payload重新泄漏legacy monsterId"
			)
			enemy.take_damage(enemy.max_hp)
			killed += 1
	assert(killed == 3, "测试刷怪区没有生成三只稻草人")


func _assert_arrival(game: Node, map_id: int, expected: Vector2) -> void:
	assert(game.current_map_id == map_id, "没有进入目标地图%d" % map_id)
	assert(game.player.global_position.distance_to(expected) < 0.1, "地图%d落脚点错误：期望%s，实际%s" % [map_id, expected, game.player.global_position])
	assert(not game.background.is_orc_tomb_point_blocked(game.player.global_position), "地图%d落脚点被环境堵塞" % map_id)
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is ZonePortal:
			if game.player.global_position.distance_to(node.global_position) <= 105.0:
				var expected_lock := "%d:%s" % [
					map_id,
					str(node.portal_data.get("source_portal_id", "")),
				]
				assert(
					str(game._portal_guard_state.get("locked_portal_id", "")) == expected_lock,
					"地图%d精确门点落脚缺少防回弹锁" % map_id
				)
	var beacons := get_tree().get_nodes_in_group("route_guidance")
	assert(beacons.is_empty(), "地图%d不应再生成额外的单箭头导航信标" % map_id)


func _assert_editor_runtime_collision(game: Node, map_id: int) -> void:
	var runtime := MapEditorRuntimeBridge.load_map(map_id)
	var blocked_tiles: Array = runtime.get("collision", {}).get("blocked_tiles", [])
	assert(not blocked_tiles.is_empty(), "地图%d缺少编辑器阻挡网格" % map_id)
	var parts := str(blocked_tiles[0]).split(",")
	assert(parts.size() == 2)
	var blocked_world := MapEditorRuntimeBridge.grid_cell_to_screen_position_px(
		runtime, [float(parts[0]), float(parts[1])]
	)
	assert(game.background.is_environment_point_blocked(blocked_world), "地图%d阻挡网格未接入主体游戏" % map_id)


func _travel_via_portal(game: Node, target_map_id: int) -> void:
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if node is ZonePortal and node.target_map_id == target_map_id:
			assert(game.travel_via_portal(node, true), "统一门点旅行失败:%d" % target_map_id)
			return
	assert(false, "统一门点缺失:%d" % target_map_id)


func _run_reentry_stability(game: Node) -> void:
	game.change_zone("比奇郊外")
	await _settle()
	var stable_environment_counts := {}
	var stable_child_counts := {}
	# 里程碑只采样一次完整往返；长时间压力测试不混入日常功能验收。
	for map_id in [4, 217, 218, 221, 4]:
		game.travel_to_map(map_id)
		await _settle()
		var environment_count: int = game.background.environment_node_count()
		var child_count: int = game.background.get_child_count()
		var actor_occluder_count := 0
		for child: Node in game.get_children():
			if bool(child.get_meta("editor_runtime_actor_occluder", false)):
				actor_occluder_count += 1
		assert(environment_count > 0, "地图%d没有构建环境节点" % map_id)
		assert(
			child_count + actor_occluder_count == environment_count,
			"地图%d切换后残留待删除的环境节点" % map_id
		)
		if stable_environment_counts.has(map_id):
			assert(environment_count == int(stable_environment_counts[map_id]), "地图%d重复进入后环境节点数量增长" % map_id)
			assert(child_count == int(stable_child_counts[map_id]), "地图%d重复进入后背景子节点数量增长" % map_id)
		else:
			stable_environment_counts[map_id] = environment_count
			stable_child_counts[map_id] = child_count
		assert(get_tree().get_nodes_in_group("route_guidance").is_empty(), "连续往返后不应生成单箭头导航信标")
	assert(game.current_map_id == 4 and game.background.uses_bich_art(), "再次出发没有回到比奇省")


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
