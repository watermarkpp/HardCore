extends RefCounted
## Accepted RPC association only. The original Coordinator remains the sole
## preparation/application/retirement scheduler and owns every real cursor.
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _coordinator: WeakRef
var _budget: RefCounted
var _policy: Dictionary={}
var _records: Dictionary={}
var _consumer_key := ""
var _accepted_count := 0
var _retired_count := 0
func owner_thread_id() -> int: return _owner
func configure_original_owner(session: RefCounted, feature: Dictionary, policy: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or OS.get_thread_caller_id()==OS.get_main_thread_id() or _session!=null or session==null or not feature.get("coordinator") is RefCounted or not feature.get("primitives") is RefCounted: return _invalid("actual_S_once_owner_required")
	var coordinator: RefCounted=feature.coordinator
	if not is_same(session.feature_resource_session().coordinator,coordinator) or coordinator.owner_thread_id()!=_owner or not is_same(coordinator.Budget,session.original_frame_budget()) or not is_same(feature.primitives.get("_budget"),coordinator.Budget): return _invalid("actual_single_Coordinator_shared_budget_required")
	# These callbacks must be implemented at the original queue/caller points.
	# Their absence refuses configuration; no synthetic readiness provider exists.
	for method: String in ["capture_actual_original_live_feature_scope","commit_original_live_feature_leaf_in_scope"]:
		if not coordinator.has_method(method): return {"success":false,"status":"MISSING","error":"actual_original_Coordinator_continuation:"+method}
	for method: String in ["settle_live_resource","apply_settled_live_resource","submit_live_resource","retire_live_resource","original_transport_obligations_released"]:
		if not session.has_method(method): return {"success":false,"status":"MISSING","error":"actual_Session_split_commit:"+method}
	for value: Variant in policy.values():
		if not value is int or value<0: return _invalid("actual_reservation_policy_required")
	_consumer_key="feature_leaf:%d"%get_instance_id()
	if not session.register_live_resource_consumer(_consumer_key,self): return _invalid("actual_consumer_registration_failed")
	_session=weakref(session);_coordinator=weakref(coordinator);_budget=coordinator.Budget;_policy=policy.duplicate(true);_policy.make_read_only()
	return {"success":true,"consumer_key":_consumer_key}
func _key(identity: Dictionary) -> String: return "%d:%d"%[identity.bridge_generation,identity.op_sequence]
func _invalid(error: String) -> Dictionary: return {"success":false,"status":"INVALID","error":error}
func submit_original_leaf(operation: String, encoded_arguments: Array, caller: Dictionary, dependencies: Array=[]) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or _session==null or _coordinator==null or _session.get_ref()==null or _coordinator.get_ref()==null or not _policy.has(operation): return _invalid("actual_configured_original_leaf_required")
	if int(_budget.snapshot().open_scopes)!=0: return {"status":"BUSY","error":"original_scalar_scope_must_close_before_reservation"}
	var coordinator: RefCounted=_coordinator.get_ref()
	var captured: Dictionary=coordinator.capture_actual_original_live_feature_scope(caller)
	if captured.get("success")!=true or not captured.get("site") is Dictionary or captured.get("caller")!=caller or captured.get("actual_coordinator_id")!=coordinator.get_instance_id(): return _invalid("actual_original_caller_and_scope_unproved")
	var site: Dictionary=captured.site
	if site.get("domain")!=&"P" and site.get("domain")!="P": return _invalid("actual_P_leaf_submission_required")
	var lane: Variant = captured.get("lane")
	var priority: Variant = captured.get("priority")
	if not lane is int or lane not in [0,1,2] or not priority is int or priority not in [0,1,2]: return _invalid("actual_original_leaf_lane_required")
	# A zero reservation predicts no elapsed cost. It does not grant new
	# background work admission after this real P's budget is exhausted.
	if lane == 0 and _budget.remaining_usec() <= 0: return {"status":"BACKPRESSURE"}
	var request: Dictionary={"protocol":"hardcore.streaming.live_primitives.v1","site":site.duplicate(true),"op":"feature."+operation,"args":encoded_arguments.duplicate(true),"main_prefix":_session.get_ref().freeze_original_main_prefix(),"deadline_usec":site.deadline_usec,"order_key":"feature:%d:%s"%[coordinator.get_instance_id(),str(caller.get("original_responsibility_key",""))],"dependencies":dependencies.duplicate(true),"priority":priority,"cleanup":bool(captured.get("cleanup",false))}
	var accepted: Dictionary=_session.get_ref().submit_live_resource(request,"feature_resources",lane,int(_policy[operation]),_consumer_key)
	if accepted.get("status") in ["BUSY","BACKPRESSURE"]: return accepted
	if accepted.get("status")!="PENDING" or not accepted.get("request") is Dictionary: return _invalid("actual_Native_Feature_admission_rejected")
	var identity: Dictionary=accepted.request.identity
	var key: String=_key(identity)
	if _records.has(key): return _invalid("actual_Feature_identity_duplicate")
	_records[key]={"identity":identity.duplicate(true),"request":accepted.request.duplicate(true),"caller":caller.duplicate(true),"applied":false,"consumed":false}
	_accepted_count+=1
	return accepted # PENDING never becomes a bool/int/resource result.
func settle_original_leaf(identity: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or _session==null or _session.get_ref()==null or not _records.has(_key(identity)): return _invalid("actual_original_Feature_owner_required")
	if int(_budget.snapshot().open_scopes)!=0: return {"status":"BUSY"}
	return _session.get_ref().settle_live_resource(identity) # Actual ordinary/closing P commit gate belongs to Session.
func apply_original_leaf(identity: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or _session==null or _session.get_ref()==null or not _records.has(_key(identity)): return _invalid("actual_original_Feature_ticket_required")
	return _session.get_ref().apply_settled_live_resource(identity)
func commit_original_live_feature_reply(identity: Dictionary, reply: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or _coordinator==null or _coordinator.get_ref()==null or not _records.has(_key(identity)): return _invalid("actual_original_Feature_consumer_required")
	var record: Dictionary=_records[_key(identity)]
	if record.applied: return {"success":reply==record.reply,"status":"INVALID" if reply!=record.reply else "SETTLED"}
	if reply.get("request")!=record.request or reply.get("executed")!=true: return _invalid("actual_Feature_reply_wire_unproved")
	# This callback verifies actual original scope/token/queue/cursor and applies
	# result, retirement and owner reentry once at that original S location.
	var applied: Dictionary=_coordinator.get_ref().commit_original_live_feature_leaf_in_scope(record.caller,identity,reply)
	if applied.get("status") in ["PENDING","BUSY"]: return applied
	if applied.get("success")!=true: return applied
	record.applied=true;record.reply=reply.duplicate(true)
	return {"success":true}
func consume_original_leaf(identity: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_owner or not _records.has(_key(identity)): return _invalid("actual_original_Feature_ticket_required")
	var record: Dictionary=_records[_key(identity)]
	if not record.applied: return {"status":"PENDING"}
	if record.consumed: return _invalid("actual_original_Feature_leaf_consumed_twice")
	record.consumed=true
	return {"status":"READY","reply":record.reply.duplicate(true),"caller":record.caller.duplicate(true)}
func original_ticket_lease_obligations_retired(identity: Dictionary) -> bool:
	return OS.get_thread_caller_id()==_owner and _session!=null and _session.get_ref()!=null and _records.has(_key(identity)) and _records[_key(identity)].applied and _records[_key(identity)].consumed and _session.get_ref().original_transport_obligations_released(identity)
func retire_original_leaf(identity: Dictionary) -> bool:
	if not original_ticket_lease_obligations_retired(identity) or not _session.get_ref().retire_live_resource(identity): return false
	_records.erase(_key(identity)); _retired_count+=1; return true
func actual_original_leaf_counts() -> Dictionary:
	return {"accepted":_accepted_count,"retired":_retired_count,"pending":_records.size()}
func live_operations_drained() -> bool: return OS.get_thread_caller_id()==_owner and _records.is_empty()
func release_original_owner() -> bool:
	if not live_operations_drained() or _session==null or _session.get_ref()==null or not _session.get_ref().unregister_live_resource_consumer(_consumer_key,self): return false
	_session=null;_coordinator=null;_budget=null;return true
