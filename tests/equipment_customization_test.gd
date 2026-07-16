extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(FileAccess.file_exists("res://assets/data/equipment_customization.json"), "装备自定义配置文件缺失")
	assert(FileAccess.file_exists("res://docs/装备自定义指南.md"), "装备自定义指南缺失")
	assert(int(GameData.equipment_customization.get("schemaVersion", 0)) == 1, "装备自定义配置版本错误")
	assert(GameData.equipment_customization.get("supportedSpecialEffectIds", []).size() == 8, "通用特殊效果ID清单不完整")

	var shield_ring := GameData.get_item("护身戒指")
	assert(bool(shield_ring.get("customized", false)), "现有装备覆盖没有进入运行目录")
	assert(shield_ring.get("specialEffect", {}).get("id", "") == "magic_shield", "特殊效果没有由配置文件驱动")
	var magic_ring := GameData.get_item("魔血戒指")
	assert(magic_ring.get("profession", "") == "通用" and int(magic_ring.get("setPiece", {}).get("power", 0)) == 25, "套装职业与power覆盖没有进入运行目录")

	var base: Array = [
		{"name": "旧剑", "category": "武器", "profession": "战士", "attackMin": 1, "attackMax": 2, "durability": 3},
		{"name": "删除戒指", "category": "戒指", "profession": "通用", "durability": 1},
	]
	var customization := {
		"overrides": {
			"旧剑": {"fields": {"attackMin": 9, "attackMax": 18, "hpBonus": 30, "maxDurability": 20}},
			"删除戒指": {"enabled": false},
		},
		"newEquipment": [
			{"name": "自定义神剑", "category": "武器", "profession": "通用", "maxDurability": 30, "attackMin": 20, "attackMax": 40, "specialEffect": {"id": "stealth", "runtime": true}},
			{"name": "无效类别", "category": "翅膀", "profession": "通用", "maxDurability": 1},
		],
	}
	var customized := GameData.apply_equipment_customization(base, customization)
	assert(customized.size() == 2, "禁用装备或无效新增装备没有被正确过滤")
	assert(customized[0].get("name", "") == "旧剑" and int(customized[0].get("attackMax", 0)) == 18, "现有装备属性覆盖失败")
	assert(int(customized[0].get("hpBonus", 0)) == 30 and int(customized[0].get("maxDurability", 0)) == 20, "扩展属性或最大耐久覆盖失败")
	assert(customized[1].get("name", "") == "自定义神剑" and bool(customized[1].get("customized", false)), "新增装备没有进入结果")
	assert(customized[1].get("specialEffect", {}).get("id", "") == "stealth", "新增装备特殊效果配置丢失")

	print("EQUIPMENT_CUSTOMIZATION_PASS：现有装备覆盖、新增、禁用、属性扩展、特殊效果与套装参数均由配置驱动")
	get_tree().quit(0)
