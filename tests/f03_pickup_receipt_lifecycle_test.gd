extends Node

const State := preload("res://scripts/player_state.gd")
const StageFixture := preload("res://tests/helpers/ordered_json_stage_fixture.gd")
var observed_signals := 0
var owned_plan: Dictionary = {}
var owned_state: Node

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	assert(GameData.ensure_loaded())
	var state := State.new()
	owned_state = state
	var root := "user://f03_receipt_%d_%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "owner"
	state.test_mode = false
	state.reset_progress(false)
	assert(state.save_game(false))
	var path: String = state._profile_path("owner")
	owned_plan = state.prepare_loot_save([{"gold": true, "amount": 17}])
	assert(owned_plan.writer.result(true).success)
	assert(state.gold == 0 and not owned_plan.completed)
	state.profile_changed.connect(_observe_completed_reward)
	await _start_promotion(state, owned_plan)
	assert(state.gold == 0, "worker may make bytes durable, but must never credit live state")
	assert(not owned_plan.writer.cancel(), "promotion already began; cancellation cannot undo durable commit")
	# This genuine public mutation must first consume the older approved loot,
	# then snapshot/add its own reward. A barrier after mutation loses the +5.
	assert(state.add_gold(5))
	assert(state.gold == 22 and observed_signals >= 1)
	assert(state.finish_prepared_loot_save(owned_plan).success)
	assert(state.finish_prepared_loot_save(owned_plan).success)
	assert(state.gold == 22, "repeated polling must not apply +17 twice")
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 22)
	state.profile_changed.disconnect(_observe_completed_reward)
	# A true backing-file failure is observed asynchronously without credit.
	var broken: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 23}])
	assert(broken.writer.result(true).success)
	var file := FileAccess.open(broken.writer.path, FileAccess.WRITE)
	assert(file != null)
	file.store_string("{bad")
	file.close()
	var result := await _finish(state, broken)
	assert(not result.get("success", false) and state.gold == 22)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 22)
	var foreign: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 29}])
	assert(foreign.writer.result(true).success)
	state.active_profile_id = "another"
	result = await _finish(state, foreign)
	assert(result.get("retry", false) and state.gold == 22)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 22)
	state.active_profile_id = "owner"
	state._json_persistence.drain()
	var unapproved: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 31}])
	assert(unapproved.writer.result(true).success)
	state.free()
	assert(unapproved.completed and unapproved.completion.get("retry", false))
	assert(not FileAccess.file_exists(unapproved.writer.path))
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 22)
	# The owner deletion boundary must consume an already committing request.
	state = State.new()
	state.profile_directory = root.path_join("characters")
	state.profile_index_path = root.path_join("profiles.json")
	state.active_profile_id = "owner"
	state.test_mode = false
	state.load_save()
	assert(state.last_load_result.success and state.gold == 22)
	var accepted: Dictionary = state.prepare_loot_save([{"gold": true, "amount": 37}])
	assert(accepted.writer.result(true).success)
	await _start_promotion(state, accepted)
	state.active_profile_id = "other_role"
	state.gold = 777
	state._json_persistence.drain()
	assert(state.gold == 777, "old receipt cannot credit a newer role")
	assert(not accepted.completion.active_state_applied)
	state.free()
	assert(accepted.completed and accepted.completion.success)
	assert(int(JSON.parse_string(FileAccess.get_file_as_string(path)).gold) == 59)
	print("F03_PICKUP_RECEIPT_LIFECYCLE_PASS")
	get_tree().quit(0)

func _start_promotion(state: Node, plan: Dictionary) -> void:
	await StageFixture.await_durable_promotion(state._json_persistence, plan.writer.job,
		state.finish_prepared_loot_save.bind(plan), get_tree())
	assert(not bool(plan.writer.job.response.finished))

func _finish(state: Node, plan: Dictionary) -> Dictionary:
	var deadline := Time.get_ticks_msec() + 5000
	var result: Dictionary = {"pending": true}
	while bool(result.get("pending", false)):
		assert(Time.get_ticks_msec() < deadline)
		result = state.finish_prepared_loot_save(plan)
		if bool(result.get("pending", false)):
			await get_tree().process_frame
	return result

func _observe_completed_reward() -> void:
	observed_signals += 1
	assert(owned_plan.completed and owned_plan.completion.success)
	assert(owned_state.finish_prepared_loot_save(owned_plan).success)
	assert(owned_state.gold in [17, 22])
