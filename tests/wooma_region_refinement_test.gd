extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const MAPS := [268, 1506, 1507]
const SOURCES := {268: "1", 1506: "E001", 1507: "E002"}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for path: String in [
		"res://assets/art/maps/wooma_region/wooma_forest_ground_tiles.png",
		"res://assets/art/maps/wooma_region/wooma_forest_props.png",
		"res://assets/art/maps/wooma_region/wooma_cave_ground_tiles.png",
		"res://assets/art/maps/wooma_region/wooma_cave_props.png",
		"res://assets/art/maps/wooma_region/wooma_cave_glow.png",
	]:
		assert(ResourceLoader.exists(path), "沃玛区域专用资源缺失：%s" % path)
	var file := FileAccess.open("res://assets/data/wooma_region_source_profiles.json", FileAccess.READ)
	assert(file != null, "沃玛区域MAP解析清单缺失")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary and parsed.get("mapProfiles", {}).size() == 3, "沃玛区域MAP解析数量错误")
	for map_id: int in MAPS:
		var profile := Catalog.get_map_profile(map_id)
		assert(profile.get("source_map_code", "") == SOURCES[map_id], "地图%d客户端MAP映射错误" % map_id)
		assert(str(profile.get("source_evidence", "")).contains("客户端MAP"), "地图%d缺少客户端来源证据" % map_id)
		assert(profile.get("props", []).size() >= 9, "地图%d场景物件不足" % map_id)
		assert(int(profile.get("prop_count_override", 0)) == 8, "地图%d未启用专用8格物件图集" % map_id)
		if map_id == 268:
			assert(profile.get("asset_set", "") == "wooma_forest" and profile.get("theme", "") == "surface", "沃玛森林资源主题错误")
		else:
			assert(profile.get("asset_set", "") == "wooma_cave" and profile.get("theme", "") == "cave", "沃玛洞穴资源主题错误")
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
		assert(background.uses_wooma_forest_art() if map_id == 268 else background.uses_wooma_cave_art(), "地图%d运行时专用资源未加载" % map_id)
		var sizes := background.wooma_region_atlas_sizes()
		assert(Vector2i(sizes.forest_ground) == Vector2i(512, 32) and Vector2i(sizes.forest_props) == Vector2i(768, 128), "森林图集规格错误")
		assert(Vector2i(sizes.cave_ground) == Vector2i(512, 32) and Vector2i(sizes.cave_props) == Vector2i(768, 128), "自然洞穴图集规格错误")
		assert(background.environment_collision_count() == int(background.environment_profile().expected_collisions), "地图%d碰撞数量错误" % map_id)
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not background.is_environment_point_blocked(portal.position), "地图%d运行时门点被阻挡" % map_id)
	game.travel_to_map(315)
	await get_tree().process_frame
	await get_tree().process_frame
	var boss_count := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor and enemy.is_boss:
			boss_count += 1
	assert(boss_count == 2, "沃玛区域精修破坏寺庙双Boss")
	print("WOOMA_REGION_REFINEMENT_PASS：1/E001/E002来源、森林/洞穴专用资源、门点碰撞与完整沃玛链正常")
	get_tree().quit(0)
