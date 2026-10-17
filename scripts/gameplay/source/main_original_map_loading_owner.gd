extends RefCounted

## Main observations and real pin references for the single original map leaf.
## This owns no scheduler, gameplay map, second loader or invented service Node.
const Graph := preload("res://scripts/gameplay/world/world_environment_value_graph.gd")
const Bridge := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const MapCode := preload("res://scripts/map_editor/map_editor_runtime_map_service.gd")
const Arrival := preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd")
const OverlayCode := preload("res://scripts/loading_transition_overlay.gd")
var _loading_ref: WeakRef
var _producer_ref: WeakRef
var _executor_ref: WeakRef
var _leaf_ref: WeakRef
var _root_ref: WeakRef
var _hud_ref: WeakRef
var _host: Object
var _descriptor: Dictionary = {}
var _current_world: Dictionary = {}
var _launch_scope: Dictionary = {}
var _scope_serial := 0
var _record: Dictionary = {}
var _resident: Dictionary = {}
var _retained_candidate: Dictionary = {}
var _arrival: Dictionary = {}
var _closing := false
var _terminal: Dictionary = {}
var _released_input: Dictionary = {}
var _release_receipt: Dictionary = {}

func configure_main(loading: RefCounted, producer: RefCounted, executor: RefCounted, leaf: RefCounted, root: Node2D, hud: Node, descriptor: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host != null: return _invalid("actual_once_Main_map_owner")
	if loading == null or producer == null or executor == null or leaf == null or not is_instance_valid(root) or not is_instance_valid(hud): return _invalid("actual_map_graph_required")
	if loading.get_script().resource_path != "res://scripts/gameplay/source/main_boot_launch_loading.gd" or producer.get_script().resource_path != "res://scripts/gameplay/source/main_map_loading_producer.gd" or executor.get_script().resource_path != "res://scripts/gameplay/world/world_map_event_main.gd" or leaf.get_script().resource_path != "res://scripts/gameplay/world/world_map_visual_main.gd": return _invalid("actual_original_map_scripts")
	if root.get_script() != preload("res://scripts/game_root.gd") or not root.is_inside_tree() or hud.get_parent() != root or root.get("hud") != hud or leaf.get("_background") != root.get("background") or leaf.get("_producer") != producer or executor.actual_map_leaf() != leaf: return _invalid("actual_same_Root_map_graph")
	if descriptor != executor.actual_owner_descriptor() or descriptor != leaf.get("_descriptor") or descriptor.get("world_context",{}).get("world_runtime_id") != root.get_instance_id(): return _invalid("actual_map_initial_descriptor")
	var launch: Dictionary = loading.actual_original_loading_scope(descriptor.world_context)
	if launch.is_empty() or loading.verify_actual_original_loading_scope(launch).get("success") != true: return _invalid("actual_original_launch_to_map_boundary")
	_loading_ref = weakref(loading); _producer_ref = weakref(producer); _executor_ref = weakref(executor); _leaf_ref = weakref(leaf); _root_ref = weakref(root); _hud_ref = weakref(hud)
	_host = producer.get("_host"); _descriptor = descriptor.duplicate(true); _current_world = descriptor.world_context.duplicate(true); _launch_scope = launch.duplicate(true)
	return {"success":true,"status":"READY","actual_owner_id":get_instance_id()}

func _actual(producer: RefCounted) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or producer == null or _host == null or _producer_ref == null or _producer_ref.get_ref() != producer or _leaf_ref.get_ref() == null or _executor_ref.get_ref() == null: return false
	var root: Node = _root_ref.get_ref()
	var hud: Node = _hud_ref.get_ref()
	return is_instance_valid(root) and is_instance_valid(hud) and root.is_inside_tree() and not root.is_queued_for_deletion() and root.get("hud") == hud and hud.get_parent() == root and _leaf_ref.get_ref().get("_background") == root.get("background") and _executor_ref.get_ref().actual_map_leaf() == _leaf_ref.get_ref()

func capture_current_cover(world: Dictionary, transition := "") -> Dictionary:
	if _producer_ref == null or not _actual(_producer_ref.get_ref()) or world != _current_world: return _invalid("actual_current_Root_map_cover")
	var hud: Node = _hud_ref.get_ref()
	var overlay: Variant = hud.get("loading_transition_overlay")
	if not overlay is Control or overlay.get_script() != OverlayCode or overlay.get_parent() != hud: return _invalid("actual_HUD_overlay_required")
	var covered: Dictionary = overlay.code_preparation_cover_receipt()
	if covered.is_empty() or not overlay.code_preparation_cover_current(covered) or (not transition.is_empty() and covered.get("transition_id") != transition): return _invalid("actual_presented_map_transition_cover")
	return {"success":true,"status":"READY","covered":covered.duplicate(true),"actual_root_id":_current_world.world_runtime_id,"actual_hud_id":hud.get_instance_id()}

func capture_current_context(world: Dictionary) -> Dictionary:
	if _producer_ref == null or not _actual(_producer_ref.get_ref()) or _closing or _record.is_empty() or _record.scope.state != "LOADING" or world != _current_world or _producer_ref.get_ref().get("_scope") != _record.scope or not _producer_ref.get_ref().get("_release_stage").is_empty() or not _producer_ref.get_ref().get("_release_requested_scope").is_empty(): return _invalid("actual_current_LOADING_Map_context")
	var covered: Dictionary = capture_current_cover(world,str(_record.scope.transition_id))
	if covered.get("success") != true: return covered
	if not _arrival.is_empty() and not _host.verify_committed_original_map_arrival(_arrival): return _invalid("actual_current_Map_arrival_proof")
	return {"success":true,"status":"READY","contract_id":"hardcore.main.current_map_loading.context.v1","world_context":_current_world.duplicate(true),"scope":_record.scope,"covered":covered.covered,"actual_owner_id":get_instance_id(),"actual_producer_id":_producer_ref.get_ref().get_instance_id(),"actual_arrival":_arrival.duplicate(true)}

func verify_current_source_site(site: Dictionary) -> Dictionary:
	if site.get("domain") != "P" or not site.get("clock_epoch") is int or site.clock_epoch < 0 or site.get("bootstrap") != (site.clock_epoch == 0) or not site.get("world_context") is Dictionary: return _invalid("actual_Map_Source_P_site")
	return capture_current_context(site.world_context)

func verify_release_source_site(site: Dictionary, scope: Dictionary) -> Dictionary:
	if site.get("domain") != "P" or not site.get("clock_epoch") is int or site.clock_epoch < 0 or site.get("bootstrap") != (site.clock_epoch == 0) or site.get("world_context") != _current_world: return _invalid("actual_Map_release_Source_P_site")
	if _producer_ref == null or not _actual(_producer_ref.get_ref()) or _record.is_empty() or not _terminal.is_empty(): return _invalid("actual_current_Map_release_owner")
	var producer: RefCounted = _producer_ref.get_ref()
	var stage: Dictionary = producer.get("_release_stage")
	var issued: bool = scope == _record.scope or scope == _released_input
	if not stage.is_empty() and scope == stage.get("loading_scope"): issued = true
	if not issued or scope.get("producer_runtime_id") != producer.get_instance_id() or scope.get("state") not in ["LOADING","RETAINED"]: return _invalid("actual_same_Map_release_ticket")
	if not _arrival.is_empty() and not _host.verify_committed_original_map_arrival(_arrival): return _invalid("actual_Map_release_arrival_proof")
	# Cleanup is justified by this producer's immutable issued ticket. Its old
	# cover remains historical evidence; hiding that cover cannot cancel debt.
	return {"success":true,"status":"READY","contract_id":"hardcore.main.current_map_release.context.v1","world_context":_current_world.duplicate(true),"requested_scope":scope.duplicate(true),"current_scope":_record.scope,"initial_launch_scope":_launch_scope,"covered":scope.get("actual_provenance",{}).get("covered",{}),"actual_owner_id":get_instance_id(),"actual_producer_id":producer.get_instance_id(),"actual_arrival":_arrival.duplicate(true)}

func capture_scope(producer: RefCounted, descriptor: Dictionary, transition: String, generation: int, map_id: int) -> Dictionary:
	if not _actual(producer) or _closing or descriptor != _descriptor or descriptor.world_context != _current_world or transition.is_empty() or generation < 0 or map_id < 0: return _invalid("actual_current_map_scope_request")
	if not _record.is_empty() and _record.scope.state == "LOADING":
		if _record.scope.owner_descriptor == descriptor and _record.scope.transition_id == transition and _record.scope.coordinator_generation == generation and _record.scope.map_id == map_id: return {"success":true,"status":"READY","scope":_record.scope}
		return _invalid("previous_Map_scope_still_LOADING")
	var covered: Dictionary = capture_current_cover(_current_world,transition)
	if covered.get("success") != true: return covered
	var leaf: RefCounted = _leaf_ref.get_ref()
	if leaf.has_pending_actual_original_map_claims(): return {"success":true,"status":"PENDING","error":"previous_actual_Map_claims_retained"}
	_scope_serial += 1
	var provenance := {"contract_id":"hardcore.main.map_loading.provenance.v1","actual_owner_id":get_instance_id(),"actual_root_id":_current_world.world_runtime_id,"actual_hud_id":covered.actual_hud_id,"actual_leaf_id":leaf.get_instance_id(),"actual_coordinator_id":leaf.get("_coordinator").get_instance_id(),"initial_launch_scope":_launch_scope,"covered":covered.covered,"actual_Main_process_frame":Engine.get_process_frames()}
	var scope := {"contract_id":"source.map.loading.scope.v1","bridge_generation":int(_host.capabilities().bridge_generation),"scope_id":_scope_serial,"producer_runtime_id":producer.get_instance_id(),"owner_descriptor":descriptor,"coordinator_generation":generation,"map_id":map_id,"transition_id":transition,"state":"LOADING","actual_provenance":provenance}
	var copied: Dictionary = Graph.copy_and_seal(scope)
	if not copied.ok: return _invalid("actual_Map_scope_not_plain")
	_record = {"scope":copied.value,"publication":{},"receipt":{},"resources":{}}
	_retained_candidate = {}; _arrival = {}; _released_input = {}; _release_receipt = {}
	return {"success":true,"status":"READY","scope":_record.scope}

func verify_scope(producer: RefCounted, scope: Dictionary, descriptor: Dictionary) -> bool:
	if not _actual(producer) or descriptor != _descriptor or _record.is_empty(): return false
	if scope != _record.scope and scope != _retained_candidate: return false
	if scope.state == "RETAINED" or _closing: return true
	var covered: Dictionary = capture_current_cover(_current_world,str(scope.transition_id))
	return covered.get("success") == true and covered.covered == scope.actual_provenance.covered

func _fingerprint(value: Variant) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256); hash.update(var_to_bytes(value))
	return hash.finish().hex_encode()

func _script_fact(code: Script) -> Dictionary:
	return {"resource_id":code.get_instance_id(),"path":code.resource_path,"source_sha256":code.get_source_code().sha256_text()}

func _resource_facts(resources: Dictionary) -> Array:
	var result: Array = []
	var paths: Array = resources.keys(); paths.sort()
	for path: String in paths:
		var resource: Resource = resources[path]
		if resource == null: return []
		result.append({"path":path,"resource_id":resource.get_instance_id(),"class":resource.get_class()})
	return result

func capture_publication(producer: RefCounted, scope: Dictionary, publication: Dictionary, coordinator: RefCounted, leaf: RefCounted) -> Dictionary:
	if not verify_scope(producer,scope,_descriptor) or scope.state != "LOADING" or leaf != _leaf_ref.get_ref() or coordinator != leaf.get("_coordinator") or coordinator.get_script() != preload("res://scripts/world_bootstrap_coordinator.gd"): return _invalid("actual_same_map_publication_owner")
	if coordinator.generation != scope.coordinator_generation or coordinator.has_failed_required_resource() or leaf.has_pending_actual_original_map_claims() or not publication.get("runtime_maps") is Dictionary: return _invalid("actual_Map_acquisition_not_ready")
	var background: Node = leaf.get("_background")
	if background.get("bootstrap_coordinator") != coordinator or background.get("_staged_build_map_id") != scope.map_id or background.get("_staged_generation") != scope.coordinator_generation: return _invalid("actual_Map_background_binding")
	for map_id: int in publication.runtime_maps:
		var row: Dictionary = publication.runtime_maps[map_id]
		if row.get("has_runtime_map") != Bridge.has_runtime_map(map_id) or row.get("runtime") != (Bridge.load_map(map_id) if Bridge.has_runtime_map(map_id) else {}): return _invalid("actual_static_MapService_value")
	var resources: Dictionary = coordinator.get("_prefetched_resources").duplicate(false)
	for path: String in coordinator.resource_manifest:
		var entry: Dictionary = coordinator.resource_manifest[path]
		if entry.get("required",true) and (entry.get("status") != "ready" or not resources.get(path) is Resource): return _invalid("actual_required_Map_resource_missing")
	var candidate := {"success":true,"status":"READY","contract_id":"hardcore.main.map_publication.receipt.v1","scope":scope,"actual_owner_id":get_instance_id(),"actual_leaf_id":leaf.get_instance_id(),"actual_coordinator_id":coordinator.get_instance_id(),"map_service_script":_script_fact(MapCode as Script),"map_bridge_script":_script_fact(Bridge as Script),"publication_sha256":_fingerprint(publication),"actual_resource_pins":_resource_facts(resources),"actual_Main_process_frame":Engine.get_process_frames()}
	var copied: Dictionary = Graph.copy_and_seal([publication,candidate])
	if not copied.ok: return _invalid("actual_Map_publication_not_plain")
	if not _record.receipt.is_empty(): return _record.receipt if copied.value[0] == _record.publication and candidate.publication_sha256 == _record.receipt.publication_sha256 and candidate.actual_resource_pins == _record.receipt.actual_resource_pins and candidate.map_service_script == _record.receipt.map_service_script and candidate.map_bridge_script == _record.receipt.map_bridge_script else _invalid("actual_Map_publication_conflict")
	# New actual resources are held before the old resident pin references drop.
	_record.resources = resources; _record.publication = copied.value[0]; _record.receipt = copied.value[1]
	_resident = {"resources":resources.duplicate(false),"receipt":_record.receipt}
	return _record.receipt

func verify_publication(producer: RefCounted, scope: Dictionary, publication: Dictionary, receipt: Dictionary) -> bool:
	return verify_scope(producer,scope,_descriptor) and scope == _record.scope and publication == _record.publication and receipt == _record.receipt and not receipt.is_empty() and receipt.actual_resource_pins == _resource_facts(_record.resources) and receipt.actual_resource_pins == _resource_facts(_leaf_ref.get_ref().get("_coordinator").get("_prefetched_resources")) and receipt.map_service_script == _script_fact(MapCode as Script) and receipt.map_bridge_script == _script_fact(Bridge as Script)

func can_apply_arrival(producer: RefCounted, transaction: Dictionary) -> bool:
	if not _actual(producer) or not Arrival.accepts(transaction) or not _host.verify_committed_original_map_arrival(transaction): return false
	if not _arrival.is_empty(): return transaction == _arrival and _current_world == transaction.after_world
	if _closing or _record.is_empty() or transaction.loading_scope != _record.scope or transaction.before_world != _current_world or transaction.source_root_id != _descriptor.source_root_id or transaction.owner_session_id != _descriptor.owner_session_id: return false
	var executor: RefCounted = _executor_ref.get_ref()
	# Native authenticates the retired eleven-field Source delivery. Main's
	# immutable original reply has nine fields; only Native's two observation
	# fields are removed for comparison, never any original execution fact.
	var delivered: Dictionary = transaction.finish_reply.duplicate(true)
	if delivered.size() != 11 or not delivered.has_all(["request","native_s_poll_epoch"]): return false
	delivered.erase("request"); delivered.erase("native_s_poll_epoch")
	return not executor.has_pending_original_map_reply() and executor.verify_actual_original_map_reply(transaction.finish_identity,delivered) and delivered.get("source_request",{}).get("operation") == "finish_visual" and delivered.get("source_request",{}).get("scope") == _record.scope and delivered.get("result",{}).get("ok") == true and not _record.receipt.is_empty()

func apply_arrival(producer: RefCounted, transaction: Dictionary) -> bool:
	if not can_apply_arrival(producer,transaction): return false
	if _arrival.is_empty(): _arrival = transaction.duplicate(true); _current_world = transaction.after_world.duplicate(true)
	return true # Old scope/descriptor/publication/lease identities remain exact.

func prepare_release(producer: RefCounted, scope: Dictionary) -> Dictionary:
	if not _actual(producer): return _invalid("actual_Map_release_owner")
	if scope == _released_input and not _release_receipt.is_empty(): return _release_receipt
	if _record.is_empty() or scope != _record.scope or scope.state != "LOADING": return _invalid("actual_original_LOADING_scope_required")
	if _executor_ref.get_ref().has_pending_original_map_reply(): return {"success":true,"status":"PENDING","error":"accepted_Map_reply_retained"}
	var drained: Dictionary = _leaf_ref.get_ref().service_actual_original_map_claim_retirement()
	if drained.get("status") != "READY": return drained
	_retained_candidate = scope.duplicate(true); _retained_candidate.state = "RETAINED"
	_retained_candidate = Graph.copy_and_seal(_retained_candidate).value
	return {"success":true,"status":"READY","scope":_retained_candidate,"actual_io":drained}

func commit_release(producer: RefCounted, loading_scope: Dictionary, retained_scope: Dictionary, descriptor: Dictionary) -> Dictionary:
	if not _actual(producer): return _invalid("actual_Map_release_commit_owner")
	if loading_scope == _released_input and not _release_receipt.is_empty(): return _release_receipt
	var expected: Dictionary = _descriptor.duplicate(true); expected.world_context = _current_world
	if retained_scope != _retained_candidate or loading_scope != _record.scope or descriptor != expected: return _invalid("actual_RETAINED_route_commit")
	_record.scope = _retained_candidate
	_descriptor = descriptor.duplicate(true); _released_input = loading_scope.duplicate(true)
	_release_receipt = Graph.copy_and_seal({"success":true,"status":"READY","scope":retained_scope,"released_scope":loading_scope,"current_owner_descriptor":_descriptor,"actual_owner_id":get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}).value
	return _release_receipt

func begin_terminal(producer: RefCounted) -> Dictionary:
	if not _actual(producer) or _host.status().get("close_requested") != true: return _invalid("actual_Native_close_required")
	_closing = true
	var status: Dictionary = _host.status()
	if _executor_ref.get_ref().has_pending_original_map_reply() or status.get("caster_reply_obligations_quiescent") != true or status.get("original_primitive_in_flight") == true or int(status.get("unsettled_original_published_prefixes",0)) != 0: return {"success":true,"status":"PENDING","error":"actual_Source_Map_retirement_still_owned"}
	var actual: Dictionary = _leaf_ref.get_ref().service_actual_original_map_terminal()
	actual.accepted_boundary_drained = true
	return actual

func capture_terminal(producer: RefCounted, descriptor: Dictionary, scope: Dictionary, facts: Dictionary) -> Dictionary:
	if not _actual(producer) or not _closing or descriptor != _descriptor or (not _record.is_empty() and scope != _record.scope) or _executor_ref.get_ref().has_pending_original_map_reply(): return _invalid("actual_Map_terminal_boundary")
	var actual: Dictionary = _leaf_ref.get_ref().inspect_actual_original_map_io()
	if actual != facts or actual.get("terminal") != true or actual.get("actual_transfer",{}).get("status") != "READY" or actual.get("actual_transfer",{}).get("observer_released") != true or actual.get("actual_prefetched_paths",[1]).size() != 0 or actual.get("actual_live_visual_ids",[1]).size() != 0: return {"success":true,"status":"PENDING","error":"actual_Map_physical_owners_retained"}
	if not _terminal.is_empty(): return _terminal
	var released_pins: int = _resident.get("resources",{}).size()
	_record = {"scope":scope,"publication":{},"receipt":{},"resources":{}}
	_resident = {}
	_terminal = Graph.copy_and_seal({"success":true,"status":"READY","contract_id":"hardcore.main.map_owner.terminal.v1","actual_owner_id":get_instance_id(),"producer_runtime_id":producer.get_instance_id(),"owner_descriptor":descriptor,"scope":scope,"actual_io":actual,"actual_released_pin_count":released_pins,"actual_remaining_pin_count":0,"actual_Main_process_frame":Engine.get_process_frames()}).value
	return _terminal

func verify_terminal(producer: RefCounted, descriptor: Dictionary, scope: Dictionary, facts: Dictionary, receipt: Dictionary) -> bool:
	return _actual(producer) and _closing and not _terminal.is_empty() and receipt == _terminal and descriptor == _descriptor and scope == _record.scope and _resident.is_empty() and _record.resources.is_empty() and facts.get("terminal") == true and facts == _leaf_ref.get_ref().inspect_actual_original_map_io() and facts.actual_transfer.status == "READY" and facts.actual_transfer.get("observer_released") == true and not _executor_ref.get_ref().has_pending_original_map_reply()

func inspect_lifecycle() -> Dictionary:
	return {"success":true,"status":"READY" if not _terminal.is_empty() else "RETAINED","actual_owner_id":get_instance_id(),"current_world":_current_world,"scope":_record.get("scope",{}),"owner_descriptor":_descriptor,"arrival_staged":not _arrival.is_empty(),"closing":_closing,"resident_pin_count":_resident.get("resources",{}).size(),"active_pin_count":_record.get("resources",{}).size(),"terminal":not _terminal.is_empty()}

func _invalid(error: String) -> Dictionary: return {"success":false,"status":"INVALID","error":error}
