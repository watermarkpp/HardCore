extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(GameData.get_available_maps(false).size() == 129, "2003基准地图数量不符")
	assert(GameData.get_available_maps(true).size() == 142, "启用后期内容后的地图数量不符")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame

	game.hud._toggle_map_panel()
	assert(game.hud.map_panel.visible, "地图目录未打开")
	assert(game.hud.has_signal("map_teleport_availability_requested"), "HUD 没有转发传送规则请求")
	assert(game.hud.has_signal("map_teleport_requested"), "HUD 没有转发结构化传送请求")
	assert(game.hud.has_method("set_map_teleport_availability"), "HUD 缺少传送开放规则注入方法")
	assert(game.hud.map_panel.map_entries.size() == 129, "地图目录默认筛选错误")
	game.hud.map_panel.later_toggle.button_pressed = true
	assert(PlayerState.later_content_enabled, "后期内容开关未保存")
	assert(game.hud.map_panel.map_entries.size() == 142, "后期地图未进入目录")
	game.hud.map_panel.hide()

	game.travel_to_map(217)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == 217 and game.current_zone == "兽人古墓一层", "地图ID切换失败")
	assert(get_tree().get_nodes_in_group("enemies").size() == 5, "首批手工地图怪物未生成")
	assert(get_tree().get_nodes_in_group("interactable").size() >= 1, "通用地图临时门点未生成")
	var generic_map_id := -1
	for map_data: Variant in GameData.maps:
		if map_data is Dictionary and bool(map_data.get("availabilityDefault", true)) and not RegionContent.has_map(int(map_data.get("mapId", -1))):
			generic_map_id = int(map_data.get("mapId", -1))
			break
	if generic_map_id > 0:
		game.travel_to_map(generic_map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() >= 8, "通用地图怪物未生成")
	else:
		for map_data: Variant in GameData.maps:
			assert(map_data is Dictionary and RegionContent.has_map(int(map_data.get("mapId", -1))), "全地图固定区域覆盖不完整")

	var wooma_map: Dictionary = {}
	for map_data: Variant in GameData.maps:
		if map_data is Dictionary and int(map_data.get("mapId", -1)) == 315:
			wooma_map = map_data
			break
	assert(not wooma_map.is_empty(), "数据库缺少沃玛寺庙核心地图")
	assert(GameData.get_bosses_for_map(wooma_map).size() >= 1, "沃玛教主地点关联失败")
	game.travel_to_map(int(wooma_map.get("mapId", -1)))
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			boss_count += 1
	assert(boss_count >= 1, "关联Boss未在目标地图生成")

	print("MAP_RUNTIME_PASS：129/142地图目录、唯一ID切换、固定区域怪物、Boss关联与门点正常")
	get_tree().quit(0)
