class_name ProfessionRules
extends RefCounted

const PROFESSIONS: Array[String] = ["战士", "法师", "道士"]

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
	"烈火剑法": {"profession": "战士", "cast_type": "melee", "multiplier": 1.0, "range": 105.0, "service_magic_id": 26, "service_mode": "arm_next_hit"},
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
	"烈火剑法": {"windup": 0.17, "hit_frame": 2, "cooldown": 0.85, "action_duration": 0.51, "service_arm_cooldown": 10.0},
}

static var _runtime_data: Dictionary = {}


static func _data() -> Dictionary:
	if not _runtime_data.is_empty():
		return _runtime_data
	var path := ContentLayers.vanilla_dataset("professionGrowth")
	var file := FileAccess.open(path, FileAccess.READ) if FileAccess.file_exists(path) else null
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_runtime_data = parsed if parsed is Dictionary else {
		"baseStats": BASE_STATS, "skillProfiles": SKILL_PROFILES,
		"castDefaults": CAST_DEFAULTS, "skillTimingOverrides": SKILL_TIMING_OVERRIDES,
	}
	return _runtime_data


static func is_valid_profession(value: String) -> bool:
	return value in PROFESSIONS


static func stats_for_level(profession: String, level: int) -> Dictionary:
	var selected := profession if is_valid_profession(profession) else "战士"
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


static func skill_profile(skill_name: String) -> Dictionary:
	return _data().get("skillProfiles", SKILL_PROFILES).get(skill_name, {})


static func skill_combat_profile(skill_name: String, learned_level := -1) -> Dictionary:
	var profile: Dictionary = skill_profile(skill_name).duplicate(true)
	if profile.is_empty():
		return profile
	var cast_type := str(profile.get("cast_type", "melee"))
	var cast_defaults: Dictionary = _data().get("castDefaults", CAST_DEFAULTS)
	var timing_overrides: Dictionary = _data().get("skillTimingOverrides", SKILL_TIMING_OVERRIDES)
	profile.merge(cast_defaults.get(cast_type, cast_defaults["melee"]), false)
	profile.merge(timing_overrides.get(skill_name, {}), true)
	profile["search_range"] = maxf(280.0, float(profile.get("range", 0.0)) + 110.0) if str(profile.get("target_mode", "self")) not in ["self", "self_area"] else 0.0
	if str(profile.get("profession", "")) == "战士":
		var level := WarriorCombatMath.clamp_skill_level(maxi(0, learned_level))
		profile["skill_level"] = level
		profile["source"] = "M2Server/ObjBase.pas + Client/Actor.pas"
		profile["confidence"] = "A"
		profile["verification"] = "服务端公式、开关/蓄力状态机与客户端6帧×85ms动作已核对"
	else:
		profile["verification"] = "运行时候选；动画与手机操作基线"
	return profile


static func primary_damage_range(profession: String, stats: Dictionary) -> Vector2i:
	match profession:
		"法师": return Vector2i(int(stats.get("magic_min", 0)), int(stats.get("magic_max", 0)))
		"道士": return Vector2i(int(stats.get("tao_min", 0)), int(stats.get("tao_max", 0)))
		_: return Vector2i(int(stats.get("attack_min", 1)), int(stats.get("attack_max", 1)))


static func missing_runtime_skills(skill_rows: Array) -> PackedStringArray:
	var missing := PackedStringArray()
	for row: Variant in skill_rows:
		if not row is Dictionary or int(row.get("skillLevel", -1)) != 0:
			continue
		var skill_name := str(row.get("skillName", ""))
		if not skill_name.is_empty() and not _data().get("skillProfiles", SKILL_PROFILES).has(skill_name) and not missing.has(skill_name):
			missing.append(skill_name)
	return missing
