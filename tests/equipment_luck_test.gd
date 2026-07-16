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
	var file := FileAccess.open("res://assets/data/equipment_luck_rules.json", FileAccess.READ)
	assert(file != null, "装备幸运规则来源表缺失")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary and int(source.defaults.get("unluckyRate", 0)) == 20, "祝福油失败率来源错误")
	var luck_points: Array = source.defaults.get("luckPoints", [])
	assert(luck_points.size() == 3 and int(luck_points[0]) == 1 and int(luck_points[1]) == 3 and int(luck_points[2]) == 7 and int(source.defaults.get("maxCurse", 0)) == 10, "幸运/诅咒边界错误")

	var outcome := EquipmentRulesScript.blessing_outcome(2, 0, 2, 12, 1, 0)
	assert(outcome == {"result": "cursed", "luck": 1, "curse": 0}, "祝福油失败没有先降低幸运")
	outcome = EquipmentRulesScript.blessing_outcome(0, 0, 2, 12, 1, 0)
	assert(outcome == {"result": "cursed", "luck": 0, "curse": 1}, "零幸运失败没有增加诅咒")
	outcome = EquipmentRulesScript.blessing_outcome(0, 2, 2, 12, 0, 0)
	assert(outcome == {"result": "improved", "luck": 0, "curse": 1}, "成功路径没有优先消除诅咒")
	outcome = EquipmentRulesScript.blessing_outcome(0, 0, 2, 12, 0, 0)
	assert(outcome == {"result": "improved", "luck": 1, "curse": 0}, "幸运0没有必定提升到1")
	outcome = EquipmentRulesScript.blessing_outcome(1, 0, 2, 12, 0, 1)
	assert(int(outcome.get("luck", 0)) == 2, "幸运1—2阶段成功判定错误")
	outcome = EquipmentRulesScript.blessing_outcome(7, 0, 2, 12, 0, 1)
	assert(outcome.get("result", "") == "ineffective" and int(outcome.get("luck", 0)) == 7, "幸运上限没有保持7")

	var neutral_rng := RandomNumberGenerator.new()
	var lucky_rng := RandomNumberGenerator.new()
	var cursed_rng := RandomNumberGenerator.new()
	neutral_rng.seed = 176
	lucky_rng.seed = 176
	cursed_rng.seed = 176
	var neutral_total := 0
	var lucky_total := 0
	var cursed_total := 0
	for index in range(512):
		neutral_total += WarriorCombatMath.roll_attack_power(2, 12, 0, neutral_rng)
		lucky_total += WarriorCombatMath.roll_attack_power(2, 12, 9, lucky_rng)
		cursed_total += WarriorCombatMath.roll_attack_power(2, 12, -9, cursed_rng)
	assert(lucky_total == 12 * 512 and cursed_total == 2 * 512, "幸运9/诅咒9没有稳定命中上下限")
	assert(cursed_total < neutral_total and neutral_total < lucky_total, "固定种子攻击分布顺序错误")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.add_item("祝福油", 2)
	var oil_index := _inventory_index("祝福油")
	assert(PlayerState.use_inventory_index(oil_index) == "需要先装备武器", "未装备武器时祝福油提示错误")
	assert(PlayerState.has_item("祝福油", 2), "未装备武器却消耗了祝福油")
	PlayerState.add_item("木剑")
	assert(PlayerState.equip_inventory_index(_inventory_index("木剑")).begins_with("已装备"), "祝福油测试武器穿戴失败")
	var weapon: Dictionary = PlayerState.equipment["武器"]
	assert(weapon.has("weapon_luck") and weapon.has("weapon_curse"), "武器实例没有幸运/诅咒字段")
	assert(PlayerState.apply_blessing_oil_with_rolls(0, 0).begins_with("祝福油生效"), "武器幸运0提升失败")
	assert(int(weapon.get("weapon_luck", 0)) == 1 and int(PlayerState.computed_stats.get("luck", 0)) == 1, "实例幸运没有进入人物攻击分布")
	PlayerState.damage_equipment_durability("武器", int(weapon.get("max_durability", 1)))
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 0 and int(weapon.get("weapon_luck", 0)) == 1, "零耐久未禁用幸运或错误清除实例幸运")
	PlayerState.gold = PlayerState.repair_cost()
	PlayerState.repair_all_equipment()
	assert(int(PlayerState.computed_stats.get("luck", 0)) == 1, "维修后实例幸运没有恢复参与结算")
	assert(PlayerState.use_inventory_index(_inventory_index("祝福油")).begins_with("使用"), "装备武器后祝福油没有正常消耗")
	assert(PlayerState.has_item("祝福油", 1), "祝福油消耗数量错误")

	var panel := InventoryPanel.new()
	add_child(panel)
	await get_tree().process_frame
	assert("幸运+1" in panel.equipment_label.text, "装备面板没有显示武器幸运")

	print("EQUIPMENT_LUCK_PASS：祝福油状态机、实例存储、零耐久隔离、固定种子攻击分布与界面提示正常")
	get_tree().quit(0)
