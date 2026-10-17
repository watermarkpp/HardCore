class_name ItemDropAffixV3Rules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/affix_v3_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().affix_v3
	return _legacy_owner

const PATH = RuleCore.PATH
const CONTRACT = RuleCore.CONTRACT
const AFFIX_CONTRACT = RuleCore.AFFIX_CONTRACT
const MAXIMUM_DURABILITY_RAW = RuleCore.MAXIMUM_DURABILITY_RAW

static var _records: Dictionary:
	get: return _owner()._records
	set(value): _owner()._records = value

static var _expected: Dictionary:
	get: return _owner()._expected
	set(value): _owner()._expected = value

static func ensure_loaded(master_ids: Array) -> bool:
	return _owner().ensure_loaded(master_ids)

static func for_seed(item_id: int, digest: String) -> Dictionary:
	return _owner().for_seed(item_id, digest)
