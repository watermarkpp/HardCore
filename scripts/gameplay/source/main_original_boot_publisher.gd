extends RefCounted
## Main assembles only actual publications/receipts. The sole S Model constructor
## receives their Native graph snapshot; no gameplay identity/ready is invented.
var _host: Object
var _facade: Node
var _blueprint: RefCounted
var _world_publications: RefCounted
var _session_publications: RefCounted
var _pins: RefCounted
var _config: RefCounted
var _prepared_blueprint: Dictionary
var _boot: Dictionary
var _path_preparation: RefCounted
func owner_thread_id() -> int: return OS.get_main_thread_id()
func configure_main(host: Object, facade: Node, blueprint: RefCounted, world_publications: RefCounted, session_publications: RefCounted, pins: RefCounted, config: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host!=null or host==null or not host.is_class("HardCoreSimulationHost") or not is_instance_valid(facade) or facade!=facade.get_tree().root.get_node_or_null("PlayerState"): return _missing("actual_Main_once_Host_PlayerState")
	for spec: Array in [[blueprint,["prepare_original_character_blueprint","actual_original_blueprint_receipt"]],[world_publications,["capture_original_prepared_world_boot"]],[session_publications,["capture_original_selected_session_boot_fields"]],[pins,["inspect_actual_original_loading_pins"]],[config,["capture_actual_original_source_host_config"]]]:
		if spec[0]==null or not spec[0].has_method("owner_thread_id") or spec[0].owner_thread_id()!=OS.get_main_thread_id(): return _missing("actual_Main_boot_publication_owner")
		for method: String in spec[1]:
			if not spec[0].has_method(method): return _missing("actual_Main_boot_publication_body:"+method)
	_host=host;_facade=facade;_blueprint=blueprint;_world_publications=world_publications;_session_publications=session_publications;_pins=pins;_config=config
	return {"success":true}
func prepare_original_character_blueprint(receiver: Node) -> Dictionary:
	if _host==null or not _prepared_blueprint.is_empty() or not is_instance_valid(receiver) or receiver!=_facade.get_tree().current_scene: return _missing("actual_single_original_character_launch_receiver")
	var actual: Dictionary=_blueprint.prepare_original_character_blueprint(receiver)
	if actual.get("success")!=true or not actual.get("world") is Dictionary or not actual.get("root") is Node2D or not actual.get("receipt") is Dictionary: return _missing("actual_original_blueprint_and_Node_receipt")
	if actual.root.get_instance_id()!=actual.world.get("world_runtime_id") or actual.root.get_script()!=preload("res://scripts/game_root.gd") or actual.get("receipt")!=_blueprint.actual_original_blueprint_receipt(actual.root): return _missing("actual_original_Main_root_script_identity")
	_prepared_blueprint=actual
	return {"success":true,"world":actual.world.duplicate(true),"actual_blueprint_receipt":actual.receipt.duplicate(true)}
func publish_original_source_session_bootstrap(admission: RefCounted, prepared: Dictionary, world: Dictionary) -> Dictionary:
	if _host==null or _prepared_blueprint.is_empty() or world!=_prepared_blueprint.world or admission==null or admission.get("_committed")!=false or prepared.get("success")!=true or not _boot.is_empty(): return _missing("actual_selected_prepared_boot_once")
	var receipt: Dictionary=prepared.get("receipt",{})
	var state: Dictionary=prepared.get("state_publication",{})
	if receipt.get("contract_id")!="hardcore.main.profile_source.prepared.v1" or receipt.get("profile_id")!=world.get("profile_id") or receipt.get("facade_id")!=_facade.get_instance_id() or state.get("source_witness",{}).get("model_object_id")!=receipt.get("model_id") or state.get("active_profile_id")!=receipt.get("profile_id"): return _missing("actual_Main_loaded_Profile_admission_identity")
	if state.get("source_witness",{}).get("profile_document",{}).get("bytes_sha256")!=receipt.get("profile_sha256") or state.get("source_witness",{}).get("shared_document",{}).get("bytes_sha256")!=receipt.get("warehouse_sha256"): return _missing("actual_Main_loaded_documents")
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_REAL_SESSION_FRONT")
	var front: Dictionary = _session_publications.prepare_original_selected_session_front(_prepared_blueprint,prepared)
	if front.get("success") != true: return front
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_REAL_WORLD_PUBLICATION")
	var first: Dictionary=_world_publications.capture_original_prepared_world_boot(_prepared_blueprint,prepared)
	if first.get("success") != true: return first
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_REAL_SESSION_PUBLICATION")
	var session: Dictionary=_session_publications.capture_original_selected_session_boot_fields(_prepared_blueprint,prepared)
	if session.get("success") != true: return session
	var native: Dictionary=_config.capture_actual_original_source_host_config(_host,_prepared_blueprint,prepared)
	if native.get("success")!=true or not native.get("config") is Dictionary: return _missing("actual_world_session_native_publication_missing",{"native":native})
	var deferred: Dictionary=prepared.get("source_deferred",{})
	if native.config.get("source_process_frame")!=Engine.get_process_frames() or native.config.get("source_physics_frame")!=Engine.get_physics_frames(): return _missing("actual_Main_Engine_counter_seeds_required")
	if native.config.get("source_deferred_max_pages")!=deferred.get("source_deferred_max_pages") or deferred.get("setting")!="memory/limits/message_queue/max_size_mb" or deferred.get("setting_value_mb")!=ProjectSettings.get_setting(deferred.setting) or deferred.get("page_size_bytes")!=4096: return _missing("actual_Main_pinned_CallQueue_configuration")
	var world_boot: Dictionary=first.get("world_boot",{})
	var boot: Dictionary=session.get("boot",{})
	if boot.get("contract_id")!="hardcore.source.session.boot.v1" or world_boot.get("world_identity")!=world or not boot.get("session_id") is int or boot.session_id<=0: return _missing("actual_world_session_identity")
	if boot.get("profile_state_handoff")!=state or boot.get("source_commit_receipt")!=receipt or not boot.get("profile_publication") is Dictionary or not boot.get("content_snapshot") is Dictionary: return _missing("actual_original_admission_bytes_and_loaded_publications")
	var source_site: Dictionary=world_boot.get("assembly",{}).get("bootstrap_source_site",{})
	if source_site.get("clock_epoch")!=0 or source_site.get("bootstrap")!=true or source_site.get("world_context")!=world or source_site.get("observation_process_epoch")!=native.config.get("source_process_frame"): return _missing("actual_epoch0_source_site_and_seeded_Main_counter")
	var closure: Dictionary=first.get("loading_pin_closure",{})
	var pinned: Dictionary=_pins.inspect_actual_original_loading_pins(closure)
	if pinned.get("success")!=true or pinned.get("closure")!=closure: return _missing("actual_Main_Loading_pin_closure")
	if world_boot.get("assembly",{}).get("source_domain_publication",{}).get("world_main_views",{}).is_empty(): return _missing("actual_Main_world_views_publication")
	world_boot=world_boot.duplicate(true)
	world_boot["actual_loading_pin_closure"]=closure
	# All independent existing publication/pin checks precede physical Path
	# handoff preparation. This same Main owner remains retained for abort/close.
	_path_preparation=preload("res://scripts/gameplay/source/source_persistent_path_main.gd").new()
	var path: Dictionary=_path_preparation.prepare_original_path_publication(_host,_facade.get_tree(),admission,prepared,_prepared_blueprint.root)
	if path.get("success")!=true: return path
	# Edit only this envelope. Deep Dictionary.duplicate breaks original DAG
	# aliases inside Path descriptors and its shared state roots. Both existing
	# publications are immutable; the final Native capture below and Host.start
	# still allocate the independent receiving graph with those aliases intact.
	boot=boot.duplicate(false)
	boot["source_path_publication"]=path.publication
	var admission_scope: Dictionary = admission.get("_actual_native_scope")
	if admission_scope.get("state") != "PREPARED" or admission_scope.get("receipt") != receipt or admission_scope.get("publication") != state or admission_scope.get("world_context") != world: return _missing("actual_same_PREPARED_Native_admission_scope_required")
	boot["source_admission_scope"] = admission_scope.duplicate(true)
	boot["first_world_boot"]=world_boot
	boot["source_frames_publication"]=world_boot.assembly.source_domain_publication.world_main_views.source_frames
	boot["actual_loading_pin_closure"]=closure
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	# Capture all draft values and the final actual Engine counters BEFORE
	# spending the one Native global-random handoff. Constructors/resource/Path
	# preparation above may use the original Main random generator.
	# This is the same Native validator with its owned readonly result retained;
	# a second full traversal after adding four scalar RNG fields is unnecessary.
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_PRE_FENCE_OWNED_BOOT_CAPTURE")
	var capture_started: int = Time.get_ticks_usec()
	var draft: Dictionary = graph.capture(boot,true,false)
	if ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false): print("HC_FINAL_BOOT_CAPTURE ",JSON.stringify({"nodes":draft.get("nodes"),"memo_entries":draft.get("memo_entries"),"success":draft.get("success"),"elapsed_usec":Time.get_ticks_usec()-capture_started}))
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"PRE_FENCE_OWNED_BOOT_CAPTURE_RETURNED")
	if draft.get("success") != true:
		var restored: bool = _path_preparation.abort_original_path_preparation(receipt)
		return _missing("actual_plain_runtime_boot_before_random_fence",{"capture":draft,"actual_Path_abort":restored})
	if native.config.source_process_frame != Engine.get_process_frames() or native.config.source_physics_frame != Engine.get_physics_frames():
		var restored: bool = _path_preparation.abort_original_path_preparation(receipt)
		return _missing("actual_final_boot_counter_changed",{"actual_Path_abort":restored})
	var random_handoff: Dictionary = _host.capture_main_gameplay_random()
	if random_handoff.size() != 4 or random_handoff.get("contract_id") != "hardcore.gameplay_global_random.handoff.v1" or not random_handoff.get("seed") is int or not random_handoff.get("state") is int or not random_handoff.get("increment") is int: return _missing("actual_final_Native_global_random_fence_required")
	var captured: Dictionary=graph.capture(random_handoff,true,false)
	if captured.get("success")!=true:
		var restored: bool=_path_preparation.abort_original_path_preparation(receipt)
		return _missing("actual_plain_runtime_boot",{"capture":captured,"actual_Path_abort":restored})
	_boot=draft.value.duplicate(false)
	_boot["global_random_handoff"] = captured.value
	_boot.make_read_only()
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_OWNED_BOOT_AND_SCALAR_RANDOM_SEALED")
	return {"success":true,"boot":_boot,"config":native.config,"prepared_receipt":receipt,"actual_blueprint_receipt":_prepared_blueprint.receipt,"actual_pin_receipt":pinned}
static func _missing(code: String, detail: Dictionary = {}) -> Dictionary: return {"success":false,"status":"MISSING","error":code,"details":detail}

func abort_original_path_preparation(prepared_receipt: Dictionary) -> bool:
	return _path_preparation!=null and _path_preparation.abort_original_path_preparation(prepared_receipt)
