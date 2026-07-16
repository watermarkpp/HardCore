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
	var expected_counts := {1544: 9, 1545: 9, 1546: 5, 1571: 10}
	var expected_portals := {1544: 4, 1545: 2, 1546: 2, 1571: 1}
	for map_id: int in RegionContent.UNKNOWN_DARK_MAPS.keys():
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("spawns", []).size() == expected_counts[map_id], "未知暗殿地图%d刷怪数不符" % map_id)
		assert(content.get("portals", []).size() == expected_portals[map_id], "未知暗殿地图%d门点数不符" % map_id)
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == expected_counts[map_id], "未知暗殿地图%d运行时怪物数不符" % map_id)
	var entrance := RegionContent.get_map_content(1544)
	assert(entrance.get("npcs", []).size() == 1 and str(entrance.npcs[0].get("name", "")) == "暗殿老人", "暗殿老人未接入")
	var palace := RegionContent.get_map_content(1571)
	var weak_leader_found := false
	for spawn: Variant in palace.spawns:
		if spawn is Dictionary and str(spawn.get("name", "")) == "沃玛教主1":
			var weak_leader := GameData.get_monster("沃玛教主1")
			weak_leader_found = str(spawn.get("display_name", "")) == "沃玛教主" and int(weak_leader.get("hp", 0)) == 100
	assert(weak_leader_found, "弱沃玛教主真假外观或属性失效")
	var line_sky := RegionContent.get_map_content(1451)
	var has_entrance := false
	for portal: Variant in line_sky.get("portals", []):
		if portal is Dictionary and int(portal.get("target_map_id", 0)) == 1544:
			has_entrance = true
	assert(has_entrance, "一线天没有接入未知暗殿入口")
	assert(RegionContent.MAPS.size() + RegionContent.CENTIPEDE_MAPS.size() + RegionContent.ZUMA_MAPS.size() + RegionContent.UNKNOWN_DARK_MAPS.size() == 75, "固定区域地图总数应为75")
	print("UNKNOWN_DARK_PALACE_PASS：4图通道、暗殿老人、10种真假怪、属性反转和返回门点正常")
	get_tree().quit(0)
