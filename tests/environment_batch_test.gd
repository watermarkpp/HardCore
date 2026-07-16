extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const Validator := preload("res://scripts/environment_validator.gd")

const SAMPLE_MAPS := [401, 404, 408, 412, 312, 313, 314, 315, 478, 248]


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var errors := Validator.validate_all()
	assert(errors.is_empty(), "批量环境目录校验失败：%s" % "；".join(errors))
	var report := Catalog.coverage_report()
	assert(int(report.configured_maps) == 23, "环境模板覆盖地图数不是23")
	assert(report.by_theme == {"surface": 1, "cave": 5, "temple": 4, "mine": 12, "desert": 1}, "五主题地图覆盖统计错误：%s" % report.by_theme)
	for map_id: int in Catalog.configured_map_ids():
		assert(Catalog.get_map_profile(map_id) == Catalog.get_map_profile(map_id), "地图%d批量配置不是确定性生成" % map_id)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	var background: WorldBackground = game.background
	var stable_nodes := {}
	var memory_before := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	for pass_index in range(4):
		for map_id: int in SAMPLE_MAPS:
			game.travel_to_map(map_id)
			await get_tree().process_frame
			await get_tree().process_frame
			var profile := Catalog.get_map_profile(map_id)
			assert(background.environment_theme_id() == str(profile.theme), "地图%d运行时主题错误" % map_id)
			assert(background.environment_collision_count() == int(profile.expected_collisions), "地图%d运行时碰撞数量错误" % map_id)
			assert(background.environment_light_count() == int(profile.expected_lights), "地图%d运行时灯光数量错误" % map_id)
			var node_count := background.environment_node_count()
			assert(node_count == Catalog.expected_runtime_nodes(profile), "地图%d运行时节点预算不符：%d" % [map_id, node_count])
			if stable_nodes.has(map_id):
				assert(int(stable_nodes[map_id]) == node_count, "地图%d重复进入产生节点残留" % map_id)
			else:
				stable_nodes[map_id] = node_count
			for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
				assert(not background.is_environment_point_blocked(portal.position), "地图%d门点被批量环境阻挡" % map_id)
	var memory_after := int(Performance.get_monitor(Performance.MEMORY_STATIC))
	assert(memory_after - memory_before < 16 * 1024 * 1024, "40次跨主题切图静态内存异常增长")

	game.travel_to_map(315)
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor and enemy.is_boss:
			boss_count += 1
	assert(boss_count == 2, "沃玛寺庙模板切换破坏了双Boss配置")
	game.travel_to_map(478)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(get_tree().get_nodes_in_group("interactable").size() >= 10, "盟重沙地模板切换破坏了NPC或六门点")
	print("ENVIRONMENT_BATCH_PASS：23图/5主题覆盖，10图样板40次跨区无残留，Boss/NPC正常，静态内存变化%dKB" % int((memory_after - memory_before) / 1024))
	get_tree().quit(0)
