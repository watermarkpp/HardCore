extends Node

const State := preload("res://scripts/player_state.gd")
const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
const World := preload("res://scripts/world_monster_respawn_state.gd")
const Delta := preload("res://scripts/world_clock_delta.gd")

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	_test_mixed_replay()
	var path := "user://f03_quest_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var state := _state(path)
	state.reset_progress(false)
	assert(state.save_game(false))
	assert(state.accept_quest("bich_beginner_gear").begins_with("已接受"))
	assert(state.abandon_quest("bich_beginner_gear").success)
	assert(state._death_event_sequence == 0)
	state.free()
	# A new instance proves the no-longer-active quest is not retained in an
	# in-memory dirty map. Backup still contains that quest at the SAME seq.
	state = _state(path)
	state.load_save()
	assert(state.last_load_result.success)
	assert(not state.quest_states.has("bich_beginner_gear"))
	assert(state.record_kills_and_experience_batch([{"monster_name": "稻草人", "experience": 1}], true).success)
	var primary: String = state._profile_path("quest")
	var backup: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(primary + ".bak"))
	assert(backup.quest_states.has("bich_beginner_gear"), "counterexample needs older active quest")
	var corrupt := FileAccess.open(primary, FileAccess.WRITE)
	assert(corrupt != null)
	corrupt.store_string("{broken")
	corrupt.close()
	state.load_save()
	assert(state.last_load_result.success)
	assert(not state.quest_states.has("bich_beginner_gear"), "journal must not resurrect abandoned quest from same-sequence backup")
	assert(state._death_event_sequence == 1 and state.experience == 1)
	state.free()
	print("F03_WORLD_DELTA_COMPATIBILITY_PASS")
	get_tree().quit(0)

func _state(path: String) -> Node:
	var state := State.new()
	state.profile_directory = path.path_join("characters")
	state.profile_index_path = path.path_join("profiles.json")
	state.active_profile_id = "quest"
	state.test_mode = false
	return state

func _test_mixed_replay() -> void:
	var baseline := World.empty_snapshot()
	var state := World.with_deadline(baseline, 913203, "old", 64, "normal_cave", 10000.0)
	var old := Ledger.death_event_document("mixed", 1, 10, 5, {}, state)
	var entry: Dictionary = state.entries["913203|old"].duplicate(true)
	entry.spawn_slot_id = "new"
	entry.respawn_at_unix = 12000.0
	var next := Ledger.delta_death_event_document("mixed", 2, 10, 6, {"q": {"status": "claimed"}}, {"913203|old": null, "913203|new": entry})
	var profile := {"profile_id": "mixed", "death_event_sequence": 0, "level": 10, "experience": 0, "quest_states": {}}
	var result := Ledger.replay(profile, Ledger.snapshot_document("mixed", 0, baseline), [old, next])
	assert(result.ok and result.latest_sequence == 2 and result.experience == 6)
	assert(result.world_state.entries.size() == 1 and result.world_state.entries.has("913203|new"))
	assert(result.quest_states.q.status == "claimed")
	assert(not Ledger.replay(profile, Ledger.snapshot_document("mixed", 0, baseline), [next]).ok)
	for variant: String in ["foreign_profile", "foreign_generation", "foreign_slot", "duplicate_removal", "fractional_id", "invalid_deadline"]:
		var broken := next.duplicate(true)
		match variant:
			"foreign_profile": broken.profile_id = "other"
			"foreign_generation": broken.world_clock_generation = "0123456789abcdef0123456789abcdef"
			"foreign_slot": broken.world_delta.upserts["913203|new"].spawn_slot_id = "other"
			"duplicate_removal": broken.world_delta.removals.append("913203|old")
			"fractional_id": broken.world_delta.upserts["913203|new"].monster_id = 64.5
			"invalid_deadline": broken.world_delta.upserts["913203|new"].respawn_at_unix = -1.0
		assert(not Ledger.valid_death_event(broken, "mixed", 2), variant)
	assert(not Delta.valid_world_patch({"upserts": {}, "removals": ["-1|slot"]}))
