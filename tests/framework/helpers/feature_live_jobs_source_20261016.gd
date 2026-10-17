extends "res://tests/framework/helpers/persistent_profile_process_source_20261015.gd"
## Component kernel state only. Formal Session.enter_live/fullWorld NOT_RUN.
## All work below uses actual Native, production Session/Budget/Coordinator,
## genuine published declarations, original code Scope/Guard and real Main refs.
const LiveProvider := preload("res://scripts/features/runtime/source_feature_live_provider.gd")
const ActualGate := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const ActualLease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const ActualSessionInstallation := preload("res://scripts/gameplay/source/source_session_runtime_installation.gd")
class ActualFailureDiagnostics extends ActualSessionInstallation.Failure:
	var coordinator: WeakRef
	func record_fatal_source_fault(code: String, details: Dictionary) -> void:
		if code == "live_feature_original_commit_rejected" and coordinator != null and coordinator.get_ref() != null:
			var actual: RefCounted = coordinator.get_ref()
			var context: Dictionary = actual.get("_live_cleanup_context")
			var leaf: Dictionary = context.get("leaf",{})
			var identity: Dictionary = leaf.get("identity",{})
			var rpc: RefCounted = actual.get("_live_feature_owner").get_ref().get("_rpc")
			var record: Dictionary = rpc.get("_records").get(rpc._key(identity),{})
			var caller: Dictionary = record.get("caller",{})
			var application: Dictionary = actual.get("_applications").get(actual.get("_apply_head"),{})
			var request: Variant = actual.get("_requests").get(leaf.get("original_owner_id"))
			var state: Dictionary = request.live_state if request != null else {}
			print("ACTUAL_FEATURE_SOURCE_COMMIT_MATRIX ",{"context_kind":context.get("kind"),"leaf_kind":leaf.get("original_owner_kind"),"leaf_identity":identity,"service_active":actual.get("_live_service_active"),"quantum_active":actual.get("_quantum_active"),"raw_site":actual.get("_primitives").current_original_source_site(),"cursor_matches":actual._actual_live_cursor_matches(leaf,caller),"caller_equal":leaf.get("caller")==caller,"leaf_request_equals_RPC":leaf.get("request")==record.get("request"),"caller":caller,"application":application,"request_present":request!=null,"state_pc":state.get("pc"),"state_leaf_is_actual":is_same(state.get("leaf"),leaf),"budget_stack":actual.get("Budget").get("_stack")})
		super.record_fatal_source_fault(code,details)

var _actual_failure: RefCounted
var _provider: RefCounted
var _gate: Dictionary
var _inputs: Array=[]
var _loans_imported := false
var _stage := "MODULE"
var _pending_request: RefCounted
var _prepared: Dictionary={}
var _record_path := ""
var _retired_leaf_count := 0
var _prepared_wire: Dictionary={}
var _target_arguments: Array=[]
var _target_imported := false
var _target_job_handoff_observed := false
var _actual_result_consumers: Array[int] = []
func _init(host: Object, boot: Dictionary) -> void:
	super._init(host,boot)
	if not _resource_ready: return
	var services: Dictionary=_session.get("_services")
	_actual_failure=ActualFailureDiagnostics.new()
	_actual_failure.coordinator=weakref(_session.feature_resource_session().coordinator)
	services.failure=_actual_failure
	var process_scope: RefCounted=_session.feature_resource_process_scope()
	var process_link: RefCounted=_actors.capture(process_scope)
	_check(_session.get("_core")==null and is_same(_session.original_service_actors(),_actors) and process_link!=null and is_same(_actors.resolve(process_link),process_scope),"the real registered persistent Feature scope captures/resolves through the sole ServiceActors without a World")
	_gate=boot.job_gate
	_check(ActualGate.enter_reader(_gate),"actual Native Source reader consumes the genuine Main catalog publication")
	_session.set("_boot",{"feature_resources":{"source_callback_manifest":boot.job_manifest}})
	# This is the explicitly limited component kernel's phase precondition,
	# not a substitute for formal world closure/admission or a capability lift.
	_session.set("_phase","LIVE")
	_provider=LiveProvider.new()
	_check(_provider.configure_original_bootstrap(boot.job_policy),"actual immutable policy supplies all finite original leaf reservations")
	services.live_feature=_provider
	var admitted: Dictionary=_provider.admit_original_live_feature_continuations(_session,_session.feature_resource_session(),{"component_kernel":true})
	_check(admitted.get("success")==true,"real Coordinator/RPC binds the actual Session budget and captured original callback")
	if admitted.get("success")!=true: _done=true; return
	for loan: Dictionary in boot.job_loans:
		var arguments: Variant=_session.feature_resource_session().primitives.decode_actual_original_feature_command_value(loan.arguments)
		var scene: Variant=_session.feature_resource_session().primitives.decode_actual_original_feature_command_value(loan.scene)
		_check(arguments is Array and scene is RefCounted,"actual Main command descriptors import into real Source proxies")
		if not arguments is Array or not scene is RefCounted: _done=true; return
		_inputs.append({"arguments":arguments,"scene":scene,"loan_id":loan.loan_id,"actual_main_process_frame":loan.actual_main_process_frame})
	_record_path=boot.job_record_path; _loans_imported=true
func _check_actual_pending_process_owner() -> void:
	var pending: Dictionary=_budget.get("_pending").get(Coordinator.CATEGORY,{})
	var process_link: RefCounted=pending.get("process_owner")
	_check(process_link!=null and is_same(_actors.resolve(process_link),_session.feature_resource_process_scope()),"actual nonempty admission retains the original registered ProcessLink scope as its Budget pending owner")
	_check(_actual_failure.actual_fault_records().is_empty() and not _session.is_faulted(),"real Source Failure remains empty while the persistent Feature owner has no World actor access")
func _context(id: int) -> Dictionary:
	return {"contract_id":"hardcore.feature.actual_Main_call.v1","owner_session_id":_session.original_budget_session_id(),"command_id":id,"actual_main_process_frame":_inputs[id-1].actual_main_process_frame,"scene":_inputs[id-1].scene,"loan_id":id}
func _service_actual_async_feature(_frame: Dictionary) -> void:
	if _live_done or _provider==null: return
	var coordinator: RefCounted=_session.feature_resource_session().coordinator
	if _pending_request==null and _stage in ["MODULE","INPUTS"]:
		var index: int=0 if _stage=="MODULE" else 1
		var method: String="prepare" if index==0 else "prepare_code_inputs"
		var admitted: Dictionary=coordinator.admit_actual_original_main_command(method,_inputs[index].arguments,_context(index+1))
		_check(admitted.get("status")=="ACCEPTED" and admitted.get("request") is RefCounted,"nonempty "+method+" synchronously admits its original Request without pretending completion")
		if admitted.get("status")!="ACCEPTED": _done=true; return
		_check_actual_pending_process_owner()
		_pending_request=admitted.request
		_pending_request.completed.connect(_actual_completed,CONNECT_ONE_SHOT)
	elif _stage=="DRAIN" and _provider.live_operations_drained():
		var counts: Dictionary=_provider.get("_rpc").actual_original_leaf_counts()
		_check(counts.accepted>12 and counts.accepted==counts.retired and counts.pending==0,"all real job/lease/code leaves retire their exact accepted Native tickets")
		_check(coordinator.get("_jobs").is_empty() and coordinator.get("_applications").is_empty() and coordinator.get("_retirements").is_empty(),"original jobs/applications/retirement queues genuinely drain")
		_retired_leaf_count=counts.retired; _live_done=true
func _actual_completed(result: Dictionary) -> void:
	_check(_budget.snapshot().get("open_scopes")==0,"original Request.completed runs after its actual budget scope closes")
	_pending_request=null
	if _stage=="MODULE":
		var lease: Variant=result.get("lease")
		_check(result.get("success")==true and lease is ActualLease and lease.is_domain() and lease.supports_path(_record_path),"nonempty actual resource job issues/retains/proves every path before canonical Source Lease construction")
		var encoded: Dictionary=_session.feature_resource_session().primitives.encode_actual_original_feature_command_result(result)
		_check(encoded.get("success")==true and encoded.value.lease.get("contract_id")=="feature.main.reference.v1","Main result maps to the same actual physical Lease descriptor without another issue")
		_actual_result_consumers.append(1); _stage="INPUTS"
	elif _stage=="INPUTS":
		_check(result.get("success")==true and result.get("lease") is ActualLease and result.get("plan") is RefCounted,"real published CodeGuard and actual Shader inputs issue the original Main-backed input Lease")
		if result.get("success")!=true: _done=true; return
		_prepared=result
		var encoded: Dictionary=_session.feature_resource_session().primitives.encode_actual_original_feature_command_result(result)
		_check(encoded.get("success")==true,"actual code result exports Main descriptors without Source Objects")
		if encoded.get("success")!=true: _done=true; return
		_prepared_wire=encoded.value; _actual_result_consumers.append(2); _stage="WAIT_TARGET"
	elif _stage=="TARGET":
		_check(_target_job_handoff_observed,"the real code target crosses the observed application-to-job handoff before delivery")
		_check(result.get("success")==true and result.get("resource") is RefCounted and "Script" in result.resource.descriptor.native_types,"actual original target load/delivery retains the genuine Script only after source revalidation")
		_check(_session.feature_resource_session().coordinator.get("_get_calls")>=1,"at least one actual code-target retrieval occurs; cached empty preparation is not the test")
		_prepared.clear(); _prepared_wire.clear(); _inputs.clear(); _target_arguments.clear(); _actual_result_consumers.append(3); _stage="DRAIN"
func on_inputs(domain: String, packets: Array) -> bool:
	if not super.on_inputs(domain,packets): return false
	for packet: Dictionary in packets:
		if packet.get("kind")!="actual_feature_kernel_target": continue
		_check(_stage=="WAIT_TARGET" and not _target_imported,"the original target call enters Source once after actual Main input")
		if _stage!="WAIT_TARGET" or _target_imported: return false
		var primitive: RefCounted=_session.feature_resource_session().primitives
		_target_arguments=primitive.decode_actual_original_feature_command_value(packet.loan.arguments)
		var scene: Variant=primitive.decode_actual_original_feature_command_value(packet.loan.scene)
		var context: Dictionary={"contract_id":"hardcore.feature.actual_Main_call.v1","owner_session_id":_session.original_budget_session_id(),"command_id":3,"actual_main_process_frame":packet.actual_main_process_frame,"scene":scene,"loan_id":packet.loan.loan_id}
		var admitted: Dictionary=_session.feature_resource_session().coordinator.admit_actual_original_main_command("request_code_script",_target_arguments,context)
		_check(admitted.get("status")=="ACCEPTED","fresh actual Main target call admits the same original Request")
		if admitted.get("status")!="ACCEPTED": return false
		_check_actual_pending_process_owner()
		_target_imported=true; _stage="TARGET"; _pending_request=admitted.request; _pending_request.completed.connect(_actual_completed,CONNECT_ONE_SHOT)
	return true
func on_phase(phase: String, frame: Dictionary) -> bool:
	if phase=="PUBLISH" and _stage=="TARGET" and _pending_request!=null and _pending_request.live_state.get("waiting_job",false):
		_check(_pending_request.live_state.leaf.is_empty(),"the actual target job handoff admits no extra application leaf or stale owner-check receipt")
		_target_job_handoff_observed=true
	if phase=="PUBLISH": return _host.publish_snapshot({"done":_done,"need_pause":_live_done and _ordinary>=2,"checks":_checks,"feature_loans_imported":_loans_imported,"feature_retired_leaf_count":_retired_leaf_count,"actual_source_fault_records":_actual_failure.actual_fault_records() if _actual_failure!=null else [],"prepared_code_value":_prepared_wire,"target_loan_imported":_target_imported,"formal_enter_live":"NOT_RUN","fullWorld":"NOT_RUN","actual_component_result_consumers":_actual_result_consumers.duplicate(),"actual_feature_kernel_state":_actual_feature_kernel_snapshot()},[])
	return super.on_phase(phase,frame)
func close_session() -> bool:
	if _provider!=null and not _provider.live_operations_drained(): return false
	if not super.close_session(): return false
	_check(ActualGate.leave_reader(_gate),"actual Source leaves the same protected registry publication")
	_provider=null; _inputs.clear(); _prepared.clear()
	return true

func _actual_feature_kernel_snapshot() -> Dictionary:
	var c: RefCounted = _session.feature_resource_session().coordinator
	var requests: Array = []
	for id: int in c.get("_requests"):
		var request: RefCounted = c.get("_requests")[id]
		var state: Dictionary = request.live_state
		var leaf: Dictionary = state.get("leaf",{})
		requests.append({"id":id,"kind":request.kind,"pc":state.get("pc"),"waiting_job":state.get("waiting_job",false),"completion":not state.get("completion",{}).is_empty(),"leaf":_actual_feature_leaf_snapshot(leaf)})
	var retire: Dictionary = c.get("_retirements").get(c.get("_retire_head"),{})
	var tickets: Array = []
	for row: Dictionary in _provider.get("_rpc").get("_records").values():
		tickets.append({"identity":row.request.identity,"op":row.request.op,"caller":row.caller,"applied":row.applied,"consumed":row.consumed})
	return {"stage":_stage,"requests":requests,"missing":c.actual_original_live_feature_missing(),"counts":_provider.get("_rpc").actual_original_leaf_counts(),"head_application":c.get("_applications").get(c.get("_apply_head"),{}),"head_work":c.get("_work").get(c.get("_head"),""),"retire_operation":retire.get("operation",""),"retire_head":c.get("_retire_head"),"retire_tail":c.get("_retire_tail"),"retire_leaf":_actual_feature_leaf_snapshot(retire.get("__live_leaf__",{})),"tickets":tickets,"source_faulted":_session.is_faulted()}
func _actual_feature_leaf_snapshot(leaf: Dictionary) -> Dictionary:
	return {"identity":leaf.get("identity",{}),"operation":leaf.get("operation",""),"applied":leaf.get("applied",false),"consumed":leaf.get("consumed",false),"retired":leaf.get("retired",false)}
