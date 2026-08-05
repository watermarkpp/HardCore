class_name WorldBootstrapCoordinator
extends RefCounted

# ── P1-B: Staged World Bootstrap Coordinator ──

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

var stage := Stage.IDLE
var generation := 0
var map_id := -1
var mode := ""
var started_at_usec := 0

# ── queues ──
var _map_build_queue: Array[Dictionary] = []
var _collision_build_queue: Array[Dictionary] = []
var _actor_spawn_queue: Array[Dictionary] = []

# ── resources ──
var resource_manifest: Dictionary = {}
var _prefetched_resources: Dictionary = {}

# ── barriers ──
var loading_frame_barrier: Callable = Callable()

# ── diagnostics ──
var diagnostic: Dictionary = {}
var _synchronous_load_during_spawn := 0
var _slice_count := 0
var _max_slice_ms := 0.0
var _total_slice_ms := 0.0


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
	_synchronous_load_during_spawn = 0
	_slice_count = 0
	_max_slice_ms = 0.0
	_total_slice_ms = 0.0
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
	}


func advance(new_stage: Stage) -> void:
	stage = new_stage
	diagnostic["stage"] = Stage.keys()[new_stage]


func finish(success: bool, reason: String) -> Dictionary:
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


func mark_heavy_work_started(gen: int) -> bool:
	return gen == generation


func loading_barrier_completed() -> void:
	diagnostic["loading_barrier_completed"] = true


# ── Resource Collection ──

func collect_map_resources(map_data: Dictionary) -> void:
	advance(Stage.COLLECT_REQUIREMENTS)
	resource_manifest.clear()
	diagnostic["resource_count"] = 0


func _register_resource(path: String, kind: String, required: bool, owner_id: String) -> void:
	if path.is_empty():
		return
	if path in resource_manifest:
		var entry: Dictionary = resource_manifest[path]
		(entry["owners"] as Array).append(owner_id)
		entry["required"] = entry["required"] or required
		return
	resource_manifest[path] = {
		"path": path,
		"kind": kind,
		"required": required,
		"owners": [owner_id],
		"status": "pending",
	}
	diagnostic["resource_count"] += 1


# ── Frame-Budget Queue Processor ──

func process_queue_with_budget(
	queue: Array,
	handler: Callable,
	max_items: int,
	budget_ms: float
) -> void:
	while not queue.is_empty():
		var _slice_start := Time.get_ticks_usec()
		var _processed := 0
		while not queue.is_empty():
			var item: Variant = queue.pop_front()
			if item is Dictionary:
				handler.call(item as Dictionary)
			_processed += 1
			var _elapsed := (Time.get_ticks_usec() - _slice_start) / 1000.0
			if _processed >= max_items or _elapsed >= budget_ms:
				break
		_slice_count += 1
		var _ms := (Time.get_ticks_usec() - _slice_start) / 1000.0
		_max_slice_ms = maxf(_max_slice_ms, _ms)
		_total_slice_ms += _ms
		if not queue.is_empty():
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
	var d := diagnostic.duplicate(true)
	d["generation"] = generation
	d["stage"] = Stage.keys()[stage]
	return d
