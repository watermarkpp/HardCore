extends Node


func _ready() -> void:
	var fireball_zero := WizardCombatMath.profile_overrides("wizard.fireball", 0)
	var fireball_three := WizardCombatMath.profile_overrides("wizard.fireball", 3)
	assert(float(fireball_three.multiplier) > float(fireball_zero.multiplier), "火球术等级成长未进入法师公式层")
	assert(WizardCombatMath.damage("wizard.lightning", 100, 3) == 175, "三级雷电术专属伤害曲线错误")
	assert(is_equal_approx(WizardCombatMath.shield_damage_reduction(3), 0.4), "三级魔法盾减伤错误")
	assert(is_equal_approx(WizardCombatMath.shield_duration(3), 14.0), "三级魔法盾持续时间错误")
	assert(is_equal_approx(WizardCombatMath.fire_wall_duration(3), 7.0), "三级火墙持续时间错误")

	var poison := TaoistCombatMath.profile_overrides("taoist.poison", 3)
	assert(is_equal_approx(float(poison.multiplier), 0.45) and is_equal_approx(float(poison.status_duration), 9.0), "三级施毒术曲线错误")
	assert(TaoistCombatMath.damage("taoist.soul_fire_talisman", 100, 3) == 135, "三级灵魂火符伤害错误")
	assert(TaoistCombatMath.healing("taoist.healing", 100, 3) == 132, "三级治愈术恢复公式错误")
	var skeleton := TaoistCombatMath.summon_profile("taoist.summon_skeleton", 3, 35, 30)
	var divine_beast := TaoistCombatMath.summon_profile("taoist.summon_divine_beast", 3, 35, 30)
	assert(skeleton.attack_type == "physical" and divine_beast.attack_type == "fire", "召唤物攻击类型错误")
	assert(int(divine_beast.max_hp) > int(skeleton.max_hp), "神兽生命成长应高于骷髅")
	assert(float(divine_beast.lifetime_seconds) > float(skeleton.lifetime_seconds), "神兽存活规则应高于骷髅")

	for skill_id: String in ProfessionRules.SKILL_CATALOG:
		if skill_id.begins_with("wizard."):
			assert(not WizardCombatMath.profile_overrides(skill_id, 3).is_empty(), "%s缺少法师专属公式" % skill_id)
		elif skill_id.begins_with("taoist."):
			assert(not TaoistCombatMath.profile_overrides(skill_id, 3).is_empty(), "%s缺少道士专属公式" % skill_id)
	var wizard_profile := ProfessionRules.skill_combat_profile("wizard.ice_storm", 3)
	var taoist_profile := ProfessionRules.skill_combat_profile("taoist.entrapment", 3)
	assert(wizard_profile.formula_source.ends_with("WizardCombatMath"), "法师档案未接入专属公式层")
	assert(taoist_profile.formula_source.ends_with("TaoistCombatMath"), "道士档案未接入专属公式层")
	print("CASTER_COMBAT_MATH_PASS：法师14技能、道士13技能专属曲线、状态时长与召唤规则正常")
	get_tree().quit(0)
