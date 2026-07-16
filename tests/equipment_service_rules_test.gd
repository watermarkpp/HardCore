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
	var file := FileAccess.open("res://assets/data/equipment_service_rules.json", FileAccess.READ)
	assert(file != null, "装备服务端规则来源表缺失")
	var source: Variant = JSON.parse_string(file.get_as_text())
	assert(source is Dictionary, "装备服务端规则来源表格式错误")
	assert(int(source.catalogCoverage.get("equipmentRecords", 0)) == 175, "175件装备没有进入来源覆盖统计")
	assert(int(source.catalogCoverage.get("concreteStdItemsRecords", -1)) == 172, "锁定StdItems逐件覆盖数错误")
	assert(source.get("missing", []) == ["落魄神兵", "辟邪手镯", "黑铁手套"], "无同名StdItems记录没有保持隔离")
	assert(source.fieldSemantics.Need == {"0": "等级", "1": "攻击上限", "2": "魔法上限", "3": "道术上限"}, "Need 0—3源码语义错误")

	assert(EquipmentRulesScript.max_wear_weight("战士", 20) == 35, "战士穿戴重量公式错误")
	assert(EquipmentRulesScript.max_hand_weight("战士", 20) == 43, "战士手持重量公式错误")
	assert(EquipmentRulesScript.max_wear_weight("法师", 20) == 19, "法师穿戴重量公式错误")
	assert(EquipmentRulesScript.max_hand_weight("道士", 20) == 22, "道士手持重量公式错误")

	var level_item := {"reqLevel": 10, "confidence": "B"}
	var attack_item := {"reqAttack": 20, "confidence": "B"}
	var magic_item := {"serviceNeed": 2, "serviceNeedLevel": 18}
	var tao_item := {"serviceNeed": 3, "serviceNeedLevel": 16}
	assert(EquipmentRulesScript.requirement_error(level_item, 9, {}) == "需要等级10", "等级需求判断错误")
	assert(EquipmentRulesScript.requirement_error(attack_item, 50, {"attack_max": 19}) == "需要攻击20", "攻击需求判断错误")
	assert(EquipmentRulesScript.requirement_error(magic_item, 50, {"magic_max": 18}).is_empty(), "服务端魔法需求判断错误")
	assert(EquipmentRulesScript.requirement_error(tao_item, 50, {"tao_max": 15}) == "需要道术16", "服务端道术需求判断错误")

	var wood_sword := GameData.get_item_record("木剑")
	assert(wood_sword.has("serviceRequirement") and wood_sword.get("concreteStdItemsStatus", "") == "已接入", "装备目录没有接入锁定StdItems值")
	assert(str(wood_sword.serviceRequirement.get("source", "")) == "服务端StdItems", "精确Need没有进入统一装备规则")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.level = 50
	PlayerState.recalculate_stats()
	PlayerState.add_item("怒斩")
	var result := PlayerState.equip_inventory_index(_inventory_index("怒斩"))
	assert(result == "需要攻击46", "Need=攻击的现有候选字段没有进入统一穿戴判定")
	PlayerState.add_item("重盔甲(女)")
	result = PlayerState.equip_inventory_index(_inventory_index("重盔甲(女)"))
	assert(result == "该装备仅限女性角色", "衣服性别判定没有接入")
	assert(int(PlayerState.computed_stats.get("max_wear_weight", 0)) == EquipmentRulesScript.max_wear_weight("战士", 50), "属性面板没有接入穿戴重量上限")
	assert(int(PlayerState.computed_stats.get("max_hand_weight", 0)) == EquipmentRulesScript.max_hand_weight("战士", 50), "属性面板没有接入手持重量上限")

	print("EQUIPMENT_SERVICE_RULES_PASS：172件StdItems、Need 0—3、职业重量、性别与缺名隔离正常")
	get_tree().quit(0)
