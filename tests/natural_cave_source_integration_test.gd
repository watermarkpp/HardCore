extends Node


const Catalog := preload("res://scripts/environment_catalog.gd")
const EXPECTED := {
	248: {"code": "D011", "blocked": 0.8026, "lights": 19, "doors": 0, "sha": "cfe306b793ec8b7cace580ee1efcf67e1dcbd4b98b4541855a5e070a1b33c067"},
	249: {"code": "D012", "blocked": 0.7258, "lights": 3, "doors": 12, "sha": "b6d301d103b3b6e87b1de46530913ca4c6b92c27f042bd469f356c4fb06147b2"},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for path: String in [
		"res://assets/art/maps/natural_cave/natural_cave_ground_tiles.png",
		"res://assets/art/maps/natural_cave/natural_cave_props.png",
		"res://assets/art/maps/natural_cave/natural_cave_glow.png",
		"res://assets/art/maps/natural_cave/source_masks/248_D011_walkability.png",
		"res://assets/art/maps/natural_cave/source_masks/249_D012_walkability.png",
	]:
		assert(ResourceLoader.exists(path), "天然洞穴资源缺失：%s" % path)
	var file := FileAccess.open("res://assets/data/natural_cave_source_profiles.json", FileAccess.READ)
	assert(file != null, "天然洞穴MAP来源清单缺失")
	var manifest: Variant = JSON.parse_string(file.get_as_text())
	assert(manifest is Dictionary and manifest.get("mapProfiles", {}).size() == 2, "天然洞穴来源清单格式错误")
	for map_id: int in EXPECTED:
		var expected: Dictionary = EXPECTED[map_id]
		var source: Dictionary = manifest.get("mapProfiles", {}).get(str(map_id), {})
		assert(source.get("sourceMapCode", "") == expected.code, "地图%d源MAP代码错误" % map_id)
		assert(int(source.get("width", 0)) == 400 and int(source.get("height", 0)) == 400, "地图%d源尺寸错误" % map_id)
		assert(is_equal_approx(float(source.get("blockedRatio", 0.0)), float(expected.blocked)), "地图%d阻挡比例错误" % map_id)
		assert(int(source.get("lightCells", -1)) == int(expected.lights) and int(source.get("doorCells", -1)) == int(expected.doors), "地图%d光源或门单元统计错误" % map_id)
		assert(source.get("sha256", "") == expected.sha, "地图%d原MAP哈希错误" % map_id)
		assert(int(source.get("largestWalkableComponents", [])[0].get("cells", 0)) > 30000, "地图%d最大可行走连通区异常" % map_id)
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("status", "") == "client_map_full_size" and content.get("source_map", "") == expected.code, "地图%d原尺寸运行来源未接入" % map_id)
		var profile := Catalog.get_map_profile(map_id)
		assert(profile.get("asset_set", "") == "natural_cave" and profile.get("source_map_code", "") == expected.code, "地图%d未启用天然洞穴专用资源" % map_id)
		assert(Vector2i(profile.get("source_size", Vector2i.ZERO)) == Vector2i(400, 400), "地图%d来源尺寸未进入运行配置" % map_id)
		assert(profile.get("coordinate_projection", "") == "isometric_64x32_full_size" and profile.get("world_bounds", Rect2()) == Rect2(-12768, -6384, 25536, 12768), "地图%d没有恢复400×400原尺寸" % map_id)
		assert(Catalog.validate_profile(profile, content.get("portals", [])).is_empty(), "地图%d环境配置校验失败" % map_id)
		for spawn: Dictionary in content.get("spawns", []):
			var source_coordinate: Vector2i = spawn.get("source_coordinate", Vector2i(-1, -1))
			assert(source_coordinate.x >= 0 and source_coordinate.x < 400 and source_coordinate.y >= 0 and source_coordinate.y < 400, "地图%d怪物缺少源坐标" % map_id)
			assert(not Catalog._point_blocked(spawn.position, profile), "地图%d怪物出生点被碰撞占用" % map_id)
		for portal: Dictionary in content.get("portals", []):
			assert(portal.get("source_confidence", "") == "C", "地图%d门点候选可信度未标注" % map_id)
			assert(not Catalog._point_blocked(portal.position, profile), "地图%d门点被碰撞占用" % map_id)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	# FREEZE-P0.2R: natural-cave source audit runs in explicit reference mode
	# (maps 248/249 are planned_unbuilt, not formal gameplay).
	game.reference_audit_mode = true
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in EXPECTED:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var background: WorldBackground = game.background
		assert(background.uses_natural_cave_art(), "地图%d运行时未加载天然洞穴专用资源" % map_id)
		var sizes := background.natural_cave_atlas_sizes()
		assert(Vector2i(sizes.ground) == Vector2i(512, 32) and Vector2i(sizes.props) == Vector2i(768, 128), "天然洞穴图集规格错误")
		assert(background.environment_collision_count() == int(background.environment_profile().expected_collisions), "地图%d碰撞数量错误" % map_id)
		assert(background.environment_light_count() == int(background.environment_profile().expected_lights), "地图%d灯光数量错误" % map_id)
		for portal: Dictionary in RegionContent.get_map_content(map_id).get("portals", []):
			assert(not background.is_environment_point_blocked(portal.position), "地图%d运行门点被阻挡" % map_id)
	print("NATURAL_CAVE_SOURCE_INTEGRATION_PASS：D011/D012哈希、400×400结构、专用资源、碰撞、门点与刷新落点完整")
	get_tree().quit(0)
