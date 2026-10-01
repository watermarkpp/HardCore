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
const Registry := preload("res://scripts/identity/entity_registry.gd")
const Professions := preload("res://scripts/profession_rules.gd")

static var _records_by_id: Dictionary = {}
static var _skill_ids_by_profession: Dictionary = {}
static var _loaded := false


static func records() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for item_id: int in [950101, 950102, 950103, 950201, 950202, 950203]:
		if _records_by_id.has(item_id):
			result.append((_records_by_id[item_id] as Dictionary).duplicate(true))
	return result


static func record_for_id(item_id: int) -> Dictionary:
	_ensure_loaded()
	return (_records_by_id.get(item_id, {}) as Dictionary).duplicate(true)


static func is_relic(item_id: int) -> bool:
	_ensure_loaded()
	return item_id in [950101, 950102, 950103] and _records_by_id.has(item_id)


static func is_badge(item_id: int) -> bool:
	_ensure_loaded()
	return item_id in [950201, 950202, 950203] and _records_by_id.has(item_id)


static func is_synthesis_item(item_id: int) -> bool:
	_ensure_loaded()
	return item_id in [950101, 950102, 950103, 950201, 950202, 950203] and _records_by_id.has(item_id)


static func recipe_professions(item_id: int) -> Array[String]:
	var result: Array[String] = []
	if is_relic(item_id):
		result.assign(["hc.profession.warrior", "hc.profession.wizard", "hc.profession.taoist"])
		return result
	var record := record_for_id(item_id)
	if not record.is_empty():
		result.append(str(record.get("skillProfessionId", "")))
	return result


static func effect_for(item_id: int) -> String:
	return str(record_for_id(item_id).get("relicEffect", ""))


static func skill_ids_for(profession: String) -> Array[String]:
	_ensure_loaded()
	# Exact legacy UI/import translation only. The source pool and runtime
	# lookup are owned by registered profession IDs, never display strings.
	var profession_id := Professions.import_profession_identity(profession)
	var result: Array[String] = []
	result.assign(_skill_ids_by_profession.get(profession_id, []))
	return result


static func roll_instance(item_id: int, profession: String, rng: RandomNumberGenerator) -> Dictionary:
	var record := record_for_id(item_id)
	if not profession.is_empty():
		profession = Professions.import_profession_identity(profession)
		if profession.is_empty(): return {}
	var allowed_professions := recipe_professions(item_id)
	var skill_ids: Array[String] = []
	if profession.is_empty() and is_relic(item_id):
		for candidate: String in allowed_professions:
			skill_ids.append_array(skill_ids_for(candidate))
	elif is_badge(item_id):
		skill_ids = skill_ids_for(allowed_professions[0])
	elif profession in allowed_professions:
		skill_ids = skill_ids_for(profession)
	if record.is_empty() or skill_ids.is_empty() or rng == null:
		return {}
	var skill_id := skill_ids[rng.randi_range(0, skill_ids.size() - 1)]
	var modifiers: Array = [{"stat": "skill_level", "op": "add", "scope": "skill:" + skill_id, "value": 1}]
	var heart_maxima := {}
	if item_id == 950102:
		for stat: String in ["attack", "magic", "tao"]:
			var value := 5
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
	if (not is_synthesis_item(item_id)
		or not _exact_integral_value(instance.get("item_id", null), item_id)
		or (instance.has("name") and not instance.name is String)
		or not _exact_integral_value(instance.get("count", null), 1)):
		return false
	var roll: Variant = instance.get("relic_roll", {})
	if not roll is Dictionary or str(roll.get("contract_id", "")) != CONTRACT_ID:
		return false
	var skill_id := str(roll.get("skill_id", ""))
	var known := false
	for profession: String in recipe_professions(item_id):
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


static func _exact_integral_value(raw: Variant, expected: int) -> bool:
	return (raw is int or raw is float) and float(raw) == float(expected)


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
	if not raw_items is Array or raw_items.size() != 6:
		push_error("圣物合成配方数量不正确")
		return
	var known_ids := [950101, 950102, 950103, 950201, 950202, 950203]
	var expected_effects := {950101: "speed", 950102: "damage", 950103: "luck", 950201: "hp_regen", 950202: "mp_regen", 950203: "mp_regen"}
	var badge_ids := [950201, 950202, 950203]
	var pools: Variant = parsed.get("skill_pools")
	if not pools is Dictionary or pools.size() != 3:
		push_error("圣物职业技能身份关系无效")
		return
	var candidate_pools := {}
	for profession_id: String in ["hc.profession.warrior", "hc.profession.wizard", "hc.profession.taoist"]:
		var pool: Variant = pools.get(profession_id)
		if not pool is Array or pool.is_empty():
			push_error("圣物职业技能身份关系无效")
			return
		var stable_ids: Array[String] = []
		for target: Variant in pool:
			if not target is String or Registry.resolve(target, "skill").is_empty():
				push_error("圣物技能身份无效")
				return
			var stable_id: String = str(Registry.legacy(target, "skill"))
			if not SkillData.is_canonical_skill_id(stable_id) or not SkillRankPolicy.can_extend(stable_id) \
				or stable_ids.has(stable_id) or SkillData.skill(stable_id).get("class") != profession_id.trim_prefix("hc.profession."):
				push_error("圣物技能身份关系冲突")
				return
			stable_ids.append(stable_id)
		stable_ids.make_read_only()
		candidate_pools[profession_id] = stable_ids
	var candidate_records := {}
	for raw: Variant in raw_items:
		if not raw is Dictionary:
			_records_by_id.clear()
			return
		var item_id := int(raw.get("item_id", -1))
		var inventory_icon := str(raw.get("inventory_icon", ""))
		var ground_icon := str(raw.get("ground_icon", ""))
		var profession_id: Variant = raw.get("skill_profession_id", "")
		if (item_id not in known_ids or candidate_records.has(item_id)
			or not raw.get("name") is String or str(raw.name).is_empty()
			or str(raw.get("effect", "")) != str(expected_effects.get(item_id, ""))
			or (item_id in badge_ids and (not profession_id is String or not candidate_pools.has(profession_id)))
			or not ResourceLoader.exists(inventory_icon) or not ResourceLoader.exists(ground_icon)):
			_records_by_id.clear()
			push_error("圣物身份或图标无效：%d" % item_id)
			return
		var record := {
			"itemId": item_id, "name": str(raw.name), "kind": "equipment", "category": "徽章" if item_id in badge_ids else "圣物",
			"weight": 0, "stackable": false, "maxStack": 1, "maxDurability": 1,
			"requirementType": "level", "requirementValue": 35,
			"relicEffect": str(raw.effect), "relicNoWear": true,
			"skillProfession": Professions.profession_display_name(profession_id),
			"skillProfessionId": profession_id,
			"art": {
				"inventoryIcon": {"path": inventory_icon, "displaySize": [32, 32]},
				"groundIcon": {"path": ground_icon, "displaySize": [36, 36]},
			},
			"source": {"contract_id": CONTRACT_ID, "distribution": "user.provided"},
		}
		if item_id == 950101:
			record["attackSpeedTier"] = 1
		elif item_id == 950103:
			record["luck"] = 1
		candidate_records[item_id] = record
	candidate_pools.make_read_only()
	candidate_records.make_read_only()
	_skill_ids_by_profession = candidate_pools
	_records_by_id = candidate_records
