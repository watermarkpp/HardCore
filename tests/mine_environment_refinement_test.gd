extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const MINE_MAPS := [401, 402, 403, 404, 405, 406, 407, 408, 409, 410, 411, 412]
const SOURCE_CODES := {
	401: "D401", 402: "D411", 403: "D413", 404: "D402", 405: "D414", 406: "D403",
	407: "D412", 408: "D404", 409: "D415", 410: "D405", 411: "D416", 412: "D406",
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(ResourceLoader.exists("res://assets/art/maps/mine/mine_ground_tiles.png"), "矿区专用地砖图集缺失")
	assert(ResourceLoader.exists("res://assets/art/maps/mine/mine_props.png"), "矿区专用物件图集缺失")
	assert(ResourceLoader.exists("res://assets/art/maps/mine/mine_lamp_glow.png"), "矿区矿灯资源缺失")
	var source_file := FileAccess.open("res://assets/data/mine_source_profiles.json", FileAccess.READ)
	assert(source_file != null, "客户端MAP解析清单缺失")
	var parsed: Variant = JSON.parse_string(source_file.get_as_text())
	assert(parsed is Dictionary and parsed.get("mapProfiles", {}).size() == 13, "客户端MAP解析清单数量错误")
	var route_signatures := {}
	for map_id: int in MINE_MAPS:
		var profile := Catalog.get_map_profile(map_id)
		assert(str(profile.get("theme", "")) == "mine", "地图%d未使用矿区主题" % map_id)
		assert(str(profile.get("source_map_code", "")) == SOURCE_CODES[map_id], "地图%d客户端MAP映射错误" % map_id)
		assert(str(profile.get("source_evidence", "")).contains("客户端MAP"), "地图%d缺少客户端来源标记" % map_id)
		assert(profile.get("coordinate_projection", "") == "isometric_64x32_full_size", "地图%d仍使用压缩坐标" % map_id)
		assert(RegionContent.get_map_content(map_id).get("status", "") == "client_map_full_size", "地图%d运行内容仍是垂直切片" % map_id)
		assert(profile.get("layout_hubs", []).size() >= 3, "地图%d没有独立线路枢纽" % map_id)
		assert(profile.get("props", []).size() >= 7, "地图%d矿区专用物件不足" % map_id)
		assert(int(profile.get("source_light_cells", -1)) >= 0, "地图%d原始灯光统计缺失" % map_id)
		var signature := str(profile.get("layout_hubs", []))
		assert(not route_signatures.has(signature), "地图%d仍在复用完全相同的线路布局" % map_id)
		route_signatures[signature] = true
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not Catalog._point_blocked(portal.position, profile), "地图%d门点被矿区碰撞占用" % map_id)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in MINE_MAPS:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var background: WorldBackground = game.background
		assert(background.uses_mine_art(), "地图%d运行时未加载矿区专用资源" % map_id)
		assert(background.mine_source_map_code() == SOURCE_CODES[map_id], "地图%d运行时来源映射丢失" % map_id)
		assert(background.mine_ground_atlas_size() == Vector2i(512, 32), "矿区地砖图集规格错误")
		assert(background.mine_prop_atlas_size() == Vector2i(768, 128), "矿区物件图集规格错误")
		assert(background.environment_collision_count() == int(background.environment_profile().expected_collisions), "地图%d碰撞实例数量错误" % map_id)
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not background.is_environment_point_blocked(portal.position), "地图%d运行时门点被阻挡" % map_id)
	game.travel_to_map(1578)
	await get_tree().process_frame
	await get_tree().process_frame
	var corpse_profile := Catalog.get_map_profile(1578)
	assert(not corpse_profile.is_empty() and corpse_profile.get("source_map_code", "") == "Q004", "尸王殿Q004环境配置缺失")
	assert(corpse_profile.get("source_size", Vector2i.ZERO) == Vector2i(30, 30), "尸王殿没有恢复30×30原尺寸")
	assert(corpse_profile.get("coordinate_projection", "") == "isometric_64x32_full_size", "尸王殿没有使用统一坐标")
	assert(corpse_profile.get("world_bounds", Rect2()) == Rect2(-928, -464, 1856, 928), "尸王殿世界边界错误")
	assert(corpse_profile.get("arena", {}).get("inner", 0.0) == 250.0 and corpse_profile.get("expected_lights", -1) == 0, "尸王殿Boss安全区或原始灯光规则错误")
	assert(game.background.environment_collision_count() == int(corpse_profile.expected_collisions), "尸王殿边界/环境碰撞数量错误")
	for boss: Dictionary in RegionContent.get_map_content(1578).get("bosses", []):
		assert(not game.background.is_environment_point_blocked(boss.position), "尸王刷新点被环境阻挡")
		for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
			assert(not game.background.is_environment_point_blocked(boss.position + direction * 145.0), "尸王战斗躲避空间被阻挡")
	var boss_count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor and enemy.is_boss:
			boss_count += 1
	assert(boss_count == 2, "矿区美术精修破坏双尸王配置")
	print("MINE_ENVIRONMENT_REFINEMENT_PASS：12图原尺寸、Q004 30×30 Boss房、统一坐标、碰撞门点和双尸王正常")
	get_tree().quit(0)
