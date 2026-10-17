extends RefCounted
## Main boot composition. This object owns only Main references and receipts;
## it cannot create profile/HP/RNG gameplay owners or authorize missing S facts.
const Loading := preload("res://scripts/gameplay/source/main_boot_launch_loading.gd")
const RootTransport := preload("res://scripts/gameplay/source/main_boot_root_transport.gd")
const Transport := preload("res://scripts/gameplay/source/main_session_transport.gd")
const Observe := preload("res://scripts/gameplay/source/main_boot_source_observations.gd")
const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const Canonical := preload("res://scripts/gameplay/profile/profile_publication.gd")
const Catalog := preload("res://scripts/gameplay/content/catalog_publication_gate.gd")
const Feature := preload("res://scripts/features/runtime/feature_resource_main_primitives.gd")
const Caster := preload("res://scripts/gameplay/world/world_caster_main_executor.gd")
const ProfileReadView := preload("res://scripts/gameplay/world/world_profile_ui_view.gd")
const BirthTemplates := preload("res://scripts/gameplay/source/main_original_actor_birth_templates.gd")
const LootPreferencesCapture := preload("res://scripts/gameplay/world/world_loot_preferences.gd")
const LootDescriptorsCapture := preload("res://scripts/gameplay/world/world_loot_descriptors.gd")
const ContentGraph := preload("res://scripts/gameplay/content/content_value_graph.gd")
const CombatRules := preload("res://scripts/combat_resolution_rules.gd")
const DamageObserver := preload("res://scripts/damage_ledger_observer.gd")
const ENTRY_META := &"hardcore_original_main_boot_application"
const POLICY_KEYS: Array[String] = ["bridge_generation","primitive_request_capacity","primitive_result_capacity","max_epochs_per_turn","timer_capacity","input_capacity","event_capacity","live_primitive_capacity"]
var _host: Object
var _facade: Node
var _content: Node
var _services: Dictionary
var _sealed_profile_publication: Dictionary
var _policy: Dictionary
var _loading: RefCounted
var _main_failure: RefCounted
var _root_transport: RefCounted
var _transport: RefCounted
var _assembly: Dictionary
var _last_launch: Dictionary
var _launch_active := false
var _content_publication: Dictionary
var _environment_boot: Dictionary
var _world_birth_inputs: Dictionary
var _launch_identity_owner: Object
var _launch_identity_receipt: Dictionary
var _session_front: Dictionary
var _profile_read_view: RefCounted
var _session_loading_site: Dictionary
var _world_bootstrap_site: Dictionary
var _world_views: RefCounted
var _world_views_publication: Dictionary
var _world_loading_pin_closure: Dictionary
var _world_assembly_result: Dictionary
var _main_composition: RefCounted
var _composition_result: Dictionary
var _actual_source_root_exit: Dictionary
var _actual_loading_release: Dictionary
var _actual_caster_pins_released := false
var _actual_terminal_exit: Dictionary
var _terminal_transition_active := false
var _terminal_transition_fault: Dictionary

func owner_thread_id() -> int: return OS.get_main_thread_id()

static func validate_actual_host_policy(policy: Dictionary) -> Dictionary:
	var missing: Array[String] = []
	for key: String in POLICY_KEYS:
		if not policy.get(key) is int or policy[key] <= 0: missing.append(key)
	if not missing.is_empty(): return _blocked("explicit_original_Host_policy_required",{"fields":missing})
	if policy.live_primitive_capacity > policy.event_capacity: return _blocked("original_Host_live_capacity_exceeds_event_capacity")
	return {"success":true, "policy":policy.duplicate(true)}

static func actual_feature_reservation_policy() -> Dictionary:
	# An explicit no-prediction policy. Real Main elapsed/CPU cost is charged
	# once by the shared Session ledger; zero never grants exhausted background
	# admission. The original RPC and Warm entrances enforce that separately.
	var policy: Dictionary = {}
	for operation: String in Feature.OPCODE_ARITY:
		if not operation.begins_with("source_admission_"): policy[operation] = 0
	for operation: String in Feature.LIVE_JOB_ARITY: policy[operation] = 0
	return policy

static func actual_streaming_reservation_policy() -> Dictionary:
	# Same explicit no-prediction policy as Feature. Source reservations still
	# respect the original shared background ledger; actual Main cost is settled
	# exactly once. No synchronous LIVE resource call is admitted by this policy.
	var policy: Dictionary = {}
	for operation: StringName in preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd").LIVE_OPERATIONS:
		policy[String(operation)] = 0
	return policy

func configure_main(host: Object, facade: Node, services: Dictionary, explicit_policy: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host != null or host == null or not host.is_class("HardCoreSimulationHost"): return _blocked("actual_Main_once_Host_required")
	if not is_instance_valid(facade) or not facade.is_inside_tree() or facade != facade.get_tree().root.get_node_or_null("PlayerState"): return _blocked("actual_Main_PlayerState_required")
	var policy: Dictionary = validate_actual_host_policy(explicit_policy)
	if policy.get("success") != true: return policy
	# Reuse the configured real executors. A same-script blank object is not an
	# actual publication vault, and cannot become one by passing an ABI check.
	var feature: Variant = services.get("feature_main")
	var caster: Variant = services.get("caster_executor")
	if not feature is RefCounted or feature.get_script() != Feature or feature.get("_generation") != explicit_policy.bridge_generation or feature.get("_facade") == null: return _blocked("actual_configured_Feature_Main_vault_required")
	if not caster is RefCounted or caster.get_script() != Caster: return _blocked("actual_original_Caster_executor_required")
	if not services.get("canonical_prepared") is Dictionary or services.canonical_prepared.get("success") != true or not services.get("catalog_lease") is Dictionary or not Catalog.is_active(services.catalog_lease): return _blocked("actual_canonical_Profile_and_catalog_publication_required")
	if not services.get("feature_publication") is Dictionary: return _blocked("actual_Feature_resource_publication_required")
	var feature_configuration: Dictionary = ContentLayers.feature_configuration()
	var publication: Dictionary = services.feature_publication
	if not publication.is_empty():
		var registered: Dictionary = feature.get("_publications")
		var id: Variant = publication.get("publication_id")
		if not id is int or not registered.has(id) or registered[id].publication != publication or not registered[id].lease is WeakRef or not is_same(registered[id].lease.get_ref(),feature_configuration.get("resource_lease")): return _blocked("actual_same_physical_Feature_publication_required")
	var sealed: Dictionary = Canonical.seal(services.canonical_prepared,services.catalog_lease,publication)
	if sealed.is_empty(): return _blocked("actual_loaded_Profile_publication_not_sealable")
	_host = host; _facade = facade; _content = facade.get_tree().root.get_node_or_null("ContentLayers")
	_services = services.duplicate(false); _policy = policy.policy
	_sealed_profile_publication = sealed
	_transport = Transport.new()
	_loading = Loading.new()
	if not _loading.configure_main(facade.get_tree(),facade,_content): return _blocked("actual_Main_launch_Loading_configuration")
	_root_transport = RootTransport.new()
	if not _root_transport.configure_main(host,_loading,_transport): return _blocked("actual_Main_root_transport_configuration")
	_main_failure = preload("res://scripts/gameplay/source/main_source_failure.gd").new()
	if not _main_failure.configure_main(host): return _blocked("actual_Native_Main_source_fault_owner_required")
	# Observe the existing process-frame boundary, before Node callbacks. Root
	# removal must not run on the transport listener's own _process stack.
	if not facade.get_tree().process_frame.is_connected(_service_actual_terminal_transition):
		facade.get_tree().process_frame.connect(_service_actual_terminal_transition)
	return {"success":true}

func actual_original_sealed_profile_publication() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _sealed_profile_publication.is_empty() or not _sealed_profile_publication.is_read_only(): return {}
	if not Catalog.is_active(_services.catalog_lease) or _sealed_profile_publication.catalog_lease != _services.catalog_lease: return {}
	if _sealed_profile_publication.database_revision != GameData.database_revision or _sealed_profile_publication.configuration_revision != _content.configuration_revision: return {}
	if _sealed_profile_publication.features.resource_publication != _services.feature_publication: return {}
	# The same actual Main seal remains immutable under this catalogue lease.
	# Native still creates the independent Source-owned bootstrap graph.
	return _sealed_profile_publication

func actual_producers() -> Dictionary:
	assert(OS.get_thread_caller_id() == OS.get_main_thread_id() and _host != null)
	return {"launch_loading":_loading, "root_transport":_root_transport,"main_failure":_main_failure,
		"world_identity":self, "world_assembly":self, "session_fields":self,
		"physical_pin_closure":self, "host_policy":self,
		"feature_main":_services.feature_main, "caster_executor":_services.caster_executor,
		"canonical_prepared":_services.canonical_prepared, "catalog_lease":_services.catalog_lease,
		"feature_publication":_services.feature_publication}

func retain_actual_factory_assembly(assembly: Dictionary) -> bool:
	if _host == null or not _assembly.is_empty() or assembly.get("success") != true: return false
	_assembly = assembly
	return true

func compose_actual_original_main_channels() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _assembly.is_empty() or _main_composition != null: return _blocked("actual_once_Main_factory_composition_required")
	_main_composition = preload("res://scripts/gameplay/source/main_boot_main_composition.gd").new()
	_composition_result = _main_composition.prepare_actual_main_channels(self,_assembly)
	return _composition_result

func apply_original_main_journal_event(event: Dictionary) -> Dictionary:
	# The sole Native prefix cursor authenticates this event. A dictionary
	# passed directly to this method cannot authorize Source retirement.
	if event.get("kind") == "original_world_presentation" and event.get("operation") == &"original_source_root_final_free":
		return _record_actual_source_root_final_free(event)
	return {"status":"INVALID","error":"unhandled_original_Main_journal_event","kind":event.get("kind"),"operation":event.get("operation"),"ordinal":event.get("ordinal")}

static func accepts_original_source_root_final_free_fact(fact: Dictionary, session_id: int, closure_id: int, world: Dictionary) -> bool:
	# A Source RefCounted ObjectID is a nonzero signed witness (commonly negative).
	# It is not a canonical Main Node ID and is never resolved/accessed on Main.
	# Schema acceptance grants no authority; the real Native cursor/site and
	# independent physical view exit are still mandatory below.
	return fact.size() == 8 and fact.get("contract_id") == "hardcore.source.Root_final_free.v1" and fact.get("owner_session_id") == session_id and fact.get("closure_id") == closure_id and fact.get("world_context") == world and fact.get("source_root_id") is int and fact.source_root_id != 0 and fact.get("exit_step") == 17 and fact.get("children_exited") == true and fact.get("children_final_freed") == true

func _record_actual_source_root_final_free(event: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _main_composition == null or _world_views == null: return _blocked("actual_bound_Source_exit_owner_required")
	var prefix: RefCounted = _main_composition.get("_prefix")
	if prefix == null or prefix.actual_current_original_event() != event: return _blocked("actual_current_Native_Source_exit_prefix_required")
	var args: Variant = event.get("arguments")
	if not args is Array or args.size() != 1 or not args[0] is Dictionary: return _blocked("actual_Source_exit_schema_required")
	var fact: Dictionary = args[0]
	var world: Dictionary = _transport.get("_world")
	var site: Dictionary = event.get("source_site",{})
	if not accepts_original_source_root_final_free_fact(fact,_session_front.get("session_id"),_world_loading_pin_closure.get("closure_id"),world): return _blocked("actual_same_Source_Root_step17_final_free_required")
	if site.get("world_context") != world or str(site.get("domain")) != "P" or site.get("entry_id") not in ["GameRoot._exit_tree","GameRoot._exit_tree:faulted_cleanup"] or not site.get("entry_ordinal") is int or site.entry_ordinal <= 0 or _host.status().get("close_requested") != true or _transport.get("_state") != "CLOSING": return _blocked("actual_closing_Source_Root_exit_site_required")
	if not _actual_source_root_exit.is_empty():
		return {"success":true,"status":"APPLIED"} if _actual_source_root_exit.event == event else _blocked("actual_Source_Root_exit_identity_changed")
	var root: Node2D = _root_transport.retained_root()
	if not is_instance_valid(root) or root.get_instance_id() != world.get("world_runtime_id") or _world_views.get("_root") != root: return _blocked("actual_retained_Main_Root_required")
	var view_exit: Dictionary = _world_views.capture_actual_original_world_view_exit(world)
	if view_exit.get("success") != true or view_exit.get("actual_original_exit") != true or view_exit.get("actual_actor_nodes_absent") != true or view_exit.get("actual_prepared_shell_absent") != true or view_exit.get("actual_ui_input_closed",{}).get("terminal") != true: return {"success":false,"status":"PENDING","error":"actual_physical_World_view_exit_pending"}
	# Keep Root/HUD in-tree: Map's final observer still needs these exact Nodes.
	_actual_source_root_exit = {"event":event.duplicate(true),"fact":fact.duplicate(true),"actual_view_exit":view_exit.duplicate(true),"actual_root_id":root.get_instance_id(),"actual_Main_process_frame":Engine.get_process_frames()}
	return {"success":true,"status":"APPLIED"}

func capture_actual_original_host_policy(host: Object, blueprint: Dictionary, prepared: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or host != _host or host == null or prepared.get("success") != true or not blueprint.get("root") is Node2D: return _blocked("actual_Host_blueprint_prepared_identity_required")
	var checked: Dictionary = validate_actual_host_policy(_policy)
	if checked.get("success") != true: return checked
	var supplied: Dictionary = checked.policy
	supplied.host_object_id = host.get_instance_id()
	return {"success":true, "policy":supplied, "prepared_receipt":prepared.get("receipt")}

static func inspect_original_root_identity(root: Node2D, facade: Node) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(root) or root.get_script() != preload("res://scripts/game_root.gd") or not is_instance_valid(facade): return _blocked("actual_original_GameRoot_Profile_identity_required")
	var context: RefCounted = WorldContext.new()
	context.configure(root,facade)
	var observed: Dictionary = context.capture_world()
	if observed.is_empty(): return _blocked("actual_original_world_context_unavailable")
	if observed.runtime_map_id < 0:
		# This captures the real constructor identity, not map readiness. The
		# guarded application entry separately proves the selected-profile/code
		# Loading boundary, and actual arrival remains the Source transaction.
		if observed.runtime_map_id == -1 and observed.world_epoch == 0 and not observed.profile_id.is_empty():
			return {"success":true,"phase":"PRE_MAP","world":observed}
		return _blocked("prepared_original_Main_has_no_active_runtime_map",{"actual_context":observed,
			"original_entry":"GameRoot._begin_initial_world_bootstrap -> travel_to_service_home",
			"required_change":"Only the selected original map -1 / generation 0 constructor is a pre-map context; no target is made active"})
	if observed.profile_id.is_empty(): return _blocked("actual_selected_Profile_identity_required",{"actual_context":observed})
	return {"success":true, "world":observed}

func capture_actual_original_prepared_world_identity(root: Node2D, receiver: Node, scope: Dictionary) -> Dictionary:
	var checked: Dictionary = _loading.verify_actual_original_loading_scope(scope)
	if checked.get("success") != true: return checked
	if receiver.get_instance_id() != scope.receiver_id or _root_transport.retained_root() != root: return _blocked("actual_same_prepared_root_and_launch_receiver_required")
	var identity: Dictionary = inspect_original_root_identity(root,_facade)
	if identity.get("success")!=true: return identity
	if _environment_boot.is_empty():
		preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_PRE_MAP_ENVIRONMENT")
		var captured: Dictionary = capture_actual_original_pre_map_environment(root,_facade,_facade.get_tree(),identity.world,_policy)
		preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"PRE_MAP_ENVIRONMENT_RETURNED")
		if captured.get("ok")!=true: return _blocked("actual_original_pre_map_environment_capture",captured)
		_environment_boot = captured.boot
	elif _environment_boot.get("world_identity")!=identity.world: return _blocked("actual_pre_map_environment_Root_changed")
	return identity

static func capture_actual_original_pre_map_environment(root: Node2D,facade: Node,tree: SceneTree,world: Dictionary,host_policy: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or tree==null or facade==null or facade!=tree.root.get_node_or_null("PlayerState"): return {"ok":false,"errors":["actual_Main_Profile_environment_producer_required"]}
	var observed: Dictionary = inspect_original_root_identity(root,facade)
	if observed.get("success")!=true or observed.get("phase")!="PRE_MAP" or observed.get("world")!=world: return {"ok":false,"errors":["actual_same_original_pre_map_identity_required"]}
	var model: RefCounted = facade.get("_model")
	if model==null or model.get_script()!=preload("res://scripts/gameplay/profile/profile_model.gd") or model.get("_owner_thread_id")!=OS.get_main_thread_id() or model.get("_configured")!=true or model.get("active_profile_id")!=world.profile_id: return {"ok":false,"errors":["actual_Main_loaded_Profile_generation_owner_required"]}
	var generation: Variant = model.get("_world_clock_generation")
	if not generation is String: return {"ok":false,"errors":["actual_loaded_Profile_world_generation_required"]}
	var target: int = GameData.service_home_runtime_map_id(false)
	if target<0: return {"ok":false,"errors":["actual_original_initial_home_map_unavailable"]}
	var background: Node2D = preload("res://scripts/world_background.gd").new()
	if not background.defer_initial_legacy_build_to_coordinator():
		background.free()
		return {"ok":false,"errors":["actual_original_Background_coordinator_handoff_required"]}
	var maps: Array[int] = [target]
	var result: Dictionary = preload("res://scripts/gameplay/world/world_environment_boot_publication.gd").capture_before_first_map(root,background,tree,maps,world,generation,host_policy)
	background.free() # Only a detached publication prototype; no runtime scope/pin is claimed.
	return result

func capture_actual_original_world_loading_assembly(blueprint: Dictionary, prepared: Dictionary) -> Dictionary:
	if _host == null or prepared.get("success") != true or not blueprint.get("root") is Node2D: return _blocked("actual_prepared_World_Profile_required")
	var root: Node2D = blueprint.root
	if root != _root_transport.retained_root(): return _blocked("actual_same_original_Main_root_required")
	var constructor: Dictionary=blueprint.get("receipt",{}).get("original_constructor_capture",{})
	if constructor.get("success")!=true or constructor.get("original_root_id")!=root.get_instance_id() or constructor.get("original_source_sha256")!=root.get_script().get_source_code().sha256_text():return _blocked("actual_pre_tree_original_constructor_capture_required")
	if _environment_boot.get("world_identity")!=blueprint.get("world"): return _blocked("actual_before_tree_original_environment_publication_required")
	if _world_birth_inputs.is_empty():
		var births: Dictionary = capture_actual_original_world_birth_inputs(root,blueprint.get("world",{}))
		if births.get("success") != true: return births
		_world_birth_inputs = births.publication
	if _world_birth_inputs.get("world_context") != blueprint.get("world") or _world_birth_inputs.get("actual_root_id") != root.get_instance_id(): return _blocked("actual_same_original_Root_birth_inputs_required")
	var initial_input: Dictionary = _root_transport.prepare_actual_original_world_input(root,blueprint.get("world",{}))
	if initial_input.get("success") != true: return initial_input
	var content_inputs: Dictionary = capture_actual_original_world_content_inputs()
	if content_inputs.get("success") != true: return content_inputs
	if _session_front.is_empty() or _session_front.prepared_receipt != prepared.get("receipt") or _session_front.world != blueprint.get("world") or _world_birth_inputs.get("initial_actor_count") != 0: return _blocked("same_pre_view_Session_front_required")
	if _main_composition == null or _composition_result.get("success") != true: return _blocked("actual_retained_Main_channel_composition_required",_composition_result)
	if _world_views == null:
		var physical: Dictionary = _main_composition.bind_actual_world_front(blueprint,prepared)
		if physical.get("success") != true: return physical
		_world_views = _main_composition.get("_views")
		_world_views_publication = physical.publication
	if _world_views == null or _world_views.get("_root") != root or _world_views.get("_profile_view") != _profile_read_view or _world_views_publication.get("world_context") != blueprint.world: return _blocked("actual_retained_Main_world_views_required",{"has_views":_world_views!=null,"same_root":_world_views!=null and _world_views.get("_root")==root,"same_profile_view":_world_views!=null and _world_views.get("_profile_view")==_profile_read_view,"publication_fields":_world_views_publication.keys(),"publication_world":_world_views_publication.get("world_context",{}),"expected_world":blueprint.world})
	if _world_loading_pin_closure.is_empty():
		preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_COMPLETE_ACTUAL_WORLD_FRONT")
		var completed: Dictionary = _complete_actual_original_world_front(blueprint,prepared,content_inputs.publication)
		preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"COMPLETE_ACTUAL_WORLD_FRONT_RETURNED")
		if completed.get("success") != true: return completed
	if _world_bootstrap_site.get("world_context") != blueprint.world or _world_bootstrap_site.get("clock_epoch") != 0 or _world_bootstrap_site.get("bootstrap") != true: return _blocked("actual_epoch0_Core_source_site_required")
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_WORLD_PIN_INSPECTION")
	var pins: Dictionary = inspect_actual_original_world_loading_pins(_world_loading_pin_closure)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_WORLD_PIN_INSPECTION_RETURNED")
	if pins.get("success") != true or pins.get("closure") != _world_loading_pin_closure: return pins
	if not pins.get("feature_cue_readiness") is Dictionary: return _blocked("actual_feature_cue_readiness_from_pin_owner_required")
	if not _world_assembly_result.is_empty(): return _world_assembly_result
	var values: Dictionary = content_inputs.publication
	var root_scope: Dictionary = _world_birth_inputs.original_root_scope.scope
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ORIGINAL_ACTOR_BIRTH_TEMPLATES")
	var actors: Dictionary = BirthTemplates.capture_main(root_scope,_environment_boot.body_templates)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ORIGINAL_ACTOR_BIRTH_TEMPLATES_RETURNED")
	if actors.get("success") != true: return actors
	var combat: Dictionary = blueprint.receipt.combat_source_template
	var combat_code: Script = load(combat.source_path)
	if combat_code == null or combat_code.get_source_code().sha256_text() != combat.source_sha256: return _blocked("original_combat_constructor_source_changed")
	# Only original Source structural children. Main HUD/camera/renderer nodes
	# and persistent Session autoloads are never copied into this local tree.
	var rows: Array = [
		{"source_key":"root","parent_source_key":"","kind":"root","callbacks":BirthTemplates.capture_callbacks(root.get_script())},
		{"source_key":"combat","parent_source_key":"root","kind":"combat_runtime","callbacks":BirthTemplates.capture_callbacks(combat_code)},
		{"source_key":"background","parent_source_key":"root","kind":"background","callbacks":BirthTemplates.capture_callbacks(preload("res://scripts/world_background.gd"))}]
	var source_tree := {"contract_id":"world.source_tree.original.v1","root_source_key":"root","rows":rows,
		"actor_birth_templates":actors.templates,"service_callback_templates":_world_birth_inputs.service_callback_templates,
		"next_stable_combat_order":_world_birth_inputs.initial_actor_count}
	var tree: SceneTree = root.get_tree()
	var preferences: Node = tree.root.get_node_or_null("LootPreferences")
	var loot_runtime: Node = tree.root.get_node_or_null("LootRuntime")
	if preferences == null or loot_runtime == null: return _blocked("actual_original_Loot_autoloads_required")
	var loot_model: Variant = loot_runtime.get("_owned_model")
	if loot_model == null or not loot_model.get("_v5_trace_enabled") is bool: return _blocked("actual_initialized_Loot_trace_state_required")
	var original_time_domains: Variant = root.get("_time_domains")
	if original_time_domains == null or not original_time_domains.get("_simulation_seconds") is float: return _blocked("actual_original_TimeDomains_constructor_required")
	var loot_index: RefCounted = preload("res://scripts/runtime_loot_spatial_index.gd").new()
	var phase := {"contract_id":"world.root.original_phase.v1","source_tree":source_tree,
		"feature_resource_source_key":"persistent:"+str(_session_front.original_persistent_process_scopes.feature.node_id),
		"source_scope_bindings":{"game_root":"root","background":"background"},
		"ready_rng":{"contract_id":"world.random.original_ready.v1","origin":"S_original_ready_randomize"},
		"loot_preferences":LootPreferencesCapture.capture_original_main(preferences),"loot_descriptors":LootDescriptorsCapture.capture_original_main(),
		"loot_bucket_size_gu":loot_index.bucket_size_gu(),"initial_bootstrap_timeout_msec":preload("res://scripts/game_root.gd").INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC,
		"original_map_loading_settings":_world_views_publication.original_map_loading_settings}
	if CombatRules._contract_cache.is_empty() or not CombatRules._contract_cache.is_read_only(): return _blocked("actual_frozen_combat_contract_required")
	# Session has already adopted the sole loaded Profile/Content/Feature owners.
	# Core consumes those actual owners, not another copy of their publications.
	var assembly := {"owner_session_id":_session_front.session_id,
		"source_scopes":{"game_root":root_scope,"player_state":_session_front.original_persistent_process_scopes.profile.scope,"background":BirthTemplates.capture_native_node2d_scope(root_scope)},
		"initial_input":initial_input.publication,"action_timing":values.action_timing,"world_random":constructor.world_random,
		"streaming_catalog":values.streaming_catalog,"visual_catalog":values.visual_catalog,"service_birth_scopes":_world_birth_inputs.service_birth_scopes,
		"source_domain_publication":{"root_phase":phase,"world_main_views":_world_views_publication,"caster_visual":values.caster_visual,
			"synchronous_monster_visual_loading_for_tests":preload("res://scripts/monster_visual.gd")._synchronous_loading_for_tests,
			"time_domains_simulation_seconds":original_time_domains.get("_simulation_seconds"),"damage_recording_enabled":DamageObserver.recording_enabled,
			"loot_trace_enabled":loot_model.get("_v5_trace_enabled"),"feature_cue_readiness":pins.feature_cue_readiness},
		"source_fields":constructor.source_fields,
		"monster_inputs":values.monster_inputs,"source_documents":values.source_documents,"bootstrap_source_site":_world_bootstrap_site,
		"journal_generation":_session_front.journal_generation,"combat_contract_sha256":ContentGraph.fingerprint(CombatRules._contract_cache)}
	var world_boot: Dictionary = _environment_boot.duplicate(false)
	var settings: Dictionary = _environment_boot.project_settings.duplicate(true)
	settings.merge(Observe.settings(),true)
	world_boot.project_settings = settings; world_boot.assembly = assembly
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_WORLD_ASSEMBLY_GRAPH_CAPTURE")
	var copied: Dictionary = Observe.capture(world_boot)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_WORLD_ASSEMBLY_GRAPH_CAPTURE_RETURNED")
	if copied.get("success") != true: return copied
	_world_assembly_result = {"success":true,"world_boot":copied.publication,"loading_pin_closure":_world_loading_pin_closure}
	return _world_assembly_result

static func capture_actual_original_world_birth_inputs(root: Node2D, world: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or not is_instance_valid(root) or not root.is_inside_tree() or root.is_queued_for_deletion() or root.get_script() != preload("res://scripts/game_root.gd") or world.size() != 5 or world.get("contract_id") != "hardcore.execution.world_context.v1" or world.get("world_runtime_id") != root.get_instance_id() or world.get("runtime_map_id") != root.get("current_map_id") or world.get("world_epoch") != root.get("_zone_generation"): return _blocked("actual_entered_original_World_Root_required")
	var attachment: Variant = root.get("_original_source_main_attachment")
	if not attachment is RefCounted or attachment.get_script() != preload("res://scripts/gameplay/world/world_main_root_attachment.gd") or not attachment.get("_root") is WeakRef or attachment.get("_root").get_ref() != root or attachment.get("_ready_entered") != true or attachment.get("_exited") == true: return _blocked("actual_original_guarded_Root_birth_checkpoint_required")
	var transport: RefCounted = attachment.get("_transport")
	if transport == null or transport.get_script() != preload("res://scripts/gameplay/source/main_boot_root_transport.gd") or transport.get("_scope").get("profile_id") != world.get("profile_id"): return _blocked("actual_same_selected_original_Root_birth_owner_required")
	var host: Object = transport.get("_host")
	if host == null or host.status().get("running") == true: return _blocked("actual_before_Source_original_birth_publication_required")
	var scope: Dictionary = preload("res://scripts/gameplay/source/main_original_process_scope.gd").capture_existing(root)
	if scope.get("success") != true: return scope
	var services: Dictionary = preload("res://scripts/gameplay/source/main_original_service_birth_capture.gd").capture(root)
	if services.get("success") != true: return services
	return Observe.capture({"world_context":world,"actual_root_id":root.get_instance_id(),"original_root_scope":scope,
		"service_birth_scopes":services.publication.service_birth_scopes,"service_callback_templates":services.publication.service_callback_templates,
		"original_service_constructor_witnesses":services.publication.constructor_witnesses})

func capture_actual_original_world_content_inputs() -> Dictionary:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or _host==null or not Catalog.is_active(_services.get("catalog_lease",{})): return _blocked("actual_Main_application_catalogue_owner_required")
	if _content_publication.is_empty():
		var captured: Dictionary = preload("res://scripts/gameplay/source/main_world_content_publication.gd").capture(_services.catalog_lease)
		if captured.get("success")!=true: return captured
		_content_publication = captured.publication
	var witness: Dictionary = _content_publication.source_witness
	if witness.database_revision!=GameData.database_revision or witness.configuration_revision!=ContentLayers.configuration_revision or FileAccess.get_sha256(witness.canonical_monster_path)!=witness.canonical_monster_sha256: return _blocked("actual_World_content_changed_under_catalogue_lease")
	for path: String in witness.source_document_sha256:
		if FileAccess.get_sha256(path)!=witness.source_document_sha256[path]: return _blocked("actual_World_parser_document_changed_under_catalogue_lease")
	return {"success":true,"publication":_content_publication}

func capture_actual_original_selected_session_fields(blueprint: Dictionary, prepared: Dictionary) -> Dictionary:
	if _host == null or prepared.get("success") != true or prepared.get("receipt",{}).get("facade_id") != _facade.get_instance_id(): return _blocked("actual_selected_prepared_Profile_receipt_required")
	if _session_front.is_empty() or _session_front.prepared_receipt != prepared.receipt or _session_front.world != blueprint.get("world") or _session_loading_site.is_empty(): return _blocked("actual_session_front_and_epoch0_site_required")
	# Draft publication only. Publisher takes the sole Native RNG fence after
	# all World/physical/Path checks, immediately before final boot freezing.
	return {"success":true,"prepared_receipt":prepared.receipt,"actual_loaded_profile_view":_session_front.actual_loaded_profile_view,
		"fields":{"session_id":_session_front.session_id,"journal_generation":_session_front.journal_generation,
			"project_settings":Observe.settings(),"feature_resources":_session_front.feature_resources,
			"loading_source_site":_session_loading_site,"feature_live_reservation_usec":_session_front.feature_live_reservation_usec,
			"streaming_live_reservation_usec":_session_front.streaming_live_reservation_usec}}

func prepare_actual_original_session_front(blueprint: Dictionary, prepared: Dictionary) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _host.status().get("running") == true or prepared.get("success") != true: return _blocked("actual_Main_pre_Host_PREPARED_front_required")
	var receipt: Dictionary = prepared.get("receipt",{})
	var world: Dictionary = blueprint.get("world",{})
	var root: Node2D = blueprint.get("root")
	var model: RefCounted = _facade.get("_model")
	var gate: RefCounted = _facade.get("_source_domain_gate")
	var handoff: Dictionary = prepared.get("state_publication",{})
	if root == null or root != _root_transport.retained_root() or gate == null or gate.state() != "PREPARED" or model == null or receipt.get("facade_id") != _facade.get_instance_id() or receipt.get("model_id") != model.get_instance_id() or handoff.get("active_profile_id") != world.get("profile_id"): return _blocked("same_actual_PREPARED_Root_Profile_required")
	if not _session_front.is_empty():
		return {"success":true,"front":_session_front} if _session_front.prepared_receipt == receipt and _session_front.world == world else _blocked("session_front_identity_changed")
	# Capture the Source constructor checkpoint before adding Main display
	# children. Persistent Profile/Feature stay outside this local Source tree.
	if _world_birth_inputs.is_empty():
		var births: Dictionary = capture_actual_original_world_birth_inputs(root,world)
		if births.get("success") != true: return births
		if root.get_child_count(true) != 0: return _blocked("unexpected_pre_view_Root_children")
		_world_birth_inputs = births.publication.duplicate(false)
		_world_birth_inputs.initial_actor_count = root.get_child_count(true)
	elif not _world_birth_inputs.has("initial_actor_count"):
		if root.get_child_count(true) != 0: return _blocked("original_Source_birth_checkpoint_already_changed")
		_world_birth_inputs = _world_birth_inputs.duplicate(false)
		_world_birth_inputs.initial_actor_count = root.get_child_count(true)
	var profile: Dictionary = actual_original_sealed_profile_publication()
	var content: Dictionary = GameData.publish_content_snapshot(_services.catalog_lease)
	if profile.is_empty() or content.is_empty(): return _blocked("actual_Profile_Content_publication_required")
	var origins: Dictionary = prepared.get("original_persistent_process_scopes",{})
	for key: String in ["profile","feature","profile_receipts"]:
		if origins.get(key,{}).get("success") != true: return _blocked("actual_pre_disable_scope:"+key)
	var feature_origin: Dictionary = origins.feature
	var legacy_feature: Node = _content.get("_feature_resource_service")
	if legacy_feature == null or legacy_feature.get_instance_id() != feature_origin.node_id or prepared.get("resource_idle_state",{}).get("contract_id") != "hardcore.feature.coordinator.idle_handoff.v1": return _blocked("same_captured_original_Feature_idle_owner_required")
	var reservation_policy: Variant = _services.get("feature_live_reservation_usec")
	if not reservation_policy is Dictionary: return _blocked("explicit_existing_Feature_reservation_policy_required")
	for key: String in actual_feature_reservation_policy():
		if not reservation_policy.get(key) is int or reservation_policy[key] < 0: return _blocked("invalid_Feature_reservation_policy:"+key)
	var streaming_policy: Variant = _services.get("streaming_live_reservation_usec")
	if not streaming_policy is Dictionary: return _blocked("explicit_existing_streaming_reservation_policy_required")
	for key: String in actual_streaming_reservation_policy():
		if not streaming_policy.get(key) is int or streaming_policy[key] < 0: return _blocked("invalid_streaming_reservation_policy:"+key)
	var lease_owner: Variant = _services.feature_main.export_boot_value(_services.feature_main.get("_facade"))
	var scene_tree: Variant = _services.feature_main.export_boot_value(root.get_tree())
	if not lease_owner is Dictionary or not scene_tree is Dictionary: return _blocked("actual_registered_Feature_Main_references_required")
	# An actual Main Object is the retained execution-incarnation token, not a
	# gameplay Session/model. Its ID never claims the future Source ObjectID.
	if _launch_identity_owner == null:
		_launch_identity_owner = Object.new()
		_launch_identity_receipt = receipt.duplicate(true)
	elif _launch_identity_receipt != receipt: return _blocked("launch_identity_owned_by_other_preparation")
	var incarnation: int = _launch_identity_owner.get_instance_id()
	if incarnation <= 0: return _blocked("positive_launch_incarnation_required")
	var snapshot: Dictionary = ProfileReadView.capture_original_main_loaded(model,handoff,incarnation,world)
	if snapshot.is_empty(): return _blocked("actual_Main_loaded_Profile_view_required")
	var view: RefCounted = ProfileReadView.new()
	if not view.accept_original_journal_snapshot(snapshot): return _blocked("actual_Profile_view_installation_failed")
	_profile_read_view = view
	_session_front = {"prepared_receipt":receipt,"world":world,"session_id":incarnation,"journal_generation":incarnation,
		"profile_publication":profile,"content_snapshot":content,"profile_state_handoff":handoff,"original_persistent_process_scopes":origins,
		"actual_loaded_profile_view":snapshot,"feature_live_reservation_usec":reservation_policy.duplicate(true),"streaming_live_reservation_usec":streaming_policy.duplicate(true),
		"feature_resources":{"lease_owner":lease_owner,"scene_tree":scene_tree,"original_idle_handoff":prepared.resource_idle_state,
			"source_callback_manifest":{"captured":true,"scope_id":feature_origin.node_id,"process_priority":feature_origin.scope.process_priority,"tree_ordinal":feature_origin.tree_ordinal,"lazy_birth_entry":"res://scripts/layers/runtime/content_layer_registry.gd:_feature_resources"}}}
	return {"success":true,"front":_session_front}

func capture_actual_original_boot_sites(prepared: Dictionary, actual_deadline_usec: int) -> Dictionary:
	if _host == null or _host.status().get("running") == true or _session_front.is_empty() or _session_front.prepared_receipt != prepared.get("receipt") or actual_deadline_usec <= Time.get_ticks_usec(): return _blocked("same_prepared_front_and_actual_boot_deadline_required")
	var checkpoint: Dictionary = prepared.receipt.original_checkpoint
	var frame := Engine.get_process_frames()
	if frame != checkpoint.process_frame: return _blocked("original_launch_checkpoint_frame_changed")
	if not _session_loading_site.is_empty() or not _world_bootstrap_site.is_empty(): return _blocked("actual_boot_sites_already_published")
	var base := {"clock_epoch":0,"domain":"P","bootstrap":true,"observation_process_epoch":frame,"world_context":_session_front.world,"deadline_usec":actual_deadline_usec}
	_session_loading_site = base.duplicate(true)
	_session_loading_site.merge({"entry_id":"res://scripts/gameplay/source/source_session.gd:adopt_original_loaded_profile","entry_ordinal":1})
	_world_bootstrap_site = base.duplicate(true)
	_world_bootstrap_site.merge({"entry_id":"res://scripts/game_root.gd:_ready","entry_ordinal":2})
	return {"success":true}

func inspect_actual_original_world_loading_pins(closure: Dictionary) -> Dictionary:
	if _host == null or not closure.get("caster_closure") is Dictionary: return _blocked("actual_world_and_Caster_Loading_closure_required")
	var caster: RefCounted = _services.caster_executor
	if caster.get("_root") == null: return _blocked("actual_Caster_Main_executor_not_bound")
	var pins: Dictionary = caster.inspect_actual_original_loading_pins(closure.caster_closure)
	if pins.get("success") != true: return pins
	var interactable: RefCounted = caster.get("_interactable")
	if interactable == null or not closure.get("interactable_loading") is Dictionary or interactable.inspect_actual_original_loading_pins(closure.interactable_loading).get("success") != true: return _blocked("actual_NPC_and_portal_Loading_pin_inspection_failed")
	if closure != _world_loading_pin_closure or _main_composition == null or _world_views == null or _world_views.get("_closed") == true or closure.get("actual_view_owner_id") != _world_views.get_instance_id() or closure.get("actual_root_id") != _world_views.get("_root").get_instance_id(): return _blocked("actual_same_World_physical_closure_required")
	var scope: Dictionary = _loading.actual_original_loading_scope(closure.world_context)
	if scope != closure.loading_scope or _loading.verify_actual_original_loading_scope(scope).get("success") != true: return _blocked("actual_World_code_and_cover_retention_required")
	var streaming: RefCounted = _main_composition.get("_streaming")
	var ledger: RefCounted = streaming.get("_actor_assets")
	var actor: Dictionary = ledger.inspect_actual_original_input_template(closure.player_inputs)
	if actor.get("success") != true: return _blocked("actual_Player_template_physical_roots_required",actor)
	for kind: String in closure.actual_view_ids:
		var node: Node = _world_views.get("_views").get(kind)
		if not is_instance_valid(node) or not node.is_inside_tree() or node.is_queued_for_deletion() or node.get_instance_id() != closure.actual_view_ids[kind]: return _blocked("actual_World_view_retention_changed:"+kind)
	var frames: Dictionary = _world_views_publication.source_frames
	if streaming.capture_original_source_texture_roots("source_overlay_frames:%d" % int(frames.session_cache_id)) != frames.actual_texture_roots: return _blocked("actual_SourceFrames_physical_root_set_changed")
	return {"success":true,"status":"READY","closure":closure,"caster_receipt":pins,"actor_input_receipt":actor,"feature_cue_readiness":closure.feature_cue_readiness,"actual_Main_process_frame":Engine.get_process_frames()}

func _complete_actual_original_world_front(blueprint: Dictionary, prepared: Dictionary, values: Dictionary) -> Dictionary:
	var caster: RefCounted = _services.caster_executor
	var registry: RefCounted = _main_composition.get("_registry")
	var root: Node2D = blueprint.root
	if caster.get("_root") == null and not caster.configure_main(root,blueprint.world,values.caster_visual,registry.resolve_original_actor_attachment,_host,Callable(_host,"sample_main_thread_cpu_usec"),_policy.event_capacity): return _blocked("actual_Caster_execution_owner_binding_failed")
	var receiver: Node = _loading.get("_receiver").get_ref()
	var code_inputs := {"result":_loading.get("_result"),"consumer":receiver}
	var ports: Dictionary = _main_composition.get("_ports")
	var checkpoint: Dictionary = prepared.receipt.original_checkpoint
	var legacy: Node = _content.get("_feature_resource_service")
	# These genuine Main views were created after Profile PREPARED. Their
	# original deferred layout/draw callbacks must finish at the same existing
	# checkpoint before its Native terminal observation can attest the pins.
	# Verify actual IO/receivers first; flushing cannot certify or erase IO debt.
	var receivers: Dictionary = ports.router.observe_original_main_source_receiver_checkpoint(checkpoint,_facade,_content,legacy)
	if receivers.get("success") != true or receivers.get("all_io_completed") != true: return _blocked("actual_World_Main_receivers_not_terminal",receivers)
	var flushed: Dictionary = ports.source_deferred.flush_original_main_source_checkpoint(checkpoint,_facade,_content,legacy)
	if flushed.get("success") != true: return _blocked("actual_World_Main_deferred_checkpoint_failed",flushed)
	if ProjectSettings.get_setting("hardcore/diagnostics/main_boot_trace",false):
		var fact: Dictionary = flushed.receipt
		print("HC_MAIN_VIEW_DEFERRED_CHECKPOINT ",JSON.stringify({"before_has_messages":fact.before_has_messages,"after_has_messages":fact.after_has_messages,"flush_invoked":fact.flush_invoked,"flush_error":fact.flush_error,"elapsed_usec":fact.actual_finish_usec-fact.actual_start_usec}))
	var proof: Dictionary = caster.prepare_actual_original_owner_closure(_session_front.session_id,prepared.receipt.original_checkpoint,_main_composition.get("_ports").source_deferred,_facade,_content,_content.get("_feature_resource_service"),code_inputs)
	if proof.get("success") != true: return proof
	var interactable := preload("res://scripts/gameplay/world/world_interactable_visual_main.gd").new()
	if not interactable.configure_main(root,caster,_loading,ports.router,blueprint.world): return _blocked("actual_interactable_Main_binding_failed")
	# The original NPC visual manifest is the complete appearance authority.
	# Load physical textures on Main before Source starts; S receives metadata.
	var npc_manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(preload("res://scripts/npc_visual.gd").MANIFEST_PATH))
	if not npc_manifest is Dictionary or not npc_manifest.get("appearances") is Dictionary: return _blocked("actual_original_NPC_appearance_manifest_required")
	var appearances: Array[int] = []
	for key: String in npc_manifest.appearances:
		if not key.is_valid_int() or str(int(key)) != key: return _blocked("invalid_original_NPC_appearance_identity")
		appearances.append(int(key))
	appearances.sort()
	if not caster.bind_original_interactable_leaf(interactable): return _blocked("actual_single_interactable_Main_owner_required")
	var npc: Dictionary = interactable.prepare_original_loading(proof.publication,checkpoint,appearances)
	if npc.get("success") != true: return _blocked("actual_interactable_Loading_preparation_failed",npc)
	# NPC probes create/final-free real visual children. Drain their actual
	# deferred calls at the same original checkpoint before the Source fence.
	var npc_flushed: Dictionary = ports.source_deferred.flush_original_main_source_checkpoint(checkpoint,_facade,_content,legacy)
	if npc_flushed.get("success") != true: return _blocked("actual_NPC_Main_deferred_checkpoint_failed",npc_flushed)
	var reservation: Variant = _services.get("original_warm_reservation_usec")
	if not reservation is int or reservation < 0: return _blocked("actual_original_warm_reservation_policy_required")
	if not _world_views.configure_original_loading_executors(caster,proof.publication,_content,_main_composition.get("_origin"),_world_views.actual_original_map_executor(),reservation,_session_front.session_id,_host,_main_composition.get("_origin")): return _blocked("actual_World_loading_executor_binding_failed")
	if not _main_composition.get("_origin").bind_actual_session_io(_session_front.session_id,_world_views,_main_composition.get("_pump"),_transport) or not _main_composition.get("_closing_frames").bind_actual_original_session_io(_main_composition.get("_origin")): return _blocked("actual_same_World_closing_IO_binding_failed")
	var view_ids: Dictionary = {}
	for kind: String in _world_views.get("_views"): view_ids[kind] = _world_views.get("_views")[kind].get_instance_id()
	var cue_readiness: Dictionary = {}
	var definitions: Script = preload("res://scripts/features/presentation/cue_definitions.gd")
	var resources: Variant = _content.feature_configuration().get("resource_lease")
	for cue: String in definitions.DEFINITIONS:
		var requirements: Dictionary = definitions.requirements(cue)
		if requirements.get("success") != true: return _blocked("actual_feature_cue_definition_invalid:"+cue)
		var available: bool = is_instance_valid(_world_views.get("_views").item_audio)
		for path: String in requirements.paths:
			available = available and resources != null and resources.resource_at(path) != null
		cue_readiness[cue] = {"policy":definitions.definition(cue).policy,"available":available}
	_world_loading_pin_closure = {"contract_id":"hardcore.main.World_boot_inputs.v1","closure_id":_session_front.session_id,"world_context":blueprint.world,"actual_root_id":root.get_instance_id(),"actual_view_owner_id":_world_views.get_instance_id(),"actual_view_ids":view_ids,"loading_scope":_loading.captured_scope(),"player_inputs":_main_composition.get("_player_inputs"),"caster_closure":proof.publication,"interactable_loading":npc.publication,"feature_cue_readiness":cue_readiness}
	# Reuse the original first-world startup deadline. No cross-frame warm
	# occurs between PREPARED and the sole final RNG/start fence.
	return capture_actual_original_boot_sites(prepared,Time.get_ticks_usec()+preload("res://scripts/game_root.gd").INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC*1000)

func release_actual_original_world_loading_pins(id: int, caster: RefCounted) -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or id <= 0 or not is_same(caster,_services.get("caster_executor")) or id != _world_loading_pin_closure.get("closure_id"): return _blocked("actual_same_physical_Loading_owner_required")
	var feature: RefCounted = _services.get("feature_main")
	var request: Dictionary = feature.get("_source_request") if feature != null else {}
	if feature == null or not feature.is_executing_original_primitive() or request.get("operation") != "feature.source_admission_release_pins" or request.get("arguments") != [id] or _actual_source_root_exit.is_empty(): return _blocked("actual_Source_final_exit_and_original_release_primitive_required")
	var site: Dictionary = request.get("site",{})
	if site.get("world_context") != _actual_source_root_exit.fact.world_context or str(site.get("domain")) != "P" or site.get("entry_id") not in ["GameRoot._exit_tree","GameRoot._exit_tree:faulted_cleanup"] or _host.status().get("close_requested") != true: return _blocked("actual_same_Source_exit_pin_release_site_required")
	if not _actual_loading_release.is_empty(): return _actual_loading_release.duplicate(true)
	if not _actual_caster_pins_released:
		if not caster.flush_original_notifications(): return _blocked("actual_Caster_notifications_still_owned")
		for field: String in ["_casts","_visuals","_cells","_batches","_cell_controller","_created_nodes","_live_reply_nodes","_claimed_event","_claimed_ticket"]:
			var debt: Variant = caster.get(field)
			if not debt is Dictionary or not debt.is_empty(): return _blocked("actual_Caster_debt_retained",{"field":field})
		if caster.get("_awaiting_reply") != false: return _blocked("actual_Caster_reply_retained")
		var released: Dictionary = caster.release_original_loading_pin_closure(id)
		if released.get("success") != true: return _blocked("actual_Caster_Warm_NPC_pin_release_pending",released)
		for field: String in ["_paths","_textures","_code_objects","_code_object_sources","_code_result"]:
			if not caster.get(field).is_empty(): return _blocked("actual_Caster_physical_pin_still_held",{"field":field})
		if caster.get("_closed") != true or caster.get("_loading_sequence_lease_held") != false: return _blocked("actual_Caster_release_not_terminal")
		_actual_caster_pins_released = true
	var code_release: Dictionary = _loading.release_actual_original_terminal_code_observation(_actual_source_root_exit,feature)
	if code_release.get("success") != true: return code_release
	_actual_loading_release = {"success":true,"status":"READY","contract_id":"hardcore.main.World_loading_release.v1","closure_id":id,"owner_session_id":_session_front.session_id,"actual_caster_id":caster.get_instance_id(),"actual_source_exit":_actual_source_root_exit.duplicate(true),"actual_code_lease_release":code_release.duplicate(true),"actual_primitive_identity":request.get("identity",{}).duplicate(true),"actual_Main_process_frame":Engine.get_process_frames()}
	return _actual_loading_release.duplicate(true)

func inspect_actual_launch_readiness() -> Dictionary:
	# This admits entry to the existing transaction, not World readiness. World
	# views/Source constructors are created once by that transaction below.
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _facade == null or _main_composition == null or _assembly.get("success") != true: return _blocked("actual_Main_composition_required")
	if _composition_result.get("success") != true or _main_composition.get("_stage") != "CHANNELS_BOUND": return _blocked("actual_Main_channels_not_bound",_composition_result)
	var ports: Dictionary = _main_composition.get("_ports")
	var pump: RefCounted = _main_composition.get("_pump")
	var driver: Node = ports.get("lifecycle")
	if ports.get("success") != true or not is_instance_valid(driver) or driver.get("_host") != _host or not is_same(driver.get("_transport"),_transport) or not is_same(driver.get("_resource_pump"),pump) or not is_same(_transport.get("_main_pump"),pump) or not is_same(_transport.get("_prefix"),_main_composition.get("_prefix")): return _blocked("actual_single_Driver_Transport_Pump_required")
	var native: Dictionary = _host.status()
	if native.get("started") == true or native.get("main_channels_prepared") != true or native.get("main_channels_aborted") != false: return _blocked("actual_unstarted_prepared_Host_required")
	if ports.admission.get("_committed") != false or not driver.get("_prepared").is_empty(): return _blocked("actual_launch_already_admitted")
	var missing: Array[Dictionary] = preload("res://scripts/gameplay/source/source_application_providers.gd").missing_native_contracts(_host)
	if not missing.is_empty(): return _blocked("actual_Source_application_execution_contracts_required",{"missing":missing})
	return {"success":true,"stage":"MAIN_CHANNELS_BOUND","actual_driver_id":driver.get_instance_id(),"actual_transport_id":_transport.get_instance_id(),"actual_pump_id":pump.get_instance_id()}

func install_actual_launch_entry() -> Dictionary:
	if _host == null or _assembly.is_empty(): return _blocked("actual_Main_factory_application_required")
	var tree: SceneTree = _facade.get_tree()
	if tree.root.has_meta(ENTRY_META): return _blocked("actual_single_Main_application_entry_required")
	# Registration is a Main reference, not admission to Source. The entry
	# below keeps the original Main path until complete Source preparation.
	tree.root.set_meta(ENTRY_META,self)
	return {"success":tree.root.get_meta(ENTRY_META) == self,"actual_installed_application_id":get_instance_id(),"preparation":inspect_actual_launch_readiness()}

func prepare_original_character_launch(receiver: Node) -> Dictionary:
	if _host == null or _launch_active or not is_instance_valid(receiver) or receiver != _facade.get_tree().current_scene: return _blocked("actual_once_current_CharacterSelect_launch_required")
	var ready: Dictionary = inspect_actual_launch_readiness()
	if ready.get("success") != true:
		_last_launch = ready.duplicate(true)
		_last_launch.handled = is_instance_valid(_root_transport.retained_root()) or _host.status().get("started") == true
		return _last_launch.duplicate(true)
	var ports: Dictionary = _main_composition.get("_ports")
	var driver: Node = ports.lifecycle
	_launch_active = true
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"BEFORE_ACTUAL_CHARACTER_DRIVER")
	var actual: Dictionary = await driver.prepare_original_character_launch(receiver)
	preload("res://scripts/gameplay/source/main_boot_trace.gd").mark(self,"ACTUAL_CHARACTER_DRIVER_RETURNED")
	if actual.get("success") == true:
		var entered: Dictionary = await _finish_actual_first_World_handoff(receiver)
		if entered.get("success") != true: actual = entered
		else: actual["actual_World_handoff"] = entered.receipt
	_launch_active = false
	_last_launch = actual.duplicate(true)
	# The same retained graph owns success and failed/accepted prefixes alike.
	# Never drop its assembly, probe/discard another Root or resume old Main
	# merely because Source adoption failed after an actual admission attempt.
	_last_launch.handled = true
	# A refused PREPARED publication can restore the original Main authority
	# without ever starting Source or acquiring physical World owners. Let the
	# existing producer perform the actual guarded Root/Native abort in that
	# precise case. An admitted or partial physical World always stays retained.
	if actual.get("success") != true and _host.status().get("started") == false and _world_views == null and _main_composition.get("_stage") == "CHANNELS_BOUND" and ports.admission.get("_gate").state() == "MAIN" and driver.get("_prepared").is_empty():
		_last_launch.handled = false
	return _last_launch.duplicate(true)

func _finish_actual_first_World_handoff(receiver: Node) -> Dictionary:
	# A map-arrival prefix can precede the adoption acknowledgement. Wait on the
	# existing real Main progress signal, without retaining that prefix or adding
	# a second timer/queue. Both real facts must be true before exposing the Root.
	while true:
		if not is_instance_valid(receiver) or _host == null or _world_views == null: return _blocked("actual_initial_World_receiver_retired")
		var native: Dictionary = _host.status()
		if not str(native.get("fault","")).is_empty() or native.get("close_requested") == true or _transport.get("_state") not in ["PREPARED","S"]: return _blocked("actual_Source_initial_World_failed",{"native":native})
		var world: Dictionary = _transport.get("_world")
		var registry: RefCounted = _main_composition.get("_registry")
		if _transport.get("_state") == "S" and world.get("runtime_map_id",-1) >= 0 and registry.actual_original_player_view(world) != null:
			return _loading.finish_actual_original_world_handoff(_root_transport.retained_root(),_transport,_world_views,registry)
		await _transport.actual_main_progress
	return _blocked("actual_initial_World_handoff_unreachable")

func _service_actual_terminal_transition() -> void:
	if _terminal_transition_active or not _terminal_transition_fault.is_empty() or not _actual_terminal_exit.is_empty() or _host == null or _transport == null or _transport.get("_state") != "CLOSED": return
	if _actual_source_root_exit.is_empty() or _actual_loading_release.get("success") != true or _launch_active: return
	# The close intent comes from the original accepted journal, never a UI bit.
	var intent: String=_transport.actual_original_terminal_intent()
	if intent not in ["QUIT","CHARACTER_SELECT"]:
		_terminal_transition_fault = _blocked("actual_original_terminal_intent_required")
		return
	_terminal_transition_active = true
	var result: Dictionary = finish_actual_original_application_character_select() if intent=="CHARACTER_SELECT" else finish_actual_original_application_quit()
	_terminal_transition_active = false
	if result.get("success") != true: _terminal_transition_fault = result

func actual_original_terminal_exit() -> Dictionary:
	return _actual_terminal_exit.duplicate(true) if not _actual_terminal_exit.is_empty() else _terminal_transition_fault.duplicate(true)

func finish_actual_original_application_quit() -> Dictionary:
	if not _terminal_transition_active: return _blocked("actual_process_frame_terminal_owner_required")
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _transport == null or _loading == null or _main_composition == null or _launch_active or _transport.get("_state") != "CLOSED" or _transport.actual_original_terminal_intent() != "QUIT" or _actual_loading_release.get("success") != true or _actual_source_root_exit.is_empty(): return _blocked("actual_released_Source_and_Main_terminal_QUIT_required")
	if not _actual_terminal_exit.is_empty(): return _actual_terminal_exit.duplicate(true)
	var terminal: Dictionary = _transport.get("_terminal")
	var native: Dictionary = _host.status()
	if terminal.get("success") != true or terminal.get("receipt",{}).get("owner_session_id") != _session_front.get("session_id") or terminal.get("receipt",{}).get("actual_main_pump_id") != _main_composition.get("_pump").get_instance_id() or native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("running") != false: return _blocked("actual_same_joined_Host_terminal_required")
	if not _host.has_method("retire_started_original_main_channels"): return _blocked("actual_Native_started_owner_unbind_contract_missing")
	var receiver: Node = _loading.actual_retained_terminal_receiver()
	if not is_instance_valid(receiver): return _blocked("actual_old_CharacterSelect_callbacks_not_terminal")
	var producer: RefCounted = receiver.get("_source_startup_producer")
	if producer == null or producer.get_script().resource_path != "res://scripts/gameplay/source/main_startup_application_producer.gd" or not is_same(producer.actual_application(),self): return _blocked("actual_original_startup_producer_required")
	var tree: SceneTree = _facade.get_tree()
	var suppress_quit: bool = receiver.get("suppress_quit_for_test") == true
	var map_producer: RefCounted = _world_views.get("_map_producer")
	var map_executor: RefCounted = _world_views.get("_map_executor")
	var map_observation: Dictionary = terminal.get("receipt",{}).get("actual_main_io",{}).get("map_terminal",{})
	var map_terminal: Dictionary = map_observation.get("actual_map_owner_terminal",{})
	# This exact Map proof was physically verified while Root/HUD were in-tree.
	# Preserve it; a verifier requiring inside_tree cannot be re-run after free.
	if map_producer == null or map_executor == null or map_producer.get("_host") != _host or map_executor.get("_host") != _host or map_observation.get("status") != "READY" or map_observation.get("actual_native_map_owner_closed") != true or map_observation.get("actual_producer_id") != map_producer.get_instance_id() or map_terminal.get("producer_runtime_id") != map_producer.get_instance_id() or map_terminal.get("owner_descriptor",{}).get("main_executor_id") != map_executor.get_instance_id() or map_terminal.get("actual_remaining_pin_count") != 0 or map_terminal.get("actual_io",{}).get("terminal") != true: return _blocked("actual_same_two_Map_owners_and_pre_free_terminal_proof_required")
	var physical: Dictionary = _root_transport.finish_actual_original_terminal_root_exit(_actual_source_root_exit,terminal)
	if physical.get("success") != true: return physical
	var retired: Dictionary = _main_composition.retire_actual_started_terminal_channels(terminal)
	if retired.get("success") != true: return retired
	var hall: Dictionary = _loading.retire_actual_original_terminal_receiver(terminal,_transport)
	if hall.get("success") != true: return hall
	if not _transport.finish_actual_started_terminal_references(retired.actual_Native_owner_unbind,terminal): return _blocked("actual_unbound_transport_reference_retirement_required")
	_actual_terminal_exit = {"success":true,"status":"READY","contract_id":"hardcore.main.application_QUIT_terminal.v1","actual_application_id":get_instance_id(),"owner_session_id":_session_front.session_id,"actual_native_terminal":terminal.duplicate(true),"actual_loading_release":_actual_loading_release.duplicate(true),"actual_Main_Root_exit":physical,"actual_Main_channels_retired":retired,"actual_old_receiver_retired":hall,"actual_Main_process_frame":Engine.get_process_frames()}
	var owner_retired: Dictionary = producer.retire_actual_started_terminal_preparation(self,_actual_terminal_exit)
	if owner_retired.get("success") != true:
		_actual_terminal_exit = {}
		return owner_retired
	_actual_terminal_exit.actual_startup_producer_retired = owner_retired
	if tree.process_frame.is_connected(_service_actual_terminal_transition): tree.process_frame.disconnect(_service_actual_terminal_transition)
	if tree.root.get_meta(ENTRY_META,null) == self: tree.root.remove_meta(ENTRY_META)
	_world_loading_pin_closure = {}; _world_birth_inputs = {}; _world_views_publication = {}; _world_assembly_result = {}
	_assembly = {}; _services = {}; _sealed_profile_publication = {}; _session_front = {}
	_main_composition = null; _world_views = null; _profile_read_view = null
	_root_transport = null; _loading = null; _transport = null; _main_failure = null; _host = null
	if _launch_identity_owner != null: _launch_identity_owner.free(); _launch_identity_owner = null
	if not suppress_quit: tree.quit(0)
	return _actual_terminal_exit.duplicate(true)

func verify_actual_started_terminal_owner_retirement(producer: RefCounted, receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or producer == null or not is_same(producer.actual_application(),self) or receipt != _actual_terminal_exit or receipt.get("success") != true or _host == null: return false
	var native: Dictionary = _host.status()
	return native.get("close_quiescent") == true and native.get("join_complete") == true and native.get("running") == false and _main_composition.get("_stage") == "RETIRED_AFTER_CLOSE"

func last_launch_receipt() -> Dictionary: return _last_launch.duplicate(true)

func is_actual_retained_launch_receiver(receiver: Node) -> bool:
	return OS.get_thread_caller_id() == OS.get_main_thread_id() and _host != null and _host.status().get("started") == true and _loading != null and _loading.is_actual_retained_launch_receiver(receiver)

func retire_actual_uncommitted_entry() -> Dictionary:
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _host.status().get("started") == true or _launch_active or _world_views != null or _main_composition == null or _main_composition.get("_stage") != "CHANNELS_BOUND": return _blocked("actual_uncommitted_Main_application_required")
	var gate: RefCounted = _facade.get("_source_domain_gate")
	if gate != null and gate.state() != "MAIN": return _blocked("actual_Profile_Main_authority_required_for_retirement")
	if is_instance_valid(_root_transport.retained_root()):
		var discarded: Dictionary = _assembly.blueprint.discard_actual_uncommitted_blueprint()
		if discarded.get("success") != true: return _blocked("actual_uncommitted_root_retirement_failed",discarded)
	var tree: SceneTree = _facade.get_tree()
	var retired: Dictionary = _main_composition.retire_actual_unstarted_channels()
	if retired.get("success") != true: return retired
	if tree.root.get_meta(ENTRY_META,null) == self: tree.root.remove_meta(ENTRY_META)
	if tree.process_frame.is_connected(_service_actual_terminal_transition): tree.process_frame.disconnect(_service_actual_terminal_transition)
	_loading.forget_actual_uncommitted_scope()
	_assembly = {}; _services = {}
	_sealed_profile_publication = {}
	_main_composition = null; _transport = null; _root_transport = null
	_main_failure = null; _loading = null; _host = null
	if _launch_identity_owner != null:
		_launch_identity_owner.free(); _launch_identity_owner = null
	return {"success":true,"actual_retired_application_id":get_instance_id(),"native_abort_receipt":retired.native_receipt}

static func _blocked(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success":false,"status":"BLOCKED","error":code,"details":details}

# Two-stage Main receiving authority. Terminal evidence is held by this actual
# application; external dictionaries cannot enable a Profile writer.
var _profile_return_context: Dictionary
func verify_actual_profile_return_terminal(gate: RefCounted, publication: Dictionary, producer_retired: bool) -> bool:
	if OS.get_thread_caller_id()!=OS.get_main_thread_id() or not _terminal_transition_active or _host==null or _transport==null or _main_composition==null or _facade.get_tree().root.get_meta(ENTRY_META,null)!=self or _main_composition.get("_stage")!="RETIRED_AFTER_CLOSE" or _profile_return_context.is_empty() or gate==null or not is_same(_profile_return_context.get("gate"),gate) or _facade.get("_source_domain_gate")!=gate or publication!=_profile_return_context.get("publication") or publication!=_transport.actual_profile_terminal_export() or _transport.actual_original_terminal_intent()!="CHARACTER_SELECT": return false
	var native: Dictionary=_host.status()
	var terminal: Dictionary=_profile_return_context.terminal
	var unbound: Dictionary=_profile_return_context.retired.get("actual_Native_owner_unbind",{})
	if terminal!=_transport.get("_terminal") or terminal.get("success")!=true or terminal.get("receipt",{}).get("owner_session_id")!=publication.get("owner_session_id") or unbound.get("success")!=true or unbound.get("host_object_id")!=_host.get_instance_id() or publication.get("actual_host_id")!=_host.get_instance_id() or publication.get("intent",{}).get("source_root_id")!=_actual_source_root_exit.get("fact",{}).get("source_root_id") or unbound.get("bridge_generation")!=publication.get("bridge_generation") or native.get("main_channels_unbound_after_close")!=true or native.get("source_model_close_completed")!=true or native.get("close_quiescent")!=true or native.get("join_complete")!=true or native.get("running")!=false or native.get("original_main_applied_prefix",-1)<_transport.get("_profile_terminal_event_identity").get("journal_event_ordinal",0): return false
	for field: String in ["source_runtime_id","source_session_object_id","source_profile_model_id"]:
		if not publication.get(field) is int or publication[field]==0 or is_instance_id_valid(publication[field]): return false
	if not preload("res://scripts/gameplay/profile/profile_terminal_return.gd").final_files_unchanged(publication): return false
	if producer_retired:
		var random_receipt: Dictionary=_profile_return_context.get("actual_global_random_restore",{})
		if random_receipt.get("success")!=true or random_receipt.get("status")!="RESTORED" or random_receipt.get("terminal_handoff")!=publication.get("global_random_terminal") or native.get("original_terminal_gameplay_random_restored")!=true: return false
		if _profile_return_context.get("producer_retired",{}).get("success")!=true or _profile_return_context.producer.get("_stage")!="RETIRED_AFTER_CLOSE" or is_instance_id_valid(_profile_return_context.physical_facade_id): return false
	return true

func finish_actual_original_application_character_select() -> Dictionary:
	# Current93d refuses before physical Root removal. Compatibility is never
	# restore authority: real Native restore is required after fresh adoption.
	if _host==null or _host.capabilities().get("profile_terminal_global_random_return_contract_id")!="hardcore.profile.global_random.return.v1": return _blocked("actual_Native_Profile_global_random_terminal_return_missing")
	if not _terminal_transition_active: return _blocked("actual_process_frame_terminal_owner_required")
	if OS.get_thread_caller_id() != OS.get_main_thread_id() or _host == null or _transport == null or _loading == null or _main_composition == null or _launch_active or _transport.get("_state") != "CLOSED" or _transport.actual_original_terminal_intent() != "CHARACTER_SELECT" or _actual_loading_release.get("success") != true or _actual_source_root_exit.is_empty(): return _blocked("actual_released_Source_and_Main_terminal_CHARACTER_SELECT_required")
	if not _actual_terminal_exit.is_empty(): return _actual_terminal_exit.duplicate(true)
	var terminal: Dictionary = _transport.get("_terminal")
	var native: Dictionary = _host.status()
	if terminal.get("success") != true or terminal.get("receipt",{}).get("owner_session_id") != _session_front.get("session_id") or terminal.get("receipt",{}).get("actual_main_pump_id") != _main_composition.get("_pump").get_instance_id() or native.get("close_quiescent") != true or native.get("join_complete") != true or native.get("running") != false: return _blocked("actual_same_joined_Host_terminal_required")
	if not _host.has_method("retire_started_original_main_channels"): return _blocked("actual_Native_started_owner_unbind_contract_missing")
	var receiver: Node = _loading.actual_retained_terminal_receiver()
	if not is_instance_valid(receiver): return _blocked("actual_old_CharacterSelect_callbacks_not_terminal")
	var producer: RefCounted = receiver.get("_source_startup_producer")
	if producer == null or producer.get_script().resource_path != "res://scripts/gameplay/source/main_startup_application_producer.gd" or not is_same(producer.actual_application(),self): return _blocked("actual_original_startup_producer_required")
	var tree: SceneTree = _facade.get_tree()
	var publication: Dictionary=_transport.actual_profile_terminal_export()
	var gate: RefCounted=_facade.get("_source_domain_gate")
	var admission: RefCounted=_main_composition.get("_ports").admission
	var legacy: Node=admission.get("_legacy_resources")
	var old_flags: Array=admission.get("_old_flags").duplicate(false)
	var physical_facade: Node=admission.get("_primitive_facade")
	var physical_id: int=physical_facade.get_instance_id()
	if publication.is_empty() or gate==null or gate.state()!="S" or not preload("res://scripts/gameplay/profile/profile_terminal_return.gd").final_files_unchanged(publication): return _blocked("actual_final_Source_Profile_and_shared_bytes_required")
	var map_producer: RefCounted = _world_views.get("_map_producer")
	var map_executor: RefCounted = _world_views.get("_map_executor")
	var map_observation: Dictionary = terminal.get("receipt",{}).get("actual_main_io",{}).get("map_terminal",{})
	var map_terminal: Dictionary = map_observation.get("actual_map_owner_terminal",{})
	# This exact Map proof was physically verified while Root/HUD were in-tree.
	# Preserve it; a verifier requiring inside_tree cannot be re-run after free.
	if map_producer == null or map_executor == null or map_producer.get("_host") != _host or map_executor.get("_host") != _host or map_observation.get("status") != "READY" or map_observation.get("actual_native_map_owner_closed") != true or map_observation.get("actual_producer_id") != map_producer.get_instance_id() or map_terminal.get("producer_runtime_id") != map_producer.get_instance_id() or map_terminal.get("owner_descriptor",{}).get("main_executor_id") != map_executor.get_instance_id() or map_terminal.get("actual_remaining_pin_count") != 0 or map_terminal.get("actual_io",{}).get("terminal") != true: return _blocked("actual_same_two_Map_owners_and_pre_free_terminal_proof_required")
	var physical: Dictionary = _root_transport.finish_actual_original_terminal_root_exit(_actual_source_root_exit,terminal)
	if physical.get("success") != true: return physical
	var retired: Dictionary = _main_composition.retire_actual_started_terminal_channels(terminal)
	if retired.get("success") != true: return retired
	var hall: Dictionary = _loading.retire_actual_original_terminal_receiver(terminal,_transport)
	if hall.get("success") != true: return hall
	_profile_return_context={"gate":gate,"publication":publication,"terminal":terminal,"retired":retired,"producer":producer,"physical_facade_id":physical_id,"old_flags":old_flags}
	if not verify_actual_profile_return_terminal(gate,publication,false): return _blocked("actual_dead_Source_Profile_owner_and_same_Native_terminal_required")
	var resource_return: Dictionary=_content.return_actual_terminal_feature_owner(self,gate,publication,legacy,physical_facade)
	if resource_return.get("success")!=true: return resource_return
	_profile_return_context.resource_return=resource_return
	var prepared: Dictionary=gate.prepare_actual_terminal_return(self,publication,_content.feature_configuration().get("resource_lease") if publication.state.resource.present else null)
	if prepared.get("success")!=true: return prepared
	# Original Model construction and full-state adoption finish first. Only
	# Native may restore Main's real default stream from the stopped S stream.
	var random_restored: Dictionary=_host.restore_original_terminal_gameplay_random(publication.get("global_random_terminal",{}))
	if random_restored.get("success")!=true or random_restored.get("status")!="RESTORED" or random_restored.get("terminal_handoff")!=publication.get("global_random_terminal") or _host.status().get("original_terminal_gameplay_random_restored")!=true: return _blocked("actual_terminal_global_random_restore_required",random_restored)
	_profile_return_context.actual_global_random_restore=random_restored
	if not _transport.finish_actual_started_terminal_references(retired.actual_Native_owner_unbind,terminal): return _blocked("actual_unbound_transport_reference_retirement_required")
	_actual_terminal_exit = {"success":true,"status":"READY","contract_id":"hardcore.main.application_CHARACTER_SELECT_terminal.v1","actual_application_id":get_instance_id(),"owner_session_id":_session_front.session_id,"actual_native_terminal":terminal.duplicate(true),"actual_loading_release":_actual_loading_release.duplicate(true),"actual_Main_Root_exit":physical,"actual_Main_channels_retired":retired,"actual_old_receiver_retired":hall,"actual_Main_process_frame":Engine.get_process_frames()}
	var owner_retired: Dictionary = producer.retire_actual_started_terminal_preparation(self,_actual_terminal_exit)
	if owner_retired.get("success") != true:
		_actual_terminal_exit = {}
		return owner_retired
	_actual_terminal_exit.actual_startup_producer_retired = owner_retired
	_profile_return_context.producer_retired=owner_retired
	var returned: Dictionary=gate.commit_actual_terminal_return(self,publication)
	if returned.get("success")!=true: return returned
	_actual_terminal_exit.actual_Profile_authority_return=returned
	_actual_terminal_exit.actual_Feature_physical_owner_return=resource_return
	for flags: Dictionary in old_flags:
		if not is_instance_valid(flags.node) or not flags.node.is_inside_tree(): return _blocked("actual_original_Main_profile_process_owner_missing")
		flags.node.set_process(flags.process); flags.node.set_physics_process(flags.physics)
	if tree.process_frame.is_connected(_service_actual_terminal_transition): tree.process_frame.disconnect(_service_actual_terminal_transition)
	if tree.root.get_meta(ENTRY_META,null) == self: tree.root.remove_meta(ENTRY_META)
	_world_loading_pin_closure = {}; _world_birth_inputs = {}; _world_views_publication = {}; _world_assembly_result = {}
	_assembly = {}; _services = {}; _sealed_profile_publication = {}; _session_front = {}
	_main_composition = null; _world_views = null; _profile_read_view = null
	_root_transport = null; _loading = null; _transport = null; _main_failure = null; _host = null
	if _launch_identity_owner != null: _launch_identity_owner.free(); _launch_identity_owner = null
	_profile_return_context={}
	var scene_error: Error=tree.change_scene_to_file("res://scenes/startup_loading.tscn")
	if scene_error!=OK: return _blocked("actual_original_StartupLoading_return_failed",{"error":scene_error,"authority_return":returned})
	_actual_terminal_exit.actual_original_startup_scene_requested=true
	return _actual_terminal_exit.duplicate(true)
