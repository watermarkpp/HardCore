extends RefCounted

## Accepted map commands reuse the Native original-event / prefix channel.
## This adapter never calls cold exchange, sleeps, joins W, or holds a budget scope.
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const OPS := ["prepare", "request_resources", "poll_resources", "select_descriptors", "build_item", "capture_environment", "finish_visual", "retire_claims", "zone", "focus"]
var _owner := OS.get_thread_caller_id()
var _world_ref: WeakRef
var _world: RefCounted:
	get: return _world_ref.get_ref() if _world_ref != null else null
	set(value): _world_ref = weakref(value) if value != null else null
var _session_ref: WeakRef
var _session: RefCounted:
	get: return _session_ref.get_ref() if _session_ref != null else null
	set(value): _session_ref = weakref(value) if value != null else null
var _host_ref: WeakRef
var _host: Object:
	get: return _host_ref.get_ref() if _host_ref != null else null
	set(value): _host_ref = weakref(value) if value != null else null
var _admission_ref: WeakRef
var _admission: RefCounted:
	get: return _admission_ref.get_ref() if _admission_ref != null else null
	set(value): _admission_ref = weakref(value) if value != null else null
var _budget: RefCounted
var _scope: Dictionary = {}
var _descriptor: Dictionary
var _reservation_usec: int
var _serial := 0
var _job: Dictionary = {}
var _last_finish: Dictionary = {}
var _arrived := false
var _arrival_transaction: Dictionary = {}
signal actual_original_map_close_service
var _exchange_running := false
var _close_service_sequence := -1
# Source-only observations. No timer, queue, publication or gameplay authority.
var _trace_enabled := false
var _trace_job: Dictionary = {}

func owner_thread_id() -> int: return _owner
func configure_owner(world: RefCounted, session: RefCounted, admission: RefCounted, host: Object, descriptor: Dictionary, reservation_usec: int) -> bool:
	if _world != null or _owner == OS.get_main_thread_id() or reservation_usec < 0: return false
	for port: Object in [world, session, admission]:
		if port == null or port is Node or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner: return false
	for method: String in ["verify_original_map_loading_scope", "verify_original_map_loading_publication", "reserve_original_map_loading_event", "accept_original_map_loading_event", "cancel_unaccepted_original_map_loading_event", "poll_original_map_loading_event", "settle_original_map_loading_event_status", "retire_original_map_loading_event"]:
		if host == null or not host.has_method(method): return false # MISSING, never a compatibility park.
	for method: String in ["request_original_map_loading_boundary", "poll_original_map_loading_boundary", "release_original_map_loading_boundary"]:
		if not admission.has_method(method): return false
	if not session.has_method("original_budget_session_id") or not session.has_method("original_event_journal"): return false
	if descriptor.get("contract_id") != "source.map.loading.owner.v1" or descriptor.get("world_context") != world.current_world_identity() or descriptor.get("owner_session_id") != session.original_budget_session_id() or not descriptor.get("source_root_id") is int or descriptor.source_root_id == 0 or not descriptor.get("main_executor_id") is int or descriptor.main_executor_id == 0: return false
	_world = world; _session = session; _admission = admission; _host = host
	_budget = session.original_frame_budget(); _descriptor = descriptor.duplicate(true); _reservation_usec = reservation_usec
	_trace_enabled = bool(world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace", false))
	return _budget.owner_thread_id() == _owner

func _next_source_p() -> void:
	# Original ProfileRuntimePort service signal, on S. Main never waits for S.
	if _world.current_clock_frame().get("closing_session") != true:
		await _world.profile_runtime.next_service()
	if _world.current_clock_frame().get("closing_session") == true:
		# A SIGNAL wake is not the NODE_PROCESS_SERVICE settlement boundary.
		await actual_original_map_close_service

func service_actual_original_map_close_at_P(frame: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _world == null or frame != _world.current_clock_frame() or frame != _host.current_clock_frame() or frame.get("closing_session") != true or frame.get("phase") != "P_CLOSE_SERVICE" or frame.get("source_boundary") != "NODE_PROCESS_SERVICE" or frame.get("closing_process_publication",{}).get("phase") != "NODE_PROCESS_SERVICE": return false
	if int(_budget.snapshot().open_scopes) != 0 or _budget.resource_external_segment_active() or _world.current_original_source_site().get("domain") != "P": return false
	var sequence: int = int(frame.get("source_process_frame",-1))
	if sequence <= _close_service_sequence: return sequence == _close_service_sequence
	_close_service_sequence = sequence
	actual_original_map_close_service.emit()
	return true
func has_pending_original_map_continuation() -> bool:
	return _exchange_running or not _job.is_empty()

func open_loading_scope(transition: String, generation: int, map_id: int) -> bool:
	if not _scope.is_empty() or not _job.is_empty() or transition.is_empty() or generation < 0: return false
	var requested: Dictionary = await _admission.request_original_map_loading_boundary(_descriptor, transition, generation, map_id)
	if requested.get("status") != "ACCEPTED": return false
	while true:
		var actual: Dictionary = _admission.poll_original_map_loading_boundary(requested.identity)
		if actual.get("status") == "INVALID": return false
		if actual.get("status") == "READY":
			if not actual.get("scope") is Dictionary or not _host.verify_original_map_loading_scope(actual.scope, _descriptor, transition, generation, map_id): return false
			_scope = actual.scope
			_last_finish = {}; _arrived = false
			return true
		await _next_source_p()
	return false # Godot requires an explicit typed tail after an infinite coroutine loop.

func scope_is_current() -> bool:
	return not _scope.is_empty() and _host.verify_original_map_loading_scope(_scope, _descriptor, str(_scope.transition_id), int(_scope.coordinator_generation), int(_scope.map_id))
func verify_actual_map_publication(publication: Dictionary, receipt: Dictionary) -> bool:
	return scope_is_current() and _host.verify_original_map_loading_publication(_scope,_descriptor,publication,receipt)

func exchange_original_map_leaf(operation: String, arguments: Array) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or _exchange_running: return {"status":"INVALID","error":"single_actual_Map_continuation"}
	_exchange_running = true
	_trace_begin(operation)
	var result: Dictionary = await _exchange_original_map_leaf(operation,arguments)
	_trace_finish(result)
	_exchange_running = false
	return result

func _exchange_original_map_leaf(operation: String, arguments: Array) -> Dictionary:
	if OS.get_thread_caller_id() != _owner: return {"status":"INVALID","error":"actual_Source_owner_required"}
	if operation not in OPS or not _job.is_empty() or not scope_is_current() or (_arrived and operation != "retire_claims"): return {"status":"INVALID","error":"actual_map_Loading_scope_or_single_continuation"}
	var trace_copy_started: int = Time.get_ticks_usec() if _trace_enabled else 0
	var copied: Dictionary = Graph.copy_and_seal(arguments)
	if _trace_enabled: _trace_job.argument_graph_copy_usec = Time.get_ticks_usec() - trace_copy_started
	if not copied.ok: return {"status":"INVALID","error":"map_live_argument"}
	while int(_budget.snapshot().open_scopes) != 0:
		_trace_step("budget_gate", "WAIT_OPEN_SCOPE")
		await _next_source_p()
	_trace_step("budget_gate", "READY")
	var reservation: Dictionary = _budget.reserve_live("map_loading:" + operation, _budget.LANE_NECESSARY, _reservation_usec)
	_trace_step("budget_reserve", "INVALID" if reservation.is_empty() else "READY")
	if reservation.is_empty(): return {"status":"INVALID","error":"map_budget_reservation"}
	var request := {"contract_id":"source.map.loading.request.v1", "owner_descriptor":_descriptor,
		"scope":_scope, "operation":operation, "arguments":copied.value, "reservation":reservation,
		"request_sequence":_serial + 1, "source_clock":_world.current_clock_frame()}
	var journal: RefCounted = _session.original_event_journal()
	while true:
		if not scope_is_current():
			if not _release_original_unaccepted_reservation(reservation): return {"status":"INVALID","error":"unaccepted_map_budget_release_failed"}
			return {"status":"INVALID","error":"actual_map_Loading_scope_retired_before_reserve"}
		# The getter is the actual current original entry. A phase label grants nothing.
		var site: Dictionary = _world.current_original_source_site()
		if site.is_empty() or site.get("world_context") != _world.current_world_identity():
			if not _release_original_unaccepted_reservation(reservation): return {"status":"INVALID","error":"unaccepted_map_budget_release_failed"}
			return {"status":"INVALID","error":"actual_map_Source_entry_required"}
		request.source_clock = _world.current_clock_frame()
		# This is a PEEK. No old unreserved ticket survives the next P await.
		var ticket: Dictionary = journal.next_original_event_identity()
		var event := {"kind":"original_world_presentation","operation":&"map_loading","arguments":[request],"source_site":site,"reply_identity":ticket,"ordinal":ticket.event_ordinal}
		var trace_event_started: int = Time.get_ticks_usec() if _trace_enabled and not _trace_job.has("first_event_graph_copy_usec") else 0
		var frozen_event: Dictionary = Graph.copy_and_seal(event)
		if trace_event_started != 0:
			_trace_job.first_event_graph_copy_usec = Time.get_ticks_usec() - trace_event_started
			if frozen_event.ok:
				# Once only. Godot Variant encoding size, not Native mailbox wire bytes.
				var trace_encoding_started: int = Time.get_ticks_usec()
				_trace_job.request_variant_bytes = var_to_bytes(request).size()
				_trace_job.request_variant_encoding_usec = Time.get_ticks_usec() - trace_encoding_started
		if not frozen_event.ok:
			if not _release_original_unaccepted_reservation(reservation): return {"status":"INVALID","error":"unaccepted_map_budget_release_failed"}
			return {"status":"INVALID","error":"map_event_not_plain"}
		event = frozen_event.value
		var reserved: Dictionary = _host.reserve_original_map_loading_event(ticket,event)
		_trace_step("reserve", str(reserved.get("status", "MISSING")))
		if reserved.get("status") == "INVALID":
			if not _release_original_unaccepted_reservation(reservation): return {"status":"INVALID","error":"unaccepted_map_budget_release_failed"}
			return reserved
		if reserved.get("status") == "READY":
			# No yield or gameplay callback between reservation and sole producer append.
			if not journal.append(event):
				_job = {"reserved_unaccepted":true,"identity":ticket,"request":request,"event":event,"reservation":reservation}
				while true:
					var cancelled: Dictionary = _host.cancel_unaccepted_original_map_loading_event(ticket)
					_trace_step("cancel", str(cancelled.get("status", "MISSING")))
					if cancelled.get("status") == "INVALID":
						_world.fault("map_unaccepted_slot_cancel_failed",cancelled)
						return cancelled # Retain slot/reservation; cannot report closure.
					if cancelled.get("status") == "READY": _job.native_cancelled = true; break
					await _next_source_p()
				if not _release_original_unaccepted_reservation(reservation): return {"status":"INVALID","error":"unaccepted_map_budget_release_failed"}
				_job = {}
				return {"status":"INVALID","error":"map_original_journal_append_failed"}
			_job = {"request":event.arguments[0],"identity":ticket,"event":event,"prefix":{},"accepted":true,"native_sealed":false,"settled":false}
			_serial += 1
			break
		if reserved.get("status") not in ["PENDING","BACKPRESSURE"]:
			_world.fault("map_native_reserve_status_invalid",reserved)
			return reserved
		await _next_source_p()
	while not _job.native_sealed:
		if _job.prefix.is_empty():
			var registered: Dictionary = _session.try_publish_original_event_prefix(_job.event)
			_trace_step("register", str(registered.get("status", "MISSING")))
			if registered.get("status")=="PENDING":
				await _next_source_p()
				continue
			if registered.get("status")!="READY":
				_world.fault("accepted_map_event_prefix_admission_failed",registered)
				return registered # Keep the accepted event and its reservation.
			_job.prefix=registered.prefix
		var accepted: Dictionary = _host.accept_original_map_loading_event(_job.identity,_job.event,_job.prefix)
		_trace_step("accept", str(accepted.get("status", "MISSING")))
		if accepted.get("status") == "READY": _job.native_sealed = true; break
		if accepted.get("status") != "PENDING":
			_world.fault("accepted_map_original_native_seal_failed",accepted)
			return accepted # Never cancel an appended/accepted Source event.
		await _next_source_p()
	while true:
		var polled: Dictionary = _host.poll_original_map_loading_event(_job.identity)
		_trace_poll(polled)
		_trace_step("poll", str(polled.get("status", "MISSING")))
		if polled.get("status") == "INVALID":
			_world.fault("accepted_map_reply_invalid", polled)
			return polled # Keep accepted obligation and reservation; no cancel/free.
		if polled.get("status") == "READY":
			var frame: Dictionary = _world.current_clock_frame()
			if frame.get("phase") != "P_GROUP" and not (frame.get("phase") == "P_CLOSE_SERVICE" and frame.get("closing_session") == true and frame.get("closing_process_publication",{}).get("phase") == "NODE_PROCESS_SERVICE"):
				_trace_step("settle_gate", "WAIT_PHASE")
				await _next_source_p()
				continue
			if int(_budget.snapshot().open_scopes) != 0:
				_trace_step("settle_gate", "WAIT_OPEN_SCOPE")
				await _next_source_p()
				continue
			_trace_step("settle_gate", "READY")
			# Frozen actual native observation and actual Main elapsed, not time at retry.
			if not _job.settled:
				var actual: Dictionary = polled.reply
				var charged: Dictionary = _budget.settle_live(reservation, _job.identity, actual,
					int(polled.native_received_usec), int(frame.epoch))
				_trace_step("budget_settle", "INVALID" if charged.is_empty() else "READY")
				if charged.is_empty(): return {"status":"INVALID","error":"actual_map_budget_settlement"}
				_job.settled = true
				_job.settlement = charged
				_job.reply = actual
				if not _session.original_event_journal().consume_normal_receipt(actual.native_main_prefix_receipt): return {"status":"INVALID","error":"actual_map_prefix_receipt"}
			var committed: Dictionary = _host.settle_original_map_loading_event_status(_job.identity,_job.settlement)
			_trace_step("settle", str(committed.get("status", "MISSING")))
			if committed.get("status") == "INVALID": return committed
			if committed.get("status") != "SETTLED":
				await _next_source_p()
				continue
			var actual_retired: bool = _host.retire_original_map_loading_event(_job.identity, _job.reply)
			_trace_step("retire", "READY" if actual_retired else "PENDING_OR_REJECTED")
			if actual_retired:
				if not _retire_original_settlement(reservation): return {"status":"INVALID","error":"map_actual_settlement_retirement_failed"}
				var result: Dictionary = _job.reply.result
				if operation == "finish_visual" and result.get("ok") == true:
					_last_finish = {"identity":_job.identity,"reply":_job.reply,"scope":_scope}
				_job = {}
				return result
		await _next_source_p()
	return {"status":"INVALID","error":"unreachable_map_reply_loop_exit"}

func _release_original_unaccepted_reservation(reservation: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	# Actual side effect survives release builds. A failed bookkeeping release
	# retains the real reservation as a Source close obligation and faults.
	var released: bool = _budget.release_unaccepted(reservation)
	if not released:
		_job["unaccepted_budget_release_failed"] = true
		_job["reservation"] = reservation.duplicate(true)
		_world.fault("map_unaccepted_budget_release_failed",{"reservation_id":reservation.get("reservation_id",0)})
	return released

func _retire_original_settlement(reservation: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner: return false
	# Caller reached here only after actual Native retirement. Keep that fact
	# even if Source budget bookkeeping cannot be retired; do not poll/replay it.
	_job.native_retired = true
	var retired: bool = _budget.retire_settlement(int(reservation.reservation_id))
	if not retired:
		_world.fault("map_actual_settlement_retirement_failed",{"reservation_id":reservation.reservation_id,"identity":_job.identity})
	return retired

func close_loading_scope() -> bool:
	if _exchange_running or not _job.is_empty() or _scope.is_empty(): return false
	# The producer must inspect real claims, pins and in-flight command retirement.
	var result: Dictionary = await _admission.release_original_map_loading_boundary(_scope)
	if result.get("status") != "READY": return false
	_scope = {}
	_last_finish = {}; _arrived = false
	# Retain immutable old scope/receipts until the real Main release above.
	# Only the next scope uses the current routing descriptor.
	_descriptor = _descriptor.duplicate(true)
	_descriptor.world_context = _world.current_world_identity()
	return true

func capture_original_map_arrival_boundary() -> Dictionary:
	if OS.get_thread_caller_id() != _owner or _arrived or not _job.is_empty() or _last_finish.is_empty() or not scope_is_current(): return {}
	if _last_finish.scope != _scope or _last_finish.reply.get("result",{}).get("ok") != true: return {}
	return Graph.copy_and_seal({"loading_scope":_scope,"finish_identity":_last_finish.identity,"finish_reply":_last_finish.reply}).value

func validate_original_map_arrival_transaction(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or _arrived or not _job.is_empty() or _last_finish.is_empty(): return false
	return transaction.get("loading_scope") == _scope and transaction.get("finish_identity") == _last_finish.identity and transaction.get("finish_reply") == _last_finish.reply and transaction.get("before_world") == _descriptor.world_context

func commit_original_map_arrival_transaction(transaction: Dictionary) -> bool:
	if _arrived: return transaction == _arrival_transaction
	if not validate_original_map_arrival_transaction(transaction): return false
	_arrival_transaction = transaction
	_arrived = true
	return true

# All trace state is scalar, short text, or bounded counters. It never owns a
# request/event/prefix/reply graph, and is discarded at this exchange's return.
func _trace_begin(operation: String) -> void:
	if not _trace_enabled: return
	var now: int = Time.get_ticks_usec()
	var frame: Dictionary = _world.current_clock_frame()
	_trace_job = {"operation":operation,"request_sequence":_serial + 1,
		"started_usec":now,"last_emit_usec":now,"start_epoch":int(frame.get("epoch",-1)),
		"stage":"begin","stage_started_usec":now,"stage_start_epoch":int(frame.get("epoch",-1))}
	_trace_job.map_id = int(_scope.get("map_id",-1))
	_trace_job.coordinator_generation = int(_scope.get("coordinator_generation",-1))

func _trace_step(stage: String, status: String) -> void:
	if not _trace_enabled or _trace_job.is_empty(): return
	var now: int = Time.get_ticks_usec()
	# Even an unexpected Native status cannot create unbounded diagnostic keys.
	var bounded_status: String = status if status in ["READY","PENDING","INVALID","MISSING","BACKPRESSURE","SETTLED","WAIT_OPEN_SCOPE","WAIT_PHASE","PENDING_OR_REJECTED"] else "OTHER"
	var key: String = "count_" + stage + "_" + bounded_status
	_trace_job[key] = int(_trace_job.get(key,0)) + 1
	if not _trace_job.has("first_" + stage + "_epoch"):
		_trace_job["first_" + stage + "_epoch"] = int(_world.current_clock_frame().get("epoch",-1))
	if _trace_job.stage != stage:
		_trace_job["elapsed_" + str(_trace_job.stage) + "_usec"] = int(_trace_job.get("elapsed_" + str(_trace_job.stage) + "_usec",0)) + now - int(_trace_job.stage_started_usec)
		_trace_job.stage = stage
		_trace_job.stage_started_usec = now
		_trace_job.stage_start_epoch = int(_world.current_clock_frame().get("epoch",-1))
	_trace_job.last_status = status.left(32)
	if now - int(_trace_job.last_emit_usec) >= 5000000: _trace_emit(false, "")

func _trace_poll(polled: Dictionary) -> void:
	if not _trace_enabled or _trace_job.is_empty() or polled.get("status") != "READY" or _trace_job.has("native_received_usec"): return
	# These are the actual Native/Main observations, sampled once per reply.
	_trace_job.event_ordinal = int(_job.get("identity",{}).get("event_ordinal",-1))
	_trace_job.fixed_prefix_through = int(_job.get("prefix",{}).get("through_ordinal",-1))
	for field: String in ["actual_queue_residence_usec","actual_dispatch_wait_usec","native_received_usec","native_s_poll_epoch","late_result_count"]:
		if polled.get(field) is int: _trace_job[field] = polled[field]
	if polled.get("deadline_status") is String: _trace_job.deadline_status = str(polled.deadline_status).left(32)
	var reply: Dictionary = polled.get("reply",{})
	for field: String in ["started_usec","finished_usec","actual_Main_CPU_usec"]:
		if reply.get(field) is int: _trace_job["main_" + field] = reply[field]
	if reply.get("started_usec") is int and reply.get("finished_usec") is int:
		_trace_job.actual_Main_elapsed_usec = int(reply.finished_usec) - int(reply.started_usec)
	if reply.get("finished_usec") is int and polled.get("native_received_usec") is int:
		_trace_job.reply_observation_delay_usec = int(polled.native_received_usec) - int(reply.finished_usec)

func _trace_finish(result: Dictionary) -> void:
	if not _trace_enabled or _trace_job.is_empty(): return
	_trace_emit(true, str(result.get("status", "READY" if result.get("ok") == true else "RESULT_NOT_OK")))
	_trace_job = {}

func _trace_emit(completed: bool, result_status: String) -> void:
	var now: int = Time.get_ticks_usec()
	_trace_job.last_emit_usec = now
	var observation: Dictionary = _trace_job.duplicate(false)
	var frame: Dictionary = _world.current_clock_frame()
	observation.completed = completed
	observation.result_status = result_status.left(32)
	observation.elapsed_usec = now - int(_trace_job.started_usec)
	observation.epoch = int(frame.get("epoch",-1))
	observation.epoch_delta = observation.epoch - int(_trace_job.start_epoch)
	observation.phase = str(frame.get("phase", "")).left(32)
	observation.current_stage_elapsed_usec = now - int(_trace_job.stage_started_usec)
	observation.current_stage_epoch_delta = observation.epoch - int(_trace_job.stage_start_epoch)
	observation.open_scopes = int(_budget.snapshot().get("open_scopes",-1))
	if not _job.is_empty():
		observation.event_ordinal = int(_job.get("identity",{}).get("event_ordinal",-1))
		observation.fixed_prefix_through = int(_job.get("prefix",{}).get("through_ordinal",-1))
		observation.native_sealed = _job.get("native_sealed",false) == true
		observation.settled = _job.get("settled",false) == true
	# status() is sampled only at the existing 5s/return boundary, never per P.
	var native: Dictionary = _host.status()
	for field: String in ["serviced_epoch","pending_epochs","unsettled_original_published_prefixes","original_main_applied_prefix","input_queue_size","deadline_misses","clock_overruns","late_starts"]:
		if native.get(field) is int: observation["native_" + field] = native[field]
	print("HC_SOURCE_MAP_EXCHANGE ",JSON.stringify(observation))
