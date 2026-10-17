extends RefCounted

const Reference := preload("res://scripts/features/runtime/feature_resource_reference.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const PROTOCOL := "hardcore.streaming.primitives.v2"
const THREAD_LOAD_INVALID_RESOURCE := 0
const THREAD_LOAD_IN_PROGRESS := 1
const THREAD_LOAD_FAILED := 2
const THREAD_LOAD_LOADED := 3
var _thread := OS.get_thread_caller_id()
var _owner: WeakRef
var _coordinator: WeakRef
var _transport: RefCounted
var _budget: RefCounted
var _clock: RefCounted
var _site: Dictionary = {}
var _generation := 0
var _failed := false
var _intern: Dictionary = {}
var _node_references: Dictionary = {}
# Receipt metadata only: no new resource owner or scheduler. Main pins remain
# authoritative; each fact below came from an executed original Main receipt.
var _actual_retention_receipts: Dictionary = {}
var _actual_reference_descriptors: Dictionary = {}
var _live_reference_cleanup: Dictionary = {}
var _self_descriptor: Dictionary
var _tree_descriptor: Dictionary
var _last_status: Dictionary = {}
var deadline_failures: Array[Dictionary] = []

func owner_thread_id() -> int: return _thread
func failed() -> bool: return _failed
func adopt_threaded_claims(path: String, count: int) -> bool: return original_issued_claim_adopt_or_exchange(path,count)
func _fault(code: String, details: Dictionary = {}) -> void:
	_failed = true
	_owner.get_ref().fault(code,details)
	# Native contract: the fatal latch aborts/quarantines the original source
	# continuation. It must not return a fabricated resource result to GDScript.
	assert(false,"fatal feature primitive source continuation")

func configure_owner(owner: RefCounted, transport: RefCounted, budget: RefCounted, clock: RefCounted, boot: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _thread or owner == null: return false
	_owner = weakref(owner)
	for provider: RefCounted in [transport,budget,clock]:
		if provider == null or not provider.has_method("owner_thread_id") or provider.owner_thread_id() != _thread: return false
	for method: String in ["capabilities","exchange_original_primitive","ordered_main_prefix","next_original_operation_sequence","completed_original_operation_sequence","next_original_call_ordinal"]:
		if not transport.has_method(method): return false
	for method: String in ["begin_resource_external_segment","resume_resource_external_segment","resource_continuations_configured"]:
		if not budget.has_method(method): return false
	var capabilities: Dictionary = transport.capabilities()
	for flag: String in ["original_point_continuation","explicit_observation_process_epoch","exclusive_same_epoch_budget","ordered_main_prefix","deadline_preserves_continuation","abort_owner_on_failure"]:
		if capabilities.get(flag) != true: return false
	_generation = int(capabilities.get("bridge_generation",0))
	if _generation <= 0 or not budget.resource_continuations_configured() or not boot.get("lease_owner") is Dictionary or not boot.get("scene_tree") is Dictionary: return false
	_self_descriptor = boot.lease_owner.duplicate(true)
	_tree_descriptor = boot.scene_tree.duplicate(true)
	if _self_descriptor.bridge_generation!=_generation or _tree_descriptor.bridge_generation!=_generation: return false
	_self_descriptor.native_types.make_read_only()
	_tree_descriptor.native_types.make_read_only()
	_self_descriptor.make_read_only()
	_tree_descriptor.make_read_only()
	_transport = transport
	_budget = budget
	_clock = clock
	return true

func bind_coordinator(coordinator: RefCounted) -> void:
	assert(_coordinator == null and coordinator != null)
	_coordinator = weakref(coordinator)

func encode_original_source_value(value: Variant) -> Variant:
	assert(OS.get_thread_caller_id()==_thread and not _site.is_empty() and not _failed)
	return _encode(value)

func decode_original_source_value(value: Variant) -> Variant:
	assert(OS.get_thread_caller_id()==_thread and not _site.is_empty() and not _failed)
	return _decode(value)

func decode_actual_original_feature_command_value(value: Variant) -> Variant:
	if OS.get_thread_caller_id() != _thread or _failed or not _actual_cleanup_side_value_valid(value): return null
	return _decode(value)

func encode_actual_original_feature_command_result(value: Variant) -> Dictionary:
	if OS.get_thread_caller_id() != _thread or _failed or not _actual_command_result_encodable(value): return {"success":false,"error":"actual_Main_command_result_has_unowned_Source_object"}
	var encoded: Variant = _encode(value)
	if _failed or not _actual_cleanup_side_value_valid(encoded): return {"success":false,"error":"actual_Main_command_result_reference_lifetime"}
	return {"success":true,"value":encoded}

func _actual_command_result_encodable(value: Variant) -> bool:
	if value is Reference: return _actual_reference_descriptors.get(int(value.descriptor.token_id)) == value.descriptor and not _live_reference_cleanup.has(int(value.descriptor.token_id))
	if value is Lease:
		var actual: RefCounted = value._domain_code_main_lease if value._domain_code_main_lease != null else value._domain_main_reference
		return actual is Reference and _actual_command_result_encodable(actual)
	if value is Object or value is Callable or value is Signal: return false
	if value is Dictionary:
		for item: Variant in value.values():
			if not _actual_command_result_encodable(item): return false
	if value is Array:
		for item: Variant in value:
			if not _actual_command_result_encodable(item): return false
	return true

func import_actual_original_job_leaf(operation: String, arguments: Array, reply: Dictionary) -> Dictionary:
	if not _actual_cleanup_side_value_valid(reply.get("result")): return {"success":false,"status":"INVALID","error":"actual_job_result_reference_lifetime"}
	var imported: Dictionary = import_actual_original_live_cleanup_side_facts(reply)
	if imported.get("success") != true: return imported
	_capture_actual_original_retention_receipt(operation,arguments,reply)
	return {"success":not _failed}

func actual_original_reference_release_pending(descriptor: Dictionary) -> bool:
	var row: Dictionary = _live_reference_cleanup.get(int(descriptor.get("token_id",0)),{})
	return not row.is_empty() and row.descriptor == descriptor and not row.physical_released

func construct_actual_original_module_lease(plan: Dictionary, issued: Dictionary, retention: int, diagnostics: Dictionary) -> RefCounted:
	if not issued.get("main_lease") is Reference or not issued.get("resource_publication") is Dictionary: return null
	var receipt: Dictionary = _actual_retention_receipts.get(retention,{})
	if receipt.is_empty() or receipt.get("lease_constructed",false) or receipt.cleanup_accepted or receipt.publication != issued.resource_publication: return null
	var result: RefCounted = Lease.issue_domain_preaccepted(plan,issued.resource_publication,_owner.get_ref(),diagnostics,issued.main_lease,retention)
	if result != null: receipt.lease_constructed = true
	return result

func begin_original_phase(site: Dictionary) -> bool:
	if _failed or OS.get_thread_caller_id() != _thread or not _site.is_empty(): return false
	if site.size()!=8: return false
	for field: String in ["clock_epoch","domain","entry_id","entry_ordinal","bootstrap","observation_process_epoch","world_context","deadline_usec"]:
		if not site.has(field): return false
	for field: String in ["clock_epoch","entry_ordinal","observation_process_epoch","deadline_usec"]:
		if not site[field] is int: return false
	if not site.bootstrap is bool or not (site.domain is String or site.domain is StringName) or not (site.entry_id is String or site.entry_id is StringName) or str(site.entry_id).is_empty(): return false
	if site.domain not in [&"H",&"P"] or int(site.deadline_usec) <= 0: return false
	if not site.world_context is Dictionary or site.world_context.size()!=5: return false
	var world: Dictionary=site.world_context
	if world.get("contract_id")!="hardcore.execution.world_context.v1" or not world.get("world_runtime_id") is int or world.world_runtime_id<=0 or not world.get("world_epoch") is int or world.world_epoch<0 or not world.get("runtime_map_id") is int or not (world.runtime_map_id>=0 or (world.runtime_map_id==-1 and world.world_epoch==0)) or not world.get("profile_id") is String or world.profile_id.is_empty(): return false
	_site = site.duplicate(true)
	return true

func finish_original_phase() -> bool:
	if _failed or _site.is_empty() or _budget.resource_external_segment_active(): return false
	_site = {}
	return true

func _encode(value: Variant) -> Variant:
	if value is Reference: return value.descriptor
	if value is Lease:
		var actual: RefCounted = value._domain_code_main_lease if value._domain_code_main_lease != null else value._domain_main_reference
		if actual != null: return _encode(actual)
	if value is Object:
		if _coordinator != null and is_same(value,_coordinator.get_ref()): return _self_descriptor
		_fault("feature_resource_non_token_object",{})
		return null
	if value is Callable or value is Signal:
		_fault("feature_resource_non_value_callback",{})
		return null
	if value is Dictionary:
		var result := {}
		for key: Variant in value: result[key] = _encode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_encode(item))
		return result
	return value

func _decode(value: Variant) -> Variant:
	if value is Dictionary:
		if value.get("contract_id") == "feature.main.reference.v1":
			var token := int(value.get("token_id",0))
			if token <= 0 or value.get("bridge_generation") != _generation:
				_fault("feature_resource_reference_identity",value)
				return null
			if _live_reference_cleanup.has(token) or (_actual_reference_descriptors.has(token) and _actual_reference_descriptors[token]!=value):
				_fault("feature_reference_reissued_during_or_after_actual_cleanup",value)
				return null
			_actual_reference_descriptors[token]=value.duplicate(true)
			var reference: RefCounted = (_intern[token] as WeakRef).get_ref() if _intern.has(token) else null
			if reference == null:
				reference = Reference.new(value,self)
				_intern[token] = weakref(reference)
				# Node tokens themselves stay interned while the actual Main Node
				# is weakly held. This preserves original WeakRef Node lifetime.
				if "Node" in value.native_types or "SceneTree" in value.native_types: _node_references[token] = reference
			return reference
		var result := {}
		for key: Variant in value: result[key] = _decode(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(_decode(item))
		return result
	return value

func _exchange(operation: String, arguments: Array) -> Variant:
	if _failed or _site.is_empty() or OS.get_thread_caller_id() != _thread:
		_fault("feature_resource_outside_original_source",{"operation":operation})
		return null
	var encoded_arguments: Variant=_encode(arguments)
	if _failed: return null
	var sequence: int = int(_transport.next_original_operation_sequence())
	var predecessor: int = int(_transport.completed_original_operation_sequence())
	if sequence <= 0 or predecessor != sequence-1:
		_fault("feature_resource_global_operation_prefix",{"sequence":sequence,"predecessor":predecessor})
		return null
	var site := _site.duplicate(true)
	site.call_ordinal = int(_transport.next_original_call_ordinal(_site))
	if site.call_ordinal<=0:
		_fault("feature_resource_global_call_ordinal",site)
		return null
	var identity := {"bridge_generation":_generation,"op_sequence":sequence}
	var segment: Dictionary = _budget.begin_resource_external_segment(identity,site)
	if segment.is_empty():
		_fault("feature_resource_budget_segment",identity)
		return null
	var request := {"protocol":PROTOCOL,"identity":identity,"site":site,"operation":"feature."+operation,"arguments":encoded_arguments,
		"budget":segment,"predecessor_receipt":predecessor,"output_slot":0,"main_prefix":_transport.ordered_main_prefix(),"submitted_usec":int(_clock.get_ticks_usec())}
	var reply: Variant = _transport.exchange_original_primitive(request)
	var received := int(_clock.get_ticks_usec())
	if not reply is Dictionary or reply.get("request") != request or reply.get("executed") != true or not reply.has("result") \
		or reply.get("disposition") not in [&"executed",&"executed_late"] or reply.get("completed_prefix_ordinal") != 1:
		_fault("feature_resource_unexecuted_or_mismatched_receipt",identity)
		return null
	if not reply.get("started_usec") is int or not reply.get("finished_usec") is int or reply.started_usec < request.submitted_usec or reply.finished_usec < reply.started_usec or received < reply.finished_usec:
		_fault("feature_resource_wall_provenance",identity)
		return null
	if not _budget.resume_resource_external_segment(segment,reply):
		_fault("feature_resource_budget_resume",identity)
		return null
	if reply.disposition == &"executed_late" or received > int(site.deadline_usec):
		deadline_failures.append({"status":"FAIL","identity":identity,"site":site,"received_usec":received})
	# Real lease PREDELETE and Main callback reentry are synchronous original
	# obligations. Import them before returning this source call, after the
	# external segment settles, while original _quantum_active/applying holds.
	for held: Variant in reply.get("retirements",[]): _coordinator.get_ref().retire_resources(_decode(held))
	for call: Dictionary in reply.get("owner_calls",[]):
		if call.method not in ["cancel_all","cancel_code_owner"]:
			_fault("feature_resource_reentry_method",call)
			return null
		_coordinator.get_ref().callv(call.method,_decode(call.arguments))
	_capture_actual_original_retention_receipt(operation,encoded_arguments,reply)
	return _decode(reply.result)

func tree() -> RefCounted: return _decode(_tree_descriptor)
func object_property(reference: RefCounted, property: String) -> Variant: return _exchange("object_get",[reference,property])
func object_call(reference: RefCounted, method: String, arguments: Array) -> Variant: return _exchange("object_call",[reference,method,arguments])
func object_script(reference: Variant) -> Variant: return _exchange("object_script",[reference])
func reference_has_method(reference: Variant, method: String) -> bool: return bool(_exchange("has_method",[reference,method]))
func object_is_valid(value: Variant) -> bool:
	if value == null: return false
	if value is Reference: return bool(_exchange("object_valid",[value]))
	return is_instance_valid(value)
func object_same(a: Variant, b: Variant, coordinator: RefCounted) -> bool:
	if a == null or b == null: return a == b
	var aid: int = int(a.descriptor.object_id) if a is Reference else (int(_self_descriptor.object_id) if is_same(a,coordinator) else a.get_instance_id())
	var bid: int = int(b.descriptor.object_id) if b is Reference else (int(_self_descriptor.object_id) if is_same(b,coordinator) else b.get_instance_id())
	return aid == bid
func is_native_type(value: Variant, kind: String) -> bool: return value is Reference and kind in value.descriptor.native_types
func cast(value: Variant, kind: String) -> Variant: return value if is_native_type(value,kind) else null
func callback_is_valid(callback: Variant) -> bool: return callback.is_valid() if callback is Callable else bool(_exchange("callback_valid",[callback]))
func invoke_callback(callback: Variant) -> bool: return bool(callback.call()) if callback is Callable else bool(_exchange("callback_invoke",[callback,publication_application_fact()]))

func publication_application_fact() -> Dictionary:
	var coordinator: RefCounted = _coordinator.get_ref()
	if not coordinator._requests.has(coordinator._applying_request): return {}
	var request: RefCounted = coordinator._requests[coordinator._applying_request]
	return _encode({"request_id":coordinator._applying_request,"kind":request.kind,"scope":request.scope,"consumer":request.consumer.get_ref() if request.consumer != null else null,
		"generation":request.generation,"image_sha256":request.image_sha256,"expected_sha256":request.plan.get("expected_sha256",""),"export_verifier":request.export_verifier})

func release_reference(descriptor: Dictionary) -> void:
	if _failed: return # Main retains accepted roots for formal fault cleanup.
	var coordinator: RefCounted=_coordinator.get_ref() if _coordinator!=null else null
	if coordinator!=null and coordinator.actual_original_live_feature_bound():
		if not coordinator.accept_original_live_reference_cleanup(descriptor):
			_fault("feature_reference_retirement_not_accepted",descriptor)
		return
	_exchange("release_reference",[descriptor])
func release_owner_node_references() -> bool:
	if _failed or _site.is_empty(): return false
	_node_references.clear()
	return true
func get_cached_ref(path: String) -> Variant: return _exchange("get_cached_ref",[path])
func exists(path: String, hint: String) -> bool: return bool(_exchange("exists",[path,hint]))
func load_threaded_get_status(path: String) -> int:
	var result: Variant = _exchange("status",[path])
	_last_status[path] = result
	return int(result)
func load_threaded_request(path: String, hint: String, subthreads: bool) -> int: return int(_exchange("request",[path,hint,subthreads]))
func load_threaded_get(path: String) -> Variant: return _exchange("get",[path])
func open_image(path: String, mode: int) -> Variant: return _exchange("open_image",[path,mode])
func issue_resource_lease(plan: Dictionary, resources: Dictionary, coordinator: RefCounted, diagnostics: Dictionary) -> Variant:
	var issued: Dictionary = _exchange("issue_resource_lease",[plan,resources,coordinator,diagnostics])
	if issued.main_lease == null: return null
	var lease: RefCounted = Lease.issue_domain(plan,issued.resource_publication,_owner.get_ref(),diagnostics)
	if lease != null: lease._domain_main_reference = issued.main_lease
	return lease
func issue_code_inputs(plan: RefCounted, resources: Dictionary, coordinator: RefCounted, diagnostics: Dictionary) -> Variant:
	var main_lease: Variant = _exchange("issue_code_inputs",[plan,resources,coordinator,diagnostics])
	return Lease.issue_code_inputs_domain(plan,main_lease,diagnostics) if main_lease != null else null
func valid_resource(path: String, resource: Variant) -> bool: return bool(_exchange("valid_resource",[path,resource]))
func retained_code_resource(lease: Variant) -> Variant:
	return lease._domain_code_resource if lease is Lease and lease._domain_code_main_lease != null else lease._retained_code_resource
func retain_feature_resource_publication(publication: Dictionary) -> Dictionary: return _exchange("retain_publication",[publication])
func release_feature_resource_retention(publication_id: int, retention_id: int) -> bool: return bool(_exchange("release_retention",[publication_id,retention_id]))
func feature_resource_retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool: return bool(_exchange("retention_supports_path",[publication_id,retention_id,path]))
func begin_code_verification(payload: Dictionary, entry: String, publisher: RefCounted, consumer: RefCounted) -> Dictionary: return _exchange("begin_code_verification",[payload,entry,publisher,consumer])
func begin_export_verification(contract: Dictionary, expected: String, context_only: bool) -> Variant: return _exchange("begin_export_verification",[contract,expected,context_only])
func acquire_shader(plan: RefCounted, scope: RefCounted, consumer: RefCounted, generation: int, path: String, job: Dictionary) -> Dictionary:
	var began := int(_clock.get_ticks_usec())
	var result: Dictionary = _exchange("acquire_shader",[plan,scope,consumer,generation,path,job])
	result.elapsed_usec = int(_clock.get_ticks_usec())-began
	return result

func load_original_loading_resource(path: String) -> Variant: return _exchange("original_loading_load",[path])

func current_original_source_site() -> Dictionary:
	assert(OS.get_thread_caller_id()==_thread)
	return _site.duplicate(true)


var _issued_claim_owner: WeakRef
func configure_original_issued_claim_owner(owner: RefCounted) -> bool:
	if _issued_claim_owner!=null or owner==null or owner.owner_thread_id()!=_thread: return false
	_issued_claim_owner=weakref(owner);return true
func original_issued_claim_adopt_or_exchange(path: String, count: int) -> bool:
	if _issued_claim_owner!=null and _issued_claim_owner.get_ref()!=null:
		var owner: RefCounted=_issued_claim_owner.get_ref()
		if not owner.get("_issued_accepting").is_empty(): return owner.original_issued_claim_adoption_gate(path,count)
	return bool(_exchange("adopt_claims",[path,count])) # Original non-issued path.


func _capture_actual_original_retention_receipt(operation: String, arguments: Array, reply: Dictionary) -> void:
	if operation=="retain_publication" and reply.result is Dictionary and reply.result.get("success")==true:
		var publication: Dictionary=arguments[0]
		var retention: int=int(reply.result.get("retention_id",0))
		if retention<=0 or _actual_retention_receipts.has(retention):
			_fault("actual_retention_receipt_identity",reply);return
		_actual_retention_receipts[retention]={"publication":publication.duplicate(true),"grant_request":reply.request.duplicate(true),"paths":{},"cleanup_accepted":false}
	elif operation=="retention_supports_path" and reply.result==true:
		var retention: int=int(arguments[1])
		if not _actual_retention_receipts.has(retention) or _actual_retention_receipts[retention].publication.publication_id!=arguments[0]:
			_fault("actual_retention_path_without_grant",reply);return
		_actual_retention_receipts[retention].paths[arguments[2]]=reply.request.duplicate(true)
	elif operation=="release_retention" and reply.result==true:
		_actual_retention_receipts.erase(int(arguments[1]))
	elif operation=="release_reference" and reply.result==true:
		var descriptor: Dictionary=arguments[0]
		_live_reference_cleanup[int(descriptor.token_id)]={"descriptor":descriptor.duplicate(true),"physical_released":true}

func actual_original_retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool:
	if OS.get_thread_caller_id()!=_thread or _failed or not _actual_retention_receipts.has(retention_id): return false
	var receipt: Dictionary=_actual_retention_receipts[retention_id]
	return not receipt.cleanup_accepted and receipt.publication.publication_id==publication_id and receipt.paths.has(path)
func accept_actual_original_retention_cleanup(publication_id: int, retention_id: int) -> bool:
	if OS.get_thread_caller_id()!=_thread or _failed or not _actual_retention_receipts.has(retention_id): return false
	var receipt: Dictionary=_actual_retention_receipts[retention_id]
	if receipt.cleanup_accepted or receipt.publication.publication_id!=publication_id: return false
	receipt.cleanup_accepted=true;return true
func accept_actual_original_reference_cleanup(descriptor: Dictionary) -> bool:
	var token: int=int(descriptor.get("token_id",0))
	if OS.get_thread_caller_id()!=_thread or _failed or not _actual_reference_descriptors.has(token) or _actual_reference_descriptors[token]!=descriptor or _live_reference_cleanup.has(token): return false
	_live_reference_cleanup[token]={"descriptor":descriptor.duplicate(true),"physical_released":false};return true
func complete_actual_original_live_cleanup(operation: String, arguments: Array) -> bool:
	if OS.get_thread_caller_id()!=_thread or _failed: return false
	if operation=="release_retention":
		var retention: int=int(arguments[1])
		if not _actual_retention_receipts.has(retention) or not _actual_retention_receipts[retention].cleanup_accepted or _actual_retention_receipts[retention].publication.publication_id!=arguments[0]: return false
		_actual_retention_receipts.erase(retention);return true
	if operation=="release_reference":
		var token: int=int(arguments[0].token_id)
		if not _live_reference_cleanup.has(token) or _live_reference_cleanup[token].descriptor!=arguments[0]: return false
		# Keep this exact retired token witness. A stale wire must never recreate
		# a Source proxy after Main removed the physical vault entry.
		_live_reference_cleanup[token].physical_released=true;return true
	return false
func _actual_cleanup_side_value_valid(value: Variant) -> bool:
	if value is Dictionary:
		if value.get("contract_id")=="feature.main.reference.v1":
			var token: int=int(value.get("token_id",0))
			return value.size()==5 and token>0 and value.get("bridge_generation")==_generation and value.get("native_types") is Array and value.get("object_id") is int and value.object_id!=0 and not _live_reference_cleanup.has(token) and (not _actual_reference_descriptors.has(token) or _actual_reference_descriptors[token]==value)
		for item: Variant in value.values():
			if not _actual_cleanup_side_value_valid(item): return false
	elif value is Array:
		for item: Variant in value:
			if not _actual_cleanup_side_value_valid(item): return false
	elif value is Object or value is Callable or value is Signal: return false
	return true
func import_actual_original_live_cleanup_side_facts(reply: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=_thread or _failed or not reply.get("retirements",[]) is Array or not reply.get("owner_calls",[]) is Array: return {"success":false,"status":"INVALID"}
	var coordinator: RefCounted=_coordinator.get_ref()
	# Prevalidate the WHOLE receipt before importing any obligations. Unsupported
	# code reentry retains the accepted leaf and exact original FIFO cursor.
	for held: Variant in reply.get("retirements",[]):
		if not held is Dictionary or not _actual_cleanup_side_value_valid(held): return {"success":false,"status":"MISSING","error":"actual_cleanup_side_reference_lifetime"}
	for call: Variant in reply.get("owner_calls",[]):
		if not call is Dictionary or not call.get("arguments") is Array: return {"success":false,"status":"INVALID","error":"actual_code_owner_reentry_shape"}
		if call.get("method") == "cancel_all":
			if call.arguments != [] or not coordinator.actual_original_live_module_cancellation_supported(): return {"success":false,"status":"MISSING","error":"actual_code_owner_reentry_CPS"}
		elif call.get("method") == "cancel_code_owner":
			if call.arguments.size() != 2 or not _actual_cleanup_side_value_valid(call.arguments) or not call.arguments[1] is int: return {"success":false,"status":"INVALID","error":"actual_code_owner_cancel_arguments"}
		else: return {"success":false,"status":"INVALID","error":"actual_code_owner_reentry_method"}
	for held: Dictionary in reply.get("retirements",[]): coordinator.retire_resources(_decode(held))
	for call: Dictionary in reply.get("owner_calls",[]):
		if call.method == "cancel_all": coordinator.cancel_original_live_module_requests()
		else: coordinator.cancel_code_owner(_decode(call.arguments[0]),call.arguments[1])
	return {"success":true}

func consume_actual_live_discarded_resource(value: Variant) -> bool:
	if OS.get_thread_caller_id() != _thread or _failed or _site.is_empty(): return false
	if value == null: return true # An actual FAILED/get result is still consumed.
	if not value is Dictionary or value.get("contract_id") != "feature.main.reference.v1" or not _actual_cleanup_side_value_valid(value) or not "Resource" in value.get("native_types",[]): return false
	var resource: Variant = _decode(value)
	if not resource is Reference: return false
	# The original proxy intern owns the reference lifecycle. Discarding this
	# get result releases its token through the same retirement FIFO; another
	# real consumer's reference, if any, remains held.
	resource = null
	return not _failed

func actual_original_live_receipt_debt_free() -> bool:
	if OS.get_thread_caller_id()!=_thread or _failed or not _actual_retention_receipts.is_empty(): return false
	for token: int in _actual_reference_descriptors:
		var descriptor: Dictionary=_actual_reference_descriptors[token]
		if "Node" in descriptor.native_types or "SceneTree" in descriptor.native_types: continue # Same weak Main-vault close contract.
		if not _live_reference_cleanup.has(token) or not _live_reference_cleanup[token].physical_released: return false
	return true
