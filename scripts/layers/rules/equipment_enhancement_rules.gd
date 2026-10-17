class_name EquipmentEnhancementRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/enhancement_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().enhancement
	return _legacy_owner

const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const CONTRACT_ID = RuleCore.CONTRACT_ID
const RULES_CONTRACT_ID = RuleCore.RULES_CONTRACT_ID
const RULES_PATH = RuleCore.RULES_PATH
const WEAPON_STATS = RuleCore.WEAPON_STATS
const ARMOR_STATS = RuleCore.ARMOR_STATS

static var _rules: Dictionary:
	get: return _owner()._rules
	set(value): _owner()._rules = value

static var _load_failed: bool:
	get: return _owner()._load_failed
	set(value): _owner()._load_failed = value

static func _config() -> Dictionary:
	return _owner()._config()

static func max_stage(category: String) -> int:
	return _owner().max_stage(category)

static func black_iron_bonus_bps(purity: int) -> int:
	return _owner().black_iron_bonus_bps(purity)

static func accessory_grade_penalty_bps(category: String, next_stage: int, target_grade: int, accessory_grade: int) -> int:
	return _owner().accessory_grade_penalty_bps(category, next_stage, target_grade, accessory_grade)

static func quote_probability(category: String, next_stage: int, purity: int, target_grade: int, accessory_a_grade: int, accessory_b_grade: int) -> Dictionary:
	return _owner().quote_probability(category, next_stage, purity, target_grade, accessory_a_grade, accessory_b_grade)

static func forge_gold_cost(category: String, next_stage: int) -> int:
	return _owner().forge_gold_cost(category, next_stage)

static func forge_attribute_weights(accessory_a: Dictionary, accessory_b: Dictionary) -> Dictionary:
	return _owner().forge_attribute_weights(accessory_a, accessory_b)

static func forge_stage(instance: Dictionary) -> int:
	return _owner().forge_stage(instance)

static func validate_enhancement(enhancement: Variant, category: String) -> bool:
	return _owner().validate_enhancement(enhancement, category)

static func _is_integral_number(value: Variant) -> bool:
	return _owner()._is_integral_number(value)
