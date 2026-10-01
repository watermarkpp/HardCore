extends Node

const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const Budget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const Streaming := preload("res://scripts/monster_visual_streaming_coordinator.gd")
var proof := Proof.new()
var checks := 0
var failures: Array[String] = []
var epoch := 2000
var clock_base := 0
var coordinator := Streaming.new()

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	checks += 1
	if not value:
		failures.append(label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var helper := MonsterVisual.new()
	var mapping := helper._client_mapping_for(GameData.get_monster_by_id(19))
	var key := helper._client_resource_cache_key(mapping)
	helper.free()
	check(not mapping.is_empty(), "formal stable monster ID resolves its authoritative art mapping")
	if mapping.is_empty():
		_finish()
		return
	# Admission itself shares the production ledger. Give setup a fresh
	# controlled epoch rather than inheriting autoload work from this frame.
	# Only ledger time is injected; requests and texture retrieval stay native.
	clock_base = Time.get_ticks_usec()
	Budget.configure_for_tests(1000, func() -> int: return epoch,
		func() -> int: return clock_base + coordinator.threaded_texture_get_count() * 1000)
	coordinator.request_client_profile(mapping, 19)
	check(coordinator.threaded_texture_request_count() == 5,
		"fresh setup allowance admits all five actual texture requests")
	var job: Dictionary = coordinator._threaded_profile_requests.get(key, {})
	var paths: Dictionary = job.get("paths", {})
	var ready := false
	var deadline := Time.get_ticks_msec() + 15000
	while not ready and Time.get_ticks_msec() < deadline:
		ready = paths.size() == 5
		for path: String in paths.values():
			ready = ready and ResourceLoader.load_threaded_get_status(path) == ResourceLoader.THREAD_LOAD_LOADED
		if not ready:
			await get_tree().process_frame
	check(ready, "all five actual threaded textures are loaded before controlled foreground retrieval")
	# The ledger advances exactly one allowance after each real threaded get.
	# ResourceLoader and validation remain real; only accounting time is injected.
	var get_before := coordinator.threaded_texture_get_count()
	for action_index in range(5):
		epoch += 1
		coordinator.poll_once(Engine.get_process_frames() + action_index + 1)
		check(coordinator.threaded_texture_get_count() - get_before == action_index + 1,
			"one exhausted quantum retrieves one actual action texture: %d" % action_index)
		check(coordinator.apply_order().is_empty(), "private partial/completed profile waits for admission: %d" % action_index)
		var pending: Dictionary = coordinator._threaded_profile_requests.get(key, {})
		if action_index < 4:
			check(str(pending.get("state", "")) == "collecting" and int(pending.get("action_cursor", 0)) == action_index + 1,
				"unpublished cursor survives between foreground quanta: %d" % action_index)
			check(coordinator._loaded_pending_bytes_total() > 0,
				"retrieved partial textures remain visible in residency accounting")
		else:
			check(str(pending.get("state", "")) == "loaded", "only the complete validated profile becomes ready")
		check(Budget.snapshot().open_scopes == 0, "poll closes all nested budget scopes")
	epoch += 1
	coordinator.poll_once(Engine.get_process_frames() + 10)
	check(coordinator.apply_order() == [key] and coordinator.pending_request_count() == 0,
		"the exact completed profile publishes once after a fresh allowance")
	check(coordinator.client_resources(key).size() > 0 and coordinator.sync_load_count() == 0,
		"production cache receives real textures without synchronous fallback loading")
	Budget.reset_test_configuration()
	_finish()

func _finish() -> void:
	if not proof.write_receipt("resource_completion_cursor_test", checks, failures.size()):
		failures.append("framework assertion receipt failed")
	print(("FRAMEWORK_RESOURCE_COMPLETION_CURSOR_PASS" if failures.is_empty()
		else "FRAMEWORK_RESOURCE_COMPLETION_CURSOR_FAIL") + " checks=" + str(checks) + " failures=" + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)
