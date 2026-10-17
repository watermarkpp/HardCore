class_name EquipmentEnhancementBlackIron
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/black_iron_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().black_iron
	return _legacy_owner

const CONTRACT_ID = RuleCore.CONTRACT_ID
const AUTHORITY_PATH = RuleCore.AUTHORITY_PATH

static var _by_id: Dictionary:
	get: return _owner()._by_id
	set(value): _owner()._by_id = value

static var _load_attempted: bool:
	get: return _owner()._load_attempted
	set(value): _owner()._load_attempted = value

static func records() -> Array[Dictionary]:
	return _owner().records()

static func record_for_id(item_id: int) -> Dictionary:
	return _owner().record_for_id(item_id)

static func purity_for(item_ref: Dictionary) -> int:
	return _owner().purity_for(item_ref)

static func _ensure_loaded() -> void:
	_owner()._ensure_loaded()
