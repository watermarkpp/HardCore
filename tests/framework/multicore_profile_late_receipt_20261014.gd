extends Node
const State := preload("res://scripts/player_state.gd")
const Stage := preload("res://tests/helpers/ordered_json_stage_fixture.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof = Proof.new()
var failures: Array[String] = []
var checks := 0
func _ready() -> void:
	_run.call_deferred()
func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value: failures.append(label)
func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var state := State.new()
	var root := "user://profile_late_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "old_owner"
	state.test_mode = false
	state.reset_progress(false)
	assert(state.save_game(false))
	var path: String = state._profile_path("old_owner")
	var plan: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 37}])
	assert(plan.writer.result(true).success)
	await Stage.await_durable_promotion(state._json_persistence, plan.writer.job,
		state.finish_prepared_loot_save.bind(plan), get_tree())
	state.active_profile_id = "new_owner"
	state.gold = 777
	var current_generation: int = state._atomic_write_generation
	var current_bytes: PackedByteArray = state._validated_profile_bytes
	var current_path: String = state._validated_profile_path
	state._json_persistence.drain()
	check(state.gold == 777 and not plan.completion.active_state_applied, "old durable reward does not apply to current role")
	check(state._atomic_write_generation == current_generation, "old receipt cannot advance current write generation")
	check(state._validated_profile_bytes == current_bytes and state._validated_profile_path == current_path, "old receipt cannot replace current validated byte cache")
	check(plan.completion.success and plan.completion.saved, "old receipt retains irreversible durable success")
	check(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 37, "the real promoted file retains the old role reward")
	var facts: Array[Dictionary] = state.persistence_receipt_snapshot()
	check(facts.size() == 1 and facts[0].path == path and facts[0].identity.profile_id == "old_owner", "durable old-owner fact remains pending by path and transaction identity")
	if not facts.is_empty():
		check(state.acknowledge_persistence_receipt(facts[0].path, facts[0].identity) and state.persistence_receipt_snapshot().is_empty(), "only explicit consumption acknowledges a durable foreign receipt")
	state.free()
	# The ordinary profile->index path must keep the accepted old-owner index
	# responsibility even when current profile identity changes after promotion.
	state = State.new()
	state.profile_directory = root.path_join("background/characters")
	state.profile_index_path = root.path_join("background/profiles.json")
	state.active_profile_id = "old_background"
	state.test_mode = false
	state.reset_progress(false)
	assert(state.save_game(false))
	assert(state._start_background_save(true))
	var background: Dictionary = state._background_save
	var job: RefCounted = state._json_persistence._queue[0].job
	await Stage.await_durable_promotion(state._json_persistence, job, Callable(state._json_persistence, "pump"), get_tree())
	state.active_profile_id = "new_background"
	state.gold = 888
	current_generation = state._atomic_write_generation
	current_bytes = state._validated_profile_bytes
	state._json_persistence.drain()
	state._world_json_persistence.drain()
	check(background.profile_written and background.index_updated and background.completed, "durable profile retains and completes its ordered index write")
	check(state.gold == 888 and state._atomic_write_generation == current_generation and state._validated_profile_bytes == current_bytes, "old profile and index receipts do not touch current-role state or caches")
	var index: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(state.profile_index_path))
	var indexed_old := false
	for row: Dictionary in index.get("profiles", []):
		if str(row.get("id", "")) == "old_background": indexed_old = true
	check(indexed_old, "the real old-profile index row is persisted after promotion")
	facts = state.persistence_receipt_snapshot()
	check(facts.size() >= 2, "profile and index durable facts remain with their original owner")
	state.free()
	if not proof.write_receipt("multicore_profile_late_receipt_20261014", checks, failures.size()): failures.append("receipt")
	print("MULTICORE_PROFILE_LATE_RECEIPT_%s checks=%d failures=%s" % ["PASS" if failures.is_empty() else "FAIL", checks, failures])
	get_tree().quit(0 if failures.is_empty() else 1)
