extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const MAPS := [338, 457, 458]
const SOURCES := {338: "2", 457: "D421", 458: "D422"}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for path: String in [
		"res://assets/art/maps/snake_valley/snake_valley_ground_tiles.png",
		"res://assets/art/maps/snake_valley/snake_valley_props.png",
		"res://assets/art/maps/snake_valley/snake_mine_ground_tiles.png",
		"res://assets/art/maps/snake_valley/snake_mine_props.png",
		"res://assets/art/maps/snake_valley/snake_mine_glow.png",
	]:
		assert(ResourceLoader.exists(path), "毒蛇区域资源缺失：%s" % path)
	var file := FileAccess.open("res://assets/data/snake_valley_source_profiles.json", FileAccess.READ)
	assert(file != null, "毒蛇区域MAP解析清单缺失")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("mapProfiles", {}).size() == 3, "毒蛇区域MAP解析数量错误")
	for map_id: int in MAPS:
		var profile := Catalog.get_map_profile(map_id)
		assert(profile.get("source_map_code", "") == SOURCES[map_id], "地图%d客户端MAP映射错误" % map_id)
		assert(str(profile.get("source_evidence", "")).contains("客户端MAP"), "地图%d缺少来源证据" % map_id)
		assert(profile.get("props", []).size() >= 9, "地图%d专用场景物件不足" % map_id)
		assert(int(profile.get("prop_count_override", 0)) == 8, "地图%d专用图集规格未记录" % map_id)
		if map_id == 338:
			assert(profile.get("asset_set", "") == "snake_valley" and profile.get("theme", "") == "surface", "毒蛇山谷资源主题错误")
		else:
			assert(profile.get("asset_set", "") == "snake_mine" and profile.get("theme", "") == "mine", "山谷矿区资源主题错误")
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not Catalog._point_blocked(portal.position, profile), "地图%d门点被碰撞占用" % map_id)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in MAPS:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var background: WorldBackground = game.background
		assert(background.environment_source_map_code() == SOURCES[map_id], "地图%d运行时来源映射丢失" % map_id)
		assert(background.uses_snake_valley_art() if map_id == 338 else background.uses_snake_mine_art(), "地图%d专用资源未加载" % map_id)
		var sizes := background.snake_valley_atlas_sizes()
		assert(Vector2i(sizes.valley_ground) == Vector2i(512, 32) and Vector2i(sizes.valley_props) == Vector2i(768, 128), "毒蛇山谷图集规格错误")
		assert(Vector2i(sizes.mine_ground) == Vector2i(512, 32) and Vector2i(sizes.mine_props) == Vector2i(768, 128), "山谷矿区图集规格错误")
		assert(background.environment_collision_count() == int(background.environment_profile().expected_collisions), "地图%d碰撞数量错误" % map_id)
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not background.is_environment_point_blocked(portal.position), "地图%d运行时门点被阻挡" % map_id)
	game.travel_to_map(338)
	await get_tree().process_frame
	await get_tree().process_frame
	var names := {}
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor:
			names[enemy.display_name] = true
	assert(names.has("红蛇") and names.has("虎蛇"), "毒蛇山谷红蛇/虎蛇阵容丢失")
	print("SNAKE_VALLEY_REFINEMENT_PASS：2/D421/D422来源、山谷/潮湿矿洞资源、门点碰撞与红蛇虎蛇正常")
	get_tree().quit(0)
