extends Node

## Legacy adapter: all drop rules, RNG progression and cache state live in one LootModel.
const LootModel := preload("res://scripts/gameplay/profile/loot_model.gd")
var _owned_model: LootModel
var _model: LootModel:
	get:
		assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
		if _owned_model == null:
			_owned_model = LootModel.new(preload("res://scripts/gameplay/profile/legacy_profile_content.gd").resolve(),
				preload("res://scripts/gameplay/profile/legacy_loot_trace_port.gd").new(),
				OS.has_feature("debug") and OS.get_environment("HARDCORE_DPV2_TRACE") == "1")
		return _owned_model

func _ready() -> void:
	# Autoload instances are constructed before any are attached to the tree.
	# Keep early construction inert; direct legacy fixtures initialize on first use.
	var _ready_model := _model

func loot_core_for_owner() -> RefCounted:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	return _model

const DROP_CONTRACT_ID = LootModel.DROP_CONTRACT_ID
const BossMaterialDropResolverScript = LootModel.BossMaterialDropResolverScript
const FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID = LootModel.FEMALE_EQUIPMENT_DROP_OUTPUT_BY_ITEM_ID

var _v5_trace_enabled: bool:
	get: return _model._v5_trace_enabled
	set(value): _model._v5_trace_enabled = value

var _v5_roll_sequence: int:
	get: return _model._v5_roll_sequence
	set(value): _model._v5_roll_sequence = value

var _user_additions: RefCounted:
	get: return _model._user_additions
	set(value): _model._user_additions = value

var _sheet_authority: RefCounted:
	get: return _model._sheet_authority
	set(value): _model._sheet_authority = value

var _overflow_telemetry_by_monster_id: Dictionary:
	get: return _model._overflow_telemetry_by_monster_id
	set(value): _model._overflow_telemetry_by_monster_id = value

var _lean_profile_by_monster_id: Dictionary:
	get: return _model._lean_profile_by_monster_id
	set(value): _model._lean_profile_by_monster_id = value

var _lean_probability_by_key: Dictionary:
	get: return _model._lean_probability_by_key
	set(value): _model._lean_probability_by_key = value

var _lean_reward_by_slot_uid: Dictionary:
	get: return _model._lean_reward_by_slot_uid
	set(value): _model._lean_reward_by_slot_uid = value

var _lean_cache_misses: Dictionary:
	get: return _model._lean_cache_misses
	set(value): _model._lean_cache_misses = value

func begin_monster_drop_roll_job(monster_id: int, rng: RandomNumberGenerator, include_audit := false) -> Dictionary:
	return _model.begin_monster_drop_roll_job(monster_id, rng, include_audit)

func _new_drop_roll_result(monster_id: int) -> Dictionary:
	return _model._new_drop_roll_result(monster_id)

func advance_monster_drop_roll_job(job: Dictionary, max_slots := 1) -> Dictionary:
	return _model.advance_monster_drop_roll_job(job, max_slots)

func _advance_monster_drop_roll_job_phase(job: Dictionary, max_slots := 1) -> Dictionary:
	return _model._advance_monster_drop_roll_job_phase(job, max_slots)

func _finish_drop_roll_job(job: Dictionary) -> Dictionary:
	return _model._finish_drop_roll_job(job)

func _production_profile(monster_id: int) -> Dictionary:
	return _model._production_profile(monster_id)

func _production_probability(monster_id: int, slot_uid: String) -> Dictionary:
	return _model._production_probability(monster_id, slot_uid)

func _lean_profile(monster_id: int) -> Dictionary:
	return _model._lean_profile(monster_id)

func _lean_probability(monster_id: int, slot_uid: String) -> Dictionary:
	return _model._lean_probability(monster_id, slot_uid)

func _lean_reward(slot: Dictionary) -> Dictionary:
	return _model._lean_reward(slot)

func _production_reward(slot: Dictionary) -> Dictionary:
	return _model._production_reward(slot)

func clear_runtime_resolution_cache_for_test() -> void:
	_model.clear_runtime_resolution_cache_for_test()

func runtime_resolution_cache_debug_snapshot() -> Dictionary:
	return _model.runtime_resolution_cache_debug_snapshot()

func possible_item_names_for_monster_ids(monster_ids: Array) -> Array[String]:
	return _model.possible_item_names_for_monster_ids(monster_ids)

func roll_monster_drops(
	monster_id: int,
	rng: RandomNumberGenerator,
	include_audit := true,
) -> Dictionary:
	return _model.roll_monster_drops(monster_id, rng, include_audit)

func _drop_output_item_name(canonical_item_id: int, original_name: String) -> String:
	return _model._drop_output_item_name(canonical_item_id, original_name)

func _drop_output_item_record(
	canonical_item_id: int,
	original_name: String,
	rng: RandomNumberGenerator = null,
) -> Dictionary:
	return _model._drop_output_item_record(canonical_item_id, original_name, rng)

func _unresolved_drop_item_record(
	attempted_item_id: int,
	original_name: String,
	output_name: String,
) -> Dictionary:
	return _model._unresolved_drop_item_record(attempted_item_id, original_name, output_name)

func _stable_catalog_item_id(record: Dictionary) -> int:
	return _model._stable_catalog_item_id(record)

func _build_attempt(
	slot: Dictionary,
	probability: Dictionary,
	reward: Dictionary,
	draw: int,
	success: bool,
) -> Dictionary:
	return _model._build_attempt(slot, probability, reward, draw, success)

func _record_attempt(result: Dictionary, attempt: Dictionary) -> void:
	_model._record_attempt(result, attempt)

func _sync_attempt_views(result: Dictionary) -> void:
	_model._sync_attempt_views(result)

func _begin_resumable_selection(successful_rewards: Array, maximum_ground_slots: int) -> Dictionary:
	return _model._begin_resumable_selection(successful_rewards, maximum_ground_slots)

func _advance_resumable_selection(selection: Dictionary, rng: RandomNumberGenerator, work: int) -> Dictionary:
	return _model._advance_resumable_selection(selection, rng, work)

func _select_ground_rewards(
	successful_rewards: Array,
	rng: RandomNumberGenerator,
	maximum_ground_slots: int,
) -> Dictionary:
	return _model._select_ground_rewards(successful_rewards, rng, maximum_ground_slots)

func _mark_selected(candidate: Dictionary) -> void:
	_model._mark_selected(candidate)

func _append_discarded(result: Dictionary, candidate: Dictionary) -> void:
	_model._append_discarded(result, candidate)

func _shuffle_candidates(candidates: Array, rng: RandomNumberGenerator) -> void:
	_model._shuffle_candidates(candidates, rng)

func _chance_denominator(token: String) -> int:
	return _model._chance_denominator(token)

func record_overflow_telemetry(monster_id: int, drop_roll: Dictionary) -> Dictionary:
	return _model.record_overflow_telemetry(monster_id, drop_roll)

func overflow_telemetry_snapshot() -> Dictionary:
	return _model.overflow_telemetry_snapshot()

func clear_overflow_telemetry() -> void:
	_model.clear_overflow_telemetry()

func _append_rejection(
	result: Dictionary,
	slot: Dictionary,
	reason: String,
) -> void:
	_model._append_rejection(result, slot, reason)

func _v5_write_trace(result: Dictionary) -> void:
	_model._v5_write_trace(result)
