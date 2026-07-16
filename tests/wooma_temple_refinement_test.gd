extends Node

const Catalog := preload("res://scripts/environment_catalog.gd")
const MAPS := [312, 313, 314, 315]
const SOURCES := {312: "D021", 313: "D022", 314: "D023", 315: "D024"}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for path: String in [
		"res://assets/art/maps/wooma_temple/wooma_temple_ground_tiles.png",
		"res://assets/art/maps/wooma_temple/wooma_temple_props.png",
		"res://assets/art/maps/wooma_temple/wooma_temple_fire_glow.png",
	]:
		assert(ResourceLoader.exists(path), "沃玛寺庙资源缺失：%s" % path)
	var source_file := FileAccess.open("res://assets/data/wooma_temple_source_profiles.json", FileAccess.READ)
	assert(source_file != null, "沃玛寺庙客户端MAP解析清单缺失")
	var parsed: Variant = JSON.parse_string(source_file.get_as_text())
	assert(parsed is Dictionary and parsed.get("mapProfiles", {}).size() == 4, "沃玛寺庙MAP解析数量错误")
	var signatures := {}
	for map_id: int in MAPS:
		var profile := Catalog.get_map_profile(map_id)
		assert(profile.get("theme", "") == "temple", "地图%d主题错误" % map_id)
		assert(profile.get("source_map_code", "") == SOURCES[map_id], "地图%d客户端MAP映射错误" % map_id)
		assert(str(profile.get("source_evidence", "")).contains("客户端MAP"), "地图%d缺少来源证据" % map_id)
		assert(profile.get("props", []).size() >= 8, "地图%d专用寺庙物件不足" % map_id)
		var signature := str(profile.get("layout_hubs", []))
		assert(not signatures.has(signature), "地图%d仍复用完全相同的布局" % map_id)
		signatures[signature] = true
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not Catalog._point_blocked(portal.position, profile), "地图%d门点被碰撞占用" % map_id)
	assert(not Catalog.get_map_profile(315).get("arena", {}).is_empty(), "教主大厅缺少Boss竞技场结构")

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in MAPS:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var background: WorldBackground = game.background
		assert(background.uses_wooma_temple_art(), "地图%d运行时未加载沃玛寺庙专用资源" % map_id)
		assert(background.environment_source_map_code() == SOURCES[map_id], "地图%d运行时来源映射丢失" % map_id)
		assert(background.wooma_temple_ground_atlas_size() == Vector2i(512, 32), "寺庙地砖图集规格错误")
		assert(background.wooma_temple_prop_atlas_size() == Vector2i(768, 128), "寺庙物件图集规格错误")
		assert(background.environment_collision_count() == int(background.environment_profile().expected_collisions), "地图%d碰撞数量错误" % map_id)
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not background.is_environment_point_blocked(portal.position), "地图%d运行时门点被阻挡" % map_id)
	game.travel_to_map(315)
	await get_tree().process_frame
	await get_tree().process_frame
	var bosses := 0
	for enemy: Node in get_tree().get_nodes_in_group("enemies"):
		if enemy is EnemyActor and enemy.is_boss:
			bosses += 1
	assert(bosses == 2, "寺庙精修破坏沃玛卫士/沃玛教主双Boss配置")
	print("WOOMA_TEMPLE_REFINEMENT_PASS：D021—D024来源、四图独立线路、寺庙专用资源、碰撞门点与双Boss正常")
	get_tree().quit(0)

