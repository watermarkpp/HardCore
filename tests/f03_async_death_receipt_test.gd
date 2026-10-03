extends Node

const OrderedStageFixture := preload("res://tests/helpers/ordered_json_stage_fixture.gd")

const State := preload("res://scripts/player_state.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
class ObservedState extends State:
	var synchronous_file_writes := 0
	func _write_json_atomic(path: String, document: Dictionary, preserve_known_wire := false) -> bool:
		synchronous_file_writes += 1
		return super._write_json_atomic(path, document, preserve_known_wire)
var signals_seen := 0

func _ready() -> void:
	_run.call_deferred()

func _new_state(root: String) -> Node:
	var state := ObservedState.new()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "death"
	state.test_mode = false
	state.reset_progress(false)
	assert(state.save_game(false))
	return state

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var root := "user://f03_async_death_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := _new_state(root.path_join("async"))
	if not state.has_method("prepare_death_settlement"):
		state.free()
		printerr("F03_ASYNC_DEATH_RECEIPT_FAIL: production death settlement has no nonblocking receipt path")
		get_tree().quit(1)
		return
	var twin := _new_state(root.path_join("compatibility"))
	var kills := [{"monster_name": "稻草人", "experience": 100}]
	assert(twin.record_kills_and_experience_batch(kills, true).success)
	var initial_experience: int = state.experience
	var initial_level: int = state.level
	var deadline := Time.get_unix_time_from_system() + 3600.0
	assert(state.mark_monster_respawn_dead(913203, "older", 64, "normal_cave", deadline))
	var entry := {"runtime_map_id": 913203, "spawn_slot_id": "new", "monster_id": 64,
		"policy_id": "normal_cave", "respawn_at_unix": deadline}
	state.profile_changed.connect(func() -> void: signals_seen += 1)
	state.synchronous_file_writes = 0
	var request: Dictionary = state.prepare_death_settlement(kills, {"913203|new": entry})
	assert(request.has("writer"))
	assert(state.experience == initial_experience and state.level == initial_level and signals_seen == 0)
	assert(state._death_event_sequence == 0 and state.world_monster_respawn_state.entries.size() == 1)
	assert(request.writer.result(true).success)
	assert(state.experience == initial_experience and signals_seen == 0)
	assert(state.mark_monster_respawn_dead(913203, "older", 64, "normal_cave", deadline + 1))
	assert(state.mark_monster_respawn_dead(913203, "later", 64, "normal_cave", deadline + 2))
	var result: Dictionary = await _finish(state, request)
	assert(result.success and state._death_event_sequence == 1)
	assert(state.level == twin.level and state.experience == twin.experience and signals_seen == 1)
	assert(state.world_monster_respawn_state.entries.size() == 3)
	assert(state._world_clock_changes.size() == 2, "later world changes must survive the older receipt")
	assert(state.synchronous_file_writes == 0, "async death may not call the synchronous file wrapper")
	var event_path: String = state._death_event_path("death", 1, state._world_clock_generation)
	var document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(event_path))
	assert(Ledger.valid_death_event(document, "death", 1, state._world_clock_generation))
	assert(document.world_delta.upserts.size() == 2)
	assert(state.finish_prepared_death_settlement(request).success and signals_seen == 1)
	var loaded := State.new()
	loaded.profile_directory = state.profile_directory
	loaded.profile_index_path = state.profile_index_path
	loaded.active_profile_id = "death"
	loaded.test_mode = false
	loaded.load_save()
	assert(loaded.last_load_result.success and loaded.level == twin.level and loaded.experience == twin.experience)
	assert(loaded.world_monster_respawn_state.entries.size() == 2)
	loaded.free()
	# Real TMP corruption: no XP/world application and no sequence advance.
	var failed: Dictionary = state.prepare_death_settlement(kills, {"913203|new": entry})
	assert(failed.writer.result(true).success)
	var broken := FileAccess.open(failed.writer.path, FileAccess.WRITE)
	broken.store_string("{corrupt")
	broken.close()
	result = await _finish(state, failed)
	assert(not result.success and state._death_event_sequence == 1 and signals_seen == 1)
	assert(state.level == twin.level and state.experience == twin.experience)
	assert(not FileAccess.file_exists(state._death_event_path("death", 2, state._world_clock_generation)))
	# A real public mutation consumes accepted older receipts before changing XP.
	var accepted: Dictionary = state.prepare_death_settlement([{"experience": 1}], {})
	assert(accepted.writer.result(true).success)
	state.add_experience(3)
	assert(accepted.completed and accepted.completion.success)
	assert(state._death_event_sequence == 2 and state.experience == twin.experience + 4)
	# A pre-promotion foreign role invalidates the frozen request.
	var foreign: Dictionary = state.prepare_death_settlement([{"experience": 1}], {})
	assert(foreign.writer.result(true).success)
	state.active_profile_id = "other"
	result = await _finish(state, foreign)
	assert(not result.success and state._death_event_sequence == 2)
	state.active_profile_id = "death"
	# The required baseline is checked in the worker; missing files are never
	# converted into an un-replayable successful event.
	var clock_path: String = state._world_clock_path("death", state._world_clock_generation)
	assert(DirAccess.rename_absolute(ProjectSettings.globalize_path(clock_path), ProjectSettings.globalize_path(clock_path + ".held")) == OK)
	var missing: Dictionary = state.prepare_death_settlement([{"experience": 1}], {})
	result = await _finish(state, missing)
	assert(not result.success and result.reason == "required_baseline_missing" and state._death_event_sequence == 2)
	assert(DirAccess.rename_absolute(ProjectSettings.globalize_path(clock_path + ".held"), ProjectSettings.globalize_path(clock_path)) == OK)
	var duplicate_path: String = state._death_event_path("death", 3, state._world_clock_generation)
	var duplicate_document := Ledger.delta_death_event_document("death", 3, state.level, state.experience, state.quest_states, {}, state._world_clock_generation)
	var duplicate := FileAccess.open(duplicate_path, FileAccess.WRITE)
	duplicate.store_string(JSON.stringify(duplicate_document))
	duplicate.close()
	var duplicate_bytes := FileAccess.get_file_as_bytes(duplicate_path)
	var refused: Dictionary = state.prepare_death_settlement([{"experience": 1}], {})
	result = await _finish(state, refused)
	assert(not result.success and result.reason == "journal_sequence_already_exists" and state._death_event_sequence == 2)
	assert(FileAccess.get_file_as_bytes(duplicate_path) == duplicate_bytes)
	# If promotion already completed on the worker, changing the active role
	# cannot undo that receipt and must not credit the newly selected role.
	var late := _new_state(root.path_join("late_foreign"))
	var late_request: Dictionary = late.prepare_death_settlement([{"experience": 1}], {})
	assert(late_request.writer.result(true).success)
	await OrderedStageFixture.await_durable_promotion(late._json_persistence, late_request.writer.job,
		late.finish_prepared_death_settlement.bind(late_request), get_tree())
	late.active_profile_id = "new_role"
	result = await _finish(late, late_request)
	assert(result.success and not result.active_state_applied and result.saved_profile_id == "death")
	assert(late.experience == 0 and late._death_event_sequence == 0)
	late.active_profile_id = "death"
	late.load_save()
	assert(late.last_load_result.success and late.experience == 1 and late._death_event_sequence == 1)
	late.free()
	state.free()
	twin.free()
	print("F03_ASYNC_DEATH_RECEIPT_PASS")
	get_tree().quit(0)

func _finish(state: Node, request: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	var result: Dictionary = {"pending": true}
	while bool(result.get("pending", false)):
		assert(Time.get_ticks_msec() < deadline)
		result = state.finish_prepared_death_settlement(request)
		if bool(result.get("pending", false)):
			await get_tree().process_frame
	return result
