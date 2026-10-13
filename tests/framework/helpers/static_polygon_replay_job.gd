extends RefCounted
## A job owns its numeric indexes, queries and outputs. Main thread prepares
## and consumes only outside run()/join; run never accesses a Node or physics.
const Index := preload("res://scripts/map_editor/polygon/poly_index.gd")
var indexes: Array[RefCounted] = []
var queries: Array = []
var results := PackedByteArray()
var thread_id := -1
var started_usec := 0
var ended_usec := 0
var snapshot_prepare_usec := 0
var private_snapshot_bytes := 0
var transfer_pack_usec := 0
var transfer_unpack_usec := 0
var query_bytes := 0
var shared_queries: Array = []
var shared_first := 0
var shared_count := 0
var shared_buffer_prepare_usec := 0

func prepare_shared_input(source: Array, output_capacity: int) -> void:
	# Called once per persistent job on main, before any task is submitted.
	# Array/dictionaries are sealed; packed point arrays have no mutable owner.
	assert(source.is_read_only() and output_capacity > 0)
	var before := Time.get_ticks_usec()
	shared_queries = source
	results = PackedByteArray()
	results.resize(output_capacity)
	shared_buffer_prepare_usec = Time.get_ticks_usec() - before

func prepare_shared_range(first: int, count: int) -> bool:
	# The coordinator calls this only after draining this job's previous task.
	if first < 0 or count < 0 or first + count > shared_queries.size() or count > results.size():
		return false
	shared_first = first
	shared_count = count
	thread_id = -1
	started_usec = 0
	ended_usec = 0
	return true

func run_shared() -> void:
	thread_id = OS.get_thread_caller_id()
	started_usec = Time.get_ticks_usec()
	for offset in range(shared_count):
		var query: Dictionary = shared_queries[shared_first + offset]
		results[offset] = 1 if indexes[int(query.snapshot_id)].footprint_blocked(query.points) else 0
	ended_usec = Time.get_ticks_usec()

func shared_evidence() -> Dictionary:
	return {"thread_id": thread_id, "started_usec": started_usec, "ended_usec": ended_usec,
		"worker_service_wall_usec": ended_usec - started_usec, "query_count": shared_count,
		"first_serial": shared_first, "last_serial": shared_first + shared_count - 1,
		"private_snapshot_bytes": private_snapshot_bytes, "private_query_bytes": 0,
		"shared_immutable_query_reference": true, "private_results_bytes": results.size(),
		"valid_results_count": shared_count, "per_thread_cpu_usec": "MISSING"}

func prepare_snapshots(snapshots: Array) -> void:
	var before := Time.get_ticks_usec()
	for snapshot: Dictionary in snapshots:
		# Binary copy makes every array/dictionary independently owned. setup()
		# is intentionally absent: no validation/recompile/Geometry2D on a worker.
		var packed := var_to_bytes(snapshot)
		var numeric: Dictionary = bytes_to_var(packed)
		private_snapshot_bytes += packed.size()
		var index := Index.new()
		index.design_size = numeric.design_size
		index.ready = numeric.ready
		index.parts.assign(numeric.parts)
		index.boxes.assign(numeric.boxes)
		index._padded_boxes.assign(numeric.padded_boxes)
		index._first_buckets.assign(numeric.first_buckets)
		index.buckets = numeric.buckets
		indexes.append(index)
	snapshot_prepare_usec = Time.get_ticks_usec() - before

func prepare_queries(source: Array) -> void:
	var before := Time.get_ticks_usec()
	var packed := var_to_bytes(source)
	transfer_pack_usec = Time.get_ticks_usec() - before
	query_bytes = packed.size()
	before = Time.get_ticks_usec()
	queries = bytes_to_var(packed)
	results = PackedByteArray()
	results.resize(queries.size())
	transfer_unpack_usec = Time.get_ticks_usec() - before
	thread_id = -1
	started_usec = 0
	ended_usec = 0

func run() -> void:
	thread_id = OS.get_thread_caller_id()
	started_usec = Time.get_ticks_usec()
	for offset in range(queries.size()):
		var query: Dictionary = queries[offset]
		results[offset] = 1 if indexes[int(query.snapshot_id)].footprint_blocked(query.points) else 0
	ended_usec = Time.get_ticks_usec()

func evidence() -> Dictionary:
	return {"thread_id": thread_id, "started_usec": started_usec, "ended_usec": ended_usec,
		"worker_service_wall_usec": ended_usec - started_usec, "query_count": queries.size(),
		"first_serial": int(queries[0].serial) if not queries.is_empty() else -1,
		"last_serial": int(queries[-1].serial) if not queries.is_empty() else -1,
		"private_snapshot_bytes": private_snapshot_bytes, "private_query_bytes": query_bytes,
		"private_results_bytes": results.size(), "per_thread_cpu_usec": "MISSING"}
