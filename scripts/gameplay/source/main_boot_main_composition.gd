extends RefCounted
## One retained Main graph. Allocate transports before PREPARED; bind physical
## World owners only after the original Source constructor checkpoint exists.
## A failed stage retains its exact objects for the real abort/close path.
const Views := preload("res://scripts/gameplay/world/world_main_views.gd")
const Registry := preload("res://scripts/gameplay/presentation/main_actor_visual_registry.gd")
const Consumer := preload("res://scripts/gameplay/presentation/actor_main_visual_journal_consumer.gd")
const Prefix := preload("res://scripts/gameplay/world/world_main_prefix_consumer.gd")
const Streaming := preload("res://scripts/gameplay/enemy/enemy_main_resource_primitives.gd")
const Pump := preload("res://scripts/gameplay/source/main_original_resource_pump.gd")
const Origin := preload("res://scripts/gameplay/source/main_source_closing_io_producer.gd")
const Ports := preload("res://scripts/gameplay/source/main_root_checkpoint_ports.gd")
var _application: WeakRef
var _host: Object
var _views: RefCounted
var _registry: RefCounted
var _consumer: RefCounted
var _prefix: RefCounted
var _streaming: RefCounted
var _pump: RefCounted
var _origin: RefCounted
var _closing_frames: RefCounted
var _ports: Dictionary
var _stage := "NEW"
var _fault: Dictionary
var _world_receipt: Dictionary
var _phase_bridge: RefCounted
var _player_inputs: Dictionary

func _fail(code: String, details: Dictionary = {}) -> Dictionary:
	_fault = {"success":false,"status":"INVALID","error":code,"stage":_stage,"details":details}
	return _fault

func prepare_actual_main_channels(application: RefCounted, assembly: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _stage != "NEW" or application == null or application.get_script() != preload("res://scripts/gameplay/source/main_boot_application.gd") or assembly.get("success") != true: return _fail("actual_once_Main_application_assembly_required")
	_application = weakref(application); _host = application.get("_host")
	var facade: Node = application.get("_facade")
	var content: Node = application.get("_content")
	var feature: RefCounted = application.get("_services").get("feature_main")
	var primitive_facade: Node = feature.get("_facade") if feature != null else null
	if _host == null or facade == null or content == null or primitive_facade == null or primitive_facade.get_script() != preload("res://scripts/features/runtime/feature_resource_main_facade.gd") or not primitive_facade.is_inside_tree() or not is_same(primitive_facade.get("_primitives"),feature): return _fail("actual_registered_Main_Feature_facade_required")
	var policy: Dictionary = application.get("_policy")
	var config: Dictionary = policy.duplicate(true)
	var observed: Dictionary = preload("res://scripts/gameplay/source/main_boot_source_observations.gd").engine(facade.get_tree())
	config.physics_hz = observed.physics_hz
	config.source_process_frame = observed.source_process_frame
	config.source_physics_frame = observed.source_physics_frame
	config.source_deferred_max_pages = preload("res://scripts/gameplay/source/main_source_admission.gd").capture_original_source_deferred_configuration().source_deferred_max_pages
	_stage = "NATIVE_CHANNEL_PREPARATION"
	var channels: Dictionary = _host.prepare_original_main_channels(config)
	if channels.get("status") != "PREPARED": return _fail("actual_Native_Main_channels_rejected",channels)
	_views = Views.new(); _registry = Registry.new(); _consumer = Consumer.new()
	if not _consumer.configure_main(_registry,_views): return _fail("actual_actor_projection_dispatcher_rejected")
	_prefix = Prefix.new(_host,_consumer)
	_streaming = Streaming.new()
	var observer: Object = ClassDB.instantiate("HardCoreResourceObservation")
	if not _streaming.configure_main(Callable(_host,"validate_original_primitive_ticket"),observer,policy.bridge_generation): return _fail("actual_Main_streaming_owner_rejected")
	_pump = Pump.new()
	if not _pump.configure_main(_host,_prefix,feature,policy.bridge_generation) or not _pump.bind_actual_original_streaming(_streaming): return _fail("actual_single_Main_resource_pump_rejected")
	if not _pump.bind_actual_original_live_feature() or not _pump.bind_actual_original_live_streaming(_streaming): return _fail("actual_Native_live_resource_bindings_rejected")
	var caster: RefCounted = application.get("_services").caster_executor
	if not _host.bind_main_caster_reply_producer(caster,caster.get_script().get_source_code().sha256_text()): return _fail("actual_Native_Caster_reply_owner_binding_rejected")
	_origin = Origin.new()
	_stage = "ORIGIN_BINDING"
	var origin: Dictionary = _origin.configure_main(_host,content,feature)
	if origin.get("success") != true: return _fail("actual_Main_claim_origin_binding_rejected",origin)
	var transport: RefCounted = application.get("_transport")
	_stage = "TRANSPORT_BINDING"
	var bound: Dictionary = transport.configure_main(_host,facade.get_tree(),facade,_prefix,assembly.publisher,_pump,_origin,application.get("_main_failure"),policy.input_capacity)
	if bound.get("success") != true: return _fail("actual_Main_transport_binding_rejected",bound)
	if not primitive_facade.bind_actual_original_owner_command_transport(transport): return _fail("actual_same_Feature_owner_command_transport_rejected")
	var file := FileAccess.open("res://scripts/gameplay/source/main_original_receiver_manifest.json",FileAccess.READ)
	if file == null: return _fail("actual_original_receiver_manifest_unavailable")
	var manifest: Variant = JSON.parse_string(file.get_as_text())
	if not manifest is Dictionary: return _fail("actual_original_receiver_manifest_invalid")
	_stage = "CHECKPOINT_PORT_BINDING"
	_ports = Ports.create_main_ports(_host,facade.get_tree(),facade,content,content.get("_feature_resource_service"),primitive_facade,feature,transport,application.get("_main_failure"),assembly.pins,manifest,_prefix,application.get("_services").caster_executor,application.get("_loading"))
	if _ports.get("success") != true: return _fail("actual_original_checkpoint_ports_rejected",_ports)
	if not _ports.lifecycle.bind_actual_original_resource_pump(_pump): return _fail("actual_Driver_and_Transport_must_share_one_pump")
	_closing_frames = preload("res://scripts/gameplay/source/main_close_process_frame_producer.gd").new()
	var closing: Dictionary = _closing_frames.configure_main(_host,facade.get_tree(),policy.bridge_generation,policy.bridge_generation,policy.input_capacity,application.get("_main_failure"))
	if closing.get("success") != true: return _fail("actual_original_close_process_producer_rejected",closing)
	if not _streaming.configure_original_actor_asset_inputs(application.get("_loading"),_prefix): return _fail("actual_actor_asset_owner_binding_rejected")
	_stage = "CHANNELS_BOUND"
	return {"success":true,"stage":_stage,"actual_prefix_id":_prefix.get_instance_id(),"actual_pump_id":_pump.get_instance_id(),"actual_transport_id":transport.get_instance_id()}

func bind_actual_world_front(blueprint: Dictionary, prepared: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _application == null or _application.get_ref() == null or not _fault.is_empty(): return _fail("actual_retained_Main_composition_required")
	var application: RefCounted = _application.get_ref()
	var root: Node2D = blueprint.get("root")
	var world: Dictionary = blueprint.get("world",{})
	var front: Dictionary = application.get("_session_front")
	if root == null or front.get("prepared_receipt") != prepared.get("receipt") or front.get("world") != world or application.get("_world_birth_inputs").get("initial_actor_count") != 0: return _fail("actual_pre_view_Source_checkpoint_required")
	if not _world_receipt.is_empty(): return _world_receipt if _views.get("_root") == root and _views.get("_world") == world else _fail("actual_single_World_binding_required")
	if _stage != "CHANNELS_BOUND": return _fail("actual_Main_channel_graph_not_ready")
	_stage = "WORLD_PHYSICAL_BINDING"
	_phase_bridge = preload("res://scripts/gameplay/presentation/main_original_visual_phase_bridge.gd").new()
	if not _phase_bridge.configure_main(root,world,_host,_prefix,_streaming,application.get("_policy").bridge_generation) or not _registry.configure_original_structural_main(root,world,_phase_bridge) or not _registry.bind_original_enemy_header_channel(_prefix,_streaming): return _fail("actual_same_World_renderer_graph_rejected")
	var shell: Dictionary = _registry.prepare_original_player_shell()
	if shell.get("success") != true: return _fail("actual_Player_shell_creation_rejected",shell)
	var loading: RefCounted = application.get("_loading")
	var scope: Dictionary = loading.actual_original_loading_scope(world)
	_player_inputs = _streaming.prepare_original_player_renderer_inputs(application.get("_profile_read_view"),world,scope)
	if _player_inputs.get("success") != true: return _fail("actual_Player_input_roots_not_prepared",_player_inputs)
	if not _registry.configure_original_player_input_template(loading,_player_inputs): return _fail("actual_Player_input_template_binding_rejected")
	var enemy_inputs: Dictionary=_streaming.prepare_original_enemy_renderer_inputs(world,scope)
	if enemy_inputs.get("success")!=true: return _fail("actual_Enemy_input_roots_not_prepared",enemy_inputs)
	if not _registry.configure_original_enemy_input_template(loading,enemy_inputs): return _fail("actual_Enemy_input_template_binding_rejected")
	var views: Dictionary = _views.create_original_main_views(root,world,shell.view,application.get("_profile_read_view"),application.get("_transport"),_streaming,application.get("_services").feature_main,_registry,loading,application)
	if views.get("success") != true: return _fail("actual_original_Main_views_not_created",views)
	var routed: Dictionary = application.get("_root_transport").bind_actual_original_world_views(world,_views)
	if routed.get("success") != true: return _fail("actual_same_Root_input_and_view_binding_rejected",routed)
	_world_receipt = {"success":true,"publication":views.publication,"actual_player_inputs":_player_inputs,"actual_root_id":root.get_instance_id(),"actual_registry_id":_registry.get_instance_id()}
	_stage = "WORLD_PHYSICAL_BOUND"
	return _world_receipt

func retire_actual_started_terminal_channels(terminal: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _application == null or _application.get_ref() == null or _stage != "WORLD_PHYSICAL_BOUND": return _fail("actual_started_Main_graph_terminal_required")
	var app: RefCounted = _application.get_ref()
	var transport: RefCounted = app.get("_transport")
	var native: Dictionary = _host.status()
	if transport.get("_state") != "CLOSED" or terminal.get("success") != true or terminal != transport.get("_terminal") or terminal.get("receipt",{}).get("actual_main_pump_id") != _pump.get_instance_id() or native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("running") != false or _prefix.has_pending(): return _fail("actual_joined_same_Main_terminal_required")
	var obligations: Dictionary = _closing_frames.capture_actual_closing_process_obligations()
	if not _closing_frames.finish_at_actual_Host_close(obligations.get("stop_receipt",{})): return _fail("actual_Host_verified_STOP_producer_retirement_required")
	if not transport.retire_actual_started_terminal_listener(terminal): return _fail("actual_terminal_transport_listener_retirement_failed")
	# Native owns these bindings and must authorize the started-only detach.
	# No use of ABORTED_BEFORE_START and no mutation of sealed owner internals.
	if not _host.has_method("retire_started_original_main_channels"): return _fail("actual_Native_started_owner_unbind_contract_missing")
	var owners: Dictionary = {"admission":_ports.admission,"claim_feature":app.get("_services").feature_main,"claim_origin":_origin,"live_feature":app.get("_services").feature_main,"streaming":_streaming,"caster":app.get("_services").caster_executor,"closing":_closing_frames,"map_producer":_views.get("_map_producer"),"map_executor":_views.get("_map_executor")}
	var map_terminal: Dictionary = terminal.get("receipt",{}).get("actual_main_io",{}).get("map_terminal",{})
	if owners.map_producer == null or owners.map_executor == null or map_terminal.get("status") != "READY" or map_terminal.get("actual_producer_id") != owners.map_producer.get_instance_id() or map_terminal.get("actual_map_owner_terminal",{}).get("owner_descriptor",{}).get("main_executor_id") != owners.map_executor.get_instance_id(): return _fail("actual_two_Map_binding_owners_required")
	var owner_ids: Dictionary = {}
	for role: String in owners: owner_ids[role] = owners[role].get_instance_id()
	var unbound: Dictionary = _host.call("retire_started_original_main_channels",owners)
	if unbound.get("success") != true or unbound.get("status") != "UNBOUND_AFTER_CLOSE" or unbound.get("host_object_id") != _host.get_instance_id() or unbound.get("bridge_generation") != terminal.receipt.bridge_generation or unbound.get("actual_owner_ids") != owner_ids or _host.status().get("main_channels_unbound_after_close") != true: return _fail("actual_Native_started_owner_unbind_not_proved",unbound)
	var driver: Node = _ports.get("lifecycle")
	if is_instance_valid(driver): driver.free()
	_ports = {}; _origin = null; _pump = null; _streaming = null; _views = null
	_registry = null; _consumer = null; _prefix = null; _closing_frames = null
	_player_inputs = {}; _world_receipt = {}; _phase_bridge = null
	_stage = "RETIRED_AFTER_CLOSE"
	_host = null; _application = null
	return {"success":true,"status":"READY","actual_composition_id":get_instance_id(),"actual_STOP_receipt":obligations.stop_receipt.duplicate(true),"actual_Native_owner_unbind":unbound.duplicate(true),"actual_pre_free_Map_terminal":map_terminal.duplicate(true)}

func actual_failure() -> Dictionary: return _fault.duplicate(true)

func retire_actual_unstarted_channels() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _application == null or _application.get_ref() == null or _host == null or _stage != "CHANNELS_BOUND" or not _world_receipt.is_empty(): return _fail("actual_unstarted_bound_Main_graph_required")
	var app: RefCounted = _application.get_ref()
	var transport: RefCounted = app.get("_transport")
	var feature: RefCounted = app.get("_services").feature_main
	if is_instance_valid(app.get("_root_transport").retained_root()) or _views.get("_root") != null or _registry.get("_root") != null or not _player_inputs.is_empty() or _prefix.has_pending() or transport.get("_state") != "MAIN": return _fail("actual_no_World_or_accepted_Main_work_required")
	var retired: Dictionary = _host.abort_prepared_original_main_channels({"admission":_ports.admission,"claim_feature":feature,"claim_origin":_origin,"live_feature":feature,"streaming":_streaming,"caster":app.get("_services").caster_executor,"closing":_closing_frames})
	if retired.get("status") != "ABORTED_BEFORE_START" or retired.get("success") != true: return _fail("actual_Native_unstarted_owner_unbinding_required",retired)
	if not _closing_frames.finish_after_actual_prestart_abort() or not transport.finish_after_actual_prestart_abort() or not _ports.admission.retire_actual_unstarted_Main_binding(retired): return _fail("actual_Native_aborted_Main_owner_retirement_failed",retired)
	var driver: Node = _ports.lifecycle
	if is_instance_valid(driver): driver.free()
	_ports = {}; _origin = null; _pump = null; _streaming = null; _views = null
	_registry = null; _consumer = null; _prefix = null; _closing_frames = null
	_stage = "ABORTED_BEFORE_START"
	_host = null; _application = null
	return {"success":true,"status":"ABORTED_BEFORE_START","native_receipt":retired}
