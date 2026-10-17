extends RefCounted
## Fixed Root composition point. These constructors are actual Source owners.
## Missing application implementations are listed by their existing Session ABI;
## an empty/default adapter is never installed as a live provider.
const Frames:=preload("res://scripts/gameplay/source/source_original_frame_dispatcher.gd")
const Admission:=preload("res://scripts/gameplay/source/profile_source_admission_port.gd")
const Checkpoint:=preload("res://scripts/gameplay/world/world_source_checkpoint.gd")
const Factory:=preload("res://scripts/gameplay/source/source_session_factory.gd")
const PathTree:=preload("res://scripts/gameplay/source/source_persistent_path_tree.gd")
const PathBindings:=preload("res://scripts/gameplay/source/source_persistent_path_bindings.gd")
const LiveFeature:=preload("res://scripts/features/runtime/source_feature_live_provider.gd")
class Failure extends RefCounted:
	var _owner:=OS.get_thread_caller_id()
	var _records: Array[Dictionary]=[]
	func owner_thread_id() -> int: return _owner
	func record_fatal_source_fault(code: String, details: Dictionary) -> void:
		assert(OS.get_thread_caller_id()==_owner)
		_records.append({"code":code,"details":details.duplicate(true),"actual_recorded_usec":Time.get_ticks_usec()})
		push_error("Source owner fault: "+code)
	func actual_fault_records() -> Array[Dictionary]: return _records.duplicate(true)
static func create_original_session_services(host: Object, boot: Dictionary) -> Dictionary:
	# Instantiate the already-implemented fixed S owners in this actual Native
	# factory. Boot still transports values, never executable provider paths.
	var made: Dictionary = preload("res://scripts/gameplay/source/source_application_providers.gd").create_original_providers(host)
	if made.get("success") != true: return made
	return create_original_session_services_with_actual_bindings(host,boot,made.services)
static func create_original_session_services_with_actual_bindings(host: Object, boot: Dictionary, actual: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()==OS.get_main_thread_id(): return _missing("actual_S_factory_required")
	var frames:=Frames.new()
	if not frames.configure_owner(host,boot): return _missing("actual_Native_frame_owner")
	var checkpoint:=Checkpoint.new()
	if not checkpoint.configure_owner(host,frames): return _missing("actual_Source_checkpoint_owner")
	var services: Dictionary={"failure":Failure.new(),"source_frames":frames,"admission":Admission.new(),"WorldSourceCheckpoint":checkpoint}
	if not boot.get("feature_live_reservation_usec") is Dictionary: return _missing("actual_Feature_LIVE_cleanup_reservation_policy_required")
	var live_feature:=LiveFeature.new()
	if not live_feature.configure_original_bootstrap(boot.feature_live_reservation_usec): return _missing("actual_Feature_LIVE_cleanup_reservation_policy_rejected")
	services.live_feature=live_feature
	if not boot.get("source_path_publication") is Dictionary: return _missing("actual_Main_persistent_Path_publication_required")
	var path_tree:=PathTree.new()
	if not path_tree.configure_bootstrap(host,boot.source_path_publication): return _missing("actual_persistent_Source_tree_capture_rejected")
	var path_bindings:=PathBindings.new()
	if not path_bindings.configure_bootstrap(boot.source_path_publication,path_tree): return _missing("actual_persistent_Path_static_handoff_rejected")
	services.source_tree=path_tree;services.path_bindings=path_bindings
	for role: String in actual:
		if services.has(role): return _missing("duplicate_source_owner:"+role)
		var port: Variant=actual[role]
		if not port is RefCounted or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id()!=OS.get_thread_caller_id(): return _missing("actual_S_provider:"+role)
		services[role]=port
	var required: Dictionary={"feature_retirement":["original_session_retirement_state"],"main_io":["service_original_source_main_io_cleanup","actual_original_session_io_retirement_state"],
		"source_tree":["lookup_original_source_tree_path_scheduler","birth_original_source_tree_path_scheduler","commit_original_source_tree_path_scheduler","retire_original_source_tree_path_scheduler","free_original_source_tree_path_scheduler","validate_original_session_path_bindings","original_source_tree_callback_order","original_source_tree_root_ordinal"],
		"path_bindings":["actual_persistent_path_bindings"],
		"WorldViewTransport":["original_world_view_ready_receipt","publish_original_world_view_prefix","actual_original_world_view_exit_receipt","actual_original_actor_view_free_receipt"],"WorldAudioProjection":["capture_original_audio_source"],
		"WorldUiLoading":["prewarm_all_panels","start_original_catalog_icon_prewarm","actual_original_panels_prewarmed","actual_original_panel_prewarm_diagnostic","start_original_budgeted_panel_prewarm"],
		"WorldMapLoadingAdmission":["request_original_map_loading_boundary","poll_original_map_loading_boundary","release_original_map_loading_boundary"]}
	for role: String in Factory.PROVIDER_ABI:
		if role not in ["failure","source_frames","admission"]: required[role]=Factory.PROVIDER_ABI[role]
	var missing: Array[Dictionary]=[]
	for role: String in required:
		if not services.has(role): missing.append({"role":role,"methods":required[role]}); continue
		for method: String in required[role]:
			if not services[role].has_method(method): missing.append({"role":role,"method":method})
	if not missing.is_empty(): return {"success":false,"status":"MISSING","errors":["actual_application_Source_provider_bodies_required"],"missing":missing,"constructed_source_services":services}
	return {"success":true,"services":services,"original_frame_dispatcher":frames}
static func _missing(code: String) -> Dictionary: return {"success":false,"status":"MISSING","errors":[code]}
