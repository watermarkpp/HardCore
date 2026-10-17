extends "res://scripts/gameplay/world/world_root_source_callbacks.gd"

## Original GameRoot source boundaries, on the same S Core. No actor or timer
## state is mirrored here. Main services are real token based ports, mandatory.
const ViewServices := preload("res://scripts/gameplay/world/world_main_service_ports.gd")
const SourceTree := preload("res://scripts/gameplay/world/world_original_source_tree.gd")
const Bootstrap := preload("res://scripts/gameplay/world/world_map_loading_coordinator.gd")
const LootPreferences := preload("res://scripts/gameplay/world/world_loot_preferences.gd")
const LootDescriptors := preload("res://scripts/gameplay/world/world_loot_descriptors.gd")
const LootFactory := preload("res://scripts/gameplay/world/world_loot_actor_factory.gd")
const LootManager := preload("res://scripts/gameplay/world/world_loot_runtime_manager.gd")
const FollowAuthority := preload("res://scripts/gameplay/world/world_follow_landing_authority.gd")

signal original_physics_frame

const REQUIRED_VIEW_SERVICES := {
	"AudioPrimitives":["service_state","find_services_in_original_group_order","classic_weapon_shape","adopt_registered_service","invoke_service","reference_has_method"],
	"CombatLog":["capture_enabled","record"], "SkillFootprintLog":["capture_enabled","record"], "LootTrace":["record"],
	"CasterPresentation":["create_visual_model","bind_projectile","bind_ground","redraw_cast","projectile_audio_phase","prepare_projectile_visual","set_cast_y_sort","create_fire_wall_cell","fire_wall_animation_diagnostics","activate_fire_wall_cells","synchronize_fire_wall_cells","redraw_ground_if_without_sprite","prepare_ground_visual"],
	"CasterVisual":["is_runtime_ready","profile","visual_profile","animation_duration","render_policy"],
	"ContentLayers":["prepare_resource_directory","claim_internal_code_world_retention","retire_internal_code_result","retire_threaded_resource_claims"],
	"SourceFrames":["profile_for_id","request_profile","poll","retire_pending_threaded_claims"], "ProjectileVisual":["prewarm_for_monster_id"], "VisualViewport":["viewport_snapshot"],
	"WorldViewLifecycle":["configure_original_ready_views","publish_original_prefix","actual_world_view_exit","release_presented_actor_at_original_free"],
	"WorldUiCommandOwner":["dispatch_original_hud_event"],
	"WorldHomeSource":["home_screen_position_px","get_map_profile"], "WorldPauseControl":["apply_original_pause"],
	"WorldSourceCheckpoint":["original_idle_callbacks","original_control_boundary","original_world_exit_admission","original_fault_exit_admission"],
	"WorldBootstrapResources":["display_server_name","exists","load","load_threaded_request","load_threaded_get_status","load_threaded_get","is_original_resource_reference","blocking_original_loading_scope_allowed"],
	"WorldBootstrapPipeline":["travel_to_service_home","set_loading_window_active","retire_pending_warm_textures","retire_loading_texture_claims"],
	"ItemDropInstanceRules":["is_affixed_instance"],
	"MonsterRespawnPolicyScript":["resolve"], "WorldClockDeltaScript":["valid_world_entry"]
}
const PROFILE_SIGNAL_METHODS := {
	"consumable_requested":"_on_consumable_used", "background_item_save_failed":"_on_background_item_save_failed",
	"scroll_requested":"_on_scroll_used", "item_audio_committed":"_on_item_audio_committed",
	"temporary_item_buff_expired":"_on_temporary_item_buff_expired", "relic_proc_started":"_on_relic_proc_started",
	"levels_gained":"_on_player_levels_gained", "skills_changed":"_synchronize_main_pet_skill_ranks",
	"equipment_changed":"_synchronize_main_pet_skill_ranks"
}
var _source_tree: RefCounted
var _source_publication: Dictionary
var _source_initialized := false
var _ready_rng_witness: Dictionary
var _exit_step := 0
var _children_exited := false
var _actual_Main_final_free_event_emitted := false
var _actual_Main_loading_pins_released := false
var _pending_prefix: Dictionary = {}
var _profile_connections: Dictionary = {}

func _source_fail(code: String, details: Dictionary = {}) -> bool:
	_world.fault(code, details)
	return false

func create_original_owner_services(publication: Dictionary) -> bool:
	for method: String in ["_pump_pending_warm_textures","_update_town_music_presence","_update_world_camera_constraint","_update_stealth_alpha","_update_taoist_buff_hints"]:
		if not has_method(method): return _source_fail("MISSING_original_root_process_closure",{"method":method})
	if _source_tree != null or publication.get("root_phase",{}).get("contract_id") != "world.root.original_phase.v1": return _source_fail("root_phase_publication_missing")
	var phase: Dictionary = publication.root_phase
	for field: String in ["source_tree","feature_resource_source_key","source_scope_bindings","ready_rng","loot_preferences","loot_descriptors","loot_bucket_size_gu","initial_bootstrap_timeout_msec"]:
		if not phase.has(field): return _source_fail("root_phase_field_missing",{"field":field})
	if not phase.loot_bucket_size_gu is float or phase.loot_bucket_size_gu <= 0.0 or not phase.initial_bootstrap_timeout_msec is int or phase.initial_bootstrap_timeout_msec != 60000: return _source_fail("original_root_literal_contract_mismatch")
	var made: Dictionary = ViewServices.create_original_world_view_services(_world, publication)
	if made.get("success") != true or not made.get("services") is Dictionary or not made.get("field_bindings") is Dictionary: return _source_fail("actual_world_view_services_missing",made)
	if not made.get("interactable_loading") is Dictionary: return _source_fail("MISSING_actual_interactable_Loading_publication")
	_original_interactable_loading = made.interactable_loading
	for name: String in REQUIRED_VIEW_SERVICES:
		var port: Variant = made.services.get(name)
		if not port is RefCounted or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _world.owner_thread_id(): return _source_fail("root_required_owner_service_invalid",{"service":name})
		for method: String in REQUIRED_VIEW_SERVICES[name]:
			if not port.has_method(method): return _source_fail("root_required_owner_method_missing",{"service":name,"method":method})
	for name: String in made.services:
		if not _world.register_original_owner_service(StringName(name), made.services[name]): return false
	if not _world.register_original_owner_service(&"FrameBudget",_world.frame_budget) or not _world.register_original_owner_service(&"CombatDiagnosticLogScript",made.services.CombatLog): return false
	# Actual ports replace only original object slots. No plain flag marks ready.
	for field: StringName in made.field_bindings:
		var bound: Variant = made.field_bindings[field]
		if bound is Object and (not bound is RefCounted or bound is Resource or not bound.has_method("owner_thread_id") or bound.owner_thread_id() != _world.owner_thread_id()): return _source_fail("Main_object_in_original_root_fields",{"field":field})
		if field in [&"player",&"_rng",&"_world_skill_domain",&"_feature_target_bound",&"_ground_effect_manager"] or not _fields.bind_owner_field(field,made.field_bindings[field]): return _source_fail("root_view_field_binding_rejected",{"field":field})
	_source_tree = SourceTree.new()
	if not _source_tree.configure_owner(_world,phase.source_tree): return _source_fail("original_source_tree_publication_rejected")
	for scope_name: String in phase.source_scope_bindings:
		if scope_name == "game_root": continue
		if scope_name == "player_state": continue
		var scope: RefCounted = _world.original_source_scope(scope_name)
		if scope == null or not _source_tree.bind_existing(phase.source_scope_bindings[scope_name],scope.get_instance_id()): return _source_fail("source_scope_tree_binding_rejected",{"scope":scope_name})
	_source_publication = phase
	var preferences := LootPreferences.new(phase.loot_preferences)
	var descriptors := LootDescriptors.new(_world.owner_services.GameData,made.services.ItemDropInstanceRules,phase.loot_descriptors)
	if not _world.register_original_owner_service(&"LootPreferences",preferences) or not _world.register_original_owner_service(&"LootActorFactory",LootFactory.new(preferences,descriptors)): return false
	var coordinator := Bootstrap.new()
	if not coordinator.configure_owner(_world.profile_runtime,made.services.WorldBootstrapResources,made.services.ContentLayers,bool(_world.clock_ports.get_setting("hardcore/diagnostics/main_boot_trace",false))): return _source_fail("original_bootstrap_ports_rejected")
	if not _fields.bind_owner_field(&"_world_bootstrap_coordinator",coordinator): return _source_fail("original_bootstrap_field_missing")
	if not has_method("original_map_loading_transport") or not coordinator.bind_original_map_transport(call(&"original_map_loading_transport")): return _source_fail("actual_Source_map_transport_missing")
	return not _world.is_faulted()

func _initialize_original_world_random() -> bool:
	if not _ready_rng_witness.is_empty() or not _source_publication.ready_rng is Dictionary: return _source_fail("original_ready_rng_repeated_or_missing")
	var source: Dictionary = _source_publication.ready_rng
	if source.get("contract_id") != "world.random.original_ready.v1" or source.get("origin") not in ["Main_original_ready_rng_once","S_original_ready_randomize"]: return _source_fail("original_ready_rng_witness_schema")
	if source.origin == "Main_original_ready_rng_once":
		for key: String in ["seed","state","source_ready_invocation","before_first_consumer"]:
			if not source.has(key): return _source_fail("original_ready_rng_witness_missing",{"field":key})
		if not source.seed is int or not source.state is int or not source.source_ready_invocation is String or source.source_ready_invocation.is_empty() or source.before_first_consumer != true: return _source_fail("original_ready_rng_witness_invalid")
		if _world.random.seed != source.seed or _world.random.state != source.state: return _source_fail("original_ready_rng_adoption_mismatch")
	else:
		# Exact GameRoot._ready: y_sort_enabled=true; _rng.randomize();
		# configure_blessing_oil_rng(_rng). This is the same independent Core RNG.
		_world.random.randomize()
	if not _fields.bind_owner_field(&"_rng",_world.random): return _source_fail("original_world_rng_field_missing")
	_ready_rng_witness = {"contract_id":"world.random.original_ready.v1","origin":source.origin,"seed":_world.random.seed,"state":_world.random.state,"clock_epoch":int(_world.current_clock_frame().epoch),"before_first_consumer":true}
	_world.profile.configure_blessing_oil_rng(_world.random)
	return true

func initialize_source_domains(_publication: Dictionary) -> bool:
	if _source_initialized or _source_tree == null: return _source_fail("original_root_ready_repeated")
	var code_claim: Dictionary = required_owner_service(&"ContentLayers").claim_internal_code_world_retention(_world.current_world_identity())
	if code_claim.get("success") != true or code_claim.get("actual_original_claim") != true or not code_claim.get("result") is Dictionary: return _source_fail("actual_original_world_code_claim_missing",code_claim)
	if not _fields.bind_owner_field(&"_initial_code_retention",code_claim.result): return _source_fail("original_initial_code_retention_field_missing")
	if not _initialize_original_world_random(): return false
	# Core has already created the same spatial/ground/streaming/context owners.
	# The detached original constructor captured this late _ready slot as null.
	# Install the existing sole S coordinator where original map loading reads
	# it, before any original ready or transition callback can use that slot.
	if _world.streaming == null or _world.streaming.owner_thread_id() != _world.owner_thread_id() or not _world.streaming.is_healthy() or not _fields.bind_owner_field(&"_streaming_coordinator",_world.streaming): return _source_fail("actual_original_root_streaming_owner_binding")
	_reset_attack_action_lifecycle(&"game_root_ready")
	# Original add_child(background) precedes player creation in GameRoot._ready.
	# Constructor publication did not claim this Source tree entry in advance.
	var background_scope: RefCounted = _world.original_source_scope("background")
	if background_scope == null or background_scope.inside_world: return _source_fail("original_background_child_boundary_repeated")
	background_scope.parent_scope_id = _world.parent_scope_id()
	background_scope.inside_world = true
	var background_callbacks: Dictionary = {}
	for row: Dictionary in _source_publication.source_tree.rows:
		if row.source_key == _source_publication.source_scope_bindings.background: background_callbacks = row.callbacks
	if not background_scope.apply_original_implicit_ready(background_callbacks): return _source_fail("original_background_implicit_READY_rejected")
	var player_source: Dictionary = original_actor_birth_publication(&"player")
	if player_source.is_empty(): return false
	var player: Object = _world.create_player_at_original_child_boundary(player_source)
	if player == null: return false
	_register_passive_wake_emitter(player)
	for signal_name: String in ["relic_proc_started","levels_gained","skills_changed","equipment_changed"]:
		if not _connect_original_profile_signal(signal_name): return false
	var manager := LootManager.new(_world,required_owner_service(&"LootPreferences"),_source_publication.loot_bucket_size_gu)
	manager.configure_player(_world.actor_access.view(_world.actor_handle_for_model(player)))
	manager.collection_path_is_clear = Callable(self,"_loot_collection_path_is_clear")
	if not _world.attach_original_process_service(&"loot_runtime_manager",manager,&"_process",&"_process") or not manager.initialize_gameplay() or not _fields.bind_owner_field(&"_loot_pickup_runtime_manager",manager): return _source_fail("original_loot_manager_child_rejected")
	_world.profile.configure_taoist_main_pets_persistence_provider(Callable(self,"_capture_taoist_main_pet_runtime_states"))
	player.restore_warrior_runtime_state(_world.profile.warrior_runtime_state_for_restore())
	# This real Source birth publication is applied by Main before the following
	# cold ready query. It does not turn pre-map life zero into a combat ActorRef.
	if not _world.publish_original_actor_visual_projection(_world.runtime_actor_id_for_model(player),false,0.0): return false
	var views: RefCounted = required_owner_service(&"WorldViewLifecycle")
	var actual_ready: Dictionary = views.configure_original_ready_views(_world.current_world_identity(),_world.runtime_actor_id_for_model(player))
	if actual_ready.get("success") != true or actual_ready.get("actual_source_ready") != true: return _source_fail("actual_original_world_ready_views_missing",actual_ready)
	_wire_item_quick_slots_hud()
	if not _world.connect_original_actor_signal(player,&"resources_changed",Callable(self,"_on_resources_changed_for_hud")): return _source_fail("original_resource_hud_subscription_rejected")
	_sync_player_runtime_snapshot_to_hud()
	var root_order: Dictionary = _source_tree.callback_order(_world.parent_scope_id(),&"_physics_process")
	if root_order.get("ok") != true or not _world.register_original_callback(self,_world.original_source_scope("game_root"),&"H",&"_physics_process",_world.original_source_scope("game_root").physics_priority,root_order.order,root_order.entry): return _source_fail("original_root_H_callback_rejected",root_order)
	root_order = _source_tree.callback_order(_world.parent_scope_id(),&"_process")
	if root_order.get("ok") != true or not _world.register_original_callback(self,_world.original_source_scope("game_root"),&"P",&"_process",_world.original_source_scope("game_root").process_priority,root_order.order,root_order.entry): return _source_fail("original_root_P_callback_rejected",root_order)
	_source_initialized = true
	_begin_initial_world_bootstrap()
	return not _world.is_faulted()

func _begin_initial_world_bootstrap() -> void:
	if _world_bootstrap_in_progress: return
	_world_bootstrap_in_progress = true
	_acquire_gameplay_input_lock(&"initial_world_bootstrap")
	var target_map_id: int = current_map_id if current_map_id >= 0 else _world.owner_services.GameData.service_home_runtime_map_id(false)
	_world_bootstrap_coordinator.begin_initial_world(target_map_id)
	_world_bootstrap_coordinator.advance(Bootstrap.Stage.SHOW_LOADING)
	if not _world.profile.test_mode and source_hud_is_present(): hud.begin_loading_transition("world:bootstrap:initial")
	# The actual original process_frame is emitted by Core at P_GROUP start,
	# including paused P. No substitute timer or H yield.
	await _world.profile_runtime.next_service()
	_world_bootstrap_coordinator.loading_barrier_completed()
	var pipeline: RefCounted = required_owner_service(&"WorldBootstrapPipeline")
	var accepted: bool = pipeline.travel_to_service_home(false,true,"")
	if not accepted:
		_world_bootstrap_coordinator.finish(false,"initial_travel_rejected")
		_world_bootstrap_in_progress = false
		return
	var deadline: int = _world.clock_ports.get_ticks_msec() + _source_publication.initial_bootstrap_timeout_msec
	while (_map_transition_in_progress or _world_bootstrap_coordinator.stage not in [Bootstrap.Stage.READY,Bootstrap.Stage.FAILED]) and _world.clock_ports.get_ticks_msec() < deadline:
		await _world.profile_runtime.next_service()
	if _map_transition_in_progress or _world_bootstrap_coordinator.stage not in [Bootstrap.Stage.READY,Bootstrap.Stage.FAILED]:
		_world_bootstrap_coordinator.revoke_current_generation()
		_fields.write_source_field(&"_active_map_transition_id","")
		_map_transition_in_progress = false
		_world_bootstrap_coordinator.finish(false,"initial_bootstrap_timeout")
		_world_bootstrap_in_progress = false
		return
	if _world_bootstrap_coordinator.stage == Bootstrap.Stage.FAILED:
		_world_bootstrap_in_progress = false
		return
	_record_player_world_location()
	pipeline.set_loading_window_active(false)
	_on_player_stats_changed(_world.skills.player.current_hp,_world.skills.player.max_hp)
	_world_bootstrap_in_progress = false
	_release_gameplay_input_lock(&"initial_world_bootstrap")

func original_actor_birth_publication(kind: StringName, template_key: StringName = &"") -> Dictionary:
	var value: Dictionary = _source_tree.reserve_actor_birth(kind,_world.parent_scope_id(),template_key)
	if value.is_empty(): _source_fail("original_actor_birth_template_missing",{"kind":kind,"template_key":template_key})
	return value

func original_actor_child_entered(id: int, source: Dictionary) -> bool:
	return _source_tree.enter_actor(id,source) or _source_fail("original_actor_child_order_rejected",{"id":id})

func original_player_pre_ready_connections(model: Object) -> bool:
	# Source _ready connects these before add_child(player)/Player._ready.
	for record: Dictionary in [
		{"signal":&"attack_requested","receiver":_world.skills,"method":&"_on_player_attack"},
		{"signal":&"skill_requested","receiver":_world.skills,"method":&"_on_player_skill"},
		{"signal":&"skill_cast_started","receiver":self,"method":&"_on_skill_cast_audio_started"},
		{"signal":&"skill_cast_started","receiver":self,"method":&"_on_first_fire_wall_cast_probe"},
		{"signal":&"warrior_skill_state_changed","receiver":self,"method":&"_on_warrior_skill_state_changed"},
		{"signal":&"stats_changed","receiver":self,"method":&"_on_player_stats_changed"},
		{"signal":&"movement_performed","receiver":self,"method":&"_on_player_moved"},
		{"signal":&"death_requested","receiver":self,"method":&"_on_player_death_requested"}]:
		if not _world.connect_original_actor_signal(model,record.signal,Callable(record.receiver,record.method)): return _source_fail("original_player_source_subscription_rejected",{"signal":record.signal,"method":record.method})
	for signal_name: String in ["consumable_requested","background_item_save_failed","scroll_requested","item_audio_committed","temporary_item_buff_expired"]:
		if not _connect_original_profile_signal(signal_name): return false
	return _world.connect_original_actor_signal(model,&"potion_buff_expired",Callable(self,"_on_player_potion_buff_expired"))

func _connect_original_profile_signal(signal_name: String) -> bool:
	if _profile_connections.has(signal_name) or not _world.profile.has_signal(signal_name): return _source_fail("original_profile_signal_missing_or_duplicate",{"signal":signal_name})
	var callback := Callable(self,PROFILE_SIGNAL_METHODS[signal_name])
	if _world.profile.connect(signal_name,callback) != OK: return _source_fail("original_profile_subscription_rejected",{"signal":signal_name})
	_profile_connections[signal_name] = callback
	return true

func _on_resources_changed_for_hud(_hp: int, _max_hp: int, _mp: int, _max_mp: int) -> void:
	_sync_player_runtime_snapshot_to_hud()

func original_service_child_entered(id: int, parent_id: int) -> bool:
	var handle: Object = _world.service_registry.resolve_service(id)
	if handle == null: return false
	return _source_tree.enter_service(id,handle.kind(),parent_id) or _source_fail("original_service_tree_parent_missing",{"id":id,"kind":handle.kind(),"parent_scope_id":parent_id})

func original_service_callback_order(id: int, method: StringName) -> Dictionary:
	var session_order: Dictionary = _world.original_source_session().original_persistent_callback_order(id,method)
	if session_order.get("matched") == true: return session_order
	var persistent: Dictionary = _persistent_path_source_order(id,method)
	if persistent.get("matched") == true: return persistent
	var service: Object = _world.service_registry.resolve_service(id)
	if service == null: return {"ok":false,"reason":"canonical_source_service_missing","id":id}
	var scope: RefCounted = service.source_scope()
	if not _source_tree.enter_service(id,service.kind(),scope.parent_scope_id): return {"ok":false,"reason":"original_service_tree_birth_missing","id":id}
	return _absolute_original_root_callback_order(id,method)

func _persistent_path_source_order(id: int, method: StringName) -> Dictionary:
	if method != &"original_physics_pump": return {"matched":false}
	var session: RefCounted = _world.original_source_session()
	if not session.has_method("original_path_session") or not session.has_method("original_source_tree_service"): return {"matched":false}
	var slot: RefCounted = session.original_path_session()
	if slot == null or not slot.has_method("original_service_handle_id") or slot.owner_thread_id() != _world.owner_thread_id() or slot.original_service_handle_id() != id: return {"matched":false}
	var tree: RefCounted = session.original_source_tree_service()
	if tree == null or not tree.has_method("original_source_tree_callback_order") or tree.owner_thread_id() != _world.owner_thread_id(): return {"matched":true,"ok":false,"reason":"actual_persistent_path_source_tree_missing"}
	var order: Dictionary = tree.original_source_tree_callback_order(id,method)
	if order.get("ok") != true or not order.get("order") is int or order.order < 0 or not order.get("entry") is String or order.entry.is_empty(): return {"matched":true,"ok":false,"reason":"actual_persistent_path_source_order_rejected"}
	order = order.duplicate(false)
	order.matched = true
	order.domain = "H"
	return order

func current_original_callback_order(target: RefCounted, scope: Object, method: StringName) -> Dictionary:
	var persistent: Dictionary = _world.original_source_session().original_persistent_callback_order(target.get_instance_id(),method)
	if persistent.get("matched") == true: return persistent
	var id: int = _world.original_callback_runtime_id(target)
	if id == 0:
		id = _world.parent_scope_id() if target == self else target.get_instance_id()
	# scope is still the original qualification object; no cached flags here.
	if scope == null: return {"ok":false,"reason":"source_callback_scope_missing"}
	return _absolute_original_root_callback_order(id,method)

func original_children_reverse_order(id: int) -> Array[int]: return _source_tree.children_in_original_reverse_order(id)
func original_owned_root_actor_models() -> Array[Object]:
	var result: Array[Object] = []
	var ids: Array[int] = _source_tree.children_in_original_reverse_order(_world.parent_scope_id())
	ids.reverse()
	for id: int in ids:
		var handle: Object = _world.registry.resolve_runtime_actor(id)
		if handle != null: result.append(handle.model())
	return result
func original_root_is_ancestor_of_actor(model: Object) -> bool:
	var handle: Object = _world.actor_handle_for_model(model)
	return handle != null and _source_tree.is_original_ancestor(_world.parent_scope_id(),handle.get_instance_id())
func original_source_final_free(id: int) -> bool: return _source_tree.detach_at_original_final_free(id)

func accept_original_input(domain: String, packet: Dictionary) -> bool:
	if domain not in ["H_INPUT","P_INPUT"] or not _world.input.accept(packet): return _source_fail("original_input_publication_rejected",{"domain":domain})
	if not packet.get("original_events") is Array: return _source_fail("original_input_event_manifest_missing")
	for event: Variant in packet.original_events:
		if not event is Dictionary or not event.get("kind") is String or not event.get("arguments") is Array: return _source_fail("original_input_event_schema")
		var args: Array = event.arguments
		match event.kind:
			"gameplay_movement":
				if args.size() != 1 or not args[0] is Vector2 or not args[0].is_finite(): return _source_fail("original_movement_input_schema")
				if _world.gameplay_input_is_enabled(): _world.skills.player.set_touch_vector(args[0])
			"mobile_attack_started", "mobile_attack_ended", "mobile_attack_cancelled":
				var expected: int = 4 if event.kind == "mobile_attack_cancelled" else 3
				if args.size() != expected or not args[0] is int or not args[1] is int or not (args[2] is String or args[2] is StringName): return _source_fail("original_attack_input_schema")
				if expected == 4 and not (args[3] is String or args[3] is StringName): return _source_fail("original_attack_cancel_reason_schema")
				_world.skills.callv({"mobile_attack_started":"_on_mobile_attack_input_started","mobile_attack_ended":"_on_mobile_attack_input_ended","mobile_attack_cancelled":"_on_mobile_attack_input_cancelled"}[event.kind],args)
			"skill_input_started", "skill_input_ended", "skill_input_cancelled":
				var expected: int = 6 if event.kind == "skill_input_cancelled" else 5
				if args.size() != expected or not args[0] is String or not args[1] is int or not args[2] is int or not args[3] is int or not (args[4] is String or args[4] is StringName): return _source_fail("original_skill_input_schema")
				if expected == 6 and not (args[5] is String or args[5] is StringName): return _source_fail("original_skill_cancel_reason_schema")
				_world.skills.callv({"skill_input_started":"_on_skill_input_started","skill_input_ended":"_on_skill_input_ended","skill_input_cancelled":"_on_skill_input_cancelled"}[event.kind],args)
			"viewport_pick_press":
				if args.size()!=1 or not args[0] is Dictionary or not _world.input.retain_original_pick_press(args[0],packet): return _source_fail("original_pick_press_schema_or_configuration")
			"unhandled_ui_cancel":
				if not args.is_empty(): return _source_fail("original_ui_cancel_schema")
				var handled: Variant = event.get("view_context",{}).get("actual_Main_ui_cancel")
				if not handled is Dictionary or handled.get("contract_id") != "hardcore.input.actual_Main_ui_cancel.v1" or handled.get("world_context") != packet.get("world_context") or not handled.get("view_sequence") is int or handled.view_sequence <= 0 or handled.get("actual_root_id") != packet.get("world_context",{}).get("world_runtime_id"): return _source_fail("actual_original_Main_ui_cancel_receipt_required")
				_toggle_system_menu()
				if not _world.emit_original_main_event(&"set_input_as_handled",[handled]): return false
			"notification":
				if args.size() != 1 or not args[0] is int: return _source_fail("original_notification_schema")
				if not _original_notification(args[0]): return false
			"item_quick_slot_assignment_requested", "item_quick_slot_use_requested":
				if args.size() != 2 or not args[0] is int or not args[1] is String: return _source_fail("original_item_slot_input_schema")
				if event.kind == "item_quick_slot_assignment_requested": _on_item_quick_slot_assignment_requested(args[0],args[1])
				else: _on_item_quick_slot_use_requested(args[0],args[1])
			_:
				if required_owner_service(&"WorldUiCommandOwner").dispatch_original_hud_event(event) != true: return _source_fail("original_hud_event_missing",event)
		if _world.is_faulted(): return false
	return true

func _original_notification(what: int) -> bool:
	match what:
		Node.NOTIFICATION_WM_GO_BACK_REQUEST: Callable(self,"_toggle_system_menu").call_deferred()
		Node.NOTIFICATION_APPLICATION_PAUSED, Node.NOTIFICATION_APPLICATION_FOCUS_OUT:
			_world.diagnostics.reset_wall_frame_interval()
			_cancel_player_input_boundary(&"application_interrupted")
		Node.NOTIFICATION_APPLICATION_RESUMED: _world.diagnostics.reset_wall_frame_interval()
		Node.NOTIFICATION_WM_CLOSE_REQUEST:
			_cancel_all_mobile_attack_inputs(true)
			_cancel_all_skill_inputs(true)
			var result: Dictionary = _prepare_safe_logout()
			if result.get("success") != true:
				_handle_safe_logout_failure(&"wm_close_request",result)
				return not _world.is_faulted()
			return _world.emit_original_main_event(&"original_tree_quit",[])
	return not _world.is_faulted()

func original_physics_frame_signal() -> bool:
	original_physics_frame.emit()
	# SceneTree: physics_frame signal -> viewport picking -> physics group.
	# H_INPUT precedes the real Native sync and cannot perform this query.
	return not _world.is_faulted() and _world.input.process_original_viewport_picking()

func original_h_after_timers() -> bool: return _original_after_timers(&"H")
func original_p_after_timers() -> bool: return _original_after_timers(&"P")
func _original_after_timers(domain: StringName) -> bool:
	if not _world.flush_original_delete_queue_at_checkpoint(domain): return false
	var receipt: Dictionary = required_owner_service(&"WorldSourceCheckpoint").original_idle_callbacks(domain,_world.current_clock_frame())
	return receipt.get("success") == true and receipt.get("actual_original_checkpoint") == true or _source_fail("actual_original_idle_checkpoint_missing",receipt)

func original_control_phase(phase: StringName, frame: Dictionary) -> bool:
	if phase not in [&"U_BEGIN",&"U_END",&"U_WAKE"] or frame != _world.current_clock_frame(): return _source_fail("original_control_clock_mismatch")
	var receipt: Dictionary = required_owner_service(&"WorldSourceCheckpoint").original_control_boundary(phase,frame)
	return receipt.get("success") == true and receipt.get("actual_original_checkpoint") == true or _source_fail("actual_original_control_checkpoint_missing",receipt)

func publish_original_presentation() -> bool:
	# Even when an earlier intention met FIFO pressure, freeze from the current
	# sole journal after actual ACK consumption. Never retry its stale events.
	var prefix: Dictionary = _world.take_original_presentation_prefix()
	if prefix.is_empty(): return false
	return publish_original_close_prefix(prefix)

func publish_original_close_prefix(prefix: Dictionary) -> bool:
	if prefix.size() != 4 or not prefix.has_all(["bridge_generation","journal_generation","through_ordinal","events"]): return _source_fail("original_prefix_schema")
	if not _pending_prefix.is_empty() and (prefix.bridge_generation != _pending_prefix.bridge_generation or prefix.journal_generation != _pending_prefix.journal_generation): return _source_fail("original_pending_prefix_producer_changed")
	# This one bounded row is an unaccepted Source intention, not a Native
	# publication or ACK. Event storage remains exclusively in the journal.
	var admitted: Dictionary = required_owner_service(&"WorldViewLifecycle").publish_original_prefix(prefix)
	match admitted.get("status"):
		"READY":
			_pending_prefix = {}
			return true
		"PENDING":
			_pending_prefix = {"bridge_generation":prefix.bridge_generation,"journal_generation":prefix.journal_generation,"through_ordinal":prefix.through_ordinal}
			# The current Source callback retained its work. World/Map/close
			# completion still requires real effects and the original Native ACK.
			return true
		_: return _source_fail("original_prefix_publication_rejected",admitted)

func source_hud_is_present() -> bool:
	return hud != null and hud.has_method("is_original_view_present") and hud.is_original_view_present()

func _refresh_target_highlights() -> void:
	var active: Object = _world.skills._active_display_target()
	var next_id: int = _world.skill_actors.runtime_actor_id(active)
	var previous_link: Variant = _fields.read_source_field(&"_presented_target_ref")
	var previous: Object = previous_link.borrow_model() if previous_link != null else null
	if next_id == int(_fields.read_source_field(&"_presented_target_instance_id")) and previous == active: return
	if previous != null and previous != active: previous.set_targeted(false)
	if _world.skill_actors.is_runtime_present(active): active.set_targeted(true)
	if previous_link != null: previous_link.dispose()
	_fields.write_source_field(&"_presented_target_instance_id",next_id)
	_fields.write_source_field(&"_presented_target_ref",_world.skill_actors.capture(active) if _world.skill_actors.is_runtime_present(active) else null)

func _update_target_hud() -> void:
	if not source_hud_is_present(): return
	var magic: bool = _world.skills._magic_target_domain_is_active()
	var target: Object = magic_locked_target if magic else locked_target
	var valid := false
	if _world.skill_actors.is_runtime_present(target) and _world.skill_actors.is_kind(target,&"enemy"):
		valid = _world.skills._is_magic_target_in_range(target) if magic else _world.skills._is_attack_target_in_range(target)
	var auto: bool = _fields.read_source_field(&"auto_target_enabled")
	if valid: hud.update_target(target.display_name,target.current_hp,target.max_hp,manual_magic_target_lock if magic else manual_target_lock,auto,target.monster_id)
	else: hud.update_target("",0,0,false,auto)

func capture_follow_landing_authority(summon: Object) -> RefCounted:
	if not _world.skills._main_pet_follow_context_is_current(summon): return null
	return FollowAuthority.capture(_world,summon,current_map_id,_zone_generation)

func register_pending_main_pet_arrival(summon: Object, authority: RefCounted) -> bool:
	if authority == null or authority.get_script() != FollowAuthority or not authority.matches_current(_world,summon,current_map_id,_zone_generation): return false
	return _world.skills._register_pending_main_pet_arrival(summon)

func exit_generic_actor_at_original_checkpoint(instance: RefCounted) -> bool:
	if instance == null or instance.handle == null: return false
	return _world.exit_generic_actor_scope_at_original_checkpoint(instance)

func close_loot_at_original_free(model: Object) -> bool:
	if model == null or not model.has_method("close_effect") or not model.belongs_to_world(_world): return _source_fail("original_loot_exit_model_invalid")
	model.close_effect()
	return true

func close_faulted_owner_world() -> bool:
	var checkpoint: RefCounted = required_owner_service(&"WorldSourceCheckpoint")
	if checkpoint == null: return false
	var proof: Dictionary = checkpoint.original_fault_exit_admission(_world.current_world_identity())
	if not _actual_exit_proof(proof): return false
	return close_at_original_world_exit()

func _actual_exit_proof(proof: Dictionary) -> bool:
	return proof.get("success") == true and proof.get("world") == _world.current_world_identity() and proof.get("source_callbacks_closed") == true and proof.get("actual_io_owners_retained") == true and proof.get("actual_checkpoint") is Dictionary

func close_at_original_world_exit() -> bool:
	# Node::_propagate_exit_tree: reverse children _exit_tree, then Root._exit_tree;
	# final free is a separate checkpoint and accepted leases can retain storage.
	_world.trace_actual_source_close("Root_before_children")
	if not _children_exited:
		var proof: Dictionary = required_owner_service(&"WorldSourceCheckpoint").original_world_exit_admission(_world.current_world_identity())
		if not _actual_exit_proof(proof): return false
		if not _world.exit_original_world_children_at_checkpoint(): return false
		_children_exited = true
	_world.trace_actual_source_close("Root_after_children")
	while _exit_step < 17:
		_world.trace_actual_source_close("Root_step:"+str(_exit_step))
		match _exit_step:
			0: if not required_owner_service(&"SourceFrames").retire_pending_threaded_claims(): return false
			1: if not _world.streaming.retire_threaded_resource_claims(): return false
			2: if not _world_bootstrap_coordinator.retire_threaded_resource_claims(): return false
			3:
				if not required_owner_service(&"ContentLayers").retire_internal_code_result(_fields.read_source_field(&"_initial_code_retention")): return false
			4:
				var retiring: Array = _respawn_wakeups.values()
				_respawn_wakeups.clear()
				for wakeup: RefCounted in retiring: wakeup.time_left = 0.0
			5: if not required_owner_service(&"WorldBootstrapPipeline").retire_pending_warm_textures(): return false
			6: if not required_owner_service(&"WorldBootstrapPipeline").retire_loading_texture_claims(): return false
			7: if _world.feature.runtime != null: _world.feature.runtime.clear()
			8:
				_poll_prepared_enemy_death_settlement(true)
				if not _prepared_enemy_death_settlement.is_empty(): return false
				_world.frame_budget.mark_pending(_death_budget_category,false)
			9:
				_disconnect_profile_signal("skills_changed")
				_disconnect_profile_signal("equipment_changed")
			10:
				if not _prepared_loot_collection.is_empty():
					if _prepared_loot_collection.plan.writer.cancel(): _prepared_loot_collection.plan.writer.result(true)
					else: _world.profile.finish_prepared_loot_save(_prepared_loot_collection.plan,true)
					_prepared_loot_collection.clear()
			11: if _audio_runtime_service != null: _audio_runtime_service.stop_all_audio("world_exited")
			12:
				_disconnect_profile_signal("levels_gained")
				_disconnect_profile_signal("item_audio_committed")
			13:
				var town: Variant = _fields.read_source_field(&"_town_music_controller")
				if town != null: town.cancel("world_exited")
			14: _world.profile.clear_taoist_main_pets_persistence_provider()
			15:
				# Persistent Profile keeps its writer; only this world unsubscribes.
				for signal_name: String in _profile_connections.keys(): _disconnect_profile_signal(signal_name)
				if _world.profile.quick_item_slots_changed.is_connected(_sync_item_quick_slots_to_hud): _world.profile.quick_item_slots_changed.disconnect(_sync_item_quick_slots_to_hud)
				if _loot_pickup_runtime_manager != null: _loot_pickup_runtime_manager.close()
				var link: Variant = _fields.read_source_field(&"_presented_target_ref")
				if link != null:
					link.dispose()
					_fields.write_source_field(&"_presented_target_ref",null)
			16:
				var view_exit: Dictionary = required_owner_service(&"WorldViewLifecycle").actual_world_view_exit(_world.current_world_identity())
				if view_exit.get("success") != true or view_exit.get("actual_original_exit") != true:
					_world.trace_actual_source_close("Root_view_exit:"+str(view_exit.get("status","MISSING"))+":"+str(view_exit.get("error",""))+":"+str(_world.current_clock_frame().get("phase","")))
					return false
		_exit_step += 1
	if not _world.final_free_original_world_children_at_checkpoint(): return false
	var session: RefCounted = _world.original_source_session()
	if not _actual_Main_final_free_event_emitted:
		var fact := {"contract_id":"hardcore.source.Root_final_free.v1",
			"owner_session_id":session.original_budget_session_id(),"closure_id":session.original_budget_session_id(),
			"world_context":_world.current_world_identity(),"source_root_id":get_instance_id(),
			"exit_step":_exit_step,"children_exited":_children_exited,"children_final_freed":true}
		if not _world.emit_original_main_event(&"original_source_root_final_free",[fact]): return false
		_actual_Main_final_free_event_emitted = true
	if not _actual_Main_loading_pins_released:
		if not session.release_loading_pins(session.original_budget_session_id()): return false
		_actual_Main_loading_pins_released = true
	return session.release_original_application_world_references(_world,self)

func _disconnect_profile_signal(signal_name: String) -> void:
	if not _profile_connections.has(signal_name): return
	var callback: Callable = _profile_connections[signal_name]
	if _world.profile.is_connected(signal_name,callback): _world.profile.disconnect(signal_name,callback)
	_profile_connections.erase(signal_name)

var _original_interactable_loading: Dictionary
func original_interactable_loading_publication() -> Dictionary: return _original_interactable_loading

func _absolute_original_root_callback_order(id: int,method: StringName) -> Dictionary:
	var local: Dictionary=_source_tree.callback_order(id,method)
	if local.get("ok")!=true: return local
	var tree: RefCounted=_world.original_source_session().original_source_tree_service()
	if tree==null: return {"ok":false,"reason":"actual_persistent_Source_tree_missing"}
	var absolute: Dictionary=tree.original_source_tree_root_ordinal(_world.registry.capture_world())
	if absolute.get("ok")!=true or not absolute.get("source_path") is Array: return {"ok":false,"reason":"actual_global_root_source_path_missing"}
	local=local.duplicate(false);local.source_path=absolute.source_path.duplicate();local.source_path.append(local.order)
	return local
