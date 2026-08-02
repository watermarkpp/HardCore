extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var expected := {268: Vector2i(4, 3), 1506: Vector2i(8, 3), 1507: Vector2i(8, 1), 312: Vector2i(2, 4), 313: Vector2i(7, 4), 314: Vector2i(8, 3), 315: Vector2i(6, 1)}
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in expected.keys():
		assert(RegionContent.has_map(map_id), "沃玛区域包缺少地图%d" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var target: Vector2i = expected[map_id]
		assert(get_tree().get_nodes_in_group("enemies").size() == target.x, "沃玛地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == target.y, "沃玛地图%d门点数量不符" % map_id)
	game.travel_to_map(315)
	await get_tree().process_frame
	await get_tree().process_frame
	var bosses := {}
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.is_boss:
			bosses[node.display_name] = float(node.get_meta("respawn_seconds", 0.0))
	assert(bosses.size() == 2 and bosses.has("沃玛卫士") and bosses.has("沃玛教主"), "沃玛核心双Boss配置不完整")
	assert(float(bosses["沃玛卫士"]) == 3600.0 and float(bosses["沃玛教主"]) == 7200.0, "沃玛Boss候选刷新配置失效")
	var horn_found := false
	for drop: Variant in GameData.get_drops_for_boss(76):
		if str(drop.get("itemName", "")) == "沃玛号角":
			horn_found = true
			break
	assert(horn_found and GameData.get_item_kind("沃玛号角") == "quest_item", "沃玛号角掉落闭环失败")
	var fire_wooma := GameData.get_monster("火焰沃玛")
	var ranged_enemy := EnemyActor.new()
	ranged_enemy.setup(fire_wooma, game.player, false)
	assert(ranged_enemy.attack_range_gu >= 150.0 / 32.0, "火焰沃玛远程攻击配置未生效")
	ranged_enemy.free()
	print("WOOMA_AREA_PASS：沃玛森林/自然洞穴/寺庙四层、普通怪物、双Boss和沃玛号角正常")
	get_tree().quit(0)
