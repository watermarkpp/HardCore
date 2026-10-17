class_name EquipmentRules
extends RefCounted

## Legacy M API: one same-source domain rule instance owns every cache.
const RuleCore := preload("res://scripts/gameplay/profile/rules/equipment_core.gd")

static var _legacy_owner: RuleCore

static func _owner() -> RuleCore:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		return null
	if _legacy_owner == null:
		_legacy_owner = load("res://scripts/gameplay/profile/legacy_profile_rules.gd").rules().equipment
	return _legacy_owner

const ItemCategories := preload("res://scripts/identity/item_category_identity.gd")
const NEED_LEVEL = RuleCore.NEED_LEVEL
const NEED_ATTACK = RuleCore.NEED_ATTACK
const NEED_MAGIC = RuleCore.NEED_MAGIC
const NEED_TAO = RuleCore.NEED_TAO
const SUPPORTED_NEEDS = RuleCore.SUPPORTED_NEEDS
const ATTRIBUTE_MASTER_CONTRACT_ID = RuleCore.ATTRIBUTE_MASTER_CONTRACT_ID
const ATTRIBUTE_MASTER_DISTRIBUTION = RuleCore.ATTRIBUTE_MASTER_DISTRIBUTION
const LEGACY_ROLL_POLICY = RuleCore.LEGACY_ROLL_POLICY
const SKILL_LEVEL_AFFIX_CONTRACT_ID = RuleCore.SKILL_LEVEL_AFFIX_CONTRACT_ID
const SKILL_LEVEL_AFFIX_STAT = RuleCore.SKILL_LEVEL_AFFIX_STAT
const SKILL_LEVEL_SCOPE_ALL = RuleCore.SKILL_LEVEL_SCOPE_ALL
const SKILL_LEVEL_SCOPE_PREFIX_PROFESSION = RuleCore.SKILL_LEVEL_SCOPE_PREFIX_PROFESSION
const SKILL_LEVEL_SCOPE_PREFIX_SKILL = RuleCore.SKILL_LEVEL_SCOPE_PREFIX_SKILL
const SKILL_LEVEL_PROFESSIONS = RuleCore.SKILL_LEVEL_PROFESSIONS
const SKILL_LEVEL_INT64_MAX = RuleCore.SKILL_LEVEL_INT64_MAX
const SKILL_LEVEL_STABLE_ID_MAX_LENGTH = RuleCore.SKILL_LEVEL_STABLE_ID_MAX_LENGTH
const REQUIREMENT_TYPE_CODES = RuleCore.REQUIREMENT_TYPE_CODES
const JOB_LOCK_DISPLAY_NAMES = RuleCore.JOB_LOCK_DISPLAY_NAMES
const BLESSING_UNLUCKY_RATE = RuleCore.BLESSING_UNLUCKY_RATE
const BLESSING_SUCCESS_RATE_MULTIPLIER = RuleCore.BLESSING_SUCCESS_RATE_MULTIPLIER
const LUCK_POINT_1 = RuleCore.LUCK_POINT_1
const LUCK_POINT_2 = RuleCore.LUCK_POINT_2
const LUCK_POINT_3 = RuleCore.LUCK_POINT_3
const LUCK_POINT_2_RATE = RuleCore.LUCK_POINT_2_RATE
const LUCK_POINT_3_RATE = RuleCore.LUCK_POINT_3_RATE
const MAX_WEAPON_CURSE = RuleCore.MAX_WEAPON_CURSE
const ACTOR_VISUAL_SORT_CONTRACT_ID = RuleCore.ACTOR_VISUAL_SORT_CONTRACT_ID
const MALE_WORLD_HELMET_EXTENSION_CONTRACT_ID = RuleCore.MALE_WORLD_HELMET_EXTENSION_CONTRACT_ID
const PLAYER_VISUAL_HELMET_V2_CONTRACT_ID = RuleCore.PLAYER_VISUAL_HELMET_V2_CONTRACT_ID
const WORLD_HELMET_RUNTIME_POLICY_CONTRACT_ID = RuleCore.WORLD_HELMET_RUNTIME_POLICY_CONTRACT_ID
const WORLD_HELMET_RUNTIME_POLICY_PATH = RuleCore.WORLD_HELMET_RUNTIME_POLICY_PATH
const SPECIAL_RULES_PATH = RuleCore.SPECIAL_RULES_PATH
const ACTOR_VISUAL_BODY_LAYER = RuleCore.ACTOR_VISUAL_BODY_LAYER
const ACTOR_VISUAL_HAIR_LAYER = RuleCore.ACTOR_VISUAL_HAIR_LAYER
const ACTOR_VISUAL_WEAPON_LAYER = RuleCore.ACTOR_VISUAL_WEAPON_LAYER
const ACTOR_VISUAL_HELMET_LAYER = RuleCore.ACTOR_VISUAL_HELMET_LAYER

static var _world_helmet_runtime_policy: Dictionary:
	get: return _owner()._world_helmet_runtime_policy
	set(value): _owner()._world_helmet_runtime_policy = value

static var _special_rules_cache: Dictionary:
	get: return _owner()._special_rules_cache
	set(value): _owner()._special_rules_cache = value

static var _special_rules_loaded: bool:
	get: return _owner()._special_rules_loaded
	set(value): _owner()._special_rules_loaded = value
const SPECIAL_EFFECTS_BY_NAME = RuleCore.SPECIAL_EFFECTS_BY_NAME
const SET_PIECES_BY_NAME = RuleCore.SET_PIECES_BY_NAME

static var _weapon_frame_order: Dictionary:
	get: return _owner()._weapon_frame_order
	set(value): _owner()._weapon_frame_order = value

static func weapon_draws_behind_actor(direction_row: int, action_name := "idle", frame := 0, gender := "男") -> bool:
	return _owner().weapon_draws_behind_actor(direction_row, action_name, frame, gender)

static func world_helmet_runtime_policy() -> Dictionary:
	return _owner().world_helmet_runtime_policy()

static func world_helmet_is_visible() -> bool:
	return _owner().world_helmet_is_visible()

static func world_helmet_head_mask_enabled() -> bool:
	return _owner().world_helmet_head_mask_enabled()

static func world_hair_appearance() -> Dictionary:
	return _owner().world_hair_appearance()

static func actor_visual_layer_order(direction_row: int) -> Array[StringName]:
	return _owner().actor_visual_layer_order(direction_row)

static func max_wear_weight(profession: String, level: int) -> int:
	return _owner().max_wear_weight(profession, level)

static func max_hand_weight(profession: String, level: int) -> int:
	return _owner().max_hand_weight(profession, level)

static func max_bag_weight(profession: String, level: int) -> int:
	return _owner().max_bag_weight(profession, level)

static func attribute_source_distribution(item: Dictionary) -> String:
	return _owner().attribute_source_distribution(item)

static func requirement_for(item: Dictionary, instance: Dictionary = {}) -> Dictionary:
	return _owner().requirement_for(item, instance)

static func requirement_error(item: Dictionary, level: int, stats: Dictionary, instance: Dictionary = {}) -> String:
	return _owner().requirement_error(item, level, stats, instance)

static func requirement_label(item: Dictionary) -> String:
	return _owner().requirement_label(item)

static func reference_price(item: Dictionary) -> int:
	return _owner().reference_price(item)

static func repair_cost(item: Dictionary, durability: int, max_durability: int) -> int:
	return _owner().repair_cost(item, durability, max_durability)

static func blessing_outcome(luck: int, curse: int, attack_min: int, attack_max: int, unlucky_roll: int, success_roll: int, upper_stage_roll := -1) -> Dictionary:
	return _owner().blessing_outcome(luck, curse, attack_min, attack_max, unlucky_roll, success_roll, upper_stage_roll)

static func blessing_is_unlucky_roll(unlucky_roll: int) -> bool:
	return _owner().blessing_is_unlucky_roll(unlucky_roll)

static func blessing_success_roll_hits(roll: int, denominator: int) -> bool:
	return _owner().blessing_success_roll_hits(roll, denominator)

static func blessing_luck12_joint_roll_hits(lower_roll: int, upper_roll: int, lower_denominator: int, upper_denominator: int) -> bool:
	return _owner().blessing_luck12_joint_roll_hits(lower_roll, upper_roll, lower_denominator, upper_denominator)

static func blessing_span_factor(attack_min: int, attack_max: int) -> int:
	return _owner().blessing_span_factor(attack_min, attack_max)

static func blessing_success_denominator(luck: int, attack_min: int, attack_max: int) -> int:
	return _owner().blessing_success_denominator(luck, attack_min, attack_max)

static func equipment_luck_contribution(item: Dictionary, instance: Dictionary = {}, include_weapon_instance := false) -> int:
	return _owner().equipment_luck_contribution(item, instance, include_weapon_instance)

static func weapon_luck_label(instance: Dictionary) -> String:
	return _owner().weapon_luck_label(instance)

static func weapon_luck_state(instance: Dictionary) -> Dictionary:
	return _owner().weapon_luck_state(instance)

static func special_effect_for(item: Dictionary) -> Dictionary:
	return _owner().special_effect_for(item)

static func set_piece_for(item: Dictionary) -> Dictionary:
	return _owner().set_piece_for(item)

static func effective_profession(item: Dictionary) -> String:
	return _owner().effective_profession(item)

static func special_action_label(effect_id: String) -> String:
	return _owner().special_action_label(effect_id)

static func _special_rules_source() -> Dictionary:
	return _owner()._special_rules_source()

static func revival_cooldown_ms() -> int:
	return _owner().revival_cooldown_ms()

static func paralysis_duration_for_classification(classification: String) -> float:
	return _owner().paralysis_duration_for_classification(classification)

static func paralysis_succeeds(target_anti_poison: int, roll: int) -> bool:
	return _owner().paralysis_succeeds(target_anti_poison, roll)

static func critical_succeeds(chance: float, roll: float) -> bool:
	return _owner().critical_succeeds(chance, roll)

static func critical_damage(damage: int, multiplier: float) -> int:
	return _owner().critical_damage(damage, multiplier)

static func required_gender(item: Dictionary) -> String:
	return _owner().required_gender(item)

static func weight_requirement_for(item: Dictionary) -> Dictionary:
	return _owner().weight_requirement_for(item)

static func legacy_range_warning(field: String, min_value: int, max_value: int) -> Dictionary:
	return _owner().legacy_range_warning(field, min_value, max_value)

static func enrich_catalog_record(item: Dictionary, price_lookup: Callable = Callable()) -> Dictionary:
	return _owner().enrich_catalog_record(item, price_lookup)

static func skill_level_affix_contributions(record: Dictionary) -> Dictionary:
	return _owner().skill_level_affix_contributions(record)

static func aggregate_skill_level_affix_records(records: Array) -> Dictionary:
	return _owner().aggregate_skill_level_affix_records(records)

static func parse_skill_level_affix_entry(entry: Dictionary) -> Dictionary:
	return _owner().parse_skill_level_affix_entry(entry)

static func _empty_skill_level_affix_result() -> Dictionary:
	return _owner()._empty_skill_level_affix_result()

static func _parse_array_skill_level_affix(entry: Dictionary) -> Dictionary:
	return _owner()._parse_array_skill_level_affix(entry)

static func _parse_skill_level_pair(key: String, value: Variant) -> Dictionary:
	return _owner()._parse_skill_level_pair(key, value)

static func _resolve_skill_level_scope(entry: Dictionary) -> Dictionary:
	return _owner()._resolve_skill_level_scope(entry)

static func _canonical_scope_from_pair_key(key: String) -> Dictionary:
	return _owner()._canonical_scope_from_pair_key(key)

static func _validate_skill_level_value(value: Variant) -> Dictionary:
	return _owner()._validate_skill_level_value(value)

static func _absorb_parse_result(result: Dictionary, parsed: Dictionary, index: int, source: String, raw_record: Variant) -> void:
	_owner()._absorb_parse_result(result, parsed, index, source, raw_record)

static func _accumulate_skill_level_value(result: Dictionary, bucket: String, key: String, value: int, index: int, source: String) -> void:
	_owner()._accumulate_skill_level_value(result, bucket, key, value, index, source)

static func _merge_skill_level_affix_result(result: Dictionary, partial: Dictionary, record_index: int) -> void:
	_owner()._merge_skill_level_affix_result(result, partial, record_index)

static func _append_rejected(result: Dictionary, index: int, source: String, code: String, message: String, raw_record: Variant) -> void:
	_owner()._append_rejected(result, index, source, code, message, raw_record)

static func _looks_like_stable_skill_id(value: String) -> bool:
	return _owner()._looks_like_stable_skill_id(value)

static func _is_stable_id_ascii_alnum(code: int) -> bool:
	return _owner()._is_stable_id_ascii_alnum(code)
