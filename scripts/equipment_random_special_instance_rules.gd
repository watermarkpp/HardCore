class_name EquipmentRandomSpecialInstanceRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/random_special_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().random_special
	return _legacy_owner

const CONTRACT_ID = RuleCore.CONTRACT_ID
const TECHNIQUE_NECKLACE_ID = RuleCore.TECHNIQUE_NECKLACE_ID
const DATA_PATH = RuleCore.DATA_PATH
const EXPECTED_POOL_SIZE = RuleCore.EXPECTED_POOL_SIZE

static var _skill_pool: Array[String]:
	get: return _owner()._skill_pool
	set(value): _owner()._skill_pool = value

static var _loaded: bool:
	get: return _owner()._loaded
	set(value): _owner()._loaded = value

static func is_technique_necklace(item_or_id: Variant) -> bool:
	return _owner().is_technique_necklace(item_or_id)

static func allowed_technique_skill_ids() -> Array[String]:
	return _owner().allowed_technique_skill_ids()

static func create_technique_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	return _owner().create_technique_instance(catalog_item, stable_drop_key)

static func validate_technique_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return _owner().validate_technique_instance(instance, catalog_item)

static func technique_skill_level_modifiers(instance: Dictionary) -> Array:
	return _owner().technique_skill_level_modifiers(instance)

static func _exact_integral(raw: Variant, expected: int) -> bool:
	return _owner()._exact_integral(raw, expected)

static func _skill_for_digest(drop_key_digest: String) -> String:
	return _owner()._skill_for_digest(drop_key_digest)

static func _ensure_loaded() -> void:
	_owner()._ensure_loaded()
