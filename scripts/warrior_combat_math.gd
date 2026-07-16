class_name WarriorCombatMath
extends RefCounted

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
	# ObjBase._Attack: if attackerHit < Random(targetSpeed) then miss。
	var safe_agility := maxi(1, target_agility)
	return accuracy >= clampi(random_roll, 0, safe_agility - 1)


static func hit_probability(accuracy: int, target_agility: int) -> float:
	var safe_agility := maxi(1, target_agility)
	return clampf(float(accuracy + 1) / float(safe_agility), 0.0, 1.0)


static func roll_hit(accuracy: int, target_agility: int, rng: RandomNumberGenerator) -> bool:
	var safe_agility := maxi(1, target_agility)
	return hit_succeeds(accuracy, safe_agility, rng.randi_range(0, safe_agility - 1))


static func attack_power_for_roll(attack_min: int, attack_max: int, roll: int) -> int:
	var low := mini(attack_min, attack_max)
	var high := maxi(attack_min, attack_max)
	return low + clampi(roll, 0, high - low)


static func roll_attack_power(attack_min: int, attack_max: int, luck: int, rng: RandomNumberGenerator) -> int:
	var low := mini(attack_min, attack_max)
	var high := maxi(attack_min, attack_max)
	var span := high - low
	if luck > 0:
		var maximum_gate := maxi(1, 10 - mini(9, luck))
		if rng.randi_range(0, maximum_gate - 1) == 0:
			return high
	var result := low + rng.randi_range(0, span)
	if luck < 0:
		var minimum_gate := maxi(1, 10 - mini(9, -luck))
		if rng.randi_range(0, minimum_gate - 1) == 0:
			return low
	return result


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
	if player_level <= target_level:
		return 0
	return clampi(clamp_skill_level(skill_level) * 4 + 6 + player_level - target_level, 0, 20)


static func wild_rush_success_probability(skill_level: int, player_level: int, target_level: int) -> float:
	return float(wild_rush_success_threshold(skill_level, player_level, target_level)) / 20.0


static func wild_rush_max_cells(skill_level: int) -> int:
	# Pascal for 0 to Max(2, level+1) 为包含上界循环。
	return maxi(2, clamp_skill_level(skill_level) + 1) + 1


static func client_attack_duration_seconds() -> float:
	return float(CLIENT_ATTACK_FRAMES * CLIENT_ATTACK_FRAME_MS) / 1000.0


static func client_effect_time_seconds() -> float:
	return float(CLIENT_EFFECT_FRAME * CLIENT_ATTACK_FRAME_MS) / 1000.0


static func active_skill_damage(skill_name: String, base_damage: int, level_value: int) -> int:
	match skill_name:
		"攻杀剑术": return slaying_damage(base_damage, level_value)
		"刺杀剑术": return thrust_secondary_damage(base_damage, level_value)
		"半月弯刀": return half_moon_secondary_damage(base_damage, level_value)
		"烈火剑法": return fire_sword_damage(base_damage, level_value)
		# 野蛮伤害取决于冲撞剩余步数，专属机制任务再接入；当前不伪称为服务端精确值。
		"野蛮冲撞": return maxi(1, roundi(float(base_damage) * 0.8))
	return maxi(1, base_damage)
