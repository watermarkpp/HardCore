extends Node
## Offline numeric replay only. No active game world and no production offload.
const Recorder := preload("res://tests/framework/helpers/static_polygon_query_recorder.gd")
const Job := preload("res://tests/framework/helpers/static_polygon_replay_job.gd")
const Proof := preload("res://tests/framework/helpers/check_receipt.gd")
const SCENE_ID := "static_polygon_replay_v113_20261013"
const MODES := ["SERIAL", "WORKER_1", "WORKER_2", "TICK_SERIAL", "TICK_WORKER_1", "TICK_WORKER_2", "SHARE_WORKER_2", "SHARE_TICK_WORKER_1", "SHARE_TICK_WORKER_2"]
var _proof := Proof.new()
var _failures: Array[String] = []
var _corpus: Dictionary = {}
var _tick_batches: Array[Array] = []
var _serial_reference := PackedByteArray()
var _serial_reference_ready := false
var _corpus_path := ""
var _corpus_sha256 := ""
var _input_bytes := 0
var _input_read_usec := 0
var _input_unpack_validate_usec := 0
var _warmups: Array[Dictionary] = []
var _rounds: Array[Dictionary] = []
var _tick_ranges: Array[Vector2i] = []
var _shared_input_prepare_usec := 0
var _shared_input_evidence_usec := 0
var _shared_query_bytes := 0
var _shared_query_hash := ""

func _ready() -> void:
	call_deferred("_run")

func _check(ok: bool, label: String) -> void:
	_proof.record(ok, label)
	if not ok:
		_failures.append(label)
		print("HC_TEST_FAIL ", label)

func _run() -> void:
	_corpus_path = OS.get_environment("HARDCORE_COMPUTE_STATIC_CORPUS_PATH")
	_check(not _corpus_path.is_empty() and FileAccess.file_exists(_corpus_path), "exact_corpus_file_present")
	if not _failures.is_empty():
		_finish()
		return
	var before := Time.get_ticks_usec()
	var packed := FileAccess.get_file_as_bytes(_corpus_path)
	_input_read_usec = Time.get_ticks_usec() - before
	_input_bytes = packed.size()
	_corpus_sha256 = Recorder.bytes_sha256(packed)
	before = Time.get_ticks_usec()
	var decoded: Variant = bytes_to_var(packed)
	_check(decoded is Dictionary and Recorder.numeric_only(decoded), "binary_corpus_only_numeric_values")
	if not _failures.is_empty():
		_finish()
		return
	_corpus = decoded
	_validate_corpus()
	_input_unpack_validate_usec = Time.get_ticks_usec() - before
	if not _failures.is_empty():
		_finish()
		return
	_prepare_shared_input()
	_serial_reference.resize(_corpus.queries.size())
	for mode: String in MODES:
		_warmups.append(_mode(mode, -1))
	for round_index in range(3):
		var order: Array = MODES.duplicate()
		if round_index % 2 == 1: order.reverse()
		for mode: String in order:
			_rounds.append(_mode(mode, round_index))
	_check(Recorder.bytes_sha256(var_to_bytes(_corpus.queries)) == _shared_query_hash, "shared_input_bytes_unchanged_after_all_jobs_joined")
	_finish()

func _validate_corpus() -> void:
	_check(str(_corpus.get("schema", "")) == Recorder.SCHEMA, "corpus_schema")
	_check(_corpus.get("source") is Dictionary and _corpus.get("capture") is Dictionary and _corpus.get("snapshots") is Array and _corpus.get("queries") is Array, "corpus_sections")
	if not _failures.is_empty(): return
	var source: Dictionary = _corpus.source
	_check(int(source.get("map_id", -1)) == 913203 and str(source.get("release_build_sha256", "")) == Recorder.RELEASE_SHA, "published_map_release_binding")
	_check(int(source.get("ticks", -1)) == 300 and int(source.get("active_count", -1)) in [30, 40], "real_300_tick_30_or_40_capture")
	_check(int(source.get("total_count", -1)) == int(source.get("active_count", 0)) + 4 and str(source.get("density", "")) == "clustered", "real_capture_density_and_background")
	_check(not str(source.get("engine_hash", "")).is_empty() and str(source.get("engine_hash", "")) == str(Engine.get_version_info().get("hash", "")), "capture_replay_engine_hash_equal")
	_check(str(source.get("HEAD", "")) == OS.get_environment("HARDCORE_R3_TESTED_SHA") and not str(source.get("source_content_sha256", "")).is_empty(), "capture_source_binding_present")
	_check(not str(source.get("run_id", "")).is_empty() and not str(source.get("invocation_id", "")).is_empty(), "capture_run_and_invocation_present")
	_check(source.get("fixture_failures", ["MISSING"]).is_empty() and _corpus.capture.get("failures", ["MISSING"]).is_empty() and not bool(_corpus.capture.get("truncated", true)), "capture_original_assertions_and_completeness")
	_check(not _corpus.snapshots.is_empty() and not _corpus.queries.is_empty() and int(_corpus.capture.get("query_count", -1)) == _corpus.queries.size(), "complete_nonempty_query_set")
	if not _failures.is_empty(): return
	for snapshot_id in range(_corpus.snapshots.size()):
		var snapshot: Dictionary = _corpus.snapshots[snapshot_id]
		var numeric := snapshot.duplicate(true)
		for key: String in ["snapshot_id", "numeric_content_sha256", "original_index_identity", "owner_label"]: numeric.erase(key)
		_check(int(snapshot.get("snapshot_id", -1)) == snapshot_id and Recorder.bytes_sha256(var_to_bytes(numeric)) == str(snapshot.get("numeric_content_sha256", "")), "exact_snapshot_hash:%d" % snapshot_id)
		_check(bool(snapshot.get("ready", false)) and snapshot.get("design_size") == Vector2i(32, 64) and snapshot.parts.size() == 47, "published_numeric_index_size:%d" % snapshot_id)
	# Preserve every original offset. Offset 300, if present, is explicitly a
	# stop-boundary input, not an invented extra physics tick or discarded query.
	for tick in range(300): _tick_batches.append([])
	var previous_tick := -1
	var valid := true
	var invalid_serial := -1
	for serial in range(_corpus.queries.size()):
		var query: Dictionary = _corpus.queries[serial]
		var tick := int(query.get("physics_tick_offset", -1))
		if int(query.get("serial", -1)) != serial or str(query.get("kind", "")) != "footprint" or not query.get("points") is PackedVector2Array or not query.get("expected_blocked") is bool or int(query.get("snapshot_id", -1)) < 0 or int(query.get("snapshot_id", -1)) >= _corpus.snapshots.size() or tick < previous_tick or tick < 0 or tick > 300:
			valid = false
			invalid_serial = serial
			break
		if tick == 300 and _tick_batches.size() == 300: _tick_batches.append([])
		_tick_batches[tick].append(query)
		previous_tick = tick
	_check(valid, "query_serial_type_tick_and_snapshot_valid:first_invalid=%d" % invalid_serial)

func _mode(mode: String, round_index: int) -> Dictionary:
	if mode.begins_with("SHARE_"): return _shared_mode(mode, round_index)
	var mode_start := Time.get_ticks_usec()
	var threaded := mode.contains("WORKER")
	var tick_mode := mode.begins_with("TICK_")
	var worker_limit := 2 if mode.ends_with("_2") else 1
	var jobs: Array[RefCounted] = []
	var snapshot_prepare_usec := 0
	var snapshot_bytes := 0
	for _unused in range(worker_limit):
		var job := Job.new()
		job.prepare_snapshots(_corpus.snapshots)
		snapshot_prepare_usec += job.snapshot_prepare_usec
		snapshot_bytes += job.private_snapshot_bytes
		jobs.append(job)
	var batches: Array = _tick_batches if tick_mode else [_corpus.queries]
	var rows: Array[Dictionary] = []
	var totals := {"kernel_replay_wall_usec": 0, "dispatch_usec": 0, "join_blocking_usec": 0,
		"transfer_pack_usec": 0, "transfer_unpack_usec": 0, "batch_split_usec": 0, "consume_compare_usec": 0,
		"worker_service_wall_sum_usec": 0, "overlap_wall_usec": 0, "query_count": 0,
		"mismatch_count": 0, "wrong_thread_count": 0, "completion_failure_count": 0, "submitted_jobs": 0, "joined_jobs": 0,
		"max_outstanding_jobs_upper_bound": 0, "peak_private_query_bytes": 0, "peak_private_results_bytes": 0}
	var first_difference: Dictionary = {}
	for batch_index in range(batches.size()):
		var batch: Array = batches[batch_index]
		var row := _batch(batch, jobs, threaded, batch_index if tick_mode else -1)
		rows.append(row)
		for key: String in totals:
			if key.begins_with("max_") or key.begins_with("peak_"):
				totals[key] = maxi(int(totals[key]), int(row.get(key, 0)))
			else:
				totals[key] = int(totals[key]) + int(row.get(key, 0))
		if first_difference.is_empty() and not row.first_difference.is_empty(): first_difference = row.first_difference
	if mode == "SERIAL" and not _serial_reference_ready: _serial_reference_ready = true
	_check(int(totals.mismatch_count) == 0 and int(totals.query_count) == _corpus.queries.size(), "%s:round%d:every_query_matches_capture_and_serial" % [mode, round_index])
	_check(int(totals.wrong_thread_count) == 0 and int(totals.completion_failure_count) == 0 and int(totals.submitted_jobs) == int(totals.joined_jobs), "%s:round%d:thread_identity_and_all_tasks_joined" % [mode, round_index])
	var total_wall := Time.get_ticks_usec() - mode_start
	# Serial can use the prepared corpus. Experiment-only serial transfer and
	# verification must not inflate the baseline used to judge worker costs.
	var pipeline := int(totals.kernel_replay_wall_usec) + int(_corpus.capture.query_copy_append_usec)
	if threaded:
		pipeline += int(totals.transfer_pack_usec) + int(totals.transfer_unpack_usec) + int(totals.batch_split_usec) + int(totals.consume_compare_usec)
	return {"mode": mode, "round": round_index, "warmup": round_index < 0,
		"timing_unit": "wall_usec_not_thread_cpu", "total_wall_usec": total_wall,
		"main_thread_active_wall_usec": total_wall - int(totals.join_blocking_usec),
		"snapshot_prepare_usec": snapshot_prepare_usec, "private_snapshot_bytes": snapshot_bytes,
		"conservative_pipeline_wall_usec": pipeline,
		"conservative_pipeline_cold_start_usec": pipeline + snapshot_prepare_usec + int(_corpus.capture.snapshot_pack_usec),
		"captured_query_copy_append_usec": int(_corpus.capture.query_copy_append_usec),
		"totals": totals, "first_difference": first_difference, "batches": rows,
		"per_tick_kernel_distribution": _distribution(rows, "kernel_replay_wall_usec") if tick_mode else {},
		"per_thread_cpu_usec": "MISSING", "per_core_utilization": "MISSING"}

func _batch(batch: Array, jobs: Array[RefCounted], threaded: bool, tick: int) -> Dictionary:
	var result := {"physics_tick_offset": tick, "stop_boundary_only": tick == 300, "query_count": batch.size(),
		"kernel_replay_wall_usec": 0, "dispatch_usec": 0, "join_blocking_usec": 0, "transfer_pack_usec": 0,
		"transfer_unpack_usec": 0, "batch_split_usec": 0, "consume_compare_usec": 0,
		"worker_service_wall_sum_usec": 0, "overlap_wall_usec": 0, "mismatch_count": 0,
		"wrong_thread_count": 0, "completion_failure_count": 0, "submitted_jobs": 0, "joined_jobs": 0, "max_outstanding_jobs_upper_bound": 0,
		"peak_private_query_bytes": 0, "peak_private_results_bytes": 0,
		"first_difference": {}, "jobs": [], "distinct_worker_ids": [], "actual_two_worker_overlap": "NOT_RUN"}
	if batch.is_empty(): return result
	var count := mini(jobs.size(), batch.size())
	var split_start := Time.get_ticks_usec()
	var chunks: Array[Array] = []
	for part in range(count):
		var first := int(batch.size() * part / count)
		var last := int(batch.size() * (part + 1) / count)
		chunks.append(batch.slice(first, last))
	result.batch_split_usec = Time.get_ticks_usec() - split_start
	for part in range(count):
		jobs[part].prepare_queries(chunks[part])
		result.transfer_pack_usec += jobs[part].transfer_pack_usec
		result.transfer_unpack_usec += jobs[part].transfer_unpack_usec
		result.peak_private_query_bytes += jobs[part].query_bytes
		result.peak_private_results_bytes += jobs[part].results.size()
	var task_ids: Array[int] = []
	var kernel_start := Time.get_ticks_usec()
	if threaded:
		var dispatch_start := Time.get_ticks_usec()
		for part in range(count):
			task_ids.append(WorkerThreadPool.add_task(Callable(jobs[part], "run"), false, "Static polygon replay"))
		result.dispatch_usec = Time.get_ticks_usec() - dispatch_start
		result.submitted_jobs = task_ids.size()
		result.max_outstanding_jobs_upper_bound = task_ids.size()
		# There is no early return or assertion between submit and final join.
		# Each task is drained exactly once before reading or reusing job data.
		var join_start := Time.get_ticks_usec()
		for task_id in task_ids:
			WorkerThreadPool.wait_for_task_completion(task_id)
			result.joined_jobs += 1
		result.join_blocking_usec = Time.get_ticks_usec() - join_start
	else:
		jobs[0].run()
	result.kernel_replay_wall_usec = Time.get_ticks_usec() - kernel_start
	var consume_start := Time.get_ticks_usec()
	var main_id := OS.get_main_thread_id()
	for part in range(count):
		var job: RefCounted = jobs[part]
		var evidence: Dictionary = job.evidence()
		result.jobs.append(evidence)
		if job.started_usec <= 0 or job.ended_usec < job.started_usec:
			result.completion_failure_count += 1
		result.worker_service_wall_sum_usec += int(evidence.worker_service_wall_usec) if threaded else 0
		if (threaded and job.thread_id == main_id) or (not threaded and job.thread_id != main_id) or job.thread_id < 0:
			result.wrong_thread_count += 1
		if not result.distinct_worker_ids.has(job.thread_id): result.distinct_worker_ids.append(job.thread_id)
		for offset in range(job.queries.size()):
			var query: Dictionary = job.queries[offset]
			var serial := int(query.serial)
			var actual := int(job.results[offset])
			var expected := 1 if bool(_corpus.queries[serial].expected_blocked) else 0
			if actual != expected or (_serial_reference_ready and actual != int(_serial_reference[serial])):
				result.mismatch_count += 1
				if result.first_difference.is_empty():
					result.first_difference = {"serial": serial, "expected": expected, "actual": actual,
						"serial_reference": int(_serial_reference[serial]) if _serial_reference_ready else -1}
			if not _serial_reference_ready: _serial_reference[serial] = actual
	if threaded and count == 2:
		result.overlap_wall_usec = maxi(0, mini(jobs[0].ended_usec, jobs[1].ended_usec) - maxi(jobs[0].started_usec, jobs[1].started_usec))
		result.actual_two_worker_overlap = "PASS" if result.distinct_worker_ids.size() == 2 and int(result.overlap_wall_usec) > 0 else "FAIL"
	result.consume_compare_usec = Time.get_ticks_usec() - consume_start
	return result

func _distribution(rows: Array, key: String) -> Dictionary:
	var values: Array[int] = []
	for row: Dictionary in rows: values.append(int(row.get(key, 0)))
	values.sort()
	if values.is_empty(): return {}
	return {"count": values.size(), "minimum": values[0], "p50": values[int(values.size() / 2)],
		"p95": values[mini(values.size() - 1, ceili(values.size() * 0.95) - 1)], "maximum": values[-1]}

func _seal_query_input(value: Variant) -> void:
	if value is Dictionary:
		for child: Variant in value.values(): _seal_query_input(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _seal_query_input(child)
		value.make_read_only()
	# PackedVector2Array has no read-only flag. The validated corpus owns it;
	# every consumer only reads and no writer exists throughout replay/join.

func _prepare_shared_input() -> void:
	var before := Time.get_ticks_usec()
	_seal_query_input(_corpus.queries)
	var serial := 0
	for batch: Array in _tick_batches:
		_tick_ranges.append(Vector2i(serial, batch.size()))
		serial += batch.size()
	_tick_ranges.make_read_only()
	_shared_input_prepare_usec = Time.get_ticks_usec() - before
	_check(serial == _corpus.queries.size() and _corpus.queries.is_read_only(), "shared_input_sealed_and_complete_ranges")
	# One-time archive/evidence accounting, outside every measured batch.
	before = Time.get_ticks_usec()
	var packed := var_to_bytes(_corpus.queries)
	_shared_query_bytes = packed.size()
	_shared_query_hash = Recorder.bytes_sha256(packed)
	_shared_input_evidence_usec = Time.get_ticks_usec() - before

func _shared_mode(mode: String, round_index: int) -> Dictionary:
	var mode_start := Time.get_ticks_usec()
	var tick_mode := mode.contains("TICK_")
	# Phone target experiment: never derive concurrency from desktop CPU count.
	var worker_limit := 2 if mode.ends_with("_2") else 1
	var ranges: Array[Vector2i] = []
	if tick_mode:
		ranges = _tick_ranges
	else:
		ranges.append(Vector2i(0, _corpus.queries.size()))
	var maximum_batch := 0
	for bounds: Vector2i in ranges: maximum_batch = maxi(maximum_batch, bounds.y)
	var capacity := maxi(1, ceili(float(maximum_batch) / float(worker_limit)))
	var jobs: Array[RefCounted] = []
	var snapshot_prepare_usec := 0
	var snapshot_bytes := 0
	var buffer_prepare_usec := 0
	var private_result_bytes := 0
	for _unused in range(worker_limit):
		var job := Job.new()
		job.prepare_snapshots(_corpus.snapshots)
		job.prepare_shared_input(_corpus.queries, capacity)
		snapshot_prepare_usec += job.snapshot_prepare_usec
		snapshot_bytes += job.private_snapshot_bytes
		buffer_prepare_usec += job.shared_buffer_prepare_usec
		private_result_bytes += job.results.size()
		jobs.append(job)
	var totals := {"kernel_replay_wall_usec": 0, "dispatch_usec": 0, "join_blocking_usec": 0,
		"range_prepare_usec": 0, "consume_compare_usec": 0, "transfer_pack_usec": 0, "transfer_unpack_usec": 0,
		"worker_service_wall_sum_usec": 0, "overlap_wall_usec": 0, "query_count": 0,
		"mismatch_count": 0, "wrong_thread_count": 0, "completion_failure_count": 0,
		"submitted_jobs": 0, "joined_jobs": 0, "max_outstanding_jobs_upper_bound": 0,
		"occupied_tick_batches": 0, "two_job_batches": 0, "two_worker_overlap_batches": 0}
	var rows: Array[Dictionary] = []
	var first_difference: Dictionary = {}
	for batch_index in range(ranges.size()):
		var bounds: Vector2i = ranges[batch_index]
		var row := _shared_batch(bounds.x, bounds.y, jobs, batch_index if tick_mode else -1)
		rows.append(row)
		for key: String in totals:
			if key.begins_with("max_"):
				totals[key] = maxi(int(totals[key]), int(row.get(key, 0)))
			else:
				totals[key] = int(totals[key]) + int(row.get(key, 0))
		if first_difference.is_empty() and not row.first_difference.is_empty(): first_difference = row.first_difference
	_check(int(totals.mismatch_count) == 0 and int(totals.query_count) == _corpus.queries.size(), "%s:round%d:every_query_matches_capture_and_serial" % [mode, round_index])
	_check(int(totals.wrong_thread_count) == 0 and int(totals.completion_failure_count) == 0 and int(totals.submitted_jobs) == int(totals.joined_jobs), "%s:round%d:thread_identity_and_all_tasks_joined" % [mode, round_index])
	var total_wall := Time.get_ticks_usec() - mode_start
	var pipeline := int(totals.kernel_replay_wall_usec) + int(totals.range_prepare_usec) + int(totals.consume_compare_usec) + int(_corpus.capture.query_copy_append_usec)
	return {"mode": mode, "round": round_index, "warmup": round_index < 0,
		"input_handoff": "shared_immutable_range_private_fixed_output", "persistent_jobs": jobs.size(),
		"timing_unit": "wall_usec_not_thread_cpu", "total_wall_usec": total_wall,
		"main_thread_active_wall_usec": total_wall - int(totals.join_blocking_usec),
		"snapshot_prepare_usec": snapshot_prepare_usec, "private_snapshot_bytes": snapshot_bytes,
		"fixed_output_prepare_usec": buffer_prepare_usec, "private_fixed_output_bytes": private_result_bytes,
		"shared_input_bytes_once": _shared_query_bytes, "shared_input_prepare_usec_once": _shared_input_prepare_usec,
		"conservative_pipeline_wall_usec": pipeline,
		"conservative_pipeline_cold_start_usec": pipeline + snapshot_prepare_usec + buffer_prepare_usec + _shared_input_prepare_usec + int(_corpus.capture.snapshot_pack_usec),
		"captured_query_copy_append_usec": int(_corpus.capture.query_copy_append_usec),
		"totals": totals, "first_difference": first_difference, "batches": rows,
		"mean_kernel_wall_usec_per_physics_tick": float(totals.kernel_replay_wall_usec) / float(_corpus.source.ticks),
		"mean_pipeline_wall_usec_per_physics_tick": float(pipeline) / float(_corpus.source.ticks),
		"per_tick_query_distribution": _distribution(rows, "query_count") if tick_mode else {},
		"per_tick_kernel_distribution": _distribution(rows, "kernel_replay_wall_usec") if tick_mode else {},
		"per_tick_handoff_kernel_consume_distribution": _distribution(rows, "handoff_kernel_consume_usec") if tick_mode else {},
		"main_thread_cpu_usec": "MISSING", "per_thread_cpu_usec": "MISSING", "per_core_utilization": "MISSING",
		"production_safe_batch_discovery": "NOT_RUN", "production_frame_benefit": "NOT_RUN"}

func _shared_batch(first_serial: int, query_count: int, jobs: Array[RefCounted], tick: int) -> Dictionary:
	var result := {"physics_tick_offset": tick, "stop_boundary_only": tick == 300, "query_count": query_count,
		"kernel_replay_wall_usec": 0, "dispatch_usec": 0, "join_blocking_usec": 0, "range_prepare_usec": 0,
		"consume_compare_usec": 0, "handoff_kernel_consume_usec": 0, "transfer_pack_usec": 0, "transfer_unpack_usec": 0,
		"worker_service_wall_sum_usec": 0, "overlap_wall_usec": 0, "mismatch_count": 0,
		"wrong_thread_count": 0, "completion_failure_count": 0, "submitted_jobs": 0, "joined_jobs": 0,
		"max_outstanding_jobs_upper_bound": 0, "occupied_tick_batches": 0, "two_job_batches": 0,
		"two_worker_overlap_batches": 0, "first_difference": {}, "jobs": [],
		"distinct_worker_ids": [], "actual_two_worker_overlap": "NOT_RUN"}
	if query_count == 0: return result
	result.occupied_tick_batches = 1 if tick >= 0 and tick < 300 else 0
	var count := mini(jobs.size(), query_count)
	result.two_job_batches = 1 if count == 2 else 0
	var before := Time.get_ticks_usec()
	for part in range(count):
		var offset := int(query_count * part / count)
		var end := int(query_count * (part + 1) / count)
		if not jobs[part].prepare_shared_range(first_serial + offset, end - offset):
			result.completion_failure_count += 1
	result.range_prepare_usec = Time.get_ticks_usec() - before
	# Never dispatch an invalid range; there are no live tasks at this point.
	if int(result.completion_failure_count) > 0: return result
	var task_ids: Array[int] = []
	var kernel_start := Time.get_ticks_usec()
	var dispatch_start := Time.get_ticks_usec()
	for part in range(count):
		task_ids.append(WorkerThreadPool.add_task(Callable(jobs[part], "run_shared"), false, "Shared static polygon replay"))
	result.dispatch_usec = Time.get_ticks_usec() - dispatch_start
	result.submitted_jobs = task_ids.size()
	result.max_outstanding_jobs_upper_bound = task_ids.size()
	var join_start := Time.get_ticks_usec()
	for task_id in task_ids:
		WorkerThreadPool.wait_for_task_completion(task_id)
		result.joined_jobs += 1
	result.join_blocking_usec = Time.get_ticks_usec() - join_start
	result.kernel_replay_wall_usec = Time.get_ticks_usec() - kernel_start
	var consume_start := Time.get_ticks_usec()
	var main_id := OS.get_main_thread_id()
	for part in range(count):
		var job: RefCounted = jobs[part]
		var evidence: Dictionary = job.shared_evidence()
		result.jobs.append(evidence)
		if job.started_usec <= 0 or job.ended_usec < job.started_usec: result.completion_failure_count += 1
		result.worker_service_wall_sum_usec += int(evidence.worker_service_wall_usec)
		if job.thread_id == main_id or job.thread_id < 0: result.wrong_thread_count += 1
		if not result.distinct_worker_ids.has(job.thread_id): result.distinct_worker_ids.append(job.thread_id)
		for offset in range(job.shared_count):
			var serial: int = job.shared_first + offset
			var actual := int(job.results[offset])
			var expected := 1 if bool(_corpus.queries[serial].expected_blocked) else 0
			if actual != expected or actual != int(_serial_reference[serial]):
				result.mismatch_count += 1
				if result.first_difference.is_empty():
					result.first_difference = {"serial": serial, "expected": expected, "actual": actual, "serial_reference": int(_serial_reference[serial])}
	if count == 2:
		result.overlap_wall_usec = maxi(0, mini(jobs[0].ended_usec, jobs[1].ended_usec) - maxi(jobs[0].started_usec, jobs[1].started_usec))
		result.actual_two_worker_overlap = "PASS" if result.distinct_worker_ids.size() == 2 and int(result.overlap_wall_usec) > 0 else "FAIL"
		result.two_worker_overlap_batches = 1 if result.actual_two_worker_overlap == "PASS" else 0
	result.consume_compare_usec = Time.get_ticks_usec() - consume_start
	result.handoff_kernel_consume_usec = int(result.range_prepare_usec) + int(result.kernel_replay_wall_usec) + int(result.consume_compare_usec)
	return result

func _summary() -> Dictionary:
	var modes: Dictionary = {}
	for mode: String in MODES:
		var rows: Array = []
		for row: Dictionary in _rounds:
			if row.mode == mode:
				rows.append({"kernel": row.totals.kernel_replay_wall_usec, "pipeline": row.conservative_pipeline_wall_usec,
					"cold": row.conservative_pipeline_cold_start_usec})
		modes[mode] = {"kernel_median_usec": _distribution(rows, "kernel").get("p50", 0),
			"pipeline_median_usec": _distribution(rows, "pipeline").get("p50", 0),
			"cold_pipeline_median_usec": _distribution(rows, "cold").get("p50", 0),
			"observations": _mode_observations(mode)}
	for mode: String in MODES:
		if not mode.contains("WORKER"): continue
		var baseline: String = "TICK_SERIAL" if mode.contains("TICK_") else "SERIAL"
		modes[mode]["kernel_cost_status"] = "PASS" if modes[mode].kernel_median_usec < modes[baseline].kernel_median_usec else "FAIL"
		modes[mode]["conservative_pipeline_cost_status"] = "PASS" if modes[mode].pipeline_median_usec < modes[baseline].pipeline_median_usec else "FAIL"
	var overlap_pass := 0
	for row: Dictionary in _rounds:
		if row.mode == "WORKER_2" and row.batches[0].actual_two_worker_overlap == "PASS": overlap_pass += 1
	return {"NUMERIC_PARITY": "PASS" if _failures.is_empty() and _rounds.size() == MODES.size() * 3 else "FAIL",
		"ACTUAL_WORKER_THREAD": "PASS" if _failures.is_empty() and _rounds.size() == MODES.size() * 3 else "FAIL",
		"ACTUAL_TWO_WORKER_OVERLAP": "PASS" if overlap_pass == 3 else "FAIL",
		"KERNEL_REPLAY_COST": {"WORKER_1": modes.WORKER_1.kernel_cost_status, "WORKER_2": modes.WORKER_2.kernel_cost_status},
		"PER_TICK_REPLAY_COST": {"WORKER_1": modes.TICK_WORKER_1.kernel_cost_status, "WORKER_2": modes.TICK_WORKER_2.kernel_cost_status},
		"CAPTURE_PACK_JOIN_COST": {"WORKER_1": modes.WORKER_1.conservative_pipeline_cost_status,
			"WORKER_2": modes.WORKER_2.conservative_pipeline_cost_status,
			"TICK_WORKER_1": modes.TICK_WORKER_1.conservative_pipeline_cost_status,
			"TICK_WORKER_2": modes.TICK_WORKER_2.conservative_pipeline_cost_status},
		"SHARED_INPUT_COST": {"SHARE_WORKER_2": modes.SHARE_WORKER_2.conservative_pipeline_cost_status,
			"SHARE_TICK_WORKER_1": modes.SHARE_TICK_WORKER_1.conservative_pipeline_cost_status,
			"SHARE_TICK_WORKER_2": modes.SHARE_TICK_WORKER_2.conservative_pipeline_cost_status},
		"PRODUCTION_FRAME_BENEFIT": "NOT_RUN", "DEVICE_TEST": "NOT_RUN", "modes": modes}

func _mode_observations(mode: String) -> Dictionary:
	var batch_count := 0
	var occupied := 0
	var two_jobs := 0
	var overlaps := 0
	var mismatches := 0
	var wrong_threads := 0
	var incomplete := 0
	var query_count := 0
	var observed_ids: Array[int] = []
	for row: Dictionary in _rounds:
		if row.mode != mode: continue
		mismatches += int(row.totals.mismatch_count)
		wrong_threads += int(row.totals.wrong_thread_count)
		incomplete += int(row.totals.completion_failure_count)
		query_count += int(row.totals.query_count)
		for batch: Dictionary in row.batches:
			batch_count += 1
			if int(batch.query_count) > 0: occupied += 1
			if int(batch.submitted_jobs) == 2: two_jobs += 1
			if batch.actual_two_worker_overlap == "PASS": overlaps += 1
			for thread_id: int in batch.distinct_worker_ids:
				if not observed_ids.has(thread_id): observed_ids.append(thread_id)
	return {"NUMERIC_PARITY": "PASS" if mismatches == 0 and incomplete == 0 and query_count == _corpus.queries.size() * 3 else "FAIL",
		"ACTUAL_WORKER_THREAD": ("PASS" if wrong_threads == 0 and incomplete == 0 else "FAIL") if mode.contains("WORKER") else "NOT_RUN",
		"ACTUAL_TWO_WORKER_OVERLAP": ("PASS" if overlaps > 0 else "FAIL") if two_jobs > 0 else "NOT_RUN",
		"batch_count_three_rounds": batch_count, "occupied_batches": occupied, "empty_batches": batch_count - occupied,
		"two_job_batches": two_jobs, "observed_overlap_batches": overlaps,
		"overlap_fraction_of_two_job_batches": float(overlaps) / float(two_jobs) if two_jobs > 0 else 0.0,
		"distinct_thread_ids": observed_ids, "queried_items_three_rounds": query_count,
		"mean_queries_per_occupied_batch": float(query_count) / float(occupied) if occupied > 0 else 0.0}

func _finish() -> void:
	var report := {"schema": "hardcore.static_polygon_probe_receipt.v2", "source_stage": "shared_input_stage2", "scene_id": SCENE_ID,
		"status": "PASS" if _failures.is_empty() else "FAIL", "failures": _failures,
		"corpus_path": _corpus_path, "corpus_sha256": _corpus_sha256, "corpus_bytes": _input_bytes,
		"capture_source": _corpus.get("source", {}), "capture_costs": _corpus.get("capture", {}),
		"archive_input_read_usec": _input_read_usec, "offline_input_unpack_validate_usec": _input_unpack_validate_usec,
		"run_id": OS.get_environment("HARDCORE_FRAMEWORK_RUN_ID"), "invocation_id": OS.get_environment("HARDCORE_FRAMEWORK_INVOCATION_ID"),
		"source_content_sha256": OS.get_environment("HARDCORE_R3_CONTENT_SHA256"), "HEAD": OS.get_environment("HARDCORE_R3_TESTED_SHA"),
		"engine": Engine.get_version_info(), "main_thread_id": OS.get_main_thread_id(),
		"runtime_appdata": OS.get_environment("APPDATA"), "user_data_directory": OS.get_user_data_dir(),
		"shared_input_once": {"seal_and_ranges_usec": _shared_input_prepare_usec,
			"probe_size_hash_evidence_usec": _shared_input_evidence_usec, "binary_encoded_query_bytes": _shared_query_bytes,
			"sha256": _shared_query_hash, "packed_points_immutability": "ownership_no_writer",
			"max_concurrent_tasks": 2, "target_device": "Honor REA-AN00", "pc_core_count_used": false},
		"warmups": _warmups, "rounds": _rounds, "conclusions": _summary() if _rounds.size() == MODES.size() * 3 else {"NUMERIC_PARITY": "FAIL", "PRODUCTION_FRAME_BENEFIT": "NOT_RUN", "DEVICE_TEST": "NOT_RUN"},
		"measurement_notes": ["All durations are wall timings. Thread CPU and per-core utilization are MISSING.",
			"Worker service interval overlap does not prove simultaneous per-core CPU execution.",
			"Kernel wall includes dispatch and join; do not add service or join again.",
			"Worker pipeline includes capture copy, binary transfer, split and consume; cold adds one-time snapshot copies.",
			"Serial pipeline uses prepared input; its experiment-only transfer and verification remain in raw totals, not its comparison baseline.",
			"Outstanding task count is a submitted-but-not-yet-joined upper bound, not an OS queue occupancy sample.",
			"Archive IO, binary validation, receipts and detailed evidence collection are experiment-only costs.",
			"Main-thread active wall is total minus join wall; it includes observation overhead and is not CPU time.",
			"Instrumented game capture is input provenance, not a production frame A/B.",
			"SHARE modes reference sealed input with private fixed output buffers and private numeric snapshots; no per-batch binary transfer.",
			"Shared range preparation, dispatch, join and result consumption are measured, never assumed free.",
			"Memory byte fields describe encoded numeric payload/output capacity, not allocator or process heap size.",
			"SHARE per-tick offline queries are known ahead of time; no production-safe discovery or batching has been implemented.",
			"Main-thread CPU is MISSING; results address repeated per-tick wall cost, not only isolated frame peaks."]}
	var directory := OS.get_environment("HARDCORE_COMPUTE_INVOCATION_PATH")
	var file := FileAccess.open(directory.path_join("static_polygon.replay.json"), FileAccess.WRITE)
	_check(file != null, "replay_report_open")
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	var failed := 0
	for record: Dictionary in _proof.records:
		if not record.passed: failed += 1
	var receipt_ok := _proof.write_receipt(SCENE_ID, _proof.records.size(), failed)
	print("STATIC_POLYGON_REPLAY_V113_%s queries=%d corpus=%s" % ["PASS" if _failures.is_empty() and receipt_ok else "FAIL", _corpus.get("queries", []).size(), _corpus_sha256])
	get_tree().quit(0 if _failures.is_empty() and receipt_ok else 1)
