extends RefCounted
## Main executes one admitted cold call without waiting for Source computation.
## Native reserves its result slot. A held prefix/body is never replayed when
## another Main service turn is needed to finish the same accepted obligation.
const Feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Streaming := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
const Prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
var _host: Object
var _prefix: RefCounted
var _feature: RefCounted
var _streaming: RefCounted
var _generation := 0
var _held: Dictionary = {}
var _ack: Dictionary = {}
var _reply: Dictionary = {}
var _confirmed := false
var _completed := 0
var _published: Dictionary = {}
var _published_completed := 0
var _live_feature_bound := false
var _live_feature_closed := false
var _live_streaming_bound := false
var _live_result_submitted := false
var _live_held: Dictionary = {}
var _live_acknowledged := false
var _live_execution: Dictionary = {}
var _live_completed := 0
var _fault: Dictionary = {}
var _actual_transport: WeakRef
var _terminal: Dictionary = {}

func configure_main(host: Object, prefix: RefCounted, feature: RefCounted, generation: int) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host != null or generation <= 0: return false
	if host == null or not host.is_class("HardCoreSimulationHost") or prefix == null or prefix.get_script() != Prefix or prefix.get("_host") != host: return false
	if feature == null or feature.get_script() != Feature or feature.get("_generation") != generation: return false
	var validator: Callable = feature.get("_validate")
	if not validator.is_valid() or validator.get_object() != host or validator.get_method() != &"validate_original_primitive_ticket": return false
	var facade: Variant = feature.get("_facade")
	if not facade is Node or not is_instance_valid(facade) or not facade.is_inside_tree(): return false
	_host = host; _prefix = prefix; _feature = feature; _generation = generation
	return true

func bind_actual_original_streaming(executor: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _streaming != null or not _held.is_empty(): return false
	if executor == null or executor.get_script() != Streaming or executor.get("_configured") != true or executor.get("_bridge_generation") != _generation: return false
	var validator: Callable = executor.get("_validate_ticket")
	if not validator.is_valid() or validator.get_object() != _host or validator.get_method() != &"validate_original_primitive_ticket": return false
	_streaming = executor
	return true

func service_original_main_resources() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null: return {"status":"INVALID","error":"actual_Main_resource_owner_required"}
	if not _fault.is_empty(): return _fault.duplicate(true)
	var progress := false
	# Each lane uses its existing held cursor. These calls do not await, spin,
	# acquire a competing prefix, or replay a completed physical operation.
	var cold: Dictionary = service_original_cold_resources()
	if cold.get("status") not in ["PENDING","SERVICED"]: return cold
	progress = cold.status == "SERVICED"
	if _live_feature_bound or _live_streaming_bound:
		var live: Dictionary = service_original_live_resources()
		if live.get("status") not in ["PENDING","SERVICED"]: return live
		progress = progress or live.status == "SERVICED"
	var published: Dictionary = service_original_main_publications()
	if published.get("status") not in ["PENDING","SERVICED"]: return published
	progress = progress or published.status == "SERVICED"
	# A map result can become sendable after an ACK even when no new packet
	# arrives. Keep using the one dispatcher's accepted reply ledger.
	var replies: Dictionary = _prefix.flush_original_main_replies()
	if replies.get("status") not in ["PENDING","READY"]: return _fail("actual_Main_reply_service_failed",replies)
	var state: Dictionary = _host.status()
	if state.get("close_requested") == true and state.get("source_model_close_completed") == true:
		# The actual Source model has finished its business and STOP receipt.
		# Final Main vault work happens here, before Native can become quiescent;
		# waiting until after join would deadlock the two real lifetime owners.
		if _live_feature_bound and not _live_feature_closed:
			var feature_close: Dictionary = service_original_live_feature_retirement()
			if feature_close.get("status") not in ["READY","PENDING"]: return feature_close
			progress = progress or feature_close.status == "READY"
		if _live_streaming_bound and state.get("live_resource_vault_closed") != true:
			var vault_close: Dictionary = _host.finalize_original_main_resource_vault()
			if vault_close.get("status") not in ["READY","PENDING"]: return _fail("actual_final_Main_resource_vault_close_failed",vault_close)
			progress = progress or vault_close.status == "READY"
	return {"status":"SERVICED" if progress else "PENDING"}

func service_actual_original_main_transport(host: Object, prefix: RefCounted, transport: RefCounted) -> Dictionary:
	if host != _host or not is_same(prefix,_prefix) or transport == null or transport.get_script() != preload("res://scripts/gameplay/source/main_session_transport.gd") or not is_same(transport.get("_main_pump"),self) or transport.get("_host") != _host or not is_same(transport.get("_prefix"),_prefix): return {"status":"INVALID","error":"actual_same_Main_transport_required"}
	if _actual_transport == null: _actual_transport = weakref(transport)
	elif not is_same(_actual_transport.get_ref(),transport): return {"status":"INVALID","error":"actual_Main_transport_identity_changed"}
	return service_original_main_resources()

func actual_original_main_terminal_receipt(host: Object, prefix: RefCounted, session_id: int, warm_io: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or host != _host or not is_same(prefix,_prefix) or session_id <= 0 or _actual_transport == null or _actual_transport.get_ref() == null: return {"success":false,"status":"INVALID","error":"actual_bound_Main_terminal_owner_required"}
	var transport: RefCounted = _actual_transport.get_ref()
	var io: RefCounted = transport.get("_io")
	if transport.get("_session_id") != session_id or transport.get("_state") != "CLOSING" or io == null or io.get_script() != preload("res://scripts/gameplay/source/main_source_closing_io_producer.gd") or io.get("_session_id") != session_id or not is_same(io.get("_session_pump"),self) or not is_same(io.get("_session_transport"),transport) or not is_same(io.get("_session_prefix"),_prefix): return {"success":false,"status":"INVALID","error":"actual_same_Session_IO_terminal_owner_required"}
	if not _terminal.is_empty(): return _terminal
	if not _fault.is_empty() or not _prefix.failure().is_empty(): return {"success":false,"status":"INVALID","error":"actual_Main_transport_fault_retained"}
	if not _held.is_empty() or not _published.is_empty() or not _live_held.is_empty() or not _reply.is_empty() or not _ack.is_empty() or _prefix.has_pending(): return {"success":false,"status":"PENDING"}
	# These are fresh observations from the same physical owners. A caller's
	# READY bit or a zero local queue cannot stand in for Source shutdown.
	var actual_warm: Dictionary = io.inspect_actual_original_main_warm_io()
	if warm_io != actual_warm or actual_warm.get("status") != "READY": return {"success":false,"status":"PENDING"}
	var actual_io: Dictionary = io.capture_actual_original_session_io()
	if actual_io.get("status") != "BUSINESS_DRAINED" or actual_io.get("owner_session_id") != session_id or actual_io.get("bridge_generation") != _generation: return {"success":false,"status":"PENDING"}
	var native: Dictionary = _host.status()
	for key: String in ["close_requested","source_model_close_completed","live_resource_vault_closed","live_feature_closed","map_owner_closed","source_admission_scopes_quiescent","caster_reply_obligations_quiescent","close_quiescent","join_complete"]:
		if native.get(key) != true: return {"success":false,"status":"PENDING"}
	for key: String in ["accepted_live_resource_obligations","accepted_worker_group_obligations","unsettled_original_published_prefixes","input_queue_size"]:
		if native.get(key) != 0: return {"success":false,"status":"PENDING"}
	if native.get("running") != false or native.get("original_primitive_in_flight") != false: return {"success":false,"status":"PENDING"}
	_terminal = {"success":true,"status":"READY","receipt":{"contract_id":"hardcore.source.Main_terminal.v1","owner_session_id":session_id,"bridge_generation":_generation,"actual_main_pump_id":get_instance_id(),"actual_prefix_id":_prefix.get_instance_id(),"actual_io_producer_id":io.get_instance_id(),"actual_main_process_frame":Engine.get_process_frames(),"actual_native_status":native,"actual_main_io":actual_io,"actual_warm_io":actual_warm}}
	return _terminal

func service_original_cold_resources() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null: return {"status":"INVALID","error":"actual_Main_resource_owner_required"}
	if not _fault.is_empty(): return _fault.duplicate(true)
	if not _published.is_empty() or not _live_held.is_empty(): return {"status":"PENDING"}
	if _held.is_empty():
		var packet: Dictionary = _host.acquire_pending_original_primitive()
		if packet.is_empty(): return {"status":"PENDING"}
		_held = packet
		if packet.get("channel") not in ["resource","world"]: return _fail("actual_original_cold_channel_required")
		if not packet.get("identity") is Dictionary or packet.identity.get("bridge_generation") != _generation or not packet.get("request") is Dictionary or packet.request.get("identity") != packet.identity or packet.get("main_prefix") != packet.request.get("main_prefix"): return _fail("actual_Native_resource_packet_identity")
		if packet.channel == "resource" and not str(packet.request.get("operation","")).begins_with("feature.") and _streaming == null: return _fail("actual_streaming_executor_missing")
	if _ack.is_empty():
		var applied: Dictionary = _prefix.apply_prefix(_held.main_prefix)
		if applied.get("status") in ["BUSY","PENDING"]: return {"status":"PENDING"}
		if applied.get("status") != "APPLIED" or applied.get("main_prefix") != _held.main_prefix: return _fail("actual_resource_prefix_not_applied",applied)
		var candidate := {"bridge_generation":_held.main_prefix.bridge_generation,"journal_generation":_held.main_prefix.journal_generation,"through_ordinal":_held.main_prefix.through_ordinal,"applied":true,"main_prefix":_held.main_prefix}
		if not _host.ack_original_main_prefix(_held.identity,candidate): return _fail("actual_resource_Native_prefix_ack_rejected")
		_ack = candidate.duplicate(true)
		_ack.erase("main_prefix")
	if _reply.is_empty():
		# The real executor claims the Native execution ticket exactly once.
		# A second pump-side validation would spend that claim before the body.
		# Streaming's standalone legacy counter is not the Session-wide sequence.
		# Its existing shared cold entry claims this exact Native global ticket.
		if _held.channel == "world": _reply = _execute_original_world_primitive(_held.request)
		else: _reply = _feature.execute(_held.request) if str(_held.request.operation).begins_with("feature.") else _streaming.execute_claimed_original_cold_primitive(_held.request)
		if _reply.get("executed") != true or _reply.get("request") != _held.request: return _fail("actual_resource_body_not_executed",_reply)
	if not _confirmed:
		# An original owner-header body may install the map executor used here;
		# Source is still parked until the actual result is submitted below.
		if not _prefix.confirm_prefix_acknowledged(_held.main_prefix,_ack): return _fail("actual_resource_local_prefix_confirmation_rejected")
		_confirmed = true
	if not _host.submit_original_primitive_result(_held.identity,_reply): return _fail("actual_resource_result_submission_rejected")
	var identity: Dictionary = _held.identity.duplicate(true)
	_completed += 1
	_held = {}; _ack = {}; _reply = {}; _confirmed = false
	return {"status":"SERVICED","identity":identity}

func _execute_original_world_primitive(request: Dictionary) -> Dictionary:
	# These are the exact original cold Main global operations. Gameplay LIVE
	# continues to draw from SourceSession's adopted native PCG; this entry
	# neither captures it again nor substitutes a second random generator.
	if request.get("protocol") != "hardcore.world.primitives.v1" or not request.get("arguments") is Array: return {}
	var op := StringName(request.get("operation",&""))
	if op not in preload("res://scripts/gameplay/world/world_original_primitive_port.gd").GLOBAL_OPERATIONS: return {}
	if not _host.validate_original_primitive_ticket(request,&"original_world_primitive"): return {}
	# Native already checked exact opcode arity/types and the current prefix.
	var args: Array = request.arguments
	var started := Time.get_ticks_usec()
	var result: Variant
	match op:
		&"global_randi": result = randi()
		&"global_randi_range": result = randi_range(args[0],args[1])
		&"global_randf": result = randf()
		&"global_randf_range": result = randf_range(args[0],args[1])
		&"global_seed": seed(args[0])
		&"global_randomize": randomize()
	var finished := Time.get_ticks_usec()
	return {"request":request,"executed":true,"disposition":&"executed_late" if finished > int(request.site.deadline_usec) else &"executed",
		"result":result,"started_usec":started,"finished_usec":finished,"completed_prefix_ordinal":1}

func service_original_main_publications() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null: return {"status":"INVALID","error":"actual_Main_publication_owner_required"}
	if not _fault.is_empty(): return _fault.duplicate(true)
	# The one consumer retains an exact partial cursor. Never switch its active
	# claim to another cold/ordinary prefix while an original write is pending.
	if not _held.is_empty() or not _live_held.is_empty(): return {"status":"PENDING"}
	if _published.is_empty():
		var pending: Dictionary = _host.inspect_next_original_published_prefix()
		if pending.get("status") in ["BUSY","PENDING"]: return {"status":"PENDING"}
		if pending.get("status") != "READY" or not pending.get("prefix") is Dictionary or pending.prefix.get("bridge_generation") != _generation: return _fail("actual_published_prefix_packet_invalid",pending)
		_published = pending.prefix
	var applied: Dictionary = _prefix.apply_prefix(_published)
	if applied.get("status") in ["BUSY","PENDING"]: return {"status":"PENDING"}
	if applied.get("status") != "APPLIED" or applied.get("main_prefix") != _published: return _fail("actual_published_prefix_not_applied",applied)
	var ack := {"bridge_generation":_published.bridge_generation,"journal_generation":_published.journal_generation,"through_ordinal":_published.through_ordinal,"applied":true}
	if not _host.ack_published_original_main_prefix(_published,ack): return _fail("actual_published_prefix_Native_ack_rejected")
	if not _prefix.confirm_prefix_acknowledged(_published,ack): return _fail("actual_published_prefix_local_confirmation_rejected")
	_published_completed += 1
	_published = {}
	return {"status":"SERVICED","native_main_prefix_receipt":ack}

func bind_actual_original_live_feature() -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _live_feature_bound: return false
	# Native verifies this exact loaded Script, instance and physical vault.
	if not _host.bind_live_original_feature_main_executor(_feature,_feature.get_script().get_source_code().sha256_text()): return false
	_live_feature_bound = true
	return true

func service_original_live_feature_resources() -> Dictionary:
	return service_original_live_resources()

func bind_actual_original_live_streaming(executor: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _live_streaming_bound or not _live_held.is_empty(): return false
	if executor == null or executor.get_script() != Streaming or executor.get("_configured") != true or executor.get("_bridge_generation") != _generation: return false
	if _streaming != null and not is_same(_streaming,executor): return false
	# The exact existing executor binds itself to Native, which verifies the
	# loaded source and retains the genuine physical vault for transfer/close.
	if not executor.configure_live_main(_host,executor.get_script().get_source_code().sha256_text()): return false
	_streaming = executor; _live_streaming_bound = true
	return true

func service_original_live_resources() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or (not _live_feature_bound and not _live_streaming_bound): return {"status":"INVALID","error":"actual_bound_Main_live_resource_owner_required"}
	if not _fault.is_empty(): return _fault.duplicate(true)
	if not _held.is_empty() or not _published.is_empty(): return {"status":"PENDING"}
	if _live_held.is_empty():
		# Also progresses actual Native Feature ownership-transfer receipts when
		# there is no new packet. No Main wait, spinning or Source join occurs.
		_live_held = _host.acquire_pending_live_original_resource()
		if _live_held.is_empty(): return {"status":"PENDING"}
		if _live_held.get("channel") != "resource_live" or not _live_held.get("request") is Dictionary: return _fail("actual_live_resource_packet_required")
		var request: Dictionary = _live_held.request
		if request.get("identity") != _live_held.get("identity") or request.identity.get("bridge_generation") != _generation: return _fail("actual_live_resource_identity_missing")
	var feature_operation: bool = str(_live_held.request.get("op","")).begins_with("feature.")
	if feature_operation and (not _live_feature_bound or _live_feature_closed): return _fail("actual_live_Feature_executor_missing")
	if not feature_operation and not _live_streaming_bound: return _fail("actual_live_streaming_executor_missing")
	var prefix: Dictionary = _live_held.request.main_prefix
	if not _live_acknowledged:
		var applied: Dictionary = _prefix.apply_prefix(prefix)
		if applied.get("status") in ["BUSY","PENDING"]: return {"status":"PENDING"}
		if applied.get("status") != "APPLIED" or applied.get("main_prefix") != prefix: return _fail("actual_live_Feature_prefix_not_applied",applied)
		if not _host.ack_live_original_main_prefix(_live_held.identity,prefix): return _fail("actual_live_Feature_prefix_Native_ack_rejected")
		_live_acknowledged = true
	if _live_execution.is_empty():
		# This existing Native entry uniquely claims, executes, validates and
		# submits the genuine Feature reply and physical owner obligations.
		if feature_operation:
			_live_execution = _host.execute_pending_live_original_feature(_live_held)
			if _live_execution.get("status") in ["PENDING","BUSY"]:
				_live_execution = {}
				return {"status":"PENDING"}
			if _live_execution.get("status") != "READY" or _live_execution.get("identity") != _live_held.identity: return _fail("actual_live_Feature_execution_not_completed",_live_execution)
		else:
			_live_execution = _streaming.execute_live_original_primitive(_live_held.request)
			if _live_execution.get("executed") != true or _live_execution.get("request") != _live_held.request: return _fail("actual_live_streaming_body_not_executed",_live_execution)
	if not _live_result_submitted:
		if not feature_operation and not _host.submit_live_original_resource_result(_live_held.identity,_live_execution): return _fail("actual_live_streaming_result_rejected")
		var ack := {"bridge_generation":prefix.bridge_generation,"journal_generation":prefix.journal_generation,"through_ordinal":prefix.through_ordinal,"applied":true}
		if not _prefix.confirm_prefix_acknowledged(prefix,ack): return _fail("actual_live_resource_prefix_local_confirmation_rejected")
		_live_result_submitted = true
	if not feature_operation:
		# Submission is not transfer. Keep this actual execution pinned across
		# service turns until Source settlement allows Native to retire/transfer
		# its exact physical obligations; never replay the resource operation.
		var transferred: Dictionary = _streaming.transfer_current_live_obligations()
		if transferred.get("status") == "PENDING": return {"status":"PENDING"}
		if transferred.get("status") != "TRANSFERRED": return _fail("actual_live_streaming_transfer_rejected",transferred)
	var identity: Dictionary = _live_held.identity.duplicate(true)
	_live_completed += 1
	_live_held = {}; _live_execution = {}; _live_acknowledged = false; _live_result_submitted = false
	return {"status":"SERVICED","identity":identity}

func service_original_live_feature_retirement() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or not _live_feature_bound: return {"status":"INVALID","error":"actual_bound_Main_live_Feature_required"}
	if not _fault.is_empty(): return _fault.duplicate(true)
	if _live_feature_closed: return {"status":"READY","actual_native_Feature_Main_closed":true,"bridge_generation":_generation}
	if not _held.is_empty() or not _published.is_empty() or not _live_held.is_empty() or _prefix.has_pending(): return {"status":"PENDING"}
	# Native independently proves close requested, accepted operations retired,
	# physical transfers complete and the real vault's close_main contract.
	if not _host.certify_live_original_feature_main_closed(): return {"status":"PENDING"}
	_live_feature_closed = true
	return {"status":"READY","actual_native_Feature_Main_closed":true,"bridge_generation":_generation}

func inspect_actual_original_pending_resources() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID"}
	# This is a local IO observation, never a terminal/quiescence proof.
	return {"status":"READY" if _fault.is_empty() else "INVALID","held":not _held.is_empty(),"executed":not _reply.is_empty(),"completed":_completed,"published_held":not _published.is_empty(),"published_completed":_published_completed,"live_held":not _live_held.is_empty(),"live_completed":_live_completed,"live_feature_closed":_live_feature_closed,"fault":_fault.duplicate(true),
		"actual_cold_prefix_through":_held.get("main_prefix",{}).get("through_ordinal",-1),"actual_published_prefix_through":_published.get("through_ordinal",-1),"actual_live_prefix_through":_live_held.get("request",{}).get("main_prefix",{}).get("through_ordinal",-1),"actual_live_prefix_acknowledged":_live_acknowledged,"actual_live_result_submitted":_live_result_submitted,"actual_live_operation":str(_live_held.get("request",{}).get("op",""))}

func _fail(reason: String, details: Dictionary = {}) -> Dictionary:
	_fault = {"status":"INVALID","error":reason,"details":details.duplicate(true)}
	return _fault.duplicate(true)
