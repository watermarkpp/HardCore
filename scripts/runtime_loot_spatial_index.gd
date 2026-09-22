class_name RuntimeLootSpatialIndex
extends RefCounted

## R3X-5: map-scoped broadphase for ground loot collection.  Loot is kept in
## its own index so combat queries never see pickup nodes.  Registration owns
## one bucket per pickup and all query output is caller-owned/reused.

const BUCKET_SIZE_SETTING := "hardcore/loot/spatial_index_bucket_size_gu"
const DEFAULT_BUCKET_SIZE_GU := 4.0
const CONTRACT_ID := "hardcore.loot.spatial_index.map_ground_gu_buckets.v1"

var _buckets: Dictionary = {}
var _entries: Dictionary = {}
var _bucket_size_gu := DEFAULT_BUCKET_SIZE_GU
var _stale_ids: Array[int] = []
var _candidate_records: Array[Dictionary] = []

var index_register_count := 0
var index_unregister_count := 0
var index_update_check_count := 0
var index_bucket_change_count := 0
var index_stale_cleanup_count := 0
var index_query_count := 0
var index_candidate_count := 0
var index_max_candidate_count := 0
var index_full_scan_count := 0


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
	loot_runtime_id: int,
	runtime_map_id: int,
	absolute_ground_gu: Vector2,
	stable_registration_order: int,
	loot: Node,
) -> bool:
	if (
		loot_runtime_id <= 0
		or not absolute_ground_gu.is_finite()
		or not is_instance_valid(loot)
	):
		return false
	unregister(loot_runtime_id)
	var bucket_key := _bucket_key(absolute_ground_gu)
	_entries[loot_runtime_id] = {
		"loot_runtime_id": loot_runtime_id,
		"runtime_map_id": runtime_map_id,
		"bucket_key": bucket_key,
		"absolute_ground_gu": absolute_ground_gu,
		"stable_registration_order": stable_registration_order,
		"node_instance_id": loot.get_instance_id(),
		"node_ref": weakref(loot),
	}
	_bucket_set(runtime_map_id, bucket_key)[loot_runtime_id] = weakref(loot)
	index_register_count += 1
	return true


func unregister(loot_runtime_id: int) -> void:
	var raw_entry: Variant = _entries.get(loot_runtime_id, null)
	if not raw_entry is Dictionary:
		return
	var entry: Dictionary = raw_entry
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var bucket_key: Vector2i = entry.get("bucket_key", Vector2i.ZERO)
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	var bucket: Dictionary = map_buckets.get(bucket_key, {})
	bucket.erase(loot_runtime_id)
	if bucket.is_empty():
		map_buckets.erase(bucket_key)
	if map_buckets.is_empty():
		_buckets.erase(runtime_map_id)
	_entries.erase(loot_runtime_id)
	index_unregister_count += 1


func update_pickup(loot_runtime_id: int, absolute_ground_gu: Vector2) -> bool:
	var raw_entry: Variant = _entries.get(loot_runtime_id, null)
	if not raw_entry is Dictionary or not absolute_ground_gu.is_finite():
		return false
	var entry: Dictionary = raw_entry
	index_update_check_count += 1
	var old_bucket: Vector2i = entry.get("bucket_key", Vector2i.ZERO)
	var new_bucket := _bucket_key(absolute_ground_gu)
	entry["absolute_ground_gu"] = absolute_ground_gu
	if old_bucket == new_bucket:
		return true
	var runtime_map_id := int(entry.get("runtime_map_id", -1))
	var node_ref: WeakRef = entry.get("node_ref", null)
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	var old_bucket_values: Dictionary = map_buckets.get(old_bucket, {})
	old_bucket_values.erase(loot_runtime_id)
	if old_bucket_values.is_empty():
		map_buckets.erase(old_bucket)
	entry["bucket_key"] = new_bucket
	_bucket_set(runtime_map_id, new_bucket)[loot_runtime_id] = node_ref
	index_bucket_change_count += 1
	return true


func clear_map(runtime_map_id: int) -> void:
	_buckets.erase(runtime_map_id)
	var removed: Array[int] = []
	for raw_id: Variant in _entries.keys():
		var entry: Variant = _entries.get(raw_id, null)
		if entry is Dictionary and int((entry as Dictionary).get("runtime_map_id", -1)) == runtime_map_id:
			removed.append(int(raw_id))
	for loot_runtime_id: int in removed:
		_entries.erase(loot_runtime_id)
	index_unregister_count += removed.size()


func clear_all() -> void:
	var removed := _entries.size()
	_buckets.clear()
	_entries.clear()
	index_unregister_count += removed


func registered_pickup_count() -> int:
	return _entries.size()


func ground_position_for(loot_runtime_id: int) -> Vector2:
	var entry: Variant = _entries.get(loot_runtime_id, null)
	if entry is Dictionary:
		return (entry as Dictionary).get("absolute_ground_gu", Vector2.INF)
	return Vector2.INF


## Query candidates conservatively by bucket, then let the manager perform the
## exact strict radius test.  Each entry owns one bucket, so no per-query
## seen/hash allocation is needed.  `output` is caller-owned and cleared.
func query_nearby_into(
	runtime_map_id: int,
	center_ground_gu: Vector2,
	radius_gu: float,
	output: Array,
) -> void:
	output.clear()
	_stale_ids.clear()
	_candidate_records.clear()
	index_query_count += 1
	if (
		not center_ground_gu.is_finite()
		or not is_finite(radius_gu)
		or radius_gu < 0.0
	):
		return
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	if map_buckets.is_empty():
		return
	var radius := maxf(0.0, radius_gu)
	var min_bucket := _bucket_key(center_ground_gu - Vector2.ONE * radius)
	var max_bucket := _bucket_key(center_ground_gu + Vector2.ONE * radius)
	for bucket_y: int in range(min_bucket.y, max_bucket.y + 1):
		for bucket_x: int in range(min_bucket.x, max_bucket.x + 1):
			var bucket: Dictionary = map_buckets.get(Vector2i(bucket_x, bucket_y), {})
			for raw_id: Variant in bucket:
				var loot_runtime_id := int(raw_id)
				var raw_entry: Variant = _entries.get(loot_runtime_id, null)
				if not raw_entry is Dictionary:
					continue
				var entry: Dictionary = raw_entry
				var weak: WeakRef = bucket.get(loot_runtime_id)
				var node: Variant = weak.get_ref() if weak != null else null
				if node == null or not is_instance_valid(node):
					_stale_ids.append(loot_runtime_id)
					continue
				if node is LootPickup:
					var pickup := node as LootPickup
					_candidate_records.append({
						"pickup": pickup,
						"stable_registration_order": int(
							entry.get("stable_registration_order", 0)
						),
						# The entry key is a loot runtime ID. Keep the node's actual
						# instance ID as the tie-break key instead of assuming those
						# identifiers are interchangeable.
						"node_instance_id": pickup.get_instance_id(),
					})
	for loot_runtime_id: int in _stale_ids:
		unregister(loot_runtime_id)
		index_stale_cleanup_count += 1
	_stale_ids.clear()
	_candidate_records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var order_a := int(a.get("stable_registration_order", 0))
			var order_b := int(b.get("stable_registration_order", 0))
			if order_a != order_b:
				return order_a < order_b
			return int(a.get("node_instance_id", 0)) < int(
				b.get("node_instance_id", 0)
			)
	)
	for record: Dictionary in _candidate_records:
		var pickup: Variant = record.get("pickup", null)
		if pickup is LootPickup and is_instance_valid(pickup):
			output.append(pickup)
	_candidate_records.clear()
	index_candidate_count += output.size()
	index_max_candidate_count = maxi(index_max_candidate_count, output.size())


func diagnostics_snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"bucket_size_gu": _bucket_size_gu,
		"registered_pickup_count": _entries.size(),
		"index_register_count": index_register_count,
		"index_unregister_count": index_unregister_count,
		"index_update_check_count": index_update_check_count,
		"index_bucket_change_count": index_bucket_change_count,
		"index_stale_cleanup_count": index_stale_cleanup_count,
		"index_query_count": index_query_count,
		"index_candidate_count": index_candidate_count,
		"index_max_candidate_count": index_max_candidate_count,
		"index_full_scan_count": index_full_scan_count,
	}


func _bucket_set(runtime_map_id: int, bucket_key: Vector2i) -> Dictionary:
	var map_buckets: Dictionary = _buckets.get(runtime_map_id, {})
	if map_buckets.is_empty():
		_buckets[runtime_map_id] = map_buckets
	var bucket: Dictionary = map_buckets.get(bucket_key, {})
	if bucket.is_empty():
		map_buckets[bucket_key] = bucket
	return bucket


func _bucket_key(ground_gu: Vector2) -> Vector2i:
	return Vector2i(
		floori(ground_gu.x / _bucket_size_gu),
		floori(ground_gu.y / _bucket_size_gu),
	)
