class_name RelicSynthesisRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/relic_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().relic
	return _legacy_owner

const CONTRACT_ID = RuleCore.CONTRACT_ID
const DATA_PATH = RuleCore.DATA_PATH
const FRAGMENT_ID = RuleCore.FRAGMENT_ID
const FRAGMENT_COUNT = RuleCore.FRAGMENT_COUNT
const GOLD_COST = RuleCore.GOLD_COST
const PROC_CHANCE_PERCENT = RuleCore.PROC_CHANCE_PERCENT
const PROC_DURATION_SECONDS = RuleCore.PROC_DURATION_SECONDS
const PROC_COOLDOWN_SECONDS = RuleCore.PROC_COOLDOWN_SECONDS
const SkillData := preload("res://scripts/skills/skill_data_loader.gd")
const SkillRankPolicy := preload("res://scripts/skills/skill_rank_extension_policy.gd")
const Registry := preload("res://scripts/identity/entity_registry.gd")
const Professions := preload("res://scripts/profession_rules.gd")

static var _records_by_id: Dictionary:
	get: return _owner()._records_by_id
	set(value): _owner()._records_by_id = value

static var _skill_ids_by_profession: Dictionary:
	get: return _owner()._skill_ids_by_profession
	set(value): _owner()._skill_ids_by_profession = value

static var _loaded: bool:
	get: return _owner()._loaded
	set(value): _owner()._loaded = value

static func records() -> Array[Dictionary]:
	return _owner().records()

static func record_for_id(item_id: int) -> Dictionary:
	return _owner().record_for_id(item_id)

static func is_relic(item_id: int) -> bool:
	return _owner().is_relic(item_id)

static func is_badge(item_id: int) -> bool:
	return _owner().is_badge(item_id)

static func is_synthesis_item(item_id: int) -> bool:
	return _owner().is_synthesis_item(item_id)

static func recipe_professions(item_id: int) -> Array[String]:
	return _owner().recipe_professions(item_id)

static func effect_for(item_id: int) -> String:
	return _owner().effect_for(item_id)

static func skill_ids_for(profession: String) -> Array[String]:
	return _owner().skill_ids_for(profession)

static func roll_instance(item_id: int, profession: String, rng: RandomNumberGenerator) -> Dictionary:
	return _owner().roll_instance(item_id, profession, rng)

static func valid_instance(instance: Dictionary, item_id: int) -> bool:
	return _owner().valid_instance(instance, item_id)

static func _exact_integral_value(raw: Variant, expected: int) -> bool:
	return _owner()._exact_integral_value(raw, expected)

static func _ensure_loaded() -> void:
	_owner()._ensure_loaded()
