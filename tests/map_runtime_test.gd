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
	await _await_map_transition(game, 5)

	game.hud._toggle_map_panel()
	assert(game.hud.map_panel.visible, "地图目录未打开")
	assert(game.hud.has_signal("map_teleport_availability_requested"), "HUD 没有转发传送规则请求")
	assert(game.hud.has_signal("map_teleport_requested"), "HUD 没有转发结构化传送请求")
	assert(game.hud.has_method("set_map_teleport_availability"), "HUD 缺少传送开放规则注入方法")
	assert(game.hud.map_panel._selected_world_node_id == "bich_province", "地图目录默认未选择首个可过滤大区")
	for map_data: Dictionary in game.hud.map_panel.map_entries:
		assert(game.hud.map_panel._node_matches_map(game.hud.map_panel._world_node("bich_province"), map_data), "默认地图列表含不匹配地图")
	PlayerState.set_later_content_enabled(true)
	game.hud.map_panel.refresh()
	assert(PlayerState.later_content_enabled, "后期内容开关未保存")
	game.hud.map_panel.hide()

	game.travel_to_map(217)
	await _await_map_transition(game)
	assert(game.current_map_id == 217 and game.current_zone == "兽人古墓一层", "地图ID切换失败")
	# Test mode completes the transition synchronously; flush queued frees before
	# inspecting the destination actor set. Production performs this frame wait
	# inside _run_map_transition before declaring READY.
	await get_tree().process_frame
	var runtime_content := MapEditorRuntimeBridge.game_content_for_map(217)
	var expected_monster_ids: Array[int] = []
	for raw_spawn: Variant in runtime_content.get("spawns", []):
		if raw_spawn is Dictionary:
			expected_monster_ids.append(int((raw_spawn as Dictionary).get("monster_id", -1)))
	var actual_monster_ids: Array[int] = []
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and not node.is_boss:
			actual_monster_ids.append(int(node.monster_data.get("monsterId", -1)))
	expected_monster_ids.sort()
	actual_monster_ids.sort()
	assert(not expected_monster_ids.is_empty(), "正式运行时地图未声明怪物")
	assert(actual_monster_ids == expected_monster_ids, "正式运行时地图怪物未按runtime语义生成")
	assert(get_tree().get_nodes_in_group("interactable").size() >= 1, "通用地图临时门点未生成")

	var generic_map_id := -1
	for map_data: Variant in GameData.maps:
		if map_data is Dictionary and bool(map_data.get("availabilityDefault", true)) and not RegionContent.has_map(int(map_data.get("mapId", -1))):
			generic_map_id = int(map_data.get("mapId", -1))
			break
	if generic_map_id > 0:
		game.travel_to_map(generic_map_id)
		await _await_map_transition(game, 8)
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
	await _await_map_transition(game)
	var boss_count := 0
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			boss_count += 1
	assert(boss_count >= 1, "关联Boss未在目标地图生成")

	print("MAP_RUNTIME_PASS：129/142地图目录、唯一ID切换、正式runtime怪物、Boss关联与门点正常")
	get_tree().quit(0)


func _await_map_transition(game: Node, minimum_enemies: int = 0) -> void:
	var deadline := Time.get_ticks_msec() + 5000
	while (bool(game.get("_world_bootstrap_in_progress")) or bool(game.get("_map_transition_in_progress")) or get_tree().get_nodes_in_group("enemies").size() < minimum_enemies) and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame
	assert(not bool(game.get("_world_bootstrap_in_progress")) and not bool(game.get("_map_transition_in_progress")))
