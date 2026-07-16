extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var layout := GothicBichCampBuilder.load_layout()
	if not _check(int(layout.get("mapId", -1)) == 4 and float(layout.get("safeRadius", 0.0)) >= 650.0, "哥特比奇布局或安全区无效"): return
	if not _check(layout.get("npcSlots", {}).size() >= 5 and layout.get("lights", []).size() <= 5, "NPC功能区或移动端灯光上限错误"): return
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	if not _check(game.current_map_id == 4, "启动未进入比奇主城地图"): return
	if not _check(game.background.environment_node_count() >= 40, "哥特主城物件没有完成构建"): return
	if not _check(game.background.environment_light_count() <= 5, "主城灯光超过移动端上限"): return
	var home: Vector2 = game._bich_home_world_position()
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if not _check(enemy.global_position.distance_to(home) >= float(layout.safeRadius), "怪物刷新在安全区内"): return
	var expected_names := ["比奇杂货商", "比奇武器店", "书店老板", "武馆教头", "比奇老兵", "仓库管理员"]
	var actual_names: Array[String] = []
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is NPCActor:
			actual_names.append(node.npc_name)
	for npc_name: String in expected_names:
		if not _check(npc_name in actual_names, "主城缺少功能NPC：%s" % npc_name): return
	print("GOTHIC_BICH_CAMP_PASS：哥特主城、安全区、功能分区、碰撞与灯光完成运行构建")
	get_tree().quit(0)


func _check(value: bool, message: String) -> bool:
	if value:
		return true
	print("GOTHIC_BICH_CAMP_FAIL：", message)
	get_tree().quit(1)
	return false
