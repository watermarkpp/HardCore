extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var runtime_ids := {}
	var later_count := 0
	for map_data: Variant in GameData.maps:
		assert(map_data is Dictionary, "地图记录类型错误")
		var runtime_id := int(map_data.get("mapId", -1))
		assert(runtime_id > 0 and not runtime_ids.has(runtime_id), "地图运行时ID重复：%d" % runtime_id)
		runtime_ids[runtime_id] = true
		assert(RegionContent.has_map(runtime_id), "地图%d尚未进入固定区域表" % runtime_id)
		if str(map_data.get("versionTag", "")).begins_with("1.76后期"):
			later_count += 1
			assert(str(map_data.get("sourceMapId", "")).begins_with("LATE-"), "后期地图缺少原始资料ID")
	assert(runtime_ids.size() == 142 and later_count == 13, "142张地图唯一ID或后期地图数量错误")
	PlayerState.set_later_content_enabled(false)
	assert(GameData.get_available_maps(false).size() == 129, "基准地图开关数量错误")
	PlayerState.set_later_content_enabled(true)
	assert(GameData.get_available_maps(true).size() == 142, "后期地图开关未启用13张追加地图")
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in RegionContent.FINAL_BASE_MAPS.keys():
		var source: Dictionary = RegionContent.FINAL_BASE_MAPS[map_id]
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		assert(get_tree().get_nodes_in_group("enemies").size() == int(source.get("spawn_count", 0)), "最终基准地图%d怪物数不符" % map_id)
	for map_id: int in RegionContent.LATER_MAPS.keys():
		var source: Dictionary = RegionContent.LATER_MAPS[map_id]
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("spawns", []).size() + content.get("bosses", []).size() == int(source.get("spawn_count", 0)), "后期地图%d怪物数不符" % map_id)
	var clothes_bosses := [225, 235, 237, 240, 236, 238]
	for boss_id: int in clothes_bosses:
		assert(not GameData.get_drops_for_boss(boss_id).is_empty(), "六件新衣Boss%d掉落未接入" % boss_id)
	game.travel_to_map(900013)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_zone == "沙巴克藏宝阁" and get_tree().get_nodes_in_group("enemies").size() == 8, "藏宝阁运行时生成失败")
	print("FINAL_MAP_COVERAGE_PASS：129张基准、13张后期地图ID唯一，香石/重装/幻境/圣域/藏宝阁固定区域正常")
	get_tree().quit(0)
