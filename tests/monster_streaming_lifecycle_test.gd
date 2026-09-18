extends Node

## perf-smoothness-r1 Phase B failing-first regressions (audit 20260918
## PERF-03/04/05): monster streaming coordinator lifecycle defects.
##
## T1  Old-map in-flight prefetch loses its delivery entry: after a map
##     switch, a completing map-prefetch job is neither in the new
##     _map_prefetch_keys nor in the runtime lane, so it can never dispatch,
##     holds textures, and its dedup entry blocks every future same-key
##     request (the monster type can never be served again that session).
## T2  Failed request entries occupy the dedup key forever: a transient
##     failure can never be retried while a waiter still needs the profile,
##     and a failed entry with no demand is never released.
## T3  Runtime delivery commits only the ready prefix: one slow early
##     request blocks already-loaded later requests, and loaded-not-admitted
##     textures are invisible to byte accounting.

const Fixtures := preload(
	"res://tests/helpers/monster_streaming_test_fixtures.gd"
)
const CoordinatorScript := preload(
	"res://scripts/monster_visual_streaming_coordinator.gd"
)

var _coordinator
var _owners: Array[Node] = []


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	PlayerState.test_mode = true
	PlayerState.reset_progress()
	await _t1_stale_prefetch_job_must_retire()
	await _t2_failed_entry_must_not_block_retry()
	_t3_runtime_ready_jobs_must_not_be_blocked()
	_cleanup()
	print("MONSTER_STREAMING_LIFECYCLE_PASS retire/retry/prefix")
	get_tree().quit(0)


func _mapping_for(monster_id: int) -> Dictionary:
	var helper := MonsterVisual.new()
	var mapping := helper._client_mapping_for(
		GameData.get_monster_by_id(monster_id)
	)
	helper.free()
	assert(not mapping.is_empty(), "missing formal mapping for %d" % monster_id)
	return mapping


func _key_for(mapping: Dictionary) -> String:
	var helper := MonsterVisual.new()
	var key := helper._client_resource_cache_key(mapping)
	helper.free()
	return key


func _new_waiter(resource_key: String, serial: int) -> Node:
	var owner := Node.new()
	add_child(owner)
	_owners.append(owner)
	_coordinator.register_visual(
		owner,
		serial,
		1,
		_coordinator.current_world_generation(),
		resource_key,
		{},
		serial
	)
	return owner


func _poll_until(predicate: Callable, timeout_msec := 30000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		_coordinator.poll_once(Engine.get_process_frames())
		if predicate.call():
			return true
		await get_tree().process_frame
	return false


## T1: an in-flight map-A prefetch job survives release_map_pins (only
## queued jobs are erased), completes after the map-B fence, and must be
## retired - dispatched into the bounded cache with a stale-completion
## diagnostic - instead of stranding forever and blocking same-key demand.
func _t1_stale_prefetch_job_must_retire() -> void:
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	var ids: Array[int] = Fixtures.catalog_ids()
	var monster_a := ids[0]
	var monster_b := ids[1]
	var mapping_a := _mapping_for(monster_a)
	var key_a := _key_for(mapping_a)
	var mapping_b := _mapping_for(monster_b)
	var key_b := _key_for(mapping_b)
	assert(key_a != key_b)

	# Map A requests monster A (in-flight once the pump starts it).
	_coordinator.begin_map_prefetch([monster_a])
	# Map B fence arrives while A is still loading: release_map_pins erases
	# only queued jobs, so A survives as an in-flight old-generation job.
	_coordinator.begin_map_prefetch([monster_b])
	var stale_before: int = int(
		_coordinator.monster_streaming_diagnostics().stale_completion_count
	)

	# Drive both jobs to completion, then require A's retirement.
	var prefetch_complete := await _poll_until(
		func() -> bool:
			var status: Dictionary = _coordinator.map_prefetch_status()
			return bool(status.get("complete", false))
	)
	assert(prefetch_complete, "map B prefetch never completed")
	# A may still be loading when B finishes; give the sweep a bounded window
	# to retire A once it completes (broken coordinators strand it forever).
	var a_retired := await _poll_until(
		func() -> bool:
			return not _coordinator._threaded_profile_requests.has(key_a)
	)
	assert(
		a_retired,
		"old-generation prefetch job was stranded in the request map"
	)
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(
		int(diag.stale_completion_count) > stale_before,
		"stale retirement was not diagnosed"
	)
	# Same-key demand after the map switch must be servicable: either the
	# retired profile is still resident (cache hit) or a fresh request loads.
	var owner := _new_waiter(key_a, 9001)
	var resources: Dictionary = _coordinator.request_visual_resources(
		owner, mapping_a, monster_a, true
	)
	if resources.is_empty():
		var served := await _poll_until(
			func() -> bool:
				return not _coordinator.client_resources(key_a).is_empty()
		)
		assert(
			served,
			"same-key runtime demand after retirement was never served"
		)
	assert(_coordinator.client_resources(key_a).is_empty() == false)
	_coordinator.release_visual_resource(owner)
	_coordinator.unregister_visual(owner.get_instance_id())


## T2: a failed entry must not hold the dedup key forever. With a live
## waiter it is retried after its backoff and can complete; with no demand
## it is released; with exhausted attempts it becomes permanent.
func _t2_failed_entry_must_not_block_retry() -> void:
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	var ids: Array[int] = Fixtures.catalog_ids()
	var monster_id := ids[2]
	var mapping := _mapping_for(monster_id)
	var key := _key_for(mapping)

	_coordinator.request_client_profile(mapping, monster_id, -1)
	assert(_coordinator._threaded_profile_requests.has(key))
	# Simulate a transient load failure with its backoff already elapsed.
	var job: Dictionary = _coordinator._threaded_profile_requests[key]
	job["state"] = "failed"
	job["failure_count"] = 1
	job["retry_at_msec"] = Time.get_ticks_msec() - 1
	_coordinator._threaded_profile_requests[key] = job

	# No waiter and no prefetch membership: the failed entry is released so
	# the dedup key stops being occupied by a dead job.
	await _poll_until(
		func() -> bool:
			return not _coordinator._threaded_profile_requests.has(key)
	)
	assert(
		not _coordinator._threaded_profile_requests.has(key),
		"failed entry without demand must be released"
	)

	# With a live waiter the failure is retried and completes for real.
	var owner := _new_waiter(key, 9002)
	assert(_coordinator.declare_visual_need(owner.get_instance_id(), key, 0))
	_coordinator.request_client_profile(mapping, monster_id, -1)
	assert(_coordinator._threaded_profile_requests.has(key))
	job = _coordinator._threaded_profile_requests[key]
	job["state"] = "failed"
	job["failure_count"] = 1
	job["retry_at_msec"] = Time.get_ticks_msec() - 1
	_coordinator._threaded_profile_requests[key] = job
	var retried_done := await _poll_until(
		func() -> bool:
			return not _coordinator.client_resources(key).is_empty()
	)
	assert(
		retried_done,
		"waited failed profile was never retried to completion"
	)
	_coordinator.release_visual_resource(owner)
	_coordinator.unregister_visual(owner.get_instance_id())

	# Exhausted attempts must become permanent instead of retrying forever.
	# Use a fresh monster id: the previous profile is already resident, so a
	# same-key request would be a cache hit with no job to fail.
	var monster_p: int = Fixtures.catalog_ids()[3]
	var mapping_p := _mapping_for(monster_p)
	var key_p := _key_for(mapping_p)
	_coordinator.request_client_profile(mapping_p, monster_p, -1)
	assert(_coordinator._threaded_profile_requests.has(key_p))
	job = _coordinator._threaded_profile_requests[key_p]
	job["state"] = "failed"
	# MAX_FAILURE_RETRIES (3) exhausted: the state must become permanent.
	job["failure_count"] = 3
	job["retry_at_msec"] = Time.get_ticks_msec() - 1
	_coordinator._threaded_profile_requests[key_p] = job
	var owner2 := _new_waiter(key_p, 9003)
	assert(_coordinator.declare_visual_need(owner2.get_instance_id(), key_p, 0))
	await _poll_until(
		func() -> bool:
			var state := str(
				_coordinator._threaded_profile_requests.get(key_p, {}).get("state", "")
			)
			return state == "permanent_failed"
	)
	assert(
		str(_coordinator._threaded_profile_requests.get(key_p, {}).get("state", ""))
			== "permanent_failed",
		"exhausted failures must stop retrying"
	)
	_coordinator.unregister_visual(owner2.get_instance_id())


## T3: runtime delivery must not stall behind an earlier not-ready request,
## and loaded-not-admitted bytes must be accounted.
func _t3_runtime_ready_jobs_must_not_be_blocked() -> void:
	_coordinator = CoordinatorScript.new()
	MonsterVisual.set_streaming_coordinator(_coordinator)
	MonsterVisual.reset_client_resource_cache()
	var small := _small_profile()
	var small_bytes: int = _coordinator._decoded_rgba8_profile_bytes(small)
	var job_a := {
		"state": "queued",
		"lane": CoordinatorScript.JOB_LANE_RUNTIME_DEMAND,
		"map_generation": -1,
		"request_sequence": 1,
	}
	var job_b := {
		"state": "loaded",
		"lane": CoordinatorScript.JOB_LANE_RUNTIME_DEMAND,
		"map_generation": -1,
		"request_sequence": 2,
		"resources": small,
	}
	var job_c := {
		"state": "loaded",
		"lane": CoordinatorScript.JOB_LANE_RUNTIME_DEMAND,
		"map_generation": -1,
		"request_sequence": 3,
		"resources": small,
	}
	_coordinator._threaded_profile_requests["t3_job_a"] = job_a
	_coordinator._threaded_profile_requests["t3_job_b"] = job_b
	_coordinator._threaded_profile_requests["t3_job_c"] = job_c
	_coordinator._loaded_pending_keys["t3_job_b"] = small_bytes
	_coordinator._loaded_pending_keys["t3_job_c"] = small_bytes

	_coordinator._commit_loaded_profiles()

	# The queued early job must not block the loaded later ones.
	assert(
		not _coordinator._threaded_profile_requests.has("t3_job_b"),
		"ready runtime job B was blocked by the earlier queued job A"
	)
	assert(
		not _coordinator._threaded_profile_requests.has("t3_job_c"),
		"ready runtime job C was blocked by the earlier queued job A"
	)
	assert(_coordinator._threaded_profile_requests.has("t3_job_a"))
	assert(_coordinator.client_resources("t3_job_b").is_empty() == false)
	assert(_coordinator.client_resources("t3_job_c").is_empty() == false)
	# Loaded-not-admitted accounting drains exactly with the dispatches.
	var diag: Dictionary = _coordinator.monster_streaming_diagnostics()
	assert(int(diag.get("loaded_pending_request_count", -1)) == 0)
	assert(int(diag.get("loaded_pending_decoded_rgba8_bytes", -1)) == 0)
	assert(
		_coordinator.cached_client_profile_decoded_rgba8_bytes()
			== small_bytes * 2
	)


func _small_profile() -> Dictionary:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var texture := ImageTexture.create_from_image(image)
	return {
		"idle": texture,
		"walk": texture,
		"attack": texture,
		"hit": texture,
		"death": texture,
	}


func _cleanup() -> void:
	for owner: Node in _owners:
		if is_instance_valid(owner):
			_coordinator.release_visual_resource(owner)
			_coordinator.unregister_visual(owner.get_instance_id())
			owner.queue_free()
	_owners.clear()
	MonsterVisual.reset_client_resource_cache()
