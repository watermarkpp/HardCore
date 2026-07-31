class_name WarriorCombatMath
extends RefCounted

const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")

# 来源：M2Server/M2Share.pas DEFHIT/DEFSPEED 与 ObjBase.pas 战士近战实现。
const BASE_HIT := 5
const BASE_AGILITY := 15
const MAX_SKILL_LEVEL := 3
const MAGIC_TRAIN_LEVEL := 3
const SWORD_LONG_POWER_RATE := 100
const HALF_MOON_DIRECTION_OFFSETS := [7, 1, 2]
const CLIENT_ATTACK_FRAMES := 6
const CLIENT_ATTACK_FRAME_MS := 85
const CLIENT_EFFECT_FRAME := 2
const WILD_RUSH_COOLDOWN_MS := 3000
const DAMAGE_RANGE_ROLL_POLICY := "legacy_clamp_negative_span"
const PHYSICAL_HIT_POLICY_ID := CombatResolutionRules.PHYSICAL_HIT_POLICY_ID
const PHYSICAL_ATTACK_SPEED_POLICY_ID := CombatResolutionRules.PHYSICAL_ATTACK_SPEED_POLICY_ID


static func clamp_skill_level(level_value: int) -> int:
	return clampi(level_value, 0, MAX_SKILL_LEVEL)


static func basic_sword_accuracy_bonus(level_value: int) -> int:
	# ObjBase.RecalcHitSpeed: Round(9 / 3 * UserMagic.btLevel)
	return 3 * clamp_skill_level(level_value)


static func slaying_accuracy_bonus(level_value: int) -> int:
	# 攻杀学习后额外增加技能等级点准确。
	return clamp_skill_level(level_value)


static func total_accuracy(item_accuracy: int, basic_level := -1, slaying_level := -1) -> int:
	var result := BASE_HIT + item_accuracy
	if basic_level >= 0:
		result += basic_sword_accuracy_bonus(basic_level)
	if slaying_level >= 0:
		result += slaying_accuracy_bonus(slaying_level)
	return result


static func hit_succeeds(accuracy: int, target_agility: int, random_roll: int) -> bool:
	return CombatResolutionRules.physical_hit_succeeds(accuracy, target_agility, random_roll)


static func hit_probability(accuracy: int, target_agility: int) -> float:
	return CombatResolutionRules.physical_hit_probability(accuracy, target_agility)


static func roll_hit(accuracy: int, target_agility: int, rng: RandomNumberGenerator) -> bool:
	return CombatResolutionRules.roll_physical_hit(accuracy, target_agility, rng)


static func physical_attack_interval_ms(attack_speed_tier: int) -> int:
	return CombatResolutionRules.physical_attack_interval_ms(attack_speed_tier)


static func physical_attack_interval_seconds(attack_speed_tier: int) -> float:
	return CombatResolutionRules.physical_attack_interval_seconds(attack_speed_tier)


static func attack_power_for_roll(attack_min: int, attack_max: int, roll: int) -> int:
	var span := maxi(0, attack_max - attack_min)
	return attack_min + clampi(roll, 0, span)


static func roll_primary_stat(stat_min: int, stat_max: int, total_luck: int, rng: RandomNumberGenerator) -> int:
	# Primary source: M2Server/ObjBase.pas GetAttackPower receives the final
	# DC/MC/SC low endpoint as nBasePower and clamps a negative high-low span
	# to zero. Endpoint order is therefore semantic and must never be normalized.
	var span := maxi(0, stat_max - stat_min)
	if span == 0:
		return stat_min
	if total_luck > 0:
		var maximum_gate := maxi(1, 10 - mini(9, total_luck))
		if rng.randi_range(0, maximum_gate - 1) == 0:
			return stat_min + span
	var result := stat_min + rng.randi_range(0, span)
	if total_luck < 0:
		var minimum_gate := maxi(1, 10 - mini(9, -total_luck))
		if rng.randi_range(0, minimum_gate - 1) == 0:
			return stat_min
	return result


static func roll_attack_power(attack_min: int, attack_max: int, total_luck: int, rng: RandomNumberGenerator) -> int:
	return roll_primary_stat(attack_min, attack_max, total_luck, rng)


static func slaying_proc_cycle(level_value: int) -> int:
	# m_btAttackSkillCount := 7 - level；每轮随机选择一个触发点。
	return 7 - clamp_skill_level(level_value)


static func slaying_damage(base_damage: int, level_value: int) -> int:
	# m_nHitPlus := DEFHIT + level；触发时 Inc(nPower, m_nHitPlus)。
	return maxi(1, base_damage + BASE_HIT + clamp_skill_level(level_value))


static func thrust_secondary_damage(base_damage: int, level_value: int, sword_long_rate := SWORD_LONG_POWER_RATE) -> int:
	var level := clamp_skill_level(level_value)
	var scaled := roundi(float(base_damage) / float(MAGIC_TRAIN_LEVEL + 2) * float(level + 2))
	return maxi(1, roundi(float(scaled) * float(sword_long_rate) / 100.0))


static func half_moon_secondary_damage(base_damage: int, level_value: int) -> int:
	var level := clamp_skill_level(level_value)
	return maxi(1, roundi(float(base_damage) / float(MAGIC_TRAIN_LEVEL + 10) * float(level + 2)))


static func fire_sword_multiplier(level_value: int) -> float:
	# m_nHitDouble=4+level*4；nPower += nPower/100*(m_nHitDouble*10)。
	return 1.4 + 0.4 * float(clamp_skill_level(level_value))


static func fire_sword_damage(base_damage: int, level_value: int) -> int:
	return maxi(1, roundi(float(base_damage) * fire_sword_multiplier(level_value)))


static func wild_rush_success_threshold(skill_level: int, player_level: int, target_level: int) -> int:
	# Compatibility helper: the user-approved runtime is deterministic after the
	# strict lower-level gate. Skill rank no longer changes the success roll.
	return 20 if player_level > target_level else 0


static func wild_rush_success_probability(skill_level: int, player_level: int, target_level: int) -> float:
	return float(wild_rush_success_threshold(skill_level, player_level, target_level)) / 20.0


static func wild_rush_max_cells(skill_level: int) -> int:
	return 3


static func client_attack_duration_seconds() -> float:
	return float(CLIENT_ATTACK_FRAMES * CLIENT_ATTACK_FRAME_MS) / 1000.0


static func client_effect_time_seconds() -> float:
	return float(CLIENT_EFFECT_FRAME * CLIENT_ATTACK_FRAME_MS) / 1000.0


static func active_skill_damage(skill_name: String, base_damage: int, level_value: int) -> int:
	# Legacy formula-only compatibility helper. Production action selection is
	# owned by SkillInputPolicy, where Slaying Swordsmanship can never be a
	# selected body mode; its modifier is resolved once by SkillRuntimeRouter.
	match skill_name:
		"攻杀剑术": return slaying_damage(base_damage, level_value)
		"刺杀剑术": return thrust_secondary_damage(base_damage, level_value)
		"半月弯刀": return half_moon_secondary_damage(base_damage, level_value)
		"烈火剑法": return fire_sword_damage(base_damage, level_value)
		"野蛮冲撞": return 0
	return maxi(1, base_damage)
