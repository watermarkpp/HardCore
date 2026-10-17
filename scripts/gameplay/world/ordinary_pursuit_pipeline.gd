extends RefCounted

## S owns admission/install/lifetime. W receives only the actual plain source
## snapshot. No HP, attack, position writer, new clock or synchronous join here.
var _owner := OS.get_thread_caller_id()
var _world: WeakRef
var _source: RefCounted
var _native: RefCounted
var _configured := false
var _closed := false
var _period_usec := 0
var _next_release_usec := 0
var _sequence := 0
var _active: Dictionary = {}
var _installed: Dictionary = {}
var _receipts: Array[Dictionary] = []
var _receipt_capacity := 0

func owner_thread_id() -> int: return _owner

func configure_owner(world: RefCounted, source: RefCounted, native: RefCounted, period_ms: int, receipt_capacity: int) -> bool:
	if _configured or _owner == OS.get_main_thread_id() or period_ms not in [50, 100, 200, 300] or receipt_capacity <= 0: return false
	for port: RefCounted in [world, source, native]:
		if port == null or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner: return false
	for method: String in ["capture_original_planning_batch", "validate_original_planning_adoption", "install_original_planning_row", "current_original_actor_key", "report_original_planning_receipt"]:
		if not source.has_method(method): return false
	for method: String in ["submit_planning_batch", "poll_planning_batch", "retire_planning_batch", "cancel_planning_batch", "has_pending_planning_batches", "close_owner", "capabilities"]:
		if not native.has_method(method): return false
	var capabilities: Dictionary = native.capabilities()
	for guarantee: String in ["immutable_numeric_snapshots", "nonblocking_submit", "nonblocking_poll", "no_S_M_worker_join", "bounded_planning_slices", "shared_short_geometry_pool", "worker_only_numeric", "actual_completed_worker_reclamation"]:
		if capabilities.get(guarantee) != true: return false
	_world = weakref(world)
	_source = source
	_native = native
	_period_usec = period_ms * 1000
	_receipt_capacity = receipt_capacity
	_next_release_usec = Time.get_ticks_usec()
	_configured = true
	return true

func _fault(code: String, details: Dictionary) -> bool:
	_world.get_ref().fault(code, details)
	return false

func original_prepare_boundary() -> bool:
	if not _configured or _closed or OS.get_thread_caller_id() != _owner: return false
	# Poll first. A historical target pose is a soft input; the source validator
	# checks actual life/map/shape/control/target identity, not new player pose.
	if not _active.is_empty() and not _poll_active(false): return false
	for id: int in _installed.keys():
		if _source.current_original_actor_key(id).is_empty(): _installed.erase(id)
	var now_usec := Time.get_ticks_usec()
	if now_usec < _next_release_usec or not _active.is_empty(): return true
	_sequence += 1
	var captured: Dictionary = _source.capture_original_planning_batch(_sequence, now_usec, _period_usec)
	if captured.get("ok") != true: return _fault("ordinary_pursuit_source_snapshot_missing", captured)
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	if not graph.validate(captured, false).get("success", false): return _fault("ordinary_pursuit_snapshot_not_plain", {})
	if not captured.get("actors") is Array or not captured.get("static_navigation") is Dictionary or not captured.get("peers") is Array: return _fault("ordinary_pursuit_snapshot_shape_missing", {})
	if not captured.get("world_context") is Dictionary or not captured.get("static_revision") is int: return _fault("ordinary_pursuit_snapshot_identity_missing", {})
	var identities: Dictionary = {}
	for actor: Dictionary in captured.actors:
		for field: String in ["runtime_id", "life", "target_runtime_id", "target_life", "radius_revision"]:
			if not actor.get(field) is int or actor[field] <= 0: return _fault("ordinary_pursuit_actor_identity_missing", {"field": field})
		if identities.has(actor.runtime_id): return _fault("ordinary_pursuit_duplicate_actor", {"id": actor.runtime_id})
		identities[actor.runtime_id] = actor
	if captured.actors.is_empty():
		_next_release_usec = now_usec + _period_usec
		_source.report_original_planning_receipt({"status": "NOT_RUN", "reason": "actual_zero_eligible_ordinary_actors", "sequence": _sequence, "actor_count": 0, "release_usec": now_usec})
		return true
	# Exact release->all-ready+install+repair cutoff includes S source capture.
	# 20 percent is engineering margin, not a statistical/device guarantee.
	var deadline_usec: int = now_usec + _period_usec * 4 / 5
	var submitted: Dictionary = _native.submit_planning_batch(captured, deadline_usec)
	if submitted.get("accepted") != true or not submitted.get("ticket") is Dictionary: return _fault("ordinary_pursuit_native_submission_rejected", submitted)
	_active = {"ticket": submitted.ticket, "source": captured, "identities": identities,
		"sequence": _sequence, "release_usec": now_usec, "deadline_usec": deadline_usec}
	_next_release_usec = now_usec + _period_usec
	return true

func original_adopt_boundary() -> bool:
	if not _configured or _closed or OS.get_thread_caller_id() != _owner: return false
	return _active.is_empty() or _poll_active(true)

func _poll_active(allow_install: bool) -> bool:
	if _active.get("installed") == true:
		if not _native.retire_planning_batch(_active.ticket): return true
		_active = {}
		return true
	var reply: Dictionary = _native.poll_planning_batch(_active.ticket)
	if reply.get("ok") != true: return _fault("ordinary_pursuit_native_poll_failed", reply)
	if reply.get("ready") != true: return true
	if not allow_install: return true
	if reply.get("ticket") != _active.ticket or not reply.get("rows") is Array or reply.rows.size() != _active.identities.size(): return _fault("ordinary_pursuit_incomplete_batch", reply)
	var seen: Dictionary = {}
	var installed := 0
	var rejected := 0
	var repair_count := 0
	for row: Dictionary in reply.rows:
		var id: int = int(row.get("runtime_id", 0))
		if not _active.identities.has(id) or seen.has(id): return _fault("ordinary_pursuit_output_identity_mismatch", {"id": id})
		seen[id] = true
		var actual: Dictionary = _source.validate_original_planning_adoption(_active.source, _active.identities[id], row)
		if actual.get("ok") != true: return _fault("ordinary_pursuit_adoption_validation_missing", actual)
		if actual.get("hard_valid") != true:
			rejected += 1
			continue
		if not actual.get("actor_key") is Dictionary or actual.actor_key.is_empty(): return _fault("ordinary_pursuit_adoption_hard_key_missing", {})
		var applied: Dictionary = _source.install_original_planning_row(_active.identities[id], row)
		if applied.get("ok") != true or not applied.get("repair_count") is int: return _fault("ordinary_pursuit_original_install_failed", applied)
		repair_count += applied.repair_count
		_installed[id] = {"actor_key": actual.actor_key, "sequence": _active.sequence, "row": row}
		installed += 1
	var finished_usec := Time.get_ticks_usec()
	var receipt := {"status": "PASS" if finished_usec <= _active.deadline_usec else "FAIL",
		"sequence": _active.sequence, "actor_count": _active.identities.size(), "all_ready_rows": reply.rows.size(),
		"installed": installed, "hard_rejected": rejected, "repair_count": repair_count,
		"release_usec": _active.release_usec, "all_ready_usec": reply.get("all_ready_usec"),
		"installed_repaired_usec": finished_usec, "deadline_usec": _active.deadline_usec,
		"complete_batch_elapsed_usec": finished_usec - int(_active.release_usec), "native_receipt": reply.get("receipt", {})}
	_receipts.append(receipt)
	if _receipts.size() > _receipt_capacity: _receipts.pop_front()
	_source.report_original_planning_receipt(receipt)
	# Reclamation is actual W-side completed task bookkeeping. S/M never join.
	_active.installed = true
	if not _native.retire_planning_batch(_active.ticket): return true
	_active = {}
	return true

func has_actual_installed_intent(runtime_id: int) -> bool:
	if not _configured or _closed or not _installed.has(runtime_id): return false
	var current: Dictionary = _source.current_original_actor_key(runtime_id)
	return not current.is_empty() and current == _installed[runtime_id].actor_key

func actual_installed_row(runtime_id: int) -> Dictionary:
	return _installed[runtime_id].row if has_actual_installed_intent(runtime_id) else {}

func receipt_snapshot() -> Array[Dictionary]: return _receipts.duplicate(true)

func close_owner() -> bool:
	if not _configured or OS.get_thread_caller_id() != _owner: return false
	_closed = true
	if not _active.is_empty():
		if not _native.cancel_planning_batch(_active.ticket): return false
		if not _native.retire_planning_batch(_active.ticket): return false
		_active = {}
	if _native.has_pending_planning_batches() or not _native.close_owner(): return false
	_installed.clear()
	_source = null
	_native = null
	_configured = false
	return true
