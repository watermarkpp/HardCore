class_name ItemDropInstanceRules
extends RefCounted

const AffixV3 := preload("res://scripts/item_drop_affix_v3_rules.gd")

const RULES_PATH := "res://assets/data/item_drop_instance_rules_v1.json"
const INSTANCE_RULES_CONTRACT_ID := "item.drop.instance.rules.v1"
const INSTANCE_CONTRACT_ID := "item.drop.instance.v1"
const AFFIX_CONTRACT_ID := "item.drop.affix.v1"
const ATTRIBUTE_MASTER_CONTRACT_ID := "equipment.attribute.master.v2"
const DURABILITY_CONTRACT_ID := "equipment.durability.raw_authority.v1"
const DURABILITY_RAW_UNITS_PER_DISPLAY := 1000
const MAX_STABLE_DROP_KEY_LENGTH := 512
const MAX_INSTANCE_ID_LENGTH := 128
const MAX_WEAPON_LUCK := 7
const MAX_WEAPON_CURSE := 10
## Persisted item.drop.affix.v1 records have frozen +1 semantics. Runtime rollout
## controls may change generation frequency, but must not reinterpret old saves.
const AFFIX_V1_INCREMENT := 1
const AFFIX_V2_RULES_PATH := "res://assets/data/item_drop_affix_rules_v2.json"
const AFFIX_V2_CONTRACT := "item.drop.affix.v2"
const RULES_V2_CONTRACT := "item.drop.affix.rules.v2"
static var _v2_by_id: Dictionary = {}
static var _v2_expected_cache: Dictionary = {}

static var _rules_cache: Dictionary = {}
static var _master_by_item_id: Dictionary = {}
static var _load_attempted := false
static var _validated_snapshots: Dictionary = {}


## Parse and validate the immutable affix catalog during startup, before loot
## can be created on a gameplay frame.
static func prepare_runtime() -> bool:
	return _ensure_loaded() and AffixV3.ensure_loaded(_master_by_item_id.keys())


static func create_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	var instance := create_legacy_instance(catalog_item, stable_drop_key)
	if instance.is_empty():
		return {}
	# Extension equipment outside the 175-ID authority keeps the existing plain
	# instance contract. It must not disappear or borrow another item's JP type.
	if not _master_by_item_id.has(int(instance.item_id)):
		return instance
	if not AffixV3.ensure_loaded(_master_by_item_id.keys()):
		return {}
	var expected := AffixV3.for_seed(int(instance.item_id), str(instance.drop_key_digest))
	if expected.is_empty():
		return {}
	instance["drop_rules_contract_id"] = AffixV3.CONTRACT
	instance["modifiers"] = expected.modifiers
	var maximum := mini(AffixV3.MAXIMUM_DURABILITY_RAW, int(instance.max_durability_raw) + int(expected.durability_bonus_raw))
	instance["durability_raw"] = maximum
	instance["max_durability_raw"] = maximum
	instance["durability"] = int(ceil(maximum / 1000.0))
	instance["max_durability"] = instance.durability
	instance["drop_affix"] = {"contract_id": AffixV3.AFFIX_CONTRACT, "applied": not expected.modifiers.is_empty() or int(expected.durability_bonus_raw) > 0}
	return instance if validate_instance(instance, catalog_item) else {}


static func create_v2_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	var instance := create_legacy_instance(catalog_item, stable_drop_key)
	if instance.is_empty() or not _ensure_v2_loaded():
		return {}
	var modifiers := _v2_modifiers(int(instance.item_id), str(instance.drop_key_digest))
	instance["drop_rules_contract_id"] = RULES_V2_CONTRACT
	instance["modifiers"] = modifiers
	instance["drop_affix"] = {"contract_id": AFFIX_V2_CONTRACT, "applied": not modifiers.is_empty()}
	return instance if validate_instance(instance, catalog_item) else {}


static func create_legacy_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	if not _ensure_loaded() or not _valid_stable_drop_key(stable_drop_key):
		return {}
	var item_id := _exact_positive_integer(catalog_item.get("itemId", null))
	if item_id < 0 or str(catalog_item.get("kind", "")) != "equipment":
		return {}
	var master: Dictionary = _master_by_item_id.get(item_id, {})
	var item_name := str(catalog_item.get("name", ""))
	if item_name.is_empty():
		return {}
	var drop_key_digest := (
		"%s|%d|%s" % [INSTANCE_CONTRACT_ID, item_id, stable_drop_key]
	).sha256_text().to_lower()
	var candidates := _eligible_stat_mappings(master)
	var affix := _empty_affix()
	var modifiers: Array = []
	var roll: Dictionary = _rules_cache.get("affix_roll", {})
	var numerator := int(roll.get("numerator", 0))
	var denominator := int(roll.get("denominator", 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = ("0x" + drop_key_digest.substr(0, 15)).hex_to_int()
	if (
		bool(_rules_cache.get("enabled", false))
		and not candidates.is_empty()
		and rng.randi_range(1, denominator) <= numerator
	):
		var mapping: Dictionary = candidates[rng.randi_range(0, candidates.size() - 1)]
		affix = {
			"contract_id": AFFIX_CONTRACT_ID,
			"applied": true,
			"source_stat": str(mapping.get("source_stat", "")),
			"stat": str(mapping.get("runtime_stat", "")),
			"op": "add",
			"value": AFFIX_V1_INCREMENT,
		}
		modifiers.append({
			"stat": affix["stat"],
			"op": "add",
			"value": affix["value"],
		})
	var maximum := maxi(1, int(catalog_item.get("maxDurability", 1)))
	var instance := {
		"drop_instance_contract_id": INSTANCE_CONTRACT_ID,
		"drop_rules_contract_id": INSTANCE_RULES_CONTRACT_ID,
		"drop_key_digest": drop_key_digest,
		"item_id": item_id,
		"name": item_name,
		"count": 1,
		"instance_id": "drop:v1:%d:%s" % [item_id, drop_key_digest.substr(0, 24)],
		"durability": maximum,
		"max_durability": maximum,
		"durability_raw": maximum * DURABILITY_RAW_UNITS_PER_DISPLAY,
		"max_durability_raw": maximum * DURABILITY_RAW_UNITS_PER_DISPLAY,
		"durability_contract_id": DURABILITY_CONTRACT_ID,
		"modifiers": modifiers,
		"drop_affix": affix,
	}
	if str(catalog_item.get("category", "")) == "武器":
		instance["weapon_luck"] = 0
		instance["weapon_curse"] = 0
	return instance if validate_instance(instance, catalog_item) else {}


static func validate_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	# Transactions validate identical immutable drop payloads repeatedly (profile,
	# shared file, WAL and readback). Reuse a positive result only for a complete
	# equal payload and all catalog fields consumed by the validator. A changed
	# durability, luck, modifier, unknown field or identity always revalidates.
	var key := str(instance.get("instance_id", "")) + ":" + str(hash(instance))
	var catalog_signature: Array = []
	for field: String in ["itemId", "kind", "name", "category", "maxDurability"]:
		catalog_signature.append(catalog_item.get(field, null))
	var cached: Dictionary = _validated_snapshots.get(key, {})
	if not cached.is_empty() and cached.instance == instance and cached.catalog == catalog_signature:
		return true
	if not _validate_instance_uncached(instance, catalog_item):
		return false
	if _validated_snapshots.size() >= 2048:
		_validated_snapshots.clear()
	_validated_snapshots[key] = {"instance": instance.duplicate(true), "catalog": catalog_signature}
	return true


static func _validate_instance_uncached(instance: Dictionary, catalog_item: Dictionary) -> bool:
	if not _ensure_loaded():
		return false
	var item_id := _exact_positive_integer(instance.get("item_id", null))
	var catalog_id := _exact_positive_integer(catalog_item.get("itemId", null))
	if (
		item_id < 0
		or item_id != catalog_id
		or str(catalog_item.get("kind", "")) != "equipment"
		or str(instance.get("drop_instance_contract_id", "")) != INSTANCE_CONTRACT_ID
		or str(instance.get("drop_rules_contract_id", "")) not in [INSTANCE_RULES_CONTRACT_ID, RULES_V2_CONTRACT, AffixV3.CONTRACT]
		or str(instance.get("name", "")) != str(catalog_item.get("name", ""))
		or _exact_positive_integer(instance.get("count", null)) != 1
	):
		return false
	var allowed_fields := {
		"drop_instance_contract_id": true,
		"drop_rules_contract_id": true,
		"drop_key_digest": true,
		"item_id": true,
		"name": true,
		"count": true,
		"instance_id": true,
		"durability": true,
		"max_durability": true,
		"durability_raw": true,
		"max_durability_raw": true,
		"durability_contract_id": true,
		"modifiers": true,
		"drop_affix": true,
		"weapon_luck": true,
		"weapon_curse": true,
	}
	for required_field: String in [
		"drop_instance_contract_id", "drop_rules_contract_id", "drop_key_digest",
		"item_id", "name", "count", "instance_id", "durability",
		"max_durability", "durability_raw", "max_durability_raw",
		"durability_contract_id", "modifiers", "drop_affix",
	]:
		if not instance.has(required_field):
			return false
	for raw_field: Variant in instance.keys():
		if not allowed_fields.has(str(raw_field)):
			return false
	var digest := str(instance.get("drop_key_digest", ""))
	var instance_id := str(instance.get("instance_id", ""))
	if (
		not _valid_sha256(digest)
		or instance_id.length() > MAX_INSTANCE_ID_LENGTH
		or instance_id != "drop:v1:%d:%s" % [item_id, digest.substr(0, 24)]
		or str(instance.get("durability_contract_id", "")) != DURABILITY_CONTRACT_ID
		or not _valid_durability(instance, catalog_item)
	):
		return false
	var is_weapon := str(catalog_item.get("category", "")) == "武器"
	if is_weapon:
		var weapon_luck := _exact_nonnegative_integer(instance.get("weapon_luck", null))
		var weapon_curse := _exact_nonnegative_integer(instance.get("weapon_curse", null))
		if (
			weapon_luck < 0
			or weapon_luck > MAX_WEAPON_LUCK
			or weapon_curse < 0
			or weapon_curse > MAX_WEAPON_CURSE
		):
			return false
	elif instance.has("weapon_luck") or instance.has("weapon_curse"):
		return false
	if str(instance.drop_rules_contract_id) == AffixV3.CONTRACT:
		var expected := AffixV3.for_seed(item_id, digest)
		if expected.is_empty() or not instance.modifiers is Array or instance.modifiers.size() != expected.modifiers.size():
			return false
		for index in range(expected.modifiers.size()):
			var actual: Variant = instance.modifiers[index]
			var value: Variant = actual.get("value") if actual is Dictionary else null
			if (not actual is Dictionary or actual.size() != 3
				or str(actual.get("stat", "")) != str(expected.modifiers[index].stat)
				or str(actual.get("op", "")) != "add"
				or not (value is int or value is float) or not is_finite(float(value))
				or float(value) != float(expected.modifiers[index].value)):
				return false
		return instance.drop_affix is Dictionary and instance.drop_affix == {
			"contract_id": AffixV3.AFFIX_CONTRACT,
			"applied": not expected.modifiers.is_empty() or int(expected.durability_bonus_raw) > 0,
		}
	if str(instance.drop_rules_contract_id) == RULES_V2_CONTRACT:
		if not _ensure_v2_loaded():
			return false
		var expected := _v2_modifiers(item_id, digest)
		if not instance.modifiers is Array or instance.modifiers.size() != expected.size():
			return false
		for index in range(expected.size()):
			var actual: Variant = instance.modifiers[index]
			if not actual is Dictionary or actual.size() != 3:
				return false
			if (str(actual.get("stat", "")) != str(expected[index].stat)
				or str(actual.get("op", "")) != "add"
				or _exact_positive_integer(actual.get("value", null)) != int(expected[index].value)):
				return false
		return (instance.drop_affix is Dictionary and instance.drop_affix == {
			"contract_id": AFFIX_V2_CONTRACT, "applied": not expected.is_empty(),
		})
	return _valid_affix(instance, _master_by_item_id.get(item_id, {}))


static func _ensure_v2_loaded() -> bool:
	if not _v2_by_id.is_empty():
		return true
	var data := _read_json(AFFIX_V2_RULES_PATH)
	if str(data.get("contract_id", "")) != RULES_V2_CONTRACT or int(data.get("record_count", 0)) != 175:
		return false
	var records: Dictionary = {}
	for record: Dictionary in data.get("records", []):
		var item_id := int(record.get("item_id", -1))
		if not _master_by_item_id.has(item_id) or records.has(item_id):
			return false
		records[item_id] = record.get("rolls", [])
	if records.size() != 175:
		return false
	_v2_by_id = records
	return true


static func _v2_modifiers(item_id: int, digest: String) -> Array:
	var result: Array = []
	if not _v2_by_id.has(item_id):
		return result
	var cache_key := "%d:%s" % [item_id, digest]
	if _v2_expected_cache.has(cache_key):
		return _v2_expected_cache[cache_key]
	if _v2_expected_cache.size() >= 4096:
		_v2_expected_cache.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("0x" + (AFFIX_V2_CONTRACT + "|" + digest).sha256_text().substr(0, 15)).hex_to_int()
	# Immutable v2: 1/2 single-player entry gate, original independent inner rolls.
	if rng.randi_range(0, 1) != 0:
		result.make_read_only()
		_v2_expected_cache[cache_key] = result
		return result
	for rule: Dictionary in _v2_by_id[item_id]:
		var increment := 1
		for trial in range(int(rule.trials)):
			if rng.randi_range(0, int(rule.trial_denominator) - 1) == 0:
				increment += 1
		if rng.randi_range(0, int(rule.gate_denominator) - 1) == 0:
			result.append({"stat": str(rule.stat), "op": "add", "value": increment})
	for modifier: Dictionary in result:
		modifier.make_read_only()
	result.make_read_only()
	_v2_expected_cache[cache_key] = result
	return result


static func is_affixed_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return (
		validate_instance(instance, catalog_item)
		and bool((instance.get("drop_affix", {}) as Dictionary).get("applied", false))
	)


static func configuration_snapshot() -> Dictionary:
	return _rules_cache.duplicate(true) if _ensure_loaded() else {}


static func _valid_affix(instance: Dictionary, master: Dictionary) -> bool:
	var affix_value: Variant = instance.get("drop_affix", null)
	var modifiers_value: Variant = instance.get("modifiers", null)
	if not affix_value is Dictionary or not modifiers_value is Array:
		return false
	var affix: Dictionary = affix_value
	var modifiers: Array = modifiers_value
	var allowed_affix_fields := {
		"contract_id": true, "applied": true, "source_stat": true,
		"stat": true, "op": true, "value": true,
	}
	if affix.size() != allowed_affix_fields.size():
		return false
	for raw_field: Variant in affix.keys():
		if not allowed_affix_fields.has(str(raw_field)):
			return false
	if (
		str(affix.get("contract_id", "")) != AFFIX_CONTRACT_ID
		or not affix.get("applied", null) is bool
		or str(affix.get("op", "")) != "add"
		or _exact_nonnegative_integer(affix.get("value", null)) < 0
	):
		return false
	if not bool(affix.get("applied", false)):
		return (
			str(affix.get("source_stat", "")).is_empty()
			and str(affix.get("stat", "")).is_empty()
			and int(affix.get("value", -1)) == 0
			and modifiers.is_empty()
		)
	if int(affix.get("value", -1)) != AFFIX_V1_INCREMENT or modifiers.size() != 1:
		return false
	var valid_mapping := false
	for mapping: Dictionary in _eligible_stat_mappings(master):
		if (
			str(mapping.get("source_stat", "")) == str(affix.get("source_stat", ""))
			and str(mapping.get("runtime_stat", "")) == str(affix.get("stat", ""))
		):
			valid_mapping = true
			break
	if not valid_mapping or not modifiers[0] is Dictionary:
		return false
	var modifier: Dictionary = modifiers[0]
	return (
		modifier.size() == 3
		and str(modifier.get("stat", "")) == str(affix.get("stat", ""))
		and str(modifier.get("op", "")) == "add"
		and _exact_nonnegative_integer(modifier.get("value", null)) == AFFIX_V1_INCREMENT
	)


static func _valid_durability(instance: Dictionary, catalog_item: Dictionary) -> bool:
	var current_raw := _exact_nonnegative_integer(instance.get("durability_raw", null))
	var maximum_raw := _exact_positive_integer(instance.get("max_durability_raw", null))
	var current_display := _exact_nonnegative_integer(instance.get("durability", null))
	var maximum_display := _exact_positive_integer(instance.get("max_durability", null))
	var catalog_maximum := maxi(1, int(catalog_item.get("maxDurability", 1)))
	var initial_maximum_raw := catalog_maximum * DURABILITY_RAW_UNITS_PER_DISPLAY
	if str(instance.get("drop_rules_contract_id", "")) == AffixV3.CONTRACT:
		if not AffixV3.ensure_loaded(_master_by_item_id.keys()):
			return false
		var expected := AffixV3.for_seed(int(instance.item_id), str(instance.drop_key_digest))
		if expected.is_empty():
			return false
		initial_maximum_raw = mini(AffixV3.MAXIMUM_DURABILITY_RAW, initial_maximum_raw + int(expected.durability_bonus_raw))
	if (
		current_raw < 0
		or maximum_raw <= 0
		or current_raw > maximum_raw
		or maximum_raw > initial_maximum_raw
	):
		return false
	var expected_maximum_display := int(ceil(float(maximum_raw) / DURABILITY_RAW_UNITS_PER_DISPLAY))
	var expected_current_display := (
		0 if current_raw == 0
		else int(ceil(float(current_raw) / DURABILITY_RAW_UNITS_PER_DISPLAY))
	)
	return maximum_display == expected_maximum_display and current_display == expected_current_display


static func _empty_affix() -> Dictionary:
	return {
		"contract_id": AFFIX_CONTRACT_ID,
		"applied": false,
		"source_stat": "",
		"stat": "",
		"op": "add",
		"value": 0,
	}


static func _eligible_stat_mappings(master: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var stats_value: Variant = master.get("stats", null)
	if not stats_value is Dictionary:
		return result
	for raw_mapping: Variant in _rules_cache.get("stat_mapping", []):
		if not raw_mapping is Dictionary:
			continue
		var mapping: Dictionary = raw_mapping
		var source_stat := str(mapping.get("source_stat", ""))
		var stat_value: Variant = (stats_value as Dictionary).get(source_stat, null)
		if not stat_value is Dictionary:
			continue
		if (
			_exact_integer((stat_value as Dictionary).get("min", null)) == -1
			or _exact_integer((stat_value as Dictionary).get("max", null)) == -1
		):
			continue
		result.append(mapping.duplicate(true))
	return result


static func _ensure_loaded() -> bool:
	if _load_attempted:
		return not _rules_cache.is_empty() and not _master_by_item_id.is_empty()
	_load_attempted = true
	var rules := _read_json(RULES_PATH)
	if not _validate_rules(rules):
		return false
	var authority: Dictionary = rules.get("eligible_item_authority", {})
	var master := _read_json(str(authority.get("path", "")))
	if (
		str(master.get("contractId", "")) != ATTRIBUTE_MASTER_CONTRACT_ID
		or str(master.get("sourceTier", "")) != "primary"
		or not master.get("records", null) is Array
	):
		return false
	var by_id: Dictionary = {}
	for raw_record: Variant in master.get("records", []):
		if not raw_record is Dictionary:
			return false
		var item_id := _exact_positive_integer((raw_record as Dictionary).get("itemId", null))
		if item_id < 0 or by_id.has(item_id):
			return false
		by_id[item_id] = (raw_record as Dictionary).duplicate(true)
	_rules_cache = rules.duplicate(true)
	_master_by_item_id = by_id
	return true


static func _validate_rules(rules: Dictionary) -> bool:
	var allowed_rule_fields := {
		"schema_version": true,
		"contract_id": true,
		"enabled": true,
		"affix_roll": true,
		"eligible_item_authority": true,
		"stat_mapping": true,
		"provenance": true,
	}
	if rules.size() != allowed_rule_fields.size():
		return false
	for raw_field: Variant in rules.keys():
		if not allowed_rule_fields.has(str(raw_field)):
			return false
	if (
		int(rules.get("schema_version", 0)) != 1
		or str(rules.get("contract_id", "")) != INSTANCE_RULES_CONTRACT_ID
		or not rules.get("enabled", null) is bool
		or not rules.get("affix_roll", null) is Dictionary
		or not rules.get("eligible_item_authority", null) is Dictionary
		or not rules.get("stat_mapping", null) is Array
	):
		return false
	var roll: Dictionary = rules.get("affix_roll", {})
	if roll.size() != 3:
		return false
	var numerator := _exact_nonnegative_integer(roll.get("numerator", null))
	var denominator := _exact_positive_integer(roll.get("denominator", null))
	var increment := _exact_positive_integer(roll.get("increment", null))
	if (
		numerator < 0
		or denominator <= 0
		or numerator > denominator
		or increment != AFFIX_V1_INCREMENT
	):
		return false
	var authority: Dictionary = rules.get("eligible_item_authority", {})
	if (
		authority.size() != 4
		or str(authority.get("path", "")) != "res://assets/data/equipment_attribute_master.json"
		or str(authority.get("contract_id", "")) != ATTRIBUTE_MASTER_CONTRACT_ID
		or str(authority.get("source_tier", "")) != "primary"
		or str(authority.get("identity_field", "")) != "itemId"
	):
		return false
	var seen_source: Dictionary = {}
	var seen_runtime: Dictionary = {}
	for raw_mapping: Variant in rules.get("stat_mapping", []):
		if not raw_mapping is Dictionary or (raw_mapping as Dictionary).size() != 2:
			return false
		var source_stat := str((raw_mapping as Dictionary).get("source_stat", ""))
		var runtime_stat := str((raw_mapping as Dictionary).get("runtime_stat", ""))
		if (
			source_stat not in ["dc", "mc", "sc", "ac", "mac"]
			or runtime_stat not in [
				"attack_max", "magic_max", "tao_max", "defense_max", "magic_defense_max",
			]
			or seen_source.has(source_stat)
			or seen_runtime.has(runtime_stat)
		):
			return false
		seen_source[source_stat] = true
		seen_runtime[runtime_stat] = true
	return seen_source.size() == 5


static func _valid_stable_drop_key(value: String) -> bool:
	return not value.is_empty() and value.length() <= MAX_STABLE_DROP_KEY_LENGTH


static func _valid_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		if not ((code >= 48 and code <= 57) or (code >= 97 and code <= 102)):
			return false
	return true


static func _exact_integer(value: Variant) -> int:
	if not (value is int or value is float) or not is_finite(float(value)):
		return -1
	if float(value) != floor(float(value)):
		return -1
	return int(value)


static func _exact_nonnegative_integer(value: Variant) -> int:
	var result := _exact_integer(value)
	return result if result >= 0 else -1


static func _exact_positive_integer(value: Variant) -> int:
	var result := _exact_integer(value)
	return result if result > 0 else -1


static func _read_json(path: String) -> Dictionary:
	if path.is_empty() or not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
