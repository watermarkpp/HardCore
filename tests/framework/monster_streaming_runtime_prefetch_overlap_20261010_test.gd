extends Node

const Coordinator := preload("res://scripts/monster_visual_streaming_coordinator.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
var proof := Proof.new()
var failures: Array[String] = []

func check(value: bool, label: String) -> void:
	proof.record(value, label)
	if not value:
		failures.append(label)
		print("HC_TEST_FAIL ", label)
	assert(value, label)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	PlayerState.test_mode = true
	var coordinator := Coordinator.new()
	var helper := MonsterVisual.new()
	var mapping := helper._client_mapping_for(GameData.get_monster_by_id(18))
	check(not mapping.is_empty(), "formal monster 18 mapping missing")
	var key := helper._client_resource_cache_key(mapping)
	helper.free()
	# Real accepted native requests precede the next map's demand for the same
	# profile. No test-created loaded job or synthetic texture replaces the loader.
	coordinator.request_client_profile(mapping, 18, coordinator.current_world_generation())
	check(coordinator._threaded_profile_requests.has(key), "formal runtime job enqueued")
	# Startup may have spent this frame's shared optional allowance. Advance
	# outer frames only until the real native request is accepted, without
	# polling completion; queued jobs are correctly canceled at a map fence.
	while str(coordinator._threaded_profile_requests[key].state) == "queued":
		await get_tree().process_frame
		coordinator._pump_threaded_profile_queue()
	check(str(coordinator._threaded_profile_requests[key].state) == "loading", "fixture requires an accepted runtime request")
	var request_count := coordinator._threaded_texture_request_count
	var sequence := int(coordinator._threaded_profile_requests[key].request_sequence)
	var original_generation := int(coordinator._threaded_profile_requests[key].map_generation)
	coordinator.begin_map_prefetch([18])
	check(coordinator._threaded_texture_request_count == request_count, "overlap issued duplicate native requests")
	check(int(coordinator._threaded_profile_requests[key].request_sequence) == sequence, "request sequence retained")
	check(int(coordinator._threaded_profile_requests[key].map_generation) == original_generation, "reuse retagged original request provenance")
	var deadline := Time.get_ticks_msec() + 20000
	while coordinator.pending_request_count() > 0 and Time.get_ticks_msec() < deadline:
		coordinator.poll_once(Engine.get_process_frames())
		await get_tree().process_frame
	var status: Dictionary = coordinator.map_prefetch_status()
	check(coordinator.pending_request_count() == 0, "real runtime request did not complete: %s" % status)
	check(coordinator._threaded_texture_get_count == request_count, "native retrieval rights must be consumed exactly once")
	check(bool(status.complete) and int(status.pending) == 0, "completed reused runtime job left current map pending: %s" % status)
	# Formal profile 18 exceeds the decoded-RGBA8 map pin budget. It must be
	# counted completed/streamed after one real ordered pin admission rejection,
	# rather than left pending or forced into an over-budget residency pin.
	check(int(status.streamed) == 1 and int(status.pinned) == 0, "oversized completed profile must retain the formal cache budget: %s" % status)
	check(coordinator.monster_streaming_diagnostics().pin_rejection_count == 1, "reused runtime job must visit current map pin admission exactly once")
	check(coordinator.stale_completion_count == 1, "old request generation must retain diagnostic provenance")
	coordinator.release_map_pins()
	if not proof.write_receipt("monster_streaming_runtime_prefetch_overlap_20261010_test", proof.records.size(), failures.size()):
		get_tree().quit(1)
		return
	print("MONSTER_STREAMING_RUNTIME_PREFETCH_OVERLAP_PASS")
	get_tree().quit()
