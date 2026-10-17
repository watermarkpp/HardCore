extends RefCounted
const Facade := preload("res://scripts/gameplay/world/world_main_view_facade.gd")
const Support := preload("res://scripts/gameplay/world/world_main_service_support.gd")
const Audio := preload("res://scripts/gameplay/world/world_audio_owner_primitives.gd")
const UI := preload("res://scripts/gameplay/world/world_ui_command_owner.gd")
const SourceFrames := preload("res://scripts/gameplay/world/world_source_frames_owner.gd")
const Rules := preload("res://scripts/gameplay/world/world_source_rule_ports.gd")
const ViewportPort := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
const Caster := preload("res://scripts/gameplay/world/world_caster_presentation_port.gd")
const CasterVisual := preload("res://scripts/gameplay/world/world_caster_visual_port.gd")
const CombatLog := preload("res://scripts/gameplay/world/world_combat_log_owner.gd")
const FootprintLog := preload("res://scripts/gameplay/world/world_footprint_log_owner.gd")
const LootTrace := preload("res://scripts/gameplay/world/world_loot_trace_owner.gd")
const Warm := preload("res://scripts/gameplay/world/world_caster_warm_port.gd")
const Pipeline := preload("res://scripts/gameplay/world/world_bootstrap_pipeline_warm.gd")
const MapLoading := preload("res://scripts/gameplay/world/world_map_loading_port.gd")
const MapTransport := preload("res://scripts/gameplay/world/world_map_loading_transport.gd")
const ProfilePublisher := preload("res://scripts/gameplay/world/world_profile_view_publisher.gd")
const REQUIRED_EXTERNAL := {
	"WorldSourceCheckpoint":["original_idle_callbacks","original_control_boundary","original_world_exit_admission","original_fault_exit_admission"],
	"WorldMapLoadingAdmission":["request_original_map_loading_boundary","poll_original_map_loading_boundary","release_original_map_loading_boundary"],
	"WorldAudioProjection":["capture_original_audio_source"],
	"WorldUiLoading":["prewarm_all_panels","start_original_catalog_icon_prewarm","actual_original_panels_prewarmed","actual_original_panel_prewarm_diagnostic","start_original_budgeted_panel_prewarm"],
	"WorldViewTransport":["original_world_view_ready_receipt","publish_original_world_view_prefix","actual_original_world_view_exit_receipt","actual_original_actor_view_free_receipt"]
}
static func _missing(code: String, details: Dictionary = {}) -> Dictionary: return {"success":false,"status":"MISSING","error":code,"details":details}
static func create_original_world_view_services(core: RefCounted, publication: Dictionary) -> Dictionary:
	if core == null or OS.get_thread_caller_id() == OS.get_main_thread_id() or core.owner_thread_id() != OS.get_thread_caller_id(): return _missing("actual_same_S_world_required")
	for method: String in ["original_source_session","original_root_owner","current_world_identity"]:
		if not core.has_method(method): return _missing("Core_actual_owner_getter",{"method":method})
	var session: RefCounted = core.original_source_session()
	var root: RefCounted = core.original_root_owner()
	if session == null or root == null or root.owner_thread_id() != core.owner_thread_id(): return _missing("actual_original_S_Root_Session_required")
	var checkpoint: Variant=session.original_world_main_dependency(&"WorldSourceCheckpoint")
	if not checkpoint is RefCounted or not checkpoint.has_method("bind_original_world") or not checkpoint.bind_original_world(core): return _missing("actual_same_Source_checkpoint_Core_binding")
	var source: Dictionary = publication.get("world_main_views",{})
	if source.get("contract_id") != "world.Main.view_services.publication.v1" or source.get("world_context") != core.current_world_identity(): return _missing("actual_Main_world_view_publication")
	# This Core's actual Root already exists. The original open bootstrap source
	# site performs one exact Loading-only Main call; no boot guessed an S ID.
	if not session.has_method("original_budget_session_id") or not session.cold_resource_calls_allowed(): return _missing("actual_original_Loading_owner_header")
	var feature: Dictionary = session.feature_resource_session()
	var site: Dictionary=core.current_original_source_site()
	var actual_frame: Dictionary=core.current_clock_frame()
	if not feature.primitives.has_method("current_original_source_site") or site.is_empty() or feature.primitives.current_original_source_site()!=site: return _missing("actual_Core_Header_source_entry_not_open")
	if site.get("bootstrap")!=true or site.get("clock_epoch")!=actual_frame.get("epoch") or actual_frame.get("epoch")!=0 or site.get("world_context")!=core.current_world_identity(): return _missing("actual_epoch0_Header_source_admission")
	if not source.get("bootstrap_resources") is Dictionary or not session.actual_original_loading_scope_is_current(source.bootstrap_resources.get("loading_scope",{})): return _missing("actual_Header_Loading_source_permission")
	if not source.get("main_service_reference") is Dictionary: return _missing("actual_Main_header_reference")
	var main_reference: Variant=feature.primitives.decode_original_source_value(source.main_service_reference)
	if not main_reference is RefCounted: return _missing("actual_Main_header_reference_decode")
	var completed: Variant=feature.primitives.object_call(main_reference,"complete_original_source_owner_header",[core.current_world_identity(),root.get_instance_id(),session.original_budget_session_id()])
	if not completed is Dictionary or completed.get("success")!=true: return _missing("actual_Main_Loading_header_completion",completed if completed is Dictionary else {})
	# object_call returns canonical S reference wrappers. The published proof
	# remains plain wire data; decode only the specific consumer below.
	source=feature.primitives.encode_original_source_value(completed.get("publication",{}))
	if source.get("contract_id")!="world.Main.view_services.publication.v1" or source.get("world_context")!=core.current_world_identity(): return _missing("actual_completed_Main_world_view_publication")
	if not session.bind_original_application_world(core,source): return _missing("actual_application_owners_completed_Main_header_binding")
	if not publication.get("caster_visual") is Dictionary: return _missing("actual_caster_visual_metadata")
	for key: String in ["views","viewport","source_frames","audio","bootstrap_resources","root_reference","caster_loading","caster_warm_owner","camera_constraint","diagnostic_policy","interactable_loading"]:
		if not source.get(key) is Dictionary: return _missing("actual_Main_view_field",{"field":key})
	if not source.get("home_screen_position_px") is Vector2 or not source.home_screen_position_px.is_finite(): return _missing("actual_editor_home_capture")
	var external := {}
	for name: String in REQUIRED_EXTERNAL:
		var port: Variant = session.original_world_main_dependency(StringName(name))
		if not port is RefCounted or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != core.owner_thread_id(): return _missing("actual_Source_dependency",{"service":name})
		for method: String in REQUIRED_EXTERNAL[name]:
			if not port.has_method(method): return _missing("actual_Source_dependency_method",{"service":name,"method":method})
		external[name] = port
	var views := {}
	for kind: String in ["hud","camera","system_menu","town_music","item_audio","level_up","relic_proc"]:
		if not source.views.get(kind) is Dictionary: return _missing("actual_Main_Node_view",{"kind":kind})
		var facade := Facade.new()
		if not facade.configure_owner(core,kind,source.views[kind]): return _missing("actual_Main_Node_capture_invalid",{"kind":kind})
		views[kind] = facade
	if not views.hud.bind_original_UI_Loading(external.WorldUiLoading): return _missing("actual_UI_Loading_continuation")
	var viewport := ViewportPort.new()
	if not viewport.configure_owner(core,source.viewport): return _missing("actual_Main_viewport_capture")
	var caster := Caster.new()
	if not caster.configure_owner(core,publication.caster_visual,source.caster_loading): return _missing("actual_caster_Loading_pin_closure")
	var visual: RefCounted = CasterVisual.create_owner(publication.caster_visual,core.original_action_timing_publication(),core.content.rules.professions,core.action_timing)
	if visual == null: return _missing("same_catalog_CasterVisual")
	var audio := Audio.new()
	if not audio.configure_owner(core,caster,source.audio,external.WorldAudioProjection): return _missing("actual_Main_audio_reply_binding")
	var consumer: Variant = feature.primitives.decode_original_source_value(source.root_reference)
	var content := Support.Content.new()
	if not content.configure(core,session,consumer): return _missing("actual_Main_original_Code_consumer")
	var frames: RefCounted = session.original_source_frames_owner(source.source_frames)
	if frames == null: return _missing("actual_Session_overlay_cache_handoff")
	var ui := UI.new()
	if not ui.configure_owner(core,root,views.hud,views.system_menu,viewport): return _missing("actual_Source_UI_callback_owner")
	var warm := Warm.new()
	if not warm.configure_owner(root,core,session,caster,source.caster_warm_owner,int(source.get("original_warm_reservation_usec",-1))): return _missing("actual_Source_warm_owner_descriptor")
	if not warm.has_method("configure_original_issued_claim_bridge") or not warm.configure_original_issued_claim_bridge(feature.coordinator): return _missing("actual_Source_warm_issued_claim_bridge")
	var pipeline := Pipeline.new()
	var travel:=MapLoading.new()
	var map_publication: Dictionary=source.get("map_loading",{})
	var map_settings: Dictionary={"max_items_per_frame":map_publication.get("max_items_per_frame"),"slice_budget_ms":map_publication.get("slice_budget_ms")}
	if publication.get("root_phase",{}).get("original_map_loading_settings")!=map_settings or source.get("original_map_loading_settings")!=map_settings: return _missing("actual_original_map_loading_settings_handoff")
	var map_transport:=MapTransport.new()
	if not map_publication.get("owner_descriptor") is Dictionary or not map_publication.get("slice_budget_ms") is float or map_publication.slice_budget_ms<0.0: return _missing("actual_Map_Loading_publication")
	if not map_transport.configure_owner(core,session,external.WorldMapLoadingAdmission,core.original_native_host(),map_publication.owner_descriptor,int(ceil(map_publication.slice_budget_ms*1000.0))): return _missing("actual_Map_Loading_transport_permission")
	if not travel.configure_owner(root,core,session,core.environment_factory,map_transport,map_publication): return _missing("actual_Source_map_loading_owner")
	if not pipeline.configure_owner(travel,warm): return _missing("actual_Source_map_travel_pipeline")
	var rules: Dictionary = Rules.create_owner_services(core.profile._rules.item_instances)
	var combat := CombatLog.new(core,source.diagnostic_policy)
	var footprint := FootprintLog.new(core,source.diagnostic_policy)
	var trace := LootTrace.new(core)
	var camera: RefCounted = session.original_camera_constraint(source.camera_constraint)
	if camera == null: return _missing("actual_Session_camera_static_handoff")
	var resources := Support.BootstrapResources.new(session,source.bootstrap_resources)
	if not feature.primitives.has_method("load_original_loading_resource") or not session.has_method("actual_original_loading_scope_is_current"): return _missing("actual_Loading_resource_leaf_or_scope_verifier")
	var publisher:=ProfilePublisher.new()
	if not publisher.configure_owner(core): return _missing("actual_Profile_UI_journal_publisher")
	if not frames.bind_current_world(core,core.resources,source.source_frames):
		publisher.detach_at_original_world_exit()
		return _missing("actual_Session_overlay_cache_endpoint_binding")
	var lifecycle:=Support.Lifecycle.new(core,external.WorldViewTransport,source,frames,publisher,audio)
	var services := {"AudioPrimitives":audio,"CombatLog":combat,"SkillFootprintLog":footprint,"LootTrace":trace,
		"CasterPresentation":caster,"CasterVisual":visual,"ContentLayers":content,"SourceFrames":frames,"ProjectileVisual":frames,
		"VisualViewport":viewport,"WorldViewLifecycle":lifecycle,"UIItemTextureCache":Support.UiTextureCache.new(core),
		"WorldUiCommandOwner":ui,"WorldHomeSource":Support.Home.new(core.environment_factory.catalog,source.home_screen_position_px),
		"WorldPauseControl":Support.Pause.new(core),"WorldSourceCheckpoint":external.WorldSourceCheckpoint,
		"WorldBootstrapResources":resources,"WorldBootstrapPipeline":pipeline,"CameraConstraint":camera}
	services.merge(rules)
	var fields := {&"hud":views.hud,&"_world_camera":views.camera,&"_system_menu_panel":views.system_menu,
		&"_town_music_controller":views.town_music,&"_audio_runtime_service":views.item_audio,
		&"_player_level_up_effect":views.level_up,&"_player_relic_proc_effect":views.relic_proc,&"background":travel.background}
	return {"success":true,"services":services,"field_bindings":fields,"interactable_loading":source.interactable_loading}
