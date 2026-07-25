class_name CombatResolutionRules
extends RefCounted

const CONTRACT_PATH := "res://assets/data/vanilla_176/combat_resolution_contract.json"
const CONTRACT_ID := "combat.resolution.openmir2.v1"
const PHYSICAL_HIT_POLICY_ID := "physical.hit.random_agility.strict_lt.v1"
const MAGIC_EVASION_POLICY_ID := "magic.evasion.anti_magic.direct_spell.v1"
const PHYSICAL_ATTACK_SPEED_POLICY_ID := "physical.attack_speed.interval_tier.v1"
const BASE_CHARACTER_ANTI_MAGIC_POINTS := 1
const ANTI_MAGIC_POINT_DISPLAY_PERCENT := 10
const ANTI_MAGIC_ROLL_SIDES := 10
const BASE_PHYSICAL_ATTACK_INTERVAL_MS := 900
const PHYSICAL_ATTACK_TIER_REDUCTION_MS := 60
const PHYSICAL_ATTACK_MODES := {
	"normal": true,
	"slaying": true,
	"thrust": true,
	"half_moon": true,
	"fire": true,
}
const ANTI_MAGIC_ELIGIBLE_SKILLS := {
	"wizard.fireball": true,
	"wizard.great_fireball": true,
	"wizard.lightning": true,
	"taoist.soul_fire_talisman": true,
}

static var _contract_cache: Dictionary = {}


static func contract() -> Dictionary:
	if not _contract_cache.is_empty():
		return _contract_cache.duplicate(true)
	var file := FileAccess.open(CONTRACT_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	_contract_cache = parsed if parsed is Dictionary else {}
	return _contract_cache.duplicate(true)


static func physical_attack_uses_accuracy(mode: String) -> bool:
	return PHYSICAL_ATTACK_MODES.has(mode)


static func physical_hit_succeeds(accuracy: int, target_agility: int, random_roll: int) -> bool:
	var safe_agility := maxi(1, target_agility)
	var checked_roll := clampi(random_roll, 0, safe_agility - 1)
	return checked_roll < maxi(0, accuracy)


static func physical_hit_probability(accuracy: int, target_agility: int) -> float:
	var safe_agility := maxi(1, target_agility)
	return clampf(float(maxi(0, accuracy)) / float(safe_agility), 0.0, 1.0)


static func roll_physical_hit(accuracy: int, target_agility: int, rng: RandomNumberGenerator) -> bool:
	var safe_agility := maxi(1, target_agility)
	return physical_hit_succeeds(accuracy, safe_agility, rng.randi_range(0, safe_agility - 1))


static func anti_magic_points_from_display_percent(display_percent: int) -> int:
	return clampi(maxi(0, display_percent) / ANTI_MAGIC_POINT_DISPLAY_PERCENT, 0, ANTI_MAGIC_ROLL_SIDES)


static func anti_magic_display_percent(internal_points: int) -> int:
	return clampi(internal_points, 0, ANTI_MAGIC_ROLL_SIDES) * ANTI_MAGIC_POINT_DISPLAY_PERCENT


static func anti_magic_points_from_context(context: Dictionary) -> int:
	if context.has("target_anti_magic_points"):
		return clampi(int(context.target_anti_magic_points), 0, ANTI_MAGIC_ROLL_SIDES)
	if context.has("target_magic_evasion_percent"):
		return anti_magic_points_from_display_percent(int(context.target_magic_evasion_percent))
	return BASE_CHARACTER_ANTI_MAGIC_POINTS


static func anti_magic_points_from_target_stats(target_stats: Dictionary) -> int:
	if target_stats.has("anti_magic_points"):
		return clampi(int(target_stats.anti_magic_points), 0, ANTI_MAGIC_ROLL_SIDES)
	if target_stats.has("magicEvasionPoints"):
		return clampi(int(target_stats.magicEvasionPoints), 0, ANTI_MAGIC_ROLL_SIDES)
	if target_stats.has("antiMagic"):
		return clampi(int(target_stats.antiMagic), 0, ANTI_MAGIC_ROLL_SIDES)
	if target_stats.has("magic_evasion_percent"):
		return anti_magic_points_from_display_percent(int(target_stats.magic_evasion_percent))
	if target_stats.has("magicEvasionPercent"):
		return anti_magic_points_from_display_percent(int(target_stats.magicEvasionPercent))
	return BASE_CHARACTER_ANTI_MAGIC_POINTS


static func anti_magic_eligible(skill_id: String) -> bool:
	return ANTI_MAGIC_ELIGIBLE_SKILLS.has(skill_id)


static func resolve_magic_damage(
	skill_id: String,
	raw_damage: int,
	target_anti_magic_points: int,
	random_0_to_9: int
) -> Dictionary:
	var eligible := anti_magic_eligible(skill_id)
	var points := clampi(target_anti_magic_points, 0, ANTI_MAGIC_ROLL_SIDES)
	var checked_roll := clampi(random_0_to_9, 0, ANTI_MAGIC_ROLL_SIDES - 1)
	var evaded := eligible and checked_roll < points
	var safe_damage := maxi(0, raw_damage)
	return {
		"contract_id": MAGIC_EVASION_POLICY_ID,
		"evasion_channel": "anti_magic" if eligible else "none",
		"anti_magic_eligible": eligible,
		"anti_magic_checked": eligible,
		"anti_magic_points": points,
		"magic_evasion_percent": anti_magic_display_percent(points),
		"anti_magic_roll": checked_roll,
		"magic_evaded": evaded,
		"damage_after_evasion": 0 if evaded else safe_damage,
		"enters_magic_defense_stage": not evaded and safe_damage > 0,
	}


static func resolve_magic_damage_for_target_stats(
	skill_id: String,
	raw_damage: int,
	target_stats: Dictionary,
	random_0_to_9: int
) -> Dictionary:
	return resolve_magic_damage(
		skill_id,
		raw_damage,
		anti_magic_points_from_target_stats(target_stats),
		random_0_to_9
	)


static func resolve_direct_spell_damage(
	skill_id: String,
	raw_damage: int,
	target_stats: Dictionary,
	random_0_to_9: int,
	magic_defense_resolver := Callable()
) -> Dictionary:
	var result := resolve_magic_damage_for_target_stats(
		skill_id,
		raw_damage,
		target_stats,
		random_0_to_9
	)
	result["stage_order"] = ["anti_magic", "magic_defense", "take_damage"]
	result["magic_defense_checked"] = false
	result["final_damage"] = int(result.damage_after_evasion)
	if not bool(result.enters_magic_defense_stage):
		return result
	if magic_defense_resolver is Callable and magic_defense_resolver.is_valid():
		result.magic_defense_checked = true
		result.final_damage = maxi(
			0,
			int(magic_defense_resolver.call(skill_id, int(result.damage_after_evasion), target_stats))
		)
	return result


static func physical_attack_interval_ms(attack_speed_tier: int) -> int:
	return maxi(0, BASE_PHYSICAL_ATTACK_INTERVAL_MS - attack_speed_tier * PHYSICAL_ATTACK_TIER_REDUCTION_MS)


static func physical_attack_interval_seconds(attack_speed_tier: int) -> float:
	return float(physical_attack_interval_ms(attack_speed_tier)) / 1000.0
