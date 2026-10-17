extends RefCounted

## Native binds this exact Main script/object and verifies its full immutable
## scope/publication receipts. Actual Root Loading and IO providers remain
## mandatory: this adapter never manufactures coverage, writer, receiver, pin
## or ContentLayers transfer completion from phase names or empty queues.
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
var _host: Object
var _loading: RefCounted
var _io: RefCounted
var _executor_ref: WeakRef
var _executor: RefCounted:
	get: return _executor_ref.get_ref() if _executor_ref != null else null
var _descriptor: Dictionary
var _scope: Dictionary = {}
var _publication: Dictionary = {}
var _publication_receipt: Dictionary = {}
var _terminal: Dictionary = {}
var _observer: RefCounted
var _arrival_transaction: Dictionary = {}
var _release_stage: Dictionary = {}
var _released_input: Dictionary = {}
var _released_result: Dictionary = {}
var _closing := false
var _release_requested_scope: Dictionary = {}
var _source_release_confirmation_required := false

func configure_main(host: Object, actual_loading_provider: RefCounted, actual_io_provider: RefCounted, actual_executor: RefCounted, descriptor: Dictionary) -> bool:
	if _host != null or OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
	for method: String in ["capture_actual_original_map_loading_scope","verify_actual_original_map_loading_scope","capture_actual_original_map_publication_receipt","verify_actual_original_map_publication_receipt","capture_actual_original_map_owner_terminal","verify_actual_original_map_owner_terminal"]:
		if actual_loading_provider == null or not actual_loading_provider.has_method(method): return false
	for method: String in ["bind_actual_original_map_io_observer","inspect_actual_original_map_claim_transfer"]:
		if actual_io_provider == null or not actual_io_provider.has_method(method): return false
	if host == null or not host.has_method("publish_original_map_loading_scope") or actual_executor == null or not actual_executor.has_method("actual_owner_descriptor") or actual_executor.actual_owner_descriptor() != descriptor: return false
	_host = host; _loading = actual_loading_provider; _io = actual_io_provider; _executor_ref = weakref(actual_executor); _descriptor = descriptor.duplicate(true)
	return true

func publish_actual_loading_scope(transition: String, coordinator_generation: int, map_id: int) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if _loading == null or _closing or not _release_stage.is_empty() or not _release_requested_scope.is_empty() or _source_release_confirmation_required or transition.is_empty() or coordinator_generation < 0 or map_id < 0: return {"status":"INVALID"}
	var captured: Dictionary = _loading.capture_actual_original_map_loading_scope(self,_descriptor,transition,coordinator_generation,map_id)
	if captured.get("status") != "READY" or not captured.get("scope") is Dictionary: return captured
	var candidate: Dictionary = captured.scope
	if not _scope_schema(candidate) or candidate.get("transition_id") != transition or candidate.get("coordinator_generation") != coordinator_generation or candidate.get("map_id") != map_id or not _loading.verify_actual_original_map_loading_scope(self,candidate,_descriptor): return {"status":"INVALID","error":"actual_Root_Loading_scope_producer"}
	var copied: Dictionary = Graph.copy_and_seal(candidate)
	if not copied.ok: return {"status":"INVALID","error":"actual_Loading_proof_not_plain"}
	var previous: Dictionary = _scope
	_scope = copied.value
	var registered: Dictionary = _host.publish_original_map_loading_scope(_scope)
	if registered.get("status") != "READY": _scope = previous; return registered
	_arrival_transaction = {}
	_released_input = {}; _released_result = {}
	return {"status":"READY","scope":_scope.duplicate(true)}

func publish_actual_retained_scope(actual_receipt: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	# Actual provider emits the entire RETAINED scope with resident pins/claims
	# still owned. This is not terminal or a permission to reuse old gameplay.
	if not actual_receipt.get("scope") is Dictionary: return {"status":"INVALID"}
	var candidate: Dictionary = actual_receipt.scope
	if not _scope_schema(candidate) or candidate.state != "RETAINED" or _scope.is_empty() or candidate.scope_id != _scope.scope_id or not _loading.verify_actual_original_map_loading_scope(self,candidate,_descriptor): return {"status":"INVALID"}
	var copied: Dictionary = Graph.copy_and_seal(candidate)
	if not copied.ok: return {"status":"INVALID"}
	var previous: Dictionary = _scope
	_scope = copied.value
	var registered: Dictionary = _host.publish_original_map_loading_scope(_scope)
	if registered.get("status") != "READY": _scope = previous
	return registered

func verify_actual_original_map_executor(executor: RefCounted) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and executor == _executor and executor.actual_owner_descriptor() == _descriptor
func verify_actual_original_map_scope(scope: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and scope == _scope and _scope_schema(scope) and _loading.verify_actual_original_map_loading_scope(self,scope,_descriptor)
func verify_original_map_loading_command(request: Dictionary, descriptor: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if descriptor != _descriptor or request.get("scope") != _scope or not verify_actual_original_map_scope(_scope): return {"status":"INVALID"}
	if (_closing or not _release_stage.is_empty() or not _release_requested_scope.is_empty() or not _arrival_transaction.is_empty() or _scope.state != "LOADING") and request.get("operation") != "retire_claims": return {"status":"INVALID"}
	return {"status":"READY","scope":_scope.duplicate(true)}

func capture_original_map_loading_publication_receipt(scope: Dictionary, publication: Dictionary, coordinator: RefCounted, leaf: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if leaf != _observer or scope != _scope or scope.state != "LOADING" or not verify_actual_original_map_scope(scope): return {"status":"INVALID"}
	var receipt: Dictionary = _loading.capture_actual_original_map_publication_receipt(self,scope,publication,coordinator,leaf)
	if receipt.get("status") != "READY" or not _loading.verify_actual_original_map_publication_receipt(self,scope,publication,receipt): return {"status":"INVALID","error":"actual_MapService_pin_receipt"}
	var copied: Dictionary = Graph.copy_and_seal([publication,receipt])
	if not copied.ok: return {"status":"INVALID","error":"actual_MapService_receipt_not_plain"}
	_publication = copied.value[0]; _publication_receipt = copied.value[1]
	return _publication_receipt.duplicate(true)
func verify_actual_original_map_publication(scope: Dictionary, publication: Dictionary, receipt: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and scope == _scope and publication == _publication and receipt == _publication_receipt and _loading.verify_actual_original_map_publication_receipt(self,scope,publication,receipt)

func bind_original_map_io_observer(leaf: RefCounted, descriptor: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if _observer != null or descriptor != _descriptor or leaf == null: return {"success":false}
	var actual: Dictionary = _io.bind_actual_original_map_io_observer(self,leaf,descriptor)
	if actual.get("success") == true and actual.get("actual_owner_descriptor") == descriptor: _observer = leaf
	return actual
func inspect_original_map_claim_transfer(leaf: RefCounted, descriptor: Dictionary, coordinator: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if leaf != _observer or descriptor != _descriptor: return {"status":"INVALID"}
	return _io.inspect_actual_original_map_claim_transfer(self,leaf,descriptor,coordinator)

func certify_actual_owner_terminal() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id(): return {"status":"INVALID","error":"actual_Main_owner_required"}
	if _executor == null or _executor.has_pending_original_map_reply(): return {"status":"PENDING"}
	var facts: Dictionary = _executor.inspect_actual_original_map_io()
	var receipt: Dictionary = _loading.capture_actual_original_map_owner_terminal(self,_descriptor,_scope,facts)
	if receipt.get("status") != "READY" or not _loading.verify_actual_original_map_owner_terminal(self,_descriptor,_scope,facts,receipt): return receipt
	var copied: Dictionary = Graph.copy_and_seal(receipt)
	if not copied.ok: return {"status":"INVALID"}
	_terminal = copied.value
	var certified: Dictionary = _host.certify_original_map_loading_owner_closed(_terminal)
	certified = certified.duplicate(true)
	certified.success = certified.get("status") == "READY"
	return certified
func verify_actual_original_map_owner_terminal(receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _executor == null or _executor.has_pending_original_map_reply() or _terminal.is_empty() or receipt != _terminal: return false
	return _loading.verify_actual_original_map_owner_terminal(self,_descriptor,_scope,_executor.inspect_actual_original_map_io(),receipt)

func _scope_schema(scope: Dictionary) -> bool:
	if scope.size() != 10 or not scope.get("owner_descriptor") is Dictionary: return false
	var owner: Dictionary = scope.owner_descriptor
	return scope.get("contract_id") == "source.map.loading.scope.v1" and scope.get("bridge_generation") is int and scope.bridge_generation > 0 and scope.get("scope_id") is int and scope.scope_id > 0 and scope.get("producer_runtime_id") == get_instance_id() and owner.size() == 5 and owner.get("contract_id") == "source.map.loading.owner.v1" and owner.get("source_root_id") == _descriptor.source_root_id and owner.get("owner_session_id") == _descriptor.owner_session_id and owner.get("main_executor_id") == _descriptor.main_executor_id and owner.get("world_context") is Dictionary and scope.get("coordinator_generation") is int and scope.coordinator_generation >= 0 and scope.get("map_id") is int and scope.map_id >= 0 and scope.get("transition_id") is String and not scope.transition_id.is_empty() and scope.get("state") in ["LOADING","RETAINED"] and scope.get("actual_provenance") is Dictionary and not scope.actual_provenance.is_empty()

func can_apply_actual_original_map_arrival(transaction: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _loading != null and _release_stage.is_empty() and _release_requested_scope.is_empty() and _loading.can_apply_actual_original_map_arrival(self,transaction)
func apply_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if not can_apply_actual_original_map_arrival(transaction) or not _loading.apply_actual_original_map_arrival(self,transaction): return false
	_arrival_transaction = transaction.duplicate(true)
	return true

func release_actual_loading_scope(scope: Dictionary, from_original_source_application := true) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _loading == null or _executor == null: return {"success":false,"status":"INVALID","error":"actual_Main_map_release_owner"}
	if from_original_source_application and not _released_result.is_empty() and scope == _scope and scope.state == "RETAINED" and scope == _released_result.scope:
		# Same admitted application leaf, exact producer-issued RETAINED bytes.
		# S sends this only after its real Native verification and coordinator ACK.
		_source_release_confirmation_required = false
		return _released_result
	if scope == _released_input and not _released_result.is_empty():
		if from_original_source_application and _host.status().get("map_owner_closed") != true: _source_release_confirmation_required = true
		return _released_result
	if _release_stage.is_empty():
		if scope != _scope or scope.get("state") != "LOADING": return {"success":false,"status":"INVALID","error":"actual_Map_release_identity"}
		if not _release_requested_scope.is_empty() and _release_requested_scope != scope: return {"success":false,"status":"INVALID","error":"actual_Map_release_requested_identity"}
		_release_requested_scope = scope.duplicate(true)
		_source_release_confirmation_required = _source_release_confirmation_required or from_original_source_application
		if _executor.has_pending_original_map_reply(): return {"success":true,"status":"PENDING"}
		var prepared: Dictionary = _loading.prepare_actual_original_map_scope_release(self,scope)
		if prepared.get("status") != "READY": return prepared
		var next: Dictionary = _descriptor.duplicate(true)
		if not _arrival_transaction.is_empty(): next.world_context = _arrival_transaction.after_world.duplicate(true)
		_release_stage = {"loading_scope":scope.duplicate(true),"retained_scope":prepared.scope,"before_descriptor":_descriptor.duplicate(true),"after_descriptor":next,"stage":"PREPARED"}
	if scope != _release_stage.loading_scope: return {"success":false,"status":"INVALID","error":"actual_Map_release_in_progress_identity"}
	var leaf: RefCounted = _executor.actual_map_leaf()
	if not _executor.can_commit_actual_original_map_route(_release_stage.before_descriptor,_release_stage.after_descriptor) or not leaf.can_commit_actual_original_map_route(_release_stage.before_descriptor,_release_stage.after_descriptor): return {"success":false,"status":"INVALID","error":"actual_Map_route_validation_retained","stage":_release_stage.stage}
	if _release_stage.stage == "PREPARED":
		var published: Dictionary = publish_actual_retained_scope({"scope":_release_stage.retained_scope})
		if published.get("status") != "READY": return {"success":published.get("status") in ["PENDING","BUSY","BACKPRESSURE"],"status":"PENDING" if published.get("status") in ["PENDING","BUSY","BACKPRESSURE"] else "INVALID","details":published,"stage":_release_stage.stage}
		_release_stage.stage = "NATIVE_RETAINED"
	# Native RETAINED is already committed. A failed suffix retains the exact
	# stage and objects; no retry can report full release before all routes agree.
	if not leaf.commit_actual_original_map_route(_release_stage.before_descriptor,_release_stage.after_descriptor) or not _executor.commit_actual_original_map_route(_release_stage.before_descriptor,_release_stage.after_descriptor): return {"success":false,"status":"INVALID","error":"actual_Map_route_apply_retained","stage":_release_stage.stage}
	var committed: Dictionary = _loading.commit_actual_original_map_scope_release(self,scope,_release_stage.retained_scope,_release_stage.after_descriptor)
	if committed.get("status") != "READY": return committed
	_descriptor = _release_stage.after_descriptor.duplicate(true)
	var final: Dictionary = committed.duplicate(true)
	final.contract_id = "hardcore.main.map_scope.release.v1"
	final.actual_io = _executor.inspect_actual_original_map_io()
	var facts: Dictionary = final.actual_io
	if facts.get("actual_transfer",{}).get("status") != "READY" or facts.actual_transfer.get("actual_producer_id") != get_instance_id() or facts.owner_descriptor != _descriptor or not facts.actual_retiring_claims.is_empty() or not facts.retired_threaded_requests.is_empty(): return {"success":false,"status":"INVALID","error":"actual_Map_release_IO_suffix_retained","stage":_release_stage.stage}
	var sealed: Dictionary = Graph.copy_and_seal(final)
	if not sealed.ok or not verify_actual_original_map_scope(final.scope) or final.actual_io != _executor.inspect_actual_original_map_io(): return {"success":false,"status":"INVALID","error":"actual_Map_release_producer_verification","stage":_release_stage.stage}
	_released_input = scope.duplicate(true); _released_result = sealed.value
	_release_stage = {}; _release_requested_scope = {}
	return _released_result

func verify_actual_original_map_scope_release(scope: Dictionary, receipt: Dictionary) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and scope == _released_input and receipt == _released_result and not receipt.is_empty() and _release_stage.is_empty() and verify_actual_original_map_scope(receipt.scope) and receipt.actual_io.actual_transfer.status == "READY" and receipt.actual_io.actual_transfer.actual_producer_id == get_instance_id()

func service_actual_owner_retirement() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _loading == null or _executor == null: return {"success":false,"status":"INVALID"}
	_closing = true
	if _source_release_confirmation_required: return {"success":true,"status":"PENDING","error":"actual_Source_RETAINED_release_confirmation_required"}
	var actual: Dictionary = _loading.service_actual_original_map_owner_retirement(self)
	if actual.get("success") != true: return actual
	if actual.get("accepted_boundary_drained") != true: return actual
	if not _scope.is_empty() and (_scope.state == "LOADING" or not _release_stage.is_empty()):
		var original: Dictionary = _release_stage.loading_scope if not _release_stage.is_empty() else _scope
		var retained: Dictionary = release_actual_loading_scope(original,false)
		if retained.get("status") != "READY": return retained
	if actual.get("status") != "READY": return actual
	var leaf: RefCounted = _executor.actual_map_leaf()
	return _io.release_actual_original_map_io_observer(self,leaf,_descriptor,leaf.get("_coordinator"))

func inspect_actual_owner_lifecycle() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _loading == null: return {"success":false,"status":"INVALID"}
	var actual: Dictionary = _loading.inspect_actual_original_map_owner().duplicate(true)
	actual.release_stage = _release_stage.duplicate(true)
	actual.release_requested_scope = _release_requested_scope.duplicate(true)
	actual.Source_release_confirmation_required = _source_release_confirmation_required
	actual.actual_io = _executor.inspect_actual_original_map_io() if _executor != null else {}
	return actual
