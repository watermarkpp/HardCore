extends RefCounted
const Handoff := preload("res://scripts/gameplay/profile/profile_state_handoff.gd")
const Gate := preload("res://scripts/gameplay/source/main_profile_source_gate.gd")
const Lease := preload("res://scripts/features/contracts/feature_resource_lease.gd")
const Pump := preload("res://scripts/layers/runtime/execution/paused_receipt_pump.gd")
const ProcessScope := preload("res://scripts/gameplay/source/main_original_process_scope.gd")
var _facade: Node
var _content: Node
var _legacy_resources: Node
var _primitive_facade: Node
var _main_primitives: RefCounted
var _deferred: RefCounted
var _router: RefCounted
var _pins: RefCounted
var _gate: RefCounted
var _prepared: Dictionary={}
var _source_state: Dictionary={}
var _old_flags: Array[Dictionary]=[]
var _serial:=0
var _committed:=false
var _physical_handoff: Dictionary = {}
var _catalog_signal_connected:=false
var _actual_native_host: Object
var _actual_native_scope: Dictionary = {}

func retire_actual_unstarted_Main_binding(receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _actual_native_host == null or _committed or not _prepared.is_empty(): return false
	if not _actual_native_scope.is_empty() and _actual_native_scope.get("state") != "ABORTED": return false
	var state: Dictionary = _actual_native_host.status()
	if receipt.get("status") != "ABORTED_BEFORE_START" or receipt.get("success") != true or receipt.get("host_object_id") != _actual_native_host.get_instance_id() or state.get("main_channels_aborted") != true or state.get("started") != false or state.get("physics_handoff_prepared") != false: return false
	if _gate == null or _gate.state() != "MAIN" or not _gate.denied_source_writes().is_empty() or _facade.get("_source_domain_gate") != _gate: return false
	# This owner installed this exact gate. Native has now unbound the same
	# never-started graph; the original Main Model itself is never replaced.
	_facade.set("_source_domain_gate",null)
	# Native has retired the same unclaimed ABORTED scope and unbound this
	# exact producer. Keep its immutable receipt until that factual proof.
	_actual_native_scope = {}
	_gate = null; _router = null; _deferred = null; _pins = null
	_main_primitives = null; _actual_native_host = null
	_legacy_resources = null; _primitive_facade = null; _content = null; _facade = null
	return true

func bind_actual_original_native_host(host: Object) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _actual_native_host != null or _main_primitives == null or host == null or not host.is_class("HardCoreSimulationHost"): return false
	var validate: Callable = _main_primitives.get("_validate")
	if not validate.is_valid() or validate.get_object() != host or validate.get_method() != &"validate_original_primitive_ticket": return false
	_actual_native_host = host
	return true

func publish_actual_original_prepared_scope(world: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _actual_native_host == null or _prepared.is_empty() or _committed or _gate.state() != "PREPARED" or world.get("profile_id") != _prepared.profile_id: return _fail("actual_native_prepared_scope_owner_required")
	var scope := {"contract_id":"hardcore.main.source.admission_scope.v1","bridge_generation":_actual_native_host.capabilities().bridge_generation,"scope_id":_prepared.serial,"producer_runtime_id":get_instance_id(),"profile_id":_prepared.profile_id,"state":"PREPARED","world_context":world.duplicate(true),"receipt":_prepared.duplicate(true),"publication":_source_state}
	if ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false):
		var sizes: Dictionary = {}
		for key: String in scope: sizes[key] = {"type":typeof(scope[key]),"bytes":var_to_bytes(scope[key]).size()}
		print("HC_MAIN_ADMISSION_SCOPE_DIAGNOSTIC ",JSON.stringify({"scope_fields":scope.size(),"wire_bytes":var_to_bytes(scope).size(),"fields":sizes,"gate":_gate.state(),"prepared_equal":scope.receipt==_prepared,"publication_equal":scope.publication==_source_state,"world":world}))
	if not _actual_native_scope.is_empty(): return {"success":true,"scope":_actual_native_scope} if _actual_native_scope == scope else _fail("actual_native_scope_identity_changed")
	var result: Dictionary = _actual_native_host.publish_original_source_admission_scope(scope)
	if result.get("status") != "READY": return _fail("actual_native_prepared_scope_not_published",result)
	_actual_native_scope = scope
	return {"success":true,"scope":scope}

func _publish_actual_native_scope_transition(state: String) -> bool:
	if _actual_native_scope.is_empty(): return true # Legacy non-Host callers own no Native scope.
	var next: Dictionary = _actual_native_scope.duplicate(true)
	next.state = state
	var result: Dictionary = _actual_native_host.publish_original_source_admission_scope(next)
	if result.get("status") != "READY": return false
	_actual_native_scope = next
	return true

func configure_main(facade: Node,content: Node,legacy_resources: Node,primitive_facade: Node,primitives: RefCounted,deferred: RefCounted,router: RefCounted,pin_inspector: RefCounted) -> Dictionary:
	var errors: Array[String]=[]
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _facade!=null: errors.append("actual_Main_once_required")
	if not is_instance_valid(facade) or facade.get_script()!=preload("res://scripts/player_state.gd") or facade.get_tree().root.get_node_or_null("PlayerState")!=facade: errors.append("actual_PlayerState_autoload_required")
	if not is_instance_valid(content) or content.get_script()!=preload("res://scripts/layers/runtime/content_layer_registry.gd"): errors.append("actual_ContentLayers_required")
	if not is_instance_valid(legacy_resources) or legacy_resources.get_script()!=preload("res://scripts/features/runtime/feature_resource_preparation.gd"): errors.append("original_physical_resource_coordinator_required")
	if not is_instance_valid(primitive_facade) or primitive_facade.get_script()!=preload("res://scripts/features/runtime/feature_resource_main_facade.gd") or not primitive_facade.is_inside_tree(): errors.append("actual_registered_Main_primitive_facade_required")
	for spec: Array in [[primitives,["handoff_original_physical_leases"]],[deferred,["flush_original_main_source_checkpoint","observe_original_main_source_receivers"]],[router,["verify_original_profile_ui_receiver_closure","reject_original_main_profile_writer","submit_original_profile_command","request_original_profile_notification","capture_original_profile_ui_view","verify_original_loading_source_site"]],[pin_inspector,["inspect_actual_original_loading_pins","release_original_loading_pin_closure"]]]:
		for method: String in spec[1]:
			if spec[0]==null or not spec[0].has_method(method): errors.append("MISSING:actual_original_Main_service:"+method)
	if not errors.is_empty(): return {"success":false,"errors":errors}
	_facade=facade; _content=content; _legacy_resources=legacy_resources; _primitive_facade=primitive_facade
	_main_primitives=primitives; _deferred=deferred; _router=router; _pins=pin_inspector
	_gate=Gate.new()
	if not _gate.configure_main(facade,router) or not facade.install_original_profile_source_gate(_gate): return {"success":false,"errors":["actual_original_Main_gate_installation_failed"]}
	return {"success":true}

static func capture_original_source_deferred_configuration() -> Dictionary:
	assert(OS.get_thread_caller_id()==OS.get_main_thread_id())
	var megabytes:=int(ProjectSettings.get_setting("memory/limits/message_queue/max_size_mb",32))
	return {"source_deferred_max_pages":megabytes*256,"source_process_frame":Engine.get_process_frames(),"source_physics_frame":Engine.get_physics_frames(),"setting":"memory/limits/message_queue/max_size_mb","setting_value_mb":megabytes,"page_size_bytes":4096}

func prepare_actual_loaded_source(original_checkpoint: Dictionary) -> Dictionary:
	if _facade==null or _committed or not _prepared.is_empty(): return _fail("actual_original_source_not_available")
	# Original UI registration and Main source receiver checkpoint MUST exist.
	# No wait-N-frames or fake empty global MessageQueue can prove these facts.
	var ui: Dictionary=_router.verify_original_profile_ui_receiver_closure(original_checkpoint)
	if ui.get("success")!=true: return _fail("MISSING:original_ui_writer_and_command_receiver_closure",ui)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_MAIN_DEFERRED_FLUSH")
	var drained: Dictionary=_deferred.flush_original_main_source_checkpoint(original_checkpoint,_facade,_content,_legacy_resources)
	if drained.get("success")!=true: return _fail("MISSING:actual_original_Main_deferred_checkpoint",drained)
	var observed: Dictionary=_deferred.observe_original_main_source_receivers(original_checkpoint,_facade,_content,_legacy_resources)
	if observed.get("success")!=true: return _fail("pending_original_Main_source_receiver",observed)
	var model: RefCounted=_facade.get("_model")
	# Exactly the existing explicit lifecycle barrier. It completes previously
	# accepted writer outcomes; neither save data nor the transaction algorithm
	# is replaced. Nonterminal clock/warehouse/capability obligations still block.
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_MAIN_WRITER_BARRIER")
	model._before_state_transaction(true)
	var terminal_receivers: Dictionary=_deferred.observe_original_main_source_receivers(original_checkpoint,_facade,_content,_legacy_resources)
	if terminal_receivers.get("success")!=true or terminal_receivers.get("receiver_receipt",{}).get("all_io_completed")!=true: return _fail("original_IO_produced_nonterminal_source_receivers",terminal_receivers)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_LOADED_PROFILE_CAPTURE")
	var captured: Dictionary=Handoff.capture_main(model,_facade)
	if captured.get("ok")!=true: return _fail("original_loaded_source_capture_rejected",captured)
	var idle:=capture_original_resource_idle_state()
	if idle.get("success")!=true: return idle
	_old_flags=[]
	for node: Node in [_facade,_legacy_resources]: _old_flags.append({"node":node,"process":node.is_processing(),"physics":node.is_physics_processing()})
	var pumps:=0
	for child: Node in _facade.get_children():
		if child.get_script()==Pump:
			pumps+=1
			_old_flags.append({"node":child,"process":child.is_processing(),"physics":child.is_physics_processing()})
	if pumps!=1: return _fail("actual_single_paused_receipt_child_required")
	# Capture before PREPARED disables Main. These exact flags/paths become the
	# one persistent S qualification, including the genuine ALWAYS receipt child.
	var origins: Dictionary = {"profile":ProcessScope.capture_existing(_facade),"feature":ProcessScope.capture_existing(_legacy_resources)}
	for flags: Dictionary in _old_flags:
		if flags.node.get_script() == Pump: origins.profile_receipts = ProcessScope.capture_existing(flags.node)
	for key: String in ["profile","feature","profile_receipts"]:
		if origins.get(key,{}).get("success") != true: return _fail("actual_original_process_scope_capture_failed",{"scope":key})
	if not _gate.prepare(): return _fail("original_Main_source_gate_prepare_rejected")
	for flags: Dictionary in _old_flags:
		flags.node.set_process(false); flags.node.set_physics_process(false)
	_catalog_signal_connected=_content.feature_catalog_changed.is_connected(model._on_feature_catalog_changed)
	if _catalog_signal_connected: _content.feature_catalog_changed.disconnect(model._on_feature_catalog_changed)
	_serial+=1
	_source_state=captured.publication
	_prepared={"contract_id":"hardcore.main.profile_source.prepared.v1","serial":_serial,"facade_id":_facade.get_instance_id(),"model_id":model.get_instance_id(),"profile_id":model.active_profile_id,"process_frame":Engine.get_process_frames(),"profile_sha256":_source_state.source_witness.profile_document.bytes_sha256,"warehouse_sha256":_source_state.source_witness.shared_document.bytes_sha256,"original_checkpoint":original_checkpoint,"deferred_receipt":drained,"receiver_receipt":terminal_receivers,"ui_receipt":ui}
	return {"success":true,"receipt":_prepared.duplicate(true),"state_publication":_source_state,"resource_idle_state":idle.publication,"source_deferred":capture_original_source_deferred_configuration(),"original_persistent_process_scopes":origins}
func capture_original_resource_idle_state() -> Dictionary:
	for field: String in ["_requests","_jobs","_work","_retirements","_applications"]:
		if not _legacy_resources.get(field).is_empty(): return _fail("accepted_legacy_resource_obligation:"+field)
	if not _legacy_resources.get("_deferred_completions").is_empty() or _legacy_resources.get("_quantum_active") or _legacy_resources.get("_applying_request")!=0 or _legacy_resources.get("_code_world_handoff_id")!=0: return _fail("accepted_legacy_code_or_callback_obligation")
	var fields: Dictionary={}
	for field: String in ["_next_request","_head","_tail","_retire_head","_retire_tail","_apply_head","_apply_tail","_request_calls","_get_calls","_next_queue","_threaded_claim_diagnostics","_code_phase_metrics"]:
		var value: Variant=_legacy_resources.get(field)
		fields[field]=value.duplicate(true) if value is Dictionary else value
	return {"success":true,"publication":{"contract_id":"hardcore.feature.coordinator.idle_handoff.v1","fields":fields}}
func prepare_original_profile_source_handoff(state: Dictionary,receipt: Dictionary,lease_owner: Variant) -> Dictionary:
	if _committed or _prepared.is_empty() or receipt!=_prepared or state!=_source_state or _gate.state()!="PREPARED": return _fail("actual_prepared_profile_state_or_receipt_mismatch")
	# Existing Main primitive _decode resolves the genuine descriptor to its
	# actual registered Node before this method; caller object_id is insufficient.
	if not lease_owner is Node or not is_same(lease_owner,_primitive_facade): return _fail("actual_physical_lease_facade_identity_required")
	# Read true files again; a late writer is rejected rather than overwritten.
	for document: Dictionary in [state.source_witness.profile_document,state.source_witness.shared_document]:
		var file:=FileAccess.open(document.path,FileAccess.READ)
		if file==null: return _fail("prepared_original_source_file_missing")
		var bytes:=file.get_buffer(file.get_length()); file.close()
		if bytes!=document.bytes: return _fail("prepared_original_source_file_changed")
	return {"success":true,"receipt":_prepared.duplicate(true)}
func commit_original_profile_source_handoff(prepared: Dictionary,adopted: Dictionary) -> Dictionary:
	if prepared.get("receipt")!=_prepared or _committed or adopted.get("ok")!=true or adopted.get("active_profile_id")!=_prepared.profile_id or adopted.get("loaded_profile_sha256")!=_prepared.profile_sha256 or adopted.get("loaded_shared_warehouse_sha256")!=_prepared.warehouse_sha256: return _fail("actual_S_loaded_profile_adoption_proof_required")
	var view: Dictionary=_router.capture_original_profile_ui_view(_source_state)
	if view.get("success")!=true: return _fail("MISSING:original_Profile_UI_plain_view",view)
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	if not view.get("fields") is Dictionary or not graph.validate(view.fields,false).get("success",false): return _fail("actual_plain_Profile_UI_view_required")
	if not _content.has_method("install_original_feature_resource_facade") or _gate.state()!="PREPARED": return _fail("actual_atomic_source_commit_targets_required")
	# Includes original Code leases held by CharacterSelect and retained subsets.
	var leases: Array=Lease.capture_original_physical_owner_leases(_legacy_resources)
	# Complete real physical closure is verified by the actual primitive barrier.
	var handoff: Dictionary=_main_primitives.handoff_original_physical_leases(_legacy_resources,leases,_prepared)
	if handoff.get("success")!=true: return _fail("original_physical_lease_handoff_rejected",handoff)
	_physical_handoff=handoff
	if not _content.install_original_feature_resource_facade(_primitive_facade): return _fail("actual_original_ContentLayers_facade_switch_rejected")
	if not _gate.commit(view.fields): return _fail("original_Main_gate_commit_rejected")
	_committed=true
	if not _publish_actual_native_scope_transition("COMMITTED"): return _fail("actual_committed_native_scope_publication_failed",{"actual_Main_committed":true})
	return {"success":true,"receipt":_prepared.duplicate(true),"physical_handoff":handoff}
func abort_original_profile_source_handoff(receipt: Dictionary) -> Dictionary:
	if _committed or not _physical_handoff.is_empty(): return _fail("committed_S_or_physical_owner_cannot_restore_old_Main_snapshot")
	if _prepared.is_empty(): return {"success":true,"original_Main_authority_unchanged":true}
	if receipt!=_prepared: return _fail("foreign_original_Main_abort")
	if not _gate.abort(): return _fail("original_Main_gate_abort_rejected")
	for flags: Dictionary in _old_flags:
		if not is_instance_valid(flags.node): return _fail("original_Main_receiver_retired_before_abort")
		flags.node.set_process(flags.process); flags.node.set_physics_process(flags.physics)
	var model: RefCounted=_facade.get("_model")
	if _catalog_signal_connected and not _content.feature_catalog_changed.is_connected(model._on_feature_catalog_changed): _content.feature_catalog_changed.connect(model._on_feature_catalog_changed)
	_prepared={}; _source_state={}; _old_flags=[]
	if not _publish_actual_native_scope_transition("ABORTED"): return _fail("actual_aborted_native_scope_publication_failed",{"actual_Main_restored":true})
	return {"success":true,"original_Main_authority_unchanged":true}
func verify_original_unselected_startup_source(boot: Dictionary) -> Dictionary:
	if _facade==null or _gate.state()!="MAIN" or _committed: return _fail("original_unselected_Main_source_required")
	var scene: Node=_facade.get_tree().current_scene
	if not is_instance_valid(scene) or scene.scene_file_path!="res://scenes/startup_loading.tscn" or not _facade.get("_model").active_profile_id.is_empty(): return _fail("actual_original_unselected_Startup_required")
	return _router.verify_original_loading_source_site(boot.loading_source_site)
func verify_original_loading_boundary(site: Dictionary) -> Dictionary: return _router.verify_original_loading_source_site(site)
func verify_actual_loading_pinned_closure(closure: Dictionary) -> Dictionary: return _pins.inspect_actual_original_loading_pins(closure)
func release_original_loading_pins(id: int) -> Dictionary: return _pins.release_original_loading_pin_closure(id)
func _fail(code: String,details: Dictionary={}) -> Dictionary: return {"success":false,"errors":[code],"details":details}
