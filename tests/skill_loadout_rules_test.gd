extends Node

const SkillLoadoutRulesScript := preload("res://scripts/skill_loadout_rules.gd")


func _ready() -> void:
	var slots: Array[String] = ["攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"]
	var learned := {"攻杀剑术": 3, "刺杀剑术": 3, "半月弯刀": 3, "烈火剑法": 3, "野蛮冲撞": 3}
	var result := SkillLoadoutRulesScript.assign_quick_slot(slots, learned, {
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "center",
		"slot_index": 1,
		"slot_id": "hud.profession_skill.2",
		"skill_id": "warrior.wild_rush",
	})
	assert(result.ok and result.changed, "已学技能无法替换指定快捷槽")
	assert(result.slots[1] == "野蛮冲撞" and result.slots[0] == "攻杀剑术", "快捷槽替换范围错误")
	assert(result.change.contract_id == "gameplay.skill.quick_slot_assignment.v1", "玩法分配结果契约不稳定")
	assert(result.change.slot_id == "player.quick_skill.2" and result.change.requested_slot_id == "hud.profession_skill.2", "玩法槽位与UI槽位映射丢失")
	var legacy := SkillLoadoutRulesScript.assign_quick_slot(slots, learned, {
		"contract_id": "ui.skill.quick_slot_assignment.v1",
		"slot_index": 2,
		"skill_name": "野蛮冲撞",
	})
	assert(legacy.ok and legacy.slots[2] == "野蛮冲撞", "旧攻击环分配请求不兼容")
	var unlearned := SkillLoadoutRulesScript.assign_quick_slot(slots, learned, {
		"contract_id": "ui.skill.button_assignment.v2",
		"slot_group": "attack_ring",
		"slot_index": 0,
		"skill_id": "wizard.lightning",
	})
	assert(not unlearned.ok and unlearned.reason == "skill_not_learned" and unlearned.slots == slots, "未学技能错误进入快捷槽")
	print("SKILL_LOADOUT_RULES_PASS：新版/旧版UI请求均可稳定替换任意已学技能槽")
	get_tree().quit(0)
