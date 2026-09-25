extends Node

const Ledger := preload("res://scripts/world_monster_clock_ledger.gd")
const WorldState := preload("res://scripts/world_monster_respawn_state.gd")


func _ready() -> void:
	var first_world := WorldState.with_deadline(
		WorldState.empty_snapshot(), 913203, "group:0", 64, "normal_cave", 2000.0
	)
	var second_world := WorldState.with_deadline(
		first_world, 913203, "group:1", 64, "normal_cave", 2100.0
	)
	var profile := {
		"profile_id": "clock_test",
		"level": 10,
		"experience": 100,
		"quest_states": {"quest": {"progress": 0}},
		"world_monster_respawn_state": WorldState.empty_snapshot(),
	}
	var first := Ledger.death_event_document(
		"clock_test", 1, 10, 110, {"quest": {"progress": 1}}, first_world
	)
	var second := Ledger.death_event_document(
		"clock_test", 2, 10, 120, {"quest": {"progress": 2}}, second_world
	)
	var replayed := Ledger.replay(profile, {}, [first, second])
	assert(replayed.ok)
	assert(replayed.experience == 120)
	assert(replayed.quest_states.quest.progress == 2)
	assert((replayed.world_state.entries as Dictionary).size() == 2)
	assert(replayed.latest_sequence == 2)
	assert(not Ledger.replay(profile, {}, [second]).ok)
	profile["death_event_sequence"] = 2
	profile["experience"] = 120
	profile["quest_states"] = second.quest_states
	profile.erase("world_monster_respawn_state")
	var snapshot := Ledger.snapshot_document("clock_test", 2, second_world)
	var checkpointed := Ledger.replay(profile, snapshot, [])
	assert(checkpointed.ok)
	assert(checkpointed.experience == 120)
	assert((checkpointed.world_state.entries as Dictionary).size() == 2)
	assert(not Ledger.valid_snapshot(snapshot, "other_profile"))
	assert(not Ledger.valid_death_event(first, "clock_test", 2))
	assert(not Ledger.replay(profile, {}, []).ok)
	var behind_world := Ledger.snapshot_document("clock_test", 1, first_world)
	assert(not Ledger.replay(profile, behind_world, []).ok)
	print("WORLD_MONSTER_CLOCK_LEDGER_PASS")
	get_tree().quit(0)
