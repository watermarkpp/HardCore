extends Node


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	assert(WarriorCombatMath.BASE_HIT == 5 and WarriorCombatMath.BASE_AGILITY == 15, "服务端基础准确/敏捷常量错误")
	assert(WarriorCombatMath.basic_sword_accuracy_bonus(0) == 0, "0级基本剑术不应额外加准确")
	assert(WarriorCombatMath.basic_sword_accuracy_bonus(3) == 9, "3级基本剑术应加9准确")
	assert(WarriorCombatMath.slaying_accuracy_bonus(3) == 3, "3级攻杀应加3准确")
	assert([0, 1, 2, 3].map(WarriorCombatMath.slaying_proc_cycle) == [7, 6, 5, 4], "攻杀触发分母错误")
	assert([0, 1, 2, 3].map(WarriorCombatMath.slaying_flat_damage_bonus) == [2, 4, 6, 8], "攻杀附加伤害表错误")
	assert(WarriorCombatMath.slaying_damage(20, 0) == 22 and WarriorCombatMath.slaying_damage(20, 3) == 28, "攻杀最终附加伤害错误")
	assert(WarriorCombatMath.thrust_secondary_damage(100, 0) == 40 and WarriorCombatMath.thrust_secondary_damage(100, 3) == 100, "刺杀第二格伤害错误")
	assert(WarriorCombatMath.half_moon_secondary_damage(130, 0) == 20 and WarriorCombatMath.half_moon_secondary_damage(130, 3) == 50, "半月侧向伤害错误")
	assert(WarriorCombatMath.fire_sword_damage(100, 0) == 140 and WarriorCombatMath.fire_sword_damage(100, 3) == 260, "烈火逐级伤害错误")
	assert(WarriorCombatMath.wild_rush_success_threshold(0, 20, 20) == 0, "野蛮不能推动同级目标")
	assert(WarriorCombatMath.wild_rush_success_threshold(3, 25, 20) == 20, "野蛮成功阈值错误")
	assert(WarriorCombatMath.wild_rush_success_probability(0, 25, 20) == 1.0, "低等级合法目标必须确定性推动")
	assert(WarriorCombatMath.wild_rush_max_cells(0) == 3 and WarriorCombatMath.wild_rush_max_cells(3) == 3, "野蛮必须固定推动三格")
	assert(WarriorCombatMath.active_skill_damage("野蛮冲撞", 100, 3) == 0, "野蛮冲撞不得造成伤害")
	assert(WarriorCombatMath.hit_succeeds(5, 15, 4) and not WarriorCombatMath.hit_succeeds(5, 15, 5), "服务端严格小于命中边界错误")
	assert(is_equal_approx(WarriorCombatMath.hit_probability(5, 15), 1.0 / 3.0), "基础命中概率应为5/15")
	assert(is_equal_approx(WarriorCombatMath.client_attack_duration_seconds(), 0.51), "客户端攻击动作应为510ms")
	assert(is_equal_approx(WarriorCombatMath.client_effect_time_seconds(), 0.17), "客户端技能声效/表现帧应为170ms")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.learned_skills = {"基本剑术": 0, "攻杀剑术": 0}
	PlayerState.recalculate_stats()
	assert(int(PlayerState.computed_stats.accuracy) == 5, "0级基本剑术/攻杀不应凭空加准确")
	PlayerState.learned_skills = {"基本剑术": 3, "攻杀剑术": 3}
	PlayerState.recalculate_stats()
	assert(int(PlayerState.computed_stats.accuracy) == 5, "技能准确仍被旧PlayerState公式提前注入，未交给Router")

	var file := FileAccess.open("res://assets/data/warrior_service_rules.json", FileAccess.READ)
	assert(file != null, "战士服务端规则数据不存在")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	assert(parsed is Dictionary, "战士服务端规则数据不是有效JSON")
	assert(int(parsed.get("skills", {}).get("烈火剑法", {}).get("magicId", -1)) == 26, "烈火MagicId来源数据错误")
	assert(parsed.get("knownMissing", []).size() >= 1, "缺失Magic.DB没有显式记录")
	print("WARRIOR_SERVICE_FORMULA_PASS：六技能ID、命中、伤害、范围规则、野蛮固定三格确定性位移与客户端510ms动作已校准")
	get_tree().quit(0)
