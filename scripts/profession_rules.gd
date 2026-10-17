class_name ProfessionRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/professions_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().professions
	return _legacy_owner

const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const EntityRegistry := preload("res://scripts/identity/entity_registry.gd")
const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)
const COMBAT_SPATIAL_PROFILE_CONTRACT_ID = RuleCore.COMBAT_SPATIAL_PROFILE_CONTRACT_ID
const LEGACY_PROFILE_SPATIAL_ADAPTER_CONTRACT_ID = RuleCore.LEGACY_PROFILE_SPATIAL_ADAPTER_CONTRACT_ID
const LEGACY_MINIMUM_SEARCH_RANGE_PX = RuleCore.LEGACY_MINIMUM_SEARCH_RANGE_PX
const LEGACY_SEARCH_RANGE_MARGIN_PX = RuleCore.LEGACY_SEARCH_RANGE_MARGIN_PX
const PROFESSIONS = RuleCore.PROFESSIONS
const PROFESSION_CATALOG = RuleCore.PROFESSION_CATALOG
const SKILL_CATALOG = RuleCore.SKILL_CATALOG
const BASE_STATS = RuleCore.BASE_STATS
const SKILL_PROFILES = RuleCore.SKILL_PROFILES
const EQUIPMENT_GRANTED_SKILLS = RuleCore.EQUIPMENT_GRANTED_SKILLS
const CASTER_SPELL_ACTION_DURATION = RuleCore.CASTER_SPELL_ACTION_DURATION
const CAST_DEFAULTS = RuleCore.CAST_DEFAULTS
const SKILL_TIMING_OVERRIDES = RuleCore.SKILL_TIMING_OVERRIDES
const COMBAT_REACTION_POLICY = RuleCore.COMBAT_REACTION_POLICY

static var _runtime_data: Dictionary:
	get: return _owner()._runtime_data
	set(value): _owner()._runtime_data = value

static var _base_growth_cache: Dictionary:
	get: return _owner()._base_growth_cache
	set(value): _owner()._base_growth_cache = value

static var _skill_ids_by_name: Dictionary:
	get: return _owner()._skill_ids_by_name
	set(value): _owner()._skill_ids_by_name = value

static var _profiles_by_id: Dictionary:
	get: return _owner()._profiles_by_id
	set(value): _owner()._profiles_by_id = value

static var _timing_by_id: Dictionary:
	get: return _owner()._timing_by_id
	set(value): _owner()._timing_by_id = value

static func _data() -> Dictionary:
	return _owner()._data()

static func is_valid_profession(value: String) -> bool:
	return _owner().is_valid_profession(value)

static func import_profession_identity(value: String) -> String:
	return _owner().import_profession_identity(value)

static func is_valid_profession_id(value: String) -> bool:
	return _owner().is_valid_profession_id(value)

static func profession_id(value: String) -> String:
	return _owner().profession_id(value)

static func profession_display_name(value: String) -> String:
	return _owner().profession_display_name(value)

static func skill_id(value: String) -> String:
	return _owner().skill_id(value)

static func skill_display_name(value: String) -> String:
	return _owner().skill_display_name(value)

static func skill_input_metadata(skill_name_or_id: String) -> Dictionary:
	return _owner().skill_input_metadata(skill_name_or_id)

static func stats_for_level(profession: String, level: int) -> Dictionary:
	return _owner().stats_for_level(profession, level)

static func base_stat_for_level(profession: String, level: int, stat: String) -> int:
	return _owner().base_stat_for_level(profession, level, stat)

static func _base_growth_row(profession: String, level: int) -> Dictionary:
	return _owner()._base_growth_row(profession, level)

static func skill_profile(skill_name_or_id: String) -> Dictionary:
	return _owner().skill_profile(skill_name_or_id)

static func skill_combat_profile(skill_name: String, learned_level := -1) -> Dictionary:
	return _owner().skill_combat_profile(skill_name, learned_level)

static func _formalize_spatial_profile(
	legacy_profile: Dictionary,
	include_search_range: bool
) -> Dictionary:
	return _owner()._formalize_spatial_profile(legacy_profile, include_search_range)

static func primary_damage_range(profession: String, stats: Dictionary) -> Vector2i:
	return _owner().primary_damage_range(profession, stats)

static func player_struck_damage_threshold(max_hp_value: int) -> int:
	return _owner().player_struck_damage_threshold(max_hp_value)

static func should_player_stagger(actual_damage: int, max_hp_value: int) -> bool:
	return _owner().should_player_stagger(actual_damage, max_hp_value)

static func player_struck_action_lock_seconds() -> float:
	return _owner().player_struck_action_lock_seconds()

static func player_struck_reaction_frame_milliseconds(character_level: int) -> int:
	return _owner().player_struck_reaction_frame_milliseconds(character_level)

static func player_struck_reaction_seconds(character_level: int) -> float:
	return _owner().player_struck_reaction_seconds(character_level)

static func missing_runtime_skills(skill_rows: Array) -> PackedStringArray:
	return _owner().missing_runtime_skills(skill_rows)
