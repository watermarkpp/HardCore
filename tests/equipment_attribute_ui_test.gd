extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var panel := InventoryPanel.new()

	var total_stats_text := panel._character_stats_text({
		"max_hp": 100,
		"max_mp": 50,
		"attack_min": 1,
		"attack_max": 2,
		"magic_min": 0,
		"magic_max": 0,
		"tao_min": 0,
		"tao_max": 0,
		"defense_min": 0,
		"defense_max": 1,
		"magic_defense_min": 0,
		"magic_defense_max": 1,
		"accuracy": 12,
		"agility": 18,
		"luck": 0,
		"magic_evasion_percent": 40,
		"attack_speed_tier": 4,
		"critical_chance": 0.0,
		"wear_weight": 0,
		"max_wear_weight": 100,
	})
	assert("准确 12" in total_stats_text, "人物总属性没有显示准确点数")
	assert("敏捷 18" in total_stats_text, "人物总属性没有显示敏捷点数")
	assert("魔法躲避 40%" in total_stats_text, "人物总属性没有按显示百分比呈现魔法躲避")
	assert("攻击速度 +4" in total_stats_text, "人物总属性没有按档位呈现攻击速度")
	assert("攻速" not in total_stats_text and "攻击速度 +4%" not in total_stats_text, "人物总属性仍把攻击速度显示为百分比")

	var item_stats_text := panel._advanced_stat_line({
		"accuracy": 2,
		"agility": 3,
		"magicEvasionPercent": 20,
		"magicEvasionPoints": 2,
		"attackSpeedTier": 2,
	})
	assert("准确 +2" in item_stats_text, "物品详情没有显示准确点数")
	assert("敏捷 +3" in item_stats_text, "物品详情没有显示敏捷点数")
	assert("魔法躲避 +20%" in item_stats_text, "物品详情没有读取 magicEvasionPercent")
	assert("攻击速度 +2" in item_stats_text, "物品详情没有读取 attackSpeedTier")
	assert("攻击速度 +2%" not in item_stats_text, "物品详情错误地把攻击速度档位显示为百分比")
	assert("magicEvasionPoints" not in item_stats_text, "物品详情不应泄露内部魔法躲避点")

	panel.free()
	print("EQUIPMENT_ATTRIBUTE_UI_PASS：装备属性 v2 的魔法躲避、准确、敏捷与攻击速度显示单位正确")
	get_tree().quit(0)
