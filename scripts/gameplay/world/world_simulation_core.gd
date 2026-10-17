extends RefCounted
const OriginalLiveClosePhase := preload("res://scripts/gameplay/world/world_live_close_phase.gd")

## Production factory: constructed by actual HardCoreSimulationHost AFTER its
## external PhysicsServer owner claim. Host owns Clock/SceneTreeTimer/step/finish;
## source Node Timers retain their own original INTERNAL group callbacks.
const Registry := preload("res://scripts/gameplay/foundation/actor_registry.gd")
const ServiceRegistry := preload("res://scripts/gameplay/foundation/service_registry.gd")
const ActorFactory := preload("res://scripts/gameplay/actors/actor_runtime_factory.gd")
const BootLoader := preload("res://scripts/gameplay/world/world_environment_boot_loader.gd")
const EnvironmentFactory := preload("res://scripts/gameplay/world/world_environment_factory.gd")
const NativeBodies := preload("res://scripts/gameplay/world/world_environment_native_bodies.gd")
const ProfileFactory := preload("res://scripts/gameplay/profile/profile_owner_factory.gd")
const FeatureFactory := preload("res://scripts/features/runtime/domain_factory.gd")
const TimingPort := preload("res://scripts/gameplay/world/world_skill_timing_port.gd")
const SkillActors := preload("res://scripts/gameplay/world/world_skill_actor_port.gd")
const M30QueueModel:=preload("res://scripts/gameplay/world/world_summon_queue_model.gd")
const M30QueuePorts:=preload("res://scripts/gameplay/world/world_summon_queue_ports.gd")
const SkillFields := preload("res://scripts/gameplay/world/world_skill_full_fields.gd")
const SpatialIndex := preload("res://scripts/gameplay/world/world_skill_spatial_index.gd")
const FrameBudget := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_budget.gd")
const ServiceActors := preload("res://scripts/gameplay/enemy/enemy_owner_service_actor_access.gd")
const DecisionBudget := preload("res://scripts/gameplay/enemy/enemy_owner_decision_budget.gd")
const ContextToken := preload("res://scripts/gameplay/enemy/enemy_owner_context_token.gd")
const Footprint := preload("res://scripts/gameplay/enemy/enemy_owner_skill_footprint.gd")
const Terrain := preload("res://scripts/gameplay/enemy/enemy_owner_terrain_navigation.gd")
const Polygon := preload("res://scripts/gameplay/enemy/enemy_owner_polygon_runtime.gd")
const Crowd := preload("res://scripts/gameplay/enemy/enemy_owner_crowd_position.gd")
const SpatialRules := preload("res://scripts/gameplay/world/world_environment_spatial_rules.gd")
const ResourcePrimitives := preload("res://scripts/gameplay/enemy/enemy_owner_resource_primitives.gd")
const StreamingCoordinator := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_coordinator.gd")
const VisualPorts := preload("res://scripts/gameplay/enemy/enemy_owner_streaming_visual_ports.gd")
const Access := preload("res://scripts/gameplay/world/world_canonical_actor_access.gd")
const Scope := preload("res://scripts/gameplay/world/world_temporal_scope.gd")
const Groups := preload("res://scripts/gameplay/world/world_owner_group_order.gd")
const ClockPorts := preload("res://scripts/gameplay/world/world_owner_clock_ports.gd")
const ProfileBudget := preload("res://scripts/gameplay/world/world_profile_budget_port.gd")
const GeometryMirror := preload("res://scripts/gameplay/world/world_crowd_geometry_mirror.gd")
const PathServices := preload("res://scripts/gameplay/world/world_owner_path_services.gd")
const InputPort := preload("res://scripts/gameplay/world/world_owner_input.gd")


const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const RootNumeric := preload("res://scripts/gameplay/world/world_root_interactable_loading.gd")
const SourceFields := preload("res://scripts/gameplay/world/world_source_field_port.gd")
const ProfileHandoff := preload("res://scripts/gameplay/profile/profile_state_handoff.gd")
const FeatureResources := preload("res://scripts/features/runtime/feature_resource_owner_factory.gd")
const PrimitivePort := preload("res://scripts/gameplay/world/world_original_primitive_port.gd")
const PrefixTransport := preload("res://scripts/gameplay/world/world_resource_prefix_transport.gd")
const Journal := preload("res://scripts/gameplay/world/world_original_event_journal.gd")
const FullSkill := preload("res://scripts/gameplay/world/world_skill_full_model.gd")
const FullPorts := preload("res://scripts/gameplay/world/world_owner_full_ports.gd")
const SkillCombat := preload("res://scripts/gameplay/world/world_skill_combat_runtime.gd")
const CastFactory := preload("res://scripts/gameplay/world/world_skill_cast_factory.gd")
const GroundClaims := preload("res://scripts/gameplay/world/world_skill_ground_claims.gd")
const TargetBound := preload("res://scripts/features/adapters/world_target_bound.gd")
const DiagnosticsPort := preload("res://scripts/gameplay/world/world_owner_diagnostics.gd")
const ProfileServices := preload("res://scripts/gameplay/world/world_owner_profile_services.gd")
const ContentServices := preload("res://scripts/gameplay/world/world_owner_content_services.gd")
const TimeDomains := preload("res://scripts/gameplay/world/world_owner_time_domains.gd")
const Engagement := preload("res://scripts/gameplay/world/world_owner_engagement_window.gd")
const LootModel := preload("res://scripts/gameplay/profile/loot_model.gd")
const BodyRules := preload("res://scripts/gameplay/world/world_owner_body_rules.gd")
const ArtRules := preload("res://scripts/gameplay/world/world_owner_art_rules.gd")
const WarriorRules := preload("res://scripts/gameplay/world/world_owner_warrior_rules.gd")
const MonsterIdentity := preload("res://scripts/gameplay/world/world_owner_monster_identity.gd")
const SourceText := preload("res://scripts/gameplay/world/world_owner_source_text.gd")
const DamageObserver := preload("res://scripts/gameplay/world/world_owner_damage_observer.gd")
const EnemyModel := preload("res://scripts/gameplay/actors/enemy_actor_model.gd")
const EnemyShared := preload("res://scripts/gameplay/actors/enemy_shared_state.gd")
const EnemyPorts := preload("res://scripts/gameplay/world/world_enemy_runtime_ports.gd")
const EnemyMotion := preload("res://scripts/gameplay/world/world_enemy_native_motion.gd")
const EnemyRuntime := preload("res://scripts/gameplay/world/world_enemy_runtime_instance.gd")
const EnemyPresentation := preload("res://scripts/gameplay/world/world_owner_enemy_presentation.gd")
const EnemyAudioShared := preload("res://scripts/gameplay/world/world_owner_enemy_audio_shared.gd")
const TargetRing := preload("res://scripts/gameplay/world/world_owner_target_ring.gd")
const NodeTimer := preload("res://scripts/gameplay/world/world_original_node_timer.gd")
const EnemyVisual := preload("res://scripts/gameplay/enemy/enemy_owner_visual.gd")
const ActorLink := preload("res://scripts/gameplay/foundation/actor_link.gd")
const GroundUnit := preload("res://scripts/ground_unit_space.gd")

var _owner := OS.get_thread_caller_id()
var _host: Object
var _boot: Dictionary
var _loader: RefCounted
var _frame: Dictionary
var _phase: StringName = &"BOOTSTRAP"
var _ready := false
var _closing := false
var _closed := false
var _faults: Array[Dictionary] = []
var _world_identity: Dictionary
var _world_clock_generation := ""
var _resource_transport: RefCounted
var _main_primitives: RefCounted
var registry: RefCounted
var service_registry: RefCounted
var world_context: RefCounted
var profile: RefCounted
var content: RefCounted
var diagnostics: RefCounted
var profile_runtime: RefCounted
var feature: Dictionary
var frame_budget: RefCounted
var clock_ports: RefCounted
var input: RefCounted
var environment_factory: RefCounted
var environment: RefCounted
var native_world: Object
var native_bodies: RefCounted
var spatial: RefCounted
var skill_actors: RefCounted
var skill_fields: RefCounted
var skills: RefCounted
var action_timing: RefCounted
var random: RandomNumberGenerator
var owner_services: Dictionary
var actor_access: RefCounted
var service_actors: RefCounted
var paths: RefCounted
var streaming: RefCounted
var resources: RefCounted
var visual_ports: RefCounted
var geometry_mirror: RefCounted
var _groups: RefCounted
var _source_scopes: Dictionary = {}
var _service_scopes: Dictionary = {}
var _service_models: Dictionary = {}
var _actor_instances: Dictionary = {}
var _actor_metadata: Dictionary = {}
var _actor_source: Dictionary = {}
var _shared_actor_views: Dictionary = {}
var _shared_parent_scopes: Dictionary = {}
var _map_identity_handles: Dictionary = {}
var _body_identity_handles: Dictionary = {}
var _body_retirements: Array[int] = []
var _actor_retirements: Array[int] = []
var _original_delete_queue: Array[Dictionary] = []
var _callbacks: Array[Dictionary] = []
var _callback_order := 0
var _events: Array[Dictionary] = []
var _geometry_registered: Dictionary = {}
var _player_id := 0
var _entry_ordinal := 0
var _environment_stage := ""
var _root_numeric: RefCounted
var _profile_services: RefCounted
var _feature_resources: RefCounted

var original_source_fields: RefCounted
var global_random: RefCounted
var time_domains: RefCounted
var loot: RefCounted
var engagement: RefCounted
var target_bound: RefCounted
var skill_combat: RefCounted
var cast_presentation: RefCounted
var casts: RefCounted
var _full_ports: RefCounted
var _ground_claims: RefCounted
var _journal: RefCounted
var _feature_resource_session: Dictionary
var _feature_resource_scope: RefCounted
var _actor_scopes: Dictionary = {}
var _actor_visuals: Dictionary = {}
var _cast_models: Dictionary = {}
var _exit_callbacks: Dictionary = {}
var _actor_signal_bridges: Dictionary = {}
var _node_timers: Dictionary = {}
var _registered_owner_services: Dictionary = {}
var _source_site: Dictionary = {}
var _enemy_shared: RefCounted
var _enemy_audio_shared: RefCounted
var _enemy_presentation: Dictionary = {}
var _enemy_visual_services: Dictionary = {}
var _target_ring: RefCounted
var _audio_primitives: RefCounted
var _original_source_session: RefCounted


func _init(host: Object, boot: Dictionary, source_session: RefCounted = null) -> void:
	_original_source_session = source_session
	_host = host
	_boot = boot
	if _owner == OS.get_main_thread_id() or host == null or not host.is_class("HardCoreSimulationHost"):
		fault("world_core_requires_real_external_owner_host", {})
		return
	if not host.has_method("source_deferred_queue_configured") or not host.source_deferred_queue_configured():
		fault("native_original_source_call_queue_missing", {})
		return
	# No live provider can be smuggled into the recursively plain boot graph.
	var graph: RefCounted = ClassDB.instantiate("HardCoreContentValueGraph")
	var checked: Dictionary = graph.validate(boot, false)
	if not checked.get("ok", checked.get("success", false)):
		fault("world_boot_not_plain", checked)
		return
	_loader = BootLoader.new()
	if not _loader.configure_owner(boot, self): return
	if not _validate_assembly_boot(): return
	if not _validate_owner_port(source_session, ["adopt_world_core", "original_frame_budget", "original_service_actors", "feature_resource_session", "feature_resource_process_scope", "bind_current_original_resource_transport", "original_event_journal", "original_profile_owner", "original_global_random", "original_engagement_owner", "original_enemy_shared_owner", "original_enemy_audio_shared_owner", "release_world_core"]):
		fault("persistent_original_source_session_required", {})
		return
	_world_identity = boot.world_identity
	if not host.has_method("bind_original_world_context") or not host.bind_original_world_context(_world_identity):
		fault("native_original_world_context_not_bound", {})
		return
	_source_site = boot.assembly.bootstrap_source_site
	if _source_site.get("world_context") != _world_identity:
		fault("bootstrap_original_world_context_mismatch", {})
		return
	_world_clock_generation = boot.world_clock_generation
	_resource_transport = host.call("resource_primitive_transport")
	_main_primitives = host.call("world_primitive_transport")
	if not _validate_owner_port(_resource_transport, ["capabilities", "exchange_original_primitive", "ordered_main_prefix"]) or not _validate_owner_port(_main_primitives, ["exchange_world_primitive"]): return
	registry = Registry.new()
	if not registry.configure_world(_world_identity, _world_clock_generation):
		fault("canonical_actor_registry_configuration", {})
		return
	_groups = Groups.new(registry)
	geometry_mirror = GeometryMirror.new(self)
	clock_ports = ClockPorts.new(self, boot.project_settings)
	input = InputPort.new(self)
	if not input.accept(boot.assembly.initial_input):
		fault("initial_input_publication_invalid", {})
		return
	for name: String in boot.assembly.source_scopes:
		if name == "player_state":
			var persistent: RefCounted = source_session.original_profile_process_scope()
			if persistent == null or persistent.owner_thread_id() != _owner:
				fault("original_persistent_Profile_scope_missing", {})
				return
			_source_scopes[name] = persistent
			continue
		var scope := Scope.new()
		if not scope.configure_source(boot.assembly.source_scopes[name], self):
			fault("source_scope_publication_invalid", {"source": name})
			return
		_source_scopes[name] = scope
	actor_access = Access.new(registry, null, self, _shared_actor_views, _shared_parent_scopes)
	if not source_session.adopt_world_core(self, actor_access, clock_ports): return
	service_actors = source_session.original_service_actors()
	frame_budget = source_session.original_frame_budget()
	if not _validate_owner_port(service_actors, ["register_process_owner"]) or not _validate_owner_port(frame_budget, ["resource_continuations_configured", "begin_resource_external_segment", "resume_resource_external_segment"]): return
	if not frame_budget.resource_continuations_configured(): return
	for scope: RefCounted in _source_scopes.values():
		if not service_actors.register_process_owner(scope): return
	var providers := {"Engine": clock_ports, "Time": clock_ports, "ProjectSettings": clock_ports, "phase": clock_ports}
	world_context = WorldContext.new()
	if not world_context.configure_domain(registry, self): return
	service_registry = ServiceRegistry.new()
	if not service_registry.configure_owner(world_context, self, self): return
	var caps: Dictionary = _host.capabilities()
	_journal = source_session.original_event_journal()
	if not _validate_owner_port(_journal, ["append", "freeze_prefix", "acknowledge", "consume_normal_receipt"]): return
	if _journal.freeze_prefix().bridge_generation != int(caps.bridge_generation) or _journal.freeze_prefix().journal_generation != int(boot.assembly.journal_generation):
		fault("persistent_original_journal_incarnation_mismatch", {})
		return
	_resource_transport = PrefixTransport.new(self, _host)
	global_random = source_session.original_global_random()
	if not _validate_owner_port(global_random, ["randi", "randi_range", "draw", "randf", "randf_range", "seed", "randomize", "is_initialized"]) or not global_random.is_class("HardCoreGameplayGlobalRandom") or not global_random.is_initialized():
		fault("actual_session_gameplay_global_random_handoff_missing", {})
		return
	# Cold original Main APIs keep their real continuation endpoint. LIVE
	# gameplay draws use the one adopted Session PCG, without parking S on M.
	_main_primitives = PrimitivePort.new()
	if not _main_primitives.configure_owner(self, _host, frame_budget, clock_ports): return
	if not _main_primitives.begin_original_phase(boot.assembly.bootstrap_source_site): return
	if not source_session.bind_current_original_resource_transport(_resource_transport): return
	_feature_resource_scope = source_session.feature_resource_process_scope()
	_feature_resource_session = source_session.feature_resource_session()
	if _feature_resource_scope == null or _feature_resource_session.get("success") != true or not _validate_owner_port(_feature_resource_session.get("coordinator"), ["prepare", "apply_ready", "original_process"]):
		fault("persistent_feature_resource_owner_missing", {})
		return
	_feature_resources = _feature_resource_session.coordinator
	if not is_same(_feature_resource_session.primitives._budget, frame_budget):
		fault("second_frame_budget_for_persistent_feature_resource_owner", {})
		return
	if not service_actors.register_process_owner(_feature_resource_scope): return
	if not _feature_resource_session.primitives.begin_original_phase(_source_site): return
	# SourceSession owns the single already-loaded Profile/Content/diagnostics.
	# World adoption never re-loads/re-initializes or re-adopts Main state.
	var made: Dictionary = source_session.original_profile_owner()
	if not made.success:
		fault("profile_owner_assembly_failed", made)
		return
	profile = made.profile
	content = made.content
	profile_runtime = made.runtime
	diagnostics = DiagnosticsPort.new(made.diagnostics.numeric_owner(),clock_ports)
	if made.get("original_loaded_handoff_applied") != true or profile._owner_thread_id != _owner or not profile._configured or profile.active_profile_id != _world_identity.profile_id:
		fault("original_loaded_profile_owner_not_adopted_once", {})
		return
	_profile_services = ProfileServices.new(profile)
	time_domains = TimeDomains.new()
	if not time_domains.configure_owner(self, float(boot.assembly.source_domain_publication.time_domains_simulation_seconds)): return
	engagement = source_session.original_engagement_owner()
	if not _validate_owner_port(engagement, ["on_skill_cast", "on_field_spawned", "on_ground_damage_tick", "on_enemy_death_committed", "record_frame_interval_ms", "original_handoff_applied"]): return
	if not engagement.original_handoff_applied():
		fault("original_engagement_static_handoff_missing", {})
		return
	feature = FeatureFactory.create(self, registry, profile, world_context)
	if not feature.success:
		fault("feature_owner_assembly_failed", feature)
		return
	assert(is_same(world_context, feature.world), "one canonical world context is required")
	var spatial_rules := SpatialRules.new()
	if not spatial_rules.configure_owner(diagnostics): return
	providers.WorldSpatialRulesScript = spatial_rules
	providers.FrameBudget = frame_budget
	var persistent_path: Dictionary=source_session.original_persistent_path_bindings()
	if persistent_path.size()!=6:
		fault("actual_persistent_path_bindings_missing",{})
		return
	providers.HCPPolyRuntime = persistent_path.HCPPolyRuntime
	owner_services = {"FrameBudget": frame_budget, "HCDecisionBudget": DecisionBudget.new(),
		"HCM30ContextTokenScript": persistent_path.HCM30ContextTokenScript, "SkillFootprintSnapshotScript": Footprint.new(),
		"MonsterTerrainNavigationPolicyScript": persistent_path.Terrain, "HCPPolyRuntime": providers.HCPPolyRuntime,
		"CrowdAttackPosition": Crowd.new(), "WorldSpatialRulesScript": spatial_rules}
	for key: String in ["HCDecisionBudget", "SkillFootprintSnapshotScript", "CrowdAttackPosition"]:
		if not owner_services[key].configure_owner(providers, service_actors):
			fault("owner_service_configuration_failed", {"service": key})
			return
	environment_factory = EnvironmentFactory.new()
	if not environment_factory.configure_owner({"world": self, "diagnostics": diagnostics, "polygon": owner_services.HCPPolyRuntime, "terrain_navigation": owner_services.MonsterTerrainNavigationPolicyScript}, _loader.publication): return
	if not _loader.attach_environment_factory(environment_factory): return
	environment = environment_factory.environment
	for map_id: Variant in _loader.publication.map_load_order:
		var identity := Object.new()
		_map_identity_handles[int(map_id)] = identity
	native_world = ClassDB.instantiate("HardCoreSimulationWorld2D")
	if native_world == null or not native_world.initialize(boot.default_area):
		fault("external_native_world_initialization_failed", {})
		return
	native_bodies = NativeBodies.new()
	if not native_bodies.configure_owner(native_world, self): return
	skill_actors = SkillActors.new()
	if not skill_actors.configure(registry, self): return
	skill_fields = SkillFields.new()
	skill_fields.configure_actor_links(skill_actors)
	skill_fields.write_field("current_map_id", int(_world_identity.runtime_map_id))
	skill_fields.write_field("_zone_generation", int(_world_identity.world_epoch))
	spatial = SpatialIndex.new(skill_actors, profile, float(boot.project_settings[SpatialIndex.BUCKET_SIZE_SETTING]))
	action_timing = TimingPort.create_owner(boot.assembly.action_timing, content.rules.professions)
	if action_timing == null:
		fault("canonical_action_timing_unavailable", {})
		return
	random = RandomNumberGenerator.new()
	random.seed = boot.assembly.world_random.seed
	random.state = boot.assembly.world_random.state
	paths = PathServices.new()
	if not paths.configure_owner(self, service_registry, actor_access, service_actors, {
		"Terrain": owner_services.MonsterTerrainNavigationPolicyScript, "HCM30ContextTokenScript": owner_services.HCM30ContextTokenScript,
		"HCPPolyRuntime": owner_services.HCPPolyRuntime, "FrameBudget": frame_budget, "Engine": clock_ports, "Time": clock_ports}, _original_source_session.original_path_session()): return
	owner_services.HCM30ContextTokenScript = _original_source_session.original_path_session().original_context_token()
	resources = ResourcePrimitives.new()
	if not resources.configure_owner(boot.assembly.streaming_catalog, _resource_transport, frame_budget, clock_ports, Callable(self, "_resource_failure")): return
	streaming = StreamingCoordinator.new()
	if not streaming.configure_owner({"FrameBudget": frame_budget, "Time": clock_ports, "RuntimeDiagnostics": diagnostics,
		"services": service_registry, "primitives": resources, "test_mode": profile.test_mode,
		"synchronous_visual_loading_for_tests": boot.assembly.source_domain_publication.synchronous_monster_visual_loading_for_tests}, _source_scopes.game_root, Callable(self, "_resource_failure")): return
	if streaming.original_initial_binding_observed.connect(_on_original_initial_enemy_binding_observed) != OK:
		fault("initial_enemy_presentation_completion_not_connected",{})
		return
	# Bind this same World coordinator to its persistent Session before the
	# original ready coroutine can submit later map/visual work. It remains
	# cold during genuine epoch-zero Loading and switches with that one Session.
	if not streaming.configure_live_session(_original_source_session,_original_source_session.original_streaming_live_reservation_policy()):
		fault("actual_same_Session_streaming_live_binding_failed",{})
		return
	visual_ports = VisualPorts.new()
	if not visual_ports.configure_owner(boot.assembly.visual_catalog, Callable(self, "_resource_failure")) or not visual_ports.configure_streaming_bindings(resources, streaming) or not visual_ports.configure_original_journal(Callable(self, "append_original_visual_event")): return
	if not resources.begin_original_phase(_source_site): return
	# The source-bound assembly module installs the remaining original numeric
	# GameRoot entries, complete skills, Enemy ports and profile preparation.
	# Missing service code is a hard admission failure, never an empty provider.
	if not _install_source_domains(): return
	# First LIVE admission uses the still-open actual epoch0 Loading source entry.
	# Main's actual pinned closure and real live Feature consumer must both pass.
	if not _original_source_session.live_resource_phase():
		if not boot.get("actual_loading_pin_closure") is Dictionary or not _original_source_session.enter_live(boot.actual_loading_pin_closure):
			fault("actual_first_world_Loading_pin_and_LIVE_admission_failed",{})
			return
	if not streaming.live_resource_phase():
		fault("actual_World_ready_requires_same_Session_LIVE_streaming",{})
		return
	if not _finish_original_entry(): return
	profile_runtime.register_world(self)
	_ready = _faults.is_empty()

func _validate_assembly_boot() -> bool:
	for method: String in ["resource_primitive_transport", "world_primitive_transport"]:
		if not _host.has_method(method): return _reject("host_primitive_bridge_missing", {"method": method})
	if not _boot.get("assembly") is Dictionary: return _reject("world_assembly_publication_missing", {})
	if _original_source_session == null or not _original_source_session.has_method("owner_thread_id") or _original_source_session.owner_thread_id() != _owner or not _original_source_session.has_method("original_budget_session_id") or not _boot.assembly.get("owner_session_id") is int or _boot.assembly.owner_session_id <= 0 or _boot.assembly.owner_session_id != _original_source_session.original_budget_session_id(): return _reject("same_persistent_Session_World_owner_required",{})
	for key: String in ["profile_publication","profile_state","content_snapshot","feature_resource_boot"]:
		if _boot.assembly.has(key): return _reject("persistent_Session_publication_must_not_be_republished_by_Core",{"field":key})
	for key: String in ["source_scopes", "initial_input", "action_timing", "world_random", "streaming_catalog", "visual_catalog", "service_birth_scopes", "source_domain_publication", "source_fields", "monster_inputs", "source_documents", "bootstrap_source_site"]:
		if not _boot.assembly.get(key) is Dictionary: return _reject("world_assembly_field_missing", {"field": key})
	for scope: String in ["game_root", "player_state", "background"]:
		if not _boot.assembly.source_scopes.get(scope) is Dictionary: return _reject("original_source_scope_missing", {"scope": scope})
	if not _boot.assembly.world_random.get("seed") is int or not _boot.assembly.world_random.get("state") is int: return _reject("world_rng_handoff_missing", {})
	if not _boot.assembly.get("journal_generation") is int or _boot.assembly.journal_generation <= 0: return _reject("original_journal_incarnation_missing", {})
	if not _boot.assembly.source_domain_publication.get("time_domains_simulation_seconds") is float: return _reject("original_feature_time_domain_handoff_missing", {})
	if not _boot.assembly.source_domain_publication.get("synchronous_monster_visual_loading_for_tests") is bool: return _reject("original_monster_visual_test_policy_handoff_missing", {})
	if not _boot.project_settings.has(SpatialIndex.BUCKET_SIZE_SETTING): return _reject("original_spatial_bucket_setting_missing", {})
	return true

func _validate_owner_port(port: Variant, methods: Array) -> bool:
	if not port is RefCounted or port is Resource or not port.has_method("owner_thread_id") or port.owner_thread_id() != _owner:
		return _reject("world_same_owner_port_required", {"methods": methods})
	for method: String in methods:
		if not port.has_method(method): return _reject("world_owner_port_method_missing", {"method": method})
	return true

func _install_source_domains() -> bool:
	# Root promotes this same-source module with the rest of this package. It is
	# deliberately installed only after all unique underlying authorities exist.
	var result: Dictionary = source_domain_installation()
	if result.get("success") != true: return _reject("source_domain_installation_failed", result)
	return true

func owner_thread_id() -> int: return _owner
func fault(code: String, details: Dictionary) -> void:
	assert(OS.get_thread_caller_id() == _owner)
	_faults.append({"code": code, "details": details, "phase": _phase, "frame": _frame, "wall_usec": Time.get_ticks_usec()})
	if _boot.get("project_settings",{}).get("hardcore/diagnostics/main_boot_trace",false):
		# Diagnostic codes only: never serialize a nested save/resource graph.
		var observation: Dictionary = {"code":code}
		for field: String in ["error","reason","method","service","field","key"]:
			if details.get(field) is String or details.get(field) is StringName: observation[field] = str(details[field]).left(256)
		if details.get("errors") is Array:
			var errors: Array[String] = []
			for entry: Variant in details.errors:
				if errors.size() >= 8: break
				if entry is String or entry is StringName: errors.append(str(entry).left(256))
			observation.errors = errors
		var nested: Variant = details.get("details")
		if nested is Dictionary:
			for field: String in ["error","reason","method","service","field","key"]:
				if nested.get(field) is String or nested.get(field) is StringName: observation["detail_"+field] = str(nested[field]).left(256)
		if code == "world_input_boundary_rejected" and details.get("packet") is Dictionary:
			var rejected_input: Dictionary = details.packet
			var input_events: Array = []
			for event: Variant in rejected_input.get("original_events",[]):
				if input_events.size() >= 8: break
				if event is Dictionary: input_events.append({"kind":event.get("kind"),"context_world":event.get("view_context",{}).get("world_context")})
			observation.input_boundary = {"current_world":_world_identity,"packet_world":rejected_input.get("world_context"),"sequence":rejected_input.get("sequence"),"last_sequence":input.get("_last_sequence") if input != null else null,"main_process_frame":rejected_input.get("main_process_frame"),"last_main_process_frame":input.get("_last_main_process_frame") if input != null else null,"main_physics_frame":rejected_input.get("main_physics_frame"),"events":input_events}
		print("HC_SOURCE_WORLD_FAULT ",JSON.stringify(observation))
	push_error("World simulation owner fault: " + code)
func _reject(code: String, details: Dictionary) -> bool:
	fault(code, details)
	return false
func _resource_failure(reason: String) -> void: fault("original_resource_continuation_failure", {"reason": reason})
func is_faulted() -> bool: return not _faults.is_empty()
func actor_runtime_is_faulted(_id: int) -> bool: return is_faulted() or _closed
func current_clock_frame() -> Dictionary:
	return _host.current_clock_frame()
func current_world_identity() -> Dictionary: return _world_identity
func world_clock_generation() -> String: return _world_clock_generation
func source_process_epoch() -> int:
	return int(current_clock_frame().source_process_frame)
func source_physics_ordinal() -> int:
	return int(current_clock_frame().source_physics_frame)
func create_timer(delay: float, always := true, physics := false, ignore_scale := false) -> RefCounted:
	var timer: RefCounted = _host.create_timer(delay, always, physics, ignore_scale)
	if timer == null: fault("original_timer_admission_failed", {"delay": delay, "always": always, "physics": physics, "ignore_scale": ignore_scale})
	return timer

func on_inputs(domain: String, packets: Array, original_profile_consumer: Callable = Callable()) -> bool:
	if not _ready or _closed or is_faulted(): return false
	_frame = current_clock_frame()
	var source_domain: StringName = &"H" if domain == "H_INPUT" else &"P"
	if not _begin_original_entry(source_domain, "SceneTree.original_input:" + domain): return false
	for packet: Dictionary in packets:
		if original_profile_consumer.is_valid():
			var consumer: Object=original_profile_consumer.get_object()
			if consumer==null or not consumer.has_method("owner_thread_id") or consumer.owner_thread_id()!=_owner: return _reject("actual_same_Source_Profile_input_consumer",{})
			var accepted: Dictionary=original_profile_consumer.call(packet)
			if accepted.get("handled")==true:
				if accepted.get("accepted")!=true: return _reject("actual_original_Profile_input_rejected",accepted)
				continue
		if not _root_numeric.accept_original_input(domain, packet): return _reject("world_input_boundary_rejected", {"domain": domain, "packet": packet})
	return _finish_original_entry() and not is_faulted()

func on_phase(phase: String, frame: Dictionary) -> bool:
	if not _ready or _closed or is_faulted(): return false
	for key: String in ["epoch", "h_ordinal", "release_usec", "next_release_usec", "observed_usec", "scaled_delta", "simulation_elapsed", "source_process_frame", "source_physics_frame"]:
		if not frame.has(key): return _reject("host_source_clock_field_missing", {"field": key})
	_phase = StringName(phase)
	_frame = frame
	if _phase == &"P_GROUP" and cast_presentation != null:
		if not cast_presentation.begin_original_warm_commit_phase(_host.current_clock_frame()): return _reject("actual_warm_P_commit_window_rejected", {})
		service_original_caster_replies()
		if not cast_presentation.end_original_warm_commit_phase(): return _reject("actual_warm_P_commit_window_end_rejected", {})
	_entry_ordinal = 0
	match _phase:
		&"P_INPUT":
			if not input.begin_original_process_boundary(frame): return _reject("actual_original_input_P_boundary_rejected",{})
		&"H_PREPARE":
			# Host owns sync/flush_queries. A prepare-before-sync hook must invoke
			# source_prepare_before_sync BEFORE its native sync, not at this point.
			if not _invoke_root_entry(&"H", &"original_physics_frame_signal", []): return false
		&"H_GROUP":
			if not _pump_group(&"H", float(frame.scaled_delta)): return false
			if not _invoke_root_entry(&"H", &"original_deferred_message_queue_flush", [&"H", &"H_GROUP:end_group"]): return false
			if not native_world.flush_transforms("SceneTree.physics group original transform flush"): return false
		&"H_AFTER_TIMERS":
			if not _invoke_root_entry(&"H", &"original_h_after_timers", []): return false
			if not native_world.flush_transforms("SceneTree.physics tail before native step"): return false
		&"P_GROUP":
			# Native SceneTree process_frame precedes group callbacks even paused.
			if not _begin_original_entry(&"P", "SceneTree.process_frame"): return false
			if not profile_runtime.service_process_frame(int(frame.source_process_frame)) or not _finish_original_entry(): return false
			if not _invoke_root_entry(&"P", &"original_deferred_message_queue_flush", [&"P", &"P_GROUP:after_process_frame"]): return false
			if not _pump_group(&"P", float(frame.scaled_delta)): return false
			if not _original_delete_queue.is_empty():
				if not _begin_original_entry(&"P","GameRoot.original_final_free_resource_debt"): return false
				var cleaned: bool = _service_original_delete_front_cleanup_at_actual_P()
				if not _finish_original_entry() or not cleaned: return false
			if not _invoke_root_entry(&"P", &"original_deferred_message_queue_flush", [&"P", &"P_GROUP:end_group"]): return false
			if not native_world.flush_transforms("SceneTree.process group original transform flush"): return false
		&"P_AFTER_TIMERS":
			if not _invoke_root_entry(&"P", &"original_p_after_timers", []): return false
			if not native_world.flush_transforms("SceneTree.process timer original transform flush"): return false
		&"U_BEGIN", &"U_END", &"U_WAKE":
			if not _invoke_root_entry(&"P", &"original_control_phase", [_phase, frame]): return false
		&"PUBLISH":
			_trace_actual_map_continuation_wait()
			if not _invoke_root_entry(&"P", &"publish_original_presentation", []): return false
	return not is_faulted()

func source_prepare_before_sync() -> bool:
	return native_world != null and native_world.flush_transforms("SceneTree.prepare before sync")

func register_original_callback(target: RefCounted, scope: Variant, domain: StringName, method: StringName, priority: int, source_order: int, source_entry: String) -> bool:
	if target == null or target is Resource or not target.has_method(method) or domain not in [&"H", &"P"] or source_order < 0: return _reject("original_callback_invalid", {"entry": source_entry})
	for row: Dictionary in _callbacks:
		if row.target.get_ref() == target and row.domain == domain and row.method == method: return _reject("duplicate_original_callback", {"entry": source_entry})
	_callback_order += 1
	_callbacks.append({"target": weakref(target), "scope": scope, "domain": domain, "method": method,
		"priority": priority, "source_order": source_order, "registration_order": _callback_order, "entry": source_entry})
	return true

func _pump_group(domain: StringName, delta: float) -> bool:
	var ordered: Array[Dictionary] = []
	for row: Dictionary in _callbacks:
		if row.domain == domain:
			var target: RefCounted = row.target.get_ref()
			if target == null: continue
			if not row.scope.runtime_object_is_present() or not row.scope.is_inside_world(): continue
			var order: Dictionary = _root_numeric.current_original_callback_order(target,row.scope,row.method)
			if order.get("ok") != true or order.get("domain") != String(domain): return _reject("current_original_tree_order_missing",order)
			var captured: Dictionary = row.duplicate(false)
			captured.source_order = order.order
			if not order.get("source_path") is Array: return _reject("actual_original_source_tree_path_missing",order)
			captured.source_path=order.source_path
			ordered.append(captured)
	ordered.append_array(original_source_session().original_persistent_callback_rows(domain))
	ordered.sort_custom(original_source_session().original_callback_before)
	for row: Dictionary in ordered:
		var target: RefCounted = row.target.get_ref()
		if target == null: continue
		var scope: Object = row.scope
		if not scope.runtime_object_is_present() or not scope.is_inside_world() or not scope.can_process(): continue
		if domain == &"H" and not _scope_physics_enabled(scope): continue
		if domain == &"P" and not _scope_process_enabled(scope): continue
		if not _begin_original_entry(domain, row.entry): return false
		var completed: Variant
		if domain == &"P" and target.get_script() == EnemyVisual and row.method == &"original_process" and _original_enemy_visual_presentation_binding_pending(target):
			# original_process's animation tail can read final-art indirectly via
			# _apply_render_state -> ground indicator. Keep its original action
			# clocks NOW; do not defer the callback delta or gameplay processing.
			if target._actor_present(): target._advance_action_timers(delta)
		else:
			completed = target.call(row.method, delta)
		if domain == &"P" and target.has_method("render_snapshot_at_original_boundary"):
			var actor_handle: Object = target._actor_link.resolve_record()
			if actor_handle != null and not publish_original_actor_visual_projection(actor_handle.get_instance_id(),false,0.0): return _reject("original_enemy_visual_publication_failed",{})
		if cast_presentation != null and cast_presentation.owns_cast_model(target) and not cast_presentation.synchronize_cast_pose(target): return _reject("original_cast_pose_publication_failed", {})
		if completed is bool and not completed: return _reject("original_callback_explicit_failure", {"entry": row.entry})
		if not _finish_original_entry() or is_faulted(): return false
	return true

func _begin_original_entry(domain: StringName, entry: String) -> bool:
	_entry_ordinal += 1
	_source_site = {"clock_epoch": int(_frame.epoch), "domain": domain,
		"entry_id": entry, "entry_ordinal": _entry_ordinal, "bootstrap": int(_frame.epoch) == 0,
		"observation_process_epoch": source_process_epoch(), "world_context": _world_identity,
		"deadline_usec": int(_frame.next_release_usec)}
	return resources.begin_original_phase(_source_site) and _main_primitives.begin_original_phase(_source_site) and _feature_resource_session.primitives.begin_original_phase(_source_site)

func service_scope_view(scope: RefCounted, id: int, _kind: StringName) -> Dictionary:
	if scope == null or scope.owner_thread_id() != _owner: return {}
	if _service_scopes.has(id) and _service_scopes[id] != scope: return {}
	return scope.snapshot()
func queue_service_retirement(scope: RefCounted, id: int) -> bool:
	if scope == null or not _service_scopes.has(id) or not is_same(_service_scopes[id],scope): return false
	if not scope.queued_for_retirement:
		if not scope.queue_retirement(): return false
		_original_delete_queue.append({"kind":&"service","id":id})
	return true
func service_retirement_allowed(scope: RefCounted, _id: int, _model: RefCounted) -> bool: return scope.exit_callbacks_complete
func service_final_free_allowed(scope: RefCounted, _id: int, _model: RefCounted) -> bool: return scope.final_free_checkpoint

func new_original_service_scope(kind: StringName, parent_id: int) -> RefCounted:
	if not _boot.assembly.service_birth_scopes.has(String(kind)):
		fault("original_service_birth_scope_missing", {"kind": kind})
		return null
	var publication: Dictionary = _boot.assembly.service_birth_scopes[String(kind)].duplicate(false)
	publication.parent_scope_id = parent_id
	var scope := Scope.new()
	if not scope.configure_source(publication, self): return null
	return scope

func enter_original_service_scope(id: int, scope: RefCounted, model: RefCounted, callback: StringName, mapped: StringName) -> bool:
	if _service_scopes.has(id) or service_registry.resolve_service(id) == null: return false
	_service_scopes[id] = scope
	_service_models[id] = model
	# Original add_child enters the source scope at this exact lexical point.
	scope.inside_world = true
	if not _root_numeric.original_service_child_entered(id,scope.parent_scope_id): return false
	if callback != &"":
		var source: Dictionary = _root_numeric.original_service_callback_order(id, callback)
		if source.get("ok") != true: return _reject("original_service_order_missing", source)
		return register_original_callback(model, service_registry.process_scope_for_service(id), &"H", mapped, scope.physics_priority, source.order, source.entry)
	return true
func forget_original_service_scope(id: int) -> void:
	var model: RefCounted = _service_models[id]
	for i: int in range(_callbacks.size()-1,-1,-1):
		if is_same(_callbacks[i].target.get_ref(),model): _callbacks.remove_at(i)
	_forget_callbacks_for_scope(_service_scopes[id])
	_service_scopes.erase(id)
	_service_models.erase(id)

func actor_process_enabled(handle: Object) -> bool: return handle.is_processing()
func actor_is_character_body(handle: Object) -> bool: return handle.kind() in [&"player", &"enemy", &"summon"]
func actors_in_group(group: StringName) -> Array[Object]: return _groups.ordered(group)
func actor_is_in_group(handle: Object, group: StringName) -> bool: return _groups.contains(handle.get_instance_id(), group)
func player_handle() -> Object: return registry.resolve_runtime_actor(_player_id)
func parent_scope_id() -> int: return int(_world_identity.world_runtime_id)
func actor_handle_for_model(model: Object) -> Object:
	if model is Access.ActorView: return model.record()
	for instance: RefCounted in _actor_instances.values():
		if instance.model == model: return instance.handle
	for id: int in _cast_models:
		if _cast_models[id] == model: return registry.resolve_runtime_actor(id)
	return null

func update_actor_spatial(id: int, view: Dictionary) -> bool:
	if is_faulted() or spatial == null: return false
	var handle: Object = registry.resolve_runtime_actor(id)
	if handle == null or view.get("runtime_id") != id: return false
	var world: Dictionary = registry.capture_world()
	if world != _world_identity: return _reject("actor_pose_registry_world_mismatch",{})
	if world.runtime_map_id == -1:
		# Original Player READY publishes its real pose before the first travel
		# begins combat life. There is no map or eligible combat ActorRef yet.
		# The actual handle already owns this pose; do not invent a positive
		# life or add a pre-map body to the combat index/geometry mirror.
		return world.world_epoch == 0 and id == _player_id and handle.kind() == &"player" \
			and handle.is_registered() and _root_numeric.get("player") == handle.model() \
			and not _geometry_registered.has(id) and view == handle.runtime_actor_view()
	var identity: Dictionary = handle.identity()
	if identity.is_empty() or identity.get("world") != world: return _reject("actor_pose_qualified_identity_missing",{})
	var map_id: int = int(world.runtime_map_id)
	var radius: float = view.combat_radius_gu
	var old: Dictionary = _geometry_registered.get(id, {})
	if old.is_empty() or old.map != map_id or old.radius != radius:
		spatial.register(id, map_id, view.position_ground_gu, radius, handle.stable_combat_order(), handle.model(), Callable(handle.model(), "spatial_index_position_ground_gu") if handle.model().has_method("spatial_index_position_ground_gu") else Callable())
		_geometry_registered[id] = {"map": map_id, "radius": radius}
	else:
		spatial.update_actor(id, view.position_ground_gu)
	return geometry_mirror.commit(handle, view, float(_actor_source[id].safe_margin_gu), runtime_map_instance_identity(map_id))
func actor_spatial_available() -> bool: return spatial != null and not is_faulted()
func query_aabb_candidates(map_id: int, bounds: Rect2, padding: float) -> Dictionary:
	if not actor_spatial_available(): return {"ok": false}
	return {"ok": true, "candidates": spatial.query_aabb_candidates(map_id, bounds, padding)}
func unregister_combat_target(id: int) -> bool:
	if spatial == null: return false
	spatial.unregister(id)
	_geometry_registered.erase(id)
	return true
func queue_actor_retirement(id: int) -> bool:
	var handle: Object = registry.resolve_runtime_actor(id)
	if handle == null or not handle.queue_retirement(): return false
	if not _actor_retirements.has(id):
		_actor_retirements.append(id)
		_original_delete_queue.append({"kind":&"actor","id":id})
	return true
func runtime_map_instance_identity(map_id: int) -> int:
	return _map_identity_handles[map_id].get_instance_id() if _map_identity_handles.has(map_id) else 0
func freeze_crowd_geometry(map_id: int) -> Dictionary: return geometry_mirror.freeze(map_id)
func read_crowd_geometry_stamp(view: Object) -> Dictionary:
	var handle: Object = actor_access.canonical(view)
	return geometry_mirror.stamp(handle.get_instance_id())
func crowd_kernel_deadline_usec(_actor: Object, _caller: StringName) -> int:
	if _frame.is_empty() or not _frame.get("next_release_usec") is int:
		fault("crowd_original_deadline_missing", {})
		return -1
	return _frame.next_release_usec
func on_crowd_kernel_receipt(receipt: Dictionary) -> void:
	_events.append({"kind": "crowd_kernel_receipt", "receipt": receipt, "clock": _frame})

func environment_blocks_actor_screen_px(position: Vector2, radius: float) -> Dictionary:
	if environment == null or is_faulted(): return {"ok": false}
	return {"ok": true, "blocked": environment_factory.spatial_rules.environment_blocks_actor_screen_px(environment, position, radius)}
func environment_generation_token(staged_generation: int = -1) -> int:
	return int(_root_numeric.original_map_coordinator_generation()) if _root_numeric != null else staged_generation
func environment_generation_is_current(generation: int) -> bool:
	return not _closed and _root_numeric != null and _root_numeric.original_map_coordinator_is_current(generation)
func set_environment_stage(stage: String) -> void: _environment_stage = stage
func create_environment_static_body(transform: Transform2D, shapes: Array[Dictionary], layer: int, mask: int, metadata: Dictionary) -> Dictionary:
	return native_bodies.create_environment_static_body(transform, shapes, layer, mask, metadata)
func retire_environment_static_body(id: int) -> bool: return native_bodies.retire_environment_static_body(id)
func ensure_gothic_environment_bodies(entries: Array, generation: int) -> Dictionary: return native_bodies.ensure_gothic_environment_bodies(entries, generation)
func allocate_environment_body_id(metadata: Dictionary) -> int:
	var identity := Object.new()
	var id := identity.get_instance_id()
	_body_identity_handles[id] = {"handle": identity, "metadata": metadata}
	return id
func enqueue_environment_body_retirement(id: int) -> bool:
	if not _body_identity_handles.has(id) or _body_retirements.has(id): return false
	_body_retirements.append(id)
	return true

func emit_actor_fact(runtime_or_fact: Variant, event: StringName = &"", payload: Dictionary = {}) -> bool:
	if is_faulted(): return false
	if runtime_or_fact is Dictionary: return _journal.append(runtime_or_fact)
	if not runtime_or_fact is int or runtime_or_fact<=0 or event==&"" or payload.size()!=2 or not payload.get("actor_ordinal") is int or payload.actor_ordinal<=0 or not payload.has("value"):
		return _reject("original_actor_fact_source_shape",{})
	return _journal.append({"runtime_id":runtime_or_fact,"actor_ordinal":payload.actor_ordinal,"event":event,"payload":payload.value})
func player_keyboard_movement_vector(_id: int) -> Vector2:
	# Same player.gd gate, evaluated by its current Source gameplay owner.
	return input.keyboard_movement_vector() if gameplay_input_is_enabled() else Vector2.ZERO
func profile_world_paused() -> bool:
	# Same Native owner control read as its clock callback. Boot is a snapshot;
	# pause changes after boot must never be copied into a second authority.
	var current: Dictionary = current_clock_frame()
	if not current.get("paused") is bool:
		fault("native_current_pause_control_missing", {})
		return false
	return current.paused
func profile_runtime_owner_view() -> Dictionary:
	return {"inside_world": _source_scopes.game_root.inside_world, "queued_for_retirement": _source_scopes.game_root.queued_for_retirement, "player_runtime_id": _player_id}
func profile_runtime_registry() -> RefCounted: return registry
func feature_world_is_active() -> bool: return _source_scopes.game_root.inside_world and not _source_scopes.game_root.queued_for_retirement
func feature_world_paused() -> bool: return profile_world_paused()
func feature_actor_in_owner_scope(actor: Object) -> bool:
	return actor != null and registry.resolve_runtime_actor(actor.get_instance_id()) == actor and actor.is_inside_world() and actor.parent_scope_id() == parent_scope_id()
func feature_simulation_usec() -> int:
	return time_domains.simulation_usec()
func feature_budget_mark_pending(category: String, pending: bool, runnable: bool, runs_when_paused := false, physics_owner := false) -> void:
	frame_budget.mark_pending(category, pending, runnable, runs_when_paused, _source_scopes.game_root, physics_owner)
func feature_budget_begin(category: String, necessary := false) -> int: return frame_budget.begin(category, necessary)
func feature_budget_end(token: int) -> void: frame_budget.end(token)

var _actual_close_trace_seen: Dictionary = {}
func trace_actual_source_close(stage: String) -> void:
	if not _boot.get("project_settings",{}).get("hardcore/diagnostics/main_boot_trace",false) or _actual_close_trace_seen.has(stage): return
	_actual_close_trace_seen[stage] = true
	print("HC_SOURCE_CORE_CLOSE ",JSON.stringify({"stage":stage,"thread":OS.get_thread_caller_id(),"core_id":get_instance_id(),"usec":Time.get_ticks_usec()}))
func close_session() -> bool:
	trace_actual_source_close("enter")
	if _closed: return true
	trace_actual_source_close("before_caster_replies")
	if cast_presentation != null: service_original_caster_replies()
	trace_actual_source_close("after_caster_replies")

	if not _closing:
		_original_close_clock_baseline = current_clock_frame()
		# Normal PUBLISH already advanced to the next-P slot. First closing
		# SIGNAL consumes it; Native advances only after SERVICE completion.
		_original_close_last_source_frame = int(_original_close_clock_baseline.source_process_frame)-1
	_closing = true
	# Exact source cleanup owns lease/renderer/accepted claim drainage. Host may
	# not free these records merely because a fault/close request was observed.
	if _root_numeric == null:
		return _close_failed_construction()
	_frame = current_clock_frame()
	if is_faulted():
		# Same original renderer close lane, even for an already faulted World.
		# An unfinished old source entry is retained; it is never reset here.
		if not _source_site.is_empty() or not _ensure_original_live_close_phase(): return false
		if not _begin_original_entry(&"P","GameRoot._exit_tree:faulted_cleanup"): return false
		var exited_faulted: bool = _root_call(&"close_faulted_owner_world", []) == true
		if exited_faulted: exited_faulted = _original_live_close_phase.finish_at_original_world_free()
		if not _finish_original_entry() or not exited_faulted: return false
	else:
		if not _source_site.is_empty(): return _reject("close_at_unfinished_original_entry", {})
		trace_actual_source_close("before_exit_entry")
		if not _begin_original_entry(&"P", "GameRoot._exit_tree"): return false
		trace_actual_source_close("after_exit_entry")
		if not _ensure_original_live_close_phase(): return false
		trace_actual_source_close("before_Root_exit")
		var exited: bool = _root_numeric.close_at_original_world_exit()
		trace_actual_source_close("after_Root_exit")
		if exited: exited = _original_live_close_phase.finish_at_original_world_free()
		if not _finish_original_entry() or not exited: return false
	if not _journal.consume_normal_receipt(_host.completed_original_main_prefix_receipt()): return false
	if _journal.has_pending():
		var prefix: Dictionary = take_original_presentation_prefix()
		if prefix.is_empty() or _root_call(&"publish_original_close_prefix", [prefix]) != true: return false
		return false
	if _host.has_original_deferred_calls(): return false
	if not _actor_instances.is_empty() or not _cast_models.is_empty() or registry.reserved_birth_count() != 0 or service_registry.remaining_service_count() != 0: return _reject("world_close_live_lifetimes", {})
	if cast_presentation != null and not service_original_caster_replies(): return false
	if cast_presentation != null and not cast_presentation.close_owner_presentation(): return false

	# Session persistent cache/escrow accepted cleanup still owns this actual
	# resource endpoint; keep Native world/Core alive until its genuine READY.
	if _original_session_close_resource_hold: return false
	if not native_bodies.close_at_original_boundary() or not native_world.close(): return false
	profile_runtime.unregister_world(self)
	for row: Dictionary in _body_identity_handles.values(): row.handle.free()
	_body_identity_handles.clear()
	for identity: Object in _map_identity_handles.values(): identity.free()
	_map_identity_handles.clear()
	if not _original_source_session.release_world_core(self): return false
	_closed = true
	return true

func _close_failed_construction() -> bool:
	# A failed constructor never acquired gameplay actors. Native objects still
	# close on S before Host releases the one external owner.
	if _host.has_original_deferred_calls(): return false
	if not _actor_instances.is_empty() or not _service_models.is_empty(): return false
	if native_bodies != null and not native_bodies.close_at_original_boundary(): return false
	if native_world != null and not native_world.close(): return false
	for identity: Object in _map_identity_handles.values(): identity.free()
	_map_identity_handles.clear()
	if _original_source_session != null and _original_source_session.get("_core") is WeakRef and is_same(_original_source_session.get("_core").get_ref(),self):
		if not _original_source_session.release_world_core(self): return false
	_closed = true
	return true

func _scope_physics_enabled(scope: Object) -> bool:
	return scope.is_physics_processing_enabled() if scope.get_script() == preload("res://scripts/gameplay/foundation/actor_handle.gd") else scope.physics_enabled()
func _scope_process_enabled(scope: Object) -> bool:
	return scope.is_processing() if scope.get_script() == preload("res://scripts/gameplay/foundation/actor_handle.gd") else scope.process_enabled()


func _finish_original_entry() -> bool:
	if not resources.finish_original_phase() or not _main_primitives.finish_original_phase() or not _feature_resource_session.primitives.finish_original_phase(): return false
	if not _host.finish_original_call_site(_source_site): return _reject("original_source_site_close_failed", _source_site)
	_source_site = {}
	return true

func freeze_original_main_prefix() -> Dictionary:
	return original_source_session().freeze_original_main_prefix()
func ack_original_main_prefix(receipt: Dictionary, submitted: Dictionary) -> bool: return _journal.acknowledge(receipt, submitted)
func append_original_visual_event(event: Dictionary) -> bool:
	return _journal.append({"kind": "enemy_visual", "event": event, "source_site": _source_site})
func emit_original_main_event(operation: StringName, arguments: Array) -> bool:
	return _journal.append({"kind": "original_world_presentation", "operation": operation, "arguments": arguments, "source_site": _source_site})
func take_original_presentation_prefix() -> Dictionary:
	# Only true Native/Main receipts advance the one Source journal. A full
	# Native FIFO leaves this producer's events here for its next original P.
	# ViewTransport registers a receipt identity only after real admission.
	return freeze_original_main_prefix()
func original_world_primitive(operation: StringName, arguments: Array) -> Dictionary: return _main_primitives.exchange(operation, arguments)
func profile_global_randi() -> int: return global_random.randi()
func profile_global_randi_range(low: int, high: int) -> int: return global_random.randi_range(low, high)
func retain_feature_resource_publication(publication: Dictionary) -> Dictionary:
	return _feature_resource_session.primitives.retain_feature_resource_publication(publication)
func release_feature_resource_retention(publication_id: int, retention_id: int) -> bool:
	return _feature_resource_session.primitives.release_feature_resource_retention(publication_id, retention_id)
func feature_resource_retention_supports_path(publication_id: int, retention_id: int, path: String) -> bool:
	return _feature_resource_session.primitives.feature_resource_retention_supports_path(publication_id, retention_id, path)
func prepare_profile_feature_resources(catalog: Dictionary, enabled: Array, _sequence: int, _scope: Dictionary) -> Dictionary:
	var ready: Dictionary = await _feature_resources.prepare(catalog, enabled)
	if ready.get("success") != true: return ready
	var lease: RefCounted = ready.lease
	ready.resource_publication = lease.domain_publication() if lease != null else {}
	ready.diagnostics = lease.diagnostics() if lease != null else {}
	return ready
func apply_profile_feature_ready(callback: Callable) -> bool: return await _feature_resources.apply_ready(callback)
func profile_feature_is_applying() -> bool: return _feature_resources.is_applying()
func cancel_profile_feature_resources() -> void: _feature_resources.cancel_all()
func feature_resource_owner_qualification() -> Dictionary:
	return {"inside_tree": _feature_resource_scope.is_inside_world(), "can_process": _feature_resource_scope.can_process(), "queued_for_deletion": _feature_resource_scope.is_queued_for_retirement()}

func register_original_owner_service(name: StringName, service: RefCounted) -> bool:
	if _registered_owner_services.has(name) or not _validate_owner_port(service, []): return _reject("original_owner_service_registration_rejected", {"service": name})
	_registered_owner_services[name] = service
	return true
func required_owner_service(name: StringName, methods: Array = []) -> RefCounted:
	var value: RefCounted = _registered_owner_services.get(name)
	if value == null or not _validate_owner_port(value, methods):
		fault("required_original_owner_service_missing", {"service": name, "methods": methods})
		return null
	return value
func _root_call(method: StringName, arguments: Array = []) -> Variant:
	if _root_numeric == null or not _root_numeric.has_method(method):
		fault("required_original_root_entry_missing", {"method": method})
		return null
	return _root_numeric.callv(method, arguments)

func source_domain_installation() -> Dictionary:
	original_source_fields = SourceFields.new()
	if not original_source_fields.configure_owner(self, skill_fields, _boot.assembly.source_fields): return {"success": false, "reason": "source_fields_handoff_rejected"}
	if not original_source_fields.bind_owner_field(&"_world_context", world_context): return {"success":false,"reason":"original_world_context_field_binding_failed"}
	var body := BodyRules.new()
	if not body.configure_publication(_boot.body_templates): return {"success": false, "reason": "body_policy_handoff_rejected"}
	var source_text := SourceText.new(self, _boot.assembly.source_documents)
	var identity := MonsterIdentity.new(self, _boot.assembly.monster_inputs)
	var observer := DamageObserver.new()
	observer.configure_owner(clock_ports, actor_access, _boot.assembly.source_domain_publication.damage_recording_enabled)
	owner_services.merge({"ActorBodyPolicyScript": body, "ArtSpec": ArtRules.new(), "WarriorCombatMath": WarriorRules.new(),
		"MonsterIdentityScript": identity, "DamageLedgerObserverScript": observer, "Engine": clock_ports, "Time": clock_ports,
		"ProjectSettings": clock_ports, "PlayerState": _profile_services, "GameData": ContentServices.new(content._source),
		"RuntimeDiagnostics": diagnostics, "CrowdGeometry": geometry_mirror, "source_text": source_text})
	_enemy_shared = _original_source_session.original_enemy_shared_owner(owner_services, actor_access)
	if _enemy_shared == null or _enemy_shared.owner_thread_id() != _owner or not _enemy_shared.original_handoff_applied(): return {"success": false, "reason": "persistent_enemy_shared_source_rejected"}
	_root_numeric = RootNumeric.new()
	if not _root_numeric.configure_owner(self, original_source_fields, _root_numeric): return {"success": false, "reason": "root_numeric_configuration_rejected"}
	if _root_call(&"create_original_owner_services", [_boot.assembly.source_domain_publication]) != true: return {"success": false, "reason": "root_source_services_missing"}
	_audio_primitives = required_owner_service(&"AudioPrimitives", ["service_state", "find_services_in_original_group_order", "classic_weapon_shape", "adopt_registered_service", "invoke_service", "reference_has_method"])
	if _audio_primitives == null: return {"success": false, "reason": "actual_audio_primitive_port_missing"}
	_enemy_audio_shared = _original_source_session.original_enemy_audio_shared_owner(_audio_primitives)
	if _enemy_audio_shared == null or _enemy_audio_shared.owner_thread_id() != _owner or not _enemy_audio_shared.original_handoff_applied(): return {"success": false, "reason": "persistent_source_audio_static_handoff_rejected"}
	_target_ring = TargetRing.new(source_text)
	var combat_log := required_owner_service(&"CombatLog", ["capture_enabled", "record"])
	var footprint_log := required_owner_service(&"SkillFootprintLog", ["capture_enabled", "record"])
	var loot_trace := required_owner_service(&"LootTrace", ["record"])
	if combat_log == null or footprint_log == null or loot_trace == null or not diagnostics.configure_original_logs(combat_log, footprint_log): return {"success": false, "reason": "original_log_services_missing"}
	loot = LootModel.new(profile._content_port, loot_trace, _boot.assembly.source_domain_publication.loot_trace_enabled)
	target_bound = TargetBound.new()
	if not target_bound.configure_owner_inputs(_boot.assembly.monster_inputs): return {"success": false, "reason": "target_bound_publication_rejected"}
	_full_ports = FullPorts.new(self)
	skill_combat = SkillCombat.new()
	if not skill_combat.configure(skill_actors, diagnostics, random, global_random, _full_ports, _full_ports): return {"success": false, "reason": "original_combat_port_configuration_rejected"}
	_ground_claims = GroundClaims.new(skill_actors, clock_ports)
	cast_presentation = required_owner_service(&"CasterPresentation", ["create_visual_model", "bind_projectile", "bind_ground", "redraw_cast", "projectile_audio_phase", "prepare_projectile_visual", "set_cast_y_sort", "create_fire_wall_cell", "fire_wall_animation_diagnostics", "activate_fire_wall_cells", "synchronize_fire_wall_cells", "redraw_ground_if_without_sprite", "prepare_ground_visual", "owns_visual_model", "enter_visual_model", "discard_visual_model", "owns_cast_model", "synchronize_cast_pose", "service_original_replies", "close_owner_presentation"])
	var caster_visual := required_owner_service(&"CasterVisual", ["is_runtime_ready", "profile", "visual_profile", "animation_duration", "render_policy"])
	if cast_presentation == null or caster_visual == null: return {"success": false, "reason": "original_caster_binding_missing"}
	if not install_original_interactable_owner(_root_numeric.original_interactable_loading_publication()): return {"success":false,"reason":"actual_interactable_Loading_publication_rejected"}
	casts = CastFactory.new()
	var binding := {"world": _full_ports, "actors": skill_actors, "visual": caster_visual, "presentation": cast_presentation,
		"clock": clock_ports, "rules": _full_ports, "random": random, "global_random": global_random, "profile": profile,
		"combat": skill_combat, "claims": _ground_claims}
	if not casts.configure(binding): return {"success": false, "reason": "original_cast_factory_rejected"}
	skills = FullSkill.new()
	if not skills.configure_full_ports({"world": _full_ports, "actors": skill_actors, "clock": clock_ports, "profile": profile,
		"input": input, "presentation": _full_ports, "casting": casts, "diagnostics": diagnostics, "engagement": engagement,
		"geometry": environment_factory.geometry_port, "combat": skill_combat, "spatial": spatial, "feature_runtime": _full_ports,
		"feature_target_bound": target_bound, "fields": skill_fields, "random": random, "execution": skills,
		"rules": _full_ports, "world_context": world_context, "time_domains": time_domains}): return {"success": false, "reason": "full_original_world_skill_ports_rejected"}
	for key: String in ["_world_skill_domain", "_feature_target_bound", "_ground_effect_manager"]:
		if not original_source_fields.has_source_field(key): return {"success": false, "reason": "original_source_object_slot_missing", "field": key}
	original_source_fields.bind_owner_field(&"_world_skill_domain", skills)
	original_source_fields.bind_owner_field(&"_feature_target_bound", target_bound)
	original_source_fields.bind_owner_field(&"_ground_effect_manager", casts.create_ground_manager(spatial, skill_combat))
	# Persistent Profile/receipt-child/Feature callbacks are supplied by the one
	# Session and merged globally with world callbacks, not rebound as Root children.
	if _root_call(&"initialize_source_domains", [_boot.assembly.source_domain_publication]) != true: return {"success": false, "reason": "original_root_initialization_rejected"}
	return {"success": not is_faulted()}

func is_inside_world() -> bool: return _source_scopes.game_root.is_inside_world()
func is_queued_for_retirement() -> bool: return _source_scopes.game_root.is_queued_for_retirement()
func original_scope_can_process(scope: RefCounted) -> bool:
	if scope == null or scope.owner_thread_id() != _owner or not scope.runtime_present or not scope.inside_world: return false
	match scope.effective_process_mode:
		1: return not profile_world_paused()
		2: return profile_world_paused()
		3: return true
		4: return false
	fault("unresolved_original_process_mode", {})
	return false
func enter_actor_group(handle: Object, group: StringName) -> bool: return _groups.add(handle, group)
func leave_actor_group(handle: Object, group: StringName) -> void: _groups.remove(handle.get_instance_id(), group)
func actor_source_publication(id: int) -> Dictionary: return _actor_source[id]
func actor_has_exact_legacy_player_contract(handle: Object) -> bool:
	return handle.kind() == &"player" and _actor_source[handle.get_instance_id()].get("exact_player_contract") == true
func actor_metadata_read(handle: Object, key: StringName, fallback: Variant = null) -> Variant:
	return _actor_metadata[handle.get_instance_id()].get(key, fallback) if handle.kind() == &"enemy" else handle.model().get_meta(key, fallback)
func actor_metadata_write(handle: Object, key: StringName, value: Variant) -> void:
	if handle.kind() == &"enemy": _actor_metadata[handle.get_instance_id()][key] = value
	else: handle.model().set_meta(key, value)
func actor_metadata_contains(handle: Object, key: StringName) -> bool: return _actor_metadata[handle.get_instance_id()].has(key) if handle.kind() == &"enemy" else handle.model().has_meta(key)
func actor_metadata_erase(handle: Object, key: StringName) -> void:
	if handle.kind() == &"enemy": _actor_metadata[handle.get_instance_id()].erase(key)
	else: handle.model().remove_meta(key)
func read_original_actor_property(handle: Object, key: StringName, access: RefCounted) -> Variant:
	var model: Object = handle.model()
	match key:
		&"global_position": return skill_actors.position_screen_px(model)
		&"velocity": return _actor_instances[handle.get_instance_id()].motion.velocity_screen_px_per_sec()
		&"owner_player": return access.resolve(model.owner_link)
		&"target": return model.target
	return model.get(key)
func write_original_actor_property(handle: Object, key: StringName, value: Variant, access: RefCounted) -> void:
	var model: Object = handle.model()
	match key:
		&"global_position": skill_actors.set_position_screen_px(model, value); return
		&"velocity": _actor_instances[handle.get_instance_id()].motion.set_velocity_screen_px_per_sec(value); return
		&"owner_player": model.owner_link = access.capture(value); return
		&"target": model.target = value; return
	model.set(key, value)
func actor_supports_original_method(handle: Object, method: StringName) -> bool:
	return handle.model().has_method(method) or method in [&"runtime_actor_id", &"parent_scope", &"is_inside_world", &"is_queued_for_retirement", &"can_process", &"is_in_group", &"read_meta", &"write_meta", &"contains_meta"]
func invoke_original_actor_method(handle: Object, method: StringName, arguments: Array, access: RefCounted) -> Variant:
	var model: Object = handle.model()
	var converted := arguments.duplicate(false)
	for i: int in range(converted.size()):
		if converted[i] is Access.ActorView:
			converted[i] = access.canonical(converted[i]).model()
	if not model.has_method(method):
		fault("original_actor_method_missing", {"method": method, "kind": handle.kind()})
		return null
	return model.callv(method, converted)

func connect_actor_exit_once(model: Object, callback: Callable, flags: int = CONNECT_ONE_SHOT) -> bool:
	return connect_original_actor_signal(model, &"tree_exiting", callback, flags)
func _emit_original_actor_tree_exiting(id: int) -> void:
	var connections: Array = _exit_callbacks.get(id, []).duplicate(false)
	# Pinned Object::emit_signal disconnects every one-shot before any callback.
	for bridge: OriginalSignalBridge in connections:
		if bridge.flags & CONNECT_ONE_SHOT: bridge.active = false
	for bridge: OriginalSignalBridge in connections: bridge.dispatch_tree_exit()
	_exit_callbacks.erase(id)
func defer_original_actor_callback(id: int, callback: Callable) -> void:
	_root_call(&"defer_original_actor_callback", [id, callback])
func enemy_visual_for_actor(id: int) -> Object: return _actor_visuals.get(id)
func enemy_original_presentation(id: int, method: StringName, arguments: Array) -> Variant:
	return _enemy_presentation[id].invoke_original(method, arguments)
func enemy_exit_at_original_checkpoint(instance: RefCounted) -> bool:
	var id: int = instance.handle.get_instance_id()
	if _actor_scopes[id].exit_callbacks_complete: return true
	var visual: RefCounted = _actor_visuals.get(id)
	if visual != null and not _service_scopes[_enemy_visual_services[id]].exit_callbacks_complete:
		emit_original_main_event(&"enemy_overhead_retire", [id])
		visual.retire()
		var visual_id: int = _enemy_visual_services[id]
		_service_scopes[visual_id].exit_at_original_checkpoint()
		if not service_registry.begin_service_retirement(visual_id): return false
	for timer_id: int in _node_timers.keys():
		var timer: RefCounted = _node_timers[timer_id]
		if _service_scopes[timer_id].parent_scope_id == id and not _service_scopes[timer_id].exit_callbacks_complete:
			var timer_scope: RefCounted = _service_scopes[timer_id]
			timer_scope.exit_at_original_checkpoint()
			if not service_registry.begin_service_retirement(timer_id): return false
	instance.model._exit_tree()
	_emit_original_actor_tree_exiting(id)
	_groups.remove_all(id)
	_exit_callbacks.erase(id)
	_actor_scopes[id].exit_at_original_checkpoint()
	instance.handle.set_world_membership(false)
	return true
func forget_actor_at_original_final_free(id: int) -> void:
	var lifecycle: RefCounted = _root_numeric.required_owner_service(&"WorldViewLifecycle")
	for timer_id: int in _node_timers.keys():
		if _service_scopes[timer_id].parent_scope_id == id:
			_service_scopes[timer_id].free_at_original_checkpoint()
			if not service_registry.final_free_service(timer_id):
				fault("original_node_timer_final_free_failed", {"id": timer_id})
				return
			_node_timers.erase(timer_id)
			forget_original_service_scope(timer_id)
	if _enemy_visual_services.has(id):
		var visual_id: int = _enemy_visual_services[id]
		_actor_visuals[id].release_original_actor_link_at_final_free()
		_service_scopes[visual_id].free_at_original_checkpoint()
		if not service_registry.final_free_service(visual_id):
			fault("original_visual_final_free_failed", {"id": visual_id})
			return
		forget_original_service_scope(visual_id)
		if not streaming.consume_original_visual_free(visual_id):
			fault("actual_original_visual_free_receipt_missing",{"id":visual_id})
			return
		_pending_initial_enemy_presentations.erase(visual_id)
		_actor_visuals.erase(id)
		_enemy_visual_services.erase(id)
	if lifecycle != null and lifecycle.get("_actor_free").has(id) and not lifecycle.consume_presented_actor_at_original_free(id):
		fault("actual_presented_actor_free_receipt_consume_failed",{"id":id})
		return
	_actor_scopes[id].free_at_original_checkpoint()
	_forget_callbacks_for_scope(_actor_scopes[id])
	_actor_instances.erase(id)
	_actor_source.erase(id)
	_actor_metadata.erase(id)
	if _enemy_presentation.has(id) and not _enemy_presentation[id].detach_actual_audio_observer_at_final_free():
		fault("actual_audio_observer_final_free_failed",{"id":id})
		return
	_enemy_presentation.erase(id)
	_actor_scopes.erase(id)
	_geometry_registered.erase(id)

func create_original_node_timer(parent_id: int, callback: Callable, one_shot: bool, process_callback: int) -> RefCounted:
	var scope := new_original_service_scope(&"node_timer", parent_id)
	if scope == null or not callback.is_valid(): return null
	var handle: Object = service_registry.allocate_service(&"node_timer", scope)
	if handle == null: return null
	var id: int = handle.get_instance_id()
	var timer := NodeTimer.new()
	if not timer.configure_owner(self, id, scope): return null
	timer.one_shot = one_shot
	timer.process_callback = process_callback
	timer.timeout.connect(callback)
	if not service_registry.bind_service_model(handle, timer): return null
	_service_scopes[id] = scope
	_service_models[id] = timer
	_node_timers[id] = timer
	scope.inside_world = true
	if not _root_numeric.original_service_child_entered(id,scope.parent_scope_id): return null
	timer.original_ready()
	for entry: Dictionary in [{"domain": &"H", "method": &"original_internal_physics", "priority": scope.physics_priority}, {"domain": &"P", "method": &"original_internal_process", "priority": scope.process_priority}]:
		var source: Variant = _root_call(&"original_service_callback_order", [id, entry.method])
		if not source is Dictionary or source.get("ok") != true: return null
		if not register_original_callback(timer, scope, entry.domain, entry.method, entry.priority, source.order, source.entry): return null
	return timer


func enemy_actor_reference(model: Object) -> Object:
	var handle: Object = actor_handle_for_model(model)
	return actor_access.view(handle) if handle != null else null
func _source_birth_publication(kind: StringName, template_key: StringName = &"") -> Dictionary:
	var value: Variant = _root_call(&"original_actor_birth_publication", [kind,template_key])
	if not value is Dictionary or value.get("contract_id") != "world.actor.original_birth.v1" or not value.get("scope") is Dictionary or not value.get("metadata") is Dictionary:
		fault("original_actor_birth_publication_missing", {"kind": kind})
		return {}
	for key: String in ["stable_combat_order", "physics_source_order", "process_source_order"]:
		if not value.get(key) is int or value[key] < 0: return {}
	for key: String in ["overhead_present", "visual_available", "damage_recording_enabled", "exact_player_contract"]:
		if not value.get(key) is bool: return {}
	return value
func create_unconfigured_enemy_model(inputs: RefCounted) -> Object:
	if inputs == null or inputs.get_script() != preload("res://scripts/features/contracts/published_monster_inputs.gd"): return null
	var published: Dictionary = inputs.view()
	var entry: Dictionary = published.entry
	var resolved: Dictionary = owner_services.ActorBodyPolicyScript.resolve_monster_body(int(entry.monster_id), str(entry.classification), published.body)
	if resolved.is_empty(): return null # Original Root will record admission failure.
	var source: Dictionary = _source_birth_publication(&"enemy")
	if source.is_empty(): return null
	var scope := Scope.new()
	if not scope.configure_source(source.scope, self) or scope.inside_world: return null
	var model := EnemyModel.new()
	# current_life reads the original empty constructor metadata before ports
	# have been configured. This sole table is then used throughout setup.
	var initial_meta: Dictionary = source.metadata
	var birth_metadata := BirthMetadata.new(self, initial_meta)
	model.metadata = birth_metadata
	var handle: Object = registry.reserve_unconfigured_actor(model, &"enemy", source.stable_combat_order)
	if handle == null: return null
	var id: int = handle.get_instance_id()
	_actor_metadata[id] = initial_meta
	var configuration: Dictionary = _loader.actor_motion_configuration(str(resolved.tier), "enemy_ground" if bool(published.behavior.get("worldCollision", true)) else "enemy_flying", Vector2.ZERO)
	configuration.safe_margin = 0.35 # exact Enemy source initialize_gameplay
	configuration.max_slides = 6
	configuration.screen_radius_px = float(resolved.screen_radius_px)
	var native: Object = native_world.create_actor(id, configuration)
	if native == null:
		registry.discard_reserved_actor(handle)
		_actor_metadata.erase(id)
		return null
	var projection: Dictionary = _loader.projection_profile(int(_world_identity.runtime_map_id))
	if projection.get("success") != true: return null
	var radius: float = preload("res://scripts/monster_unit_adapter.gd").footprint_radius_px_to_combat_radius_gu(float(resolved.screen_radius_px))
	var access := Access.new(registry, handle, self, _shared_actor_views, _shared_parent_scopes)
	var ports := EnemyPorts.new(self, registry, handle, model, _host, projection.screen_to_ground, radius, source.visual_available, source.damage_recording_enabled)
	ports.configure_enemy(access, scope, owner_services, _enemy_shared)
	var motion := EnemyMotion.new(self, native_world, native, ports, access, configuration)
	ports.bind_motion(motion)
	var instance := EnemyRuntime.new(self, model, handle, ports, motion)
	_actor_instances[id] = instance
	_actor_scopes[id] = scope
	if not handle.bind_original_temporal_scope(scope): return null
	source.safe_margin_gu = preload("res://scripts/monster_unit_adapter.gd").footprint_radius_px_to_combat_radius_gu(configuration.safe_margin)
	_actor_source[id] = source
	_enemy_presentation[id] = EnemyPresentation.new(self, model, id, _enemy_audio_shared, _audio_primitives, _target_ring)
	if not model.configure_ports(ports.bindings(motion)): return null
	return model
class BirthMetadata:
	extends RefCounted
	var values: Dictionary
	var core: WeakRef
	func _init(world: RefCounted, fields: Dictionary) -> void:
		core = weakref(world)
		values = fields
	func read(key: StringName, fallback: Variant = null) -> Variant: return values.get(key, fallback)
func commit_enemy_at_original_setup_life(id: int) -> bool:
	var instance: RefCounted = _actor_instances[id]
	if not registry.commit_reserved_actor(instance.handle) or not instance.model.bind_runtime_actor_id(id): return false
	return append_original_enemy_structural_header(&"ACTOR_HEADER",instance.handle)
func enter_spawned_enemy_at_original_child_boundary(model: Object) -> bool:
	var handle: Object = actor_handle_for_model(model)
	if handle == null or registry.resolve_runtime_actor(handle.get_instance_id()) != handle: return false
	var id: int = handle.get_instance_id()
	var scope: RefCounted = _actor_scopes[id]
	if scope.inside_world or not handle.set_world_membership(true): return false
	scope.inside_world = true
	scope.parent_scope_id = parent_scope_id()
	if not _root_numeric.original_actor_child_entered(id,_actor_source[id]): return false
	if not scope.apply_original_implicit_ready(_actor_source[id].source_callbacks): return _reject("original_enemy_implicit_READY_rejected",{})
	if not handle.set_runtime_qualification(parent_scope_id(),scope.can_process(),scope.physics_processing_enabled): return false
	model.initialize_gameplay()
	if is_faulted(): return false
	var source: Dictionary = _actor_source[id]
	return register_original_callback(model, scope, &"H", &"_physics_process", scope.physics_priority, source.physics_source_order, "EnemyActor._physics_process")
func discard_unconfigured_enemy_at_original_free(model: Object) -> bool:
	var handle: Object = actor_handle_for_model(model)
	if handle == null: return false
	var id: int = handle.get_instance_id()
	if registry.resolve_runtime_actor(id) != null:
		return retire_actor_at_original_free_checkpoint(id)
	if not native_world.retire_actor(id) or not registry.discard_reserved_actor(handle): return false
	_actor_instances[id].motion.detach()
	_actor_scopes[id].exit_at_original_checkpoint()
	forget_actor_at_original_final_free(id)
	return true


func actor_native_birth_registered(instance: RefCounted, context: Dictionary) -> bool:
	if not context.get("source_publication") is Dictionary: return _reject("generic_actor_source_birth_missing", {})
	var source: Dictionary = context.source_publication
	var scope := Scope.new()
	if not scope.configure_source(source.scope, self): return false
	var id: int = instance.handle.get_instance_id()
	_actor_instances[id] = instance
	_actor_scopes[id] = scope
	if not instance.handle.bind_original_temporal_scope(scope): return false
	_actor_source[id] = source
	_actor_metadata[id] = source.metadata
	for key: StringName in source.metadata: instance.model.set_meta(key, source.metadata[key])
	_actor_source[id].safe_margin_gu = preload("res://scripts/monster_unit_adapter.gd").footprint_radius_px_to_combat_radius_gu(float(context.motion_configuration.safe_margin))
	if instance.handle.kind() == &"player":
		if _player_id != 0: return _reject("second_player_authority_forbidden", {})
		_player_id = id
		if not original_source_fields.bind_owner_field(&"player", instance.model): return false
	return true
func _character_birth_context(kind: StringName, source: Dictionary, tier: String) -> Dictionary:
	var projection: Dictionary = _loader.projection_profile(int(_world_identity.runtime_map_id))
	if projection.get("success") != true: return {}
	var configuration: Dictionary = _loader.actor_motion_configuration(tier, String(kind), source.position_screen_px)
	if configuration.is_empty(): return {}
	return {"world_core": self, "registry": registry, "host": _host, "native_world": native_world, "profile": profile,
		"content": content, "action_timing": action_timing, "screen_to_ground": projection.screen_to_ground,
		"ground_to_screen": projection.ground_to_screen, "motion_configuration": configuration,
		"life_generation": int(source.scope.life_generation), "stable_combat_order": int(source.stable_combat_order),
		"parent_scope_id": int(source.scope.parent_scope_id), "can_process": bool(source.scope.can_process),
		"physics_processing_enabled": bool(source.scope.physics_processing_enabled), "combat_radius_gu": float(source.combat_radius_gu),
		"visual_available": bool(source.visual_available), "damage_recording_enabled": bool(source.damage_recording_enabled),
		"combat_contract_sha256": _boot.assembly.combat_contract_sha256, "source_publication": source,
		"hc_world_skill_preflight": Callable(skills, "_hc_skill_preflight"),
		"hc_action_configuration_provider": Callable(skills, "_capture_action_configuration"),
		"hc_melee_configuration_provider": Callable(skills, "_capture_melee_configuration"),
		"hc_action_configuration_identity": Callable(skills, "_action_configuration_identity")}
func create_player_at_original_child_boundary(source: Dictionary) -> Object:
	if _player_id != 0 or not source.get("position_screen_px") is Vector2 or not source.get("combat_radius_gu") is float: return null
	var context: Dictionary = _character_birth_context(&"player", source, "player")
	if context.is_empty(): return null
	var made: Dictionary = ActorFactory.create_player(context)
	if made.get("ok") != true:
		fault("original_player_factory_rejected", made)
		return null
	var instance: RefCounted = made.runtime
	var scope: RefCounted = _actor_scopes[instance.handle.get_instance_id()]
	# Player has no _process callback. Its genuine PlayerVisual child owns P.
	if not register_original_callback(instance, scope, &"H", &"step_physics", scope.physics_priority, source.physics_source_order, "PlayerCharacter._physics_process"): return null
	return instance.model
func create_summon_model(stable_skill_id: String) -> Object:
	var tier: String = owner_services.ActorBodyPolicyScript.summon_tier("skeleton" if stable_skill_id == "taoist.summon_skeleton" else "divine_beast")
	if stable_skill_id not in ["taoist.summon_skeleton", "taoist.summon_divine_beast"] or tier.is_empty(): return null
	var source: Dictionary = _source_birth_publication(&"summon")
	if source.is_empty(): return null
	source.combat_radius_gu = preload("res://scripts/monster_unit_adapter.gd").footprint_radius_px_to_combat_radius_gu(owner_services.ActorBodyPolicyScript.tier_screen_radius_px(StringName(tier)))
	var context: Dictionary = _character_birth_context(&"summon", source, tier)
	if context.is_empty(): return null
	var made: Dictionary = ActorFactory.create_unconfigured_summon(context)
	if made.get("ok") != true:
		fault("original_summon_constructor_rejected", made)
		return null
	return made.runtime.model
func allocate_cast_model(model: RefCounted, kind: StringName) -> Object:
	if kind not in [&"projectile", &"field"] or actor_handle_for_model(model) != null: return null
	var template_key: StringName = kind
	if kind==&"projectile" and model.get_script()==preload("res://scripts/gameplay/world/world_enemy_projectile_effect_model.gd"): template_key=&"enemy_projectile"
	if kind == &"field":
		if model.get_script() == preload("res://scripts/gameplay/world/world_skill_fire_wall_model.gd"): template_key = &"fire_wall"
		elif model.get_script()==preload("res://scripts/gameplay/world/world_enemy_target_magic_model.gd"): template_key=&"enemy_target_magic"
		elif model.get_script() != preload("res://scripts/gameplay/world/world_skill_ground_model.gd"):
			fault("unregistered_field_source_template",{}); return null
	var source: Dictionary = _source_birth_publication(kind,template_key)
	if source.is_empty(): return null
	var scope := Scope.new()
	if not scope.configure_source(source.scope, self) or scope.inside_world: return null
	var handle: Object = registry.register_actor(model, scope.life_generation, kind, source.stable_combat_order)
	if handle == null or not handle.set_world_membership(false): return null
	var id: int = handle.get_instance_id()
	_cast_models[id] = model
	_actor_scopes[id] = scope
	if not handle.bind_original_temporal_scope(scope): return null
	_actor_source[id] = source
	_actor_metadata[id] = source.metadata
	return handle
func register_cast_model(model: Object) -> void:
	if cast_presentation.owns_visual_model(model):
		if not cast_presentation.enter_visual_model(model): fault("original_caster_display_entry_failed", {})
		return
	var handle: Object = actor_handle_for_model(model)
	if handle == null:
		fault("original_cast_child_identity_missing", {})
		return
	var id: int = handle.get_instance_id()
	var scope: RefCounted = _actor_scopes[id]
	if scope.inside_world or not handle.set_world_membership(true):
		fault("original_cast_double_tree_entry", {})
		return
	scope.inside_world = true
	scope.parent_scope_id = parent_scope_id()
	handle.set_runtime_qualification(parent_scope_id(), scope.can_process(), scope.physics_processing_enabled)
	if not _root_numeric.original_actor_child_entered(id,_actor_source[id]): return
	if handle.kind() == &"summon": model.initialize_gameplay()
	elif model.has_method("initialize_gameplay"): model.initialize_gameplay()
	elif model.has_method("_ready"): model._ready()
	var source: Dictionary = _actor_source[id]
	if handle.kind() == &"summon":
		var instance: RefCounted = _actor_instances[id]
		register_original_callback(instance,scope,&"H",&"step_physics",scope.physics_priority,source.physics_source_order,"SummonActor._physics_process")
		register_original_callback(instance,scope,&"P",&"step_process",scope.process_priority,source.process_source_order,"SummonActor._process")
	elif model.has_method("_physics_process"): register_original_callback(model, scope, &"H", &"_physics_process", scope.physics_priority, source.physics_source_order, String(handle.kind()) + "._physics_process")
	if model.has_method("_process"): register_original_callback(model, scope, &"P", &"_process", scope.process_priority, source.process_source_order, String(handle.kind()) + "._process")
func discard_cast_birth(model: Object) -> void:
	if cast_presentation.owns_visual_model(model):
		if not cast_presentation.discard_visual_model(model): fault("original_caster_display_discard_failed", {})
		return
	var handle: Object = actor_handle_for_model(model)
	if handle == null:
		fault("discard_original_cast_identity_missing", {})
		return
	retire_actor_at_original_free_checkpoint(handle.get_instance_id())
func queue_cast_retirement(model: Object) -> void:
	var handle: Object = actor_handle_for_model(model)
	if handle == null or not queue_actor_retirement(handle.get_instance_id()): fault("original_cast_queue_retirement_failed", {})
func enter_cast_group(model: Object, group: StringName) -> void:
	enter_actor_group(actor_handle_for_model(model), group)
func set_cast_physics_processing(model: Object, enabled: bool) -> void:
	var handle: Object = actor_handle_for_model(model)
	var scope: RefCounted = _actor_scopes[handle.get_instance_id()]
	scope.physics_processing_enabled = enabled
	handle.set_processing_qualification(scope.can_process(), enabled)
func retire_actor_at_original_free_checkpoint(id: int) -> bool:
	var handle: Object = registry.resolve_runtime_actor(id)
	if handle == null: return false
	if _actor_instances.has(id):
		var instance: RefCounted = _actor_instances[id]
		if handle.kind() == &"enemy":
			if not enemy_exit_at_original_checkpoint(instance) or not _prepare_original_presented_actor_final_free(id): return false
			if not instance.final_retire(): return false
			_actor_retirements.erase(id)
			return true
		if not _root_call(&"exit_generic_actor_at_original_checkpoint", [instance]): return false
		if handle.kind() == &"player" and not _prepare_original_presented_actor_final_free(id): return false
		release_actor_signal_bridges_at_original_final_free(id, instance.model)
		if not instance.final_retire(): return false
		forget_actor_at_original_final_free(id)
	else:
		var model: RefCounted = _cast_models[id]
		if not exit_original_actor_scope_at_checkpoint(id): return false
		release_actor_signal_bridges_at_original_final_free(id, model)
		if not registry.retire_runtime_actor(id): return false
		_actor_scopes[id].free_at_original_checkpoint()
		_forget_callbacks_for_scope(_actor_scopes[id])
		_cast_models.erase(id)
		_actor_scopes.erase(id)
		_actor_source.erase(id)
		_actor_metadata.erase(id)
	_actor_retirements.erase(id)
	return true
func feature_actor_commit_projection(handle: Object) -> Dictionary:
	if not feature_actor_in_owner_scope(handle): return {"success": false}
	var model: Object = handle.model()
	if model.get("runtime_map_id") != int(_world_identity.runtime_map_id) or not model.has_method("try_screen_position_px_to_ground_position_gu"): return {"success": false}
	return model.try_screen_position_px_to_ground_position_gu(skill_actors.position_screen_px(model))
func enqueue_feature_presentation(port_id: String, ordinal: int, kind: String, effect_handle: String, value: Dictionary) -> bool:
	return _journal.append({"kind": "feature_presentation", "port_id": port_id, "producer_ordinal": ordinal, "operation": kind, "effect_handle": effect_handle, "value": value, "source_site": _source_site})
func feature_cue_is_supported(cue_id: String, policy: String) -> bool:
	var table: Variant = _boot.assembly.source_domain_publication.get("feature_cue_readiness")
	if not table is Dictionary or not table.get(cue_id) is Dictionary:
		fault("actual_feature_cue_readiness_publication_missing", {"cue_id": cue_id})
		return false
	var row: Dictionary = table[cue_id]
	if row.get("policy") != policy or not row.get("available") is bool:
		fault("actual_feature_cue_readiness_publication_invalid", {"cue_id": cue_id})
		return false
	return row.available
func feature_action_resource_lease() -> RefCounted: return profile._feature_port._source._feature_resource_lease
func feature_child_plan_context(release_id: String) -> Dictionary:
	return {"release_id": release_id, "runtime_map_id": int(_world_identity.runtime_map_id), "screen_to_ground_position_px": Callable(skills, "_canonical_screen_px_to_ground_gu"), "ground_gu_to_screen_position_px": Callable(skills, "_canonical_ground_gu_to_screen_px")}
func feature_child_query_actor_ids(plan: Dictionary) -> Dictionary:
	var query: Dictionary = skills._aoe_spell_query_plan(plan.skill_id, [], plan.gameplay_actions[0], {}, plan.canonical_snapshot, plan.canonical_snapshot.center_ground_gu, {})
	if not skills._aoe_plan_is_ready(query) or not skills._aoe_query_enemy_candidates_aabb(query, query.get("ground_aabb", Rect2()), false): return {"success": false}
	var targets: Array = []
	var ids: Array[int] = []
	for enemy: Object in skills._aoe_candidate_scratch:
		if enemy.current_hp > 0 and not skill_actors.is_queued_for_retirement(enemy) and skills._aoe_validated_snapshot_intersects(query, enemy): skills._aoe_insert_by_instance_id(targets, ids, enemy)
	return {"success": true, "actor_ids": ids}
func execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array, source: Object, resources_lease: RefCounted) -> Dictionary:
	return skills._execute_feature_child_action(request, ticket, bindings, source.model() if source != null else null, resources_lease)
func canonical_summon_follow_landing_plan(id: int) -> Dictionary: return skills._canonical_summon_follow_landing_plan(registry.resolve_runtime_actor(id).model())
func capture_follow_landing_authority(id: int) -> RefCounted: return _root_call(&"capture_follow_landing_authority", [registry.resolve_runtime_actor(id).model()])
func register_pending_main_pet_arrival(authority: RefCounted, id: int) -> bool: return _root_call(&"register_pending_main_pet_arrival", [registry.resolve_runtime_actor(id).model(), authority]) == true
func on_player_stats_changed(id: int, hp: int, maximum: int) -> void:
	_observe_original_signal_subscription(id, &"stats_changed")
func on_player_resources_changed(id: int, hp: int, max_hp: int, mp: int, max_mp: int) -> void:
	# Original Root has no resources_changed subscriber. The source port
	# publishes the real resource fact through its existing _fact call.
	assert(registry.resolve_runtime_actor(id) != null)
func on_actor_passive_wakeup_changed(id: int) -> void:
	_observe_original_signal_subscription(id, &"passive_wakeup_changed")
func on_player_attack_requested(id: int, _model: Object, origin: Vector2, direction: Vector2, damage: int) -> void:
	_observe_original_signal_subscription(id, &"attack_requested")
func on_player_skill_requested(id: int, _model: Object, skill: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	_observe_original_signal_subscription(id, &"skill_requested")
func on_player_death_requested(id: int) -> void:
	_observe_original_signal_subscription(id, &"death_requested")
func on_player_movement_performed(id: int, position: Vector2, facing: Vector2) -> void:
	_observe_original_signal_subscription(id, &"movement_performed")
func on_player_skill_cast_started(id: int, skill: String) -> void:
	_observe_original_signal_subscription(id, &"skill_cast_started")
func on_player_warrior_skill_state_changed(id: int, skill: String, enabled: bool, message: String) -> void:
	_observe_original_signal_subscription(id, &"warrior_skill_state_changed")
func on_summon_state_changed(id: int, previous: int, current: int) -> void:
	_observe_original_signal_subscription(id, &"summon_state_changed")

func prepare_profile_feature_directory(path: String) -> Dictionary:
	return await required_owner_service(&"ContentLayers", ["prepare_resource_directory"]).prepare_resource_directory(path)
func gameplay_input_is_enabled() -> bool:
	# Original GameRoot:806 getter, using the same source scalar and model.
	return bool(original_source_fields.read_source_field(&"_player_input_enabled")) and skill_actors.is_runtime_present(skills.player) and not skills.player._dead and skills.player.current_hp > 0 and not skills.player.combat_transition_is_active()
func feature_publication_scope() -> Dictionary: return skills.feature_publication_scope()
func feature_world_capacity_bound() -> Dictionary: return skills.feature_world_capacity_bound()
func create_unconfigured_loot_model() -> Object:
	var factory := required_owner_service(&"LootActorFactory", ["create_unconfigured"])
	if factory == null: return null
	var source: Dictionary = _source_birth_publication(&"loot")
	if source.is_empty(): return null
	var scope := Scope.new()
	if not scope.configure_source(source.scope, self) or scope.inside_world: return null
	var model: RefCounted = factory.create_unconfigured(self)
	if model == null or not model.has_method("bind_runtime_actor_id"): return null
	var handle: Object = registry.register_actor(model, scope.life_generation, &"loot", source.stable_combat_order)
	if handle == null or not handle.set_world_membership(false) or not model.bind_runtime_actor_id(handle.get_instance_id()): return null
	var id: int = handle.get_instance_id()
	_cast_models[id] = model
	_actor_scopes[id] = scope
	if not handle.bind_original_temporal_scope(scope): return null
	_actor_source[id] = source
	_actor_metadata[id] = source.metadata
	return model
func enter_spawned_loot_at_original_child_boundary(model: Object) -> bool:
	var handle: Object = actor_handle_for_model(model)
	if handle == null or handle.kind() != &"loot": return false
	register_cast_model(model)
	return not is_faulted()
func runtime_actor_id_for_model(model: Object) -> int:
	var handle: Object = actor_handle_for_model(model)
	return handle.get_instance_id() if handle != null else 0

func read_enemy_observer_field(id: int, key: StringName) -> Variant:
	assert(key in [&"_audio_attack_start_accepted", &"_audio_attack_frame_ready"])
	return _enemy_presentation[id].get(key)
func write_enemy_observer_field(id: int, key: StringName, value: Variant) -> void:
	assert(key in [&"_audio_attack_start_accepted", &"_audio_attack_frame_ready"] and value is bool)
	_enemy_presentation[id].set(key, value)
func activate_enemy_visual_at_original_ready(id: int, clock: Callable, title: String, boss: bool, hp: int, maximum: int) -> void:
	if _actor_visuals.has(id):
		fault("duplicate_original_enemy_visual_birth", {"actor": id})
		return
	var instance: RefCounted = _actor_instances[id]
	var scope := new_original_service_scope(&"monster_visual", id)
	if scope == null: return
	var handle: Object = service_registry.allocate_service(&"monster_visual", scope)
	if handle == null: return
	var service_id: int = handle.get_instance_id()
	_service_scopes[service_id] = scope
	var visual := EnemyVisual.new()
	var source_frames := required_owner_service(&"SourceFrames", ["profile_for_id", "request_profile"])
	var projectile_visual := required_owner_service(&"ProjectileVisual", ["prewarm_for_monster_id"])
	var viewport := required_owner_service(&"VisualViewport", ["viewport_snapshot"])
	if source_frames == null or projectile_visual == null or viewport == null: return
	var bindings := {"SourceFrames": source_frames, "ProjectileVisual": projectile_visual, "MonsterIdentityScript": owner_services.MonsterIdentityScript,
		"synchronous_visual_loading_for_tests":_boot.assembly.source_domain_publication.synchronous_monster_visual_loading_for_tests,
		"RuntimeDiagnostics": diagnostics, "Engine": clock_ports, "Time": clock_ports, "PlayerState": _profile_services,
		"presentation": visual_ports, "catalog": visual_ports, "resources": visual_ports, "coordinator": streaming, "viewport": viewport}
	if not visual.configure_owner(ActorLink.capture(registry, instance.handle), handle, instance.ports.access, bindings, service_registry, scope) or not service_registry.bind_service_model(handle, visual):
		fault("original_enemy_visual_configuration_rejected", {"actor": id})
		return
	_service_models[service_id] = visual
	_actor_visuals[id] = visual
	_enemy_visual_services[id] = service_id
	# This source child is constructed/entered before the overhead child.
	visual._combat_clock_s = clock
	scope.inside_world = true
	if not _root_numeric.original_service_child_entered(service_id,scope.parent_scope_id): return
	if not _apply_original_service_implicit_ready(&"monster_visual",scope): return
	if not append_original_enemy_structural_header(&"VISUAL_HEADER",instance.handle,service_id): return
	if resources.live_resource_phase():
		_pending_initial_enemy_presentations[service_id] = {
			"actor_identity":instance.handle.identity().duplicate(true),
			"service_identity":handle.identity().duplicate(true),
			"actor_handle":weakref(instance.handle),"service_handle":weakref(handle),"visual":weakref(visual)}
	visual.initialize_at_original_ready()
	_trace_actual_initial_enemy_binding("pending",id,service_id,{})
	if resources.live_resource_phase() and not original_enemy_presentation_binding_pending(id):
		fault("initial_enemy_presentation_observation_not_retained",{"actor":id,"service_id":service_id})
		return
	var order: Variant = _root_call(&"original_service_callback_order", [service_id, &"_process"])
	if not order is Dictionary or order.get("ok") != true: return
	register_original_callback(visual, scope, &"P", &"original_process", scope.process_priority, order.order, order.entry)
	var overhead_context: Dictionary=preload("res://scripts/gameplay/presentation/enemy_overhead_birth_context.gd").capture_original(instance.handle,instance.model)
	if overhead_context.is_empty(): fault("actual_original_enemy_overhead_context_missing",{"actor":id}); return
	emit_original_main_event(&"enemy_overhead_create", [id, title, boss, hp, maximum, overhead_context])
	instance.model.refresh_name_label_position()

func release_enemy_links_at_original_final_free(model: Object) -> void:
	release_actor_signal_bridges_at_original_final_free(runtime_actor_id_for_model(model), model)
	# Original Node destructor ends its own outgoing references. Accepted
	# external ActorRefs still retain retired storage until their own release.
	for field: StringName in [&"_target_link", &"_primary_target_link", &"_pending_target_link", &"_last_damaging_pet", &"_attack_ab_pending_target"]:
		var link: Variant = model.get(field)
		if link != null:
			assert(link is RefCounted and link.get_script() == ActorLink)
			link.dispose()
			model.set(field, null)

func _invoke_root_entry(domain: StringName, method: StringName, arguments: Array) -> bool:
	var prior_faults: int = _faults.size()
	var cleanup: bool = _host.current_clock_frame().get("closing_session") == true
	if not _begin_original_entry(domain, String(method)): return false
	var completed: Variant = _root_call(method, arguments)
	var ended: bool = _finish_original_entry()
	if not ended or (completed is bool and not completed): return false
	return _faults.size() == prior_faults if cleanup else not is_faulted()
func _forget_callbacks_for_scope(scope: RefCounted) -> void:
	for i: int in range(_callbacks.size() - 1, -1, -1):
		if is_same(_callbacks[i].scope, scope): _callbacks.remove_at(i)

class OriginalSignalBridge:
	extends RefCounted
	var core: WeakRef
	var receiver: WeakRef
	var method: StringName
	var bound_values: Array = []
	var signal_name: StringName
	var signal_callable: Callable
	var original_callback: Callable
	var flags := 0
	var active := true
	var actor_id := 0
	func normalize(value: Variant) -> Variant:
		if value is Access.ActorView:
			var record: Object = value.record()
			return record.model() if record != null else null
		return value
	func invoke(arguments: Array) -> void:
		var target: Object = receiver.get_ref()
		if target == null:
			if flags & CONNECT_ONE_SHOT: release_bound_links()
			return # original receiver destruction disconnects it
		var converted: Array = []
		for value: Variant in arguments: converted.append(normalize(value))
		for value: Variant in bound_values:
			converted.append(value.borrow_model() if value is RefCounted and value.get_script() == ActorLink else value)
		target.callv(method, converted)
		if flags & CONNECT_ONE_SHOT:
			active = false
			release_bound_links()
	func dispatch(arguments: Array) -> void: invoke(arguments)
	func dispatch_tree_exit() -> void:
		if flags & CONNECT_DEFERRED:
			Callable(self, "invoke").call_deferred([])
		else: invoke([])
	func emit_zero() -> void: dispatch([])
	func emit_three(a: Variant, b: Variant, c: Variant) -> void: dispatch([a, b, c])
	func emit_one(a: Variant) -> void: dispatch([a])
	func emit_two(a: Variant, b: Variant) -> void: dispatch([a, b])
	func emit_four(a: Variant, b: Variant, c: Variant, d: Variant) -> void: dispatch([a, b, c, d])
	func release_bound_links() -> void:
		for value: Variant in bound_values:
			if value is RefCounted and value.get_script() == ActorLink: value.dispose()
		bound_values.clear()
		original_callback = Callable()
func connect_original_actor_signal(model: Object, signal_name: StringName, callback: Callable, flags: int = 0) -> bool:
	var handle: Object = actor_handle_for_model(model)
	if handle == null or (signal_name != &"tree_exiting" and not model.has_signal(signal_name)) or not callback.is_valid() or callback.get_object() == null: return false
	if flags & ~(CONNECT_DEFERRED | CONNECT_ONE_SHOT): return _reject("original_actor_signal_flags_not_source_mapped", {"flags": flags})
	if callback.get_object() is Node or callback.get_object() is Resource: return _reject("original_actor_signal_main_receiver", {})
	if original_actor_signal_is_connected(model, signal_name, callback): return false
	var arity := 0 if signal_name == &"tree_exiting" else -1
	for info: Dictionary in model.get_signal_list():
		if info.name == signal_name: arity = info.args.size()
	if arity not in [0, 1, 2, 3, 4]: return _reject("original_actor_signal_arity_not_mapped", {"signal": signal_name, "arity": arity})
	var bridge := OriginalSignalBridge.new()
	bridge.core = weakref(self)
	bridge.receiver = weakref(callback.get_object())
	bridge.method = callback.get_method()
	bridge.signal_name = signal_name
	bridge.original_callback = callback
	bridge.flags = flags
	bridge.actor_id = handle.get_instance_id()
	for value: Variant in callback.get_bound_arguments():
		if value is Object and actor_handle_for_model(value) != null:
			var link: RefCounted = ActorLink.capture(registry, actor_handle_for_model(value))
			if link == null: return false
			bridge.bound_values.append(link)
		else: bridge.bound_values.append(value)
	bridge.signal_callable = Callable(bridge, ["emit_zero", "emit_one", "emit_two", "emit_three", "emit_four"][arity])
	if signal_name == &"tree_exiting":
		if not _exit_callbacks.has(bridge.actor_id): _exit_callbacks[bridge.actor_id] = []
		_exit_callbacks[bridge.actor_id].append(bridge)
	elif model.connect(signal_name, bridge.signal_callable, flags) != OK:
		bridge.release_bound_links()
		return false
	var id: int = handle.get_instance_id()
	if not _actor_signal_bridges.has(id): _actor_signal_bridges[id] = []
	_actor_signal_bridges[id].append(bridge)
	return true
func original_actor_signal_is_connected(model: Object, signal_name: StringName, callback: Callable) -> bool:
	var handle: Object = actor_handle_for_model(model)
	if handle == null: return false
	for bridge: OriginalSignalBridge in _actor_signal_bridges.get(handle.get_instance_id(), []):
		if bridge.signal_name == signal_name and bridge.original_callback == callback:
			var connected: bool = bridge.active if signal_name == &"tree_exiting" else model.is_connected(signal_name, bridge.signal_callable)
			if connected: return true
	return false
func release_actor_signal_bridges_at_original_final_free(id: int, model: Object) -> void:
	for bridge: OriginalSignalBridge in _actor_signal_bridges.get(id, []):
		if bridge.signal_name != &"tree_exiting" and model.is_connected(bridge.signal_name, bridge.signal_callable): model.disconnect(bridge.signal_name, bridge.signal_callable)
		bridge.release_bound_links()
	_actor_signal_bridges.erase(id)
	_exit_callbacks.erase(id)

func _observe_original_signal_subscription(id: int, signal_name: StringName) -> void:
	# This port observes existing source signals. A newborn model can emit from
	# _ready before the original Root connect statement even while the world
	# is active. Root's actual connect statements own subscription ordering.
	var instance: RefCounted = _actor_instances.get(id)
	if instance == null or not instance.model.has_signal(signal_name):
		fault("original_actor_signal_observation_invalid", {"actor": id, "signal": signal_name})

## Narrow Root phase ABI; all lifetime reads address the existing Scope maps.
func original_source_scope(name: String) -> RefCounted:
	return _source_scopes.get(name)
func original_feature_resource_coordinator() -> RefCounted: return _feature_resources
func original_source_session() -> RefCounted: return _original_source_session
func original_service_id_for_model(model: RefCounted) -> int:
	for id: int in _service_models:
		if is_same(_service_models[id],model): return id
	return 0
func original_callback_runtime_id(target: RefCounted) -> int:
	for id: int in _actor_instances:
		if is_same(_actor_instances[id],target) or is_same(_actor_instances[id].model,target): return id
	for id: int in _cast_models:
		if is_same(_cast_models[id],target): return id
	return original_service_id_for_model(target)

func attach_original_process_service(kind: StringName, model: RefCounted, callback: StringName, mapped: StringName) -> bool:
	var scope: RefCounted = new_original_service_scope(kind,parent_scope_id())
	if scope == null: return false
	var handle: Object = service_registry.allocate_service(kind,scope)
	if handle == null or not service_registry.bind_service_model(handle,model): return false
	var id: int = handle.get_instance_id()
	_service_scopes[id] = scope
	_service_models[id] = model
	scope.inside_world = true
	if not _root_numeric.original_service_child_entered(id,scope.parent_scope_id): return false
	if not _apply_original_service_implicit_ready(kind,scope): return false
	var order: Dictionary = _root_numeric.original_service_callback_order(id,callback)
	if order.get("ok") != true or order.get("domain") != "P": return _reject("original_process_service_order_missing",order)
	return register_original_callback(model,service_registry.process_scope_for_service(id),&"P",mapped,scope.process_priority,order.order,order.entry)

func prepare_original_player_ready(instance: RefCounted) -> bool:
	var id: int = instance.handle.get_instance_id()
	if not _actor_scopes.has(id) or instance.handle.kind() != &"player": return false
	if not _root_numeric.original_player_pre_ready_connections(instance.model): return false
	var scope: RefCounted = _actor_scopes[id]
	if scope.inside_world or not instance.handle.set_world_membership(true): return false
	scope.parent_scope_id = parent_scope_id()
	scope.inside_world = true
	if not _root_numeric.original_actor_child_entered(id,_actor_source[id]): return false
	if not scope.apply_original_implicit_ready(_actor_source[id].source_callbacks): return _reject("original_player_implicit_READY_rejected",{})
	if not instance.handle.set_runtime_qualification(parent_scope_id(),scope.can_process(),scope.physics_processing_enabled): return false
	return true

func _apply_original_service_implicit_ready(kind: StringName, scope: RefCounted) -> bool:
	var template: Variant = _boot.assembly.source_domain_publication.root_phase.source_tree.service_callback_templates.get(String(kind))
	if not template is Dictionary or not template.get("callbacks") is Dictionary or not scope.apply_original_implicit_ready(template.callbacks): return _reject("original_service_implicit_READY_rejected",{"kind":kind})
	return true

func queued_original_scope_ids() -> Dictionary:
	var actors: Array[int] = []
	var services: Array[int] = []
	for id: int in _actor_scopes:
		if _actor_scopes[id].queued_for_retirement: actors.append(id)
	for id: int in _service_scopes:
		if _service_scopes[id].queued_for_retirement: services.append(id)
	return {"actors":actors,"services":services,"delete_queue":_original_delete_queue.duplicate(true)}

var _last_original_source_delete_checkpoint: Dictionary = {}
func original_source_delete_checkpoint_receipt() -> Dictionary:
	assert(OS.get_thread_caller_id()==_owner)
	return _last_original_source_delete_checkpoint.duplicate(true)
func is_original_world_closed() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	return _closed
func flush_original_delete_queue_at_checkpoint(domain: StringName) -> bool:
	if domain not in [&"H",&"P"]: return false
	var prior_faults: int = _faults.size()
	var actual_frame: Dictionary=current_clock_frame()
	var closing_service: bool = domain == &"P" and actual_frame.get("closing_session") == true and actual_frame.get("phase") == "P_CLOSE_SERVICE" and actual_frame.get("source_boundary") == "NODE_PROCESS_SERVICE" and actual_frame.get("closing_process_publication",{}).get("phase") == "NODE_PROCESS_SERVICE"
	if actual_frame.get("phase")!=("H_AFTER_TIMERS" if domain==&"H" else "P_AFTER_TIMERS") and not closing_service: return false
	var completed: Array[Dictionary]=[]
	# The pinned delete queue drains FIFO to empty, including original nested
	# queue_delete calls from destructors. A failed accepted obligation leaves
	# the exact front entry and all remaining original objects alive.
	while not _original_delete_queue.is_empty():
		var entry: Dictionary = _original_delete_queue.front()
		var id: int = entry.id
		if _actor_scopes.has(id) or _service_scopes.has(id):
			if not _exit_original_subtree(id): return false
			if not _free_original_subtree(id):
				var debt: Dictionary = _capture_original_delete_front_resource_debt(id)
				if _faults.size() != prior_faults or debt.is_empty(): return false
				_last_original_source_delete_checkpoint = {"success":true,"frame":actual_frame,"domain":domain,"freed_fifo":completed,"remaining":_original_delete_queue.size(),"retained_front":entry.duplicate(true),"deferred_final_free":debt}
				return verify_original_deferred_final_free(_last_original_source_delete_checkpoint)
		completed.append(entry.duplicate(true))
		_original_delete_queue.pop_front()
	_last_original_source_delete_checkpoint={"success":true,"frame":actual_frame,"domain":domain,"freed_fifo":completed,"remaining":_original_delete_queue.size()}
	return true

func exit_generic_actor_scope_at_original_checkpoint(instance: RefCounted) -> bool:
	var id: int = instance.handle.get_instance_id()
	if not _actor_scopes.has(id): return false
	var scope: RefCounted = _actor_scopes[id]
	if scope.exit_callbacks_complete: return true
	if instance.handle.kind() == &"player":
		if not instance.apply_original_world_exit_once(): return false
	_emit_original_actor_tree_exiting(id)
	_groups.remove_all(id)
	if not instance.handle.set_world_membership(false): return false
	return scope.exit_at_original_checkpoint()

func exit_original_actor_scope_at_checkpoint(id: int) -> bool:
	if not _actor_scopes.has(id): return false
	var scope: RefCounted = _actor_scopes[id]
	if scope.exit_callbacks_complete: return true
	if _actor_instances.has(id):
		var instance: RefCounted = _actor_instances[id]
		if instance.handle.kind() == &"enemy": return enemy_exit_at_original_checkpoint(instance)
		return exit_generic_actor_scope_at_original_checkpoint(instance)
	if not _cast_models.has(id): return _reject("original_actor_exit_model_missing",{"id":id})
	var model: RefCounted = _cast_models[id]
	if model.has_method("_exit_tree"): model._exit_tree()
	if model.has_method("close_effect"): model.close_effect()
	elif not _root_numeric.close_loot_at_original_free(model): return false
	_emit_original_actor_tree_exiting(id)
	_groups.remove_all(id)
	var handle: Object = registry.resolve_runtime_actor(id)
	if handle == null or not handle.set_world_membership(false): return false
	return scope.exit_at_original_checkpoint()

func _exit_original_service_at_checkpoint(id: int) -> bool:
	if not _service_scopes.has(id): return false
	var scope: RefCounted = _service_scopes[id]
	if scope.exit_callbacks_complete: return true
	var handle: Object = service_registry.resolve_service(id)
	if handle == null: return false
	var model: RefCounted = _service_models[id]
	match handle.kind():
		&"polygon_pursuit_driver",&"path_scheduler": return paths.retire_at_original_exit(id)
		&"monster_visual":
			model.retire()
			# End presentation responsibility at original exit only. The binding
			# FIFO, accepted tickets and their cleanup keep their original owners.
			_pending_initial_enemy_presentations.erase(id)
		&"node_timer": model.stop()
		&"m30_summon_queue": pass # original script has no _exit_tree body
		&"player_visual": pass # original PlayerVisual has no _exit_tree body
		&"loot_runtime_manager": model.close()
		_: return _reject("original_service_exit_algorithm_missing",{"id":id,"kind":handle.kind()})
	return scope.exit_at_original_checkpoint() and service_registry.begin_service_retirement(id)

func _exit_original_subtree(id: int) -> bool:
	trace_actual_source_close("subtree_enter:"+str(id))
	for child: int in _root_numeric.original_children_reverse_order(id):
		if not _exit_original_subtree(child): return false
	if _actor_scopes.has(id): return exit_original_actor_scope_at_checkpoint(id)
	if _service_scopes.has(id): return _exit_original_service_at_checkpoint(id)
	return _reject("original_tree_child_scope_missing",{"id":id})

func _free_original_service_at_checkpoint(id: int) -> bool:
	if not _service_scopes.has(id) or not _service_scopes[id].exit_callbacks_complete: return false
	var handle: Object = service_registry.resolve_original_retiring_service(id)
	# begin_retirement keeps the genuine handle in the registry until final free.
	if handle == null: return _reject("original_service_final_free_handle_missing",{"id":id})
	var kind: StringName = handle.kind()
	if kind in [&"polygon_pursuit_driver",&"path_scheduler"]: return paths.free_at_original_checkpoint(id)
	if kind == &"monster_visual":
		var actor_id: int = int(_service_scopes[id].parent_scope_id)
		if not _prepare_original_presented_actor_final_free(actor_id,id): return false
		_service_models[id].release_original_actor_link_at_final_free()
	if not _service_scopes[id].free_at_original_checkpoint() or not service_registry.final_free_service(id): return false
	if kind == &"monster_visual":
		if not streaming.consume_original_visual_free(id): return _reject("actual_visual_free_receipt_consume_failed",{"id":id})
		_pending_initial_enemy_presentations.erase(id)
		for owner_id: int in _enemy_visual_services.keys():
			if _enemy_visual_services[owner_id] == id:
				_enemy_visual_services.erase(owner_id)
				_actor_visuals.erase(owner_id)
	if kind == &"player_visual":
		for actor_id: int in _player_visual_publication_callbacks.keys():
			if is_same(_player_visual_publication_callbacks[actor_id],_service_models[id]): _player_visual_publication_callbacks.erase(actor_id)
	_node_timers.erase(id)
	forget_original_service_scope(id)
	return true

func _free_original_subtree(id: int) -> bool:
	for child: int in _root_numeric.original_children_reverse_order(id):
		if not _free_original_subtree(child): return false
	if _actor_scopes.has(id):
		# Reliable actor/presentation facts must be accepted before final free.
		if _actor_instances.has(id) and _actor_instances[id].has_method("flush_facts") and not _actor_instances[id].flush_facts(): return false
		if not retire_actor_at_original_free_checkpoint(id): return false
	elif _service_scopes.has(id):
		if not _free_original_service_at_checkpoint(id): return false
	else: return _reject("original_final_free_scope_missing",{"id":id})
	return _root_numeric.original_source_final_free(id)

func exit_original_world_children_at_checkpoint() -> bool:
	for child: int in _root_numeric.original_children_reverse_order(parent_scope_id()):
		if _actor_scopes.has(child) or _service_scopes.has(child):
			if not _exit_original_subtree(child): return false
	# SceneTree-root scheduler is deliberately excluded: its original lifetime
	# is persistent. Missing Session scheduler adoption remains a strict gate.
	return true

func final_free_original_world_children_at_checkpoint() -> bool:
	for child: int in _root_numeric.original_children_reverse_order(parent_scope_id()):
		if _actor_scopes.has(child) or _service_scopes.has(child):
			if not _free_original_subtree(child): return false
	return _source_scopes.game_root.exit_at_original_checkpoint()


var _caster_pending_accepts: Array[Dictionary] = []
func emit_original_caster_main_event(command: Dictionary) -> Dictionary:
	var ticket: Dictionary = _journal.next_original_event_identity()
	var event := {"kind":"original_world_presentation", "operation":&"caster_presentation", "arguments":[command], "source_site":_source_site, "reply_identity":ticket, "ordinal":ticket.event_ordinal}
	var reserved: Dictionary = _host.reserve_original_caster_event(ticket,event)
	if reserved.get("status") != "READY": return reserved
	if not _journal.append(event):
		_host.cancel_unaccepted_original_caster_event(ticket)
		return {"status":"INVALID"}
	# Appending accepts the original event obligation, not a Native FIFO packet.
	# Do not pin an unaccepted prefix across genuine Main ACK progress.
	_caster_pending_accepts.append({"ticket":ticket, "event":event, "prefix":{}})
	service_original_caster_event_acceptance()
	return {"status":"ACCEPTED", "reply_identity":ticket}
func service_original_caster_event_acceptance() -> bool:
	while not _caster_pending_accepts.is_empty():
		var item: Dictionary = _caster_pending_accepts[0]
		if item.prefix.is_empty():
			var registered: Dictionary = original_source_session().try_publish_original_event_prefix(item.event)
			if registered.get("status")=="PENDING": return false
			if registered.get("status")!="READY":
				fault("accepted_caster_event_prefix_admission_failed",registered)
				return false
			item.prefix=registered.prefix # Immutable actual Native acceptance, retained on reply-lock PENDING.
		var admitted: Dictionary = _host.accept_original_caster_event(item.ticket,item.event,item.prefix)
		if admitted.get("status") == "PENDING": return false
		if admitted.get("status") != "READY":
			# Bounded first-failure facts only: never copy a save or resource graph.
			var matched := false
			var same_wire := false
			for captured: Dictionary in item.prefix.events:
				if captured.get("ordinal") == item.ticket.event_ordinal:
					matched = captured == item.event
					same_wire = var_to_bytes(captured) == var_to_bytes(item.event)
			var actual: Dictionary = _host.status()
			var observation := {"ordinal":item.ticket.event_ordinal,"first":-1 if item.prefix.events.is_empty() else item.prefix.events[0].ordinal,"through":item.prefix.through_ordinal,"journal":_journal.applied_ordinal(),"native":actual.get("original_main_applied_prefix"),"in_flight":actual.get("original_primitive_in_flight"),"packets":actual.get("unsettled_original_published_prefixes"),"matched":matched,"same_wire":same_wire}
			fault("accepted_caster_event_exact_native_seal_failed", {"error":str(admitted.get("error","")),"reason":JSON.stringify(observation)})
			return false
		_caster_pending_accepts.pop_front()
	return true
func original_caster_reply_host() -> Object: return _host
func service_original_caster_replies() -> bool:
	if not service_original_caster_event_acceptance(): return false
	return cast_presentation == null or cast_presentation.service_original_replies()


var _original_live_close_phase: RefCounted
var _original_close_clock_baseline: Dictionary = {}
var _original_close_last_source_frame := -1
var _original_close_last_Main_frame := -1
var _original_close_pending_service := false
var _original_session_close_resource_hold := false
func _ensure_original_live_close_phase() -> bool:
	if _original_live_close_phase != null: return true
	if is_faulted() and not original_source_session().actual_original_closing_resource_service(): return false
	if _root_numeric == null or not _root_numeric.has_method("required_owner_service"):
		return _reject("actual_root_close_service_missing", {})
	var renderer: RefCounted = _root_numeric.required_owner_service(&"WorldViewLifecycle")
	_original_live_close_phase = OriginalLiveClosePhase.new()
	if not _original_live_close_phase.configure_owner(self,streaming,renderer):
		_original_live_close_phase = null
		return _reject("actual_live_close_phase_dependencies_missing", {})
	if not _original_live_close_phase.begin_original_world_exit():
		_original_live_close_phase = null
		return false
	return true

func on_original_close_process_phase(frame: Dictionary) -> bool:
	var prior_faults: int = _faults.size()
	if OS.get_thread_caller_id()!=_owner or not _closing or _closed or frame!=current_clock_frame() or frame.get("closing_session")!=true:
		return _reject("actual_native_closing_process_frame_required", {})
	var publication: Variant = frame.get("closing_process_publication")
	if not publication is Dictionary or publication.get("contract_id")!="hardcore.source.closing_process_frame.v1" or frame.get("actual_main_process_frame")!=publication.get("main_process_frame"):
		return _reject("original_closing_Main_process_provenance_missing", {})
	var boundary: String = str(publication.get("phase",""))
	if boundary not in ["PROCESS_SIGNAL","NODE_PROCESS_SERVICE"] or str(frame.get("source_boundary",""))!=boundary or str(frame.get("phase",""))!=("P_CLOSE_SIGNAL" if boundary=="PROCESS_SIGNAL" else "P_CLOSE_SERVICE"):
		return _reject("actual_closing_process_phase_pair_required", {})
	for key: String in ["epoch","source_process_frame","source_physics_frame","h_ordinal","simulation_elapsed","next_release_usec","published_signal_highwater"]:
		if not frame.has(key): return _reject("original_close_clock_field_missing", {"field":key})
	if not _source_site.is_empty() or frame_budget.snapshot().get("open_scopes")!=0:
		return _reject("original_close_P_crossed_active_source_scope", {})
	# Native holds the last real H/physics/simulation/host epoch throughout close.
	for key: String in ["epoch","source_physics_frame","h_ordinal","simulation_elapsed"]:
		if not _original_close_clock_baseline.has(key) or frame[key]!=_original_close_clock_baseline[key]: return _reject("closing_P_advanced_H_or_simulation", {"field":key})
	var sequence: int = int(frame.source_process_frame)
	var main_frame: int = int(frame.actual_main_process_frame)
	if boundary=="PROCESS_SIGNAL":
		if _original_close_pending_service or sequence!=_original_close_last_source_frame+1 or main_frame<=_original_close_last_Main_frame:
			return _reject("original_close_SIGNAL_not_next_actual_pair", {})
		_original_close_last_source_frame=sequence
		_original_close_last_Main_frame=main_frame
		_original_close_pending_service=true
		_entry_ordinal=0 # Retained for the SERVICE half of this same Source P.
	else:
		if not _original_close_pending_service or sequence!=_original_close_last_source_frame or main_frame!=_original_close_last_Main_frame:
			return _reject("original_close_SERVICE_without_same_SIGNAL", {})
	_frame=frame; _phase=StringName(frame.phase)
	if (boundary != "PROCESS_SIGNAL" or not is_faulted()) and not _ensure_original_live_close_phase(): return false
	if boundary=="PROCESS_SIGNAL":
		if not _begin_original_entry(&"P","SceneTree.process_frame"): return false
		# Only the nine source-proven Profile resource/transaction waits; ordinary
		# service_frame listeners, actor groups, gameplay timers and HP stay barred.
		if not profile_runtime.service_original_close_process_signal(sequence,main_frame,int(frame.published_signal_highwater)): return false
		if not _finish_original_entry(): return false
		return _invoke_root_entry(&"P",&"original_deferred_message_queue_flush",[&"P",&"P_GROUP:after_process_frame"])
	if not _begin_original_entry(&"P","GameRoot.accepted_close_cleanup"): return false
	# C99/Warm overlays are merged separately by Root. This exact port must be
	# present; no warm settlement from a worker/resource-only wake or SIGNAL.
	if cast_presentation==null or not cast_presentation.has_method("begin_original_warm_commit_phase") or not cast_presentation.has_method("end_original_warm_commit_phase") or not has_method("service_original_caster_replies"):
		return _reject("MISSING_actual_C99_warm_close_commit",{})
	if not cast_presentation.begin_original_warm_commit_phase(frame): return _reject("actual_warm_close_commit_rejected",{})
	call("service_original_caster_replies")
	var caster_window_closed: bool = cast_presentation.end_original_warm_commit_phase()
	# false from this existing service means outstanding real receipts, as in
	# normal P_GROUP. A true service fault is recorded in the same Core ledger.
	if not caster_window_closed or _faults.size() != prior_faults: return _reject("actual_warm_close_reply_commit_failed",{})
	# Map cleanup owns the same actual closing P opportunity. Its accepted
	# continuation may suspend on Source service signals; no Main waits for S.
	var map_coordinator: RefCounted = _root_numeric.get("_world_bootstrap_coordinator")
	if map_coordinator != null:
		var map_transport: RefCounted = _root_numeric.original_map_loading_transport()
		var map_terminal: Dictionary = publication.get("main_io",{}).get("map_terminal",{})
		if map_terminal.get("status") == "READY":
			if not map_coordinator.acknowledge_actual_original_map_owner_terminal(self,frame): return _reject("actual_Main_Map_terminal_ack_rejected",map_terminal)
			if map_transport != null and not map_transport.service_actual_original_map_close_at_P(frame): return _reject("actual_Map_close_SERVICE_wake_rejected",{})
		else:
			if map_transport != null and not map_transport.service_actual_original_map_close_at_P(frame): return _reject("actual_Map_close_SERVICE_wake_rejected",{})
			var map_admission: RefCounted = _original_source_session.original_world_main_dependency(&"WorldMapLoadingAdmission")
			if map_transport != null and not map_transport.has_pending_original_map_continuation() and (map_admission == null or not map_admission.has_pending_original_map_scope_release()):
				map_coordinator.service_original_map_retirement_at_actual_P(frame)
	# Original persistence pump only; Profile.step_process contains gameplay and
	# is deliberately not called by this original closing service opportunity.
	if not _service_original_delete_front_cleanup_at_actual_P(): return _reject("actual_delete_front_close_cleanup_rejected",{})
	profile.service_receipts()
	var progressed: Dictionary = _original_live_close_phase.original_p_close_commit(frame)
	trace_actual_source_close("Renderer_progress:"+str(progressed.get("status","MISSING"))+":"+str(progressed.get("phase",""))+":"+str(progressed.get("service_id",0)))
	if progressed.has("observation"): trace_actual_source_close("Renderer_detail:"+JSON.stringify(progressed))
	if progressed.get("status") not in ["PENDING","RENDERER_READY","READY","CLOSED"]:
		return _reject("original_live_close_process_cleanup_failed",progressed)
	# Persistent MonsterSourceFrames cache/escrow cleanup uses this SAME actual
	# Core.resources phase while the actual Core remains held. No second endpoint.
	if not _original_source_session.service_original_session_resource_close_at_actual_P(self,frame): return false
	if not _finish_original_entry(): return false
	if not _invoke_root_entry(&"P",&"original_deferred_message_queue_flush",[&"P",&"P_GROUP:end_group"]): return false
	# Source delete/idle checkpoint once, without ordinary H/P or timer dispatch.
	if not _invoke_root_entry(&"P",&"original_p_after_timers",[]): return false
	_original_close_pending_service=false
	return _faults.size() == prior_faults

func hold_original_session_close_resource_owner() -> bool:
	if OS.get_thread_caller_id()!=_owner or _closed: return false
	_original_session_close_resource_hold=true
	return true
func release_original_session_close_resource_owner() -> bool:
	if OS.get_thread_caller_id()!=_owner or not _closing or _closed or not _original_session_close_resource_hold: return false
	_original_session_close_resource_hold=false
	return true
func original_session_close_resource_owner_held() -> bool:
	assert(OS.get_thread_caller_id()==_owner)
	return _original_session_close_resource_hold

func capture_original_persistent_close_scope() -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not _closing or _closed or not _source_site.is_empty() or int(frame_budget.snapshot().open_scopes) != 0: return {}
	# This is an exact Source-owner handoff, including a SIGNAL whose SERVICE
	# has not arrived yet. The closed Core is never called to service later P.
	return {"contract_id":"hardcore.source.persistent_close_scope.v1","source_core_id":get_instance_id(),"owner_session_id":_original_source_session.original_budget_session_id(),"world_context":current_world_identity(),"baseline":_original_close_clock_baseline.duplicate(true),"last_source_frame":_original_close_last_source_frame,"last_Main_frame":_original_close_last_Main_frame,"pending_service":_original_close_pending_service,"entry_ordinal":_entry_ordinal}

func original_close_renderer_retirement_complete() -> bool:
	return _original_live_close_phase != null and _original_live_close_phase.original_renderer_retirement_complete()

func original_root_owner() -> RefCounted: return _root_numeric
func original_action_timing_publication() -> Dictionary: return _boot.assembly.action_timing
func actor_model_for_runtime_id(id: int) -> Object:
	var handle: Object=registry.resolve_runtime_actor(id)
	return handle.model() if handle!=null else null
func actor_handle_for_runtime_id(id: int) -> Object: return registry.resolve_runtime_actor(id)

func original_native_host() -> Object: return _host
func current_original_source_site() -> Dictionary: return _source_site.duplicate(true)


func commit_original_source_map_arrival_context(root: RefCounted, map_id: int, source_generation: int) -> bool:
	if OS.get_thread_caller_id() != _owner or root != _root_numeric or _closing or _closed or is_faulted(): return false
	if not _last_original_map_arrival.is_empty() and _world_identity == _last_original_map_arrival.after_world and map_id == int(_world_identity.runtime_map_id) and source_generation == int(_world_identity.world_epoch):
		return _host.verify_committed_original_map_arrival(_last_original_map_arrival)
	if _source_site.is_empty() or str(_source_site.get("domain","")) != "P" or _source_site.get("world_context") != _world_identity: return false
	var transport: RefCounted = root.original_map_loading_transport()
	if transport == null: return false
	var boundary: Dictionary = transport.capture_original_map_arrival_boundary()
	if boundary.is_empty(): return false
	var after: Dictionary = _world_identity.duplicate(true)
	after.runtime_map_id = map_id; after.world_epoch = source_generation
	var player_identity: Dictionary = registry.capture_attached_player_map_arrival_identity(_player_id,_world_identity,after)
	if player_identity.is_empty(): return false
	var candidate := {"contract_id":"hardcore.source.map_arrival.v2", "before_world":_world_identity,
		"after_world":after,"source_root_id":root.get_instance_id(),"world_core_id":get_instance_id(),
		"registry_id":registry.get_instance_id(),"owner_session_id":_original_source_session.original_budget_session_id(),
		"player_runtime_id":_player_id,"player_identity":player_identity,"coordinator_generation":root.original_map_coordinator_generation(),
		"transition_id":str(boundary.loading_scope.transition_id),"loading_scope":boundary.loading_scope,
		"finish_identity":boundary.finish_identity,"finish_reply":boundary.finish_reply}
	var captured: Dictionary = preload("res://scripts/gameplay/world/world_environment_value_graph.gd").copy_and_seal(candidate)
	if not captured.ok: return false
	var transaction: Dictionary = captured.value
	if not validate_original_map_arrival_transaction(transaction) or not _original_source_session.validate_original_map_arrival_transaction(self,transaction): return false
	var viewport := required_owner_service(&"VisualViewport", ["can_commit_original_map_arrival_transaction","commit_original_map_arrival_transaction"])
	if viewport == null or not viewport.can_commit_original_map_arrival_transaction(transaction): return false
	# Finish the old world entry, but retain the original P, deadline, budget,
	# journal, Player life/HP/physics/scope, and every old actor retirement debt.
	_original_map_arrival_commit_state = {"transaction":transaction,"stage":"VALIDATED"}
	if not _finish_original_entry(): return _reject("actual_map_arrival_old_entry_finish_failed",capture_original_map_arrival_commit_state())
	_original_map_arrival_commit_state.stage = "OLD_ENTRY_FINISHED"
	var committed: Dictionary = _host.commit_original_map_arrival(self,transaction)
	if committed.get("status") != "READY": return _reject("actual_Native_map_arrival_CAS_failed",{"native_result":committed,"actual_state":capture_original_map_arrival_commit_state()})
	_original_map_arrival_commit_state = {"transaction":transaction,"stage":"NATIVE_COMMITTED"}
	if not registry.commit_attached_player_map_arrival(_player_id,transaction.before_world,transaction.after_world,transaction.player_identity): return _reject("actual_map_arrival_registry_commit_failed",capture_original_map_arrival_commit_state())
	_world_identity = transaction.after_world
	_original_map_arrival_commit_state.stage = "REGISTRY_CORE_COMMITTED"
	if not _original_source_session.apply_original_map_arrival_transaction(self,transaction): return _reject("actual_map_arrival_current_route_failed",capture_original_map_arrival_commit_state())
	_original_map_arrival_commit_state.stage = "SESSION_ROUTE_COMMITTED"
	if not transport.commit_original_map_arrival_transaction(transaction): return _reject("actual_map_arrival_transport_route_failed",capture_original_map_arrival_commit_state())
	_original_map_arrival_commit_state.stage = "SOURCE_ROUTE_COMMITTED"
	if not viewport.commit_original_map_arrival_transaction(transaction): return _reject("actual_map_arrival_viewport_binding_failed",capture_original_map_arrival_commit_state())
	_original_map_arrival_commit_state.stage = "VIEWPORT_BINDING_COMMITTED"
	if not _begin_original_entry(&"P","GameRoot._load_zone:after_actual_arrival"): return _reject("actual_map_arrival_same_P_reopen_failed",capture_original_map_arrival_commit_state())
	# Enter combat geometry only with the actual committed map and the same
	# player's already-authoritative pose/life. No placeholder map qualification.
	if not _actor_instances.has(_player_id) or not _actor_instances[_player_id].ports.publish_pose(): return _reject("actual_map_arrival_player_pose_commit_failed",{})
	if not emit_original_main_event(&"source_map_arrival",[transaction]): return _reject("actual_map_arrival_Main_journal_append_failed",capture_original_map_arrival_commit_state())
	_original_map_arrival_commit_state.stage = "MAIN_EVENT_APPENDED"
	_last_original_map_arrival = transaction
	return true

var _last_original_map_arrival: Dictionary = {}
var _original_map_arrival_commit_state: Dictionary = {}
func capture_original_map_arrival_commit_state() -> Dictionary:
	if OS.get_thread_caller_id() != _owner or _original_map_arrival_commit_state.is_empty(): return {}
	var captured: Dictionary = _original_map_arrival_commit_state.duplicate(true)
	captured.current_core_world = _world_identity
	captured.current_registry_world = registry.capture_world()
	captured.current_session_world = _original_source_session.get("_persistent_world_context")
	captured.current_source_site = _source_site
	var player: Object = registry.resolve_runtime_actor(_player_id)
	captured.current_player_identity = player.identity() if player != null else {}
	return captured

func validate_original_map_arrival_transaction(transaction: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or not preload("res://scripts/gameplay/world/world_original_map_arrival_contract.gd").accepts(transaction) or _root_numeric == null or registry == null: return false
	if transaction.get("world_core_id") != get_instance_id() or transaction.get("registry_id") != registry.get_instance_id() or transaction.get("source_root_id") != _root_numeric.get_instance_id() or transaction.get("owner_session_id") != _original_source_session.original_budget_session_id() or transaction.get("player_runtime_id") != _player_id: return false
	var player: Object = registry.resolve_runtime_actor(_player_id)
	if player == null or _root_numeric.get("player") != player.model(): return false
	if transaction.get("before_world") != _world_identity or not transaction.get("after_world") is Dictionary: return false
	var after: Dictionary = transaction.after_world
	if after.get("world_epoch") != _root_numeric.get("_zone_generation") or after.get("runtime_map_id") != _root_numeric.get("current_map_id"): return false
	if transaction.get("coordinator_generation") != _root_numeric.original_map_coordinator_generation() or not _root_numeric.original_map_coordinator_is_current(int(transaction.coordinator_generation)) or transaction.get("transition_id") != _root_numeric.get("_active_map_transition_id"): return false
	if frame_budget.resource_external_segment_active() or int(frame_budget.snapshot().open_scopes) != 0: return false
	var transport: RefCounted = _root_numeric.original_map_loading_transport()
	return transport != null and transport.validate_original_map_arrival_transaction(transaction) and registry.can_commit_attached_player_map_arrival(_player_id,transaction.before_world,after,transaction.player_identity)
func register_original_gothic_environment_bodies(entries: Array, generation: int) -> bool:
	return native_bodies.register_gothic_environment_bodies(entries,generation)
func retire_original_gothic_environment_bodies() -> bool:
	return native_bodies.retire_original_gothic_environment_bodies()
func defer_original_actor_free(model: Object) -> bool:
	var handle: Object = actor_handle_for_model(model)
	return handle != null and queue_actor_retirement(handle.get_instance_id())
func enqueue_original_environment_focus_rebuild(environment: RefCounted, source: Vector2i, generation: int) -> void:
	# NativeHost's actual S CallQueue TLS override preserves original deferred lane.
	environment.apply_original_environment_focus_rebuild.call_deferred(source,generation)


var interactables: RefCounted
func install_original_interactable_owner(publication: Dictionary) -> bool:
	if interactables!=null: return false
	var port := preload("res://scripts/gameplay/world/world_interactable_owner_port.gd").new()
	if not port.configure_owner(self,publication): return _reject("actual_interactable_Loading_owner_missing",{})
	interactables=port
	return true
func create_interactable_at_original_constructor(kind: StringName) -> Object:
	if interactables==null or kind not in [&"npc",&"zone_portal"]: return null
	var source: Dictionary=_source_birth_publication(kind)
	if source.is_empty(): return null
	var scope := Scope.new()
	if not scope.configure_source(source.scope,self): return null
	var made: Dictionary=ActorFactory.create_interactable({"world_core":self,"registry":registry,"scope":scope,"ports":interactables,"source_publication":source},kind)
	if made.get("ok")!=true: fault("original_interactable_factory_failed",made); return null
	var instance: RefCounted=made.runtime
	var id: int=instance.handle.get_instance_id()
	_actor_instances[id]=instance; _actor_scopes[id]=scope; _actor_source[id]=source; _actor_metadata[id]=source.metadata
	for key: StringName in source.metadata: instance.model.set_meta(key,source.metadata[key])
	return instance.model
func enter_interactable_at_original_child_boundary(model: Object) -> bool:
	var handle: Object=actor_handle_for_model(model)
	if handle==null or handle.kind() not in [&"npc",&"zone_portal"]: return false
	var id: int=handle.get_instance_id()
	var scope: RefCounted=_actor_scopes[id]
	if scope.inside_world or not handle.set_runtime_qualification(scope.parent_scope_id,scope.can_process(),scope.physics_processing_enabled): return false
	scope.inside_world=true
	if not handle.set_world_membership(true) or not interactables.publish_pose(model) or not _root_numeric.original_actor_child_entered(id,_actor_source[id]): return false
	model.initialize_gameplay()
	return model._ready_complete and not interactables.faulted()

static func _original_source_path_before(a: Array,b: Array) -> bool:
	for index: int in range(mini(a.size(),b.size())):
		if a[index]!=b[index]: return a[index]<b[index]
	return a.size()<b.size()

func create_unconfigured_original_m30_summon_queue(root: RefCounted) -> RefCounted:
	if OS.get_thread_caller_id()!=_owner or not is_same(root,_root_numeric): return null
	var scope: RefCounted=new_original_service_scope(&"m30_summon_queue",parent_scope_id())
	if scope==null or scope.inside_world: return null
	var handle: Object=service_registry.allocate_service(&"m30_summon_queue",scope)
	if handle==null: return null
	var model:=M30QueueModel.new()
	var ports:=M30QueuePorts.new()
	if not ports.configure_owner(self,root) or not model.configure_owner(ports,scope) or not service_registry.bind_service_model(handle,model):
		fault("original_M30_queue_constructor_failed",{});return null
	# Constructor qualification survives configure(), before add_child admits
	# membership. This is the existing single service scope/model storage.
	_service_scopes[handle.get_instance_id()]=scope
	_service_models[handle.get_instance_id()]=model
	return model
func enter_original_m30_summon_queue_at_child_boundary(model: RefCounted) -> bool:
	var id: int=original_service_id_for_model(model)
	var handle: Object=service_registry.resolve_service(id)
	if handle==null or handle.kind()!=&"m30_summon_queue": return _reject("original_M30_queue_identity_missing",{})
	var scope: RefCounted=_service_scopes[id]
	if scope.inside_world or scope.exit_callbacks_complete: return _reject("original_M30_queue_double_enter",{})
	# Original configure sets PAUSABLE. Original add_child enters, then READY
	# sets physics enable according to the original pending jobs.
	scope.inside_world=true
	if not _root_numeric.original_service_child_entered(id,scope.parent_scope_id): return false
	var order: Dictionary=_root_numeric.original_service_callback_order(id,&"_physics_process")
	if order.get("ok")!=true or order.get("domain")!="H": return _reject("MISSING_actual_M30_source_callback_template",order)
	model.original_ready()
	return register_original_callback(model,service_registry.process_scope_for_service(id),&"H",&"original_physics_pump",scope.physics_priority,order.order,order.entry)


# Main actor projections read this sole Source model and use the sole journal.
const ActorVisualPublication := preload("res://scripts/gameplay/presentation/source_actor_visual_publication.gd")
var _actor_visual_publication_sequences: Dictionary = {}
var _player_visual_publication_callbacks: Dictionary = {}
# Identity/presentation responsibility only: no cached art answer, readiness,
# profile, Native reply or resource-work cursor.
var _pending_initial_enemy_presentations: Dictionary = {}

func _initial_enemy_presentation_world_matches(before: Dictionary, after: Dictionary) -> bool:
	if before == after: return true
	var arrival: Dictionary = _last_original_map_arrival
	# Only the existing exact contiguous arrival can explain ServiceHandle's
	# dynamic registry world. This helper never changes either captured world.
	if arrival.is_empty() or arrival.before_world != before or arrival.after_world != after or _world_identity != after: return false
	if arrival.world_core_id != get_instance_id() or arrival.registry_id != registry.get_instance_id() or arrival.source_root_id != _root_numeric.get_instance_id() or arrival.owner_session_id != _original_source_session.original_budget_session_id(): return false
	return _original_source_session.get("_last_original_map_arrival") == arrival and _host.verify_committed_original_map_arrival(arrival)

func _initial_enemy_presentation_owner_matches(id: int, held: Dictionary, service: Object) -> bool:
	if not _actor_instances.has(id) or service == null: return false
	var instance: RefCounted = _actor_instances[id]
	if held.actor_handle.get_ref() != instance.handle or registry.resolve_runtime_actor(id) != instance.handle or held.service_handle.get_ref() != service: return false
	# Enemy ActorHandle worlds are frozen at birth. Existing arrival rebinds
	# ONLY the attached Player; old Enemies retain retirement responsibility.
	if instance.handle.identity() != held.actor_identity or int(_enemy_visual_services.get(id,0)) != service.get_instance_id(): return false
	if held.visual.get_ref() != service.model() or not is_same(_actor_visuals.get(id),service.model()): return false
	var current: Dictionary = service.identity()
	var original: Dictionary = held.service_identity
	if current.size() != original.size(): return false
	for key: String in original:
		if key != "world" and current.get(key) != original[key]: return false
	return _initial_enemy_presentation_world_matches(original.world,current.world)

func original_enemy_presentation_binding_pending(id: int) -> bool:
	if OS.get_thread_caller_id() != _owner or not _actor_instances.has(id): return false
	var service_id: int = int(_enemy_visual_services.get(id,0))
	var held: Dictionary = _pending_initial_enemy_presentations.get(service_id,{})
	if held.is_empty() or _closing or _closed: return false
	var service: Object = service_registry.resolve_service(service_id)
	if service == null or service.is_queued_for_retirement() or _actor_instances[id].handle.is_queued_for_retirement(): return false
	if not _initial_enemy_presentation_owner_matches(id,held,service):
		fault("initial_enemy_presentation_owner_changed",{"actor":id,"service_id":service_id})
		return false
	if not streaming.original_initial_binding_observation_pending(service_id,held.service_identity):
		fault("initial_enemy_presentation_observation_missing",{"actor":id,"service_id":service_id})
		return false
	# An earlier visibility fact is not this observation's completion.
	return true

func _original_enemy_visual_presentation_binding_pending(visual: RefCounted) -> bool:
	var actor: Object = visual._actor_link.resolve_record()
	return actor != null and original_enemy_presentation_binding_pending(actor.get_instance_id())

func _on_original_initial_enemy_binding_observed(service_id: int, original_identity: Dictionary, consumed: Dictionary) -> void:
	var held: Dictionary = _pending_initial_enemy_presentations.get(service_id,{})
	# Actual exit can already have ended the presentation responsibility;
	# accepted resource work still settles through the unchanged FIFO.
	if held.is_empty():
		if _closing or _closed: return
		var retiring: Object = service_registry.resolve_service(service_id)
		if retiring == null or retiring.is_queued_for_retirement(): return
		fault("initial_enemy_presentation_obligation_missing",{"service_id":service_id})
		return
	var id: int = int(held.actor_identity.runtime_id)
	var service: Object = service_registry.resolve_service(service_id)
	if _closing or _closed or service == null or service.is_queued_for_retirement() or not _actor_instances.has(id) or _actor_instances[id].handle.is_queued_for_retirement():
		_pending_initial_enemy_presentations.erase(service_id)
		return
	if original_identity != held.service_identity or not _initial_enemy_presentation_owner_matches(id,held,service):
		fault("initial_enemy_presentation_completion_owner_changed",{"actor":id,"service_id":service_id})
		return
	var reply: Dictionary = consumed.get("reply",{})
	var request: Dictionary = reply.get("request",{})
	if consumed.get("status") != "COMMITTED" or reply.get("executed") != true or request.get("op") != &"observe_binding" or request.get("args") != [service_id] or not _initial_enemy_presentation_world_matches(held.service_identity.world,request.get("site",{}).get("world_context",{})):
		fault("initial_enemy_presentation_consumed_observation_invalid",{"service_id":service_id})
		return
	if not resources.has_binding_fact(service_id) or resources.binding_fact(service_id) != consumed.get("result"):
		fault("initial_enemy_presentation_actual_fact_missing",{"service_id":service_id})
		return
	if int(_actor_visual_publication_sequences.get(id,0)) != 0:
		fault("initial_enemy_presentation_already_published",{"actor":id})
		return
	# Consume only presentation responsibility, after the genuine row/result.
	# No stale delta is replayed and the existing physical shell is reused.
	_pending_initial_enemy_presentations.erase(service_id)
	if not publish_original_actor_visual_projection(id,false,0.0): return
	# First full projection must precede dependent anchor/redraw operations.
	var observer: RefCounted = _enemy_presentation[id]
	observer.refresh_name_label_position()
	observer._request_actor_redraw_if_dynamic()
	_trace_actual_initial_enemy_binding("completed",id,service_id,consumed)

func _trace_actual_initial_enemy_binding(stage: String, id: int, service_id: int, consumed: Dictionary) -> void:
	if not _boot.get("project_settings",{}).get("hardcore/diagnostics/main_boot_trace",false): return
	var visual: RefCounted = _actor_visuals.get(id)
	var actor: RefCounted = _actor_instances.get(id)
	var service: Object = service_registry.resolve_service(service_id)
	if visual == null or actor == null or service == null: return
	var receipt: Dictionary = consumed.get("reply",{})
	var value := {"stage":stage,"core_id":get_instance_id(),"source_thread":_owner,"actor_identity":actor.handle.identity(),"service_identity":service.identity(),"service_id":service_id,"source_P":source_process_epoch(),"source_H":source_physics_ordinal(),"visual_process_enabled":visual.is_processing(),"publication_sequence":int(_actor_visual_publication_sequences.get(id,0)),"initial_observation_pending":streaming.original_initial_binding_observation_pending(service_id,service.identity()),"actual_binding_fact":resources.has_binding_fact(service_id),"consumed_status":consumed.get("status",""),"native_deadline_status":receipt.get("native_deadline_status",""),"native_operation_identity":consumed.get("identity",{}),"budget_settlement":consumed.get("budget_receipt",{})}
	print("HC_ACTUAL_INITIAL_ENEMY_BINDING ",JSON.stringify(value))

func capture_original_actor_visual_projection(id: int, advance_visual: bool, delta: float) -> Dictionary:
	if OS.get_thread_caller_id() != _owner or not _actor_instances.has(id) or not is_finite(delta) or delta < 0.0: return {}
	var instance: RefCounted = _actor_instances[id]
	var sequence: int = int(_actor_visual_publication_sequences.get(id,0)) + 1
	var value: Dictionary = ActorVisualPublication.capture_original(self,instance.handle,instance.model,_actor_visuals.get(id),sequence,advance_visual,delta)
	if value.is_empty(): return {}
	_actor_visual_publication_sequences[id] = sequence
	return value

func publish_original_actor_visual_projection(id: int, advance_visual: bool, delta: float) -> bool:
	if OS.get_thread_caller_id() != _owner or not _actor_instances.has(id): return false
	if original_enemy_presentation_binding_pending(id): return true
	if is_faulted(): return false
	# The existing retained actor-fact queue must be accepted first; a later
	# P snapshot cannot overtake a failed earlier presentation fact.
	if _actor_instances[id].ports.has_method("flush_facts") and not _actor_instances[id].ports.flush_facts(): return _reject("original_actor_fact_prefix_pending",{})
	var value: Dictionary = capture_original_actor_visual_projection(id,advance_visual,delta)
	if value.is_empty(): return _reject("original_actor_visual_capture_rejected",{"runtime_id":id})
	if not emit_original_main_event(&"actor_visual_projection",[value]): return _reject("original_actor_visual_journal_rejected",{"runtime_id":id})
	return true

func bind_original_player_visual_process_publication(id: int, actual_child_scope: RefCounted, source_order: int, source_entry: String) -> bool:
	if OS.get_thread_caller_id() != _owner or not _actor_instances.has(id) or _actor_instances[id].handle.kind() != &"player" or _player_visual_publication_callbacks.has(id): return false
	if actual_child_scope == null or actual_child_scope.owner_thread_id() != _owner or actual_child_scope.parent_scope_id != id or not actual_child_scope.inside_world or source_order < 0 or source_entry.is_empty(): return false
	# Root must supply the actual captured PlayerVisual child callback scope,
	# its original priority/order/entry and lifecycle. No PUBLISH surrogate.
	var callback: RefCounted
	for service_id: int in _service_scopes:
		if is_same(_service_scopes[service_id],actual_child_scope):
			var handle: Object = service_registry.resolve_service(service_id)
			if handle == null or handle.kind() != &"player_visual": return false
			callback = _service_models[service_id]
			break
	if callback == null: return false
	if not register_original_callback(callback,actual_child_scope,&"P",&"_process",actual_child_scope.process_priority,source_order,source_entry): return false
	_player_visual_publication_callbacks[id] = callback
	return true

func enter_original_player_visual_ready(instance: RefCounted) -> bool:
	if OS.get_thread_caller_id() != _owner or instance == null: return false
	var actor_id: int = instance.handle.get_instance_id()
	if _actor_instances.get(actor_id) != instance or instance.handle.kind() != &"player" or not instance.handle.is_inside_world(): return false
	var scope: RefCounted = new_original_service_scope(&"player_visual",actor_id)
	if scope == null: return false
	var handle: Object = service_registry.allocate_service(&"player_visual",scope)
	if handle == null: return false
	var callback := ActorVisualPublication.PlayerVisualProcessPublisher.new(self,actor_id)
	if not service_registry.bind_service_model(handle,callback): return false
	var service_id: int = handle.get_instance_id()
	_service_scopes[service_id] = scope
	_service_models[service_id] = callback
	scope.inside_world = true
	if not _root_numeric.original_service_child_entered(service_id,actor_id) or not _apply_original_service_implicit_ready(&"player_visual",scope): return false
	var order: Dictionary = _root_numeric.original_service_callback_order(service_id,&"_process")
	if order.get("ok") != true or order.get("domain") != "P": return _reject("original_player_visual_order_missing",order)
	return bind_original_player_visual_process_publication(actor_id,scope,order.order,order.entry)


const EnemyBirthHeader := preload("res://scripts/gameplay/presentation/enemy_birth_structural_header.gd")
func append_original_enemy_structural_header(kind: StringName, actor_handle: Object, visual_service_id: int = 0) -> bool:
	if OS.get_thread_caller_id() != _owner or actor_handle == null or registry.resolve_runtime_actor(actor_handle.get_instance_id()) != actor_handle or actor_handle.kind() != &"enemy": return _reject("enemy_header_canonical_commit_missing",{})
	var identity: Dictionary = actor_handle.identity()
	var event_identity: Dictionary = _journal.next_original_event_identity()
	var header: Dictionary = {"contract_id":EnemyBirthHeader.CONTRACT,"header_kind":String(kind),"actor_identity":identity,
		"event_identity":event_identity,"source_site":_source_site,"sequence":event_identity.event_ordinal}
	if kind == &"VISUAL_HEADER":
		if visual_service_id <= 0 or _enemy_visual_services.get(identity.runtime_id) != visual_service_id or not _service_models.has(visual_service_id) or not _service_scopes[visual_service_id].inside_world: return _reject("enemy_header_real_visual_child_missing",{})
		header.visual_service_id = visual_service_id
	if not EnemyBirthHeader.validate(header,String(kind)): return _reject("enemy_structural_header_invalid",{})
	header = EnemyBirthHeader.capture(header)
	if header.is_empty() or not emit_original_main_event(kind,[header]): return _reject("enemy_structural_header_journal_rejected",{})
	return true

func _prepare_original_presented_actor_final_free(id: int, service_id := 0, original_free := true) -> bool:
	var handle: Object = registry.resolve_runtime_actor(id)
	if handle == null or handle.kind() not in [&"player",&"enemy"]: return false
	var visual_id: int = service_id if service_id > 0 else int(_enemy_visual_services.get(id,0))
	var lifecycle: RefCounted = _root_numeric.required_owner_service(&"WorldViewLifecycle")
	if lifecycle == null or not lifecycle.remember_presented_actor_at_original_free(id): return false
	if visual_id > 0 and not streaming.original_visual_free_started(visual_id) and not streaming.live_binding_ready_for_original_renderer_free(visual_id): return false
	var actual: Dictionary = lifecycle.release_presented_actor_at_original_free(id)
	if actual.get("status") != "READY":
		if actual.get("status") not in ["PENDING","BUSY","BACKPRESSURE"]: return _reject("actual_original_actor_free_observation_failed",actual)
		return false
	if actual.get("actual_node_absent") != true: return _reject("actual_original_actor_Node_storage_retained",actual)
	if visual_id > 0 and actual.get("service_id") != visual_id: return _reject("actual_original_visual_free_service_identity",{"id":id,"service_id":visual_id})
	if visual_id > 0:
		if not streaming.original_visual_free_started(visual_id):
			# This call belongs solely to the original final-free checkpoint.
			if not original_free: return false
			if not streaming.finish_visual_resources_at_original_free(visual_id): return false
		if not streaming.original_visual_free_committed(visual_id): return false
		if not streaming.live_binding_ready_for_original_renderer_free(visual_id): return false
	var confirmed: bool = lifecycle.confirm_presented_actor_at_original_free(id)
	if not confirmed and not lifecycle.get("_actor_free")[id].failure.is_empty(): return _reject("actual_original_actor_free_confirmation_failed",lifecycle.get("_actor_free")[id].failure)
	return confirmed

func _capture_original_delete_front_resource_debt(id: int) -> Dictionary:
	for child: int in _root_numeric.original_children_reverse_order(id):
		var nested: Dictionary = _capture_original_delete_front_resource_debt(child)
		if not nested.is_empty(): return nested
	var actor_id := 0
	var visual_id := 0
	if _actor_scopes.has(id) and _actor_scopes[id].exit_callbacks_complete:
		actor_id = id; visual_id = int(_enemy_visual_services.get(id,0))
	elif _service_scopes.has(id) and _service_scopes[id].exit_callbacks_complete:
		actor_id = int(_service_scopes[id].parent_scope_id)
		if _enemy_visual_services.get(actor_id) != id: return {}
		visual_id = id
	else: return {}
	var lifecycle: RefCounted = _root_numeric.required_owner_service(&"WorldViewLifecycle")
	if lifecycle == null or not lifecycle.get("_actor_free").has(actor_id): return {}
	var actual: Dictionary = lifecycle.get("_actor_free")[actor_id]
	if not actual.failure.is_empty() or actual.receipt.get("metadata_released") == true: return {}
	var canonical: Dictionary = lifecycle._retiring_identity(actor_id)
	if canonical.is_empty() or canonical != actual.identity: return {}
	var binding: Dictionary = streaming.get("_original_visual_free").get(visual_id,{})
	return {"contract_id":"hardcore.source.deferred_final_free.v1","core_id":get_instance_id(),"source_scope_id":id,"actor_identity":canonical,"service_id":visual_id,"actual_original_exit_complete":true,"actual_actor_free_receipt":actual.receipt.duplicate(true),"actual_binding_status":binding.get("status","NOT_STARTED")}

func verify_original_deferred_final_free(receipt: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner or _original_delete_queue.is_empty() or receipt.get("frame") != current_clock_frame() or receipt.get("remaining") != _original_delete_queue.size() or receipt.get("retained_front") != _original_delete_queue.front(): return false
	var actual: Dictionary = _capture_original_delete_front_resource_debt(int(_original_delete_queue.front().id))
	return not actual.is_empty() and receipt.get("deferred_final_free") == actual and actual.core_id == get_instance_id() and actual.actual_original_exit_complete == true

func _service_original_delete_front_cleanup_at_actual_P() -> bool:
	if _original_delete_queue.is_empty(): return true
	var prior_faults: int = _faults.size()
	var frame: Dictionary = current_clock_frame()
	var budget: RefCounted = original_source_session().original_frame_budget()
	if current_original_source_site().get("domain") != "P" or frame.get("phase") not in ["P_GROUP","P_CLOSE_SERVICE"] or budget.snapshot().open_scopes != 0 or budget.resource_external_segment_active(): return false
	if frame.get("phase") == "P_CLOSE_SERVICE" and (frame.get("closing_session") != true or frame.get("source_boundary") != "NODE_PROCESS_SERVICE" or frame.get("closing_process_publication",{}).get("phase") != "NODE_PROCESS_SERVICE"): return false
	var front: Dictionary = _original_delete_queue.front()
	var debt: Dictionary = _capture_original_delete_front_resource_debt(int(front.id))
	if debt.is_empty(): return true
	_prepare_original_presented_actor_final_free(int(debt.actor_identity.runtime_id),int(debt.service_id),false)
	return _faults.size() == prior_faults and not _original_delete_queue.is_empty() and _original_delete_queue.front() == front

# Read-only Source-owner heartbeat for a suspended genuine map continuation.
# The trace does not poll Native replies, wake waiters, or execute a callback.
var _last_actual_map_wait_trace_usec := 0
func _trace_actual_map_continuation_wait() -> void:
	if not bool(clock_ports.get_setting("hardcore/diagnostics/main_boot_trace",false)) or _root_numeric == null: return
	var now: int = Time.get_ticks_usec()
	if now - _last_actual_map_wait_trace_usec < 5000000: return
	_last_actual_map_wait_trace_usec = now
	var transport: RefCounted = _root_numeric.original_map_loading_transport()
	if transport == null: return
	var coordinator: RefCounted = _root_numeric.get("_world_bootstrap_coordinator")
	var staged: Dictionary = coordinator.actual_staged_continuation_observation() if coordinator!=null else {}
	if not transport.has_pending_original_map_continuation() and staged.is_empty(): return
	var waiting: Array = profile_runtime.get("_resource_service_waiters")
	var counts: Array[int] = []
	for waiter: RefCounted in waiting: counts.append(waiter.get_signal_connection_list("released").size())
	var job: Dictionary = transport.get("_job")
	var trace: Dictionary = transport.get("_trace_job")
	print("HC_SOURCE_MAP_WAIT ",JSON.stringify({"usec":now,"epoch":_frame.get("epoch"),"source_P":_frame.get("source_process_frame"),"profile_last_P":profile_runtime.get("_last_service_sequence"),"profile_runtime_id":profile_runtime.get_instance_id(),"staged":staged,"waiters":waiting.size(),"waiter_connections":counts,"exchange_running":transport.get("_exchange_running"),"job_identity":job.get("identity",{}),"native_sealed":job.get("native_sealed",false),"settled":job.get("settled",false),"trace":trace}))
