class_name MonsterVisualStreamingCoordinator
extends RefCounted

## Q2-D / HC-P1-011: single owner of the global MonsterVisual streaming poll.
## GameRoot owns exactly one instance; MonsterVisual instances register their
## needs, receive cached results and keep their own animation. The coordinator
## never decides actions, directions, frames, timing or combat.

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")

const CONTRACT_ID := "hardcore.monster.visual_streaming_coordinator.v1"
const CLIENT_RESOURCE_CACHE_CAPACITY := 12
const CLIENT_RESOURCE_CACHE_BUDGET_BYTES := 64 * 1024 * 1024
const MAX_CONCURRENT_PROFILE_LOADS := 2
const ACTIONS := ["idle", "walk", "attack", "hit", "death"]


var _threaded_profile_requests: Dictionary = {}
var _threaded_profile_queue: Array[String] = []
var _client_resource_profiles: Dictionary = {}
var _client_resource_profile_lru: Array[String] = []
var _client_resource_profile_bytes: Dictionary = {}
var _client_resource_cache_bytes := 0
var _threaded_texture_request_count := 0
var _threaded_texture_get_count := 0
var _map_prefetch_keys: Array[String] = []
var _map_pinned_profile_keys: Dictionary = {}
var _map_prefetch_completed_keys: Dictionary = {}
var _map_pinned_bytes := 0
var _map_prefetch_generation := 0
var _last_streaming_poll_frame := -1
var _request_sequence := 0

var _visual_subscriptions: Dictionary = {}
var _resource_waiters: Dictionary = {}
var _sync_load_count := 0
var _sync_load_paths: Array[String] = []
var _request_order: Array[String] = []
var _apply_order: Array[String] = []

## Diagnostics (monster_streaming_diagnostics).
var per_instance_poll_call_count := 0
var coordinator_poll_count := 0
var heavy_poll_execution_count := 0
var request_enqueue_count := 0
var unique_request_count := 0
var duplicate_request_count := 0
var active_request_count := 0
var ready_resource_count := 0
var failed_resource_count := 0
var status_poll_count := 0
var resource_apply_count := 0
var stale_completion_count := 0
var invalid_subscriber_cleanup_count := 0
var max_waiting_visuals_per_resource := 0


func client_resources(cache_key: String) -> Dictionary:
	var cached: Variant = _client_resource_profiles.get(cache_key, {})
	if cached is Dictionary and not cached.is_empty():
		_touch_client_resource_profile(cache_key)
		return cached
	return {}


## Public cache admission used by the deterministic test/sync path (keeps one
## cache truth inside the coordinator).
func retain_client_resource_profile(
	cache_key: String,
	resources: Dictionary
) -> void:
	_retain_client_resource_profile(cache_key, resources)


func request_client_profile(
	client_mapping: Dictionary,
	monster_id := -1,
	map_generation := -1
) -> void:
	var helper := MonsterVisualScript.new()
	var cache_key := helper._client_resource_cache_key(client_mapping)
	helper.free()
	request_enqueue_count += 1
	if _client_resource_profiles.has(cache_key):
		duplicate_request_count += 1
		return
	if _threaded_profile_requests.has(cache_key):
		var existing: Dictionary = _threaded_profile_requests[cache_key]
		if map_generation >= 0:
			existing["map_generation"] = map_generation
			existing["monster_id"] = monster_id
			_threaded_profile_requests[cache_key] = existing
		duplicate_request_count += 1
		return
	var paths := {}
	var expected_sizes := {}
	var frame_size_values: Array = client_mapping.get("frameSize", [160, 160])
	var frame_size := Vector2i(int(frame_size_values[0]), int(frame_size_values[1]))
	var actions: Dictionary = client_mapping.get("actions", {})
	for action_name: String in ACTIONS:
		var action: Dictionary = actions.get(action_name, {})
		var path := str(action.get("path", ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			_threaded_profile_requests[cache_key] = {
				"state": "failed",
				"mapping": client_mapping,
				"monster_id": monster_id,
				"map_generation": map_generation,
				"request_sequence": _request_sequence,
				"failed_path": path,
			}
			failed_resource_count += 1
			_request_sequence += 1
			return
		paths[action_name] = path
		expected_sizes[action_name] = (
			frame_size
			* Vector2i(int(action.get("framesPerDirection", 1)), 8)
		)
	_request_sequence += 1
	_request_order.append(cache_key)
	_threaded_profile_requests[cache_key] = {
		"state": "queued",
		"mapping": client_mapping.duplicate(true),
		"paths": paths,
		"expected_sizes": expected_sizes,
		"monster_id": monster_id,
		"map_generation": map_generation,
		"request_sequence": _request_sequence,
	}
	unique_request_count += 1
	_threaded_profile_queue.append(cache_key)
	_pump_threaded_profile_queue()


func _pump_threaded_profile_queue() -> void:
	var active_count := 0
	for job: Dictionary in _threaded_profile_requests.values():
		if str(job.get("state", "")) in ["loading", "loaded"]:
			active_count += 1
	while (
		active_count < MAX_CONCURRENT_PROFILE_LOADS
		and not _threaded_profile_queue.is_empty()
	):
		var cache_key: String = _threaded_profile_queue.pop_front()
		if not _threaded_profile_requests.has(cache_key):
			continue
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "queued":
			continue
		var paths: Dictionary = job.get("paths", {})
		var failed_path := ""
		for action_name: String in ACTIONS:
			var path := str(paths.get(action_name, ""))
			var request_error := ResourceLoader.load_threaded_request(
				path,
				"Texture2D",
				true
			)
			if request_error != OK:
				failed_path = path
				break
			_threaded_texture_request_count += 1
		if not failed_path.is_empty():
			job["state"] = "failed"
			job["failed_path"] = failed_path
			failed_resource_count += 1
		else:
			job["state"] = "loading"
			active_count += 1
		_threaded_profile_requests[cache_key] = job
	active_request_count = _threaded_profile_requests.size()


## The single formal streaming poll. GameRoot calls this once per frame with
## the current process-frame id; internal frame dedup keeps heavy work <= 1.
func poll_once(frame_id: int) -> Dictionary:
	if frame_id == _last_streaming_poll_frame:
		return map_prefetch_status()
	_last_streaming_poll_frame = frame_id
	coordinator_poll_count += 1
	heavy_poll_execution_count += 1
	var helper := MonsterVisualScript.new()
	for cache_key: String in _threaded_profile_requests.keys():
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "loading":
			continue
		var ready := true
		var failed := false
		var paths: Dictionary = job.get("paths", {})
		for action_name: String in ACTIONS:
			status_poll_count += 1
			var status := ResourceLoader.load_threaded_get_status(
				str(paths.get(action_name, ""))
			)
			if (
				status == ResourceLoader.THREAD_LOAD_FAILED
				or status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
			):
				failed = true
				break
			if status != ResourceLoader.THREAD_LOAD_LOADED:
				ready = false
		if failed:
			job["state"] = "failed"
			job["failed_path"] = str(paths.get("idle", ""))
			failed_resource_count += 1
			_threaded_profile_requests[cache_key] = job
			continue
		if not ready:
			continue
		var mapping: Dictionary = job.get("mapping", {})
		var result := helper._client_profile_shell(mapping)
		var expected_sizes: Dictionary = job.get("expected_sizes", {})
		for action_name: String in ACTIONS:
			var texture := ResourceLoader.load_threaded_get(
				str(paths[action_name])
			) as Texture2D
			_threaded_texture_get_count += 1
			if (
				texture == null
				or Vector2i(texture.get_size())
					!= Vector2i(expected_sizes[action_name])
			):
				failed = true
				break
			result[action_name] = texture
			result["frame_counts"][action_name] = int(
				mapping.get("actions", {}).get(action_name, {}).get(
					"framesPerDirection", 1
				)
			)
		if failed or not MonsterAnimationPolicy.validate(result).is_empty():
			job["state"] = "failed"
			job["failed_path"] = str(paths.get("idle", ""))
			failed_resource_count += 1
			_threaded_profile_requests[cache_key] = job
			continue
		job["state"] = "loaded"
		job["resources"] = result
		_threaded_profile_requests[cache_key] = job
	_commit_loaded_profiles()
	_pump_threaded_profile_queue()
	helper.free()
	_cleanup_invalid_subscribers()
	return map_prefetch_status()


func _commit_loaded_profiles() -> void:
	# Prefetch jobs commit strictly in caller order (stable pin priority).
	for cache_key: String in _map_prefetch_keys:
		if _map_prefetch_completed_keys.has(cache_key):
			continue
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		var state := str(job.get("state", ""))
		if state == "failed":
			continue
		if state != "loaded":
			break
		_dispatch_loaded_job(cache_key, job, true)
	# Non-prefetch requests commit in stable request-sequence order.
	var ready_keys: Array[String] = []
	for cache_key: String in _threaded_profile_requests.keys():
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("state", "")) != "loaded":
			continue
		if (
			int(job.get("map_generation", -1)) == _map_prefetch_generation
			and _map_prefetch_keys.has(cache_key)
		):
			continue
		ready_keys.append(cache_key)
	ready_keys.sort_custom(
		func(a: String, b: String) -> bool:
			return (
				int(_threaded_profile_requests.get(a, {}).get(
					"request_sequence", 0
				))
				< int(_threaded_profile_requests.get(b, {}).get(
					"request_sequence", 0
				))
			)
	)
	for cache_key: String in ready_keys:
		_dispatch_loaded_job(cache_key, _threaded_profile_requests[cache_key], false)


func _dispatch_loaded_job(
	cache_key: String,
	job: Dictionary,
	is_prefetch: bool
) -> void:
	var request_generation := int(job.get("map_generation", -1))
	if (
		request_generation >= 0
		and request_generation != _map_prefetch_generation
	):
		# Old-generation completion: never applied to the new world; the shared
		# resource may still enter the bounded cache.
		stale_completion_count += 1
	var resources: Dictionary = job.get("resources", {})
	var estimated_bytes := _estimated_client_profile_bytes(resources)
	if is_prefetch:
		_try_pin_map_profile(cache_key, estimated_bytes)
		_map_prefetch_completed_keys[cache_key] = true
	_retain_client_resource_profile(cache_key, resources)
	_threaded_profile_requests.erase(cache_key)
	_apply_order.append(cache_key)
	ready_resource_count = _client_resource_profiles.size()
	active_request_count = _threaded_profile_requests.size()


func _retain_client_resource_profile(
	cache_key: String,
	resources: Dictionary
) -> void:
	if _client_resource_profiles.has(cache_key):
		_client_resource_cache_bytes -= int(
			_client_resource_profile_bytes.get(cache_key, 0)
		)
	_client_resource_profiles[cache_key] = resources
	var estimated_bytes := _estimated_client_profile_bytes(resources)
	_client_resource_profile_bytes[cache_key] = estimated_bytes
	_client_resource_cache_bytes += estimated_bytes
	_touch_client_resource_profile(cache_key)
	_evict_client_resource_profiles()
	ready_resource_count = _client_resource_profiles.size()


func _evict_client_resource_profiles() -> void:
	while (
		_client_resource_profile_lru.size() > CLIENT_RESOURCE_CACHE_CAPACITY
		or _client_resource_cache_bytes > CLIENT_RESOURCE_CACHE_BUDGET_BYTES
	):
		var expired_index := -1
		for index: int in range(_client_resource_profile_lru.size()):
			if not _map_pinned_profile_keys.has(
				_client_resource_profile_lru[index]
			):
				expired_index = index
				break
		if expired_index < 0:
			return
		var expired_key: String = _client_resource_profile_lru.pop_at(
			expired_index
		)
		_client_resource_cache_bytes -= int(
			_client_resource_profile_bytes.get(expired_key, 0)
		)
		_client_resource_profile_bytes.erase(expired_key)
		_client_resource_profiles.erase(expired_key)
	ready_resource_count = _client_resource_profiles.size()


func _try_pin_map_profile(cache_key: String, estimated_bytes: int) -> bool:
	if _map_pinned_profile_keys.has(cache_key):
		return true
	if _map_pinned_profile_keys.size() >= CLIENT_RESOURCE_CACHE_CAPACITY:
		return false
	if (
		estimated_bytes <= 0
		or _map_pinned_bytes + estimated_bytes
			> CLIENT_RESOURCE_CACHE_BUDGET_BYTES
	):
		return false
	_map_pinned_profile_keys[cache_key] = true
	_map_pinned_bytes += estimated_bytes
	return true


func _estimated_client_profile_bytes(resources: Dictionary) -> int:
	var total := 0
	for action_name: String in ACTIONS:
		var texture := resources.get(action_name) as Texture2D
		if texture != null:
			var size := texture.get_size()
			total += int(size.x) * int(size.y)
	return total


func _touch_client_resource_profile(cache_key: String) -> void:
	_client_resource_profile_lru.erase(cache_key)
	_client_resource_profile_lru.append(cache_key)


func begin_map_prefetch(monster_ids: Array) -> Dictionary:
	release_map_pins()
	_map_prefetch_generation += 1
	var helper := MonsterVisualScript.new()
	var seen_ids := {}
	for value: Variant in monster_ids:
		var monster_id := int(value)
		if seen_ids.has(monster_id):
			continue
		seen_ids[monster_id] = true
		var data := GameData.get_monster_by_id(monster_id)
		if data.is_empty():
			continue
		var mapping := helper._client_mapping_for(data)
		if mapping.is_empty():
			continue
		var cache_key := helper._client_resource_cache_key(mapping)
		_map_prefetch_keys.append(cache_key)
		if _client_resource_profiles.has(cache_key):
			_map_prefetch_completed_keys[cache_key] = true
			_try_pin_map_profile(
				cache_key,
				int(_client_resource_profile_bytes.get(cache_key, 0))
			)
		else:
			request_client_profile(mapping, monster_id, _map_prefetch_generation)
	helper.free()
	return map_prefetch_status()


func map_prefetch_status() -> Dictionary:
	var ready := 0
	var failed := 0
	var streamed := 0
	var pending_details := []
	var failed_details := []
	for cache_key: String in _map_prefetch_keys:
		if _map_prefetch_completed_keys.has(cache_key):
			if _client_resource_profiles.has(cache_key):
				ready += 1
			else:
				streamed += 1
			continue
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		if str(job.get("state", "")) == "failed":
			failed += 1
			failed_details.append({
				"monsterId": int(job.get("monster_id", -1)),
				"path": str(job.get("failed_path", "")),
				"state": "failed",
			})
			continue
		var path_states := []
		for path: Variant in job.get("paths", {}).values():
			var threaded_status := (
				ResourceLoader.load_threaded_get_status(str(path))
				if str(job.get("state", "")) == "loading"
				else -1
			)
			if threaded_status != ResourceLoader.THREAD_LOAD_LOADED:
				path_states.append({"path": str(path), "status": threaded_status})
		pending_details.append({
			"monsterId": int(job.get("monster_id", -1)),
			"state": str(job.get("state", "missing")),
			"paths": path_states,
		})
	var completed := ready + streamed
	return {
		"requested": _map_prefetch_keys.size(),
		"ready": ready,
		"streamed": streamed,
		"pinned": _map_pinned_profile_keys.size(),
		"pinned_bytes": _map_pinned_bytes,
		"failed": failed,
		"pending": _map_prefetch_keys.size() - completed - failed,
		"pending_details": pending_details,
		"failed_details": failed_details,
		"complete": completed + failed == _map_prefetch_keys.size(),
	}


func release_map_pins() -> void:
	_map_prefetch_keys.clear()
	_map_pinned_profile_keys.clear()
	_map_prefetch_completed_keys.clear()
	_map_pinned_bytes = 0
	for cache_key: String in _threaded_profile_queue.duplicate():
		var job: Dictionary = _threaded_profile_requests.get(cache_key, {})
		if (
			int(job.get("map_generation", -1)) >= 0
			and str(job.get("state", "")) == "queued"
		):
			_threaded_profile_queue.erase(cache_key)
			_threaded_profile_requests.erase(cache_key)
	_evict_client_resource_profiles()


func register_visual(
	visual: Node,
	monster_runtime_id: int,
	runtime_map_id: int,
	world_generation: int,
	resource_key: String,
	resource_paths: Dictionary,
	stable_visual_order: int
) -> void:
	var visual_id := visual.get_instance_id()
	if _visual_subscriptions.has(visual_id):
		return
	_visual_subscriptions[visual_id] = {
		"visual_ref": weakref(visual),
		"monster_runtime_id": monster_runtime_id,
		"runtime_map_id": runtime_map_id,
		"world_generation": world_generation,
		"resource_key": resource_key,
		"resource_paths": resource_paths,
		"stable_visual_order": stable_visual_order,
	}
	if not resource_key.is_empty():
		var waiters: Array = _resource_waiters.get(resource_key, [])
		waiters.append(visual_id)
		_resource_waiters[resource_key] = waiters
		max_waiting_visuals_per_resource = maxi(
			max_waiting_visuals_per_resource,
			waiters.size()
		)


func unregister_visual(visual_id: int) -> void:
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	if sub.is_empty():
		return
	var key := str(sub.get("resource_key", ""))
	_visual_subscriptions.erase(visual_id)
	if not key.is_empty() and _resource_waiters.has(key):
		var waiters: Array = _resource_waiters[key]
		waiters.erase(visual_id)
		if waiters.is_empty():
			_resource_waiters.erase(key)
		else:
			_resource_waiters[key] = waiters


func registered_visual_count() -> int:
	return _visual_subscriptions.size()


## Called by MonsterVisual when a cached client profile is applied to a visual
## (the pull-based application path). Counts per-visual resource applications.
func notify_visual_applied(resource_key: String) -> void:
	resource_apply_count += 1


func request_order() -> Array:
	return _request_order.duplicate()


func apply_order() -> Array:
	return _apply_order.duplicate()


func set_generation_for_tests(generation: int) -> void:
	_map_prefetch_generation = generation


func waiting_visual_count_for_resource(resource_key: String) -> int:
	return (_resource_waiters.get(resource_key, []) as Array).size()


func pending_request_count() -> int:
	return _threaded_profile_requests.size()


func _cleanup_invalid_subscribers() -> void:
	for raw_id: Variant in _visual_subscriptions.keys():
		var sub: Dictionary = _visual_subscriptions.get(raw_id, {})
		var visual_ref: WeakRef = sub.get("visual_ref")
		var visual: Object = (
			visual_ref.get_ref()
			if visual_ref != null
			else null
		)
		if (
			visual == null
			or not is_instance_valid(visual)
			or (visual is Node and (visual as Node).is_queued_for_deletion())
		):
			unregister_visual(int(raw_id))
			invalid_subscriber_cleanup_count += 1


func record_sync_load(path: String) -> void:
	_sync_load_count += 1
	_sync_load_paths.append(path)


func sync_load_count() -> int:
	return _sync_load_count


func sync_load_paths() -> Array:
	return _sync_load_paths.duplicate()


func cached_client_profile_count() -> int:
	return _client_resource_profiles.size()


func cached_client_profile_estimated_bytes() -> int:
	return _client_resource_cache_bytes


func threaded_texture_request_count() -> int:
	return _threaded_texture_request_count


func threaded_texture_get_count() -> int:
	return _threaded_texture_get_count


func current_world_generation() -> int:
	return _map_prefetch_generation


func reset_for_tests() -> void:
	_threaded_profile_requests.clear()
	_threaded_profile_queue.clear()
	_client_resource_profiles.clear()
	_client_resource_profile_lru.clear()
	_client_resource_profile_bytes.clear()
	_client_resource_cache_bytes = 0
	_threaded_texture_request_count = 0
	_threaded_texture_get_count = 0
	_map_prefetch_keys.clear()
	_map_pinned_profile_keys.clear()
	_map_prefetch_completed_keys.clear()
	_map_pinned_bytes = 0
	_map_prefetch_generation = 0
	_last_streaming_poll_frame = -1
	_request_sequence = 0
	_request_order.clear()
	_apply_order.clear()
	_visual_subscriptions.clear()
	_resource_waiters.clear()
	_sync_load_count = 0
	_sync_load_paths.clear()
	per_instance_poll_call_count = 0
	coordinator_poll_count = 0
	heavy_poll_execution_count = 0
	request_enqueue_count = 0
	unique_request_count = 0
	duplicate_request_count = 0
	active_request_count = 0
	ready_resource_count = 0
	failed_resource_count = 0
	status_poll_count = 0
	resource_apply_count = 0
	stale_completion_count = 0
	invalid_subscriber_cleanup_count = 0
	max_waiting_visuals_per_resource = 0


func monster_streaming_diagnostics() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"registered_visual_count": _visual_subscriptions.size(),
		"per_instance_poll_call_count": per_instance_poll_call_count,
		"coordinator_poll_count": coordinator_poll_count,
		"heavy_poll_execution_count": heavy_poll_execution_count,
		"request_enqueue_count": request_enqueue_count,
		"unique_request_count": unique_request_count,
		"duplicate_request_count": duplicate_request_count,
		"active_request_count": _threaded_profile_requests.size(),
		"ready_resource_count": _client_resource_profiles.size(),
		"failed_resource_count": failed_resource_count,
		"status_poll_count": status_poll_count,
		"resource_apply_count": resource_apply_count,
		"stale_completion_count": stale_completion_count,
		"invalid_subscriber_cleanup_count": invalid_subscriber_cleanup_count,
		"sync_load_count": _sync_load_count,
		"sync_load_paths": _sync_load_paths.duplicate(),
		"max_waiting_visuals_per_resource": max_waiting_visuals_per_resource,
	}
