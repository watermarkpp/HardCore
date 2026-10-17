extends RefCounted
## One admitted application call on the existing Session/Native resource lane.
## No own clock, resource scheduler, budget, prefix acquirer or gameplay owner.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _binding: WeakRef
var _pending: Dictionary = {}
var _consumer_key := ""
var _registered := false
func owner_thread_id() -> int: return _owner
func configure_owner(session: RefCounted, binding: RefCounted) -> bool:
	if _owner == OS.get_main_thread_id() or _session != null or session == null or session.get_script() != preload("res://scripts/gameplay/source/source_session.gd") or session.owner_thread_id() != _owner: return false
	if binding == null or binding.owner_thread_id() != _owner or not binding.get("_session") is WeakRef or binding.get("_session").get_ref() != session: return false
	_session = weakref(session); _binding = weakref(binding)
	_consumer_key = "source_application:%d" % get_instance_id()
	return true
func _bound() -> bool:
	return OS.get_thread_caller_id() == _owner and _session != null and _session.get_ref() != null and _binding != null and _binding.get_ref() != null
func _invalid(error: String) -> Dictionary: return {"success":false,"status":"INVALID","error":error}
func _site() -> Dictionary:
	if not _bound(): return {}
	var session: RefCounted = _session.get_ref()
	var site: Dictionary = session.feature_resource_session().primitives.current_original_source_site()
	var frame: Dictionary = session.actual_original_clock_frame()
	if site.get("bootstrap") != false or site.get("clock_epoch",0) <= 0 or str(site.get("domain","")) != "P" or site.get("clock_epoch") != frame.get("epoch"): return {}
	if frame.get("phase") not in ["P_GROUP","P_CLOSE_SERVICE"]: return {}
	if frame.get("closing_session") == true and frame.get("source_boundary") != "NODE_PROCESS_SERVICE": return {}
	return site
func poll_or_submit(operation: String, arguments: Array, publication: Dictionary) -> Dictionary:
	if not _bound() or not preload("res://scripts/gameplay/world/world_source_application_contract.gd").accepts(operation,arguments): return _invalid("actual_application_owner_and_fixed_operation_required")
	var session: RefCounted = _session.get_ref()
	var budget: RefCounted = session.original_frame_budget()
	if not _pending.is_empty():
		if _pending.operation != operation or _pending.arguments != arguments: return {"status":"BUSY","error":"original_application_call_still_held"}
		return _service_pending()
	var site: Dictionary = _site()
	if site.is_empty(): return _invalid("actual_positive_Source_P_application_site_required")
	if budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active(): return {"status":"BUSY","error":"application_scalar_scope_must_close_before_reservation"}
	var target: Variant = publication.get("main_service_reference")
	if not target is Dictionary or target.get("contract_id") != "feature.main.reference.v1" or publication.get("world_context") != site.world_context: return _invalid("actual_current_Main_application_reference_required")
	var settings: Dictionary = session.get("_boot").get("project_settings",{})
	var reservation: Variant = settings.get("hardcore/performance/frame_progress_budget_usec")
	if not reservation is int or reservation < 0: return _invalid("actual_captured_progress_budget_required")
	if not _registered:
		if not session.register_live_resource_consumer(_consumer_key,self): return _invalid("same_Session_application_consumer_registration_failed")
		_registered = true
	var cleanup: bool = operation in ["release_map_scope","panel_state","map_warm_state","world_view_exit_state","actor_view_free_state"]
	var request := {"protocol":"hardcore.streaming.live_primitives.v1","site":site.duplicate(true),"op":"feature.object_call","args":[target,"source_application_call",[operation,arguments]],"main_prefix":session.freeze_original_main_prefix(),"deadline_usec":site.deadline_usec,"order_key":_consumer_key,"dependencies":[],"priority":2 if cleanup else 0,"cleanup":cleanup}
	# The actual captured progress allowance reserves this same Session lane.
	# Actual Main elapsed cost is settled once, including reported overruns.
	var accepted: Dictionary = session.submit_live_resource(request,"source_application",2,int(reservation),_consumer_key)
	if accepted.get("status") in ["BUSY","BACKPRESSURE"]:
		if not session.unregister_live_resource_consumer(_consumer_key,self): return _invalid("unaccepted_application_consumer_detach_failed")
		_registered = false
		return accepted
	if accepted.get("status") != "PENDING" or not accepted.get("request") is Dictionary: return _invalid("actual_Native_application_admission_rejected")
	_pending = {"operation":operation,"arguments":arguments.duplicate(true),"request":accepted.request,"identity":accepted.request.identity,"applied":false,"consumed":false}
	return {"status":"PENDING","identity":_pending.identity}
func _service_pending() -> Dictionary:
	var session: RefCounted = _session.get_ref()
	var budget: RefCounted = session.original_frame_budget()
	if _site().is_empty() or budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active(): return {"status":"BUSY"}
	var owns_phase: bool = not session.actual_original_resource_commit_phase_active()
	if owns_phase and not session.begin_resource_commit_phase(int(session.actual_original_clock_frame().source_process_frame)): return {"status":"BUSY"}
	var committed: Dictionary = session.commit_live_resource(_pending.identity)
	if owns_phase and not session.finish_resource_commit_phase(): return _invalid("actual_application_commit_phase_finish_failed")
	if committed.get("status") in ["PENDING","BUSY"]: return {"status":"PENDING","identity":_pending.identity}
	if committed.get("status") != "SETTLED" or _pending.get("applied") != true: return _invalid("actual_application_commit_failed")
	_pending.consumed = true
	if not session.original_transport_obligations_released(_pending.identity) or not session.retire_live_resource(_pending.identity): return {"status":"PENDING","identity":_pending.identity}
	var result: Dictionary = _pending.result
	_pending = {}
	if not session.unregister_live_resource_consumer(_consumer_key,self): return _invalid("actual_application_consumer_retirement_failed")
	_registered = false
	return result
func commit_original_live_feature_reply(identity: Dictionary, reply: Dictionary) -> Dictionary:
	if not _bound() or _pending.is_empty() or identity != _pending.identity or reply.get("request") != _pending.request or reply.get("executed") != true or not reply.get("result") is Dictionary: return _invalid("actual_application_receipt_identity_required")
	if _pending.applied: return {"success":true}
	var session: RefCounted = _session.get_ref()
	var primitives: RefCounted = session.feature_resource_session().primitives
	if not _pending.get("side_facts_imported",false):
		var imported: Dictionary = primitives.import_actual_original_live_cleanup_side_facts(reply)
		if imported.get("success") != true: return imported
		_pending.side_facts_imported = true
	if not _pending.has("decoded_result"):
		_pending.decoded_result = primitives.decode_original_source_value(reply.result)
	var result: Variant = _pending.decoded_result
	if not result is Dictionary: return _invalid("actual_plain_application_result_required")
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary = graph.capture(result,true,false)
	if captured.get("success") != true: return _invalid("application_result_contains_Main_objects")
	_pending.result = captured.value; _pending.applied = true
	return {"success":true}
func original_ticket_lease_obligations_retired(identity: Dictionary) -> bool:
	return _bound() and not _pending.is_empty() and _pending.identity == identity and _pending.applied and _pending.consumed and _session.get_ref().original_transport_obligations_released(identity)
func live_operations_drained() -> bool: return OS.get_thread_caller_id() == _owner and _pending.is_empty()
func has_accepted_call() -> bool: return not _pending.is_empty()
func has_accepted_call_for(operation: String, arguments: Array) -> bool:
	return not _pending.is_empty() and _pending.operation == operation and _pending.arguments == arguments
