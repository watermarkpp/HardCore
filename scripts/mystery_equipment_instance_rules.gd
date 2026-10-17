class_name MysteryEquipmentInstanceRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/mystery_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().mystery
	return _legacy_owner

const CONTRACT_ID = RuleCore.CONTRACT_ID
const SOURCE_PATH = RuleCore.SOURCE_PATH

static var _source_loaded: bool:
	get: return _owner()._source_loaded
	set(value): _owner()._source_loaded = value

static var _source_valid: bool:
	get: return _owner()._source_valid
	set(value): _owner()._source_valid = value

static var _source: Dictionary:
	get: return _owner()._source
	set(value): _owner()._source = value

static var _source_error: String:
	get: return _owner()._source_error
	set(value): _owner()._source_error = value

static func source_validation_error() -> String:
	return _owner().source_validation_error()

static func is_mystery_item(catalog_or_id: Variant) -> bool:
	return _owner().is_mystery_item(catalog_or_id)

static func create_roll(catalog: Dictionary, stable_drop_key_digest: String) -> Dictionary:
	return _owner().create_roll(catalog, stable_drop_key_digest)

static func validate_roll(instance: Dictionary, catalog: Dictionary) -> bool:
	return _owner().validate_roll(instance, catalog)

static func modifiers(instance: Dictionary) -> Array:
	return _owner().modifiers(instance)

static func requirement(instance: Dictionary) -> Dictionary:
	return _owner().requirement(instance)

static func _item_id(value: Variant) -> int:
	return _owner()._item_id(value)

static func _integral(value: Variant) -> bool:
	return _owner()._integral(value)

static func _int_array_equal(actual: Variant, expected: Array) -> bool:
	return _owner()._int_array_equal(actual, expected)

static func _family(catalog: Dictionary) -> String:
	return _owner()._family(catalog)

static func _family_params(family: String) -> Dictionary:
	return _owner()._family_params(family)

static func _roll_count(digest: String, key: String, count: int, rate: int) -> int:
	return _owner()._roll_count(digest, key, count, rate)

static func _requirement(catalog: Dictionary, family: String, stats: Dictionary) -> Dictionary:
	return _owner()._requirement(catalog, family, stats)

static func _strict_roll_equal(actual: Dictionary, expected: Dictionary) -> bool:
	return _owner()._strict_roll_equal(actual, expected)

static func _base_requirement_value(catalog: Dictionary) -> int:
	return _owner()._base_requirement_value(catalog)

static func _ensure_source() -> void:
	_owner()._ensure_source()
