class_name EquipmentEnhancementGrade
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/enhancement_grade_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().enhancement_grade
	return _legacy_owner

const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const CONTRACT_ID = RuleCore.CONTRACT_ID
const AUTHORITY_PATH = RuleCore.AUTHORITY_PATH
const ACCESSORY_CATEGORIES = RuleCore.ACCESSORY_CATEGORIES

static var _loaded: bool:
	get: return _owner()._loaded
	set(value): _owner()._loaded = value

static var _by_id: Dictionary:
	get: return _owner()._by_id
	set(value): _owner()._by_id = value

static func record_for_id(item_id: int) -> Dictionary:
	return _owner().record_for_id(item_id)

static func grade_for_id(item_id: int) -> int:
	return _owner().grade_for_id(item_id)

static func can_use_as_accessory_material(item_id: int) -> bool:
	return _owner().can_use_as_accessory_material(item_id)

static func records() -> Array[Dictionary]:
	return _owner().records()

static func _ensure_loaded() -> void:
	_owner()._ensure_loaded()

static func _is_integer(value: Variant) -> bool:
	return _owner()._is_integer(value)
