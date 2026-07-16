extends Node

const EquipmentRulesScript = preload("res://scripts/equipment_rules.gd")


func _ready() -> void:
	_run.call_deferred()


func _inventory_index(item_name: String) -> int:
	for index in range(PlayerState.inventory.size()):
		if str(PlayerState.inventory[index].get("name", "")) == item_name:
			return index
	return -1


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	var wood_sword: Dictionary = GameData.get_item("木剑")
	wood_sword["modifiers"] = {
		"criticalChance": 0.25,
		"criticalDamageBonus": 0.75,
		"attackSpeedPercent": 0.20,
		"castSpeedPercent": 0.25,
		"skillLevels": {"all": 1, "烈火剑法": 2},
	}
	PlayerState.learned_skills = {"烈火剑法": 0}
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "扩展词条测试武器穿戴失败")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("critical_chance", 0.0)), 0.25), "暴击率词条没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("critical_damage_multiplier", 0.0)), 2.25), "暴击倍率词条没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("attack_speed_percent", 0.0)), 0.20), "攻击速度词条没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("cast_speed_percent", 0.0)), 0.25), "施法速度词条没有聚合")
	assert(PlayerState.effective_skill_level("烈火剑法") == 3 and PlayerState.effective_skill_level("攻杀剑术") == 1, "指定/全技能等级词条没有叠加")
	assert(EquipmentRulesScript.critical_succeeds(0.25, 0.249) and not EquipmentRulesScript.critical_succeeds(0.25, 0.25), "暴击边界判断错误")
	assert(EquipmentRulesScript.critical_damage(100, 2.25) == 225, "暴击伤害计算错误")

	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	assert(is_equal_approx(player._attack_speed_multiplier, 1.20) and is_equal_approx(player._cast_speed_multiplier, 1.25), "速度词条没有进入角色运行参数")
	assert(player.request_attack(), "速度词条测试攻击无法启动")
	assert(is_equal_approx(player._attack_timer, 0.85 / 1.20), "攻击速度没有缩短850ms间隔")
	assert(is_equal_approx(player._attack_action_timer, 0.51 / 1.20), "攻击速度没有缩短510ms动作")

	var weapon: Dictionary = PlayerState.equipment["武器"]
	PlayerState.damage_equipment_durability("武器", int(weapon.get("max_durability", 1)))
	assert(float(PlayerState.computed_stats.get("critical_chance", 1.0)) == 0.0, "零耐久装备仍提供扩展词条")
	assert(is_equal_approx(player._attack_speed_multiplier, 1.0) and is_equal_approx(player._cast_speed_multiplier, 1.0), "零耐久后速度词条没有撤销")

	print("EQUIPMENT_FUTURE_MODIFIERS_PASS：暴击、攻速、施法速度、技能等级和零耐久撤销均支持数据扩展")
	get_tree().quit(0)
