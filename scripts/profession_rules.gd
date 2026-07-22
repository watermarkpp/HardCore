class_name ProfessionRules
extends RefCounted

const PROFESSIONS: Array[String] = ["战士", "法师", "道士"]
const PROFESSION_CATALOG := {
	"warrior": "战士",
	"wizard": "法师",
	"taoist": "道士",
}
const SKILL_CATALOG := {
	"warrior.basic_swordsmanship": "基本剑术",
	"warrior.slaying_swordsmanship": "攻杀剑术",
	"warrior.thrusting": "刺杀剑术",
	"warrior.half_moon": "半月弯刀",
	"warrior.wild_rush": "野蛮冲撞",
	"warrior.fire_sword": "烈火剑法",
	"wizard.fireball": "火球术",
	"wizard.repulsion_ring": "抗拒火环",
	"wizard.temptation_light": "诱惑之光",
	"wizard.hellfire": "地狱火",
	"wizard.lightning": "雷电术",
	"wizard.teleport": "瞬息移动",
	"wizard.great_fireball": "大火球",
	"wizard.exploding_flame": "爆裂火焰",
	"wizard.fire_wall": "火墙",
	"wizard.laser": "疾光电影",
	"wizard.hell_lightning": "地狱雷光",
	"wizard.magic_shield": "魔法盾",
	"wizard.holy_word": "圣言术",
	"wizard.ice_storm": "冰咆哮",
	"taoist.healing": "治愈术",
	"taoist.spiritual_warfare": "精神力战法",
	"taoist.poison": "施毒术",
	"taoist.soul_fire_talisman": "灵魂火符",
	"taoist.summon_skeleton": "召唤骷髅",
	"taoist.invisibility": "隐身术",
	"taoist.mass_invisibility": "集体隐身术",
	"taoist.magic_defense": "幽灵盾",
	"taoist.defense": "神圣战甲术",
	"taoist.revelation": "心灵启示",
	"taoist.entrapment": "困魔咒",
	"taoist.mass_healing": "群体治疗术",
	"taoist.summon_divine_beast": "召唤神兽",
}

# 运行时成长入口。精确逐级官服数值将在等级经验/属性表完成考据后替换，
# 所有调用方只依赖此处，避免把职业公式散落到角色、HUD和技能代码中。
const BASE_STATS := {
	"战士": {"hp_base": 100, "hp_per_level": 20, "mp_base": 20, "mp_per_level": 4, "attack_min": 2, "attack_max": 5},
	"法师": {"hp_base": 55, "hp_per_level": 8, "mp_base": 55, "mp_per_level": 18, "attack_min": 1, "attack_max": 3},
	"道士": {"hp_base": 75, "hp_per_level": 12, "mp_base": 40, "mp_per_level": 12, "attack_min": 1, "attack_max": 4},
}

# 覆盖数据库中的33个基准技能。cast_type决定通用技能执行器的行为入口。
const SKILL_PROFILES := {
	"基本剑术": {"profession": "战士", "cast_type": "passive", "multiplier": 1.0, "range": 0.0, "service_magic_id": 3, "service_mode": "passive"},
	"攻杀剑术": {"profession": "战士", "cast_type": "melee", "multiplier": 1.0, "range": 105.0, "service_magic_id": 7, "service_mode": "automatic_proc"},
	"刺杀剑术": {"profession": "战士", "cast_type": "line", "multiplier": 1.0, "range": 175.0, "service_magic_id": 12, "service_mode": "toggle_second_cell"},
	"半月弯刀": {"profession": "战士", "cast_type": "area", "multiplier": 1.0, "range": 125.0, "service_magic_id": 25, "service_mode": "toggle_three_directions"},
	"野蛮冲撞": {"profession": "战士", "cast_type": "dash", "multiplier": 0.8, "range": 115.0, "service_magic_id": 27, "service_mode": "rush"},
	"烈火剑法": {"profession": "战士", "cast_type": "melee", "multiplier": 1.0, "range": 105.0, "service_magic_id": 26, "service_mode": "arm_next_hit", "ui_interaction_mode": "toggle", "runtime_activation_mode": "toggle_auto_use", "toggle_state_id": "warrior.fire_sword.auto_enabled"},
	"火球术": {"profession": "法师", "cast_type": "projectile", "multiplier": 1.0, "range": 360.0},
	"抗拒火环": {"profession": "法师", "cast_type": "knockback", "multiplier": 0.0, "range": 115.0},
	"诱惑之光": {"profession": "法师", "cast_type": "control", "multiplier": 0.0, "range": 300.0},
	"地狱火": {"profession": "法师", "cast_type": "line", "multiplier": 1.2, "range": 260.0},
	"雷电术": {"profession": "法师", "cast_type": "projectile", "multiplier": 1.35, "range": 410.0},
	"瞬息移动": {"profession": "法师", "cast_type": "teleport", "multiplier": 0.0, "range": 220.0},
	"大火球": {"profession": "法师", "cast_type": "projectile", "multiplier": 1.45, "range": 390.0},
	"爆裂火焰": {"profession": "法师", "cast_type": "area", "multiplier": 1.35, "range": 260.0},
	"火墙": {"profession": "法师", "cast_type": "ground_dot", "multiplier": 0.65, "range": 250.0},
	"疾光电影": {"profession": "法师", "cast_type": "line", "multiplier": 1.7, "range": 430.0},
	"地狱雷光": {"profession": "法师", "cast_type": "area", "multiplier": 1.1, "range": 150.0},
	"魔法盾": {"profession": "法师", "cast_type": "shield", "multiplier": 0.0, "range": 0.0},
	"圣言术": {"profession": "法师", "cast_type": "execute", "multiplier": 1.0, "range": 300.0},
	"冰咆哮": {"profession": "法师", "cast_type": "area", "multiplier": 1.9, "range": 300.0},
	"治愈术": {"profession": "道士", "cast_type": "heal", "multiplier": 1.2, "range": 280.0},
	"精神力战法": {"profession": "道士", "cast_type": "passive", "multiplier": 1.0, "range": 0.0},
	"施毒术": {"profession": "道士", "cast_type": "poison", "multiplier": 0.45, "range": 330.0},
	"灵魂火符": {"profession": "道士", "cast_type": "projectile", "multiplier": 1.35, "range": 370.0},
	"召唤骷髅": {"profession": "道士", "cast_type": "summon", "multiplier": 1.0, "range": 0.0},
	"隐身术": {"profession": "道士", "cast_type": "stealth", "multiplier": 0.0, "range": 0.0},
	"集体隐身术": {"profession": "道士", "cast_type": "stealth_area", "multiplier": 0.0, "range": 170.0},
	"幽灵盾": {"profession": "道士", "cast_type": "magic_defense_buff", "multiplier": 0.0, "range": 170.0},
	"神圣战甲术": {"profession": "道士", "cast_type": "defense_buff", "multiplier": 0.0, "range": 170.0},
	"心灵启示": {"profession": "道士", "cast_type": "inspect", "multiplier": 0.0, "range": 300.0},
	"困魔咒": {"profession": "道士", "cast_type": "root_area", "multiplier": 0.0, "range": 260.0},
	"群体治疗术": {"profession": "道士", "cast_type": "heal_area", "multiplier": 1.0, "range": 190.0},
	"召唤神兽": {"profession": "道士", "cast_type": "summon", "multiplier": 1.5, "range": 0.0},
}

# 手机战斗与动画共用时序基线。当前为运行时候选值，后续按可靠资料逐项替换。
const CAST_DEFAULTS := {
	"passive": {"target_mode": "self", "windup": 0.0, "hit_frame": 0, "cooldown": 0.0, "area_radius": 0.0},
	"melee": {"target_mode": "single", "windup": 0.25, "hit_frame": 3, "cooldown": 0.55, "area_radius": 0.0},
	"line": {"target_mode": "direction", "windup": 0.28, "hit_frame": 3, "cooldown": 0.62, "area_radius": 34.0},
	"area": {"target_mode": "target_area", "windup": 0.34, "hit_frame": 4, "cooldown": 0.72, "area_radius": 115.0},
	"dash": {"target_mode": "direction", "windup": 0.18, "hit_frame": 2, "cooldown": 0.75, "area_radius": 32.0},
	"projectile": {"target_mode": "single", "windup": 0.32, "hit_frame": 4, "cooldown": 0.72, "area_radius": 24.0},
	"execute": {"target_mode": "single", "windup": 0.40, "hit_frame": 4, "cooldown": 0.90, "area_radius": 24.0},
	"ground_dot": {"target_mode": "target_area", "windup": 0.38, "hit_frame": 4, "cooldown": 0.85, "area_radius": 74.0},
	"poison": {"target_mode": "single", "windup": 0.32, "hit_frame": 4, "cooldown": 0.72, "area_radius": 24.0},
	"control": {"target_mode": "single", "windup": 0.38, "hit_frame": 4, "cooldown": 0.90, "area_radius": 24.0},
	"knockback": {"target_mode": "self_area", "windup": 0.25, "hit_frame": 3, "cooldown": 0.80, "area_radius": 115.0},
	"teleport": {"target_mode": "direction", "windup": 0.18, "hit_frame": 2, "cooldown": 1.0, "area_radius": 0.0},
	"heal": {"target_mode": "self", "windup": 0.35, "hit_frame": 4, "cooldown": 0.75, "area_radius": 0.0},
	"heal_area": {"target_mode": "self_area", "windup": 0.42, "hit_frame": 4, "cooldown": 1.0, "area_radius": 190.0},
	"shield": {"target_mode": "self", "windup": 0.32, "hit_frame": 4, "cooldown": 0.9, "area_radius": 0.0},
	"stealth": {"target_mode": "self", "windup": 0.35, "hit_frame": 4, "cooldown": 0.9, "area_radius": 0.0},
	"stealth_area": {"target_mode": "self_area", "windup": 0.42, "hit_frame": 4, "cooldown": 1.0, "area_radius": 170.0},
	"magic_defense_buff": {"target_mode": "self_area", "windup": 0.40, "hit_frame": 4, "cooldown": 0.9, "area_radius": 170.0},
	"defense_buff": {"target_mode": "self_area", "windup": 0.40, "hit_frame": 4, "cooldown": 0.9, "area_radius": 170.0},
	"summon": {"target_mode": "self", "windup": 0.55, "hit_frame": 5, "cooldown": 1.2, "area_radius": 0.0},
	"inspect": {"target_mode": "single", "windup": 0.22, "hit_frame": 3, "cooldown": 0.55, "area_radius": 0.0},
	"root_area": {"target_mode": "target_area", "windup": 0.45, "hit_frame": 5, "cooldown": 1.0, "area_radius": 115.0},
}

const SKILL_TIMING_OVERRIDES := {
	"攻杀剑术": {"windup": 0.17, "hit_frame": 2, "cooldown": 0.85, "action_duration": 0.51},
	"刺杀剑术": {"windup": 0.17, "hit_frame": 2, "cooldown": 0.85, "action_duration": 0.51},
	"半月弯刀": {"windup": 0.17, "hit_frame": 2, "cooldown": 0.85, "action_duration": 0.51, "area_radius": 125.0},
	"野蛮冲撞": {"windup": 0.17, "hit_frame": 2, "cooldown": 3.0, "action_duration": 0.51},
	"烈火剑法": {"windup": 0.17, "hit_frame": 2, "cooldown": 0.85, "action_duration": 0.51, "service_arm_cooldown": 10.0, "auto_release_cooldown": 10.0},
}

# 这不是“1.76 原版阈值”。可读的本地 2002 源码自述为修改版 1.5：
# 服务端对任意 nPower>0 发 SM_STRUCK，并以 StruckTime=100 拒绝新动作；
# 客户端则将 SM_STRUCK 排在当前动作之后，并以三帧表现受击。用户明确要求
# 小额擦伤不能触发硬反应，因此下列阈值是 HardCore 的数据化平衡策略。
const COMBAT_REACTION_POLICY := {
	"policy_id": "hardcore_player_hit_reaction_v2",
	"origin": "hardcore_custom_balance_not_original_176",
	"max_hp_ratio": 0.02,
	"minimum_actual_damage": 3,
	"comparison": "actual_damage_gte_threshold",
	"server_action_lock_seconds": 0.10,
	"reaction_animation_seconds": 0.24,
	"reaction_frame_count": 3,
	"reaction_queue_policy": "after_current_action",
	"balance_basis": "Bich baseline: scarecrow 1-2; rake/hook cats 2-4; level-1 warrior HP 120",
	"reaction_basis": "mobile fixed 3x80ms, using the floor of modified-1.5 client max(80, 200-level*5) per-frame timing",
	"evidence": [
		{"confidence": "B", "scope": "modified_1.5_2002_not_verified_1.76", "path": "dev_art_sources/reference/original_gameofmir/M2Server/ObjBase.pas:5468-5521,25225-25243", "finding": "nPower>0 sends SM_STRUCK; CheckActionStatus uses configured StruckTime"},
		{"confidence": "B", "scope": "modified_1.5_2002_not_verified_1.76", "path": "dev_art_sources/reference/original_gameofmir/Client/Actor.pas:75-90,1407-1414,1536-1546,1617-1634", "finding": "three struck frames; frame_ms=max(80,200-level*5); SM_STRUCK waits for current action to finish"},
		{"confidence": "C_corroboration_only", "url": "https://github.com/miniPizza/mir2/blob/e8859977462558a09bf3fb2278dd07be7269a4f4/Client/MirScenes/GameScene.cs#L2920-L2971", "finding": "later community client also appends Struck to ActionFeed"},
	],
}

static var _runtime_data: Dictionary = {}
static var _skill_ids_by_name: Dictionary = {}


static func _data() -> Dictionary:
	if not _runtime_data.is_empty():
		return _runtime_data
	var path := ContentLayers.vanilla_dataset("professionGrowth")
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_runtime_data = parsed if parsed is Dictionary else {
		"baseStats": BASE_STATS, "skillProfiles": SKILL_PROFILES,
		"castDefaults": CAST_DEFAULTS, "skillTimingOverrides": SKILL_TIMING_OVERRIDES,
		"combatReactionPolicy": COMBAT_REACTION_POLICY,
	}
	return _runtime_data


static func is_valid_profession(value: String) -> bool:
	return value in PROFESSIONS


static func is_valid_profession_id(value: String) -> bool:
	return PROFESSION_CATALOG.has(value)


static func profession_id(value: String) -> String:
	if PROFESSION_CATALOG.has(value):
		return value
	for stable_id: String in PROFESSION_CATALOG:
		if PROFESSION_CATALOG[stable_id] == value:
			return stable_id
	return ""


static func profession_display_name(value: String) -> String:
	return str(PROFESSION_CATALOG.get(value, value if value in PROFESSIONS else ""))


static func skill_id(value: String) -> String:
	if SKILL_CATALOG.has(value):
		return value
	if _skill_ids_by_name.is_empty():
		for stable_id: String in SKILL_CATALOG:
			_skill_ids_by_name[SKILL_CATALOG[stable_id]] = stable_id
	return str(_skill_ids_by_name.get(value, ""))


static func skill_display_name(value: String) -> String:
	return str(SKILL_CATALOG.get(value, value if skill_id(value) != "" else ""))


static func stats_for_level(profession: String, level: int) -> Dictionary:
	var resolved_profession := profession_display_name(profession)
	var selected := resolved_profession if is_valid_profession(resolved_profession) else "战士"
	if GameData != null and not GameData.service_reference.is_empty():
		var service_stats := GameData.service_profession_stats(selected, level)
		if not service_stats.is_empty():
			return service_stats
	var source: Dictionary = _data().get("baseStats", BASE_STATS)[selected]
	var safe_level := maxi(1, level)
	return {
		"max_hp": int(source.hp_base) + safe_level * int(source.hp_per_level),
		"max_mp": int(source.mp_base) + safe_level * int(source.mp_per_level),
		"attack_min": int(source.attack_min),
		"attack_max": int(source.attack_max),
	}


static func skill_profile(skill_name_or_id: String) -> Dictionary:
	var display_name := skill_display_name(skill_name_or_id)
	var profile: Dictionary = _data().get("skillProfiles", SKILL_PROFILES).get(display_name, {}).duplicate(true)
	if profile.is_empty():
		return profile
	var stable_id := skill_id(display_name)
	profile["skill_id"] = stable_id
	profile["display_name"] = display_name
	profile["profession_id"] = profession_id(str(profile.get("profession", "")))
	return profile


static func skill_combat_profile(skill_name: String, learned_level := -1) -> Dictionary:
	var profile: Dictionary = skill_profile(skill_name).duplicate(true)
	if profile.is_empty():
		return profile
	var display_name := str(profile.get("display_name", skill_name))
	var stable_id := str(profile.get("skill_id", skill_id(display_name)))
	var cast_type := str(profile.get("cast_type", "melee"))
	var cast_defaults: Dictionary = _data().get("castDefaults", CAST_DEFAULTS)
	var timing_overrides: Dictionary = _data().get("skillTimingOverrides", SKILL_TIMING_OVERRIDES)
	profile.merge(cast_defaults.get(cast_type, cast_defaults["melee"]), false)
	profile.merge(timing_overrides.get(display_name, {}), true)
	profile["search_range"] = maxf(280.0, float(profile.get("range", 0.0)) + 110.0) if str(profile.get("target_mode", "self")) not in ["self", "self_area"] else 0.0
	var stable_profession_id := str(profile.get("profession_id", profession_id(str(profile.get("profession", "")))))
	if stable_profession_id == "warrior":
		var level := WarriorCombatMath.clamp_skill_level(maxi(0, learned_level))
		profile["skill_level"] = level
		profile["source"] = "M2Server/ObjBase.pas + Client/Actor.pas"
		profile["confidence"] = "A"
		profile["verification"] = "服务端公式、开关/蓄力状态机与客户端6帧×85ms动作已核对"
	elif stable_profession_id == "wizard":
		profile.merge(WizardCombatMath.profile_overrides(stable_id, maxi(0, learned_level)), true)
		profile["verification"] = "法师专属公式层候选；字段来源见profession_combat_rules.json"
	elif stable_profession_id == "taoist":
		profile.merge(TaoistCombatMath.profile_overrides(stable_id, maxi(0, learned_level)), true)
		profile["verification"] = "道士专属公式层候选；字段来源见profession_combat_rules.json"
	else:
		profile["verification"] = "未识别职业的兼容档案"
	return profile


static func primary_damage_range(profession: String, stats: Dictionary) -> Vector2i:
	match profession_display_name(profession):
		"法师": return Vector2i(int(stats.get("magic_min", 0)), int(stats.get("magic_max", 0)))
		"道士": return Vector2i(int(stats.get("tao_min", 0)), int(stats.get("tao_max", 0)))
		_: return Vector2i(int(stats.get("attack_min", 1)), int(stats.get("attack_max", 1)))


static func player_struck_damage_threshold(max_hp_value: int) -> int:
	var policy: Dictionary = _data().get("combatReactionPolicy", COMBAT_REACTION_POLICY)
	var ratio := maxf(0.0, float(policy.get("max_hp_ratio", COMBAT_REACTION_POLICY.max_hp_ratio)))
	var minimum := maxi(1, int(policy.get("minimum_actual_damage", COMBAT_REACTION_POLICY.minimum_actual_damage)))
	return maxi(minimum, ceili(float(maxi(1, max_hp_value)) * ratio))


static func should_player_stagger(actual_damage: int, max_hp_value: int) -> bool:
	return actual_damage >= player_struck_damage_threshold(max_hp_value)


static func player_struck_action_lock_seconds() -> float:
	var policy: Dictionary = _data().get("combatReactionPolicy", COMBAT_REACTION_POLICY)
	return maxf(0.0, float(policy.get("server_action_lock_seconds", COMBAT_REACTION_POLICY.server_action_lock_seconds)))


static func player_struck_reaction_seconds() -> float:
	var policy: Dictionary = _data().get("combatReactionPolicy", COMBAT_REACTION_POLICY)
	return maxf(0.0, float(policy.get("reaction_animation_seconds", COMBAT_REACTION_POLICY.reaction_animation_seconds)))


static func missing_runtime_skills(skill_rows: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for row: Variant in skill_rows:
		if not row is Dictionary or int(row.get("skillLevel", -1)) != 0:
			continue
		var skill_name := str(row.get("skillName", ""))
		var stable_id := str(row.get("skill_id", skill_id(skill_name)))
		if not skill_name.is_empty() and skill_profile(stable_id if not stable_id.is_empty() else skill_name).is_empty() and not missing.has(skill_name):
			missing.append(skill_name)
	return missing
