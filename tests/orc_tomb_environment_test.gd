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
	var background: WorldBackground = game.background

	game.travel_to_map(217)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(background.uses_orc_tomb_art(), "兽人古墓一层没有启用正式环境")
	assert(background.orc_tomb_ground_atlas_size() == Vector2i(512, 32), "兽人古墓地砖图集规格错误")
	assert(background.orc_tomb_prop_atlas_size() == Vector2i(768, 128), "兽人古墓客户端物件图集规格错误")
	assert(background.orc_tomb_collision_count() == int(background.environment_profile().expected_collisions), "一层客户端结构碰撞数量错误")
	assert(background.orc_tomb_light_count() == int(background.environment_profile().expected_lights), "一层映射灯光数量错误")
	var floor_one := RegionContent.get_map_content(217)
	var floor_one_route: Array = background.environment_profile().get("routes", [])[0]
	assert(background.orc_tomb_tile_index_for_world(floor_one_route[0].lerp(floor_one_route[1], 0.5)) == 5, "一层雕刻主通道没有生成")
	for portal: Dictionary in floor_one.get("portals", []):
		assert(not background.is_orc_tomb_point_blocked(portal.position), "一层门点被碰撞堵塞")
	assert(_boss_count() == 0, "兽人古墓一层不应出现Boss")

	game.travel_to_map(218)
	await get_tree().process_frame
	await get_tree().process_frame
	var floor_two_boss: Vector2 = RegionContent.get_map_content(218).get("bosses", [])[0].position
	assert(background.orc_tomb_collision_count() == int(background.environment_profile().expected_collisions), "二层Boss房碰撞数量错误")
	assert(background.orc_tomb_light_count() == int(background.environment_profile().expected_lights), "二层映射灯光数量错误")
	assert(background.orc_tomb_tile_index_for_world(floor_two_boss) == 7, "二层Boss房没有使用符文地砖")
	assert(background.orc_tomb_tile_index_for_world(floor_two_boss + Vector2(225, 0)) == 3, "二层Boss房外环没有血祭地砖")
	_assert_boss_room_clear(background, floor_two_boss)
	for portal: Dictionary in RegionContent.get_map_content(218).get("portals", []):
		assert(not background.is_orc_tomb_point_blocked(portal.position), "二层门点被碰撞堵塞")
	assert(_boss_count() == 1, "兽人古墓二层骷髅精灵缺失")

	game.travel_to_map(221)
	await get_tree().process_frame
	await get_tree().process_frame
	var floor_three_boss: Vector2 = RegionContent.get_map_content(221).get("bosses", [])[0].position
	assert(background.orc_tomb_collision_count() == int(background.environment_profile().expected_collisions), "三层Boss房碰撞数量错误")
	assert(background.orc_tomb_light_count() == int(background.environment_profile().expected_lights), "三层映射灯光数量错误")
	assert(background.orc_tomb_tile_index_for_world(floor_three_boss) == 7, "三层Boss房没有使用符文地砖")
	_assert_boss_room_clear(background, floor_three_boss)
	for portal: Dictionary in RegionContent.get_map_content(221).get("portals", []):
		assert(not background.is_orc_tomb_point_blocked(portal.position), "三层返回门点被碰撞堵塞")
	assert(_boss_count() == 1, "兽人古墓三层骷髅精灵缺失")

	game.travel_to_map(4)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(not background.uses_orc_tomb_art() and background.uses_bich_art(), "返回比奇省后环境没有正确切换")
	assert(background.orc_tomb_collision_count() == 0 and background.orc_tomb_light_count() == 0, "离开古墓后洞穴碰撞或灯光残留")

	print("ORC_TOMB_ENVIRONMENT_PASS：D001—D003三层客户端地表、映射碰撞/灯光、双Boss房与门点清理正常")
	get_tree().quit(0)


func _assert_boss_room_clear(background: WorldBackground, center: Vector2) -> void:
	assert(not background.is_orc_tomb_point_blocked(center), "Boss刷新点被环境碰撞占用")
	for direction in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP, Vector2(1, 1).normalized(), Vector2(-1, 1).normalized()]:
		assert(not background.is_orc_tomb_point_blocked(center + direction * 145.0), "Boss扇形技能躲避空间被阻挡")


func _boss_count() -> int:
	var count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			count += 1
	return count
