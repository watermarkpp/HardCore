extends Node2D

const WorldSkillRuntimeScript := preload("res://scripts/gameplay/world/world_skill_full_model.gd")
const LegacyWorldSkillPortsScript := preload("res://scripts/gameplay/world/world_skill_legacy_full_ports.gd")
var _world_skill_domain: RefCounted

func _world_skill_runtime() -> RefCounted:
	if _world_skill_domain == null:
		var ports := LegacyWorldSkillPortsScript.new(self)
		_world_skill_domain = WorldSkillRuntimeScript.new()
		var configured: bool = _world_skill_domain.configure_full_ports(ports.full_bindings(_world_skill_domain))
		assert(configured, "full WorldSkill required legacy ports unavailable")
	return _world_skill_domain


const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
const PASSIVE_WAKE_BUDGET_CATEGORY := "monster_passive_wakeup"
const HCDecisionBudget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const WorldContext := preload("res://scripts/layers/runtime/execution/world_context.gd")
const TimeDomains := preload("res://scripts/layers/runtime/execution/time_domains.gd")
var _death_budget_category := "death_work:%d" % get_instance_id()
var _world_context := WorldContext.new()
var _time_domains := TimeDomains.new()
var _feature_effect_runtime: RefCounted

const BICH_RUNTIME_MAP_ID := 910001
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")
const ORC_TOMB_F3_RUNTIME_MAP_ID := 911003
const INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC := 60000
## perf-smoothness-r1 Phase C (audit 20260918): the loading window owns ONE
## prewarm entry with ONE absolute deadline. Non-critical prewarm stops when
## the budget is gone; the fire-wall first-cast workset always completes and
## is pinned. Combat never synchronously loads/decodes textures: misses are
## queued and drained through the bounded threaded warm-up channel below.
const LOADING_PREWARM_BUDGET_USEC := 1500000
const LOADING_RENDER_WARM_BUDGET_USEC := 1000000
const FRAME_TEXTURE_WARM_PER_FRAME := 2
const FRAME_TEXTURE_WARM_MAX_IN_FLIGHT := 4
const TownMusicControllerScript := preload("res://scripts/town_music_controller.gd")
const AudioRuntimeServiceScript := preload("res://scripts/audio_runtime_service.gd")
const LevelUpEffectScript := preload("res://scripts/ui_level_up_preview.gd")
const RelicProcEffectScript := preload("res://scripts/ui_relic_proc_effect.gd")
const LootVisualEffectScript := preload("res://scripts/loot_visual_effect.gd")

var _town_music_controller: Node
var _audio_runtime_service: Node
var _player_level_up_effect: Node2D
var _player_relic_proc_effect: Node2D

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
const EquipmentGrantedSkills := preload("res://scripts/equipment_granted_skill_rules.gd")
const UIErrorFeedbackScript := preload("res://scripts/ui_error_feedback.gd")
const UIPlayerNoticeScript := preload("res://scripts/ui_player_notice.gd")
const CombatResolutionRulesScript := preload("res://scripts/combat_resolution_rules.gd")
const MapCoordinateMapperScript := preload("res://scripts/map_coordinate_mapper.gd")
const GothicBichCampBuilderScript := preload("res://scripts/layers/presentation/gothic_bich_camp_builder.gd")
const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")
const MapTeleportRuntimePolicyScript := preload(
	"res://scripts/layers/runtime/map_teleport_runtime_policy.gd"
)
const MapPortalRuntimeServiceScript := preload("res://scripts/map_editor/map_portal_runtime_service.gd")
const MapPortalTravelGuardScript := preload("res://scripts/map_editor/map_portal_travel_guard.gd")
const MapDiamondCameraConstraintScript := preload("res://scripts/map_editor/map_diamond_camera_constraint_service.gd")
const WorldCameraFollowScript := preload("res://scripts/world_camera_follow.gd")
const MapRuntimeCollisionGeometryScript := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)
const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)
const MonsterVisualStreamingCoordinatorScript := preload(
	"res://scripts/monster_visual_streaming_coordinator.gd"
)
const MonsterSourceFramesScript := preload("res://scripts/monster_source_frames.gd")
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")
const SystemMenuPanelScript := preload("res://scripts/system_menu_panel.gd")
const SkillLoadoutRulesScript := preload("res://scripts/skill_loadout_rules.gd")
const SkillInputPolicyScript := preload("res://scripts/skill_input_policy.gd")
const SkillRuntimeRouterScript := preload("res://scripts/skills/skill_runtime_router.gd")
const SkillExecutionPlanScript := preload(
	"res://scripts/skills/skill_execution_plan.gd"
)
const SkillExecutionPlanContractScript := preload(
	"res://scripts/skills/skill_execution_plan_contract.gd"
)
const SkillCastRequestScript := preload("res://scripts/skills/skill_cast_request.gd")
const SkillDataLoaderScript := preload("res://scripts/skills/skill_data_loader.gd")
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
const WarriorMeleeVisualEffectScript := preload("res://scripts/warrior_melee_visual_effect.gd")
const CombatRuntimeServiceScript := preload("res://scripts/layers/runtime/combat_runtime_service.gd")
const CombatDiagnosticLogScript := preload("res://scripts/layers/runtime/combat_diagnostic_log.gd")
const SkillFootprintDiagnosticLogScript := preload(
	"res://scripts/layers/runtime/skill_footprint_diagnostic_log.gd"
)
const CasterSkillRuntimeScript := preload("res://scripts/caster_skill_runtime.gd")
var _initial_code_retention: Dictionary = {}
const SkillRuntimeClassificationScript := preload("res://scripts/skills/skill_runtime_classification.gd")
const FireWallFieldControllerScript := preload(
	"res://scripts/fire_wall_field_controller.gd"
)
const CasterSpellGeometryScript := preload("res://scripts/skills/caster_spell_geometry.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const SkillFootprintQueryPlanScript := preload(
	"res://scripts/skills/skill_footprint_query_plan.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const PersistentGroundEffectManagerScript := preload(
	"res://scripts/persistent_ground_effect_manager.gd"
)
const LootPickupRuntimeManagerScript := preload(
	"res://scripts/loot_pickup_runtime_manager.gd"
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
const DeviceLabRuntimeScript := preload("res://scripts/device_lab_runtime.gd")
const MonsterRespawnPolicyScript := preload(
	"res://scripts/monster_respawn_policy.gd"
)
const MonsterTerrainNavigationPolicyScript := preload(
	"res://scripts/monster_terrain_navigation_policy.gd"
)
const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")
const DEFAULT_NORMAL_RESPAWN_SECONDS := MonsterRespawnPolicyScript.BEGINNER_OUTDOOR_SECONDS
const DEFAULT_BOSS_RESPAWN_SECONDS := MonsterRespawnPolicyScript.BOSS_SECONDS
const MONSTER_PREFETCH_TIMEOUT_MSEC := 8000
const CANONICAL_MATERIAL_ITEMS := PlayerState.CANONICAL_MATERIAL_ITEMS
const SKILL_PRODUCTION_ADAPTER_CONTRACT := "skills.production_adaptation.hardcore.v1"
const ATTACK_LOCK_CONTRACT := "combat.attack_lock.euclidean_gu.v2"
const ATTACK_LOCK_RANGE_GU := 10.0
const MELEE_LOCK_IMPACT_POLICY_ID := "combat.melee_lock.facing_priority_nonexclusive.v1"
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
const PLAYER_STEALTH_ALPHA := 0.60
const ATTACK_INPUT_TICKET_CONTRACT_ID := "combat.input.ordinary_attack.live_owner_no_debt.v2"
const MAX_BUFFERED_MOBILE_ATTACK_TICKETS := 0
const SKILL_INPUT_TICKET_CONTRACT_ID := (
	"combat.input.skill_ticket.cooldown_coalesce_hold_repeat.v2"
)
const SKILL_HOLD_REPEAT_THRESHOLD_MS := 300
const MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS := 0.10
const MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS := 0.60
const SAFE_ZONE_ACTOR_PADDING_GU := 0.05
const SAFE_ZONE_ENFORCEMENT_INTERVAL_SECONDS := 0.10
const BOSS_SURROUNDED_NEIGHBOR_RADIUS_GU := 1.65
const ACTOR_LANDING_CLEARANCE_GU := 0.25
const ENEMY_LANDING_CLEARANCE_GU := 0.125
const SAFE_RING_TELEPORT_DISTANCES_GU := [
	5.625,
	4.5,
	3.375,
	2.25,
	1.125,
]
const RANDOM_TELEPORT_MAX_ATTEMPTS := 256
const SKILL_TELEPORT_MAX_ATTEMPTS := 96
const SKILL_TELEPORT_MIN_DISTANCE_GU := 3.0
const SKILL_TELEPORT_MAX_DISTANCE_GU := 16.25
const RANDOM_TELEPORT_ACTOR_CLEARANCE_GU := 0.25
const CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU := 2.0
const CANONICAL_SUMMON_TELEPORT_SEARCH_RADIUS_GU := 8
const CANONICAL_SUMMON_ACTOR_CLEARANCE_GU := 0.05
const DEATH_DROP_WORK_BUDGET_USEC := 1200
const DEATH_JOBS_MAX_PER_FRAME := 4
const DROP_NODES_MAX_PER_FRAME := 1
const LOOT_FALLBACK_RADII := [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]
const DEATH_QUEUE_MAX_RETRIES := 3
const DEATH_QUEUE_RETRY_DELAY_MSEC := 100
const DEATH_TERMINAL_LEDGER_MAX := 64
const DEATH_STATE_QUEUED := "QUEUED"
const DEATH_STATE_PERSISTING := "PERSISTING"
const WorldClockDeltaScript := preload("res://scripts/world_clock_delta.gd")
const DEATH_STATE_SETTLING := "SETTLING"
const DEATH_STATE_PLANNED := "PLANNED"
const DEATH_STATE_MATERIALIZING := "MATERIALIZING"
const DEATH_STATE_COMMITTED := "COMMITTED"
const DEATH_STATE_RETRY := "RETRY"
const DEATH_STATE_FAILED := "FAILED"
const DEATH_STATE_CANCELLED := "CANCELLED"
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
const SKILL_VISUAL_GEOMETRY_DEBUG_SETTING := (
	"debug/skill_visual_geometry/enabled"
)

var player: PlayerCharacter
var _world_camera: Camera2D
var _world_camera_presented_center := Vector2.INF
var _world_camera_follow_map_id := -1
var hud: GameHUD
var background: WorldBackground
var current_zone := ""
var current_map_id := -1
var current_map_data: Dictionary = {}
var _zone_generation := 0
var _respawn_wakeups: Dictionary = {}
var _ready_world_map_id := -1
var _ready_world_zone_generation := -1
# Own exactly one genuine safe-home publication after a failed world swap.
var _map_failure_recovery_active := false
var _map_transition_environment_replaced := false
var _monster_terrain_navigation_context: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var locked_target: EnemyActor
var manual_target_lock := false
var magic_locked_target: EnemyActor
var manual_magic_target_lock := false
## Target presentation keeps only the previous displayed actor.  Enemy group
## enumeration is not needed to update one changed highlight; the WeakRef also
## lets map/death teardown clear a stale presentation without retaining it.
var _presented_target_instance_id := 0
var _presented_target_ref: WeakRef
## Presentation/selection follows the latest combat action. Caster
## professions still own an independent magic lock, but an empty primary slot
## temporarily presents and consumes the physical lock just like a warrior.
var _active_target_domain_magic := true
var auto_target_enabled := true
var _mobile_attack_held := false
var _queued_mobile_attack_tickets: Array[int] = []
var _active_mobile_attack_tokens: Dictionary = {}
var _legacy_mobile_attack_token := 0
var _next_synthetic_attack_token := -1
var _active_skill_inputs: Dictionary = {}
var _next_skill_input_sequence := 1
var _skill_input_retry_remaining := 0.0
var _keyboard_bound_skill_token := 0
const ATTACK_ACTION_LIFECYCLE_CONTRACT_ID := "input.attack.fresh_down.v1"
const ATTACK_ACTION_DIAGNOSTIC_LIMIT := 256
var _attack_action_press_owned := false
var _attack_action_neutral_observed := true
var _attack_action_ignored_pressed_recorded := false
var _attack_action_lifecycle_epoch := 0
var _attack_action_diagnostic_serial := 0
var _attack_action_diagnostic_events: Array[Dictionary] = []
var _magic_shield_auto_enabled := false
var _magic_shield_auto_retry_remaining := 0.0
var _queued_mobile_attacks: int:
	get:
		return _queued_mobile_attack_tickets.size()
var _warrior_hud_timer := 0.0
var _system_menu_layer: CanvasLayer
var _system_menu_panel: Control
## The system menu is the only owner of the pause it creates.  Keep this
## explicit so an unrelated pause source is never released by a panel hide.
var _system_menu_pause_owned := false
var _movement_target_refresh_remaining := 0.0
var _bich_camp_layout: Dictionary = {}
var _active_safe_zones: Array = []
var _safe_zone_context: Dictionary = {
	"contract_id": WorldSpatialRulesScript.SAFE_ZONE_CONTEXT_CONTRACT_ID,
	"map_id": -1,
	"revision": 0,
	"generation": 0,
	"valid": true,
	"failure_reason": "",
	"zones": [],
	"aabb_ground_gu": Rect2(),
}
var _safe_zone_revision := 0
var _safe_zone_candidate_scratch: Array[EnemyActor] = []
var _safe_zone_query_scratch: Array[EnemyActor] = []
var _safe_zone_candidate_stamp_serial := 0
var _player_safe_zone_cache: Dictionary = {
	"player_instance_id": 0,
	"map_id": -1,
	"revision": -1,
	"generation": -1,
	"ground_position_gu": Vector2.INF,
	"inside": false,
	"valid": false,
}
var _runtime_spawn_serial := 0
var _collecting_staged_actor_plan := false
var _staged_actor_source_index := 0
var _staged_actor_spawn_failure_reason := ""
var _active_enemy_cache: Dictionary = {}
## Projection of real EnemyActor target edges; no scan or independent timer.
var _player_combat_enemy_ids: Dictionary = {}
var _active_boss_cache: Dictionary = {}
var _safe_zone_enforcement_remaining := 0.0
var _combat_spatial_index: RuntimeCombatSpatialIndexScript
var _passive_wake_dirty := true
var _passive_wake_query_pending := true
var _passive_wake_candidates: Array[EnemyActor] = []
var _passive_wake_cursor := 0
var _passive_wake_max_extent_gu := 0.0
var _passive_wake_extent_map_id := -1
var _passive_wake_extent_generation := -1
var _passive_wake_pump_epoch := -1
var _passive_wake_candidates_used := 0
var _passive_wake_emitters: Dictionary = {}
var _passive_wake_emitter_queue: Array[int] = []
var _passive_wake_active_emitter_id := 0
## R1-B: the shared target-query service fronts every special-geometry
## broadphase query (d1d015ba pattern). The service is stateless between
## queries; this instance is rebuilt whenever the map id or the index
## instance changes so the runtime-map binding can never go stale.
var _combat_target_query_service: RefCounted
var _combat_target_query_service_map_id := -2
var _combat_target_query_service_index: RuntimeCombatSpatialIndexScript
## Shared caller-owned scratch for player-facing enemy broadphase queries.  All
## production consumers filter the current map generation after the index
## query; no SceneTree group fallback is permitted when this contract is not
## ready.
var _target_spatial_query_scratch: Array[EnemyActor] = []
var _aoe_candidate_scratch: Array[EnemyActor] = []
var _aoe_target_scratch: Array[EnemyActor] = []
var _aoe_distance_scratch: Array[float] = []
var _aoe_id_scratch: Array[int] = []
var _direct_spell_target_stats_scratch: Dictionary = {}
var _aoe_cell_stamp := 0
var _ground_effect_manager: PersistentGroundEffectManagerScript
var _loot_pickup_runtime_manager: LootPickupRuntimeManagerScript
## FREEZE-P0.1: fail-closed canonical projection diagnostics.
var missing_projection_rejection_count := 0
var projection_rejection_reason := &""
## FREEZE-P0.2R: explicit dev/reference audit context. When true, the formal
## implementation gate is bypassed and reference (authored source/centered)
## projections are used - allowed ONLY for migration tools, import/reference
## audits and test/dev preview, never for normal gameplay.
var reference_audit_mode := false
## R3X-2: an explicit test-only escape hatch for the legacy group authority.
## PlayerState.test_mode is intentionally not consulted here: ordinary tests
## must exercise the mapped spatial path and fail closed when it is absent.
var _aoe_reference_fallback_test_enabled := false
## FREEZE-P0.2R: projection profiles contain closures and must be reused during
## actor/location updates. Formal profiles also retain the exact runtime
## Dictionary that their closures captured, so a bridge cache invalidation can
## discard only the stale map profile without a cross-script generation API.
var _projection_profile_cache: Dictionary = {}
var _projection_profile_cache_audit_mode := false
var _projection_profile_runtime_identity_cache: Dictionary = {}
var _ground_effect_runtime_serial := 0
var _portal_guard_state := MapPortalTravelGuardScript.new_state()
var _active_portal_claim_id := ""
var _active_portal_claim_transition_serial := -1
var _map_transition_in_progress := false
var _map_transition_serial := 0
var _pending_main_pet_arrivals: Array[SummonActor] = []
var _pending_main_pet_retry_tile := Vector2i.ZERO
var _pending_main_pet_retry_tile_valid := false
# Q0-B test hook (inert outside test_mode): forces _resolve_bich_home() to
# return invalid so safe-logout failure control flow can be reproduced.
var _test_force_home_failure := false
# Q0-B.1: injectable safe-logout/home failure reporter. Production default
# emits push_error; tests may replace it (test_mode only) with a capture
# callable so expected failures never write engine-log ERROR lines.
var _safe_logout_error_reporter: Callable = Callable(
	self, "_report_safe_logout_error_production"
)
var _active_map_transition_id := ""
# P1-A: map transitions hold the gameplay input lock
const INPUT_LOCK_MAP_TRANSITION_LOCAL := INPUT_LOCK_MAP_TRANSITION
var _monster_prefetch_enabled := true
var _last_monster_prefetch_status: Dictionary = {}
var _streaming_coordinator: MonsterVisualStreamingCoordinatorScript
var _combat_runtime: Node = CombatRuntimeServiceScript.new()
var _canonical_cast_serial := 0
var _skill_footprint_release_serial := 0
var _canonical_fire_charge_expires_ms := 0
var _skill_cast_target: EnemyActor
var _selected_friendly_instance_id := 0
var _ongoing_heals: Array[Dictionary] = []
var _stealth_alpha_restore: Dictionary = {}
var _last_taoist_buff_hint_text := ""
var _melee_diagnostic_serial := 0
var _pending_melee_diagnostic: Dictionary = {}
var _pending_enemy_deaths: Array[Dictionary] = []
var _prepared_enemy_death_settlement: Dictionary = {}
var _enemy_death_flush_queued := false
var _enemy_death_pipeline_running := false
var _enemy_death_target_refresh_pending := false
var _enemy_death_sequence := 0
var _enemy_death_terminal_jobs: Array[Dictionary] = []
var _enemy_death_terminal_total_count := 0
var _last_death_logout_failure: Dictionary = {}
var _death_settled_jobs_last_batch := 0
var _death_drop_work_budget_usec_override := -1
var _last_drop_node_frame := -2
var _death_jobs_max_per_frame_override := -1
var _drop_nodes_max_per_frame_override := -1
var _death_roll_quantum_slicing_enabled := bool(
	ProjectSettings.get_setting(
		"hardcore/performance/death_drop_slicing",
		true,
	)
)
var _death_optional_pump_frame := -1
var _test_force_loot_materialization_failure_count := 0
var _pending_loot_collections: Array = []
var _prepared_loot_collection: Dictionary = {}
## FRAME-STALL probe: fires once per session on the first >250ms wall-clock
## frame, but only after loading has ended (armed post-baseline), so bootstrap
## spikes cannot consume it. Counters are facts only: absence of growth means
## no tracked CPU cache grew - engine-side costs (render/driver/allocator) are
## NOT observable through these counters and must not be inferred from them.
var _first_long_frame_diagnosed := false
var _first_combat_probe_armed := false
## Session identity header (perf-smoothness-r1 Phase A): printed once per
## process at the first loading-window end so every captured log discloses
## what ran and where. Engine timing parameters are included because the
## process-delta clamp they define was itself a measurement defect.
static var _session_header_printed := false
## AOE first-engagement window (perf-smoothness-r1 Phase A): the cast/field/
## tick/death milestones and real frame intervals live in AoeEngagementWindow;
## GameRoot only forwards events. Replaces the retired 12-delta probe whose
## window could never cover the actual engagement and whose samples were
## clamped deltas.
var _loot_collection_flush_queued := false
## Legacy loot candidates are rejected unless a focused test explicitly opts
## into the old fixture shape. Formal pickups always carry map/generation
## metadata from LootPickupRuntimeManager registration.
var _loot_legacy_reference_fallback_test_enabled := false
var _loot_collection_origin_rejection_count := 0
var _active_physical_hit_diagnostics: Array[Dictionary] = []
var _world_bootstrap_in_progress := false
var _player_input_enabled := false
var _death_experience_penalty_applied := false
var _death_event_serial := 0
var _active_death_id := ""
var _death_revival_request_in_flight := false
var _world_bootstrap_coordinator := WorldBootstrapCoordinator.new()
var _gameplay_input_locks: Dictionary = {}
var _device_lab_runtime: DeviceLabRuntimeScript
## Debug-only lifecycle markers for the character-hall -> world handoff.
## GameRoot._init() is the earliest hook available in this script; scene
## resource loading/instantiation before that hook remains outside this
## profile and is called out explicitly in the emitted record.
var _loading_handoff_init_usec := 0
var _loading_handoff_enter_tree_usec := 0


func _clear_aoe_query_scratch() -> void:
	_aoe_candidate_scratch.clear()
	_aoe_target_scratch.clear()
	_aoe_distance_scratch.clear()
	_aoe_id_scratch.clear()
	_aoe_cell_stamp = 0


func _begin_safe_zone_context(runtime_map_id: int) -> void:
	_safe_zone_revision += 1
	_safe_zone_context = {
		"contract_id": WorldSpatialRulesScript.SAFE_ZONE_CONTEXT_CONTRACT_ID,
		"map_id": runtime_map_id,
		"revision": _safe_zone_revision,
		"generation": _zone_generation,
		"valid": true,
		"failure_reason": "",
		"zones": [],
		"aabb_ground_gu": Rect2(),
	}
	_active_safe_zones = _safe_zone_context["zones"]
	_safe_zone_candidate_scratch.clear()
	_safe_zone_query_scratch.clear()
	_safe_zone_candidate_stamp_serial = 0
	_invalidate_player_safe_zone_cache()


func _compile_active_safe_zones(raw_zones: Variant) -> void:
	_safe_zone_context = WorldSpatialRulesScript.compile_safe_zone_context(
		current_map_id,
		_safe_zone_revision,
		_zone_generation,
		raw_zones,
	)
	_active_safe_zones = _safe_zone_context.get("zones", []) as Array
	if not bool(_safe_zone_context.get("valid", false)):
		# Invalid formal authored geometry is a map-data error. Keep the active
		# set empty and let all safe-zone consumers fail closed; never reinterpret
		# a malformed polygon as a circle or infer a shape from screen bounds.
		_active_safe_zones.clear()
		_safe_zone_context["zones"] = _active_safe_zones
	_invalidate_player_safe_zone_cache()


func _invalidate_player_safe_zone_cache() -> void:
	_world_skill_runtime()._invalidate_player_safe_zone_cache()


func _refresh_player_safe_zone_cache(force := false) -> bool:
	return _world_skill_runtime()._refresh_player_safe_zone_cache(force)


func _player_inside_active_safe_zone() -> bool:
	return _world_skill_runtime()._player_inside_active_safe_zone()


func _set_player_world_position(position_px: Vector2, reset_camera_follow := true) -> void:
	if not is_instance_valid(player):
		return
	player.global_position = position_px
	if reset_camera_follow:
		_world_camera_presented_center = Vector2.INF
	_refresh_player_safe_zone_cache(true)
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.player_position_changed(position_px)


func _safe_zone_runtime_zones() -> Array:
	return _active_safe_zones


func _safe_zone_context_is_valid() -> bool:
	return bool(_safe_zone_context.get("valid", false))


func safe_zone_runtime_context() -> Dictionary:
	return _safe_zone_context.duplicate(true)


## R3X-2: the broadphase is the only production candidate source for player
## hostile target resolution.  Group enumeration remains available solely for
## explicit reference/test callers so parity fixtures can exercise the old
## authority without creating a gameplay fallback.
func set_aoe_reference_fallback_for_test(enabled: bool) -> void:
	if not OS.is_debug_build():
		_aoe_reference_fallback_test_enabled = false
		return
	_aoe_reference_fallback_test_enabled = enabled


func _aoe_reference_fallback_allowed() -> bool:
	return _world_skill_runtime()._aoe_reference_fallback_allowed()


func _aoe_reference_enemy_nodes_into(output: Array[EnemyActor]) -> bool:
	return _world_skill_runtime()._aoe_reference_enemy_nodes_into(output)


func _target_spatial_query_ready() -> bool:
	return _world_skill_runtime()._target_spatial_query_ready()


func _target_spatial_enemy_is_current(enemy: EnemyActor) -> bool:
	return _world_skill_runtime()._target_spatial_enemy_is_current(enemy)


func _target_query_service() -> CombatTargetQueryService:
	return _world_skill_runtime()._target_query_service()


## PERF-1: one allocation-conscious service call for the special-geometry
## skills. The aabb pass-through keeps each skill's canonical gate (melee
## footprint/sector predicates, wizard snapshot gate) as the exact authority.
## The service fast path delegates to the index caller-owned node query
## (query-stamp dedup, inline live filter), so with epsilon 0 the candidate
## set is exactly the one the legacy direct node queries produced and the
## hot path allocates no request Dictionary and no candidate records.
func _service_envelope_into(
	bounds_ground_gu: Rect2,
	output: Array[EnemyActor],
	stable_order: bool = true,
) -> bool:
	return _world_skill_runtime()._service_envelope_into(bounds_ground_gu, output, stable_order)


func _target_spatial_query_aabb_into(
	bounds_ground_gu: Rect2,
	output: Array[EnemyActor],
	stable_order: bool = true,
) -> bool:
	return _world_skill_runtime()._target_spatial_query_aabb_into(bounds_ground_gu, output, stable_order)


func _target_spatial_query_segment_into(
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float,
	output: Array[EnemyActor],
	stable_order: bool = true,
) -> bool:
	return _world_skill_runtime()._target_spatial_query_segment_into(start_ground_gu, end_ground_gu, expansion_gu, output, stable_order)


func _aoe_build_query_plan(
	skill_id: String,
	release_id: String,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary,
	release_cache: Dictionary,
) -> Dictionary:
	return _world_skill_runtime()._aoe_build_query_plan(skill_id, release_id, snapshot, validation_context, options, release_cache)


func _aoe_plan_snapshot(plan: Dictionary) -> Dictionary:
	return _world_skill_runtime()._aoe_plan_snapshot(plan)


func _aoe_plan_is_ready(plan: Dictionary) -> bool:
	return _world_skill_runtime()._aoe_plan_is_ready(plan)


func _aoe_record_query_rejection(reason: String) -> void:
	_world_skill_runtime()._aoe_record_query_rejection(reason)


func _aoe_query_enemy_candidates_aabb(
	plan: Dictionary,
	bounds_ground_gu: Rect2,
	allow_reference_fallback := true,
) -> bool:
	return _world_skill_runtime()._aoe_query_enemy_candidates_aabb(plan, bounds_ground_gu, allow_reference_fallback)


func _aoe_query_enemy_candidates_segment(
	plan: Dictionary,
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float,
	allow_reference_fallback := true,
) -> bool:
	return _world_skill_runtime()._aoe_query_enemy_candidates_segment(plan, start_ground_gu, end_ground_gu, expansion_gu, allow_reference_fallback)


func _aoe_validated_snapshot_intersects(
	plan: Dictionary,
	enemy: EnemyActor,
) -> bool:
	return _world_skill_runtime()._aoe_validated_snapshot_intersects(plan, enemy)


func _aoe_insert_by_instance_id(
	targets: Array[EnemyActor],
	ids: Array[int],
	enemy: EnemyActor,
) -> void:
	_world_skill_runtime()._aoe_insert_by_instance_id(targets, ids, enemy)


func _aoe_insert_by_distance(
	targets: Array[EnemyActor],
	distances: Array[float],
	ids: Array[int],
	enemy: EnemyActor,
	distance_along_line_gu: float,
) -> void:
	_world_skill_runtime()._aoe_insert_by_distance(targets, distances, ids, enemy, distance_along_line_gu)


func _aoe_geometry_cells_aabb(cells: Array[Vector2i]) -> Rect2:
	return _world_skill_runtime()._aoe_geometry_cells_aabb(cells)


func _aoe_legacy_damage_query_plan(
	skill_id: String,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	radius_gu: float,
	release_cache: Dictionary,
) -> Dictionary:
	return _world_skill_runtime()._aoe_legacy_damage_query_plan(skill_id, origin_ground_gu, direction_ground_gu, radius_gu, release_cache)


func _aoe_apply_legacy_damage_candidates(
	candidates: Array[EnemyActor],
	origin_screen_px: Vector2,
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
	damage: int,
	radial: bool,
	attack_range_gu: float,
	physical_accuracy: bool,
	source_skill_id: String,
) -> Dictionary:
	return _world_skill_runtime()._aoe_apply_legacy_damage_candidates(candidates, origin_screen_px, origin_ground_gu, direction_ground_gu, damage, radial, attack_range_gu, physical_accuracy, source_skill_id)


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
	return _world_skill_runtime()._aoe_melee_query_plan(mode, origin_ground_gu, direction, release_geometry, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, release_cache)


func _aoe_collect_primary_melee_candidates(
	candidates: Array[EnemyActor],
	result: Array[EnemyActor],
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	thrust_damage_axis_plan: Dictionary,
	melee_release_snapshot: Dictionary,
	target_aligned_plan: Dictionary,
	query_plan: Dictionary,
) -> void:
	_world_skill_runtime()._aoe_collect_primary_melee_candidates(candidates, result, origin_ground_gu, direction_index, mode, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, query_plan)


func _aoe_target_aligned_melee_sector(
	target_plan: Dictionary,
	target_ground_gu: Vector2,
	target_radius_gu: float,
	mode: String,
) -> int:
	return _world_skill_runtime()._aoe_target_aligned_melee_sector(target_plan, target_ground_gu, target_radius_gu, mode)


func _aoe_spell_snapshot(
	skill_release_snapshot: Dictionary,
	continuous_line_strip_ground_gu: Dictionary,
) -> Dictionary:
	return _world_skill_runtime()._aoe_spell_snapshot(skill_release_snapshot, continuous_line_strip_ground_gu)


func _aoe_spell_query_plan(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	continuous_line_strip_ground_gu: Dictionary,
	skill_release_snapshot: Dictionary,
	origin_ground_gu: Vector2,
	release_cache: Dictionary,
) -> Dictionary:
	return _world_skill_runtime()._aoe_spell_query_plan(stable_skill_id, raw_geometry_cells, effect, continuous_line_strip_ground_gu, skill_release_snapshot, origin_ground_gu, release_cache)


# --- P1-A: Gameplay Input Gate (counted runtime locks) ---

const INPUT_LOCK_INITIAL_BOOTSTRAP := &"initial_world_bootstrap"
const INPUT_LOCK_MAP_TRANSITION := &"map_transition"
const INPUT_LOCK_PLAYER_DEATH := &"player_death"
const DEATH_REVIVAL_CONTRACT_ID := "ui.death.revival.v1"
const DEATH_REVIVAL_FLOW_ID := "player.death.lifecycle.ui_gated.v1"


func gameplay_input_is_enabled() -> bool:
	return (
		_player_input_enabled and is_instance_valid(player)
		and not player._dead and player.current_hp > 0
		and not player.combat_transition_is_active()
	)


func _acquire_gameplay_input_lock(reason: StringName) -> void:
	_reset_attack_action_lifecycle(reason)
	var _count: int = int(_gameplay_input_locks.get(reason, 0))
	_gameplay_input_locks[reason] = _count + 1
	_refresh_gameplay_input_state()
	if RuntimeDiagnostics.input_gate_enabled():
		print("[GameplayInputGate] enabled=false locks=", _gameplay_input_locks)


func _release_gameplay_input_lock(reason: StringName) -> void:
	var _count: int = int(_gameplay_input_locks.get(reason, 0))
	if _count <= 0:
		push_warning("attempted to release missing gameplay lock: %s" % reason)
		return
	if _count == 1:
		_gameplay_input_locks.erase(reason)
	else:
		_gameplay_input_locks[reason] = _count - 1
	_refresh_gameplay_input_state()
	if _gameplay_input_locks.is_empty() and is_instance_valid(player):
		# A completed bootstrap/map/death transition is a fresh movement
		# gesture. Never carry a pre-transition run-up into the ready world,
		# even when the player keeps a direction held through the lock.
		player.reset_locomotion()
	if RuntimeDiagnostics.input_gate_enabled():
		print("[GameplayInputGate] enabled=", gameplay_input_is_enabled(), " locks=", _gameplay_input_locks)


func _refresh_gameplay_input_state() -> void:
	_player_input_enabled = _gameplay_input_locks.is_empty() and is_instance_valid(player)


func gameplay_input_gate_snapshot() -> Dictionary:
	var _ls: Dictionary = {}
	for _r: Variant in _gameplay_input_locks:
		_ls[str(_r)] = int(_gameplay_input_locks[_r])
	return {
		"enabled": gameplay_input_is_enabled(),
		"locks": _ls,
		"legacy_enabled": _player_input_enabled,
		"bootstrap_in_progress": _world_bootstrap_in_progress,
	}


func _on_gameplay_movement(value: Vector2) -> void:
	if not gameplay_input_is_enabled():
		return
	player.set_touch_vector(value)


func _cancel_map_transition_movement_input() -> void:
	if is_instance_valid(hud) and hud.has_method("cancel_movement_input"):
		hud.cancel_movement_input()
	if is_instance_valid(player):
		# HUD's zero signal is intentionally ignored while the gameplay lock is
		# held, so clear the authoritative player vector at the boundary too.
		player.set_touch_vector(Vector2.ZERO)



func _init() -> void:
	if OS.is_debug_build():
		_loading_handoff_init_usec = Time.get_ticks_usec()
	# Lifetime is owned by this GameRoot, including instances never added
	# to SceneTree. Do not create another service or change combat math.
	_combat_runtime.name = "CombatRuntimeService"
	add_child(_combat_runtime)


func _enter_tree() -> void:
	if OS.is_debug_build():
		_loading_handoff_enter_tree_usec = Time.get_ticks_usec()


func _loading_profile_mark(
	profile: Dictionary,
	stage_name: String,
	stage_started_usec: int,
	profile_started_usec: int,
) -> int:
	var ended_usec := Time.get_ticks_usec()
	profile["stages_ms"][stage_name] = {
		"start_ms": float(stage_started_usec - profile_started_usec) / 1000.0,
		"duration_ms": float(ended_usec - stage_started_usec) / 1000.0,
	}
	return ended_usec


func _ready() -> void:
	if _original_source_main_attachment!=null:
		_original_source_main_attachment.original_main_ready(self)
		return
	_initial_code_retention = ContentLayers.claim_internal_code_world_retention(self)
	_world_context.configure(self, PlayerState)
	_time_domains.configure(self)
	PlayerState.register_profile_gameplay_owner(self)
	var loading_profile_enabled := OS.is_debug_build()
	var ready_started_usec := 0
	if loading_profile_enabled:
		ready_started_usec = Time.get_ticks_usec()
	var profile_started_usec := ready_started_usec
	if _loading_handoff_init_usec > 0:
		profile_started_usec = _loading_handoff_init_usec
	var loading_profile: Dictionary = {}
	if loading_profile_enabled:
		loading_profile = {
			"origin": "GameRoot._init",
			"pre_ready_boundary": (
				"scene_resource_loading_and_instantiation_before_GameRoot._init_not_instrumented"
			),
			"stages_ms": {},
			"lifecycle_ms": {
				"init_to_enter_tree": (
					float(_loading_handoff_enter_tree_usec - _loading_handoff_init_usec)
					/ 1000.0
					if _loading_handoff_init_usec > 0
					and _loading_handoff_enter_tree_usec > 0
					else -1.0
				),
				"enter_tree_to_ready": (
					float(ready_started_usec - _loading_handoff_enter_tree_usec)
					/ 1000.0
					if _loading_handoff_enter_tree_usec > 0
					else -1.0
				),
			},
		}
	var stage_started_usec := ready_started_usec

	y_sort_enabled = true
	_rng.randomize()
	PlayerState.configure_blessing_oil_rng(_rng)
	_combat_spatial_index = RuntimeCombatSpatialIndexScript.new()
	# Q2-B: one scheduler for generic persistent ground effects. It reuses the
	# shared enemy spatial index; FireWall's formal field path stays outside.
	_ground_effect_manager = PersistentGroundEffectManagerScript.new(
		_combat_spatial_index,
		# R1-C: the manager's damage deliveries share GameRoot's owned
		# CombatRuntimeService instance (M30 ownership contract); the manager
		# never delivers damage outside the shared authority.
		_combat_runtime
	)
	# Q2-D: one MonsterVisual streaming coordinator; MonsterVisual instances
	# register needs and the coordinator owns the single global streaming poll.
	_streaming_coordinator = MonsterVisualStreamingCoordinatorScript.new()
	_streaming_coordinator.configure_process_owner(self)
	MonsterVisualScript.set_streaming_coordinator(_streaming_coordinator)
	# Q0-B: make the window close request interceptable so a failed safe logout
	# can cancel the normal shutdown instead of silently quitting.
	get_tree().auto_accept_quit = false
	_bich_camp_layout = GothicBichCampBuilderScript.load_layout()
	_register_input_actions()
	_reset_attack_action_lifecycle(&"game_root_ready")
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"pre_background_setup",
			stage_started_usec,
			profile_started_usec,
		)
	background = WorldBackground.new()
	# The initial world is built by WorldBootstrapCoordinator's staged pipeline.
	# Declare this before attachment so WorldBackground._ready() does not also
	# run the legacy synchronous environment build.
	background.defer_initial_legacy_build_to_coordinator()
	add_child(background)
	# WALL-P0 diagnostics: inert unless explicitly enabled via env/arg or the
	# user:// marker file; read-only metrics only. Preload (not the global
	# class name) so the hook never depends on the script class cache.
	var probe_script: GDScript = preload(
		"res://scripts/wall_runtime_perf_probe.gd"
	)
	if probe_script.enabled_by_environment():
		var wall_perf_probe: Node = probe_script.new()
		wall_perf_probe.configure(background, self, true)
		add_child(wall_perf_probe)
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"background_construct_and_attach",
			stage_started_usec,
			profile_started_usec,
		)

	player = PlayerCharacter.new()
	player.name = "Player"
	player.attack_requested.connect(_on_player_attack)
	player.environment_blocker = background
	player.skill_requested.connect(_on_player_skill)
	player.hc_world_skill_preflight = Callable(self, "_hc_skill_preflight")
	player.hc_action_configuration_provider = Callable(self, "_capture_action_configuration")
	player.hc_melee_configuration_provider = Callable(self, "_capture_melee_configuration")
	player.hc_action_configuration_identity = Callable(self, "_action_configuration_identity")
	player.skill_cast_started.connect(_on_skill_cast_audio_started)
	player.skill_cast_started.connect(_on_first_fire_wall_cast_probe)
	player.warrior_skill_state_changed.connect(_on_warrior_skill_state_changed)
	player.stats_changed.connect(_on_player_stats_changed)
	player.movement_performed.connect(_on_player_moved)
	player.death_requested.connect(_on_player_death_requested)
	PlayerState.consumable_requested.connect(_on_consumable_used)
	PlayerState.background_item_save_failed.connect(_on_background_item_save_failed)
	PlayerState.scroll_requested.connect(_on_scroll_used)
	PlayerState.item_audio_committed.connect(_on_item_audio_committed)
	# R2: timed 神水 effects report their end through the central notice layer.
	PlayerState.temporary_item_buff_expired.connect(_on_temporary_item_buff_expired)
	player.potion_buff_expired.connect(_on_player_potion_buff_expired)
	add_child(player)
	_register_passive_wake_emitter(player)
	_player_level_up_effect = LevelUpEffectScript.new()
	_player_level_up_effect.name = "PlayerLevelUpEffect"
	_player_level_up_effect.z_index = 0
	player.add_child(_player_level_up_effect)
	_player_level_up_effect.process_mode = Node.PROCESS_MODE_INHERIT
	_player_level_up_effect.set_meta("preview_only", false)
	_player_level_up_effect.set_meta("gameplay_event_source", "PlayerState.levels_gained")
	_player_relic_proc_effect = RelicProcEffectScript.new()
	_player_relic_proc_effect.name = "PlayerRelicProcEffect"
	_player_relic_proc_effect.z_index = 0
	player.add_child(_player_relic_proc_effect)
	PlayerState.relic_proc_started.connect(_on_relic_proc_started)
	PlayerState.levels_gained.connect(_on_player_levels_gained)
	PlayerState.skills_changed.connect(_synchronize_main_pet_skill_ranks)
	PlayerState.equipment_changed.connect(_synchronize_main_pet_skill_ranks)
	_loot_pickup_runtime_manager = LootPickupRuntimeManagerScript.new()
	_loot_pickup_runtime_manager.name = "LootPickupRuntimeManager"
	_loot_pickup_runtime_manager.configure_player(player)
	_loot_pickup_runtime_manager.collection_path_is_clear = Callable(self, "_loot_collection_path_is_clear")
	add_child(_loot_pickup_runtime_manager)
	PlayerState.configure_taoist_main_pets_persistence_provider(
		Callable(self, "_capture_taoist_main_pet_runtime_states")
	)
	player.restore_warrior_runtime_state(PlayerState.warrior_runtime_state_for_restore())
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"player_construct_wire_attach_restore",
			stage_started_usec,
			profile_started_usec,
		)

	_world_camera = Camera2D.new()
	_world_camera.name = "WorldCamera"
	# Integrate follow once in _process. Engine smoothing also runs from
	# transform/zoom publication, which can advance it repeatedly in one frame.
	_world_camera.position_smoothing_enabled = false
	_world_camera.zoom = Vector2.ONE * ArtSpec.CAMERA_ZOOM
	# The camera target is resolved explicitly in _process.  Keep it in the
	# stable GameRoot coordinate domain so Player physics cannot implicitly move
	# the camera between constraint updates and introduce a one-frame jitter.
	add_child(_world_camera)
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"camera_construct_and_attach",
			stage_started_usec,
			profile_started_usec,
		)

	hud = GameHUD.new()
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"hud_construct",
			stage_started_usec,
			profile_started_usec,
		)
	hud.movement_changed.connect(_on_gameplay_movement)
	hud.attack_input_started.connect(_on_mobile_attack_input_started)
	hud.attack_input_ended.connect(_on_mobile_attack_input_ended)
	hud.attack_input_cancelled.connect(_on_mobile_attack_input_cancelled)
	hud.skill_input_started.connect(_on_skill_input_started)
	hud.skill_input_ended.connect(_on_skill_input_ended)
	hud.skill_input_cancelled.connect(_on_skill_input_cancelled)
	hud.interact_pressed.connect(_try_interact)
	hud.skill_slot_pressed.connect(_use_skill_slot)
	hud.map_teleport_availability_requested.connect(
		_on_map_teleport_availability_requested
	)
	hud.map_teleport_requested.connect(_on_map_teleport_requested)
	hud.target_switch_pressed.connect(_cycle_target)
	hud.auto_target_changed.connect(_set_auto_target_enabled)
	hud.skill_button_assignment_requested.connect(_on_skill_button_assignment_requested)
	hud.shop_buy_quotes_requested.connect(_on_shop_buy_quotes_requested)
	hud.shop_buy_requested.connect(_on_shop_buy_requested)
	hud.shop_sell_quotes_requested.connect(_on_shop_sell_quotes_requested)
	hud.shop_sell_requested.connect(_on_shop_sell_requested)
	hud.quest_abandon_requested.connect(_on_quest_abandon_requested)
	hud.warehouse_sort_requested.connect(_on_warehouse_sort_requested)
	hud.revival_requested.connect(_on_revival_requested)
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"hud_signal_wiring",
			stage_started_usec,
			profile_started_usec,
		)
	add_child(hud)
	_town_music_controller = TownMusicControllerScript.new()
	_town_music_controller.name = "TownMusicController"
	add_child(_town_music_controller)
	_audio_runtime_service = AudioRuntimeServiceScript.new()
	_audio_runtime_service.name = "AudioRuntimeService"
	add_child(_audio_runtime_service)
	_audio_runtime_service.sync_sfx_enabled_from_bus()
	hud.loading_transition_finished.connect(
		_town_music_controller.on_loading_transition_finished
	)
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"hud_attach_and_ready",
			stage_started_usec,
			profile_started_usec,
		)
	hud.set_skill_button_assignments(PlayerState.skill_button_assignments_snapshot())
	# Device Lab is intentionally a Debug-only child.  It exposes only the
	# bounded ADB mailbox and opt-in local recording; release builds omit it.
	if OS.is_debug_build():
		_device_lab_runtime = DeviceLabRuntimeScript.new()
		_device_lab_runtime.configure(self)
		_device_lab_runtime.name = "DeviceLabRuntime"
		add_child(_device_lab_runtime)
	_wire_item_quick_slots_hud()
	player.resources_changed.connect(
		func(_current_hp: int, _max_hp: int, _current_mp: int, _max_mp: int) -> void:
			_sync_player_runtime_snapshot_to_hud()
	)
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"hud_post_ready_setup",
			stage_started_usec,
			profile_started_usec,
		)
	# 主动同步首次运行时快照到 HUD，确保资源正确后再加载地图。
	# 120/120、40/40 仅作为未绑定前的占位值。
	_sync_player_runtime_snapshot_to_hud()
	# 初次进场通过独立 bootstrap 合约：显示遮罩 → 预加载 → 加载地图 → 开放输入。
	_build_system_menu()
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"system_menu_build",
			stage_started_usec,
			profile_started_usec,
		)
	_begin_initial_world_bootstrap()
	if loading_profile_enabled:
		stage_started_usec = _loading_profile_mark(
			loading_profile,
			"bootstrap_dispatch",
			stage_started_usec,
			profile_started_usec,
		)
		loading_profile["total_ms"] = (
			float(Time.get_ticks_usec() - profile_started_usec) / 1000.0
		)
		print("[InitialGameRootProfile] ", JSON.stringify(loading_profile))


func _exit_tree() -> void:
	if _original_source_main_attachment!=null:
		_original_source_main_attachment.original_main_exit(self)
		return
	if not MonsterSourceFramesScript.retire_pending_threaded_claims():
		push_error("Monster overlay resource claims could not transfer to the persistent owner.")
	if is_instance_valid(_streaming_coordinator) and not _streaming_coordinator.retire_threaded_resource_claims():
		push_error("Monster visual resource claims could not transfer to the persistent owner.")
	if not _world_bootstrap_coordinator.retire_threaded_resource_claims():
		push_error("World resource claims could not transfer to the persistent owner.")
	ContentLayers.retire_internal_code_result(_initial_code_retention)
	_cancel_respawn_wakeups()
	_retire_pending_warm_textures()
	_retire_loading_texture_claims()
	if _feature_effect_runtime != null:
		_feature_effect_runtime.clear()
	_poll_prepared_enemy_death_settlement(true)
	FrameBudget.mark_pending(_death_budget_category, false)
	if PlayerState.skills_changed.is_connected(_synchronize_main_pet_skill_ranks):
		PlayerState.skills_changed.disconnect(_synchronize_main_pet_skill_ranks)
	if PlayerState.equipment_changed.is_connected(_synchronize_main_pet_skill_ranks):
		PlayerState.equipment_changed.disconnect(_synchronize_main_pet_skill_ranks)
	if not _prepared_loot_collection.is_empty():
		if _prepared_loot_collection.plan.writer.cancel():
			_prepared_loot_collection.plan.writer.result(true)
		else:
			PlayerState.finish_prepared_loot_save(_prepared_loot_collection.plan, true)
		_prepared_loot_collection.clear()
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.stop_all_audio("world_exited")
	if PlayerState.levels_gained.is_connected(_on_player_levels_gained):
		PlayerState.levels_gained.disconnect(_on_player_levels_gained)
	if PlayerState.item_audio_committed.is_connected(_on_item_audio_committed):
		PlayerState.item_audio_committed.disconnect(_on_item_audio_committed)
	if is_instance_valid(_town_music_controller):
		_town_music_controller.cancel("world_exited")
	PlayerState.clear_taoist_main_pets_persistence_provider()
	PlayerState.unregister_profile_gameplay_owner(self)
	# Child visuals have already unregistered at this boundary. The static
	# access path must not prolong this world's coordinator/cache lifetime,
	# and an older exiting world must never detach a newer world's owner.
	if MonsterVisualScript.streaming_coordinator() == _streaming_coordinator:
		MonsterVisualScript.set_streaming_coordinator(null)


func _notification(what: int) -> void:
	if _original_source_main_attachment!=null:
		_original_source_main_attachment.original_main_notification(self,what)
		return
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's WM back notification does not travel through ui_cancel, so
		# defer the same toggle used by the keyboard path.  This also lets a
		# paused tree close the WHEN_PAUSED menu cleanly on the next idle tick.
		call_deferred("_toggle_system_menu")
	elif what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		# Perf Window probe (perf-smoothness-r1): an app pause is a measurement
		# boundary. Reset the wall-clock baseline so the post-resume frame is
		# not recorded as a giant fake frame interval.
		RuntimeDiagnostics.reset_wall_frame_interval()
		_cancel_player_input_boundary(&"application_interrupted")
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		RuntimeDiagnostics.reset_wall_frame_interval()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cancel_all_mobile_attack_inputs(true)
		_cancel_all_skill_inputs(true)
		var close_logout_result := _prepare_safe_logout()
		if not bool(close_logout_result.get("success", false)):
			_handle_safe_logout_failure(&"wm_close_request", close_logout_result)
			return
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if _original_source_main_attachment!=null:
		_original_source_main_attachment.original_main_unhandled_input(self,event)
		return
	if event.is_action_pressed("ui_cancel"):
		_toggle_system_menu()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _original_source_main_attachment!=null: return
	if _feature_effect_runtime != null and _feature_effect_runtime.has_work():
		_time_domains.advance_simulation(delta)
		_feature_effect_runtime.pump()
	var physics_started_usec := RuntimeDiagnostics.timing_start()
	if not _pending_main_pet_arrivals.is_empty() and not _map_transition_in_progress:
		_retry_pending_main_pet_arrivals()
	# Q2-B: generic persistent ground effects are scheduled once per physics
	# frame by the shared manager (old per-effect _physics_process cadence).
	if _ground_effect_manager != null:
		_ground_effect_manager.tick_frame(delta)
	RuntimeDiagnostics.record_timing_ms(&"physics_process_ms", physics_started_usec)


func _process(delta: float) -> void:
	if _original_source_main_attachment!=null:
		_original_source_main_attachment.original_main_process(self,delta)
		return
	_recover_equipment_stealth_if_out_of_combat()
	var full_process_started_usec := RuntimeDiagnostics.timing_start()
	# Real frame pacing (perf-smoothness-r1 Phase A): `_process(delta)` is
	# clamped by the engine (8/60 = 0.133s default) and was provably blind to
	# real stalls (PERF-02 of the 2026-09-18 audit). Measure wall-clock time
	# between process callbacks instead. -1.0 marks a measurement boundary
	# (first frame or pause/resume discard), never a gameplay stall.
	var wall_interval_ms := -1.0
	if OS.is_debug_build():
		wall_interval_ms = RuntimeDiagnostics.wall_frame_interval_ms()
	# AOE first-engagement window (see AoeEngagementWindow): bounded ring of real
	# frame intervals between the first fire wall cast and first batch death.
	if wall_interval_ms >= 0.0 and AoeEngagementWindow.window_active():
		AoeEngagementWindow.record_frame_interval_ms(wall_interval_ms)
	# FRAME-STALL long-frame probe (perf-smoothness-r1 Phase A): armed only
	# after loading ends so bootstrap spikes cannot consume the one shot. Now
	# keyed on the real wall interval (the old `delta > 0.25` could never fire
	# under the engine's clamped delta). Counters remain neutral facts.
	if _first_combat_probe_armed and not _first_long_frame_diagnosed and wall_interval_ms > 250.0:
		_first_long_frame_diagnosed = true
		print(
			"[FRAME-STALL] long frame %.3fs at process frame %d: caster=%s presentation=%d monster_overlay=%s"
			% [
				wall_interval_ms / 1000.0,
				Engine.get_process_frames(),
				CasterSkillVisualRegistry.frame_texture_cache_diagnostics(),
				PresentationAssets.cached_resource_count(),
				preload(
					"res://scripts/monster_source_frames.gd"
				).diagnostics(),
			]
		)
	preload("res://scripts/monster_source_frames.gd").poll()
	# perf-smoothness-r1 Phase C: drain combat texture misses through the
	# bounded threaded warm-up channel (no synchronous decode in combat).
	_pump_pending_warm_textures()
	if not _prepared_loot_collection.is_empty(): _poll_prepared_loot_collection()
	var process_started_usec := RuntimeDiagnostics.timing_start()
	# R3X-4: advance deferred death settlement/materialization in bounded main
	# thread slices.  The queue is deliberately pumped before ordinary world
	# presentation so a non-empty queue cannot starve behind unrelated UI work.
	_pump_enemy_death_work_queue()
	_pump_passive_monster_wakeup()
	UIItemTextureCacheScript.poll_threaded_paths()
	# Q2-D: the single formal MonsterVisual streaming poll (once per frame).
	if _streaming_coordinator != null:
		_streaming_coordinator.poll_once(Engine.get_process_frames())
	if HCDecisionBudget.pursuit_dispatch_enabled():
		HCDecisionBudget.dispatch_pursuit_process_batch(self)
	# Effect work participates in the same frame rotation as resource/death
	# consumers. Physics alone cannot use the turn they release later in this
	# frame. Pumping here never advances simulation or grants another budget.
	if _feature_effect_runtime != null and _feature_effect_runtime.has_work():
		_feature_effect_runtime.pump()
	_expire_canonical_fire_charge_if_needed()
	_constrain_player_foot_to_runtime_ground()
	_refresh_player_safe_zone_cache()
	_update_town_music_presence()
	background.set_focus_position(player.global_position)
	_update_world_camera_constraint(delta)
	_update_portal_arrival_guard()
	_tick_bich_safe_zone_enforcement(delta)
	_update_boss_world_mechanics(delta)
	_record_player_world_location()
	_validate_locked_target()
	_update_target_hud()
	_process_skill_input_actions(delta)
	_process_magic_shield_auto_refresh(delta)
	_tick_ongoing_heals(delta)
	_update_stealth_alpha()
	_update_taoist_buff_hints()
	_warrior_hud_timer -= delta
	_movement_target_refresh_remaining = maxf(0.0, _movement_target_refresh_remaining - delta)
	if _warrior_hud_timer <= 0.0:
		_warrior_hud_timer = 0.2
		PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save())
		hud.update_warrior_states(player.warrior_state_snapshot())
	var bound_attack_skill := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	var attack_action_lifecycle := _poll_attack_action_lifecycle(gameplay_input_is_enabled())
	if bound_attack_skill.is_empty():
		_process_ordinary_attack_input(attack_action_lifecycle)
	else:
		_queued_mobile_attack_tickets.clear()
		if bool(attack_action_lifecycle.get("started", false)):
			_keyboard_bound_skill_token = _allocate_synthetic_attack_token()
			_on_skill_input_started(
				PlayerState.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
		if bool(attack_action_lifecycle.get("ended", false)) and _keyboard_bound_skill_token != 0:
			_on_skill_input_ended(
				PlayerState.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
			_keyboard_bound_skill_token = 0
	if Input.is_action_just_pressed("interact"):
		_try_interact()
	for index in range(4):
		if Input.is_action_just_pressed("skill_%d" % (index + 1)):
			_use_quick_slot(index)
	RuntimeDiagnostics.record_timing_ms(&"process_ms", process_started_usec)
	var full_process_usec := RuntimeDiagnostics.timing_elapsed_usec(full_process_started_usec)
	if full_process_usec > 0:
		RuntimeDiagnostics.record_performance_max(&"full_process_max_ms", float(full_process_usec) / 1000.0)


func _constrain_player_foot_to_runtime_ground() -> bool:
	if (
		not is_instance_valid(player)
		or not MapEditorRuntimeBridgeScript.has_runtime_map(current_map_id)
	):
		return false
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		return false
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var corrected := (
		MapRuntimeCollisionGeometryScript.project_player_foot_inside_boundary(
			player.global_position, design_size
		)
	)
	if corrected.is_equal_approx(player.global_position):
		return false
	_set_player_world_position(corrected, false)
	player.velocity = Vector2.ZERO
	PlayerState.update_world_location(
		current_map_id,
		corrected,
		_canonical_screen_px_to_ground_gu(corrected)
	)
	return true


func _update_world_camera_constraint(delta := 1.0 / 60.0) -> void:
	if not is_instance_valid(_world_camera) or not is_instance_valid(player):
		return
	var base_zoom := Vector2.ONE * ArtSpec.CAMERA_ZOOM
	if not MapEditorRuntimeBridgeScript.has_runtime_map(current_map_id):
		_world_camera.zoom = base_zoom
		_world_camera.position = Vector2.ZERO
		_world_camera.offset = Vector2.ZERO
		_world_camera_presented_center = Vector2.INF
		return
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		_world_camera.zoom = base_zoom
		_world_camera.position = Vector2.ZERO
		_world_camera.offset = Vector2.ZERO
		_world_camera_presented_center = Vector2.INF
		return
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var viewport_half := get_viewport().get_visible_rect().size * 0.5
	# R14-CAM-R2 BLACK-BUDGET REGION (user work order 2026-09-19, review of
	# 7c2631d3), replacing the superseded R14-CAM-R1 per-axis anchor box:
	#   Ruled follow shape: the player stays EXACTLY at the camera center
	#         while black(player) <= B - the unlock threshold event happens
	#         EXACTLY when the centered view reaches the frozen black
	#         budget (the review-declared cap). Past it the camera is the
	#         nearest point of the FIXED convex budget region K_B
	#         intersected with the player display visibility box, so the
	#         black exposure stays capped AND the full player display stays
	#         on screen (the box is centered on the player, so it never
	#         triggers or delays the unlock). The early glide unlock of
	#         C1.5 stays rejected by device ruling.
	#   The view height is exactly ArtSpec.CAMERA_ZOOM (1.06); no dynamic
	#         zoom exists here. Follow integration below changes presentation only;
	#         the authored map geometry and budget constraint stay unchanged.
	var fixed_zoom := Vector2.ONE * ArtSpec.CAMERA_ZOOM
	var camera_center := (
		MapDiamondCameraConstraintScript.apply_player_visibility_guard(
			design_size,
			viewport_half,
			fixed_zoom,
			player.global_position,
			_player_display_extent_world_px()
		)
	)
	if _world_camera_follow_map_id != current_map_id:
		_world_camera_presented_center = Vector2.INF
		_world_camera_follow_map_id = current_map_id
	_world_camera_presented_center = WorldCameraFollowScript.advance(_world_camera_presented_center, camera_center, delta)
	if _world_camera.zoom != fixed_zoom:
		_world_camera.zoom = fixed_zoom
	_world_camera.global_position = camera_center
	_world_camera.offset = _world_camera_presented_center - camera_center
	_world_camera.force_update_scroll()


## R14-CAM-R2: the real display geometry of the player composite, derived
## from the ArtSpec display contract (the final displayed character cell
## CHARACTER_FRAME 64x96 with its foot anchor, placed by the approved
## visual composite offset) and measured against the approved logical foot
## point (visual.position + PLAYER_VISUAL_FOOT_ANCHOR_ADJUSTMENT = origin).
## This is the real displayed-character bound - NOT a hardcoded body width
## and NOT the padded 192x160 source atlas cell the body sprite samples
## from (that cell is mostly transparent padding and would phantom-tighten
## the visibility box). Returned as Vector3(sideways half extent,
## above-foot, below-foot) in world px relative to the logical foot.
func _player_display_extent_world_px() -> Vector3:
	var frame_size := Vector2(ArtSpec.CHARACTER_FRAME)
	var foot_in_frame := Vector2(ArtSpec.CHARACTER_FOOT_ANCHOR)
	var composite := ArtSpec.PLAYER_VISUAL_RUNTIME_POSITION
	# Cell edges relative to the logical foot (the player origin): the
	# cell top-left sits at composite - foot_in_frame in the actor space.
	var left := foot_in_frame.x - composite.x
	var right := frame_size.x - foot_in_frame.x + composite.x
	var above := foot_in_frame.y - composite.y
	var below := frame_size.y - foot_in_frame.y + composite.y
	return Vector3(maxf(left, right), above, below)


## FW-COLD (GPT audit 2026-09-16): prewarm the caster-skill animation frames
## of the player's learned skills during the loading window. Learned skills
## are the superset of the hotbar contents, so this covers every skill the
## player can actually cast first. Fire wall's six frames land here, killing
## the first-cast main-thread texture load spike.
##
## FIRST-COMBAT extension (user device report 2026-09-16): a one-time ~1s
## hitch a few seconds after the first aggro. Static tracing determined the
## only remaining first-combat synchronous loads on the main thread: the
## weapon swing audio streams (PresentationAssets.audio resolves through a
## sync load() on cache miss, first played on the first attack) and the
## fallback presentation action textures. Everything else in the first
## combat presentation path is already warm: paper doll and weapon action
## atlases load at equipment refresh, monster action frames thread-load
## off the main thread, and caster skill frames prewarm above. The audio
## warming is idempotent (all three swing ids, whatever the equipped
## weapon resolves to).
## perf-smoothness-r1 Phase C: bounded async warm-up channel for combat-time
## animation-frame misses. The registry queues paths instead of synchronously
## loading/decoding on the main thread; this pump admits a few threaded
## requests per frame and retains finished textures back into the registry
## cache. Deliberately no-ops while the loading window is active.
var _frame_texture_threaded: Dictionary = {}
var _loading_texture_threaded: Dictionary = {}


func _retire_loading_texture_claims() -> void:
	if _loading_texture_threaded.is_empty():
		return
	# ResourceLoader threaded requests cannot be cancelled by GameRoot. Transfer
	# each accepted claim to the existing persistent preparation owner instead of
	# joining it here. In particular, never call load_threaded_get() for an
	# IN_PROGRESS request during _exit_tree: that would turn owner retirement
	# into a synchronous frame hitch.
	for raw_path: Variant in _loading_texture_threaded.keys():
		var path := str(raw_path)
		if ContentLayers.retire_threaded_resource_claims(path, 1):
			_loading_texture_threaded.erase(path)
		else:
			# Keep the local record when the persistent owner rejects the handoff;
			# silently dropping an accepted native claim would leak ownership.
			push_error("Caster texture claim handoff rejected: %s" % path)


func _retire_pending_warm_textures() -> void:
	if _frame_texture_threaded.is_empty():
		return
	# Requests cannot be cancelled. Only this final owner boundary may join
	# the bounded admitted jobs; ordinary combat polling stays nonblocking.
	var token := FrameBudget.begin("caster_texture_retirement", true)
	for path: String in _frame_texture_threaded.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status != ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			if texture != null:
				CasterSkillVisualRegistry.retain_loaded_texture(path, texture)
			else:
				CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(
					path, "failed" if status == ResourceLoader.THREAD_LOAD_FAILED else "wrong_resource_type"
				)
		else:
			CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(path, "invalid")
	_frame_texture_threaded.clear()
	if token != 0:
		FrameBudget.end(token)


func _pump_pending_warm_textures() -> void:
	if CasterSkillVisualRegistry.is_loading_window_active():
		return
	for path: String in _frame_texture_threaded.keys():
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			_frame_texture_threaded.erase(path)
			var texture := ResourceLoader.load_threaded_get(path) as Texture2D
			if texture != null:
				CasterSkillVisualRegistry.retain_loaded_texture(path, texture)
			else:
				CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(path, "wrong_resource_type")
		elif status == ResourceLoader.THREAD_LOAD_FAILED:
			_frame_texture_threaded.erase(path)
			# FAILED is terminal; retrieve once to release this request's token.
			ResourceLoader.load_threaded_get(path)
			CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(path, "failed")
		elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
			_frame_texture_threaded.erase(path)
			CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(path, "invalid")
	# Collect admitted results first. A queued world's final notification must
	# not start new work whose result this retiring owner will never collect.
	if is_queued_for_deletion():
		return
	if _frame_texture_threaded.size() >= FRAME_TEXTURE_WARM_MAX_IN_FLIGHT:
		return
	for path: String in CasterSkillVisualRegistry.take_pending_warm_paths(
		mini(FRAME_TEXTURE_WARM_PER_FRAME,
			FRAME_TEXTURE_WARM_MAX_IN_FLIGHT - _frame_texture_threaded.size())
	):
		if _frame_texture_threaded.has(path):
			continue
		# PERF-R2 R5: combat warm-up must never use sub threads - the main
		# thread's frame time stability outranks background texture speed.
		var request_error := ResourceLoader.load_threaded_request(path, "Texture2D", false)
		if request_error == OK:
			_frame_texture_threaded[path] = true
		elif request_error == ERR_BUSY:
			# No accepted claim belongs to this owner. A busy request can become
			# available later and must not terminate the visual sequence.
			CasterSkillVisualRegistry.queue_sequence_warm([path], false)
		else:
			CasterSkillVisualRegistry.mark_frame_texture_terminal_failure(
				path, "request_rejected_%d" % request_error
			)


## perf-smoothness-r1 C-R1 (PERF-R2 R7): the workset priority comes from the
## player's ACTUAL bound attack slots and attack ring, not the learned-skills
## Dictionary whose key order is historical. A skill the player cannot cast
## has zero first-cast value.
func _active_skill_workset_candidates() -> Array[String]:
	var raw: Array = []
	raw.append_array(
		PlayerState.skill_slots_for_group(
			PlayerState.SKILL_SLOT_GROUP_ATTACK
		)
	)
	raw.append_array(
		PlayerState.skill_slots_for_group(
			PlayerState.SKILL_SLOT_GROUP_ATTACK_RING
		)
	)
	var display_names: Array = []
	for identity: Variant in raw:
		display_names.append(SkillDataLoaderScript.display_name(str(identity)))
	return CasterSkillVisualRegistry.workset_skill_order(display_names, 7)


## PERF-R2 R8: thread-pump texture paths with a REAL absolute deadline.
## No synchronous load() ever runs on this budget path: paths are admitted
## through load_threaded_request, polled every frame, and only a
## THREAD_LOAD_LOADED status may call load_threaded_get. The deadline stops
## new admissions; already-in-flight completions are still collected so no
## threaded work is wasted or leaked.
func _prewarm_texture_paths_until(
	paths: Array[String],
	deadline_usec: int
) -> Dictionary:
	var cursor := 0
	_loading_texture_threaded.clear()
	var loaded := 0
	var failed := 0
	# perf(R13-D1): first moment the absolute deadline became true, so the
	# in-flight drain tail is measurable (diagnostics only, no behavior).
	var first_deadline_hit_usec := 0
	while cursor < paths.size() or not _loading_texture_threaded.is_empty():
		var deadline_hit := Time.get_ticks_usec() >= deadline_usec
		if deadline_hit and first_deadline_hit_usec == 0:
			first_deadline_hit_usec = Time.get_ticks_usec()
		if not deadline_hit:
			while (
				_loading_texture_threaded.size() < FRAME_TEXTURE_WARM_MAX_IN_FLIGHT
				and cursor < paths.size()
			):
				var path := paths[cursor]
				cursor += 1
				if CasterSkillVisualRegistry.frame_texture_is_resident(path):
					loaded += 1
					continue
				var err := ResourceLoader.load_threaded_request(
					path, "Texture2D", true
				)
				if err == OK:
					_loading_texture_threaded[path] = true
				else:
					failed += 1
		for raw_path: Variant in _loading_texture_threaded.keys():
			var path := str(raw_path)
			var status := ResourceLoader.load_threaded_get_status(path)
			if status == ResourceLoader.THREAD_LOAD_LOADED:
				_loading_texture_threaded.erase(path)
				var texture := ResourceLoader.load_threaded_get(
					path
				) as Texture2D
				if texture != null:
					CasterSkillVisualRegistry.retain_loaded_texture(path, texture)
					loaded += 1
				else:
					failed += 1
			elif status == ResourceLoader.THREAD_LOAD_FAILED:
				# FAILED is terminal but still owns one native retrieval claim.
				# Consume that claim before retiring this local request owner;
				# otherwise a failed accepted request survives as an orphan.
				ResourceLoader.load_threaded_get(path)
				_loading_texture_threaded.erase(path)
				failed += 1
			elif status == ResourceLoader.THREAD_LOAD_INVALID_RESOURCE:
				_loading_texture_threaded.erase(path)
				failed += 1
		if _loading_texture_threaded.is_empty() and (
			cursor >= paths.size() or Time.get_ticks_usec() >= deadline_usec
		):
			break
		await get_tree().process_frame
	var completed_usec := Time.get_ticks_usec()
	var tail_after_deadline_ms := 0.0
	if first_deadline_hit_usec > 0:
		tail_after_deadline_ms = (
			float(completed_usec - first_deadline_hit_usec) / 1000.0
		)
	return {
		"loaded": loaded,
		"failed": failed,
		"not_admitted": paths.size() - cursor,
		"in_flight_at_deadline": _loading_texture_threaded.size(),
		"deadline_exceeded": first_deadline_hit_usec > 0,
		"deadline_hit_at_usec": first_deadline_hit_usec,
		"completed_at_usec": completed_usec,
		"tail_after_deadline_ms": tail_after_deadline_ms,
	}


## perf(R13-D2): returns the prewarm diagnostics Dictionary so the caller can
## fold it into the self-contained [LOADING-TOTAL] record - no second state
## copy, the values are the same pump/pin/gate results already printed.
func _prewarm_learned_skill_visuals() -> Dictionary:
	# perf-smoothness-r1 Phase C + C-R1: the loading window is explicitly
	# opened for this one prewarm entry and closed at READY release; combat
	# texture misses go through the async warm-up channel instead. The whole
	# entry now runs under ONE enforced absolute deadline: texture prewarm is
	# thread-pumped frame by frame and stops admitting past the budget.
	CasterSkillVisualRegistry.set_loading_window_active(true)
	CasterSkillVisualRegistry.unpin_all_frames()
	var workset: Array[String] = _active_skill_workset_candidates()
	if workset.is_empty():
		return {
			"deadline_exceeded": false,
			"tail_after_deadline_ms": 0.0,
			"loaded": 0,
			"failed": 0,
			"not_admitted": 0,
			"incomplete_skills": [],
		}
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + LOADING_PREWARM_BUDGET_USEC
	# R14-C6: directional skills prewarm ONLY the current player-facing
	# sequence instead of every direction (a 16-direction laser sequence is
	# ~3-4 MiB, not ~48 MiB); non-directional skills prewarm their unique
	# sequence. Same workset, same deadlines, same pin budget.
	var facing_direction_index := 8
	if is_instance_valid(player):
		facing_direction_index = CasterSkillVisualRegistry.direction_index(
			player.facing
		)
	var all_paths: Array[String] = []
	for skill_id: String in workset:
		all_paths.append_array(
			CasterSkillVisualRegistry.animation_sequence_paths(
				skill_id, facing_direction_index
			)
		)
	var pump_result: Dictionary = await _prewarm_texture_paths_until(
		all_paths, deadline_usec
	)
	# Optional low-cost warming yields to the same deadline: skipped entirely
	# once the budget is gone (PERF-R2 R8 - the deadline is absolute).
	var optional_skipped := false
	if Time.get_ticks_usec() < deadline_usec:
		for audio_id: String in ["sword", "wood", "fist"]:
			PresentationAssets.audio(audio_id)
		for action_key: String in ["attack", "hit", "cast", "death"]:
			PresentationAssets.player_texture(action_key)
	else:
		optional_skipped = true
	# READY-critical workset gate: every workset skill's PREWARMED SEQUENCE
	# (R14-C6: the current-facing sequence for directional skills) must be
	# fully resident before Loading ends. The gate reports truthfully.
	var incomplete_skills: Array[String] = []
	for skill_id: String in workset:
		var sequence_paths := (
			CasterSkillVisualRegistry.animation_sequence_paths(
				skill_id, facing_direction_index
			)
		)
		if not CasterSkillVisualRegistry.sequence_resident(sequence_paths):
			incomplete_skills.append(skill_id)
	# Pin the bounded workset lease (atomic per skill, R14-C6 sequence-level):
	# accepted skills are exempt from LRU eviction; rejected skills are
	# reported truthfully.
	var pin_result: Dictionary = CasterSkillVisualRegistry.pin_skill_workset(
		workset, facing_direction_index
	)
	var prewarm_usec := Time.get_ticks_usec() - started_usec
	print(
		"[LOADING-WORKSET] skills=%d paths=%d loaded=%d failed=%d not_admitted=%d prewarm_ms=%d deadline_exceeded=%s tail_after_deadline_ms=%.1f optional_skipped=%s accepted=%s rejected=%s pinned_paths=%d pinned_bytes=%d incomplete=%s"
		% [
			workset.size(),
			all_paths.size(),
			int(pump_result.get("loaded", 0)),
			int(pump_result.get("failed", 0)),
			int(pump_result.get("not_admitted", 0)),
			prewarm_usec / 1000,
			str(pump_result.get("deadline_exceeded", false)),
			float(pump_result.get("tail_after_deadline_ms", 0.0)),
			str(optional_skipped),
			str(pin_result.get("accepted_skills", [])),
			str(pin_result.get("rejected_skills", [])),
			int(pin_result.get("pinned_paths", -1)),
			int(pin_result.get("pinned_bytes", -1)),
			str(incomplete_skills),
		]
	)
	return {
		"deadline_exceeded": bool(pump_result.get("deadline_exceeded", false)),
		"tail_after_deadline_ms": float(
			pump_result.get("tail_after_deadline_ms", 0.0)
		),
		"loaded": int(pump_result.get("loaded", 0)),
		"failed": int(pump_result.get("failed", 0)),
		"not_admitted": int(pump_result.get("not_admitted", 0)),
		"incomplete_skills": incomplete_skills,
	}


## FW-COLD2 Phase B (remote review 2026-09-16): RESOURCE WARM is not RENDER
## WARM. The device still showed a one-time first fire wall cast hitch while
## the CPU texture cache was already hot; on this project's gl_compatibility
## renderer that matches the first-render cold path (GPU texture upload,
## first CanvasItem draw state, driver first-use). The officially recommended
## Compatibility warm-up is to really draw the effect inside the viewport
## once per frame texture while the loading overlay still fully covers the
## screen. Presentation-only: no fire wall field controller, no damage, no
## combat-side registration, no MP cost. The visual must stay visible -
## visible=false or alpha 0 lets the renderer skip the draw - the loading
## overlay is what hides it from the player.
## R14-C-R1 P0-11..16: the warm covers EVERY workset skill's actual
## prewarmed facing sequence under a hard wall-clock budget
## (LOADING_RENDER_WARM_BUDGET_USEC, ~1s) so GPU warm can never consume the
## user-allowed Loading budget. Skills whose sequence is not fully resident
## are skipped (no extending resource loading for render warm). Every warm
## visual is deterministically released (P0-13) so _exit_tree reclaims its
## sequence lease; the active-sequence lease refcount before/after must be
## identical (P0-15). Returns a structured diagnostic merged into
## [LOADING-TOTAL] (P0-16).
func _warm_fire_wall_render_path() -> Dictionary:
	var result := {
		"skills_considered": 0,
		"skills_warmed": 0,
		"frames_drawn": 0,
		"budget_exhausted": false,
		"elapsed_ms": 0.0,
		"lease_refcount_before": 0,
		"lease_refcount_after": 0,
	}
	var lease_before := 0
	var lease_after := 0
	if DisplayServer.get_name() == "headless":
		# Automated headless runs have no real rendering server; the CPU
		# residency gate already proves everything headless can prove. Still
		# report the structured result with the (trivially equal) lease pair.
		lease_before = 0
		lease_after = 0
		result["lease_refcount_before"] = lease_before
		result["lease_refcount_after"] = lease_after
		return result
	lease_before = int(
		CasterSkillVisualRegistry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", 0
		)
	)
	result["lease_refcount_before"] = lease_before
	var started_usec := Time.get_ticks_usec()
	var deadline_usec := started_usec + LOADING_RENDER_WARM_BUDGET_USEC
	var warm_position := Vector2.ZERO
	if is_instance_valid(_world_camera):
		warm_position = _world_camera.get_screen_center_position()
	elif is_instance_valid(player):
		warm_position = player.global_position
	var facing_direction := Vector2.DOWN
	if is_instance_valid(player):
		var normalized := player.facing.normalized()
		if normalized.length_squared() > 0.0:
			facing_direction = normalized
	var facing_direction_index := (
		CasterSkillVisualRegistry.direction_index(facing_direction)
	)
	for skill_id: String in _active_skill_workset_candidates():
		result["skills_considered"] += 1
		if not CasterSkillVisualRegistry.is_runtime_ready(skill_id):
			continue
		# P0-12: warm only fully-resident facing sequences; never extend
		# resource loading for the sake of render warm.
		var sequence_paths := (
			CasterSkillVisualRegistry.animation_sequence_paths(
				skill_id, facing_direction_index
			)
		)
		if not CasterSkillVisualRegistry.sequence_resident(sequence_paths):
			continue
		var warm_visual := CasterSkillAnimationPlayer.new()
		# P0-1: configure returns true for any ACCEPTED configuration; a
		# structural failure (unknown skill/contract/frames) still returns
		# false and frees the candidate.
		if not warm_visual.configure(skill_id, facing_direction):
			warm_visual.free()
			continue
		result["skills_warmed"] += 1
		if skill_id == "wizard.fire_wall":
			# P0-14: fire wall keeps its production presentation values.
			warm_visual.modulate = Color(1.0, 1.0, 1.0, 0.78)
			warm_visual.scale.y *= 0.6
		warm_visual.global_position = warm_position
		# P0-12: the visual must be actually visible so the renderer cannot
		# skip the draw; the loading overlay hides it from the player.
		warm_visual.visible = true
		add_child(warm_visual)
		var budget_exhausted := false
		for frame_index: int in warm_visual.frame_count():
			warm_visual.set_manual_frame(frame_index)
			await RenderingServer.frame_post_draw
			result["frames_drawn"] += 1
			if Time.get_ticks_usec() >= deadline_usec:
				budget_exhausted = true
				break
		if budget_exhausted:
			result["budget_exhausted"] = true
		# P0-13: EVERY warm visual is deterministically released so
		# _exit_tree reclaims its sequence lease.
		warm_visual.queue_free()
		await RenderingServer.frame_post_draw
		if Time.get_ticks_usec() >= deadline_usec:
			result["budget_exhausted"] = true
			break
	lease_after = int(
		CasterSkillVisualRegistry.frame_texture_cache_diagnostics().get(
			"leased_sequence_refcount_total", 0
		)
	)
	result["lease_refcount_after"] = lease_after
	result["elapsed_ms"] = (
		float(Time.get_ticks_usec() - started_usec) / 1000.0
	)
	if lease_after != lease_before:
		# P0-15: render warm must never leak or drop an active-sequence lease.
		push_error(
			"[RENDER-WARM] sequence lease leak detected: before=%d after=%d"
			% [lease_before, lease_after]
		)
	# FRAME-STALL baseline: one print at the end of the loading window. The
	# one-time long-frame probe (see _process) prints the same counters when
	# the first >250ms wall-clock frame occurs; the delta localizes the stall
	# source. Counters are separated per cache owner (perf-smoothness-r1
	# PERF-01): caster skill frames, presentation assets, monster overlay
	# frames, and the monster BODY streaming coordinator are distinct caches.
	var body_streaming := {}
	if _streaming_coordinator != null:
		var raw_body: Dictionary = _streaming_coordinator.monster_streaming_diagnostics()
		body_streaming = {
			"ready": raw_body.get("ready_resource_count", 0),
			"failed": raw_body.get("failed_request_count", raw_body.get("failed_resource_count", 0)),
			"decoded_bytes": raw_body.get("decoded_rgba8_bytes", 0),
			"pinned_bytes": raw_body.get("pinned_decoded_rgba8_bytes", 0),
			"leased": raw_body.get("leased_visual_count", 0),
			"sync_loads": raw_body.get("sync_load_count", 0),
		}
	print(
		"[FRAME-STALL] baseline: caster=%s presentation=%d monster_overlay=%s monster_body=%s"
		% [
			CasterSkillVisualRegistry.frame_texture_cache_diagnostics(),
			PresentationAssets.cached_resource_count(),
			preload(
				"res://scripts/monster_source_frames.gd"
			).diagnostics(),
			JSON.stringify(body_streaming),
		]
	)
	return result


## Session identity header (perf-smoothness-r1 Phase A): once per process.
## Discloses the running identity and the engine timing parameters that
## define the process-delta clamp, so captured logs are self-describing.
func _print_session_diagnostics_header() -> void:
	if _session_header_printed:
		return
	_session_header_printed = true
	var refresh_rate := -1.0
	if DisplayServer.get_name() != "headless":
		refresh_rate = DisplayServer.screen_get_refresh_rate()
	print(
		"[SESSION-ID] godot=%s renderer=%s adapter=%s api=%s refresh=%.1fHz physics_tps=%d max_physics_steps=%d app_version=%s os=%s"
		% [
			Engine.get_version_info().get("string", ""),
			str(ProjectSettings.get_setting("rendering/renderer/rendering_method", "")),
			RenderingServer.get_video_adapter_name(),
			RenderingServer.get_video_adapter_api_version(),
			refresh_rate,
			Engine.physics_ticks_per_second,
			Engine.max_physics_steps_per_frame,
			str(ProjectSettings.get_setting("application/config/version", "")),
			OS.get_name(),
		]
	)


func _register_input_actions() -> void:
	_add_key_action("move_left", [KEY_A, KEY_LEFT])
	_add_key_action("move_right", [KEY_D, KEY_RIGHT])
	_add_key_action("move_up", [KEY_W, KEY_UP])
	_add_key_action("move_down", [KEY_S, KEY_DOWN])
	_add_key_action("attack", [KEY_SPACE, KEY_J])
	_add_key_action("interact", [KEY_E])
	_add_key_action("skill_1", [KEY_1])
	_add_key_action("skill_2", [KEY_2])
	_add_key_action("skill_3", [KEY_3])
	_add_key_action("skill_4", [KEY_4])


func _add_key_action(action: StringName, keycodes: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for code: int in keycodes:
		var event := InputEventKey.new()
		event.physical_keycode = code
		InputMap.action_add_event(action, event)


func _build_system_menu() -> void:
	_system_menu_layer = CanvasLayer.new()
	_system_menu_layer.layer = 200
	add_child(_system_menu_layer)
	_system_menu_panel = SystemMenuPanelScript.new()
	_system_menu_panel.name = "SystemMenuPanel"
	_system_menu_panel.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_system_menu_panel.visible = false
	_system_menu_panel.visibility_changed.connect(_on_system_menu_visibility_changed)
	_system_menu_panel.continue_requested.connect(_hide_system_menu)
	_system_menu_panel.return_to_character_select_requested.connect(_return_to_character_select)
	_system_menu_panel.save_and_exit_requested.connect(_exit_game)
	_system_menu_panel.audio_setting_changed.connect(_on_system_menu_audio_setting_changed)
	_system_menu_layer.add_child(_system_menu_panel)
	_system_menu_panel.set_audio_levels(
		AudioPreferences.music_volume,
		AudioPreferences.sfx_volume
	)


func _show_system_menu() -> void:
	if _system_menu_panel == null:
		return
	# The paused tree may never receive the matching Android UP/CANCEL. Revoke
	# each current owner before pausing; a later press must establish a new token.
	_cancel_player_input_boundary(&"system_menu_opened")
	_system_menu_pause_owned = _system_menu_pause_owned or not get_tree().paused
	_system_menu_panel.open_menu()
	get_tree().paused = true


func _hide_system_menu() -> void:
	if _system_menu_panel != null:
		_system_menu_panel.close_menu()
	_release_system_menu_pause()


func _toggle_system_menu() -> void:
	if _system_menu_panel != null and _system_menu_panel.visible:
		_hide_system_menu()
	else:
		_show_system_menu()


func _on_system_menu_visibility_changed() -> void:
	if _system_menu_panel == null:
		return
	# A panel can be hidden by an owner other than the Continue action (for
	# example a modal coordinator or a scene transition).  Do not leave the
	# world paused behind an invisible menu, but only release a pause this menu
	# actually acquired.
	if not _system_menu_panel.visible or not _system_menu_panel.is_visible_in_tree():
		_release_system_menu_pause()


func _release_system_menu_pause() -> void:
	if not _system_menu_pause_owned:
		return
	_cancel_player_input_boundary(&"system_menu_closed")
	_system_menu_pause_owned = false
	get_tree().paused = false


func _cancel_player_input_boundary(reason: StringName) -> void:
	if is_instance_valid(hud):
		hud.cancel_attack_inputs(reason)
		hud.cancel_skill_inputs(reason)
		hud.cancel_item_slot_input_boundary(reason)
	_cancel_map_transition_movement_input()
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	_reset_attack_action_lifecycle(reason)


## R2: timed 神水 (temporary stat buff) expiry reports once through the
## central notice layer, projecting display text from the formal item owner.
func _on_temporary_item_buff_expired(entity_id: String) -> void:
	if not is_instance_valid(hud):
		return
	var item := GameData.get_entity_record(entity_id)
	if not item.is_empty():
		hud.show_message("%s效果结束" % str(item.get("name", "")))


## R2: legacy potion combat buffs (ac/mac) report their end the same way.
func _on_player_potion_buff_expired(kind: String) -> void:
	if not is_instance_valid(hud):
		return
	hud.show_message("神水效果结束")


func _on_player_levels_gained(previous_level: int, new_level: int) -> void:
	if new_level <= previous_level or not is_instance_valid(player):
		return
	player.restore_level_up_resources()
	# PlayerState emits once per successful experience settlement, outside its
	# level loop. The approved visual follows the actor rather than a world point.
	if is_instance_valid(_player_level_up_effect):
		_player_level_up_effect.replay(player.approved_ground_footpoint_local_px())
	# R2: the level-up result joins the unified central notice layer.
	hud.show_success_message("等级提升至 %d" % new_level)


func _on_relic_proc_started(_item_id: int) -> void:
	if is_instance_valid(player) and is_instance_valid(_player_relic_proc_effect):
		_player_relic_proc_effect.replay(player.approved_ground_footpoint_local_px())


func _update_town_music_presence() -> void:
	if (
		not is_instance_valid(_town_music_controller)
		or _map_transition_in_progress
		or _world_bootstrap_in_progress
	):
		return
	# Reuse the already-computed player safe-area result, without adding a
	# second geometry query or a world scan to the presentation hot path.
	_town_music_controller.set_town_presence(
		TownMusicControllerScript.is_main_city_map(current_map_id)
		and bool(_player_safe_zone_cache.get("valid", false))
		and int(_player_safe_zone_cache.get("map_id", -1)) == current_map_id
		and bool(_player_safe_zone_cache.get("inside", false))
	)


func _audio_bus_enabled(bus_name: StringName) -> bool:
	var bus_index := AudioServer.get_bus_index(bus_name)
	return bus_index < 0 or not AudioServer.is_bus_mute(bus_index)


func _on_system_menu_audio_setting_changed(request: Dictionary) -> void:
	var contract_id := str(request.get("contract_id", ""))
	if contract_id == "ui.audio.setting.v2":
		AudioPreferences.set_level(str(request.get("channel", "")), request.get("value", null))
	elif contract_id == "ui.audio.setting.v1":
		var setting_id := str(request.get("setting_id", ""))
		if setting_id not in ["audio.music.enabled", "audio.sfx.enabled"]:
			return
		var channel := "music" if setting_id == "audio.music.enabled" else "sfx"
		AudioPreferences.set_level(channel, 1.0 if bool(request.get("enabled", true)) else 0.0)


func _on_shop_sell_quotes_requested(items: Array) -> void:
	if is_instance_valid(hud):
		hud.set_shop_sell_quotes(PlayerState.shop_sell_quotes(items))


func _on_shop_buy_quotes_requested(stock: Array) -> void:
	if is_instance_valid(hud):
		hud.set_shop_buy_quotes(PlayerState.shop_buy_quotes(stock))


func _on_shop_buy_requested(request: Dictionary) -> void:
	if not is_instance_valid(hud) or not is_instance_valid(hud.shop_panel):
		return
	hud.apply_shop_buy_result(PlayerState.buy_shop_item(request, hud.shop_panel.stock))


func _on_shop_sell_requested(request: Dictionary) -> void:
	if is_instance_valid(hud):
		var result := PlayerState.sell_inventory_items(request.get("batch", [])) if request.get("batch", null) is Array else PlayerState.sell_inventory_item(request)
		hud.apply_shop_sell_result(result)


func _on_quest_abandon_requested(quest_id: String) -> void:
	if is_instance_valid(hud):
		hud.apply_quest_abandon_result(PlayerState.abandon_quest(quest_id))


func _on_warehouse_sort_requested() -> void:
	if is_instance_valid(hud):
		hud.apply_warehouse_sort_result(PlayerState.sort_warehouse(hud.warehouse_panel.warehouse_page))


func _prepare_safe_logout() -> Dictionary:
	var death_queue_result := _drain_enemy_death_queue_for_logout()
	if not bool(death_queue_result.get("success", false)):
		return death_queue_result
	var loot_queue_result := _drain_loot_collection_queue_for_logout()
	if not bool(loot_queue_result.get("success", false)):
		return loot_queue_result
	PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save())
	PlayerState.apply_taoist_main_pet_runtime_states(
		_capture_taoist_main_pet_runtime_states()
	)
	var home_map_id := GameData.service_home_runtime_map_id(false)
	var resolved := _resolve_bich_home()
	if not bool(resolved.get("valid", false)):
		return {
			"success": false,
			"save_performed": false,
			"reason": str(
				resolved.get("reason", "safe_logout_home_resolution_failed")
			),
			"home_source": str(resolved.get("source", "")),
		}
	var home_screen_position_px: Vector2 = resolved.get(
		"position_px", Vector2.ZERO
	) as Vector2
	var home_ground_gu := _ground_position_gu_for_map(
		home_map_id,
		home_screen_position_px
	)
	if not home_ground_gu.is_finite():
		# FREEZE-P0.2: never write Vector2.INF into the save/PlayerState.
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_projection_unavailable",
			"home_source": str(resolved.get("source", "")),
		}
	var save_success := PlayerState.save_safe_logout(
		home_map_id,
		home_screen_position_px,
		home_ground_gu
	)
	if not save_success:
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_save_failed",
			"home_source": str(resolved.get("source", "")),
		}
	return {
		"success": true,
		"save_performed": true,
		"reason": "",
		"home_source": str(resolved.get("source", "")),
	}


func _drain_loot_collection_queue_for_logout() -> Dictionary:
	# A close request may arrive after a pickup emitted its signal but before
	# the deferred transaction flush.  Force the manager's final nearby query
	# and consume the deferred collection synchronously before logout save.
	var manager_result: Dictionary = {}
	if _loot_pickup_runtime_manager != null:
		manager_result = _loot_pickup_runtime_manager.flush_for_logout()
		if not bool(manager_result.get("success", false)):
			return {
				"success": false,
				"save_performed": false,
				"reason": "safe_logout_loot_manager_failed",
				"loot_queue": manager_result,
			}
		if int(manager_result.get("logout_retry_blocked_count", 0)) > 0:
			return {
				"success": false,
				"save_performed": false,
				"reason": "safe_logout_loot_retry_pending",
				"loot_queue": manager_result,
			}
	if _pending_loot_collections.is_empty() and _prepared_loot_collection.is_empty():
		return {
			"success": true,
			"save_performed": false,
			"reason": "",
			"loot_queue_drained": true,
		}
	var result := _flush_loot_collections()
	if not bool(result.get("success", false)):
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_loot_collection_failed",
			"loot_queue": result,
		}
	if not _pending_loot_collections.is_empty():
		return {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_loot_queue_pending",
			"loot_queue": result,
		}
	return {
		"success": true,
		"save_performed": false,
		"reason": "",
		"loot_queue_drained": true,
	}


func _flush_pending_enemy_death_signals_for_logout() -> void:
	# A lethal hit queues Enemy._begin_death() through call_deferred().  A WM
	# close can arrive before that deferred callback, so explicitly finish the
	# actor-side death boundary before draining the GameRoot queue.  This is an
	# exit-only scan; it is never part of gameplay or per-frame processing.
	var pending_actors: Array[EnemyActor] = []
	var seen_instance_ids: Dictionary = {}
	var candidates: Array = []
	if is_inside_tree():
		candidates.append_array(get_tree().get_nodes_in_group("death_pending"))
	for raw_actor: Variant in _active_enemy_cache.values():
		candidates.append(raw_actor)
	for raw_actor: Variant in candidates:
		if not raw_actor is EnemyActor or not is_instance_valid(raw_actor):
			continue
		var enemy := raw_actor as EnemyActor
		var instance_id := enemy.get_instance_id()
		if seen_instance_ids.has(instance_id):
			continue
		seen_instance_ids[instance_id] = true
		if enemy._death_pending and not enemy._dying:
			pending_actors.append(enemy)
	for enemy: EnemyActor in pending_actors:
		if is_instance_valid(enemy) and enemy._death_pending and not enemy._dying:
			enemy._begin_death()


func _drain_enemy_death_queue_for_logout() -> Dictionary:
	# Exit actions are the one deliberate synchronous boundary for the deferred
	# death pipeline.  A queued death must finish (or become an explicit,
	# diagnosable terminal failure) before PlayerState writes its logout record;
	# otherwise a successful logout can silently lose XP, respawn state, or loot.
	if not _last_death_logout_failure.is_empty():
		var early_latched_failure := _last_death_logout_failure.duplicate(true)
		early_latched_failure["death_queue"] = death_work_queue_snapshot()
		return early_latched_failure
	_flush_pending_enemy_death_signals_for_logout()
	var terminal_count_before := _enemy_death_terminal_jobs.size()
	var guard := 0
	while not _pending_enemy_deaths.is_empty() and guard < 4096:
		var progressed := _pump_enemy_death_work_queue(true)
		guard += 1
		if not progressed:
			break
	if not _pending_enemy_deaths.is_empty():
		var pending_result := {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_death_queue_pending",
			"pending_deaths": _pending_enemy_deaths.size(),
			"death_queue": death_work_queue_snapshot(),
		}
		# Pending is the current queue state, not a terminal failure. A later
		# receipt can finish this work, so the next exit request must drain again.
		# Only FAILED settlements enter the durable in-session failure latch.
		return pending_result
	# A bounded terminal ledger can evict the just-created record when it was
	# already full.  The failure latch is therefore authoritative for this
	# drain; do not rely only on array indices below.
	if not _last_death_logout_failure.is_empty():
		var latched_failure := _last_death_logout_failure.duplicate(true)
		latched_failure["death_queue"] = death_work_queue_snapshot()
		return latched_failure
	for index: int in range(terminal_count_before, _enemy_death_terminal_jobs.size()):
		var terminal: Dictionary = _enemy_death_terminal_jobs[index]
		if str(terminal.get("state", "")) != DEATH_STATE_FAILED:
			continue
		var failed_result := {
			"success": false,
			"save_performed": false,
			"reason": "safe_logout_death_queue_failed",
			"death_key": str(terminal.get("death_key", "")),
			"death_error": str(terminal.get("last_error", "")),
			"death_queue": death_work_queue_snapshot(),
		}
		_last_death_logout_failure = failed_result.duplicate(true)
		return failed_result
	return {
		"success": true,
		"save_performed": false,
		"reason": "",
		"death_queue_drained": true,
	}


func _return_to_character_select() -> void:
	var logout_result := _prepare_safe_logout()
	if not bool(logout_result.get("success", false)):
		_handle_safe_logout_failure(
			&"return_to_character_select",
			logout_result
		)
		return
	_perform_character_select_transition()


func _perform_character_select_transition() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")


func _exit_game() -> void:
	var logout_result := _prepare_safe_logout()
	if not bool(logout_result.get("success", false)):
		_handle_safe_logout_failure(&"exit_game", logout_result)
		return
	get_tree().paused = false
	get_tree().quit()


func _handle_safe_logout_failure(action: StringName, result: Dictionary) -> void:
	var diagnostic := {
		"action": str(action),
		"reason": str(result.get("reason", "")),
		"home_source": str(result.get("home_source", "")),
		"current_map_id": current_map_id,
		"player_position": (
			player.global_position if is_instance_valid(player) else Vector2.ZERO
		),
		"save_performed": bool(result.get("save_performed", false)),
		"timestamp": Time.get_ticks_msec(),
	}
	set_meta("safe_logout_failure_diagnostic", diagnostic)
	_report_safe_logout_error(
		action,
		str(result.get("reason", "safe_logout_failed"))
	)
	var user_message := UIErrorFeedbackScript.from_result(result, "安全退出失败，请稍后重试。")
	if is_instance_valid(_system_menu_panel) and _system_menu_panel.visible:
		_system_menu_panel.show_save_exit_failure(user_message)
	if is_instance_valid(hud) and hud.has_method("show_error_message"):
		# Player sees Chinese prose only; the raw reason stays in the
		# diagnostic above and in push_error via the reporter.
		hud.show_error_message(
			user_message,
			2.0
		)


func _handle_home_resolution_failure(
	action: StringName,
	result: Dictionary
) -> void:
	var diagnostic := {
		"action": str(action),
		"reason": str(result.get("reason", "home_resolution_failed")),
		"home_source": str(result.get("source", "")),
		"current_map_id": current_map_id,
		"player_position": (
			player.global_position if is_instance_valid(player) else Vector2.ZERO
		),
		"timestamp": Time.get_ticks_msec(),
	}
	set_meta("home_resolution_failure_diagnostic", diagnostic)
	_report_safe_logout_error(
		action,
		str(result.get("reason", "home_resolution_failed"))
	)
	if is_instance_valid(hud) and hud.has_method("show_error_message"):
		# Player-readable Chinese only; the raw resolution reason is retained
		# in the diagnostic above and in push_error via the reporter.
		hud.show_error_message("无法确定安全返回位置。", 2.0)


func _report_safe_logout_error_production(action: StringName, reason: String) -> void:
	push_error(
		"safe logout failed for %s: %s" % [str(action), reason]
	)


func _report_safe_logout_error(action: StringName, reason: String) -> void:
	if _safe_logout_error_reporter.is_valid():
		_safe_logout_error_reporter.call(action, reason)


func set_safe_logout_error_reporter(reporter: Callable) -> void:
	if PlayerState.test_mode:
		_safe_logout_error_reporter = reporter


func change_zone(zone_name: String, initial := false) -> void:
	var target_map_id := -1
	var map_data: Dictionary = GameData.get_map(zone_name)
	if zone_name == "比奇城":
		map_data = GameData.get_map_by_id(GameData.service_runtime_map_id(0))
	if not map_data.is_empty():
		target_map_id = int(map_data.get("mapId", -1))
	var operation := Callable(self, "_change_zone_immediate").bind(zone_name, initial)
	if _should_animate_map_transition(initial):
		_begin_map_transition(operation, target_map_id)
	else:
		operation.call()


func _change_zone_immediate(zone_name: String, initial := false) -> void:
	if zone_name == "比奇城":
		# 旧样板把“比奇城”画成独立伪地图；经典客户端中城镇属于0.map的比奇省。
		# 保留旧调用兼容，但统一进入服务端地图0所映射的运行地图4。
		var bich_map := GameData.get_map_by_id(GameData.service_runtime_map_id(0))
		var home := _resolve_bich_home()
		if not bool(home.get("valid", false)):
			_handle_home_resolution_failure(&"change_zone_bich", home)
			return
		_load_zone(str(bich_map.get("name", "比奇省")), initial, bich_map)
		_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
		background.set_focus_position(player.global_position)
		return
	_load_zone(zone_name, initial, GameData.get_map(zone_name))


func travel_to_service_home(
	red_name := false,
	initial := false,
	fallback_zone := "",
	after_arrival := Callable()
) -> bool:
	# P1-002/004: always route through coordinator pipeline
	var service_map_id := GameData.service_home_map_id(red_name)
	var runtime_map_id := GameData.service_runtime_map_id(service_map_id)
	var home_result := _resolve_bich_home()
	if not bool(home_result.get("valid", false)):
		_handle_home_resolution_failure(&"travel_to_service_home", home_result)
		return false
	var operation := Callable(self, "_complete_service_home_travel").bind(
		red_name, initial, fallback_zone, after_arrival
	)
	return _begin_map_transition(operation, runtime_map_id)


func _complete_service_home_travel(
	red_name: bool,
	initial: bool,
	fallback_zone: String,
	after_arrival: Callable
) -> void:
	_travel_to_service_home_immediate(red_name, initial, fallback_zone)
	if after_arrival.is_valid():
		after_arrival.call()


func _travel_to_service_home_immediate(
	red_name := false,
	initial := false,
	fallback_zone := ""
) -> void:
	var home := _resolve_bich_home()
	if not bool(home.get("valid", false)):
		_handle_home_resolution_failure(&"service_home_immediate", home)
		return
	var service_map_id := GameData.service_home_map_id(red_name)
	var runtime_map_id := GameData.service_runtime_map_id(service_map_id)
	var map_data := GameData.get_map_by_id(runtime_map_id)
	if not map_data.is_empty():
		_load_zone(str(map_data.get("name", "比奇省")), initial, map_data)
		if not red_name and service_map_id == 0:
			# 服务端(289,618)直接进入700×700原MAP统一坐标，不再压缩到场景中心。
			_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
			player.velocity = Vector2.ZERO
			_relocate_main_pets_after_map_arrival()
			background.set_focus_position(player.global_position)
	else:
		# 红名地图3尚未进入项目地图表；保留显式回退，不伪造服务端映射。
		var resolved_fallback := fallback_zone
		if resolved_fallback.is_empty():
			resolved_fallback = "比奇省" if not red_name else "比奇郊外"
		_change_zone_immediate(resolved_fallback, initial)


func travel_to_map(map_id: int) -> void:
	_request_map_travel(map_id)


func _on_map_teleport_availability_requested(map_ids: Array) -> void:
	if not is_instance_valid(hud):
		return
	hud.set_map_teleport_availability(
		MapTeleportRuntimePolicyScript.rules_for_maps(
			map_ids,
			Callable(self, "_map_teleport_item_count_by_id"),
		)
	)


func _on_map_teleport_requested(request: Dictionary) -> void:
	if not gameplay_input_is_enabled() or _map_transition_in_progress:
		return
	var selected_map_id := int(request.get("selected_map_id", -1))
	var rule := MapTeleportRuntimePolicyScript.rule_for_map(
		selected_map_id,
		Callable(self, "_map_teleport_item_count_by_id"),
	)
	if not MapTeleportRuntimePolicyScript.request_matches_rule(request, rule):
		if is_instance_valid(hud):
			hud.set_map_teleport_availability({selected_map_id: rule})
			hud.show_error_message(
				UIErrorFeedbackScript.user_message(
					str(rule.get("reason", "传送条件已经失效"))
				)
			)
		return
	var destination_map_id := int(rule.get("destination_map_id", -1))
	var travel_profile := _resolve_projection_profile_for_map(destination_map_id)
	if not bool(travel_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(travel_profile.get("reason", ""))
		hud.show_error_message("目标地图投影暂不可用（%d）" % destination_map_id)
		return
	var map_data := GameData.get_map_by_id(destination_map_id)
	if map_data.is_empty():
		hud.show_error_message("地图数据不存在：%d" % destination_map_id)
		return
	var operation := Callable(self, "_teleport_to_map_immediate").bind(
		destination_map_id,
		str(rule.get("arrival_anchor_id", "")),
	)
	if not _begin_map_transition(operation, destination_map_id):
		hud.show_error_message("当前无法开始传送")


func _teleport_to_map_immediate(map_id: int, arrival_anchor_id: String) -> bool:
	var arrival := MapTeleportRuntimePolicyScript.resolve_arrival(
		map_id,
		arrival_anchor_id,
	)
	if not bool(arrival.get("valid", false)):
		return false
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		return false
	map_data = _runtime_named_map_data(map_data)
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != map_id:
		return false
	_set_player_world_position(arrival.get("position_px", Vector2.ZERO) as Vector2)
	player.velocity = Vector2.ZERO
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	_record_player_world_location()
	return true


func _map_teleport_item_count_by_id(item_id: int) -> int:
	if item_id <= 0:
		return 0
	var total := 0
	for raw_record: Variant in PlayerState.inventory:
		if not raw_record is Dictionary or (raw_record as Dictionary).is_empty():
			continue
		var record: Dictionary = raw_record
		var catalog_item := GameData.get_item_record(record)
		if int(catalog_item.get("itemId", -1)) == item_id:
			total += maxi(0, int(record.get("count", 1)))
	return total


func _request_map_travel(map_id: int) -> bool:
	if not gameplay_input_is_enabled(): return false
	map_id = GameData.service_runtime_map_id(map_id)
	# FREEZE-P0.2: refuse travel before the transition when the target map has
	# no formal projection profile; never load_zone into a half-broken world.
	var travel_profile := _resolve_projection_profile_for_map(map_id)
	if not bool(travel_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(
			travel_profile.get("reason", "")
		)
		hud.show_error_message("当前地图投影暂不可用（%d）" % map_id)
		return false
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		hud.show_error_message("地图数据不存在：%d" % map_id)
		return false
	if current_map_id == map_id:
		return false
	var operation := Callable(self, "_travel_to_map_immediate").bind(map_id)
	if _should_animate_map_transition(false):
		return _begin_map_transition(operation, map_id)
	return bool(operation.call())


func _travel_to_map_immediate(map_id: int) -> bool:
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty() or current_map_id == map_id:
		return false
	# Resolve Home before _load_zone tears down the source world. The staged
	# pipeline already has this gate; synchronous travel must fail closed too.
	if map_id == BICH_RUNTIME_MAP_ID:
		var home_result := _resolve_bich_home()
		if not bool(home_result.get("valid", false)):
			_handle_home_resolution_failure(&"sync_travel_arrival", home_result)
			return false
	map_data = _runtime_named_map_data(map_data)
	var source_map_id := current_map_id
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id == map_id:
		_set_player_world_position(route_arrival_position(map_id, source_map_id))
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
		background.set_focus_position(player.global_position)
	return current_map_id == map_id


func travel_via_portal(portal: ZonePortal, fresh_activation := true) -> bool:
	if not gameplay_input_is_enabled():
		return false
	if str(portal.portal_data.get("portal_contract_id", "")) != MapPortalRuntimeServiceScript.PORTAL_CONTRACT_ID:
		return _request_map_travel(portal.target_map_id)
	var portal_id := str(portal.portal_data.get("source_portal_id", ""))
	var current_runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		current_runtime, portal_id
	)
	if endpoint.is_empty():
		hud.show_error_message("传送节点端点不存在", 1.5)
		return false
	var current_ground_gu := (
		MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			current_runtime, player.global_position
		)
		if not current_runtime.is_empty()
		else Vector2.ZERO
	)
	if not MapPortalTravelGuardScript.can_activate(
		_portal_guard_state,
		_portal_guard_key(current_map_id, portal_id),
		Time.get_ticks_msec(),
		current_ground_gu,
		fresh_activation
	):
		hud.show_error_message("传送节点尚未稳定，请稍候或先离开入口", 1.5)
		return false
	var request := MapPortalRuntimeServiceScript.travel_request(endpoint)
	if not _valid_portal_request(request):
		hud.show_error_message("传送节点配置无效", 1.5)
		return false
	if not MapPortalTravelGuardScript.begin_travel(_portal_guard_state):
		return false
	var portal_claim_id := MapPortalTravelGuardScript.active_claim_id(
		_portal_guard_state
	)
	_active_portal_claim_id = portal_claim_id
	var target_map_id := int(request.get("target_map_id", -1))
	var map_data := GameData.get_map_by_id(target_map_id)
	if map_data.is_empty():
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("地图数据不存在：%d" % target_map_id)
		return false
	var target_runtime := MapEditorRuntimeBridgeScript.load_map(target_map_id)
	var target_portal_id := str(request.get("target_portal_id", ""))
	var target_endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		target_runtime, target_portal_id
	)
	if target_runtime.is_empty() or target_endpoint.is_empty():
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标地图或目标门点不可用", 1.5)
		return false
	if str(target_runtime.get("source", {}).get("map_id", "")) != str(request.get("target_map_key", "")):
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标地图标识不匹配", 1.5)
		return false
	var target_tile := _portal_tile(target_endpoint.get("tile", []))
	if target_tile == Vector2.INF or target_tile != _portal_tile(request.get("target_tile", [])):
		_cancel_portal_travel_claim(portal_claim_id)
		hud.show_error_message("目标门点坐标不匹配", 1.5)
		return false
	map_data = _runtime_named_map_data(map_data)
	var operation := Callable(self, "_complete_portal_travel").bind(
		target_map_id,
		map_data,
		target_runtime,
		target_portal_id,
		target_tile,
		portal_claim_id
	)
	if _should_animate_map_transition(false):
		if _begin_map_transition(operation, target_map_id, portal_claim_id):
			return true
		_cancel_portal_travel_claim(portal_claim_id)
		return false
	return bool(operation.call())


func _complete_portal_travel(
	target_map_id: int,
	map_data: Dictionary,
	target_runtime: Dictionary,
	target_portal_id: String,
	target_tile: Vector2,
	portal_claim_id: String
) -> bool:
	if portal_claim_id != MapPortalTravelGuardScript.active_claim_id(_portal_guard_state):
		return false
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != target_map_id:
		_cancel_portal_travel_claim(portal_claim_id)
		return false
	var arrival_ground_gu := MapEditorRuntimeBridgeScript.cell_to_ground_position_gu(
		[target_tile.x, target_tile.y]
	)
	var arrival_position := (
		MapEditorRuntimeBridgeScript.ground_position_gu_to_screen_position_px(
			target_runtime,
			arrival_ground_gu
		)
	)
	_set_player_world_position(arrival_position)
	player.velocity = Vector2.ZERO
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	MapPortalTravelGuardScript.finish_arrival(
		_portal_guard_state,
		_portal_guard_key(target_map_id, target_portal_id),
		Time.get_ticks_msec(),
		arrival_ground_gu
	)
	_active_portal_claim_id = ""
	_active_portal_claim_transition_serial = -1
	return true


func _should_animate_map_transition(initial: bool) -> bool:
	return (
		not initial
		and not PlayerState.test_mode
		and is_instance_valid(hud)
		and hud.has_method("begin_loading_transition")
		and hud.has_method("finish_loading_transition")
		and hud.has_signal("loading_transition_covered")
	)


func _begin_initial_world_bootstrap() -> void:
	if _world_bootstrap_in_progress:
		return
	_world_bootstrap_in_progress = true
	_acquire_gameplay_input_lock(INPUT_LOCK_INITIAL_BOOTSTRAP)
	var target_map_id := (
		current_map_id
		if current_map_id >= 0
		else GameData.service_home_runtime_map_id(false)
	)
	_world_bootstrap_coordinator.begin_initial_world(target_map_id)
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)

	if (
		not PlayerState.test_mode
		and is_instance_valid(hud)
		and hud.has_method("begin_loading_transition")
	):
		hud.begin_loading_transition("world:bootstrap:initial")

	# P1-B: Ensure Loading renders at least one frame before heavy work.
	# Production uses real process_frame; tests inject a controlled barrier.
	if _world_bootstrap_coordinator.loading_frame_barrier.is_valid():
		await _world_bootstrap_coordinator.loading_frame_barrier.call()
	else:
		await get_tree().process_frame
	_world_bootstrap_coordinator.loading_barrier_completed()

	# HC-P1-004: initial world goes through the same staged coordinator
	# pipeline as map transitions (collect -> prefetch -> map -> collision ->
	# actors -> READY contract). Input stays locked until READY.
	var accepted := travel_to_service_home(false, true)
	if not accepted:
		_world_bootstrap_coordinator.finish(false, "initial_travel_rejected")
		_world_bootstrap_in_progress = false
		return
	var bootstrap_deadline := (
		Time.get_ticks_msec() + INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC
	)
	while (
		(_map_transition_in_progress
			or _world_bootstrap_coordinator.stage not in [
				WorldBootstrapCoordinator.Stage.READY,
				WorldBootstrapCoordinator.Stage.FAILED,
			])
		and Time.get_ticks_msec() < bootstrap_deadline
	):
		await get_tree().process_frame
	if (
		_map_transition_in_progress
		or _world_bootstrap_coordinator.stage not in [
			WorldBootstrapCoordinator.Stage.READY,
			WorldBootstrapCoordinator.Stage.FAILED,
		]
	):
		# A formal map may require substantially more resources than the legacy
		# 11-map slice. Never release input onto a half-built world when the
		# bounded bootstrap deadline is exhausted.
		# Retire the coordinator owner before releasing the transition boundary;
		# suspended pipeline coroutines must fail closed at their next await.
		_world_bootstrap_coordinator.revoke_current_generation()
		_active_map_transition_id = ""
		_map_transition_in_progress = false
		_world_bootstrap_coordinator.finish(false, "initial_bootstrap_timeout")
		_world_bootstrap_in_progress = false
		return
	if _world_bootstrap_coordinator.stage == WorldBootstrapCoordinator.Stage.FAILED:
		# Keep the input lock and Loading overlay; the bootstrap failed and the
		# game must not accept gameplay on a half-built world.
		_world_bootstrap_in_progress = false
		return
	_record_player_world_location()
	# perf-smoothness-r1 Phase C: initial-world READY releases the loading
	# window; combat-time texture misses now queue for async warm-up.
	CasterSkillVisualRegistry.set_loading_window_active(false)
	_on_player_stats_changed(player.current_hp, player.max_hp)
	_world_bootstrap_in_progress = false
	_release_gameplay_input_lock(INPUT_LOCK_INITIAL_BOOTSTRAP)


func _begin_map_transition(
	operation: Callable,
	target_map_id := -1,
	portal_claim_id := ""
) -> bool:
	if _map_transition_in_progress or not operation.is_valid():
		return false
	if not is_instance_valid(player):
		return false
	var revival_authorized := _death_revival_request_in_flight and not _active_death_id.is_empty()
	if (player._dead or player.current_hp <= 0) and not revival_authorized:
		return false
	_map_transition_serial += 1
	if not portal_claim_id.is_empty():
		_active_portal_claim_transition_serial = _map_transition_serial
	var combat_token := "map-combat:%d" % _map_transition_serial
	if not player.begin_combat_transition(combat_token, revival_authorized):
		return false
	_world_bootstrap_coordinator.begin_map_transition(target_map_id)
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)
	_active_map_transition_id = "map:%d:%d" % [
		Time.get_ticks_msec(),
		_map_transition_serial,
	]
	set_meta("map_combat_transition_token", combat_token)
	_map_transition_in_progress = true
	_map_transition_environment_replaced = false
	if is_instance_valid(_town_music_controller):
		_town_music_controller.begin_map_transition(target_map_id, _active_map_transition_id)
	# A new transition takes over the retained terminal map lock, if any.
	if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
		_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
	_cancel_map_transition_movement_input()
	_run_map_transition(_active_map_transition_id, operation, target_map_id)
	return true


func _begin_monster_transition_prefetch(target_map_id: int) -> Dictionary:
	# Same-map Home/revival/teleport keeps the existing EnemyActors: _load_zone
	# returns without rebuilding that world. Do not fence their visual leases
	# merely because a Loading transition is shown. A real map change (or first
	# bootstrap) still starts a new generation and rejects stale actors.
	if target_map_id == current_map_id and target_map_id >= 0 and not _world_bootstrap_in_progress:
		return {"complete": true, "preserved_world": true}
	return _streaming_coordinator.begin_map_prefetch(
		_monster_ids_for_map(target_map_id), _world_bootstrap_in_progress
	)


func _run_map_transition(
	transition_id: String,
	operation: Callable,
	target_map_id: int
) -> void:
	hud.begin_loading_transition(transition_id)
	# perf(R13-D1): total-loading timing profile. Read-only diagnostics only;
	# the production execution order below is untouched. Covered = the moment
	# the overlay confirmed coverage (loading_transition_covered); total = the
	# moment the loading cover lift starts (fade excluded).
	var r13_mode := "map_transition"
	if _world_bootstrap_in_progress:
		r13_mode = "initial_world"
	var r13_loading_profile := {
		"mode": r13_mode,
		"transition_id": transition_id,
		"target_map_id": target_map_id,
		"covered_usec": 0,
		"monster_prefetch_ms": 0.0,
		"world_pipeline_ms": 0.0,
		"actor_spawn_ms": 0.0,
		"skill_workset_ms": 0.0,
		"render_warm_ms": 0.0,
		"ui_panels_ms": 0.0,
		"finalize_ms": 0.0,
	}
	var r13_stage_started_usec := Time.get_ticks_usec()
	if not PlayerState.test_mode:
		while _map_transition_in_progress and _active_map_transition_id == transition_id:
			var request: Dictionary = await hud.loading_transition_covered
			if (
				str(request.get("contract_id", "")) == LoadingTransitionOverlay.CONTRACT_ID
				and str(request.get("transition_id", "")) == transition_id
			):
				r13_loading_profile["covered_usec"] = Time.get_ticks_usec()
				break
	else:
		# Test mode skips the real covered await; anchor at begin for the
		# stage decomposition (diagnostics only).
		r13_loading_profile["covered_usec"] = r13_stage_started_usec
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	hud.update_loading_progress(transition_id, 0.05, "准备场景")
	# The player-visible bar reports completed loading stages; UI construction
	# is included in the initial covered window after the world becomes ready.
	_last_monster_prefetch_status.clear()
	r13_stage_started_usec = Time.get_ticks_usec()
	_preload_map_loot_icons(target_map_id)
	if PlayerState.test_mode:
		_last_monster_prefetch_status = {"complete": true}
	elif _monster_prefetch_enabled and target_map_id >= 0:
		_last_monster_prefetch_status = (
			_begin_monster_transition_prefetch(target_map_id)
		)
		var prefetch_deadline := (
			Time.get_ticks_msec() + MONSTER_PREFETCH_TIMEOUT_MSEC
		)
		while (
			_map_transition_in_progress
			and _active_map_transition_id == transition_id
			and not bool(_last_monster_prefetch_status.get("complete", false))
			and Time.get_ticks_msec() < prefetch_deadline
		):
			await get_tree().process_frame
			_last_monster_prefetch_status = (
				_streaming_coordinator.poll_once(Engine.get_process_frames())
			)
	elif _monster_prefetch_enabled:
		_streaming_coordinator.release_map_pins()
	r13_loading_profile["monster_prefetch_ms"] = (
		float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	hud.update_loading_progress(transition_id, 0.22, "资源已准备")
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	# HC-P1-004: stage the world build through the coordinator budget queues
	# (resource scope -> threaded prefetch -> map items -> collisions). The
	# operation below only performs zone arrival (content spawn + player
	# placement); WorldBackground.set_zone_data() skips the rebuild because the
	# environment was already staged-built for the same map.
	r13_stage_started_usec = Time.get_ticks_usec()
	var built_ok := await _run_world_build_pipeline(target_map_id, transition_id)
	# A cancelled old pipeline also returns false; only its current owner
	# may update the HUD or route a genuine failure through recovery.
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	r13_loading_profile["world_pipeline_ms"] = (
		float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	if built_ok:
		hud.update_loading_progress(transition_id, 0.58, "地图已建立")
	if not built_ok:
		# P0-3: pre-arrival failure - the coordinator is already FAILED and
		# the old world is untouched. Own the whole FAILED transition through
		# the central recovery function instead of stranding the transition
		# lock, the player combat token and the Loading overlay.
		_fail_map_transition(&"pre_arrival_keep_world")
		return
	r13_stage_started_usec = Time.get_ticks_usec()
	_world_bootstrap_coordinator.begin_actor_collection(Callable(self, "_validate_queued_actor_descriptor"))
	_collecting_staged_actor_plan = true
	_staged_actor_source_index = 0
	_staged_actor_spawn_failure_reason = ""
	operation.call()
	_collecting_staged_actor_plan = false
	_world_bootstrap_coordinator.close_actor_collection()
	_feature_target_bound.sync_world(_world_context.capture_world())
	if not _staged_actor_spawn_failure_reason.is_empty() or not _feature_target_bound.seal():
		_world_bootstrap_coordinator.finish(false, "published_birth_plan_failed")
		_fail_map_transition(&"post_arrival_safe_home")
		return
	if PlayerState.test_mode:
		# Preserve the established deterministic synchronous travel hook while
		# exercising the identical descriptor handler and slice accounting.
		_world_bootstrap_coordinator.process_actor_queue_blocking(
			Callable(self, "_spawn_staged_actor_descriptor"),
			_bootstrap_max_items_per_frame(),
			_bootstrap_slice_budget_ms()
		)
	else:
		await _world_bootstrap_coordinator.process_actor_queue(
			Callable(self, "_spawn_staged_actor_descriptor"),
			_bootstrap_max_items_per_frame(),
			_bootstrap_slice_budget_ms()
		)
	r13_loading_profile["actor_spawn_ms"] = (
		float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
	)
	hud.update_loading_progress(transition_id, 0.75, "人物和怪物已就位")
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	var actor_summary := _world_bootstrap_coordinator.ready_contract_summary()
	if (
		int(actor_summary.get("failed_actors", 0)) != 0
		or int(actor_summary.get("duplicate_actors", 0)) != 0
		or int(actor_summary.get("planned_actors", 0))
		!= int(actor_summary.get("spawned_actors", 0))
		+ int(actor_summary.get("deferred_actors", 0))
	):
		_world_bootstrap_coordinator.finish(false, "actor_spawn_plan_failed")
		# P0-3: the world was already swapped by operation.call(), so this
		# is a post-arrival failure - recover through the safe home instead
		# of stranding the lock/token/Loading over an incomplete world.
		_fail_map_transition(&"post_arrival_safe_home")
		return
	if not PlayerState.test_mode:
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.FINALIZE)
	# P0-3b: route_arrival_position never consults environment collision
	# (the collision layer does not exist yet at selection time), so a map
	# whose routed arrival point sits on an environment-blocked cell used
	# to hard-fail the ready contract even though the world itself is
	# complete. With collision built, relocate the player to the nearest
	# unblocked point before validating; the blocked-arrival invariant the
	# contract enforces ("the player never stands inside a wall") is then
	# satisfied in the freshly built world instead of discarding the whole
	# transition.
	_maybe_relocate_blocked_arrival()
	if _check_world_ready_contract():
		_relocate_main_pets_after_map_arrival()
		# FW-COLD (perf-smoothness-r1 C-R1): thread-pumped, deadline-aware
		# prewarm of the ACTUAL bound workset under the loading overlay. The
		# first real cast of every workset skill must be a pure texture-cache
		# hit. Loading-phase work only: damage, spatial index and fire wall
		# systems are untouched.
		r13_stage_started_usec = Time.get_ticks_usec()
		var r13_workset_diag: Dictionary = (
			await _prewarm_learned_skill_visuals()
		)
		r13_loading_profile["skill_workset_ms"] = (
			float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		hud.update_loading_progress(transition_id, 0.76, "技能资源已准备")
		# FW-COLD2 Phase B + PERF-R2 R7/C8: the GPU render warm is bound to
		# the workset - a warrior/taoist without fire wall bound never pays
		# for fire-wall warm-up here. R14-C7 + R14-C-R1 P0-11..16: the warm
		# covers every workset skill's prewarmed facing sequence under a hard
		# ~1s budget and reports a structured result merged into
		# [LOADING-TOTAL].
		r13_stage_started_usec = Time.get_ticks_usec()
		var r13_render_warm_diag: Dictionary = {}
		if not _active_skill_workset_candidates().is_empty():
			r13_render_warm_diag = await _warm_fire_wall_render_path()
		r13_loading_profile["render_warm_ms"] = (
			float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		hud.update_loading_progress(transition_id, 0.80, "画面已准备")
		r13_loading_profile["render_warm_diag"] = r13_render_warm_diag
		if not _map_transition_in_progress or _active_map_transition_id != transition_id:
			return
		if _world_bootstrap_in_progress and hud.has_method("prewarm_all_panels"):
			hud.update_loading_progress(transition_id, 0.81, "准备界面")
			r13_stage_started_usec = Time.get_ticks_usec()
			await hud.prewarm_all_panels(_system_menu_panel)
			# Initial Loading has a bounded window for inventory icons as well.
			# The HUD advances one batch per frame and survives map teardown
			# without a suspended icon-prewarm coroutine.
			if not hud._catalog_icon_prewarm_complete:
				hud._start_catalog_icon_prewarm(false)
			var catalog_deadline_msec := int(
				float(r13_loading_profile.get("covered_usec", 0)) / 1000.0
			) + 9000
			while (
				_map_transition_in_progress
				and _active_map_transition_id == transition_id
				and not hud._catalog_icon_prewarm_complete
				and Time.get_ticks_msec() < catalog_deadline_msec
			):
				await get_tree().process_frame
			r13_loading_profile["ui_panels_ms"] = (
				float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
			)
			if not hud.all_panels_are_prewarmed():
				push_warning("Loading ended with incomplete UI panel prewarm; the background retry remains available")
			if not hud._catalog_icon_prewarm_complete:
				push_warning("Loading ended with item icons still prewarming in background")
			if not _map_transition_in_progress or _active_map_transition_id != transition_id:
				return
		# perf(R13-D2): Finalize restarts its own timer HERE - it must never
		# include the render-warm span (stages do not overlap).
		r13_stage_started_usec = Time.get_ticks_usec()
		if is_instance_valid(_town_music_controller):
			_town_music_controller.set_map_context(
				current_map_id,
				_active_safe_zones,
				_canonical_screen_px_to_ground_gu(player.global_position),
				transition_id
			)
		# Release the world first. Reusable UI then warms invisibly in small,
		# frame-separated batches; this keeps Loading and gameplay input responsive
		# while removing the one-time cost from the player's first panel click.
		# perf-smoothness-r1 Phase C: map-transition READY releases the loading
		# window the same way the initial-world READY does.
		CasterSkillVisualRegistry.set_loading_window_active(false)
		# perf(R13-D1): finalize = READY release tail (music context + window
		# close) up to the finish_loading_transition call. Total = covered ->
		# finish, the player-visible Loading duration (fade excluded). Bootstrap
		# stage data comes from the coordinator's own non-destructive
		# diagnostic - no second implementation.
		r13_loading_profile["finalize_ms"] = (
			float(Time.get_ticks_usec() - r13_stage_started_usec) / 1000.0
		)
		var r13_bootstrap_diag: Dictionary = (
			_world_bootstrap_coordinator.diagnostic
		)
		var r13_total_usec: int = maxi(
			1,
			Time.get_ticks_usec() - int(r13_loading_profile.get("covered_usec", 0)),
		)
		r13_loading_profile["total_ms"] = float(r13_total_usec) / 1000.0
		if OS.is_debug_build():
			print("[LOADING-TOTAL] ", JSON.stringify({
				"mode": r13_loading_profile.get("mode", ""),
				"transition_id": str(r13_loading_profile.get("transition_id", "")),
				"target_map_id": int(r13_loading_profile.get("target_map_id", -1)),
				"monster_prefetch_ms": float(r13_loading_profile.get("monster_prefetch_ms", 0.0)),
				"world_pipeline_ms": float(r13_loading_profile.get("world_pipeline_ms", 0.0)),
				"actor_spawn_ms": float(r13_loading_profile.get("actor_spawn_ms", 0.0)),
				"skill_workset_ms": float(r13_loading_profile.get("skill_workset_ms", 0.0)),
				"render_warm_ms": float(r13_loading_profile.get("render_warm_ms", 0.0)),
				"ui_panels_ms": float(r13_loading_profile.get("ui_panels_ms", 0.0)),
				"catalog_icon_prewarm_complete": hud._catalog_icon_prewarm_complete,
				"render_warm": {
					"skills_considered": int(
						r13_render_warm_diag.get("skills_considered", 0)
					),
					"skills_warmed": int(
						r13_render_warm_diag.get("skills_warmed", 0)
					),
					"frames_drawn": int(
						r13_render_warm_diag.get("frames_drawn", 0)
					),
					"budget_exhausted": bool(
						r13_render_warm_diag.get("budget_exhausted", false)
					),
					"elapsed_ms": float(
						r13_render_warm_diag.get("elapsed_ms", 0.0)
					),
					"lease_refcount_before": int(
						r13_render_warm_diag.get("lease_refcount_before", 0)
					),
					"lease_refcount_after": int(
						r13_render_warm_diag.get("lease_refcount_after", 0)
					),
				},
				"finalize_ms": float(r13_loading_profile.get("finalize_ms", 0.0)),
				"total_ms": float(r13_loading_profile.get("total_ms", 0.0)),
				"prewarm_deadline_exceeded": bool(
					r13_workset_diag.get("deadline_exceeded", false)
				),
				"prewarm_tail_after_deadline_ms": float(
					r13_workset_diag.get("tail_after_deadline_ms", 0.0)
				),
				"stage_elapsed_ms": r13_bootstrap_diag.get("stage_elapsed_ms", {}),
				"map_slice_count": int(r13_bootstrap_diag.get("map_slice_count", 0)),
				"collision_slice_count": int(r13_bootstrap_diag.get("collision_slice_count", 0)),
				"actor_slice_count": int(r13_bootstrap_diag.get("actor_slice_count", 0)),
				"map_max_slice_ms": float(r13_bootstrap_diag.get("map_max_slice_ms", 0.0)),
				"collision_max_slice_ms": float(r13_bootstrap_diag.get("collision_max_slice_ms", 0.0)),
				"actor_max_slice_ms": float(r13_bootstrap_diag.get("actor_max_slice_ms", 0.0)),
				"actor_max_item_ms": float(r13_bootstrap_diag.get("actor_max_item_ms", 0.0)),
			}))
		hud.update_loading_progress(transition_id, 1.0, "进入游戏")
		hud.finish_loading_transition()
		# FRAME-STALL discipline (remote review 2026-09-16): arm the generic
		# long-frame probe only now - loading has ended and the prewarm
		# baseline has printed - so bootstrap spikes cannot consume it.
		_first_combat_probe_armed = true
		_print_session_diagnostics_header()
		if PlayerState.test_mode and hud.loading_transition_overlay != null:
			# Test-mode fast path hides the fade overlay immediately so tests
			# can assert the bootstrap completed without waiting the fade tween.
			hud.loading_transition_overlay.hide()
			hud.loading_transition_overlay.modulate.a = 1.0
		_active_map_transition_id = ""
		_map_transition_in_progress = false
		# Same-map home/revival/teleport preserves this world and creates no
		# new actor descriptors. Only a previously successful READY may certify
		# that exact retained generation on a later transition.
		_ready_world_map_id = current_map_id
		_ready_world_zone_generation = _zone_generation
		_map_failure_recovery_active = false
		_map_transition_environment_replaced = false
		var bootstrap_profile := _world_bootstrap_coordinator.finish(
			true, "map_transition_ready"
		)
		if OS.is_debug_build() and _world_bootstrap_in_progress:
			print("[WorldBootstrapProfile] ", JSON.stringify({
				"total_ms": float(bootstrap_profile.get("total_duration_ms", 0.0)),
				"stages_ms": bootstrap_profile.get("stage_elapsed_ms", {}),
				"map_slices": int(bootstrap_profile.get("map_slice_count", 0)),
				"collision_slices": int(bootstrap_profile.get("collision_slice_count", 0)),
				"actor_slices": int(bootstrap_profile.get("actor_slice_count", 0)),
				"planned_actors": int(bootstrap_profile.get("planned_actors", 0)),
				"spawned_actors": int(bootstrap_profile.get("spawned_actors", 0)),
				"deferred_actors": int(bootstrap_profile.get("deferred_actors", 0)),
				"failed_actors": int(bootstrap_profile.get("failed_actors", 0)),
				"duplicate_actors": int(bootstrap_profile.get("duplicate_actors", 0)),
				"actor_total_ms": float(bootstrap_profile.get("actor_total_ms", 0.0)),
				"actor_max_item_ms": float(bootstrap_profile.get("actor_max_item_ms", 0.0)),
				"actor_max_slice_ms": float(bootstrap_profile.get("actor_max_slice_ms", 0.0)),
				"max_slice_ms": float(bootstrap_profile.get("max_slice_ms", 0.0)),
				"hud": hud.panel_prewarm_diagnostic(),
			}))
		# Cancel again immediately before READY releases the lock. This covers a
		# release delivered during the lock as well as a release lost entirely.
		_cancel_map_transition_movement_input()
		player.finish_combat_transition(str(get_meta("map_combat_transition_token", "")))
		_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if not PlayerState.test_mode and hud.has_method("start_budgeted_panel_prewarm"):
			hud.start_budgeted_panel_prewarm(_system_menu_panel)
	else:
		# P0-3: READY contract failed after the world swap (post-arrival).
		# The player must never act on an incomplete world, but the FAILED
		# transition may not strand its lock/token/Loading either - hand the
		# whole thing to the central recovery owner (safe home).
		_world_bootstrap_coordinator.finish(false, "ready_contract_failed")
		_fail_map_transition(&"post_arrival_safe_home")


## P0-3b: nearest-unblocked-point relocation for a blocked routed arrival.
## Only relocates a living player whose current position is actually
## environment-blocked; every other condition is left to the normal ready
## contract / failure paths. Bounded spiral search keeps the relocation
## deterministic and cheap.
func _maybe_relocate_blocked_arrival() -> void:
	if player == null or not is_instance_valid(player):
		return
	if not is_instance_valid(background):
		return
	if bool(player._dead) or int(player.current_hp) <= 0:
		return
	if not background.is_environment_point_blocked(player.global_position):
		return
	var origin := player.global_position
	var best := Vector2.INF
	var radius := 24.0
	while radius <= 320.0 and best == Vector2.INF:
		var steps := maxi(8, int(radius / 4.0))
		for i: int in steps:
			var angle := TAU * float(i) / float(steps)
			var candidate := origin + Vector2(cos(angle), sin(angle)) * radius
			if not background.is_environment_point_blocked(candidate):
				best = candidate
				break
		radius += 24.0
	if best == Vector2.INF:
		return
	player.global_position = best
	player.velocity = Vector2.ZERO
	if is_instance_valid(background):
		background.set_focus_position(player.global_position)
	print("[MapTransition] blocked arrival point; relocated player to nearest unblocked point (%.0f, %.0f)" % [best.x, best.y])


## P0-3: single owner for a FAILED map transition. Every FAILED path funnels
## here; no implicit combat token, map-transition lock or Loading overlay may
## survive the call. Callers must have already finished the coordinator with
## the concrete failure reason (this function reads it for the user message).
## pre_arrival_keep_world: the old world is still current - keep it playable
## and surface a retryable error.
## post_arrival_safe_home: the world was swapped but is not contract-ready -
## relocate the player to the resolved safe home so an incomplete map is
## never handed to gameplay input.
func _fail_map_transition(recovery_policy: StringName) -> void:
	var failed_transition_serial := _map_transition_serial
	# A portal operation owns its single-flight claim across the whole async
	# transition. Retire only that claim when the transition fails before the
	# bound operation reaches _complete_portal_travel.
	if _active_portal_claim_transition_serial == failed_transition_serial:
		_cancel_portal_travel_claim(_active_portal_claim_id)
	# prepare_map_build clears the prior real environment before arrival.
	# After that boundary a pre-arrival failure cannot keep it playable.
	if recovery_policy == &"pre_arrival_keep_world" and _map_transition_environment_replaced:
		recovery_policy = &"post_arrival_safe_home"
	var coordinator := _world_bootstrap_coordinator
	var reason := "map_transition_failed"
	if coordinator != null and is_instance_valid(coordinator):
		reason = str(coordinator.diagnostic.get("failure_reason", reason))
	if player != null and is_instance_valid(player):
		player.finish_combat_transition(str(get_meta("map_combat_transition_token", "")))
	_cancel_map_transition_movement_input()
	_active_map_transition_id = ""
	_map_transition_in_progress = false
	if _map_failure_recovery_active:
		# The failed destination was already unsafe. A failed real home build
		# cannot restore it, release input, or recursively start another home.
		_map_failure_recovery_active = false
		if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
			_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if is_instance_valid(hud):
			hud.finish_loading_transition()
			hud.show_error_message("安全区域加载失败，请重新进入游戏。", 4.0)
		print("[MapTransition] terminal safe-home failure reason=%s" % reason)
		return
	if is_instance_valid(hud):
		hud.finish_loading_transition()
		if recovery_policy == &"pre_arrival_keep_world":
			hud.show_error_message("地图切换失败，已保留当前区域，可稍后重试。", 4.0)
		elif recovery_policy == &"post_arrival_safe_home":
			hud.show_error_message("地图加载未完成，正在送回安全点。", 4.0)
		else:
			hud.show_error_message("地图切换失败，请稍后重试。", 4.0)
	print("[MapTransition] FAILED reason=%s policy=%s" % [reason, str(recovery_policy)])
	if recovery_policy == &"post_arrival_safe_home":
		_map_failure_recovery_active = true
		# A player killed during the failed arrival goes through the
		# production death revival (home relocation + death state cleanup);
		# a living player goes through the plain safe-home relocation. An
		# in-flight death flow (hp 0, _dead not yet set) gets a short settle
		# window so the revival sees the real state; the transition lock is
		# only released after the recovery finished.
		if player != null and is_instance_valid(player):
			# Death settlement is queued and may land after the transition
			# already ended (the arrival fight can kill the player while the
			# ready-contract check is still running); give it a bounded
			# window to land so the recovery picks the right branch.
			var death_settle := Time.get_ticks_msec() + 5000
			while (
				int(player.current_hp) <= 0
				and not bool(player._dead)
				and Time.get_ticks_msec() < death_settle
			):
				await get_tree().create_timer(0.05, true).timeout
			# A real death-UI transition may take ownership during the settle
			# await. The old failure cannot release that new owner's lock.
			if _map_transition_serial != failed_transition_serial or not _map_failure_recovery_active:
				return
			print("[MapTransition] recovery state dead=%s hp=%d" % [
				str(player._dead), int(player.current_hp),
			])
			# The FAILED transition's own lock must go before a new home
			# transition can acquire it; the recovery transition re-owns
			# the lock and releases it through its own READY/FAILED path.
			if _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
				_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
			var recovery_started := false
			if bool(player._dead):
				# Formal production town revival: full home travel +
				# _finish_death_revival completion boundary (no bare
				# teleport - the player must land in the home WORLD).
				recovery_started = _request_production_town_revival()
			else:
				recovery_started = travel_to_service_home(
					false, true, "比奇省", Callable()
				)
			if recovery_started:
				print("[MapTransition] safe-home recovery transition started")
				return
		# No recovery exists: the current incomplete world stays closed.
		_map_failure_recovery_active = false
		if not _gameplay_input_locks.has(INPUT_LOCK_MAP_TRANSITION_LOCAL):
			_acquire_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if is_instance_valid(hud):
			hud.show_error_message("安全区域加载失败，请重新进入游戏。", 4.0)
		return
	# pre_arrival_keep_world (and future title-return): the current world is
	# safe to hand back to gameplay input, so the transition lock goes away.
	_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)


func _cancel_portal_travel_claim(claim_id: String) -> void:
	if claim_id.is_empty():
		return
	MapPortalTravelGuardScript.cancel_travel(_portal_guard_state, claim_id)
	if _active_portal_claim_id == claim_id:
		_active_portal_claim_id = ""
		_active_portal_claim_transition_serial = -1


## P0-3: formal production town revival for a dead player - constructs the
## revival request and hands it to the production handler, which owns the
## home travel, the revival completion boundary and the death-lock release.
func _request_production_town_revival() -> bool:
	if _active_death_id.is_empty() or _death_revival_request_in_flight:
		return false
	return _on_revival_requested({
		"contract_id": DEATH_REVIVAL_CONTRACT_ID,
		"death_id": _active_death_id,
		"option_slot": "town",
		"method_id": "revive.nearest_town",
	})


func _run_world_build_pipeline(map_id: int, transition_id: String) -> bool:
	var coordinator := _world_bootstrap_coordinator
	if coordinator == null or not is_instance_valid(background):
		return false
	var generation := coordinator.generation
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false

	# 1) COLLECT_REQUIREMENTS also clears the old real environment. Record
	# this ownership boundary before preparation, including failure returns.
	coordinator.advance(WorldBootstrapCoordinator.Stage.COLLECT_REQUIREMENTS)
	var target_map_data: Dictionary = {}
	if map_id >= 0:
		target_map_data = GameData.get_map_by_id(map_id)
	if target_map_data.is_empty():
		target_map_data = {"mapId": map_id, "name": "未命名地图"}
	_map_transition_environment_replaced = true
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	var prepared := background.prepare_map_build(
		map_id, coordinator, target_map_data
	)
	if not bool(prepared.get("ok", false)):
		coordinator.finish(false, "prepare_map_build_failed")
		return false
	var arrival_result := _pipeline_arrival_position(map_id)
	if not bool(arrival_result.get("valid", false)):
		_handle_home_resolution_failure(&"world_pipeline_arrival", arrival_result)
		coordinator.finish(false, "missing_target_arrival")
		return false
	background.set_pending_arrival_position(
		arrival_result.get("position_px", Vector2.ZERO) as Vector2
	)

	# 2) REQUEST_RESOURCES -> 3) WAIT_RESOURCES
	coordinator.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coordinator.request_threaded_prefetch()
	coordinator.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	if PlayerState.test_mode:
		if not coordinator.poll_threaded_prefetch_blocking():
			coordinator.finish(false, "prefetch_timeout")
			return false
	else:
		while true:
			if not _world_pipeline_owner_current(coordinator, generation, transition_id):
				return false
			if coordinator.poll_threaded_prefetch():
				break
			await get_tree().process_frame
	if coordinator.has_failed_required_resource():
		coordinator.finish(false, "prefetch_failed_required_resource")
		return false
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false

	# WALL-P1R C4: the descriptor queue is handed over only after
	# WAIT_RESOURCES (and the required-resource gate) completed, so
	# submit_staged_build's optimized/legacy mode selection can verify the
	# prefetched derived textures. The resource manifest was fully built
	# during prepare_map_build; nothing needs the queue before this point.
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	background.submit_staged_build()

	# 4) BUILD_MAP: one atomic map unit per queue task, frame-budgeted.
	coordinator.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	var max_items := _bootstrap_max_items_per_frame()
	var budget_ms := _bootstrap_slice_budget_ms()
	coordinator.defer_between_slices = not PlayerState.test_mode
	await coordinator.process_map_queue(
		Callable(background, "build_one_map_item"), max_items, budget_ms
	)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if coordinator.has_unexpected_sync_load():
		coordinator.finish(false, "unexpected_sync_load_during_build_map")
		return false
	if coordinator.planned_map_item_count != coordinator.built_map_item_count:
		coordinator.finish(false, "map_item_count_mismatch")
		return false

	# 5) BUILD_COLLISION: one atomic collision unit per queue task.
	coordinator.advance(WorldBootstrapCoordinator.Stage.BUILD_COLLISION)
	await coordinator.process_collision_queue(
		Callable(background, "build_one_collision"), max_items, budget_ms
	)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	if coordinator.has_unexpected_sync_load():
		coordinator.finish(false, "unexpected_sync_load_during_build_collision")
		return false
	if coordinator.failed_collision_count > 0:
		coordinator.finish(false, "collision_build_failed")
		return false
	if coordinator.planned_collision_count != coordinator.built_collision_count:
		coordinator.finish(false, "collision_count_mismatch")
		return false

	# 6) SPAWN_ACTORS: the arrival operation records production actor
	# descriptors after this pipeline returns. GameRoot then drains that exact
	# plan with the same frame budget before FINALIZE/READY.
	coordinator.advance(WorldBootstrapCoordinator.Stage.SPAWN_ACTORS)
	if not _world_pipeline_owner_current(coordinator, generation, transition_id):
		return false
	background.finish_map_build()
	return true


func _world_pipeline_owner_current(
	coordinator: WorldBootstrapCoordinator,
	generation: int,
	transition_id: String
) -> bool:
	## Every async resume and environment mutation belongs to both the
	## transition and the coordinator generation.  Generation alone is not
	## sufficient: timeout/recovery can retire it before a new generation starts.
	return (
		is_instance_valid(coordinator)
		and coordinator.is_generation_current(generation)
		and _map_transition_in_progress
		and _active_map_transition_id == transition_id
	)


func _bootstrap_max_items_per_frame() -> int:
	return int(ProjectSettings.get_setting(
		"world/loading/max_items_per_frame",
		WorldBootstrapCoordinator.DEFAULT_MAX_ITEMS_PER_FRAME
	))


func _bootstrap_slice_budget_ms() -> float:
	return float(ProjectSettings.get_setting(
		"world/loading/slice_budget_ms",
		WorldBootstrapCoordinator.DEFAULT_SLICE_BUDGET_MS
	))


func _pipeline_arrival_position(map_id: int) -> Dictionary:
	if map_id == BICH_RUNTIME_MAP_ID:
		return _resolve_bich_home()
	return {
		"valid": true,
		"position_px": route_arrival_position(map_id, current_map_id),
		"source": "route_arrival",
		"reason": "",
	}


func _check_world_ready_contract() -> bool:
	var coordinator := _world_bootstrap_coordinator
	if coordinator == null or not is_instance_valid(background):
		return false
	var summary := coordinator.ready_contract_summary()
	var birth_plan := feature_world_capacity_bound()
	if not bool(birth_plan.get("sealed", false)) or not bool(birth_plan.get("proved", false)):
		return false
	# FREEZE-P0.2: gameplay is only reachable in a projection-ready world. The
	# formal map profile gate keeps legacy Vector2 wrappers out of broken maps.
	var ready_profile := _resolve_projection_profile_for_map(current_map_id)
	if not bool(ready_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(ready_profile.get("reason", ""))
		return false

	if not coordinator.is_generation_current(int(summary.get("generation", -1))):
		return false
	if int(summary.get("map_id", -1)) != current_map_id:
		return false
	if background.environment_node_count() <= 0 and background.editor_runtime_chunk_texture_count() <= 0:
		return false
	if int(summary.get("planned_map_item_count", 0)) != int(summary.get("built_map_item_count", 0)):
		return false
	if int(summary.get("planned_collision_count", 0)) != int(summary.get("built_collision_count", 0)):
		return false
	if int(summary.get("failed_collision_count", 0)) != 0:
		return false
	if (
		int(summary.get("planned_actors", 0))
		!= int(summary.get("spawned_actors", 0))
		+ int(summary.get("deferred_actors", 0))
	):
		return false
	if int(summary.get("failed_actors", 0)) != 0:
		return false
	if int(summary.get("duplicate_actors", 0)) != 0:
		return false
	if int(summary.get("unexpected_sync_load_count", 0)) != 0:
		return false
	if not is_instance_valid(player):
		return false
	if background.is_environment_point_blocked(player.global_position):
		return false
	if not is_instance_valid(_world_camera):
		return false
	if (
		is_instance_valid(hud)
		and (int(hud._last_hp) != int(player.current_hp)
			or int(hud._last_max_hp) != int(player.max_hp))
	):
		return false
	# Necessary gameplay actors / door points must be present when the map
	# content declares them.
	var content: Dictionary = {}
	if MapEditorRuntimeBridgeScript.has_runtime_map(current_map_id):
		content = MapEditorRuntimeBridgeScript.game_content_for_map(current_map_id)
	if content.is_empty() and RegionContent.has_map(current_map_id):
		content = RegionContent.get_map_content(current_map_id)
	var declares_content: bool = (
		not (content.get("spawns", []) as Array).is_empty()
		or not (content.get("bosses", []) as Array).is_empty()
		or not (content.get("npcs", []) as Array).is_empty()
		or not (content.get("portals", []) as Array).is_empty()
	)
	# The generation's actor plan accounts for live AND persisted respawn
	# slots above. Boss-only maps are correctly empty until their deadline;
	# scene-wide groups also include queued old-map nodes, making this gate
	# intermittently reject the same valid save depending on load timing.
	var retained_ready_world := (
		_ready_world_map_id == current_map_id
		and _ready_world_zone_generation == _zone_generation
	)
	if declares_content and int(summary.get("planned_actors", 0)) <= 0 and not retained_ready_world:
		return false
	return true


func _preload_map_loot_icons(map_id: int) -> void:
	if map_id < 0:
		return
	var names := LootRuntime.possible_item_names_for_monster_ids(_monster_ids_for_map(map_id))
	LootPickup.prewarm_item_names(names)


func _monster_ids_for_map(map_id: int) -> Array[int]:
	var content: Dictionary = {}
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		content = MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
	if content.is_empty() and RegionContent.has_map(map_id):
		content = RegionContent.get_map_content(map_id)
	var result: Array[int] = []
	var seen := {}
	for group_name: String in ["spawns", "bosses"]:
		for raw_entry: Variant in content.get(group_name, []):
			if not raw_entry is Dictionary:
				continue
			var entry: Dictionary = raw_entry
			var raw_id: Variant = entry.get("monster_id", null)
			var monster_id := GameData.canonical_monster_id(raw_id)
			if (
				monster_id <= 0
				or GameData.get_canonical_monster_entry(
					monster_id, "runtime"
				).is_empty()
				or seen.has(monster_id)
			):
				continue
			seen[monster_id] = true
			result.append(monster_id)
	return result


func _valid_portal_request(request: Dictionary) -> bool:
	return (
		bool(request.get("ok", false))
		and int(request.get("target_map_id", -1)) >= 0
		and not str(request.get("target_map_key", "")).is_empty()
		and not str(request.get("target_portal_id", "")).is_empty()
		and str(request.get("arrival_guard_policy_id", "")) == MapPortalTravelGuardScript.POLICY_ID
		and is_equal_approx(float(request.get("return_minimum_seconds", 0.0)), 3.0)
		and is_equal_approx(
			float(request.get("return_unlock_distance_gu", -1.0)),
			MapPortalTravelGuardScript.UNLOCK_DISTANCE_GU
		)
		and bool(request.get("single_flight", false))
	)


func _portal_tile(raw_tile: Variant) -> Vector2:
	if not raw_tile is Array or raw_tile.size() != 2:
		return Vector2.INF
	return Vector2(float(raw_tile[0]), float(raw_tile[1]))


func _portal_guard_key(map_id: int, portal_id: String) -> String:
	return "%d:%s" % [map_id, portal_id]


func _runtime_named_map_data(map_data: Dictionary) -> Dictionary:
	var resolved := map_data.duplicate(true)
	var map_id := int(resolved.get("mapId", -1))
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		var content := MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
		if not content.is_empty():
			resolved["name"] = str(content.get("name", resolved.get("name", "未命名地图")))
	return resolved


func _update_portal_arrival_guard() -> void:
	var locked_key := str(_portal_guard_state.get("locked_portal_id", ""))
	if locked_key.is_empty() or bool(_portal_guard_state.get("travel_in_flight", false)):
		return
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if runtime.is_empty():
		return
	MapPortalTravelGuardScript.clear_lock_after_departure(
		_portal_guard_state,
		locked_key,
		MapEditorRuntimeBridgeScript.screen_position_px_to_ground_position_gu(
			runtime,
			player.global_position
		)
	)


func route_arrival_position(destination_map_id: int, source_map_id: int) -> Vector2:
	if MapEditorRuntimeBridgeScript.has_runtime_map(destination_map_id):
		return MapEditorRuntimeBridgeScript.portal_screen_position_px(
			destination_map_id, "", source_map_id
		)
	var content := RegionContent.get_map_content(destination_map_id)
	for portal: Dictionary in content.get("portals", []):
		if int(portal.get("target_map_id", -1)) == source_map_id:
			var portal_screen_px: Vector2 = portal.get("position", Vector2.ZERO)
			var interior_target_screen_px := (
				_bich_home_position_px_if_valid()
				if destination_map_id == BICH_RUNTIME_MAP_ID
				else Vector2.ZERO
			)
			var portal_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					portal_screen_px
				)
			)
			var interior_target_ground_gu := (
				GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
					interior_target_screen_px
				)
			)
			var inward_direction_ground_gu := (
				GroundUnitSpaceScript.normalized_ground_direction(
					portal_ground_gu,
					interior_target_ground_gu
				)
			)
			var arrival_offset_gu := (
				CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
					140.0
				)
			)
			return GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				portal_ground_gu + inward_direction_ground_gu * arrival_offset_gu
			)
	return (
		_bich_home_position_px_if_valid()
		if destination_map_id == BICH_RUNTIME_MAP_ID
		else Vector2.ZERO
	)


func route_next_target(map_id: int) -> Dictionary:
	var content := RegionContent.get_map_content(map_id)
	if (
		map_id == ORC_TOMB_F3_RUNTIME_MAP_ID
		and not content.get("bosses", []).is_empty()
	):
		return {"position": content.get("bosses", [])[0].get("position", Vector2.ZERO), "label": "骷髅精灵Boss房"}
	var portals: Array = content.get("portals", [])
	if not portals.is_empty():
		var portal: Dictionary = portals[-1]
		return {"position": portal.get("position", Vector2.ZERO), "label": str(portal.get("label", "区域出口"))}
	return {}


func _resolve_bich_home() -> Dictionary:
	if PlayerState.test_mode and _test_force_home_failure:
		return {
			"valid": false,
			"position_px": Vector2.ZERO,
			"source": "test_hook",
			"reason": "missing_bich_home_position",
		}
	var editor_home := MapEditorRuntimeBridgeScript.home_screen_position_px()
	if editor_home != Vector2.ZERO:
		return {"valid": true, "position_px": editor_home, "source": "runtime_bridge", "reason": ""}
	var profile: Dictionary = EnvironmentCatalog.get_map_profile(4)
	var runtime_home: Variant = profile.get("runtime_home_position")
	if runtime_home is Vector2 and (runtime_home as Vector2) != Vector2.ZERO:
		return {"valid": true, "position_px": runtime_home as Vector2, "source": "runtime_home_position", "reason": ""}
	var home_coord: Variant = profile.get("service_home_coordinate")
	var source_size: Variant = profile.get("source_size", null)
	if home_coord is Vector2i and source_size is Vector2i:
		return {"valid": true, "position_px": MapCoordinateMapperScript.source_to_world(Vector2(home_coord), source_size as Vector2i), "source": "service_home_coordinate", "reason": ""}
	push_error("no formal home position available from editor, catalog, or map profile for map 4")
	return {"valid": false, "position_px": Vector2.ZERO, "source": "", "reason": "missing_bich_home_position"}


# Read-only convenience for tests/debug/display only. Returns the formal Home
# position when resolvable, else Vector2.ZERO. Production side-effect paths must
# call _resolve_bich_home() and handle failure explicitly.
func _bich_home_screen_position_px() -> Vector2:
	var resolved: Dictionary = _resolve_bich_home()
	return resolved.get("position_px", Vector2.ZERO) as Vector2


# Returns Vector2.INF (explicit no-result sentinel) when Home resolution fails,
# so callers never consume a source-map current position as a target Home.
func _bich_home_position_px_if_valid() -> Vector2:
	var resolved := _resolve_bich_home()
	if not bool(resolved.get("valid", false)):
		return Vector2.INF
	return resolved.get("position_px", Vector2.ZERO) as Vector2


func _bich_portal_screen_position_px_to(target_map_id: int) -> Vector2:
	for portal: Dictionary in RegionContent.get_map_content(4).get("portals", []):
		if int(portal.get("target_map_id", -1)) == target_map_id:
			return portal.get("position", Vector2.INF) as Vector2
	return _bich_home_position_px_if_valid()


func _load_zone(zone_name: String, initial: bool, map_data: Dictionary) -> void:
	# FREEZE-P0.2R: formal gameplay only loads implemented (runtime-built)
	# maps. Reference/planned maps (e.g. 248/338/401/478) must never enter a
	# half-broken world through the formal loader.
	var target_map_id := (
		int(map_data.get("mapId", -1))
		if not map_data.is_empty()
		else GameData.service_runtime_map_id(0)
	)
	if (
		target_map_id >= 0
		and not MapEditorRuntimeBridgeScript.is_formal_playable(target_map_id)
		and not reference_audit_mode
	):
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpaceScript.REASON_MAP_NOT_IMPLEMENTED
		)
		return
	if zone_name == current_zone and not initial:
		if map_data.is_empty() or int(map_data.get("mapId", -1)) == current_map_id:
			return
	_zone_generation += 1
	_cancel_respawn_wakeups()
	_cancel_pending_enemy_deaths_for_generation_change()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.clear_map(current_map_id)
	_active_safe_zones.clear()
	_active_enemy_cache.clear()
	_active_boss_cache.clear()
	_player_combat_enemy_ids.clear()
	_safe_zone_enforcement_remaining = 0.0
	_cancel_all_combat_targets()
	if _combat_spatial_index != null and current_map_id >= 0:
		# Actors are queued for deletion below; clear the old map partition now so
		# a transition cannot expose stale candidates before their exit callbacks.
		_combat_spatial_index.clear_map(current_map_id)
	# Preserve the live summon before zone_content is queued for deletion. The
	# destination map restores the same gameplay state beside the owner.
	PlayerState.apply_taoist_main_pet_runtime_states(_capture_taoist_main_pet_runtime_states())
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if is_instance_valid(node):
			node.queue_free()
	if _ground_effect_manager != null:
		# Every zone_content node (including ground effect visuals) is freed
		# above; their manager registrations must not survive into the next map.
		_ground_effect_manager.clear_all()
	# FireWall field controllers are not zone_content members; free them
	# explicitly so no field (or registry entry) crosses a map transition.
	_clear_fire_wall_field_registry()
	current_zone = zone_name
	current_map_data = map_data.duplicate(true)
	_passive_wake_candidates.clear()
	_passive_wake_cursor = 0
	_passive_wake_query_pending = true
	var retained_player_emitter: Dictionary = {}
	if is_instance_valid(player):
		retained_player_emitter = _passive_wake_emitters.get(player.get_instance_id(), {})
	_passive_wake_emitters.clear()
	if not retained_player_emitter.is_empty():
		retained_player_emitter["dirty"] = false
		retained_player_emitter["map_id"] = current_map_id
		retained_player_emitter["generation"] = _zone_generation
		_passive_wake_emitters[player.get_instance_id()] = retained_player_emitter
	_passive_wake_emitter_queue.clear()
	_passive_wake_active_emitter_id = 0
	_passive_wake_dirty = false
	_passive_wake_max_extent_gu = 0.0
	_passive_wake_extent_map_id = -1
	_passive_wake_extent_generation = -1
	current_map_id = int(map_data.get("mapId", -1)) if not map_data.is_empty() else -1
	if map_data.is_empty():
		# Q1-B: legacy zones without a database map entry (for example the
		# outskirts playground) belong to the client 0.map home realm (runtime
		# map 4). Snapshot consumers receive a formal runtime map id instead of
		# -1, so STRICT_V2 absolute snapshots stay valid.
		current_map_id = GameData.service_runtime_map_id(0)
	if is_instance_valid(player):
		_register_passive_wake_emitter(player)
	_mark_passive_monster_wakeup_dirty()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.configure_map(
			current_map_id,
			_zone_generation,
			Callable(self, "_canonical_screen_px_to_ground_gu"),
			Callable(self, "_canonical_ground_gu_to_screen_px"),
		)
	_begin_safe_zone_context(current_map_id)
	_monster_terrain_navigation_context = (
		MonsterTerrainNavigationPolicyScript.build_context(
			current_map_id,
			MapEditorRuntimeBridgeScript.load_map(current_map_id),
			MonsterTerrainNavigationPolicyScript.EXPECTED_GROUND_COORDINATE_CONTRACT_ID,
		)
	)
	background.set_zone_data(zone_name, current_map_data)
	hud.set_zone_name(
		"比奇营地 · 安全区"
		if current_map_id == BICH_RUNTIME_MAP_ID
		else zone_name
	)
	if zone_name == "比奇城":
		_set_player_world_position(Vector2(0, 80))
		_spawn_city_content()
	elif zone_name == "比奇郊外":
		_set_player_world_position(Vector2.ZERO)
		_spawn_outskirts_content()
	else:
		if current_map_id == BICH_RUNTIME_MAP_ID:
			var home := _resolve_bich_home()
			if bool(home.get("valid", false)):
				_set_player_world_position(home.get(
					"position_px", Vector2.ZERO
				) as Vector2)
			else:
				_handle_home_resolution_failure(&"load_zone_arrival", home)
		else:
			_set_player_world_position(Vector2.ZERO)
		_spawn_database_zone_content(current_map_data)
	_refresh_player_safe_zone_cache(true)
	player.velocity = Vector2.ZERO
	background.set_focus_position(player.global_position)
	_restore_persisted_taoist_main_pet_if_needed()
	_on_player_stats_changed(player.current_hp, player.max_hp)
	hud.show_message("进入%s" % zone_name, 1.5)


func _spawn_database_zone_content(map_data: Dictionary) -> void:
	if map_data.is_empty():
		_spawn_outskirts_content()
		return
	var map_id := int(map_data.get("mapId", -1))
	# FREEZE-P0.2R: never seed an unbuilt map with WorldContent/reference
	# placeholder spawns in formal gameplay; the authored data is preserved for
	# migration/audit/reference use only.
	if (
		not MapEditorRuntimeBridgeScript.is_formal_playable(map_id)
		and not reference_audit_mode
	):
		return
	if MapEditorRuntimeBridgeScript.has_runtime_map(map_id):
		var editor_content := (
			MapEditorRuntimeBridgeScript.game_content_for_map(map_id)
		)
		if not editor_content.is_empty():
			_spawn_editor_runtime_content(editor_content)
			return
	if RegionContent.has_map(map_id):
		_spawn_authored_map_content(RegionContent.get_map_content(map_id))
		return
	var region := str(map_data.get("region", ""))
	var recommended_level := 18
	if "比奇" in region:
		recommended_level = 10
	elif "毒蛇" in region:
		recommended_level = 16
	elif "沃玛" in region:
		recommended_level = 22
	elif "盟重" in region:
		recommended_level = 28
	elif "封魔" in region:
		recommended_level = 32
	elif "白日门" in region:
		recommended_level = 35
	elif "苍月" in region:
		recommended_level = 38
	# A formal map without an editor/authored spawn plan remains empty.  The
	# legacy region/level/base-name guesses could select the wrong variant and
	# are no longer a production monster source.
	_spawn_portal(Vector2(0, 390), "比奇城", "返回比奇城（临时门点）")


func _spawn_editor_runtime_content(content: Dictionary) -> void:
	_compile_active_safe_zones(content.get("safe_areas", []))
	var editor_spawn_index := -1
	for spawn: Dictionary in content.get("spawns", []):
		editor_spawn_index += 1
		var monster_id := GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var monster := GameData.get_monster_by_id(monster_id)
		if not monster.is_empty():
			var count:=mini(int(spawn.get("count",1)),int(spawn.get("max_alive",spawn.get("count",1))))
			var center_screen_px: Vector2 = spawn.get("screen_position_px", Vector2.ZERO)
			var radius_gu := maxf(0.0, float(spawn.get("radius_gu", 0.0)))
			for copy_index in maxi(1,count):
				var offset_ground_gu := Vector2.ZERO
				if count > 1 and radius_gu > 0.0:
					var radial_fraction := sqrt(
						float(copy_index + 1) / float(count)
					)
					offset_ground_gu = (
						Vector2.from_angle(float(copy_index) * TAU / float(count))
						* radius_gu
						* radial_fraction
					)
				var offset_screen_px := (
					GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
						offset_ground_gu
					)
				)
				var raw_group: Dictionary = spawn.get("spawn_group", {})
				var group_id := str(spawn.get(
					"spawnGroupId",
					raw_group.get("id", "editor:%d:%d" % [current_map_id, editor_spawn_index])
				))
				_spawn_enemy(
					monster,
					center_screen_px + offset_screen_px,
					false,
					float(spawn.get("respawn_seconds", 60)),
					{
						"spawn_group_id": group_id,
						"spawn_slot_id": "%s:%d" % [group_id, copy_index],
						"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
						"respawn_evidence": spawn.get("respawnEvidence", {"status": "map_editor_authored"}),
						"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
					}
				)
	var editor_boss_index := -1
	for spawn: Dictionary in content.get("bosses", []):
		editor_boss_index += 1
		var boss_id := GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var boss := GameData.get_monster_by_id(boss_id)
		if boss.is_empty():
			continue
		var raw_group: Dictionary = spawn.get("spawn_group", {})
		var group_id := str(raw_group.get(
			"spawn_group_id",
			"editor:%d:boss:%d" % [
				current_map_id,
				editor_boss_index,
			]
		))
		_spawn_enemy(
			boss,
			spawn.get("screen_position_px", Vector2.ZERO),
			true,
			float(spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
			{
				"spawn_group_id": group_id,
				"spawn_slot_id": "%s:0" % group_id,
				"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
				"respawn_evidence": {
					"status": "map_editor_authored",
				},
			}
		)
	for npc_data: Dictionary in content.get("npcs", []):
		var role := str(npc_data.get("kind", "dialogue"))
		var name := str(npc_data.get("name", "NPC"))
		var stock_key := str(npc_data.get("stock", ""))
		var stock: Array = []
		match stock_key:
			"general": stock = _general_shop_stock()
			"starter_gear": stock = _starter_gear_stock()
			"medicine": stock = _medicine_shop_stock()
			"books": stock = _build_skill_book_stock(PlayerState.profession_id)
		_spawn_npc(npc_data.get("screen_position_px", Vector2.ZERO), name, role, stock, stock_key, int(npc_data.get("appearance", -1)), content.get("map_center_screen_position_px", _current_map_center_screen_position_px()))
	for portal: Dictionary in content.get("portals", []):
		_spawn_map_portal(
			portal.get("screen_position_px", Vector2.ZERO),
			int(portal.get("target_map_id", -1)),
			str(portal.get("label", "地图入口")),
			portal
		)


func _spawn_authored_map_content(content: Dictionary) -> void:
	if content.has("safe_areas"):
		_compile_active_safe_zones(content.get("safe_areas", []))
	var camp_layout := (
		_bich_camp_layout if current_map_id == BICH_RUNTIME_MAP_ID else {}
	)
	var camp_home := Vector2.ZERO
	if current_map_id == BICH_RUNTIME_MAP_ID:
		var home := _resolve_bich_home()
		if not bool(home.get("valid", false)):
			_handle_home_resolution_failure(&"camp_spawn", home)
			return
		camp_home = home.get("position_px", Vector2.ZERO) as Vector2
	var authored_spawn_index := -1
	for spawn: Variant in content.get("spawns", []):
		authored_spawn_index += 1
		if not spawn is Dictionary:
			continue
		var monster_id := GameData.canonical_monster_id(
			spawn.get("monster_id", null)
		)
		var monster := GameData.get_monster_by_id(monster_id)
		if not monster.is_empty():
			var spawn_position: Vector2 = spawn.get("position", Vector2.ZERO)
			var group_id := str(spawn.get(
				"spawnGroupId",
				"map:%d:spawn:%d" % [current_map_id, authored_spawn_index]
			))
			if current_map_id == BICH_RUNTIME_MAP_ID:
				var copies := int(camp_layout.get("fieldSpawnCopies", 4))
				var radii: Array = camp_layout.get("fieldSpawnRadii", [940, 1180, 1460, 1740])
				for copy_index in range(copies):
					var angle := float(authored_spawn_index * copies + copy_index) * TAU / float(maxi(1, content.get("spawns", []).size() * copies))
					var radius := float(radii[copy_index % radii.size()])
					_spawn_enemy(
						monster,
						camp_home + Vector2.RIGHT.rotated(angle) * radius,
						false,
						float(spawn.get("respawn_seconds", DEFAULT_NORMAL_RESPAWN_SECONDS)),
						{
							"spawn_group_id": group_id,
							"spawn_slot_id": "%s:%d" % [group_id, copy_index],
							"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
							"respawn_evidence": spawn.get("respawnEvidence", {}),
							"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
						}
					)
				continue
			_spawn_enemy(
				monster,
				spawn_position,
				false,
				float(spawn.get("respawn_seconds", DEFAULT_NORMAL_RESPAWN_SECONDS)),
				{
					"spawn_group_id": group_id,
					"spawn_slot_id": "%s:0" % group_id,
					"respawn_policy_id": str(spawn.get("respawn_policy_id", "")),
					"respawn_evidence": spawn.get("respawnEvidence", {}),
					"respawn_random_seconds": float(spawn.get("respawn_random_seconds", 0.0)),
				}
			)
	var authored_boss_index := -1
	for boss_spawn: Variant in content.get("bosses", []):
		authored_boss_index += 1
		if not boss_spawn is Dictionary:
			continue
		var boss_id := GameData.canonical_monster_id(
			boss_spawn.get("monster_id", null)
		)
		var boss := GameData.get_monster_by_id(boss_id)
		if not boss.is_empty():
			var boss_group_id := str(boss_spawn.get(
				"spawnGroupId",
				"map:%d:boss:%d" % [current_map_id, authored_boss_index]
			))
			_spawn_enemy(
				boss,
				boss_spawn.get("position", Vector2(560, 230)),
				true,
				float(boss_spawn.get("respawn_seconds", DEFAULT_BOSS_RESPAWN_SECONDS)),
				{
					"spawn_group_id": boss_group_id,
					"spawn_slot_id": "%s:0" % boss_group_id,
					"respawn_policy_id": str(boss_spawn.get("respawn_policy_id", "")),
					"respawn_evidence": boss_spawn.get("respawnEvidence", {}),
					"respawn_random_seconds": float(boss_spawn.get("respawn_random_seconds", 0.0)),
				}
			)
	for npc_data: Variant in content.get("npcs", []):
		if not npc_data is Dictionary:
			continue
		var stock: Array = []
		match str(npc_data.get("stock", "")):
			"general": stock = _general_shop_stock()
			"starter_gear": stock = _starter_gear_stock()
			"mid_gear": stock = _mid_gear_stock()
			"medicine": stock = _medicine_shop_stock()
			"books": stock = _build_skill_book_stock(PlayerState.profession_id)
		var npc_name := str(npc_data.get("name", "NPC"))
		var npc_position: Vector2 = npc_data.get("position", Vector2.ZERO)
		if (
			current_map_id == BICH_RUNTIME_MAP_ID
			and camp_layout.get("npcSlots", {}).has(npc_name)
		):
			npc_position = camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots[npc_name])
		_spawn_npc(npc_position, npc_name, str(npc_data.get("kind", "shop")), stock, str(npc_data.get("stock", "")), int(npc_data.get("appearance", -1)))
	if current_map_id == BICH_RUNTIME_MAP_ID:
		_spawn_npc(camp_home + GothicBichCampBuilderScript._vector(camp_layout.npcSlots.get("仓库管理员", [-520, 185])), "仓库管理员", "warehouse")
	for portal: Variant in content.get("portals", []):
		if portal is Dictionary:
			_spawn_map_portal(portal.get("position", Vector2.ZERO), int(portal.get("target_map_id", -1)), str(portal.get("label", "地图入口")))


func _tick_bich_safe_zone_enforcement(delta: float) -> void:
	if current_map_id != BICH_RUNTIME_MAP_ID:
		_safe_zone_enforcement_remaining = 0.0
		return
	_safe_zone_enforcement_remaining -= delta
	if _safe_zone_enforcement_remaining > 0.0:
		return
	_safe_zone_enforcement_remaining = SAFE_ZONE_ENFORCEMENT_INTERVAL_SECONDS
	_enforce_bich_safe_zone()


func _enforce_enemy_outside_bich_safe_zone(enemy: EnemyActor) -> void:
	var safe_zone_started_usec := RuntimeDiagnostics.timing_start()
	RuntimeDiagnostics.increment_performance_counter(&"safe_zone_queries")
	if (
		current_map_id != BICH_RUNTIME_MAP_ID
		or not is_instance_valid(enemy)
		or enemy.is_queued_for_deletion()
	):
		RuntimeDiagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)
		return
	var current_ground_gu := _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var legal_ground_gu: Vector2 = hc_m30_stable_enemy_ground_point(
		current_ground_gu, float(enemy.combat_radius_gu), enemy.runtime_map_id
	)
	if not legal_ground_gu.is_finite():
		RuntimeDiagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)
		return
	if not legal_ground_gu.is_equal_approx(current_ground_gu):
		enemy.set_combat_position(
			_canonical_ground_gu_to_screen_px(legal_ground_gu),
			&"safe_zone_enforcement",
		)
		enemy.velocity = Vector2.ZERO
	RuntimeDiagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)


func _enforce_bich_safe_zone() -> void:
	if (
		current_map_id != BICH_RUNTIME_MAP_ID
		or not _safe_zone_context_is_valid()
		or _active_safe_zones.is_empty()
		or _combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
	):
		return
	_safe_zone_candidate_scratch.clear()
	_safe_zone_candidate_stamp_serial += 1
	if _safe_zone_candidate_stamp_serial <= 0:
		_safe_zone_candidate_stamp_serial = 1
	for zone_variant: Variant in _active_safe_zones:
		if not zone_variant is Dictionary:
			continue
		var zone := zone_variant as Dictionary
		var zone_aabb: Variant = zone.get("aabb_ground_gu", null)
		if not zone_aabb is Rect2:
			continue
		_combat_spatial_index.query_enemy_nodes_aabb_into(
			current_map_id,
			zone_aabb as Rect2,
			_safe_zone_query_scratch,
		)
		for value: Variant in _safe_zone_query_scratch:
			if not value is EnemyActor:
				continue
			var enemy := value as EnemyActor
			if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
				continue
			if enemy._safe_zone_candidate_stamp == _safe_zone_candidate_stamp_serial:
				continue
			enemy._safe_zone_candidate_stamp = _safe_zone_candidate_stamp_serial
			_append_safe_zone_candidate_sorted(enemy)
	for enemy: EnemyActor in _safe_zone_candidate_scratch:
		_enforce_enemy_outside_bich_safe_zone(enemy)
	_safe_zone_query_scratch.clear()


func _append_safe_zone_candidate_sorted(enemy: EnemyActor) -> void:
	var candidate_order := int(
		enemy.get_meta("spawn_serial", enemy.get_instance_id())
	)
	var insert_at := _safe_zone_candidate_scratch.size()
	while insert_at > 0:
		var previous := _safe_zone_candidate_scratch[insert_at - 1]
		var previous_order := int(
			previous.get_meta("spawn_serial", previous.get_instance_id())
		)
		if previous_order < candidate_order:
			break
		if (
			previous_order == candidate_order
			and previous.get_instance_id() < enemy.get_instance_id()
		):
			break
		insert_at -= 1
	_safe_zone_candidate_scratch.insert(insert_at, enemy)


func _general_shop_stock() -> Array:
	return GameData.merchant_stock("general")


func _starter_gear_stock() -> Array:
	return GameData.merchant_stock("starter_gear")


func _medicine_shop_stock() -> Array:
	return GameData.merchant_stock("medicine")


func _mid_gear_stock() -> Array:
	# Fail closed until the stable stock key is mapped to an exact primary NPC
	# [Trade] script.  Guessed/project-authored inventories are forbidden.
	return GameData.merchant_stock("mid_gear")


func _spawn_outskirts_content() -> void:
	var spawn_plan := [
		[21, Vector2(-320, 170)], [24, Vector2(310, 125)],
		[26, Vector2(430, -35)], [28, Vector2(-470, -170)],
		[30, Vector2(520, 160)],
		[56, Vector2(670, 280)],
	]
	for spawn_index in range(spawn_plan.size()):
		var entry: Array = spawn_plan[spawn_index]
		var monster := GameData.get_monster_by_id(int(entry[0]))
		if not monster.is_empty():
			var group_id := "outskirts:%d:spawn:%d" % [current_map_id, spawn_index]
			var policy := MonsterRespawnPolicyScript.resolve(
				"", str(monster.get("classification", "")),
				DEFAULT_NORMAL_RESPAWN_SECONDS,
				str(monster.get("spawn_classification", ""))
			)
			_spawn_enemy(
				monster,
				entry[1],
				false,
				DEFAULT_NORMAL_RESPAWN_SECONDS,
				{
					"spawn_group_id": group_id,
					"spawn_slot_id": "%s:0" % group_id,
					"respawn_policy_id": str(policy.get("policy_id", "")),
				}
			)
	_spawn_portal(Vector2(560, -305), "比奇城", "进入比奇城")


func _spawn_city_content() -> void:
	var general_stock := _general_shop_stock()
	var book_stock := _build_skill_book_stock(PlayerState.profession_id)
	_spawn_npc(Vector2(-250, -60), "杂货商", "shop", general_stock, "general")
	_spawn_npc(Vector2(250, -60), "书店老板", "shop", book_stock, "books")
	_spawn_npc(Vector2(0, -255), "武馆教头", "trainer")
	_spawn_npc(Vector2(-420, 210), "比奇老兵", "quest")
	_spawn_portal(Vector2(0, 390), "比奇郊外", "前往比奇郊外")


func _build_skill_book_stock(profession: String) -> Array:
	var allowed := {}
	for skill: Variant in GameData.get_profession_skills(profession):
		if not skill is Dictionary:
			continue
		allowed[str(skill.get("skillName", ""))] = true
	var stock: Array = []
	for raw_entry: Variant in GameData.merchant_stock("books"):
		if raw_entry is Dictionary and allowed.has(str(raw_entry.get("name", ""))):
			stock.append(raw_entry)
	return stock


func _submit_staged_actor_descriptor(
	actor_type: String,
	payload: Dictionary,
	stable_actor_id := ""
) -> bool:
	if not _collecting_staged_actor_plan or not _world_bootstrap_coordinator.actor_collection_is_open():
		return false
	var source_index := _staged_actor_source_index
	var actor_id := stable_actor_id
	if actor_id.is_empty():
		actor_id = "%s:%d:%06d" % [actor_type, current_map_id, source_index]
	var descriptor := {"actor_id": actor_id, "actor_type": actor_type,
		"source_index": source_index, "payload": payload}
	# The existing queue owner preflights stable identity before cold compilation.
	if not _world_bootstrap_coordinator.actor_descriptor_is_admissible(descriptor):
		return false
	if actor_type == "enemy":
		var monster_id := _strict_runtime_monster_id(payload)
		var position: Variant = payload.get("position")
		var seconds: Variant = payload.get("respawn_seconds", -1.0)
		var raw_context: Variant = payload.get("spawn_context", {})
		if monster_id <= 0 or not position is Vector2 or not position.is_finite() \
			or (not seconds is int and not seconds is float) or not is_finite(float(seconds)) \
			or not raw_context is Dictionary:
			return false
		var spawn_context: Dictionary = raw_context
		var slot := str(spawn_context.get("spawn_slot_id", spawn_context.get("spawn_group_id", "")))
		if slot.is_empty() or not str(spawn_context.get("summoner_spawn_slot", "")).is_empty():
			return false
		_feature_target_bound.sync_world(_world_context.capture_world())
		if not _feature_target_bound.declare_base(slot, monster_id, position, float(seconds), spawn_context, actor_id):
			return false
	var accepted := _world_bootstrap_coordinator.submit_actor_descriptor(descriptor)
	if accepted:
		_staged_actor_source_index += 1
	return accepted


func _validate_queued_actor_descriptor(descriptor: Dictionary) -> bool:
	if not _collecting_staged_actor_plan:
		return false
	var actor_type := str(descriptor.get("actor_type", ""))
	if actor_type != "enemy":
		return actor_type in ["npc", "zone_portal", "map_portal"]
	var payload: Dictionary = descriptor.get("payload", {})
	var position: Variant = payload.get("position")
	var seconds: Variant = payload.get("respawn_seconds", -1.0)
	var raw_context: Variant = payload.get("spawn_context", {})
	if not position is Vector2 or not position.is_finite() \
		or (not seconds is int and not seconds is float) or not is_finite(float(seconds)) \
		or not raw_context is Dictionary:
		return false
	var context: Dictionary = raw_context
	var slot := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot.is_empty():
		return false
	return _feature_target_bound.declared_base_matches(
		_strict_runtime_monster_id(payload), position, float(seconds), context, str(descriptor.get("actor_id", "")))


func _spawn_staged_actor_descriptor(descriptor: Dictionary) -> Dictionary:
	var actor_type := str(descriptor.get("actor_type", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	match actor_type:
		"enemy":
			var monster_id := int(payload.get("monster_id", -1))
			var monster := {"monster_id": monster_id}
			_staged_actor_spawn_failure_reason = ""
			var enemy := _spawn_enemy(
				monster,
				payload.get("position", Vector2.ZERO),
				bool(payload.get("is_boss", false)),
				float(payload.get("respawn_seconds", -1.0)),
				payload.get("spawn_context", {})
			)
			if not _staged_actor_spawn_failure_reason.is_empty():
				return {
					"ok": false,
					"reason": _staged_actor_spawn_failure_reason,
				}
			# A persisted death may deliberately schedule this slot for later. The
			# descriptor was still handled successfully even though no node exists yet.
			return {"ok": true, "materialized": enemy != null}
		"npc":
			_spawn_npc(
				payload.get("position", Vector2.ZERO),
				str(payload.get("display_name", "NPC")),
				str(payload.get("kind", "dialogue")),
				payload.get("stock", []),
				str(payload.get("stock_key", "")),
				int(payload.get("appearance", -1)),
				payload.get("map_center_override", null)
			)
			return {"ok": true, "materialized": true}
		"zone_portal":
			_spawn_portal(
				payload.get("position", Vector2.ZERO),
				str(payload.get("target_zone", "")),
				str(payload.get("label_text", ""))
			)
			return {"ok": true, "materialized": true}
		"map_portal":
			_spawn_map_portal(
				payload.get("position", Vector2.ZERO),
				int(payload.get("target_map_id", -1)),
				str(payload.get("label_text", "")),
				payload.get("portal_data", {})
			)
			return {"ok": true, "materialized": true}
		_:
			return {"ok": false, "reason": "unknown_actor_type"}


func _spawn_npc(position: Vector2, display_name: String, kind: String, stock: Array = [], stock_key := "", appearance := -1, map_center_override: Variant = null) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("npc", {
			"position": position,
			"display_name": display_name,
			"kind": kind,
			"stock": stock,
			"stock_key": stock_key,
			"appearance": appearance,
			"map_center_override": map_center_override,
		})
		return
	var npc := NPCActor.new()
	var map_center := _current_map_center_screen_position_px() if map_center_override == null else Vector2(map_center_override)
	npc.setup(display_name, kind, stock, stock_key, appearance, map_center)
	npc.global_position = position
	add_child(npc)


func _current_map_center_screen_position_px() -> Vector2:
	var source_size := Vector2i.ZERO
	if current_map_data.has("source_size"):
		source_size = Vector2i(current_map_data.get("source_size", Vector2i.ZERO))
	if source_size == Vector2i.ZERO and RegionContent.has_map(current_map_id):
		source_size = Vector2i(RegionContent.get_map_content(current_map_id).get("source_size", Vector2i.ZERO))
	if source_size != Vector2i.ZERO:
		return MapCoordinateMapperScript.source_to_world((Vector2(source_size) - Vector2.ONE) * 0.5, source_size)
	return Vector2.ZERO


func _spawn_portal(position: Vector2, target_zone: String, label_text: String) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("zone_portal", {
			"position": position,
			"target_zone": target_zone,
			"label_text": label_text,
		})
		return
	var portal := ZonePortal.new()
	portal.setup(target_zone, label_text)
	portal.global_position = position
	add_child(portal)


func _spawn_map_portal(
	position: Vector2,
	target_map_id: int,
	label_text: String,
	portal_data: Dictionary = {}
) -> void:
	if _collecting_staged_actor_plan:
		_submit_staged_actor_descriptor("map_portal", {
			"position": position,
			"target_map_id": target_map_id,
			"label_text": label_text,
			"portal_data": portal_data,
		})
		return
	var portal := ZonePortal.new()
	portal.setup_map(target_map_id, label_text, portal_data)
	portal.global_position = position
	add_child(portal)


func _spawn_enemy(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	respawn_seconds := -1.0,
	spawn_context: Dictionary = {}
) -> EnemyActor:
	_feature_target_bound.sync_world(_world_context.capture_world())
	if _collecting_staged_actor_plan:
		var monster_id_for_plan := _strict_runtime_monster_id(monster_data)
		var slot_id_for_plan := str(spawn_context.get(
			"spawn_slot_id",
			spawn_context.get("spawn_group_id", "")
		))
		var planned := _submit_staged_actor_descriptor(
			"enemy",
			{
				"monster_id": monster_id_for_plan,
				"position": spawn_position,
				"is_boss": is_boss,
				"respawn_seconds": respawn_seconds,
				"spawn_context": spawn_context,
			},
			"enemy:%s" % slot_id_for_plan if not slot_id_for_plan.is_empty() else ""
		)
		if not planned:
			_staged_actor_spawn_failure_reason = "invalid_published_base_descriptor"
		return null
	var monster_id := _strict_runtime_monster_id(monster_data)
	var summoner_slot := str(spawn_context.get("summoner_spawn_slot", ""))
	var admission: Dictionary = {}
	var inputs: RefCounted
	if summoner_slot.is_empty():
		admission = _feature_target_bound.admit_base(monster_id, spawn_position, float(respawn_seconds), spawn_context)
		if not bool(admission.get("accepted", false)):
			_staged_actor_spawn_failure_reason = str(admission.get("reason", "unpublished_base_spawn"))
			return null
		inputs = admission.get("inputs")
	else:
		if not _feature_target_bound.admits_child(summoner_slot, monster_id):
			_staged_actor_spawn_failure_reason = "unpublished_summon_child"
			return null
		inputs = _feature_target_bound.monster_inputs(monster_id)
		if not is_instance_valid(_hc_m30_summon_queue) or not _hc_m30_summon_queue.claim_birth(monster_id, spawn_position, spawn_context):
			_staged_actor_spawn_failure_reason = "unissued_summon_birth"
			return null
	if inputs == null:
		_staged_actor_spawn_failure_reason = "missing_published_monster_inputs"
		return null
	var canonical_monster: Dictionary = inputs.view().entry
	monster_data = canonical_monster
	# Classification is canonical data, never a caller-controlled flag.
	is_boss = str(monster_data.get("classification", "")) == "boss"
	if current_map_id >= 0:
		var spawn_ground_result := _try_canonical_screen_px_to_ground_gu(
			spawn_position
		)
		if not bool(spawn_ground_result.get("success", false)):
			# FREEZE-P0.1: mapped world without a loadable runtime projection
			# must never register an enemy at fake/delta coordinates.
			missing_projection_rejection_count += 1
			_staged_actor_spawn_failure_reason = "missing_spawn_projection"
			return null
	var explicit_slot := str(spawn_context.get("spawn_slot_id",spawn_context.get("spawn_group_id","")))
	if not explicit_slot.is_empty() and str(spawn_context.get("summoner_spawn_slot","")).is_empty() \
		and _spawn_slot_is_alive(explicit_slot,_zone_generation,true):
		# The old body owns its base slot until queued retirement. A deferred
		# death/revival callback cannot reopen it alongside a replacement.
		_staged_actor_spawn_failure_reason = "occupied_base_spawn_slot"
		return null
	_runtime_spawn_serial += 1
	# The original job is a synchronous factory capability, never actor/save data.
	var context := spawn_context.duplicate(false)
	context.erase("_m30_job")
	context = context.duplicate(true)
	var respawn_enabled := bool(context.get("respawn_enabled", true))
	var slot_id := str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
	if slot_id.is_empty():
		if respawn_enabled:
			push_error(
				"Monster respawn authority rejected unstable formal slot: monster_id=%d map_id=%d"
				% [monster_id, current_map_id]
			)
			_staged_actor_spawn_failure_reason = "unstable_spawn_slot"
			return null
		slot_id = "runtime:%d:%d" % [_zone_generation, _runtime_spawn_serial]
	context["spawn_slot_id"] = slot_id
	var spawn_classification := str(
		canonical_monster.get("spawn_classification", "")
	)
	var policy: Dictionary = {}
	var effective_respawn := maxf(0.0, float(respawn_seconds))
	if respawn_enabled:
		policy = admission.get("policy", {})
		if not bool(policy.get("valid", false)):
			push_error(
				"Monster respawn policy rejected monster_id=%d slot=%s reason=%s"
				% [
					monster_id,
					slot_id,
					str(policy.get("reason", "invalid_policy")),
				]
			)
			_staged_actor_spawn_failure_reason = "invalid_respawn_policy"
			return null
		effective_respawn = float(policy.get("seconds", 0.0))
		context["respawn_policy_id"] = str(policy.get("policy_id", ""))
		context["respawn_policy_source"] = str(policy.get("source", ""))
		context["spawn_classification"] = spawn_classification
		context["respawn_policy_requires_authored_policy"] = bool(
			policy.get("requires_authored_policy", false)
		)
	else:
		context["respawn_policy_id"] = ""
		context["respawn_policy_source"] = "respawn_disabled"
		context["respawn_policy_requires_authored_policy"] = false
	context["respawn_runtime_map_id"] = current_map_id
	context["respawn_base_seconds"] = effective_respawn
	# MFC-4 fixed tiers are exact. Historical random variance remains readable
	# in old authored data but is retired from runtime authority.
	context["respawn_random_seconds"] = 0.0

	var clear_persisted_respawn_after_spawn := false
	if respawn_enabled:
		var persisted := PlayerState.monster_respawn_entry(current_map_id, slot_id)
		if not persisted.is_empty():
			if int(persisted.get("monster_id", -1)) != monster_id:
				# The map slot was deliberately re-authored to another
				# canonical identity. A stale death record must not suppress it.
				PlayerState.clear_monster_respawn_slot(current_map_id, slot_id)
			else:
				var remaining := maxf(
					0.0,
					float(persisted.get("respawn_at_unix", 0.0))
					- Time.get_unix_time_from_system()
				)
				if remaining > 0.0:
					_respawn_later(
						canonical_monster,
						spawn_position,
						is_boss,
						remaining,
						_zone_generation,
						context
					)
					return null
				clear_persisted_respawn_after_spawn = true
	var enemy := EnemyActor.new()
	enemy.setup(monster_data, player, is_boss, inputs)
	# R4 T3: the body admission verdict is obtained synchronously BEFORE the
	# world registers anything. A config-rejected profile never occupies the
	# spatial index, the activity cache or the respawn slot: the spawn
	# transaction fails atomically (bounded diagnostic, node freed) instead
	# of leaving a half-registered invulnerable candidate behind. Legal
	# non-combat chests keep their own contract untouched.
	if enemy.resolve_body_for_admission():
		_staged_actor_spawn_failure_reason = "body_policy_rejected"
		enemy.free()
		return null
	enemy.configure_runtime_map_projection(
		current_map_id,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu")
	)
	enemy.configure_terrain_navigation_context(
		_monster_terrain_navigation_context
	)
	enemy.configure_spatial_index(
		_combat_spatial_index,
		_runtime_spawn_serial
	)
	enemy.set_meta("spawn_serial", _runtime_spawn_serial)
	enemy.set_combat_position(spawn_position, &"spawn")
	_combat_spatial_index.register(
		_runtime_spawn_serial,
		current_map_id,
		_canonical_screen_px_to_ground_gu(spawn_position),
		enemy.combat_radius_gu,
		_runtime_spawn_serial,
		enemy,
		Callable(enemy, "spatial_index_position")
	)
	# FREEZE-P0: the initial register and the live provider must share the
	# exact same absolute map-ground semantics (within the frozen GU epsilon).
	assert(
		_canonical_screen_px_to_ground_gu(spawn_position).distance_to(
			enemy.spatial_index_position()
		) <= GroundUnitSpaceScript.EPSILON_GU,
		"enemy spatial index register/provider coordinate mismatch"
	)
	enemy.set_meta("spawn_position", spawn_position)
	enemy.set_meta("spawn_is_boss", is_boss)
	enemy.set_meta("respawn_seconds", effective_respawn)
	enemy.set_meta("respawn_random_seconds", float(context["respawn_random_seconds"]))
	enemy.set_meta("respawn_enabled", respawn_enabled)
	enemy.set_meta("respawn_policy_id", str(context.get("respawn_policy_id", "")))
	enemy.set_meta("respawn_policy_source", str(context.get("respawn_policy_source", "")))
	enemy.set_meta("respawn_policy_requires_authored_policy", bool(context.get("respawn_policy_requires_authored_policy", false)))
	enemy.set_meta("spawn_slot_id", slot_id)
	enemy.set_meta("spawn_group_id", str(context.get("spawn_group_id", slot_id)))
	enemy.set_meta("spawn_context", context)
	if enemy.has_method("passive_acquisition_extent_gu"):
		var passive_extent := float(enemy.call("passive_acquisition_extent_gu"))
		if is_finite(passive_extent) and passive_extent >= 0.0:
			enemy.set_meta("passive_wake_extent_gu", passive_extent)
			var extent_was_unavailable := (
				_passive_wake_extent_map_id != current_map_id
				or _passive_wake_extent_generation != _zone_generation
				or _passive_wake_max_extent_gu <= 0.0
			)
			if (
				_passive_wake_extent_map_id != current_map_id
				or _passive_wake_extent_generation != _zone_generation
			):
				_passive_wake_max_extent_gu = passive_extent
				_passive_wake_extent_map_id = current_map_id
				_passive_wake_extent_generation = _zone_generation
			else:
				_passive_wake_max_extent_gu = maxf(
					_passive_wake_max_extent_gu,
					passive_extent,
				)
			if extent_was_unavailable and _passive_wake_max_extent_gu > 0.0:
				_mark_passive_wake_emitters_for_extent_availability()
	enemy.set_meta(
		"death_runtime_snapshot",
		_build_enemy_death_runtime_snapshot(canonical_monster)
	)
	enemy.set_meta("summoner_spawn_slot", str(context.get("summoner_spawn_slot", "")))
	enemy.set_meta("zone_generation", _zone_generation)
	# All actors on a loaded map share the compiled context. Do not deep-copy
	# polygon geometry per EnemyActor; realtime checks remain actor-owned while
	# consuming this map-lifetime immutable value.
	enemy.set_meta("safe_zone_context", _safe_zone_context)
	enemy.set_meta("safe_zones", _active_safe_zones)
	enemy.environment_blocker = background
	enemy.add_to_group("zone_content")
	enemy.died.connect(_on_enemy_died)
	enemy.combat_target_changed.connect(_on_enemy_combat_target_changed)
	_on_enemy_combat_target_changed(enemy, enemy.target)
	enemy.target_requested.connect(_on_enemy_target_requested)
	enemy.summon_requested.connect(_on_boss_summon_requested)
	enemy.relocation_requested.connect(_on_boss_relocation_requested)
	enemy.fixed_area_ground_spike_requested.connect(
		_on_enemy_fixed_area_ground_spike_requested.bind(enemy)
	)
	add_child(enemy)
	var enemy_instance_id := enemy.get_instance_id()
	_active_enemy_cache[enemy_instance_id] = enemy
	if is_instance_valid(_hc_m30_summon_queue):
		_hc_m30_summon_queue.track_child(enemy)
	if enemy.is_boss:
		_active_boss_cache[enemy_instance_id] = enemy
	enemy.tree_exiting.connect(
		_on_cached_enemy_tree_exiting.bind(enemy_instance_id),
		CONNECT_ONE_SHOT
	)
	# Authored placement is corrected before the first rendered frame. Runtime
	# movement also enforces safe-zone targeting/motion; the 10 Hz cache sweep is
	# a bounded safety net rather than an all-enemy scan on every render frame.
	_enforce_enemy_outside_bich_safe_zone(enemy)
	if clear_persisted_respawn_after_spawn:
		PlayerState.clear_monster_respawn_slot(current_map_id, slot_id)
	_mark_passive_monster_wakeup_dirty()
	return enemy


func _on_cached_enemy_tree_exiting(enemy_instance_id: int) -> void:
	_player_combat_enemy_ids.erase(enemy_instance_id)
	_active_enemy_cache.erase(enemy_instance_id)
	_active_boss_cache.erase(enemy_instance_id)


func _strict_runtime_monster_id(monster_data: Dictionary) -> int:
	if (
		not monster_data.has("monster_id")
		or monster_data.has("monsterId")
		or monster_data.has("boss_id")
		or monster_data.has("content_id")
	):
		return -1
	var raw_id: Variant = monster_data.get("monster_id", null)
	if raw_id is int:
		return int(raw_id) if int(raw_id) > 0 else -1
	if raw_id is float:
		var numeric_id := float(raw_id)
		if (
			is_finite(numeric_id)
			and numeric_id > 0.0
			and numeric_id == floorf(numeric_id)
			and numeric_id <= 9007199254740991.0
		):
			return int(numeric_id)
	return -1


func _build_enemy_death_runtime_snapshot(canonical_monster: Dictionary) -> Dictionary:
	var monster_id := _strict_runtime_monster_id(canonical_monster)
	if monster_id <= 0:
		return {}
	var combat: Dictionary = canonical_monster.get("combat", {})
	var stats: Dictionary = combat.get("stats", {})
	return {
		"monster_id": monster_id,
		"canonical_name": str(canonical_monster.get("canonical_name", "")),
		"experience": int(stats.get("exp", 0)),
		"classification": str(canonical_monster.get("classification", "")),
		"spawn_classification": str(
			canonical_monster.get("spawn_classification", "")
		),
	}


func _request_mobile_attack() -> bool:
	return _world_skill_runtime()._request_mobile_attack()


func _build_melee_input_diagnostic(
	target: EnemyActor,
	mode: String,
	attack_direction: Vector2,
	release_geometry: Dictionary,
	has_hittable_target: bool,
	facing_before: Vector2,
	touch_before: Vector2,
	movement_was_active: bool
) -> Dictionary:
	_melee_diagnostic_serial += 1
	var target_valid := is_instance_valid(target)
	var target_world := target.global_position if target_valid else Vector2.ZERO
	var target_ground_gu := (
		_canonical_screen_px_to_ground_gu(target_world)
		if target_valid
		else Vector2.ZERO
	)
	var input_direction_index := _melee_direction_index(
		attack_direction,
		release_geometry
	)
	var actor_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var target_candidate := (
		WarriorMeleeDiagnosticScript.explain_footprint_candidate(
			actor_ground_gu,
			target_ground_gu,
			target.combat_radius_gu,
			input_direction_index,
			mode
		)
		if target_valid
		else {}
	)
	if target_valid:
		target_candidate["angle_quantization_audit"] = (
			WarriorMeleeDiagnosticScript.audit_ground_delta_gu(
				target_ground_gu - actor_ground_gu
			)
		)
	return {
		"action_id": "player:%d:melee:%d" % [
			player.get_instance_id(),
			_melee_diagnostic_serial,
		],
		"map_id": current_map_id,
		"requested_mode": mode,
		"actor_id": player.get_instance_id(),
		"actor_screen_px_at_input": player.global_position,
		"actor_ground_gu_at_input": actor_ground_gu,
		"locked_target_id": target.get_instance_id() if target_valid else 0,
		"locked_target_name": str(target.display_name) if target_valid else "",
		"target_screen_px_at_input": target_world,
		"target_ground_gu_at_input": target_ground_gu,
		"facing_before_input": facing_before,
		"facing_before_input_index": ArtSpec.direction_index(facing_before),
		"touch_vector_at_input": touch_before,
		"movement_input_active_at_input": movement_was_active,
		"attack_direction_screen_px_at_input": attack_direction,
		"attack_direction_index_at_input": input_direction_index,
		"attack_direction_tile_step_at_input": (
			WarriorMeleeGeometryScript.facing_tile_step(input_direction_index)
		),
		"direction_loop_audit_at_input": (
			WarriorMeleeDiagnosticScript.audit_direction(input_direction_index)
		),
		"locked_target_candidate_at_input": target_candidate,
		"expected_visual_row_at_input": ArtSpec.mir2_client_direction_row(attack_direction),
		"visual_row_before_input": player.visual.current_direction if player.visual != null else -1,
		"has_hittable_target_at_input": has_hittable_target,
		"release_policy_at_input": release_geometry.duplicate(true),
	}


func _request_primary_attack_action() -> void:
	_world_skill_runtime()._request_primary_attack_action()


func _selected_warrior_melee_mode() -> String:
	return _world_skill_runtime()._selected_warrior_melee_mode()


func _has_melee_hittable_target(
	direction: Vector2,
	mode := "",
	release_geometry: Dictionary = {}
) -> bool:
	return _world_skill_runtime()._has_melee_hittable_target(direction, mode, release_geometry)


func _allocate_synthetic_attack_token() -> int:
	return _world_skill_runtime()._allocate_synthetic_attack_token()


func _submit_mobile_attack_ticket(press_token: int) -> void:
	_world_skill_runtime()._submit_mobile_attack_ticket(press_token)


func _drain_next_mobile_attack_ticket() -> bool:
	return _world_skill_runtime()._drain_next_mobile_attack_ticket()


func _refresh_mobile_attack_held() -> void:
	_world_skill_runtime()._refresh_mobile_attack_held()


func _on_mobile_attack_input_started(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	_world_skill_runtime()._on_mobile_attack_input_started(press_token, touch_id, source)


func _on_mobile_attack_input_ended(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	_world_skill_runtime()._on_mobile_attack_input_ended(press_token, touch_id, source)


func _on_mobile_attack_input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
) -> void:
	_world_skill_runtime()._on_mobile_attack_input_cancelled(press_token, touch_id, source, reason)


func _cancel_all_mobile_attack_inputs(_clear_tickets := false) -> void:
	_world_skill_runtime()._cancel_all_mobile_attack_inputs(_clear_tickets)


func _skill_input_key(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int
) -> String:
	return _world_skill_runtime()._skill_input_key(slot_group, slot_index, press_token, touch_id)


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	_world_skill_runtime()._on_skill_input_started(slot_group, slot_index, press_token, touch_id, source)


func _on_skill_input_ended(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName
) -> void:
	_world_skill_runtime()._on_skill_input_ended(slot_group, slot_index, press_token, touch_id, _source)


func _on_skill_input_cancelled(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName,
	_reason: StringName
) -> void:
	_world_skill_runtime()._on_skill_input_cancelled(slot_group, slot_index, press_token, touch_id, _source, _reason)


func _cancel_all_skill_inputs(clear_tickets := false) -> void:
	_world_skill_runtime()._cancel_all_skill_inputs(clear_tickets)


func _reset_attack_action_lifecycle(reason: StringName) -> void:
	_world_skill_runtime()._reset_attack_action_lifecycle(reason)


func _poll_attack_action_lifecycle(input_enabled: bool) -> Dictionary:
	return _world_skill_runtime()._poll_attack_action_lifecycle(input_enabled)


func _record_attack_action_diagnostic(
	kind: StringName,
	reason: StringName,
	details: Dictionary = {}
) -> void:
	_world_skill_runtime()._record_attack_action_diagnostic(kind, reason, details)


func attack_action_lifecycle_snapshot() -> Dictionary:
	return _world_skill_runtime().attack_action_lifecycle_snapshot()


func _submit_skill_input_ticket(entry: Dictionary) -> void:
	_world_skill_runtime()._submit_skill_input_ticket(entry)


func _process_skill_input_actions(delta: float) -> void:
	_world_skill_runtime()._process_skill_input_actions(delta)


func _handle_toggle_skill_input(skill_name: String) -> void:
	_world_skill_runtime()._handle_toggle_skill_input(skill_name)


func _process_magic_shield_auto_refresh(delta: float) -> void:
	_world_skill_runtime()._process_magic_shield_auto_refresh(delta)


func _on_mobile_attack_pressed() -> void:
	_world_skill_runtime()._on_mobile_attack_pressed()


func _on_mobile_attack_released() -> void:
	_world_skill_runtime()._on_mobile_attack_released()


func _ensure_attack_locked_target(excluded: EnemyActor = null) -> EnemyActor:
	return _world_skill_runtime()._ensure_attack_locked_target(excluded)


func _ensure_combat_target(
	excluded: EnemyActor = null,
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU
) -> EnemyActor:
	return _world_skill_runtime()._ensure_combat_target(excluded, _maximum_range_gu)


func _refresh_auto_target(
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU,
	excluded: EnemyActor = null
) -> EnemyActor:
	return _world_skill_runtime()._refresh_auto_target(_maximum_range_gu, excluded)


func _set_attack_locked_target(target: EnemyActor, manual := false) -> void:
	_world_skill_runtime()._set_attack_locked_target(target, manual)


func _set_locked_target(target: EnemyActor, manual := false) -> void:
	_world_skill_runtime()._set_locked_target(target, manual)


func _attack_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._attack_lock_candidates(excluded): values.append(value as EnemyActor)
	return values


func _uses_magic_lock_domain() -> bool:
	return _world_skill_runtime()._uses_magic_lock_domain()


func _magic_target_domain_is_active() -> bool:
	return _world_skill_runtime()._magic_target_domain_is_active()


func _set_active_target_domain_magic(active: bool) -> void:
	_world_skill_runtime()._set_active_target_domain_magic(active)


func _activate_physical_attack_domain() -> void:
	_world_skill_runtime()._activate_physical_attack_domain()


func _activate_magic_skill_domain() -> void:
	_world_skill_runtime()._activate_magic_skill_domain()


func _spell_lock_ground_gu(screen_position_px: Vector2) -> Vector2:
	return _world_skill_runtime()._spell_lock_ground_gu(screen_position_px)


func _spell_lock_distance_gu(target: EnemyActor) -> float:
	return _world_skill_runtime()._spell_lock_distance_gu(target)


func _is_magic_target_in_range(target: EnemyActor) -> bool:
	return _world_skill_runtime()._is_magic_target_in_range(target)


func _spell_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._spell_lock_candidates(excluded): values.append(value as EnemyActor)
	return values


func _set_magic_locked_target(target: EnemyActor, manual := false) -> void:
	_world_skill_runtime()._set_magic_locked_target(target, manual)


func _active_display_target() -> EnemyActor:
	return _world_skill_runtime()._active_display_target()


func _refresh_target_highlights() -> void:
	var active_target := _active_display_target()
	var next_instance_id := (
		active_target.get_instance_id()
		if is_instance_valid(active_target)
		else 0
	)
	var previous_target: EnemyActor = null
	if _presented_target_ref != null:
		var previous_value: Variant = _presented_target_ref.get_ref()
		if previous_value is EnemyActor and is_instance_valid(previous_value):
			previous_target = previous_value as EnemyActor
	if (
		next_instance_id == _presented_target_instance_id
		and previous_target == active_target
	):
		return
	if previous_target != null and previous_target != active_target:
		previous_target.set_targeted(false)
	if is_instance_valid(active_target):
		active_target.set_targeted(true)
	_presented_target_instance_id = next_instance_id
	_presented_target_ref = (
		weakref(active_target)
		if is_instance_valid(active_target)
		else null
	)


func _attack_lock_distance_gu(target: EnemyActor) -> float:
	return _world_skill_runtime()._attack_lock_distance_gu(target)


func _is_attack_target_in_range(target: EnemyActor) -> bool:
	return _world_skill_runtime()._is_attack_target_in_range(target)


func _on_enemy_target_requested(enemy: EnemyActor) -> void:
	_world_skill_runtime()._on_enemy_target_requested(enemy)


func _update_boss_world_mechanics(delta: float) -> void:
	# Only bosses can own these mechanics. The spawn/exit cache keeps this
	# per-frame path independent of the total number of ordinary monsters.
	for value: Variant in _active_boss_cache.values():
		if not value is EnemyActor:
			continue
		var enemy := value as EnemyActor
		if not enemy.is_boss or enemy.is_queued_for_deletion():
			continue
		var relocation: Dictionary = enemy.boss_rule.get("mechanics", {}).get("surroundedRelocation", {})
		if not bool(relocation.get("enabled", false)):
			continue
		var remaining := float(enemy.get_meta("relocation_check_remaining", 0.0)) - delta
		if remaining > 0.0:
			enemy.set_meta("relocation_check_remaining", remaining)
			continue
		enemy.set_meta("relocation_check_remaining", maxf(0.25, float(relocation.get("checkSeconds", 10.0))))
		enemy.request_surrounded_relocation(_blocking_neighbor_count(enemy))


func _blocking_neighbor_count(enemy: EnemyActor) -> int:
	var seen: Dictionary = {}
	var count := 0
	var blocking_radius_gu := maxf(
		BOSS_SURROUNDED_NEIGHBOR_RADIUS_GU,
		enemy.combat_radius_gu * 2.5
	)
	var enemy_ground_gu := _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var candidates: Array = get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("combat_targets")
	candidates.append(player)
	for value: Variant in candidates:
		if not value is Node2D or value == enemy or not is_instance_valid(value):
			continue
		var node := value as Node2D
		var instance_key := str(node.get_instance_id())
		if seen.has(instance_key):
			continue
		var node_ground_gu := _canonical_screen_px_to_ground_gu(
			node.global_position
		)
		if not GroundUnitSpaceScript.is_within_range_gu(
			enemy_ground_gu,
			node_ground_gu,
			blocking_radius_gu
		):
			continue
		seen[instance_key] = true
		count += 1
	return count


func _on_boss_summon_requested(enemy: EnemyActor, monster_ids: Array, count: int, max_active: int) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or monster_ids.is_empty():
		return
	if enemy.current_hp <= 0 or enemy._dying or enemy._death_pending:
		return
	if enemy.runtime_map_id != current_map_id or int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	if _map_transition_in_progress or _world_bootstrap_in_progress:
		return
	_hc_m30_get_summon_queue().enqueue(enemy, monster_ids, count, max_active)



func _on_boss_relocation_requested(enemy: EnemyActor, radius_gu: float) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	var destination := _find_valid_enemy_landing(
		enemy.global_position,
		1.5,
		maxf(1.5, radius_gu),
		enemy.combat_radius_gu,
		enemy
	)
	if destination == enemy.global_position:
		return
	enemy.set_combat_position(destination, &"boss_relocation")
	enemy.velocity = Vector2.ZERO


func _on_enemy_fixed_area_ground_spike_requested(
	descriptor: Dictionary,
	enemy: EnemyActor,
) -> void:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion():
		return
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	if str(descriptor.get("effect_id", "")) != MonsterGroundSpikeEffectScript.EFFECT_ID:
		return
	if str(descriptor.get("release_id", "")).is_empty():
		return
	if int(descriptor.get("source_instance_id", 0)) != enemy.get_instance_id():
		return
	if int(descriptor.get("source_monster_id", -1)) != enemy.monster_id:
		return
	var target_world_px: Variant = descriptor.get("target_world_px", null)
	if not target_world_px is Vector2 or not (target_world_px as Vector2).is_finite():
		return
	var effect: Node2D = MonsterGroundSpikeEffectScript.create_visual(descriptor)
	add_child(effect)


func _find_valid_enemy_landing(
	origin_screen_px: Vector2,
	minimum_distance_gu: float,
	maximum_distance_gu: float,
	combat_radius_gu: float,
	ignored_enemy: EnemyActor
) -> Vector2:
	# Relocation retains its old synchronous 96-attempt API and origin sentinel.
	# Enemy summons instead call ONE probe through the global frame-budget queue.
	var origin_gu: Vector2 = _canonical_screen_px_to_ground_gu(origin_screen_px)
	if not origin_gu.is_finite():
		return origin_screen_px
	for _attempt: int in range(96):
		var candidate_gu: Vector2 = origin_gu + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(minimum_distance_gu, maximum_distance_gu)
		if _hc_m30_landing_clear(candidate_gu, combat_radius_gu, ignored_enemy):
			return _canonical_ground_gu_to_screen_px(candidate_gu)
	return origin_screen_px



func _cycle_target() -> void:
	_validate_locked_target()
	var magic_domain := _magic_target_domain_is_active()
	var candidates := (
		_spell_lock_candidates()
		if magic_domain
		else _attack_lock_candidates()
	)
	if candidates.is_empty():
		if magic_domain:
			_cancel_magic_target()
		else:
			_cancel_target()
		hud.show_error_message(
			"周围12格内没有可锁定目标"
			if magic_domain
			else "周围10格内没有可锁定目标"
		)
		return
	var next_index := 0
	var current_target := magic_locked_target if magic_domain else locked_target
	var current_index := candidates.find(current_target)
	if current_index >= 0:
		next_index = (current_index + 1) % candidates.size()
	if magic_domain:
		_set_magic_locked_target(candidates[next_index], true)
		_skill_cast_target = magic_locked_target
		_face_skill_cast_target()
	else:
		_set_attack_locked_target(candidates[next_index], true)
		_face_locked_target()


func _set_auto_target_enabled(enabled: bool) -> void:
	auto_target_enabled = enabled
	hud.set_auto_target_enabled(enabled)
	if enabled:
		if _uses_magic_lock_domain():
			# Re-enabling auto-target is a fresh selection boundary for casters;
			# clear both independent domains so an inactive stale lock cannot
			# reappear when the next action switches domains.
			_cancel_target()
			_cancel_magic_target()
		else:
			_cancel_target()
	else:
		if _uses_magic_lock_domain():
			manual_target_lock = is_instance_valid(locked_target)
			manual_magic_target_lock = is_instance_valid(magic_locked_target)
		else:
			manual_target_lock = is_instance_valid(locked_target)
		_update_target_hud()


func _on_player_moved(_position: Vector2, _facing: Vector2) -> void:
	_refresh_player_safe_zone_cache()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.player_position_changed(_position)
	_validate_locked_target()
	_mark_passive_monster_wakeup_dirty()
	_pump_passive_monster_wakeup()


func _passive_wake_emitter_current(emitter: Node2D) -> bool:
	if (
		not is_instance_valid(emitter)
		or emitter.is_queued_for_deletion()
		or current_map_id < 0
	):
		return false
	if emitter == player:
		return not player._dead and player.current_hp > 0 and not player.is_stealthed()
	if emitter is SummonActor:
		var summon := emitter as SummonActor
		return (
			is_instance_valid(summon.owner_player)
			and summon.owner_player == player
			and not summon.owner_player._dead
			and summon.owner_player.current_hp > 0
			and summon.runtime_map_id == current_map_id
			and summon.current_hp > 0
			and summon.state not in [SummonActor.SummonState.DEAD, SummonActor.SummonState.EXPIRED]
			and not summon.owner_teleport_pending
			and not summon.is_stealthed()
		)
	return false


func _register_passive_wake_emitter(emitter: Node2D) -> void:
	# Deferred events from a pet leaving the old map must not recreate its
	# registry entry after the map generation has been replaced.
	if (
		not is_instance_valid(emitter)
		or emitter.is_queued_for_deletion()
		or not emitter.is_inside_tree()
		or not is_ancestor_of(emitter)
		or is_queued_for_deletion()
	):
		return
	var id := emitter.get_instance_id()
	if _passive_wake_emitters.has(id):
		_mark_passive_monster_wakeup_dirty(id)
		return
	_passive_wake_emitters[id] = {
		"ref": weakref(emitter),
		"dirty": true,
		"map_id": current_map_id,
		"generation": _zone_generation,
	}
	# Connections belong to the live emitter, while the registry belongs to a
	# map generation. Re-admitting a surviving emitter must reuse its hooks.
	var changed_callback := _on_passive_wake_emitter_changed.bind(id)
	if (
		emitter.has_signal("passive_wakeup_changed")
		and not emitter.is_connected("passive_wakeup_changed", changed_callback)
	):
		emitter.connect("passive_wakeup_changed", changed_callback, CONNECT_DEFERRED)
	var exiting_callback := _on_passive_wake_emitter_exiting.bind(id)
	if not emitter.tree_exiting.is_connected(exiting_callback):
		emitter.tree_exiting.connect(exiting_callback, CONNECT_ONE_SHOT)
	if emitter is SummonActor:
		var summon := emitter as SummonActor
		var state_callback := _on_passive_wake_summon_state_changed.bind(id)
		if not summon.summon_state_changed.is_connected(state_callback):
			summon.summon_state_changed.connect(state_callback, CONNECT_DEFERRED)
	_passive_wake_emitter_queue.append(id)
	_passive_wake_dirty = true
	FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, true, true, false, self, false)


func _on_passive_wake_emitter_changed(emitter_id: int) -> void:
	_mark_passive_monster_wakeup_dirty(emitter_id)


func _on_passive_wake_summon_state_changed(
	_previous_state: int,
	_current_state: int,
	emitter_id: int,
) -> void:
	_mark_passive_monster_wakeup_dirty(emitter_id)


func _on_passive_wake_emitter_exiting(emitter_id: int) -> void:
	_passive_wake_emitters.erase(emitter_id)
	if _passive_wake_active_emitter_id == emitter_id:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		_passive_wake_active_emitter_id = 0


func _mark_passive_wake_emitters_for_extent_availability() -> void:
	# A deferred/dynamic first enemy can establish the spawn-time extent after
	# the initial emitter query. Re-arm the small registered emitter set once;
	# this is a birth-time event, never a per-frame scan.
	var emitter_ids: Array = _passive_wake_emitters.keys()
	for raw_id: Variant in emitter_ids:
		_mark_passive_monster_wakeup_dirty(int(raw_id))


func _mark_passive_monster_wakeup_dirty(emitter_id := 0) -> void:
	if not is_instance_valid(player) or player._dead or current_map_id < 0:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		_passive_wake_active_emitter_id = 0
		_passive_wake_emitter_queue.clear()
		_passive_wake_dirty = false
		FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	if emitter_id <= 0:
		emitter_id = player.get_instance_id()
	var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
	if entry.is_empty():
		var emitter := instance_from_id(emitter_id) as Node2D
		if not is_instance_valid(emitter):
			return
		_register_passive_wake_emitter(emitter)
		return
	if not bool(entry.get("dirty", false)):
		entry["dirty"] = true
		_passive_wake_emitter_queue.append(emitter_id)
	var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
	if is_instance_valid(raw_emitter) and raw_emitter is Node2D and not _passive_wake_emitter_current(raw_emitter as Node2D):
		entry["dirty"] = false
		_passive_wake_emitter_queue.erase(emitter_id)
		if _passive_wake_active_emitter_id == emitter_id:
			_passive_wake_candidates.clear()
			_passive_wake_cursor = 0
			_passive_wake_query_pending = true
			_passive_wake_active_emitter_id = 0
	entry["map_id"] = current_map_id
	entry["generation"] = _zone_generation
	_passive_wake_emitters[emitter_id] = entry
	_passive_wake_dirty = true
	if _passive_wake_active_emitter_id == 0:
		_passive_wake_query_pending = true
	FrameBudget.mark_pending(
		PASSIVE_WAKE_BUDGET_CATEGORY,
		true,
		true,
		false,
		self,
		false,
	)


func _passive_wake_candidate_current(enemy: EnemyActor) -> bool:
	return (
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and not enemy._dying
		and not enemy._death_pending
		and enemy.current_hp > 0
		and enemy.runtime_map_id == current_map_id
		and int(enemy.get_meta("zone_generation", -1)) == _zone_generation
	)


func _begin_passive_monster_wakeup_batch() -> bool:
	if (
		not is_instance_valid(player)
		or player._dead
		or current_map_id < 0
		or _combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
	):
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		return false
	var emitter: Node2D = null
	# Emitter events are necessary acquisition work, even when optional AI
	# has spent its allowance. This finite queue is drained up to a live event.
	while not _passive_wake_emitter_queue.is_empty():
		var emitter_id: int = int(_passive_wake_emitter_queue.pop_front())
		var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
		var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
		if not is_instance_valid(raw_emitter) or not raw_emitter is Node2D:
			_passive_wake_emitters.erase(emitter_id)
			continue
		var candidate_emitter := raw_emitter as Node2D
		if not _passive_wake_emitter_current(candidate_emitter):
			entry["dirty"] = false
			_passive_wake_emitters[emitter_id] = entry
			continue
		if (
			int(entry.get("map_id", -1)) != current_map_id
			or int(entry.get("generation", -1)) != _zone_generation
		):
			entry["dirty"] = false
			_passive_wake_emitters[emitter_id] = entry
			continue
		emitter = candidate_emitter
		_passive_wake_active_emitter_id = emitter_id
		entry["dirty"] = false
		_passive_wake_emitters[emitter_id] = entry
		break
	if emitter == null:
		_passive_wake_active_emitter_id = 0
		return false
	var emitter_ground := _canonical_screen_px_to_ground_gu(emitter.global_position)
	if not emitter_ground.is_finite():
		_retain_passive_wake_active_event()
		return false
	var max_extent := _passive_wake_max_extent_gu
	if (
		_passive_wake_extent_map_id != current_map_id
		or _passive_wake_extent_generation != _zone_generation
	):
		max_extent = 0.0
	if max_extent <= 0.0:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		return true
	var bounds := Rect2(
		emitter_ground - Vector2.ONE * max_extent,
		Vector2.ONE * (max_extent * 2.0),
	)
	if not _target_spatial_query_aabb_into(bounds, _passive_wake_candidates, false):
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		_retain_passive_wake_active_event()
		return false
	_passive_wake_cursor = 0
	_passive_wake_query_pending = false
	return true


func _retain_passive_wake_active_event() -> void:
	# Projection/query availability may recover while the emitter stands still.
	# Retain only this current event in the existing deduplicated queue. The
	# failed service returns immediately; the regular pump can retry later,
	# without a timer, a world scan, or a tight loop inside this callback.
	var emitter_id := _passive_wake_active_emitter_id
	var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
	var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
	if (
		is_instance_valid(raw_emitter)
		and raw_emitter is Node2D
		and _passive_wake_emitter_current(raw_emitter as Node2D)
		and int(entry.get("map_id", -1)) == current_map_id
		and int(entry.get("generation", -1)) == _zone_generation
	):
		entry["dirty"] = true
		_passive_wake_emitters[emitter_id] = entry
		if not _passive_wake_emitter_queue.has(emitter_id):
			_passive_wake_emitter_queue.append(emitter_id)
		_passive_wake_dirty = true
		_passive_wake_query_pending = true


func _pump_passive_monster_wakeup() -> void:
	if not is_instance_valid(player) or player._dead or current_map_id < 0:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_dirty = false
		_passive_wake_query_pending = false
		FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	var process_epoch := Engine.get_process_frames()
	if process_epoch != _passive_wake_pump_epoch:
		_passive_wake_pump_epoch = process_epoch
		_passive_wake_candidates_used = 0
	# A new movement/birth event can arrive after this frame's process pump.
	# Consume that event too; the dirty queue, not the frame number, dedupes work.
	if (
		not _passive_wake_dirty
		and _passive_wake_active_emitter_id == 0
		and not _passive_wake_query_pending
		and _passive_wake_cursor >= _passive_wake_candidates.size()
	):
		FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	FrameBudget.mark_pending(
		PASSIVE_WAKE_BUDGET_CATEGORY,
		true,
		true,
		false,
		self,
		false,
	)
	# Consume the finite emitter events present at entry. Acquisition cannot
	# wait behind optional AI or resource work; new events stay for the next
	# callback, and failed map queries are retried once rather than spun here.
	var event_count := _passive_wake_emitter_queue.size() + (1 if _passive_wake_active_emitter_id != 0 else 0)
	for _event: int in maxi(1, event_count):
		if not _service_passive_monster_wakeup_batch():
			break
		if not _passive_wake_query_pending:
			break


func _service_passive_monster_wakeup_batch() -> bool:
	if _passive_wake_query_pending:
		var query_token := FrameBudget.begin(PASSIVE_WAKE_BUDGET_CATEGORY, true)
		if not _begin_passive_monster_wakeup_batch():
			_passive_wake_dirty = not _passive_wake_emitter_queue.is_empty()
			_passive_wake_query_pending = _passive_wake_dirty
			_passive_wake_active_emitter_id = 0
			if not _passive_wake_dirty:
				FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
			FrameBudget.end(query_token)
			return false
		_passive_wake_dirty = false
		FrameBudget.end(query_token)
	var processed := 0
	var token := FrameBudget.begin(PASSIVE_WAKE_BUDGET_CATEGORY, true)
	while _passive_wake_cursor < _passive_wake_candidates.size():
		var raw_enemy: Variant = _passive_wake_candidates[_passive_wake_cursor]
		_passive_wake_cursor += 1
		processed += 1
		if not is_instance_valid(raw_enemy) or not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		var emitter_entry: Dictionary = _passive_wake_emitters.get(
			_passive_wake_active_emitter_id,
			{}
		)
		var raw_emitter: Variant = emitter_entry.get("ref").get_ref() if emitter_entry.has("ref") else null
		if (
			_passive_wake_candidate_current(enemy)
			and is_instance_valid(raw_emitter)
			and raw_emitter is Node2D
			and _passive_wake_emitter_current(raw_emitter as Node2D)
		):
			var emitter := raw_emitter as Node2D
			if enemy.has_method("request_passive_target_wakeup"):
				enemy.call("request_passive_target_wakeup", emitter, current_map_id, _zone_generation)
			elif emitter == player and enemy.has_method("request_passive_player_wakeup"):
				enemy.call("request_passive_player_wakeup", player, current_map_id, _zone_generation)
	FrameBudget.end(token)
	_passive_wake_candidates_used += processed
	if _passive_wake_cursor >= _passive_wake_candidates.size():
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		var finished_emitter_id := _passive_wake_active_emitter_id
		_passive_wake_active_emitter_id = 0
		var finished_entry: Dictionary = _passive_wake_emitters.get(finished_emitter_id, {})
		if not finished_entry.is_empty() and not bool(finished_entry.get("dirty", false)):
			finished_entry["dirty"] = false
			_passive_wake_emitters[finished_emitter_id] = finished_entry
		_passive_wake_query_pending = not _passive_wake_emitter_queue.is_empty()
		_passive_wake_dirty = _passive_wake_query_pending
		if not _passive_wake_query_pending:
			FrameBudget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
	return true


func _on_player_death_requested() -> void:
	# Death is a lifecycle event, not gameplay input. The input gate correctly
	# rejects zero HP before this delayed notification is delivered.
	if not is_instance_valid(player) or not _active_death_id.is_empty():
		return
	if not player._dead or player.current_hp > 0 or player.combat_transition_is_active():
		return
	# player.gd emits this only after the automatic-revival branch has failed,
	# making it the formal-death boundary.  This boundary opens the gameplay-
	# owned revival choices; no map transition may start before the player
	# explicitly selects one of those choices.
	if not _death_experience_penalty_applied:
		PlayerState.apply_death_experience_penalty()
		_death_experience_penalty_applied = true
	_death_event_serial += 1
	_active_death_id = "death:%d:%d" % [Time.get_ticks_msec(), _death_event_serial]
	_death_revival_request_in_flight = false
	_acquire_gameplay_input_lock(INPUT_LOCK_PLAYER_DEATH)
	_cancel_all_combat_targets()
	_magic_shield_auto_enabled = false
	if is_instance_valid(hud):
		hud.cancel_attack_inputs(&"player_death")
		hud.cancel_skill_inputs(&"player_death")
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	if is_instance_valid(hud):
		hud.show_death_screen(_death_revival_context())


func _death_revival_context() -> Dictionary:
	return {
		"contract_id": DEATH_REVIVAL_CONTRACT_ID,
		"flow_id": DEATH_REVIVAL_FLOW_ID,
		"death_id": _active_death_id,
		"message": "你倒在了%s" % (current_zone if not current_zone.is_empty() else "冒险途中"),
		"loss_text": "死亡损失：经验 10%",
		"revival_options": [
			{
				"option_slot": "town",
				"method_id": "revive.nearest_town",
				"label": "最近城镇复活",
				"enabled": true,
				"countdown_seconds": 0,
				"hint": "返回比奇省安全区",
			},
			{
				"option_slot": "special",
				"method_id": "revive.special.scroll",
				"label": "特殊复活",
				"enabled": false,
				"countdown_seconds": 0,
				"reason": "特殊复活暂不可用",
			},
		],
	}


func _on_revival_requested(request: Dictionary) -> bool:
	if _active_death_id.is_empty() or _death_revival_request_in_flight:
		return false
	if str(request.get("contract_id", "")) != DEATH_REVIVAL_CONTRACT_ID:
		return false
	if str(request.get("death_id", "")) != _active_death_id:
		return false
	if (
		str(request.get("option_slot", "")) != "town"
		or str(request.get("method_id", "")) != "revive.nearest_town"
	):
		return false
	_death_revival_request_in_flight = true
	var accepted := travel_to_service_home(
		false,
		_map_failure_recovery_active,
		"比奇省",
		Callable(self, "_finish_death_revival")
	)
	if accepted:
		return true
	_death_revival_request_in_flight = false
	if is_instance_valid(hud):
		hud.apply_revival_result({
			"success": false,
			"message": "复活位置暂不可用",
			"revival_options": _death_revival_context().get("revival_options", []),
		})
	return false


func _finish_death_revival() -> void:
	var home := _resolve_bich_home()
	if not bool(home.get("valid", false)):
		# Keep the death state; never revive at a source-map current position.
		_handle_home_resolution_failure(&"death_revival", home)
		_death_revival_request_in_flight = false
		if is_instance_valid(hud):
			hud.apply_revival_result({
				"success": false,
				"message": "复活位置暂不可用",
				"revival_options": _death_revival_context().get("revival_options", []),
			})
		return
	_set_player_world_position(home.get("position_px", Vector2.ZERO) as Vector2)
	player.velocity = Vector2.ZERO
	player.complete_death_revival()
	_relocate_main_pets_after_map_arrival()
	background.set_focus_position(player.global_position)
	_record_player_world_location()
	PlayerState.save_game()
	_death_experience_penalty_applied = false
	_active_death_id = ""
	_death_revival_request_in_flight = false
	if _gameplay_input_locks.has(INPUT_LOCK_PLAYER_DEATH):
		_release_gameplay_input_lock(INPUT_LOCK_PLAYER_DEATH)
	if is_instance_valid(hud):
		hud.apply_revival_result({"success": true, "message": "已经复活"})
		hud.show_message("你已在最近的城镇复活", 2.0)


func _cancel_target() -> void:
	_world_skill_runtime()._cancel_target()


func _cancel_magic_target() -> void:
	_world_skill_runtime()._cancel_magic_target()


func _cancel_all_combat_targets() -> void:
	_world_skill_runtime()._cancel_all_combat_targets()


func _validate_locked_target() -> void:
	_world_skill_runtime()._validate_locked_target()


func _face_locked_target() -> Vector2:
	return _world_skill_runtime()._face_locked_target()


func _ensure_skill_cast_target(excluded: EnemyActor = null) -> EnemyActor:
	return _world_skill_runtime()._ensure_skill_cast_target(excluded)


func _face_skill_cast_target() -> Vector2:
	return _world_skill_runtime()._face_skill_cast_target()


func _select_wild_rush_target() -> EnemyActor:
	return _world_skill_runtime()._select_wild_rush_target()


func _wild_rush_target_is_eligible(target: EnemyActor) -> bool:
	return _world_skill_runtime()._wild_rush_target_is_eligible(target)


func _build_wild_rush_path_plan(target: EnemyActor, release_id := "") -> Dictionary:
	return _world_skill_runtime()._build_wild_rush_path_plan(target, release_id)


func _wild_rush_has_dynamic_blocker(
	target: EnemyActor,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> bool:
	return _world_skill_runtime()._wild_rush_has_dynamic_blocker(target, target_ground_gu, direction_ground_gu)


func _wild_rush_static_clear_distance_gu(
	target: EnemyActor,
	player_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> float:
	return _world_skill_runtime()._wild_rush_static_clear_distance_gu(target, player_ground_gu, target_ground_gu, direction_ground_gu)


func _apply_wild_rush_displacement(
	target: EnemyActor,
	effect: Dictionary,
	target_context: Dictionary
) -> bool:
	return _world_skill_runtime()._apply_wild_rush_displacement(target, effect, target_context)


func _update_target_hud() -> void:
	if not is_instance_valid(hud):
		return
	var magic_domain := _magic_target_domain_is_active()
	var active_target := magic_locked_target if magic_domain else locked_target
	# A target can be freed by a test/world teardown without emitting the normal
	# death signal. Never pass that stale Object through a typed range helper.
	var target_valid := false
	if is_instance_valid(active_target) and active_target is EnemyActor:
		target_valid = (
			_is_magic_target_in_range(active_target as EnemyActor)
			if magic_domain
			else _is_attack_target_in_range(active_target as EnemyActor)
		)
	if target_valid:
		hud.update_target(
			active_target.display_name,
			active_target.current_hp,
			active_target.max_hp,
			manual_magic_target_lock if magic_domain else manual_target_lock,
			auto_target_enabled,
			active_target.monster_id
		)
	else:
		hud.update_target("", 0, 0, false, auto_target_enabled)


func play_npc_interaction_voice(service_id: String) -> void:
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_npc_interaction_success(service_id, {"map_id": current_map_id})


func _try_interact() -> void:
	if not gameplay_input_is_enabled(): return
	var nearest: Node2D
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var nearest_distance_gu := (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			105.0
		)
	)
	for node: Node in get_tree().get_nodes_in_group("interactable"):
		if not node is Node2D:
			continue
		var distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(node.global_position)
		)
		if distance_gu < nearest_distance_gu:
			nearest = node
			nearest_distance_gu = distance_gu
	if nearest == null:
		hud.show_error_message("附近没有可交互目标")
		return
	nearest.interact(self)


func _use_quick_slot(index: int) -> void:
	if not gameplay_input_is_enabled(): return
	_use_skill_slot(PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, index)


func _use_skill_slot(slot_group: String, slot_index: int) -> void:
	_world_skill_runtime()._use_skill_slot(slot_group, slot_index)


func _try_release_skill(skill_name: String, show_failure := true) -> StringName:
	return _world_skill_runtime()._try_release_skill(skill_name, show_failure)


func _definition_requires_hostile_target(definition: Dictionary) -> bool:
	return _world_skill_runtime()._definition_requires_hostile_target(definition)


func _hostile_skill_blocked_by_safe_zone(definition: Dictionary) -> bool:
	return _world_skill_runtime()._hostile_skill_blocked_by_safe_zone(definition)


func _spell_definition_allows_target(
	definition: Dictionary,
	target: EnemyActor
) -> bool:
	return _world_skill_runtime()._spell_definition_allows_target(definition, target)


func _wire_item_quick_slots_hud() -> void:
	if not is_instance_valid(hud):
		return
	if (
		hud.has_signal("item_quick_slot_assignment_requested")
		and not hud.is_connected(
			"item_quick_slot_assignment_requested",
			Callable(self, "_on_item_quick_slot_assignment_requested")
		)
	):
		hud.connect(
			"item_quick_slot_assignment_requested",
			Callable(self, "_on_item_quick_slot_assignment_requested")
		)
	if (
		hud.has_signal("item_quick_slot_use_requested")
		and not hud.is_connected(
			"item_quick_slot_use_requested",
			Callable(self, "_on_item_quick_slot_use_requested")
		)
	):
		hud.connect(
			"item_quick_slot_use_requested",
			Callable(self, "_on_item_quick_slot_use_requested")
		)
	_sync_item_quick_slots_to_hud()
	if not PlayerState.quick_item_slots_changed.is_connected(
		_sync_item_quick_slots_to_hud
	):
		PlayerState.quick_item_slots_changed.connect(_sync_item_quick_slots_to_hud)


func _sync_item_quick_slots_to_hud(_change: Dictionary = {}) -> void:
	if not is_instance_valid(hud) or not hud.has_method("set_item_quick_slots"):
		return
	hud.call("set_item_quick_slots", PlayerState.quick_item_slots_snapshot())


func _on_item_quick_slot_assignment_requested(
	slot_index: int,
	item_id: String
) -> void:
	var result := PlayerState.assign_quick_item_slot(slot_index, item_id)
	if not bool(result.get("ok", false)):
		_sync_item_quick_slots_to_hud()
		hud.show_error_message(UIErrorFeedbackScript.user_message(str(result.get("message", "快捷物品绑定失败"))))
		return
	_sync_item_quick_slots_to_hud()
	hud.show_message(str(result.get("message", "快捷物品已绑定")))


func _on_item_quick_slot_use_requested(
	slot_index: int,
	item_id: String
) -> void:
	if not gameplay_input_is_enabled():
		return
	var result := PlayerState.use_quick_item_slot(slot_index, item_id)
	if not bool(result.get("ok", false)):
		hud.show_error_message(UIErrorFeedbackScript.user_message(str(result.get("message", "快捷物品使用失败"))))
		return
	# One player action owns one central result notice (R2). Only the
	# contract-approved uses report (skill books, blessing/repair oils,
	# timed 神水); instant potions stay silent by design.
	var used_item := GameData.get_entity_record(str(result.get("entity_id", "")))
	if UIPlayerNoticeScript.should_report_item_use(used_item):
		hud.show_success_message(str(result.get("message", "")))


func _on_skill_button_assignment_requested(request: Dictionary) -> void:
	var result := (
		SkillLoadoutRulesScript.clear_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			request
		)
		if bool(request.get("clear", false))
		else SkillLoadoutRulesScript.assign_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			PlayerState.skill_assignment_roster(),
			request
		)
	)
	if not bool(result.get("ok", false)):
		hud.show_error_message("技能栏配置失败")
		return
	if not PlayerState.apply_skill_button_assignment(result):
		if is_instance_valid(hud) and hud.has_method("set_skill_button_assignments"):
			hud.call(
				"set_skill_button_assignments",
				PlayerState.skill_button_assignments_snapshot()
			)
		hud.show_error_message("技能栏配置未能保存")
		return
	_reset_attack_action_lifecycle(&"skill_assignment_changed")
	if is_instance_valid(hud):
		hud.cancel_attack_inputs(&"skill_assignment_changed")
		hud.cancel_skill_inputs(&"skill_assignment_changed")
	_cancel_all_mobile_attack_inputs(true)
	_cancel_all_skill_inputs(true)
	hud.set_skill_button_assignments(PlayerState.skill_button_assignments_snapshot())
	var change: Dictionary = result.get("change", {})
	var group_label := (
		"攻击键"
		if str(change.get("slot_group", "")) == PlayerState.SKILL_SLOT_GROUP_ATTACK
		else "攻击环%d" % (int(change.get("slot_index", 0)) + 1)
	)
	if str(change.get("operation", "")) == "clear":
		hud.show_message(
			"%s已恢复普通攻击" % group_label
			if group_label == "攻击键"
			else "%s已清空" % group_label,
			1.5
		)
	else:
		hud.show_message(
			"已将%s配置到%s" % [
				str(change.get("skill_name", "技能")),
				group_label,
			],
			1.5
		)


func _on_player_attack(origin: Vector2, direction: Vector2, damage: int) -> void:
	_world_skill_runtime()._on_player_attack(origin, direction, damage)


func _spawn_target_aligned_melee_visual(
	snapshot: Dictionary,
	mode: String,
	hit_any: bool,
	anchor_screen_px: Vector2,
	release_geometry: Dictionary = {}
) -> void:
	var plan: Dictionary = release_geometry.get("target_aligned_plan", {})
	if plan.is_empty() or not bool(plan.get("target_axis_eligible", false)):
		return
	var visual: Node2D = WarriorMeleeVisualEffectScript.create_visual(
		snapshot,
		mode,
		{"hit": hit_any, "release_id": str(plan.get("release_id", ""))},
		release_geometry.get(
			"snapshot_validation_context",
			_canonical_snapshot_validation_context(plan.get("origin_ground_gu", Vector2.ZERO))
		),
		anchor_screen_px
	)
	if visual == null:
		return
	var parent: Node = self
	if is_inside_tree() and get_tree().current_scene != null:
		parent = get_tree().current_scene
	parent.add_child(visual)
	visual.add_to_group("zone_content")


func _record_melee_release_diagnostic(
	diagnostic: Dictionary,
	context: Dictionary,
	release_geometry: Dictionary,
	origin: Vector2,
	direction: Vector2,
	selection_mode: String,
	effect_mode: String,
	primary_targets: Array[EnemyActor],
	eligible_target_count: int,
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool
) -> void:
	if not CombatDiagnosticLogScript.capture_enabled():
		return
	# Direct unit-test calls deliberately have no input trace. Avoid turning the
	# existing test suite into noisy production telemetry while retaining a
	# complete record for every real mobile/keyboard attack action.
	if diagnostic.is_empty() and PlayerState.test_mode:
		return
	if diagnostic.is_empty():
		_melee_diagnostic_serial += 1
		diagnostic = {
			"action_id": "player:%d:melee:%d" % [
				player.get_instance_id(),
				_melee_diagnostic_serial,
			],
			"actor_id": player.get_instance_id(),
			"map_id": current_map_id,
			"trace_origin": "release_without_input_trace",
		}
	var release_direction_index := _melee_direction_index(
		direction,
		release_geometry
	)
	diagnostic["event"] = "attack_release_resolved"
	diagnostic["body_context"] = context.duplicate(true)
	diagnostic["release_geometry"] = release_geometry.duplicate(true)
	diagnostic["actor_screen_px_at_release"] = origin
	diagnostic["actor_ground_gu_at_release"] = _canonical_screen_px_to_ground_gu(origin)
	diagnostic["release_direction_screen_px"] = direction
	diagnostic["release_direction_index"] = release_direction_index
	diagnostic["release_direction_tile_step"] = (
		WarriorMeleeGeometryScript.facing_tile_step(release_direction_index)
	)
	diagnostic["direction_loop_audit_at_release"] = (
		WarriorMeleeDiagnosticScript.audit_direction(release_direction_index)
	)
	diagnostic["expected_visual_row_at_release"] = ArtSpec.mir2_client_direction_row(direction)
	diagnostic["actual_visual_row_at_release"] = (
		player.visual.current_direction if player.visual != null else -1
	)
	diagnostic["visual_geometry_direction_match"] = (
		player.visual == null
		or player.visual.current_direction == ArtSpec.mir2_client_direction_row(direction)
	)
	diagnostic["player_facing_at_release"] = player.facing
	diagnostic["player_facing_index_at_release"] = ArtSpec.direction_index(player.facing)
	diagnostic["input_release_direction_match"] = (
		int(diagnostic.get("attack_direction_index_at_input", release_direction_index))
		== release_direction_index
	)
	diagnostic["selection_mode"] = selection_mode
	diagnostic["effect_mode"] = effect_mode
	diagnostic["selection_candidate_decisions"] = _melee_candidate_diagnostics(
		origin,
		release_direction_index,
		selection_mode,
		primary_targets
	)
	diagnostic["effect_candidate_decisions"] = _melee_candidate_diagnostics(
		origin,
		release_direction_index,
		effect_mode,
		primary_targets
	)
	diagnostic["primary_target_ids"] = _enemy_instance_ids(primary_targets)
	diagnostic["eligible_target_count"] = eligible_target_count
	diagnostic["has_eligible_target"] = has_eligible_target
	diagnostic["canonical_resolution"] = canonical_resolution
	diagnostic["physical_hit_attempts"] = _active_physical_hit_diagnostics.duplicate(true)
	diagnostic["result_code"] = _melee_diagnostic_result_code(
		has_eligible_target,
		canonical_resolution,
		hit_any,
		_active_physical_hit_diagnostics
	)
	diagnostic["damage_applied"] = hit_any
	CombatDiagnosticLogScript.record(diagnostic)


func _melee_candidate_diagnostics(
	origin: Vector2,
	direction_index: int,
	mode: String,
	primary_targets: Array[EnemyActor]
) -> Array[Dictionary]:
	return _world_skill_runtime()._melee_candidate_diagnostics(origin, direction_index, mode, primary_targets)


func _enemy_instance_ids(enemies: Array[EnemyActor]) -> Array[int]:
	return _world_skill_runtime()._enemy_instance_ids(enemies)


func _melee_direction_index(
	direction: Vector2,
	release_geometry: Dictionary = {}
) -> int:
	return _world_skill_runtime()._melee_direction_index(direction, release_geometry)


func _melee_diagnostic_result_code(
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool,
	hit_attempts: Array[Dictionary]
) -> String:
	return _world_skill_runtime()._melee_diagnostic_result_code(has_eligible_target, canonical_resolution, hit_any, hit_attempts)


func _commit_warrior_melee_modifier_events(modifiers: Dictionary) -> void:
	_world_skill_runtime()._commit_warrior_melee_modifier_events(modifiers)


func _release_equipment_skill(skill_name_or_id: String, show_failure := true) -> StringName:
	return _world_skill_runtime()._release_equipment_skill(skill_name_or_id, show_failure)


func _on_enemy_combat_target_changed(enemy: EnemyActor, new_target: Node2D) -> void:
	if not is_instance_valid(enemy): return
	var id := enemy.get_instance_id()
	if not enemy._dying and not enemy._death_pending and enemy.current_hp > 0 and is_instance_valid(new_target) and (new_target == player or new_target is SummonActor):
		_player_combat_enemy_ids[id] = true
	else:
		_player_combat_enemy_ids.erase(id)
		if not is_instance_valid(new_target):
			_mark_passive_monster_wakeup_dirty()


func _recover_equipment_stealth_if_out_of_combat() -> void:
	if not is_instance_valid(player) or not player._stealth_break_override or not _player_combat_enemy_ids.is_empty():
		return
	if not gameplay_input_is_enabled() or player._dead or player._pending_combat_action_active or player._attack_action_timer > 0.0:
		return
	player.recover_equipment_stealth_after_combat_exit()


func _try_safe_ring_teleport() -> bool:
	var direction_screen_px := player.facing.normalized()
	if direction_screen_px == Vector2.ZERO:
		direction_screen_px = Vector2.DOWN
	var direction_ground := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	for distance_gu: float in SAFE_RING_TELEPORT_DISTANCES_GU:
		var motion_screen_px := (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground * distance_gu
			)
		)
		if not player.test_move(player.global_transform, motion_screen_px):
			player.global_position += motion_screen_px
			player.velocity = Vector2.ZERO
			player.movement_performed.emit(player.global_position, player.facing)
			return true
	return false


func _on_warrior_skill_state_changed(_skill_name: String, _enabled: bool, message: String) -> void:
	PlayerState.apply_warrior_runtime_state(player.warrior_runtime_state_for_save(), true)
	if hud != null:
		hud.show_message(message, 1.5)
		hud.update_warrior_states(player.warrior_state_snapshot())


func _on_skill_cast_audio_started(stable_skill_id: String) -> void:
	_play_skill_audio_phase(stable_skill_id, "cast")


## AOE first-engagement window (perf-smoothness-r1 Phase A): the first
## wizard.fire_wall cast opens the milestone window in AoeEngagementWindow. The
## window closes on the first committed enemy death (or its deadline) and
## reports real wall-clock frame intervals once. See AoeEngagementWindow.
func _on_first_fire_wall_cast_probe(stable_skill_id: String) -> void:
	AoeEngagementWindow.on_skill_cast(stable_skill_id)


func _on_item_audio_committed(identity_domain: String, identity_id: int, semantic_event: String) -> void:
	if identity_domain not in ["item", "service"] or identity_id < 0:
		return
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_item_event(
			"%s:%d" % [identity_domain, identity_id], semantic_event,
			{"map_id": current_map_id},
		)


func _play_skill_audio_phase(stable_skill_id: String, phase: String) -> void:
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_event("skill.%s.%s" % [stable_skill_id, phase], {
			"gender": PlayerState.gender,
			"map_id": current_map_id,
		})


func _on_player_skill(skill_name: String, origin: Vector2, direction: Vector2, damage: int) -> void:
	_world_skill_runtime()._on_player_skill(skill_name, origin, direction, damage)


func _execute_canonical_skill(
	skill_name: String,
	origin: Vector2,
	direction: Vector2,
	client_damage: int,
	extra_target_context: Dictionary = {},
	apply_effects := true,
	authoritative_cast_target := false,
	configuration: RefCounted = null
) -> Dictionary:
	return _world_skill_runtime()._execute_canonical_skill(skill_name, origin, direction, client_damage, extra_target_context, apply_effects, authoritative_cast_target, configuration)


func _execute_canonical_skill_plan(
	skill_name: String, origin: Vector2, direction: Vector2, client_damage: int,
	extra_target_context: Dictionary, apply_effects: bool, authoritative_cast_target: bool,
	configuration: RefCounted, feature_batch: RefCounted
) -> Dictionary:
	return _world_skill_runtime()._execute_canonical_skill_plan(skill_name, origin, direction, client_damage, extra_target_context, apply_effects, authoritative_cast_target, configuration, feature_batch)


func _canonical_execution_context(
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: EnemyActor,
	release_id: String,
	definition: Dictionary = {}
) -> Dictionary:
	return _world_skill_runtime()._canonical_execution_context(stable_skill_id, origin, direction, target_context, target, release_id, definition)


func _q3b_build_line_strip(
	effect: Dictionary,
	release_id: String,
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2,
	definition: Dictionary = {}
) -> Dictionary:
	return _world_skill_runtime()._q3b_build_line_strip(effect, release_id, stable_skill_id, origin, direction, definition)


func _q3b_build_effective_cells(
	raw_geometry_cells: Variant,
	effect: Dictionary,
	stable_skill_id: String,
	definition: Dictionary = {}
) -> Array[Vector2i]:
	return _world_skill_runtime()._q3b_build_effective_cells(raw_geometry_cells, effect, stable_skill_id, definition)


func _legacy_result_from_plan(plan: Dictionary) -> Dictionary:
	return _world_skill_runtime()._legacy_result_from_plan(plan)


func _plan_proficiency_event(plan: Dictionary) -> String:
	return _world_skill_runtime()._plan_proficiency_event(plan)


func _execute_canonical_melee(
	mode: String,
	origin: Vector2,
	direction: Vector2,
	base_damage: int,
	post_body_damage_bonus: int,
	accuracy_bonus: int,
	direct_toggle_release := false,
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	resolved_primary_targets: Array[EnemyActor] = [],
	resolved_thrust_secondaries: Array[EnemyActor] = [],
	resolved_half_moon_secondaries: Array[EnemyActor] = [],
	targets_resolved_at_release := false,
	configuration: RefCounted = null,
	damage_batch: RefCounted = null
) -> Dictionary:
	return _world_skill_runtime()._execute_canonical_melee(mode, origin, direction, base_damage, post_body_damage_bonus, accuracy_bonus, direct_toggle_release, release_geometry, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, resolved_primary_targets, resolved_thrust_secondaries, resolved_half_moon_secondaries, targets_resolved_at_release, configuration, damage_batch)


func _canonical_basic_sword_bonus(origin: Vector2, direction: Vector2, valid_swing: bool) -> int:
	return _world_skill_runtime()._canonical_basic_sword_bonus(origin, direction, valid_swing)


func _canonical_target_context(
	definition: Dictionary,
	origin: Vector2,
	direction: Vector2,
	allow_auto_target := true,
	release_id := "",
	context_overrides: Dictionary = {},
	configuration: RefCounted = null
) -> Dictionary:
	return _world_skill_runtime()._canonical_target_context(definition, origin, direction, allow_auto_target, release_id, context_overrides, configuration)


func _canonical_resource_context(stable_skill_id: String, configuration: RefCounted = null) -> Dictionary:
	return _world_skill_runtime()._canonical_resource_context(stable_skill_id, configuration)


func _commit_canonical_resources(result: Dictionary) -> bool:
	return _world_skill_runtime()._commit_canonical_resources(result)


func _canonical_summon_resource_commit_rejection(plan: Dictionary) -> String:
	return _world_skill_runtime()._canonical_summon_resource_commit_rejection(plan)


func _apply_canonical_effects_from_plan(
	plan: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: EnemyActor = null,
	configuration: RefCounted = null,
	feature_batch: RefCounted = null
) -> Dictionary:
	return _world_skill_runtime()._apply_canonical_effects_from_plan(plan, origin, direction, target_context, target, configuration, feature_batch)


func _spawn_canonical_cast_nodes_from_plan(
	plan: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target: EnemyActor,
	target_position: Vector2,
	configuration: RefCounted = null
) -> Array[Node2D]:
	var values: Array[Node2D] = []
	for value: Variant in _world_skill_runtime()._spawn_canonical_cast_nodes_from_plan(plan, origin, direction, target, target_position, configuration): values.append(value as Node2D)
	return values


func _canonical_plan_ground_effect(plan: Dictionary) -> Dictionary:
	return _world_skill_runtime()._canonical_plan_ground_effect(plan)


func _apply_canonical_main_pet_from_descriptor(
	descriptor: Dictionary,
	plan: Dictionary
) -> void:
	_world_skill_runtime()._apply_canonical_main_pet_from_descriptor(descriptor, plan)


func _canonical_effect_enemy(effect: Dictionary) -> EnemyActor:
	return _world_skill_runtime()._canonical_effect_enemy(effect)


func _set_canonical_fire_charge_expires_at(expires_at_ms: int) -> void:
	_world_skill_runtime()._set_canonical_fire_charge_expires_at(expires_at_ms)


func _expire_canonical_fire_charge_if_needed() -> void:
	_world_skill_runtime()._expire_canonical_fire_charge_if_needed()


func _apply_canonical_spell_damage(
	stable_skill_id: String,
	raw_power: int,
	origin: Vector2,
	direction: Vector2,
	effect_type: String,
	primary: EnemyActor,
	raw_geometry_cells: Variant = [],
	effect: Dictionary = {},
	continuous_line_strip_ground_gu: Dictionary = {},
	skill_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
	release_cache: Dictionary = {},
	damage_batch: RefCounted = null,
) -> bool:
	return _world_skill_runtime()._apply_canonical_spell_damage(stable_skill_id, raw_power, origin, direction, effect_type, primary, raw_geometry_cells, effect, continuous_line_strip_ground_gu, skill_release_snapshot, query_plan, release_cache, damage_batch)


func _record_aoe_candidate_timing(started_usec: int) -> void:
	_world_skill_runtime()._record_aoe_candidate_timing(started_usec)


func _record_skill_footprint_release_diagnostic(
	stable_skill_id: String,
	skill_release_snapshot: Dictionary,
	eligible_target_count: int,
	damage_applied: bool
) -> void:
	_world_skill_runtime()._record_skill_footprint_release_diagnostic(stable_skill_id, skill_release_snapshot, eligible_target_count, damage_applied)


func _actor_combat_radius_gu(actor: Node2D) -> float:
	return _world_skill_runtime()._actor_combat_radius_gu(actor)


func _skill_snapshot_intersects_enemy(
	skill_release_snapshot: Dictionary,
	enemy: EnemyActor
) -> bool:
	return _world_skill_runtime()._skill_snapshot_intersects_enemy(skill_release_snapshot, enemy)


func _canonical_effective_spell_geometry_cells(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	definition: Dictionary = {}
) -> Array[Vector2i]:
	return _world_skill_runtime()._canonical_effective_spell_geometry_cells(stable_skill_id, raw_geometry_cells, effect, definition)


func _is_supported_continuous_line_contract(
	contract_id: String
) -> bool:
	return _world_skill_runtime()._is_supported_continuous_line_contract(contract_id)


func _canonical_continuous_line_strip_ground_gu(
	stable_skill_id: String,
	effect: Dictionary,
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	release_id := "",
	definition: Dictionary = {}
) -> Dictionary:
	return _world_skill_runtime()._canonical_continuous_line_strip_ground_gu(stable_skill_id, effect, origin_screen_px, direction_screen_px, release_id, definition)


func _canonical_continuous_line_unblocked_length_gu(
	line_strip_ground_gu: Dictionary
) -> float:
	return _world_skill_runtime()._canonical_continuous_line_unblocked_length_gu(line_strip_ground_gu)


func _canonical_spell_cell_is_terrain_blocked(cell: Vector2i) -> bool:
	return _world_skill_runtime()._canonical_spell_cell_is_terrain_blocked(cell)


func _aoe_collect_continuous_line_candidates(
	plan: Dictionary,
	line_strip: Dictionary,
	candidates: Array[EnemyActor],
	targets: Array[EnemyActor],
	distances: Array[float],
	ids: Array[int],
	origin_ground_gu: Vector2,
	direction_ground_gu: Vector2,
) -> void:
	_world_skill_runtime()._aoe_collect_continuous_line_candidates(plan, line_strip, candidates, targets, distances, ids, origin_ground_gu, direction_ground_gu)


func _canonical_spell_geometry_targets(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary,
	continuous_line_strip_ground_gu: Dictionary = {},
	skill_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._canonical_spell_geometry_targets(stable_skill_id, raw_geometry_cells, effect, continuous_line_strip_ground_gu, skill_release_snapshot, query_plan): values.append(value as EnemyActor)
	return values


func _enemy_footprint_polygon_ground_gu(enemy: EnemyActor) -> PackedVector2Array:
	return _world_skill_runtime()._enemy_footprint_polygon_ground_gu(enemy)


func _ground_circle_intersects_enemy_footprint_gu(
	center_screen_px: Vector2,
	radius_gu: float,
	enemy: EnemyActor
) -> bool:
	return _world_skill_runtime()._ground_circle_intersects_enemy_footprint_gu(center_screen_px, radius_gu, enemy)


func _spawn_canonical_ground_field(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	fallback_position: Vector2,
	effect: Dictionary,
	release_id := "",
	skill_release_snapshot: Dictionary = {}
) -> Array[Node2D]:
	var values: Array[Node2D] = []
	for value: Variant in _world_skill_runtime()._spawn_canonical_ground_field(stable_skill_id, raw_geometry_cells, fallback_position, effect, release_id, skill_release_snapshot): values.append(value as Node2D)
	return values


## SOT wizard.fire_wall mechanics (mir2_176_skills_source_of_truth_v1,
## status project_canonical):
##   "stacking_policy":
##     "same_caster_same_tile_refreshes_duration; one target takes at most
##      one tick per caster per tick"
##   "max_active_fields_per_caster": "config_required_default_8"
## The registry below restores that canonical stacking contract in the
## runtime: same center tile refreshes the existing field, different tiles
## create fields up to the canonical cap. The registry key is source-aware
## (GPT audit R1-P0): map, zone generation, caster identity, skill family
## and the selected center tile — a tile alone is not the field identity, so
## two casters on one tile own separate fields and never cross-refresh.
## Cap policy: explicit data from the SOT mechanics ("cap_policy":
## "evict_oldest" | "reject_new"). R2 ruling (user device ruling
## 2026-09-15): the SOT now records evict_oldest for wizard.fire_wall —
## casting always succeeds and the oldest field is cancelled at the cap —
## because the R1-P0 reject_new default locked the skill out for the whole
## 10-40s field duration window. Unconfigured data still fails closed to
## reject_new.
const FIRE_WALL_MAX_ACTIVE_FIELDS_PER_CASTER := 8
const FIRE_WALL_CAP_POLICY_EVICT_OLDEST := "evict_oldest"
const FIRE_WALL_CAP_POLICY_REJECT_NEW := "reject_new"
var _fire_wall_field_registry: Dictionary = {}
var _fire_wall_field_order: Array = []
## R2-6 (GPT audit adoption): debug registry-invariant switch. The
## functional-verification APK keeps it on; the dedicated performance A/B
## build turns it off so lifecycle diagnostics cannot pollute frame-timing
## percentiles during rapid fire-wall casting.
var _fire_wall_registry_validation_enabled := true


func _fire_wall_registry_controller_is_active(controller: Variant) -> bool:
	return _world_skill_runtime()._fire_wall_registry_controller_is_active(controller)


func _fire_wall_registry_center_cell(coverage_cells: Array[Vector2i]) -> Vector2i:
	return _world_skill_runtime()._fire_wall_registry_center_cell(coverage_cells)


func _fire_wall_registry_key(
	caster: Node2D,
	family: String,
	registry_center: Vector2i
) -> String:
	return _world_skill_runtime()._fire_wall_registry_key(caster, family, registry_center)


func _fire_wall_registry_caster_prefix(caster: Node2D) -> String:
	return _world_skill_runtime()._fire_wall_registry_caster_prefix(caster)


func _fire_wall_max_active_fields(effect: Dictionary) -> int:
	return _world_skill_runtime()._fire_wall_max_active_fields(effect)


func _fire_wall_cap_policy(effect: Dictionary) -> String:
	return _world_skill_runtime()._fire_wall_cap_policy(effect)


func _fire_wall_cap_allows_new_field(
	effect: Dictionary,
	caster: Node2D,
	_family: String
) -> bool:
	return _world_skill_runtime()._fire_wall_cap_allows_new_field(effect, caster, _family)


func _fire_wall_prune_invalid_registry_entries() -> void:
	_world_skill_runtime()._fire_wall_prune_invalid_registry_entries()


func _on_fire_wall_field_tree_exited(
	registry_key: String,
	controller: FireWallFieldController
) -> void:
	_world_skill_runtime()._on_fire_wall_field_tree_exited(registry_key, controller)


func _debug_validate_fire_wall_registry(context := "") -> void:
	_world_skill_runtime()._debug_validate_fire_wall_registry(context)


func _fire_wall_evict_oldest_field_for_caster(caster_prefix: String) -> void:
	_world_skill_runtime()._fire_wall_evict_oldest_field_for_caster(caster_prefix)


func _clear_fire_wall_field_registry() -> void:
	_world_skill_runtime()._clear_fire_wall_field_registry()


func _spawn_canonical_ground_effect(
	stable_skill_id: String,
	position: Vector2,
	effect: Dictionary,
	applies_damage := true,
	coverage_cell: Variant = null,
	release_id := "",
	skill_release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {}
) -> GroundSkillEffect:
	return _world_skill_runtime()._spawn_canonical_ground_effect(stable_skill_id, position, effect, applies_damage, coverage_cell, release_id, skill_release_snapshot, snapshot_validation_context)


func _register_manager_ground_effect(
	ground_effect: GroundSkillEffect,
	stable_skill_id: String,
	release_id: String,
	skill_release_snapshot: Dictionary,
	snapshot_validation_context: Dictionary
) -> void:
	_world_skill_runtime()._register_manager_ground_effect(ground_effect, stable_skill_id, release_id, skill_release_snapshot, snapshot_validation_context)


func _manager_ground_effect_ended(reason: String, effect: Variant) -> void:
	if effect is Node and is_instance_valid(effect):
		(effect as Node).queue_free()


func _canonical_ground_cell_contains_enemy(
	enemy: EnemyActor,
	coverage_cell: Vector2i
) -> bool:
	return _world_skill_runtime()._canonical_ground_cell_contains_enemy(enemy, coverage_cell)


func _ground_field_snapshot_contains_enemy(
	enemy: EnemyActor,
	skill_release_snapshot: Dictionary
) -> bool:
	return _world_skill_runtime()._ground_field_snapshot_contains_enemy(enemy, skill_release_snapshot)


func _ignore_canonical_ground_visual_tick(
	_enemy: EnemyActor,
	_raw_power: int
) -> void:
	_world_skill_runtime()._ignore_canonical_ground_visual_tick(_enemy, _raw_power)


func _apply_canonical_ground_tick(enemy: EnemyActor, raw_power: int, stable_skill_id: String) -> void:
	_world_skill_runtime()._apply_canonical_ground_tick(enemy, raw_power, stable_skill_id)


func _apply_canonical_displacement_screen_px(
	actor: Node2D,
	displacement_screen_px: Vector2
) -> bool:
	return _world_skill_runtime()._apply_canonical_displacement_screen_px(actor, displacement_screen_px)


func _apply_canonical_player_teleport(destination: Vector2) -> bool:
	return _world_skill_runtime()._apply_canonical_player_teleport(destination)


func _apply_canonical_poison(target: EnemyActor, effect: Dictionary) -> void:
	_world_skill_runtime()._apply_canonical_poison(target, effect)


func _apply_canonical_temptation(target: EnemyActor, effect: Dictionary) -> void:
	_world_skill_runtime()._apply_canonical_temptation(target, effect)


func _synchronize_main_pet_skill_ranks() -> void:
	_world_skill_runtime()._synchronize_main_pet_skill_ranks()


func _synchronize_pet_skill_rank(summon: SummonActor) -> void:
	_world_skill_runtime()._synchronize_pet_skill_rank(summon)


func _canonical_main_pet(summon_id: String = "") -> SummonActor:
	return _world_skill_runtime()._canonical_main_pet(summon_id)


func _canonical_main_pets(summon_id: String = "") -> Array[SummonActor]:
	var values: Array[SummonActor] = []
	for value: Variant in _world_skill_runtime()._canonical_main_pets(summon_id): values.append(value as SummonActor)
	return values


func _owned_skeleton_slots() -> Dictionary:
	return _world_skill_runtime()._owned_skeleton_slots()


func _next_skeleton_slot_index(used: Dictionary) -> int:
	return _world_skill_runtime()._next_skeleton_slot_index(used)


func _canonical_main_pet_summon_ids() -> Array[String]:
	return _world_skill_runtime()._canonical_main_pet_summon_ids()


static func _summon_id_for_skill(stable_skill_id: String) -> String:
	match stable_skill_id:
		"taoist.summon_skeleton":
			return "skeleton"
		"taoist.summon_divine_beast":
			return "divine_beast"
	return ""


func _capture_taoist_main_pet_runtime_states() -> Dictionary:
	return _world_skill_runtime()._capture_taoist_main_pet_runtime_states()


func _on_canonical_main_pet_state_changed(
	_previous_state: int,
	current_state: int,
	summon: SummonActor
) -> void:
	_world_skill_runtime()._on_canonical_main_pet_state_changed(_previous_state, current_state, summon)


func _wire_canonical_main_pet_persistence(summon: SummonActor) -> void:
	summon.summon_state_changed.connect(
		Callable(self, "_on_canonical_main_pet_state_changed").bind(summon)
	)


func _restore_persisted_taoist_main_pet_if_needed(allow_deferred_arrival: bool = false) -> bool:
	return _world_skill_runtime()._restore_persisted_taoist_main_pet_if_needed(allow_deferred_arrival)


func _canonical_friendly_actor(instance_id: int) -> Node2D:
	return _world_skill_runtime()._canonical_friendly_actor(instance_id)


func _apply_canonical_friendly_heal(actor: Node2D, amount: int) -> int:
	return _world_skill_runtime()._apply_canonical_friendly_heal(actor, amount)


func _register_ongoing_heal(
	target_instance_id: int,
	heal_per_tick: int,
	tick_count: int,
	tick_interval_seconds: float
) -> void:
	_world_skill_runtime()._register_ongoing_heal(target_instance_id, heal_per_tick, tick_count, tick_interval_seconds)


func _tick_ongoing_heals(delta: float) -> void:
	_world_skill_runtime()._tick_ongoing_heals(delta)


func _ongoing_heal_remaining_ticks(target_instance_id: int) -> int:
	return _world_skill_runtime()._ongoing_heal_remaining_ticks(target_instance_id)


func _set_actor_stealth_alpha(actor: Node2D, stealthed: bool) -> void:
	if not is_instance_valid(actor):
		return
	var actor_id := actor.get_instance_id()
	if actor is SummonActor:
		## SummonActor owns body/fire fading through self_modulate. Keeping the
		## parent opaque leaves its health bar and buff hints fully readable.
		actor.modulate.a = 1.0
		## Discard values cached by builds that faded the whole summon parent.
		_stealth_alpha_restore.erase(actor_id)
		return
	if stealthed:
		if not _stealth_alpha_restore.has(actor_id):
			_stealth_alpha_restore[actor_id] = actor.modulate.a
		actor.modulate.a = PLAYER_STEALTH_ALPHA
	else:
		if _stealth_alpha_restore.has(actor_id):
			actor.modulate.a = float(_stealth_alpha_restore[actor_id])
			_stealth_alpha_restore.erase(actor_id)


func _update_stealth_alpha() -> void:
	if not is_instance_valid(player):
		return
	_set_actor_stealth_alpha(player, player.is_stealthed())
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if (
			node is SummonActor
			and (node as SummonActor).owner_player == player
		):
			_set_actor_stealth_alpha(
				node as SummonActor,
				(node as SummonActor).is_stealthed()
			)


func _update_taoist_buff_hints() -> void:
	if hud == null or not is_instance_valid(player):
		return
	var entries := _status_buff_entries()
	var signature: Array = []
	for entry: Dictionary in entries:
		signature.append([entry.id, ceili(entry.remaining), entry.started_at, entry.get("item_id", -1)])
	var hint_text := str(signature)
	if hint_text == _last_taoist_buff_hint_text:
		return
	_last_taoist_buff_hint_text = hint_text
	hud.update_status_buffs(entries)

func _status_buff_entries() -> Array:
	var entries: Array = []
	for spec: Array in [["ac", player.defense_buff_time, player.defense_buff > 0], ["mac", player.mac_buff_time, player.mac_buff > 0], ["shield", player.shield_time, player.shield_capacity > 0.0], ["stealth", player.stealth_time, player.is_stealthed()]]:
		if not bool(spec[2]) or (float(spec[1]) <= 0.0 and spec[0] != "stealth"): continue
		var entry := {"id":spec[0], "remaining":spec[1], "started_at":int(player.status_buff_started_at.get(spec[0], 0))}
		if spec[0] == "shield": entry.skill = "魔法盾"
		if spec[0] == "stealth": entry.skill = "隐身术"
		entries.append(entry)
	var heal_remaining := 0.0
	var heal_started := 9223372036854775807
	for heal: Dictionary in _ongoing_heals:
		if int(heal.target_instance_id) != player.get_instance_id(): continue
		heal_remaining = maxf(heal_remaining, int(heal.remaining_ticks) * float(heal.tick_interval_seconds) - float(heal.elapsed))
		heal_started = mini(heal_started, int(heal.get("started_at_usec", 0)))
	if heal_remaining > 0.0:
		entries.append({"id":"heal", "skill":"治愈术", "remaining":heal_remaining, "started_at":heal_started})
	for buff: Dictionary in PlayerState.temporary_item_buffs.values():
		if float(buff.remaining) <= 0.0: continue
		entries.append({"id":"item:" + str(buff.buffGroup), "entity_id":str(buff.get("entity_id", "")), "item_id":int(buff.get("item_id", -1)), "remaining":float(buff.remaining), "started_at":int(buff.get("started_at_usec", 0))})
	var relic_proc := PlayerState.relic_proc_status()
	if float(relic_proc.get("remaining", 0.0)) > 0.0:
		entries.append({"id": "relic:%d" % int(relic_proc.get("item_id", -1)), "item_id": int(relic_proc.get("item_id", -1)), "remaining": float(relic_proc.remaining), "started_at": int(relic_proc.get("started_at_usec", 0))})
	# Player 麻痹/中毒 no longer surface on the bottom HUD buff strip (R1.1):
	# they present as fixed-slot dots on the status marker row under the
	# player overhead HP bar (PlayerStatusMarkerStrip). Gameplay poison and
	# control timers are unchanged.
	return entries


func _canonical_friendly_candidates() -> Array:
	return _world_skill_runtime()._canonical_friendly_candidates()


func _select_taoist_heal_target(center_ground_gu: Vector2) -> Dictionary:
	return _world_skill_runtime()._select_taoist_heal_target(center_ground_gu)


func _resolve_release_friendly_target(
	requested_instance_id: int,
	candidates: Array,
	center_ground_gu: Vector2
) -> Dictionary:
	return _world_skill_runtime()._resolve_release_friendly_target(requested_instance_id, candidates, center_ground_gu)


func _apply_friendly_defence_buff_to_actor(
	actor: Node2D,
	stat: String,
	value: int,
	duration_seconds: float,
	buff_id: String
) -> void:
	_world_skill_runtime()._apply_friendly_defence_buff_to_actor(actor, stat, value, duration_seconds, buff_id)


func _apply_friendly_stealth_to_actor(
	actor: Node2D,
	duration_seconds: float,
	buff_id: String
) -> void:
	_world_skill_runtime()._apply_friendly_stealth_to_actor(actor, duration_seconds, buff_id)


func _apply_canonical_main_pet(
	descriptor: Dictionary,
	stable_skill_id: String,
	release_id: String
) -> void:
	_world_skill_runtime()._apply_canonical_main_pet(descriptor, stable_skill_id, release_id)


func _relocate_main_pets_after_map_arrival() -> void:
	_world_skill_runtime()._relocate_main_pets_after_map_arrival()


func _main_pet_follow_context_is_current(summon: SummonActor) -> bool:
	return _world_skill_runtime()._main_pet_follow_context_is_current(summon)


func _canonical_summon_follow_landing_plan(summon: SummonActor) -> Dictionary:
	return _world_skill_runtime()._canonical_summon_follow_landing_plan(summon)


func _register_pending_main_pet_arrival(summon: SummonActor) -> bool:
	return _world_skill_runtime()._register_pending_main_pet_arrival(summon)


func _main_pet_owner_tile() -> Vector2i:
	return _world_skill_runtime()._main_pet_owner_tile()


func _retry_pending_main_pet_arrivals() -> void:
	_world_skill_runtime()._retry_pending_main_pet_arrivals()


func _canonical_summon_teleport_fallback_plan(
	summon: SummonActor,
	pending: Array[SummonActor],
) -> Dictionary:
	return _world_skill_runtime()._canonical_summon_teleport_fallback_plan(summon, pending)


func _canonical_summon_spawn_plan(
	stable_skill_id: String,
	ignored_summon: SummonActor = null,
	pet_slot_index: int = 0,
	ignored_summons: Array[SummonActor] = [],
) -> Dictionary:
	return _world_skill_runtime()._canonical_summon_spawn_plan(stable_skill_id, ignored_summon, pet_slot_index, ignored_summons)


func _canonical_summon_position_is_valid(
	candidate_ground_gu: Vector2,
	summon_radius_gu: float,
	ignored_summon: SummonActor,
	ignored_summons: Array[SummonActor] = [],
) -> bool:
	return _world_skill_runtime()._canonical_summon_position_is_valid(candidate_ground_gu, summon_radius_gu, ignored_summon, ignored_summons)


func _summon_spawn_screen_position_px() -> Vector2:
	return _world_skill_runtime()._summon_spawn_screen_position_px()


func _spawn_canonical_teleport_arrival(
	stable_skill_id: String,
	destination: Vector2,
	direction: Vector2,
	skill_release_snapshot: Dictionary = {}
) -> void:
	if stable_skill_id != "wizard.teleport":
		return
	var visual_profile := CasterSkillVisualRegistry.profile(stable_skill_id)
	var arrival_presentation := {
		"success": true,
		"skill_id": stable_skill_id,
		"release_id": str(skill_release_snapshot.get("release_id", "")),
		"canonical_geometry_contract": CasterSpellGeometryScript.CONTRACT_ID,
		"ground_gu_to_screen_position_px": Callable(self, "_canonical_ground_gu_to_screen_px"),
		"operation": "canonical_visual_only",
		"visual": visual_profile,
		"visual_duration": CasterSkillVisualRegistry.animation_duration(
			stable_skill_id,
			"arrival"
		),
		"visual_radius_px": 72.0,
		"snapshot_validation_policy": (
			SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
		),
		"snapshot_validation_context": _canonical_snapshot_validation_context(
			_canonical_screen_px_to_ground_gu(destination)
		),
		"skill_footprint_snapshot": skill_release_snapshot,
	}
	var arrival := CasterSkillRuntimeScript.create_visual(
		arrival_presentation,
		destination,
		direction,
		player,
		"arrival"
	)
	if arrival != null:
		add_child(arrival)


func _record_player_world_location() -> void:
	if not is_instance_valid(player):
		return
	var ground_gu := _ground_position_gu_for_map(
		current_map_id,
		player.global_position
	)
	if not ground_gu.is_finite():
		# FREEZE-P0.2: never write Vector2.INF into PlayerState.
		return
	PlayerState.update_world_location(
		current_map_id,
		player.global_position,
		ground_gu
	)


func _ground_position_gu_for_map(
	map_id: int,
	screen_position_px: Vector2
) -> Vector2:
	return _world_skill_runtime()._ground_position_gu_for_map(map_id, screen_position_px)


func _canonical_screen_px_to_grid_cell(screen_position_px: Vector2) -> Vector2i:
	return _world_skill_runtime()._canonical_screen_px_to_grid_cell(screen_position_px)


func _resolve_projection_profile_for_map(map_id: int) -> Dictionary:
	return _world_skill_runtime()._resolve_projection_profile_for_map(map_id)


func _try_canonical_screen_px_to_ground_gu(
	screen_position_px: Vector2
) -> Dictionary:
	return _world_skill_runtime()._try_canonical_screen_px_to_ground_gu(screen_position_px)


func _try_canonical_ground_gu_to_screen_px(
	ground_position_gu: Vector2
) -> Dictionary:
	return _world_skill_runtime()._try_canonical_ground_gu_to_screen_px(ground_position_gu)


func _canonical_screen_px_to_ground_gu(screen_position_px: Vector2) -> Vector2:
	return _world_skill_runtime()._canonical_screen_px_to_ground_gu(screen_position_px)


func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2:
	return _world_skill_runtime()._canonical_ground_gu_to_screen_px(ground_position_gu)


func _canonical_grid_cell_to_screen_px(grid_cell: Variant) -> Vector2:
	return _world_skill_runtime()._canonical_grid_cell_to_screen_px(grid_cell)


func _canonical_snapshot_absolute_context(
	origin_ground_gu: Vector2
) -> Dictionary:
	return _world_skill_runtime()._canonical_snapshot_absolute_context(origin_ground_gu)


func _canonical_snapshot_validation_context(
	origin_ground_gu: Vector2
) -> Dictionary:
	return _world_skill_runtime()._canonical_snapshot_validation_context(origin_ground_gu)


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	return _world_skill_runtime()._snapshot_strict_ok(snapshot)


func _canonical_facing(direction: Vector2) -> Vector2i:
	return _world_skill_runtime()._canonical_facing(direction)


func _canonical_facing_for_skill(skill_id: String, direction: Vector2) -> Vector2i:
	return _world_skill_runtime()._canonical_facing_for_skill(skill_id, direction)


func _canonical_primary_stat_roll(profession_id: String, stats: Dictionary = {}) -> int:
	return _world_skill_runtime()._canonical_primary_stat_roll(profession_id, stats)


func _next_canonical_seed() -> int:
	return _world_skill_runtime()._next_canonical_seed()


func _next_skill_footprint_release_id(stable_skill_id: String) -> String:
	return _world_skill_runtime()._next_skill_footprint_release_id(stable_skill_id)


func _skill_needs_target(cast_type: String) -> bool:
	return _world_skill_runtime()._skill_needs_target(cast_type)


func _spawn_projectile(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	maximum_distance_gu: float,
	color: Color,
	effect := "damage",
	effect_strength := 0,
	effect_duration := 0.0,
	source_skill_id := "",
	source_release_id := ""
) -> void:
	_world_skill_runtime()._spawn_projectile(origin_screen_px, direction_screen_px, damage, maximum_distance_gu, color, effect, effect_strength, effect_duration, source_skill_id, source_release_id)


func _damage_enemies(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	damage: int,
	radial: bool,
	attack_range_gu := 1.5,
	physical_accuracy := false,
	source_skill_id := "",
	query_plan: Dictionary = {},
) -> bool:
	return _world_skill_runtime()._damage_enemies(origin_screen_px, direction_screen_px, damage, radial, attack_range_gu, physical_accuracy, source_skill_id, query_plan)


func _resolve_magic_defense(_skill_id: String, damage_after_anti_magic: int, target_stats: Dictionary) -> int:
	return _world_skill_runtime()._resolve_magic_defense(_skill_id, damage_after_anti_magic, target_stats)


func _combat_release_target(release_geometry: Dictionary) -> EnemyActor:
	return _world_skill_runtime()._combat_release_target(release_geometry)


func _create_melee_release_footprint_snapshot(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	mode: String,
	release_geometry: Dictionary = {}
) -> Dictionary:
	return _world_skill_runtime()._create_melee_release_footprint_snapshot(origin_screen_px, direction_screen_px, mode, release_geometry)


func _physical_primary_target(
	origin: Vector2,
	direction: Vector2,
	mode := "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> EnemyActor:
	return _world_skill_runtime()._physical_primary_target(origin, direction, mode, release_geometry, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, query_plan)


func _physical_primary_targets(
	origin: Vector2,
	direction: Vector2,
	mode := "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._physical_primary_targets(origin, direction, mode, release_geometry, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, query_plan): values.append(value as EnemyActor)
	return values


func _sort_melee_targets(
	targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	release_geometry: Dictionary
) -> void:
	_world_skill_runtime()._sort_melee_targets(targets, origin_ground_gu, release_geometry)


func _is_primary_melee_candidate(
	enemy: EnemyActor,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> bool:
	return _world_skill_runtime()._is_primary_melee_candidate(enemy, origin_ground_gu, direction_index, mode, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, query_plan)


func _apply_physical_hit(
	enemy: EnemyActor, damage: int, accuracy_bonus := 0, ignore_ac := false, configuration: RefCounted = null, damage_batch: RefCounted = null
) -> bool:
	return _world_skill_runtime()._apply_physical_hit(enemy, damage, accuracy_bonus, ignore_ac, configuration, damage_batch)


func _aoe_collect_thrust_secondary_candidates(
	candidates: Array[EnemyActor],
	result: Array[EnemyActor],
	excluded_targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	target_plan: Dictionary,
	thrust_damage_axis_plan: Dictionary,
	melee_release_snapshot: Dictionary,
	query_plan: Dictionary,
	direction_index: int,
	release_geometry: Dictionary,
) -> void:
	_world_skill_runtime()._aoe_collect_thrust_secondary_candidates(candidates, result, excluded_targets, origin_ground_gu, target_plan, thrust_damage_axis_plan, melee_release_snapshot, query_plan, direction_index, release_geometry)


func _aoe_collect_half_moon_secondary_candidates(
	candidates: Array[EnemyActor],
	result: Array[EnemyActor],
	excluded_targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	direction_index: int,
	target_plan: Dictionary,
	query_plan: Dictionary,
	release_geometry: Dictionary,
) -> void:
	_world_skill_runtime()._aoe_collect_half_moon_secondary_candidates(candidates, result, excluded_targets, origin_ground_gu, direction_index, target_plan, query_plan, release_geometry)


func _thrust_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._thrust_secondary_targets(origin, direction, excluded_targets, release_geometry, thrust_damage_axis_plan, melee_release_snapshot, target_aligned_plan, query_plan): values.append(value as EnemyActor)
	return values


func _half_moon_secondary_targets(
	origin: Vector2,
	direction: Vector2,
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var values: Array[EnemyActor] = []
	for value: Variant in _world_skill_runtime()._half_moon_secondary_targets(origin, direction, excluded_targets, release_geometry, melee_release_snapshot, query_plan): values.append(value as EnemyActor)
	return values


func _execute_wild_rush(_direction: Vector2, _skill_level: int) -> bool:
	return _world_skill_runtime()._execute_wild_rush(_direction, _skill_level)


func _show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	# Removed: the prototype drew a three-point V on every attack and also
	# overlaid the final Magic.wil skill effects.  Finished combat art is owned
	# by PlayerVisual; attacks without formal art deliberately show no fallback.
	return


func _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
	_player_combat_enemy_ids.erase(enemy.get_instance_id())
	var queued_at_usec := Time.get_ticks_usec()
	if _combat_spatial_index != null:
		_combat_spatial_index.unregister(
			int(enemy.get_meta("spawn_serial", 0))
		)
	# Clearing references is cheap and must be immediate, but refreshing every
	# enemy highlight and the HUD here would run inside the death signal and can
	# interrupt a multi-target release. Coalesce that presentation work into the
	# deferred death pipeline.
	if enemy == locked_target:
		locked_target = null
		manual_target_lock = false
		_enemy_death_target_refresh_pending = true
	if enemy == magic_locked_target:
		magic_locked_target = null
		manual_magic_target_lock = false
		_enemy_death_target_refresh_pending = true
	if enemy == _skill_cast_target:
		_skill_cast_target = null
		_enemy_death_target_refresh_pending = true
	var monster_id := _strict_runtime_monster_id(monster_data)
	var raw_snapshot: Variant = enemy.get_meta("death_runtime_snapshot", {})
	var death_runtime_snapshot: Dictionary = (
		raw_snapshot as Dictionary if raw_snapshot is Dictionary else {}
	)
	if int(death_runtime_snapshot.get("monster_id", -1)) != monster_id:
		var canonical_monster := GameData.get_monster_by_id(monster_id)
		death_runtime_snapshot = _build_enemy_death_runtime_snapshot(
			canonical_monster
		)
	if death_runtime_snapshot.is_empty():
		_schedule_enemy_death_work()
		return
	# The callback can run after a deferred death animation and even after a
	# map transition.  Runtime map/generation and positions therefore come only
	# from the lethal-time actor snapshot, never from current_map_id or the
	# current zone generation.
	var raw_death_origin: Variant = enemy.get_meta("death_origin", {})
	var death_origin: Dictionary = (
		raw_death_origin.duplicate(true)
		if raw_death_origin is Dictionary
		else {}
	)
	var origin_captured := bool(death_origin.get("captured", false))
	var origin_map_id := int(death_origin.get("map_id", -1))
	var origin_generation := int(death_origin.get("generation", -1))
	if not origin_captured:
		var snapshot_map_id := int(
			death_runtime_snapshot.get("death_runtime_map_id", -1)
		)
		var snapshot_generation := int(
			death_runtime_snapshot.get("death_zone_generation", -1)
		)
		if snapshot_map_id >= 0 or snapshot_generation >= 0:
			origin_map_id = snapshot_map_id
			origin_generation = snapshot_generation
			origin_captured = true
	if not origin_captured:
		var actor_map_id := int(enemy.runtime_map_id)
		var actor_generation := int(enemy.get_meta("zone_generation", -1))
		if actor_map_id >= 0 or actor_generation >= 0:
			origin_map_id = actor_map_id
			origin_generation = actor_generation
			origin_captured = true
	var raw_death_position: Variant = death_origin.get(
		"death_position", enemy.global_position
	)
	var death_position := (
		raw_death_position as Vector2
		if raw_death_position is Vector2
		else enemy.global_position
	)
	var raw_spawn_position: Variant = death_origin.get(
		"spawn_position", enemy.get_meta("spawn_position", death_position)
	)
	var spawn_position := (
		raw_spawn_position as Vector2
		if raw_spawn_position is Vector2
		else death_position
	)
	var raw_spawn_context: Variant = death_origin.get(
		"spawn_context", enemy.get_meta("spawn_context", {})
	)
	var spawn_context: Dictionary = (
		raw_spawn_context.duplicate(true)
		if raw_spawn_context is Dictionary
		else {}
	)
	_enemy_death_sequence += 1
	var sequence := _enemy_death_sequence
	var canonical_snapshot := death_runtime_snapshot.duplicate(true)
	var canonical_monster := {
		"monster_id": monster_id,
		"classification": str(canonical_snapshot.get("classification", "")),
		"spawn_classification": str(
			canonical_snapshot.get("spawn_classification", "")
		),
	}
	_pending_enemy_deaths.append({
		"death_key": "death:%d:%d:%d:%d" % [
			origin_map_id,
			origin_generation,
			sequence,
			enemy.get_instance_id(),
		],
		"sequence": sequence,
		"state": DEATH_STATE_QUEUED,
		"origin": {
			"map_id": origin_map_id,
			"generation": origin_generation,
		},
		"origin_map_id": origin_map_id,
		"origin_generation": origin_generation,
		"origin_captured": origin_captured,
		"queued_at_usec": queued_at_usec,
		"death_position": death_position,
		"spawn_position": spawn_position,
		"monster_snapshot": canonical_snapshot,
		"canonical_monster": canonical_monster,
		"monster_id": monster_id,
		"monster_name": str(canonical_snapshot.get("canonical_name", "")),
		"experience": int(canonical_snapshot.get("experience", 0)),
		"respawn": {
			"enabled": bool(enemy.get_meta("respawn_enabled", true)),
			"configured_seconds": float(
				enemy.get_meta("respawn_seconds", -1.0)
			),
			"was_boss": bool(enemy.get_meta("spawn_is_boss", false)),
			"spawn_context": spawn_context,
		},
		"was_boss": bool(enemy.get_meta("spawn_is_boss", false)),
		"generation": origin_generation,
		"configured_respawn": float(enemy.get_meta("respawn_seconds", -1.0)),
		"respawn_enabled": bool(enemy.get_meta("respawn_enabled", true)),
		"spawn_context": spawn_context,
		"drop_plan": {},
		"transaction_result": {},
		"respawn_preparation": {},
		"retry_count": 0,
		"retry_at_msec": 0,
		"materialization_retry_count": 0,
		"materialized_node_index": 0,
		"materialized_node_count": 0,
		"remaining_requests": [],
		"remaining_request_count": 0,
		"reward_status": "queued",
		"respawn_scheduled": false,
		"last_error": "",
	})
	RuntimeDiagnostics.record_performance_max(
		&"drop_queue_depth_max",
		float(_pending_enemy_deaths.size()),
	)
	_schedule_enemy_death_work()


func _schedule_enemy_death_work() -> void:
	if _enemy_death_flush_queued or _enemy_death_pipeline_running:
		return
	_enemy_death_flush_queued = true
	call_deferred("_flush_enemy_deaths", true)


func _flush_enemy_deaths(spread_across_frames := true) -> void:
	_enemy_death_flush_queued = false
	if spread_across_frames:
		_pump_enemy_death_work_queue()
		return
	# Tests and a few synchronous compatibility callers explicitly request the
	# old completion boundary.  Use the same state machine without yielding.
	var guard := 0
	while not _pending_enemy_deaths.is_empty() and guard < 4096:
		var progressed := _pump_enemy_death_work_queue(true)
		guard += 1
		if not progressed and not _pending_enemy_deaths.is_empty():
			# A future retry deadline is ignored by the synchronous compatibility
			# path; a malformed item is terminally observable rather than silently
			# stranded in the queue.
			var head: Dictionary = _pending_enemy_deaths[0]
			_set_enemy_death_state(head, DEATH_STATE_FAILED)
			head["last_error"] = "death_queue_no_progress"
			RuntimeDiagnostics.increment_performance_counter(
				&"death_queue_failed_count"
			)
			_compact_enemy_death_queue()


func _pump_enemy_death_work_queue(force_synchronous := false) -> bool:
	if _enemy_death_pipeline_running:
		return false
	_enemy_death_pipeline_running = true
	# Already accepted settlement receipts and reference cleanup are necessary.
	# They share accounting, but cannot be rejected by optional-work exhaustion.
	var receipt_token := FrameBudget.begin("death_receipt", true)
	var progressed := _poll_prepared_enemy_death_settlement(force_synchronous)
	if _enemy_death_target_refresh_pending:
		_enemy_death_target_refresh_pending = false
		RuntimeDiagnostics.increment_performance_counter(&"death_target_refresh_count")
		if is_inside_tree():
			_refresh_target_highlights()
			if is_instance_valid(hud):
				_update_target_hud()
		progressed = true
	_compact_enemy_death_queue()
	FrameBudget.end(receipt_token)
	_refresh_death_budget_owner()
	if not _pending_enemy_deaths.is_empty():
		var process_frame := Engine.get_process_frames()
		var optional_allowed := force_synchronous or _death_optional_pump_frame != process_frame
		if optional_allowed:
			var token := FrameBudget.begin(_death_budget_category, force_synchronous)
			if token > 0:
				var optional_progressed := _advance_enemy_death_work_slice(force_synchronous, false)
				progressed = optional_progressed or progressed
				if optional_progressed and not force_synchronous:
					_death_optional_pump_frame = process_frame
				FrameBudget.end(token)
	_enemy_death_pipeline_running = false
	_refresh_death_budget_owner()
	return progressed


func _refresh_death_budget_owner() -> void:
	var runnable := not _pending_enemy_deaths.is_empty()
	if runnable:
		var head: Dictionary = _pending_enemy_deaths[0]
		runnable = str(head.get("state", "")) != DEATH_STATE_PERSISTING
		if str(head.get("state", "")) == DEATH_STATE_RETRY:
			runnable = _death_retry_ready(head)
	FrameBudget.mark_pending(_death_budget_category, not _pending_enemy_deaths.is_empty(), runnable, false, self)


func _advance_enemy_death_work_slice(force_synchronous: bool, progressed: bool) -> bool:
	# Scheduling is production behavior, independent of diagnostic sampling.
	# Diagnostic timers return zero when disabled (the normal gameplay case).
	var slice_started_usec := Time.get_ticks_usec()
	var budget_usec := _death_drop_work_budget_usec()
	if not force_synchronous:
		budget_usec = mini(budget_usec, FrameBudget.remaining_usec())
	var jobs_limit := _death_jobs_max_per_frame()
	var nodes_limit := _drop_nodes_max_per_frame()
	if not force_synchronous and not PlayerState.test_mode:
		# Keep large reward bursts off one render frame, even if a project override is higher.
		nodes_limit = mini(nodes_limit, 1)
	if force_synchronous:
		budget_usec = 2147483647
		jobs_limit = 2147483647
		nodes_limit = 2147483647
	if _pending_enemy_deaths.is_empty():
		return progressed
	var jobs_processed := _death_settled_jobs_last_batch
	var nodes_processed := 0
	var unsettled_index := _first_unsettled_death_index()
	if unsettled_index >= 0 and str(_pending_enemy_deaths[unsettled_index].get("state", "")) == DEATH_STATE_RETRY:
		var retry_item: Dictionary = _pending_enemy_deaths[unsettled_index]
		if force_synchronous or _death_retry_ready(retry_item):
			retry_item["retry_at_msec"] = 0
			_set_enemy_death_state(retry_item, DEATH_STATE_QUEUED)
			progressed = true
	if unsettled_index >= 0 and str(_pending_enemy_deaths[unsettled_index].get("state", "")) == DEATH_STATE_QUEUED:
		if (
			(force_synchronous or _death_retry_ready(_pending_enemy_deaths[unsettled_index]))
			and (
				force_synchronous
				or Time.get_ticks_usec() - slice_started_usec < budget_usec
			)
		):
			# Settlement and display consume one canonical queue independently.
			# Reserve one work slot for an older display so new deaths cannot starve it.
			var display_reserved := 1 if unsettled_index > 0 and not force_synchronous else 0
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed - display_reserved, force_synchronous or PlayerState.test_mode):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
	while not _pending_enemy_deaths.is_empty():
		if (
			not force_synchronous
			and Time.get_ticks_usec() - slice_started_usec >= budget_usec
		):
			break
		var death: Dictionary = _pending_enemy_deaths[0]
		var state := str(death.get("state", ""))
		if state in [DEATH_STATE_FAILED, DEATH_STATE_CANCELLED, DEATH_STATE_COMMITTED]:
			_compact_enemy_death_queue()
			progressed = true
			continue
		if state == DEATH_STATE_RETRY:
			if not force_synchronous and not _death_retry_ready(death):
				break
			death["retry_at_msec"] = 0
			_set_enemy_death_state(death, DEATH_STATE_QUEUED)
			progressed = true
			continue
		if state == DEATH_STATE_QUEUED:
			if not force_synchronous and not _death_retry_ready(death):
				break
			if jobs_processed >= jobs_limit:
				break
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed, force_synchronous or PlayerState.test_mode):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
				continue
			break
		if state == DEATH_STATE_PERSISTING:
			break # A real file receipt is pending; no reward roll or display yet.
		if state == DEATH_STATE_SETTLING:
			if jobs_processed >= jobs_limit:
				break
			jobs_processed += 1
			if _plan_enemy_death_item(death, slice_started_usec, budget_usec):
				progressed = true
				continue
			break
		if state == DEATH_STATE_PLANNED:
			if jobs_processed >= jobs_limit:
				break
			_set_enemy_death_state(death, DEATH_STATE_MATERIALIZING)
			jobs_processed += 1
			progressed = true
		elif state == DEATH_STATE_MATERIALIZING:
			if jobs_processed >= jobs_limit:
				break
			if not force_synchronous and not _death_retry_ready(death):
				break
			jobs_processed += 1
		if (
			not force_synchronous
			and not PlayerState.test_mode
			and int(death.get("remaining_request_count", 0)) > 0
			and Engine.get_process_frames() - _last_drop_node_frame < 2
		):
			break
		var materialization := _materialize_enemy_death_nodes(
			death,
			slice_started_usec,
			budget_usec,
			nodes_limit - nodes_processed,
			force_synchronous,
		)
		nodes_processed += int(materialization.get("nodes", 0))
		if bool(materialization.get("progressed", false)):
			progressed = true
		if bool(materialization.get("complete", false)):
			if str(death.get("state", "")) == DEATH_STATE_MATERIALIZING:
				_commit_enemy_death_item(death)
			elif str(death.get("state", "")) == DEATH_STATE_FAILED:
				# The XP/quest/respawn transaction already committed before node
				# materialization. A terminal node failure must not strand a valid
				# respawn, but it must never retry or duplicate a reward node.
				_schedule_queued_enemy_respawn(death)
			progressed = true
			_compact_enemy_death_queue()
			continue
		break
	if progressed:
		RuntimeDiagnostics.increment_performance_counter(&"death_work_frames")
		RuntimeDiagnostics.increment_performance_counter(&"drop_work_frames")
	RuntimeDiagnostics.record_performance_max(
		&"death_jobs_per_frame_max", float(jobs_processed)
	)
	RuntimeDiagnostics.record_performance_max(
		&"drop_nodes_per_frame_max", float(nodes_processed)
	)
	return progressed


func _death_drop_work_budget_usec() -> int:
	if _death_drop_work_budget_usec_override >= 0:
		return maxi(1, _death_drop_work_budget_usec_override)
	return maxi(
		1,
		int(ProjectSettings.get_setting(
			"hardcore/performance/death_drop_work_budget_usec",
			DEATH_DROP_WORK_BUDGET_USEC,
		)),
	)


func _death_jobs_max_per_frame() -> int:
	if _death_jobs_max_per_frame_override >= 0:
		return maxi(1, _death_jobs_max_per_frame_override)
	return maxi(
		1,
		int(ProjectSettings.get_setting(
			"hardcore/performance/death_jobs_max_per_frame",
			DEATH_JOBS_MAX_PER_FRAME,
		)),
	)


func _drop_nodes_max_per_frame() -> int:
	if _drop_nodes_max_per_frame_override >= 0:
		return maxi(1, _drop_nodes_max_per_frame_override)
	return maxi(
		1,
		int(ProjectSettings.get_setting(
			"hardcore/performance/drop_nodes_max_per_frame",
			DROP_NODES_MAX_PER_FRAME,
		)),
	)


func set_death_drop_work_limits_for_test(
	budget_usec: int,
	jobs_per_frame: int,
	nodes_per_frame: int,
) -> bool:
	if not PlayerState.test_mode:
		return false
	_death_drop_work_budget_usec_override = budget_usec
	_death_jobs_max_per_frame_override = jobs_per_frame
	_drop_nodes_max_per_frame_override = nodes_per_frame
	return true


func clear_death_drop_work_limits_for_test() -> void:
	_death_drop_work_budget_usec_override = -1
	_death_jobs_max_per_frame_override = -1
	_drop_nodes_max_per_frame_override = -1

func set_death_roll_quantum_slicing_for_test(enabled: bool) -> bool:
	if not PlayerState.test_mode:
		return false
	_death_roll_quantum_slicing_enabled = enabled
	return true


func set_loot_materialization_failure_count_for_test(count: int) -> bool:
	if not PlayerState.test_mode:
		return false
	_test_force_loot_materialization_failure_count = maxi(0, count)
	return true


func set_loot_legacy_reference_fallback_for_test(enabled: bool) -> bool:
	if enabled and not PlayerState.test_mode:
		return false
	_loot_legacy_reference_fallback_test_enabled = enabled
	return true


func death_work_queue_snapshot() -> Dictionary:
	var oldest_age_usec := 0
	var maximum_completion_latency_usec := 0
	for death: Dictionary in _pending_enemy_deaths:
		oldest_age_usec = maxi(oldest_age_usec, Time.get_ticks_usec() - int(death.get("queued_at_usec", Time.get_ticks_usec())))
	for death: Dictionary in _enemy_death_terminal_jobs:
		maximum_completion_latency_usec = maxi(maximum_completion_latency_usec,
			int(death.get("completion_latency_usec", 0)))
	return {
		"oldest_age_usec": oldest_age_usec,
		"maximum_completion_latency_usec": maximum_completion_latency_usec,
		"pending": _pending_enemy_deaths.duplicate(true),
		"terminal": _enemy_death_terminal_jobs.duplicate(true),
		"terminal_count": _enemy_death_terminal_total_count,
		"terminal_ledger_limit": DEATH_TERMINAL_LEDGER_MAX,
	}


func _death_retry_ready(death: Dictionary) -> bool:
	return Time.get_ticks_msec() >= int(death.get("retry_at_msec", 0))


func _set_enemy_death_state(death: Dictionary, next_state: String) -> void:
	var previous := str(death.get("state", ""))
	if previous == next_state:
		return
	death["state"] = next_state
	RuntimeDiagnostics.increment_performance_counter(
		&"death_queue_state_transitions"
	)


func _compact_enemy_death_queue() -> void:
	if _pending_enemy_deaths.is_empty():
		return
	var retained: Array[Dictionary] = []
	for death: Dictionary in _pending_enemy_deaths:
		var state := str(death.get("state", ""))
		if state in [DEATH_STATE_FAILED, DEATH_STATE_CANCELLED, DEATH_STATE_COMMITTED]:
			death["completion_latency_usec"] = maxi(0,
				Time.get_ticks_usec() - int(death.get("queued_at_usec", Time.get_ticks_usec())))
			if state == DEATH_STATE_FAILED and _last_death_logout_failure.is_empty():
				_last_death_logout_failure = {
					"success": false,
					"save_performed": false,
					"reason": "safe_logout_death_queue_failed",
					"death_key": str(death.get("death_key", "")),
					"death_error": str(death.get("last_error", "")),
				}
			_enemy_death_terminal_total_count += 1
			if _enemy_death_terminal_jobs.size() >= DEATH_TERMINAL_LEDGER_MAX:
				_enemy_death_terminal_jobs.pop_front()
			_enemy_death_terminal_jobs.append(death.duplicate(true))
		else:
			retained.append(death)
	_pending_enemy_deaths = retained


func _death_origin_matches_current(death: Dictionary) -> bool:
	return (
		bool(death.get("origin_captured", false))
		and
		int(death.get("origin_map_id", -1)) == current_map_id
		and int(death.get("origin_generation", -1)) == _zone_generation
	)


func _cancel_pending_enemy_deaths_for_generation_change() -> void:
	if not _prepared_enemy_death_settlement.is_empty():
		_prepared_enemy_death_settlement.plan.writer.cancel()
		_poll_prepared_enemy_death_settlement(true)
	if _pending_enemy_deaths.is_empty():
		return
	for death: Dictionary in _pending_enemy_deaths:
		if (
			bool(death.get("origin_captured", false))
			and int(death.get("origin_generation", -1)) == _zone_generation
			and int(death.get("origin_map_id", -1)) == current_map_id
		):
			continue
		death["last_error"] = "origin_map_generation_changed_before_settlement"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
	_compact_enemy_death_queue()



func _first_unsettled_death_index() -> int:
	for index: int in range(_pending_enemy_deaths.size()):
		if str(_pending_enemy_deaths[index].get("state", "")) in [DEATH_STATE_QUEUED, DEATH_STATE_RETRY, DEATH_STATE_PERSISTING]:
			return index
	return -1


func _death_settlement_origins_valid(batch: Array[Dictionary]) -> bool:
	for death: Dictionary in batch:
		if not _death_origin_matches_current(death):
			return false
	return true


func _poll_prepared_enemy_death_settlement(wait := false) -> bool:
	_death_settled_jobs_last_batch = 0
	if _prepared_enemy_death_settlement.is_empty():
		return false
	var cohort := _prepared_enemy_death_settlement
	var settlement := PlayerState.finish_prepared_death_settlement(cohort.plan, wait)
	if bool(settlement.get("pending", false)):
		return false
	_prepared_enemy_death_settlement = {}
	_death_settled_jobs_last_batch = (cohort.batch as Array).size()
	var started_usec := RuntimeDiagnostics.timing_start()
	_finish_enemy_death_settlement_batch(cohort.batch, settlement)
	RuntimeDiagnostics.record_timing_usec(&"death_settlement_usec", started_usec)
	return true


func _settle_pending_enemy_death_batch(
	max_deaths := DEATH_JOBS_MAX_PER_FRAME,
	force_synchronous := true,
) -> bool:
	_death_settled_jobs_last_batch = 0
	if not _prepared_enemy_death_settlement.is_empty():
		return false
	if _pending_enemy_deaths.is_empty():
		return false
	if max_deaths <= 0:
		return false
	var unsettled_index := _first_unsettled_death_index()
	if unsettled_index < 0:
		return false
	var first: Dictionary = _pending_enemy_deaths[unsettled_index]
	if str(first.get("state", "")) != DEATH_STATE_QUEUED:
		return false
	if not _death_retry_ready(first):
		return false
	# Reject stale/unidentified deaths before touching PlayerState.  This guard
	# is intentionally before the batched save so an old actor can never grant
	# XP, quest progress, respawn state, or a drop after a map transition.
	if not _death_origin_matches_current(first):
		first["last_error"] = (
			"origin_map_generation_mismatch_before_settlement"
			if bool(first.get("origin_captured", false))
			else "death_origin_missing"
		)
		_set_enemy_death_state(first, DEATH_STATE_CANCELLED)
		_death_settled_jobs_last_batch = 1
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return true
	var batch: Array[Dictionary] = []
	for death_index: int in range(unsettled_index, _pending_enemy_deaths.size()):
		var death: Dictionary = _pending_enemy_deaths[death_index]
		if batch.size() >= max_deaths:
			break
		if str(death.get("state", "")) != DEATH_STATE_QUEUED:
			break
		if not _death_retry_ready(death):
			break
		if not _death_origin_matches_current(death):
			break
		_set_enemy_death_state(death, DEATH_STATE_SETTLING)
		batch.append(death)
	if batch.is_empty():
		return false
	_death_settled_jobs_last_batch = batch.size()
	RuntimeDiagnostics.increment_performance_counter(&"death_batch_count")
	RuntimeDiagnostics.record_performance_max(
		&"death_batch_size_max", float(batch.size())
	)
	var oldest_queued_usec := int(batch[0].get("queued_at_usec", 0))
	RuntimeDiagnostics.record_performance_max(
		&"drop_queue_oldest_age_ms",
		float(RuntimeDiagnostics.timing_elapsed_usec(oldest_queued_usec)) / 1000.0,
	)
	var settlements: Array = []
	var respawn_state_before: Dictionary = (
		PlayerState.world_clock_mutation_snapshot() if force_synchronous else {}
	)
	var world_upserts: Dictionary = {}
	for death: Dictionary in batch:
		var respawn_preparation := _prepare_queued_enemy_respawn(death, force_synchronous)
		if respawn_preparation.has("world_entry"):
			world_upserts[str(respawn_preparation.world_key)] = respawn_preparation.world_entry
		death["respawn_preparation"] = respawn_preparation
		var respawn: Dictionary = death.get("respawn", {})
		respawn["preparation"] = respawn_preparation
		death["respawn"] = respawn
		settlements.append({
			"monster_name": str(death.get("monster_name", "")),
			"experience": int(death.get("experience", 0)),
		})
	var settlement_started_usec := RuntimeDiagnostics.timing_start()
	if not force_synchronous:
		var plan := PlayerState.prepare_death_settlement(settlements, world_upserts, _death_settlement_origins_valid.bind(batch))
		if bool(plan.get("pending", false)) and not plan.has("writer"):
			for death: Dictionary in batch:
				_set_enemy_death_state(death, DEATH_STATE_QUEUED)
			_death_settled_jobs_last_batch = 0
			return false
		if plan.has("immediate"):
			_finish_enemy_death_settlement_batch(batch, plan.immediate)
			return true
		for death: Dictionary in batch:
			_set_enemy_death_state(death, DEATH_STATE_PERSISTING)
		_prepared_enemy_death_settlement = {"batch": batch, "plan": plan}
		RuntimeDiagnostics.record_timing_usec(&"death_prepare_usec", settlement_started_usec)
		return true
	var settlement := PlayerState.record_kills_and_experience_batch(
		settlements,
		true,
	)
	RuntimeDiagnostics.record_timing_usec(
		&"death_settlement_usec", settlement_started_usec
	)
	_finish_enemy_death_settlement_batch(batch, settlement, respawn_state_before)
	return true


func _finish_enemy_death_settlement_batch(batch: Array[Dictionary], settlement: Dictionary, respawn_state_before: Dictionary = {}) -> void:
	if bool(settlement.get("success", false)) and not bool(settlement.get("active_state_applied", true)):
		for death: Dictionary in batch:
			death["transaction_result"] = settlement.duplicate(true)
			death["last_error"] = "settlement_saved_for_inactive_role"
			_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		_compact_enemy_death_queue()
		return
	if not bool(settlement.get("success", false)):
		# Respawn state, quest progress and experience are one save boundary. A
		# failed save restores the pre-attempt state, and the death item remains
		# observable for retry/terminal handling; no drop roll is performed.
		if not respawn_state_before.is_empty():
			PlayerState.restore_world_clock_mutation(respawn_state_before)
		for death: Dictionary in batch:
			death["transaction_result"] = settlement.duplicate(true)
			death["last_error"] = str(settlement.get("reason", "save_failed"))
			death["retry_count"] = int(death.get("retry_count", 0)) + 1
			if int(death["retry_count"]) >= DEATH_QUEUE_MAX_RETRIES:
				_set_enemy_death_state(death, DEATH_STATE_FAILED)
				RuntimeDiagnostics.increment_performance_counter(
					&"death_queue_failed_count"
				)
			else:
				death["retry_at_msec"] = (
					Time.get_ticks_msec() + DEATH_QUEUE_RETRY_DELAY_MSEC
				)
				_set_enemy_death_state(death, DEATH_STATE_RETRY)
				RuntimeDiagnostics.increment_performance_counter(
					&"death_queue_retry_count"
				)
		_compact_enemy_death_queue()
		return
	for death: Dictionary in batch:
		death["transaction_result"] = settlement.duplicate(true)
		# The durable receipt closes PERSISTING. Resume reward planning through
		# the same stage used by synchronous settlement, without settling twice.
		_set_enemy_death_state(death, DEATH_STATE_SETTLING)
	return


var _drop_instance_session_key := Crypto.new().generate_random_bytes(16).hex_encode()


func _plan_enemy_death_item(death: Dictionary, slice_started_usec := 0, budget_usec := 0) -> bool:
	if not _death_origin_matches_current(death):
		death["last_error"] = "origin_map_generation_mismatch_before_roll"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return true
	var started_usec := RuntimeDiagnostics.timing_start()
	var monster_id := int(death.get("monster_id", -1))
	var drop_roll: Dictionary
	if _death_roll_quantum_slicing_enabled:
		var resumable: Dictionary = death.get("drop_roll_job", {})
		if resumable.is_empty():
			RuntimeDiagnostics.increment_performance_counter(&"drop_roll_count")
			resumable = LootRuntime.begin_monster_drop_roll_job(monster_id, _rng, false)
		var advanced := LootRuntime.advance_monster_drop_roll_job(resumable, 1)
		# A source row is a small resumable quantum, not a whole death job.
		# Use the admitted slice's existing wall budget for further quanta;
		# retain the cursor as soon as that budget is spent. RNG order is unchanged.
		while (
			not bool(advanced.get("done", false))
			and budget_usec > 0
			and Time.get_ticks_usec() - slice_started_usec < budget_usec
		):
			advanced = LootRuntime.advance_monster_drop_roll_job(advanced, 1)
		if not bool(advanced.get("done", false)):
			death["drop_roll_job"] = advanced
			RuntimeDiagnostics.increment_performance_counter(&"drop_roll_slice_count")
			RuntimeDiagnostics.record_timing_usec(&"drop_roll_usec", started_usec)
			return true
		drop_roll = advanced.get("result", {})
		death.erase("drop_roll_job")
	else:
		RuntimeDiagnostics.increment_performance_counter(&"drop_roll_count")
		drop_roll = LootRuntime.roll_monster_drops(monster_id, _rng, false)
	var death_position: Vector2 = death.get("death_position", Vector2.ZERO)
	var requests: Array[Dictionary] = []
	var raw_items: Variant = drop_roll.get("items", [])
	var identity_records: Array = drop_roll.get("item_records", [])
	if raw_items is Array:
		for item_index in range(raw_items.size()):
			var item_name := str(raw_items[item_index])
			var identity_record: Dictionary = (
				identity_records[item_index]
				if item_index < identity_records.size() and identity_records[item_index] is Dictionary
				else {}
			)
			identity_record = PlayerState.create_drop_item_instance(
				identity_record,
				"%s:%s:item:%d" % [_drop_instance_session_key, str(death.get("death_key", "")), item_index],
			)
			requests.append({
				"item_name": item_name,
				"item_record": identity_record,
				"position": death_position + Vector2(
					_rng.randf_range(-34, 34),
					_rng.randf_range(-18, 18)
				),
			})
	var raw_gold_drops: Variant = drop_roll.get("gold_drops", [])
	if raw_gold_drops is Array:
		for raw_gold: Variant in raw_gold_drops:
			var amount := int(raw_gold)
			if amount > 0:
				requests.append({
					"gold_amount": amount,
					"position": death_position + Vector2(
						_rng.randf_range(-34, 34),
						_rng.randf_range(-18, 18)
					),
				})
	var overflow_discarded_count := int(
		drop_roll.get("overflow_discarded_count", 0)
	)
	if overflow_discarded_count > 0:
		var overflow_telemetry := LootRuntime.record_overflow_telemetry(
			monster_id,
			drop_roll
		)
		if (
			not overflow_telemetry.is_empty()
			and CombatDiagnosticLogScript.capture_enabled()
		):
			CombatDiagnosticLogScript.record({
				"event": "loot_overflow_discarded",
				"monster_id": int(overflow_telemetry.get("monster_id", monster_id)),
				"successful_roll_count": int(
					overflow_telemetry.get("successful_roll_count", 0)
				),
				"ground_output_count": int(
					overflow_telemetry.get("ground_output_count", 0)
				),
				"overflow_discarded_count": int(
					overflow_telemetry.get("overflow_discarded_count", 0)
				),
				"protected_overflow_count": int(
					overflow_telemetry.get("protected_overflow_count", 0)
				),
			})
	death["drop_plan"] = {
		"roll": drop_roll.duplicate(true),
		"requests": requests,
		"next_request_index": 0,
		"item_count": raw_items.size() if raw_items is Array else 0,
		"gold_drop_count": raw_gold_drops.size() if raw_gold_drops is Array else 0,
		"materialized": false,
	}
	death["remaining_requests"] = requests.duplicate(true)
	death["remaining_request_count"] = requests.size()
	death["reward_status"] = "planned"
	death["materialized_node_index"] = 0
	death["materialized_node_count"] = 0
	death["materialization_retry_count"] = 0
	_set_enemy_death_state(death, DEATH_STATE_PLANNED)
	RuntimeDiagnostics.increment_performance_counter(
		&"drop_request_count", requests.size()
	)
	RuntimeDiagnostics.record_timing_usec(&"drop_roll_usec", started_usec)
	return true


func _materialize_enemy_death_nodes(
	death: Dictionary,
	slice_started_usec: int,
	budget_usec: int,
	node_budget: int,
	force_synchronous: bool,
) -> Dictionary:
	var raw_plan: Variant = death.get("drop_plan", {})
	if not raw_plan is Dictionary:
		death["last_error"] = "drop_plan_invalid"
		death["remaining_requests"] = []
		death["remaining_request_count"] = 0
		death["reward_status"] = "materialization_failed"
		_set_enemy_death_state(death, DEATH_STATE_FAILED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_materialization_failures"
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_failed_count"
		)
		return {"complete": true, "progressed": true, "nodes": 0}
	var plan: Dictionary = raw_plan
	var raw_requests: Variant = plan.get("requests", [])
	if not raw_requests is Array:
		death["last_error"] = "drop_plan_requests_invalid"
		death["remaining_requests"] = []
		death["remaining_request_count"] = 0
		death["reward_status"] = "materialization_failed"
		_set_enemy_death_state(death, DEATH_STATE_FAILED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_materialization_failures"
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_failed_count"
		)
		return {"complete": true, "progressed": true, "nodes": 0}
	if not _death_origin_matches_current(death):
		death["last_error"] = "origin_map_generation_mismatch_after_roll"
		death["remaining_requests"] = raw_requests.duplicate(true)
		death["remaining_request_count"] = raw_requests.size()
		death["reward_status"] = "cancelled_after_roll"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return {"complete": true, "progressed": true, "nodes": 0}
	var requests: Array = raw_requests
	var request_index := int(death.get("materialized_node_index", 0))
	var nodes := 0
	var progressed := false
	while request_index < requests.size():
		if node_budget <= nodes:
			break
		if (
			not force_synchronous
			and progressed
			and Time.get_ticks_usec() - slice_started_usec >= budget_usec
		):
			break
		if not _death_origin_matches_current(death):
			death["last_error"] = "origin_map_generation_mismatch_after_roll"
			death["remaining_requests"] = requests.slice(request_index)
			death["remaining_request_count"] = requests.size() - request_index
			death["reward_status"] = "cancelled_after_roll"
			_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
			RuntimeDiagnostics.increment_performance_counter(
				&"death_queue_cancelled_count"
			)
			return {"complete": true, "progressed": true, "nodes": nodes}
		var request_value: Variant = requests[request_index]
		if not request_value is Dictionary:
			death["last_error"] = "drop_request_invalid"
			death["remaining_requests"] = requests.slice(request_index)
			death["remaining_request_count"] = requests.size() - request_index
			death["reward_status"] = "materialization_failed"
			_set_enemy_death_state(death, DEATH_STATE_FAILED)
			RuntimeDiagnostics.increment_performance_counter(
				&"death_queue_materialization_failures"
			)
			RuntimeDiagnostics.increment_performance_counter(
				&"death_queue_failed_count"
			)
			return {"complete": true, "progressed": true, "nodes": nodes}
		var request: Dictionary = request_value
		var placement_search: Dictionary = death.get("placement_search", {})
		if int(placement_search.get("request_index", request_index)) != request_index:
			placement_search = {}
		placement_search["request_index"] = request_index
		var placement := _advance_loot_ground_position(
			request.get("position", death.get("death_position", Vector2.ZERO)),
			death.get("death_position", Vector2.INF),
			placement_search,
			slice_started_usec,
			budget_usec,
			force_synchronous or PlayerState.test_mode,
		)
		if not bool(placement.get("complete", false)):
			death["placement_search"] = placement_search
			return {"complete": false, "progressed": true, "nodes": nodes}
		death.erase("placement_search")
		var resolved_position: Vector2 = placement.get("position", Vector2.INF)
		var materialized := false
		if not resolved_position.is_finite():
			materialized = false
		elif request.has("gold_amount"):
			materialized = _spawn_gold_loot(
				int(request.get("gold_amount", 0)),
				resolved_position,
				death.get("death_position", Vector2.INF),
				true,
			)
		else:
			materialized = _spawn_loot(
				str(request.get("item_name", "")),
				resolved_position,
				request.get("item_record", {}),
				death.get("death_position", Vector2.INF),
				true,
			)
		if not materialized:
			death["remaining_requests"] = requests.slice(request_index)
			death["remaining_request_count"] = requests.size() - request_index
			death["reward_status"] = "materialization_retry"
			death["materialization_retry_count"] = (
				int(death.get("materialization_retry_count", 0)) + 1
			)
			death["last_error"] = "loot_node_materialization_failed"
			RuntimeDiagnostics.increment_performance_counter(
				&"death_queue_materialization_failures"
			)
			if int(death["materialization_retry_count"]) >= DEATH_QUEUE_MAX_RETRIES:
				death["reward_status"] = "materialization_failed"
				_set_enemy_death_state(death, DEATH_STATE_FAILED)
				RuntimeDiagnostics.increment_performance_counter(
					&"death_queue_failed_count"
				)
				return {"complete": true, "progressed": true, "nodes": nodes}
			death["retry_at_msec"] = (
				Time.get_ticks_msec() + DEATH_QUEUE_RETRY_DELAY_MSEC
			)
			return {"complete": false, "progressed": true, "nodes": nodes}
		request_index += 1
		nodes += 1
		if not force_synchronous and not PlayerState.test_mode:
			_last_drop_node_frame = Engine.get_process_frames()
		progressed = true
		death["materialized_node_index"] = request_index
		death["materialized_node_count"] = (
			int(death.get("materialized_node_count", 0)) + 1
		)
		death["retry_at_msec"] = 0
	plan["next_request_index"] = request_index
	if request_index >= requests.size():
		plan["materialized"] = true
		death["remaining_requests"] = []
		death["remaining_request_count"] = 0
		death["reward_status"] = "materialized"
		death["drop_plan"] = plan
		return {"complete": true, "progressed": progressed, "nodes": nodes}
	return {"complete": false, "progressed": progressed, "nodes": nodes}


func _commit_enemy_death_item(death: Dictionary) -> void:
	_schedule_queued_enemy_respawn(death)
	death["reward_status"] = "committed"
	_set_enemy_death_state(death, DEATH_STATE_COMMITTED)
	RuntimeDiagnostics.increment_performance_counter(
		&"death_queue_committed_count"
	)
	# AOE window probe: first committed death closes the first-engagement
	# window. Diagnostics only.
	AoeEngagementWindow.on_enemy_death_committed()


func _schedule_queued_enemy_respawn(death: Dictionary) -> void:
	if bool(death.get("respawn_scheduled", false)):
		return
	var preparation: Dictionary = death.get("respawn_preparation", {})
	if preparation.is_empty() or not bool(preparation.get("valid", false)):
		return
	if not bool(preparation.get("enabled", false)):
		return
	var canonical_monster: Dictionary = death.get("canonical_monster", {})
	var respawn: Dictionary = death.get("respawn", {})
	var spawn_context: Dictionary = preparation.get(
		"spawn_context", respawn.get("spawn_context", {})
	)
	var world_entry: Dictionary = preparation.get("world_entry", {})
	var remaining_seconds := maxf(
		0.0,
		float(world_entry.get("respawn_at_unix", 0.0)) - Time.get_unix_time_from_system()
	)
	_respawn_later(
		canonical_monster,
		death.get("spawn_position", death.get("death_position", Vector2.ZERO)),
		bool(respawn.get("was_boss", death.get("was_boss", false))),
		remaining_seconds,
		int(death.get("origin_generation", _zone_generation)),
		spawn_context,
	)
	death["respawn_scheduled"] = true


func _resolve_queued_enemy_death(
	death: Dictionary,
	_spread_across_frames := false,
) -> Dictionary:
	# Compatibility helper retained for focused tests/tools.  Production uses
	# _pump_enemy_death_work_queue so scheduling and state transitions remain
	# observable and budgeted.
	var started_usec := RuntimeDiagnostics.timing_start()
	if not death.has("origin_map_id"):
		# Compatibility callers must provide a frozen origin explicitly.  Never
		# manufacture one from the current world here, since this helper may be
		# invoked after a delayed death signal.
		death["origin_map_id"] = -1
		death["origin_generation"] = -1
		death["origin_captured"] = false
	if str(death.get("state", "")) == "":
		death["state"] = DEATH_STATE_SETTLING
	var raw_plan: Variant = death.get("drop_plan", {})
	if not raw_plan is Dictionary or (raw_plan as Dictionary).is_empty():
		_plan_enemy_death_item(death)
	if str(death.get("state", "")) == DEATH_STATE_PLANNED:
		_set_enemy_death_state(death, DEATH_STATE_MATERIALIZING)
	var result := _materialize_enemy_death_nodes(
		death,
		RuntimeDiagnostics.timing_start(),
		2147483647,
		2147483647,
		true,
	)
	if bool(result.get("complete", false)) and str(death.get("state", "")) == DEATH_STATE_MATERIALIZING:
		_commit_enemy_death_item(death)
	return {
		"monster_id": int(death.get("monster_id", -1)),
		"item_count": int((death.get("drop_plan", {}) as Dictionary).get("item_count", 0)),
		"gold_drop_count": int((death.get("drop_plan", {}) as Dictionary).get("gold_drop_count", 0)),
		"respawn_scheduled": bool(death.get("respawn_scheduled", false)),
		"state": str(death.get("state", "")),
		"reason": str(death.get("last_error", "")),
		"total_ms": float(RuntimeDiagnostics.timing_elapsed_usec(started_usec)) / 1000.0,
	}


func _prepare_queued_enemy_respawn(death: Dictionary, apply_world := true) -> Dictionary:
	if not bool(death.get("respawn_enabled", true)):
		return {"valid": true, "enabled": false}
	var monster_id := int(death.get("monster_id", -1))
	var canonical_monster: Dictionary = death.get("canonical_monster", {})
	var spawn_context: Dictionary = (
		(death.get("spawn_context", {}) as Dictionary).duplicate(true)
	)
	var spawn_classification := str(
		canonical_monster.get("spawn_classification", "")
	)
	var policy := MonsterRespawnPolicyScript.resolve(
		str(spawn_context.get("respawn_policy_id", "")),
		str(canonical_monster.get("classification", "")),
		float(death.get("configured_respawn", -1.0)),
		spawn_classification
	)
	if not bool(policy.get("valid", false)):
		push_error(
			"Monster death respawn policy rejected monster_id=%d reason=%s"
			% [monster_id, str(policy.get("reason", "invalid_policy"))]
		)
		return {"valid": false, "reason": "invalid_respawn_policy"}
	var respawn_wait_seconds := float(policy.get("seconds", 0.0))
	var respawn_runtime_map_id := int(
		spawn_context.get("respawn_runtime_map_id", current_map_id)
	)
	var spawn_slot_id := str(spawn_context.get("spawn_slot_id", ""))
	var world_entry := {"runtime_map_id": respawn_runtime_map_id, "spawn_slot_id": spawn_slot_id.strip_edges(),
		"monster_id": monster_id, "policy_id": str(policy.get("policy_id", "")),
		"respawn_at_unix": Time.get_unix_time_from_system() + respawn_wait_seconds}
	var world_key := "%d|%s" % [respawn_runtime_map_id, spawn_slot_id.strip_edges()]
	var respawn_marked := (
		PlayerState.mark_monster_respawn_dead(respawn_runtime_map_id, spawn_slot_id, monster_id,
			str(policy.get("policy_id", "")), float(world_entry.respawn_at_unix))
		if apply_world else WorldClockDeltaScript.valid_world_entry(world_key, world_entry)
	)
	if not respawn_marked:
		push_error(
			"Monster respawn state rejected unstable slot monster_id=%d map_id=%d slot=%s"
			% [monster_id, respawn_runtime_map_id, spawn_slot_id]
		)
		return {"valid": false, "reason": "unstable_respawn_slot"}
	if apply_world:
		RuntimeDiagnostics.increment_performance_counter(&"respawn_state_updates")
	spawn_context["respawn_policy_id"] = str(policy.get("policy_id", ""))
	spawn_context["spawn_classification"] = spawn_classification
	spawn_context["respawn_base_seconds"] = respawn_wait_seconds
	spawn_context["respawn_random_seconds"] = 0.0
	return {
		"valid": true,
		"enabled": true,
		"wait_seconds": respawn_wait_seconds,
		"spawn_context": spawn_context,
		"world_key": world_key,
		"world_entry": world_entry,
	}


func _loot_world_segment_clear(
	origin_px: Vector2,
	target_px: Vector2,
	reusable_query: PhysicsRayQueryParameters2D = null,
) -> bool:
	if not origin_px.is_finite() or not target_px.is_finite() or not is_instance_valid(background):
		return false
	var origin_gu := _canonical_screen_px_to_ground_gu(origin_px)
	var target_gu := _canonical_screen_px_to_ground_gu(target_px)
	if background.is_environment_segment_blocked_ground(origin_gu, target_gu, 0.125):
		return false
	var space := get_world_2d().direct_space_state
	if space == null:
		return false
	var query := reusable_query
	if query == null:
		query = PhysicsRayQueryParameters2D.create(origin_px, target_px, WorldSpatialRulesScript.WORLD_MASK)
	else:
		query.from = origin_px
		query.to = target_px
	query.hit_from_inside = true
	return space.intersect_ray(query).is_empty()


func _loot_ground_point_clear(
	position_px: Vector2,
	reusable_query: PhysicsShapeQueryParameters2D = null,
) -> bool:
	if not position_px.is_finite() or not is_instance_valid(background):
		return false
	if background.is_environment_actor_blocked(position_px, 6.0):
		return false
	var query := reusable_query
	if query == null:
		var shape := CircleShape2D.new()
		shape.radius = 5.0
		query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
	query.transform = Transform2D(0.0, position_px)
	query.collision_mask = WorldSpatialRulesScript.WORLD_MASK
	return get_world_2d().direct_space_state.intersect_shape(query, 1).is_empty()


func _resolve_loot_ground_position(desired_px: Vector2, death_origin := Vector2.INF) -> Vector2:
	var search: Dictionary = {}
	var result := _advance_loot_ground_position(
		desired_px, death_origin, search, 0, 0, true
	)
	return result.get("position", Vector2.INF)


func _advance_loot_ground_position(
	desired_px: Vector2,
	death_origin: Vector2,
	search: Dictionary,
	slice_started_usec: int,
	budget_usec: int,
	force_synchronous: bool,
) -> Dictionary:
	var anchor: Vector2 = death_origin if death_origin.is_finite() else desired_px
	var anchor_gu := _canonical_screen_px_to_ground_gu(anchor)
	var reusable_point_query := search.get("point_query") as PhysicsShapeQueryParameters2D
	if reusable_point_query == null:
		var shape := CircleShape2D.new()
		shape.radius = 5.0
		reusable_point_query = PhysicsShapeQueryParameters2D.new()
		reusable_point_query.shape = shape
		search["point_query"] = reusable_point_query
	var reusable_segment_query := search.get("segment_query") as PhysicsRayQueryParameters2D
	if reusable_segment_query == null:
		reusable_segment_query = PhysicsRayQueryParameters2D.create(
			anchor, anchor, WorldSpatialRulesScript.WORLD_MASK
		)
		search["segment_query"] = reusable_segment_query
	var candidate_index := int(search.get("candidate_index", -1))
	var checked := 0
	# Resume the original deterministic candidate order without repeating prior physics queries.
	var fallback_count := 1 + (LOOT_FALLBACK_RADII.size() - 1) * 8
	while candidate_index < fallback_count:
		if (
			not force_synchronous
			and checked > 0
			and Time.get_ticks_usec() - slice_started_usec >= budget_usec
		):
			search["candidate_index"] = candidate_index
			return {"complete": false, "progressed": true}
		var candidate := desired_px
		if candidate_index >= 0:
			var radius_index := 0 if candidate_index == 0 else 1 + int((candidate_index - 1) / 8)
			var direction := 0 if candidate_index == 0 else (candidate_index - 1) % 8
			candidate = _canonical_ground_gu_to_screen_px(
				anchor_gu + Vector2.from_angle(direction * TAU / 8.0) * LOOT_FALLBACK_RADII[radius_index]
			)
		if _loot_ground_point_clear(candidate, reusable_point_query) and _loot_world_segment_clear(anchor, candidate, reusable_segment_query):
			search.clear()
			return {"complete": true, "position": candidate, "progressed": true}
		candidate_index += 1
		checked += 1
	search.clear()
	return {"complete": true, "position": Vector2.INF, "progressed": checked > 0}


func _loot_collection_path_is_clear(pickup: LootPickup) -> bool:
	if not is_instance_valid(pickup) or not is_instance_valid(player) or not gameplay_input_is_enabled():
		return false
	if pickup.filtered or pickup.is_queued_for_deletion():
		return false
	var origin_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var target_gu := _canonical_screen_px_to_ground_gu(pickup.global_position)
	if origin_gu.distance_to(target_gu) >= LootPickupRuntimeManagerScript.COLLECTION_RADIUS_GU:
		return false
	return _loot_world_segment_clear(player.global_position, pickup.global_position)


func _spawn_loot(item_name: String, position: Vector2, item_record: Dictionary = {}, death_origin := Vector2.INF, placement_resolved := false) -> bool:
	# A formal but unresolved identity must never become an unrelated valid
	# name-only item at collection time. Legacy callers still pass no record.
	if not item_record.is_empty() and str(item_record.get("identity_status", "")) != "resolved":
		return false
	if _test_force_loot_materialization_failure_count > 0:
		_test_force_loot_materialization_failure_count -= 1
		return false
	if not placement_resolved:
		position = _resolve_loot_ground_position(position, death_origin)
	if not position.is_finite():
		return false
	var loot := LootPickup.new()
	if item_record.is_empty():
		loot.setup(item_name, player)
	else:
		loot.setup_item_record(item_record, player)
	loot.global_position = position
	loot.add_to_group("zone_content")
	loot.collected.connect(_on_loot_collected)
	loot.collection_rejected.connect(_on_loot_collection_rejected)
	var spawn_started_usec := RuntimeDiagnostics.timing_start()
	add_child(loot)
	var registered := (
		_loot_pickup_runtime_manager != null
		and _loot_pickup_runtime_manager.register_pickup(loot)
	)
	if not registered:
		# A formal loot node without a map-scoped registration is not collectible;
		# remove it synchronously so materialization cannot leave dead ground loot.
		loot.free()
		return false
	RuntimeDiagnostics.increment_performance_counter(&"drop_node_spawn_count")
	RuntimeDiagnostics.record_timing_usec(&"drop_node_spawn_usec", spawn_started_usec)
	return is_instance_valid(loot)


func _spawn_gold_loot(amount: int, position: Vector2, death_origin := Vector2.INF, placement_resolved := false) -> bool:
	if _test_force_loot_materialization_failure_count > 0:
		_test_force_loot_materialization_failure_count -= 1
		return false
	if not placement_resolved:
		position = _resolve_loot_ground_position(position, death_origin)
	if not position.is_finite():
		return false
	var loot := LootPickup.new()
	loot.setup_gold(amount, player)
	loot.global_position = position
	loot.add_to_group("zone_content")
	loot.gold_collected.connect(_on_gold_loot_collected)
	loot.collection_rejected.connect(_on_loot_collection_rejected)
	var spawn_started_usec := RuntimeDiagnostics.timing_start()
	add_child(loot)
	var registered := (
		_loot_pickup_runtime_manager != null
		and _loot_pickup_runtime_manager.register_pickup(loot)
	)
	if not registered:
		loot.free()
		return false
	RuntimeDiagnostics.increment_performance_counter(&"drop_node_spawn_count")
	RuntimeDiagnostics.record_timing_usec(&"drop_node_spawn_usec", spawn_started_usec)
	return is_instance_valid(loot)


func _on_gold_loot_collected(amount: int, pickup: LootPickup) -> void:
	_queue_loot_collection({"gold": true, "amount": amount, "pickup": pickup})


func _on_loot_collected(item_name: String, pickup: LootPickup) -> void:
	var candidate := {"item_name": item_name, "pickup": pickup}
	if is_instance_valid(pickup) and pickup.item_id >= 0:
		candidate["item_id"] = pickup.item_id
		if pickup.item_record.has("item_instance"):
			var instance_value: Variant = pickup.item_record["item_instance"]
			candidate["item_instance"] = (
				instance_value.duplicate(true)
				if instance_value is Dictionary or instance_value is Array
				else instance_value
			)
	_queue_loot_collection(candidate)


func _queue_loot_collection(candidate: Dictionary) -> bool:
	var queued_candidate := candidate.duplicate(true)
	var pickup: Variant = queued_candidate.get("pickup")
	if not pickup is LootPickup or not is_instance_valid(pickup):
		_loot_collection_origin_rejection_count += 1
		RuntimeDiagnostics.increment_performance_counter(
			&"loot_collection_origin_rejections"
		)
		return false
	var pickup_object := pickup as LootPickup
	var raw_map_id: Variant = null
	var raw_generation: Variant = null
	if pickup_object.has_meta("loot_runtime_map_id"):
		raw_map_id = pickup_object.get_meta("loot_runtime_map_id")
	if pickup_object.has_meta("loot_zone_generation"):
		raw_generation = pickup_object.get_meta("loot_zone_generation")
	var formal_origin_valid := (
			raw_map_id is int
			and raw_generation is int
			and int(raw_map_id) >= 0
			and int(raw_generation) >= 0
		)
	if not formal_origin_valid:
		if not (PlayerState.test_mode and _loot_legacy_reference_fallback_test_enabled):
			_loot_collection_origin_rejection_count += 1
			RuntimeDiagnostics.increment_performance_counter(
				&"loot_collection_origin_rejections"
			)
			pickup_object.reject_collection("拾取来源无效，无法入账。")
			return false
		raw_map_id = current_map_id
		raw_generation = _zone_generation
	queued_candidate["origin_map_id"] = int(raw_map_id)
	queued_candidate["origin_generation"] = int(raw_generation)
	if int(queued_candidate.get("origin_map_id", -1)) < 0 or int(queued_candidate.get("origin_generation", -1)) < 0:
		_loot_collection_origin_rejection_count += 1
		RuntimeDiagnostics.increment_performance_counter(
			&"loot_collection_origin_rejections"
		)
		pickup_object.reject_collection("拾取来源无效，无法入账。")
		return false
	# Reachability decides admission. Once this real source is accepted, its
	# ordered transaction survives ordinary player movement while IO finishes.
	if not pickup_object.collection_pending():
		return false
	if not _loot_collection_path_is_clear(pickup_object):
		pickup_object.reject_collection("暂时无法到达该物品。")
		return false
	_pending_loot_collections.append(queued_candidate)
	if not _loot_collection_flush_queued:
		_loot_collection_flush_queued = true
		call_deferred("_flush_loot_collections", true)
	return true


func _flush_loot_collections(allow_background := false) -> Dictionary:
	if not _prepared_loot_collection.is_empty():
		if allow_background:
			# This deferred call has been consumed. The in-flight completion must
			# be allowed to schedule the next cohort queued during its write.
			_loot_collection_flush_queued = false
			return {"pending": true}
		var finished := _poll_prepared_loot_collection(true)
		if not bool(finished.get("success", false)) and not bool(finished.get("retry", false)): return finished
	var profile_started_usec := Time.get_ticks_usec()
	_loot_collection_flush_queued = false
	if _pending_loot_collections.is_empty():
		return {"success": true, "candidate_count": 0, "saved": false}
	var pending := _pending_loot_collections
	_pending_loot_collections = []
	var candidates: Array = []
	var transaction_pending: Array[Dictionary] = []
	var stale_count := 0
	for candidate: Dictionary in pending:
		var origin_matches := (
			int(candidate.get("origin_map_id", -1)) == current_map_id
			and int(candidate.get("origin_generation", -1)) == _zone_generation
		)
		var pickup: Variant = candidate.get("pickup")
		if not origin_matches:
			stale_count += 1
			if pickup is LootPickup and is_instance_valid(pickup):
				(pickup as LootPickup).reject_collection("地图已切换，无法拾取。")
			continue
		if not pickup is LootPickup or not is_instance_valid(pickup) or not pickup.collection_pending():
			continue
		transaction_pending.append(candidate)
		candidates.append(candidate.duplicate(true))
	if allow_background and not PlayerState.test_mode and not candidates.is_empty():
		var inventory_bucket := -1
		if RuntimeDiagnostics.performance_timing_enabled():
			var occupied_slots := 0
			for item: Variant in PlayerState.inventory:
				if item is Dictionary and not (item as Dictionary).is_empty():
					occupied_slots += 1
			inventory_bucket = mini(4, floori(float(occupied_slots) / 25.0))
			RuntimeDiagnostics.set_performance_value(&"loot_inventory_occupied_last", float(occupied_slots))
			RuntimeDiagnostics.increment_performance_counter(StringName("loot_prepare_bucket_%d_count" % inventory_bucket))
		var prepare_started_usec := RuntimeDiagnostics.timing_start()
		var plan := PlayerState.prepare_loot_save(candidates)
		var prepare_usec := RuntimeDiagnostics.timing_elapsed_usec(prepare_started_usec)
		if prepare_usec > 0:
			RuntimeDiagnostics.record_performance_max(&"loot_prepare_max_ms", float(prepare_usec) / 1000.0)
			RuntimeDiagnostics.record_performance_max(StringName("loot_prepare_bucket_%d_max_ms" % inventory_bucket), float(prepare_usec) / 1000.0)
		if not plan.has("immediate"):
			_prepared_loot_collection = {"plan": plan, "pending": transaction_pending, "candidate_count": pending.size(), "stale_count": stale_count, "inventory_bucket": inventory_bucket}
			return {"pending": true}
		return _finish_loot_collection_outcomes(transaction_pending, plan.immediate, pending.size(), stale_count, profile_started_usec)
	var result: Dictionary = (
		PlayerState.receive_loot_batch_partial(candidates)
		if not candidates.is_empty()
		else {"success": true, "saved": false, "outcomes": [], "success_count": 0}
	)
	return _finish_loot_collection_outcomes(transaction_pending, result, pending.size(), stale_count, profile_started_usec)


func _poll_prepared_loot_collection(wait := false) -> Dictionary:
	if _prepared_loot_collection.is_empty(): return {"success": true}
	var cohort := _prepared_loot_collection
	var started_usec := Time.get_ticks_usec()
	var valid := true
	for candidate: Dictionary in cohort.pending:
		var pickup: Variant = candidate.get("pickup")
		if (int(candidate.get("origin_map_id", -1)) != current_map_id
			or int(candidate.get("origin_generation", -1)) != _zone_generation
			or not pickup is LootPickup or not is_instance_valid(pickup)
			or not pickup.collection_pending()):
			valid = false
			break
	var result: Dictionary
	if not valid:
		if cohort.plan.writer.cancel():
			result = {"retry": true, "reason": "pickup_origin_changed"}
		else:
			# Approval preceded the origin change and the durable commit already
			# started. Consume its exact receipt; never report a false cancellation.
			result = PlayerState.finish_prepared_loot_save(cohort.plan, true)
	else:
		var commit_started_usec := RuntimeDiagnostics.timing_start()
		result = PlayerState.finish_prepared_loot_save(cohort.plan, wait)
		if not bool(result.get("pending", false)):
			if cohort.plan.has("bytes"):
				RuntimeDiagnostics.set_performance_value(&"loot_save_bytes_last", float((cohort.plan.bytes as PackedByteArray).size()))
			var commit_usec := RuntimeDiagnostics.timing_elapsed_usec(commit_started_usec)
			if commit_usec > 0:
				var field := &"loot_gold_commit_max_ms" if int(cohort.plan.gold_after) != int(cohort.plan.gold_before) else &"loot_item_commit_max_ms"
				RuntimeDiagnostics.record_performance_max(field, float(commit_usec) / 1000.0)
				var inventory_bucket := int(cohort.get("inventory_bucket", -1))
				if inventory_bucket >= 0:
					RuntimeDiagnostics.increment_performance_counter(StringName("loot_commit_bucket_%d_count" % inventory_bucket))
					RuntimeDiagnostics.record_performance_max(StringName("loot_commit_bucket_%d_max_ms" % inventory_bucket), float(commit_usec) / 1000.0)
	if bool(result.get("pending", false)): return result
	_prepared_loot_collection = {}
	if bool(result.get("retry", false)):
		# These sources were accepted before the next cohort. A state barrier
		# may invalidate preparation, but cannot put older rewards behind new
		# ones (including when inventory capacity makes order significant).
		var ordered_pending: Array[Dictionary] = []
		ordered_pending.assign(cohort.pending)
		ordered_pending.append_array(_pending_loot_collections)
		_pending_loot_collections = ordered_pending
	else:
		result = _finish_loot_collection_outcomes(cohort.pending, result, int(cohort.candidate_count), int(cohort.stale_count), started_usec)
	if not _pending_loot_collections.is_empty() and not _loot_collection_flush_queued:
		_loot_collection_flush_queued = true
		call_deferred("_flush_loot_collections", true)
	return result


func _finish_loot_collection_outcomes(transaction_pending: Array, result: Dictionary, candidate_count: int, stale_count: int, profile_started_usec: int) -> Dictionary:
	var transaction_finished_usec := Time.get_ticks_usec()
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_authority_checks", candidate_count)
	var outcomes: Array = result.get("outcomes", [])
	var loot_feedback_names: Array = []
	var collected_gold := 0
	var processed_count := mini(transaction_pending.size(), outcomes.size())
	for index in range(processed_count):
		var candidate: Dictionary = transaction_pending[index]
		var outcome: Dictionary = outcomes[index]
		var pickup: Variant = candidate.get("pickup")
		if bool(outcome.get("success", false)):
			if bool(candidate.get("gold", false)):
				collected_gold += maxi(0, int(candidate.get("amount", 0)))
			if bool(candidate.get("gold", false)):
				loot_feedback_names.append("金币 +%d" % int(candidate.get("amount", 0)))
			else:
				var display_item_id := LootVisualEffectScript.exact_item_id(pickup.item_record) if pickup is LootPickup and is_instance_valid(pickup) else int(candidate.get("item_id", -1))
				var display_name := ("★" if pickup is LootPickup and is_instance_valid(pickup) and LootVisualEffectScript.affix_is_valid(pickup.item_record) else "") + str(candidate.get("item_name", ""))
				loot_feedback_names.append({"item_name": display_name, "item_id": display_item_id})
			if pickup is LootPickup and is_instance_valid(pickup) and (pickup as LootPickup).collection_pending():
				pickup.confirm_collect()
		elif pickup is LootPickup and is_instance_valid(pickup) and (pickup as LootPickup).collection_pending():
			pickup.reject_collection(str(outcome.get("message", "超过负重，无法拾取。")))
	var outcomes_complete := processed_count == transaction_pending.size()
	if not outcomes_complete:
		# Keep unacknowledged candidates pending for a diagnosable retry instead
		# of silently dropping them when a malformed/partial transaction result
		# is returned.
		var ordered_pending: Array[Dictionary] = []
		ordered_pending.assign(transaction_pending.slice(processed_count))
		ordered_pending.append_array(_pending_loot_collections)
		_pending_loot_collections = ordered_pending
		if not _pending_loot_collections.is_empty() and not _loot_collection_flush_queued:
			_loot_collection_flush_queued = true
			call_deferred("_flush_loot_collections", true)
	if collected_gold > 0 and is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_item_event("currency:gold", "loot_success", {"map_id": current_map_id})
	if hud != null and not loot_feedback_names.is_empty():
		hud.show_loot_batch(loot_feedback_names)
	var feedback_usec := RuntimeDiagnostics.timing_elapsed_usec(transaction_finished_usec)
	if feedback_usec > 0:
		RuntimeDiagnostics.record_performance_max(&"loot_feedback_max_ms", float(feedback_usec) / 1000.0)
	if CombatDiagnosticLogScript.capture_enabled():
		print("[LootPickupProfile] ", JSON.stringify({
			"candidate_count": candidate_count,
			"transaction_ms": float(transaction_finished_usec - profile_started_usec) / 1000.0,
			"feedback_ms": float(Time.get_ticks_usec() - transaction_finished_usec) / 1000.0,
			"total_ms": float(Time.get_ticks_usec() - profile_started_usec) / 1000.0,
			"transaction": PlayerState._last_loot_batch_profile.duplicate(true),
		}))
	return {
		"success": bool(result.get("success", false)) and outcomes_complete,
		"saved": bool(result.get("saved", false)),
		"candidate_count": candidate_count,
		"success_count": int(result.get("success_count", 0)),
		"stale_count": stale_count,
		"outcomes_count": outcomes.size(),
		"remaining_count": _pending_loot_collections.size(),
		"reason": (
			"loot_collection_outcomes_incomplete"
			if not outcomes_complete
			else str(result.get("reason", ""))
		),
	}


func _on_loot_collection_rejected(_item_name: String, message: String) -> void:
	if is_instance_valid(hud):
		# A rejected pickup is an operation failure: it belongs to the
		# dedicated error channel, not the general notice lane.
		hud.show_error_message(message)


func _on_player_stats_changed(current_hp: int, max_hp: int) -> void:
	if hud != null:
		hud.update_hp(current_hp, max_hp)


func _sync_player_runtime_snapshot_to_hud() -> void:
	if hud == null or player == null:
		return
	hud.update_resources(player.current_hp, player.max_hp, player.current_mp, player.max_mp)
	hud.update_warrior_states(player.warrior_state_snapshot())


func _on_background_item_save_failed() -> void:
	if is_instance_valid(hud):
		hud.show_error_message("最近的进度尚未保存，请检查存储空间")


func _on_consumable_used(entity_id: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item := GameData.get_entity_record(entity_id)
	if item.get("kind") != "consumable" or not item.get("usable", true): return
	var effect := str(item.get("useEffect", ""))
	var restored_hp := int(item.get("restoreHealth", 0))
	var restored_mp := int(item.get("restoreMana", 0))
	if effect == "delayed_restore" and (restored_hp > 0 or restored_mp > 0):
		player.queue_potion_restore(restored_hp, restored_mp)
	elif effect == "restore_both" and (restored_hp > 0 or restored_mp > 0):
		player.restore_health(restored_hp)
		player.restore_mana(restored_mp)
	elif effect == "temporary_buff":
		var duration := maxf(1.0, float(item.get("durationMinutes", 1)) * 60.0)
		var stats: Dictionary = item.get("stats", {})
		player.apply_defense_buff(duration, maxi(int(stats.get("MaxAC", 0)), int(stats.get("MaxMAC", 0))))
	elif entity_id == "hc.service_item.000123":
		# Preserve this exact pre-ID compatibility behavior. Its source curse
		# rule is a separate gameplay decision, not an identity migration.
		player.restore_health(30)
		player.restore_mana(30)
		player.apply_defense_buff(60.0, 2)
	# R2: the generic "使用了X" text is retired here — the structured use
	# result is the single central owner for every consumable use notice, so
	# this legacy signal lane must not add a second one. Effects stay.


func _on_scroll_used(entity_id: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item := GameData.get_entity_record(entity_id)
	if item.get("kind") != "scroll" or not item.get("usable", true): return
	var effect := str(item.get("useEffect", ""))
	if effect in ["town_teleport", "dungeon_escape"]:
		travel_to_service_home(false, false, "比奇省")
	elif effect == "random_teleport":
		var destination := _find_valid_random_teleport_position(player.global_position)
		if destination == player.global_position:
			hud.show_error_message("附近没有可用传送落点")
			return
		_set_player_world_position(destination)
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
	elif effect == "repair_oil":
		_report_repair_oil_result(PlayerState.apply_weapon_repair_oil_result(false))
		return
	elif effect == "war_god_oil":
		_report_repair_oil_result(PlayerState.apply_weapon_repair_oil_result(true))
		return
	# R2: the generic "使用了X" text is retired here — the structured use
	# result is the single central owner for every scroll use notice, so this
	# legacy signal lane must not add a second one. Effects stay.


func _report_repair_oil_result(result: Dictionary) -> void:
	# The repair-oil authority now reports a structured result: an actual
	# repair stays on the notice lane, every rejection (no weapon, nothing to
	# repair, save failure) surfaces on the dedicated error channel.
	if bool(result.get("success", false)):
		hud.show_message(str(result.get("message", "")))
	else:
		hud.show_error_message(
			UIErrorFeedbackScript.from_result(result, "修复失败，请稍后重试。")
		)


func _skill_teleport_destination_is_valid(origin_screen_px: Vector2, destination_ground_gu: Vector2) -> bool:
	return _world_skill_runtime()._skill_teleport_destination_is_valid(origin_screen_px, destination_ground_gu)


func _teleport_destination_is_clear(candidate_ground_gu: Vector2) -> bool:
	return _world_skill_runtime()._teleport_destination_is_clear(candidate_ground_gu)


func _find_valid_skill_teleport_position(origin_screen_px: Vector2) -> Vector2:
	return _world_skill_runtime()._find_valid_skill_teleport_position(origin_screen_px)


func _find_valid_random_teleport_position(origin_screen_px: Vector2) -> Vector2:
	return _world_skill_runtime()._find_valid_random_teleport_position(origin_screen_px)


func _respawn_later(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	seconds: float,
	generation: int,
	spawn_context: Dictionary = {}
) -> void:
	# Delayed births use the same published base qualification before acquiring
	# Timer ownership. The factory rechecks after the real timeout as before.
	if not is_inside_tree() or generation != _zone_generation or not is_finite(seconds) or seconds < 0.0:
		return
	if not _world_context.matches_world(_feature_target_bound.snapshot().get("world", {})):
		return
	var raw_base_seconds: Variant = spawn_context.get("respawn_base_seconds", seconds)
	if not raw_base_seconds is int and not raw_base_seconds is float:
		return
	var base_seconds: float = float(raw_base_seconds)
	var admission := _feature_target_bound.admit_base(
		_strict_runtime_monster_id(monster_data), spawn_position, base_seconds, spawn_context)
	if not bool(admission.get("accepted", false)):
		return
	var wakeup := get_tree().create_timer(seconds)
	var identity := wakeup.get_instance_id()
	_respawn_wakeups[identity] = wakeup
	await wakeup.timeout
	# A retired owner may have re-entered the tree before the cancelled timer
	# is reclaimed. Only a still-owned wakeup can attempt the original spawn.
	if not _respawn_wakeups.erase(identity):
		return
	if not is_inside_tree() or generation != _zone_generation:
		return
	var slot_id := str(spawn_context.get("spawn_slot_id", ""))
	if not slot_id.is_empty() and _spawn_slot_is_alive(slot_id, generation):
		return
	_spawn_enemy(
		monster_data,
		spawn_position,
		is_boss,
		float(spawn_context.get("respawn_base_seconds", seconds)),
		spawn_context
	)


func _cancel_respawn_wakeups() -> void:
	# Preserve the original SceneTreeTimer clock while this world is live.
	# Retirement revokes dispatch first, then lets SceneTree reclaim timers on
	# its next idle pass instead of retaining dead-world wakeups for 5-60 min.
	var retiring: Array = _respawn_wakeups.values()
	_respawn_wakeups.clear()
	for wakeup: SceneTreeTimer in retiring:
		wakeup.time_left = 0.0


func _spawn_slot_is_alive(slot_id: String, generation: int, owned_only := false) -> bool:
	# Fatal HP removes the receiver from `enemies` immediately; its body and
	# deferred callbacks still belong to this factory until queued retirement.
	var candidates: Array=get_children() if owned_only else get_tree().get_nodes_in_group("enemies")
	for value: Variant in candidates:
		if value is EnemyActor and not value.is_queued_for_deletion():
			if str(value.get_meta("spawn_slot_id", "")) == slot_id and int(value.get_meta("zone_generation", -1)) == generation:
				if not owned_only or is_ancestor_of(value):
					return true
	return false

# HC-MELEE-AI-PACKAGE: lightning legality stays in the canonical pipeline.
var _hc_lightning_hint_ms := -1000

func _hc_lightning_clear(victim: EnemyActor, caster_origin: Vector2) -> bool:
	return _world_skill_runtime()._hc_lightning_clear(victim, caster_origin)


func _combat_target_world_clear(victim: EnemyActor, caster_origin: Vector2, allow_cache := false) -> bool:
	return _world_skill_runtime()._combat_target_world_clear(victim, caster_origin, allow_cache)


func _hc_skill_preflight(stable_skill_id: String, target_id: int) -> bool:
	return _world_skill_runtime()._hc_skill_preflight(stable_skill_id, target_id)


func _action_configuration_identity() -> Dictionary:
	return _world_skill_runtime()._action_configuration_identity()


func feature_publication_scope() -> Dictionary:
	return _world_skill_runtime().feature_publication_scope()


var _feature_target_bound := preload("res://scripts/features/adapters/world_target_bound.gd").new()

func feature_world_capacity_bound() -> Dictionary:
	return _world_skill_runtime().feature_world_capacity_bound()


func _capture_action_configuration(stable_skill_id: String, melee: Dictionary = {}) -> RefCounted:
	return _world_skill_runtime()._capture_action_configuration(stable_skill_id, melee)


func _reserve_feature_action(configuration: RefCounted) -> Dictionary:
	return _world_skill_runtime()._reserve_feature_action(configuration)


func _reserve_feature_bindings(skill_id: String, bindings: Array) -> RefCounted:
	return _world_skill_runtime()._reserve_feature_bindings(skill_id, bindings)


func _capture_melee_configuration() -> RefCounted:
	return _world_skill_runtime()._capture_melee_configuration()


func _canonical_action_primary_stats(configuration: RefCounted) -> Dictionary:
	return _world_skill_runtime()._canonical_action_primary_stats(configuration)


func _begin_feature_damage_batch(skill_id: String, release_id: String, configuration: RefCounted = null) -> RefCounted:
	return _world_skill_runtime()._begin_feature_damage_batch(skill_id, release_id, configuration)


func _finish_feature_damage_batch(batch: RefCounted) -> Dictionary:
	return _world_skill_runtime()._finish_feature_damage_batch(batch)


# Only the same admitted runtime owns this entry. It passes an already minted
# branch ticket; no child may acquire capacity after its parent's HP commit.
func _execute_feature_child_action(request: Dictionary, ticket: RefCounted, bindings: Array,
	source: Node2D, resources: RefCounted) -> Dictionary:
	return _world_skill_runtime()._execute_feature_child_action(request, ticket, bindings, source, resources)


func _ordinary_attack_owner_matches(
	press_token: int, touch_id: int, source: StringName
) -> bool:
	return _world_skill_runtime()._ordinary_attack_owner_matches(press_token, touch_id, source)


func _process_ordinary_attack_input(attack_action_lifecycle: Dictionary) -> void:
	_world_skill_runtime()._process_ordinary_attack_input(attack_action_lifecycle)


func _reconcile_ordinary_attack_button_owners() -> void:
	_world_skill_runtime()._reconcile_ordinary_attack_button_owners()


func _try_ordinary_attack_intent(origin: StringName) -> bool:
	return _world_skill_runtime()._try_ordinary_attack_intent(origin)


# HCM30-R4: adapters are deliberately kept in GameRoot, the existing authority.
const HCM30SummonQueueScript := preload("res://scripts/monster_ai_package/m30/summon_queue.gd")
var _hc_m30_summon_queue: HCM30SummonQueue
var _hc_m30_landing_scratch: Array = []

func _hc_m30_get_summon_queue() -> HCM30SummonQueue:
	if not is_instance_valid(_hc_m30_summon_queue):
		_hc_m30_summon_queue = HCM30SummonQueueScript.new()
		_hc_m30_summon_queue.configure(self)
		add_child(_hc_m30_summon_queue)
	return _hc_m30_summon_queue

func _hc_m30_probe_landing(origin_screen_px: Vector2) -> Vector2:
	var origin_gu: Vector2 = _canonical_screen_px_to_ground_gu(origin_screen_px)
	if not origin_gu.is_finite():
		return Vector2.INF
	# Preserve the existing angle/radius distribution (NOT uniform-area sampling).
	var candidate_gu: Vector2 = origin_gu + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(1.5, 6.0)
	# This is deliberately the SAME radius as the original summon call site.
	var radius_gu: float = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.MONSTER_COLLISION_RADIUS_PX)
	return _canonical_ground_gu_to_screen_px(candidate_gu) if _hc_m30_landing_clear(candidate_gu, radius_gu, null) else Vector2.INF

func _hc_m30_landing_clear(candidate_gu: Vector2, radius_gu: float, ignored_enemy: EnemyActor) -> bool:
	if not candidate_gu.is_finite() or not is_finite(radius_gu) or radius_gu < 0.0:
		return false
	if not is_instance_valid(background) or _combat_spatial_index == null or current_map_id < 0:
		return false
	if not bool(_safe_zone_context.get("valid", false)):
		return false
	if WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(candidate_gu, _active_safe_zones):
		return false
	var candidate_px: Vector2 = _canonical_ground_gu_to_screen_px(candidate_gu)
	var radius_px: float = WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(radius_gu)
	if not candidate_px.is_finite() or WorldSpatialRulesScript.environment_blocks_actor_screen_px(background, candidate_px, radius_px):
		return false
	if is_instance_valid(player):
		var player_gu: Vector2 = _canonical_screen_px_to_ground_gu(player.global_position)
		var player_radius: float = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.PLAYER_COLLISION_RADIUS_PX)
		if not player_gu.is_finite() or player_gu.distance_to(candidate_gu) < radius_gu + player_radius + ACTOR_LANDING_CLEARANCE_GU:
			return false
	# Degenerate segment = point AABB. The index itself adds max actor bounds.
	# Use the unsorted API: occupancy is existence, not a selected damage victim.
	_combat_spatial_index.query_enemy_nodes_segment_unsorted_into(
		current_map_id, candidate_gu, candidate_gu,
		radius_gu + ENEMY_LANDING_CLEARANCE_GU, _hc_m30_landing_scratch)
	for raw: Variant in _hc_m30_landing_scratch:
		if not is_instance_valid(raw) or not raw is EnemyActor:
			continue
		var other: EnemyActor = raw as EnemyActor
		if other == ignored_enemy or other.is_queued_for_deletion() or other.current_hp <= 0 or other._death_pending or other._dying:
			continue
		if other.runtime_map_id != current_map_id or int(other.get_meta("zone_generation", -1)) != _zone_generation:
			continue
		var other_gu: Vector2 = other.spatial_index_position()
		if not other_gu.is_finite():
			return false
		if other_gu.distance_to(candidate_gu) < radius_gu + other.combat_radius_gu + ENEMY_LANDING_CLEARANCE_GU:
			return false
	return true

func _hc_m30_materialize(monster: Dictionary, candidate_px: Vector2, context: Dictionary) -> EnemyActor:
	# Return through the canonical spawn authority; no parallel EnemyActor factory.
	return _spawn_enemy(monster, candidate_px, false, DEFAULT_NORMAL_RESPAWN_SECONDS, context)

func hc_m30_summon_snapshot() -> Dictionary:
	return _hc_m30_summon_queue.snapshot() if is_instance_valid(_hc_m30_summon_queue) else {"pending_batches": 0}

func _hc_m30_summon_request_valid(source: EnemyActor, ids: Array, count: int, maximum: int) -> bool:
	if not is_instance_valid(source):
		return false
	return _feature_target_bound.summon_request_valid(
		str(source.get_meta("spawn_slot_id", "")), source.monster_id, ids, count, maximum)

func _hc_m30_resolve_monster(raw_id: Variant) -> Dictionary:
	if not raw_id is int and not raw_id is float:
		return {}
	if float(raw_id) != floorf(float(raw_id)):
		return {}
	var inputs: RefCounted = _feature_target_bound.monster_inputs(int(raw_id))
	return inputs.view().entry if inputs != null else {}

func hc_m30_stable_enemy_ground_point(point: Vector2, radius_gu: float, expected_map_id: int) -> Vector2:
	# Read-only projection shared by existing Bich enforcement and navigation.
	# Does NOT modify positions, safe zones, attack reach or attack eligibility.
	if expected_map_id != current_map_id or not point.is_finite() or not is_finite(radius_gu) or radius_gu < 0.0:
		return Vector2.INF
	if current_map_id != BICH_RUNTIME_MAP_ID:
		return point
	if not _safe_zone_context_is_valid():
		return Vector2.INF
	return WorldSpatialRulesScript.project_outside_safe_zones_ground_gu(
		point, _active_safe_zones, radius_gu + SAFE_ZONE_ACTOR_PADDING_GU
	)

var _original_source_main_attachment: RefCounted
