extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var profile := EnvironmentCatalog.get_map_profile(4)
	assert(profile.get("source_map_code", "") == "0", "比奇省未标记客户端0.map来源")
	assert(profile.get("source_size", Vector2i.ZERO) == Vector2i(700, 700), "0.map尺寸解析错误")
	assert(is_equal_approx(float(profile.get("blocked_ratio", 0.0)), 0.3318), "0.map阻挡率解析错误")
	assert(int(profile.get("source_lights", 0)) == 85 and int(profile.get("source_doors", 0)) == 182, "0.map灯光或门格统计错误")
	assert(int(profile.get("service_map_id", -1)) == 0, "比奇运行地图未保留服务端地图号0")
	assert(profile.get("service_home_coordinate", Vector2i.ZERO) == Vector2i(289, 618), "服务端出生坐标未进入环境来源配置")
	assert(profile.get("coordinate_projection", "") == "isometric_64x32_full_size", "比奇省仍在使用压缩坐标")
	assert(profile.get("runtime_home_position", Vector2.ZERO) == Vector2(-10528, 3328), "服务端出生点没有按原MAP尺寸映射")
	assert(profile.get("world_bounds", Rect2()) == Rect2(-22368, -11184, 44736, 22368), "700×700地图世界边界错误")

	var file := FileAccess.open("res://assets/data/bich_source_profiles.json", FileAccess.READ)
	assert(file != null, "比奇客户端来源画像不存在")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "比奇客户端来源画像不是有效JSON")
	var maps: Dictionary = parsed.get("mapProfiles", {})
	assert(int(maps.get("0", {}).get("width", 0)) == 700, "来源画像缺少0.map")
	assert(int(maps.get("0100", {}).get("width", 0)) == 15 and int(maps.get("0100", {}).get("height", 0)) == 18, "0100室内图尺寸错误")
	assert("小型室内图" in str(maps.get("0100", {}).get("name", "")), "0100仍被错误标成整座比奇城")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var game: Node = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame
	await get_tree().process_frame
	assert(game.current_map_id == 4 and game.current_zone == "比奇省", "游戏启动未进入服务端HomeMap=0映射")
	assert(game.player.global_position == MapEditorRuntimeBridge.home_screen_position_px(), "游戏启动未落到当前实际复活/回城锚点")
	assert(game.background.environment_source_map_code() == "0", "运行时背景丢失0.map来源")
	assert(RegionContent.get_map_content(4).get("status", "") == "client_map_full_size", "比奇省运行内容仍标为垂直切片")
	print("BICH_SOURCE_MAP_INTEGRATION_PASS：0.map 700×700原尺寸、HomeMap坐标与运行地图4统一映射")
	get_tree().quit(0)
