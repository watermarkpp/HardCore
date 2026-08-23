class_name WorldBootstrapCoordinator
extends RefCounted

# ── P1-B / P1-004: Staged World Bootstrap Coordinator ──
#
# HC-P1-004 contract:
#   * every bootstrap stage obtains formal resources through the unified
#     prefetch cache (get_build_resource); a missing cache entry is recorded
#     as an unexpected synchronous load and fails the bootstrap;
#   * BUILD_MAP / BUILD_COLLISION are drained through frame-budget queues,
#     one atomic unit per task, with real planned/built/slice metrics;
#   * generation tokens guard every async resume point;
#   * READY is only granted after the full collision/readiness contract.

enum Stage {
	IDLE,
	SHOW_LOADING,
	COLLECT_REQUIREMENTS,
	REQUEST_RESOURCES,
	WAIT_RESOURCES,
	BUILD_MAP,
	BUILD_COLLISION,
	SPAWN_ACTORS,
	FINALIZE,
	READY,
	FAILED,
}

const DEFAULT_SLICE_BUDGET_MS := 3.0
const DEFAULT_MAX_ITEMS_PER_FRAME := 12
const BUILD_STAGE_LABELS := {
	"BUILD_MAP": "BUILD_MAP",
	"BUILD_COLLISION": "BUILD_COLLISION",
	"SPAWN_ACTORS": "SPAWN_ACTORS",
}

var stage := Stage.IDLE
var generation := 0
var map_id := -1
var mode := ""
var started_at_usec := 0

# When false the budget queues drain without yielding between slices. This is
# the production adapter's test-mode fast path; slicing, metrics and per-item
# handlers are identical to the yielding path.
var defer_between_slices := true

# ── queues ──
var _map_build_queue: Array[Dictionary] = []
var _collision_build_queue: Array[Dictionary] = []
var _actor_spawn_queue: Array[Dictionary] = []

# ── resources ──
var resource_manifest: Dictionary = {}
var _prefetched_resources: Dictionary = {}
var _consumed_paths: Dictionary = {}
var _sync_load_recorded: Dictionary = {}
var target_region := ""

# ── barriers ──
var loading_frame_barrier: Callable = Callable()

# ── diagnostics ──
var diagnostic: Dictionary = {}
var _synchronous_load_during_spawn := 0
var _slice_count := 0
var _max_slice_ms := 0.0
var _total_slice_ms := 0.0

var unexpected_sync_load_count := 0
var unexpected_sync_load_count_build_map := 0
var unexpected_sync_load_count_build_collision := 0
var unexpected_sync_load_count_spawn_actors := 0
var unexpected_sync_load_paths: Array = []
var unexpected_sync_load_stages: Array = []

var planned_map_item_count := 0
var built_map_item_count := 0
var map_slice_count := 0
var map_max_items_in_slice := 0
var map_max_slice_ms := 0.0

var planned_collision_count := 0
var built_collision_count := 0
var failed_collision_count := 0
var collision_slice_count := 0
var collision_max_items_in_slice := 0
var collision_max_slice_ms := 0.0

var target_map_resource_count := 0
var shared_resource_count := 0
var cross_region_resource_count := 0
var unused_prefetched_resource_count := 0


func begin_initial_world(_map_id: int) -> void:
	_internal_begin(_map_id, "initial_world")


func begin_map_transition(_map_id: int) -> void:
	_internal_begin(_map_id, "map_transition")


func _internal_begin(_map_id: int, _mode: String) -> void:
	generation += 1
	map_id = _map_id
	mode = _mode
	stage = Stage.IDLE
	started_at_usec = Time.get_ticks_usec()
	_map_build_queue.clear()
	_collision_build_queue.clear()
	_actor_spawn_queue.clear()
	resource_manifest.clear()
	_prefetched_resources.clear()
	_consumed_paths.clear()
	_sync_load_recorded.clear()
	_synchronous_load_during_spawn = 0
	_slice_count = 0
	_max_slice_ms = 0.0
	_total_slice_ms = 0.0
	unexpected_sync_load_count = 0
	unexpected_sync_load_count_build_map = 0
	unexpected_sync_load_count_build_collision = 0
	unexpected_sync_load_count_spawn_actors = 0
	unexpected_sync_load_paths.clear()
	unexpected_sync_load_stages.clear()
	planned_map_item_count = 0
	built_map_item_count = 0
	map_slice_count = 0
	map_max_items_in_slice = 0
	map_max_slice_ms = 0.0
	planned_collision_count = 0
	built_collision_count = 0
	failed_collision_count = 0
	collision_slice_count = 0
	collision_max_items_in_slice = 0
	collision_max_slice_ms = 0.0
	target_map_resource_count = 0
	shared_resource_count = 0
	cross_region_resource_count = 0
	unused_prefetched_resource_count = 0
	target_region = ""
	diagnostic = _empty_diagnostic()


func _empty_diagnostic() -> Dictionary:
	return {
		"generation": generation,
		"mode": mode,
		"map_id": map_id,
		"stage": "",
		"success": true,
		"failure_reason": "",
		"loading_barrier_completed": false,
		"resource_count": 0,
		"prefetch_failure_count": 0,
		"map_item_count": 0,
		"collision_count": 0,
		"planned_actors": 0,
		"spawned_actors": 0,
		"duplicate_actors": 0,
		"failed_actors": 0,
		"sync_load_spawn": 0,
		"slice_count": 0,
		"max_slice_ms": 0.0,
		"avg_slice_ms": 0.0,
		"target_map_resource_count": 0,
		"shared_resource_count": 0,
		"cross_region_resource_count": 0,
		"unused_prefetched_resource_count": 0,
		"planned_map_item_count": 0,
		"built_map_item_count": 0,
		"map_slice_count": 0,
		"map_max_items_in_slice": 0,
		"map_max_slice_ms": 0.0,
		"planned_collision_count": 0,
		"built_collision_count": 0,
		"failed_collision_count": 0,
		"collision_slice_count": 0,
		"collision_max_items_in_slice": 0,
		"collision_max_slice_ms": 0.0,
		"unexpected_sync_load_count": 0,
		"unexpected_sync_load_count_build_map": 0,
		"unexpected_sync_load_count_build_collision": 0,
		"unexpected_sync_load_count_spawn_actors": 0,
		"unexpected_sync_load_paths": [],
		"unexpected_sync_load_stages": [],
		"stage_elapsed_ms": {},
	}


func advance(new_stage: Stage) -> void:
	stage = new_stage
	var stage_name := str(Stage.keys()[new_stage])
	diagnostic["stage"] = stage_name
	var elapsed_by_stage: Dictionary = diagnostic.get("stage_elapsed_ms", {})
	elapsed_by_stage[stage_name] = (
		(Time.get_ticks_usec() - started_at_usec) / 1000.0
	)
	diagnostic["stage_elapsed_ms"] = elapsed_by_stage


func is_generation_current(gen: int) -> bool:
	return gen == generation


func mark_heavy_work_started(gen: int) -> bool:
	return gen == generation


func loading_barrier_completed() -> void:
	diagnostic["loading_barrier_completed"] = true


func finish(success: bool, reason: String) -> Dictionary:
	_finalize_resource_scope()
	_sync_diagnostics()
	if success:
		stage = Stage.READY
	else:
		stage = Stage.FAILED
	diagnostic["success"] = success
	diagnostic["failure_reason"] = reason
	diagnostic["sync_load_spawn"] = _synchronous_load_during_spawn
	diagnostic["slice_count"] = _slice_count
	diagnostic["max_slice_ms"] = _max_slice_ms
	diagnostic["avg_slice_ms"] = _total_slice_ms / maxf(1.0, float(_slice_count))
	diagnostic["total_duration_ms"] = (Time.get_ticks_usec() - started_at_usec) / 1000.0
	return snapshot()


func _sync_diagnostics() -> void:
	diagnostic["target_map_resource_count"] = target_map_resource_count
	diagnostic["shared_resource_count"] = shared_resource_count
	diagnostic["cross_region_resource_count"] = cross_region_resource_count
	diagnostic["unused_prefetched_resource_count"] = unused_prefetched_resource_count
	diagnostic["planned_map_item_count"] = planned_map_item_count
	diagnostic["built_map_item_count"] = built_map_item_count
	diagnostic["map_slice_count"] = map_slice_count
	diagnostic["map_max_items_in_slice"] = map_max_items_in_slice
	diagnostic["map_max_slice_ms"] = map_max_slice_ms
	diagnostic["planned_collision_count"] = planned_collision_count
	diagnostic["built_collision_count"] = built_collision_count
	diagnostic["failed_collision_count"] = failed_collision_count
	diagnostic["collision_slice_count"] = collision_slice_count
	diagnostic["collision_max_items_in_slice"] = collision_max_items_in_slice
	diagnostic["collision_max_slice_ms"] = collision_max_slice_ms
	diagnostic["unexpected_sync_load_count"] = unexpected_sync_load_count
	diagnostic["unexpected_sync_load_count_build_map"] = unexpected_sync_load_count_build_map
	diagnostic["unexpected_sync_load_count_build_collision"] = unexpected_sync_load_count_build_collision
	diagnostic["unexpected_sync_load_count_spawn_actors"] = unexpected_sync_load_count_spawn_actors
	diagnostic["unexpected_sync_load_paths"] = unexpected_sync_load_paths.duplicate()
	diagnostic["unexpected_sync_load_stages"] = unexpected_sync_load_stages.duplicate()


# ── Resource Collection ──

func set_target_region(region: String) -> void:
	target_region = region


func collect_map_resources(map_data: Dictionary) -> void:
	advance(Stage.COLLECT_REQUIREMENTS)
	resource_manifest.clear()
	diagnostic["resource_count"] = 0
	target_map_resource_count = 0
	shared_resource_count = 0
	cross_region_resource_count = 0
	unused_prefetched_resource_count = 0


func _register_resource(
	path: String,
	kind: String,
	required: bool,
	owner_id: String,
	scope := "target",
	region := ""
) -> void:
	if path.is_empty():
		return
	if path in resource_manifest:
		var entry: Dictionary = resource_manifest[path]
		(entry["owners"] as Array).append(owner_id)
		entry["required"] = entry["required"] or required
		if scope == "shared":
			entry["scope"] = "shared"
		if region != "":
			entry["region"] = region
		return
	var effective_scope := "shared" if scope == "shared" else "target"
	var effective_region := region if region != "" else target_region
	resource_manifest[path] = {
		"path": path,
		"kind": kind,
		"required": required,
		"owners": [owner_id],
		"status": "pending",
		"scope": effective_scope,
		"region": effective_region,
	}
	if effective_scope == "shared":
		shared_resource_count += 1
	else:
		target_map_resource_count += 1
	diagnostic["resource_count"] += 1


func register_resource(
	path: String,
	kind: String,
	required: bool,
	owner_id: String,
	scope := "target",
	region := ""
) -> void:
	_register_resource(path, kind, required, owner_id, scope, region)


func _finalize_resource_scope() -> void:
	cross_region_resource_count = 0
	for _path: Variant in resource_manifest:
		var entry: Dictionary = resource_manifest[_path]
		if str(entry.get("scope", "target")) == "target":
			var entry_region := str(entry.get("region", ""))
			if target_region != "" and entry_region != target_region:
				cross_region_resource_count += 1
	unused_prefetched_resource_count = 0
	for _path: Variant in resource_manifest:
		var entry: Dictionary = resource_manifest[_path]
		if str(entry.get("status", "")) == "ready" and not _consumed_paths.has(str(_path)):
			unused_prefetched_resource_count += 1


func resource_scope_summary() -> Dictionary:
	_finalize_resource_scope()
	return {
		"target_map_resource_count": target_map_resource_count,
		"shared_resource_count": shared_resource_count,
		"cross_region_resource_count": cross_region_resource_count,
		"unused_prefetched_resource_count": unused_prefetched_resource_count,
		"target_region": target_region,
	}


# ── Unified resource acquisition / sync-load sentinel ──

func get_build_resource(path: String, stage_name: String) -> Resource:
	var res := get_prefetched_resource(path)
	if res != null:
		_consumed_paths[path] = true
		return res
	_record_unexpected_sync_load(path, stage_name)
	return null


func _record_unexpected_sync_load(path: String, stage_name: String) -> void:
	if _sync_load_recorded.get(stage_name, {}).has(path):
		return
	if not _sync_load_recorded.has(stage_name):
		_sync_load_recorded[stage_name] = {}
	_sync_load_recorded[stage_name][path] = true
	unexpected_sync_load_paths.append(path)
	unexpected_sync_load_stages.append(stage_name)
	unexpected_sync_load_count += 1
	match stage_name:
		"BUILD_MAP":
			unexpected_sync_load_count_build_map += 1
		"BUILD_COLLISION":
			unexpected_sync_load_count_build_collision += 1
		"SPAWN_ACTORS":
			unexpected_sync_load_count_spawn_actors += 1


func has_unexpected_sync_load() -> bool:
	return unexpected_sync_load_count > 0


func sync_load_summary() -> Dictionary:
	return {
		"count": unexpected_sync_load_count,
		"build_map": unexpected_sync_load_count_build_map,
		"build_collision": unexpected_sync_load_count_build_collision,
		"spawn_actors": unexpected_sync_load_count_spawn_actors,
		"paths": unexpected_sync_load_paths.duplicate(),
		"stages": unexpected_sync_load_stages.duplicate(),
	}


func ready_contract_summary() -> Dictionary:
	_sync_diagnostics()
	return {
		"generation": generation,
		"stage": Stage.keys()[stage],
		"map_id": map_id,
		"planned_map_item_count": planned_map_item_count,
		"built_map_item_count": built_map_item_count,
		"planned_collision_count": planned_collision_count,
		"built_collision_count": built_collision_count,
		"failed_collision_count": failed_collision_count,
		"unexpected_sync_load_count": unexpected_sync_load_count,
		"resource_count": diagnostic.get("resource_count", 0),
		"cross_region_resource_count": cross_region_resource_count,
	}


# ── Frame-Budget Queue Processor ──

func process_queue_with_budget(
	queue: Array,
	handler: Callable,
	max_items: int,
	budget_ms: float
) -> void:
	await _process_staged_queue(queue, handler, max_items, budget_ms, "generic")


func submit_map_descriptors(descriptors: Array) -> void:
	_map_build_queue.clear()
	for descriptor: Variant in descriptors:
		if descriptor is Dictionary:
			_map_build_queue.append(descriptor as Dictionary)
	planned_map_item_count = _map_build_queue.size()
	built_map_item_count = 0
	map_slice_count = 0
	map_max_items_in_slice = 0
	map_max_slice_ms = 0.0


func submit_collision_descriptors(descriptors: Array) -> void:
	_collision_build_queue.clear()
	for descriptor: Variant in descriptors:
		if descriptor is Dictionary:
			_collision_build_queue.append(descriptor as Dictionary)
	planned_collision_count = _collision_build_queue.size()
	built_collision_count = 0
	failed_collision_count = 0
	collision_slice_count = 0
	collision_max_items_in_slice = 0
	collision_max_slice_ms = 0.0


func process_map_queue(handler: Callable, max_items: int, budget_ms: float) -> void:
	await _process_staged_queue(_map_build_queue, handler, max_items, budget_ms, "map")


func process_collision_queue(
	handler: Callable,
	max_items: int,
	budget_ms: float
) -> void:
	await _process_staged_queue(
		_collision_build_queue,
		handler,
		max_items,
		budget_ms,
		"collision"
	)


func _process_staged_queue(
	queue: Array,
	handler: Callable,
	max_items: int,
	budget_ms: float,
	kind: String
) -> void:
	while not queue.is_empty():
		var slice_start := Time.get_ticks_usec()
		var processed := 0
		while not queue.is_empty():
			var item: Variant = queue.pop_front()
			if item is Dictionary:
				var result: Variant = handler.call(item as Dictionary)
				if kind == "map":
					built_map_item_count += 1
				elif kind == "collision":
					if result == null:
						failed_collision_count += 1
					else:
						built_collision_count += 1
			processed += 1
			var elapsed_ms := (Time.get_ticks_usec() - slice_start) / 1000.0
			if processed >= max_items or elapsed_ms >= budget_ms:
				break
		var slice_ms := (Time.get_ticks_usec() - slice_start) / 1000.0
		_slice_count += 1
		_max_slice_ms = maxf(_max_slice_ms, slice_ms)
		_total_slice_ms += slice_ms
		if kind == "map":
			map_slice_count += 1
			map_max_items_in_slice = maxi(map_max_items_in_slice, processed)
			map_max_slice_ms = maxf(map_max_slice_ms, slice_ms)
		elif kind == "collision":
			collision_slice_count += 1
			collision_max_items_in_slice = maxi(
				collision_max_items_in_slice, processed
			)
			collision_max_slice_ms = maxf(collision_max_slice_ms, slice_ms)
		if not queue.is_empty() and defer_between_slices:
			await Engine.get_main_loop().process_frame


func record_sync_load() -> void:
	_synchronous_load_during_spawn += 1


# ── Threaded Resource Prefetch ──

func request_threaded_prefetch() -> int:
	var _requested := 0
	for _path: Variant in resource_manifest:
		var _entry: Dictionary = resource_manifest[_path]
		if not (_entry.get("required", true) as bool):
			continue
		var _status := ResourceLoader.load_threaded_request(str(_path))
		if _status == OK or _status == ERR_ALREADY_IN_USE:
			_entry["status"] = "requested"
			_requested += 1
		else:
			_entry["status"] = "request_failed"
			diagnostic["prefetch_failure_count"] += 1
	return _requested


func poll_threaded_prefetch() -> bool:
	var _pending := 0
	for _path: Variant in resource_manifest:
		var _entry: Dictionary = resource_manifest[_path]
		if _entry.get("status", "") != "requested":
			continue

		var _progress: Array = []
		var _status := ResourceLoader.load_threaded_get_status(str(_path), _progress)
		match _status:
			ResourceLoader.THREAD_LOAD_LOADED:
				var _res := ResourceLoader.load_threaded_get(str(_path))
				if _res != null:
					_prefetched_resources[str(_path)] = _res
					_entry["status"] = "ready"
				else:
					_entry["status"] = "load_failed"
					if _entry.get("required", true):
						diagnostic["prefetch_failure_count"] += 1
			ResourceLoader.THREAD_LOAD_FAILED:
				_entry["status"] = "load_failed"
				if _entry.get("required", true):
					diagnostic["prefetch_failure_count"] += 1
			_:
				_pending += 1
	return _pending == 0


func poll_threaded_prefetch_blocking(timeout_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not poll_threaded_prefetch():
		if Time.get_ticks_msec() >= deadline:
			return false
	return true


func get_prefetched_resource(path: String) -> Resource:
	var _res: Variant = _prefetched_resources.get(path)
	if _res is Resource:
		return _res
	return null


func has_failed_required_resource() -> bool:
	for _path: Variant in resource_manifest:
		var _entry: Dictionary = resource_manifest[_path]
		if _entry.get("required", true) and _entry.get("status", "") in ["request_failed", "load_failed"]:
			return true
	return false


func snapshot() -> Dictionary:
	_sync_diagnostics()
	var d := diagnostic.duplicate(true)
	d["generation"] = generation
	d["stage"] = Stage.keys()[stage]
	return d
