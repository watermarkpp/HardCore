extends Node


const Catalog := preload("res://scripts/environment_catalog.gd")
const EXPECTED := {
	217: {"code": "D001", "blocked": 0.6908, "lights": 32, "doors": 0, "sha": "0047842a53a4806562746f6580859b3b06e2d64a7c4bfeb1ead40831bea2fa24"},
	218: {"code": "D002", "blocked": 0.8241, "lights": 19, "doors": 12, "sha": "ab03734fdc35327cee0f663eb5a020ff69d453e4d3e565483be81521cc7fbe3f"},
	221: {"code": "D003", "blocked": 0.6788, "lights": 31, "doors": 0, "sha": "46f18a27b58bbf76087ddf4df679717beea06eafbe6c19de854fbc0a6cb79d81"},
}


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	for path: String in [
		"res://assets/art/maps/orc_tomb/orc_tomb_ground_tiles.png",
		"res://assets/art/maps/orc_tomb/orc_tomb_props.png",
		"res://assets/art/maps/orc_tomb/orc_tomb_fire_glow.png",
		"res://assets/art/maps/orc_tomb/source_masks/217_D001_walkability.png",
		"res://assets/art/maps/orc_tomb/source_masks/218_D002_walkability.png",
		"res://assets/art/maps/orc_tomb/source_masks/221_D003_walkability.png",
	]:
		assert(ResourceLoader.exists(path), "兽人古墓客户端资源缺失：%s" % path)
	var file := FileAccess.open("res://assets/data/orc_tomb_source_profiles.json", FileAccess.READ)
	assert(file != null, "兽人古墓MAP来源清单缺失")
	var manifest: Variant = JSON.parse_string(file.get_as_text())
	assert(manifest is Dictionary and manifest.get("mapProfiles", {}).size() == 3, "兽人古墓来源清单格式错误")
	for map_id: int in EXPECTED:
		var expected: Dictionary = EXPECTED[map_id]
		var source: Dictionary = manifest.get("mapProfiles", {}).get(str(map_id), {})
		assert(source.get("sourceMapCode", "") == expected.code, "地图%d源MAP代码错误" % map_id)
		assert(int(source.get("width", 0)) == 400 and int(source.get("height", 0)) == 400, "地图%d源尺寸错误" % map_id)
		assert(source.get("sha256", "") == expected.sha, "地图%d原MAP哈希错误" % map_id)
		assert(is_equal_approx(float(source.get("blockedRatio", 0.0)), float(expected.blocked)), "地图%d阻挡比例错误" % map_id)
		assert(int(source.get("lightCells", -1)) == int(expected.lights) and int(source.get("doorCells", -1)) == int(expected.doors), "地图%d光源或门单元统计错误" % map_id)
		assert(int(source.get("largestWalkableComponents", [])[0].get("cells", 0)) > 28000, "地图%d最大连通区异常" % map_id)
		var content := RegionContent.get_map_content(map_id)
		assert(content.get("status", "") == "client_map_full_size" and content.get("source_map", "") == expected.code, "地图%d原尺寸运行来源未接入" % map_id)
		var profile := Catalog.get_map_profile(map_id)
		assert(profile.get("source_map_code", "") == expected.code and profile.get("ground_style", "") == "orc_tomb_client", "地图%d未启用客户端古墓配置" % map_id)
		assert(profile.get("coordinate_projection", "") == "isometric_64x32_full_size" and profile.get("world_bounds", Rect2()) == Rect2(-12768, -6384, 25536, 12768), "地图%d没有恢复400×400原尺寸" % map_id)
		assert(Catalog.validate_profile(profile, content.get("portals", [])).is_empty(), "地图%d环境配置校验失败" % map_id)
		for spawn: Dictionary in content.get("spawns", []):
			var source_coordinate: Vector2i = spawn.get("source_coordinate", Vector2i(-1, -1))
			assert(source_coordinate.x >= 0 and source_coordinate.x < 400 and source_coordinate.y >= 0 and source_coordinate.y < 400, "地图%d怪物缺少源坐标" % map_id)
			assert(not Catalog._point_blocked(spawn.position, profile), "地图%d怪物出生点被碰撞占用" % map_id)
		for boss: Dictionary in content.get("bosses", []):
			assert(not Catalog._point_blocked(boss.position, profile), "地图%d Boss出生点被碰撞占用" % map_id)
			for direction: Vector2 in [Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2.UP]:
				assert(not Catalog._point_blocked(boss.position + direction * 145.0, profile), "地图%d Boss躲避空间被阻挡" % map_id)
		for portal: Dictionary in content.get("portals", []):
			assert(portal.get("source_confidence", "") == "C" and not Catalog._point_blocked(portal.position, profile), "地图%d门点可信度或安全区错误" % map_id)

	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	for map_id: int in EXPECTED:
		game.travel_to_map(map_id)
		await get_tree().process_frame
		await get_tree().process_frame
		var background: WorldBackground = game.background
		assert(background.uses_orc_tomb_art() and background.environment_source_map_code() == EXPECTED[map_id].code, "地图%d运行时客户端古墓资源未加载" % map_id)
		assert(background.orc_tomb_ground_atlas_size() == Vector2i(512, 32) and background.orc_tomb_prop_atlas_size() == Vector2i(768, 128), "兽人古墓图集规格错误")
		assert(background.editor_runtime_ground_ready(), "地图%d编辑器尺寸地表未加载" % map_id)
		assert(background.editor_runtime_chunk_texture_count() == 5, "地图%d正式编辑器地表块未完整加载" % map_id)
		assert(not background.uses_editor_runtime_fallback_ground(), "地图%d错误回退到旧兽人古墓地表" % map_id)
		assert(background._editor_runtime_size == Vector2i(38, 38), "地图%d仍混用旧400x400运行碰撞" % map_id)
		assert(background.source_collision_mask_size() == Vector2i.ZERO, "地图%d仍加载旧MAP阻挡图" % map_id)
		assert(background.source_collision_shape_count() >= 4, "地图%d编辑器阻挡网格或硬边界缺失" % map_id)
		assert(not background.is_environment_point_blocked(game.player.global_position), "地图%d出生点不可行走" % map_id)
	print("ORC_TOMB_SOURCE_INTEGRATION_PASS：D001—D003哈希、400×400结构、专用资源、碰撞、门点、刷新和Boss空间完整")
	get_tree().quit(0)
