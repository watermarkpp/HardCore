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
	PlayerState.learned_skills = {"烈火剑法": 0}
	PlayerState.add_item("木剑")
	var weapon_index := _inventory_index("木剑")
	PlayerState.inventory[weapon_index]["modifiers"] = {
		"criticalChance": 0.25,
		"criticalDamageBonus": 0.75,
		"attackSpeedTier": 2,
		"attackSpeedPercent": 0.20,
		"castSpeedPercent": 0.25,
		"skillLevels": {"all": 1, "烈火剑法": 2},
	}
	assert(PlayerState.equip_inventory_index(weapon_index).begins_with("已装备"), "扩展词条测试武器穿戴失败")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("critical_chance", 0.0)), 0.25), "暴击率词条没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("critical_damage_multiplier", 0.0)), 2.25), "暴击倍率词条没有聚合")
	assert(int(PlayerState.computed_stats.get("attack_speed_tier", 0)) == 2, "物理攻速档位没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("attack_speed_percent", 0.0)), 0.20), "旧百分比攻速兼容字段没有聚合")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("cast_speed_percent", 0.0)), 0.25), "施法速度词条没有聚合")
	assert(PlayerState.effective_skill_level("烈火剑法") == 3 and PlayerState.effective_skill_level("攻杀剑术") == 0, "指定/全技能等级词条叠加或未学技能加成错误")
	assert(EquipmentRulesScript.critical_succeeds(0.25, 0.249) and not EquipmentRulesScript.critical_succeeds(0.25, 0.25), "暴击边界判断错误")
	assert(EquipmentRulesScript.critical_damage(100, 2.25) == 225, "暴击伤害计算错误")

	var player := PlayerCharacter.new()
	add_child(player)
	await get_tree().process_frame
	var expected_attack_interval := float(maxi(0, 900 - 2 * 60)) / 1000.0
	assert(int(player.get("_attack_speed_tier")) == 2, "物理攻速档位没有进入角色运行参数")
	assert(is_equal_approx(player.attack_cooldown, expected_attack_interval), "物理攻击间隔没有按max(0,900-tier*60)/1000计算")
	assert(is_equal_approx(player._cast_speed_multiplier, 1.25), "施法速度没有保持独立运行参数")
	assert(player.request_attack(), "速度词条测试攻击无法启动")
	assert(is_equal_approx(player._attack_timer, expected_attack_interval), "旧百分比攻速不应再次缩放物理攻击间隔")
	assert(is_equal_approx(player._attack_action_timer, 0.51), "物理攻速档位不应缩放攻击动作时长")

	var weapon: Dictionary = PlayerState.equipment["武器"]
	PlayerState.damage_equipment_durability("武器", int(weapon.get("max_durability", 1)))
	assert(float(PlayerState.computed_stats.get("critical_chance", 1.0)) == 0.0, "零耐久装备仍提供扩展词条")
	assert(int(PlayerState.computed_stats.get("attack_speed_tier", -1)) == 0, "零耐久后物理攻速档位没有撤销")
	assert(is_equal_approx(float(PlayerState.computed_stats.get("attack_speed_percent", -1.0)), 0.0), "零耐久后旧百分比攻速字段没有撤销")
	assert(int(player.get("_attack_speed_tier")) == 0 and is_equal_approx(player.attack_cooldown, 0.9), "零耐久后物理攻击间隔没有恢复到900ms")
	assert(is_equal_approx(player._cast_speed_multiplier, 1.0), "零耐久后施法速度词条没有撤销")
	assert(PlayerState.effective_skill_level("烈火剑法") == 0, "零耐久装备仍提供技能等级加成")

	print("EQUIPMENT_FUTURE_MODIFIERS_PASS：物理攻速档位、旧百分比隔离、施法速度独立和零耐久撤销均通过")
	get_tree().quit(0)
