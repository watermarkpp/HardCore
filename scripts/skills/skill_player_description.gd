extends RefCounted

## Read-only presentation of canonical runtime plans. Endpoint choices are
## local to this preview; opening a panel must never advance combat RNG.
const Data := preload("res://scripts/skills/skill_data_loader.gd")
const Wizard := preload("res://scripts/skills/runtimes/wizard_skill_runtime.gd")
const Taoist := preload("res://scripts/skills/runtimes/taoist_skill_runtime.gd")
const Warrior := preload("res://scripts/skills/runtimes/warrior_skill_runtime.gd")
const Ranks := preload("res://scripts/skills/skill_rank_resolver.gd")
const Resources := preload("res://scripts/skills/skill_resource_service.gd")

class EndpointChoice extends RefCounted:
	var upper := false
	func pascal_random_exclusive(bound: int) -> int:
		return maxi(0, bound - 1) if upper else 0
	func chance(probability: float) -> bool:
		return probability > 0.0


static func mana_cost(id: String, rank: int, partner_rank := -1) -> int:
	var context := {}
	if id in ["taoist.defense", "taoist.magic_defense"] and partner_rank >= 0:
		context["dual_defense_context"] = {
			"partner_skill_id": "taoist.defense" if id == "taoist.magic_defense" else "taoist.magic_defense",
			"partner_rank": partner_rank,
		}
	return int(Resources.quote(Data.skill(id), rank, {"mana": 1000000}, context).get("mp_cost", 0))


static func preview_effects(id: String, rank: int, stats: Dictionary, caster_level: int, upper := false) -> Array:
	rank = Ranks.formula_rank(rank) if Ranks.mode_for(id) == "EXCLUDED" else Ranks.safe_effective_rank(rank)
	var definition := Data.skill(id)
	if definition.is_empty(): return []
	var rng := EndpointChoice.new()
	rng.upper = upper
	var prefix := "tao" if id.begins_with("taoist.") else "magic"
	var minimum := int(stats.get(prefix + "_min", 0))
	var maximum := maxi(minimum, int(stats.get(prefix + "_max", minimum)))
	var luck := int(stats.get("luck", 0))
	var primary_stat := maximum if upper else minimum
	if luck >= 9: primary_stat = maximum
	elif luck <= -9: primary_stat = minimum
	var context := {
		"primary_stat_roll": primary_stat,
		"actual_hp_missing": 999999, "affected_friendly_count": 1,
		"caster_ground_position_gu": Vector2.ZERO,
		"friendly_candidates": [{"level": caster_level, "instance_id": 1,
			"is_self": true, "current_hp": 1, "max_hp": 1000000,
			"ground_position_gu": Vector2.ZERO}],
		"valid_melee_swing": true, "force_proc": true,
		"target_is_monster": true, "target_is_undead": false,
		"target_level": maxi(1, caster_level - 2),
		"forced_temptation_outcome": "no_effect",
	}
	var request := {"rank": rank, "caster_level": caster_level, "target_context": context}
	var plan: Dictionary
	if id.begins_with("warrior."):
		plan = Warrior.execute(definition, request, rng)
	elif id.begins_with("wizard."):
		plan = Wizard.execute(definition, request, rng)
	else:
		plan = Taoist.execute(definition, request, rng)
	return plan.get("effects", [])


static func describe(id: String, rank: int, stats: Dictionary, caster_level: int) -> String:
	rank = Ranks.formula_rank(rank) if Ranks.mode_for(id) == "EXCLUDED" else Ranks.safe_effective_rank(rank)
	var definition := Data.skill(id)
	if definition.is_empty(): return "暂无技能资料。"
	var low := preview_effects(id, rank, stats, caster_level)
	var high := preview_effects(id, rank, stats, caster_level, true)
	var first: Dictionary = low[0] if not low.is_empty() else {}
	var lines: Array[String] = []
	match id:
		"warrior.basic_swordsmanship", "taoist.spiritual_warfare":
			lines.append("被动提高准确 %d 点，帮助近战攻击命中，不提高法术命中率。技能超过基础 3 级后，每提升一级再增加 3 点准确。" % int(first.get("value", 0)))
		"warrior.slaying_swordsmanship":
			lines.append("被动提高准确 %d 点。每次有效近战攻击有 %.1f%% 概率追加 %d 点物理伤害。" % [int(first.flat_accuracy_bonus), float(first.success_probability) * 100.0, int(first.flat_damage_bonus)])
			lines.append("普攻、刺杀、半月和烈火都可触发；同一挥击命中多个目标时，共用一次触发结果。")
		"warrior.thrusting":
			lines.append("沿出手方向攻击 3 格直线内的敌人。前 1.5 格造成基础物理伤害的 %.1f%%，正常计算防御；后 1.5 格造成 %.1f%%，忽略物理防御。" % [float(first.multiplier) * 100.0, float(low[1].multiplier) * 100.0])
		"warrior.half_moon":
			lines.append("横扫前方 2 格、120°扇形内的敌人。正面目标承受基础物理伤害的 %.1f%%，侧面目标承受 %.1f%%，均正常计算防御。" % [float(first.primary_multiplier) * 100.0, float(first.side_multiplier) * 100.0])
		"warrior.fire_sword":
			lines.append("为下一次有效近战蓄力，造成基础物理伤害的 %.2f 倍。蓄力保留 %.0f 秒，不能叠加。" % [float(first.damage_multiplier), float(first.charge_lifetime_ms) / 1000.0])
		"warrior.wild_rush":
			lines.append("冲撞等级低于自己的普通怪物，最多推进 3 格，不造成伤害。目标符合条件且道路畅通时必定成功；Boss、不可移动目标和安全区内目标不生效。")
			lines.append("前方有其他怪物挡住时无法推进，遇到地形障碍则在障碍前停下。")
		"wizard.fireball": lines.append("发射一枚火球攻击目标；飞行途中被障碍阻挡，或目标避开时，可能无法命中。")
		"wizard.great_fireball": lines.append("发射威力更强的火球攻击目标，飞行途中会受到障碍阻挡。")
		"wizard.lightning": lines.append("从目标上方召下雷电。对不死系怪物的威力提高至 1.5 倍，再计算目标的魔法防御。")
		"wizard.hellfire": lines.append("向前喷出长 5 格、宽 1 格的火焰，攻击范围内的敌人；地形会阻挡火焰。")
		"wizard.laser": lines.append("沿出手方向发出长 8 格、宽 1 格的光束，可以贯穿直线内的敌人，遇地形障碍停止。")
		"wizard.exploding_flame": lines.append("引爆目标附近的火焰，攻击 3×3 格内的敌人。")
		"wizard.ice_storm": lines.append("在目标附近掀起冰风暴，攻击 3×3 格内的敌人。")
		"wizard.fire_wall":
			lines.append("在目标附近布下 3×3 格火墙，持续 %s 秒。每隔 %.1f 秒结算一次伤害；自己的多片火墙重叠时，同一轮不会对同一目标重复扣血。" % [_range(low, high, "duration_seconds"), float(first.tick_interval_ms) / 1000.0])
		"wizard.hell_lightning": lines.append("释放以自身为中心的雷光，攻击周围 5×5 格内、中心格以外的敌人，最多命中 24 个目标。")
		"wizard.repulsion_ring":
			lines.append("击退身边等级低于自己的普通怪物，不造成伤害。Boss 和不可移动目标无效；被障碍挡住时无法推开。")
			lines.append("当前等级可推开 %d～%d 格。成功率为 %.0f%% 加上每领先目标一级增加的 5%%，最高 100%%。" % [1 + maxi(0, rank - 1), 2 + maxi(0, rank - 1), minf(100.0, (6.0 + 3.0 * rank) * 5.0)])
		"wizard.temptation_light":
			lines.append("尝试使怪物定身、混乱或成为宠物，也可能失败。Boss 和已有其他主人的怪物无法诱惑。")
			lines.append("收服要求：可被驯服、不是不死系、等级不超过 50 且不高于自己 2 级。目标生命上限越高，越难收服；通过多次随机判定后才会成功，并非满足条件就必定收服。")
			lines.append("最多携带 %d 只诱惑宠物。部分失败分支可能直接杀死目标。" % int(first.get("pet_cap", 0)))
		"wizard.teleport":
			lines.append("随机移动到当前地图的一个可落脚位置。当前成功率 %.1f%%；失败或没有合法落点时留在原地，禁传地图不能使用。" % (float(first.success_probability) * 100.0))
		"wizard.magic_shield":
			lines.append("为自己施加魔法盾，承受的伤害减少 %.0f%%，持续 %s 秒。再次施放刷新护盾，减伤不叠加。" % [float(first.damage_reduction) * 100.0, _range(low, high, "duration_seconds")])
			lines.append("护盾的吸收容量等于施放时的魔法上限，每次减免的伤害都会消耗容量；容量耗尽会提前破盾。怪物持续毒伤不受此盾减免。")
		"wizard.holy_word":
			lines.append("尝试直接消灭等级低于自己的普通不死系怪物；Boss 和免疫圣言的目标无效。")
			lines.append("成功率为 %.0f%% 加上每领先目标一级增加的 1%%，最高 100%%。仅领先一级时还需先通过一次 50%% 判定；失败不造成普通伤害。" % minf(100.0, 15.0 + 7.0 * rank))
		"taoist.healing", "taoist.mass_healing":
			lines.append("为一名友方恢复生命。" if id == "taoist.healing" else "为目标区域 3×3 格内的友方恢复生命。")
			lines.append("自动选择 9 格内自己或召唤物中生命损失比例最高的目标；比例相同时优先自己，再选较近者。")
			lines.append("按当前道术，每名目标可恢复 %s 点生命，不超过其生命上限。" % _range(low, high, "raw_heal" if id == "taoist.healing" else "raw_heal_per_target"))
			lines.append(("目标已满血" if id == "taoist.healing" else "范围内目标全部满血") + "时施放会附加短暂持续恢复，每 0.8 秒恢复一次，共 3 次。")
		"taoist.poison":
			lines.append("同时施加绿毒和红毒，持续 %s 秒。绿毒每 2 秒造成 %s 点伤害；红毒使物理防御和魔法防御各降低 %s 点。" % [_range(low, high, "duration_seconds"), _range(low, high, "damage_per_tick"), _range(low, high, "flat_ac_reduction", 1)])
			lines.append("目标抗毒越高，越容易抵抗施毒。红绿毒可以共存，同类毒再次施加只刷新持续时间。")
		"taoist.soul_fire_talisman": lines.append("发出灵魂火符攻击目标，以道术决定威力，由目标魔法防御抵挡。")
		"taoist.summon_skeleton", "taoist.summon_divine_beast":
			lines.append("召唤%s协助战斗，最多同时拥有 %d 只该类召唤物。初始宠物等级 %d，战斗成长上限 %d；技能等级与宠物成长等级是两回事。" % ["骷髅" if id == "taoist.summon_skeleton" else "神兽", int(first.group_limit), int(first.initial_pet_level), int(first.max_pet_level)])
			lines.append("达到数量上限时再次施放会召回已有宠物，召回不消耗魔法。切换地图时跟随主人，主人死亡时消失。")
			if id == "taoist.summon_divine_beast" and rank > 3:
				lines.append("当前技能等级使神兽攻击威力达到 3 级技能时的 %.1f%%，不会增加神兽数量。" % (Ranks.more_multiplier(rank) * 100.0))
		"taoist.invisibility", "taoist.mass_invisibility":
			lines.append("使自己暂时不被普通怪物主动发现。" if id == "taoist.invisibility" else "使自身周围 3×3 格内的友方暂时不被普通怪物主动发现。")
			lines.append("持续 %s 秒。移动到另一格、攻击或使用技能会解除；受伤本身不解除，也不提供无敌。能看破隐身的怪物仍可发现目标。" % _range(low, high, "duration_seconds"))
		"taoist.magic_defense", "taoist.defense":
			lines.append("提高周围 3 格内友方的%s，增加量为目标等级每满 7 级增加 1 点，至少 1 点。" % ("魔法防御" if id == "taoist.magic_defense" else "物理防御"))
			lines.append("当前施放持续 %s 秒。两种防御增益可共存，重复施放刷新时间；两种技能都学会后，一次施放会同时提供两种增益，各自按对应技能等级计算。" % _range(low, high, "duration_seconds"))
		"taoist.revelation":
			lines.append("显示目标当前生命及生命上限，不造成伤害。当前成功率 %.1f%%，成功后持续 %s 秒。" % [float(first.success_probability) * 100.0, _range(low, high, "duration_ms", 0, 0.001)])
		"taoist.entrapment":
			lines.append("在目标周围形成 3×3 格的围栏，限制中央怪物离开，持续 %s 秒。Boss、控制免疫或超出等级限制的怪物不能被困；人物进入围栏会解除。" % _range(low, high, "duration_seconds"))
	if first.has("raw_power"):
		lines.append("按当前%s计算，%s未扣魔法防御的威力为 %s 点。实际扣血还会受目标魔防、抗性及减伤影响。" % ["道术" if id.begins_with("taoist.") else "魔法攻击", "每次结算" if id == "wizard.fire_wall" else "每次命中", _range(low, high, "raw_power")])
		lines.append("每次施放会在属性与技能允许的区间内取值；幸运会影响属性取值。装备提供的技能等级已计入上面的数值。")
	if id.begins_with("taoist.") and id != "taoist.spiritual_warfare":
		lines.append("本游戏的道士法术不消耗符纸或毒粉。")
	return "\n".join(lines)


static func _range(low: Array, high: Array, key: String, index := 0, scale := 1.0) -> String:
	assert(index < low.size() and index < high.size() and low[index].has(key) and high[index].has(key), "description missing canonical field: " + key)
	var a := float(low[index][key]) * scale
	var b := float(high[index][key]) * scale
	return _number(a) if is_equal_approx(a, b) else "%s～%s" % [_number(a), _number(b)]


static func _number(value: float) -> String:
	return str(roundi(value)) if is_equal_approx(value, roundf(value)) else str(snappedf(value, 0.01))
