extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var expected := {338: Vector2i(6, 3), 457: Vector2i(7, 2), 458: Vector2i(10, 4), 478: Vector2i(6, 12), 1183: Vector2i(0, 2)}
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in expected.keys():
		assert(RegionContent.has_map(map_id), "毒蛇/盟重区域包缺少地图%d" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var target: Vector2i = expected[map_id]
		assert(get_tree().get_nodes_in_group("enemies").size() == target.x, "地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == target.y, "地图%d门点或NPC数量不符" % map_id)
	game.travel_to_map(478)
	await get_tree().process_frame
	await get_tree().process_frame
	var npc_count := 0
	var mid_shop_found := false
	var portal_targets := {}
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if node is NPCActor:
			npc_count += 1
			if node.stock_key == "mid_gear":
				mid_shop_found = not node.shop_stock.is_empty()
		elif node is ZonePortal:
			portal_targets[node.target_map_id] = true
	assert(npc_count == 4 and mid_shop_found, "盟重商店、书店或导师配置不完整")
	for target_id in [338, 1197, 1378, 659, 1183, 3013, 2863, 3165]:
		assert(portal_targets.has(target_id), "盟重缺少区域入口%d" % target_id)
	assert(RegionContent.MAPS.size() >= 31, "盟重阶段手工地图数量回退")
	print("MENGZHONG_AREA_PASS：毒蛇山谷/矿区、盟重枢纽、商店NPC和封魔谷等区域入口正常")
	get_tree().quit(0)
