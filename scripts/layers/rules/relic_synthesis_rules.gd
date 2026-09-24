class_name RelicSynthesisRules
extends RefCounted

const CONTRACT_ID := "equipment.relic_synthesis.v1"
const DATA_PATH := "res://assets/data/relic_synthesis_v1.json"
const FRAGMENT_ID := 950001
const FRAGMENT_COUNT := 4
const GOLD_COST := 400000
const PROC_CHANCE_PERCENT := 20
const PROC_DURATION_SECONDS := 10.0
const PROC_COOLDOWN_SECONDS := 15.0
const SkillData := preload("res://scripts/skills/skill_data_loader.gd")
const SkillRankPolicy := preload("res://scripts/skills/skill_rank_extension_policy.gd")
const SKILL_NAMES := {
	"战士": ["基本剑术", "攻杀剑术", "刺杀剑术", "半月弯刀", "烈火剑法"],
	"法师": ["雷电术", "地狱雷光", "疾光电影", "火墙", "冰咆哮", "爆裂火焰"],
	"道士": ["灵魂火符", "施毒术", "召唤骷髅", "召唤神兽", "治愈术", "群体治疗术"],
}

static var _records_by_id: Dictionary = {}
static var _loaded := false


static func records() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item_id: int in [950101, 950102, 950103]:
		if _records_by_id.has(item_id):
			result.append((_records_by_id[item_id] as Dictionary).duplicate(true))
	return result


static func record_for_id(item_id: int) -> Dictionary:
	_ensure_loaded()
	return (_records_by_id.get(item_id, {}) as Dictionary).duplicate(true)


static func is_relic(item_id: int) -> bool:
	_ensure_loaded()
	return _records_by_id.has(item_id)


static func effect_for(item_id: int) -> String:
	return str(record_for_id(item_id).get("relicEffect", ""))


static func skill_ids_for(profession: String) -> Array[String]:
	var result: Array[String] = []
	var seen := {}
	for raw_name: String in SKILL_NAMES.get(profession, []):
		var stable_id := SkillData.stable_skill_id(raw_name)
		if stable_id.is_empty() or not SkillRankPolicy.can_extend(stable_id) or seen.has(stable_id):
			push_error("圣物随机技能清单无效：%s/%s" % [profession, raw_name])
			return []
		seen[stable_id] = true
		result.append(stable_id)
	return result


static func roll_instance(item_id: int, profession: String, rng: RandomNumberGenerator) -> Dictionary:
	var record := record_for_id(item_id)
	var skill_ids := skill_ids_for(profession)
	if record.is_empty() or skill_ids.is_empty() or rng == null:
		return {}
	var skill_id := skill_ids[rng.randi_range(0, skill_ids.size() - 1)]
	var modifiers: Array = [{"stat": "skill_level", "op": "add", "scope": "skill:" + skill_id, "value": 1}]
	var heart_maxima := {}
	if item_id == 950102:
		for stat: String in ["attack", "magic", "tao"]:
			var value := rng.randi_range(3, 5)
			heart_maxima[stat] = value
			modifiers.append({"stat": stat + "_max", "op": "add", "value": value})
	return {
		"name": str(record.name),
		"item_id": item_id,
		"count": 1,
		"modifiers": modifiers,
		"relic_roll": {"contract_id": CONTRACT_ID, "skill_id": skill_id, "heart_maxima": heart_maxima},
	}


static func valid_instance(instance: Dictionary, item_id: int) -> bool:
	if (not is_relic(item_id)
		or int(instance.get("item_id", -1)) != item_id
		or str(instance.get("name", "")) != str(record_for_id(item_id).get("name", ""))
		or int(instance.get("count", 0)) != 1):
		return false
	var roll: Variant = instance.get("relic_roll", {})
	if not roll is Dictionary or str(roll.get("contract_id", "")) != CONTRACT_ID:
		return false
	var skill_id := str(roll.get("skill_id", ""))
	var known := false
	for profession: String in SKILL_NAMES:
		if skill_ids_for(profession).has(skill_id):
			known = true
	if not known:
		return false
	var maxima: Variant = roll.get("heart_maxima", {})
	if not maxima is Dictionary:
		return false
	var expected: Array = [{"stat": "skill_level", "op": "add", "scope": "skill:" + skill_id, "value": 1}]
	if item_id == 950102:
		if maxima.size() != 3:
			return false
		for stat: String in ["attack", "magic", "tao"]:
			var raw_maximum: Variant = maxima.get(stat, -1)
			if not (raw_maximum is int or raw_maximum is float) or float(raw_maximum) != float(int(raw_maximum)):
				return false
			var value := int(raw_maximum)
			if value < 3 or value > 5:
				return false
			expected.append({"stat": stat + "_max", "op": "add", "value": value})
	elif not maxima.is_empty():
		return false
	var actual: Variant = instance.get("modifiers", [])
	if not actual is Array or (actual as Array).size() != expected.size():
		return false
	for index in expected.size():
		var entry: Variant = actual[index]
		var wanted: Dictionary = expected[index]
		if not entry is Dictionary or (entry as Dictionary).size() != wanted.size():
			return false
		for key: String in wanted:
			if not (entry as Dictionary).has(key):
				return false
			if key == "value":
				var raw_value: Variant = entry[key]
				if not (raw_value is int or raw_value is float) or float(raw_value) != float(wanted[key]):
					return false
			elif entry[key] != wanted[key]:
				return false
	return true


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary or str(parsed.get("contract_id", "")) != CONTRACT_ID:
		push_error("圣物合成权威数据无效")
		return
	if (int(parsed.get("fragment_item_id", -1)) != FRAGMENT_ID
		or int(parsed.get("fragment_count", -1)) != FRAGMENT_COUNT
		or int(parsed.get("gold_cost", -1)) != GOLD_COST
		or int(parsed.get("success_percent", -1)) != 100
		or int(parsed.get("required_level", -1)) != 35):
		push_error("圣物合成合同字段不一致")
		return
	var raw_items: Variant = parsed.get("items", [])
	if not raw_items is Array or raw_items.size() != 3:
		push_error("圣物合成配方数量不正确")
		return
	var expected_names := {950101: "魔龙之眼", 950102: "魔龙之心", 950103: "幸运守护"}
	var expected_effects := {950101: "speed", 950102: "damage", 950103: "luck"}
	for raw: Variant in raw_items:
		if not raw is Dictionary:
			_records_by_id.clear()
			return
		var item_id := int(raw.get("item_id", -1))
		var inventory_icon := str(raw.get("inventory_icon", ""))
		var ground_icon := str(raw.get("ground_icon", ""))
		if (_records_by_id.has(item_id) or str(raw.get("name", "")) != str(expected_names.get(item_id, ""))
			or str(raw.get("effect", "")) != str(expected_effects.get(item_id, ""))
			or not ResourceLoader.exists(inventory_icon) or not ResourceLoader.exists(ground_icon)):
			_records_by_id.clear()
			push_error("圣物身份或图标无效：%d" % item_id)
			return
		var record := {
			"itemId": item_id, "name": str(raw.name), "kind": "equipment", "category": "圣物",
			"weight": 0, "stackable": false, "maxStack": 1, "maxDurability": 1,
			"requirementType": "level", "requirementValue": 35,
			"relicEffect": str(raw.effect), "relicNoWear": true,
			"art": {
				"inventoryIcon": {"path": inventory_icon, "displaySize": [56, 56]},
				"groundIcon": {"path": ground_icon, "displaySize": [36, 36]},
			},
			"source": {"contract_id": CONTRACT_ID, "distribution": "user.provided"},
		}
		if item_id == 950101:
			record["attackSpeedTier"] = 1
		elif item_id == 950103:
			record["luck"] = 1
		_records_by_id[item_id] = record
