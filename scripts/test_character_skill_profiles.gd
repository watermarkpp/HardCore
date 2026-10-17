class_name TestCharacterSkillProfiles
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/test_character_profiles_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().test_character_profiles
	return _legacy_owner

const SkillLoadoutRulesScript := preload("res://scripts/skill_loadout_rules.gd")
const SkillData := preload("res://scripts/skills/skill_data_loader.gd")
const DATA_PATH = RuleCore.DATA_PATH
const CONTRACT_ID = RuleCore.CONTRACT_ID
const QA_V2_DATA_PATH = RuleCore.QA_V2_DATA_PATH
const QA_V2_CONTRACT_ID = RuleCore.QA_V2_CONTRACT_ID
const EQUIPMENT_TIERS = RuleCore.EQUIPMENT_TIERS

static var _data_cache: Dictionary:
	get: return _owner()._data_cache
	set(value): _owner()._data_cache = value

static var _qa_v2_data_cache: Dictionary:
	get: return _owner()._qa_v2_data_cache
	set(value): _owner()._qa_v2_data_cache = value

static func profile_for_profession(profession_name_or_id: String) -> Dictionary:
	return _owner().profile_for_profession(profession_name_or_id)

static func profile_for_character(profession_name_or_id: String, equipment_tier: String) -> Dictionary:
	return _owner().profile_for_character(profession_name_or_id, equipment_tier)

static func qa_v2_profile_for_profession(profession_name_or_id: String) -> Dictionary:
	return _owner().qa_v2_profile_for_profession(profession_name_or_id)

static func qa_v2_profile_for_character(
	profession_name_or_id: String,
	equipment_tier: String
) -> Dictionary:
	return _owner().qa_v2_profile_for_character(profession_name_or_id, equipment_tier)

static func qa_v2_profiles() -> Array[Dictionary]:
	return _owner().qa_v2_profiles()

static func _data() -> Dictionary:
	return _owner()._data()

static func _qa_v2_data() -> Dictionary:
	return _owner()._qa_v2_data()
