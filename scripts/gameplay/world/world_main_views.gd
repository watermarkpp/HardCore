extends RefCounted
## Main physical view owner. The caller retains this instance for the world's
## actual lifetime; no gameplay Node/model is constructed here.
const Hud := preload("res://scripts/gameplay/world/world_main_hud.gd")
const Menu := preload("res://scripts/system_menu_panel.gd")
const Town := preload("res://scripts/town_music_controller.gd")
const Audio := preload("res://scripts/audio_runtime_service.gd")
const Level := preload("res://scripts/ui_level_up_preview.gd")
const Relic := preload("res://scripts/ui_relic_proc_effect.gd")
const Frames := preload("res://scripts/monster_source_frames.gd")
const ViewportPort := preload("res://scripts/gameplay/world/world_visual_viewport_port.gd")
const Home := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const CameraPublication := preload("res://scripts/gameplay/world/world_camera_constraint_publication.gd")
const GroundSpike := preload("res://scripts/monster_ground_spike_effect.gd")
const MapExecutor := preload("res://scripts/gameplay/world/world_map_event_main.gd")
const CALLS := {
	"hud":["show_message","show_error_message","show_success_message","update_resources","update_warrior_states","update_status_buffs","cancel_attack_inputs","cancel_skill_inputs","cancel_item_slot_input_boundary","cancel_movement_input","set_item_quick_slots","set_skill_button_assignments","update_target","set_zone_name","begin_loading_transition","update_loading_progress","finish_loading_transition","set_shop_sell_quotes","set_shop_buy_quotes","apply_shop_buy_result","apply_shop_sell_result","apply_quest_abandon_result","apply_warehouse_sort_result","set_map_teleport_availability","set_auto_target_enabled","show_death_screen","show_loot_batch","update_hp","apply_revival_result"],
	"camera":["force_update_scroll","reset_smoothing"],"system_menu":["open_menu","close_menu","show_save_exit_failure"],
	"town_music":["set_town_presence","begin_map_transition","set_map_context","cancel"],"item_audio":["play_item_event","play_event"],"level_up":["replay"],"relic_proc":["replay"]
}
const PROPERTIES := {"camera":["global_position","position","zoom","offset","position_smoothing_enabled"]}
const INPUT_ARITIES := {"movement_changed":1,"interact_pressed":0,"skill_slot_pressed":2,"target_switch_pressed":0,"auto_target_changed":1,
	"skill_button_assignment_requested":1,"shop_buy_quotes_requested":1,"shop_buy_requested":1,"shop_sell_quotes_requested":1,"shop_sell_requested":1,
	"quest_abandon_requested":1,"warehouse_sort_requested":0,"map_teleport_availability_requested":1,"map_teleport_requested":1,"revival_requested":1,
	"item_quick_slot_assignment_requested":2,"item_quick_slot_use_requested":2,"attack_input_started":3,"attack_input_ended":3,"attack_input_cancelled":4,
	"skill_input_started":5,"skill_input_ended":5,"skill_input_cancelled":6,"loading_transition_covered":1}
var _root: Node2D
var _world: Dictionary
var _views: Dictionary = {}
var _transport: RefCounted
var _vault: RefCounted
var _feature: RefCounted
var _profile_view: RefCounted
var _player_view: Node2D
var _renderer_registry: RefCounted
var _actual_loading: RefCounted
var _prefix_fallback: RefCounted
var _menu_layer: CanvasLayer
var _closed := false
var _input_closed := false
var _input_sequence := 0
var _input_outbox: Array[Dictionary] = []
var _root_cancel_receipts: Dictionary = {}
var _publication_sequence := 0
var _caster: RefCounted
var _caster_loading: Dictionary
var _content: Node
var _closing_producer: RefCounted
var _map_executor: RefCounted
var _map_leaf: RefCounted
var _map_producer: RefCounted
var _map_host: Object
var _map_io: RefCounted
var _main_warm: RefCounted
var _original_warm_reservation_usec := -1
var _actual_budget_session_id := 0
var _source_header: Dictionary
var _header_identity: Dictionary
var _header_failure: Dictionary
var _prepared_source_frames_id := 0
var _application_main: RefCounted
var _last_map_arrival: Dictionary = {}
var _publication_failure: Dictionary = {}
func source_application_call(operation: String, arguments: Array) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _root == null or _feature == null: return _missing("actual_Main_application_target_required")
	if _closed and (_application_main == null or _renderer_registry == null or not _renderer_registry.has_accepted_original_retirement(operation,arguments)): return _missing("actual_accepted_Main_cleanup_continuation_required")
	if _application_main == null:
		var made := preload("res://scripts/gameplay/world/world_source_application_main.gd").new()
		if not made.configure_main(self): return _missing("actual_Main_application_binding_failed")
		_application_main = made
	return _application_main.execute_loading(operation,arguments)
func configure_original_loading_executors(caster: RefCounted, caster_loading: Dictionary, content: Node, closing_producer: RefCounted, map_executor: RefCounted, reservation_usec: int, actual_budget_session_id: int, actual_host: Object, actual_map_io: RefCounted) -> bool:
	_main()
	if _caster!=null or caster==null or content==null or closing_producer==null or map_executor==null or not is_same(map_executor,_map_executor) or actual_host==null or actual_map_io==null or reservation_usec<0 or actual_budget_session_id<=0: return false
	if caster_loading.get("world_context")!=_world or caster_loading.get("main_executor_id")!=caster.get_instance_id(): return false
	if not caster.has_method("install_original_warm_Main_leaf") or not caster.has_method("install_original_audio_main"): return false
	_caster=caster;_caster_loading=caster_loading;_content=content;_closing_producer=closing_producer;_map_executor=map_executor;_original_warm_reservation_usec=reservation_usec;_actual_budget_session_id=actual_budget_session_id;_map_host=actual_host;_map_io=actual_map_io
	return caster.install_original_audio_main(_views.item_audio,_renderer_registry.actual_original_audio_projection,_renderer_registry.capture_actual_original_audio_delivery)
func complete_original_source_owner_header(world: Dictionary, actual_source_root_id: int, actual_owner_session_id: int) -> Dictionary:
	_main()
	if world!=_world or actual_source_root_id>=0 or actual_owner_session_id!=_actual_budget_session_id or actual_owner_session_id<=0 or _caster==null: return _missing("actual_S_Root_Session_header_required")
	var scope: Dictionary=_actual_loading.actual_original_loading_scope(world)
	if _actual_loading.verify_actual_original_loading_scope(scope).get("success")!=true: return _missing("actual_Loading_header_scope")
	var identity: Dictionary={"world_context":world,"source_root_id":actual_source_root_id,"owner_session_id":actual_owner_session_id}
	if not _source_header.is_empty(): return {"success":true,"publication":_source_header.publication} if _source_header.identity==identity else _missing("actual_source_header_changed")
	if not _header_identity.is_empty(): return _header_failure if _header_identity==identity else _missing("actual_source_header_changed")
	var descriptor: Dictionary={"contract_id":"source.caster.warm.owner.v1","source_root_id":actual_source_root_id,"world_context":world,"main_executor_id":_caster.get_instance_id(),"owner_session_id":actual_owner_session_id}
	# Qualify/map-bind before warm mutates the actual accepted-claim owner. A
	# failed original mutation is retained for cleanup and never replayed.
	_header_identity=identity
	_header_failure=_missing("actual_header_initialization_incomplete")
	_map_leaf=preload("res://scripts/gameplay/world/world_map_visual_main.gd").new()
	_map_producer=preload("res://scripts/gameplay/source/main_map_loading_producer.gd").new()
	var map: Dictionary=preload("res://scripts/gameplay/world/world_map_visual_main.gd").capture_main(_views.background,actual_source_root_id,actual_owner_session_id,world,_map_executor.get_instance_id(),_map_producer)
	if map.get("success")!=true: _header_failure=map; return map
	if not _map_executor.configure_main(_map_host,_map_leaf,_map_producer,map.publication.owner_descriptor):
		_header_failure=_missing("actual_Map_Main_executor_binding"); return _header_failure
	if not _map_producer.configure_main(_map_host,_actual_loading,_map_io,_map_executor,map.publication.owner_descriptor):
		_header_failure=_missing("actual_Map_Loading_IO_providers"); return _header_failure
	if not _map_host.has_method("bind_original_map_loading_producer"):
		_header_failure=_missing("actual_Native_Map_producer_binding_API"); return _header_failure
	var map_producer_script: Script=_map_producer.get_script()
	var map_executor_script: Script=_map_executor.get_script()
	if not _map_host.bind_original_map_loading_producer(_map_producer,map_producer_script.get_source_code().sha256_text(),_map_executor,map_executor_script.get_source_code().sha256_text()):
		_header_failure=_missing("actual_Native_Map_producer_Script_binding"); return _header_failure
	if not _map_leaf.configure_main(_views.background,_map_producer,map.publication.owner_descriptor):
		_header_failure=_missing("actual_Map_Main_visual_leaf_binding"); return _header_failure
	var owner_binding: Dictionary = _actual_loading.bind_actual_original_map_loading_owner(_map_producer,_map_executor,_map_leaf,_root,_views.hud,map.publication.owner_descriptor)
	if owner_binding.get("success") != true:
		_header_failure=owner_binding; return _header_failure
	var warm:=preload("res://scripts/gameplay/world/world_caster_warm_main.gd").new()
	_main_warm=warm
	var configured: Dictionary=warm.configure_main(_caster,_root,_content,_closing_producer,descriptor)
	if configured.get("success")!=true: _header_failure=configured; return configured
	if not warm.has_method("configure_original_issued_claim_bridge") or not warm.configure_original_issued_claim_bridge(_feature):
		_header_failure=_missing("actual_Main_warm_issued_claim_bridge"); return _header_failure
	var adopted: Dictionary=warm.adopt_actual_original_loading_claims(_root)
	if adopted.get("success")!=true or not _caster.install_original_warm_Main_leaf(warm):
		_header_failure=_missing("actual_Main_warm_claim_adoption"); return _header_failure
	var publication: Dictionary=capture_original_publication(scope)
	if publication.is_empty(): _header_failure=_missing("actual_Main_header_publication"); return _header_failure
	publication.caster_loading=_caster_loading
	publication.caster_warm_owner=descriptor
	publication.original_warm_reservation_usec=_original_warm_reservation_usec
	publication.map_loading=map.publication
	var interactable: RefCounted = _caster.get("_interactable")
	if interactable == null or interactable.get("_proof").is_empty():
		_header_failure=_missing("actual_interactable_Loading_owner_missing"); return _header_failure
	var npc: Dictionary = interactable.inspect_actual_original_loading_pins(interactable.get("_proof"))
	if npc.get("success") != true: _header_failure=npc; return npc
	publication.interactable_loading=npc.publication
	_source_header={"identity":identity,"publication":publication}
	return {"success":true,"publication":publication}
func _main() -> void: assert(OS.get_thread_caller_id() == OS.get_main_thread_id())
static func _missing(reason: String) -> Dictionary: return {"success":false,"status":"MISSING","error":reason}
func create_original_main_views(root: Node2D, world: Dictionary, actual_player_view: Node2D,
	profile_view: RefCounted, transport: RefCounted, vault: RefCounted, feature: RefCounted,
	renderer_registry: RefCounted, actual_loading: RefCounted, fallback: RefCounted) -> Dictionary:
	_main()
	if _root != null or not is_instance_valid(root) or not root.is_inside_tree() or root.is_queued_for_deletion() or not is_instance_valid(actual_player_view) or actual_player_view.get_parent() != root: return _missing("actual_original_Main_root_and_player_view")
	if world.get("world_runtime_id") != root.get_instance_id(): return _missing("actual_original_Main_root_identity")
	for specification: Array in [[profile_view,["actual_source_snapshot","owner_thread_id"]],[transport,["submit_original_world_hud_event"]],[vault,["texture_for_renderer"]],[feature,["export_boot_value"]],[renderer_registry,["actual_original_prepared_player_shell","actual_original_player_view","actual_original_audio_projection","actual_world_views_retired"]],[actual_loading,["actual_original_loading_scope","verify_actual_original_loading_scope"]],[fallback,["apply_original_main_journal_event"]]]:
		if specification[0] == null: return _missing("actual_Main_dependency_null")
		for method: String in specification[1]:
			if not specification[0].has_method(method): return _missing("actual_Main_dependency:"+method)
	if profile_view.owner_thread_id() != OS.get_main_thread_id() or profile_view.actual_source_snapshot().is_empty(): return _missing("actual_Source_Profile_UI_publication")
	if renderer_registry.actual_original_prepared_player_shell(world) != actual_player_view: return _missing("actual_prepared_player_shell_registry")
	var scope: Dictionary = actual_loading.actual_original_loading_scope(world)
	if actual_loading.verify_actual_original_loading_scope(scope).get("success") != true: return _missing("actual_physical_Loading_scope")
	# Qualify every dependency before Node creation; errors do not leave a
	# half-created world view tree or silently re-run original gameplay _ready.
	_root = root; _world = world.duplicate(true); _player_view = actual_player_view
	_profile_view = profile_view; _transport = transport; _vault = vault; _feature = feature
	_renderer_registry = renderer_registry; _actual_loading = actual_loading; _prefix_fallback = fallback
	# The sole reply cursor exists before the first cold prefix is acquired.
	# Binding its real Source descriptor still happens only at the owner header;
	# its original empty-effect body can already flush unrelated boot prefixes.
	_map_executor = MapExecutor.new()
	var frames_publication: Dictionary=Frames.capture_original_owner_handoff()
	if frames_publication.is_empty() or not vault.has_method("capture_original_source_texture_roots") or not Frames.adopt_original_source_owner(int(frames_publication.session_cache_id),vault): return _missing("actual_persistent_overlay_Main_adoption")
	_prepared_source_frames_id = int(frames_publication.session_cache_id)
	var background:=preload("res://scripts/gameplay/world/world_main_background.gd").new()
	if not background.has_method("configure_original_Main_visual_only") or not background.configure_original_Main_visual_only(): return _missing("actual_Background_visual_only_source_overlay")
	_root.add_child(background);_root.move_child(background,0);_views.background=background
	var camera := Camera2D.new()
	camera.name = "WorldCamera"; camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE * preload("res://scripts/art_spec.gd").CAMERA_ZOOM
	_root.add_child(camera); _views.camera = camera
	var hud := Hud.new()
	if not hud.configure_original_profile_view(profile_view): return _missing("actual_Main_HUD_read_view")
	for name: String in INPUT_ARITIES:
		if not hud.has_signal(name): return _missing("original_HUD_signal:"+name)
		_connect_signal(hud,StringName(name),INPUT_ARITIES[name])
	_root.add_child(hud); _views.hud = hud
	var town := Town.new(); town.name = "TownMusicController"; _root.add_child(town); _views.town_music = town
	var audio := Audio.new(); audio.name = "AudioRuntimeService"; _root.add_child(audio); audio.sync_sfx_enabled_from_bus(); _views.item_audio = audio
	hud.loading_transition_finished.connect(town.on_loading_transition_finished)
	var level := Level.new(); level.name = "PlayerLevelUpEffect"; level.z_index = 0
	_player_view.add_child(level); level.process_mode = Node.PROCESS_MODE_INHERIT
	level.set_meta("preview_only",false); level.set_meta("gameplay_event_source","PlayerState.levels_gained"); _views.level_up = level
	var relic := Relic.new(); relic.name = "PlayerRelicProcEffect"; relic.z_index = 0; _player_view.add_child(relic); _views.relic_proc = relic
	_menu_layer = CanvasLayer.new(); _menu_layer.layer = 200; _root.add_child(_menu_layer)
	var menu := Menu.new(); menu.name = "SystemMenuPanel"; menu.process_mode = Node.PROCESS_MODE_WHEN_PAUSED; menu.visible = false
	for name: StringName in [&"visibility_changed",&"continue_requested",&"return_to_character_select_requested",&"save_and_exit_requested"]: _connect_signal(menu,name,0)
	_connect_signal(menu,&"audio_setting_changed",1)
	_menu_layer.add_child(menu); menu.set_audio_levels(AudioPreferences.music_volume,AudioPreferences.sfx_volume); _views.system_menu = menu
	# Actual compatible Main slots remain literal views. The original typed
	# CharacterBody player slot is deliberately not used for the pure shell.
	for field: String in {"background":"background","hud":"hud","_world_camera":"camera","_system_menu_panel":"system_menu","_town_music_controller":"town_music","_audio_runtime_service":"item_audio","_player_level_up_effect":"level_up","_player_relic_proc_effect":"relic_proc"}:
		var kind: String={"background":"background","hud":"hud","_world_camera":"camera","_system_menu_panel":"system_menu","_town_music_controller":"town_music","_audio_runtime_service":"item_audio","_player_level_up_effect":"level_up","_player_relic_proc_effect":"relic_proc"}[field]
		_root.set(field,_views[kind])
	var publication: Dictionary = capture_original_publication(scope)
	if publication.is_empty(): return _publication_failure if not _publication_failure.is_empty() else _missing("actual_Main_view_publication_missing")
	return {"success":true,"publication":publication}

func actual_original_map_executor() -> RefCounted:
	_main()
	return _map_executor

func abort_actual_original_uncommitted_views(host: Object) -> Dictionary:
	# This is exclusively the before-Host-start rollback. An admitted Source
	# header/claim cannot be released by pretending it is an uncommitted view.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _closed or _root == null or host == null or not host.is_class("HardCoreSimulationHost") or host.status().get("running") == true or not _header_identity.is_empty() or not _source_header.is_empty(): return _missing("actual_uncommitted_Main_views_required")
	var attachment: Variant = _root.get("_original_source_main_attachment")
	if not attachment is RefCounted or attachment.get("_transport") == null or attachment.get("_transport").get("_host") != host: return _missing("actual_same_unstarted_Root_Host_required")
	if _renderer_registry == null or not _renderer_registry.get("_actors").is_empty() or not _renderer_registry.get("_retiring").is_empty() or _renderer_registry.get("_player_id") != 0: return _missing("actual_Source_actor_bindings_bar_uncommitted_abort")
	if _prepared_source_frames_id != 0 and not Frames.close_original_source_owner(_prepared_source_frames_id): return {"success":false,"status":"PENDING","error":"actual_overlay_claims_or_demands_still_owned"}
	_input_closed = true
	var released: Array[int] = []
	for field: String in {"background":"background","hud":"hud","_world_camera":"camera","_system_menu_panel":"system_menu","_town_music_controller":"town_music","_audio_runtime_service":"item_audio","_player_level_up_effect":"level_up","_player_relic_proc_effect":"relic_proc"}:
		var kind: String = {"background":"background","hud":"hud","_world_camera":"camera","_system_menu_panel":"system_menu","_town_music_controller":"town_music","_audio_runtime_service":"item_audio","_player_level_up_effect":"level_up","_player_relic_proc_effect":"relic_proc"}[field]
		if _views.has(kind) and _root.get(field) == _views[kind]: _root.set(field,null)
	# Only the nodes actually created by this owner are released. The Root,
	# selected Profile, prepared player shell and launch code lease keep their
	# original owners and are retired by the existing blueprint abort chain.
	for value: Variant in _views.values():
		if is_instance_valid(value):
			released.append(value.get_instance_id())
			value.free()
	if is_instance_valid(_menu_layer):
		released.append(_menu_layer.get_instance_id())
		_menu_layer.free()
	_views = {}; _menu_layer = null; _prepared_source_frames_id = 0
	_closed = true
	return {"success":true,"status":"READY","actual_released_node_ids":released,"world_context":_world.duplicate(true),"actual_Source_started":false}

func _connect_signal(node: Node, name: StringName, count: int) -> void:
	match count:
		0: node.connect(name,func(): _submit_ui(name,[]))
		1: node.connect(name,func(a: Variant): _submit_ui(name,[a]))
		2: node.connect(name,func(a: Variant,b: Variant): _submit_ui(name,[a,b]))
		3: node.connect(name,func(a: Variant,b: Variant,c: Variant): _submit_ui(name,[a,b,c]))
		4: node.connect(name,func(a: Variant,b: Variant,c: Variant,d: Variant): _submit_ui(name,[a,b,c,d]))
		5: node.connect(name,func(a: Variant,b: Variant,c: Variant,d: Variant,e: Variant): _submit_ui(name,[a,b,c,d,e]))
		6: node.connect(name,func(a: Variant,b: Variant,c: Variant,d: Variant,e: Variant,f: Variant): _submit_ui(name,[a,b,c,d,e,f]))
func _submit_ui(name: StringName, args: Array) -> void:
	_main()
	if _closed or _input_closed: return
	var actual: Dictionary = _capture_actual_original_input(name,args)
	if actual.get("status") != "RETAINED": push_error("actual_original_UI_command_transport_failure")
func submit_actual_original_root_input(root: Node2D, attachment: RefCounted, name: StringName, args: Array) -> Dictionary:
	_main()
	if root != _root or attachment == null or root.get("_original_source_main_attachment") != attachment or attachment.get_script() != preload("res://scripts/gameplay/world/world_main_root_attachment.gd") or not attachment.get("_root") is WeakRef or attachment.get("_root").get_ref() != root: return {"status":"INVALID","error":"actual_same_Root_input_callback_required"}
	var depths: Dictionary = attachment.get("_callback_depths")
	if name == &"notification":
		if int(depths.get("notification",0)) <= 0 or args.size() != 1 or args[0] not in [Node.NOTIFICATION_WM_GO_BACK_REQUEST,Node.NOTIFICATION_APPLICATION_PAUSED,Node.NOTIFICATION_APPLICATION_FOCUS_OUT,Node.NOTIFICATION_APPLICATION_RESUMED,Node.NOTIFICATION_WM_CLOSE_REQUEST]: return {"status":"INVALID","error":"actual_original_Root_notification_required"}
	elif name == &"unhandled_ui_cancel":
		if int(depths.get("unhandled_input",0)) <= 0 or not args.is_empty(): return {"status":"INVALID","error":"actual_original_Root_unhandled_input_required"}
	elif name == &"viewport_pick_press":
		if int(depths.get("unhandled_input",0))<=0 or not args.is_empty(): return {"status":"INVALID","error":"actual_pointer_callback_required"}
		var fact: Dictionary=preload("res://scripts/gameplay/presentation/main_original_pick_input.gd").capture_main(root,attachment.get("_actual_pointer_event"))
		if fact.is_empty(): return {"status":"INVALID","error":"actual_unhandled_pointer_press_required"}
		args=[fact]
	else: return {"status":"INVALID","error":"unknown_original_Root_input"}
	if _closed or _input_closed: return {"status":"CLOSED"}
	if name == &"unhandled_ui_cancel":
		# Handle this actual Main input event now. Source acknowledges this same
		# physical action later; it must not mark an unrelated later frame input.
		var receipt: Dictionary = {"contract_id":"hardcore.input.actual_Main_ui_cancel.v1","world_context":_world.duplicate(true),"actual_root_id":root.get_instance_id(),"view_sequence":_input_sequence+1,"main_process_frame":Engine.get_process_frames()}
		root.get_viewport().set_input_as_handled()
		_root_cancel_receipts[receipt.view_sequence] = receipt
		return _capture_actual_original_input(name,args,{"actual_Main_ui_cancel":receipt})
	return _capture_actual_original_input(name,args)
func _capture_actual_original_input(name: StringName, args: Array, actual_context: Dictionary = {}) -> Dictionary:
	var context := {"actual_Main_capture":true,"world_context":_world.duplicate(true),"main_process_frame":Engine.get_process_frames()}
	context.merge(actual_context,false)
	if name == &"loading_transition_covered": context.actual_hud_id = _views.hud.get_instance_id()
	if name == &"world_viewport_publication":
		var hud: Node = _views.hud
		context.actual_hud_observation = {"actual_hud_id":hud.get_instance_id(),"_last_hp":hud.get("_last_hp"),"_last_max_hp":hud.get("_last_max_hp"),"_catalog_icon_prewarm_complete":hud.get("_catalog_icon_prewarm_complete")}
	if name == &"shop_buy_requested":
		if not is_instance_valid(_views.hud.shop_panel): return {"status":"INVALID","error":"actual_shop_view_required"}
		context.shop_stock = _views.hud.shop_panel.stock.duplicate(true)
	if name == &"warehouse_sort_requested":
		if not is_instance_valid(_views.hud.warehouse_panel): return {"status":"INVALID","error":"actual_warehouse_view_required"}
		context.warehouse_page = _views.hud.warehouse_panel.warehouse_page
	if name == &"visibility_changed": context.menu_visible_in_tree = _views.system_menu.visible and _views.system_menu.is_visible_in_tree()
	_input_sequence += 1
	var source_name: StringName = {&"movement_changed":&"gameplay_movement",&"attack_input_started":&"mobile_attack_started",&"attack_input_ended":&"mobile_attack_ended",&"attack_input_cancelled":&"mobile_attack_cancelled"}.get(name,name)
	var graph: RefCounted=ClassDB.instantiate("HardCoreContentValueGraph")
	var captured: Dictionary=graph.capture({"name":source_name,"arguments":args,"context":context,"sequence":_input_sequence},true,false)
	assert(captured.get("success")==true,"actual_original_UI_event_contains_Main_object")
	_input_outbox.append(captured.value)
	if not _flush_original_input_outbox():
		return {"status":"INVALID","error":"actual_original_input_transport_rejected"}
	return {"status":"RETAINED","sequence":_input_sequence}
func _flush_original_input_outbox() -> bool:
	while not _input_outbox.is_empty():
		var entry: Dictionary=_input_outbox.front()
		var admitted: Dictionary=_transport.submit_original_world_hud_event(_world,entry.name,entry.arguments,entry.context,entry.sequence)
		if admitted.get("status")=="BACKPRESSURE": return true
		if admitted.get("status")!="ACCEPTED": return false
		_input_outbox.pop_front()
	return true
func original_main_pending_view_input_count() -> int:
	_main()
	return _input_outbox.size()+_root_cancel_receipts.size()

func service_actual_original_ui_close() -> Dictionary:
	_main()
	if not _input_closed: return _missing("actual_world_input_close_boundary_required")
	if _map_producer != null and _map_host.status().get("close_requested") == true:
		var retirement: Dictionary = _map_producer.service_actual_owner_retirement()
		if retirement.get("status") not in ["PENDING","READY"]: return retirement
		if retirement.get("status") == "READY":
			var certified: Dictionary = _map_producer.certify_actual_owner_terminal()
			if certified.get("success") != true: return certified
	var hud: Node = _views.get("hud")
	if not is_instance_valid(hud) or hud.get_script() not in [Hud,preload("res://scripts/hud.gd")] or not hud.is_inside_tree(): return _missing("actual_live_original_HUD_required")
	if not hud.begin_actual_original_source_prewarm_close(): return _missing("actual_HUD_prewarm_close_rejected")
	var progress: Dictionary = hud.service_actual_original_source_prewarm_close()
	if progress.get("success") != true: return progress
	return capture_actual_original_ui_close_state()

func capture_actual_original_ui_close_state() -> Dictionary:
	_main()
	var hud: Node = _views.get("hud")
	if not is_instance_valid(hud): return _missing("actual_HUD_close_observation_required")
	var callbacks: Variant = hud.get("_original_main_callback_ledger")
	var pending: Variant = hud.get("_panel_script_pending")
	if not callbacks is Dictionary or not pending is Dictionary: return _missing("actual_HUD_callback_and_loader_ledgers_required")
	var callback_depth := 0
	for name: Variant in callbacks:
		var count: Variant = callbacks[name]
		if not count is int or count < 0: return _missing("actual_HUD_callback_depth_invalid")
		callback_depth += count
	var panels: Variant = hud.get("_panel_prewarm_in_progress")
	var icons: Variant = hud.get("_catalog_icon_prewarm_in_progress")
	if not panels is bool or not icons is bool: return _missing("actual_HUD_prewarm_state_required")
	var icon_pending: int = preload("res://scripts/hud.gd").UIItemTextureCacheScript.threaded_pending_count()
	var map_warm: Dictionary = {"created":false,"pending":false}
	if _application_main != null:
		map_warm = _application_main.inspect_actual_original_map_warm()
		map_warm = map_warm.duplicate(true)
		map_warm.created = true
		map_warm.pending = _application_main.has_pending_original_map_warm()
	return {"success":true,"terminal":_input_closed and _input_outbox.is_empty() and _root_cancel_receipts.is_empty() and callback_depth == 0 and pending.is_empty() and not panels and not icons and icon_pending == 0 and not map_warm.pending,"actual_hud_id":hud.get_instance_id(),"callback_depth":callback_depth,"panel_script_pending":pending.size(),"panel_prewarm_active":panels,"catalog_prewarm_active":icons,"icon_requests_pending":icon_pending,"actual_map_warm":map_warm}

func capture_original_publication(scope: Dictionary) -> Dictionary:
	_main()
	_publication_failure = {}
	if _root == null or _closed:
		_publication_failure = _missing("actual_Main_view_owner_retired")
		return {}
	var loading: Dictionary = _actual_loading.verify_actual_original_loading_scope(scope)
	if loading.get("success") != true:
		_publication_failure = loading
		return {}
	var views := {}
	for kind: String in _views:
		var node: Node = _views[kind]
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion():
			_publication_failure = _missing("actual_Main_view_not_retained:"+kind)
			return {}
		var state := {}
		if kind == "hud":
			for field: String in ["_last_hp","_last_max_hp","_catalog_icon_prewarm_complete"]: state[field] = node.get(field)
		if kind == "system_menu": state.visible = node.visible
		if kind == "camera":
			for property: String in PROPERTIES.camera: state[property] = node.get(property)
		views[kind] = {"present":true,"node_id":node.get_instance_id(),"script_sha256":node.get_script().get_source_code().sha256_text() if node.get_script() != null else "", "state":state,"input_routes":INPUT_ARITIES.keys() if kind == "hud" else []}
	_publication_sequence += 1
	var audio_services: Array = []
	for service: Node in _root.get_tree().get_nodes_in_group("audio_runtime_service"):
		if not service.has_method("play_monster_event"): continue
		var methods: Array[StringName] = []
		for method: StringName in [&"play_monster_event",&"play_player_physical_contact",&"retire_monster_audio_owner"]:
			if service.has_method(method): methods.append(method)
		audio_services.append({"token":service.get_instance_id(),"state":{"present":true,"inside_tree":service.is_inside_tree(),"same_tree":service.get_tree()==_root.get_tree(),"methods":methods}})
	var frames: Dictionary=Frames.capture_original_owner_handoff()
	if frames.is_empty():
		_publication_failure = _missing("actual_SourceFrames_publication_missing")
		return {}
	frames.actual_texture_roots=_vault.capture_original_source_texture_roots("source_overlay_frames:%d" % int(frames.session_cache_id))
	frames.loading_scope=scope
	return {"contract_id":"world.Main.view_services.publication.v1","world_context":_world.duplicate(true),"views":views,
		"viewport":ViewportPort.capture_original_main(_root,_world,_publication_sequence),
		"source_frames":frames,"audio":{"contract_id":"world.audio.actual_Main_services.v1","world_context":_world.duplicate(true),"services":audio_services,"equipment_visual_catalog":GameData.equipment_visual_catalog.duplicate(true),"equipment_visual_catalog_sha256":FileAccess.get_sha256(GameData.EQUIPMENT_VISUAL_CATALOG_PATH)},
		"root_reference":_feature.export_boot_value(_root),"home_screen_position_px":Home.home_screen_position_px(),
		"main_service_reference":_feature.export_boot_value(self),
		"original_map_loading_settings":{"max_items_per_frame":int(ProjectSettings.get_setting("world/loading/max_items_per_frame",preload("res://scripts/world_bootstrap_coordinator.gd").DEFAULT_MAX_ITEMS_PER_FRAME)),"slice_budget_ms":float(ProjectSettings.get_setting("world/loading/slice_budget_ms",preload("res://scripts/world_bootstrap_coordinator.gd").DEFAULT_SLICE_BUDGET_MS))},
		"camera_constraint":CameraPublication.capture_original_main(),"bootstrap_resources":{"loading_scope":scope.duplicate(true),"display_server_name":DisplayServer.get_name()},
		"diagnostic_policy":{"combat_enabled":CombatDiagnosticLog.capture_enabled(),"skill_geometry_enabled":SkillFootprintDiagnosticLog.capture_enabled(),"file_output_enabled":RuntimeDiagnostics.file_output_enabled()}}

func _acknowledge_actual_original_ui_cancel(event: Dictionary) -> bool:
	_main()
	if _transport == null or _transport.get("_prefix") == null or _transport.get("_prefix").actual_current_original_event() != event: return false
	var args: Variant = event.get("arguments")
	if not args is Array or args.size() != 1 or not args[0] is Dictionary: return false
	var receipt: Dictionary = args[0]
	var sequence: Variant = receipt.get("view_sequence")
	if not sequence is int or not _root_cancel_receipts.has(sequence) or _root_cancel_receipts[sequence] != receipt: return false
	_root_cancel_receipts.erase(sequence)
	return true

func apply_original_main_journal_event(event: Dictionary) -> Variant:
	if event.get("kind") == "original_world_presentation" and event.get("operation") == &"set_input_as_handled":
		return _acknowledge_actual_original_ui_cancel(event)
	_main()
	if event.get("kind") == "original_profile_transport" and event.get("operation") in [&"original_profile_session_adopted",&"original_profile_command_receipt",&"original_profile_command_acknowledged",&"original_application_close_authorized"]:
		return _transport.apply_original_transport_journal_event(event) if _transport != null else false
	if event.get("kind") == "original_world_presentation" and event.get("operation") in [&"original_feature_call_admitted",&"original_feature_call_result",&"original_feature_call_acknowledged"]:
		return _transport.apply_original_transport_journal_event(event) if _transport != null else {"status":"INVALID","error":"actual_transport_executor_missing"}
	if event.get("kind") == "original_world_presentation" and event.get("operation") == &"original_source_root_final_free":
		return _prefix_fallback.apply_original_main_journal_event(event)
	if event.get("kind") == "original_profile_transport" and event.get("operation") == &"original_profile_terminal_export":
		return _transport.apply_original_transport_journal_event(event) if _transport != null else false
	if event.get("kind") == "original_world_presentation" and event.get("operation") == &"safe_logout_error_report":
		return _apply_actual_safe_logout_error_report(event)
	if _closed: return false
	if event.get("kind") != "original_world_presentation": return _prefix_fallback.apply_original_main_journal_event(event)
	if event.get("operation") in [&"original_profile_session_adopted",&"original_profile_command_receipt",&"original_profile_command_acknowledged",&"original_application_close_authorized"]:
		return _transport.apply_original_transport_journal_event(event) if _transport != null else {"status":"INVALID","error":"actual_transport_executor_missing"}
	if event.get("operation") == &"caster_presentation":
		return _caster.execute_original_journal_event(event) if _caster != null else {"status":"INVALID","error":"actual_caster_executor_missing"}
	if event.get("operation")==&"map_loading":
		return _map_executor.execute_original_journal_event(event) if _map_executor!=null else {"status":"INVALID","error":"actual_map_executor_missing"}
	if event.get("operation") in [&"source_map_visual_zone",&"source_map_visual_focus"]:
		return _map_executor!=null and _map_executor.apply_original_map_visual_effect(event).get("success")==true
	var args: Array = event.get("arguments",[])
	match event.get("operation"):
		&"original_UI_texture_poll":
			if not args.is_empty(): return false
			preload("res://scripts/ui_item_texture_cache.gd").poll_threaded_paths()
			return true
		&"original_Main_frame_boundary_reset":
			if not args.is_empty(): return false
			RuntimeDiagnostics.reset_wall_frame_interval()
			return true
		&"source_map_arrival":
			return args.size() == 1 and args[0] is Dictionary and _apply_actual_original_map_arrival(args[0])
		&"original_enemy_ground_spike_visual":
			if args.size() != 1 or not args[0] is Dictionary: return false
			var descriptor: Dictionary = args[0]
			if str(descriptor.get("effect_id", "")) != GroundSpike.EFFECT_ID or str(descriptor.get("release_id", "")).is_empty(): return false
			var effect: Node2D = GroundSpike.create_visual(descriptor)
			if effect == null: return false
			_root.add_child(effect)
			return true
		&"original_view_call":
			if args.size()!=4 or not CALLS.has(args[0]) or args[2] not in CALLS[args[0]]: return false
			var node: Node = _views[args[0]]
			if node.get_instance_id()!=args[1] or not is_instance_valid(node) or node.is_queued_for_deletion(): return false
			node.callv(args[2],args[3]); return true
		&"original_view_set":
			if args.size()!=4 or not PROPERTIES.has(args[0]) or args[2] not in PROPERTIES[args[0]]: return false
			var node: Node = _views[args[0]]
			if node.get_instance_id()!=args[1] or not is_instance_valid(node) or node.is_queued_for_deletion(): return false
			node.set(args[2],args[3]); return true
		&"source_overlay_install": return args.size()==3 and Frames.install_original_owner_texture(args[0],args[1],args[2],_vault)
		&"source_overlay_evict": return args.size()==2 and Frames.evict_original_owner_texture(args[0],args[1])
		&"source_overlay_close": return args.size()==1 and Frames.close_original_source_owner(args[0])
		&"original_tree_pause":
			if args.size()!=1 or not args[0] is bool: return false
			_root.get_tree().paused=args[0]; return true
		&"original_audio_retire":
			if args.size()!=2 or _views.item_audio.get_instance_id()!=args[0]: return false
			return _views.item_audio.retire_monster_audio_owner(args[1][0],args[1][1])
		&"original_audio_setting":
			if args.size()!=1 or not args[0] is Dictionary: return false
			var request: Dictionary = args[0]
			if request.get("contract_id")=="ui.audio.setting.v2": AudioPreferences.set_level(str(request.get("channel","")),request.get("value",null))
			elif request.get("contract_id")=="ui.audio.setting.v1":
				var id := str(request.get("setting_id",""))
				if id not in ["audio.music.enabled","audio.sfx.enabled"]: return false
				AudioPreferences.set_level("music" if id=="audio.music.enabled" else "sfx",1.0 if bool(request.get("enabled",true)) else 0.0)
			return true
		&"original_diagnostic_line":
			if args.size()!=2 or not args[1] is String: return false
			if args[0]=="combat": CombatDiagnosticLog._append_json_line(args[1]); print(CombatDiagnosticLog.LOG_PREFIX+args[1])
			elif args[0]=="footprint": SkillFootprintDiagnosticLog._append_json_line(args[1]); print(SkillFootprintDiagnosticLog.LOG_PREFIX+args[1])
			else: return false
			return true
		&"original_loot_trace":
			if args.size()!=1 or not args[0] is Dictionary: return false
			preload("res://scripts/gameplay/profile/legacy_loot_trace_port.gd").new().write_trace(args[0]); return true
		&"original_profile_view":
			return args.size()==1 and _profile_view.accept_original_journal_snapshot(args[0])
		&"original_character_select_transition":
			return args.is_empty() and _transport.request_original_character_select_transition(_world)
		&"original_tree_quit":
			return args.is_empty() and _transport.request_original_application_close(_world)
	return _prefix_fallback.apply_original_main_journal_event(event)

func _apply_actual_original_map_arrival(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _closed or _map_host == null or not _map_host.verify_committed_original_map_arrival(transaction): return false
	if transaction == _last_map_arrival: return _world == transaction.get("after_world")
	if _world != transaction.get("before_world") or _root.get_instance_id() != transaction.get("after_world",{}).get("world_runtime_id") or _root.get("current_map_id") != _world.runtime_map_id or _root.get("_zone_generation") != _world.world_epoch: return false
	if _renderer_registry==null or not _renderer_registry.prepare_actual_original_map_arrival_effect_exit(transaction): return false
	var attachment: RefCounted = _root.get("_original_source_main_attachment")
	var root_transport: RefCounted = attachment.get("_transport") if attachment != null else null
	if root_transport == null or _caster == null or _map_producer == null or not _map_producer.can_apply_actual_original_map_arrival(transaction) or not root_transport.can_commit_actual_original_map_arrival(transaction) or not _transport.can_commit_actual_original_map_arrival(transaction) or not _renderer_registry.can_commit_actual_original_map_arrival(transaction) or not _caster.can_commit_actual_original_map_arrival(transaction): return false
	# Every identity and physical pin is checked before the synchronous Main
	# commit. Failed suffixes retain these actual owners and the claimed prefix.
	if not _renderer_registry.commit_actual_original_map_arrival(transaction): return false
	if not _caster.commit_actual_original_map_arrival(transaction): return false
	if not _map_producer.apply_actual_original_map_arrival(transaction): return false
	if not root_transport.commit_actual_original_map_arrival(transaction) or not _transport.commit_actual_original_map_arrival(transaction): return false
	_world = transaction.after_world.duplicate(true)
	_root.set("current_map_id",_world.runtime_map_id)
	_root.set("_zone_generation",_world.world_epoch)
	_last_map_arrival = transaction.duplicate(true)
	return true
func service_actual_Main_overlay_demands() -> bool:
	_main()
	if not _flush_original_input_outbox(): return false
	var admitted: bool = not _input_closed and _transport.original_world_hud_input_admission_current(_world)
	if admitted:
		_publication_sequence+=1
		var actual_viewport: Dictionary=ViewportPort.capture_original_main(_root,_world,_publication_sequence)
		if actual_viewport.is_empty(): return false
		_submit_ui(&"world_viewport_publication",[actual_viewport])
	if admitted:
		for demand: Dictionary in Frames.take_original_owner_demands():
			_submit_ui(&"source_frames_texture_demand",[demand])
	return true

func close_original_view_input_admission(world: Dictionary) -> bool:
	_main()
	if world!=_world: return false
	_input_closed=true
	# These are Main-local unaccepted optional demands, never accepted Native
	# loader or UI commands. The actual transport independently drains accepted.
	Frames.take_original_owner_demands()
	return _flush_original_input_outbox() and _input_outbox.is_empty()

func confirm_original_main_prefix_acknowledged(prefix: Dictionary, actual_native_receipt: Dictionary) -> bool:
	_main()
	if _map_executor==null: return false
	return _map_executor.confirm_original_map_prefix_acknowledged(prefix,actual_native_receipt)
func flush_original_main_replies() -> Dictionary:
	_main()
	if _map_executor==null: return {"status":"INVALID","error":"actual_map_executor_missing"}
	return _map_executor.flush_original_map_replies()
func has_pending_original_main_replies() -> bool:
	_main()
	return _map_executor!=null and _map_executor.has_pending_original_map_reply()

func capture_actual_original_world_view_exit(world: Dictionary) -> Dictionary:
	_main()
	if world != _world or _renderer_registry == null: return {"success":false,"status":"INVALID"}
	if not _input_closed: return {"success":true,"status":"PENDING"}
	var ui: Dictionary = capture_actual_original_ui_close_state()
	if ui.get("success") != true or ui.get("terminal") != true: return {"success":true,"status":"PENDING"}
	var actual: Dictionary = _renderer_registry.capture_original_world_exit_state(world)
	if actual.get("status") != "READY": return actual
	var result: Dictionary = actual.duplicate(true)
	result.actual_ui_input_closed = ui.duplicate(true)
	return result

func capture_actual_original_actor_view_free(identity: Dictionary) -> Dictionary:
	_main()
	return _renderer_registry.capture_original_actor_free_state(identity) if _renderer_registry != null else {"success":false,"status":"INVALID"}

func _apply_actual_safe_logout_error_report(event: Dictionary) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _transport==null or _transport.get("_prefix")==null or _transport.get("_prefix").actual_current_original_event()!=event: return false
	if event.get("kind")!="original_world_presentation" or event.get("operation")!=&"safe_logout_error_report" or event.get("source_site",{}).get("world_context")!=_world or not is_instance_valid(_root) or not _root.is_inside_tree() or _root.get_instance_id()!=_world.get("world_runtime_id") or _root.get_script()!=preload("res://scripts/game_root.gd"): return false
	var args: Variant=event.get("arguments")
	if not args is Array or args.size()!=2 or not (args[0] is String or args[0] is StringName) or not args[1] is String: return false
	_root._report_safe_logout_error(StringName(args[0]),args[1])
	return true
