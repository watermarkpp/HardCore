extends Node

const TargetingSystem := preload("res://scripts/targeting_system.gd")


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

	game.travel_to_map(217)
	await _settle()
	_assert_arrival(game, 217, game.route_arrival_position(217, 4), game.route_next_target(217).position)
	assert(game.background.orc_tomb_collision_count() == int(game.background.environment_profile().expected_collisions), "一层环境碰撞未加载")
	await _assert_real_pillar_collision(game)
	_assert_mobile_target_available(game, "一层怪群附近没有手机自动选敌目标")

	game.travel_to_map(218)
	await _settle()
	_assert_arrival(game, 218, game.route_arrival_position(218, 217), game.route_next_target(218).position)
	_assert_mobile_target_available(game, "二层怪群附近没有手机自动选敌目标")

	game.travel_to_map(221)
	await _settle()
	_assert_arrival(game, 221, game.route_arrival_position(221, 218), game.route_next_target(221).position)
	var boss := _first_boss()
	assert(boss != null, "三层刷装闭环缺少骷髅精灵")
	assert(not GameData.get_drops_for_boss(int(boss.monster_data.get("monsterId", 0))).is_empty(), "骷髅精灵没有数据库掉落链")
	var experience_before := PlayerState.experience
	game.player.global_position = boss.global_position + Vector2(-120, 0)
	boss.apply_control(5.0)
	boss.take_damage(boss.max_hp)
	await get_tree().process_frame
	assert(_first_boss() == null, "骷髅精灵死亡后仍保留在战斗目标组")
	assert(PlayerState.experience > experience_before or PlayerState.level > 22, "击杀Boss没有获得经验")

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
	print("VERTICAL_SLICE_LOOP_PASS：任务、三怪、三层门点、实碰撞、自动选敌、Boss、回城、装备与重复进图正常")
	get_tree().quit(0)


func _kill_three_strawmen(game: Node) -> void:
	var existing := get_tree().get_nodes_in_group("enemies")
	var data := GameData.get_monster("稻草人")
	for offset in [Vector2(-70, 0), Vector2(0, -70), Vector2(70, 0)]:
		game._spawn_enemy(data, game.player.global_position + offset, false, 120.0)
	var killed := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy not in existing and enemy is EnemyActor and enemy.display_name == "稻草人":
			enemy.take_damage(enemy.max_hp)
			killed += 1
	assert(killed == 3, "测试刷怪区没有生成三只稻草人")


func _assert_arrival(game: Node, map_id: int, expected: Vector2, route_target: Vector2) -> void:
	assert(game.current_map_id == map_id, "没有进入目标地图%d" % map_id)
	assert(game.player.global_position.distance_to(expected) < 0.1, "地图%d落脚点错误：期望%s，实际%s" % [map_id, expected, game.player.global_position])
	assert(not game.background.is_orc_tomb_point_blocked(game.player.global_position), "地图%d落脚点被环境堵塞" % map_id)
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is ZonePortal:
			assert(game.player.global_position.distance_to(node.global_position) > 105.0, "地图%d落脚点位于门点重复交互范围" % map_id)
	var beacons := get_tree().get_nodes_in_group("route_guidance")
	assert(beacons.size() == 1 and beacons[0] is RouteBeacon, "地图%d方向信标数量错误" % map_id)
	var expected_direction: Vector2 = game.player.global_position.direction_to(route_target)
	assert((beacons[0] as RouteBeacon).direction_to_target().dot(expected_direction) > 0.999, "地图%d信标方向错误" % map_id)


func _assert_real_pillar_collision(game: Node) -> void:
	var prop: Dictionary = game.background.environment_profile().get("props", [])[0]
	var prop_position: Vector2 = prop.get("position", Vector2.ZERO) + prop.get("collision_offset", Vector2.ZERO)
	game.player.global_position = prop_position + Vector2(-100, 0)
	game.player.set_touch_vector(Vector2.RIGHT)
	for _frame in range(35):
		await get_tree().physics_frame
	game.player.set_touch_vector(Vector2.ZERO)
	assert(game.player.global_position.x < prop_position.x + 40.0, "角色穿过了一层石柱实体碰撞")
	game.player.global_position = game.route_arrival_position(217, 4)


func _assert_mobile_target_available(game: Node, message: String) -> void:
	game._cancel_target()
	var enemies := get_tree().get_nodes_in_group("enemies")
	assert(not enemies.is_empty(), message)
	game.player.global_position = (enemies[0] as EnemyActor).global_position + Vector2(-100, 0)
	game.player.facing = Vector2.RIGHT
	var target: EnemyActor = game._ensure_combat_target()
	assert(target != null and target.global_position.distance_to(game.player.global_position) <= TargetingSystem.DEFAULT_SEARCH_RADIUS, message)


func _run_reentry_stability(game: Node) -> void:
	game.change_zone("比奇郊外")
	await _settle()
	# 里程碑只采样一次完整往返；长时间压力测试不混入日常功能验收。
	for map_id in [4, 217, 218, 221, 4]:
		game.travel_to_map(map_id)
		await _settle()
		assert(game.background.get_child_count() < 80, "连续往返后环境节点异常增长")
		assert(get_tree().get_nodes_in_group("route_guidance").size() == 1, "连续往返后方向信标残留")
	assert(game.current_map_id == 4 and game.background.uses_bich_art(), "再次出发没有回到比奇省")


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _first_boss() -> EnemyActor:
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			return node
	return null


func _settle() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
