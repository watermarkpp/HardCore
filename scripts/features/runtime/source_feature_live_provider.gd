extends RefCounted
## One Source attachment to the existing Feature Coordinator and Budget.
## The Coordinator's original application/retirement FIFOs retain all cursors.
const RPC := preload("res://scripts/features/runtime/feature_resource_live_rpc.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Registry := preload("res://scripts/features/compilation/feature_resource_registry.gd")
const LIVE_JOB_OPERATIONS := ["release_reference","release_retention","get_cached_ref","exists","status","request","get","valid_resource","issue_resource_lease","retain_publication","retention_supports_path","issue_code_inputs","object_get","object_call","open_image","acquire_shader","callback_invoke","code_scope_check","code_inputs_admit","code_publication_admit","code_publication_owner","code_publication_apply","code_target_admission","code_target_deliver","code_image_chunk","code_image_close","code_scope_cancel"]
var _owner := OS.get_thread_caller_id()
var _session: WeakRef
var _coordinator: WeakRef
var _rpc: RefCounted
var _policy: Dictionary={}
var _closed := false
var _closing_service_active := false
var _missing: Dictionary={}
func owner_thread_id() -> int: return _owner
func configure_original_bootstrap(policy: Dictionary) -> bool:
	if _owner==OS.get_main_thread_id() or not _policy.is_empty(): return false
	for operation: String in LIVE_JOB_OPERATIONS:
		if not policy.get(operation) is int or policy[operation]<0: return false
	_policy=policy.duplicate(true);_policy.make_read_only();return true
func _bound() -> bool:
	return OS.get_thread_caller_id()==_owner and _session!=null and _session.get_ref()!=null and _coordinator!=null and _coordinator.get_ref()!=null
func _missing_result(code: String) -> Dictionary:
	_missing={"success":false,"status":"MISSING","errors":[code],"lease":null};return _missing.duplicate(true)
func admit_original_live_feature_continuations(session: RefCounted, feature: Dictionary, closure: Dictionary) -> Dictionary:
	if _session!=null or session==null or session.owner_thread_id()!=_owner or _policy.is_empty() or closure.is_empty(): return _missing_result("actual_once_Feature_LIVE_policy_and_closure_required")
	if not feature.get("coordinator") is RefCounted or not is_same(session.feature_resource_session().coordinator,feature.coordinator): return _missing_result("actual_original_Coordinator_required")
	var coordinator: RefCounted=feature.coordinator
	var admitted: Dictionary=coordinator.configure_original_live_feature_owner(self,session)
	if admitted.get("success")!=true: return admitted
	_rpc=RPC.new()
	var configured: Dictionary=_rpc.configure_original_owner(session,feature,_policy)
	if configured.get("success")!=true:
		if not coordinator.abandon_unaccepted_original_live_feature_owner(self): return _missing_result("actual_unaccepted_Feature_owner_detach")
		_rpc=null;return configured
	_session=weakref(session);_coordinator=weakref(coordinator)
	return {"success":true,"actual_coordinator_id":coordinator.get_instance_id(),"actual_budget_id":session.original_frame_budget().get_instance_id(),"implemented":"original_jobs_applications_completions_and_exact_cleanup_CPS"}
func commit_original_live_feature_reply(identity: Dictionary, reply: Dictionary) -> Dictionary:
	return _rpc.commit_original_live_feature_reply(identity,reply) if _bound() else _missing_result("actual_bound_original_Feature_consumer_required")
func original_ticket_lease_obligations_retired(identity: Dictionary) -> bool:
	return _bound() and _rpc.original_ticket_lease_obligations_retired(identity)
func prepare_original_profile_feature_resources(catalog: Dictionary, enabled: Array) -> Dictionary:
	if not _bound() or _closed: return _missing_result("actual_open_original_Feature_owner_required")
	# Requirements stay in the canonical Lease/Registry and DomainCodeSettings
	# chain. Empty original plans need no physical resource or a readiness token.
	var plan: Dictionary=Lease.requirements(catalog,enabled)
	if plan.get("success")!=true: return {"success":false,"errors":plan.get("errors",[]),"lease":null}
	var declared: Dictionary=Registry.declarations()
	if declared.get("success")!=true: return {"success":false,"errors":declared.get("errors",[]),"lease":null}
	for path: String in plan.paths:
		if not declared.records.has(path): return {"success":false,"errors":["feature_resource_undeclared:"+path],"lease":null}
	if plan.paths.is_empty(): return {"success":true,"errors":[],"lease":null}
	# Coordinator admission captures the actual synchronous caller context into
	# the original Request before the first await. No later scene substitution.
	return await _coordinator.get_ref().prepare(catalog,enabled)
func apply_original_profile_feature_ready(callback: Callable) -> bool:
	if not _bound() or _closed or int(_session.get_ref().original_frame_budget().snapshot().open_scopes)!=0: return false
	return await _coordinator.get_ref().apply_ready(callback) # Same original Request.completed and _applications FIFO.
func retain_original_feature_publication(publication: Dictionary) -> Dictionary:
	# A synchronous subset cannot mint a new physical Main pin. Only a grant
	# obtained by a genuine earlier Main execution may be consumed here.
	return _missing_result("actual_preaccepted_exact_retention_grant_required")
func release_original_feature_retention(publication_id: int, retention_id: int) -> bool:
	if not _bound(): return false
	return _coordinator.get_ref().accept_original_live_retention_cleanup(publication_id,retention_id)
func original_feature_retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool:
	return _bound() and _session.get_ref().feature_resource_session().primitives.actual_original_retention_supports_path(publication_id,retention_id,path)
func original_feature_is_applying() -> bool:
	return _bound() and _coordinator.get_ref().is_applying()
func cancel_original_feature_requests() -> void:
	if _bound(): _coordinator.get_ref().cancel_original_live_module_requests()
func live_operations_drained() -> bool:
	return _bound() and _rpc.live_operations_drained() and _coordinator.get_ref().actual_original_live_feature_drained()
func submit_original_cleanup(caller: Dictionary, operation: String, arguments: Array, dependencies: Array = []) -> Dictionary:
	return _rpc.submit_original_leaf(operation,arguments,caller,dependencies) if _bound() else _missing_result("actual_Feature_cleanup_owner_required")
func settle_original_cleanup(identity: Dictionary) -> Dictionary: return _rpc.settle_original_leaf(identity)
func apply_original_cleanup(identity: Dictionary) -> Dictionary: return _rpc.apply_original_leaf(identity)
func consume_original_cleanup(identity: Dictionary) -> Dictionary: return _rpc.consume_original_leaf(identity)
func retire_original_cleanup(identity: Dictionary) -> bool: return _rpc.retire_original_leaf(identity)
func service_original_feature_cleanup_at_actual_P(frame: Dictionary) -> bool:
	if not _bound() or frame!=_session.get_ref().actual_original_clock_frame() or frame.get("closing_session")!=true or frame.get("source_boundary")!="NODE_PROCESS_SERVICE": return false
	if not _closed: _coordinator.get_ref().cancel_original_live_module_requests()
	_closed=true;_closing_service_active=true
	_coordinator.get_ref().original_process(0.0)
	_closing_service_active=false
	return not _session.get_ref().feature_resource_session().primitives.failed()
func actual_original_closing_feature_service_active() -> bool:
	return _bound() and _closed and _closing_service_active
func actual_original_missing_boundary() -> Dictionary: return _missing.duplicate(true)
