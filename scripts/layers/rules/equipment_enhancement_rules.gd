class_name EquipmentEnhancementRules
extends RefCounted

const CONTRACT_ID := "equipment.enhancement.instance.v1"
const RULES_CONTRACT_ID := "equipment.enhancement.rules.v1"
const RULES_PATH := "res://assets/data/equipment_enhancement_rules_v1.json"
const WEAPON_STATS := [&"attack_max", &"magic_max", &"tao_max"]
const ARMOR_STATS := [&"defense_max", &"magic_defense_max"]

static var _rules: Dictionary = {}
static var _load_failed := false


static func _config() -> Dictionary:
	if not _rules.is_empty() or _load_failed:
		return _rules
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(RULES_PATH))
	if not data is Dictionary or str(data.get("contract_id", "")) != RULES_CONTRACT_ID:
		_load_failed = true
		return {}
	for field: String in ["weapon_stage_base_bps", "armor_stage_base_bps", "weapon_accessory_penalty_by_stage_bps", "armor_accessory_penalty_by_stage_bps", "weapon_gold_cost", "armor_gold_cost"]:
		if not data.get(field) is Array:
			_load_failed = true
			return {}
	if (data.weapon_stage_base_bps as Array).size() != 7 or (data.armor_stage_base_bps as Array).size() != 3:
		_load_failed = true
		return {}
	_rules = data
	return _rules


static func max_stage(category: String) -> int:
	match category:
		"武器": return 7
		"盔甲", "衣服", "头盔": return 3
	return 0


static func black_iron_bonus_bps(purity: int) -> int:
	var config := _config()
	if config.is_empty() or purity < int(config.black_iron_min_purity) or purity > int(config.black_iron_max_purity):
		return -1
	return int(config.black_iron_bonus_at_min_bps) + (purity - int(config.black_iron_min_purity)) * int(config.black_iron_bonus_step_bps)


static func accessory_grade_penalty_bps(category: String, next_stage: int, target_grade: int, accessory_grade: int) -> int:
	var config := _config()
	var cap := max_stage(category)
	if config.is_empty() or next_stage < 1 or next_stage > cap or target_grade < 0 or target_grade > 3 or accessory_grade < 0 or accessory_grade > 3:
		return -1
	var rates: Array = config.weapon_accessory_penalty_by_stage_bps if category == "武器" else config.armor_accessory_penalty_by_stage_bps
	return maxi(0, target_grade - accessory_grade) * int(rates[next_stage - 1])


static func quote_probability(category: String, next_stage: int, purity: int, target_grade: int, accessory_a_grade: int, accessory_b_grade: int) -> Dictionary:
	var config := _config()
	var cap := max_stage(category)
	var iron_bonus := black_iron_bonus_bps(purity)
	var penalty_a := accessory_grade_penalty_bps(category, next_stage, target_grade, accessory_a_grade)
	var penalty_b := accessory_grade_penalty_bps(category, next_stage, target_grade, accessory_b_grade)
	if config.is_empty() or next_stage < 1 or next_stage > cap or iron_bonus < 0 or penalty_a < 0 or penalty_b < 0:
		return {}
	var bases: Array = config.weapon_stage_base_bps if category == "武器" else config.armor_stage_base_bps
	var scale := int(config.weapon_difficulty_scale_bps) if category == "武器" else int(config.armor_difficulty_scale_bps)
	var base := int(bases[next_stage - 1])
	var raw := base + iron_bonus - penalty_a - penalty_b
	var scaled := (raw * scale + 5000) / 10000
	return {
		"base_success_bps": base,
		"black_iron_bonus_bps": iron_bonus,
		"accessory_a_penalty_bps": penalty_a,
		"accessory_b_penalty_bps": penalty_b,
		"raw_success_bps": raw,
		"difficulty_scale_bps": scale,
		"final_success_bps": clampi(scaled, int(config.minimum_success_bps), int(config.maximum_success_bps)),
	}


static func forge_gold_cost(category: String, next_stage: int) -> int:
	var config := _config()
	if config.is_empty() or next_stage < 1 or next_stage > max_stage(category):
		return -1
	var costs: Array = config.weapon_gold_cost if category == "武器" else config.armor_gold_cost
	return int(costs[next_stage - 1])


static func forge_attribute_weights(accessory_a: Dictionary, accessory_b: Dictionary) -> Dictionary:
	var weights := {"attack_max": 0, "magic_max": 0, "tao_max": 0}
	for item: Dictionary in [accessory_a, accessory_b]:
		for entry: Array in [["attack_max", "attackMax"], ["magic_max", "magicMax"], ["tao_max", "taoMax"]]:
			var base_value: Variant = item.get(entry[1], 0)
			weights[entry[0]] += maxi(0, int(base_value) if base_value != null else 0)
		for modifier: Variant in item.get("modifiers", []):
			if modifier is Dictionary and str(modifier.get("stat", "")) in weights and str(modifier.get("op", "")) == "add":
				weights[str(modifier.stat)] += maxi(0, int(modifier.get("value", 0)))
	if weights.attack_max + weights.magic_max + weights.tao_max == 0:
		return {"attack_max": 1, "magic_max": 1, "tao_max": 1}
	return weights


static func forge_stage(instance: Dictionary) -> int:
	var enhancement: Variant = instance.get("enhancement", {})
	if not enhancement is Dictionary:
		return -1
	var forge: Variant = enhancement.get("forge", {})
	return int(forge.get("stage", 0)) if forge is Dictionary else -1


static func validate_enhancement(enhancement: Variant, category: String) -> bool:
	if not enhancement is Dictionary or enhancement.size() != 2 or str(enhancement.get("contract_id", "")) != CONTRACT_ID:
		return false
	var forge: Variant = enhancement.get("forge", null)
	if not forge is Dictionary or forge.size() != 3:
		return false
	var raw_stage: Variant = forge.get("stage", null)
	var history: Variant = forge.get("history", null)
	var modifiers: Variant = forge.get("modifiers", null)
	if not raw_stage is int or not history is Array or not modifiers is Array:
		return false
	var stage: int = raw_stage
	if stage < 0 or stage > max_stage(category) or history.size() != stage:
		return false
	var totals := {}
	for stat: Variant in history:
		if category == "武器":
			if str(stat) not in WEAPON_STATS:
				return false
			totals[str(stat)] = int(totals.get(str(stat), 0)) + 1
		else:
			if str(stat) != "defense_max":
				return false
			totals["defense_max"] = int(totals.get("defense_max", 0)) + 1
			totals["magic_defense_max"] = int(totals.get("magic_defense_max", 0)) + 1
	if modifiers.size() != totals.size():
		return false
	var seen := {}
	for value: Variant in modifiers:
		if not value is Dictionary or value.size() != 3 or str(value.get("op", "")) != "add":
			return false
		var stat := str(value.get("stat", ""))
		if seen.has(stat) or not value.get("value") is int or int(value.value) != int(totals.get(stat, -1)):
			return false
		seen[stat] = true
	return true
