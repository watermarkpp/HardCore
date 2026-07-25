extends Node

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const ITEM_COMBAT_FIELDS := ["magicEvasionPoints", "magicEvasionPercent", "attackSpeedTier"]


func _ready() -> void:
	_run.call_deferred()


func _direct_spell_context(skill_id: String, anti_magic_roll: int, anti_magic_points := 1) -> Dictionary:
	var context := {
		"skill_level": 3,
		"magic_power_roll": 0,
		"def_power_roll": 0,
		"anti_magic_roll": anti_magic_roll,
		"target_anti_magic_points": anti_magic_points,
	}
	if skill_id.begins_with("wizard."):
		context["magic_stat_roll"] = 12
	else:
		context["spiritual_stat_roll"] = 12
	return context


func _assert_direct_spell_anti_magic(skill_id: String) -> void:
	var evaded := CasterSkillRuntime.resolve(skill_id, _direct_spell_context(skill_id, 0))
	assert(evaded.success and evaded.anti_magic_eligible and evaded.anti_magic_checked, "%s未调用AntiMagic" % skill_id)
	assert(evaded.magic_evaded and evaded.damage == 0, "%s躲避成功后没有整次归零" % skill_id)
	assert(not evaded.enters_magic_defense_stage, "%s躲避成功后错误进入MAC阶段" % skill_id)

	var connected := CasterSkillRuntime.resolve(skill_id, _direct_spell_context(skill_id, 1))
	assert(not connected.magic_evaded and connected.damage > 0, "%s未命中AntiMagic边界" % skill_id)
	assert(connected.enters_magic_defense_stage, "%s未躲避伤害没有进入MAC阶段契约" % skill_id)

	var zero_points := CasterSkillRuntime.resolve(skill_id, _direct_spell_context(skill_id, 0, 0))
	assert(not zero_points.magic_evaded and zero_points.damage > 0, "%s的0点AntiMagic不应躲避" % skill_id)


func _snapshot_item_combat_fields(item: Dictionary) -> Dictionary:
	var snapshot := {}
	for field: String in ITEM_COMBAT_FIELDS:
		snapshot[field] = item[field] if item.has(field) else null
	return snapshot


func _restore_item_combat_fields(item: Dictionary, snapshot: Dictionary) -> void:
	for field: String in ITEM_COMBAT_FIELDS:
		if snapshot[field] == null:
			item.erase(field)
		else:
			item[field] = snapshot[field]


func _run() -> void:
	var contract := CombatResolutionRules.contract()
	assert(contract.contractId == CombatResolutionRules.CONTRACT_ID, "战斗结算数据契约ID错误")
	assert(contract.sourceTrace.lane == "server_rules" and contract.sourceTrace.tier == "primary", "战斗结算未指向主源")
	assert(contract.sourceTrace.originalPaths.size() == 2, "战斗结算主源路径不完整")
	assert(
		contract.sourceTrace.sha256ByOriginalPath.size() == 2
		and not contract.sourceTrace.fallbackUsed
		and contract.sourceTrace.primaryResult == "present_parsed_compatible",
		"战斗结算主源哈希或降级证据不完整"
	)
	assert(
		contract.integrationAdapters.playerOutgoingDirectSpellImpact.api == "CombatResolutionRules.resolve_direct_spell_damage"
		and contract.integrationAdapters.playerIncomingDirectSpell.targetStats == "PlayerState.computed_stats"
		and contract.integrationAdapters.playerIncomingDirectSpell.api == "PlayerCharacter.take_direct_spell_damage",
		"跨系统运行时适配清单不完整"
	)
	assert(
		contract.professionRuntimeClosure.directSpellDamageApi == "CombatResolutionRules.resolve_direct_spell_damage"
		and contract.professionRuntimeClosure.closedCallSites.size() == 3
		and contract.professionRuntimeClosure.playerIncomingRuntimeId == PlayerCharacter.DIRECT_SPELL_DAMAGE_RUNTIME_ID
		and contract.integrationAdapters.playerOutgoingDirectSpellImpact.requiredProjectileArgument == "stable source_skill_id",
		"职业运行时闭环或GameRoot最小接线契约不完整"
	)

	assert(WarriorCombatMath.PHYSICAL_HIT_POLICY_ID == "physical.hit.random_agility.strict_lt.v1")
	assert(WarriorCombatMath.hit_succeeds(5, 15, 4), "roll=accuracy-1应命中")
	assert(not WarriorCombatMath.hit_succeeds(5, 15, 5), "roll=accuracy必须闪避")
	assert(not WarriorCombatMath.hit_succeeds(0, 15, 0), "0准确不得产生off-by-one命中")
	assert(WarriorCombatMath.hit_succeeds(15, 15, 14), "准确达到敏捷应全命中")
	assert(is_equal_approx(WarriorCombatMath.hit_probability(5, 15), 1.0 / 3.0), "命中概率必须为accuracy/agility")
	for mode in ["normal", "slaying", "thrust", "half_moon", "fire"]:
		assert(CombatResolutionRules.physical_attack_uses_accuracy(mode), "%s没有统一物理命中契约" % mode)
	assert(not CombatResolutionRules.physical_attack_uses_accuracy("wizard.fireball"), "法术错误使用敏捷物理闪避")

	assert(CombatResolutionRules.BASE_CHARACTER_ANTI_MAGIC_POINTS == 1, "角色基础AntiMagic必须为1点")
	assert(CombatResolutionRules.anti_magic_display_percent(1) == 10, "1内部点必须显示10%")
	assert(CombatResolutionRules.anti_magic_points_from_display_percent(10) == 1, "10%必须转换为1内部点")
	assert(CombatResolutionRules.anti_magic_points_from_display_percent(99) == 9, "显示百分比必须按10%内部点向下转换")
	assert(CombatResolutionRules.anti_magic_points_from_context({}) == 0, "无目标字段的施法上下文不得凭空获得10%魔闪")
	assert(CombatResolutionRules.anti_magic_points_from_context({"target_magic_evasion_percent": 30}) == 3)
	assert(
		CombatResolutionRules.anti_magic_points_from_target_stats({}) == 0,
		"无AntiMagic字段的通用/怪物目标不得凭空获得10%魔闪"
	)
	assert(
		CombatResolutionRules.anti_magic_points_from_target_stats({
			"magicEvasionPoints": 2,
			"magicEvasionPercent": 90,
		}) == 2,
		"运行时目标属性未优先消费内部点或发生percent双算"
	)
	var target_stat_resolution := CombatResolutionRules.resolve_magic_damage_for_target_stats(
		"wizard.fireball",
		12,
		{"anti_magic_points": 1},
		0
	)
	assert(target_stat_resolution.magic_evaded and target_stat_resolution.damage_after_evasion == 0, "运行时目标属性适配API未执行AntiMagic")

	PlayerState.test_mode = true
	PlayerState.reset_progress()
	assert(
		int(PlayerState.computed_stats.anti_magic_points) == 1
		and int(PlayerState.computed_stats.magic_evasion_percent) == 10
		and int(PlayerState.computed_stats.attack_speed_tier) == 0,
		"PlayerState基础AntiMagic或攻速tier契约错误"
	)
	var wood_sword := GameData.get_item("木剑")
	var previous_modifiers: Variant = wood_sword.get("modifiers", null)
	wood_sword["modifiers"] = {"antiMagicPoints": 3, "attackSpeedTier": 2}
	PlayerState.equipment["武器"] = {"name": "木剑", "durability": 1}
	PlayerState.recalculate_stats()
	assert(
		int(PlayerState.computed_stats.anti_magic_points) == 4
		and int(PlayerState.computed_stats.magic_evasion_percent) == 40
		and int(PlayerState.computed_stats.attack_speed_tier) == 2,
		"装备稳定字段未聚合到PlayerState战斗属性"
	)
	if previous_modifiers == null:
		wood_sword.erase("modifiers")
	else:
		wood_sword["modifiers"] = previous_modifiers
	PlayerState.reset_progress()

	var white_tiger_tooth := GameData.get_item("白色虎齿项链")
	var lantern_necklace := GameData.get_item("灯笼项链")
	var gale_necklace := GameData.get_item("狂风项链")
	var gale_ring := GameData.get_item("狂风戒指")
	var item_field_snapshots := {
		"white_tiger_tooth": _snapshot_item_combat_fields(white_tiger_tooth),
		"lantern_necklace": _snapshot_item_combat_fields(lantern_necklace),
		"gale_necklace": _snapshot_item_combat_fields(gale_necklace),
		"gale_ring": _snapshot_item_combat_fields(gale_ring),
	}
	white_tiger_tooth.merge({"magicEvasionPoints": 2, "magicEvasionPercent": 20}, true)
	lantern_necklace.merge({"magicEvasionPoints": 1, "magicEvasionPercent": 10}, true)
	gale_necklace["attackSpeedTier"] = 2
	gale_ring["attackSpeedTier"] = 1
	# Synthetic multi-record loadout: it verifies recalculate_stats aggregation only,
	# independently from inventory slot validation.
	PlayerState.equipment.merge({
		"项链": {"name": "白色虎齿项链", "durability": 1},
		"头盔": {"name": "灯笼项链", "durability": 1},
		"衣服": {"name": "狂风项链", "durability": 1},
		"左戒指": {"name": "狂风戒指", "durability": 1},
		"右戒指": {"name": "狂风戒指", "durability": 1},
	}, true)
	PlayerState.recalculate_stats()
	assert(
		int(PlayerState.computed_stats.anti_magic_points) == 4
		and int(PlayerState.computed_stats.magic_evasion_percent) == 40,
		"顶层魔闪字段未按基础1+虎齿2+灯笼1聚合，或points/percent发生双算"
	)
	assert(int(PlayerState.computed_stats.attack_speed_tier) == 4, "狂风项链2档与两枚狂风戒指各1档未累加为4档")
	var field_contract_player := PlayerCharacter.new()
	add_child(field_contract_player)
	assert(is_equal_approx(field_contract_player.attack_cooldown, 0.66), "4档物理攻速应得到660ms最小间隔")
	field_contract_player.free()
	_restore_item_combat_fields(white_tiger_tooth, item_field_snapshots.white_tiger_tooth)
	_restore_item_combat_fields(lantern_necklace, item_field_snapshots.lantern_necklace)
	_restore_item_combat_fields(gale_necklace, item_field_snapshots.gale_necklace)
	_restore_item_combat_fields(gale_ring, item_field_snapshots.gale_ring)
	PlayerState.reset_progress()

	for skill_id in [
		"wizard.fireball",
		"wizard.great_fireball",
		"wizard.lightning",
		"taoist.soul_fire_talisman",
	]:
		_assert_direct_spell_anti_magic(skill_id)

	var low_agility_magic := _direct_spell_context("wizard.fireball", 0)
	low_agility_magic["target_agility"] = 1
	var high_agility_magic := low_agility_magic.duplicate(true)
	high_agility_magic["target_agility"] = 999
	var low_agility_plan := CasterSkillRuntime.resolve("wizard.fireball", low_agility_magic)
	var high_agility_plan := CasterSkillRuntime.resolve("wizard.fireball", high_agility_magic)
	assert(
		low_agility_plan.magic_evaded == high_agility_plan.magic_evaded
		and low_agility_plan.damage == high_agility_plan.damage,
		"敏捷错误影响法术闪避"
	)

	for skill_id in ["taoist.healing", "taoist.mass_healing"]:
		var healing := CasterSkillRuntime.resolve(skill_id, {
			"skill_level": 3,
			"spiritual_stat_roll": 12,
			"magic_power_roll": 0,
			"def_power_roll": 0,
			"anti_magic_roll": 0,
			"target_anti_magic_points": 10,
		})
		assert(healing.healing > 0 and not healing.anti_magic_eligible and not healing.anti_magic_checked, "%s误用AntiMagic" % skill_id)

	var poison_success := CasterSkillRuntime.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": 12,
		"poison_type": "green",
		"anti_poison_random": 6,
		"anti_magic_roll": 0,
		"target_anti_magic_points": 10,
	})
	var poison_resisted := CasterSkillRuntime.resolve("taoist.poison", {
		"skill_level": 3,
		"spiritual_stat_roll": 12,
		"poison_type": "green",
		"anti_poison_random": 7,
		"anti_magic_roll": 9,
		"target_anti_magic_points": 0,
	})
	assert(poison_success.success and not poison_resisted.success, "施毒没有使用独立AntiPoison门")
	assert(poison_success.evasion_channel == "anti_poison" and not poison_success.anti_magic_checked, "施毒误用AntiMagic")

	for skill_id in [
		"taoist.invisibility",
		"taoist.mass_invisibility",
		"taoist.summon_skeleton",
		"taoist.summon_divine_beast",
	]:
		var plan := CasterSkillRuntime.resolve(skill_id, {
			"skill_level": 3,
			"spiritual_stat_roll": 12,
			"owner_level": 35,
			"anti_magic_roll": 0,
			"target_anti_magic_points": 10,
		})
		assert(plan.success and not plan.anti_magic_eligible and not plan.anti_magic_checked, "%s误用AntiMagic" % skill_id)

	assert(WarriorCombatMath.PHYSICAL_ATTACK_SPEED_POLICY_ID == "physical.attack_speed.interval_tier.v1")
	assert(WarriorCombatMath.physical_attack_interval_ms(-1) == 960, "负攻速档公式错误")
	assert(WarriorCombatMath.physical_attack_interval_ms(0) == 900, "零攻速档公式错误")
	assert(WarriorCombatMath.physical_attack_interval_ms(1) == 840, "一档攻速公式错误")
	assert(WarriorCombatMath.physical_attack_interval_ms(14) == 60, "十四档攻速公式错误")
	assert(WarriorCombatMath.physical_attack_interval_ms(15) == 0, "十五档攻速下限错误")
	assert(WarriorCombatMath.physical_attack_interval_ms(99) == 0, "攻速间隔不得为负")

	PlayerState.reset_progress()
	PlayerState.select_profession("战士")
	PlayerState.computed_stats.merge({
		"attack_speed_tier": 5,
		"attack_speed_percent": 5.0,
	}, true)
	var warrior := PlayerCharacter.new()
	add_child(warrior)
	assert(is_equal_approx(warrior.attack_cooldown, 0.6), "玩家物理攻击未消费攻速tier")
	assert(is_equal_approx(warrior.move_speed, 190.0), "攻速tier错误修改移动速度")
	assert(warrior.request_attack(), "攻速tier玩家未能发起普通攻击")
	assert(is_equal_approx(warrior._attack_timer, 0.6), "物理攻击最小间隔未使用tier公式")
	assert(is_equal_approx(warrior._attack_action_timer, 0.51), "攻速tier错误缩短物理动作/移动锁")
	warrior.free()

	PlayerState.reset_progress()
	PlayerState.select_profession("法师")
	PlayerState.learned_skills = {"火球术": 0}
	PlayerState.computed_stats.merge({
		"attack_speed_tier": 15,
		"attack_speed_percent": 5.0,
		"cast_speed_percent": 0.0,
		"magic_min": 4,
		"magic_max": 12,
		"max_mp": 100,
	}, true)
	var wizard := PlayerCharacter.new()
	add_child(wizard)
	var fireball_profile := ProfessionRules.skill_combat_profile("火球术", 0)
	assert(wizard.request_skill("火球术"), "攻速隔离测试无法施放火球")
	assert(
		is_equal_approx(wizard._attack_timer, float(fireball_profile.cooldown)),
		"攻速tier错误缩短施法或技能冷却"
	)

	print("COMBAT_RESOLUTION_CONTRACT_PASS：物理严格命中、AntiMagic/AntiPoison隔离与攻速tier边界统一")
	get_tree().quit(0)
