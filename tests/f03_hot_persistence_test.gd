extends Node

const StateScript := preload("res://scripts/player_state.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")

class ObservedState extends StateScript:
	var synchronous_atomic_entries: Array[String] = []
	func _write_json_atomic(target: String, document: Dictionary) -> bool:
		synchronous_atomic_entries.append(target)
		return super._write_json_atomic(target, document)

var failures: Array[String] = []
var measurements: Array[Dictionary] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true # Only the unused autoload; fixtures use real IO.
	_expect(GameData.ensure_loaded(), "authority must load")
	for size: int in [1, 51, 201, 501]:
		await _measure_existing_table(size)
	_expect(measurements.size() == 4, "all table sizes must execute")
	if measurements.size() == 4:
		_expect(int(measurements[3].event_bytes) - int(measurements[0].event_bytes) < 1500, "one changed slot must not serialize the other 501 existing slots")
	print("F03_HOT_PERSISTENCE_MEASUREMENTS " + JSON.stringify(measurements))
	for failure: String in failures:
		printerr("F03_HOT_PERSISTENCE_FAILURE " + failure)
	print("F03_HOT_PERSISTENCE_PASS" if failures.is_empty() else "F03_HOT_PERSISTENCE_FAIL")
	get_tree().quit(0 if failures.is_empty() else 1)


func _measure_existing_table(size: int) -> void:
	# Constructor only: avoid invoking a second autoload _ready or reading a
	# profile outside this fixture. Every file path is under runner-isolated user://.
	var state: ObservedState = ObservedState.new()
	state.test_mode = false
	var sandbox := "user://f03_hot_%d_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec(), size]
	state.profile_directory = sandbox.path_join("characters")
	state.profile_index_path = sandbox.path_join("profiles.json")
	state.active_profile_id = "hot"
	state.reset_progress(false)
	state.level = 50
	state.recalculate_stats(false)
	var deadline := Time.get_unix_time_from_system() + 3600.0
	for index in range(size):
		_expect(state.mark_monster_respawn_dead(913203, "existing:%d" % index, 64, "normal_cave", deadline), "existing deadline rejected")
	_expect(state.save_game(false), "initial real world/profile baseline must commit")
	_expect(state.mark_monster_respawn_dead(913203, "new-death", 64, "normal_cave", deadline), "new deadline rejected")
	state.synchronous_atomic_entries.clear()
	var death_started := Time.get_ticks_usec()
	var death_request := state.prepare_death_settlement([{"monster_name": "", "experience": 1}], {})
	var death_prepare_usec := Time.get_ticks_usec() - death_started
	var settled: Dictionary = {"pending": true}
	var poll_max_usec := 0
	while bool(settled.get("pending", false)):
		var poll_started := Time.get_ticks_usec()
		settled = state.finish_prepared_death_settlement(death_request)
		poll_max_usec = maxi(poll_max_usec, Time.get_ticks_usec() - poll_started)
		if bool(settled.get("pending", false)):
			await get_tree().process_frame
	_expect(state.synchronous_atomic_entries.is_empty(), "native death must not enter synchronous file persistence")
	_expect(bool(settled.get("success", false)), "real compatibility death settlement must commit")
	var event_path := state._death_event_path(state.active_profile_id, 1)
	var bytes := FileAccess.get_file_as_bytes(event_path)
	var event: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	_expect(event is Dictionary and Ledger.valid_death_event(event, "hot", 1), "real event must validate")
	state.synchronous_atomic_entries.clear()
	var started := Time.get_ticks_usec()
	var plan: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 7}])
	var preparation_usec := Time.get_ticks_usec() - started
	_expect(plan.has("writer"), "gold pickup must use its preparation owner")
	var prepare_sync_entries := state.synchronous_atomic_entries.size()
	_expect(prepare_sync_entries == 0, "pickup preparation must not call synchronous world/profile atomic persistence")
	if plan.has("writer"):
		var result: Dictionary = {"pending": true}
		var until := Time.get_ticks_msec() + 5000
		while bool(result.get("pending", false)) and Time.get_ticks_msec() < until:
			result = state.finish_prepared_loot_save(plan)
			if bool(result.get("pending", false)):
				await get_tree().process_frame
		_expect(bool(result.get("success", false)), "gold pickup must eventually durably commit")
		# Test the recovery contract used to remove pickup's forced checkpoint:
		# older world snapshot + newer character + consecutive journal events.
		state.world_monster_respawn_state = {}
		state.load_save()
		_expect(bool(state.last_load_result.get("success", false)), "uncheckpointed world must recover through its journal")
		_expect(absf(float(state.monster_respawn_entry(913203, "new-death").get("respawn_at_unix", 0.0)) - deadline) < 0.0001, "recovered deadline must match its native persisted value")
		_expect(state.gold == 7 and state.experience == 1, "recovery must retain XP and exactly one pickup")
	measurements.append({"existing_slots": size, "event_bytes": bytes.size(), "death_prepare_usec": death_prepare_usec, "death_poll_max_usec": poll_max_usec, "pickup_prepare_usec": preparation_usec, "prepare_sync_atomic_entries": prepare_sync_entries})
	state.free()


func _expect(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
