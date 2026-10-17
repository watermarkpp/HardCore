extends Node

const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")

## Actual Main lease owner and registered ContentLayers primitive facade.
## No scheduling, _process, FrameBudget, queue or readiness coordinator.
var _primitives: RefCounted
var _applying: Dictionary = {}
var _owner_transport: RefCounted

func configure_main(primitives: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitives != null or primitives == null or primitives.get_script().resource_path != "res://scripts/features/runtime/feature_resource_main_primitives.gd" or primitives.get("_facade") != self: return false
	_primitives = primitives
	set_process(false)
	return true

func bind_actual_original_owner_command_transport(transport: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitives == null or _owner_transport != null or transport == null or transport.get_script().resource_path != "res://scripts/gameplay/source/main_session_transport.gd": return false
	if transport.get("_state") != "MAIN" or transport.get("_host") == null or transport.get("_facade") != get_tree().root.get_node_or_null("PlayerState"): return false
	_owner_transport = transport
	return true

func _admit_original_owner_call(method: String, arguments: Array, consume_automatically := false) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _owner_transport == null: return {"success":false,"status":"INVALID","error":"actual_original_Feature_command_transport_required"}
	return _owner_transport.admit_original_feature_owner_call(method,arguments,consume_automatically)

func retire_resources(resources: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
	if _primitives.is_executing_original_primitive(): _primitives.capture_retirement(resources)
	elif _admit_original_owner_call("retire_resources",[resources],true).get("status") != "MAIN_HELD":
		# A rejected reliable owner command retains the physical refs for
		# formal final-fault retirement; no silent retirement disappearance.
		_primitives.reject_external_retirement(resources)

func set_original_applying_fact(fact: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id() and _applying.is_empty())
	_applying = fact

func clear_original_applying_fact() -> void:
	_applying = {}

func code_publication_image_current(scope: RefCounted, consumer: Node, generation: int, expected_sha256: String) -> bool:
	return not _applying.is_empty() and _applying.kind == "code_publication" and _applying.export_verifier == null \
		and is_same(_applying.scope,scope) and is_same(_applying.consumer,consumer) and _applying.generation == generation \
		and _applying.image_sha256 == expected_sha256 and _applying.expected_sha256 == expected_sha256 \
		and is_instance_valid(consumer) and scope != null and scope.valid_for(consumer,generation)

func code_publication_export_current(scope: RefCounted, consumer: Node, generation: int, expected_sha256: String) -> bool:
	return not _applying.is_empty() and _applying.kind == "code_publication" and _applying.export_verifier != null \
		and bool(_applying.export_verifier.is_verified()) and is_same(_applying.scope,scope) and is_same(_applying.consumer,consumer) \
		and _applying.generation == generation and _applying.expected_sha256 == expected_sha256 \
		and is_instance_valid(consumer) and scope != null and scope.valid_for(consumer,generation)

func cancel_all() -> void:
	if not _applying.is_empty(): _primitives.capture_owner_reentry("cancel_all",[])
	else:
		var admitted: Dictionary = _admit_original_owner_call("cancel_all",[],true)
		if admitted.get("status") != "MAIN_HELD": _primitives.reject_external_retirement({})

func cancel_code_owner(consumer: Node, generation: int) -> void:
	if _actual_terminal_code_owner_cancel_no_work(consumer,generation): return
	if not _applying.is_empty(): _primitives.capture_owner_reentry("cancel_code_owner",[consumer,generation])
	else:
		var admitted: Dictionary = _admit_original_owner_call("cancel_code_owner",[consumer,generation],true)
		if admitted.get("status") != "MAIN_HELD": _primitives.reject_external_retirement({})

func _actual_terminal_code_owner_cancel_no_work(consumer: Node, generation: int) -> bool:
	# CharacterSelect's real _exit_tree always calls this original cancel. Once
	# S has actually retired every job and Host has joined, sending a NEW owner
	# command is invalid. Only that exact terminal receiver's cancel is empty.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _owner_transport == null or _primitives == null or not _applying.is_empty() or not is_instance_valid(consumer): return false
	if _owner_transport.get("_state") != "CLOSED" or _owner_transport.get("_actual_terminal_listener_retired") != true or _primitives.get("_facade") != self: return false
	var host: Object = _owner_transport.get("_host")
	if host == null or not host.is_class("HardCoreSimulationHost"): return false
	var native: Dictionary = host.status()
	for key: String in ["main_channels_unbound_after_close","close_requested","source_model_close_completed","live_resource_vault_closed","live_feature_closed","map_owner_closed","source_admission_scopes_quiescent","caster_reply_obligations_quiescent","close_quiescent","join_complete"]:
		if native.get(key) != true: return false
	for key: String in ["accepted_live_resource_obligations","accepted_worker_group_obligations","unsettled_original_published_prefixes","input_queue_size"]:
		if native.get(key) != 0: return false
	if native.get("running") != false or native.get("original_primitive_in_flight") != false: return false
	var terminal: Dictionary = _owner_transport.get("_terminal")
	if terminal.get("success") != true or terminal.get("receipt",{}).get("owner_session_id") != _owner_transport.get("_session_id") or terminal.get("receipt",{}).get("bridge_generation") != _primitives.get("_generation") or terminal.get("receipt",{}).get("actual_main_io",{}).get("parts",{}).get("feature",{}).get("total") != 0: return false
	for field: String in ["_claims","_retirements","_owner_calls","_retentions","_issued_claim_records","_issued_live_pending_paths","_issued_claim_facts","_command_reference_loans","_normal_live_jobs"]:
		var held: Variant = _primitives.get(field)
		if not (held is Dictionary or held is Array) or not held.is_empty(): return false
	var application: Variant = get_tree().root.get_meta(&"hardcore_original_main_boot_application",null)
	if not application is RefCounted or not is_same(application.get("_transport"),_owner_transport) or application.get("_terminal_transition_active") != true or application.get("_main_composition").get("_stage") != "RETIRED_AFTER_CLOSE": return false
	var loading: RefCounted = application.get("_loading")
	if loading == null or loading.get("_receiver") == null or loading.get("_receiver").get_ref() != consumer or consumer.get_script().resource_path != "res://scripts/character_select.gd" or consumer.get_instance_id() != loading.get("_initial_world_handoff").get("actual_receiver_id") or generation != loading.get("_scope").get("launch_generation") or not consumer.get("_launch_code_result").is_empty() or loading.get("_terminal_code_release").get("actual_lease_PREDELETE_observed") != true: return false
	var root_transport: RefCounted = application.get("_root_transport")
	if root_transport == null or root_transport.get("_exited") != true or root_transport.get("_normal_exit_receipt").get("success") != true or root_transport.retained_root() != null: return false
	var depths: Dictionary = consumer.get("_original_main_callback_ledger")
	if depths.get("_exit_tree") != 1: return false
	for callback: String in depths:
		if callback != "_exit_tree" and depths[callback] != 0: return false
	return true

func is_applying() -> bool:
	return not _applying.is_empty()

func threaded_claim_diagnostics() -> Dictionary:
	# Main observes its actual physical responsibilities. Original job/get
	# counters stay on S; do not counterfeit those counters or query S here.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitives == null or _primitives.get("_facade") != self: return {"success":false,"status":"INVALID","error":"actual_Main_physical_claim_owner_required"}
	var claims: Dictionary = _primitives.get("_claims")
	var outstanding := 0
	for path: String in claims:
		if not claims[path] is int or claims[path] <= 0: return {"success":false,"status":"INVALID","error":"invalid_actual_physical_claim_count"}
		outstanding += claims[path]
	return {"success":true,"contract_id":"hardcore.feature.actual_Main_claim_observation.v1","actual_owner_id":get_instance_id(),"bridge_generation":_primitives.get("_generation"),"actual_main_process_frame":Engine.get_process_frames(),"physical_claims":claims.duplicate(true),"outstanding_physical_claims":outstanding,"issued_claim_records":_primitives.get("_issued_claim_records").size(),"physical_retirements":_primitives.get("_retirements").size()}

func submit_original_call(method: String, arguments: Array) -> Variant:
	# Root routes a Main UI coroutine asynchronously to S. This is not a
	# blocking Main-to-S wait; resource native continuation goes S-to-M only.
	var admitted: Dictionary = _admit_original_owner_call(method,arguments)
	if admitted.get("status") != "MAIN_HELD": return admitted
	return await _owner_transport.await_original_feature_owner_result(admitted.ticket)

func prepare(catalog: Dictionary, enabled: Array) -> Dictionary:
	return await submit_original_call("prepare",[catalog,enabled])

func prepare_code_publication(expected_sha256: String, expected_bytes: int, callback: Callable, scope: RefCounted, consumer: Node, generation: int, publisher_sequence: int, export_contract: Dictionary = {}) -> Dictionary:
	return await submit_original_call("prepare_code_publication",[expected_sha256,expected_bytes,callback,scope,consumer,generation,publisher_sequence,export_contract])

func prepare_code_inputs(payload: Dictionary, entry_id: String, publisher: Node, scope: RefCounted, consumer: Node, generation: int) -> Dictionary:
	return await submit_original_call("prepare_code_inputs",[payload,entry_id,publisher,scope,consumer,generation])

func request_code_script(prepared: Dictionary, consumer: Node, generation: int) -> Dictionary:
	return await submit_original_call("request_code_script",[prepared,consumer,generation])

func retire_code_result(result: Dictionary) -> void:
	# Physical retirement primitive copied from the original service. It never
	# decides S admission or starts a second retirement/application queue.
	var resource: Variant = result.get("resource")
	var lease: Variant = result.get("lease")
	if resource is Resource and not (lease is RefCounted and is_same(lease.get_script(), Lease) and is_same(lease._retained_code_resource, resource)):
		retire_resources({resource.resource_path: resource})
	result.clear()

func code_result_retention_current(result: Dictionary, consumer: Node) -> bool:
	var lease: Variant = result.get("lease")
	var resource: Variant = result.get("resource")
	return bool(result.get("success", false)) and lease is RefCounted and is_same(lease.get_script(), Lease) and resource is Script and bool(lease.loaded_code_retention_current(resource, consumer, self))

func transfer_code_result_retention(result: Dictionary, previous: Node, next_consumer: Node) -> bool:
	if not code_result_retention_current(result, previous) or not is_instance_valid(next_consumer) or not next_consumer.is_inside_tree():
		return false
	var previous_script: Script = previous.get_script() as Script
	var next_script: Script = next_consumer.get_script() as Script
	if previous_script == null or next_script == null or previous_script.resource_path != "res://scripts/startup_loading.gd" or next_script.resource_path != "res://scripts/character_select.gd":
		return false
	return bool(result.lease.transfer_loaded_code_retention(result.resource, previous, next_consumer, self))

func transfer_prepared_world_code_retention(result: Dictionary, previous: Node, world_root: Node2D, scope: Dictionary) -> bool:
	# The sole admitted epoch-zero Main primitive may transfer the already
	# constructed selected Root's exact code lease. This does not invoke the
	# old scene-changing handoff or manufacture a second PackedScene instance.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _primitives == null or not _primitives.is_executing_original_primitive() or not code_result_retention_current(result,previous): return false
	var request: Dictionary = _primitives.get("_source_request")
	var site: Dictionary = request.get("site",{})
	if request.get("operation") != "feature.object_call" or request.get("arguments",[]).size() != 3 or request.arguments[1] != "source_application_call" or request.arguments[2] != ["claim_initial_code_retention",[site.get("world_context",{})]] or site.get("bootstrap") != true or site.get("clock_epoch") != 0 or site.get("domain") != "P": return false
	if not is_instance_valid(previous) or previous.get_script() != preload("res://scripts/character_select.gd") or previous != get_tree().current_scene or previous.get_instance_id() != scope.get("receiver_id"): return false
	if not is_instance_valid(world_root) or world_root.get_script() != preload("res://scripts/game_root.gd") or world_root.get_parent() != get_tree().root or world_root.get_instance_id() != site.get("world_context",{}).get("world_runtime_id") or world_root.get("current_map_id") != -1 or world_root.get("_zone_generation") != 0: return false
	var attachment: RefCounted = world_root.get("_original_source_main_attachment")
	if attachment == null or attachment.get("_root").get_ref() != world_root or attachment.get("_loading_scope") != scope or attachment.get("_ready_entered") != true or attachment.get("_exited") == true: return false
	var gate: RefCounted = get_tree().root.get_node("PlayerState").get("_source_domain_gate")
	if gate == null or gate.state() != "S": return false
	return bool(result.lease.transfer_loaded_code_retention(result.resource,previous,world_root,self))
