extends RefCounted
## Main-thread-only recorder. No file IO or binary encoding in the sample window.
const SCHEMA := "hardcore.static_polygon_replay.v1"
const RELEASE_SHA := "005a0cdbc11241a094d815cb9753a03254712331353d5ab00b483aac90652711"
var snapshots: Array[Dictionary] = []
var queries: Array[Dictionary] = []
var failures: Array[String] = []
var identities: Dictionary = {}
var active := false
var start_frame := 0
var snapshot_pack_usec := 0
var snapshot_bytes := 0
var query_copy_append_usec := 0
var original_kernel_usec := 0
var point_count := 0

static func numeric_only(value: Variant) -> bool:
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_RECT2, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_BYTE_ARRAY:
			return true
		TYPE_ARRAY:
			for child: Variant in value:
				if not numeric_only(child): return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not numeric_only(key) or not numeric_only(value[key]): return false
			return true
	return false

static func bytes_sha256(data: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	hashing.start(HashingContext.HASH_SHA256)
	hashing.update(data)
	return hashing.finish().hex_encode()

static func numeric_snapshot(index: RefCounted) -> Dictionary:
	var copied_parts: Array[PackedVector2Array] = []
	for part: PackedVector2Array in index.parts: copied_parts.append(part.duplicate())
	return {"design_size": index.design_size, "ready": index.ready,
		"parts": copied_parts, "boxes": index.boxes.duplicate(),
		"padded_boxes": index._padded_boxes.duplicate(),
		"first_buckets": index._first_buckets.duplicate(), "buckets": index.buckets.duplicate(true)}

func register_context(context: Dictionary, owner_label: String) -> void:
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		failures.append("snapshot_registration_not_main_thread")
		return
	if active:
		failures.append("snapshot_registration_during_capture")
		return
	if int(context.get("runtime_map_id", -1)) != 913203 or str(context.get("build_sha256", "")) != RELEASE_SHA or not context.has("poly_index"):
		failures.append("unbound_release_context:" + owner_label)
		return
	var index: RefCounted = context.poly_index
	if not index.ready or index.design_size != context.get("design_size"):
		failures.append("unready_or_size_mismatch:" + owner_label)
		return
	var identity := index.get_instance_id()
	if identities.has(identity): return
	var before := Time.get_ticks_usec()
	var snapshot := numeric_snapshot(index)
	if not numeric_only(snapshot):
		failures.append("snapshot_contains_non_numeric_value:" + owner_label)
		return
	var packed := var_to_bytes(snapshot)
	snapshot["numeric_content_sha256"] = bytes_sha256(packed)
	snapshot["snapshot_id"] = snapshots.size()
	snapshot["original_index_identity"] = identity
	snapshot["owner_label"] = owner_label
	identities[identity] = snapshots.size()
	snapshots.append(snapshot)
	snapshot_bytes += packed.size()
	snapshot_pack_usec += Time.get_ticks_usec() - before

func start(frame: int) -> void:
	start_frame = frame
	active = true

func record(index: RefCounted, points: PackedVector2Array, blocked: bool, kernel_start: int, kernel_end: int) -> void:
	if not active: return
	if OS.get_thread_caller_id() != OS.get_main_thread_id():
		failures.append("capture_query_not_main_thread")
		return
	var identity := index.get_instance_id()
	if not identities.has(identity):
		failures.append("query_from_unregistered_index:%d" % identity)
		return
	queries.append({"serial": queries.size(), "physics_tick_offset": Engine.get_physics_frames() - start_frame,
		"snapshot_id": int(identities[identity]), "kind": "footprint", "points": points.duplicate(), "expected_blocked": blocked})
	point_count += points.size()
	original_kernel_usec += kernel_end - kernel_start
	# Includes hook-to-sink call and all append bookkeeping after the kernel.
	query_copy_append_usec += Time.get_ticks_usec() - kernel_end

func verify_context(context: Dictionary, owner_label: String) -> void:
	if not context.has("poly_index"):
		failures.append("context_lost_index:" + owner_label)
		return
	var index: RefCounted = context.poly_index
	var identity := index.get_instance_id()
	if not identities.has(identity):
		failures.append("context_changed_index:" + owner_label)
		return
	if int(context.get("runtime_map_id", -1)) != 913203 or str(context.get("build_sha256", "")) != RELEASE_SHA:
		failures.append("context_changed_release:" + owner_label)
	if bytes_sha256(var_to_bytes(numeric_snapshot(index))) != str(snapshots[int(identities[identity])].numeric_content_sha256):
		failures.append("numeric_snapshot_changed:" + owner_label)

func write_corpus(path: String, source: Dictionary, revision_start: int, revision_end: int) -> Dictionary:
	active = false
	if revision_start != revision_end: failures.append("environment_revision_changed")
	if queries.is_empty(): failures.append("no_real_footprint_queries")
	if snapshots.is_empty(): failures.append("no_registered_snapshots")
	var capture := {"snapshot_pack_usec": snapshot_pack_usec, "snapshot_bytes": snapshot_bytes,
		"query_copy_append_usec": query_copy_append_usec, "original_kernel_usec": original_kernel_usec,
		"instrumentation_timing_included": true, "query_count": queries.size(), "point_count": point_count,
		"map_revision_start": revision_start, "map_revision_end": revision_end, "failures": failures.duplicate(),
		"truncated": false, "production_frame_benefit": "NOT_RUN"}
	var corpus := {"schema": SCHEMA, "source": source, "snapshots": snapshots, "queries": queries, "capture": capture}
	if not numeric_only(corpus):
		failures.append("corpus_contains_non_numeric_value")
		return {"status": "FAIL", "failures": failures.duplicate()}
	var pack_start := Time.get_ticks_usec()
	var packed := var_to_bytes(corpus)
	var pack_usec := Time.get_ticks_usec() - pack_start
	var io_start := Time.get_ticks_usec()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		failures.append("corpus_open_failed")
		return {"status": "FAIL", "failures": failures.duplicate()}
	file.store_buffer(packed)
	file.close()
	var archive_io_usec := Time.get_ticks_usec() - io_start
	var read_bytes := FileAccess.get_file_as_bytes(path)
	var recovered: Variant = bytes_to_var(read_bytes)
	var roundtrip_ok := read_bytes == packed and recovered is Dictionary and numeric_only(recovered)
	if roundtrip_ok:
		roundtrip_ok = var_to_bytes(recovered) == packed and recovered.queries.size() == queries.size()
		for serial in range(queries.size()):
			if recovered.queries[serial] != queries[serial]:
				roundtrip_ok = false
				break
	if not roundtrip_ok: failures.append("binary_roundtrip_mismatch")
	return {"status": "PASS" if failures.is_empty() else "FAIL", "failures": failures.duplicate(),
		"corpus_path": path, "corpus_sha256": bytes_sha256(packed), "output_bytes": packed.size(),
		"corpus_pack_usec": pack_usec, "archive_file_io_usec": archive_io_usec, "binary_roundtrip": roundtrip_ok,
		"source": source, "capture": capture, "snapshot_count": snapshots.size(), "query_count": queries.size()}
