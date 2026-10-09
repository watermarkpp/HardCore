class_name EquipmentRandomSpecialInstanceRules
extends RefCounted

const CONTRACT_ID := "equipment.technique_necklace_random_skill.v1"
const TECHNIQUE_NECKLACE_ID := 250
const DATA_PATH := "res://assets/data/relic_synthesis_v1.json"
const EXPECTED_POOL_SIZE := 17

static var _skill_pool: Array[String] = []
static var _loaded := false


static func is_technique_necklace(item_or_id: Variant) -> bool:
	if item_or_id is Dictionary:
		var catalog: Dictionary = item_or_id
		var has_snake := catalog.has("item_id")
		var has_camel := catalog.has("itemId")
		if not has_snake and not has_camel:
			return false
		if has_snake and has_camel and (not _exact_integral(catalog.get("item_id"), TECHNIQUE_NECKLACE_ID) or not _exact_integral(catalog.get("itemId"), TECHNIQUE_NECKLACE_ID)):
			return false
		var raw_id: Variant = catalog.get("item_id", catalog.get("itemId", null))
		return _exact_integral(raw_id, TECHNIQUE_NECKLACE_ID)
	return _exact_integral(item_or_id, TECHNIQUE_NECKLACE_ID)


static func allowed_technique_skill_ids() -> Array[String]:
	_ensure_loaded()
	return _skill_pool.duplicate()


static func create_technique_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	if not is_technique_necklace(catalog_item) or stable_drop_key.is_empty():
		return {}
	_ensure_loaded()
	if _skill_pool.size() != EXPECTED_POOL_SIZE:
		return {}
	var skill_id := _skill_for_digest(stable_drop_key)
	return {
		"item_id": TECHNIQUE_NECKLACE_ID,
		"name": str(catalog_item.get("name", "技巧项链")),
		"count": 1,
		"technique_roll": {
			"contract_id": CONTRACT_ID,
			"drop_key_digest": stable_drop_key,
			"skill_id": skill_id,
			"value": 1,
		},
	}


static func validate_technique_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	if not is_technique_necklace(catalog_item):
		return false
	if not _exact_integral(instance.get("item_id", null), TECHNIQUE_NECKLACE_ID):
		return false
	var count: Variant = instance.get("count", null)
	if not _exact_integral(count, 1):
		return false
	if not instance.has("technique_roll"):
		return true # legacy item 250 instances predate instance rolls
	var roll: Variant = instance.get("technique_roll")
	if not roll is Dictionary:
		return false
	var expected_keys := ["contract_id", "drop_key_digest", "skill_id", "value"]
	if roll.size() != expected_keys.size():
		return false
	for key: String in expected_keys:
		if not roll.has(key):
			return false
	if str(roll.get("contract_id", "")) != CONTRACT_ID:
		return false
	var roll_digest := str(roll.get("drop_key_digest", ""))
	if roll_digest.is_empty():
		return false
	if instance.has("drop_key_digest") and str(instance.get("drop_key_digest", "")) != roll_digest:
		return false
	_ensure_loaded()
	var skill_id := str(roll.get("skill_id", ""))
	if not _skill_pool.has(skill_id) or not _exact_integral(roll.get("value", null), 1):
		return false
	if _skill_for_digest(roll_digest) != skill_id:
		return false
	return true


static func technique_skill_level_modifiers(instance: Dictionary) -> Array:
	_ensure_loaded()
	if not instance.has("technique_roll"):
		return []
	var roll: Variant = instance.get("technique_roll")
	if not roll is Dictionary:
		return []
	var skill_id := str(roll.get("skill_id", ""))
	if skill_id.is_empty() or not _skill_pool.has(skill_id):
		return []
	return [{"stat": "skill_level", "op": "add", "scope": "skill:" + skill_id, "value": 1}]


static func _exact_integral(raw: Variant, expected: int) -> bool:
	return (raw is int or raw is float) and float(raw) == float(expected)


static func _skill_for_digest(drop_key_digest: String) -> String:
	_ensure_loaded()
	if _skill_pool.is_empty() or drop_key_digest.is_empty():
		return ""
	return _skill_pool[int(abs(drop_key_digest.hash())) % _skill_pool.size()]


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		return
	var pools: Variant = parsed.get("skill_pools", null)
	if not pools is Dictionary:
		return
	var seen := {}
	for profession_id: String in ["hc.profession.warrior", "hc.profession.wizard", "hc.profession.taoist"]:
		var pool: Variant = pools.get(profession_id, null)
		if not pool is Array:
			_skill_pool.clear()
			return
		for raw_skill: Variant in pool:
			var skill_id := str(raw_skill)
			if skill_id.is_empty() or seen.has(skill_id):
				_skill_pool.clear()
				return
			seen[skill_id] = true
			_skill_pool.append(skill_id)
	if _skill_pool.size() != EXPECTED_POOL_SIZE:
		_skill_pool.clear()
