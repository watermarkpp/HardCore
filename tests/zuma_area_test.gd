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
	for map_id: int in RegionContent.ZUMA_MAPS.keys():
		var source: Dictionary = RegionContent.ZUMA_MAPS[map_id]
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "祖玛地图%d怪物数量不符" % map_id)
		assert(get_tree().get_nodes_in_group("interactable").size() == source.get("targets", []).size(), "祖玛地图%d门点数量不符" % map_id)
	game.travel_to_map(682)
	await get_tree().process_frame
	await get_tree().process_frame
	var leader: EnemyActor
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if node is EnemyActor and node.display_name == "祖玛教主":
			leader = node
			break
	assert(leader != null and float(leader.get_meta("respawn_seconds", 0.0)) == 10800.0, "祖玛教主刷新候选值失效")
	var avatar_found := false
	for drop: Variant in GameData.get_drops_for_boss(160):
		if str(drop.get("itemName", "")) == "祖玛头像":
			avatar_found = true
			break
	assert(avatar_found and GameData.get_item_kind("祖玛头像") == "quest_item", "祖玛头像掉落闭环失败")
	var archer := EnemyActor.new()
	archer.setup(GameData.get_monster("祖玛弓箭手"), game.player, false)
	assert(archer.attack_range_gu >= 200.0 / 32.0, "祖玛弓箭手远程配置未生效")
	archer.free()
	var statue := EnemyActor.new()
	statue.setup(GameData.get_monster("祖玛雕像"), game.player, false)
	assert(statue.dormant, "祖玛雕像休眠配置未生效")
	statue.free()
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() + RegionContent.ZUMA_MAPS.size() == 71, "手工地图总数应为71")
	print("ZUMA_AREA_PASS：祖玛12图、祖玛阁、七层、休眠怪、远程弓手、教主和祖玛头像正常")
	get_tree().quit(0)
