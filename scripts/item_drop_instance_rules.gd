class_name ItemDropInstanceRules
extends RefCounted

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

static var _rules_cache: Dictionary = {}
static var _master_by_item_id: Dictionary = {}
static var _load_attempted := false


static func create_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
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
	if not _ensure_loaded():
		return false
	var item_id := _exact_positive_integer(instance.get("item_id", null))
	var catalog_id := _exact_positive_integer(catalog_item.get("itemId", null))
	if (
		item_id < 0
		or item_id != catalog_id
		or str(catalog_item.get("kind", "")) != "equipment"
		or str(instance.get("drop_instance_contract_id", "")) != INSTANCE_CONTRACT_ID
		or str(instance.get("drop_rules_contract_id", "")) != INSTANCE_RULES_CONTRACT_ID
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
	return _valid_affix(instance, _master_by_item_id.get(item_id, {}))


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
	if (
		current_raw < 0
		or maximum_raw <= 0
		or current_raw > maximum_raw
		or maximum_raw > catalog_maximum * DURABILITY_RAW_UNITS_PER_DISPLAY
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
