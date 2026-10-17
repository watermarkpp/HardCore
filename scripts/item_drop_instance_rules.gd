class_name ItemDropInstanceRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/item_instances_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().item_instances
	return _legacy_owner

const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const AffixV3 := preload("res://scripts/item_drop_affix_v3_rules.gd")
const AffixV4 := preload("res://scripts/item_drop_affix_v4_rules.gd")
const EnhancementRules := preload("res://scripts/layers/rules/equipment_enhancement_rules.gd")
const RandomSpecialRules := preload("res://scripts/equipment_random_special_instance_rules.gd")
const MysteryRules := preload("res://scripts/mystery_equipment_instance_rules.gd")
const RULES_PATH = RuleCore.RULES_PATH
const INSTANCE_RULES_CONTRACT_ID = RuleCore.INSTANCE_RULES_CONTRACT_ID
const INSTANCE_CONTRACT_ID = RuleCore.INSTANCE_CONTRACT_ID
const AFFIX_CONTRACT_ID = RuleCore.AFFIX_CONTRACT_ID
const ATTRIBUTE_MASTER_CONTRACT_ID = RuleCore.ATTRIBUTE_MASTER_CONTRACT_ID
const DURABILITY_CONTRACT_ID = RuleCore.DURABILITY_CONTRACT_ID
const DURABILITY_RAW_UNITS_PER_DISPLAY = RuleCore.DURABILITY_RAW_UNITS_PER_DISPLAY
const MAX_STABLE_DROP_KEY_LENGTH = RuleCore.MAX_STABLE_DROP_KEY_LENGTH
const MAX_INSTANCE_ID_LENGTH = RuleCore.MAX_INSTANCE_ID_LENGTH
const MAX_WEAPON_LUCK = RuleCore.MAX_WEAPON_LUCK
const MAX_WEAPON_CURSE = RuleCore.MAX_WEAPON_CURSE
const AFFIX_V1_INCREMENT = RuleCore.AFFIX_V1_INCREMENT
const AFFIX_V2_RULES_PATH = RuleCore.AFFIX_V2_RULES_PATH
const AFFIX_V2_CONTRACT = RuleCore.AFFIX_V2_CONTRACT
const RULES_V2_CONTRACT = RuleCore.RULES_V2_CONTRACT

static var _v2_by_id: Dictionary:
	get: return _owner()._v2_by_id
	set(value): _owner()._v2_by_id = value

static var _v2_expected_cache: Dictionary:
	get: return _owner()._v2_expected_cache
	set(value): _owner()._v2_expected_cache = value

static var _rules_cache: Dictionary:
	get: return _owner()._rules_cache
	set(value): _owner()._rules_cache = value

static var _master_by_item_id: Dictionary:
	get: return _owner()._master_by_item_id
	set(value): _owner()._master_by_item_id = value

static var _load_attempted: bool:
	get: return _owner()._load_attempted
	set(value): _owner()._load_attempted = value

static var _validated_snapshots: Dictionary:
	get: return _owner()._validated_snapshots
	set(value): _owner()._validated_snapshots = value

static func prepare_runtime() -> bool:
	return _owner().prepare_runtime()

static func create_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	return _owner().create_instance(catalog_item, stable_drop_key)

static func create_v2_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	return _owner().create_v2_instance(catalog_item, stable_drop_key)

static func create_legacy_instance(catalog_item: Dictionary, stable_drop_key: String) -> Dictionary:
	return _owner().create_legacy_instance(catalog_item, stable_drop_key)

static func validate_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return _owner().validate_instance(instance, catalog_item)

static func _validate_instance_uncached(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return _owner()._validate_instance_uncached(instance, catalog_item)

static func _ensure_v2_loaded() -> bool:
	return _owner()._ensure_v2_loaded()

static func _v2_modifiers(item_id: int, digest: String) -> Array:
	return _owner()._v2_modifiers(item_id, digest)

static func is_affixed_instance(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return _owner().is_affixed_instance(instance, catalog_item)

static func configuration_snapshot() -> Dictionary:
	return _owner().configuration_snapshot()

static func _valid_affix(instance: Dictionary, master: Dictionary) -> bool:
	return _owner()._valid_affix(instance, master)

static func _valid_durability(instance: Dictionary, catalog_item: Dictionary) -> bool:
	return _owner()._valid_durability(instance, catalog_item)

static func _empty_affix() -> Dictionary:
	return _owner()._empty_affix()

static func _eligible_stat_mappings(master: Dictionary) -> Array[Dictionary]:
	return _owner()._eligible_stat_mappings(master)

static func _ensure_loaded() -> bool:
	return _owner()._ensure_loaded()

static func _validate_rules(rules: Dictionary) -> bool:
	return _owner()._validate_rules(rules)

static func _valid_stable_drop_key(value: String) -> bool:
	return _owner()._valid_stable_drop_key(value)

static func _valid_sha256(value: String) -> bool:
	return _owner()._valid_sha256(value)

static func _exact_integer(value: Variant) -> int:
	return _owner()._exact_integer(value)

static func _exact_nonnegative_integer(value: Variant) -> int:
	return _owner()._exact_nonnegative_integer(value)

static func _exact_positive_integer(value: Variant) -> int:
	return _owner()._exact_positive_integer(value)

static func _read_json(path: String) -> Dictionary:
	return _owner()._read_json(path)
