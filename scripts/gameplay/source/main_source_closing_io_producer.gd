extends RefCounted
## Actual Main IO witness, using the same physical Feature claim ledger and
## three caster-attached progress operations. No resource scheduling here.
const WARM_PATH := "res://scripts/gameplay/world/world_caster_warm_main.gd"
const CONTENT_PATH := "res://scripts/layers/runtime/content_layer_registry.gd"
const FEATURE_PATH := "res://scripts/features/runtime/feature_resource_main_primitives.gd"
const IssuedClaimIdentity := preload("res://scripts/features/runtime/issued_claim_identity.gd")
var _host: Object
var _content: Node
var _feature: RefCounted
var _observer: RefCounted
var _bound: Dictionary={}
var _terminal_delivered: Dictionary={}
var _session_id := 0
var _session_views: RefCounted
var _session_pump: RefCounted
var _session_transport: RefCounted
var _session_prefix: RefCounted
var _session_streaming: RefCounted
var _session_registry: RefCounted
var _session_caster: RefCounted
var _session_root_id := 0

func bind_actual_session_io(session_id: int, views: RefCounted, pump: RefCounted, transport: RefCounted) -> bool:
	if not _main() or _session_id != 0 or session_id <= 0 or views == null or pump == null or transport == null: return false
	if views.get_script() != preload("res://scripts/gameplay/world/world_main_views.gd") or pump.get_script() != preload("res://scripts/gameplay/source/main_original_resource_pump.gd") or transport.get_script() != preload("res://scripts/gameplay/source/main_session_transport.gd"): return false
	var prefix: RefCounted = pump.get("_prefix")
	var streaming: RefCounted = pump.get("_streaming")
	var registry: RefCounted = views.get("_renderer_registry")
	var caster: RefCounted = views.get("_caster")
	var root: Node2D = views.get("_root")
	if prefix == null or streaming == null or registry == null or caster == null or not is_instance_valid(root) or caster.get("_root") != root: return false
	if pump.get("_host") != _host or transport.get("_host") != _host or not is_same(views.get("_feature"),_feature) or not is_same(views.get("_vault"),streaming) or prefix.get("_host") != _host or registry.get("_root") != root or views.get("_actual_budget_session_id") != session_id: return false
	_session_id = session_id; _session_views = views; _session_pump = pump; _session_transport = transport
	_session_prefix = prefix; _session_streaming = streaming; _session_registry = registry; _session_caster = caster; _session_root_id = root.get_instance_id()
	return true

func _actual_collection_counts(owner: Object, fields: Array) -> Dictionary:
	if owner == null or not is_instance_valid(owner): return {"success":false,"error":"actual_collection_owner_missing"}
	var counts := {}; var total := 0
	for field: String in fields:
		var value: Variant = owner.get(field)
		if not value is Dictionary and not value is Array: return {"success":false,"error":"actual_collection_missing:"+field}
		counts[field] = value.size(); total += value.size()
	return {"success":true,"counts":counts,"total":total}

func capture_actual_original_session_io() -> Dictionary:
	if not _main() or _session_id <= 0: return _fail("actual_session_IO_binding_required")
	var parts := {}
	parts.feature = _actual_collection_counts(_feature,["_claims","_retirements","_owner_calls","_retentions","_issued_claim_records","_issued_live_pending_paths","_issued_claim_facts","_command_reference_loans","_normal_live_jobs"])
	parts.streaming = _actual_collection_counts(_session_streaming,["_accepted_claims","_get_escrow","_texture_roots","_texture_references","_renderers"])
	var assets: Variant = _session_streaming.get("_actor_assets")
	if not assets is RefCounted: return _fail("actual_actor_asset_subledger_required")
	parts.actor_assets = _actual_collection_counts(assets,["_templates","_owners","_audio_references","_aux_references"])
	parts.registry = _actual_collection_counts(_session_registry,["_actors","_retiring"])
	parts.caster = _actual_collection_counts(_session_caster,["_casts","_visuals","_cells","_batches","_cell_controller","_created_nodes","_live_reply_nodes","_claimed_event","_claimed_ticket","_paths","_textures"])
	parts.transport = _actual_collection_counts(_session_transport,["_pending","_acks","_ack_submitted","_results","_notifications","_hud","_feature_calls","_feature_acks","_feature_ack_submitted"])
	parts.pump = _actual_collection_counts(_session_pump,["_held","_published","_live_held"])
	for name: String in parts:
		if parts[name].get("success") != true: return _fail("actual_session_IO_collection:"+name)
	var warm: Dictionary = inspect_actual_original_main_warm_io()
	if warm.get("status") not in ["READY","PENDING"]: return warm
	var ui: Dictionary = _session_views.capture_actual_original_ui_close_state()
	if ui.get("success") != true: return ui
	var native: Dictionary = _host.status()
	if not native.get("map_owner_closed") is bool: return _fail("actual_Native_map_owner_state_required")
	var prepared_shell: Variant = _session_registry.get("_prepared_player_shell")
	var renderer_gone: bool = parts.registry.total == 0 and not is_instance_valid(prepared_shell)
	var drained: bool = parts.feature.total == 0 and parts.streaming.total == 0 and parts.actor_assets.total == 0 and parts.caster.total == 0 and renderer_gone and parts.transport.total == 0 and not _session_prefix.has_pending() and parts.pump.total == 0 and warm.status == "READY" and ui.terminal and native.map_owner_closed and _session_streaming.get("_live_transfer_completed") == true and _session_caster.get("_awaiting_reply") == false
	return {"contract_id":"hardcore.source.main_io_observation.v1","owner_session_id":_session_id,"bridge_generation":_feature.get("_generation"),"world_runtime_id":_session_root_id,"actual_main_process_frame":Engine.get_process_frames(),"actual_wall_usec":Time.get_ticks_usec(),"actual_io_producer_id":get_instance_id(),"physical_owners_retained":true,"status":"BUSINESS_DRAINED" if drained else "OWNERS_RETAINED","parts":parts,"warm":warm,"ui":ui,"map_owner_closed":native.map_owner_closed,"map_terminal":capture_actual_original_map_terminal_state(),"main_applied_prefix":native.get("original_main_applied_prefix"),"feature_command_acknowledgements":_session_transport.actual_original_feature_closing_acknowledgements()}
func configure_main(host: Object, content: Node, feature: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null: return _fail("actual_Main_once_required")
	if not is_instance_valid(content) or content.get_script().resource_path!=CONTENT_PATH or not content.is_inside_tree() or feature==null or feature.get_script().resource_path!=FEATURE_PATH: return _fail("actual_Main_ContentLayers_Feature_required")
	for method: String in ["offer_claim_transfer","confirm_origin_released","bind_original_main_warm_claim_origin_producer","capabilities"]:
		if host==null or not host.has_method(method): return _fail("MISSING:Native_caster_attached_claim:"+method)
	if not feature.configure_original_issued_claim_bridge(host): return _fail("actual_Main_Feature_claim_registration_failed")
	_host=host;_content=content;_feature=feature;_observer=ClassDB.instantiate("HardCoreResourceObservation")
	if _observer==null or not host.bind_original_main_warm_claim_origin_producer(self,get_script().get_source_code().sha256_text()): return _fail("actual_Main_origin_observer_binding_failed")
	return {"success":true}
func bind_original_caster_warm_io_observer(helper: RefCounted, sha: String, descriptor: Dictionary) -> Dictionary:
	if not _main() or helper==null or helper.get_script().resource_path!=WARM_PATH or helper.get_script().get_source_code().sha256_text()!=sha or helper.get("_content")!=_content or helper.get("_owner_descriptor")!=descriptor: return _fail("actual_Warm_origin_provenance_required")
	if descriptor.size()!=5 or descriptor.get("contract_id")!="source.caster.warm.owner.v1" or descriptor.get("source_root_id",0)==0 or int(descriptor.get("owner_session_id",0))<=0 or helper.get("_caster")==null or descriptor.get("main_executor_id")!=helper.get("_caster").get_instance_id(): return _fail("actual_Warm_owner_descriptor_required")
	var id: int=helper.get_instance_id()
	if _bound.has(id): return _fail("actual_Warm_observer_duplicate")
	_bound[id]={"helper":helper,"sha256":sha,"descriptor":descriptor.duplicate(true)}
	return {"success":true,"actual_owner_descriptor":descriptor}
func capture_original_issued_claim_evidence(helper: RefCounted, identity: Dictionary, path: String, count: int, process_frame: int) -> Dictionary:
	if not _actual_helper(helper) or count!=1 or helper.get("_loading_claims").get(path)!=true or process_frame<0: return _fail("actual_original_loading_claim_required")
	var parent: Dictionary=identity.duplicate(true);parent.erase("transfer_sequence")
	if parent!=helper.get("_active_ticket"): return _fail("actual_accepted_caster_parent_required")
	var observation: Dictionary=_observer.threaded_status(path,process_frame,int(_host.capabilities().bridge_generation))
	if observation.get("ok")!=true: return _fail("actual_Native_loader_observation_failed")
	return {"contract_id":"hardcore.caster.issued_claim.offer.v1","identity":identity,"owner_descriptor":helper.get("_owner_descriptor").duplicate(true),"path":path,"claim_count":count,"actual_main_root_id":helper.get("_original_main_root_id"),"actual_content_id":_content.get_instance_id(),"actual_helper_id":helper.get_instance_id(),"actual_feature_main_id":_feature.get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames(),"loader_observation":observation}
func verify_original_warm_claim_offer_origin(identity: Dictionary, evidence: Dictionary) -> Dictionary:
	if not _main() or evidence.size()!=11 or evidence.get("identity")!=identity or evidence.get("actual_content_id")!=_content.get_instance_id() or evidence.get("actual_feature_main_id")!=_feature.get_instance_id(): return _fail("actual_claim_origin_evidence_required")
	var id: int=int(evidence.get("actual_helper_id",0))
	if not _bound.has(id): return _fail("actual_Warm_helper_not_bound")
	var helper: RefCounted=_bound[id].helper
	if helper.get("_loading_claims").get(evidence.path)!=true or helper.get("_issued_loading_offers").get(evidence.path,{}).get("evidence")!=evidence: return _fail("actual_frozen_original_claim_required")
	return {"success":true,"identity":identity,"evidence":evidence}
func verify_original_warm_claim_origin_released(identity: Dictionary, evidence: Dictionary) -> Dictionary:
	if not _main() or not _bound.has(int(evidence.get("actual_helper_id",0))): return _fail("actual_Warm_origin_owner_required")
	var helper: RefCounted=_bound[evidence.actual_helper_id].helper
	var transfer: Dictionary=helper.get("_transfers").get(evidence.path,{})
	if helper.get("_loading_claims").has(evidence.path) or transfer.get("issued_claim_identity")!=identity or transfer.get("issued_claim_evidence")!=evidence: return _fail("actual_original_origin_deletion_required")
	return {"success":true,"identity":identity,"evidence":evidence}
func inspect_actual_original_threaded_claim_transfer(transfer: Dictionary) -> Dictionary:
	if not _main() or not transfer.get("issued_claim_identity") is Dictionary: return _fail("actual_transfer_identity_required")
	var key: String=IssuedClaimIdentity.key(transfer.issued_claim_identity)
	if _terminal_delivered.has(key):
		if _terminal_delivered[key].actual_transfer!=transfer: return _fail("actual_terminal_delivery_conflict")
		return _terminal_delivered[key]
	var state: Dictionary=_feature.original_issued_claim_transfer_state(transfer.issued_claim_identity)
	if state.get("state") in ["OFFERED","ACCEPTED","ORIGIN_RELEASED"] or state.get("status") in ["BUSY","BACKPRESSURE"]: return {"status":"PENDING"}
	if state.get("state")!="TERMINAL" or state.get("evidence")!=transfer.get("issued_claim_evidence") or not state.get("terminal_receipt") is Dictionary: return _fail("actual_physical_range_and_FIFO_terminal_unproved")
	var actual: Dictionary={"status":"READY","actual_transfer":transfer,"actual_claims_terminal":true,"native_retirement_receipt":state.terminal_receipt}
	if not _feature.acknowledge_original_issued_claim_terminal_delivery(transfer.issued_claim_identity): return _fail("actual_Main_terminal_delivery_not_sealed")
	_terminal_delivered[key]=actual
	return actual
func release_original_caster_warm_io_observer(helper: RefCounted, descriptor: Dictionary) -> Dictionary:
	if not _actual_helper(helper) or _bound[helper.get_instance_id()].descriptor!=descriptor: return _fail("actual_Warm_observer_required")
	var io: Dictionary=helper.inspect_actual_original_caster_warm_io()
	if io.get("retirement_requested")!=true or not io.frame_texture_threaded.is_empty() or not io.loading_texture_threaded.is_empty() or not io.persistent_transfers.is_empty() or not helper.get("_issued_loading_offers").is_empty(): return _fail("actual_Warm_obligations_not_terminal")
	for key: String in _terminal_delivered.keys():
		if _terminal_delivered[key].actual_transfer.issued_claim_evidence.actual_helper_id==helper.get_instance_id(): _terminal_delivered.erase(key)
	_bound.erase(helper.get_instance_id())
	return {"success":true,"actual_owner_descriptor":descriptor}
func inspect_actual_original_main_warm_io() -> Dictionary:
	if not _main(): return _fail("actual_Main_observer_required")
	var values: Array[Dictionary]=[]
	var terminal := true
	for row: Dictionary in _bound.values():
		if not _actual_helper(row.helper): return _fail("actual_bound_Warm_source_changed")
		var actual: Dictionary=row.helper.inspect_actual_original_caster_warm_io()
		values.append(actual)
		terminal=terminal and actual.retirement_requested and actual.frame_texture_threaded.is_empty() and actual.loading_texture_threaded.is_empty() and actual.persistent_transfers.is_empty() and row.helper.get("_issued_loading_offers").is_empty()
	return {"status":"READY" if terminal else "PENDING","actual_producer_id":get_instance_id(),"actual_content_id":_content.get_instance_id(),"observers":values,"actual_Main_process_frame":Engine.get_process_frames()}
func _actual_helper(helper: RefCounted) -> bool:
	return _main() and helper!=null and _bound.has(helper.get_instance_id()) and _bound[helper.get_instance_id()].helper==helper and helper.get_script().get_source_code().sha256_text()==_bound[helper.get_instance_id()].sha256
func _main() -> bool: return OS.get_thread_caller_id()==OS.get_main_thread_id() and _host!=null
func _fail(code: String) -> Dictionary: return {"success":false,"status":"INVALID","error":code}

## Map observers are separate from the immutable Caster registration/claim
## ledger. The real Map leaf keeps accepted tokens until its terminal get.
var _actual_map_observers: Dictionary = {}
var _actual_map_terminals: Dictionary = {}
var _actual_map_terminal_producers: Dictionary = {}
func bind_actual_original_map_io_observer(producer: RefCounted, leaf: RefCounted, descriptor: Dictionary) -> Dictionary:
	if not _main() or producer == null or leaf == null or producer.get_script().resource_path != "res://scripts/gameplay/source/main_map_loading_producer.gd" or leaf.get_script().resource_path != "res://scripts/gameplay/world/world_map_visual_main.gd" or leaf.get("_producer") != producer or leaf.get("_descriptor") != descriptor: return _fail("actual_Map_origin_graph")
	var coordinator: RefCounted = leaf.get("_coordinator")
	if coordinator == null or coordinator.get_script() != preload("res://scripts/world_bootstrap_coordinator.gd") or descriptor.get("contract_id") != "source.map.loading.owner.v1" or descriptor.size() != 5: return _fail("actual_Map_coordinator_descriptor")
	var id := leaf.get_instance_id()
	if _actual_map_observers.has(id) or _actual_map_terminals.has(id): return _fail("actual_Map_observer_already_bound")
	_actual_map_observers[id] = {"leaf":weakref(leaf),"producer":weakref(producer),"coordinator":weakref(coordinator),"leaf_sha256":leaf.get_script().get_source_code().sha256_text(),"registration_descriptor":descriptor.duplicate(true)}
	_actual_map_terminal_producers[id] = weakref(producer)
	return {"success":true,"status":"READY","actual_owner_descriptor":descriptor}

func inspect_actual_original_map_claim_transfer(producer: RefCounted, leaf: RefCounted, descriptor: Dictionary, coordinator: RefCounted) -> Dictionary:
	if not _main() or leaf == null or producer == null or coordinator == null: return _fail("actual_Map_IO_objects")
	var id := leaf.get_instance_id()
	if _actual_map_terminals.has(id):
		var terminal: Dictionary = _actual_map_terminals[id]
		return terminal if terminal.actual_producer_id == producer.get_instance_id() and terminal.actual_coordinator_id == coordinator.get_instance_id() and terminal.owner_descriptor == descriptor and not leaf.has_pending_actual_original_map_claims() else _fail("actual_Map_terminal_conflict")
	if not _actual_map_observers.has(id): return _fail("actual_Map_observer_not_registered")
	var row: Dictionary = _actual_map_observers[id]
	if row.leaf.get_ref() != leaf or row.producer.get_ref() != producer or row.coordinator.get_ref() != coordinator or leaf.get("_producer") != producer or leaf.get("_descriptor") != descriptor or leaf.get_script().get_source_code().sha256_text() != row.leaf_sha256: return _fail("actual_Map_observer_identity_changed")
	var pending: Dictionary = {}
	for path: String in coordinator.resource_manifest:
		var entry: Dictionary = coordinator.resource_manifest[path]
		if entry.get("status") == "requested": pending[path] = int(entry.get("claim_count",1))
	for path: String in coordinator.get("_retired_threaded_requests"):
		pending[path] = int(pending.get(path,0))+int(coordinator.get("_retired_threaded_requests")[path].get("claim_count",0))
	for path: String in leaf.get("_actual_retiring_claims"):
		pending[path] = int(pending.get(path,0))+int(leaf.get("_actual_retiring_claims")[path].remaining)
	var observations: Array = []
	for path: String in pending:
		var observed: Dictionary = _observer.threaded_status(path,Engine.get_process_frames(),int(_host.capabilities().bridge_generation))
		if observed.get("ok") != true: return _fail("actual_Native_Map_loader_observation")
		observations.append({"path":path,"remaining":pending[path],"observation":observed})
	return {"status":"READY" if pending.is_empty() else "PENDING","contract_id":"hardcore.main.map_io.observation.v1","actual_producer_id":producer.get_instance_id(),"actual_leaf_id":id,"actual_coordinator_id":coordinator.get_instance_id(),"actual_content_id":_content.get_instance_id(),"actual_observer_id":_observer.get_instance_id(),"owner_descriptor":descriptor.duplicate(true),"registration_descriptor":row.registration_descriptor,"actual_pending_claim_counts":pending,"actual_loader_observations":observations,"actual_claim_history":leaf.get("_actual_claim_history").duplicate(true),"actual_claims_terminal":pending.is_empty(),"actual_transfer_performed":false,"actual_retirement_started":leaf.get("_actual_retirement_started"),"actual_Main_process_frame":Engine.get_process_frames()}

func release_actual_original_map_io_observer(producer: RefCounted, leaf: RefCounted, descriptor: Dictionary, coordinator: RefCounted) -> Dictionary:
	var actual: Dictionary = inspect_actual_original_map_claim_transfer(producer,leaf,descriptor,coordinator)
	if actual.get("status") != "READY" or leaf.get("_actual_terminal_started") != true: return _fail("actual_Map_terminal_observer_required")
	if not leaf.call("_actual_live_visual_ids").is_empty() or not coordinator.get("_prefetched_resources").is_empty(): return {"success":true,"status":"PENDING"}
	actual = actual.duplicate(true); actual.success = true; actual.observer_released = true
	_actual_map_terminals[leaf.get_instance_id()] = actual
	_actual_map_observers.erase(leaf.get_instance_id())
	return actual

func capture_actual_original_map_terminal_state() -> Dictionary:
	if not _main() or _host.status().get("map_owner_closed") != true or _actual_map_terminals.size() != 1 or not _actual_map_observers.is_empty(): return {"success":true,"status":"PENDING"}
	var id: int = _actual_map_terminals.keys()[0]
	var producer: RefCounted = _actual_map_terminal_producers[id].get_ref()
	if producer == null or producer.get("_host") != _host: return _fail("actual_Map_terminal_producer_retired")
	var receipt: Dictionary = producer.get("_terminal")
	if receipt.get("contract_id") != "hardcore.main.map_owner.terminal.v1" or receipt.get("producer_runtime_id") != _actual_map_terminals[id].actual_producer_id or not producer.verify_actual_original_map_owner_terminal(receipt): return _fail("actual_certified_Map_terminal_receipt")
	return {"success":true,"status":"READY","contract_id":"hardcore.main.map_terminal.observation.v1","actual_producer_id":producer.get_instance_id(),"actual_map_owner_terminal":receipt.duplicate(true),"actual_origin_id":get_instance_id(),"actual_native_map_owner_closed":true}
