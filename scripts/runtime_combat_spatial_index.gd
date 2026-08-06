class_name RuntimeCombatSpatialIndex
extends RefCounted

## Q2-A: map-scoped broadphase for projectile swept-segment queries.
## Coordinate contract: typed int runtime_map_id + absolute ground GU buckets.
## Owned by GameRoot; injected into enemy spawn and projectile spawn.
##
## Live-position provider limitation (Q2-A.1):
## - It is used to read a candidate's current true position before the narrow
##   phase (removing stale false positives that already left the query range).
## - It CANNOT discover an actor that has not been registered into the
##   target bucket, cannot replace explicit index updates, and cannot repair a
##   new-bucket false negative by itself. Forced position writes must call
##   set_combat_position() so the index updates in the same transaction;
##   synchronized index updates prevent false negatives, while live-position
##   reads prevent stale candidates from producing wrong narrow-phase results.

const BUCKET_SIZE_SETTING := "hardcore/combat/spatial_index_bucket_size_gu"
const DEFAULT_BUCKET_SIZE_GU := 4.0
const CONTRACT_ID := "hardcore.combat.spatial_index.map_ground_gu_buckets.v1"


var _buckets: Dictionary = {}
var _entries: Dictionary = {}
var _max_actor_bounds_gu := 0.0
var _bucket_size_gu := DEFAULT_BUCKET_SIZE_GU

var index_register_count := 0
var index_unregister_count := 0
var index_update_check_count := 0
var index_bucket_change_count := 0
var index_stale_cleanup_count := 0
var index_query_count := 0
var index_total_candidate_count := 0
var index_max_candidate_count := 0


func _init() -> void:
	_bucket_size_gu = maxf(
		0.5,
		float(ProjectSettings.get_setting(
			BUCKET_SIZE_SETTING,
			DEFAULT_BUCKET_SIZE_GU
		))
	)


func bucket_size_gu() -> float:
	return _bucket_size_gu


func register(
	actor_runtime_id: int,
	runtime_map_id: int,
	absolute_ground_gu: Vector2,
	bounds_radius_gu: float,
	stable_combat_order: int,
	node: Node,
	position_provider: Callable = Callable()
) -> void:
	if actor_runtime_id <= 0 or runtime_map_id < 0:
		return
	unregister(actor_runtime_id)
	var safe_bounds := maxf(0.0, bounds_radius_gu)
	_entries[actor_runtime_id] = {
		"runtime_map_id": runtime_map_id,
		"bucket_key": _bucket_key(absolute_ground_gu),
		"absolute_ground_gu": absolute_ground_gu,
		"bounds_gu": safe_bounds,
		"stable_combat_order": stable_combat_order,
		"position_provider": (
			position_provider if position_provider is Callable else Callable()
		),
	}
	_max_actor_bounds_gu = maxf(_max_actor_bounds_gu, safe_bounds)
	_bucket_set(runtime_map_id, _entries[actor_runtime_id]["bucket_key"])[
		actor_runtime_id
	] = weakref(node)
	index_register_count += 1


func unregister(actor_runtime_id: int) -> void:
	var entry: Dictionary = _entries.get(actor_runtime_id, {})
	if entry.is_empty():
		return
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var bucket_key: Vector2i = entry.get("bucket_key", Vector2i.ZERO)
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	var bucket: Dictionary = map_buckets.get(bucket_key, {})
	bucket.erase(actor_runtime_id)
	if bucket.is_empty():
		map_buckets.erase(bucket_key)
	if map_buckets.is_empty():
		_buckets.erase(runtime_map_id)
	_entries.erase(actor_runtime_id)
	index_unregister_count += 1


func update_actor(actor_runtime_id: int, absolute_ground_gu: Vector2) -> void:
	var entry: Dictionary = _entries.get(actor_runtime_id, {})
	if entry.is_empty():
		return
	index_update_check_count += 1
	var new_bucket := _bucket_key(absolute_ground_gu)
	var old_bucket: Vector2i = entry.get("bucket_key", Vector2i.ZERO)
	entry["absolute_ground_gu"] = absolute_ground_gu
	if new_bucket == old_bucket:
		return
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var node_ref: WeakRef = _take_bucket_ref(
		runtime_map_id,
		old_bucket,
		actor_runtime_id
	)
	entry["bucket_key"] = new_bucket
	_bucket_set(runtime_map_id, new_bucket)[actor_runtime_id] = node_ref
	index_bucket_change_count += 1


func clear_map(runtime_map_id: int) -> void:
	_buckets.erase(runtime_map_id)
	var removed := 0
	for raw_id: Variant in _entries.keys():
		var entry: Dictionary = _entries.get(raw_id, {})
		if int(entry.get("runtime_map_id", -1)) == runtime_map_id:
			_entries.erase(raw_id)
			removed += 1
	index_unregister_count += removed


func registered_actor_count() -> int:
	return _entries.size()


func query_segment_candidates(
	runtime_map_id: int,
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float
) -> Array[Dictionary]:
	var expansion := maxf(0.0, expansion_gu) + _max_actor_bounds_gu
	var min_gu := Vector2(
		minf(start_ground_gu.x, end_ground_gu.x),
		minf(start_ground_gu.y, end_ground_gu.y)
	) - Vector2.ONE * expansion
	var max_gu := Vector2(
		maxf(start_ground_gu.x, end_ground_gu.x),
		maxf(start_ground_gu.y, end_ground_gu.y)
	) + Vector2.ONE * expansion
	return _query_aabb_candidates(
		runtime_map_id,
		Rect2(min_gu, max_gu - min_gu)
	)


func query_aabb_candidates(
	runtime_map_id: int,
	bounds_ground_gu: Rect2,
	expansion_gu := 0.0
) -> Array[Dictionary]:
	var expansion := maxf(0.0, expansion_gu) + _max_actor_bounds_gu
	return _query_aabb_candidates(
		runtime_map_id,
		Rect2(
			bounds_ground_gu.position - Vector2.ONE * expansion,
			bounds_ground_gu.size + Vector2.ONE * expansion * 2.0
		)
	)


func _query_aabb_candidates(
	runtime_map_id: int,
	bounds_ground_gu: Rect2
) -> Array[Dictionary]:
	index_query_count += 1
	var result: Array[Dictionary] = []
	if runtime_map_id < 0 or bounds_ground_gu.size.x < 0.0:
		return result
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	if map_buckets.is_empty():
		return result
	var min_bucket := _bucket_key(bounds_ground_gu.position)
	var max_bucket := _bucket_key(bounds_ground_gu.end)
	var seen: Dictionary = {}
	for bucket_y: int in range(min_bucket.y, max_bucket.y + 1):
		for bucket_x: int in range(min_bucket.x, max_bucket.x + 1):
			var query_bucket := Vector2i(bucket_x, bucket_y)
			var bucket: Dictionary = map_buckets.get(query_bucket, {})
			for raw_id: Variant in bucket.keys():
				var actor_id := int(raw_id)
				if seen.has(actor_id):
					continue
				var entry: Dictionary = _entries.get(actor_id, {})
				if entry.is_empty():
					continue
				var node_ref: WeakRef = bucket.get(actor_id)
				var node: Node = (
					node_ref.get_ref()
					if node_ref != null
					else null
				)
				if node == null or not is_instance_valid(node):
					_erase_entry(actor_id)
					index_stale_cleanup_count += 1
					continue
				var position_provider: Callable = entry.get(
					"position_provider",
					Callable()
				)
				var live_position_gu := (
					entry.get("absolute_ground_gu", Vector2.ZERO) as Vector2
				)
				if position_provider.is_valid():
					var live_value: Variant = position_provider.call()
					if live_value is Vector2:
						live_position_gu = live_value as Vector2
				var current_bucket := _bucket_key(live_position_gu)
				if current_bucket != query_bucket:
					# Lazy re-home: entry's stored bucket is stale. Move it and
					# only keep it when its current bucket is inside the query.
					_move_entry_to(actor_id, current_bucket)
					if not _bucket_in_range(
						current_bucket,
						min_bucket,
						max_bucket
					):
						continue
				seen[actor_id] = true
				result.append({
					"actor_runtime_id": actor_id,
					"stable_combat_order": int(
						entry.get("stable_combat_order", actor_id)
					),
					"node": node,
					"bounds_gu": float(entry.get("bounds_gu", 0.0)),
				})
	result.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("stable_combat_order", 0)) < int(
				b.get("stable_combat_order", 0)
			)
	)
	index_total_candidate_count += result.size()
	index_max_candidate_count = maxi(
		index_max_candidate_count,
		result.size()
	)
	return result


func diagnostics() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"bucket_size_gu": _bucket_size_gu,
		"registered_actor_count": _entries.size(),
		"map_count": _buckets.size(),
		"max_actor_bounds_gu": _max_actor_bounds_gu,
		"index_register_count": index_register_count,
		"index_unregister_count": index_unregister_count,
		"index_update_check_count": index_update_check_count,
		"index_bucket_change_count": index_bucket_change_count,
		"index_stale_cleanup_count": index_stale_cleanup_count,
		"index_query_count": index_query_count,
		"index_total_candidate_count": index_total_candidate_count,
		"index_max_candidate_count": index_max_candidate_count,
	}


func _bucket_key(absolute_ground_gu: Vector2) -> Vector2i:
	return Vector2i(
		floori(absolute_ground_gu.x / _bucket_size_gu),
		floori(absolute_ground_gu.y / _bucket_size_gu)
	)


func _bucket_in_range(
	bucket_key: Vector2i,
	min_bucket: Vector2i,
	max_bucket: Vector2i
) -> bool:
	return (
		bucket_key.x >= min_bucket.x
		and bucket_key.x <= max_bucket.x
		and bucket_key.y >= min_bucket.y
		and bucket_key.y <= max_bucket.y
	)


func _bucket_set(runtime_map_id: int, bucket_key: Vector2i) -> Dictionary:
	if not _buckets.has(runtime_map_id):
		_buckets[runtime_map_id] = {}
	var map_buckets: Dictionary = _buckets[runtime_map_id]
	if not map_buckets.has(bucket_key):
		map_buckets[bucket_key] = {}
	return map_buckets[bucket_key]


func _take_bucket_ref(
	runtime_map_id: int,
	bucket_key: Vector2i,
	actor_runtime_id: int
) -> WeakRef:
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	var bucket: Dictionary = map_buckets.get(bucket_key, {})
	var node_ref: WeakRef = bucket.get(actor_runtime_id)
	bucket.erase(actor_runtime_id)
	if bucket.is_empty():
		map_buckets.erase(bucket_key)
	if map_buckets.is_empty():
		_buckets.erase(runtime_map_id)
	return node_ref


func _move_entry_to(actor_runtime_id: int, new_bucket: Vector2i) -> void:
	var entry: Dictionary = _entries.get(actor_runtime_id, {})
	if entry.is_empty():
		return
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var node_ref: WeakRef = _take_bucket_ref(
		runtime_map_id,
		entry.get("bucket_key", Vector2i.ZERO),
		actor_runtime_id
	)
	entry["bucket_key"] = new_bucket
	_bucket_set(runtime_map_id, new_bucket)[actor_runtime_id] = node_ref
	index_bucket_change_count += 1


func _erase_entry(actor_runtime_id: int) -> void:
	var entry: Dictionary = _entries.get(actor_runtime_id, {})
	if entry.is_empty():
		return
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var bucket_key: Vector2i = entry.get("bucket_key", Vector2i.ZERO)
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	var bucket: Dictionary = map_buckets.get(bucket_key, {})
	bucket.erase(actor_runtime_id)
	if bucket.is_empty():
		map_buckets.erase(bucket_key)
	if map_buckets.is_empty():
		_buckets.erase(runtime_map_id)
	_entries.erase(actor_runtime_id)
	index_unregister_count += 1
