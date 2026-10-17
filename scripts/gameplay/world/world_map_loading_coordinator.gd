extends RefCounted

var _owner := OS.get_thread_caller_id()
var _runtime: RefCounted
var _resources: RefCounted
var _claim_owner: RefCounted
func owner_thread_id() -> int: return _owner
func configure_owner(runtime: RefCounted, resources: RefCounted, claim_owner: RefCounted) -> bool:
	if _runtime != null or _owner == OS.get_main_thread_id(): return false
	for port: RefCounted in [runtime,resources,claim_owner]:
		if port == null or port is Resource or not port.has_method("owner_thread_id"): return false
		# ProfileRuntimePort uses its original _thread owner field.
		if port.owner_thread_id() != _owner: return false
	for method: String in ["next_service"]:
		if not runtime.has_method(method): return false
	for method: String in ["display_server_name","exists","load","load_threaded_request","load_threaded_get_status","load_threaded_get","is_original_resource_reference","blocking_original_loading_scope_allowed"]:
		if not resources.has_method(method): return false
	if not claim_owner.has_method("retire_threaded_resource_claims"): return false
	_runtime = runtime
	_resources = resources
	_claim_owner = claim_owner
	return true

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
var _generation_valid := true
var map_id := -1
var mode := ""
var started_at_usec := 0
# P0-1/P0-3 audit trail: the most recent FAILED bootstrap, kept across
# chained recovery transitions that overwrite stage/diagnostic.
var last_failure: Dictionary = {}

# When false the budget queues drain without yielding between slices. This is
# the production adapter's test-mode fast path; slicing, metrics and per-item
# handlers are identical to the yielding path.
var defer_between_slices := true

# ── queues ──
var _map_build_queue: Array[Dictionary] = []
var _collision_build_queue: Array[Dictionary] = []
var _actor_spawn_queue: Array[Dictionary] = []
var _actor_collection_open := false
var _actor_collection_started := false
var _actor_descriptor_validator := Callable()

# ── resources ──
var resource_manifest: Dictionary = {}
var _prefetched_resources: Dictionary = {}
var _consumed_paths: Dictionary = {}
## Accepted threaded requests whose original generation was retired.  These
## remain owned until a terminal ResourceLoader state is observed and its
## retrieval right is consumed; starting a new world never drops them.
var _retired_threaded_requests: Dictionary = {}
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

var planned_actors := 0
var spawned_actors := 0
var deferred_actors := 0
var duplicate_actors := 0
var failed_actors := 0
var actor_slice_count := 0
var actor_max_items_in_slice := 0
var actor_max_slice_ms := 0.0
var actor_max_item_ms := 0.0
var actor_total_ms := 0.0
var _planned_actor_ids: Dictionary = {}

var target_map_resource_count := 0
var shared_resource_count := 0
var cross_region_resource_count := 0
var unused_prefetched_resource_count := 0


func begin_initial_world(_map_id: int) -> void:
	_internal_begin(_map_id, "initial_world")


func begin_map_transition(_map_id: int) -> void:
	_internal_begin(_map_id, "map_transition")


func _internal_begin(_map_id: int, _mode: String) -> void:
	_retire_pending_threaded_requests()
	generation += 1
	_generation_valid = true
	map_id = _map_id
	mode = _mode
	stage = Stage.IDLE
	started_at_usec = Time.get_ticks_usec()
	_map_build_queue.clear()
	_collision_build_queue.clear()
	_actor_spawn_queue.clear()
	_actor_collection_open = false
	_actor_collection_started = false
	_actor_descriptor_validator = Callable()
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
	planned_actors = 0
	spawned_actors = 0
	deferred_actors = 0
	duplicate_actors = 0
	failed_actors = 0
	actor_slice_count = 0
	actor_max_items_in_slice = 0
	actor_max_slice_ms = 0.0
	actor_max_item_ms = 0.0
	actor_total_ms = 0.0
	_planned_actor_ids.clear()
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
		"deferred_actors": 0,
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
		"actor_slice_count": 0,
		"actor_max_items_in_slice": 0,
		"actor_max_slice_ms": 0.0,
		"actor_max_item_ms": 0.0,
		"actor_total_ms": 0.0,
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
	return _generation_valid and gen == generation


func mark_heavy_work_started(gen: int) -> bool:
	return is_generation_current(gen)


func revoke_current_generation() -> void:
	## Invalidates every suspended coroutine owned by the current transition.
	## The numeric generation is retained for diagnostics; the next begin still
	## advances it and re-arms the owner boundary.
	_generation_valid = false


func loading_barrier_completed() -> void:
	diagnostic["loading_barrier_completed"] = true


func finish(success: bool, reason: String) -> Dictionary:
	_finalize_resource_scope()
	_sync_diagnostics()
	if success:
		stage = Stage.READY
	else:
		stage = Stage.FAILED
		# A FAILED owner must not remain eligible for an async resume after the
		# caller clears its transition lock or starts recovery.
		revoke_current_generation()
		# P0-1/P0-3 audit trail: a FAILED bootstrap may be immediately
		# followed by a chained recovery transition (central failure owner),
		# which re-runs this coordinator and overwrites stage/diagnostic
		# within the same frame. Keep the last FAILED record persistent so
		# strict drivers and diagnostics can still attribute the failure.
		last_failure = {
			"generation": generation,
			"map_id": int(diagnostic.get("map_id", -1)),
			"reason": reason,
			"total_duration_ms": float(diagnostic.get("total_duration_ms", 0.0)),
		}
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
	diagnostic["planned_actors"] = planned_actors
	diagnostic["spawned_actors"] = spawned_actors
	diagnostic["deferred_actors"] = deferred_actors
	diagnostic["duplicate_actors"] = duplicate_actors
	diagnostic["failed_actors"] = failed_actors
	diagnostic["actor_slice_count"] = actor_slice_count
	diagnostic["actor_max_items_in_slice"] = actor_max_items_in_slice
	diagnostic["actor_max_slice_ms"] = actor_max_slice_ms
	diagnostic["actor_max_item_ms"] = actor_max_item_ms
	diagnostic["actor_total_ms"] = actor_total_ms
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


## WALL-P1R C3 narrow interface: best-effort threaded prefetch for derived
## resources. Optional entries ARE prefetched (threaded request like any
## other) but their failure never counts as a required-resource failure, so
## a missing wall atlas/chunk degrades that map to legacy rendering instead
## of blocking the map load. Required-resource semantics are untouched.
func register_optional_prefetch_resource(
	path: String,
	kind: String,
	owner_id: String,
	scope := "target",
	region := ""
) -> void:
	_register_resource(path, kind, false, owner_id, scope, region)
	if resource_manifest.has(path):
		resource_manifest[path]["optional_prefetch"] = true


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

func get_build_resource(path: String, stage_name: String) -> RefCounted:
	var res: RefCounted = get_prefetched_resource(path)
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
		"planned_actors": planned_actors,
		"spawned_actors": spawned_actors,
		"deferred_actors": deferred_actors,
		"duplicate_actors": duplicate_actors,
		"failed_actors": failed_actors,
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


func begin_actor_collection(validator: Callable) -> bool:
	if stage != Stage.SPAWN_ACTORS or _actor_collection_started or not validator.is_valid():
		return false
	_actor_collection_started = true
	_actor_descriptor_validator = validator
	_actor_collection_open = true
	return true


func close_actor_collection() -> void:
	_actor_collection_open = false


func actor_collection_is_open() -> bool:
	return _actor_collection_open and stage == Stage.SPAWN_ACTORS


func actor_descriptor_is_admissible(descriptor: Dictionary) -> bool:
	if not actor_collection_is_open():
		return false
	var actor_id: Variant = descriptor.get("actor_id")
	if not actor_id is String or actor_id.is_empty() or _planned_actor_ids.has(actor_id):
		return false
	return descriptor.get("actor_type", "") in ["enemy", "npc", "zone_portal", "map_portal"] \
		and descriptor.get("payload") is Dictionary


func submit_actor_descriptor(descriptor: Dictionary) -> bool:
	# Admission precedes every queue, identity and diagnostic counter mutation.
	if not actor_descriptor_is_admissible(descriptor):
		return false
	if not _actor_descriptor_validator.is_valid() or not bool(_actor_descriptor_validator.call(descriptor)):
		return false
	planned_actors += 1
	var actor_id := str(descriptor.get("actor_id", ""))
	_planned_actor_ids[actor_id] = true
	_actor_spawn_queue.append(descriptor.duplicate(true))
	return true


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


func process_actor_queue(handler: Callable, max_items: int, budget_ms: float) -> void:
	close_actor_collection()
	await _process_staged_queue(
		_actor_spawn_queue,
		handler,
		max_items,
		budget_ms,
		"actor"
	)


func process_actor_queue_blocking(
	handler: Callable,
	max_items: int,
	budget_ms: float
) -> void:
	close_actor_collection()
	var owner_generation := generation
	while is_generation_current(owner_generation) and not _actor_spawn_queue.is_empty():
		_process_staged_queue_slice(
			_actor_spawn_queue,
			handler,
			max_items,
			budget_ms,
			"actor"
		)


func _process_staged_queue(
	queue: Array,
	handler: Callable,
	max_items: int,
	budget_ms: float,
	kind: String
) -> void:
	var owner_generation := generation
	while is_generation_current(owner_generation) and not queue.is_empty():
		await _process_staged_queue_slice(queue, handler, max_items, budget_ms, kind)
		if not is_generation_current(owner_generation):
			return
		if not queue.is_empty() and defer_between_slices:
			await _runtime.next_service()


func _process_staged_queue_slice(
	queue: Array,
	handler: Callable,
	max_items: int,
	budget_ms: float,
	kind: String
) -> void:
	var owner_generation := generation
	var slice_start := Time.get_ticks_usec()
	var processed := 0
	while is_generation_current(owner_generation) and not queue.is_empty():
		var item: Variant = queue.pop_front()
		if item is Dictionary:
			var item_started_usec := Time.get_ticks_usec()
			var result: Variant
			if kind == "map": result = await handler.call(item as Dictionary)
			else: result = handler.call(item as Dictionary)
			# A real callback may replace this generation synchronously. Neither
			# its returned item nor its slice belongs to the replacement owner.
			if not is_generation_current(owner_generation):
				return
			var item_ms := (
				float(Time.get_ticks_usec() - item_started_usec) / 1000.0
			)
			if kind == "map":
				if not result is Dictionary or result.get("ok") != true:
					finish(false,"actual_map_leaf_failed")
					return
				built_map_item_count += 1
			elif kind == "collision":
				if result == null:
					failed_collision_count += 1
				else:
					built_collision_count += 1
			elif kind == "actor":
				actor_total_ms += item_ms
				actor_max_item_ms = maxf(actor_max_item_ms, item_ms)
				if result is Dictionary and bool(result.get("ok", false)):
					if bool(result.get("materialized", true)):
						spawned_actors += 1
					else:
						deferred_actors += 1
				else:
					failed_actors += 1
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
	elif kind == "actor":
		actor_slice_count += 1
		actor_max_items_in_slice = maxi(actor_max_items_in_slice, processed)
		actor_max_slice_ms = maxf(actor_max_slice_ms, slice_ms)


func record_sync_load() -> void:
	_synchronous_load_during_spawn += 1


# ── Threaded Resource Prefetch ──

func request_threaded_prefetch() -> int:
	var actual: Dictionary = await _map_transport.exchange_original_map_leaf("request_resources",[resource_manifest])
	if actual.get("ok") != true: return 0
	resource_manifest = actual.resource_manifest.duplicate(true)
	diagnostic.merge(actual.diagnostic,true)
	_apply_original_Main_resource_counters(actual)
	return int(actual.requested)

func poll_threaded_prefetch() -> bool:
	var actual: Dictionary = await _map_transport.exchange_original_map_leaf("poll_resources",[])
	if actual.get("ok") != true: return false
	resource_manifest = actual.resource_manifest.duplicate(true)
	diagnostic.merge(actual.diagnostic,true)
	_apply_original_Main_resource_counters(actual)
	return bool(actual.complete)

func poll_retired_threaded_prefetch() -> void:
	_map_physical_retirement_required = true # Actual Main owner/observer must drain or transfer.
	_map_actual_transfer_ack = false

func retire_threaded_resource_claims() -> bool:
	# Generic close is a nonblocking predicate, never an async coroutine/park.
	return _map_actual_transfer_ack and not _map_retirement_pending
func service_original_map_retirement_at_actual_P(frame: Dictionary) -> void:
	if _map_retirement_pending or _map_actual_transfer_ack: return
	if frame.get("phase") != "P_GROUP" and not (frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("closing_session") == true and frame.get("closing_process_publication",{}).get("phase") == "NODE_PROCESS_SERVICE"): return
	if _map_transport == null or not _map_transport.scope_is_current(): return
	_map_retirement_pending = true
	var actual: Dictionary = await _map_transport.exchange_original_map_leaf("retire_claims",[])
	if actual.get("ok") != true or not actual.get("actual_io") is Dictionary: return
	_map_last_actual_io = actual.actual_io
	_map_physical_retirement_required = false
	# This is actual transfer admission, not proof that persistent physical claims
	# or resident/GPU leases disappeared. The Main producer remains responsible.
	_map_actual_transfer_ack = bool(actual.get("transferred",false))
	_map_retirement_pending = false

func _retire_pending_threaded_requests() -> void:
	_map_physical_retirement_required = true # Actual Main owner/observer must drain or transfer.
	_map_actual_transfer_ack = false

func _poll_retired_threaded_requests() -> void:
	_map_physical_retirement_required = true # Actual Main owner/observer must drain or transfer.
	_map_actual_transfer_ack = false

func _transfer_retired_threaded_claims() -> void:
	_map_physical_retirement_required = true # Actual Main owner/observer must drain or transfer.
	_map_actual_transfer_ack = false

func _consume_threaded_claims(path: String, claim_count: int) -> RefCounted:
	var result: RefCounted = null
	for _claim in range(maxi(0, claim_count)):
		var candidate: RefCounted = _resources.load_threaded_get(path)
		if candidate != null:
			result = candidate
	return result


func poll_threaded_prefetch_blocking(timeout_ms := 3000) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while not await poll_threaded_prefetch():
		if Time.get_ticks_msec() >= deadline: return false
		await _runtime.next_service()
	return true

func get_prefetched_resource(path: String) -> RefCounted:
	var _res: Variant = _prefetched_resources.get(path)
	if _resources.is_original_resource_reference(_res):
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

var _map_transport: RefCounted
var _map_physical_retirement_required := false
var _map_last_actual_io: Dictionary = {}
var _map_actual_transfer_ack := false
var _map_retirement_pending := false
var _actual_map_scope_release_receipt: Dictionary = {}
var _actual_map_owner_terminal_receipt: Dictionary = {}
func acknowledge_actual_original_map_owner_terminal(core: RefCounted, frame: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or core == null or core.owner_thread_id() != _owner or core.original_root_owner().get("_world_bootstrap_coordinator") != self or frame != core.current_clock_frame() or frame.get("closing_session") != true or frame.get("phase") != "P_CLOSE_SERVICE" or frame.get("source_boundary") != "NODE_PROCESS_SERVICE": return false
	if _map_retirement_pending or (_map_transport != null and not _map_transport.get("_job").is_empty()): return false
	var publication: Dictionary = frame.get("closing_process_publication",{})
	var io: Dictionary = publication.get("main_io",{})
	var observed: Dictionary = io.get("map_terminal",{})
	if publication.get("phase") != "NODE_PROCESS_SERVICE" or io.get("contract_id") != "hardcore.source.main_io_observation.v1" or io.get("map_owner_closed") != true or io.get("owner_session_id") != core.original_source_session().original_budget_session_id() or io.get("world_runtime_id") != core.current_world_identity().world_runtime_id or io.get("actual_main_process_frame") != frame.get("actual_main_process_frame") or observed.get("success") != true or observed.get("status") != "READY" or observed.get("contract_id") != "hardcore.main.map_terminal.observation.v1" or observed.get("actual_native_map_owner_closed") != true: return false
	var receipt: Dictionary = observed.get("actual_map_owner_terminal",{})
	var descriptor: Dictionary = receipt.get("owner_descriptor",{})
	if receipt.get("contract_id") != "hardcore.main.map_owner.terminal.v1" or receipt.get("producer_runtime_id") != observed.get("actual_producer_id") or observed.get("actual_origin_id") != io.get("actual_io_producer_id") or descriptor.get("world_context") != core.current_world_identity() or descriptor.get("source_root_id") != core.original_root_owner().get_instance_id() or descriptor.get("owner_session_id") != core.original_source_session().original_budget_session_id() or receipt.get("actual_remaining_pin_count") != 0 or receipt.get("actual_io",{}).get("terminal") != true or receipt.get("actual_io",{}).get("actual_transfer",{}).get("observer_released") != true: return false
	_actual_map_owner_terminal_receipt = receipt.duplicate(true)
	_map_last_actual_io = receipt.actual_io.duplicate(true)
	_map_physical_retirement_required = false; _map_actual_transfer_ack = true
	return true
func acknowledge_actual_original_map_scope_release(scope: Dictionary, receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _map_transport == null or _map_retirement_pending or not _map_transport.get("_job").is_empty() or _map_transport.get("_scope") != scope or scope.get("coordinator_generation") != generation: return false
	if receipt.get("contract_id") != "hardcore.main.map_scope.release.v1" or receipt.get("success") != true or receipt.get("status") != "READY" or receipt.get("released_scope") != scope or not receipt.get("scope") is Dictionary or not receipt.get("actual_io") is Dictionary: return false
	var retained: Dictionary = receipt.scope
	var expected: Dictionary = scope.duplicate(true); expected.state = "RETAINED"
	if retained != expected: return false
	var descriptor: Dictionary = scope.owner_descriptor
	if descriptor != _map_transport.get("_descriptor"): return false
	var host: Object = _map_transport.get("_host")
	if host == null or not host.verify_original_map_loading_scope(retained,descriptor,str(scope.transition_id),generation,int(scope.map_id)): return false
	var io: Dictionary = receipt.actual_io
	var transfer: Dictionary = io.get("actual_transfer",{})
	if io.get("generation") != generation or io.get("owner_descriptor") != receipt.get("current_owner_descriptor") or transfer.get("status") != "READY" or transfer.get("contract_id") != "hardcore.main.map_io.observation.v1" or transfer.get("actual_producer_id") != scope.producer_runtime_id or transfer.get("actual_claims_terminal") != true or transfer.get("actual_transfer_performed") != false or not transfer.get("actual_pending_claim_counts") is Dictionary or not transfer.actual_pending_claim_counts.is_empty(): return false
	if not io.get("actual_retiring_claims") is Dictionary or not io.actual_retiring_claims.is_empty() or not io.get("retired_threaded_requests") is Dictionary or not io.retired_threaded_requests.is_empty(): return false
	_actual_map_scope_release_receipt = receipt.duplicate(true)
	_map_last_actual_io = io.duplicate(true)
	_map_physical_retirement_required = false; _map_actual_transfer_ack = true
	return true
func _apply_original_Main_resource_counters(actual: Dictionary) -> void:
	unexpected_sync_load_count = int(actual.unexpected_sync_load_count)
	unexpected_sync_load_count_build_map = int(actual.unexpected_sync_load_count_build_map)
	unexpected_sync_load_count_build_collision = int(actual.unexpected_sync_load_count_build_collision)
	unexpected_sync_load_count_spawn_actors = int(actual.unexpected_sync_load_count_spawn_actors)
func bind_original_map_transport(transport: RefCounted) -> bool:
	if _map_transport != null or transport.owner_thread_id() != _owner: return false
	_map_transport = transport
	return true
