class_name MysteryEquipmentInstanceRules
extends RefCounted

const CONTRACT_ID := "equipment.mystery_random_stats.v1"
const SOURCE_PATH := "res://assets/data/mystery_equipment_random.source.json"
static var _source_loaded := false
static var _source_valid := false
static var _source: Dictionary = {}
static var _source_error := ""

static func source_validation_error() -> String:
	_ensure_source()
	return _source_error

static func is_mystery_item(catalog_or_id: Variant) -> bool:
	_ensure_source()
	if not _source_valid:
		return false
	var item_id := _item_id(catalog_or_id)
	return item_id in [218, 219, 220]

static func create_roll(catalog: Dictionary, stable_drop_key_digest: String) -> Dictionary:
	if not is_mystery_item(catalog) or stable_drop_key_digest.is_empty():
		return {}
	var family := _family(catalog)
	var params: Dictionary = _family_params(family)
	if params.is_empty():
		return {}
	var stats := {
		"defense_max": _roll_count(stable_drop_key_digest, "defense_max", int(params.get("ac_max", 0)), int(params.get("ac_rate", 1))),
		"magic_defense_max": _roll_count(stable_drop_key_digest, "magic_defense_max", int(params.get("mac_max", 0)), int(params.get("mac_rate", 1))),
		"attack_max": _roll_count(stable_drop_key_digest, "attack_max", int(params.get("dc_max", 0)), int(params.get("dc_rate", 1))),
		"magic_max": _roll_count(stable_drop_key_digest, "magic_max", int(params.get("mc_max", 0)), int(params.get("mc_rate", 1))),
		"tao_max": _roll_count(stable_drop_key_digest, "tao_max", int(params.get("sc_max", 0)), int(params.get("sc_rate", 1))),
	}
	var requirement := _requirement(catalog, family, stats)
	if requirement.is_empty():
		return {}
	return {
		"contract_id": CONTRACT_ID,
		"drop_key_digest": stable_drop_key_digest,
		"stats": stats,
		"requirement": requirement,
	}

static func validate_roll(instance: Dictionary, catalog: Dictionary) -> bool:
	if not is_mystery_item(catalog):
		return false
	if _item_id(instance) != _item_id(catalog) or not _integral(instance.get("count", null)) or int(instance.get("count")) != 1:
		return false
	if not instance.has("mystery_roll"):
		return true # pre-roll instances remain load-compatible
	var roll: Variant = instance.get("mystery_roll")
	if not roll is Dictionary:
		return false
	var digest := str(roll.get("drop_key_digest", ""))
	if digest.is_empty():
		return false
	if not instance.has("drop_key_digest") or str(instance.get("drop_key_digest")) != digest:
		return false
	var expected := create_roll(catalog, digest)
	if expected.is_empty():
		return false
	return _strict_roll_equal(roll, expected)

static func modifiers(instance: Dictionary) -> Array:
	var roll: Variant = instance.get("mystery_roll", null)
	if not roll is Dictionary:
		return []
	var stats: Variant = roll.get("stats", null)
	if not stats is Dictionary:
		return []
	var result: Array = []
	for key: String in ["defense_max", "magic_defense_max", "attack_max", "magic_max", "tao_max"]:
		var value := int(stats.get(key, 0))
		if value > 0:
			result.append({"stat": key, "op": "add", "value": value})
	return result

static func requirement(instance: Dictionary) -> Dictionary:
	var roll: Variant = instance.get("mystery_roll", null)
	if roll is Dictionary and roll.get("requirement", null) is Dictionary:
		return (roll.get("requirement") as Dictionary).duplicate(true)
	return {}

static func _item_id(value: Variant) -> int:
	if value is Dictionary:
		var d: Dictionary = value
		if d.has("itemId") and not _integral(d.get("itemId")):
			return -1
		if d.has("item_id") and not _integral(d.get("item_id")):
			return -1
		if d.has("itemId") and d.has("item_id") and int(d.itemId) != int(d.item_id):
			return -1
		if d.has("itemId"):
			return int(d.itemId) if _integral(d.itemId) else -1
		if d.has("item_id"):
			return int(d.item_id) if _integral(d.item_id) else -1
		return -1
	return int(value) if _integral(value) else -1

static func _integral(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number)

static func _int_array_equal(actual: Variant, expected: Array) -> bool:
	if not actual is Array or actual.size() != expected.size():
		return false
	for index in expected.size():
		if not _integral(actual[index]) or int(actual[index]) != int(expected[index]):
			return false
	return true

static func _family(catalog: Dictionary) -> String:
	match _item_id(catalog):
		218: return "helmet"
		219: return "bracelet"
		220: return "ring"
	return ""

static func _family_params(family: String) -> Dictionary:
	_ensure_source()
	var families: Variant = _source.get("families", {})
	if not families is Dictionary:
		return {}
	var spec: Variant = families.get(family, null)
	if not spec is Dictionary:
		return {}
	return {
		"ac_max": int(spec.get("acMax", 0)), "ac_rate": int(spec.get("acRate", 0)),
		"mac_max": int(spec.get("macMax", 0)), "mac_rate": int(spec.get("macRate", 0)),
		"dc_max": int(spec.get("dcMax", 0)), "dc_rate": int(spec.get("dcRate", 0)),
		"mc_max": int(spec.get("mcMax", 0)), "mc_rate": int(spec.get("mcRate", 0)),
		"sc_max": int(spec.get("scMax", 0)), "sc_rate": int(spec.get("scRate", 0))
	}

static func _roll_count(digest: String, key: String, count: int, rate: int) -> int:
	if count <= 0 or rate <= 0:
		return 0
	var rng := RandomNumberGenerator.new()
	var seed_hex := (digest + ":mystery_equipment_random:v1:" + key).sha256_text().substr(0, 15)
	rng.seed = seed_hex.hex_to_int()
	var result := 0
	for index in count:
		if rng.randi_range(0, rate - 1) == 0:
			result += 1
	return result

static func _requirement(catalog: Dictionary, family: String, stats: Dictionary) -> Dictionary:
	var upgrade := 0
	for key in stats:
		upgrade += int(stats[key])
	var base_value := _base_requirement_value(catalog)
	if base_value < 0:
		return {}
	var base := {"type": "level", "value": base_value}
	if family == "helmet" and upgrade >= 3:
		if int(stats.defense_max) >= 5: return {"type": "attack", "value": int(stats.defense_max) * 3 + 25}
		if int(stats.attack_max) >= 2: return {"type": "attack", "value": int(stats.attack_max) * 4 + 35}
		if int(stats.magic_max) >= 2: return {"type": "magic", "value": int(stats.magic_max) * 2 + 18}
		if int(stats.tao_max) >= 2: return {"type": "tao", "value": int(stats.tao_max) * 2 + 18}
	if family == "ring" and upgrade >= 3:
		if int(stats.attack_max) >= 3: return {"type": "attack", "value": int(stats.attack_max) * 3 + 25}
		if int(stats.magic_max) >= 3: return {"type": "magic", "value": int(stats.magic_max) * 2 + 18}
		if int(stats.tao_max) >= 3: return {"type": "tao", "value": int(stats.tao_max) * 2 + 18}
	if family == "bracelet" and upgrade >= 2:
		if int(stats.defense_max) >= 3: return {"type": "attack", "value": int(stats.defense_max) * 3 + 25}
		if int(stats.attack_max) >= 2: return {"type": "attack", "value": int(stats.attack_max) * 3 + 30}
		if int(stats.magic_max) >= 2: return {"type": "magic", "value": int(stats.magic_max) * 2 + 20}
		if int(stats.tao_max) >= 2: return {"type": "tao", "value": int(stats.tao_max) * 2 + 20}
	if upgrade >= (3 if family != "bracelet" else 2):
		return {"type": "level", "value": upgrade * 2 + 18}
	return base

static func _strict_roll_equal(actual: Dictionary, expected: Dictionary) -> bool:
	if actual.keys().size() != 4:
		return false
	for key: String in ["contract_id", "drop_key_digest", "stats", "requirement"]:
		if not actual.has(key):
			return false
	if str(actual.get("contract_id", "")) != str(expected.get("contract_id", "")):
		return false
	if str(actual.get("drop_key_digest", "")) != str(expected.get("drop_key_digest", "")):
		return false
	var actual_stats: Variant = actual.get("stats", null)
	var expected_stats: Variant = expected.get("stats", null)
	if not actual_stats is Dictionary or not expected_stats is Dictionary or actual_stats.keys().size() != expected_stats.keys().size():
		return false
	for key: String in ["defense_max", "magic_defense_max", "attack_max", "magic_max", "tao_max"]:
		if not actual_stats.has(key) or not _integral(actual_stats.get(key)) or int(actual_stats.get(key)) != int(expected_stats.get(key, -1)):
			return false
	var actual_requirement: Variant = actual.get("requirement", null)
	var expected_requirement: Variant = expected.get("requirement", null)
	if not actual_requirement is Dictionary or not expected_requirement is Dictionary:
		return false
	if actual_requirement.keys().size() != 2 or not actual_requirement.has("type") or not actual_requirement.has("value"):
		return false
	return str(actual_requirement.get("type", "")) == str(expected_requirement.get("type", "")) and _integral(actual_requirement.get("value")) and int(actual_requirement.get("value")) == int(expected_requirement.get("value", -1))

static func _base_requirement_value(catalog: Dictionary) -> int:
	if catalog.has("requirementValue") and _integral(catalog.get("requirementValue")):
		return int(catalog.get("requirementValue"))
	var service: Variant = catalog.get("serviceRequirement", null)
	if service is Dictionary and _integral(service.get("value", null)):
		return int(service.get("value"))
	var requirement: Variant = catalog.get("requirement", null)
	if requirement is Dictionary and _integral(requirement.get("value", null)):
		return int(requirement.get("value"))
	return -1

static func _ensure_source() -> void:
	if _source_loaded:
		return
	_source_loaded = true
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOURCE_PATH))
	if not parsed is Dictionary:
		_source_error = "source_json_invalid"
		return
	var candidate: Dictionary = parsed
	if str(candidate.get("contractId", "")) != CONTRACT_ID:
		_source_error = "contract_mismatch"
		return
	var families: Variant = candidate.get("families", null)
	if not families is Dictionary:
		_source_error = "families_missing"
		return
	var expected := {
		"helmet": {"id": 218, "category": "头盔", "std": [15]},
		"bracelet": {"id": 219, "category": "手镯", "std": [24, 26]},
		"ring": {"id": 220, "category": "戒指", "std": [22, 23]},
	}
	for family: String in expected:
		var spec: Variant = families.get(family, null)
		var wanted: Dictionary = expected[family]
		if not spec is Dictionary:
			_source_error = "family_missing:" + family
			return
		if not _int_array_equal(spec.get("catalogItemIds", []), [int(wanted.get("id"))]) or str(spec.get("canonicalCategory", "")) != str(wanted.get("category", "")) or not _int_array_equal(spec.get("legacyStdModeFamily", []), wanted.get("std", [])):
			_source_error = "family_identity_mismatch:" + family
			return
		for key: String in ["acMax", "acRate", "macMax", "macRate", "dcMax", "dcRate", "mcMax", "mcRate", "scMax", "scRate", "upgradeThreshold"]:
			if not spec.has(key) or not _integral(spec.get(key)) or int(spec.get(key)) <= 0:
				_source_error = "family_parameter_missing:" + family + ":" + key
				return
	var policy: Variant = candidate.get("instancePolicy", null)
	if not policy is Dictionary or str(policy.get("rollAt", "")) != "drop_instance_creation" or bool(policy.get("rerollOnEquip", true)) or bool(policy.get("randomDurability", true)):
		_source_error = "instance_policy_mismatch"
		return
	_source = candidate
	_source_valid = true
