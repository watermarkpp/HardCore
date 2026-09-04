class_name MonsterVisualStreamingCoordinator
extends RefCounted

## Q2-D / HC-P1-011: single owner of the global MonsterVisual streaming poll.
## GameRoot owns exactly one instance; MonsterVisual instances register their
## needs, receive cached results and keep their own animation. The coordinator
## never decides actions, directions, frames, timing or combat.

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")

const CONTRACT_ID := "hardcore.monster.visual_streaming_coordinator.v1"
const CLIENT_RESOURCE_CACHE_CAPACITY := 12
## All cache accounting is decoded, lossless RGBA8 residency: four bytes per
## atlas pixel, summed across the five action atlases. The old name is kept as
## a compatibility constant, but its value is not compressed/ETC2 residency.
const CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES := 64 * 1024 * 1024
const CLIENT_RESOURCE_CACHE_BUDGET_BYTES := CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES
const MAX_CONCURRENT_PROFILE_LOADS := 2
## Subscriber expiry is housekeeping, not resource-completion work. Keep the
## loader/status path per-frame, but visit a fixed number of weak subscriptions
## so a dense map cannot add one full visual walk to every rendered frame.
const MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL := 8
const ACTIONS := ["idle", "walk", "attack", "hit", "death"]
const JOB_LANE_MAP_PREFETCH := "map_prefetch"
const JOB_LANE_RUNTIME_DEMAND := "runtime_demand"


var _threaded_profile_requests: Dictionary = {}
var _threaded_profile_queue: Array[String] = []
var _client_resource_profiles: Dictionary = {}
var _client_resource_profile_lru: Array[String] = []
var _client_resource_profile_decoded_rgba8_bytes: Dictionary = {}
var _client_resource_cache_decoded_rgba8_bytes := 0
var _threaded_texture_request_count := 0
var _threaded_texture_get_count := 0
var _map_prefetch_keys: Array[String] = []
var _map_pinned_profile_keys: Dictionary = {}
var _map_prefetch_completed_keys: Dictionary = {}
var _map_pinned_decoded_rgba8_bytes := 0
var _map_prefetch_generation := 0
## Bootstrap handoff protection is separate from map pins. A profile may be
## larger than the steady-state cache budget, or map pin admission may be
## rejected, while the initial world is still waiting for its first real
## MonsterVisual lease.
var _bootstrap_handoff_hold_keys: Dictionary = {}
var _bootstrap_handoff_hold_generation := -1
var _last_streaming_poll_frame := -1
var _request_sequence := 0

var _visual_subscriptions: Dictionary = {}
var _visual_cleanup_order: Array[int] = []
var _visual_cleanup_cursor := 0
var _sync_load_count := 0
var _sync_load_paths: Array[String] = []
var _request_order: Array[String] = []
var _apply_order: Array[String] = []

## Per-visual/per-resource residency state. A visual is only a waiter while it
## has explicitly requested activation; registration alone is deliberately not
## a waiter. Dictionary values are sets represented as {visual_id: true}.
var _resource_waiters: Dictionary = {}
var _resource_leases: Dictionary = {}
var _visual_waiting_resources: Dictionary = {}
var _visual_leased_resources: Dictionary = {}
var _resource_delivery_keys: Dictionary = {}
var _resource_had_demand: Dictionary = {}
var _resource_first_apply_seen: Dictionary = {}
var _resource_ever_loaded: Dictionary = {}

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
var subscriber_cleanup_visit_count := 0
var subscriber_cleanup_max_visits_per_poll := 0
var max_waiting_visuals_per_resource := 0
var pin_rejection_count := 0
var immediate_eviction_count := 0
var same_key_reload_count := 0
var evicted_before_first_apply_count := 0
var late_completion_resident_skip_count := 0


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
	map_generation := -1,
	job_lane := JOB_LANE_RUNTIME_DEMAND
) -> void:
	var helper := MonsterVisualScript.new()
	var cache_key := helper._client_resource_cache_key(client_mapping)
	helper.free()
	request_enqueue_count += 1
	if _client_resource_profiles.has(cache_key):
		duplicate_request_count += 1
		return
	if _threaded_profile_requests.has(cache_key):
		# The first request owns the job's generation provenance. A later visual
		# from another generation may reuse the completion, but must never retag
		# the job and erase the stale-completion diagnostic.
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
				"lane": job_lane,
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
	if _resource_ever_loaded.has(cache_key):
		same_key_reload_count += 1
	_request_order.append(cache_key)
	_threaded_profile_requests[cache_key] = {
		"state": "queued",
		"mapping": client_mapping.duplicate(true),
		"paths": paths,
		"expected_sizes": expected_sizes,
		"monster_id": monster_id,
		"map_generation": map_generation,
		"request_sequence": _request_sequence,
		"lane": job_lane,
	}
	unique_request_count += 1
	_threaded_profile_queue.append(cache_key)
	_pump_threaded_profile_queue()


func _pump_threaded_profile_queue() -> void:
	var active_count := 0
	for job: Dictionary in _threaded_profile_requests.values():
		if str(job.get("state", "")) == "loading":
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
		if str(job.get("lane", JOB_LANE_MAP_PREFETCH)) != JOB_LANE_MAP_PREFETCH:
			continue
		var state := str(job.get("state", ""))
		if state == "failed":
			continue
		if state != "loaded":
			break
		_dispatch_loaded_job(cache_key, job, true)
	# Runtime demand (including a reload of a completed/evicted map-prefetch
	# key) is a separate delivery lane. It must never re-open or wait behind the
	# map-prefetch completion order: that order only owns initial pin priority.
	# Stable request sequence keeps simultaneous visual demand deterministic.
	var runtime_keys: Array[String] = []
	for cache_key: String in _threaded_profile_requests.keys():
		var job: Dictionary = _threaded_profile_requests[cache_key]
		if str(job.get("lane", JOB_LANE_RUNTIME_DEMAND)) != JOB_LANE_RUNTIME_DEMAND:
			continue
		runtime_keys.append(cache_key)
	runtime_keys.sort_custom(
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
	# Commit only the ready prefix. A later completion cannot overtake an
	# earlier runtime request, but queued/loading jobs no longer consume loaded
	# slots in the queue pump, so this ordering fence cannot deadlock the pump.
	for cache_key: String in runtime_keys:
		var job: Dictionary = _threaded_profile_requests[cache_key]
		var state := str(job.get("state", ""))
		if state == "failed":
			continue
		if state != "loaded":
			break
		_dispatch_loaded_job(cache_key, job, false)


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
	var decoded_rgba8_bytes := _decoded_rgba8_profile_bytes(resources)
	# A loaded completion is a delivery operation. Keep a true current waiter
	# protected across admission/publish even if the byte budget is exceeded;
	# the delivery marker also makes that ordering explicit for diagnostics.
	if _has_resource_waiters(cache_key):
		_resource_delivery_keys[cache_key] = true
	if is_prefetch:
		_try_pin_map_profile(cache_key, decoded_rgba8_bytes)
		_map_prefetch_completed_keys[cache_key] = true
	_retain_client_resource_profile(cache_key, resources)
	_resource_delivery_keys.erase(cache_key)
	_threaded_profile_requests.erase(cache_key)
	_apply_order.append(cache_key)
	ready_resource_count = _client_resource_profiles.size()
	active_request_count = _threaded_profile_requests.size()


func _retain_client_resource_profile(
	cache_key: String,
	resources: Dictionary
) -> void:
	if (
		_client_resource_profiles.has(cache_key)
		and _resource_is_protected(cache_key)
	):
		# A late completion can arrive after another generation/visual has already
		# leased this resident entry. Never replace the Texture2D objects under an
		# active lease (or W/pin); the completion is satisfied by the existing
		# profile and its resource identity remains stable.
		late_completion_resident_skip_count += 1
		_touch_client_resource_profile(cache_key)
		ready_resource_count = _client_resource_profiles.size()
		return
	if _client_resource_profiles.has(cache_key):
		_client_resource_cache_decoded_rgba8_bytes -= int(
			_client_resource_profile_decoded_rgba8_bytes.get(cache_key, 0)
		)
	_client_resource_profiles[cache_key] = resources
	var decoded_rgba8_bytes := _decoded_rgba8_profile_bytes(resources)
	_client_resource_profile_decoded_rgba8_bytes[cache_key] = decoded_rgba8_bytes
	_client_resource_cache_decoded_rgba8_bytes += decoded_rgba8_bytes
	_resource_ever_loaded[cache_key] = true
	# Demand/apply diagnostics describe this resident profile, not an old
	# incarnation of the same cache key. A new W or delivery marker starts a
	# fresh first-apply window; a prefetch-only admission starts with neither.
	if _has_resource_waiters(cache_key) or _resource_delivery_keys.has(cache_key):
		_resource_had_demand[cache_key] = true
	else:
		_resource_had_demand.erase(cache_key)
	_resource_first_apply_seen.erase(cache_key)
	_touch_client_resource_profile(cache_key)
	_evict_client_resource_profiles()
	if (
		not _client_resource_profiles.has(cache_key)
		and _resource_delivery_keys.has(cache_key)
	):
		# This counter is reserved for the forbidden ordering where an active
		# delivery loses its protection during admission and is evicted before
		# its first apply. A cancelled W has no delivery marker and is diagnosed
		# separately by evicted_before_first_apply_count.
		immediate_eviction_count += 1
	ready_resource_count = _client_resource_profiles.size()


func _evict_client_resource_profiles() -> void:
	while (
		_client_resource_profile_lru.size() > CLIENT_RESOURCE_CACHE_CAPACITY
		or _client_resource_cache_decoded_rgba8_bytes
			> CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES
	):
		var expired_index := -1
		for index: int in range(_client_resource_profile_lru.size()):
			var candidate_key: String = _client_resource_profile_lru[index]
			if not _client_resource_profiles.has(candidate_key):
				expired_index = index
				break
			if not _resource_is_protected(candidate_key):
				expired_index = index
				break
		if expired_index < 0:
			return
		var expired_key: String = _client_resource_profile_lru.pop_at(
			expired_index
		)
		_client_resource_cache_decoded_rgba8_bytes -= int(
			_client_resource_profile_decoded_rgba8_bytes.get(expired_key, 0)
		)
		_client_resource_profile_decoded_rgba8_bytes.erase(expired_key)
		_client_resource_profiles.erase(expired_key)
		if (
			_resource_had_demand.has(expired_key)
			and not _resource_first_apply_seen.has(expired_key)
		):
			evicted_before_first_apply_count += 1
		_resource_had_demand.erase(expired_key)
		_resource_first_apply_seen.erase(expired_key)
	ready_resource_count = _client_resource_profiles.size()


func _try_pin_map_profile(cache_key: String, decoded_rgba8_bytes: int) -> bool:
	if _map_pinned_profile_keys.has(cache_key):
		return true
	if _map_pinned_profile_keys.size() >= CLIENT_RESOURCE_CACHE_CAPACITY:
		pin_rejection_count += 1
		return false
	if (
		decoded_rgba8_bytes <= 0
		or _map_pinned_decoded_rgba8_bytes + decoded_rgba8_bytes
			> CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES
	):
		pin_rejection_count += 1
		return false
	_map_pinned_profile_keys[cache_key] = true
	_map_pinned_decoded_rgba8_bytes += decoded_rgba8_bytes
	return true


## Exact cache accounting for the formal lossless mode0/vram=false imports:
## decoded RGBA8 is four bytes for every pixel in every action atlas.
func _decoded_rgba8_profile_bytes(resources: Dictionary) -> int:
	var total := 0
	for action_name: String in ACTIONS:
		var texture := resources.get(action_name) as Texture2D
		if texture != null:
			var size := texture.get_size()
			total += int(size.x) * int(size.y) * 4
	return total


## Compatibility getter. Despite the historical name, this returns exact
## decoded RGBA8 bytes, never compressed/ETC2 residency.
func _estimated_client_profile_bytes(resources: Dictionary) -> int:
	return _decoded_rgba8_profile_bytes(resources)


func _touch_client_resource_profile(cache_key: String) -> void:
	_client_resource_profile_lru.erase(cache_key)
	_client_resource_profile_lru.append(cache_key)


func _set_world_generation(generation: int) -> void:
	if generation == _map_prefetch_generation:
		return
	# A generation fence is also a bootstrap-handoff cancellation boundary.
	# Clear the old hold before stale visual state is released.
	_bootstrap_handoff_hold_keys.clear()
	_bootstrap_handoff_hold_generation = -1
	_map_prefetch_generation = generation
	# Fence old W/L state before any new-generation admission can be published.
	# unregister_visual is idempotent and also removes stale reverse indexes.
	_release_stale_generation_visuals()
	_evict_client_resource_profiles()


func begin_map_prefetch(
	monster_ids: Array,
	hold_for_bootstrap := false
) -> Dictionary:
	release_map_pins()
	_set_world_generation(_map_prefetch_generation + 1)
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
				int(_client_resource_profile_decoded_rgba8_bytes.get(cache_key, 0))
			)
		else:
			request_client_profile(
				mapping,
				monster_id,
				_map_prefetch_generation,
				JOB_LANE_MAP_PREFETCH
			)
	helper.free()
	if hold_for_bootstrap:
		begin_bootstrap_handoff_hold()
	return map_prefetch_status()


## Protect every profile requested by the current map prefetch until its first
## real visual lease arrives. This is temporary handoff protection, not a
## permanent cache pin; leased visuals take over protection per key.
func begin_bootstrap_handoff_hold() -> void:
	_bootstrap_handoff_hold_keys.clear()
	_bootstrap_handoff_hold_generation = _map_prefetch_generation
	for cache_key: String in _map_prefetch_keys:
		_bootstrap_handoff_hold_keys[cache_key] = true
	_evict_client_resource_profiles()


func release_bootstrap_handoff_hold() -> void:
	_bootstrap_handoff_hold_keys.clear()
	_bootstrap_handoff_hold_generation = -1
	_evict_client_resource_profiles()


func bootstrap_handoff_status() -> Dictionary:
	var resident_count := 0
	var held_bytes := 0
	for raw_key: Variant in _bootstrap_handoff_hold_keys.keys():
		var cache_key := str(raw_key)
		if not _client_resource_profiles.has(cache_key):
			continue
		resident_count += 1
		held_bytes += int(
			_client_resource_profile_decoded_rgba8_bytes.get(cache_key, 0)
		)
	return {
		"active": not _bootstrap_handoff_hold_keys.is_empty(),
		"generation": _bootstrap_handoff_hold_generation,
		"hold_count": _bootstrap_handoff_hold_keys.size(),
		"resident_count": resident_count,
		"held_decoded_rgba8_bytes": held_bytes,
	}


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
		"pinned_bytes": _map_pinned_decoded_rgba8_bytes,
		"pinned_decoded_rgba8_bytes": _map_pinned_decoded_rgba8_bytes,
		"decoded_rgba8_bytes": _client_resource_cache_decoded_rgba8_bytes,
		"protected_overbudget_bytes": protected_overbudget_bytes(),
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
	_map_pinned_decoded_rgba8_bytes = 0
	_bootstrap_handoff_hold_keys.clear()
	_bootstrap_handoff_hold_generation = -1
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
	if visual == null or not is_instance_valid(visual):
		return
	if world_generation >= 0 and world_generation != _map_prefetch_generation:
		# A stale actor cannot re-enter R after a map fence. The caller must
		# register again with the current generation from its new map lifecycle.
		return
	var visual_id := visual.get_instance_id()
	if _visual_subscriptions.has(visual_id):
		return
	var subscription_generation := (
		world_generation if world_generation >= 0 else _map_prefetch_generation
	)
	_visual_subscriptions[visual_id] = {
		"visual_ref": weakref(visual),
		"monster_runtime_id": monster_runtime_id,
		"runtime_map_id": runtime_map_id,
		"world_generation": subscription_generation,
		"resource_key": resource_key,
		"resource_paths": resource_paths,
		"stable_visual_order": stable_visual_order,
		"resource_state": "registered",
	}
	_visual_cleanup_order.append(visual_id)


func unregister_visual(visual_id: int) -> void:
	# Unregister is the final U transition and is safe after _exit_tree has
	# already released the same visual. Clear every reverse-indexed key so a
	# stale actor can never keep a new generation's profile protected.
	_forget_visual_cleanup_id(visual_id)
	_release_all_visual_resources(visual_id)
	if not _visual_subscriptions.has(visual_id):
		_evict_client_resource_profiles()
		return
	_visual_subscriptions.erase(visual_id)
	_evict_client_resource_profiles()


func registered_visual_count() -> int:
	return _visual_subscriptions.size()


## Declare an activation demand for one registered visual. Registration is only
## R (registered/no demand); this call is the R -> W transition. The returned
## dictionary is a cache hit, otherwise the caller keeps its fallback while the
## coordinator's one threaded request completes.
func request_visual_resources(
	visual: Node,
	client_mapping: Dictionary,
	monster_id := -1,
	request_async := true
) -> Dictionary:
	if visual == null or not is_instance_valid(visual):
		return {}
	var visual_id := visual.get_instance_id()
	var cache_key := _cache_key_for_mapping(client_mapping)
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	if sub.is_empty() or not _visual_subscription_is_current(visual_id, cache_key):
		return {}
	if not declare_visual_need(
		visual_id,
		cache_key,
		int(sub.get("world_generation", -1))
	):
		return {}
	var cached := client_resources(cache_key)
	if not cached.is_empty():
		return cached
	if request_async:
		# request_client_profile preserves this first job generation as immutable
		# provenance. A later-generation visual reuses, but never retags, it.
		request_client_profile(
			client_mapping,
			monster_id,
			int(sub.get("world_generation", -1)),
			JOB_LANE_RUNTIME_DEMAND
		)
	return {}


## R -> W. The operation is idempotent for repeated activation polls.
func declare_visual_need(
	visual_id: int,
	resource_key: String,
	world_generation := -1
) -> bool:
	if resource_key.is_empty():
		return false
	if not _visual_subscription_is_current(visual_id, resource_key, world_generation):
		return false
	var waiting: Dictionary = _visual_waiting_resources.get(visual_id, {})
	var released_old_lease := false
	for raw_key: Variant in waiting.keys():
		var old_key := str(raw_key)
		if old_key != resource_key:
			_remove_resource_waiter(visual_id, old_key)
	var leases: Dictionary = _visual_leased_resources.get(visual_id, {})
	for raw_key: Variant in leases.keys():
		var old_key := str(raw_key)
		if old_key != resource_key:
			_remove_resource_lease(visual_id, old_key)
			released_old_lease = true
	if _visual_has_resource_lease(visual_id, resource_key):
		if released_old_lease:
			_evict_client_resource_profiles()
		return true
	_add_resource_waiter(visual_id, resource_key)
	_resource_had_demand[resource_key] = true
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	sub["resource_state"] = "waiting"
	_visual_subscriptions[visual_id] = sub
	if released_old_lease:
		_evict_client_resource_profiles()
	return true


## W -> L after MonsterVisual has successfully applied every profile field and
## its first idle frame. Repeated notifications for the same lease are no-ops.
func notify_visual_applied(
	visual_or_id,
	resource_key := "",
	world_generation := -1
) -> bool:
	var visual_id := _visual_id(visual_or_id)
	if visual_id < 0 or resource_key.is_empty():
		# Historical callers only supplied a key; they cannot establish a
		# per-visual lease and are intentionally ignored for safety.
		return false
	if not _visual_subscription_is_current(visual_id, resource_key, world_generation):
		return false
	if not _client_resource_profiles.has(resource_key):
		# L is only valid after the coordinator has admitted the exact profile
		# that the visual says it applied. A stale/optimistic callback cannot
		# create a lease for a resource that is no longer resident.
		return false
	if _visual_has_resource_lease(visual_id, resource_key):
		return true
	_remove_resource_waiter(visual_id, resource_key)
	_add_resource_lease(visual_id, resource_key)
	# The first real visual lease is the handoff boundary for this profile.
	# From here normal per-visual lease protection owns its residency.
	_bootstrap_handoff_hold_keys.erase(resource_key)
	_resource_first_apply_seen[resource_key] = true
	_resource_had_demand[resource_key] = true
	resource_apply_count += 1
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	sub["resource_state"] = "leased"
	_visual_subscriptions[visual_id] = sub
	return true


## L/W -> R. Releasing a visual resource immediately re-runs the original
## cross-zone LRU boundary once the last protection for each key disappears.
func release_visual_resource(
	visual_or_id,
	resource_key := ""
) -> void:
	var visual_id := _visual_id(visual_or_id)
	if visual_id < 0:
		return
	var keys: Dictionary = {}
	if not resource_key.is_empty():
		keys[resource_key] = true
	for raw_key: Variant in (
		_visual_waiting_resources.get(visual_id, {}) as Dictionary
	).keys():
		keys[str(raw_key)] = true
	for raw_key: Variant in (
		_visual_leased_resources.get(visual_id, {}) as Dictionary
	).keys():
		keys[str(raw_key)] = true
	for raw_key: Variant in keys.keys():
		var key := str(raw_key)
		_remove_resource_waiter(visual_id, key)
		_remove_resource_lease(visual_id, key)
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	if not sub.is_empty():
		sub["resource_state"] = "registered"
		_visual_subscriptions[visual_id] = sub
	_evict_client_resource_profiles()


func visual_subscription_is_current(
	visual_or_id,
	resource_key := ""
) -> bool:
	return _visual_subscription_is_current(
		_visual_id(visual_or_id),
		resource_key
	)


func visual_resource_state(visual_or_id) -> String:
	var visual_id := _visual_id(visual_or_id)
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	return str(sub.get("resource_state", "unregistered"))


func _cache_key_for_mapping(client_mapping: Dictionary) -> String:
	var helper := MonsterVisualScript.new()
	var cache_key := helper._client_resource_cache_key(client_mapping)
	helper.free()
	return cache_key


func _visual_id(visual_or_id) -> int:
	if visual_or_id is Node:
		return (visual_or_id as Node).get_instance_id()
	if typeof(visual_or_id) == TYPE_INT:
		return int(visual_or_id)
	return -1


func _visual_subscription_is_current(
	visual_id: int,
	resource_key := "",
	world_generation := -1
) -> bool:
	if visual_id < 0:
		return false
	var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
	if sub.is_empty():
		return false
	var subscribed_key := str(sub.get("resource_key", ""))
	if not resource_key.is_empty() and subscribed_key != str(resource_key):
		return false
	var subscribed_generation := int(sub.get("world_generation", -1))
	if (
		world_generation >= 0
		and subscribed_generation >= 0
		and world_generation != subscribed_generation
	):
		return false
	if (
		subscribed_generation >= 0
		and subscribed_generation != _map_prefetch_generation
	):
		return false
	return true


func _add_resource_waiter(visual_id: int, resource_key: String) -> void:
	var waiters: Dictionary = _resource_waiters.get(resource_key, {})
	waiters[visual_id] = true
	_resource_waiters[resource_key] = waiters
	var waiting: Dictionary = _visual_waiting_resources.get(visual_id, {})
	waiting[resource_key] = true
	_visual_waiting_resources[visual_id] = waiting
	max_waiting_visuals_per_resource = maxi(
		max_waiting_visuals_per_resource,
		waiters.size()
	)


func _remove_resource_waiter(visual_id: int, resource_key: String) -> void:
	if _resource_waiters.has(resource_key):
		var waiters: Dictionary = _resource_waiters[resource_key]
		waiters.erase(visual_id)
		if waiters.is_empty():
			_resource_waiters.erase(resource_key)
		else:
			_resource_waiters[resource_key] = waiters
	if _visual_waiting_resources.has(visual_id):
		var waiting: Dictionary = _visual_waiting_resources[visual_id]
		waiting.erase(resource_key)
		if waiting.is_empty():
			_visual_waiting_resources.erase(visual_id)
		else:
			_visual_waiting_resources[visual_id] = waiting


func _add_resource_lease(visual_id: int, resource_key: String) -> void:
	var leases: Dictionary = _resource_leases.get(resource_key, {})
	leases[visual_id] = true
	_resource_leases[resource_key] = leases
	var visual_leases: Dictionary = _visual_leased_resources.get(visual_id, {})
	visual_leases[resource_key] = true
	_visual_leased_resources[visual_id] = visual_leases


func _remove_resource_lease(visual_id: int, resource_key: String) -> void:
	if _resource_leases.has(resource_key):
		var leases: Dictionary = _resource_leases[resource_key]
		leases.erase(visual_id)
		if leases.is_empty():
			_resource_leases.erase(resource_key)
		else:
			_resource_leases[resource_key] = leases
	if _visual_leased_resources.has(visual_id):
		var visual_leases: Dictionary = _visual_leased_resources[visual_id]
		visual_leases.erase(resource_key)
		if visual_leases.is_empty():
			_visual_leased_resources.erase(visual_id)
		else:
			_visual_leased_resources[visual_id] = visual_leases


func _visual_has_resource_lease(visual_id: int, resource_key: String) -> bool:
	return (
		_visual_leased_resources.has(visual_id)
		and (_visual_leased_resources[visual_id] as Dictionary).has(resource_key)
	)


func _has_resource_waiters(resource_key: String) -> bool:
	return (
		_resource_waiters.has(resource_key)
		and not (_resource_waiters[resource_key] as Dictionary).is_empty()
	)


func _resource_is_protected(resource_key: String) -> bool:
	return (
		_map_pinned_profile_keys.has(resource_key)
		or (
			_bootstrap_handoff_hold_generation == _map_prefetch_generation
			and _bootstrap_handoff_hold_keys.has(resource_key)
		)
		or _has_resource_waiters(resource_key)
		or (
			_resource_leases.has(resource_key)
			and not (_resource_leases[resource_key] as Dictionary).is_empty()
		)
		or _resource_delivery_keys.has(resource_key)
	)


func _release_all_visual_resources(visual_id: int) -> void:
	var keys: Dictionary = {}
	for raw_key: Variant in (
		_visual_waiting_resources.get(visual_id, {}) as Dictionary
	).keys():
		keys[str(raw_key)] = true
	for raw_key: Variant in (
		_visual_leased_resources.get(visual_id, {}) as Dictionary
	).keys():
		keys[str(raw_key)] = true
	for raw_key: Variant in keys.keys():
		var key := str(raw_key)
		_remove_resource_waiter(visual_id, key)
		_remove_resource_lease(visual_id, key)


func _release_stale_generation_visuals() -> void:
	for raw_id: Variant in _visual_subscriptions.keys():
		var visual_id := int(raw_id)
		var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
		var subscribed_generation := int(sub.get("world_generation", -1))
		if subscribed_generation >= 0 and subscribed_generation != _map_prefetch_generation:
			unregister_visual(visual_id)


func request_order() -> Array:
	return _request_order.duplicate()


func apply_order() -> Array:
	return _apply_order.duplicate()


func set_generation_for_tests(generation: int) -> void:
	_set_world_generation(generation)


func waiting_visual_count_for_resource(resource_key: String) -> int:
	return (_resource_waiters.get(resource_key, {}) as Dictionary).size()


func active_lease_count_for_resource(resource_key: String) -> int:
	return (_resource_leases.get(resource_key, {}) as Dictionary).size()


func leased_visual_count() -> int:
	return _visual_leased_resources.size()


func leased_profile_count() -> int:
	var count := 0
	for raw_key: Variant in _resource_leases.keys():
		if not (_resource_leases[raw_key] as Dictionary).is_empty():
			count += 1
	return count


func waiting_visual_count() -> int:
	return _visual_waiting_resources.size()


func protected_overbudget_bytes() -> int:
	return maxi(
		0,
		_client_resource_cache_decoded_rgba8_bytes
			- CLIENT_RESOURCE_CACHE_BUDGET_DECODED_RGBA8_BYTES
	)


func unprotected_cached_client_profile_decoded_rgba8_bytes() -> int:
	var total := 0
	for raw_key: Variant in _client_resource_profiles.keys():
		var key := str(raw_key)
		if _resource_is_protected(key):
			continue
		total += int(_client_resource_profile_decoded_rgba8_bytes.get(key, 0))
	return total


func pending_request_count() -> int:
	return _threaded_profile_requests.size()


func _cleanup_invalid_subscribers() -> void:
	var visits_this_poll := 0
	var visit_budget := mini(
		MAX_SUBSCRIBER_CLEANUP_VISITS_PER_POLL,
		_visual_cleanup_order.size(),
	)
	while visits_this_poll < visit_budget and not _visual_cleanup_order.is_empty():
		if _visual_cleanup_cursor >= _visual_cleanup_order.size():
			_visual_cleanup_cursor = 0
		var visual_id := _visual_cleanup_order[_visual_cleanup_cursor]
		visits_this_poll += 1
		subscriber_cleanup_visit_count += 1
		if not _visual_subscriptions.has(visual_id):
			_visual_cleanup_order.remove_at(_visual_cleanup_cursor)
			continue
		var sub: Dictionary = _visual_subscriptions.get(visual_id, {})
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
			unregister_visual(visual_id)
			invalid_subscriber_cleanup_count += 1
		else:
			_visual_cleanup_cursor += 1
	subscriber_cleanup_max_visits_per_poll = maxi(
		subscriber_cleanup_max_visits_per_poll,
		visits_this_poll,
	)


func _forget_visual_cleanup_id(visual_id: int) -> void:
	var order_index := _visual_cleanup_order.find(visual_id)
	if order_index < 0:
		return
	_visual_cleanup_order.remove_at(order_index)
	if order_index < _visual_cleanup_cursor:
		_visual_cleanup_cursor -= 1
	if _visual_cleanup_order.is_empty() or _visual_cleanup_cursor >= _visual_cleanup_order.size():
		_visual_cleanup_cursor = 0


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
	# Compatibility getter; the returned value is decoded RGBA8 bytes.
	return _client_resource_cache_decoded_rgba8_bytes


func cached_client_profile_decoded_rgba8_bytes() -> int:
	return _client_resource_cache_decoded_rgba8_bytes


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
	_client_resource_profile_decoded_rgba8_bytes.clear()
	_client_resource_cache_decoded_rgba8_bytes = 0
	_threaded_texture_request_count = 0
	_threaded_texture_get_count = 0
	_map_prefetch_keys.clear()
	_map_pinned_profile_keys.clear()
	_map_prefetch_completed_keys.clear()
	_map_pinned_decoded_rgba8_bytes = 0
	_bootstrap_handoff_hold_keys.clear()
	_bootstrap_handoff_hold_generation = -1
	_map_prefetch_generation = 0
	_last_streaming_poll_frame = -1
	_request_sequence = 0
	_request_order.clear()
	_apply_order.clear()
	_visual_subscriptions.clear()
	_visual_cleanup_order.clear()
	_visual_cleanup_cursor = 0
	_resource_waiters.clear()
	_resource_leases.clear()
	_visual_waiting_resources.clear()
	_visual_leased_resources.clear()
	_resource_delivery_keys.clear()
	_resource_had_demand.clear()
	_resource_first_apply_seen.clear()
	_resource_ever_loaded.clear()
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
	subscriber_cleanup_visit_count = 0
	subscriber_cleanup_max_visits_per_poll = 0
	max_waiting_visuals_per_resource = 0
	pin_rejection_count = 0
	immediate_eviction_count = 0
	same_key_reload_count = 0
	evicted_before_first_apply_count = 0
	late_completion_resident_skip_count = 0


func monster_streaming_diagnostics() -> Dictionary:
	var request_state_counts := {
		"queued": 0,
		"loading": 0,
		"loaded": 0,
		"failed": 0,
	}
	for raw_job: Variant in _threaded_profile_requests.values():
		if not raw_job is Dictionary:
			continue
		var state := str((raw_job as Dictionary).get("state", ""))
		if request_state_counts.has(state):
			request_state_counts[state] = int(request_state_counts[state]) + 1
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
		"queued_request_count": int(request_state_counts.queued),
		"loading_request_count": int(request_state_counts.loading),
		"loaded_request_count": int(request_state_counts.loaded),
		"failed_request_count": int(request_state_counts.failed),
		"ready_resource_count": _client_resource_profiles.size(),
		"decoded_rgba8_bytes": _client_resource_cache_decoded_rgba8_bytes,
		"cached_client_profile_decoded_rgba8_bytes": _client_resource_cache_decoded_rgba8_bytes,
		"unprotected_decoded_rgba8_bytes": unprotected_cached_client_profile_decoded_rgba8_bytes(),
		"map_pinned_profile_count": _map_pinned_profile_keys.size(),
		"pinned_decoded_rgba8_bytes": _map_pinned_decoded_rgba8_bytes,
		"bootstrap_handoff_hold_count": _bootstrap_handoff_hold_keys.size(),
		"bootstrap_handoff_resident_count": int(
			bootstrap_handoff_status().get("resident_count", 0)
		),
		"bootstrap_handoff_generation": _bootstrap_handoff_hold_generation,
		"protected_overbudget_bytes": protected_overbudget_bytes(),
		"failed_resource_count": failed_resource_count,
		"status_poll_count": status_poll_count,
		"resource_apply_count": resource_apply_count,
		"stale_completion_count": stale_completion_count,
		"invalid_subscriber_cleanup_count": invalid_subscriber_cleanup_count,
		"subscriber_cleanup_visit_count": subscriber_cleanup_visit_count,
		"subscriber_cleanup_max_visits_per_poll": subscriber_cleanup_max_visits_per_poll,
		"sync_load_count": _sync_load_count,
		"sync_load_paths": _sync_load_paths.duplicate(),
		"max_waiting_visuals_per_resource": max_waiting_visuals_per_resource,
		"waiting_visual_count": _visual_waiting_resources.size(),
		"leased_visual_count": leased_visual_count(),
		"leased_profile_count": leased_profile_count(),
		"pin_rejection_count": pin_rejection_count,
		"immediate_eviction_count": immediate_eviction_count,
		"same_key_reload_count": same_key_reload_count,
		"evicted_before_first_apply_count": evicted_before_first_apply_count,
		"late_completion_resident_skip_count": late_completion_resident_skip_count,
	}
