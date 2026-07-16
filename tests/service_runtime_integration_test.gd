extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	_expect(GameData.service_home_map_id(false) == 0, "默认出生地图未读取服务端HomeMap")
	_expect(GameData.service_home_runtime_map_id(false) == 4, "服务端HomeMap=0没有映射到比奇运行地图4")
	_expect(int(GameData.get_service_map_by_id(0).get("mapId", -1)) == 4, "服务端地图0别名无法读取比奇省资料")
	_expect(GameData.service_home_point(false) == Vector2i(289, 618), "默认出生坐标未读取服务端HomeX/HomeY")
	_expect(GameData.service_home_map_id(true) == 3, "红名回城地图未读取服务端RedHomeMap")
	_expect(GameData.service_home_point(true) == Vector2i(845, 674), "红名回城坐标未读取服务端RedHomeX/RedHomeY")
	_expect(GameData.service_exp_to_next_level(1) == 100, "服务端运行时经验表1级错误")
	_expect(GameData.service_exp_to_next_level(23) == 350000, "服务端运行时经验表23级错误")
	_expect(GameData.service_exp_to_next_level(40) == 12000000, "服务端运行时经验表40级错误")
	PlayerState.level = 20
	var warrior_name := ProfessionRules.PROFESSIONS[0]
	var wizard_name := ProfessionRules.PROFESSIONS[1]
	var tao_name := ProfessionRules.PROFESSIONS[2]
	PlayerState.select_profession(warrior_name)
	PlayerState.recalculate_stats()
	var warrior_hp := int(PlayerState.computed_stats.get("max_hp", 0))
	var warrior_mp := int(PlayerState.computed_stats.get("max_mp", 0))
	_expect(warrior_hp == 224 and warrior_mp == 81, "战士HP/MP未按服务端公式计算：%d/%d" % [warrior_hp, warrior_mp])
	PlayerState.select_profession(wizard_name)
	PlayerState.recalculate_stats()
	var wizard_hp := int(PlayerState.computed_stats.get("max_hp", 0))
	var wizard_mp := int(PlayerState.computed_stats.get("max_mp", 0))
	_expect(wizard_hp == 77 and wizard_mp == 277, "法师HP/MP未按服务端公式计算：%d/%d" % [wizard_hp, wizard_mp])
	PlayerState.select_profession(tao_name)
	PlayerState.recalculate_stats()
	var tao_hp := int(PlayerState.computed_stats.get("max_hp", 0))
	var tao_mp := int(PlayerState.computed_stats.get("max_mp", 0))
	_expect(tao_hp == 131 and tao_mp == 123, "道士HP/MP未按服务端公式计算：%d/%d" % [tao_hp, tao_mp])
	_expect(warrior_hp > tao_hp and tao_hp > wizard_hp, "三职业HP成长顺序异常")
	_expect(wizard_mp > tao_mp and tao_mp > warrior_mp, "三职业MP成长顺序异常")
	_expect(GameData.get_map_by_id(GameData.service_home_map_id(true)).is_empty(), "当前测试前提变化：RedHomeMap=3已入库，应更新红名回城测试")
	print("SERVICE_RUNTIME_INTEGRATION_PASS：服务端出生点、HomeMap=0别名、经验表与职业成长已接入运行时")
	get_tree().quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error(message)
	print("SERVICE_RUNTIME_INTEGRATION_FAIL：" + message)
	get_tree().quit(1)
