class_name ModifierEffectRuntime
extends RefCounted

const STAT_ALIASES := {
	"attack_speed": "attack_speed_percent",
	"cast_speed": "cast_speed_percent",
	"critical": "critical_chance",
	"life_steal": "life_steal_percent",
}


static func apply_modifiers(base_stats: Dictionary, modifiers: Array, context: Dictionary = {}) -> Dictionary:
	var result := base_stats.duplicate(true)
	for modifier: Variant in modifiers:
		if not modifier is Dictionary or not condition_matches(modifier.get("condition", {}), context):
			continue
		var requested_stat := str(modifier.get("stat", ""))
		var stat := str(STAT_ALIASES.get(requested_stat, requested_stat))
		if stat.is_empty():
			continue
		var current := float(result.get(stat, 0.0))
		var value := float(modifier.get("value", 0.0))
		match str(modifier.get("op", "add")):
			"add": current += value
			"percent": current *= 1.0 + value / 100.0
			"multiply": current *= value
			"override": current = value
			_: continue
		result[stat] = current
	return result


static func active_set_effects(equipped_set_counts: Dictionary, set_definitions: Array) -> Array:
	var result: Array = []
	for definition: Variant in set_definitions:
		if not definition is Dictionary:
			continue
		var set_id := str(definition.get("setId", ""))
		var count := int(equipped_set_counts.get(set_id, 0))
		for bonus: Variant in definition.get("bonuses", []):
			if bonus is Dictionary and count >= int(bonus.get("pieces", 999)):
				result.append_array(bonus.get("effects", []))
	return result


static func triggered_effects(trigger_id: String, effects: Array, context: Dictionary, rng: RandomNumberGenerator = null) -> Array:
	var result: Array = []
	for effect: Variant in effects:
		if not effect is Dictionary or str(effect.get("trigger", "")) != trigger_id:
			continue
		if not condition_matches(effect.get("condition", {}), context):
			continue
		var chance := clampf(float(effect.get("chance", 1.0)), 0.0, 1.0)
		if rng == null or rng.randf() <= chance:
			result.append(effect.duplicate(true))
	return result


static func condition_matches(condition: Variant, context: Dictionary) -> bool:
	if not condition is Dictionary or condition.is_empty():
		return true
	var key := str(condition.get("key", ""))
	var actual: Variant = context.get(key)
	var expected: Variant = condition.get("value")
	match str(condition.get("op", "eq")):
		"eq": return actual == expected
		"neq": return actual != expected
		"gte": return float(actual) >= float(expected)
		"lte": return float(actual) <= float(expected)
		"in": return expected is Array and actual in expected
	return false
