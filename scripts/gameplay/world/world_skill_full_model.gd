extends RefCounted

## Source-owned gameplay input state. World execution, actors, clocks and
## presentation are explicit owner-local ports; no SceneTree lookup on S.
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
var _fields: RefCounted
var _profile: RefCounted
var _input: RefCounted
var _clock: RefCounted
var _actors: RefCounted
var _execution_ref: WeakRef
var _execution: RefCounted:
	get:
		var owner: RefCounted = _execution_ref.get_ref() if _execution_ref != null else null
		assert(owner != null, "WorldSkill execution owner has retired")
		return owner
var _presentation: RefCounted

func _configure_input_ports(bindings: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or _configured: return false
	for key: String in ["fields", "profile", "input", "clock", "actors", "execution", "presentation"]:
		if not bindings.get(key) is RefCounted or bindings[key] is Resource: return false
	_fields = bindings.fields
	_profile = bindings.profile
	_input = bindings.input
	_clock = bindings.clock
	_actors = bindings.actors
	_execution_ref = weakref(bindings.execution)
	_presentation = bindings.presentation
	_configured = true
	return true

func _owned() -> bool:
	return _configured and OS.get_thread_caller_id() == _owner_thread

var player: Object:
	get: return _actors.player() if _owned() else null
var locked_target: Object:
	get: return _actors.locked_target() if _owned() else null
	set(value):
		if _owned(): _actors.set_locked_target(value)

const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
const ATTACK_INPUT_TICKET_CONTRACT_ID := "combat.input.ordinary_attack.live_owner_no_debt.v2"
const SKILL_INPUT_TICKET_CONTRACT_ID := (
	"combat.input.skill_ticket.cooldown_coalesce_hold_repeat.v2"
)
const SKILL_HOLD_REPEAT_THRESHOLD_MS := 300
const MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS := 0.10
const MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS := 0.60
const ATTACK_ACTION_LIFECYCLE_CONTRACT_ID := "input.attack.fresh_down.v1"
const ATTACK_ACTION_DIAGNOSTIC_LIMIT := 256

var current_map_id: int:
	get: return _fields.read_field("current_map_id") if _owned() else -1
	set(value):
		if _owned(): _fields.write_field("current_map_id", value)
var _zone_generation: int:
	get: return _fields.read_field("_zone_generation") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_zone_generation", value)
var _mobile_attack_held: bool:
	get: return _fields.read_field("_mobile_attack_held") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_mobile_attack_held", value)
var _queued_mobile_attack_tickets: Array[int]:
	get: return _fields.read_field("_queued_mobile_attack_tickets") if _owned() else ([] as Array[int])
	set(value):
		if _owned(): _fields.write_field("_queued_mobile_attack_tickets", value)
var _active_mobile_attack_tokens: Dictionary:
	get: return _fields.read_field("_active_mobile_attack_tokens") if _owned() else {}
	set(value):
		if _owned(): _fields.write_field("_active_mobile_attack_tokens", value)
var _legacy_mobile_attack_token: int:
	get: return _fields.read_field("_legacy_mobile_attack_token") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_legacy_mobile_attack_token", value)
var _next_synthetic_attack_token: int:
	get: return _fields.read_field("_next_synthetic_attack_token") if _owned() else -1
	set(value):
		if _owned(): _fields.write_field("_next_synthetic_attack_token", value)
var _active_skill_inputs: Dictionary:
	get: return _fields.read_field("_active_skill_inputs") if _owned() else {}
	set(value):
		if _owned(): _fields.write_field("_active_skill_inputs", value)
var _next_skill_input_sequence: int:
	get: return _fields.read_field("_next_skill_input_sequence") if _owned() else 1
	set(value):
		if _owned(): _fields.write_field("_next_skill_input_sequence", value)
var _skill_input_retry_remaining: float:
	get: return _fields.read_field("_skill_input_retry_remaining") if _owned() else 0.0
	set(value):
		if _owned(): _fields.write_field("_skill_input_retry_remaining", value)
var _keyboard_bound_skill_token: int:
	get: return _fields.read_field("_keyboard_bound_skill_token") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_keyboard_bound_skill_token", value)
var _attack_action_press_owned: bool:
	get: return _fields.read_field("_attack_action_press_owned") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_attack_action_press_owned", value)
var _attack_action_neutral_observed: bool:
	get: return _fields.read_field("_attack_action_neutral_observed") if _owned() else true
	set(value):
		if _owned(): _fields.write_field("_attack_action_neutral_observed", value)
var _attack_action_ignored_pressed_recorded: bool:
	get: return _fields.read_field("_attack_action_ignored_pressed_recorded") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_attack_action_ignored_pressed_recorded", value)
var _attack_action_lifecycle_epoch: int:
	get: return _fields.read_field("_attack_action_lifecycle_epoch") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_attack_action_lifecycle_epoch", value)
var _attack_action_diagnostic_serial: int:
	get: return _fields.read_field("_attack_action_diagnostic_serial") if _owned() else 0
	set(value):
		if _owned(): _fields.write_field("_attack_action_diagnostic_serial", value)
var _attack_action_diagnostic_events: Array[Dictionary]:
	get: return _fields.read_field("_attack_action_diagnostic_events") if _owned() else ([] as Array[Dictionary])
	set(value):
		if _owned(): _fields.write_field("_attack_action_diagnostic_events", value)
var _magic_shield_auto_enabled: bool:
	get: return _fields.read_field("_magic_shield_auto_enabled") if _owned() else false
	set(value):
		if _owned(): _fields.write_field("_magic_shield_auto_enabled", value)
var _magic_shield_auto_retry_remaining: float:
	get: return _fields.read_field("_magic_shield_auto_retry_remaining") if _owned() else 0.0
	set(value):
		if _owned(): _fields.write_field("_magic_shield_auto_retry_remaining", value)


var _world: Object

var _random: Object

var _rules: Object

var _geometry: Object

var _casting: Object

var _diagnostics: Object

var _engagement: Object

var _combat: Object

var _spatial: Object

var _world_context: Object

var _time_domains: Object

var _feature_runtime: Object

var _feature_target_bound: Object

var _plan_contract: RefCounted
var _planner: RefCounted
var last_fault := ""
const PlanContractCore := preload("res://scripts/gameplay/world/world_skill_plan_contract.gd")
const PlannerCore := preload("res://scripts/gameplay/world/world_skill_planner.gd")

func configure_full_ports(bindings: Dictionary) -> bool:
	if OS.get_thread_caller_id() != _owner_thread or _configured: return false
	if not bindings.get("random") is RandomNumberGenerator: return false
	for name: String in REQUIRED_PORTS:
		var port: Variant = bindings.get(name)
		if not port is RefCounted or port is Resource: return false
		for method: String in REQUIRED_PORTS[name]:
			if not port.has_method(method): return false
	for name: String in REQUIRED_VALUE_PORTS:
		var port: Variant = bindings.get(name)
		if not port is RefCounted or port is Resource: return false
	_world = bindings["world"]
	_random = bindings["random"]
	_rules = bindings["rules"]
	_geometry = bindings["geometry"]
	_casting = bindings["casting"]
	_diagnostics = bindings["diagnostics"]
	_engagement = bindings["engagement"]
	_combat = bindings["combat"]
	_spatial = bindings["spatial"]
	_world_context = bindings["world_context"]
	_time_domains = bindings["time_domains"]
	_feature_runtime = bindings["feature_runtime"]
	_feature_target_bound = bindings["feature_target_bound"]

	if bindings.has("legacy_planner") or bindings.has("legacy_plan_contract"):
		if OS.get_thread_caller_id() != OS.get_main_thread_id(): return false
		if bindings.get("legacy_planner") != preload("res://scripts/skills/skill_runtime_router.gd") 			or bindings.get("legacy_plan_contract") != preload("res://scripts/skills/skill_execution_plan_contract.gd"): return false
		_planner = bindings.legacy_planner
		_plan_contract = bindings.legacy_plan_contract
	else:
		_plan_contract = PlanContractCore.new()
		_planner = PlannerCore.new()
		if not _planner.configure_contract(_plan_contract): return false
	if not _configure_input_ports(bindings): return false
	return true

func _fault(code: String, details: Dictionary = {}) -> void:
	last_fault = code
	_world.fault(code, details)

func activate_magic_skill_domain() -> void:
	_activate_magic_skill_domain()

func try_release_skill(skill_name: String, show_feedback: bool) -> StringName:
	return _try_release_skill(skill_name, show_feedback)

func request_mobile_attack() -> bool:
	return _request_mobile_attack()

var manual_target_lock: Variant:
	get: return _fields.read_field("manual_target_lock")
	set(value): _fields.write_field("manual_target_lock", value)

var magic_locked_target: Object:
	get: return _actors.magic_locked_target()
	set(value): _actors.set_magic_locked_target(value)

var manual_magic_target_lock: Variant:
	get: return _fields.read_field("manual_magic_target_lock")
	set(value): _fields.write_field("manual_magic_target_lock", value)

var _active_target_domain_magic: Variant:
	get: return _fields.read_field("_active_target_domain_magic")
	set(value): _fields.write_field("_active_target_domain_magic", value)

var auto_target_enabled: Variant:
	get: return _fields.read_field("auto_target_enabled")
	set(value): _fields.write_field("auto_target_enabled", value)

var _active_safe_zones: Array:
	get: return _fields.read_field("_active_safe_zones")
	set(value): _fields.write_field("_active_safe_zones", value)

var _safe_zone_context: Dictionary:
	get: return _fields.read_field("_safe_zone_context")
	set(value): _fields.write_field("_safe_zone_context", value)

var _player_safe_zone_cache: Dictionary:
	get: return _fields.read_field("_player_safe_zone_cache")
	set(value): _fields.write_field("_player_safe_zone_cache", value)

var _combat_target_query_service: Object:
	get: return _fields.read_field("_combat_target_query_service")
	set(value): _fields.write_field("_combat_target_query_service", value)

var _combat_target_query_service_map_id: Variant:
	get: return _fields.read_field("_combat_target_query_service_map_id")
	set(value): _fields.write_field("_combat_target_query_service_map_id", value)

var _combat_target_query_service_index: Object:
	get: return _fields.read_field("_combat_target_query_service_index")
	set(value): _fields.write_field("_combat_target_query_service_index", value)

var _target_spatial_query_scratch: Array:
	get: return _fields.read_field("_target_spatial_query_scratch")
	set(value): _fields.write_field("_target_spatial_query_scratch", value)

var _aoe_candidate_scratch: Array:
	get: return _fields.read_field("_aoe_candidate_scratch")
	set(value): _fields.write_field("_aoe_candidate_scratch", value)

var _direct_spell_target_stats_scratch: Dictionary:
	get: return _fields.read_field("_direct_spell_target_stats_scratch")
	set(value): _fields.write_field("_direct_spell_target_stats_scratch", value)

var _ground_effect_manager: Object:
	get: return _fields.read_field("_ground_effect_manager")
	set(value): _fields.write_field("_ground_effect_manager", value)

var missing_projection_rejection_count: Variant:
	get: return _fields.read_field("missing_projection_rejection_count")
	set(value): _fields.write_field("missing_projection_rejection_count", value)

var projection_rejection_reason: Variant:
	get: return _fields.read_field("projection_rejection_reason")
	set(value): _fields.write_field("projection_rejection_reason", value)

var reference_audit_mode: Variant:
	get: return _fields.read_field("reference_audit_mode")
	set(value): _fields.write_field("reference_audit_mode", value)

var _aoe_reference_fallback_test_enabled: Variant:
	get: return _fields.read_field("_aoe_reference_fallback_test_enabled")
	set(value): _fields.write_field("_aoe_reference_fallback_test_enabled", value)

var _projection_profile_cache: Dictionary:
	get: return _fields.read_field("_projection_profile_cache")
	set(value): _fields.write_field("_projection_profile_cache", value)

var _projection_profile_cache_audit_mode: Variant:
	get: return _fields.read_field("_projection_profile_cache_audit_mode")
	set(value): _fields.write_field("_projection_profile_cache_audit_mode", value)

var _projection_profile_runtime_identity_cache: Dictionary:
	get: return _fields.read_field("_projection_profile_runtime_identity_cache")
	set(value): _fields.write_field("_projection_profile_runtime_identity_cache", value)

var _ground_effect_runtime_serial: Variant:
	get: return _fields.read_field("_ground_effect_runtime_serial")
	set(value): _fields.write_field("_ground_effect_runtime_serial", value)

var _map_transition_in_progress: Variant:
	get: return _fields.read_field("_map_transition_in_progress")
	set(value): _fields.write_field("_map_transition_in_progress", value)

var _pending_main_pet_arrivals: Object:
	get: return _fields.read_field("_pending_main_pet_arrivals")
	set(value): _fields.write_field("_pending_main_pet_arrivals", value)

var _pending_main_pet_retry_tile: Variant:
	get: return _fields.read_field("_pending_main_pet_retry_tile")
	set(value): _fields.write_field("_pending_main_pet_retry_tile", value)

var _pending_main_pet_retry_tile_valid: Variant:
	get: return _fields.read_field("_pending_main_pet_retry_tile_valid")
	set(value): _fields.write_field("_pending_main_pet_retry_tile_valid", value)

var _canonical_cast_serial: Variant:
	get: return _fields.read_field("_canonical_cast_serial")
	set(value): _fields.write_field("_canonical_cast_serial", value)

var _skill_footprint_release_serial: Variant:
	get: return _fields.read_field("_skill_footprint_release_serial")
	set(value): _fields.write_field("_skill_footprint_release_serial", value)

var _canonical_fire_charge_expires_ms: Variant:
	get: return _fields.read_field("_canonical_fire_charge_expires_ms")
	set(value): _fields.write_field("_canonical_fire_charge_expires_ms", value)

var _skill_cast_target: Object:
	get: return _actors.cast_target()
	set(value): _actors.set_cast_target(value)

var _selected_friendly_instance_id: Variant:
	get: return _fields.read_field("_selected_friendly_instance_id")
	set(value): _fields.write_field("_selected_friendly_instance_id", value)

var _ongoing_heals: Array[Dictionary]:
	get: return _fields.read_field("_ongoing_heals")
	set(value): _fields.write_field("_ongoing_heals", value)

var _pending_melee_diagnostic: Dictionary:
	get: return _fields.read_field("_pending_melee_diagnostic")
	set(value): _fields.write_field("_pending_melee_diagnostic", value)

var _active_physical_hit_diagnostics: Array[Dictionary]:
	get: return _fields.read_field("_active_physical_hit_diagnostics")
	set(value): _fields.write_field("_active_physical_hit_diagnostics", value)

var _fire_wall_field_registry: Object:
	get: return _fields.read_field("_fire_wall_field_registry")
	set(value): _fields.write_field("_fire_wall_field_registry", value)

var _fire_wall_field_order: Array:
	get: return _fields.read_field("_fire_wall_field_order")
	set(value): _fields.write_field("_fire_wall_field_order", value)

var _fire_wall_registry_validation_enabled: Variant:
	get: return _fields.read_field("_fire_wall_registry_validation_enabled")
	set(value): _fields.write_field("_fire_wall_registry_validation_enabled", value)

var _hc_lightning_hint_ms: Variant:
	get: return _fields.read_field("_hc_lightning_hint_ms")
	set(value): _fields.write_field("_hc_lightning_hint_ms", value)

const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")

const CombatResolutionRulesScript := preload("res://scripts/combat_resolution_rules.gd")

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")

const SkillGeometryServiceScript := preload(
	"res://scripts/skills/skill_geometry_service.gd"
)

const CombatDirectionSpaceScript := preload("res://scripts/skills/combat_direction_space.gd")

const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const CombatReleaseGeometryScript := preload("res://scripts/skills/combat_release_geometry.gd")

const TaoistSupportPolicyScript := preload(
	"res://scripts/skills/taoist_support_policy.gd"
)

const TaoistFriendlyTargetingScript := preload(
	"res://scripts/skills/taoist_friendly_targeting.gd"
)

const WarriorMeleeGeometryScript := preload("res://scripts/skills/warrior_melee_geometry.gd")

const WarriorMeleeDiagnosticScript := preload("res://scripts/skills/warrior_melee_diagnostic.gd")

const SkillRuntimeClassificationScript := preload("res://scripts/skills/skill_runtime_classification.gd")

const CasterSpellGeometryScript := preload("res://scripts/skills/caster_spell_geometry.gd")

const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)

const SkillFootprintQueryPlanScript := preload(
	"res://scripts/skills/skill_footprint_query_plan.gd"
)

const SpellTargetLockPolicyScript := preload(
	"res://scripts/skills/spell_target_lock_policy.gd"
)

const SkillResourceServiceScript := preload(
	"res://scripts/skills/skill_resource_service.gd"
)

const SkillVisibilityPolicyScript := preload(
	"res://scripts/skills/skill_visibility_policy.gd"
)

const SKILL_PRODUCTION_ADAPTER_CONTRACT := "skills.production_adaptation.hardcore.v1"

const ATTACK_LOCK_CONTRACT := "combat.attack_lock.euclidean_gu.v2"

const ATTACK_LOCK_RANGE_GU := 10.0

const WILD_RUSH_SKILL_ID := "warrior.wild_rush"

const FIRE_WALL_SKILL_ID := "wizard.fire_wall"

const TAOIST_HEAL_SKILL_IDS := {
	"taoist.healing": true,
	"taoist.mass_healing": true,
}

const TAOIST_SUPPORT_SKILL_IDS := {
	"taoist.healing": true,
	"taoist.mass_healing": true,
	"taoist.mass_invisibility": true,
	"taoist.magic_defense": true,
	"taoist.defense": true,
}

const RANDOM_TELEPORT_MAX_ATTEMPTS := 256

const SKILL_TELEPORT_MAX_ATTEMPTS := 96

const SKILL_TELEPORT_MIN_DISTANCE_GU := 3.0

const SKILL_TELEPORT_MAX_DISTANCE_GU := 16.25

const RANDOM_TELEPORT_ACTOR_CLEARANCE_GU := 0.25

const CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU := 2.0

const CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU := 8

const CANONICAL_SUMMON_ACTOR_CLEARANCE_GU := 0.05

const CANONICAL_WIZARD_GEOMETRY_SKILLS := [
	"wizard.hellfire",
	"wizard.hell_lightning",
	"wizard.laser",
]

const CONTINUOUS_WIZARD_LINE_SKILLS := [
	"wizard.hellfire",
	"wizard.laser",
]

const CONTINUOUS_AIM_LINE_CONTRACT_ID_LEGACY := (
	"skills.wizard.line.continuous_tile_axis_footprint_sat.v1"
)

const GROUND_EXACT_SKILL_IDS := {
	"wizard.repulsion_ring": true,
	"wizard.exploding_flame": true,
	"wizard.fire_wall": true,
	"wizard.hell_lightning": true,
	"wizard.ice_storm": true,
	"taoist.mass_invisibility": true,
	"taoist.magic_defense": true,
	"taoist.defense": true,
	"taoist.entrapment": true,
	"taoist.mass_healing": true,
}

const TARGET_FOOTPRINT_SKILL_IDS := {
	"wizard.lightning": true,
	"wizard.temptation_light": true,
	"wizard.holy_word": true,
	"taoist.healing": true,
	"taoist.poison": true,
	"taoist.revelation": true,
}

const ATTACHED_STATE_SKILL_IDS := {
	"wizard.magic_shield": true,
	"taoist.invisibility": true,
}

const FIRE_WALL_MAX_ACTIVE_FIELDS_PER_CASTER := 8

const FIRE_WALL_CAP_POLICY_EVICT_OLDEST := "evict_oldest"

const FIRE_WALL_CAP_POLICY_REJECT_NEW := "reject_new"

const TargetQueryCore := preload("res://scripts/gameplay/world/world_skill_target_query.gd")

const REQUIRED_PORTS := {
  "world": [
    "discard_cast_birth",
    "fault",
    "is_inside_world",
    "is_queued_for_retirement",
    "register_cast_model",
    "register_passive_wake_emitter",
    "set_player_world_position",
    "try_safe_ring_teleport",
    "wire_canonical_main_pet_persistence"
  ],
  "actors": [
    "actor_view",
    "actors_in_group",
    "capture",
    "cast_target",
    "is_in_parent_scope",
    "is_inside_world",
    "is_kind",
    "is_queued_for_retirement",
    "is_runtime_present",
    "locked_target",
    "magic_locked_target",
    "magic_shield_auto_refresh_ratio",
    "owner_model",
    "player",
    "position_screen_px",
    "resolve_runtime_model",
    "runtime_actor_id",
    "set_cast_target",
    "set_locked_target",
    "set_magic_locked_target",
    "set_position_screen_px",
    "stop_velocity"
  ],
  "clock": [
    "now_msec",
    "now_usec"
  ],
  "profile": [
    "action_configuration_versions",
    "apply_taoist_main_pet_runtime_states",
    "canonical_material_item_name",
    "canonical_skill_resource_context",
    "clear_taoist_main_pet_runtime_state",
    "effective_skill_definition",
    "effective_skill_level",
    "feature_bundle",
    "has_special_effect",
    "is_skill_available",
    "is_skill_learned",
    "item_count",
    "remove_item",
    "skill_name_for_slot",
    "taoist_main_pet_runtime_states_for_restore",
    "try_trigger_relic_proc"
  ],
  "input": [
    "button_lifecycle_snapshot",
    "button_owns_lifecycle_input",
    "gameplay_input_is_enabled",
    "has_button_lifecycle_owner",
    "has_button_lifecycle_snapshot",
    "is_action_just_pressed",
    "is_action_pressed"
  ],
  "presentation": [
    "build_melee_input_diagnostic",
    "play_skill_audio_phase",
    "record_melee_release_diagnostic",
    "redraw_cast",
    "refresh_target_highlights",
    "show_attack_flash",
    "show_error_message",
    "show_message",
    "spawn_canonical_teleport_arrival",
    "spawn_target_aligned_melee_visual",
    "update_target_hud",
    "update_warrior_states"
  ],
  "casting": [
    "bind_field_retirement",
    "configure_summon_spatial_index",
    "create_cast_models_from_canonical_plan",
    "create_fire_wall_model",
    "create_ground_model",
    "create_projectile_model",
    "create_summon_model",
    "setup_summon_model"
  ],
  "diagnostics": [
    "combat_capture_enabled",
    "combat_record",
    "footprint_capture_enabled",
    "footprint_record",
    "increment_performance_counter",
    "record_performance_max",
    "record_timing_usec",
    "set_performance_release_context",
    "timing_elapsed_usec",
    "timing_start"
  ],
  "engagement": [
    "on_field_spawned",
    "on_ground_damage_tick"
  ],
  "geometry": [
    "call",
    "environment_blocks_actor_screen_px",
    "has_method",
    "is_environment_point_blocked",
    "is_present"
  ],
  "combat": [
    "apply_damage",
    "apply_enemy_direct_spell_damage",
    "apply_enemy_physical_damage",
    "apply_feature_child_damage",
    "face_target_screen_px"
  ],
  "spatial": [
    "query_enemy_nodes_aabb_into",
    "query_aabb_candidates",
    "query_segment_candidates"
  ],
  "feature_runtime": [
    "create_damage_batch",
    "reserve_action",
    "submit_batch"
  ],
  "feature_target_bound": [
    "snapshot",
    "sync_world"
  ],
  "fields": [
    "read_field",
    "write_field"
  ],
  "random": [
    "randi",
    "randi_range",
    "randf_range"
  ],
  "execution": [
    "activate_magic_skill_domain",
    "try_release_skill",
    "request_mobile_attack"
  ]
}

const REQUIRED_VALUE_PORTS := ["world", "random", "rules", "geometry", "casting", "diagnostics", "engagement", "combat", "spatial", "world_context", "time_domains", "feature_runtime", "feature_target_bound"]


func _invalidate_player_safe_zone_cache() -> void:
	if not _owned(): return
	_player_safe_zone_cache = {
		"player_instance_id": (
			_actors.runtime_actor_id(player)
			if _actors.is_runtime_present(player)
			else 0
		),
		"map_id": current_map_id,
		"revision": int(_safe_zone_context.get("revision", -1)),
		"generation": _zone_generation,
		"ground_position_gu": Vector2.INF,
		"inside": false,
		"valid": false,
	}


func _refresh_player_safe_zone_cache(force = false) -> bool:
	if not _owned(): return false
	# A formally compiled empty map has no safety geometry. Dungeon movement,
	# attacks and casting must not project points or rebuild a player cache.
	if bool(_safe_zone_context.get("valid", false)) and _active_safe_zones.is_empty():
		return false
	if not _actors.is_runtime_present(player):
		_invalidate_player_safe_zone_cache()
		return false
	var context_valid = bool(_safe_zone_context.get("valid", false))
	var ground_position_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	var context_revision = int(_safe_zone_context.get("revision", -1))
	var player_instance_id = _actors.runtime_actor_id(player)
	if (
		not force
		and int(_player_safe_zone_cache.get("player_instance_id", 0)) == player_instance_id
		and int(_player_safe_zone_cache.get("map_id", -1)) == current_map_id
		and int(_player_safe_zone_cache.get("revision", -1)) == context_revision
		and int(_player_safe_zone_cache.get("generation", -1)) == _zone_generation
		and _player_safe_zone_cache.get("ground_position_gu", Vector2.INF) is Vector2
		and (_player_safe_zone_cache["ground_position_gu"] as Vector2).is_equal_approx(ground_position_gu)
	):
		return bool(_player_safe_zone_cache.get("inside", false))
	var inside = (
		true
		if not context_valid
		else WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			ground_position_gu,
			_active_safe_zones,
		)
	)
	_player_safe_zone_cache = {
		"player_instance_id": player_instance_id,
		"map_id": current_map_id,
		"revision": context_revision,
		"generation": _zone_generation,
		"ground_position_gu": ground_position_gu,
		"inside": inside,
		"valid": context_valid and ground_position_gu.is_finite(),
	}
	return inside


func _player_inside_active_safe_zone() -> bool:
	if not _owned(): return false
	return _refresh_player_safe_zone_cache()


func _aoe_reference_fallback_allowed() -> bool:
	if not _owned(): return false
	return reference_audit_mode or _aoe_reference_fallback_test_enabled


func _aoe_reference_enemy_nodes_into(output: Array) -> bool:
	if not _owned(): return false
	output.clear()
	if not _aoe_reference_fallback_allowed():
		return false
	_diagnostics.increment_performance_counter(
		&"aoe_full_enemy_group_scans"
	)
	for value: Variant in _actors.actors_in_group("enemies"):
		if (
			_actors.is_kind(value, &"enemy")
			and _actors.is_runtime_present(value)
			and not _actors.is_queued_for_retirement(value)
			and not bool(value._dying)
			and not bool(value._death_pending)
			and value.current_hp > 0
		):
			output.append(value)
	_diagnostics.increment_performance_counter(
		&"aoe_spatial_candidates",
		output.size(),
	)
	return true


func _target_spatial_query_ready() -> bool:
	if not _owned(): return false
	## Player target/occupancy paths are formal mapped-world consumers.  A
	## missing index or projection is a rejection, never an implicit group scan.
	if (
		_spatial == null
		or not is_instance_valid(_spatial)
		or current_map_id < 0
	):
		projection_rejection_reason = &"target_spatial_index_unavailable"
		return false
	var profile = _resolve_projection_profile_for_map(current_map_id)
	if not bool(profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(profile.get(
			"reason",
			GroundUnitSpaceScript.REASON_INVALID_RUNTIME_PROJECTION,
		))
		return false
	var screen_to_ground: Variant = profile.get("screen_to_ground", Callable())
	var ground_to_screen: Variant = profile.get("ground_to_screen", Callable())
	if (
		not screen_to_ground is Callable
		or not (screen_to_ground as Callable).is_valid()
		or not ground_to_screen is Callable
		or not (ground_to_screen as Callable).is_valid()
	):
		missing_projection_rejection_count += 1
		projection_rejection_reason = &"target_spatial_projection_unavailable"
		return false
	return true


func _target_spatial_enemy_is_current(enemy: Object) -> bool:
	if not _owned(): return false
	return (
		_actors.is_runtime_present(enemy)
		and not _actors.is_queued_for_retirement(enemy)
		and not enemy._dying
		and not enemy._death_pending
		and enemy.current_hp > 0
		and enemy.runtime_map_id == current_map_id
		and enemy.projection_ready()
		and int(_actors.read_meta(enemy, "zone_generation", -1)) == _zone_generation
	)


func _target_query_service() -> Object:
	if not _owned(): return null
	if (
		_combat_target_query_service == null
		or _combat_target_query_service_map_id != current_map_id
		or _combat_target_query_service_index != _spatial
	):
		_combat_target_query_service = TargetQueryCore.new(
			_spatial, current_map_id, _actors
		)
		_combat_target_query_service_map_id = current_map_id
		_combat_target_query_service_index = _spatial
	return _combat_target_query_service


func _service_envelope_into(
	bounds_ground_gu: Rect2,
	output: Array,
	stable_order: bool = true,
) -> bool:
	if not _owned(): return false
	var service = _target_query_service()
	var service_ready = service.query_envelope_into(
		bounds_ground_gu, output, stable_order
	)
	if not service_ready and service.last_rejection_reason() != "":
		projection_rejection_reason = StringName(
			"target_query_%s" % service.last_rejection_reason()
		)
	return service_ready


func _target_spatial_query_aabb_into(
	bounds_ground_gu: Rect2,
	output: Array,
	stable_order: bool = true,
) -> bool:
	if not _owned(): return false
	output.clear()
	if (
		not _target_spatial_query_ready()
		or not bounds_ground_gu.position.is_finite()
		or not bounds_ground_gu.size.is_finite()
		or bounds_ground_gu.size.x < 0.0
		or bounds_ground_gu.size.y < 0.0
	):
		if bounds_ground_gu.size.x < 0.0 or bounds_ground_gu.size.y < 0.0:
			projection_rejection_reason = &"target_spatial_query_bounds_invalid"
		return false
	var service_ready = _service_envelope_into(bounds_ground_gu, output, stable_order)
	var write_index = 0
	for raw_enemy: Variant in output:
		if not _actors.is_kind(raw_enemy, &"enemy"):
			continue
		var enemy = raw_enemy
		if not _target_spatial_enemy_is_current(enemy):
			continue
		output[write_index] = enemy
		write_index += 1
	output.resize(write_index)
	return service_ready


func _target_spatial_query_segment_into(
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float,
	output: Array,
	stable_order: bool = true,
) -> bool:
	if not _owned(): return false
	output.clear()
	if (
		not _target_spatial_query_ready()
		or not start_ground_gu.is_finite()
		or not end_ground_gu.is_finite()
		or not is_finite(expansion_gu)
	):
		if not is_finite(expansion_gu):
			projection_rejection_reason = &"target_spatial_query_expansion_invalid"
		return false
	# PERF-1: the segment broadphase enters the service fast path as one
	# expanded AABB with the exact envelope the index node query built
	# (segment AABB expanded by the caller's expansion); with epsilon 0 the
	# service adds only the index max actor bounds on top, so the candidate
	# set is identical to the direct node query it replaces.
	var expansion = maxf(0.0, expansion_gu)
	var min_gu = Vector2(
		minf(start_ground_gu.x, end_ground_gu.x),
		minf(start_ground_gu.y, end_ground_gu.y)
	) - Vector2.ONE * expansion
	var max_gu = Vector2(
		maxf(start_ground_gu.x, end_ground_gu.x),
		maxf(start_ground_gu.y, end_ground_gu.y)
	) + Vector2.ONE * expansion
	var service_ready = _service_envelope_into(
		Rect2(min_gu, max_gu - min_gu), output, stable_order
	)
	var write_index = 0
	for raw_enemy: Variant in output:
		if not _actors.is_kind(raw_enemy, &"enemy"):
			continue
		var enemy = raw_enemy
		if not _target_spatial_enemy_is_current(enemy):
			continue
		output[write_index] = enemy
		write_index += 1
	output.resize(write_index)
	return service_ready


func _aoe_build_query_plan(
	skill_id: String,
	release_id: String,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary,
	release_cache: Dictionary,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	if snapshot.is_empty() or skill_id.is_empty() or release_id.is_empty():
		return {}
	var was_cached = release_cache.has(release_id)
	var strict_count_before = SkillFootprintQueryPlanScript.strict_validation_count
	var plan = SkillFootprintQueryPlanScript.build_once(
		release_cache,
		release_id,
		skill_id,
		current_map_id,
		snapshot,
		validation_context,
		options,
	)
	if not was_cached:
		_diagnostics.increment_performance_counter(
			&"aoe_query_plan_builds"
		)
		if SkillFootprintQueryPlanScript.strict_validation_count > strict_count_before:
			_diagnostics.increment_performance_counter(
				&"aoe_snapshot_validation_calls"
			)
	return plan


func _aoe_plan_snapshot(plan: Dictionary) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var raw_snapshot: Variant = plan.get("validated_snapshot_reference", {})
	return raw_snapshot as Dictionary if raw_snapshot is Dictionary else {}


func _aoe_plan_is_ready(plan: Dictionary) -> bool:
	if not _owned(): return false
	if (
		plan.is_empty()
		or not bool(plan.get("valid", false))
		or _spatial == null
		or not is_instance_valid(_spatial)
		or current_map_id < 0
		or int(plan.get("runtime_map_id", -1)) != current_map_id
	):
		return false
	var snapshot = _aoe_plan_snapshot(plan)
	return str(snapshot.get("coordinate_space", "")) == str(
		SkillFootprintSnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	)


func _aoe_record_query_rejection(reason: String) -> void:
	if not _owned(): return
	projection_rejection_reason = reason


func _aoe_query_enemy_candidates_aabb(
	plan: Dictionary,
	bounds_ground_gu: Rect2,
	allow_reference_fallback = true,
) -> bool:
	if not _owned(): return false
	_aoe_candidate_scratch.clear()
	if _aoe_plan_is_ready(plan):
		_diagnostics.increment_performance_counter(
			&"aoe_spatial_queries"
		)
		if (
			not bounds_ground_gu.position.is_finite()
			or not bounds_ground_gu.size.is_finite()
			or bounds_ground_gu.size.x < 0.0
			or bounds_ground_gu.size.y < 0.0
		):
			# The replaced index node query answered invalid envelopes with
			# an empty candidate set and no rejection; keep that behavior.
			_diagnostics.increment_performance_counter(
				&"aoe_spatial_candidates", 0
			)
			return true
		var query_ready = _service_envelope_into(
			bounds_ground_gu, _aoe_candidate_scratch
		)
		_diagnostics.increment_performance_counter(
			&"aoe_spatial_candidates", _aoe_candidate_scratch.size()
		)
		return query_ready
	if allow_reference_fallback and _aoe_reference_fallback_allowed():
		return _aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
	_aoe_record_query_rejection(
		"aoe_spatial_index_unavailable_or_runtime_map_mismatch"
	)
	return false


func _aoe_query_enemy_candidates_segment(
	plan: Dictionary,
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float,
	allow_reference_fallback = true,
) -> bool:
	if not _owned(): return false
	_aoe_candidate_scratch.clear()
	if _aoe_plan_is_ready(plan):
		_diagnostics.increment_performance_counter(
			&"aoe_spatial_queries"
		)
		if (
			not start_ground_gu.is_finite()
			or not end_ground_gu.is_finite()
			or not is_finite(expansion_gu)
		):
			# The replaced index node query answered invalid segments with
			# an empty candidate set and no rejection; keep that behavior.
			_diagnostics.increment_performance_counter(
				&"aoe_spatial_candidates", 0
			)
			return true
		var expansion = maxf(0.0, expansion_gu)
		var min_gu = Vector2(
			minf(start_ground_gu.x, end_ground_gu.x),
			minf(start_ground_gu.y, end_ground_gu.y)
		) - Vector2.ONE * expansion
		var max_gu = Vector2(
			maxf(start_ground_gu.x, end_ground_gu.x),
			maxf(start_ground_gu.y, end_ground_gu.y)
		) + Vector2.ONE * expansion
		var query_ready = _service_envelope_into(
			Rect2(min_gu, max_gu - min_gu), _aoe_candidate_scratch
		)
		_diagnostics.increment_performance_counter(
			&"aoe_spatial_candidates", _aoe_candidate_scratch.size()
		)
		return query_ready
	if allow_reference_fallback and _aoe_reference_fallback_allowed():
		return _aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
	_aoe_record_query_rejection(
		"aoe_spatial_index_unavailable_or_runtime_map_mismatch"
	)
	return false


func _aoe_validated_snapshot_intersects(
	plan: Dictionary,
	enemy: Object,
) -> bool:
	if not _owned(): return false
	if not _aoe_plan_is_ready(plan) or not _actors.is_runtime_present(enemy):
		return false
	var target_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy))
	if not target_ground_gu.is_finite():
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		_aoe_plan_snapshot(plan),
		target_ground_gu,
		enemy.combat_radius_gu,
	)


func _aoe_insert_by_instance_id(
	targets: Array,
	ids: Array[int],
	enemy: Object,
) -> void:
	if not _owned(): return
	var enemy_id = _actors.runtime_actor_id(enemy)
	var insert_at = targets.size()
	for index: int in range(ids.size()):
		if enemy_id < ids[index]:
			insert_at = index
			break
	ids.insert(insert_at, enemy_id)
	targets.insert(insert_at, enemy)


func _aoe_insert_by_distance(
	targets: Array,
	distances: Array[float],
	ids: Array[int],
	enemy: Object,
	distance_along_line_gu: float,
) -> void:
	if not _owned(): return
	var enemy_id = _actors.runtime_actor_id(enemy)
	var insert_at = targets.size()
	for index: int in range(targets.size()):
		if (
			distance_along_line_gu < distances[index]
			or (
				is_equal_approx(distance_along_line_gu, distances[index])
				and enemy_id < ids[index]
			)
		):
			insert_at = index
			break
	distances.insert(insert_at, distance_along_line_gu)
	ids.insert(insert_at, enemy_id)
	targets.insert(insert_at, enemy)


func _aoe_geometry_cells_aabb(cells: Array[Vector2i]) -> Rect2:
	if not _owned(): return Rect2()
	if cells.is_empty():
		return Rect2()
	var minimum = Vector2(cells[0]) - Vector2.ONE * 0.5
	var maximum = Vector2(cells[0]) + Vector2.ONE * 0.5
	for cell: Vector2i in cells:
		var center = Vector2(cell)
		minimum = minimum.min(center - Vector2.ONE * 0.5)
		maximum = maximum.max(center + Vector2.ONE * 0.5)
	return Rect2(minimum, maximum - minimum)


func _aoe_legacy_damage_query_plan(
	skill_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	radius_gu: float,
	release_cache: Dictionary,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var resolved_skill_id = skill_id if not skill_id.is_empty() else "legacy_damage"
	var snapshot = SkillFootprintSnapshotScript.create_circle(
		resolved_skill_id,
		"legacy_damage",
		origin_ground_gu,
		maxf(0.0, radius_gu),
		32,
		_canonical_snapshot_absolute_context(origin_ground_gu),
	)
	var options = {
		"maximum_targets": -1,
		"query_kind": SkillFootprintQueryPlanScript.QUERY_KIND_AABB,
		"ordering_policy": SkillFootprintQueryPlanScript.ORDERING_STABLE_COMBAT_INSTANCE,
		"line_origin_ground_gu": origin_ground_gu,
		"line_direction_ground_gu": direction_ground_gu,
	}
	return _aoe_build_query_plan(
		resolved_skill_id,
		"legacy_damage",
		snapshot,
		_canonical_snapshot_validation_context(origin_ground_gu),
		options,
		release_cache,
	)


func _aoe_apply_legacy_damage_candidates(
	candidates: Array,
	origin_screen_px: Vector2,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	damage: int,
	radial: bool,
	attack_range_gu: float,
	physical_accuracy: bool,
	source_skill_id: String,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var hit_any = false
	var geometry_matches = 0
	for enemy: Object in candidates:
		if (
			not _actors.is_runtime_present(enemy)
			or _actors.is_queued_for_retirement(enemy)
			or enemy.current_hp <= 0
		):
			continue
		_diagnostics.increment_performance_counter(
			&"aoe_exact_intersection_tests"
		)
		var target_ground_gu = _canonical_screen_px_to_ground_gu(
			_actors.position_screen_px(enemy)
		)
		var offset_ground_gu = target_ground_gu - origin_ground_gu
		var in_arc = (
			offset_ground_gu.length_squared()
			<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
			or offset_ground_gu.normalized().dot(direction_ground_gu) > -0.05
		)
		if not (
			_ground_circle_intersects_enemy_footprint_gu(
				origin_screen_px,
				attack_range_gu,
				enemy,
			)
			and (radial or in_arc)
		):
			continue
		geometry_matches += 1
		_diagnostics.increment_performance_counter(
			&"aoe_selected_targets"
		)
		_diagnostics.increment_performance_counter(
			&"aoe_damage_target_count"
		)
		if physical_accuracy and not _profile.test_mode:
			var accuracy = int(_profile.computed_stats.get("accuracy", _rules.warrior.BASE_HIT))
			if not _rules.warrior.roll_hit(accuracy, enemy.agility, _random):
				continue
		var resolved_damage = damage
		if CombatResolutionRulesScript.anti_magic_eligible(source_skill_id):
			var resolution: Dictionary = _combat.apply_enemy_direct_spell_damage(
				enemy,
				source_skill_id,
				damage,
				player,
				_random,
				Callable(self, "_resolve_magic_defense"),
				-1,
				_direct_spell_target_stats_scratch,
				# source176 Task 1: generic AoE applier - the registry resolves
				# the per-skill delivery family; unknown ids fail closed.
				_combat.EnemyMagicDeliveryKind.AUTO,
			)
			resolved_damage = int(resolution.get("final_damage", 0))
			if resolved_damage > 0:
				hit_any = true
			continue
		if resolved_damage <= 0:
			continue
		hit_any = _combat.apply_enemy_physical_damage(
			enemy,
			resolved_damage,
			player,
			(
				{
					"damage_kind": "player_physical",
					"confirmed_hit": true,
					"source_skill_id": source_skill_id,
					"source": "game_root._aoe_apply_legacy_damage_candidates",
				}
				if physical_accuracy
				and not CombatResolutionRulesScript.anti_magic_eligible(source_skill_id)
				else {}
			),
		) or hit_any
	return {
		"hit_any": hit_any,
		"geometry_matches": geometry_matches,
	}


func _aoe_melee_query_plan(
	mode: String,
	origin_ground_gu: Vector2,
	direction: Vector2,
	release_geometry: Dictionary,
	thrust_damage_axis_plan: Dictionary,
	melee_release_snapshot: Dictionary,
	target_aligned_plan: Dictionary,
	release_cache: Dictionary,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var snapshot = melee_release_snapshot
	if snapshot.is_empty():
		var raw_snapshot: Variant = release_geometry.get(
			"skill_footprint_snapshot", {}
		)
		if raw_snapshot is Dictionary:
			snapshot = raw_snapshot as Dictionary
	if snapshot.is_empty() and not target_aligned_plan.is_empty():
		var raw_target_snapshot: Variant = target_aligned_plan.get(
			"skill_footprint_snapshot", {}
		)
		if raw_target_snapshot is Dictionary:
			snapshot = raw_target_snapshot as Dictionary
	if snapshot.is_empty():
		var raw_axis_snapshot: Variant = thrust_damage_axis_plan.get(
			"skill_footprint_snapshot", {}
		)
		if raw_axis_snapshot is Dictionary:
			snapshot = raw_axis_snapshot as Dictionary
	var skill_id: String = {
		WarriorMeleeGeometryScript.SKILL_THRUST: "warrior.thrusting",
		WarriorMeleeGeometryScript.SKILL_HALF_MOON: "warrior.half_moon",
		WarriorMeleeGeometryScript.SKILL_FIRE: "warrior.fire_sword",
	}.get(mode, "warrior.normal_attack")
	var release_id = str(release_geometry.get("release_id", ""))
	if release_id.is_empty() and not snapshot.is_empty():
		release_id = str(snapshot.get("release_id", ""))
	if release_id.is_empty():
		release_id = "melee:preflight:%s" % mode
	if snapshot.is_empty():
		var direction_index = _melee_direction_index(direction, release_geometry)
		snapshot = WarriorMeleeGeometryScript.attack_release_footprint_snapshot_ground_gu(
			skill_id,
			release_id,
			origin_ground_gu,
			direction_index,
			mode,
			0.0,
			_canonical_snapshot_absolute_context(origin_ground_gu),
		)
	var options = {
		"maximum_targets": -1,
		"query_kind": SkillFootprintQueryPlanScript.QUERY_KIND_AABB,
		"ordering_policy": SkillFootprintQueryPlanScript.ORDERING_STABLE_COMBAT_INSTANCE,
	}
	var validation_context: Dictionary = release_geometry.get(
		"snapshot_validation_context",
		_canonical_snapshot_validation_context(origin_ground_gu),
	)
	if validation_context.is_empty():
		validation_context = _canonical_snapshot_validation_context(origin_ground_gu)
	return _aoe_build_query_plan(
		skill_id,
		release_id,
		snapshot,
		validation_context,
		options,
		release_cache,
	)


func _aoe_collect_primary_melee_candidates(
	candidates: Array,
	result: Array,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	thrust_damage_axis_plan: Dictionary,
	melee_release_snapshot: Dictionary,
	target_aligned_plan: Dictionary,
	query_plan: Dictionary,
) -> void:
	if not _owned(): return
	for enemy: Object in candidates:
		if not _is_primary_melee_candidate(
			enemy,
			origin_ground_gu,
			direction_index,
			mode,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			target_aligned_plan,
			query_plan,
		):
			continue
		result.append(enemy)


func _aoe_target_aligned_melee_sector(
	target_plan: Dictionary,
	target_ground_gu: Vector2,
	target_radius_gu: float,
	mode: String,
) -> int:
	if not _owned(): return 0
	if not bool(target_plan.get("target_axis_eligible", false)):
		return -1
	var raw_snapshot: Variant = target_plan.get("skill_footprint_snapshot", {})
	if not raw_snapshot is Dictionary:
		return -1
	var snapshot = raw_snapshot as Dictionary
	if not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		snapshot,
		target_ground_gu,
		target_radius_gu,
	):
		return -1
	var origin_ground_gu: Vector2 = target_plan.get(
		"origin_ground_gu", Vector2.ZERO
	)
	var axis_ground_gu: Vector2 = target_plan.get(
		"continuous_axis_ground_gu", Vector2.ZERO
	)
	if mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		return WarriorMeleeGeometryScript.thrust_footprint_slot_for_direction_ground_gu(
			origin_ground_gu,
			target_ground_gu,
			target_radius_gu,
			axis_ground_gu,
		)
	if mode != WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		return 0
	var effective_reach_gu = WarriorMeleeGeometryScript.reach_gu(
		WarriorMeleeGeometryScript.SKILL_HALF_MOON,
		float(target_plan.get("range_bonus_gu", 0.0)),
	)
	if WarriorMeleeGeometryScript.footprint_intersects_continuous_direction_sector_gu(
		origin_ground_gu,
		target_ground_gu,
		target_radius_gu,
		axis_ground_gu,
		effective_reach_gu,
	):
		return 0
	if WarriorMeleeGeometryScript.footprint_intersects_continuous_direction_sector_gu(
		origin_ground_gu,
		target_ground_gu,
		target_radius_gu,
		axis_ground_gu.rotated(-PI / 4.0),
		effective_reach_gu,
	):
		return 7
	if WarriorMeleeGeometryScript.footprint_intersects_continuous_direction_sector_gu(
		origin_ground_gu,
		target_ground_gu,
		target_radius_gu,
		axis_ground_gu.rotated(PI / 4.0),
		effective_reach_gu,
	):
		return 1
	if WarriorMeleeGeometryScript.footprint_intersects_continuous_direction_sector_gu(
		origin_ground_gu,
		target_ground_gu,
		target_radius_gu,
		axis_ground_gu.rotated(PI / 2.0),
		effective_reach_gu,
	):
		return 2
	return -1


func _aoe_spell_snapshot(
	skill_release_snapshot: Dictionary,
	continuous_line_strip_ground_gu: Dictionary,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	if not skill_release_snapshot.is_empty():
		return skill_release_snapshot
	var raw_snapshot: Variant = continuous_line_strip_ground_gu.get(
		"skill_footprint_snapshot", {}
	)
	return raw_snapshot as Dictionary if raw_snapshot is Dictionary else {}


func _aoe_spell_query_plan(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	continuous_line_strip_ground_gu: Dictionary,
	skill_release_snapshot: Dictionary,
	origin_ground_gu: Vector2,
	release_cache: Dictionary,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var snapshot = _aoe_spell_snapshot(
		skill_release_snapshot,
		continuous_line_strip_ground_gu,
	)
	if snapshot.is_empty():
		return {}
	var resolved_skill_id = stable_skill_id
	if resolved_skill_id.is_empty():
		resolved_skill_id = str(snapshot.get("skill_id", ""))
	if resolved_skill_id.is_empty():
		resolved_skill_id = "canonical_aoe"
	var release_id = str(snapshot.get("release_id", ""))
	if release_id.is_empty():
		release_id = str(continuous_line_strip_ground_gu.get("release_id", ""))
	if release_id.is_empty():
		return {}
	var maximum_targets = int(effect.get("maximum_targets", -1))
	var is_continuous_line = (
		resolved_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		and _is_supported_continuous_line_contract(
			str(continuous_line_strip_ground_gu.get("contract_id", ""))
		)
	)
	if is_continuous_line and str(effect.get("target_limit_policy", "")) == "all_intersecting_effect_cells":
		maximum_targets = -1
	var ordering_policy = SkillFootprintQueryPlanScript.ORDERING_STABLE_COMBAT_INSTANCE
	if str(snapshot.get("shape_type", "")) == SkillFootprintSnapshotScript.SHAPE_CELL_UNION:
		ordering_policy = SkillFootprintQueryPlanScript.ORDERING_CELL_INSTANCE
	elif raw_geometry_cells is Array and not (raw_geometry_cells as Array).is_empty():
		ordering_policy = SkillFootprintQueryPlanScript.ORDERING_CELL_INSTANCE
	var options = {
		"maximum_targets": maximum_targets,
		"query_kind": (
			SkillFootprintQueryPlanScript.QUERY_KIND_SEGMENT
			if is_continuous_line
			else SkillFootprintQueryPlanScript.QUERY_KIND_AABB
		),
		"ordering_policy": (
			SkillFootprintQueryPlanScript.ORDERING_DISTANCE_INSTANCE
			if is_continuous_line
			else ordering_policy
		),
	}
	if raw_geometry_cells is Array and not (raw_geometry_cells as Array).is_empty():
		var cell_sequence: Array[Vector2i] = []
		for raw_cell: Variant in raw_geometry_cells as Array:
			if raw_cell is Vector2i:
				cell_sequence.append(raw_cell)
		if not cell_sequence.is_empty():
			options["cell_sequence"] = cell_sequence
	if is_continuous_line:
		var line_origin: Variant = continuous_line_strip_ground_gu.get(
			"origin_ground_gu", snapshot.get("origin_ground_gu", origin_ground_gu)
		)
		var line_direction: Variant = continuous_line_strip_ground_gu.get(
			"direction_ground_gu", snapshot.get("direction_ground_gu", Vector2.ZERO)
		)
		if line_origin is Vector2:
			options["line_origin_ground_gu"] = line_origin
		if line_direction is Vector2:
			options["line_direction_ground_gu"] = line_direction
	var snapshot_origin: Variant = snapshot.get("origin_ground_gu", origin_ground_gu)
	var validation_origin = (
		snapshot_origin as Vector2 if snapshot_origin is Vector2 else origin_ground_gu
	)
	return _aoe_build_query_plan(
		resolved_skill_id,
		release_id,
		snapshot,
		_canonical_snapshot_validation_context(validation_origin),
		options,
		release_cache,
	)


func _request_mobile_attack() -> bool:
	if not _owned(): return false
	if not _input.gameplay_input_is_enabled() or not player.can_start_attack():
		return false
	_activate_physical_attack_domain()
	var target = _ensure_attack_locked_target()
	var facing_before = player.facing
	var touch_before = player.touch_vector
	var movement_was_active = player.movement_input_active
	var attack_direction = player.facing.normalized()
	if _actors.is_runtime_present(target):
		attack_direction = _face_locked_target()
	var melee_mode = _selected_warrior_melee_mode()
	var target_instance_id = _actors.runtime_actor_id(target) if _actors.is_runtime_present(target) else 0
	var input_release_geometry = CombatReleaseGeometryScript.resolve(
		_actors.position_screen_px(player),
		attack_direction,
		target_instance_id,
		_actors.position_screen_px(target) if _actors.is_runtime_present(target) else Vector2.ZERO,
		_actors.is_runtime_present(target),
		true,
		CombatReleaseGeometryScript.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
		target.combat_radius_gu if _actors.is_runtime_present(target) else 0.0
	)
	attack_direction = Vector2(
		input_release_geometry.get("direction_screen_px", attack_direction)
	).normalized()
	var input_has_hittable_target = _has_melee_hittable_target(
		attack_direction,
		melee_mode,
		input_release_geometry
	)
	var diagnostics_enabled = _diagnostics.combat_capture_enabled()
	var diagnostic: Dictionary = {}
	if diagnostics_enabled:
		diagnostic = _presentation.build_melee_input_diagnostic(
			target,
			melee_mode,
			attack_direction,
			input_release_geometry,
			input_has_hittable_target,
			facing_before,
			touch_before,
			movement_was_active
		)
	else:
		_pending_melee_diagnostic.clear()
	var accepted = player.request_attack_toward(
		attack_direction,
		input_has_hittable_target,
		target_instance_id
	)
	if accepted and diagnostics_enabled:
		diagnostic["event"] = "attack_input_accepted"
		diagnostic["facing_after_input"] = player.facing
		diagnostic["facing_after_input_index"] = ArtSpec.direction_index(player.facing)
		_pending_melee_diagnostic = diagnostic.duplicate(true)
		_diagnostics.combat_record(diagnostic)
	elif not accepted and diagnostics_enabled:
		diagnostic["event"] = "attack_input_rejected"
		diagnostic["reject_code"] = "PLAYER_REQUEST_REJECTED"
		_diagnostics.combat_record(diagnostic)
	return accepted


func _request_primary_attack_action() -> void:
	if not _owned(): return
	var bound_skill = _profile.skill_name_for_slot(
		_profile.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	if bound_skill.is_empty():
		_request_mobile_attack()
		return
	_use_skill_slot(_profile.SKILL_SLOT_GROUP_ATTACK, 0)


func _selected_warrior_melee_mode() -> String:
	if not _owned(): return ""
	if player.fire_sword_enabled:
		return WarriorMeleeGeometryScript.SKILL_FIRE
	if player.half_moon_enabled and _profile.is_skill_learned("warrior.half_moon"):
		return WarriorMeleeGeometryScript.SKILL_HALF_MOON
	if player.thrusting_enabled and _profile.is_skill_learned("warrior.thrusting"):
		return WarriorMeleeGeometryScript.SKILL_THRUST
	return WarriorMeleeGeometryScript.SKILL_NORMAL


func _has_melee_hittable_target(
	direction: Vector2,
	mode = "",
	release_geometry: Dictionary = {}
) -> bool:
	if not _owned(): return false
	if direction.length_squared() <= 0.01:
		return false
	var resolved_mode = mode if not mode.is_empty() else _selected_warrior_melee_mode()
	var release_origin_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	var melee_release_cache: Dictionary = {}
	var melee_query_plan = _aoe_melee_query_plan(
		resolved_mode,
		release_origin_ground_gu,
		direction.normalized(),
		release_geometry,
		{},
		release_geometry.get("skill_footprint_snapshot", {}),
		release_geometry.get("target_aligned_plan", {}),
		melee_release_cache,
	)
	var primary_targets = _physical_primary_targets(
		_actors.position_screen_px(player),
		direction.normalized(),
		resolved_mode,
		release_geometry,
		{},
		release_geometry.get("skill_footprint_snapshot", {}),
		release_geometry.get("target_aligned_plan", {}),
		melee_query_plan,
	)
	if not primary_targets.is_empty():
		return true
	if resolved_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		return not _thrust_secondary_targets(
			_actors.position_screen_px(player),
			direction.normalized(),
			primary_targets,
			release_geometry,
			{},
		release_geometry.get("skill_footprint_snapshot", {}),
		release_geometry.get("target_aligned_plan", {}),
		melee_query_plan,
		).is_empty()
	if resolved_mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		return not _half_moon_secondary_targets(
			_actors.position_screen_px(player),
			direction.normalized(),
			primary_targets,
			release_geometry,
		release_geometry.get("skill_footprint_snapshot", {}),
		melee_query_plan,
		).is_empty()
	return false


func _allocate_synthetic_attack_token() -> int:
	if not _owned(): return 0
	var token = _next_synthetic_attack_token
	_next_synthetic_attack_token -= 1
	return token


func _submit_mobile_attack_ticket(press_token: int) -> void:
	if not _owned(): return
	# Compatibility entry point only. A DOWN is an attempt, NOT a future debt.
	_queued_mobile_attack_tickets.clear()
	if press_token == 0:
		return
	_try_ordinary_attack_intent(&"fresh_down")


func _drain_next_mobile_attack_ticket() -> bool:
	if not _owned(): return false
	# Compatibility shim: an old caller can never resurrect deferred attacks.
	_queued_mobile_attack_tickets.clear()
	return false


func _refresh_mobile_attack_held() -> void:
	if not _owned(): return
	_mobile_attack_held = not _active_mobile_attack_tokens.is_empty()


func _on_mobile_attack_input_started(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled() or press_token == 0:
		return
	if _active_mobile_attack_tokens.has(press_token):
		return
	var ordinary_attack = _profile.skill_name_for_slot(
		_profile.SKILL_SLOT_GROUP_ATTACK, 0
	).is_empty()
	if not ordinary_attack:
		_on_skill_input_started(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source
		)
		return
	_active_mobile_attack_tokens[press_token] = {
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
		"started_at_ms": _clock.now_msec(),
	}
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_down", source, {
		"press_token": press_token, "touch_id": touch_id,
	})
	_submit_mobile_attack_ticket(press_token)


func _on_mobile_attack_input_ended(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_ended(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source
		)
		return
	if not _ordinary_attack_owner_matches(press_token, touch_id, source):
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.clear()
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_up", source, {
		"press_token": press_token, "touch_id": touch_id,
	})


func _on_mobile_attack_input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
) -> void:
	if not _owned(): return
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_cancelled(
			_profile.SKILL_SLOT_GROUP_ATTACK, 0,
			press_token, touch_id, source, reason
		)
		return
	if not _ordinary_attack_owner_matches(press_token, touch_id, source):
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.clear()
	_refresh_mobile_attack_held()
	_record_attack_action_diagnostic(&"pointer_cancel", reason, {
		"press_token": press_token, "touch_id": touch_id,
		"source": str(source),
	})


func _cancel_all_mobile_attack_inputs(_clear_tickets = false) -> void:
	if not _owned(): return
	# Retain the argument for old callers, but stale debt is never retained.
	_active_mobile_attack_tokens.clear()
	_mobile_attack_held = false
	_legacy_mobile_attack_token = 0
	_queued_mobile_attack_tickets.clear()


func _skill_input_key(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int
) -> String:
	if not _owned(): return ""
	return "%s:%d:%d:%d" % [slot_group, slot_index, press_token, touch_id]


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	if press_token == 0:
		return
	var input_key = _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	if _active_skill_inputs.has(input_key):
		return
	var skill_name = _profile.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		_presentation.show_error_message("技能栏为空")
		return
	var metadata = SkillInputPolicyScript.metadata(skill_name)
	if metadata.is_empty() or bool(metadata.get("passive", false)):
		return
	_execution.activate_magic_skill_domain()
	var entry = {
		"contract_id": SKILL_INPUT_TICKET_CONTRACT_ID,
		"input_key": input_key,
		"slot_group": slot_group,
		"slot_index": slot_index,
		"press_token": press_token,
		"touch_id": touch_id,
		"source": source,
		"skill_name": skill_name,
		"skill_id": str(metadata.get("skill_id", "")),
		"repeatable": bool(metadata.get("repeatable_offensive_spell", false)),
		"started_at_ms": _clock.now_msec(),
		"sequence": _next_skill_input_sequence,
	}
	_next_skill_input_sequence += 1
	_active_skill_inputs[input_key] = entry
	if bool(metadata.get("toggle", false)):
		# Keep the physical input active until UP/CANCEL so duplicate DOWN events
		# from the same touch cannot flip a toggle twice.
		_handle_toggle_skill_input(skill_name)
		return
	_submit_skill_input_ticket(entry)


func _on_skill_input_ended(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName
) -> void:
	if not _owned(): return
	_active_skill_inputs.erase(
		_skill_input_key(slot_group, slot_index, press_token, touch_id)
	)


func _on_skill_input_cancelled(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName,
	_reason: StringName
) -> void:
	if not _owned(): return
	var input_key = _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	_active_skill_inputs.erase(input_key)


func _cancel_all_skill_inputs(clear_tickets = false) -> void:
	if not _owned(): return
	_active_skill_inputs.clear()
	_keyboard_bound_skill_token = 0
	# Kept as an API-compatible argument for callers that clear attack and skill
	# input together. Skill clicks are no longer buffered past their physical
	# lifetime, so there are no deferred skill tickets to clear.
	if clear_tickets:
		_skill_input_retry_remaining = 0.0


func _reset_attack_action_lifecycle(reason: StringName) -> void:
	if not _owned(): return
	if _keyboard_bound_skill_token != 0:
		_on_skill_input_cancelled(
			_profile.SKILL_SLOT_GROUP_ATTACK,
			0,
			_keyboard_bound_skill_token,
			-4,
			&"keyboard",
			reason
		)
		_keyboard_bound_skill_token = 0
	_attack_action_press_owned = false
	_attack_action_neutral_observed = not _input.is_action_pressed("attack")
	_attack_action_ignored_pressed_recorded = false
	_attack_action_lifecycle_epoch += 1
	_record_attack_action_diagnostic(&"boundary", reason)


func _poll_attack_action_lifecycle(input_enabled: bool) -> Dictionary:
	if not _owned(): return {}
	var pressed = _input.is_action_pressed("attack")
	if not input_enabled:
		_attack_action_press_owned = false
		_attack_action_neutral_observed = not pressed
		return {"started": false, "ended": false, "active": false}
	if not pressed:
		var ended = _attack_action_press_owned
		_attack_action_press_owned = false
		_attack_action_neutral_observed = true
		_attack_action_ignored_pressed_recorded = false
		if ended:
			_record_attack_action_diagnostic(&"released", &"input_action")
		return {"started": false, "ended": ended, "active": false}
	if (
		not _attack_action_press_owned
		and _attack_action_neutral_observed
		and _input.is_action_just_pressed("attack")
	):
		_attack_action_press_owned = true
		_attack_action_neutral_observed = false
		_attack_action_ignored_pressed_recorded = false
		_record_attack_action_diagnostic(&"fresh_down", &"input_action")
		return {"started": true, "ended": false, "active": true}
	if not _attack_action_press_owned and not _attack_action_ignored_pressed_recorded:
		_attack_action_ignored_pressed_recorded = true
		_record_attack_action_diagnostic(&"pressed_without_fresh_down_ignored", &"input_action")
	return {"started": false, "ended": false, "active": _attack_action_press_owned}


func _record_attack_action_diagnostic(
	kind: StringName,
	reason: StringName,
	details: Dictionary = {}
) -> void:
	if not _owned(): return
	_attack_action_diagnostic_serial += 1
	var entry = {
		"serial": _attack_action_diagnostic_serial,
		"time_ms": _clock.now_msec(),
		"epoch": _attack_action_lifecycle_epoch,
		"kind": str(kind),
		"reason": str(reason),
		"pressed": _input.is_action_pressed("attack"),
		"touch_attack_held": _mobile_attack_held,
		"active_touch_count": _active_mobile_attack_tokens.size(),
		"queued_ticket_count": _queued_mobile_attack_tickets.size(),
		"map_id": current_map_id,
		"zone_generation": _zone_generation,
	}
	if is_instance_valid(player):
		entry["attack_timer"] = player._attack_timer
		entry["attack_action_timer"] = player._attack_action_timer
		entry["attack_cooldown"] = player.attack_cooldown
		entry["combat_action_sequence"] = player._combat_action_sequence
		entry["player_hp"] = player.current_hp
	if is_instance_valid(locked_target):
		entry["locked_target_id"] = _actors.runtime_actor_id(locked_target)
		entry["locked_target_hp"] = locked_target.current_hp
	else:
		entry["locked_target_id"] = 0
		entry["locked_target_hp"] = 0
	entry["details"] = details.duplicate(true)
	_attack_action_diagnostic_events.append(entry)
	while _attack_action_diagnostic_events.size() > ATTACK_ACTION_DIAGNOSTIC_LIMIT:
		_attack_action_diagnostic_events.pop_front()


func attack_action_lifecycle_snapshot() -> Dictionary:
	if not _owned(): return {}
	var result = {
		"contract_id": ATTACK_ACTION_LIFECYCLE_CONTRACT_ID,
		"ordinary_attack_contract_id": ATTACK_INPUT_TICKET_CONTRACT_ID,
		"epoch": _attack_action_lifecycle_epoch,
		"press_owned": _attack_action_press_owned,
		"neutral_observed": _attack_action_neutral_observed,
		"raw_attack_pressed": _input.is_action_pressed("attack"),
		"touch_attack_held": _mobile_attack_held,
		"active_touch_count": _active_mobile_attack_tokens.size(),
		"active_touch_owners": _active_mobile_attack_tokens.duplicate(true),
		"queued_ticket_count": _queued_mobile_attack_tickets.size(),
		"events": _attack_action_diagnostic_events.duplicate(true),
	}
	if is_instance_valid(player):
		result["attack_timer"] = player._attack_timer
		result["attack_action_timer"] = player._attack_action_timer
		result["combat_action_sequence"] = player._combat_action_sequence
		result["attack_cooldown"] = player.attack_cooldown
	if _input.has_button_lifecycle_snapshot():
		result["button"] = _input.button_lifecycle_snapshot()
	return result


func _submit_skill_input_ticket(entry: Dictionary) -> void:
	if not _owned(): return
	# One physical DOWN makes exactly one immediate attempt. A busy cast gate
	# coalesces all additional taps during that interval instead of storing them
	# for forced release later. Continuous casting is owned exclusively by the
	# still-active press in _process_skill_input_actions().
	_execution.try_release_skill(str(entry.get("skill_name", "")), true)


func _process_skill_input_actions(delta: float) -> void:
	if not _owned(): return
	_skill_input_retry_remaining = maxf(
		0.0, _skill_input_retry_remaining - delta
	)
	if _skill_input_retry_remaining > 0.0:
		return
	_skill_input_retry_remaining = 0.05
	var repeat_entry: Dictionary = {}
	var now_ms = _clock.now_msec()
	for raw_entry: Variant in _active_skill_inputs.values():
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry
		if not bool(entry.get("repeatable", false)):
			continue
		if (
			now_ms - int(entry.get("started_at_ms", now_ms))
			< SKILL_HOLD_REPEAT_THRESHOLD_MS
		):
			continue
		if (
			repeat_entry.is_empty()
			or int(entry.get("sequence", 0))
			< int(repeat_entry.get("sequence", 0))
		):
			repeat_entry = entry
	if not repeat_entry.is_empty():
		_execution.try_release_skill(str(repeat_entry.get("skill_name", "")), false)


func _handle_toggle_skill_input(skill_name: String) -> void:
	if not _owned(): return
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	if stable_skill_id != "wizard.magic_shield":
		_execution.try_release_skill(skill_name, true)
		return
	_magic_shield_auto_enabled = not _magic_shield_auto_enabled
	if not _magic_shield_auto_enabled:
		_presentation.show_message("魔法盾自动补盾：关", 1.5)
		return
	_presentation.show_message("魔法盾自动补盾：开", 1.5)
	_magic_shield_auto_retry_remaining = 0.0
	_process_magic_shield_auto_refresh(
		MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	)


func _process_magic_shield_auto_refresh(delta: float) -> void:
	if not _owned(): return
	if not _magic_shield_auto_enabled or not is_instance_valid(player):
		return
	_magic_shield_auto_retry_remaining = maxf(
		0.0, _magic_shield_auto_retry_remaining - delta
	)
	if _magic_shield_auto_retry_remaining > 0.0:
		return
	_magic_shield_auto_retry_remaining = MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	if not player.magic_shield_requires_refresh(
		_actors.magic_shield_auto_refresh_ratio(),
		MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS
	):
		return
	_execution.try_release_skill(
		SkillDataLoaderScript.display_name("wizard.magic_shield"),
		false
	)


func _on_mobile_attack_pressed() -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	if _legacy_mobile_attack_token != 0:
		return
	_legacy_mobile_attack_token = _allocate_synthetic_attack_token()
	_on_mobile_attack_input_started(
		_legacy_mobile_attack_token,
		-3,
		&"legacy"
	)


func _on_mobile_attack_released() -> void:
	if not _owned(): return
	# A duplicate legacy release must not release another finger's ownership.
	if _legacy_mobile_attack_token == 0:
		return
	var press_token = _legacy_mobile_attack_token
	_legacy_mobile_attack_token = 0
	_on_mobile_attack_input_ended(press_token, -3, &"legacy")


func _ensure_attack_locked_target(excluded: Object = null) -> Object:
	if not _owned(): return null
	if not _actors.is_runtime_present(locked_target):
		locked_target = null
		manual_target_lock = false
	if _is_attack_target_in_range(locked_target) and locked_target != excluded:
		return locked_target
	if locked_target != null:
		_cancel_target()
	if not auto_target_enabled:
		return null
	var candidates = _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _ensure_combat_target(
	excluded: Object = null,
	_maximum_range_gu = ATTACK_LOCK_RANGE_GU
) -> Object:
	if not _owned(): return null
	return _ensure_attack_locked_target(excluded)


func _refresh_auto_target(
	_maximum_range_gu = ATTACK_LOCK_RANGE_GU,
	excluded: Object = null
) -> Object:
	if not _owned(): return null
	var candidates = _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _set_attack_locked_target(target: Object, manual = false) -> void:
	if not _owned(): return
	if target != null and not _is_attack_target_in_range(target):
		target = null
	locked_target = target
	manual_target_lock = manual and _actors.is_runtime_present(target)
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _set_locked_target(target: Object, manual = false) -> void:
	if not _owned(): return
	_set_attack_locked_target(target, manual)


func _attack_lock_candidates(excluded: Object = null) -> Array:
	if not _owned(): return []
	var ranked: Array[Dictionary] = []
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	if not origin_ground_gu.is_finite():
		return []
	if not _target_spatial_query_aabb_into(
		Rect2(
			origin_ground_gu - Vector2.ONE * ATTACK_LOCK_RANGE_GU,
			Vector2.ONE * ATTACK_LOCK_RANGE_GU * 2.0,
		),
		_target_spatial_query_scratch,
	):
		return []
	for enemy: Object in _target_spatial_query_scratch:
		if enemy == excluded or not _is_attack_target_in_range(enemy):
			continue
		var target_ground_gu = _canonical_screen_px_to_ground_gu(
			_actors.position_screen_px(enemy)
		)
		ranked.append({
			"target": enemy,
			"contract_id": ATTACK_LOCK_CONTRACT,
			"origin_ground_gu": origin_ground_gu,
			"target_ground_gu": target_ground_gu,
			"distance_squared_gu": GroundUnitSpaceScript.distance_squared_gu(
				origin_ground_gu,
				target_ground_gu
			),
			"instance_id": _actors.runtime_actor_id(enemy),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance_squared_gu = float(
			a.get("distance_squared_gu", INF)
		)
		var b_distance_squared_gu = float(
			b.get("distance_squared_gu", INF)
		)
		if not is_equal_approx(a_distance_squared_gu, b_distance_squared_gu):
			return a_distance_squared_gu < b_distance_squared_gu
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	var result: Array = []
	for entry: Dictionary in ranked:
		result.append(entry.get("target") as Object)
	return result


func _uses_magic_lock_domain() -> bool:
	if not _owned(): return false
	return _rules.profession.profession_id(_profile.profession_id) in [
		"wizard",
		"taoist",
	]


func _magic_target_domain_is_active() -> bool:
	if not _owned(): return false
	return _uses_magic_lock_domain() and _active_target_domain_magic


func _set_active_target_domain_magic(active: bool) -> void:
	if not _owned(): return
	_active_target_domain_magic = active
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _activate_physical_attack_domain() -> void:
	if not _owned(): return
	_set_active_target_domain_magic(false)
	# A manual caster selection is stored in the independent magic domain. If
	# that exact target is also inside the physical lock range, carry it across
	# before the ordinary attack asks the normal auto-target policy for a target.
	# Never widen the physical range or replace an existing physical lock with an
	# automatically selected magic target.
	if _is_attack_target_in_range(magic_locked_target) and (
		not _is_attack_target_in_range(locked_target)
		or manual_magic_target_lock
	):
		_set_attack_locked_target(magic_locked_target, manual_magic_target_lock)


func _activate_magic_skill_domain() -> void:
	if not _owned(): return
	if not _uses_magic_lock_domain():
		return
	_set_active_target_domain_magic(true)
	# Preserve a manually selected physical target when a caster switches back
	# to a bound/ring skill, but only when that same target satisfies the magic
	# lock range. The two lock domains remain independent outside this bridge.
	if (
		_is_magic_target_in_range(locked_target)
		and not _is_magic_target_in_range(magic_locked_target)
	):
		_set_magic_locked_target(locked_target, manual_target_lock)


func _spell_lock_ground_gu(screen_position_px: Vector2) -> Vector2:
	if not _owned(): return Vector2.INF
	return _canonical_screen_px_to_ground_gu(screen_position_px)


func _spell_lock_distance_gu(target: Object) -> float:
	if not _owned(): return 0.0
	if not _actors.is_runtime_present(target):
		return SpellTargetLockPolicyScript.LOCK_RANGE_GU + 1.0
	return SpellTargetLockPolicyScript.distance_gu(
		_spell_lock_ground_gu(_actors.position_screen_px(player)),
		_spell_lock_ground_gu(_actors.position_screen_px(target))
	)


func _is_magic_target_in_range(target: Object) -> bool:
	if not _owned(): return false
	return (
		_actors.is_runtime_present(target)
		and not _actors.is_queued_for_retirement(target)
		and target.current_hp > 0
		and SpellTargetLockPolicyScript.is_within_lock_range(
			_spell_lock_ground_gu(_actors.position_screen_px(player)),
			_spell_lock_ground_gu(_actors.position_screen_px(target))
		)
		and _combat_target_world_clear(target, _actors.position_screen_px(player), true)
	)


func _spell_lock_candidates(excluded: Object = null) -> Array:
	if not _owned(): return []
	var raw_candidates: Array[Dictionary] = []
	var origin_ground_gu = _spell_lock_ground_gu(_actors.position_screen_px(player))
	if not origin_ground_gu.is_finite():
		return []
	if not _target_spatial_query_aabb_into(
		Rect2(
			origin_ground_gu - Vector2.ONE * SpellTargetLockPolicyScript.LOCK_RANGE_GU,
			Vector2.ONE * SpellTargetLockPolicyScript.LOCK_RANGE_GU * 2.0,
		),
		_target_spatial_query_scratch,
	):
		return []
	for enemy: Object in _target_spatial_query_scratch:
		if enemy == excluded or not _is_magic_target_in_range(enemy):
			continue
		raw_candidates.append({
			"target": enemy,
			"origin_ground_gu": origin_ground_gu,
			"target_ground_gu": _spell_lock_ground_gu(_actors.position_screen_px(enemy)),
			"instance_id": _actors.runtime_actor_id(enemy),
		})
	var result: Array = []
	for ranked: Dictionary in SpellTargetLockPolicyScript.ordered_candidates(
		raw_candidates
	):
		result.append(ranked.get("target") as Object)
	return result


func _set_magic_locked_target(target: Object, manual = false) -> void:
	if not _owned(): return
	if target != null and not _is_magic_target_in_range(target):
		target = null
	magic_locked_target = target
	manual_magic_target_lock = manual and _actors.is_runtime_present(target)
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _active_display_target() -> Object:
	if not _owned(): return null
	return magic_locked_target if _magic_target_domain_is_active() else locked_target


func _attack_lock_distance_gu(target: Object) -> float:
	if not _owned(): return 0.0
	if not _actors.is_runtime_present(target):
		return ATTACK_LOCK_RANGE_GU + 1.0
	return GroundUnitSpaceScript.distance_gu(
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player)),
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(target))
	)


func _is_attack_target_in_range(target: Object) -> bool:
	if not _owned(): return false
	return (
		_actors.is_runtime_present(target)
		and not _actors.is_queued_for_retirement(target)
		and target.current_hp > 0
		and _attack_lock_distance_gu(target)
		<= ATTACK_LOCK_RANGE_GU + GroundUnitSpaceScript.EPSILON_GU
		and _combat_target_world_clear(target, _actors.position_screen_px(player), true)
	)


func _on_enemy_target_requested(enemy: Object) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled():
		return
	var magic_domain_active = _magic_target_domain_is_active()
	if _uses_magic_lock_domain():
		# A caster click may be valid in one or both lock domains. Keep each
		# domain's range contract independent while only the active action domain
		# controls presentation and facing.
		if _is_attack_target_in_range(enemy):
			_set_attack_locked_target(enemy, true)
		if _is_magic_target_in_range(enemy):
			_set_magic_locked_target(enemy, true)
			_skill_cast_target = enemy
		if magic_domain_active and _is_magic_target_in_range(enemy):
			_face_skill_cast_target()
		elif not magic_domain_active and _is_attack_target_in_range(enemy):
			_face_locked_target()
		return
	if _is_attack_target_in_range(enemy):
		_set_attack_locked_target(enemy, true)
		_face_locked_target()


func _cancel_target() -> void:
	if not _owned(): return
	locked_target = null
	manual_target_lock = false
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _cancel_magic_target() -> void:
	if not _owned(): return
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _cancel_all_combat_targets() -> void:
	if not _owned(): return
	locked_target = null
	manual_target_lock = false
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_presentation.refresh_target_highlights()
	_presentation.update_target_hud()


func _validate_locked_target() -> void:
	if not _owned(): return
	if not _actors.is_runtime_present(locked_target):
		locked_target = null
		manual_target_lock = false
	elif not _is_attack_target_in_range(locked_target):
		_cancel_target()
	if not _actors.is_runtime_present(magic_locked_target):
		magic_locked_target = null
		manual_magic_target_lock = false
	elif not _is_magic_target_in_range(magic_locked_target):
		_cancel_magic_target()


func _face_locked_target() -> Vector2:
	if not _owned(): return Vector2.INF
	if not _is_attack_target_in_range(locked_target):
		return player.facing.normalized()
	var direction_resolution = CombatDirectionSpaceScript.resolve_screen_delta_px(
		_actors.position_screen_px(locked_target) - _actors.position_screen_px(player)
	)
	var direction = Vector2(
		direction_resolution.get("projected_screen_direction_px", player.facing)
	).normalized()
	if direction.length_squared() > 0.01:
		player.set_combat_facing(direction)
	return direction


func _ensure_skill_cast_target(excluded: Object = null) -> Object:
	if not _owned(): return null
	_activate_magic_skill_domain()
	if not _actors.is_runtime_present(magic_locked_target):
		magic_locked_target = null
		manual_magic_target_lock = false
	if not _actors.is_runtime_present(_skill_cast_target):
		_skill_cast_target = null
	if _is_magic_target_in_range(magic_locked_target) and magic_locked_target != excluded:
		_skill_cast_target = magic_locked_target
		return _skill_cast_target
	if magic_locked_target != null:
		_cancel_magic_target()
	if not auto_target_enabled:
		_skill_cast_target = null
		return null
	var candidates = _spell_lock_candidates(excluded)
	_set_magic_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	_skill_cast_target = magic_locked_target
	return _skill_cast_target


func _face_skill_cast_target() -> Vector2:
	if not _owned(): return Vector2.INF
	if not _is_magic_target_in_range(_skill_cast_target):
		return player.facing.normalized()
	var direction_screen_px = _actors.position_screen_px(player).direction_to(
		_actors.position_screen_px(_skill_cast_target)
	)
	if direction_screen_px.length_squared() > 0.01:
		direction_screen_px = _combat.face_target_screen_px(
			player,
			_skill_cast_target
		)
	return direction_screen_px


func _select_wild_rush_target() -> Object:
	if not _owned(): return null
	if not _actors.is_runtime_present(locked_target):
		locked_target = null
		manual_target_lock = false
	if _is_attack_target_in_range(locked_target):
		# A live lock is authoritative. An ineligible, over-level, boss, or
		# out-of-reach lock must make this cast invalid instead of silently
		# redirecting the charge to a different nearby monster.
		return locked_target if _wild_rush_target_is_eligible(locked_target) else null
	var player_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
	if not player_ground_gu.is_finite():
		return null
	if not _target_spatial_query_aabb_into(
		Rect2(
			player_ground_gu - Vector2.ONE * WarriorMeleeGeometryScript.WILD_RUSH_TARGET_REACH_GU,
			Vector2.ONE * WarriorMeleeGeometryScript.WILD_RUSH_TARGET_REACH_GU * 2.0,
		),
		_target_spatial_query_scratch,
	):
		return null
	var best: Object
	var best_distance_gu = INF
	for enemy: Object in _target_spatial_query_scratch:
		if not _wild_rush_target_is_eligible(enemy):
			continue
		var enemy_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy))
		var distance_gu = GroundUnitSpaceScript.distance_gu(
			player_ground_gu,
			enemy_ground_gu
		)
		# The no-lock contract is strict at 1.5 GU.  The index result is kept in
		# the established stable spawn/group order, so equal distances retain the
		# first legacy candidate instead of introducing an instance-id tie-break.
		if (
			distance_gu < WarriorMeleeGeometryScript.WILD_RUSH_TARGET_REACH_GU
			and distance_gu < best_distance_gu
		):
			best = enemy
			best_distance_gu = distance_gu
	return best


func _wild_rush_target_is_eligible(target: Object) -> bool:
	if not _owned(): return false
	if (
		not _actors.is_runtime_present(target)
		or _actors.is_queued_for_retirement(target)
		or target.current_hp <= 0
		or target.is_boss
		or bool(_actors.read_meta(target, "immovable", false))
		or int(target.monster_data.get("level", target.level)) >= _profile.level
	):
		return false
	if (
		_player_inside_active_safe_zone()
		or WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(target)),
			_active_safe_zones
		)
	):
		return false
	return WarriorMeleeGeometryScript.wild_rush_target_is_adjacent(
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player)),
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(target))
	)


func _build_wild_rush_path_plan(target: Object, release_id = "") -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var result = {
		"contract_id": WarriorMeleeGeometryScript.WILD_RUSH_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"eligible": false,
		"dynamic_blocker_in_corridor": false,
		"static_clear_distance_gu": 0.0,
		"resolved_push_distance_gu": 0.0,
	}
	if not _wild_rush_target_is_eligible(target):
		return result
	var player_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
	var target_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(target))
	var direction_ground_gu = WarriorMeleeGeometryScript.wild_rush_direction_ground_gu(
		player_ground_gu,
		target_ground_gu
	)
	var direction_index = WarriorMeleeGeometryScript.direction_index_for_ground_delta_gu(
		direction_ground_gu
	)
	var direction_step = WarriorMeleeGeometryScript.facing_tile_step(direction_index)
	var dynamic_blocked = _wild_rush_has_dynamic_blocker(
		target,
		target_ground_gu,
		direction_ground_gu
	)
	var static_clear_distance_gu = _wild_rush_static_clear_distance_gu(
		target,
		player_ground_gu,
		target_ground_gu,
		direction_ground_gu
	)
	result.merge({
		"eligible": true,
		"direction_index": direction_index,
		"direction_step": direction_step,
		"direction_ground_gu": direction_ground_gu,
		"player_origin_ground_gu": player_ground_gu,
		"target_origin_ground_gu": target_ground_gu,
		"dynamic_blocker_in_corridor": dynamic_blocked,
		"static_clear_distance_gu": static_clear_distance_gu,
		"resolved_push_distance_gu": (
			0.0 if dynamic_blocked else static_clear_distance_gu
		),
	}, true)
	var resolved_release_id = str(release_id)
	if resolved_release_id.is_empty():
		resolved_release_id = _next_skill_footprint_release_id(WILD_RUSH_SKILL_ID)
	result["release_id"] = resolved_release_id
	result["skill_footprint_snapshot"] = (
		WarriorMeleeGeometryScript.wild_rush_release_footprint_snapshot_ground_gu(
			resolved_release_id,
			player_ground_gu,
			player_ground_gu
			+ direction_ground_gu
			* float(result.get("resolved_push_distance_gu", 0.0)),
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			),
			_canonical_snapshot_validation_context(player_ground_gu)
		)
	)
	return result


func _wild_rush_has_dynamic_blocker(
	target: Object,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> bool:
	if not _owned(): return false
	var forward_ground_gu = direction_ground_gu.normalized()
	var side_ground_gu = Vector2(-forward_ground_gu.y, forward_ground_gu.x)
	var target_radius_gu = target.combat_radius_gu
	if (
		not target_ground_gu.is_finite()
		or forward_ground_gu.length_squared()
		<= WarriorMeleeGeometryScript.EPSILON * WarriorMeleeGeometryScript.EPSILON
	):
		return false
	if not _target_spatial_query_segment_into(
		target_ground_gu,
		target_ground_gu
			+ forward_ground_gu * WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU,
		target_radius_gu,
		_target_spatial_query_scratch,
		# PERF-2: existence probe — the boolean blocker verdict is
		# order-insensitive, so the broadphase may skip combat ordering.
		false,
	):
		return false
	for other: Object in _target_spatial_query_scratch:
		if other == target:
			continue
		if _actors.is_queued_for_retirement(other) or other.current_hp <= 0:
			continue
		var delta_ground_gu = (
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(other))
			- target_ground_gu
		)
		var forward_distance_gu = delta_ground_gu.dot(forward_ground_gu)
		var lateral_distance_gu = absf(delta_ground_gu.dot(side_ground_gu))
		var other_radius_gu = other.combat_radius_gu
		if (
			forward_distance_gu > WarriorMeleeGeometryScript.EPSILON
			and forward_distance_gu - other_radius_gu
			<= WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
				+ WarriorMeleeGeometryScript.EPSILON
			and lateral_distance_gu
			<= target_radius_gu + other_radius_gu + WarriorMeleeGeometryScript.EPSILON
		):
			return true
	return false


func _wild_rush_static_clear_distance_gu(
	target: Object,
	player_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> float:
	if not _owned(): return 0.0
	const SAMPLE_STEP_GU = 0.25
	var maximum_distance_gu = WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
	var sample_count = ceili(maximum_distance_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu = 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu = minf(
			float(sample_index) * SAMPLE_STEP_GU,
			maximum_distance_gu
		)
		var motion_ground_gu = direction_ground_gu * distance_gu
		var player_destination = _canonical_ground_gu_to_screen_px(
			player_ground_gu + motion_ground_gu
		)
		var target_destination = _canonical_ground_gu_to_screen_px(
			target_ground_gu + motion_ground_gu
		)
		if (
			_geometry.environment_blocks_actor_screen_px(
				_geometry,
				player_destination,
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
			or _geometry.environment_blocks_actor_screen_px(
				_geometry,
				target_destination,
				target.collision_radius_px
			)
		):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _apply_wild_rush_displacement(
	target: Object,
	effect: Dictionary,
	target_context: Dictionary
) -> bool:
	if not _owned(): return false
	var distance_gu = clampf(
		float(effect.get("resolved_push_distance_gu", 0.0)),
		0.0,
		WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
	)
	if distance_gu <= 0.0 or bool(target_context.get("dynamic_blocker_in_corridor", false)):
		return false
	var direction_ground_gu: Vector2 = target_context.get(
		"direction_ground_gu", Vector2.ZERO
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		return false
	var motion_ground_gu = direction_ground_gu.normalized() * distance_gu
	var rush_snapshot: Dictionary = target_context.get(
		"skill_footprint_snapshot", {}
	)
	var player_origin_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	if not _snapshot_strict_ok(rush_snapshot):
		return false
	if (
		str(rush_snapshot.get("shape_type", ""))
		!= SkillFootprintSnapshotScript.SHAPE_SWEPT_CAPSULE_PATH
		or not (rush_snapshot.get(
			"segment_start_ground_gu", Vector2.INF
		) as Vector2).is_equal_approx(player_origin_ground_gu)
		or not (rush_snapshot.get(
			"segment_end_ground_gu", Vector2.INF
		) as Vector2).is_equal_approx(player_origin_ground_gu + motion_ground_gu)
	):
		return false
	var player_destination = _canonical_ground_gu_to_screen_px(
		player_origin_ground_gu
		+ motion_ground_gu
	)
	var target_destination = _canonical_ground_gu_to_screen_px(
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(target))
		+ motion_ground_gu
	)
	if (
		_geometry.environment_blocks_actor_screen_px(
			_geometry,
			player_destination,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
		or _geometry.environment_blocks_actor_screen_px(
			_geometry,
			target_destination,
			target.collision_radius_px
		)
	):
		return false
	# Both destinations were preflighted before either actor is mutated. This is
	# one coupled transaction: partial single-actor movement is forbidden.
	target.set_combat_position(target_destination, &"wild_rush_displacement")
	_world.set_player_world_position(player_destination, false)
	_actors.stop_velocity(player)
	player.movement_performed.emit(_actors.position_screen_px(player), player.facing)
	return true


func _use_skill_slot(slot_group: String, slot_index: int) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	var skill_name = _profile.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		var group_label = (
			"攻击键"
			if slot_group == _profile.SKILL_SLOT_GROUP_ATTACK
			else "攻击环%d" % (slot_index + 1)
		)
		_presentation.show_error_message("%s为空" % group_label)
		return
	var metadata = SkillInputPolicyScript.metadata(skill_name)
	if bool(metadata.get("toggle", false)):
		_handle_toggle_skill_input(skill_name)
		return
	_try_release_skill(skill_name, true)


func _try_release_skill(skill_name: String, show_failure = true) -> StringName:
	if not _owned(): return &"rejected"
	if not _rules.granted.definition(skill_name).is_empty():
		return _release_equipment_skill(skill_name, show_failure)
	if skill_name.is_empty() or not _profile.is_skill_learned(skill_name):
		if show_failure:
			_presentation.show_error_message("技能尚未学习")
		return &"rejected"
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	var configuration = _capture_action_configuration(stable_skill_id)
	if configuration == null:
		return &"rejected"
	var definition: Dictionary = configuration.definition_for(stable_skill_id)
	if definition.is_empty():
		return &"rejected"
	var input_metadata = SkillInputPolicyScript.metadata(stable_skill_id)
	var warrior_toggle = (
		_profile.profession_id == "hc.profession.warrior"
		and stable_skill_id.begins_with("warrior.")
		and bool(input_metadata.get("toggle", false))
	)
	# A warrior toggle only changes the next melee mode; it never targets or
	# releases an attack at this input boundary.
	if not warrior_toggle and _hostile_skill_blocked_by_safe_zone(definition):
		if show_failure:
			_presentation.show_error_message("安全区内无法对敌人释放技能")
		return &"rejected"
	if not SkillVisibilityPolicyScript.is_skill_castable(stable_skill_id):
		if show_failure:
			_presentation.show_error_message("该技能已隐藏，无法使用")
		return &"rejected"
	_activate_magic_skill_domain()
	if warrior_toggle:
		# Warrior toggles only configure the next melee mode. They do not cast,
		# spend MP, select a target, or commit cooldown/action state here. Keep
		# Player.request_skill as the authority for dead/control/struck locks.
		if not player.request_skill(skill_name, 0, configuration):
			if show_failure:
				_presentation.show_error_message("技能动作或冷却尚未结束")
			return &"busy"
		_skill_cast_target = null
		return &"accepted"
	if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
		## Friendly healing is selected by the pure support policy BEFORE any
		## action/cooldown/MP commit. Full-HP friendlies remain valid targets
		## (user override 2026-08-09); only an empty/in-range-less pool rejects.
		var heal_selection = _select_taoist_heal_target(
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
		)
		if not bool(heal_selection.get("valid", false)):
			if show_failure:
				_presentation.show_error_message("附近没有可治疗的友方")
			_skill_cast_target = null
			_selected_friendly_instance_id = 0
			return &"rejected"
		_selected_friendly_instance_id = int(
			heal_selection.get("selected", {}).get("instance_id", 0)
		)
	var learned_level: int = configuration.rank()
	var profile = _rules.profession.skill_combat_profile(skill_name, learned_level)
	var resource_context = _canonical_resource_context(stable_skill_id, configuration)
	var resource_quote = SkillResourceServiceScript.quote(
		definition,
		learned_level,
		resource_context,
		resource_context
	)
	var mana_cost = maxi(0, int(resource_quote.get("mp_cost", 0)))
	if player.current_mp < mana_cost:
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			_selected_friendly_instance_id = 0
		if show_failure:
			_presentation.show_error_message("魔法不足")
		return &"rejected"
	if not player.can_request_skill(skill_name, configuration):
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			_selected_friendly_instance_id = 0
		if show_failure:
			_presentation.show_error_message("技能动作或冷却尚未结束")
		return &"busy"
	_skill_cast_target = null
	if stable_skill_id == WILD_RUSH_SKILL_ID:
		_skill_cast_target = _select_wild_rush_target()
		if _skill_cast_target == null:
			if show_failure:
				_presentation.show_error_message("附近没有可冲撞的低级普通怪物")
			return &"rejected"
		_face_skill_cast_target()
	elif _skill_needs_target(str(profile.get("cast_type", "melee"))):
		_ensure_skill_cast_target(null)
		_face_skill_cast_target()
	if _definition_requires_hostile_target(definition):
		if not _actors.is_runtime_present(_skill_cast_target):
			if show_failure:
				_presentation.show_error_message("法术需要有效目标")
			return &"rejected"
		if not _spell_definition_allows_target(definition, _skill_cast_target):
			if show_failure:
				_presentation.show_error_message("目标超出该法术的有效范围")
			return &"rejected"
	var locked_skill_target_id = 0
	if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
		locked_skill_target_id = _selected_friendly_instance_id
		_skill_cast_target = null
	else:
		locked_skill_target_id = (
			_actors.runtime_actor_id(_skill_cast_target)
			if _actors.is_runtime_present(_skill_cast_target)
			else 0
		)
	if not player.request_skill(skill_name, locked_skill_target_id, configuration):
		_selected_friendly_instance_id = 0
		if show_failure:
			_presentation.show_error_message("技能动作或冷却尚未结束")
		return &"busy"
	if stable_skill_id.begins_with("warrior."):
		_skill_cast_target = null
	return &"accepted"


func _definition_requires_hostile_target(definition: Dictionary) -> bool:
	if not _owned(): return false
	if str(definition.get("skill_id", "")) == FIRE_WALL_SKILL_ID:
		return true
	var target: Dictionary = definition.get("target", {})
	var relation = str(target.get("relation", ""))
	if not relation.contains("hostile"):
		return false
	var mode = str(target.get("mode", ""))
	## Entrapment is a ground-point hostile-monster area skill but must use the
	## current valid locked monster like every other hostile spell.
	if mode == "ground_point_hostile_monster_area":
		return true
	return (
		mode != "facing_line"
		and not mode.contains("surrounding")
		and not mode.contains("ground")
		and not mode.begins_with("self")
	)


func _hostile_skill_blocked_by_safe_zone(definition: Dictionary) -> bool:
	if not _owned(): return false
	return (
		_definition_requires_hostile_target(definition)
		and _player_inside_active_safe_zone()
	)


func _spell_definition_allows_target(
	definition: Dictionary,
	target: Object
) -> bool:
	if not _owned(): return false
	if not _is_magic_target_in_range(target):
		return false
	var target_contract: Dictionary = definition.get("target", {})
	if not str(target_contract.get("relation", "")).contains("hostile"):
		return true
	var geometry: Dictionary = definition.get("geometry", {})
	if str(geometry.get("shape", "")) != "projectile":
		return true
	var maximum_range_gu = float(geometry.get("maximum_range_gu", 0.0))
	if maximum_range_gu <= 0.0:
		return true
	return (
		_spell_lock_distance_gu(target)
		<= maximum_range_gu + GroundUnitSpaceScript.EPSILON_GU
	)


func _on_player_attack(origin: Vector2, direction: Vector2, damage: int) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	var context = player.consume_attack_context()
	var configuration: RefCounted = context.get("action_config_lease")
	var release_geometry: Dictionary = context.get("release_geometry", {})
	if configuration == null and not _profile.feature_bundle().get("event_index",{}).is_empty(): return
	if configuration != null and not configuration.begin_release(_action_configuration_identity(),str(release_geometry.get("release_id",""))):
		return
	var accepted_melee: Dictionary = configuration.melee_context() if configuration != null else {}
	_profile.try_trigger_relic_proc()
	var diagnostic = _pending_melee_diagnostic.duplicate(true)
	_pending_melee_diagnostic.clear()
	_active_physical_hit_diagnostics.clear()
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
	_expire_canonical_fire_charge_if_needed()
	var body_selection = context.duplicate(true)
	var selection_mode = str(body_selection.get("mode", WarriorMeleeGeometryScript.SKILL_NORMAL))
	if _clock.now_msec() < _canonical_fire_charge_expires_ms:
		selection_mode = WarriorMeleeGeometryScript.SKILL_FIRE
	var melee_release_snapshot = _create_melee_release_footprint_snapshot(
		origin,
		direction,
		selection_mode,
		release_geometry
	)
	release_geometry = release_geometry.duplicate(true)
	release_geometry["origin_ground_gu"] = _canonical_screen_px_to_ground_gu(origin)
	release_geometry["snapshot_validation_context"] = (
		_canonical_snapshot_validation_context(
			release_geometry["origin_ground_gu"] as Vector2
		)
	)
	release_geometry["release_id"] = str(melee_release_snapshot.get(
		"release_id", release_geometry.get("release_id", "")
	))
	release_geometry["skill_footprint_snapshot"] = melee_release_snapshot
	var thrust_damage_axis_plan: Dictionary = {}
	if selection_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		thrust_damage_axis_plan = (
			WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
				_melee_direction_index(direction, release_geometry),
				release_geometry,
				release_geometry.get("snapshot_validation_context", {})
			)
		)
		thrust_damage_axis_plan["skill_footprint_snapshot"] = melee_release_snapshot
	var melee_release_cache: Dictionary = {}
	var melee_query_plan = _aoe_melee_query_plan(
		selection_mode,
		release_geometry["origin_ground_gu"],
		direction,
		release_geometry,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		release_geometry.get("target_aligned_plan", {}),
		melee_release_cache,
	)
	var primary_targets = _physical_primary_targets(
		origin,
		direction,
		selection_mode,
		release_geometry,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		release_geometry.get("target_aligned_plan", {}),
		melee_query_plan,
	)
	var thrust_secondary_targets: Array = []
	var half_moon_secondary_targets: Array = []
	var eligible_target_count = primary_targets.size()
	if selection_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		thrust_secondary_targets = _thrust_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			release_geometry.get("target_aligned_plan", {}),
			melee_query_plan,
		)
		eligible_target_count += thrust_secondary_targets.size()
	elif selection_mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		half_moon_secondary_targets = _half_moon_secondary_targets(
			origin,
			direction,
			primary_targets,
			release_geometry,
			melee_release_snapshot,
			melee_query_plan,
		)
		eligible_target_count += half_moon_secondary_targets.size()
	var has_eligible_target = eligible_target_count > 0
	var consumes_armed_fire = false
	if not primary_targets.is_empty() and _clock.now_msec() < _canonical_fire_charge_expires_ms:
		body_selection["mode"] = "fire"
		body_selection["selected_body_mode"] = "fire"
		body_selection["skill_name"] = "烈火剑法"
		body_selection["skill_level"] = configuration.rank_for("warrior.fire_sword") if configuration != null else _profile.effective_skill_level("warrior.fire_sword")
		body_selection["direct_toggle_release"] = false
		consumes_armed_fire = true

	var hit_effect = SkillInputPolicyScript.resolve_warrior_hit_effect(
		body_selection,
		{
			"learned_skills": accepted_melee.learned_skills if not accepted_melee.is_empty() else _profile.learned_skills,
			"toggles": accepted_melee.toggles if not accepted_melee.is_empty() else {
				"warrior.fire_sword": player.fire_sword_enabled,
				"warrior.half_moon": player.half_moon_enabled,
				"warrior.thrusting": player.thrusting_enabled,
			},
			"has_combat_target": has_eligible_target,
			"current_mp": player.current_mp,
			"fire_rank": configuration.rank_for("warrior.fire_sword") if configuration != null else _profile.effective_skill_level("warrior.fire_sword"),
			"half_moon_rank": configuration.rank_for("warrior.half_moon") if configuration != null else _profile.effective_skill_level("warrior.half_moon"),
			"action_config_lease": configuration,
		}
	)
	var effect_mode = str(hit_effect.get("effect_mode", ""))
	if (
		effect_mode in [
			WarriorMeleeGeometryScript.SKILL_NORMAL,
			WarriorMeleeGeometryScript.SKILL_THRUST,
			WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			WarriorMeleeGeometryScript.SKILL_FIRE,
		]
		and effect_mode != selection_mode
	):
		melee_release_snapshot = _create_melee_release_footprint_snapshot(
			origin,
			direction,
			effect_mode,
			release_geometry
		)
		release_geometry["skill_footprint_snapshot"] = melee_release_snapshot
		thrust_damage_axis_plan = {}
		if effect_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
			thrust_damage_axis_plan = (
				WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
					_melee_direction_index(direction, release_geometry),
					release_geometry,
					release_geometry.get("snapshot_validation_context", {})
				)
			)
			thrust_damage_axis_plan["skill_footprint_snapshot"] = melee_release_snapshot
		melee_release_cache.clear()
		melee_query_plan = _aoe_melee_query_plan(
			effect_mode,
			release_geometry["origin_ground_gu"],
			direction,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			release_geometry.get("target_aligned_plan", {}),
			melee_release_cache,
		)
		primary_targets = _physical_primary_targets(
			origin,
			direction,
			effect_mode,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			release_geometry.get("target_aligned_plan", {}),
			melee_query_plan,
		)
		thrust_secondary_targets.clear()
		half_moon_secondary_targets.clear()
		eligible_target_count = primary_targets.size()
		if effect_mode == WarriorMeleeGeometryScript.SKILL_THRUST:
			thrust_secondary_targets = _thrust_secondary_targets(
				origin,
				direction,
				primary_targets,
				release_geometry,
				thrust_damage_axis_plan,
				melee_release_snapshot,
				release_geometry.get("target_aligned_plan", {}),
				melee_query_plan,
			)
			eligible_target_count += thrust_secondary_targets.size()
		elif effect_mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
			half_moon_secondary_targets = _half_moon_secondary_targets(
				origin,
				direction,
				primary_targets,
				release_geometry,
				melee_release_snapshot,
				melee_query_plan,
			)
			eligible_target_count += half_moon_secondary_targets.size()
		has_eligible_target = eligible_target_count > 0
	var feature_skill: String = {"fire":"warrior.fire_sword","half_moon":"warrior.half_moon",
		"thrust":"warrior.thrusting"}.get(effect_mode,"")
	var feature_batch = _begin_feature_damage_batch(feature_skill,str(release_geometry.get("release_id","")),configuration)
	if configuration != null and not configuration.event_bindings_for(feature_skill).is_empty() and feature_batch == null:
		return
	if consumes_armed_fire and effect_mode == "fire":
		_set_canonical_fire_charge_expires_at(0)
	var melee_modifiers = _planner.resolve_warrior_melee_modifiers({
		"body_mode": effect_mode,
		"basic_sword_learned": accepted_melee.learned_skills.has("hc.skill.warrior.basic_swordsmanship") if not accepted_melee.is_empty() else _profile.is_skill_learned("warrior.basic_swordsmanship"),
		"basic_sword_rank": configuration.rank_for("warrior.basic_swordsmanship") if configuration != null else _profile.effective_skill_level("warrior.basic_swordsmanship"),
		"slaying_learned": accepted_melee.learned_skills.has("hc.skill.warrior.slaying_swordsmanship") if not accepted_melee.is_empty() else _profile.is_skill_learned("warrior.slaying_swordsmanship"),
		"slaying_rank": configuration.rank_for("warrior.slaying_swordsmanship") if configuration != null else _profile.effective_skill_level("warrior.slaying_swordsmanship"),
		"action_config_lease": configuration,
		"valid_melee_swing": has_eligible_target,
		"seed": _next_canonical_seed(),
	})
	var modified_base_damage = (
		damage
		+ int(melee_modifiers.get("flat_dc_bonus_before_body_formula", 0))
	)
	var post_body_damage_bonus = int(
		melee_modifiers.get("flat_damage_bonus_after_body_formula", 0)
	)
	var accuracy_bonus = int(melee_modifiers.get("flat_accuracy_bonus", 0))
	if (accepted_melee.learned_skills.has("hc.skill.taoist.spiritual_warfare") if not accepted_melee.is_empty() else _profile.is_skill_learned("taoist.spiritual_warfare")):
		accuracy_bonus += _planner.taoist_melee_accuracy_bonus(
			configuration.rank_for("taoist.spiritual_warfare") if configuration != null else _profile.effective_skill_level("taoist.spiritual_warfare"), configuration
		)
	var hit_any = false
	var primary_hit = false
	var canonical_resolution = "rejected"
	if effect_mode in ["thrust", "half_moon", "fire"]:
		var melee_resolution = _execute_canonical_melee(
			effect_mode,
			origin,
			direction,
			modified_base_damage,
			post_body_damage_bonus,
			accuracy_bonus,
			bool(body_selection.get("direct_toggle_release", false)),
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			release_geometry.get("target_aligned_plan", {}),
			primary_targets,
			thrust_secondary_targets,
			half_moon_secondary_targets,
			true,
			configuration,
			feature_batch
		)
		hit_any = bool(melee_resolution.get("hit_any", false))
		primary_hit = bool(melee_resolution.get("primary_hit", false))
		canonical_resolution = str(melee_resolution.get("resolution", "rejected"))
	elif effect_mode == "normal":
		if not primary_targets.is_empty():
			var target = primary_targets[0]
			hit_any = _apply_physical_hit(
				target,
				modified_base_damage + post_body_damage_bonus,
				accuracy_bonus, false, configuration, feature_batch
			)
			primary_hit = hit_any
			canonical_resolution = "hit" if hit_any else "miss"
	_finish_feature_damage_batch(feature_batch)
	# Weapon wear belongs to the physical swing, not to each target struck by
	# that swing. Besides matching the original server, this prevents Half Moon,
	# Thrusting and any future multi-target melee release from performing one
	# synchronous save per victim.
	if primary_hit and _actors.is_runtime_present(player):
		player.apply_confirmed_physical_hit_durability(
			maxi(1, modified_base_damage + post_body_damage_bonus)
		)
	_presentation.spawn_target_aligned_melee_visual(
		melee_release_snapshot,
		effect_mode,
		hit_any,
		origin,
		release_geometry
	)
	if SkillInputPolicyScript.fire_direct_release_consumes_cooldown(
		body_selection,
		hit_effect,
		canonical_resolution
	):
		_plan_contract.cooldown_commit_count += 1
		player.commit_fire_sword_cooldown(configuration)
	_commit_warrior_melee_modifier_events(melee_modifiers)
	if (
		bool(melee_modifiers.get("slaying_proc", false))
		and effect_mode == "normal"
		and player.visual != null
		and player.visual.has_method("play_passive_proc_effect")
	):
		player.visual.call("play_passive_proc_effect", "攻杀剑术", 0.24)
	if effect_mode == "fire" and _presentation != null:
		_presentation.update_warrior_states(player.warrior_state_snapshot())
	_presentation.show_attack_flash(origin, direction, hit_any, Color(1.0, 0.72, 0.25))
	_presentation.record_melee_release_diagnostic(
		diagnostic,
		context,
		release_geometry,
		origin,
		direction,
		selection_mode,
		effect_mode,
		primary_targets,
		eligible_target_count,
		has_eligible_target,
		canonical_resolution,
		hit_any
	)


func _melee_candidate_diagnostics(
	origin: Vector2,
	direction_index: int,
	mode: String,
	primary_targets: Array
) -> Array[Dictionary]:
	if not _owned(): return []
	# Explicit diagnostic-only candidate evidence still uses the same mapped
	# broadphase.  Diagnostics must not reintroduce a SceneTree full-group scan
	# into an attack release just because the log is enabled.
	var result: Array[Dictionary] = []
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	var resolved_mode = (
		mode
		if mode in [
			WarriorMeleeGeometryScript.SKILL_NORMAL,
			WarriorMeleeGeometryScript.SKILL_FIRE,
			WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			WarriorMeleeGeometryScript.SKILL_THRUST,
		]
		else WarriorMeleeGeometryScript.SKILL_NORMAL
	)
	if not origin_ground_gu.is_finite():
		return result
	var diagnostic_radius_gu = (
		WarriorMeleeGeometryScript.reach_gu(resolved_mode) + 1.0
	)
	if not _target_spatial_query_aabb_into(
		Rect2(
			origin_ground_gu - Vector2.ONE * diagnostic_radius_gu,
			Vector2.ONE * diagnostic_radius_gu * 2.0,
		),
		_target_spatial_query_scratch,
	):
		return result
	# A selected target is authoritative release evidence. Preserve it in the
	# diagnostic record even if a malformed fixture placed it outside the
	# conservative diagnostic envelope, without broadening the production query.
	for selected: Object in primary_targets:
		if (
			_target_spatial_enemy_is_current(selected)
			and not _target_spatial_query_scratch.has(selected)
		):
			_target_spatial_query_scratch.append(selected)
	for enemy: Object in _target_spatial_query_scratch:
		var explanation = WarriorMeleeDiagnosticScript.explain_footprint_candidate(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
			enemy.combat_radius_gu,
			direction_index,
			resolved_mode
		)
		explanation["angle_quantization_audit"] = (
			WarriorMeleeDiagnosticScript.audit_ground_delta_gu(
				_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)) - origin_ground_gu
			)
		)
		explanation["target_id"] = _actors.runtime_actor_id(enemy)
		explanation["target_name"] = enemy.display_name
		explanation["target_world"] = _actors.position_screen_px(enemy)
		explanation["selected_as_primary"] = enemy in primary_targets
		if (
			float(explanation.get("distance_gu", INF))
			> float(explanation.get("effective_reach_gu", 0.0)) + 1.0
			and not bool(explanation.get("footprint_accepted", false))
			and not bool(explanation["selected_as_primary"])
		):
			continue
		result.append(explanation)
	return result


func _enemy_instance_ids(enemies: Array) -> Array[int]:
	if not _owned(): return []
	var result: Array[int] = []
	for enemy: Object in enemies:
		if _actors.is_runtime_present(enemy):
			result.append(_actors.runtime_actor_id(enemy))
	return result


func _melee_direction_index(
	direction: Vector2,
	release_geometry: Dictionary = {}
) -> int:
	if not _owned(): return 0
	var resolved_index = int(release_geometry.get("direction_index", -1))
	if resolved_index >= 0 and resolved_index < 8:
		return resolved_index
	return ArtSpec.direction_index(direction)


func _melee_diagnostic_result_code(
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool,
	hit_attempts: Array[Dictionary]
) -> String:
	if not _owned(): return ""
	if hit_any:
		return "HIT_COMMITTED"
	if not has_eligible_target:
		return "GEOMETRY_NO_ELIGIBLE_TARGET"
	if canonical_resolution == "rejected":
		return "CANONICAL_SKILL_REJECTED"
	for attempt: Dictionary in hit_attempts:
		if str(attempt.get("result_code", "")) == "DAMAGE_COMMIT_FAILED":
			return "DAMAGE_COMMIT_FAILED"
	for attempt: Dictionary in hit_attempts:
		if str(attempt.get("result_code", "")) == "ACCURACY_MISS":
			return "ACCURACY_MISS"
	return "NO_DAMAGE_UNCLASSIFIED"


func _commit_warrior_melee_modifier_events(modifiers: Dictionary) -> void:
	if not _owned(): return
	## HardCore v2: proficiency is disabled. Canonical melee modifier events are
	## intentionally discarded; they never grow, upgrade or persist skills.
	pass


func _release_equipment_skill(skill_name_or_id: String, show_failure = true) -> StringName:
	if not _owned(): return &"rejected"
	var grant = _rules.granted.definition(skill_name_or_id)
	if not _input.gameplay_input_is_enabled() or not _actors.is_runtime_present(player) or player._dead or player.current_hp <= 0 or player.combat_transition_is_active():
		return &"rejected"
	if grant.is_empty() or not _profile.is_skill_available(str(grant.get("skill_id", ""))):
		if show_failure: _presentation.show_error_message("装备技能已失效")
		return &"rejected"
	if player.control_time > 0.0:
		return &"busy"
	var effect_id = str(grant.effect_id)
	if effect_id == "grant_fireball_skill" and _hostile_skill_blocked_by_safe_zone(SkillDataLoaderScript.skill("wizard.fireball")):
		if show_failure: _presentation.show_error_message("安全区内无法对敌人释放技能")
		return &"rejected"
	match effect_id:
		"safe_teleport":
			if _world.try_safe_ring_teleport():
				_presentation.show_message("传送戒指：安全位移")
			else:
				if show_failure: _presentation.show_error_message("前方没有合法传送落点")
				return &"rejected"
		"grant_fireball_skill":
			if not player.spend_mana(5):
				if show_failure: _presentation.show_error_message("火球需要5点魔法")
				return &"rejected"
			player.break_stealth()
			_skill_cast_target = null
			_ensure_skill_cast_target(null)
			var direction = _face_skill_cast_target()
			if direction == Vector2.ZERO:
				direction = player.facing.normalized()
			var low = maxi(1, int(_profile.computed_stats.get("magic_min", 0)))
			var high = maxi(low, int(_profile.computed_stats.get("magic_max", low)))
			_spawn_projectile(
				_actors.position_screen_px(player),
				direction,
				_random.randi_range(low, high),
				float(
					SkillDataLoaderScript.skill("wizard.fireball")
					.get("geometry", {})
					.get("maximum_range_gu", 0.0)
				),
				Color(1.0, 0.30, 0.08),
				"damage",
				0,
				0.0,
				"wizard.fireball"
			)
			_skill_cast_target = null
			_presentation.show_message("火焰戒指：火球")
		"grant_healing_skill":
			if not player.spend_mana(5):
				if show_failure: _presentation.show_error_message("治愈需要5点魔法")
				return &"rejected"
			var amount = maxi(12, int(_profile.level / 2) + int(_profile.computed_stats.get("tao_max", 0)) * 2)
			player.restore_health(amount)
			_presentation.show_message("防御戒指：恢复%d生命" % amount)
		_: return &"rejected"
	return &"released"


func _on_player_skill(skill_name: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	if not _owned(): return
	if not _input.gameplay_input_is_enabled(): return
	var skill_context = player.consume_skill_context()
	var release_geometry: Dictionary = skill_context.get("release_geometry", {})
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
		var release_target = _combat_release_target(release_geometry)
		if (
			not CombatReleaseGeometryScript.target_centered_spatial_policy_id(
				stable_skill_id
			).is_empty()
			and not _is_magic_target_in_range(release_target)
		):
			# Target-centred area spells retain the selected monster identity only
			# so its live, manually calibrated footpoint can be sampled here. If
			# that exact instance dies, despawns or leaves the 12-tile spell-lock
			# domain during windup, reject the cast instead of degrading to the
			# generic ground/direction fallback used by untargeted area spells.
			_skill_cast_target = null
			_presentation.show_error_message("锁定目标已失效，技能未释放", 1.5)
			return
		_skill_cast_target = release_target
	_profile.try_trigger_relic_proc()
	var friendly_identity_release: Dictionary = release_geometry.get(
		"friendly_identity_release",
		{}
	)
	if not friendly_identity_release.is_empty():
		## The identity and live footpoint recorded at the release frame are
		## authoritative for Taoist friendly-target skills.
		_selected_friendly_instance_id = int(
			friendly_identity_release.get(
				"selected_friendly_instance_id",
				0
			)
		)
	var release_id = str(release_geometry.get("release_id", ""))
	if release_id.is_empty():
		release_id = _next_skill_footprint_release_id(stable_skill_id)
	var execution = _execute_canonical_skill(
		skill_name,
		origin,
		direction,
		damage,
		{"release_id": release_id},
		true,
		not release_geometry.is_empty(),
		skill_context.get("action_config_lease")
	)
	var hit_any = bool(execution.get("effect_success", false))
	if not bool(execution.get("accepted", false)):
		_presentation.show_error_message(
			"安全区内无法对敌人释放技能"
			if str(execution.get("reason", "")) == "caster_in_safe_zone"
			else "技能释放失败", 1.5
		)
		return
	if hit_any:
		_presentation.play_skill_audio_phase(stable_skill_id, "effect")
	var effect_color = Color(1.0, 0.22, 0.05) if _profile.profession_id == "hc.profession.warrior" else (Color(0.28, 0.62, 1.0) if _profile.profession_id == "hc.profession.wizard" else Color(0.45, 0.92, 0.55))
	_presentation.show_attack_flash(origin, direction, hit_any, effect_color)
	if skill_name == "烈火剑法":
		_presentation.update_warrior_states(player.warrior_state_snapshot())
	_presentation.show_message("施放：%s" % skill_name, 1.0)


func _execute_canonical_skill(
	skill_name: String,
	origin: Vector2,
	direction: Vector2,
	client_damage: int,
	extra_target_context: Dictionary = {},
	apply_effects = true,
	authoritative_cast_target = false,
	configuration: RefCounted = null
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	# A nonempty extension must enter through the accepted Player configuration.
	# Reject a direct unaccepted caller before planner RNG or resource/HP writes.
	if configuration == null and not _profile.feature_bundle().get("event_index",{}).get("damage_committed:"+SkillDataLoaderScript.entity_skill_id(stable_skill_id),[]).is_empty():
		return {"accepted":false,"effect_success":false,"reason":"missing_accepted_feature_configuration"}
	if configuration != null and not configuration.begin_plan(_action_configuration_identity(),
		str(extra_target_context.get("release_id","")),not apply_effects and not configuration.melee_context().is_empty()):
		return {"accepted":false,"effect_success":false,"reason":"stale_action_configuration"}
	# A promised batch is acquired before planner RNG or resource commits.
	# Null means no extension only when this accepted definition has no binding.
	var feature_batch: RefCounted = null
	if apply_effects:
		feature_batch = _begin_feature_damage_batch(stable_skill_id,str(extra_target_context.get("release_id","")),configuration)
		if configuration != null and not configuration.event_bindings_for(stable_skill_id).is_empty() and feature_batch == null:
			return {"accepted":false,"effect_success":false,"reason":"feature_batch_unavailable"}
	var result = _execute_canonical_skill_plan(skill_name,origin,direction,client_damage,extra_target_context,
		apply_effects,authoritative_cast_target,configuration,feature_batch)
	_finish_feature_damage_batch(feature_batch)
	return result


func _execute_canonical_skill_plan(
	skill_name: String, origin: Vector2, direction: Vector2, client_damage: int,
	extra_target_context: Dictionary, apply_effects: bool, authoritative_cast_target: bool,
	configuration: RefCounted, feature_batch: RefCounted
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(skill_name)
	var definition: Dictionary = (configuration.definition_for(stable_skill_id)
		if configuration != null else _profile.effective_skill_definition(stable_skill_id))
	if definition.is_empty():
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "unknown_skill"}
	if SkillRuntimeClassificationScript.profile(stable_skill_id).is_empty():
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "unknown_runtime_classification"}
	# Recheck the live caster at release: entering a safe zone during windup
	# must not bypass the pre-commit input gate.
	if _hostile_skill_blocked_by_safe_zone(definition):
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "caster_in_safe_zone"}
	var rank: int = configuration.rank_for(stable_skill_id) if configuration != null else _profile.effective_skill_level(stable_skill_id)
	var release_context = (extra_target_context as Dictionary).duplicate(true)
	var support_center_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	if TAOIST_SUPPORT_SKILL_IDS.has(stable_skill_id):
		release_context["friendly_candidates"] = _canonical_friendly_candidates()
		release_context["caster_ground_position_gu"] = support_center_ground_gu
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			var friendly_resolution = _resolve_release_friendly_target(
				_selected_friendly_instance_id,
				release_context.get("friendly_candidates", []),
				support_center_ground_gu
			)
			if not bool(friendly_resolution.get("valid", false)):
				_selected_friendly_instance_id = 0
				_skill_cast_target = null
				return {
					"accepted": false,
					"effect_success": false,
					"skill_id": stable_skill_id,
					"reason": str(
						friendly_resolution.get(
							"reason",
							"no_injured_friendly_target_in_range"
						)
					),
					"execution_result": {},
				}
			var selected_friendly: Dictionary = friendly_resolution.get(
				"selected",
				{}
			)
			_selected_friendly_instance_id = int(
				selected_friendly.get("instance_id", 0)
			)
			release_context["selected_friendly_instance_id"] = (
				_selected_friendly_instance_id
			)
			var selected_ground_gu: Vector2 = selected_friendly.get(
				"ground_position_gu",
				support_center_ground_gu
			)
			release_context["actual_hp_missing"] = (
				int(selected_friendly.get("max_hp", 1))
				- int(selected_friendly.get("current_hp", 0))
			)
			if stable_skill_id == "taoist.mass_healing":
				var mass_heal_center_tile = (
					TaoistFriendlyTargetingScript.grid_tile(
						selected_ground_gu
					)
				)
				release_context["target_tile"] = mass_heal_center_tile
				release_context["origin_tile"] = mass_heal_center_tile
		else:
			## mass invisibility / defence stay fixed to the caster's
			## release-frame position; never an enemy/ground/facing point.
			var self_center_tile = TaoistFriendlyTargetingScript.grid_tile(
				support_center_ground_gu
			)
			release_context["target_tile"] = self_center_tile
			## The professional geometry service treats target_tile ZERO as
			## "unset" and falls back to the origin tile; pin both to the same
			## floor tile so canonical cells stay centred on the caster.
			release_context["origin_tile"] = self_center_tile
		var support_resource_context = _canonical_resource_context(
			stable_skill_id, configuration
		)
		if support_resource_context.has("dual_defense_context"):
			release_context["dual_defense_context"] = (
				support_resource_context.get("dual_defense_context", {})
			)
	var target_context = _canonical_target_context(
		definition,
		origin,
		direction,
		not authoritative_cast_target,
		str(extra_target_context.get("release_id", "")),
		release_context,
		configuration
	)
	var cast_target = _skill_cast_target
	if stable_skill_id == "wizard.lightning" and not _hc_lightning_clear(cast_target, origin):
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "world_los_blocked", "skill_id": stable_skill_id}
	if stable_skill_id == "wizard.lightning":
		target_context["line_of_sight"] = true
	var request_facing = _canonical_facing_for_skill(stable_skill_id, direction)
	if stable_skill_id == WILD_RUSH_SKILL_ID and cast_target != null:
		var rush_plan = _build_wild_rush_path_plan(
			cast_target,
			str(target_context.get("release_id", ""))
		)
		if bool(rush_plan.get("eligible", false)):
			target_context.merge(rush_plan, true)
			request_facing = rush_plan.get("direction_step", request_facing)
	var resource_context = _canonical_resource_context(stable_skill_id, configuration)
	var request = SkillCastRequestScript.create(
		stable_skill_id,
		rank,
		configuration.actor_level() if configuration != null else _profile.level,
		(
			release_context.get("origin_tile", Vector2i(-99, -99))
			if release_context.has("origin_tile")
			else _canonical_screen_px_to_grid_cell(origin)
		),
		request_facing,
		target_context,
		resource_context,
		_next_canonical_seed()
	)
	request["client_claimed_damage"] = client_damage
	if configuration != null:
		request["action_config_lease"] = configuration
	# Q3-B: the single canonical plan comes from the router's formal planner
	# entry. No second plan object is ever built by GameRoot or the runtime.
	_plan_contract.release_id_generation_count += 1
	var canonical_context = _canonical_execution_context(
		stable_skill_id,
		origin,
		direction,
		target_context,
		cast_target,
		str(target_context.get("release_id", "")),
		definition
	)
	if configuration != null:
		canonical_context["action_config_lease"] = configuration
	var plan = _planner.build_canonical_plan(
		request,
		canonical_context
	)
	var plan_rejection: Dictionary = plan.get("rejection", {})
	var plan_hash_before = str(plan.get("plan_hash", ""))
	var result = _legacy_result_from_plan(plan)
	result["adapter_contract"] = SKILL_PRODUCTION_ADAPTER_CONTRACT
	result["adapter_bindings"] = [
		"combat_resolution",
		"inventory_resources",
		"map_tile_geometry",
		"target_relations",
		"buff_runtime",
		"taoist_main_pet",
	]
	result["canonical_plan"] = plan
	result["plan_hash_before"] = plan_hash_before
	if not bool(plan_rejection.get("accepted", false)):
		_skill_cast_target = null
		result["execution_result"] = _plan_contract.build_result(
			plan,
			{"accepted": false}
		)
		return result
	var summon_resource_rejection = _canonical_summon_resource_commit_rejection(plan)
	if not summon_resource_rejection.is_empty():
		result["accepted"] = false
		result["effect_success"] = false
		result["reason"] = summon_resource_rejection
		result["execution_result"] = _plan_contract.build_result(
			plan,
			{
				"accepted": false,
				"rejection_reason": summon_resource_rejection,
			}
		)
		_skill_cast_target = null
		return result
	var resource_quote: Dictionary = plan.get("resource_cost", {})
	var needs_resource = (
		int(resource_quote.get("mp_cost", 0)) > 0
		or int(resource_quote.get("material_amount", 0)) > 0
	)
	var resource_commit_required = bool(
		plan.get("resource_commit_required", true)
	)
	var resource_committed = false
	if resource_commit_required and needs_resource:
		resource_committed = _commit_canonical_resources(plan)
	elif resource_commit_required:
		resource_committed = true
	if resource_commit_required and not resource_committed:
		result["accepted"] = false
		result["effect_success"] = false
		result["reason"] = "resource_commit_failed"
		result["execution_result"] = _plan_contract.build_result(
			plan,
			{
				"accepted": false,
				"rejection_reason": "resource_commit_failed",
			}
		)
		_skill_cast_target = null
		return result
	var execution_overrides: Dictionary = {}
	if apply_effects:
		execution_overrides = _apply_canonical_effects_from_plan(
			plan,
			origin,
			direction,
			target_context,
			cast_target,
			configuration,
			feature_batch
		)
	var execution_result = _plan_contract.build_result(
		plan,
		{
			"accepted": true,
			"resource_committed": resource_committed,
			"cooldown_committed": false,
		}.merged(execution_overrides)
	)
	result["execution_result"] = execution_result
	if stable_skill_id == "wizard.teleport" and apply_effects:
		# Acceptance consumes the cast; successful movement is an applied result.
		# Never report success merely because the immutable plan was accepted.
		result["effect_success"] = false
		for status: Dictionary in execution_result.get("status_results", []):
			if str(status.get("type", "")) == "player_teleport":
				result["effect_success"] = bool(status.get("applied", false))
	result["plan_immutable"] = _plan_contract.verify_immutable(
		plan,
		plan_hash_before
	)
	_skill_cast_target = null
	return result


func _canonical_execution_context(
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: Object,
	release_id: String,
	definition: Dictionary = {}
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## Q3-B: frozen inputs for the canonical planner. GameRoot only prepares
	## world/projection context; the planner builds the single plan/snapshot.
	var target_position = _canonical_grid_cell_to_screen_px(
		target_context.get(
			"target_tile",
			_canonical_screen_px_to_grid_cell(origin)
		)
	)
	var target_ground_gu = _canonical_screen_px_to_ground_gu(
		target_position
	)
	var context = {
		"release_id": release_id,
		"runtime_map_id": current_map_id,
		"caster_runtime_id": _actors.runtime_actor_id(player),
		"target_runtime_id": (
			_actors.runtime_actor_id(target)
			if _actors.is_runtime_present(target)
			else 0
		),
		"input_mode": "production_canonical",
		"origin_screen_px": origin,
		"direction_screen_px": direction,
		"target_position_screen_px": target_position,
		"summon_spawn_position_screen_px": target_context.get(
			"summon_spawn_position_screen_px",
			_actors.position_screen_px(player)
		),
		"target": target,
		"fallback_target_actor": player,
		"player_actor": player,
		"player_combat_radius_gu": _actor_combat_radius_gu(player),
		"target_combat_radius_gu": (
			_actor_combat_radius_gu(target)
			if _actors.is_runtime_present(target)
			else _actor_combat_radius_gu(player)
		),
		"screen_to_ground_position_px": (
			Callable(self, "_canonical_screen_px_to_ground_gu")
		),
		"ground_gu_to_screen_position_px": (
			Callable(self, "_canonical_ground_gu_to_screen_px")
		),
		"grid_cell_to_screen_position_px": (
			Callable(self, "_canonical_grid_cell_to_screen_px")
		),
		"snapshot_validation_context": _canonical_snapshot_validation_context(
			_canonical_screen_px_to_ground_gu(origin)
		),
		"line_strip_builder": (
			Callable(self, "_q3b_build_line_strip").bind(
				stable_skill_id,
				origin,
				direction,
				definition
			)
		),
		"effective_cells_builder": (
			Callable(self, "_q3b_build_effective_cells").bind(
				stable_skill_id, definition
			)
		),
	}
	context["player_actor_view"] = _actors.actor_view(player)
	context["target_actor_view"] = _actors.actor_view(target if is_instance_valid(target) and _actors.is_kind(target, &"enemy") else player)
	context["fallback_target_actor_view"] = _actors.actor_view(player)
	return context


func _q3b_build_line_strip(
	effect: Dictionary,
	release_id: String,
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2,
	definition: Dictionary = {}
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	return _canonical_continuous_line_strip_ground_gu(
		stable_skill_id,
		effect,
		origin,
		direction,
		release_id, definition
	)


func _q3b_build_effective_cells(
	raw_geometry_cells: Variant,
	effect: Dictionary,
	stable_skill_id: String,
	definition: Dictionary = {}
) -> Array[Vector2i]:
	if not _owned(): return []
	return _canonical_effective_spell_geometry_cells(
		stable_skill_id,
		raw_geometry_cells,
		effect, definition
	)


func _legacy_result_from_plan(plan: Dictionary) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## Q3-C: compat return envelope for existing GameRoot callers, sourced
	## entirely from the canonical plan. The formal result truth is
	## skill_execution_result.v1 (result["execution_result"]).
	var rejection: Dictionary = plan.get("rejection", {})
	var accepted = bool(rejection.get("accepted", false))
	var skill_id = str(plan.get("skill_id", ""))
	var result = {
		"contract_id": "skills.cast_result.v1",
		"accepted": false,
		"effect_success": false,
		"skill_id": skill_id,
		"reason": str(rejection.get("reason", "")),
		"resource_commit": false,
		"proficiency_event": "",
		"effects": [],
	}
	if accepted:
		result = {
			"contract_id": "skills.cast_result.v1",
			"accepted": true,
			"effect_success": true,
			"skill_id": skill_id,
			"reason": "",
			"resource_commit": bool(
				plan.get("resource_commit_required", true)
			),
			"proficiency_event": _plan_proficiency_event(plan),
			"effects": plan.get("gameplay_actions", []).duplicate(true),
		}
	result["runtime_contract"] = "skills.runtime_router.cn_mir2_176.v1"
	return result


func _plan_proficiency_event(plan: Dictionary) -> String:
	if not _owned(): return ""
	return str(plan.get("proficiency_event", ""))


func _execute_canonical_melee(
	mode: String,
	origin: Vector2,
	direction: Vector2,
	base_damage: int,
	post_body_damage_bonus: int,
	accuracy_bonus: int,
	direct_toggle_release = false,
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	resolved_primary_targets: Array = [],
	resolved_thrust_secondaries: Array = [],
	resolved_half_moon_secondaries: Array = [],
	targets_resolved_at_release = false,
	configuration: RefCounted = null,
	damage_batch: RefCounted = null
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var skill_name: String = {
		"thrust": "刺杀剑术",
		"half_moon": "半月弯刀",
		"fire": "烈火剑法",
	}.get(mode, "")
	if skill_name.is_empty():
		return {"accepted": false, "hit_any": false, "resolution": "rejected"}
	if mode == WarriorMeleeGeometryScript.SKILL_THRUST and thrust_damage_axis_plan.is_empty():
		thrust_damage_axis_plan = (
			WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
				_melee_direction_index(direction, release_geometry),
				release_geometry,
				release_geometry.get("snapshot_validation_context", {})
			)
		)
	var primary_targets: Array = resolved_primary_targets
	var thrust_secondaries: Array = resolved_thrust_secondaries
	var half_moon_secondaries: Array = resolved_half_moon_secondaries
	var melee_query_plan: Dictionary = {}
	if not targets_resolved_at_release:
		var release_cache: Dictionary = {}
		melee_query_plan = _aoe_melee_query_plan(
			mode,
			_canonical_screen_px_to_ground_gu(origin),
			direction,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			target_aligned_plan if not target_aligned_plan.is_empty() else release_geometry.get("target_aligned_plan", {}),
			release_cache,
		)
		primary_targets = _physical_primary_targets(
			origin,
			direction,
			mode,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			target_aligned_plan if not target_aligned_plan.is_empty() else release_geometry.get("target_aligned_plan", {}),
			melee_query_plan,
		)
		if mode == "thrust":
			thrust_secondaries = _thrust_secondary_targets(
				origin,
				direction,
				primary_targets,
				release_geometry,
				thrust_damage_axis_plan,
				melee_release_snapshot,
				target_aligned_plan if not target_aligned_plan.is_empty() else release_geometry.get("target_aligned_plan", {}),
				melee_query_plan,
			)
		elif mode == "half_moon":
			half_moon_secondaries = _half_moon_secondary_targets(
				origin,
				direction,
				primary_targets,
				release_geometry,
				melee_release_snapshot,
				melee_query_plan,
			)
	var eligible_target_count = (
		primary_targets.size()
		+ thrust_secondaries.size()
		+ half_moon_secondaries.size()
	)
	var extra = {
		"release_id": str(release_geometry.get("release_id","")),
		"has_target": eligible_target_count > 0,
		"line_of_sight": eligible_target_count > 0,
		"valid_melee_swing": eligible_target_count > 0,
		"eligible_target_count": eligible_target_count,
		# The release-frame melee resolver already produced the authoritative
		# hostile target lists. Canonical planning must not run the generic spell
		# target scan (or its terrain probes) a second time.
		"hostile_targets_pre_resolved": targets_resolved_at_release,
		"charge_consumed": mode == "fire" and not primary_targets.is_empty(),
		"direct_toggle_release": (
			mode == "fire"
			and not primary_targets.is_empty()
			and direct_toggle_release
		),
	}
	# Q3-B: the melee release geometry is frozen before the canonical plan is
	# built; the plan consumes that same release snapshot instead of treating
	# warrior melee as non-spatial.
	if not melee_release_snapshot.is_empty():
		extra["skill_footprint_snapshot"] = melee_release_snapshot
		var melee_release_id = str(
			melee_release_snapshot.get("release_id", "")
		)
		if not melee_release_id.is_empty():
			extra["release_id"] = melee_release_id
	var result = _execute_canonical_skill(skill_name, origin, direction, base_damage, extra, false, false, configuration)
	if not bool(result.get("accepted", false)):
		return {"accepted": false, "hit_any": false, "resolution": "rejected"}
	var hit_any = false
	var primary_hit = false
	for raw_effect: Variant in result.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		match str(effect.get("type", "")):
			"melee_hit":
				var targets: Array = (
					primary_targets
					if int(effect.get("cell", 1)) == 1
					else thrust_secondaries
				)
				for target: Object in targets:
					var resolved_damage = (
						roundi(float(base_damage) * float(effect.get("multiplier", 1.0)))
						+ post_body_damage_bonus
					)
					var target_hit = _apply_physical_hit(
						target,
						resolved_damage,
						accuracy_bonus,
						mode == "thrust" and _rules.warrior.thrust_segment_ignores_ac(
							int(effect.get("cell", 1))
						),
						configuration,
						damage_batch,
					)
					hit_any = target_hit or hit_any
					if int(effect.get("cell", 1)) == 1:
						primary_hit = target_hit or primary_hit
			"melee_arc":
				for primary: Object in primary_targets:
					var target_hit = _apply_physical_hit(
						primary,
						roundi(float(base_damage) * float(effect.get("primary_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus, false, configuration, damage_batch
					)
					primary_hit = target_hit or primary_hit
					hit_any = target_hit or hit_any
				for secondary: Object in half_moon_secondaries:
					hit_any = _apply_physical_hit(
						secondary,
						roundi(float(base_damage) * float(effect.get("side_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus, false, configuration, damage_batch
					) or hit_any
			"next_melee_charge":
				if not primary_targets.is_empty():
					var target = primary_targets[0]
					primary_hit = _apply_physical_hit(
						target,
						roundi(float(base_damage) * float(effect.get("damage_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus, false, configuration, damage_batch
					)
					hit_any = primary_hit
	return {
		"accepted": true,
		"hit_any": hit_any,
		"primary_hit": primary_hit,
		"resolution": "hit" if hit_any else "miss",
	}


func _canonical_basic_sword_bonus(origin: Vector2, direction: Vector2, valid_swing: bool) -> int:
	if not _owned(): return 0
	if not _profile.is_skill_learned("基本剑术"):
		return 0
	var result = _execute_canonical_skill(
		"基本剑术",
		origin,
		direction,
		0,
		{"valid_melee_swing": valid_swing}
	)
	for raw_effect: Variant in result.get("effects", []):
		if raw_effect is Dictionary and str(raw_effect.get("type", "")) == "passive_stat_modifier":
			return int(raw_effect.get("value", 0))
	return 0


func _canonical_target_context(
	definition: Dictionary,
	origin: Vector2,
	direction: Vector2,
	allow_auto_target = true,
	release_id = "",
	context_overrides: Dictionary = {},
	configuration: RefCounted = null
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var target_contract: Dictionary = definition.get("target", {})
	var stable_skill_id = str(definition.get("skill_id", ""))
	var target_mode = str(target_contract.get("mode", ""))
	var target_relation = str(target_contract.get("relation", ""))
	var friendly_cast = target_relation.contains("friendly") or target_mode in ["self", "self_or_friendly_single"]
	var search_range_gu = SpellTargetLockPolicyScript.LOCK_RANGE_GU
	if allow_auto_target and not friendly_cast and target_mode not in ["self", "self_stat", "self_summon", "self_next_melee_charge", "self_random_destination", "caster_surrounding_area", "surrounding_units"]:
		_ensure_skill_cast_target(null)
	var target = _skill_cast_target if not friendly_cast and _actors.is_runtime_present(_skill_cast_target) else null
	var target_within_skill_range = (
		target != null and _spell_definition_allows_target(definition, target)
	)
	var hostile_target_required = _definition_requires_hostile_target(definition)
	var independent_geometry_target = (
		str(definition.get("skill_id", "")) != FIRE_WALL_SKILL_ID
		and not hostile_target_required
		and (
			target_mode == "facing_line"
			or target_mode.contains("surrounding")
			or target_mode.contains("ground")
			or target_mode.begins_with("self")
		)
	)
	var usable_target = (
		target != null
		and (not target_relation.contains("hostile") or target_within_skill_range)
	)
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	var direction_ground_gu = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
		direction
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		direction_ground_gu = GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.facing
		)
	direction_ground_gu = direction_ground_gu.normalized()
	var maximum_range_gu = float(
		definition.get("geometry", {}).get("maximum_range_gu", 0.0)
	)
	var fallback_distance_gu = (
		maximum_range_gu
		if maximum_range_gu > 0.0
		else search_range_gu
	)
	var fallback_target_ground_gu = (
		origin_ground_gu + direction_ground_gu * fallback_distance_gu
	)
	var fallback_target_tile = Vector2i(
		roundi(fallback_target_ground_gu.x),
		roundi(fallback_target_ground_gu.y)
	)
	if friendly_cast and GROUND_EXACT_SKILL_IDS.has(str(definition.get("skill_id", ""))):
		fallback_target_tile = _canonical_screen_px_to_grid_cell(origin)
	if maximum_range_gu > 0.0:
		fallback_target_tile = Vector2i(
			roundi(fallback_target_ground_gu.x),
			roundi(fallback_target_ground_gu.y)
		)
	var context = {
		"input_mode": "production_canonical",
		"runtime_map_id": current_map_id,
		"caster_runtime_id": _actors.runtime_actor_id(player),
		"has_target": usable_target or independent_geometry_target or friendly_cast,
		"line_of_sight": usable_target or independent_geometry_target or friendly_cast,
		"friendly": friendly_cast,
		"hostile": usable_target and not friendly_cast,
		"spell_lock_contract": SpellTargetLockPolicyScript.CONTRACT_ID,
		"spell_lock_range_gu": SpellTargetLockPolicyScript.LOCK_RANGE_GU,
		"target_within_skill_range": target_within_skill_range,
		"target_tile": _canonical_screen_px_to_grid_cell(
			_actors.position_screen_px(target)
			if usable_target
			else _canonical_grid_cell_to_screen_px(fallback_target_tile)
		),
		"primary_stat_roll": _canonical_primary_stat_roll(str(definition.get("class", "")), _canonical_action_primary_stats(configuration)),
		"actual_hp_missing": player.max_hp - player.current_hp,
		"friendly_missing_hp": [player.max_hp - player.current_hp],
		"affected_friendly_count": 1,
		"friendly_targets": [{
			"instance_id": _actors.runtime_actor_id(player),
			"target_instance_id": _actors.runtime_actor_id(player),
			"level": _profile.level,
		}],
		"friendly_target_instance_ids": [_actors.runtime_actor_id(player)],
		"affected_friendly_target_instance_ids": [_actors.runtime_actor_id(player)],
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"spawn_tile_valid": false,
		"has_main_pet": _canonical_main_pet() != null,
		"active_main_pet_summon_ids": _canonical_main_pet_summon_ids(),
		"requested_main_pet_summon_id": _summon_id_for_skill(stable_skill_id),
		"current_pet_count": _actors.actors_in_group("summons").size(),
		"caster_max_hp": player.max_hp,
	}
	if stable_skill_id == "taoist.summon_skeleton":
		var skeleton_slots = _owned_skeleton_slots()
		context["active_skeleton_count"] = skeleton_slots.size()
		context["next_skeleton_slot_index"] = _next_skeleton_slot_index(skeleton_slots)
	var snapshot_origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	context["snapshot_coordinate_context"] = (
		_canonical_snapshot_absolute_context(snapshot_origin_ground_gu)
	)
	if stable_skill_id == "wizard.teleport":
		var destination = _find_valid_skill_teleport_position(origin)
		context["destination_valid"] = destination != origin
		context["destination_tile"] = _canonical_screen_px_to_grid_cell(destination)
		context["destination_ground_gu"] = _canonical_screen_px_to_ground_gu(destination)
	if target != null:
		var monster_data: Dictionary = target.monster_data
		var target_control_immunity = target.control_immunity_snapshot()
		var service_behavior: Dictionary = target.behavior_profile.get(
			"serviceBehavior", {}
		)
		var target_is_undead = bool(service_behavior.get(
			"undead",
			monster_data.get("undead", monster_data.get("isUndead", false))
		))
		context.merge({
			"target_instance_id": _actors.runtime_actor_id(target),
			"target_level": int(monster_data.get("level", target.level)),
			"target_is_boss": target.is_boss,
			"target_immovable": target.is_boss,
			"target_is_monster": true,
			"target_is_undead": target_is_undead,
			"target_tameable": not target.is_boss,
			"target_has_other_master": false,
			"target_max_hp": target.max_hp,
			"target_poison_resist": target.anti_poison,
			"target_is_living": target.current_hp > 0,
			"actual_hp_missing": target.max_hp - target.current_hp,
			"target_control_immune": bool(
				target_control_immunity.get("immune", false)
			),
			"target_within_level_gate": target.level <= _profile.level,
		}, true)
	# Caller-provided authoritative values (for example a server-selected
	# teleport destination) must be applied before the immutable release
	# footprint is built.  Merging them afterwards produces a result whose
	# effect destination and footprint snapshot describe different ground
	# positions.
	context.merge(context_overrides, true)
	if stable_skill_id == "wizard.teleport":
		var teleport_ground: Vector2 = context.get("destination_ground_gu", Vector2.INF)
		context["destination_valid"] = (
			bool(context.get("destination_valid", false))
			and _skill_teleport_destination_is_valid(origin, teleport_ground)
		)
	if stable_skill_id == "wizard.lightning":
		context["line_of_sight"] = usable_target and _hc_lightning_clear(target, origin)
	if stable_skill_id in [
		"taoist.summon_skeleton",
		"taoist.summon_divine_beast",
	]:
		var summon_spawn_plan = _canonical_summon_spawn_plan(stable_skill_id, null, int(context.get("next_skeleton_slot_index", 0)))
		context["spawn_tile_valid"] = bool(
			summon_spawn_plan.get("valid", false)
		)
		context["summon_spawn_position_screen_px"] = summon_spawn_plan.get(
			"position_screen_px",
			_actors.position_screen_px(player)
		)
		context["summon_spawn_position_ground_gu"] = summon_spawn_plan.get(
			"position_ground_gu",
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
		)
	var resolved_release_id = str(release_id)
	if resolved_release_id.is_empty():
		resolved_release_id = _next_skill_footprint_release_id(stable_skill_id)
	context["release_id"] = resolved_release_id
	var exact_geometry_cells: Array[Vector2i] = []
	var exact_release_snapshot: Dictionary = {}
	if GROUND_EXACT_SKILL_IDS.has(stable_skill_id):
		var geometry_origin_tile: Vector2i = context.get(
			"origin_tile",
			_canonical_screen_px_to_grid_cell(origin)
		)
		var declared_geometry_cells = SkillGeometryServiceScript.cells(
			definition,
			geometry_origin_tile,
			Vector2i(signi(roundi(direction_ground_gu.x)), signi(roundi(direction_ground_gu.y))),
			context.get("target_tile", Vector2i.ZERO)
		)
		exact_geometry_cells = CasterSpellGeometryScript.effective_cells(
			stable_skill_id,
			definition.get("geometry", {}),
			declared_geometry_cells,
			Callable(self, "_canonical_spell_cell_is_terrain_blocked")
		)
		exact_release_snapshot = (
			CasterSpellGeometryScript.create_exact_cell_union_release_snapshot(
				stable_skill_id,
				resolved_release_id,
				origin_ground_gu,
				exact_geometry_cells,
				_canonical_snapshot_absolute_context(origin_ground_gu)
			)
		)
		context["geometry_cells"] = exact_geometry_cells
		context["skill_footprint_snapshot"] = exact_release_snapshot
	elif TARGET_FOOTPRINT_SKILL_IDS.has(stable_skill_id):
		var target_actor: Object = target if _actors.is_runtime_present(target) else player
		if (
			stable_skill_id == "taoist.healing"
			and int(context.get("selected_friendly_instance_id", 0)) > 0
		):
			var selected_friendly_actor = _canonical_friendly_actor(
				int(context.get("selected_friendly_instance_id", 0))
			)
			if selected_friendly_actor != null:
				target_actor = selected_friendly_actor
		if _actors.is_runtime_present(target_actor):
			context["skill_footprint_snapshot"] = (
				SkillFootprintSnapshotScript.create_target_footprint(
					stable_skill_id,
					resolved_release_id,
					_canonical_screen_px_to_ground_gu(_actors.position_screen_px(target_actor)),
					_actor_combat_radius_gu(target_actor),
					_actors.runtime_actor_id(target_actor),
					_canonical_snapshot_absolute_context(
						_canonical_screen_px_to_ground_gu(
							_actors.position_screen_px(target_actor)
						)
					)
				)
			)
	elif ATTACHED_STATE_SKILL_IDS.has(stable_skill_id) and _actors.is_runtime_present(player):
		context["skill_footprint_snapshot"] = (
			SkillFootprintSnapshotScript.create_target_footprint(
				stable_skill_id,
				resolved_release_id,
				_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player)),
				_actor_combat_radius_gu(player),
				_actors.runtime_actor_id(player),
				_canonical_snapshot_absolute_context(
					_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
				)
			)
		)
	elif stable_skill_id == "wizard.teleport":
		var teleport_destination_ground_gu: Vector2 = context.get(
			"destination_ground_gu", Vector2.INF)
		context["skill_footprint_snapshot"] = (
			SkillFootprintSnapshotScript.create_target_footprint(
				stable_skill_id,
				resolved_release_id,
				teleport_destination_ground_gu,
				_actor_combat_radius_gu(player),
				_actors.runtime_actor_id(player),
				_canonical_snapshot_absolute_context(
					teleport_destination_ground_gu
				)
			)
		)
	var exact_snapshot_valid = false
	if (
		not bool(context.get("hostile_targets_pre_resolved", false))
		or friendly_cast
	):
		exact_snapshot_valid = _snapshot_strict_ok(exact_release_snapshot)
	var nearby: Array[Dictionary] = []
	var adjacent_ring_cells: Array[Vector2i] = []
	if str(definition.get("geometry", {}).get("shape", "")) == "adjacent_ring":
		var caster_tile = _canonical_screen_px_to_grid_cell(origin)
		for ring_y: int in range(-1, 2):
			for ring_x: int in range(-1, 2):
				if ring_x != 0 or ring_y != 0:
					adjacent_ring_cells.append(
						caster_tile + Vector2i(ring_x, ring_y)
					)
	if (
		SkillRuntimeClassificationScript.needs_hostile_context_targets(stable_skill_id)
		and not bool(context.get("hostile_targets_pre_resolved", false))
	):
		# The broadphase envelope is deliberately conservative; the exact
		# snapshot/range/adjacent-ring checks below remain authoritative.
		var target_query_bounds = Rect2(
			origin_ground_gu - Vector2.ONE * search_range_gu,
			Vector2.ONE * search_range_gu * 2.0,
		)
		if exact_snapshot_valid:
			var snapshot_aabb = SkillFootprintSnapshotScript.ground_aabb(
				exact_release_snapshot
			)
			if bool(snapshot_aabb.get("valid", false)):
				target_query_bounds = snapshot_aabb.get(
					"bounds_ground_gu",
					target_query_bounds
				)
		if _target_spatial_query_aabb_into(
			target_query_bounds,
			_target_spatial_query_scratch,
		):
			for node: Object in _target_spatial_query_scratch:
				if (
					exact_snapshot_valid
					and not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
						exact_release_snapshot,
						_canonical_screen_px_to_ground_gu(_actors.position_screen_px(node)),
						node.combat_radius_gu,
					)
				):
					continue
				if (
					not exact_snapshot_valid
					and not GroundUnitSpaceScript.is_within_range_gu(
						origin_ground_gu,
						_canonical_screen_px_to_ground_gu(_actors.position_screen_px(node)),
						search_range_gu
					)
				):
					continue
				if (
					not exact_snapshot_valid and not adjacent_ring_cells.is_empty()
					and not bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
						adjacent_ring_cells,
						_canonical_screen_px_to_ground_gu(_actors.position_screen_px(node)),
						node.combat_radius_gu
					).get("intersects", false))
				):
					continue
				var node_ground_gu = _canonical_screen_px_to_ground_gu(
					_actors.position_screen_px(node)
				)
				nearby.append({
					"instance_id": _actors.runtime_actor_id(node),
					"target_instance_id": _actors.runtime_actor_id(node),
					"level": node.level,
					"is_boss": node.is_boss,
					"immovable": node.is_boss,
					"path_blocked": SkillRuntimeClassificationScript.needs_push_path_probe(stable_skill_id) and _geometry.is_environment_point_blocked(
						_canonical_ground_gu_to_screen_px(
							node_ground_gu + (
								node_ground_gu - origin_ground_gu
							).normalized()
						)
					),
					"hostile_monster": true,
					"control_immune": node.is_boss,
					"within_level_gate": node.level <= _profile.level,
				})
	context["targets"] = nearby
	if friendly_cast and exact_snapshot_valid:
		var friendly_targets: Array[Dictionary] = []
		var friendly_missing_hp: Array[int] = []
		var friendly_actors: Array = [player]
		for summon_node: Object in _actors.actors_in_group("summons"):
			if _actors.is_kind(summon_node, &"summon") and _actors.owner_model(summon_node) == player:
				friendly_actors.append(summon_node)
		for friendly_actor: Object in friendly_actors:
			if not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
				exact_release_snapshot,
				_canonical_screen_px_to_ground_gu(_actors.position_screen_px(friendly_actor)),
				_actor_combat_radius_gu(friendly_actor)
			):
				continue
			var actor_level = (
				_profile.level
				if friendly_actor == player
				else int(friendly_actor.owner_level)
			)
			var actor_max_hp = int(friendly_actor.get("max_hp"))
			var actor_current_hp = int(friendly_actor.get("current_hp"))
			friendly_targets.append({
				"instance_id": _actors.runtime_actor_id(friendly_actor),
				"target_instance_id": _actors.runtime_actor_id(friendly_actor),
				"level": actor_level,
			})
			friendly_missing_hp.append(maxi(0, actor_max_hp - actor_current_hp))
		context["friendly_targets"] = friendly_targets
		context["friendly_missing_hp"] = friendly_missing_hp
		context["affected_friendly_count"] = friendly_targets.size()
		var friendly_target_instance_ids: Array[int] = []
		for friendly_data: Dictionary in friendly_targets:
			friendly_target_instance_ids.append(int(friendly_data.get(
				"target_instance_id", 0
			)))
		context["friendly_target_instance_ids"] = friendly_target_instance_ids
		context["affected_friendly_target_instance_ids"] = (
			friendly_target_instance_ids.duplicate()
		)
	return context


func _canonical_resource_context(stable_skill_id: String, configuration: RefCounted = null) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var result = _profile.canonical_skill_resource_context(
		stable_skill_id,
		player.current_mp
	)
	if configuration != null:
		player._freeze_partner_resource_context(result, configuration)
	var requested_summon_id = _summon_id_for_skill(stable_skill_id)
	if not requested_summon_id.is_empty():
		# Live actors are authoritative during play. PlayerState supplies the same
		# typed contract to Player.can_request_skill and old-save restoration.
		result["requested_main_pet_summon_id"] = requested_summon_id
		result["active_main_pet_summon_ids"] = (
			_canonical_main_pet_summon_ids()
		)
		if requested_summon_id == "skeleton":
			result["active_skeleton_count"] = _owned_skeleton_slots().size()
		result["effective_skill_rank"] = _profile.effective_skill_level(stable_skill_id)
	return result


func _commit_canonical_resources(result: Dictionary) -> bool:
	if not _owned(): return false
	## Q3-B: consumes the canonical plan's frozen resource_cost (legacy
	## resource_quote accepted for compat); commits at most once per release.
	var quote: Dictionary = result.get(
		"resource_quote",
		result.get("resource_cost", {})
	)
	var mana_cost = maxi(0, int(quote.get("mp_cost", 0)))
	var material_id = str(quote.get("material_id", ""))
	var material_amount = maxi(0, int(quote.get("material_amount", 0)))
	var item_name = _profile.canonical_material_item_name(material_id)
	if player.current_mp < mana_cost:
		return false
	if material_amount > 0 and (item_name.is_empty() or _profile.item_count(item_name) < material_amount):
		return false
	if not player.spend_mana(mana_cost):
		return false
	if material_amount > 0 and not _profile.remove_item(item_name, material_amount):
		player.restore_mana(mana_cost)
		return false
	_plan_contract.resource_commit_count += 1
	return true


func _canonical_summon_resource_commit_rejection(plan: Dictionary) -> String:
	if not _owned(): return ""
	## A release may retain an accepted rank while live equipment has changed.
	## Recheck only the final summon sink's safety limit before committing MP or
	## materials; the accepted plan and its rank remain immutable.
	for raw_descriptor: Variant in plan.get("summon_descriptors", []):
		if not raw_descriptor is Dictionary:
			continue
		var descriptor = raw_descriptor as Dictionary
		if str(descriptor.get("operation", "")) != "main_pet_spawn":
			continue
		if not bool(descriptor.get("spawned", false)):
			continue
		var summon_id = str(descriptor.get("template_id", ""))
		var live_pets = _canonical_main_pets(summon_id)
		if summon_id == "skeleton":
			var live_cap = SkillRankResolver.skeleton_count(
				_profile.effective_skill_level(str(plan.get("skill_id", "")))
			)
			if live_pets.size() >= live_cap:
				return "summon_live_cap_changed"
			var requested_slot = int(descriptor.get("pet_slot_index", 0))
			for pet: Object in live_pets:
				if pet.pet_slot_index == requested_slot:
					return "summon_slot_already_occupied"
		elif summon_id == "divine_beast" and not live_pets.is_empty():
			return "summon_live_cap_changed"
	return ""


func _apply_canonical_effects_from_plan(
	plan: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: Object = null,
	configuration: RefCounted = null,
	feature_batch: RefCounted = null
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## Q3-B: commits the canonical plan's gameplay actions. Object creation
	## (projectile/ground/summon/visual) comes from the plan's descriptors via
	## create_cast_nodes_from_canonical_plan; this loop only applies direct
	## damage/status/buff side effects. No second plan is ever built.
	var stable_skill_id = str(plan.get("skill_id", ""))
	if not _actors.is_runtime_present(target):
		target = null
	var target_position = _canonical_grid_cell_to_screen_px(
		target_context.get(
			"target_tile",
			_canonical_screen_px_to_grid_cell(origin)
		)
	)
	var release_id = str(plan.get("release_id", ""))
	var skill_release_snapshot: Dictionary = plan.get(
		"canonical_snapshot", {}
	)
	var effective_geometry_cells: Array[Vector2i] = []
	for raw_cell: Variant in plan.get("effective_geometry_cells", []):
		if raw_cell is Vector2i:
			effective_geometry_cells.append(raw_cell)
	var continuous_line_strip_ground_gu: Dictionary = plan.get(
		"continuous_line_strip_ground_gu", {}
	)
	var aoe_release_cache: Dictionary = {}
	var spawned_nodes: Array = _spawn_canonical_cast_nodes_from_plan(
		plan,
		origin,
		direction,
		target,
		target_position,
		configuration
	)
	var spawned_projectiles: Array[int] = []
	var spawned_ground_effects: Array[int] = []
	var spawned_summons: Array[int] = []
	var created_visuals: Array[int] = []
	var applied_status_results: Array[Dictionary] = []
	for node: Object in spawned_nodes:
		if _actors.is_kind(node, &"projectile"):
			spawned_projectiles.append(_actors.runtime_actor_id(node))
		elif _actors.is_kind(node, &"field") or _actors.is_kind(node, &"fire_wall"):
			spawned_ground_effects.append(_actors.runtime_actor_id(node))
		elif _actors.is_kind(node, &"summon"):
			spawned_summons.append(_actors.runtime_actor_id(node))
		else:
			created_visuals.append(_actors.runtime_actor_id(node))
	var friendly_effect_index = 0
	for raw_effect: Variant in plan.get("gameplay_actions", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type = str(effect.get("type", ""))
		match effect_type:
			"projectile_damage", "talisman_projectile_damage", "persistent_ground_damage", "main_pet_spawn", "recall_existing_main_pet":
				# Object creation is owned by the canonical descriptors (adapter /
				# summon sink); the gameplay action itself is already committed.
				pass
			"targeted_sky_strike", "line_damage", "piercing_line_damage", "area_damage", "caster_centered_area_damage":
				var raw_power = int(
					effect.get(
						"raw_power_after_race",
						effect.get("raw_power", 0)
					)
				)
				var damage_origin = (
					_canonical_grid_cell_to_screen_px(
						target_context.get("target_tile", Vector2i.ZERO)
					)
					if effect_type == "area_damage"
					else origin
				)
				_apply_canonical_spell_damage(
					stable_skill_id,
					raw_power,
					damage_origin,
					direction,
					effect_type,
					target,
					effective_geometry_cells,
					effect,
					continuous_line_strip_ground_gu,
					skill_release_snapshot,
					{},
					aoe_release_cache,
					feature_batch,
				)
			"dedicated_heal":
				var heal_target_id = int(
					effect.get("target_instance_id", 0)
				)
				var heal_actor = (
					_canonical_friendly_actor(heal_target_id)
					if heal_target_id > 0
					else player
				)
				_apply_canonical_friendly_heal(
					heal_actor,
					int(effect.get("actual_hp_restored", 0))
				)
				var ongoing_heal: Variant = effect.get("ongoing_heal", {})
				if ongoing_heal is Dictionary and not (
					ongoing_heal as Dictionary
				).is_empty():
					_register_ongoing_heal(
						int(
							(ongoing_heal as Dictionary).get(
								"target_instance_id",
								heal_target_id
							)
						),
						int((ongoing_heal as Dictionary).get("heal_per_tick", 1)),
						int((ongoing_heal as Dictionary).get("tick_count", 3)),
						float(
							(ongoing_heal as Dictionary).get(
								"tick_interval_seconds",
								0.8
							)
						)
					)
			"dedicated_area_heal":
				var target_results: Array = effect.get("target_results", [])
				if not target_results.is_empty():
					for target_result_value: Variant in target_results:
						if not target_result_value is Dictionary:
							continue
						var target_result: Dictionary = target_result_value
						_apply_canonical_friendly_heal(
							_canonical_friendly_actor(
								int(target_result.get("target_instance_id", 0))
							),
							int(target_result.get("actual_hp_restored", 0))
						)
				else:
					var restored_by_target: Array = effect.get(
						"actual_hp_restored_by_target", []
					)
					var friendly_targets: Array = target_context.get(
						"friendly_targets", []
					)
					for heal_index: int in range(mini(
						restored_by_target.size(), friendly_targets.size()
					)):
						var friendly_data: Dictionary = friendly_targets[heal_index]
						_apply_canonical_friendly_heal(
							_canonical_friendly_actor(
								int(friendly_data.get(
									"target_instance_id",
									friendly_data.get("instance_id", 0)
								))
							),
							int(restored_by_target[heal_index])
						)
				var ongoing_heal_targets: Array = effect.get(
					"ongoing_heal_targets",
					[]
				)
				for raw_ongoing: Variant in ongoing_heal_targets:
					if not raw_ongoing is Dictionary:
						continue
					var ongoing_entry: Dictionary = raw_ongoing
					_register_ongoing_heal(
						int(ongoing_entry.get("target_instance_id", 0)),
						int(ongoing_entry.get("heal_per_tick", 1)),
						int(ongoing_entry.get("tick_count", 3)),
						float(
							ongoing_entry.get(
								"tick_interval_seconds",
								0.8
							)
						)
					)
			"adjacent_push":
				var repulsion_target = _canonical_effect_enemy(effect)
				if (
					repulsion_target != null
					and bool(effect.get("displaced", false))
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						repulsion_target
					)
				):
					var source_ground_gu = _canonical_screen_px_to_ground_gu(
						origin
					)
					var target_ground_gu = _canonical_screen_px_to_ground_gu(
						_actors.position_screen_px(repulsion_target)
					)
					var push_direction_ground_gu = (
						target_ground_gu - source_ground_gu
					).normalized()
					_apply_canonical_displacement_screen_px(
						repulsion_target,
						GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
							push_direction_ground_gu
							* float(effect.get("push_distance_gu", 1.0))
						)
					)
			"level_gated_push":
				if target != null and bool(effect.get("displaced", false)):
					_apply_wild_rush_displacement(target, effect, target_context)
			"self_damage":
				_combat.apply_damage(
					player,
					int(effect.get("amount", 1))
				)
			"server_random_teleport":
				var teleport_applied = false
				var destination_ground_gu: Vector2 = effect.get("destination_ground_gu", Vector2.INF)
				if bool(effect.get("moved", false)):
					var destination = _canonical_ground_gu_to_screen_px(destination_ground_gu)
					var snapshot_destination_ground_gu: Vector2 = (
						skill_release_snapshot.get(
							"target_center_ground_gu", Vector2.INF
						)
					)
					if (
						_snapshot_strict_ok(skill_release_snapshot)
						and snapshot_destination_ground_gu.is_equal_approx(
							destination_ground_gu
						)
						and _skill_teleport_destination_is_valid(origin, destination_ground_gu)
						and _apply_canonical_player_teleport(destination)
					):
						teleport_applied = true
						_presentation.spawn_canonical_teleport_arrival(
							stable_skill_id,
							destination,
							direction,
							skill_release_snapshot
						)
				applied_status_results.append({
					"type": "player_teleport", "applied": teleport_applied,
					"destination_ground_gu": destination_ground_gu,
				})
			"refreshable_damage_reduction_buff":
				player.apply_magic_shield(
					float(effect.get("duration_seconds", 1)),
					float(effect.get("damage_reduction", 0.0))
				)
			"monster_aggro_stealth":
				player.apply_stealth(
					float(effect.get("duration_seconds", 1))
				)
			"area_monster_aggro_stealth":
				var stealth_target_ids: Array = effect.get(
					"target_instance_ids", []
				)
				if stealth_target_ids.is_empty():
					for friendly_data: Dictionary in target_context.get(
						"friendly_targets", []
					):
						stealth_target_ids.append(
							int(friendly_data.get("instance_id", 0))
						)
				for target_instance_id: int in stealth_target_ids:
					var stealth_actor = _canonical_friendly_actor(
						target_instance_id
					)
					_apply_friendly_stealth_to_actor(
						stealth_actor,
						float(effect.get("duration_seconds", 1)),
						str(
							effect.get(
								"buff_id",
								"buff.taoist.mass_invisibility"
							)
						)
					)
			"friendly_defence_buff":
				var defence_stat = str(effect.get("stat", "AC"))
				var defence_duration = float(
					effect.get("duration_seconds", 1)
				)
				var defence_buff_id = str(effect.get("buff_id", ""))
				var aggregate_targets: Array = effect.get("targets", [])
				if not aggregate_targets.is_empty():
					for raw_entry: Variant in aggregate_targets:
						if not raw_entry is Dictionary:
							continue
						var entry: Dictionary = raw_entry
						_apply_friendly_defence_buff_to_actor(
							_canonical_friendly_actor(
								int(entry.get("target_instance_id", 0))
							),
							defence_stat,
							int(
								entry.get(
									"value",
									entry.get("flat_bonus", 1)
								)
							),
							defence_duration,
							defence_buff_id
						)
				else:
					var buff_target_id = int(
						effect.get("target_instance_id", 0)
					)
					if buff_target_id <= 0:
						var friendly_targets: Array = target_context.get(
							"friendly_targets", []
						)
						if friendly_effect_index < friendly_targets.size():
							buff_target_id = int(
								(friendly_targets[friendly_effect_index] as Dictionary).get(
									"instance_id", 0
								)
							)
					friendly_effect_index += 1
					_apply_friendly_defence_buff_to_actor(
						_canonical_friendly_actor(buff_target_id),
						defence_stat,
						int(
							effect.get(
								"value",
								effect.get("flat_bonus", 1)
							)
						),
						defence_duration,
						defence_buff_id
					)
			"poison_resolution":
				if (
					target != null
					and not bool(effect.get("resisted", false))
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						target
					)
				):
					_apply_canonical_poison(target, effect)
			"temptation_resolution":
				if (
					target != null
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						target
					)
				):
					_apply_canonical_temptation(target, effect)
			"holy_word_resolution":
				if (
					target != null
					and bool(effect.get("instant_kill", false))
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						target
					)
				):
					_combat.apply_enemy_physical_damage(
						target,
						target.current_hp,
						player
					)
			"hp_information_reveal":
				if (
					target != null
					and bool(effect.get("revealed", false))
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						target
					)
				):
					_presentation.show_message(
						"%s：生命 %d/%d" % [
							target.display_name,
							target.current_hp,
							target.max_hp,
						],
						2.0
					)
			"monster_boundary_control":
				if int(effect.get("trapped_count", 0)) > 0:
					var trapped_target_ids: Array = effect.get(
						"target_instance_ids", []
					)
					for trapped_target_id: int in trapped_target_ids:
						var node = _actors.resolve_runtime_model(trapped_target_id)
						## The plan's trapped identity and immutable strict-V2
						## release snapshot are authoritative. Object owns the
						## boundary lifecycle; this integration sink must not
						## degrade entrapment into generic immobilization.
						if _actors.is_kind(node, &"enemy"):
							node.apply_entrapment(
								effect,
								skill_release_snapshot,
								player
							)
			"next_melee_charge":
				_set_canonical_fire_charge_expires_at(
					_clock.now_msec()
					+ maxi(1, int(effect.get("charge_lifetime_ms", 10000)))
				)
	return {
		"spawned_projectile_ids": spawned_projectiles,
		"status_results": applied_status_results,
		"spawned_ground_effect_ids": spawned_ground_effects,
		"spawned_summon_ids": spawned_summons,
		"created_visual_ids": created_visuals,
		"side_effect_count": (
			spawned_projectiles.size()
			+ spawned_ground_effects.size()
			+ spawned_summons.size()
			+ created_visuals.size()
		),
	}


func _spawn_canonical_cast_nodes_from_plan(
	plan: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target: Object,
	target_position: Vector2,
	configuration: RefCounted = null
) -> Array:
	if not _owned(): return []
	## Q3-B: the ONLY formal node creation entry - CasterSkillRuntime consumes
	## the canonical plan (no legacy presentation plan or cast-node entry).
	var stable_skill_id = str(plan.get("skill_id", ""))
	if stable_skill_id == FIRE_WALL_SKILL_ID:
		# Q2-C/Q3-B: the formal fire wall release owns exactly ONE
		# Object plus its pure-visual cells (3x3 geometry =>
		# 9 cells today; the old "4 cells" comment predates the 2026-09-13
		# geometry override). Never fall back
		# to the generic ground-dot factory or standalone Object
		# cells; the field controller is the single damage/visual owner.
		var ground_effect = _canonical_plan_ground_effect(plan)
		if not ground_effect.is_empty():
			return _spawn_canonical_ground_field(
				stable_skill_id,
				plan.get("effective_geometry_cells", []),
				target_position,
				ground_effect,
				str(plan.get("release_id", "")),
				plan.get("canonical_snapshot", {})
			)
		return []
	if (
		not stable_skill_id.begins_with("wizard.")
		and not stable_skill_id.begins_with("taoist.")
	):
		return []
	var nodes: Array = (
		_casting.create_cast_models_from_canonical_plan(
			plan,
			origin,
			direction,
			Color.WHITE,
			target,
			player,
			_canonical_primary_stat_roll("taoist", _canonical_action_primary_stats(configuration)),
			configuration.actor_level() if configuration != null else _profile.level,
			Callable(self, "_apply_canonical_main_pet_from_descriptor"),
			{
				"action_definition": configuration.definition_for(stable_skill_id) if configuration != null else _profile.effective_skill_definition(stable_skill_id),
				"combat_spatial_index": _spatial,
				"runtime_map_id": current_map_id,
				"ground_gu_to_screen_position_px": (
					Callable(self, "_canonical_ground_gu_to_screen_px")
				),
				"screen_to_ground_position_px": (
					Callable(self, "_canonical_screen_px_to_ground_gu")
				),
				"magic_defense_adapter": Callable(
					self,
					"_resolve_magic_defense"
				),
				"caster": player,
			}
		)
	)
	for node: Object in nodes:
		if _actors.is_runtime_present(node):
			_world.register_cast_model(node)
	return nodes


func _canonical_plan_ground_effect(plan: Dictionary) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	for raw_effect: Variant in plan.get("gameplay_actions", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		if str(effect.get("type", "")) == "persistent_ground_damage":
			return effect
	return {}


func _apply_canonical_main_pet_from_descriptor(
	descriptor: Dictionary,
	plan: Dictionary
) -> void:
	if not _owned(): return
	_apply_canonical_main_pet(
		descriptor,
		str(plan.get("skill_id", "")),
		str(plan.get("release_id", ""))
	)


func _canonical_effect_enemy(effect: Dictionary) -> Object:
	if not _owned(): return null
	var instance_id = int(effect.get("target_instance_id", 0))
	if instance_id <= 0:
		return null
	var candidate = _actors.resolve_runtime_model(instance_id)
	if (
		_actors.is_kind(candidate, &"enemy")
		and _actors.is_runtime_present(candidate)
		and _actors.is_inside_world(candidate)
		and not _actors.is_queued_for_retirement(candidate)
	):
		return candidate
	return null


func _set_canonical_fire_charge_expires_at(expires_at_ms: int) -> void:
	if not _owned(): return
	_canonical_fire_charge_expires_ms = maxi(0, expires_at_ms)
	if player != null:
		player.set_fire_sword_charge_display(_canonical_fire_charge_expires_ms)


func _expire_canonical_fire_charge_if_needed() -> void:
	if not _owned(): return
	if (
		_canonical_fire_charge_expires_ms > 0
		and _clock.now_msec() >= _canonical_fire_charge_expires_ms
	):
		_set_canonical_fire_charge_expires_at(0)


func _apply_canonical_spell_damage(
	stable_skill_id: String,
	raw_power: int,
	origin: Vector2,
	direction: Vector2,
	effect_type: String,
	primary: Object,
	raw_geometry_cells: Variant = [],
	effect: Dictionary = {},
	continuous_line_strip_ground_gu: Dictionary = {},
	skill_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
	release_cache: Dictionary = {},
	damage_batch: RefCounted = null,
) -> bool:
	if not _owned(): return false
	var resolved_snapshot = _aoe_spell_snapshot(
		skill_release_snapshot,
		continuous_line_strip_ground_gu,
	)
	var context_release_id = str(resolved_snapshot.get("release_id", ""))
	if context_release_id.is_empty():
		context_release_id = str(continuous_line_strip_ground_gu.get("release_id", ""))
	var context_skill_id = stable_skill_id if not stable_skill_id.is_empty() else "canonical_aoe"
	if context_release_id.is_empty():
		context_release_id = context_skill_id
	_diagnostics.set_performance_release_context(
		context_release_id,
		context_skill_id,
	)
	_diagnostics.increment_performance_counter(&"aoe_release_count")
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_spell_query_plan(
			stable_skill_id,
			raw_geometry_cells,
			effect,
			continuous_line_strip_ground_gu,
			resolved_snapshot,
			_canonical_screen_px_to_ground_gu(origin),
			release_cache,
		)
	var aoe_candidate_started_usec = _diagnostics.timing_start()
	if not _aoe_plan_is_ready(plan) and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"aoe_query_plan_invalid_or_spatial_index_unavailable"
		)
		_record_aoe_candidate_timing(aoe_candidate_started_usec)
		return false
	var targets: Array = []
	var has_declared_geometry_cells = (
		raw_geometry_cells is Array
		and not (raw_geometry_cells as Array).is_empty()
	)
	if stable_skill_id in CANONICAL_WIZARD_GEOMETRY_SKILLS or has_declared_geometry_cells:
		targets = _canonical_spell_geometry_targets(
			stable_skill_id,
			raw_geometry_cells,
			effect,
			continuous_line_strip_ground_gu,
			resolved_snapshot,
			plan,
		)
	elif (
		effect_type == "targeted_sky_strike"
		and primary != null
	):
		if _aoe_plan_is_ready(plan):
			if _aoe_query_enemy_candidates_aabb(
				plan,
				plan.get("ground_aabb", Rect2()),
				false,
			):
				for node: Object in _aoe_candidate_scratch:
					_diagnostics.increment_performance_counter(
						&"aoe_exact_intersection_tests"
					)
					if node == primary and _aoe_validated_snapshot_intersects(plan, node):
						targets.append(node)
						break
				if targets.is_empty() and _aoe_validated_snapshot_intersects(plan, primary):
					# The locked target is already an authoritative identity; the
					# broadphase only gates unbounded discovery and does not replace
					# direct identity resolution.
					targets.append(primary)
		elif _aoe_reference_fallback_allowed() and _skill_snapshot_intersects_enemy(
			resolved_snapshot,
			primary,
		):
			targets.append(primary)
	elif (
		primary != null
		and effect_type not in ["area_damage", "caster_centered_area_damage"]
	):
		if _aoe_plan_is_ready(plan):
			if _aoe_query_enemy_candidates_aabb(
				plan,
				plan.get("ground_aabb", Rect2()),
				false,
			):
				for node: Object in _aoe_candidate_scratch:
					_diagnostics.increment_performance_counter(
						&"aoe_exact_intersection_tests"
					)
					if node == primary and _aoe_validated_snapshot_intersects(plan, node):
						targets.append(node)
						break
				if targets.is_empty() and _aoe_validated_snapshot_intersects(plan, primary):
					targets.append(primary)
		elif _aoe_reference_fallback_allowed() and (
				resolved_snapshot.is_empty()
				or _skill_snapshot_intersects_enemy(resolved_snapshot, primary)
			):
			targets.append(primary)
	else:
		var radial: bool = effect_type in ["area_damage", "caster_centered_area_damage"]
		var radius_gu = maxf(0.0, float(effect.get("radius_gu", 0.0)))
		if not radial or radius_gu <= 0.0:
			_record_aoe_candidate_timing(aoe_candidate_started_usec)
			return false
		if _aoe_plan_is_ready(plan):
			_aoe_query_enemy_candidates_aabb(
				plan,
				plan.get("ground_aabb", Rect2()),
				false,
			)
			for enemy: Object in _aoe_candidate_scratch:
				_diagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _aoe_validated_snapshot_intersects(plan, enemy):
					targets.append(enemy)
		elif _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			for enemy: Object in _aoe_candidate_scratch:
				_diagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _ground_circle_intersects_enemy_footprint_gu(
					origin,
					radius_gu,
					enemy,
				):
					targets.append(enemy)
		if targets.is_empty() and _aoe_plan_is_ready(plan) and _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			for enemy: Object in _aoe_candidate_scratch:
				_diagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _aoe_validated_snapshot_intersects(plan, enemy):
					targets.append(enemy)
	_record_aoe_candidate_timing(aoe_candidate_started_usec)
	_diagnostics.increment_performance_counter(&"aoe_selected_targets", targets.size())
	_diagnostics.increment_performance_counter(&"aoe_damage_target_count", targets.size())
	var aoe_exact_started_usec = _diagnostics.timing_start()
	var hit_any = false
	for enemy: Object in targets:
		if stable_skill_id == "wizard.lightning" and not _hc_lightning_clear(enemy, origin):
			continue
		var resolution: Dictionary = _combat.apply_enemy_direct_spell_damage(
			enemy,
			stable_skill_id,
			raw_power,
			player,
			_random,
			Callable(self, "_resolve_magic_defense"),
			-1,
			_direct_spell_target_stats_scratch,
			# source176 Task 1: generic canonical-AoE applier - registry-resolved
			# delivery family; unknown ids fail closed.
			_combat.EnemyMagicDeliveryKind.AUTO,
			{"feature_damage_batch":damage_batch,"source_class":"direct","damage_channel":"magic_defense"} if damage_batch != null else {},
		)
		hit_any = bool(resolution.get("success", false)) or hit_any
	_diagnostics.record_timing_usec(&"aoe_exact_phase_usec", aoe_exact_started_usec)
	_record_skill_footprint_release_diagnostic(
		stable_skill_id,
		resolved_snapshot,
		targets.size(),
		hit_any
	)
	return hit_any


func _record_aoe_candidate_timing(started_usec: int) -> void:
	if not _owned(): return
	var elapsed_usec = _diagnostics.timing_elapsed_usec(started_usec)
	if elapsed_usec <= 0:
		return
	_diagnostics.increment_performance_counter(&"aoe_candidate_usec", elapsed_usec)
	_diagnostics.record_performance_max(
		&"aoe_max_single_release_candidate_usec",
		float(elapsed_usec),
	)


func _record_skill_footprint_release_diagnostic(
	stable_skill_id: String,
	skill_release_snapshot: Dictionary,
	eligible_target_count: int,
	damage_applied: bool
) -> void:
	if not _owned(): return
	if not _diagnostics.footprint_capture_enabled():
		return
	var raw_snapshot: Variant = skill_release_snapshot
	if not _snapshot_strict_ok(skill_release_snapshot):
		raw_snapshot = skill_release_snapshot.get("skill_footprint_snapshot", {})
	if (
		not raw_snapshot is Dictionary
		or not _snapshot_strict_ok(raw_snapshot)
	):
		return
	var snapshot: Dictionary = raw_snapshot as Dictionary
	var projected_polygon_px = (
		SkillFootprintSnapshotScript.projected_polygon_screen_offset_px(
			snapshot
		)
	)
	_diagnostics.footprint_record({
		"event": "skill_footprint_release_resolved",
		"release_id": str(snapshot.get("release_id", "")),
		"snapshot_id": str(snapshot.get("snapshot_id", "")),
		"skill_id": stable_skill_id,
		"shape_type": str(snapshot.get("shape_type", "")),
		"origin_ground_gu": snapshot.get("origin_ground_gu", Vector2.ZERO),
		"direction_ground_gu": snapshot.get(
			"direction_ground_gu", Vector2.ZERO
		),
		"effect_length_gu": float(snapshot.get("effect_length_gu", 0.0)),
		"effect_width_gu": float(snapshot.get("effect_width_gu", 0.0)),
		"expected_length_px": float(snapshot.get("axis_screen_length_px", 0.0)),
		"actual_visual_core_length_px": float(
			snapshot.get("axis_screen_length_px", 0.0)
		),
		"expected_width_px": float(snapshot.get("cross_screen_extent_px", 0.0)),
		"actual_visual_core_width_px": float(
			snapshot.get("cross_screen_extent_px", 0.0)
		),
		"declared_effect_length_gu": float(
			snapshot.get(
				"declared_effect_length_gu",
				snapshot.get("effect_length_gu", 0.0)
			)
		),
		"resolved_effect_length_gu": float(
			snapshot.get(
				"resolved_effect_length_gu",
				snapshot.get("effect_length_gu", 0.0)
			)
		),
		"projection_policy": str(snapshot.get("laser_projection_policy", "")),
		"expected_projected_polygon_px": projected_polygon_px,
		"actual_visual_core_polygon_px": projected_polygon_px,
		"maximum_corner_error_px": 0.0,
		"eligible_target_count": eligible_target_count,
		"damage_applied": damage_applied,
		"terrain_truncated": bool(skill_release_snapshot.get(
			"terrain_truncated", false
		)),
	})


func _actor_combat_radius_gu(actor: Object) -> float:
	if not _owned(): return 0.0
	if not _actors.is_runtime_present(actor):
		return 0.0
	for property: Dictionary in actor.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(actor.get("combat_radius_gu")))
	return WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
		ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)


func _skill_snapshot_intersects_enemy(
	skill_release_snapshot: Dictionary,
	enemy: Object
) -> bool:
	if not _owned(): return false
	return (
		_actors.is_runtime_present(enemy)
		and _snapshot_strict_ok(skill_release_snapshot)
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_release_snapshot,
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
			enemy.combat_radius_gu
		)
	)


func _canonical_effective_spell_geometry_cells(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	definition: Dictionary = {}
) -> Array[Vector2i]:
	if not _owned(): return []
	if definition.is_empty():
		definition = SkillDataLoaderScript.skill(stable_skill_id)
	var geometry: Dictionary = definition.get("geometry", {}).duplicate(true)
	if effect.has("stops_on_terrain"):
		geometry["stops_on_terrain"] = bool(effect.stops_on_terrain)
	return CasterSpellGeometryScript.effective_cells(
		stable_skill_id,
		geometry,
		raw_geometry_cells,
		Callable(self, "_canonical_spell_cell_is_terrain_blocked")
	)


func _is_supported_continuous_line_contract(
	contract_id: String
) -> bool:
	if not _owned(): return false
	return contract_id in [
		CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID,
		CONTINUOUS_AIM_LINE_CONTRACT_ID_LEGACY
	]


func _canonical_continuous_line_strip_ground_gu(
	stable_skill_id: String,
	effect: Dictionary,
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	release_id = "",
	definition: Dictionary = {}
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	if (
		stable_skill_id not in CONTINUOUS_WIZARD_LINE_SKILLS
		or not _is_supported_continuous_line_contract(
			str(effect.get("line_geometry_contract", ""))
		)
	):
		return {}
	if definition.is_empty():
		definition = SkillDataLoaderScript.skill(stable_skill_id)
	var geometry: Dictionary = definition.get("geometry", {})
	var effect_length_gu = maxf(
		0.0,
		float(effect.get("effect_length_gu", geometry.get("effect_length_gu", 0.0)))
	)
	var effect_width_gu = maxf(
		0.0001,
		float(effect.get("effect_width_gu", geometry.get("effect_width_gu", 1.0)))
	)
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	var resolved_effect_length_gu = effect_length_gu
	if stable_skill_id == "wizard.laser" and bool(effect.get("stops_on_terrain", geometry.get("stops_on_terrain", false))):
		resolved_effect_length_gu = CasterSpellGeometryScript.resolve_laser_effect_length_gu(
			direction_ground_gu,
			effect_length_gu
		)
	var final_effect_length_gu = resolved_effect_length_gu
	var laser_projection_policy = ""
	if stable_skill_id == "wizard.laser":
		laser_projection_policy = "screen_length_limit_diagonal_reference_v1"
	var resolved_release_id = str(release_id)
	if resolved_release_id.is_empty():
		resolved_release_id = _next_skill_footprint_release_id(stable_skill_id)
	var line_coordinate_context = _canonical_snapshot_absolute_context(
		origin_ground_gu
	)
	var strip_ground_gu = CasterSpellGeometryScript.continuous_line_strip_ground_gu(
		origin_ground_gu,
		origin_ground_gu + direction_ground_gu,
		direction_screen_px,
		resolved_effect_length_gu,
		effect_width_gu,
		stable_skill_id,
		resolved_release_id,
		effect_length_gu,
		resolved_effect_length_gu,
		laser_projection_policy,
		line_coordinate_context
	)
	if bool(effect.get("stops_on_terrain", geometry.get("stops_on_terrain", false))):
		var unblocked_length_gu = _canonical_continuous_line_unblocked_length_gu(
			strip_ground_gu
		)
		if unblocked_length_gu < resolved_effect_length_gu:
			final_effect_length_gu = unblocked_length_gu
			strip_ground_gu = CasterSpellGeometryScript.continuous_line_strip_ground_gu(
				origin_ground_gu,
				origin_ground_gu + direction_ground_gu,
				direction_screen_px,
				final_effect_length_gu,
				effect_width_gu,
				stable_skill_id,
				resolved_release_id,
				effect_length_gu,
				final_effect_length_gu,
				laser_projection_policy,
				line_coordinate_context
			)
			strip_ground_gu["terrain_truncated"] = true
			strip_ground_gu["source_effect_length_gu"] = resolved_effect_length_gu
	if stable_skill_id == "wizard.laser":
		strip_ground_gu["declared_effect_length_gu"] = effect_length_gu
		strip_ground_gu["resolved_effect_length_gu"] = final_effect_length_gu
		strip_ground_gu["laser_projection_policy"] = laser_projection_policy
		var line_snapshot: Variant = strip_ground_gu.get(
			"skill_footprint_snapshot", {}
		)
		if line_snapshot is Dictionary:
			var snap = (line_snapshot as Dictionary).duplicate(true)
			snap["declared_effect_length_gu"] = effect_length_gu
			snap["resolved_effect_length_gu"] = final_effect_length_gu
			snap["laser_projection_policy"] = laser_projection_policy
			snap.make_read_only()
			strip_ground_gu["skill_footprint_snapshot"] = snap
	strip_ground_gu["integration_contract_id"] = (
		"gameplay.wizard.continuous_line.damage_visual_terrain_shared.v1"
	)
	return strip_ground_gu


func _canonical_continuous_line_unblocked_length_gu(
	line_strip_ground_gu: Dictionary
) -> float:
	if not _owned(): return 0.0
	var effect_length_gu = maxf(
		0.0,
		float(line_strip_ground_gu.get("effect_length_gu", 0.0))
	)
	if effect_length_gu <= 0.0:
		return 0.0
	var origin_ground_gu: Vector2 = line_strip_ground_gu.get(
		"origin_ground_gu", Vector2.ZERO
	)
	var direction_ground_gu: Vector2 = line_strip_ground_gu.get(
		"direction_ground_gu", Vector2.DOWN
	)
	# Quarter-step centreline sampling is a deterministic supercover for the
	# continuous ray. It catches cells crossed between integer sample points,
	# while the damage width remains independent from terrain traversal.
	const SAMPLE_STEP_GU = 0.25
	var sample_count = ceili(effect_length_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu = 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu = minf(
			float(sample_index) * SAMPLE_STEP_GU,
			effect_length_gu
		)
		var sample_ground_gu = (
			origin_ground_gu + direction_ground_gu * distance_gu
		)
		var sample_cell = Vector2i(
			roundi(sample_ground_gu.x),
			roundi(sample_ground_gu.y)
		)
		if _canonical_spell_cell_is_terrain_blocked(sample_cell):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _canonical_spell_cell_is_terrain_blocked(cell: Vector2i) -> bool:
	if not _owned(): return false
	var runtime = _geometry.map_data.load_map(current_map_id)
	if not runtime.is_empty():
		return runtime.get("collision", {}).get("blocked_tiles", []).has(
			"%d,%d" % [cell.x, cell.y]
		)
	return (
		_geometry.is_present()
		and _geometry.has_method("is_environment_point_blocked")
		and bool(_geometry.call(
			"is_environment_point_blocked",
			_canonical_grid_cell_to_screen_px(cell)
		))
	)


func _aoe_collect_continuous_line_candidates(
	plan: Dictionary,
	line_strip: Dictionary,
	candidates: Array,
	targets: Array,
	distances: Array[float],
	ids: Array[int],
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
) -> void:
	if not _owned(): return
	for enemy: Object in candidates:
		if (
			not _actors.is_runtime_present(enemy)
			or _actors.is_queued_for_retirement(enemy)
			or enemy.current_hp <= 0
		):
			continue
		_diagnostics.increment_performance_counter(
			&"aoe_exact_intersection_tests"
		)
		var intersects = (
			_aoe_validated_snapshot_intersects(plan, enemy)
			if _aoe_plan_is_ready(plan)
			else CasterSpellGeometryScript.target_footprint_intersects_continuous_line_ground_gu(
				line_strip,
				_enemy_footprint_polygon_ground_gu(enemy),
			)
		)
		if not intersects:
			continue
		var enemy_ground_gu = _canonical_screen_px_to_ground_gu(
			_actors.position_screen_px(enemy)
		)
		if not enemy_ground_gu.is_finite():
			continue
		_aoe_insert_by_distance(
			targets,
			distances,
			ids,
			enemy,
			(enemy_ground_gu - origin_ground_gu).dot(direction_ground_gu),
		)


func _canonical_spell_geometry_targets(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	continuous_line_strip_ground_gu: Dictionary = {},
	skill_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array:
	if not _owned(): return []
	var geometry_cells: Array[Vector2i] = []
	if raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				geometry_cells.append(raw_cell)
	var targets: Array = []
	var release_cache: Dictionary = {}
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_spell_query_plan(
			stable_skill_id,
			geometry_cells,
			effect,
			continuous_line_strip_ground_gu,
			skill_release_snapshot,
			_canonical_screen_px_to_ground_gu(
				_actors.position_screen_px(player) if _actors.is_runtime_present(player) else Vector2.ZERO
			),
			release_cache,
		)
		if not _aoe_spell_snapshot(
			skill_release_snapshot,
			continuous_line_strip_ground_gu,
		).is_empty():
			_diagnostics.increment_performance_counter(&"aoe_release_count")
	var broadphase_ready = _aoe_plan_is_ready(plan)
	if not broadphase_ready and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"aoe_query_plan_invalid_or_spatial_index_unavailable"
		)
		return targets
	# Hellfire is a five-tile, one-tile-wide area line. `pierces_units` controls
	# whether units stop the visual/line traversal; it must not turn the area
	# damage into a single-target spell. A negative limit means every hostile
	# footprint intersecting the formal geometry is selected.
	# Both canonical line spells affect every intersecting monster. Limiting the
	# result to the nominal number of cells makes stacked or large-footprint
	# monsters visually intersect the line without receiving damage.
	var maximum_targets = int(effect.get("maximum_targets", -1))
	var selects_all_intersecting_effect_cells = (
		stable_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		and str(effect.get("target_limit_policy", ""))
		== "all_intersecting_effect_cells"
	)
	if selects_all_intersecting_effect_cells:
		maximum_targets = -1
	elif maximum_targets == 0:
		return targets
	if (
		stable_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		and str(continuous_line_strip_ground_gu.get("contract_id", ""))
		in [
			CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID,
			CONTINUOUS_AIM_LINE_CONTRACT_ID_LEGACY
		]
	):
		var origin_ground_gu: Vector2 = continuous_line_strip_ground_gu.get(
			"origin_ground_gu", plan.get("line_origin_ground_gu", Vector2.ZERO)
		)
		var direction_ground_gu: Vector2 = continuous_line_strip_ground_gu.get(
			"direction_ground_gu", plan.get("line_direction_ground_gu", Vector2.DOWN)
		)
		var line_end_ground_gu: Vector2 = continuous_line_strip_ground_gu.get(
			"strip_end_ground_gu",
			origin_ground_gu + direction_ground_gu * float(
				continuous_line_strip_ground_gu.get("effect_length_gu", 0.0)
			),
		)
		var line_width_gu = maxf(
			0.0,
			float(continuous_line_strip_ground_gu.get("effect_width_gu", 0.0)) * 0.5,
		)
		if not _aoe_query_enemy_candidates_segment(
			plan,
			origin_ground_gu,
			line_end_ground_gu,
			line_width_gu,
		):
			return targets
		var distances: Array[float] = []
		var ids: Array[int] = []
		_aoe_collect_continuous_line_candidates(
			plan,
			continuous_line_strip_ground_gu,
			_aoe_candidate_scratch,
			targets,
			distances,
			ids,
			origin_ground_gu,
			direction_ground_gu,
		)
		if targets.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			_aoe_collect_continuous_line_candidates(
				plan,
				continuous_line_strip_ground_gu,
				_aoe_candidate_scratch,
				targets,
				distances,
				ids,
				origin_ground_gu,
				direction_ground_gu,
			)
		if maximum_targets > 0 and targets.size() > maximum_targets:
			targets.resize(maximum_targets)
		return targets
	if broadphase_ready and str(plan.get("shape_type", "")) == SkillFootprintSnapshotScript.SHAPE_CELL_UNION:
		_aoe_query_enemy_candidates_aabb(
			plan,
			plan.get("ground_aabb", Rect2()),
			false,
		)
		var target_ids: Array[int] = []
		for enemy: Object in _aoe_candidate_scratch:
			_diagnostics.increment_performance_counter(
				&"aoe_exact_intersection_tests"
			)
			if _aoe_validated_snapshot_intersects(plan, enemy):
				_aoe_insert_by_instance_id(targets, target_ids, enemy)
		if targets.is_empty() and _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			for enemy: Object in _aoe_candidate_scratch:
				_diagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _aoe_validated_snapshot_intersects(plan, enemy):
					_aoe_insert_by_instance_id(targets, target_ids, enemy)
		if maximum_targets > 0 and targets.size() > maximum_targets:
			targets.resize(maximum_targets)
		return targets
	var query_bounds: Rect2 = (
		plan.get("ground_aabb", Rect2()) as Rect2
		if broadphase_ready
		else _aoe_geometry_cells_aabb(geometry_cells)
	)
	if not _aoe_query_enemy_candidates_aabb(plan, query_bounds):
		return targets
	var selected_instance_ids: Array[int] = []
	var cells_to_visit: Array[Vector2i] = geometry_cells
	if broadphase_ready:
		var raw_cells_to_visit: Variant = plan.get(
			"cell_sequence", geometry_cells
		)
		if raw_cells_to_visit is Array:
			cells_to_visit.clear()
			for raw_cell: Variant in raw_cells_to_visit as Array:
				if raw_cell is Vector2i:
					cells_to_visit.append(raw_cell)
		if cells_to_visit.is_empty():
			cells_to_visit = geometry_cells
	for cell: Vector2i in cells_to_visit:
		_diagnostics.increment_performance_counter(&"aoe_nested_cell_enemy_scans")
		var cell_targets: Array = []
		var cell_target_ids: Array[int] = []
		for enemy: Object in _aoe_candidate_scratch:
			if selected_instance_ids.has(_actors.runtime_actor_id(enemy)):
				continue
			_diagnostics.increment_performance_counter(
				&"aoe_exact_intersection_tests"
			)
			var contact = CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
				[cell],
				_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
				enemy.combat_radius_gu
			)
			if bool(contact.get("intersects", false)):
				_aoe_insert_by_instance_id(cell_targets, cell_target_ids, enemy)
		for enemy: Object in cell_targets:
			targets.append(enemy)
			selected_instance_ids.append(_actors.runtime_actor_id(enemy))
			if maximum_targets > 0 and targets.size() >= maximum_targets:
				return targets
	if targets.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		selected_instance_ids.clear()
		targets.clear()
		for cell: Vector2i in cells_to_visit:
			var cell_targets: Array = []
			var cell_target_ids: Array[int] = []
			for enemy: Object in _aoe_candidate_scratch:
				if selected_instance_ids.has(_actors.runtime_actor_id(enemy)):
					continue
				var contact = CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
					[cell],
					_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
					enemy.combat_radius_gu
				)
				if bool(contact.get("intersects", false)):
					_aoe_insert_by_instance_id(cell_targets, cell_target_ids, enemy)
			for enemy: Object in cell_targets:
				targets.append(enemy)
				selected_instance_ids.append(_actors.runtime_actor_id(enemy))
				if maximum_targets > 0 and targets.size() >= maximum_targets:
					return targets
	return targets


func _enemy_footprint_polygon_ground_gu(enemy: Object) -> PackedVector2Array:
	if not _owned(): return PackedVector2Array()
	if not _actors.is_runtime_present(enemy):
		return PackedVector2Array()
	return CasterSpellGeometryScript.actor_footprint_polygon_ground_gu(
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
		enemy.combat_radius_gu
	)


func _ground_circle_intersects_enemy_footprint_gu(
	center_screen_px: Vector2,
	radius_gu: float,
	enemy: Object
) -> bool:
	if not _owned(): return false
	if not _actors.is_runtime_present(enemy):
		return false
	var center_ground_gu = _canonical_screen_px_to_ground_gu(center_screen_px)
	var enemy_center_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(enemy)
	)
	var enemy_radius_gu = enemy.combat_radius_gu
	return GroundUnitSpaceScript.is_within_range_gu(
		center_ground_gu,
		enemy_center_ground_gu,
		maxf(0.0, radius_gu) + enemy_radius_gu
	)


func _spawn_canonical_ground_field(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	fallback_position: Vector2,
	effect: Dictionary,
	release_id = "",
	skill_release_snapshot: Dictionary = {}
) -> Array:
	if not _owned(): return []
	var positions: Array[Vector2] = []
	var coverage_cells: Array[Vector2i] = []
	if raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				positions.append(_canonical_grid_cell_to_screen_px(raw_cell))
				coverage_cells.append(raw_cell)
	if positions.is_empty():
		positions.append(fallback_position)

	if stable_skill_id == FIRE_WALL_SKILL_ID:
		# AOE window probe: fire wall field spawn milestone. Diagnostics only.
		_engagement.on_field_spawned(stable_skill_id)
		var field_snapshot_validation_context = (
			_canonical_snapshot_validation_context(
				_canonical_screen_px_to_ground_gu(fallback_position)
			)
		)
		# Q2-C: the formal release owns exactly ONE canonical 3x3 union
		# snapshot. Legacy/test callers that omit one get a deterministic
		# fallback built from the same coverage cells, so the controller never
		# needs per-cell damage geometry.
		var canonical_snapshot = skill_release_snapshot
		if not _snapshot_strict_ok(canonical_snapshot):
			var canonical_origin_ground_gu = Vector2.ZERO
			if not positions.is_empty():
				canonical_origin_ground_gu = (
					_canonical_screen_px_to_ground_gu(positions[0])
				)
			var fallback_release_id = (
				release_id
				if not release_id.is_empty()
				else "wizard.fire_wall:canonical:%d" % _clock.now_usec()
			)
			# The union's geometry_cells_grid_steps are ABSOLUTE grid cells
			# (same convention as the formal release snapshot producer).
			var canonical_cells = coverage_cells
			if canonical_cells.is_empty():
				canonical_cells.append(Vector2i.ZERO)
			canonical_snapshot = (
				CasterSpellGeometryScript.create_exact_cell_union_release_snapshot(
					stable_skill_id,
					fallback_release_id,
					canonical_origin_ground_gu,
					canonical_cells,
					field_snapshot_validation_context
				)
			)
		var empty_target_filters: Array[Callable] = []
		# SOT wizard.fire_wall mechanics (mir2_176_skills_source_of_truth_v1,
		# project_canonical): "same_caster_same_tile_refreshes_duration" with
		# "max_active_fields_per_caster": "config_required_default_8".
		# R2 ruling (user device ruling 2026-09-15, GPT audit adoption): the
		# ninth-field behavior is now recorded in the SOT mechanics as
		# "cap_policy": "evict_oldest" — casting must always succeed and the
		# oldest field is cancelled when the cap is reached. The runtime
		# keeps fail-closed to reject_new ONLY for unconfigured data. The
		# registry key is source-aware: caster/map/generation/family/tile,
		# so two casters on one tile own separate fields instead of
		# cross-refreshing each other.
		var registry_center = _fire_wall_registry_center_cell(coverage_cells)
		var registry_usable = not coverage_cells.is_empty()
		var registry_key = ""
		if registry_usable:
			registry_key = _fire_wall_registry_key(
				player, stable_skill_id, registry_center
			)
			_fire_wall_prune_invalid_registry_entries()
			var existing_field: Variant = _fire_wall_field_registry.lookup(
				registry_key
			)
			if _fire_wall_registry_controller_is_active(existing_field):
				existing_field.refresh_field(
					effect,
					canonical_snapshot,
					field_snapshot_validation_context,
					release_id
				)
				return [existing_field]
			if not _fire_wall_cap_allows_new_field(
				effect, player, stable_skill_id
			):
				return []
		var field_controller = _casting.create_fire_wall_model()
		field_controller.setup_fire_wall_field(
			player,
			stable_skill_id,
			effect,
			positions,
			coverage_cells,
			empty_target_filters,
			Callable(self, "_apply_canonical_ground_tick").bind(stable_skill_id),
			Callable(self, "_canonical_screen_px_to_ground_gu"),
			release_id,
			canonical_snapshot,
			field_snapshot_validation_context,
			_spatial,
			current_map_id
		)
		_world.register_cast_model(field_controller)
		if registry_usable:
			_fire_wall_field_registry.store(registry_key, field_controller)
			_fire_wall_field_order.append(registry_key)
			# R2-2: the controller releases its registry slot the moment it
			# leaves the tree (expiry/cancel/map teardown) instead of
			# waiting for the next cast's lazy prune.
			_casting.bind_field_retirement(field_controller, 
				_on_fire_wall_field_tree_exited.bind(
					registry_key, field_controller
				)
			)
			_debug_validate_fire_wall_registry("cast_insert")
		# Q2-C: the controller owns the GroundSkillVisualCell presentation
		# nodes (3x3 geometry => 9 cells today); no additional standalone
		# Object cells are spawned, so the base-class enemy-group
		# scan can never run on this path.
		return [field_controller]

	# Generic persistent ground effects share one canonical validation context
	# so the manager can run STRICT_V2 snapshot validation per tick.
	var generic_snapshot_validation_context = (
		_canonical_snapshot_validation_context(
			_canonical_screen_px_to_ground_gu(fallback_position)
		)
	)
	var spawned_effects: Array = []
	for index: int in range(positions.size()):
		spawned_effects.append(_spawn_canonical_ground_effect(
			stable_skill_id,
			positions[index],
			effect,
			true,
			coverage_cells[index] if index < coverage_cells.size() else null,
			release_id,
			skill_release_snapshot,
			generic_snapshot_validation_context
		))
	return spawned_effects


func _fire_wall_registry_controller_is_active(controller: Variant) -> bool:
	if not _owned(): return false
	## R2-6 (GPT audit adoption): CAST_ACTIVE = structural validity plus not
	## queued for deletion. A queued controller is mid-release (expiry or
	## cancel already ran; Godot frees it at frame end): refreshing it could
	## not save it, and keeping it registered would swallow a same-tile
	## recast for one frame. Prune and the same-tile refresh gate share this
	## helper so both treat the window identically.
	return (
		_actors.is_kind(controller, &"fire_wall")
		and _actors.is_runtime_present(controller)
		and not controller._world.is_queued_for_retirement()
	)


func _fire_wall_registry_center_cell(coverage_cells: Array[Vector2i]) -> Vector2i:
	if not _owned(): return Vector2i.ZERO
	## The registry center is the selected center tile of the field footprint.
	## Coverage cells are absolute grid steps, so two casts on the same tile
	## produce the same centered 3x3 cell set and therefore the same key.
	if coverage_cells.is_empty():
		return Vector2i.ZERO
	var minimum = Vector2i(2147483647, 2147483647)
	var maximum = Vector2i(-2147483648, -2147483648)
	for cell: Vector2i in coverage_cells:
		minimum = Vector2i(mini(minimum.x, cell.x), mini(minimum.y, cell.y))
		maximum = Vector2i(maxi(maximum.x, cell.x), maxi(maximum.y, cell.y))
	var center = Vector2(minimum + maximum) * 0.5
	return Vector2i(roundi(center.x), roundi(center.y))


func _fire_wall_registry_key(
	caster: Object,
	family: String,
	registry_center: Vector2i
) -> String:
	if not _owned(): return ""
	return "%d|%d|%d|%s|%d_%d" % [
		current_map_id,
		_zone_generation,
		_actors.runtime_actor_id(caster) if _actors.is_runtime_present(caster) else 0,
		family,
		registry_center.x,
		registry_center.y,
	]


func _fire_wall_registry_caster_prefix(caster: Object) -> String:
	if not _owned(): return ""
	return "%d|%d|%d|" % [
		current_map_id,
		_zone_generation,
		_actors.runtime_actor_id(caster) if _actors.is_runtime_present(caster) else 0,
	]


func _fire_wall_max_active_fields(effect: Dictionary) -> int:
	if not _owned(): return 0
	var raw = str(effect.get("max_active_fields_per_caster", ""))
	if raw.begins_with("config_required_default_"):
		var suffix = raw.trim_prefix("config_required_default_")
		if suffix.is_valid_int():
			return maxi(1, int(suffix))
	if raw.is_valid_int():
		return maxi(1, int(raw))
	return FIRE_WALL_MAX_ACTIVE_FIELDS_PER_CASTER


func _fire_wall_cap_policy(effect: Dictionary) -> String:
	if not _owned(): return ""
	var raw = str(effect.get("cap_policy", "")).strip_edges().to_lower()
	if raw == FIRE_WALL_CAP_POLICY_EVICT_OLDEST:
		return FIRE_WALL_CAP_POLICY_EVICT_OLDEST
	return FIRE_WALL_CAP_POLICY_REJECT_NEW


func _fire_wall_cap_allows_new_field(
	effect: Dictionary,
	caster: Object,
	_family: String
) -> bool:
	if not _owned(): return false
	## Per-caster cap check: "max_active_fields_per_caster" counts the
	## fields of THIS caster only, not the whole registry.
	var max_fields = _fire_wall_max_active_fields(effect)
	var caster_prefix = _fire_wall_registry_caster_prefix(caster)
	var caster_fields = 0
	for key: Variant in _fire_wall_field_order:
		if str(key).begins_with(caster_prefix):
			caster_fields += 1
	if caster_fields < max_fields:
		return true
	if _fire_wall_cap_policy(effect) == FIRE_WALL_CAP_POLICY_EVICT_OLDEST:
		_fire_wall_evict_oldest_field_for_caster(caster_prefix)
		return true
	_diagnostics.increment_performance_counter(
		&"fire_wall_cap_reject_new"
	)
	return false


func _fire_wall_prune_invalid_registry_entries() -> void:
	if not _owned(): return
	var stale_keys: Array = []
	for key: Variant in _fire_wall_field_registry.keys():
		var controller: Variant = _fire_wall_field_registry.lookup(key)
		# R2-6: CAST_ACTIVE check — a queued-for-deletion controller is
		# stale NOW, so a same-tile recast inside the expiry frame creates
		# a fresh field instead of refreshing a dying one.
		if not _fire_wall_registry_controller_is_active(controller):
			stale_keys.append(key)
	for key: Variant in stale_keys:
		_fire_wall_field_registry.erase(key)
		_fire_wall_field_order.erase(key)
	if not stale_keys.is_empty():
		_debug_validate_fire_wall_registry("prune")


func _on_fire_wall_field_tree_exited(
	registry_key: String,
	controller: Object
) -> void:
	if not _owned(): return
	## R2-2: proactive registry release when a field controller leaves the
	## tree. The identity guard keeps a stale signal from evicting a newer
	## field that was registered under the same key (same-tile recast).
	if _fire_wall_field_registry.lookup(registry_key) == controller:
		_fire_wall_field_registry.erase(registry_key)
		_fire_wall_field_order.erase(registry_key)
	_debug_validate_fire_wall_registry("tree_exited")


func _debug_validate_fire_wall_registry(context = "") -> void:
	if not _owned(): return
	## R2-5 (GPT audit adoption): debug-only STRUCTURAL invariant, executed
	## at lifecycle boundaries (cast insert, eviction, expiry release, prune,
	## map teardown): registry keys and order slots must stay 1:1 and every
	## entry must reference a valid controller. STRUCTURAL_VALID means type
	## correct + instance still valid — a queued-for-deletion entry is
	## accepted as mid-release because its own tree_exited hook drops the
	## slot within the same frame. CAST_ACTIVE (also !is_queued_for_deletion)
	## is the separate production gate in
	## _fire_wall_registry_controller_is_active(). Never runs per frame.
	if (
		not OS.is_debug_build()
		or not _fire_wall_registry_validation_enabled
	):
		return
	assert(
		_fire_wall_field_registry.size() == _fire_wall_field_order.size(),
		"fire wall registry/order size mismatch (%s): %d vs %d" % [
			context,
			_fire_wall_field_registry.size(),
			_fire_wall_field_order.size(),
		]
	)
	var order_keys = {}
	for key: Variant in _fire_wall_field_order:
		assert(
			not order_keys.has(key),
			"fire wall order duplicates key %s (%s)" % [str(key), context]
		)
		order_keys[key] = true
		assert(
			_fire_wall_field_registry.has(key),
			"fire wall order key %s missing from registry (%s)"
			% [str(key), context]
		)
	for key: Variant in _fire_wall_field_registry:
		var entry: Variant = _fire_wall_field_registry.lookup(key)
		# A queued-for-deletion controller is mid-release: its own
		# tree_exited hook drops the registry slot within the same frame
		# (expiry/cancel window), so queued entries are still consistent.
		assert(
			_actors.is_kind(entry, &"fire_wall")
			and _actors.is_runtime_present(entry),
			"fire wall registry entry %s must reference a structurally valid controller (%s)"
			% [str(key), context]
		)
		assert(
			order_keys.has(key),
			"fire wall registry key %s missing from order (%s)"
			% [str(key), context]
		)


func _fire_wall_evict_oldest_field_for_caster(caster_prefix: String) -> void:
	if not _owned(): return
	for key: Variant in _fire_wall_field_order:
		if not str(key).begins_with(caster_prefix):
			continue
		var controller: Variant = _fire_wall_field_registry.lookup(key)
		if _actors.is_runtime_present(controller):
			controller.cancel()
		_fire_wall_field_registry.erase(key)
		_fire_wall_field_order.erase(key)
		_debug_validate_fire_wall_registry("evict_oldest")
		return


func _clear_fire_wall_field_registry() -> void:
	if not _owned(): return
	for key: Variant in _fire_wall_field_registry.keys():
		var controller: Variant = _fire_wall_field_registry.lookup(key)
		if _actors.is_runtime_present(controller):
			controller.cancel()
	_fire_wall_field_registry.clear()
	_fire_wall_field_order.clear()
	_debug_validate_fire_wall_registry("clear")


func _spawn_canonical_ground_effect(
	stable_skill_id: String,
	position: Vector2,
	effect: Dictionary,
	applies_damage = true,
	coverage_cell: Variant = null,
	release_id = "",
	skill_release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {}
) -> Object:
	if not _owned(): return null
	var ground_effect = _casting.create_ground_model()
	ground_effect.setup_ground_unit_effect(
		position,
		maxi(0, int(effect.get("raw_power", 0))),
		maxf(0.0, float(effect.get("radius_gu", 0.5))),
		maxf(0.1, float(effect.get("duration_seconds", 1))),
		Color(0.45, 0.72, 1.0),
		stable_skill_id,
		maxf(0.05, float(effect.get("tick_interval_ms", 1000)) / 1000.0),
		74.0,
		release_id,
		skill_release_snapshot,
		snapshot_validation_context
	)
	ground_effect.configure_runtime_resolution(
		player,
		(
			Callable(self, "_apply_canonical_ground_tick").bind(stable_skill_id)
			if applies_damage
			else Callable(self, "_ignore_canonical_ground_visual_tick")
		),
		applies_damage,
		(
			Callable(self, "_ground_field_snapshot_contains_enemy").bind(
				skill_release_snapshot
			)
			if _snapshot_strict_ok(skill_release_snapshot)
			else (
				Callable(self, "_canonical_ground_cell_contains_enemy").bind(
					coverage_cell
				)
				if coverage_cell is Vector2i
				else Callable()
			)
		),
		Callable(self, "_canonical_screen_px_to_ground_gu")
	)
	# R1-B: give the self-managed tick the shared spatial candidate authority
	# (the manager-owned path ignores it; the legacy group scan stays closed).
	ground_effect.set_combat_spatial_context(
		_spatial, current_map_id
	)
	_world.register_cast_model(ground_effect)
	if applies_damage:
		_register_manager_ground_effect(
			ground_effect,
			stable_skill_id,
			release_id,
			skill_release_snapshot,
			snapshot_validation_context
		)
	return ground_effect


func _register_manager_ground_effect(
	ground_effect: Object,
	stable_skill_id: String,
	release_id: String,
	skill_release_snapshot: Dictionary,
	snapshot_validation_context: Dictionary
) -> void:
	if not _owned(): return
	## Q2-B: the generic damage-bearing ground effect is scheduled by the
	## manager. The node keeps visuals/lifecycle only; the old per-effect
	## enemy-group scan must never run again for this node.
	ground_effect.manager_owned_damage_ticks = true
	if _ground_effect_manager == null:
		ground_effect.runtime_damage_enabled = false
		return
	_ground_effect_runtime_serial += 1
	var effect_runtime_id = _ground_effect_runtime_serial
	var runtime_map_id = int(
		skill_release_snapshot.get("runtime_map_id", current_map_id)
	)
	var registered = _ground_effect_manager.register({
		"effect_runtime_id": effect_runtime_id,
		"skill_id": stable_skill_id,
		"release_id": release_id,
		"snapshot_id": str(
			skill_release_snapshot.get("snapshot_id", release_id)
		),
		"runtime_map_id": runtime_map_id,
		"caster_reference": player,
		"canonical_snapshot": skill_release_snapshot,
		"expected_context": (
			snapshot_validation_context
			if snapshot_validation_context is Dictionary
			else {}
		),
		"tick_interval_s": ground_effect.tick_interval,
		"expiration_s": ground_effect.duration,
		"stacking_policy": "per_effect_independent",
		"claim_policy": "effect_claim_only",
		"damage_callback": (
			Callable(self, "_apply_canonical_ground_tick").bind(
				stable_skill_id
			)
		),
		"lifecycle_callback": (
			Callable(self, "_manager_ground_effect_ended")
		),
		"manager_owned_damage_ticks": true,
		"effect": ground_effect,
	})
	if not registered:
		# Missing strict V2 snapshot or unavailable manager: never fall back to
		# the legacy group scan; the visual node stays but damage is refused.
		ground_effect.runtime_damage_enabled = false


func _canonical_ground_cell_contains_enemy(
	enemy: Object,
	coverage_cell: Vector2i
) -> bool:
	if not _owned(): return false
	return (
		_actors.is_runtime_present(enemy)
		and bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
			[coverage_cell],
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
			enemy.combat_radius_gu
		).get("intersects", false))
	)


func _ground_field_snapshot_contains_enemy(
	enemy: Object,
	skill_release_snapshot: Dictionary
) -> bool:
	if not _owned(): return false
	if (
		not _actors.is_runtime_present(enemy)
		or not _snapshot_strict_ok(skill_release_snapshot)
	):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		skill_release_snapshot,
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
		enemy.combat_radius_gu
	)


func _ignore_canonical_ground_visual_tick(
	_enemy: Object,
	_raw_power: int
) -> void:
	if not _owned(): return
	pass


func _apply_canonical_ground_tick(enemy: Object, raw_power: int, stable_skill_id: String) -> void:
	if not _owned(): return
	# AOE window probe: first canonical ground damage tick after the first
	# fire wall cast. Diagnostics only, one write while the window is active.
	_engagement.on_ground_damage_tick(stable_skill_id)
	# R1: ground-effect ticks are the RM_MAGSTRUCK_MINE family (the vanilla
	# TFireBurnEvent.Run sends RM_MAGSTRUCK_MINE, never RM_MAGSTRUCK). They
	# keep normal MAC/damage, but never insert STRUCK or pause action/movement.
	# Every ground tick settles the area's current targets once.
	_combat.apply_enemy_direct_spell_damage(
		enemy,
		stable_skill_id,
		raw_power,
		player,
		_random,
		Callable(self, "_resolve_magic_defense"),
		-1,
		_direct_spell_target_stats_scratch,
		_combat.EnemyMagicDeliveryKind.MAGSTRUCK_MINE,
	)


func _apply_canonical_displacement_screen_px(
	actor: Object,
	displacement_screen_px: Vector2
) -> bool:
	if not _owned(): return false
	if not _actors.is_runtime_present(actor):
		return false
	var destination_screen_px = _actors.position_screen_px(actor) + displacement_screen_px
	var collision_radius_px: float = (
		actor.collision_radius_px
		if _actors.is_kind(actor, &"enemy")
		else ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)
	if _geometry.environment_blocks_actor_screen_px(
		_geometry,
		destination_screen_px,
		collision_radius_px
	):
		return false
	if _actors.is_kind(actor, &"enemy"):
		actor.set_combat_position(
			destination_screen_px,
			&"canonical_displacement",
		)
	else:
		_actors.set_position_screen_px(actor, destination_screen_px)
	return true


func _apply_canonical_player_teleport(destination: Vector2) -> bool:
	if not _owned(): return false
	if not destination.is_finite() or _geometry.environment_blocks_actor_screen_px(_geometry, destination, ArtSpec.PLAYER_COLLISION_RADIUS_PX):
		return false
	_world.set_player_world_position(destination)
	_actors.stop_velocity(player)
	_relocate_main_pets_after_map_arrival()
	player.movement_performed.emit(_actors.position_screen_px(player), player.facing)
	return true


func _apply_canonical_poison(target: Object, effect: Dictionary) -> void:
	if not _owned(): return
	var now_ms = _clock.now_msec()
	var duration = float(effect.get("duration_seconds", 1))
	if str(effect.get("poison_type", "")) == "green_poison":
		target.apply_poison(
			int(effect.get("damage_per_tick", 1)),
			duration,
			float(effect.get("tick_interval_ms", 1000)) / 1000.0
		)
	else:
		var previous: Variant = _actors.read_meta(target, "canonical_red_poison", {})
		var previous_active: Dictionary = (
			(previous as Dictionary).duplicate(true)
			if previous is Dictionary and int((previous as Dictionary).get("expires_at_ms", 0)) > now_ms
			else {}
		)
		# An expired red poison contributes no AC/MAC, durability, or duration.
		# Keep the current cast as the sole new owner, while preserving the
		# existing max-refresh contract for an active red poison.
		var merged = previous_active.duplicate(true)
		for key: Variant in effect:
			if not merged.has(key):
				merged[key] = effect[key]
		var flat_ac = maxi(
			int(merged.get("flat_ac_reduction", 0)),
			int(effect.get("flat_ac_reduction", 0))
		)
		var flat_mac = maxi(
			int(merged.get("flat_mac_reduction", 0)),
			int(effect.get("flat_mac_reduction", 0))
		)
		var extra_durability = maxi(
			int(merged.get("extra_durability_loss_per_hit", 0)),
			int(effect.get("extra_durability_loss_per_hit", 0))
		)
		merged["contract_id"] = "buff.taoist.red_poison.v1"
		merged["poison_type"] = "red_poison"
		merged["flat_ac_reduction"] = flat_ac
		merged["flat_mac_reduction"] = flat_mac
		merged["flat_reduction"] = maxi(flat_ac, flat_mac)
		merged["extra_durability_loss_per_hit"] = extra_durability
		merged["duration_seconds"] = maxf(
			float(merged.get("duration_seconds", 0.0)),
			duration
		)
		merged["expires_at_ms"] = maxi(
			int(merged.get("expires_at_ms", 0)),
			now_ms + roundi(duration * 1000.0)
		)
		_actors.write_meta(target, "canonical_red_poison", merged)
		_diagnostics.increment_performance_counter(&"actor_redraw_requests")
		_presentation.redraw_cast(target)


func _apply_canonical_temptation(target: Object, effect: Dictionary) -> void:
	if not _owned(): return
	match str(effect.get("outcome", "no_effect")):
		"rooted":
			target.apply_control(float(effect.get("duration_seconds", 1)))
		"confused", "tamed":
			target.apply_charm(float(effect.get("duration_seconds", float(effect.get("loyalty_duration_ms", 1000)) / 1000.0)))
		"instant_kill":
			_combat.apply_enemy_physical_damage(target, target.current_hp, player)


func _synchronize_main_pet_skill_ranks() -> void:
	if not _owned(): return
	for summon_id: String in ["skeleton", "divine_beast"]:
		for summon: Object in _canonical_main_pets(summon_id):
			_synchronize_pet_skill_rank(summon)
	var skeletons = _canonical_main_pets("skeleton")
	var limit = SkillRankResolver.skeleton_count(_profile.effective_skill_level("taoist.summon_skeleton"))
	for i: int in range(skeletons.size() - 1, limit - 1, -1):
		skeletons[i].retire_for_rank_cap()
	# Re-read the canonical live set after retirement callbacks so the stable
	# slot retention pass does not count actors already leaving the tree.
	skeletons = _canonical_main_pets("skeleton")
	var saved_groups: Dictionary = _profile.taoist_main_pet_runtime_states_for_restore().get("groups", {})
	var retained_slots: Dictionary = {}
	for summon: Object in skeletons:
		retained_slots[summon.pet_slot_index] = true
	var pending_capacity = maxi(0, limit - skeletons.size())
	var saved_skeletons: Array = (saved_groups.get("skeleton", []) as Array).duplicate(true)
	saved_skeletons.sort_custom(func(a: Variant, b: Variant) -> bool:
		return int((a as Dictionary).get("pet_slot_index", 0)) < int((b as Dictionary).get("pet_slot_index", 0))
	)
	for raw_snapshot: Variant in saved_skeletons:
		if raw_snapshot is Dictionary:
			var slot = int((raw_snapshot as Dictionary).get("pet_slot_index", 0))
			if retained_slots.has(slot):
				continue
			if pending_capacity > 0:
				retained_slots[slot] = true
				pending_capacity -= 1
			else:
				_profile.clear_taoist_main_pet_runtime_state("skeleton", slot)


func _synchronize_pet_skill_rank(summon: Object) -> void:
	if not _owned(): return
	var skill_name = _rules.profession.skill_display_name(summon.skill_id)
	if _profile.is_skill_learned(skill_name):
		summon.synchronize_skill_rank(_profile.effective_skill_level(skill_name))


func _canonical_main_pet(summon_id: String = "") -> Object:
	if not _owned(): return null
	var pets = _canonical_main_pets(summon_id)
	return pets[0] if not pets.is_empty() else null


func _canonical_main_pets(summon_id: String = "") -> Array:
	if not _owned(): return []
	var result: Array = []
	for node: Object in _actors.actors_in_group("summons"):
		if (
			_actors.is_kind(node, &"summon")
			and _actors.is_runtime_present(node)
			and not _actors.is_queued_for_retirement(node)
			and _actors.owner_model(node) == player
			and bool(_actors.read_meta(node, "taoist_main_pet", false))
			and (summon_id.is_empty() or node.summon_id == summon_id)
			and node.current_hp > 0
			and node.state not in [
				_casting.SummonState.EXPIRED,
				_casting.SummonState.DEAD,
			]
		):
			result.append(node)
	result.sort_custom(func(a: Object, b: Object) -> bool:
		return a.pet_slot_index < b.pet_slot_index
	)
	return result


func _owned_skeleton_slots() -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var used = {}
	var saved_groups: Dictionary = _profile.taoist_main_pet_runtime_states_for_restore().get("groups", {})
	for raw_snapshot: Variant in saved_groups.get("skeleton", []):
		if raw_snapshot is Dictionary:
			used[int((raw_snapshot as Dictionary).get("pet_slot_index", 0))] = true
	for summon: Object in _canonical_main_pets("skeleton"):
		used[summon.pet_slot_index] = true
	return used


func _next_skeleton_slot_index(used: Dictionary) -> int:
	if not _owned(): return 0
	for slot: int in range(SkillRankExtensionPolicy.skeleton_count_cap()):
		if not used.has(slot):
			return slot
	return 0


func _canonical_main_pet_summon_ids() -> Array[String]:
	if not _owned(): return []
	var result: Array[String] = []
	for summon_id: String in ["skeleton", "divine_beast"]:
		if _canonical_main_pet(summon_id) != null:
			result.append(summon_id)
	return result


static func _summon_id_for_skill(stable_skill_id: String) -> String:
	match stable_skill_id:
		"taoist.summon_skeleton":
			return "skeleton"
		"taoist.summon_divine_beast":
			return "divine_beast"
	return ""


func _capture_taoist_main_pet_runtime_states() -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var result = {
		"contract_id": _profile.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"groups": {"skeleton": [], "divine_beast": []},
	}
	var groups = result["groups"] as Dictionary
	# A saved slot can remain pending when this map has no legal birth tile.
	# Keep it across a partial restore and overwrite only matching live slots.
	var preserved_groups: Dictionary = _profile.taoist_main_pet_runtime_states_for_restore().get("groups", {})
	for summon_id: String in ["skeleton", "divine_beast"]:
		var by_slot = {}
		for raw_snapshot: Variant in preserved_groups.get(summon_id, []):
			if raw_snapshot is Dictionary:
				var snapshot = raw_snapshot as Dictionary
				by_slot[int(snapshot.get("pet_slot_index", 0))] = snapshot.duplicate(true)
		for summon: Object in _canonical_main_pets(summon_id):
			if summon.has_method("persistence_snapshot"):
				by_slot[summon.pet_slot_index] = summon.persistence_snapshot()
		var slot_indices: Array = by_slot.keys()
		slot_indices.sort()
		for slot: Variant in slot_indices:
			(groups[summon_id] as Array).append(by_slot[slot])
	return result


func _on_canonical_main_pet_state_changed(
	_previous_state: int,
	current_state: int,
	summon: Object
) -> void:
	if not _owned(): return
	if (
		current_state in [
			_casting.SummonState.EXPIRED,
			_casting.SummonState.DEAD,
		]
		and _actors.is_runtime_present(summon)
		and _actors.owner_model(summon) == player
		and bool(_actors.read_meta(summon, "taoist_main_pet", false))
	):
		_profile.clear_taoist_main_pet_runtime_state(summon.summon_id, summon.pet_slot_index)


func _restore_persisted_taoist_main_pet_if_needed(allow_deferred_arrival: bool = false) -> bool:
	if not _owned(): return false
	if _rules.profession.profession_id(_profile.profession_id) != "taoist":
		return false
	var restored_any = false
	var saved_groups: Dictionary = (
		_profile.taoist_main_pet_runtime_states_for_restore().get("groups", {})
	)
	for summon_id: String in ["skeleton", "divine_beast"]:
		var allowed_skeleton_slots: Dictionary = {}
		if summon_id == "skeleton":
			# Slot ids are stable identities, not a dense array index. After a
			# skill-rank downgrade, preserve the lowest persisted live slots up to
			# the new count; do not reject a valid sparse slot merely because its
			# numeric id is >= the count.
			var candidate_slots: Array[int] = []
			for candidate_raw: Variant in saved_groups.get(summon_id, []):
				if candidate_raw is Dictionary and bool((candidate_raw as Dictionary).get("alive", false)):
					candidate_slots.append(int((candidate_raw as Dictionary).get("pet_slot_index", 0)))
			candidate_slots.sort()
			var skeleton_limit = SkillRankResolver.skeleton_count(
				_profile.effective_skill_level("taoist.summon_skeleton")
			)
			for candidate_index: int in range(mini(skeleton_limit, candidate_slots.size())):
				allowed_skeleton_slots[candidate_slots[candidate_index]] = true
		for raw_snapshot: Variant in saved_groups.get(summon_id, []):
			if not raw_snapshot is Dictionary:
				continue
			var snapshot = raw_snapshot as Dictionary
			var slot = int(snapshot.get("pet_slot_index", 0))
			if not bool(snapshot.get("alive", false)):
				continue
			if summon_id == "skeleton" and not allowed_skeleton_slots.has(slot):
				_profile.clear_taoist_main_pet_runtime_state(summon_id, slot)
				continue
			var stable_skill_id = str(snapshot.get("skill_id", ""))
			if _summon_id_for_skill(stable_skill_id) != summon_id:
				_profile.clear_taoist_main_pet_runtime_state(summon_id, slot)
				continue
			var existing_slot = false
			for pet: Object in _canonical_main_pets(summon_id):
				if pet.pet_slot_index == slot:
					existing_slot = true
			if existing_slot:
				continue
			var spawn_plan = _canonical_summon_spawn_plan(stable_skill_id, null, slot)
			if not bool(spawn_plan.get("valid", false)) and not allow_deferred_arrival:
				continue
			var summon = _casting.create_summon_model(stable_skill_id)
			_casting.setup_summon_model(summon, 
				player,
				"神兽" if summon_id == "divine_beast" else "骷髅",
				maxi(1, _canonical_primary_stat_roll("taoist")),
				maxi(0, int(snapshot.get("skill_rank", 0))),
				stable_skill_id,
				maxi(1, int(snapshot.get("owner_level", _profile.level))),
				int(snapshot.get("maximum_pet_level", -1)),
			)
			if not summon.restore_persistence_snapshot(snapshot):
				_world.discard_cast_birth(summon)
				_profile.clear_taoist_main_pet_runtime_state(summon_id, slot)
				continue
			_synchronize_pet_skill_rank(summon)
			_actors.write_meta(summon, "taoist_main_pet", true)
			_actors.write_meta(summon, 
				"taoist_main_pet_contract",
				_profile.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
			)
			summon.configure_runtime_map_projection(
				current_map_id,
				Callable(self, "_canonical_ground_gu_to_screen_px"),
				Callable(self, "_canonical_screen_px_to_ground_gu"),
			)
			_casting.configure_summon_spatial_index(summon, _spatial)
			_actors.set_position_screen_px(summon, spawn_plan.get("position_screen_px", _actors.position_screen_px(player)) as Vector2)
			summon.configure_spawn_release_footprint(
				"restore:%s:%d:%d" % [stable_skill_id, slot, _clock.now_msec()]
			)
			_world.wire_canonical_main_pet_persistence(summon)
			_world.register_cast_model(summon)
			_world.register_passive_wake_emitter(summon)
			if not bool(spawn_plan.get("valid", false)):
				summon.defer_owner_teleport_relocation()
			restored_any = true
	if restored_any:
		_profile.apply_taoist_main_pet_runtime_states(
			_capture_taoist_main_pet_runtime_states()
		)
	return restored_any


func _canonical_friendly_actor(instance_id: int) -> Object:
	if not _owned(): return null
	if instance_id <= 0:
		return null
	var actor = _actors.resolve_runtime_model(instance_id)
	if not actor is Object or not _actors.is_runtime_present(actor):
		return null
	if actor == player:
		return player
	if _actors.is_kind(actor, &"summon") and _actors.owner_model(actor) == player:
		return actor
	return null


func _apply_canonical_friendly_heal(actor: Object, amount: int) -> int:
	if not _owned(): return 0
	if not _actors.is_runtime_present(actor) or amount <= 0:
		return 0
	if actor == player:
		var hp_before = player.current_hp
		player.restore_health(amount)
		return maxi(0, player.current_hp - hp_before)
	elif _actors.is_kind(actor, &"summon"):
		return actor.restore_health(amount)
	return 0


func _register_ongoing_heal(
	target_instance_id: int,
	heal_per_tick: int,
	tick_count: int,
	tick_interval_seconds: float
) -> void:
	if not _owned(): return
	if target_instance_id <= 0 or heal_per_tick <= 0 or tick_count <= 0:
		return
	_ongoing_heals.append({
		"started_at_usec": _clock.now_usec(),
		"target_instance_id": target_instance_id,
		"target_link": _actors.capture(_canonical_friendly_actor(target_instance_id)),
		"heal_per_tick": heal_per_tick,
		"remaining_ticks": tick_count,
		"tick_interval_seconds": maxf(0.1, tick_interval_seconds),
		"elapsed": 0.0,
	})


func _tick_ongoing_heals(delta: float) -> void:
	if not _owned(): return
	if _ongoing_heals.is_empty():
		return
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _ongoing_heals:
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		var interval = float(entry.get("tick_interval_seconds", 0.8))
		while float(entry.get("elapsed", 0.0)) >= interval:
			entry["elapsed"] = float(entry.get("elapsed", 0.0)) - interval
			var remaining = int(entry.get("remaining_ticks", 0)) - 1
			entry["remaining_ticks"] = remaining
			var actor = entry.target_link.borrow_model() if entry.target_link != null else null
			if not _actors.is_runtime_present(actor):
				entry["remaining_ticks"] = 0
				break
			_apply_canonical_friendly_heal(
				actor,
				int(entry.get("heal_per_tick", 1))
			)
			if remaining <= 0:
				break
		if (
			int(entry.get("remaining_ticks", 0)) > 0
			and is_instance_valid(_canonical_friendly_actor(
				int(entry.get("target_instance_id", 0))
			))
		):
			keep.append(entry)
	for entry: Dictionary in _ongoing_heals:
		if not keep.has(entry) and entry.get("target_link") != null: entry.target_link.dispose()
	_ongoing_heals = keep


func _ongoing_heal_remaining_ticks(target_instance_id: int) -> int:
	if not _owned(): return 0
	var total = 0
	for entry: Dictionary in _ongoing_heals:
		if int(entry.get("target_instance_id", 0)) == target_instance_id:
			total += int(entry.get("remaining_ticks", 0))
	return total


func _canonical_friendly_candidates() -> Array:
	if not _owned(): return []
	## Candidate pool contract: the caster plus alive, owned, non-queued
	## SummonActors. Positions use the formal map projection.
	var result: Array = []
	if not _actors.is_runtime_present(player):
		return result
	result.append(TaoistSupportPolicyScript.make_candidate(
		_actors.runtime_actor_id(player),
		true,
		player.current_hp,
		player.max_hp,
		_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player)),
		_profile.level,
		"self"
	))
	for node: Object in _actors.actors_in_group("summons"):
		if not _actors.is_kind(node, &"summon"):
			continue
		var summon = node
		if (
			_actors.is_queued_for_retirement(summon)
			or _actors.owner_model(summon) != player
			or summon.current_hp <= 0
		):
			continue
		result.append(TaoistSupportPolicyScript.make_candidate(
			_actors.runtime_actor_id(summon),
			false,
			summon.current_hp,
			summon.max_hp,
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(summon)),
			maxi(1, summon.owner_level),
			"summon"
		))
	return result


func _select_taoist_heal_target(center_ground_gu: Vector2) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	return TaoistSupportPolicyScript.select_heal_target(
		_canonical_friendly_candidates(),
		center_ground_gu,
		TaoistSupportPolicyScript.DEFAULT_HEAL_RANGE_GU
	)


func _resolve_release_friendly_target(
	requested_instance_id: int,
	candidates: Array,
	center_ground_gu: Vector2
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## Release-time validation of the identity recorded at input. On failure it
	## reselects exactly once via the same pure policy; a missing result means
	## no canonical plan and no MP commit. The recorded target stays
	## authoritative only while it is still the policy's current best; once it
	## became full while another friendly is injured (or left range / died),
	## the release reselects exactly once. Full-HP pools still resolve validly
	## with self preferred (user override 2026-08-09).
	if requested_instance_id > 0:
		var current_best = TaoistSupportPolicyScript.select_heal_target(
			candidates,
			center_ground_gu,
			TaoistSupportPolicyScript.DEFAULT_HEAL_RANGE_GU
		)
		if (
			bool(current_best.get("valid", false))
			and int(
				current_best.get("selected", {}).get("instance_id", 0)
			) == requested_instance_id
		):
			var recorded: Dictionary = {}
			for raw_candidate: Variant in candidates:
				if not raw_candidate is Dictionary:
					continue
				var candidate: Dictionary = raw_candidate
				if int(candidate.get("instance_id", 0)) == requested_instance_id:
					recorded = candidate
					break
			if not recorded.is_empty():
				return {
					"valid": true,
					"selected": recorded,
					"reselected": false,
					"reason": "",
				}
	var selection = TaoistSupportPolicyScript.select_heal_target(
		candidates,
		center_ground_gu,
		TaoistSupportPolicyScript.DEFAULT_HEAL_RANGE_GU
	)
	if bool(selection.get("valid", false)):
		return {
			"valid": true,
			"selected": selection.get("selected", {}),
			"reselected": requested_instance_id > 0,
			"reason": "",
		}
	return {
		"valid": false,
		"selected": {},
		"reselected": false,
		"reason": str(
			selection.get("reason", "no_injured_friendly_target_in_range")
		),
	}


func _apply_friendly_defence_buff_to_actor(
	actor: Object,
	stat: String,
	value: int,
	duration_seconds: float,
	buff_id: String
) -> void:
	if not _owned(): return
	if not _actors.is_runtime_present(actor) or value <= 0:
		return
	if stat == "MAC":
		if actor == player:
			player.apply_mac_buff(duration_seconds, value)
		elif _actors.is_kind(actor, &"summon"):
			actor.apply_mac_buff(
				value,
				duration_seconds,
				buff_id
			)
	else:
		if actor == player:
			player.apply_ac_buff(duration_seconds, value)
		elif _actors.is_kind(actor, &"summon"):
			actor.apply_ac_buff(
				value,
				duration_seconds,
				buff_id
			)


func _apply_friendly_stealth_to_actor(
	actor: Object,
	duration_seconds: float,
	buff_id: String
) -> void:
	if not _owned(): return
	if not _actors.is_runtime_present(actor):
		return
	if actor == player:
		player.apply_stealth(duration_seconds)
	elif _actors.is_kind(actor, &"summon"):
		actor.apply_stealth(
			duration_seconds,
			buff_id
		)


func _apply_canonical_main_pet(
	descriptor: Dictionary,
	stable_skill_id: String,
	release_id: String
) -> void:
	if not _owned(): return
	var operation = str(descriptor.get("operation", ""))
	if operation not in [
		"recall_existing_main_pet",
		"main_pet_spawn",
		"summon",
	]:
		return
	var requested_summon_id = str(
		descriptor.get(
			"template_id",
			descriptor.get(
				"template_requested", _summon_id_for_skill(stable_skill_id)
			)
		)
	)
	if requested_summon_id not in ["skeleton", "divine_beast"]:
		return
	var spawn_snapshot: Dictionary = descriptor.get(
		"spawn_footprint_snapshot", {}
	)
	var descriptor_snapshot_id = str(
		descriptor.get("spawn_snapshot_id", "")
	)
	var descriptor_map_id = int(
		descriptor.get(
			"spawn_runtime_map_id",
			descriptor.get("runtime_map_id", -1)
		)
	)
	if (
		not _snapshot_strict_ok(spawn_snapshot)
		or descriptor_snapshot_id.is_empty()
		or descriptor_snapshot_id != str(spawn_snapshot.get("snapshot_id", ""))
		or descriptor_map_id != current_map_id
	):
		return
	var spawn_ground_gu: Vector2 = spawn_snapshot.get(
		"target_center_ground_gu", Vector2.INF
	)
	if not spawn_ground_gu.is_finite():
		return
	var spawn_screen_px = _canonical_ground_gu_to_screen_px(spawn_ground_gu)
	var summon_radius_px = ActorBodyPolicyScript.tier_screen_radius_px(StringName(ActorBodyPolicyScript.summon_tier(requested_summon_id)))
	if summon_radius_px <= 0.0:
		return
	var summon_radius_gu = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(summon_radius_px)
	var snapshot_radius = float(spawn_snapshot.get("target_combat_radius_gu", -1.0))
	if not is_finite(snapshot_radius) or absf(snapshot_radius - summon_radius_gu) > GroundUnitSpaceScript.EPSILON_GU:
		return
	var existing = _canonical_main_pet(requested_summon_id)
	var requested_slot = int(descriptor.get("pet_slot_index", 0))
	if operation == "recall_existing_main_pet":
		for pet: Object in _canonical_main_pets(requested_summon_id):
			if pet.owner_teleport_pending:
				var pending_generation = int(_actors.read_meta(pet, "pending_arrival_zone_generation", -1))
				if pending_generation != _zone_generation:
					# A late recall descriptor from an older map arrival has no
					# authority to make a hidden old-generation pet visible again.
					_pending_main_pet_arrivals.erase(pet)
					pet.remove_meta("pending_arrival_zone_generation")
					continue
			var recall_plan = _canonical_summon_spawn_plan(stable_skill_id, pet, pet.pet_slot_index)
			if not bool(recall_plan.get("valid", false)):
				continue
			var relocation = pet.relocate_after_owner_teleport(
				recall_plan.get("position_screen_px") as Vector2
			)
			if bool(relocation.get("relocated", false)):
				_pending_main_pet_arrivals.erase(pet)
				pet.remove_meta("pending_arrival_zone_generation")
			_synchronize_pet_skill_rank(pet)
			pet.configure_spawn_release_footprint(release_id)
		return
	if not bool(descriptor.get("spawned", false)):
		return
	if requested_summon_id == "divine_beast" and existing != null:
		return
	if requested_summon_id == "skeleton":
		var skeletons = _canonical_main_pets("skeleton")
		if skeletons.size() >= SkillRankResolver.skeleton_count(_profile.effective_skill_level(stable_skill_id)):
			return
		for pet: Object in skeletons:
			if pet.pet_slot_index == requested_slot:
				return
	if not _canonical_summon_position_is_valid(
		spawn_ground_gu,
		summon_radius_gu,
		null
	):
		return
	var summon_name = (
		"神兽"
		if requested_summon_id == "divine_beast"
		else "骷髅"
	)
	var summon = _casting.create_summon_model(stable_skill_id)
	_casting.setup_summon_model(summon, 
		player,
		summon_name,
		maxi(1, _canonical_primary_stat_roll("taoist")),
		int(descriptor.get("initial_pet_level", 0)),
		stable_skill_id,
		_profile.level,
		int(descriptor.get("max_pet_level", -1))
	)
	summon.pet_slot_index = requested_slot
	_synchronize_pet_skill_rank(summon)
	_actors.write_meta(summon, "taoist_main_pet", true)
	_actors.write_meta(summon, "taoist_main_pet_contract", _profile.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID)
	summon.configure_runtime_map_projection(
		current_map_id,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu")
	)
	_casting.configure_summon_spatial_index(summon, _spatial)
	_actors.set_position_screen_px(summon, spawn_screen_px)
	summon.configure_spawn_release_footprint(release_id)
	_actors.write_meta(summon, 
		"canonical_spawn_footprint_snapshot",
		spawn_snapshot.duplicate(true)
	)
	_world.wire_canonical_main_pet_persistence(summon)
	_world.register_cast_model(summon)
	_world.register_passive_wake_emitter(summon)
	_profile.apply_taoist_main_pet_runtime_states(
		_capture_taoist_main_pet_runtime_states()
	)


func _relocate_main_pets_after_map_arrival() -> void:
	if not _owned(): return
	# _load_zone restores pets before the caller installs its final arrival.
	# Restore any saved slots that had no room at _load_zone's provisional
	# position, then place every live slot at the owner's final destination.
	_restore_persisted_taoist_main_pet_if_needed(true)
	# Stale positions of the other moving pets cannot reserve arrival tiles.
	_pending_main_pet_arrivals.clear()
	_pending_main_pet_retry_tile_valid = false
	var pending: Array = []
	for summon_id: String in ["skeleton", "divine_beast"]:
		pending.append_array(_canonical_main_pets(summon_id))
	for summon_id: String in ["skeleton", "divine_beast"]:
		for summon: Object in _canonical_main_pets(summon_id):
			summon.configure_runtime_map_projection(
				current_map_id,
				Callable(self, "_canonical_ground_gu_to_screen_px"),
				Callable(self, "_canonical_screen_px_to_ground_gu"),
			)
			_casting.configure_summon_spatial_index(summon, _spatial)
			var stable_skill_id = (
				"taoist.summon_skeleton" if summon_id == "skeleton"
				else "taoist.summon_divine_beast"
			)
			var plan = _canonical_summon_spawn_plan(
				stable_skill_id, summon, summon.pet_slot_index, pending
			)
			if not bool(plan.get("valid", false)):
				plan = _canonical_summon_teleport_fallback_plan(summon, pending)
			if bool(plan.get("valid", false)):
				summon.relocate_after_owner_teleport(plan.get("position_screen_px") as Vector2)
				pending.erase(summon)
			else:
				summon.defer_owner_teleport_relocation()
				_actors.write_meta(summon, "pending_arrival_zone_generation", _zone_generation)
				_pending_main_pet_arrivals.append(summon)
	if not _pending_main_pet_arrivals.is_empty():
		_pending_main_pet_retry_tile = _main_pet_owner_tile()
		_pending_main_pet_retry_tile_valid = true


func _main_pet_follow_context_is_current(summon: Object) -> bool:
	if not _owned(): return false
	return (
		_world.is_inside_world()
		and not _world.is_queued_for_retirement()
		and not _map_transition_in_progress
		and _actors.is_runtime_present(player)
		and player.current_hp > 0
		and _geometry.is_present()
		and _actors.is_runtime_present(summon)
		and not _actors.is_queued_for_retirement(summon)
		and _actors.is_inside_world(summon)
		and _actors.is_in_parent_scope(summon)
		and _actors.owner_model(summon) == player
		and bool(_actors.read_meta(summon, "taoist_main_pet", false))
		and summon.summon_id in ["skeleton", "divine_beast"]
		and summon.runtime_map_id == current_map_id
		and summon.runtime_ground_gu_to_screen_position_px.is_valid()
		and summon.runtime_screen_to_ground_position_px.is_valid()
		and summon.current_hp > 0
		and summon.state not in [_casting.SummonState.DEAD, _casting.SummonState.EXPIRED]
	)


func _canonical_summon_follow_landing_plan(summon: Object) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	# Follow teleport uses the same map/body placement authority as arrival.
	# Invalid ownership or a transition cannot authorize relocation or deferral.
	if not _main_pet_follow_context_is_current(summon):
		return {"valid": false, "reason": "follow_context_not_current", "defer_allowed": false}
	var pending: Array = [summon]
	var formation_screen_px = summon._owner_formation_anchor_screen_px()
	var formation_ground_gu = _canonical_screen_px_to_ground_gu(formation_screen_px)
	if _canonical_summon_position_is_valid(
		formation_ground_gu, _actor_combat_radius_gu(summon), summon, pending
	):
		return {
			"valid": true,
			"reason": "",
			"position_ground_gu": formation_ground_gu,
			"position_screen_px": formation_screen_px,
			"defer_allowed": true,
		}
	var stable_skill_id = (
		"taoist.summon_skeleton" if summon.summon_id == "skeleton"
		else "taoist.summon_divine_beast"
	)
	var plan = _canonical_summon_spawn_plan(stable_skill_id, summon, summon.pet_slot_index, pending)
	if not bool(plan.get("valid", false)):
		plan = _canonical_summon_teleport_fallback_plan(summon, pending)
	plan["defer_allowed"] = true
	return plan


func _register_pending_main_pet_arrival(summon: Object) -> bool:
	if not _owned(): return false
	if not _main_pet_follow_context_is_current(summon) or not summon.owner_teleport_pending:
		return false
	_actors.write_meta(summon, "pending_arrival_zone_generation", _zone_generation)
	if not _pending_main_pet_arrivals.has(summon):
		_pending_main_pet_arrivals.append(summon)
		_pending_main_pet_retry_tile = _main_pet_owner_tile()
		_pending_main_pet_retry_tile_valid = true
	return true


func _main_pet_owner_tile() -> Vector2i:
	if not _owned(): return Vector2i.ZERO
	var owner_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
	return Vector2i(floori(owner_ground_gu.x), floori(owner_ground_gu.y))


func _retry_pending_main_pet_arrivals() -> void:
	if not _owned(): return
	if not _actors.is_runtime_present(player):
		return
	var owner_tile = _main_pet_owner_tile()
	if _pending_main_pet_retry_tile_valid and owner_tile == _pending_main_pet_retry_tile:
		return
	_pending_main_pet_retry_tile = owner_tile
	_pending_main_pet_retry_tile_valid = true
	var pending = _pending_main_pet_arrivals.duplicate()
	for summon: Object in pending:
		if not _actors.is_runtime_present(summon) or _actors.is_queued_for_retirement(summon):
			_pending_main_pet_arrivals.erase(summon)
			continue
		if (
			not summon.owner_teleport_pending
			or not _main_pet_follow_context_is_current(summon)
			or int(_actors.read_meta(summon, "pending_arrival_zone_generation", -1)) != _zone_generation
		):
			_pending_main_pet_arrivals.erase(summon)
			continue
		var stable_skill_id = (
			"taoist.summon_skeleton" if summon.summon_id == "skeleton"
			else "taoist.summon_divine_beast"
		)
		var plan = _canonical_summon_spawn_plan(
			stable_skill_id, summon, summon.pet_slot_index, pending
		)
		if not bool(plan.get("valid", false)):
			plan = _canonical_summon_teleport_fallback_plan(summon, pending)
		if bool(plan.get("valid", false)):
			summon.relocate_after_owner_teleport(plan.get("position_screen_px") as Vector2)
			_pending_main_pet_arrivals.erase(summon)
			pending.erase(summon)


func _canonical_summon_teleport_fallback_plan(
	summon: Object,
	pending: Array,
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	# Casting retains its two-GU search. An existing pet may need a wider legal
	# landing after its owner arrives in a narrow passage. Search in stable
	# nearest-first order without drawing RNG or moving through map collision.
	var owner_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
	var center = Vector2i(roundi(owner_ground_gu.x), roundi(owner_ground_gu.y))
	var radius_gu = _actor_combat_radius_gu(summon)
	var candidates: Array[Vector2i] = []
	for offset_y: int in range(
		-CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU,
		CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU + 1,
	):
		for offset_x: int in range(
			-CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU,
			CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU + 1,
		):
			var candidate = center + Vector2i(offset_x, offset_y)
			if Vector2(candidate).distance_to(owner_ground_gu) <= (
				float(CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU)
				+ GroundUnitSpaceScript.EPSILON_GU
			):
				candidates.append(candidate)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance = Vector2(a).distance_squared_to(owner_ground_gu)
		var b_distance = Vector2(b).distance_squared_to(owner_ground_gu)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	for candidate: Vector2i in candidates:
		var candidate_gu = Vector2(candidate)
		if not _canonical_summon_position_is_valid(
			candidate_gu, radius_gu, summon, pending
		):
			continue
		return {
			"valid": true,
			"reason": "",
			"position_ground_gu": candidate_gu,
			"position_screen_px": _canonical_ground_gu_to_screen_px(candidate_gu),
		}
	return {"valid": false, "reason": "no_legal_teleport_landing"}


func _canonical_summon_spawn_plan(
	stable_skill_id: String,
	ignored_summon: Object = null,
	pet_slot_index: int = 0,
	ignored_summons: Array = [],
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	if not _actors.is_runtime_present(player):
		return {"valid": false, "reason": "player_unavailable"}
	var player_ground_gu = _canonical_screen_px_to_ground_gu(
		_actors.position_screen_px(player)
	)
	var facing_ground_gu = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.facing
		).normalized()
	)
	if (
		facing_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		facing_ground_gu = Vector2(1.0, 1.0).normalized()
	var side_direction_ground_gu = Vector2(
		-facing_ground_gu.y,
		facing_ground_gu.x
	)
	var summon_offset_gu = (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			42.0
		)
	)
	var desired_ground_gu = (
		player_ground_gu
		+ side_direction_ground_gu * summon_offset_gu * float(1 + pet_slot_index / 2)
		- facing_ground_gu * summon_offset_gu * float(pet_slot_index % 2)
	)
	var center_tile = Vector2i(
		roundi(desired_ground_gu.x),
		roundi(desired_ground_gu.y)
	)
	var candidates: Array[Vector2i] = []
	for offset_y: int in range(-2, 3):
		for offset_x: int in range(-2, 3):
			var candidate_tile = center_tile + Vector2i(offset_x, offset_y)
			if Vector2(candidate_tile).distance_to(desired_ground_gu) <= (
				CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU
				+ GroundUnitSpaceScript.EPSILON_GU
			):
				candidates.append(candidate_tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance = Vector2(a).distance_squared_to(desired_ground_gu)
		var b_distance = Vector2(b).distance_squared_to(desired_ground_gu)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	var summon_tier = ActorBodyPolicyScript.summon_tier(_summon_id_for_skill(stable_skill_id))
	var summon_radius_px = ActorBodyPolicyScript.tier_screen_radius_px(StringName(summon_tier))
	if summon_radius_px <= 0.0:
		return {"valid": false, "reason": "unknown_summon_body_policy"}
	var summon_radius_gu = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(summon_radius_px)
	for candidate_tile: Vector2i in candidates:
		var candidate_ground_gu = Vector2(candidate_tile)
		if not _canonical_summon_position_is_valid(
			candidate_ground_gu,
			summon_radius_gu,
			ignored_summon,
			ignored_summons
		):
			continue
		return {
			"valid": true,
			"reason": "",
			"position_ground_gu": candidate_ground_gu,
			"position_screen_px": _canonical_ground_gu_to_screen_px(
				candidate_ground_gu
			),
			"desired_ground_gu": desired_ground_gu,
			"search_radius_gu": CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU,
		}
	return {
		"valid": false,
		"reason": "no_valid_adjacent_tile",
		"position_ground_gu": desired_ground_gu,
		"position_screen_px": _actors.position_screen_px(player),
		"desired_ground_gu": desired_ground_gu,
		"search_radius_gu": CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU,
	}


func _canonical_summon_position_is_valid(
	candidate_ground_gu: Vector2,
	summon_radius_gu: float,
	ignored_summon: Object,
	ignored_summons: Array = [],
) -> bool:
	if not _owned(): return false
	if not candidate_ground_gu.is_finite():
		return false
	var candidate_screen_px = _canonical_ground_gu_to_screen_px(
		candidate_ground_gu
	)
	if _geometry.environment_blocks_actor_screen_px(
		_geometry,
		candidate_screen_px,
		WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
			summon_radius_gu
		)
	):
		return false
	if _actors.is_runtime_present(player) and player != ignored_summon:
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(player)),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ _actor_combat_radius_gu(player)
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	var enemy_query_radius_gu = (
		summon_radius_gu
		+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
	)
	if not _target_spatial_query_aabb_into(
		Rect2(
			candidate_ground_gu - Vector2.ONE * enemy_query_radius_gu,
			Vector2.ONE * enemy_query_radius_gu * 2.0,
		),
		_target_spatial_query_scratch,
		# PERF-2: existence probe — occupancy is order-insensitive.
		false,
	):
		return false
	for enemy: Object in _target_spatial_query_scratch:
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ enemy.combat_radius_gu
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	for raw_summon: Variant in _actors.actors_in_group("summons"):
		if (
			not raw_summon is Object
			or not _actors.is_runtime_present(raw_summon)
			or raw_summon == ignored_summon
			or (_actors.is_kind(raw_summon, &"summon") and ignored_summons.has(raw_summon))
			or (_actors.is_kind(raw_summon, &"summon") and raw_summon.owner_teleport_pending)
			or _actors.is_queued_for_retirement(raw_summon)
		):
			continue
		var summon = raw_summon as Object
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(summon)),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ _actor_combat_radius_gu(summon)
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	return true


func _summon_spawn_screen_position_px() -> Vector2:
	if not _owned(): return Vector2.INF
	var spawn_plan = _canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	return spawn_plan.get("position_screen_px", _actors.position_screen_px(player))


func _ground_position_gu_for_map(
	map_id: int,
	screen_position_px: Vector2
) -> Vector2:
	if not _owned(): return Vector2.INF
	var profile = _resolve_projection_profile_for_map(map_id)
	if bool(profile.get("success", false)):
		var screen_to_ground: Callable = profile.get(
			"screen_to_ground",
			Callable()
		)
		if screen_to_ground.is_valid():
			var ground_position_gu: Variant = screen_to_ground.call(
				screen_position_px
			)
			if ground_position_gu is Vector2:
				return ground_position_gu
	if map_id < 0:
		return GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			screen_position_px
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = str(profile.get("reason", ""))
	return Vector2.INF


func _canonical_screen_px_to_grid_cell(screen_position_px: Vector2) -> Vector2i:
	if not _owned(): return Vector2i.ZERO
	var profile = _resolve_projection_profile_for_map(current_map_id)
	if bool(profile.get("success", false)):
		var screen_to_ground: Callable = profile.get(
			"screen_to_ground",
			Callable()
		)
		if screen_to_ground.is_valid():
			var ground_position_gu: Variant = screen_to_ground.call(
				screen_position_px
			)
			if ground_position_gu is Vector2:
				return Vector2i(
					roundi(ground_position_gu.x),
					roundi(ground_position_gu.y)
				)
	if current_map_id < 0:
		var unmapped_ground_gu = (
			GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
				screen_position_px
			)
		)
		return Vector2i(
			roundi(unmapped_ground_gu.x),
			roundi(unmapped_ground_gu.y)
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = str(profile.get("reason", ""))
	return Vector2i(-100000, -100000)


func _resolve_projection_profile_for_map(map_id: int) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## FREEZE-P0.2R: formal runtime profile in normal gameplay; reference
	## profile only inside an explicit reference_audit_mode context (migration /
	## import audit / test-dev preview). Never inferred from WorldContent.
	if _projection_profile_cache_audit_mode != reference_audit_mode:
		_projection_profile_cache.clear()
		_projection_profile_runtime_identity_cache.clear()
		_projection_profile_cache_audit_mode = reference_audit_mode
	var cache_key = "%d|%d" % [
		map_id,
		1 if reference_audit_mode else 0,
	]
	var profile: Dictionary
	if reference_audit_mode:
		_projection_profile_runtime_identity_cache.clear()
		if _projection_profile_cache.has(cache_key):
			return _projection_profile_cache[cache_key]
		profile = _geometry.mapper.resolve_reference_projection_profile(
			map_id
		)
	else:
		var runtime_identity = _geometry.map_data.load_map(map_id)
		if (
			_projection_profile_cache.has(cache_key)
			and _projection_profile_runtime_identity_cache.has(cache_key)
			and is_same(
				_projection_profile_runtime_identity_cache[cache_key],
				runtime_identity
			)
		):
			return _projection_profile_cache[cache_key]
		_projection_profile_cache.erase(cache_key)
		_projection_profile_runtime_identity_cache.erase(cache_key)
		profile = _geometry.mapper.resolve_formal_runtime_projection_profile(
			map_id
		)
		_projection_profile_runtime_identity_cache[cache_key] = runtime_identity
	_projection_profile_cache[cache_key] = profile
	return profile


func _try_canonical_screen_px_to_ground_gu(
	screen_position_px: Vector2
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	## FREEZE-P0.2R: explicit fail-closed result driven by the current map's
	## projection profile (formal runtime in normal gameplay; reference profile
	## only inside an explicit reference_audit_mode context). Never falls back
	## to identity/delta for a mapped id.
	var profile = _resolve_projection_profile_for_map(current_map_id)
	if not bool(profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(profile.get("reason", ""))
		return GroundUnitSpaceScript.projection_result(
			false,
			str(profile.get("reason", ""))
		)
	var screen_to_ground: Callable = profile.get(
		"screen_to_ground",
		Callable()
	)
	if not screen_to_ground.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		return GroundUnitSpaceScript.projection_result(
			false,
			GroundUnitSpaceScript.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
	var ground_position_gu: Variant = screen_to_ground.call(screen_position_px)
	if ground_position_gu is Vector2:
		return GroundUnitSpaceScript.projection_result(
			true,
			&"",
			ground_position_gu
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpaceScript.REASON_INVALID_RUNTIME_PROJECTION
	)
	return GroundUnitSpaceScript.projection_result(
		false,
		GroundUnitSpaceScript.REASON_INVALID_RUNTIME_PROJECTION
	)


func _try_canonical_ground_gu_to_screen_px(
	ground_position_gu: Vector2
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var profile = _resolve_projection_profile_for_map(current_map_id)
	if not bool(profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(profile.get("reason", ""))
		return GroundUnitSpaceScript.projection_result(
			false,
			str(profile.get("reason", ""))
		)
	var ground_to_screen: Callable = profile.get(
		"ground_to_screen",
		Callable()
	)
	if not ground_to_screen.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MISSING_GROUND_TO_SCREEN_PROJECTION
		)
		return GroundUnitSpaceScript.projection_result(
			false,
			GroundUnitSpaceScript.REASON_MISSING_GROUND_TO_SCREEN_PROJECTION
		)
	var screen_position_px: Variant = ground_to_screen.call(ground_position_gu)
	if screen_position_px is Vector2:
		return GroundUnitSpaceScript.projection_result(
			true,
			&"",
			screen_position_px
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpaceScript.REASON_INVALID_RUNTIME_PROJECTION
	)
	return GroundUnitSpaceScript.projection_result(
		false,
		GroundUnitSpaceScript.REASON_INVALID_RUNTIME_PROJECTION
	)


func _canonical_screen_px_to_ground_gu(screen_position_px: Vector2) -> Vector2:
	if not _owned(): return Vector2.INF
	var result = _try_canonical_screen_px_to_ground_gu(screen_position_px)
	if bool(result.get("success", false)):
		return result.get("value", Vector2.ZERO)
	return Vector2.INF


func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2:
	if not _owned(): return Vector2.INF
	var result = _try_canonical_ground_gu_to_screen_px(ground_position_gu)
	if bool(result.get("success", false)):
		return result.get("value", Vector2.ZERO)
	return Vector2.INF


func _canonical_grid_cell_to_screen_px(grid_cell: Variant) -> Vector2:
	if not _owned(): return Vector2.INF
	var tile = Vector2i(grid_cell) if grid_cell is Vector2i else Vector2i.ZERO
	var profile = _resolve_projection_profile_for_map(current_map_id)
	if bool(profile.get("success", false)):
		var ground_to_screen: Callable = profile.get(
			"ground_to_screen",
			Callable()
		)
		if ground_to_screen.is_valid():
			var screen_position_px: Variant = ground_to_screen.call(
				Vector2(tile)
			)
			if screen_position_px is Vector2:
				return screen_position_px
	if current_map_id < 0:
		return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
			Vector2(tile)
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = str(profile.get("reason", ""))
	return Vector2.INF


func _canonical_snapshot_absolute_context(
	origin_ground_gu: Vector2
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	# HC-P1-010: absolute snapshots must carry the runtime map id, an explicit
	# projection origin (the skill release origin) and the map projection
	# callable. Screen offsets are relative to that origin.
	return SkillFootprintSnapshotScript.make_absolute_runtime_context(
		current_map_id,
		origin_ground_gu,
		origin_ground_gu,
		Callable(self, "_canonical_ground_gu_to_screen_px")
	)


func _canonical_snapshot_validation_context(
	origin_ground_gu: Vector2
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var context = _canonical_snapshot_absolute_context(origin_ground_gu)
	context["expected_runtime_map_id"] = current_map_id
	return context


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	if not _owned(): return false
	var origin = Vector2.ZERO
	if _actors.is_runtime_present(player):
		origin = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(player))
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_canonical_snapshot_validation_context(origin),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


func _canonical_facing(direction: Vector2) -> Vector2i:
	if not _owned(): return Vector2i.ZERO
	if direction.length_squared() < 0.01:
		return Vector2i.DOWN
	return Vector2i(signi(roundi(direction.x)), signi(roundi(direction.y)))


func _canonical_facing_for_skill(skill_id: String, direction: Vector2) -> Vector2i:
	if not _owned(): return Vector2i.ZERO
	if skill_id in ["warrior.thrusting", "warrior.half_moon", "warrior.fire_sword"]:
		return WarriorMeleeGeometryScript.facing_tile_step(ArtSpec.direction_index(direction))
	if skill_id in CANONICAL_WIZARD_GEOMETRY_SKILLS:
		return CasterSpellGeometryScript.canonical_facing_grid_step_from_screen_direction_px(
			direction
		)
	return _canonical_facing(direction)


func _canonical_primary_stat_roll(profession_id: String, stats: Dictionary = {}) -> int:
	if not _owned(): return 0
	var minimum_key = "tao_min" if profession_id == "taoist" else ("magic_min" if profession_id == "wizard" else "attack_min")
	var maximum_key = "tao_max" if profession_id == "taoist" else ("magic_max" if profession_id == "wizard" else "attack_max")
	var snapshot: Dictionary = _profile.computed_stats if stats.is_empty() else stats
	var minimum = int(snapshot.get(minimum_key, 0))
	var maximum = maxi(minimum, int(snapshot.get(maximum_key, minimum)))
	return _rules.warrior.roll_primary_stat(minimum, maximum, int(snapshot.get("luck", 0)), _random)


func _next_canonical_seed() -> int:
	if not _owned(): return 0
	_canonical_cast_serial += 1
	return hash([_clock.now_msec(), _canonical_cast_serial, _profile.active_profile_id])


func _next_skill_footprint_release_id(stable_skill_id: String) -> String:
	if not _owned(): return ""
	_skill_footprint_release_serial += 1
	return "player:%d:skill:%s:release:%d" % [
		_actors.runtime_actor_id(player) if _actors.is_runtime_present(player) else 0,
		stable_skill_id,
		_skill_footprint_release_serial,
	]


func _skill_needs_target(cast_type: String) -> bool:
	if not _owned(): return false
	return cast_type not in ["passive", "heal", "heal_area", "shield", "stealth", "stealth_area", "magic_defense_buff", "defense_buff", "summon", "teleport"]


func _spawn_projectile(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	maximum_distance_gu: float,
	color: Color,
	effect = "damage",
	effect_strength = 0,
	effect_duration = 0.0,
	source_skill_id = "",
	source_release_id = ""
) -> void:
	if not _owned(): return
	var stable_skill_id = SkillDataLoaderScript.stable_skill_id(source_skill_id)
	var formal_maximum_distance_gu = maxf(0.0, maximum_distance_gu)
	if not stable_skill_id.is_empty():
		var definition = SkillDataLoaderScript.skill(stable_skill_id)
		var configured_maximum_distance_gu = float(
			definition.get("geometry", {}).get("maximum_range_gu", 0.0)
		)
		if configured_maximum_distance_gu > 0.0:
			formal_maximum_distance_gu = configured_maximum_distance_gu
	var direction_ground_gu = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		direction_ground_gu = Vector2(1.0, -1.0).normalized()
	var visual_direction_screen_px = direction_screen_px.normalized()
	if visual_direction_screen_px.length_squared() <= 0.000001:
		visual_direction_screen_px = (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
			).normalized()
		)
	var projectile = _casting.create_projectile_model()
	projectile.setup_ground_unit_projectile(
		origin_screen_px,
		direction_ground_gu,
		formal_maximum_distance_gu,
		damage,
		CombatUnitLegacyAdapterScript.PROJECTILE_SPEED_GU_PER_SEC,
		CombatUnitLegacyAdapterScript.PROJECTILE_RADIUS_GU,
		visual_direction_screen_px * 24.0,
		color,
		effect,
		effect_strength,
		effect_duration,
		source_skill_id,
		source_release_id
	)
	projectile.configure_runtime_map_projection(
		current_map_id,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu")
	)
	projectile.configure_spatial_index(_spatial)
	projectile.configure_runtime_resolution(player, Callable(self, "_resolve_magic_defense"))
	_world.register_cast_model(projectile)


func _damage_enemies(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	radial: bool,
	attack_range_gu = 1.5,
	physical_accuracy = false,
	source_skill_id = "",
	query_plan: Dictionary = {},
) -> bool:
	if not _owned(): return false
	var context_skill_id = source_skill_id if not source_skill_id.is_empty() else "legacy_damage"
	_diagnostics.set_performance_release_context(
		"legacy_damage",
		context_skill_id,
	)
	_diagnostics.increment_performance_counter(&"aoe_release_count")
	var aoe_candidate_started_usec = _diagnostics.timing_start()
	var hit_any = false
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	var release_cache: Dictionary = {}
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_legacy_damage_query_plan(
			context_skill_id,
			origin_ground_gu,
			direction_ground_gu,
			attack_range_gu,
			release_cache,
		)
	if not _aoe_plan_is_ready(plan) and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"aoe_query_plan_invalid_or_spatial_index_unavailable"
		)
		_record_aoe_candidate_timing(aoe_candidate_started_usec)
		return false
	if not _aoe_query_enemy_candidates_aabb(
		plan,
		plan.get("ground_aabb", _aoe_geometry_cells_aabb([])),
	):
		_record_aoe_candidate_timing(aoe_candidate_started_usec)
		return false
	var pass_result = _aoe_apply_legacy_damage_candidates(
		_aoe_candidate_scratch,
		origin_screen_px,
		origin_ground_gu,
		direction_ground_gu,
		damage,
		radial,
		attack_range_gu,
		physical_accuracy,
		source_skill_id,
	)
	hit_any = bool(pass_result.get("hit_any", false))
	if (
		int(pass_result.get("geometry_matches", 0)) == 0
		and _aoe_plan_is_ready(plan)
		and _aoe_reference_fallback_allowed()
	):
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		pass_result = _aoe_apply_legacy_damage_candidates(
			_aoe_candidate_scratch,
			origin_screen_px,
			origin_ground_gu,
			direction_ground_gu,
			damage,
			radial,
			attack_range_gu,
			physical_accuracy,
			source_skill_id,
		)
		hit_any = bool(pass_result.get("hit_any", false))
	_record_aoe_candidate_timing(aoe_candidate_started_usec)
	return hit_any


func _resolve_magic_defense(_skill_id: String, damage_after_anti_magic: int, target_stats: Dictionary) -> int:
	if not _owned(): return 0
	var defense_min = int(
		target_stats.get(
			"magic_defense_min",
			target_stats.get("mdefMin", target_stats.get("MinMAC", 0))
		)
	)
	var defense_max = int(
		target_stats.get(
			"magic_defense_max",
			target_stats.get("mdefMax", target_stats.get("MaxMAC", defense_min))
		)
	)
	defense_min = maxi(0, defense_min)
	defense_max = maxi(defense_min, defense_max)
	return maxi(0, damage_after_anti_magic - _random.randi_range(defense_min, defense_max))


func _combat_release_target(release_geometry: Dictionary) -> Object:
	if not _owned(): return null
	var target_instance_id = int(release_geometry.get("locked_target_instance_id", 0))
	if target_instance_id <= 0 or not bool(
		release_geometry.get("locked_target_valid_at_release", false)
	):
		return null
	var candidate = _actors.resolve_runtime_model(target_instance_id)
	if (
		not _actors.is_kind(candidate, &"enemy")
		or not _actors.is_runtime_present(candidate)
		or _actors.is_queued_for_retirement(candidate)
		or candidate.current_hp <= 0
	):
		return null
	return candidate


func _create_melee_release_footprint_snapshot(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	mode: String,
	release_geometry: Dictionary = {}
) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var skill_id: String = {
		WarriorMeleeGeometryScript.SKILL_THRUST: "warrior.thrusting",
		WarriorMeleeGeometryScript.SKILL_HALF_MOON: "warrior.half_moon",
		WarriorMeleeGeometryScript.SKILL_FIRE: "warrior.fire_sword",
	}.get(mode, "warrior.normal_attack")
	var release_id = str(release_geometry.get("release_id", ""))
	if release_id.is_empty():
		release_id = _next_skill_footprint_release_id(skill_id)
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin_screen_px)
	var declared_origin: Variant = release_geometry.get("origin_ground_gu", Vector2.INF)
	if (not is_finite(origin_ground_gu.x) or not is_finite(origin_ground_gu.y)) and declared_origin is Vector2:
		origin_ground_gu = declared_origin as Vector2
	# Production release geometry carries lock-at-release fields. Route those
	# releases through the continuous target-aligned planner; an invalid lock
	# deliberately returns no snapshot so callers fail closed instead of
	# quantizing back to the legacy eight-direction footprint.
	if release_geometry.has("locked_target_valid_at_release"):
		release_geometry["origin_ground_gu"] = origin_ground_gu
		release_geometry["snapshot_validation_context"] = _canonical_snapshot_validation_context(origin_ground_gu)
		# CombatReleaseGeometry freezes the target delta in GU, while mapped
		# gameplay resolves the actor origin in absolute runtime-map GU. Rebase
		# the locked footpoint onto that formal origin before range/shape checks;
		# mixing the legacy delta-space origin with the absolute origin makes every
		# real mapped target appear tens of GU out of range.
		var locked_delta: Variant = release_geometry.get(
			"live_locked_target_delta_ground_gu",
			null
		)
		if locked_delta is Vector2:
			release_geometry["locked_target_ground_gu_at_release"] = (
				origin_ground_gu + (locked_delta as Vector2)
			)
		var plan = WarriorMeleeGeometryScript.target_aligned_melee_release_plan_ground_gu(
			release_geometry,
		mode,
		_canonical_snapshot_validation_context(origin_ground_gu)
		)
		release_geometry["target_aligned_plan"] = plan
		if not bool(plan.get("target_axis_eligible", false)):
			return {}
		return plan.get("skill_footprint_snapshot", {}) as Dictionary
	return WarriorMeleeGeometryScript.attack_release_footprint_snapshot_ground_gu(
		skill_id,
		release_id,
		origin_ground_gu,
		_melee_direction_index(direction_screen_px, release_geometry),
		mode,
		0.0,
		_canonical_snapshot_validation_context(origin_ground_gu)
	)


func _physical_primary_target(
	origin: Vector2,
	direction: Vector2,
	mode = "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Object:
	if not _owned(): return null
	var targets = _physical_primary_targets(
		origin,
		direction,
		mode,
		release_geometry,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		target_aligned_plan,
		query_plan,
	)
	return targets[0] if not targets.is_empty() else null


func _physical_primary_targets(
	origin: Vector2,
	direction: Vector2,
	mode = "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array:
	if not _owned(): return []
	# The attack lock owns facing and priority only. Actual damage rights are
	# rebuilt from live footpoints and the selected melee geometry at release.
	# This deliberately overrides the single-target candidate filter used by
	# caster projectiles without changing their shared release contract.
	var result: Array = []
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	var direction_index = _melee_direction_index(direction, release_geometry)
	var resolved_target_plan: Dictionary = target_aligned_plan
	if resolved_target_plan.is_empty():
		resolved_target_plan = release_geometry.get("target_aligned_plan", {})
	var release_cache: Dictionary = {}
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_melee_query_plan(
			mode,
			origin_ground_gu,
			direction,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			resolved_target_plan,
			release_cache,
		)
	var broadphase_ready = _aoe_plan_is_ready(plan)
	if not broadphase_ready and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"melee_query_plan_invalid_or_spatial_index_unavailable"
		)
		return result
	if not _aoe_query_enemy_candidates_aabb(
		plan,
		plan.get("ground_aabb", Rect2()),
	):
		return result
	_aoe_collect_primary_melee_candidates(
		_aoe_candidate_scratch,
		result,
		origin_ground_gu,
		direction_index,
		mode,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		resolved_target_plan,
		plan,
	)
	if result.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		_aoe_collect_primary_melee_candidates(
			_aoe_candidate_scratch,
			result,
			origin_ground_gu,
			direction_index,
			mode,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			resolved_target_plan,
			plan,
		)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _sort_melee_targets(
	targets: Array,
	origin_ground_gu: Vector2,
	release_geometry: Dictionary
) -> void:
	if not _owned(): return
	var locked_instance_id = int(release_geometry.get("locked_target_instance_id", 0))
	if (
		locked_instance_id <= 0
		and _actors.is_runtime_present(locked_target)
		and _is_attack_target_in_range(locked_target)
	):
		locked_instance_id = _actors.runtime_actor_id(locked_target)
	var ordered: Array = []
	var ordered_distances: Array[float] = []
	var ordered_ids: Array[int] = []
	for enemy: Object in targets:
		var enemy_id = _actors.runtime_actor_id(enemy)
		var enemy_distance_gu = GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
		)
		var enemy_locked = enemy_id == locked_instance_id
		var insert_at = ordered.size()
		for index: int in range(ordered.size()):
			var existing_locked = ordered_ids[index] == locked_instance_id
			if enemy_locked != existing_locked:
				if enemy_locked:
					insert_at = index
				break
			elif (
				enemy_distance_gu < ordered_distances[index]
				or (
					is_equal_approx(enemy_distance_gu, ordered_distances[index])
					and enemy_id < ordered_ids[index]
				)
			):
				insert_at = index
				break
		ordered.insert(insert_at, enemy)
		ordered_distances.insert(insert_at, enemy_distance_gu)
		ordered_ids.insert(insert_at, enemy_id)
	targets.clear()
	targets.append_array(ordered)


func _is_primary_melee_candidate(
	enemy: Object,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> bool:
	if not _owned(): return false
	if not _actors.is_runtime_present(enemy) or _actors.is_queued_for_retirement(enemy) or enemy.current_hp <= 0:
		return false
	var target_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy))
	var query_context: Dictionary = query_plan.get(
		"validation_context_reference",
		_canonical_snapshot_validation_context(origin_ground_gu),
	)
	var validated_plan_ready = _aoe_plan_is_ready(query_plan)
	var target_plan: Dictionary = target_aligned_plan
	if not target_plan.is_empty():
		if not bool(target_plan.get("target_axis_eligible", false)):
			return false
		var target_aligned_sector = _aoe_target_aligned_melee_sector(
			target_plan,
			target_ground_gu,
			enemy.combat_radius_gu,
			mode,
		)
		if mode == WarriorMeleeGeometryScript.SKILL_THRUST:
			return target_aligned_sector == 1
		if mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
			return target_aligned_sector == 0
		return target_aligned_sector == 0
	if (
		validated_plan_ready
		and not _aoe_validated_snapshot_intersects(query_plan, enemy)
	):
		return false
	if not validated_plan_ready and not _aoe_reference_fallback_allowed():
		return false
	if mode == WarriorMeleeGeometryScript.SKILL_THRUST:
		if thrust_damage_axis_plan.is_empty():
			thrust_damage_axis_plan = (
				WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
					direction_index,
					{},
					query_context
				)
			)
		if str(thrust_damage_axis_plan.get("contract_id", "")) != WarriorMeleeGeometryScript.THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID:
			return false
		var damage_direction: Variant = thrust_damage_axis_plan.get(
			"damage_direction_ground_gu", Vector2.ZERO
		)
		if not damage_direction is Vector2 or (damage_direction as Vector2).length_squared() <= 0.000001:
			return false
		return WarriorMeleeGeometryScript.thrust_footprint_slot_for_direction_ground_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			(damage_direction as Vector2),
			0.0,
		) == 1
	if mode == WarriorMeleeGeometryScript.SKILL_HALF_MOON:
		return WarriorMeleeGeometryScript.half_moon_footprint_relative_sector_gu(
			origin_ground_gu,
			target_ground_gu,
			enemy.combat_radius_gu,
			direction_index
		) == 0
	return WarriorMeleeGeometryScript.footprint_intersects_mode_gu(
		origin_ground_gu,
		target_ground_gu,
		enemy.combat_radius_gu,
		direction_index,
		mode
	)


func _apply_physical_hit(
	enemy: Object, damage: int, accuracy_bonus = 0, ignore_ac = false, configuration: RefCounted = null, damage_batch: RefCounted = null
) -> bool:
	if not _owned(): return false
	if (
		enemy == null
		or _actors.is_queued_for_retirement(enemy)
		or not enemy.can_receive_damage()
	):
		return false
	var accuracy = int(
		_canonical_action_primary_stats(configuration).get("accuracy", _rules.warrior.BASE_HIT)
	) + accuracy_bonus
	var target_agility = maxi(1, enemy.agility)
	var diagnostics_enabled = _diagnostics.combat_capture_enabled()
	var hit_roll = -1
	var hit_probability = (
		_rules.warrior.hit_probability(accuracy, target_agility)
		if diagnostics_enabled
		else 0.0
	)
	if not _profile.test_mode:
		hit_roll = _random.randi_range(0, target_agility - 1)
		if not _rules.warrior.hit_succeeds(accuracy, target_agility, hit_roll):
			if diagnostics_enabled:
				_active_physical_hit_diagnostics.append({
					"target_id": _actors.runtime_actor_id(enemy),
					"target_name": enemy.display_name,
					"accuracy": accuracy,
					"accuracy_bonus": accuracy_bonus,
					"target_agility": target_agility,
					"hit_roll": hit_roll,
					"hit_probability": hit_probability,
					"test_mode_bypass": false,
					"requested_damage": maxi(1, damage),
					"result_code": "ACCURACY_MISS",
				})
			return false
	var hp_before = enemy.current_hp
	var physical_resolution = _rules.warrior.resolve_enemy_physical_damage(
		damage, enemy.effective_physical_defense(), ignore_ac
	)
	var damage_context = {"damage_kind":"player_physical","confirmed_hit":true,"source":"game_root._apply_physical_hit"}
	if damage_batch != null:
		damage_context["feature_damage_batch"] = damage_batch
		damage_context["source_class"] = "direct"
		damage_context["damage_channel"] = "physical"
	if not _combat.apply_enemy_physical_damage(
		enemy,
		int(physical_resolution.get("final_damage", 0)),
		player,
		damage_context,
	):
		if diagnostics_enabled:
			_active_physical_hit_diagnostics.append({
				"target_id": _actors.runtime_actor_id(enemy),
				"target_name": enemy.display_name,
				"accuracy": accuracy,
				"accuracy_bonus": accuracy_bonus,
				"target_agility": target_agility,
				"hit_roll": hit_roll,
				"hit_probability": hit_probability,
				"test_mode_bypass": _profile.test_mode,
				"requested_damage": maxi(1, damage),
				"hp_before": hp_before,
				"hp_after": enemy.current_hp,
				"result_code": "DAMAGE_COMMIT_FAILED",
			})
		return false
	if diagnostics_enabled:
		_active_physical_hit_diagnostics.append({
			"target_id": _actors.runtime_actor_id(enemy),
			"target_name": enemy.display_name,
			"accuracy": accuracy,
			"accuracy_bonus": accuracy_bonus,
			"target_agility": target_agility,
			"hit_roll": hit_roll,
			"hit_probability": hit_probability,
			"test_mode_bypass": _profile.test_mode,
			"requested_damage": maxi(1, damage),
			"hp_before": hp_before,
			"hp_after": enemy.current_hp,
			"actual_hp_delta": maxi(0, hp_before - enemy.current_hp),
			"result_code": "HIT_COMMITTED",
		})
	var life_steal_percent = int(_profile.computed_stats.get("life_steal_percent", 0))
	var recovered = int(float(maxi(1, damage)) * float(life_steal_percent) / 100.0)
	if recovered >= 2:
		player.restore_health(recovered)
	if _profile.has_special_effect("paralysis") and _rules.equipment.paralysis_succeeds(enemy.anti_poison, _random.randi_range(0, maxi(1, enemy.anti_poison + 5) - 1)):
		enemy.apply_control(_rules.equipment.paralysis_duration_for_classification(
			str(enemy.monster_data.get("classification", ""))
		))
	return true


func _aoe_collect_thrust_secondary_candidates(
	candidates: Array,
	result: Array,
	excluded_targets: Array,
	origin_ground_gu: Vector2,
	target_plan: Dictionary,
	thrust_damage_axis_plan: Dictionary,
	melee_release_snapshot: Dictionary,
	query_plan: Dictionary,
	direction_index: int,
	release_geometry: Dictionary,
) -> void:
	if not _owned(): return
	var query_context: Dictionary = query_plan.get(
		"validation_context_reference",
		release_geometry.get(
			"snapshot_validation_context",
			_canonical_snapshot_validation_context(origin_ground_gu),
		),
	)
	var axis_plan = thrust_damage_axis_plan
	if axis_plan.is_empty():
		axis_plan = WarriorMeleeGeometryScript.thrust_damage_axis_plan_ground_gu(
			direction_index,
			release_geometry,
			query_context,
		)
	if str(axis_plan.get("contract_id", "")) != WarriorMeleeGeometryScript.THRUST_CONTINUOUS_DAMAGE_AXIS_CONTRACT_ID:
		return
	var axis_ground_gu: Vector2 = axis_plan.get(
		"damage_direction_ground_gu",
		Vector2(
			WarriorMeleeGeometryScript.facing_tile_step(direction_index)
			).normalized(),
	)
	if axis_ground_gu.length_squared() <= 0.000001:
		return
	for enemy: Object in candidates:
		if (
			not _actors.is_runtime_present(enemy)
			or excluded_targets.has(enemy)
			or _actors.is_queued_for_retirement(enemy)
			or enemy.current_hp <= 0
		):
			continue
		var target_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy))
		var slot = (
			_aoe_target_aligned_melee_sector(
				target_plan,
				target_ground_gu,
				enemy.combat_radius_gu,
				WarriorMeleeGeometryScript.SKILL_THRUST,
			)
			if not target_plan.is_empty()
			else (
				WarriorMeleeGeometryScript.thrust_footprint_slot_for_direction_ground_gu(
					origin_ground_gu,
					target_ground_gu,
					enemy.combat_radius_gu,
					axis_ground_gu,
				)
				if (
					query_plan.is_empty()
					or not _aoe_plan_is_ready(query_plan)
					or _aoe_validated_snapshot_intersects(query_plan, enemy)
				)
				else 0
			)
		)
		if slot == 2:
			result.append(enemy)


func _aoe_collect_half_moon_secondary_candidates(
	candidates: Array,
	result: Array,
	excluded_targets: Array,
	origin_ground_gu: Vector2,
	direction_index: int,
	target_plan: Dictionary,
	query_plan: Dictionary,
	release_geometry: Dictionary,
) -> void:
	if not _owned(): return
	for enemy: Object in candidates:
		if (
			not _actors.is_runtime_present(enemy)
			or excluded_targets.has(enemy)
			or _actors.is_queued_for_retirement(enemy)
			or enemy.current_hp <= 0
		):
			continue
		var target_ground_gu = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy))
		var sector = -1
		if not target_plan.is_empty():
			sector = _aoe_target_aligned_melee_sector(
				target_plan,
				target_ground_gu,
				enemy.combat_radius_gu,
				WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			)
		else:
			if (
				query_plan.is_empty()
				or not _aoe_plan_is_ready(query_plan)
				or _aoe_validated_snapshot_intersects(query_plan, enemy)
			):
				sector = WarriorMeleeGeometryScript.half_moon_footprint_relative_sector_gu(
					origin_ground_gu,
					target_ground_gu,
					enemy.combat_radius_gu,
					direction_index,
				)
			else:
				sector = -1
		if sector != -1 and sector != 0:
			result.append(enemy)


func _thrust_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array,
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array:
	if not _owned(): return []
	var result: Array = []
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	var target_plan: Dictionary = target_aligned_plan if not target_aligned_plan.is_empty() else release_geometry.get("target_aligned_plan", {})
	var direction_index = _melee_direction_index(direction, release_geometry)
	var release_cache: Dictionary = {}
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_melee_query_plan(
			WarriorMeleeGeometryScript.SKILL_THRUST,
			origin_ground_gu,
			direction,
			release_geometry,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			target_plan,
			release_cache,
		)
	var broadphase_ready = _aoe_plan_is_ready(plan)
	if not broadphase_ready and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"melee_query_plan_invalid_or_spatial_index_unavailable"
		)
		return result
	if not _aoe_query_enemy_candidates_aabb(
		plan,
		plan.get("ground_aabb", Rect2()),
	):
		return result
	_aoe_collect_thrust_secondary_candidates(
		_aoe_candidate_scratch,
		result,
		excluded_targets,
		origin_ground_gu,
		target_plan,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		plan,
		direction_index,
		release_geometry,
	)
	if result.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		_aoe_collect_thrust_secondary_candidates(
			_aoe_candidate_scratch,
			result,
			excluded_targets,
			origin_ground_gu,
			target_plan,
			thrust_damage_axis_plan,
			melee_release_snapshot,
			plan,
			direction_index,
			release_geometry,
		)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _half_moon_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array,
	release_geometry: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array:
	if not _owned(): return []
	var result: Array = []
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin)
	var target_plan: Dictionary = release_geometry.get("target_aligned_plan", {})
	var direction_index = _melee_direction_index(direction, release_geometry)
	var release_cache: Dictionary = {}
	var plan = query_plan
	if plan.is_empty():
		plan = _aoe_melee_query_plan(
			WarriorMeleeGeometryScript.SKILL_HALF_MOON,
			origin_ground_gu,
			direction,
			release_geometry,
			{},
			melee_release_snapshot,
			target_plan,
			release_cache,
		)
	var broadphase_ready = _aoe_plan_is_ready(plan)
	if not broadphase_ready and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"melee_query_plan_invalid_or_spatial_index_unavailable"
		)
		return result
	if not _aoe_query_enemy_candidates_aabb(
		plan,
		plan.get("ground_aabb", Rect2()),
	):
		return result
	_aoe_collect_half_moon_secondary_candidates(
		_aoe_candidate_scratch,
		result,
		excluded_targets,
		origin_ground_gu,
		direction_index,
		target_plan,
		plan,
		release_geometry,
	)
	if result.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		_aoe_collect_half_moon_secondary_candidates(
			_aoe_candidate_scratch,
			result,
			excluded_targets,
			origin_ground_gu,
			direction_index,
			target_plan,
			plan,
			release_geometry,
		)
	_sort_melee_targets(result, origin_ground_gu, release_geometry)
	return result


func _execute_wild_rush(_direction: Vector2, _skill_level: int) -> bool:
	if not _owned(): return false
	# Compatibility/test entrypoint. Production reaches the same planner through
	# the canonical skill router; input direction and rank cannot alter geometry.
	var target = _select_wild_rush_target()
	if target == null:
		return false
	var plan = _build_wild_rush_path_plan(target)
	var resolved_distance_gu = float(plan.get("resolved_push_distance_gu", 0.0))
	return _apply_wild_rush_displacement(
		target,
		{
			"resolved_push_distance_gu": resolved_distance_gu,
			"displaced": resolved_distance_gu > 0.0,
		},
		plan
	)


func _skill_teleport_destination_is_valid(origin_screen_px: Vector2, destination_ground_gu: Vector2) -> bool:
	if not _owned(): return false
	if not destination_ground_gu.is_finite():
		return false
	var distance_gu = _canonical_screen_px_to_ground_gu(origin_screen_px).distance_to(destination_ground_gu)
	if distance_gu < SKILL_TELEPORT_MIN_DISTANCE_GU or distance_gu > SKILL_TELEPORT_MAX_DISTANCE_GU:
		return false
	return _teleport_destination_is_clear(destination_ground_gu)


func _teleport_destination_is_clear(candidate_ground_gu: Vector2) -> bool:
	if not _owned(): return false
	if not candidate_ground_gu.is_finite() or not _target_spatial_query_ready():
		return false
	var candidate_screen_px = _canonical_ground_gu_to_screen_px(candidate_ground_gu)
	if _geometry.environment_blocks_actor_screen_px(
		_geometry, candidate_screen_px, ArtSpec.PLAYER_COLLISION_RADIUS_PX
	):
		return false
	var player_radius_gu = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
		ArtSpec.PLAYER_COLLISION_RADIUS_PX)
	var query_radius_gu = player_radius_gu + RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
	if not _target_spatial_query_aabb_into(Rect2(
		candidate_ground_gu - Vector2.ONE * query_radius_gu,
		Vector2.ONE * query_radius_gu * 2.0), _target_spatial_query_scratch, false):
		return false
	for enemy: Object in _target_spatial_query_scratch:
		if _canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)).distance_to(candidate_ground_gu) < (
			player_radius_gu + enemy.combat_radius_gu + RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
		):
			return false
	return true


func _find_valid_skill_teleport_position(origin_screen_px: Vector2) -> Vector2:
	if not _owned(): return Vector2.INF
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(origin_screen_px)
	if not origin_ground_gu.is_finite() or not _target_spatial_query_ready():
		return origin_screen_px
	for _attempt in range(SKILL_TELEPORT_MAX_ATTEMPTS):
		var angle = _random.randf_range(0.0, TAU)
		var distance_gu = _random.randf_range(SKILL_TELEPORT_MIN_DISTANCE_GU, SKILL_TELEPORT_MAX_DISTANCE_GU)
		var candidate_ground_gu = origin_ground_gu + Vector2.RIGHT.rotated(angle) * distance_gu
		if _teleport_destination_is_clear(candidate_ground_gu):
			return _canonical_ground_gu_to_screen_px(candidate_ground_gu)
	return origin_screen_px


func _find_valid_random_teleport_position(origin_screen_px: Vector2) -> Vector2:
	if not _owned(): return Vector2.INF
	# Every candidate goes through the same world boundary/obstacle contract as
	# movement and monster spawning.  A scroll can never bypass black borders.
	var origin_ground_gu = _canonical_screen_px_to_ground_gu(
		origin_screen_px
	)
	if not origin_ground_gu.is_finite() or not _target_spatial_query_ready():
		return origin_screen_px
	# Primary MapRandomMove samples the map dimensions, not a radius around
	# the actor. Use the published map's actual GU extent; collision below
	# rejects black borders, walls and occupied cells without biasing to Home.
	var runtime = _geometry.map_data.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2 or int(raw_size[0]) <= 0 or int(raw_size[1]) <= 0:
		return origin_screen_px
	var player_combat_radius_gu = (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
	)
	for _attempt in range(RANDOM_TELEPORT_MAX_ATTEMPTS):
		var candidate_ground_gu = Vector2(
			float(_random.randi_range(0, int(raw_size[0]) - 1)) + 0.5,
			float(_random.randi_range(0, int(raw_size[1]) - 1)) + 0.5,
		)
		var candidate_screen_px = _canonical_ground_gu_to_screen_px(
			candidate_ground_gu
		)
		if _geometry.environment_blocks_actor_screen_px(
			_geometry,
			candidate_screen_px,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		):
			continue
		var occupied = false
		var enemy_query_radius_gu = (
			player_combat_radius_gu + RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
		)
		if not _target_spatial_query_aabb_into(
			Rect2(
				candidate_ground_gu - Vector2.ONE * enemy_query_radius_gu,
				Vector2.ONE * enemy_query_radius_gu * 2.0,
			),
			_target_spatial_query_scratch,
			# PERF-2: existence probe — occupancy is order-insensitive.
			false,
		):
			return origin_screen_px
		for enemy: Object in _target_spatial_query_scratch:
			if GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(_actors.position_screen_px(enemy)),
				candidate_ground_gu
			) < (
				player_combat_radius_gu
				+ enemy.combat_radius_gu
				+ RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
			):
				occupied = true
				break
		if not occupied:
			return candidate_screen_px
	return origin_screen_px


func _hc_lightning_clear(victim: Object, caster_origin: Vector2) -> bool:
	if not _owned(): return false
	return _combat_target_world_clear(victim, caster_origin, false)


func _combat_target_world_clear(victim: Object, caster_origin: Vector2, allow_cache = false) -> bool:
	if not _owned(): return false
	if not _actors.is_runtime_present(player) or player._dead or player.combat_transition_is_active() or current_map_id < 0:
		return false
	if not _actors.is_runtime_present(victim) or not victim.can_receive_damage():
		return false
	if victim.runtime_map_id != current_map_id or _actors.is_queued_for_retirement(victim):
		return false
	if int(_actors.read_meta(victim, "zone_generation", _zone_generation)) != _zone_generation:
		return false
	var a = _canonical_screen_px_to_ground_gu(caster_origin)
	var b = _canonical_screen_px_to_ground_gu(_actors.position_screen_px(victim))
	if not a.is_finite() or not b.is_finite() or not _geometry.is_present():
		return false
	# Cast gates query fresh WORLD geometry; target selection can reuse its cache.
	# The victim provides the same formal map projection injected by GameRoot.
	return victim._world_attack_path_is_clear(a, b, caster_origin, _actors.position_screen_px(victim), allow_cache)


func _hc_skill_preflight(stable_skill_id: String, target_id: int) -> bool:
	if not _owned(): return false
	var configuration = player.current_preflight_action_configuration()
	var definition: Dictionary = configuration.definition_for(stable_skill_id) if configuration != null else _profile.effective_skill_definition(stable_skill_id)
	if _hostile_skill_blocked_by_safe_zone(definition):
		if _presentation != null:
			_presentation.show_error_message("安全区内无法对敌人释放技能")
		return false
	if stable_skill_id != "wizard.lightning":
		return true
	var object: Object = _actors.resolve_runtime_model(target_id) if target_id > 0 else null
	var victim = object
	var clear = _hc_lightning_clear(victim, _actors.position_screen_px(player))
	if not clear and _presentation != null and _clock.now_msec() - _hc_lightning_hint_ms >= 500:
		_hc_lightning_hint_ms = _clock.now_msec()
		_presentation.show_error_message("目标被遮挡或已失效", 1.5)
	return clear


func _action_configuration_identity() -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	return {"world_generation":_zone_generation,"runtime_id":_actors.runtime_actor_id(player) if _actors.is_runtime_present(player) else 0,
		"life_generation":player.combat_epoch if _actors.is_runtime_present(player) else 0}


func feature_publication_scope() -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	return {"world":_world_context.capture_world(), "actor":_action_configuration_identity()}


func feature_world_capacity_bound() -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	_feature_target_bound.sync_world(_world_context.capture_world())
	return _feature_target_bound.snapshot()


func _capture_action_configuration(stable_skill_id: String, melee: Dictionary = {}) -> RefCounted:
	if not _owned(): return null
	stable_skill_id = SkillDataLoaderScript.stable_skill_id(stable_skill_id)
	var definition = _profile.effective_skill_definition(stable_skill_id)
	if definition.is_empty() or not _actors.is_runtime_present(player):
		return null
	var partner: Dictionary = {}
	var partner_rank = 0
	if stable_skill_id in ["taoist.defense", "taoist.magic_defense"]:
		var partner_id = "taoist.magic_defense" if stable_skill_id == "taoist.defense" else "taoist.defense"
		if _profile.is_skill_learned(partner_id):
			partner = _profile.effective_skill_definition(partner_id)
			partner_rank = _profile.effective_skill_level(partner_id)
	var contract = preload("res://scripts/features/contracts/action_config_lease.gd")
	var bundle = _profile.feature_bundle()
	var has_numeric_configuration: bool = not bundle.get("stat_operations", []).is_empty() \
		or not bundle.get("skill_operations", {}).is_empty()
	var primary_policy: String = (contract.ACCEPTED_PRIMARY_STATS if has_numeric_configuration \
		else contract.LEGACY_RELEASE_PRIMARY_STATS)
	var captured = contract.create(
		definition, _profile.effective_skill_level(stable_skill_id), _profile.level, _profile.computed_stats,
		_profile.action_configuration_versions(), _action_configuration_identity(), partner, partner_rank, primary_policy, melee,bundle.get("event_index",{}),_profile._feature_loadout.resource_lease())
	if bool(captured.success): captured.lease.configure_admission(Callable(self,"_reserve_feature_action"))
	return captured.lease if bool(captured.success) else null


func _reserve_feature_action(configuration: RefCounted) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var skill_id: String = configuration.primary_skill_id()
	if not configuration.melee_context().is_empty():
		for candidate: String in configuration.melee_context().definitions:
			if candidate != "hc.skill.warrior.fire_sword" and not configuration.event_bindings_for(candidate).is_empty():
				return {"success":false,"reason":"unproved_melee_feature_producer"}
		# The existing hit-frame owner can consume a previously armed fire charge.
		# Reserve that possible outcome without freezing or changing its body choice.
		skill_id = "warrior.fire_sword"
	var bindings: Array = configuration.event_bindings_for(skill_id)
	if bindings.is_empty(): return {"success":true,"reservation":null}
	var ticket = _reserve_feature_bindings(skill_id,bindings)
	return {"success":ticket != null,"reservation":ticket}


func _reserve_feature_bindings(skill_id: String, bindings: Array) -> RefCounted:
	if not _owned(): return null
	if not _input.gameplay_input_is_enabled(): return null
	var bound = feature_world_capacity_bound()
	if not bool(bound.proved): return null
	var maximum = int(bound.maximum_receivers)
	match SkillDataLoaderScript.stable_skill_id(skill_id):
		"warrior.fire_sword": maximum = mini(maximum,1)
		"wizard.ice_storm": pass
		_: return null # New direct/delayed producer families need their own bound proof.
	if _feature_runtime == null:
		_fault("world_skill_feature_runtime_missing", {})
		return null
	_feature_runtime.require_reservations = true
	# Player increments this existing serial synchronously after acceptance and
	# before any release signal. A fresh ticket cannot be attached to an old label.
	var release_id = "player:%d:action:%d" % [_actors.runtime_actor_id(player),player._combat_action_sequence+1]
	return _feature_runtime.reserve_action(SkillDataLoaderScript.entity_skill_id(skill_id),bindings,maximum,release_id,int(bound.maximum_receivers))


func _capture_melee_configuration() -> RefCounted:
	if not _owned(): return null
	var melee = {"definitions":{},"ranks":{},"learned_skills":{},"toggles":{
		"warrior.fire_sword":player.fire_sword_enabled,"warrior.half_moon":player.half_moon_enabled,
		"warrior.thrusting":player.thrusting_enabled}}
	for id: String in ["warrior.basic_swordsmanship","warrior.slaying_swordsmanship","warrior.thrusting",
		"warrior.half_moon","warrior.fire_sword","taoist.spiritual_warfare"]:
		var entity_id = SkillDataLoaderScript.entity_skill_id(id)
		melee.definitions[entity_id] = _profile.effective_skill_definition(id)
		melee.ranks[entity_id] = _profile.effective_skill_level(id)
		if _profile.is_skill_learned(id):
			melee.learned_skills[entity_id] = melee.ranks[entity_id]
	return _capture_action_configuration("warrior.basic_swordsmanship", melee)


func _canonical_action_primary_stats(configuration: RefCounted) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var contract = preload("res://scripts/features/contracts/action_config_lease.gd")
	# Original release-time combat additions retain their original owner when
	# no numeric extension participated at acceptance. This is an explicit
	# policy, not an empty-value guess or a second calculator.
	if configuration == null or configuration.primary_stat_policy() == contract.LEGACY_RELEASE_PRIMARY_STATS:
		return _profile.computed_stats
	return configuration.primary_stats()


func _begin_feature_damage_batch(skill_id: String, release_id: String, configuration: RefCounted = null) -> RefCounted:
	if not _owned(): return null
	var bindings: Array = []
	if configuration != null:
		bindings = configuration.event_bindings_for(skill_id)
	else:
		var index: Dictionary = _profile.feature_bundle().get("event_index",{})
		if index.is_empty(): return null
		bindings = index.get("damage_committed:" + SkillDataLoaderScript.entity_skill_id(skill_id),[])
	if bindings.is_empty(): return null
	var entity_id = SkillDataLoaderScript.entity_skill_id(skill_id)
	var reservation: RefCounted = configuration.effect_reservation() if configuration != null else null
	if configuration != null and reservation == null:
		push_error("Feature producer has no accepted capacity reservation"); return null
	if _feature_runtime == null:
		_fault("world_skill_feature_runtime_missing", {})
		return null
	if configuration == null and _feature_runtime.require_reservations:
		push_error("Unticketed feature producer cannot enter an admitted action runtime"); return null
	var created = _feature_runtime.create_damage_batch(_world_context,release_id,entity_id,
		bindings,{"profile_id":_profile.active_profile_id},_time_domains.simulation_usec(),reservation,
		configuration.resource_lease() if configuration != null else _profile._feature_loadout.resource_lease(),
		reservation.chain_context(release_id) if reservation!=null else {})
	if not bool(created.success):
		push_error("Feature damage batch rejected: " + str(created.reason)); return null
	var batch: RefCounted = created.batch
	if not batch.begin_base_scope(): return null
	return batch


func _finish_feature_damage_batch(batch: RefCounted) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	if batch == null: return {"success":true,"outcome":"not_applicable","reason":""}
	if not batch.finish_base_scope() or not batch.errors.is_empty():
		batch.finish_production()
		push_error("Feature damage fact rejected: " + str(batch.errors))
		return {"success":false,"outcome":"rejected","reason":"feature_batch_rejected"}
	var ticket: RefCounted=batch.reservation()
	if _feature_runtime==null or (ticket!=null and not ticket.batch_owner_is_current()):
		batch.finish_production()
		return {"success":false,"outcome":"owner_retired","reason":"feature_batch_owner_retired"}
	# A valid miss/empty release owns no post-hit work. Nonempty rejected
	# transfers remain intact and must be visible as failures, never successes.
	if batch.pending_fact_count() == 0:
		batch.finish_production()
		return {"success":true,"outcome":"empty","reason":""}
	var transferred: bool=_feature_runtime.submit_batch(batch)
	if not transferred:
		push_error("Feature damage batch submission rejected: " + str(_feature_runtime.errors))
	batch.finish_production()
	return {"success":transferred,"outcome":"transferred" if transferred else "rejected",
		"reason":"" if transferred else "feature_batch_submission_rejected"}


func _execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array,
	source: Object, resources: RefCounted) -> Dictionary:
	if not _owned(): return {"success":false,"accepted":false,"valid":false,"reason":"world_skill_owner_rejected"}
	var child: RefCounted=preload("res://scripts/features/contracts/child_action_lease.gd").from_request(request)
	if child==null or ticket==null or ticket.get_script()!=preload("res://scripts/features/contracts/effect_reservation.gd") \
		or _feature_runtime==null or not ticket.belongs_to(_feature_runtime) \
		or not ticket.authorizes_child_request(request):
		return {"success":false,"reason":"child_owner_rejected"}
	var release_id: String=ticket.branch()
	var lineage: Dictionary=ticket.chain_context(release_id)
	if lineage.is_empty() or lineage!=child.chain_context(): return {"success":false,"reason":"child_lineage_rejected"}
	var context: Dictionary={"release_id":release_id,"runtime_map_id":current_map_id,
		"screen_to_ground_position_px":Callable(self,"_canonical_screen_px_to_ground_gu"),
		"ground_gu_to_screen_position_px":Callable(self,"_canonical_ground_gu_to_screen_px")}
	var plan: Dictionary=_planner.build_canonical_plan(request,context)
	if not bool(plan.rejection.accepted): return {"success":false,"reason":plan.rejection.reason}
	var snapshot: Dictionary=plan.canonical_snapshot
	var cache: Dictionary={}
	var origin: Vector2=snapshot.center_ground_gu
	var query: Dictionary=_aoe_spell_query_plan(plan.skill_id,[],plan.gameplay_actions[0],{},snapshot,origin,cache)
	if not _aoe_plan_is_ready(query) or not _aoe_query_enemy_candidates_aabb(query,query.get("ground_aabb",Rect2()),false):
		return {"success":false,"reason":"child_query_rejected"}
	var targets: Array=[]; var ids: Array[int]=[]
	for enemy: Object in _aoe_candidate_scratch:
		if enemy.current_hp>0 and not _actors.is_queued_for_retirement(enemy) and _aoe_validated_snapshot_intersects(query,enemy):
			_aoe_insert_by_instance_id(targets,ids,enemy)
	var made: Dictionary=_feature_runtime.create_damage_batch(_world_context,
		release_id,plan.skill_id,bindings,plan.historical_credit,_time_domains.simulation_usec(),ticket,resources,
		plan.chain_context,"child",str(plan.chain_context.root_skill_id))
	if not made.success: return {"success":false,"reason":made.reason}
	var batch: RefCounted=made.batch
	if not batch.begin_base_scope(): batch.finish_production(); return {"success":false,"reason":"child_scope_rejected"}
	var rng=RandomNumberGenerator.new(); rng.seed=int(request.seed)
	var succeeded=true
	for enemy: Object in targets:
		if not _actors.is_runtime_present(enemy) or enemy.current_hp<=0 or _actors.is_queued_for_retirement(enemy): continue
		var hit: Dictionary=_combat.apply_feature_child_damage(enemy,int(plan.gameplay_actions[0].raw_power),
			source,rng,plan.historical_credit,batch)
		if not hit.success: succeeded=false
	var transfer: Dictionary=_finish_feature_damage_batch(batch)
	var delivered: bool=succeeded and batch.errors.is_empty() and bool(transfer.success)
	return {"success":delivered,"reason":"" if delivered else
		(str(transfer.reason) if not transfer.success else "child_commit_rejected"),"batch_outcome":transfer.outcome}


func _ordinary_attack_owner_matches(
	press_token: int, touch_id: int, source: StringName
) -> bool:
	if not _owned(): return false
	var raw_entry: Variant = _active_mobile_attack_tokens.get(press_token)
	if not raw_entry is Dictionary:
		return false
	var entry = raw_entry as Dictionary
	return (
		int(entry.get("touch_id", -999)) == touch_id
		and StringName(entry.get("source", &"")) == source
	)


func _process_ordinary_attack_input(attack_action_lifecycle: Dictionary) -> void:
	if not _owned(): return
	_queued_mobile_attack_tickets.clear()
	if not _input.gameplay_input_is_enabled():
		_cancel_all_mobile_attack_inputs(true)
		return
	_reconcile_ordinary_attack_button_owners()
	if bool(attack_action_lifecycle.get("started", false)):
		_submit_mobile_attack_ticket(_allocate_synthetic_attack_token())
	elif _mobile_attack_held or bool(attack_action_lifecycle.get("active", false)):
		_try_ordinary_attack_intent(&"live_hold")


func _reconcile_ordinary_attack_button_owners() -> void:
	if not _owned(): return
	# Reconcile two software ledgers; this is NOT an inactivity/hold timer.
	# No inference is made from the absence of DRAG events.
	if not _input.has_button_lifecycle_owner():
		return
	for raw_token: Variant in _active_mobile_attack_tokens.keys():
		var token = int(raw_token)
		var raw_entry: Variant = _active_mobile_attack_tokens.get(token)
		if not raw_entry is Dictionary:
			# Legacy bool entries cannot describe a current verified pointer.
			_active_mobile_attack_tokens.erase(token)
			continue
		var entry = raw_entry as Dictionary
		var source = StringName(entry.get("source", &""))
		if source not in [&"touch", &"mouse", &"ui_accept"]:
			continue
		var touch_id = int(entry.get("touch_id", -999))
		if not bool(_input.button_owns_lifecycle_input(token, touch_id, source)):
			_on_mobile_attack_input_cancelled(
				token, touch_id, source, &"button_owner_revoked"
			)
	_refresh_mobile_attack_held()


func _try_ordinary_attack_intent(origin: StringName) -> bool:
	if not _owned(): return false
	if not _input.gameplay_input_is_enabled():
		return false
	# Reject before target selection/geometry. Never adjust gameplay timers.
	if not player.can_start_attack():
		return false
	var accepted = _execution.request_mobile_attack()
	if accepted:
		# This means action STARTED; it does NOT mean damage has been committed.
		_record_attack_action_diagnostic(&"attack_action_started", origin)
	return accepted
