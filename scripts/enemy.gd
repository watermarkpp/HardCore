class_name EnemyActor
extends CharacterBody2D

const EnemyActorModelScript := preload("res://scripts/gameplay/actors/enemy_actor_model.gd")
const EnemyLegacyPortsScript := preload("res://scripts/gameplay/actors/enemy_legacy_actor_ports.gd")
const EnemyLegacyContext := preload("res://scripts/gameplay/actors/enemy_legacy_context.gd")
var domain_model := EnemyActorModelScript.new()
var _enemy_ports: RefCounted

func _ensure_enemy_domain() -> void:
	if _enemy_ports != null: return
	_enemy_ports = EnemyLegacyPortsScript.new(self, domain_model, EnemyLegacyContext.owner_context())
	var configured: bool = domain_model.configure_ports(_enemy_ports.bindings())
	assert(configured, "Enemy Main port admission failed")
	if not configured: return
	var bound: bool = domain_model.bind_runtime_actor_id(get_instance_id())
	assert(bound, "Enemy canonical identity admission failed")
	if not bound: return
	_enemy_ports.connect_model_signals()


signal combat_target_changed(enemy: EnemyActor, new_target: Node2D)

const CombatActionStateScript := preload("res://scripts/gameplay/actors/enemy_combat_action_state.gd")
# Serial legacy adapter and S both use this exact rule/state instance.
var combat_actions: RefCounted:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.combat_actions)
	set(value):
		_ensure_enemy_domain()
		domain_model.combat_actions = _enemy_ports.to_domain(value)

const HCM30ContextTokenScript := preload("res://scripts/monster_ai_package/m30/context_token.gd")
const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")
const FeatureDamageBatchScript := preload("res://scripts/features/runtime/damage_batch.gd")
const AttackTimingScript := preload("res://scripts/monster_attack_timing.gd")
# Exact transaction fault seam, callable only in an explicit test fixture.
var test_attack_admission_hook: Callable:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.test_attack_admission_hook)
	set(value):
		_ensure_enemy_domain()
		domain_model.test_attack_admission_hook = _enemy_ports.to_domain(value)

const HCM30WalkPhaseScript := preload("res://scripts/monster_ai_package/m30/walk_phase.gd")
var _hc_m30_attack_move_cutoff: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_m30_attack_move_cutoff)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_m30_attack_move_cutoff = _enemy_ports.to_domain(value)

var _hc_m30_attack_pose_remaining: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_m30_attack_pose_remaining)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_m30_attack_pose_remaining = _enemy_ports.to_domain(value)

var _locomotion_pose_intent: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._locomotion_pose_intent)
	set(value):
		_ensure_enemy_domain()
		domain_model._locomotion_pose_intent = _enemy_ports.to_domain(value)

var _directional_collision: KinematicCollision2D:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._directional_collision)
	set(value):
		_ensure_enemy_domain()
		domain_model._directional_collision = _enemy_ports.to_domain(value)

var _used_directional_sweep: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._used_directional_sweep)
	set(value):
		_ensure_enemy_domain()
		domain_model._used_directional_sweep = _enemy_ports.to_domain(value)

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const MonsterTargetRingGeometryScript := preload("res://scripts/monster_target_ring_geometry.gd")
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const MonsterGroundRuntimeDiagnosticOverlayScript := preload(
	"res://scripts/monster_ground_runtime_diagnostic_overlay.gd"
)
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const CombatResolutionRules := preload("res://scripts/combat_resolution_rules.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const PublishedMonsterInputsScript := preload("res://scripts/features/contracts/published_monster_inputs.gd")
const MonsterUnitAdapterScript := preload("res://scripts/monster_unit_adapter.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const MonsterDeliveryGeometryScript := preload(
	"res://scripts/monster_ai_package/delivery_geometry.gd"
)
const EntrapmentBoundaryControllerScript := preload(
	"res://scripts/entrapment_boundary_controller.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const ActorBodyPolicyScript := preload("res://scripts/actor_body_policy.gd")
const MonsterRangedProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)
const MonsterTargetMagicEffectScript := preload(
	"res://scripts/monster_target_magic_effect.gd"
)
const MonsterMovementCadenceScript := preload(
	"res://scripts/monster_movement_cadence.gd"
)
const Source176Melee := preload(
	"res://scripts/monster_source176/source_melee_geometry.gd"
)
const SourceStepPlan := preload(
	"res://scripts/monster_source176/source_step_plan.gd"
)
const CrowdAttackPosition := preload("res://scripts/monster_crowd_attack_position_policy.gd")
const HCDecisionBudget := preload("res://scripts/monster_ai_package/decision_budget.gd")
const SourceActionBoundary := preload(
	"res://scripts/monster_source176/action_boundary.gd"
)
## Shared read-only empty damage context so DOT/poison ticks never allocate a
## per-tick Dictionary on the damage core path.
const EMPTY_DAMAGE_CONTEXT: Dictionary = {}
const MonsterNaturalRegenPolicyScript := preload(
	"res://scripts/monster_natural_regen_policy.gd"
)
const MonsterNeighborStepPolicyScript := preload(
	"res://scripts/monster_neighbor_step_policy.gd"
)
const MonsterTargetAcquisitionPolicyScript := preload(
	"res://scripts/monster_target_acquisition_policy.gd"
)
const MonsterTerrainNavigationPolicyScript := preload(
	"res://scripts/monster_terrain_navigation_policy.gd"
)
const PlayerCharacterScript := preload("res://scripts/player.gd")
const MONSTER_RUNTIME_AUTHORITY_PATH := (
	"res://assets/data/monster_runtime_authority_v1.json"
)
const MONSTER_ATTACK_RANGE_POLICY_PATH := (
	"res://assets/data/monster_attack_range_policy_v1.json"
)
const MONSTER_MAGIC_MELEE_EFFECT_ID := "monster.flame_wooma.magic_melee.v1"
const MONSTER_AREA_MAGIC_EFFECT_ID := "monster.touch_dragon.area_magic.v1"
const RETIRED_SOURCE_ONLY_MONSTER_IDS := [71]
const FIXED_AREA_GROUND_SPIKE_EFFECT_ID := (
	"monster.fixed_area_ground_spike.v1"
)
const FIXED_AREA_GROUND_SPIKE_MONSTER_IDS := [180, 195]
const CROWD_GRID_CELL_SIZE_GU := 3.0
const CROWD_GRID_REFRESH_FRAMES := 3
const CROWD_STEERING_INTERVAL_SECONDS := 0.10
const FAR_RETARGET_MIN_SECONDS := 0.28
const FAR_RETARGET_STAGGER_SECONDS := 0.017
const NEAR_RETARGET_MIN_SECONDS := 0.18
const NEAR_RETARGET_STAGGER_SECONDS := 0.011
## Damage contributes to the shared threat competition, but one hit must never
## rewrite the current target. A challenger may win only after the current
## target has remained stable briefly and the challenger's accumulated threat
## exceeds both an absolute and relative hysteresis margin. Physical summon
## interception remains an explicit override below.
const TARGET_SWITCH_MIN_STABLE_SECONDS := 0.45
const TARGET_SWITCH_MIN_THREAT_ADVANTAGE := 100.0
const TARGET_SWITCH_THREAT_ADVANTAGE_RATIO := 0.20
## Source targetSearch values describe the legacy service loop, where a Boss
## could retain one valid target for up to eight seconds.  Runtime movement is
## continuous now, so target *re-evaluation* is capped separately without
## changing source-authoritative attack or movement intervals.  The per-instance
## phase keeps a room of bosses from evaluating on one physics frame.
const BOSS_TARGET_REEVALUATION_MAX_SECONDS := 0.35
const BOSS_TARGET_REEVALUATION_STAGGER_SECONDS := 0.013
const SUMMON_INTERCEPT_CONTACT_EPSILON_GU := 0.25
const BACKGROUND_AI_INTERVAL_SECONDS := 0.25
## At-rest actors with no target/threat need only two local acquisition wakes
## per second. Keep return/other maintenance and the shared target index at
## their existing cadence; damage still wakes through the event path.
const IDLE_ACQUISITION_INTERVAL_SECONDS := 0.5
const BACKGROUND_AI_MIN_DISTANCE_GU := 37.5
const BACKGROUND_WAKE_PHASE_SLOTS := 15
## The acquisition broadphase is screen-space only.  The exact phase below
## still evaluates canonical Ground GU deltas, so this rectangle can only add
## candidates; it must never decide whether a target is in range.
const TARGET_GRID_CELL_SIZE_PX := Vector2(128.0, 64.0)
## Keep the broadphase rectangle deliberately conservative around the formal
## iso projection.  Exact Ground-GU checks remain authoritative below.
const TARGET_GRID_HALF_EXTENTS_PER_GU := Vector2(128.0, 64.0)
## Secondary combat targets may be newly spawned between shared refreshes.  A
## 250 ms window matches the existing background decision cadence; the known
## primary player remains a live direct candidate and is never delayed here.
const TARGET_GRID_REFRESH_SECONDS := BACKGROUND_AI_INTERVAL_SECONDS
const ENVIRONMENT_GUARD_INTERVAL_SECONDS := 0.10
const ENEMY_MOTION_MASK := WorldSpatialRulesScript.ENEMY_MASK
const POISON_INDICATOR_STYLE := "overhead_green_red_dot_row"
const POISON_INDICATOR_DOT_RADIUS := 3.0
const POISON_INDICATOR_DOT_CENTER_OFFSET_X := 5.0
const NAME_LABEL_SIZE := MonsterOverheadScript.NAME_LABEL_SIZE
const NAME_LABEL_HEALTH_BAR_GAP := MonsterOverheadScript.NAME_LABEL_HEALTH_BAR_GAP
const TARGET_RING_FOOTPRINT_SCALE := 1.25
const PLAYER_MELEE_CONTACT_CONTRACT_ID := "monster.melee_player_contact.ground_gu.v2"
const BOSS_WARNING_PROJECTION_CONTRACT_ID := "monster.boss.warning.ground_projection.v1"
const BOSS_PHASE_GROUND_RING_VISIBLE := false
const SAFE_ZONE_REFERENCE_CONTRACT_ID := "monster.safe_zone.relative_ground_reference.v1"
const ATTACK_FOOTPRINT_CONTRACT_ID := (
	"monster.attack.release_footpoint_projection.v1"
)
const PROJECTION_RELATIONSHIP_RELEASE_CONTACT := "release_contact"
const PROJECTION_RELATIONSHIP_DIRECTED_CORE := "directed_core"
const PROJECTION_RELATIONSHIP_PROJECTILE_SWEEP := "projectile_sweep"
const PROJECTION_RELATIONSHIP_GROUND_EXACT := "ground_exact"
const PLAYER_MELEE_CONTACT_GAP_GU := 0.4375
const DELAYED_HIT_TOLERANCE_GU := 0.25
# Existing ranged profiles start at 155px. This guard only selects the moving
# contact attackers whose stop point must be compatible with the player's
# formal 1.5-tile melee geometry; it never shortens or expands ranged attacks.
const RANGED_ATTACK_RANGE_FLOOR_GU := 4.0
const SPAWN_RETURN_EPSILON_GU := 0.1875
const SAFE_ZONE_RETURN_EPSILON_GU := 0.125
const CONTACT_RETREAT_EPSILON_GU := 0.09375
const CROWD_SEPARATION_GAP_GU := 0.375
const CROWD_NEIGHBOR_QUERY_RADIUS_GU := 2.0
const LAST_SAFE_REFRESH_DISTANCE_GU := 2.0
const PROJECTILE_OBSTACLE_SAMPLE_STEP_GU := 0.25
const ATTACK_PATH_OBSTACLE_SAMPLE_STEP_GU := PROJECTILE_OBSTACLE_SAMPLE_STEP_GU
const CORPSE_HOLD_SECONDS := 2.0
const HC_SHARED_GOAL_CACHE_LIMIT := 64
const SPECIAL_DELIVERY_SETTLEMENT_LIMIT := 512
const MONSTER_SPECIAL_CELL_DELIVERY_KINDS := [
	"directional_spit_map",
	"gas_adjacent",
	"line_magic",
	"mixed_target_tile",
	"guard_direct_projectile",
]

static var _crowd_query_candidate_count: int:
	get: return EnemyLegacyContext.owner_context().shared._crowd_query_candidate_count
	set(value): EnemyLegacyContext.owner_context().shared._crowd_query_candidate_count = value

static var _crowd_steering_evaluation_count: int:
	get: return EnemyLegacyContext.owner_context().shared._crowd_steering_evaluation_count
	set(value): EnemyLegacyContext.owner_context().shared._crowd_steering_evaluation_count = value

static var _retarget_full_scan_count: int:
	get: return EnemyLegacyContext.owner_context().shared._retarget_full_scan_count
	set(value): EnemyLegacyContext.owner_context().shared._retarget_full_scan_count = value

static var _retarget_decision_count: int:
	get: return EnemyLegacyContext.owner_context().shared._retarget_decision_count
	set(value): EnemyLegacyContext.owner_context().shared._retarget_decision_count = value

static var _target_grid_last_refresh_msec: int:
	get: return EnemyLegacyContext.owner_context().shared._target_grid_last_refresh_msec
	set(value): EnemyLegacyContext.owner_context().shared._target_grid_last_refresh_msec = value

static var _target_grid: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._target_grid
	set(value): EnemyLegacyContext.owner_context().shared._target_grid = value

static var _target_grid_node_ids: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._target_grid_node_ids
	set(value): EnemyLegacyContext.owner_context().shared._target_grid_node_ids = value

static var _target_grid_group_scan_count: int:
	get: return EnemyLegacyContext.owner_context().shared._target_grid_group_scan_count
	set(value): EnemyLegacyContext.owner_context().shared._target_grid_group_scan_count = value

static var _target_grid_candidate_count: int:
	get: return EnemyLegacyContext.owner_context().shared._target_grid_candidate_count
	set(value): EnemyLegacyContext.owner_context().shared._target_grid_candidate_count = value

static var _background_ai_evaluation_count: int:
	get: return EnemyLegacyContext.owner_context().shared._background_ai_evaluation_count
	set(value): EnemyLegacyContext.owner_context().shared._background_ai_evaluation_count = value

static var _background_fast_path_skip_count: int:
	get: return EnemyLegacyContext.owner_context().shared._background_fast_path_skip_count
	set(value): EnemyLegacyContext.owner_context().shared._background_fast_path_skip_count = value

static var _foreground_ai_tick_count: int:
	get: return EnemyLegacyContext.owner_context().shared._foreground_ai_tick_count
	set(value): EnemyLegacyContext.owner_context().shared._foreground_ai_tick_count = value

static var _background_deep_sleep_entry_count: int:
	get: return EnemyLegacyContext.owner_context().shared._background_deep_sleep_entry_count
	set(value): EnemyLegacyContext.owner_context().shared._background_deep_sleep_entry_count = value

static var _background_deep_sleep_wakeup_count: int:
	get: return EnemyLegacyContext.owner_context().shared._background_deep_sleep_wakeup_count
	set(value): EnemyLegacyContext.owner_context().shared._background_deep_sleep_wakeup_count = value

static var _physics_move_count: int:
	get: return EnemyLegacyContext.owner_context().shared._physics_move_count
	set(value): EnemyLegacyContext.owner_context().shared._physics_move_count = value

static var _environment_guard_check_count: int:
	get: return EnemyLegacyContext.owner_context().shared._environment_guard_check_count
	set(value): EnemyLegacyContext.owner_context().shared._environment_guard_check_count = value

static var _runtime_map_id_property_list_scan_count: int:
	get: return EnemyLegacyContext.owner_context().shared._runtime_map_id_property_list_scan_count
	set(value): EnemyLegacyContext.owner_context().shared._runtime_map_id_property_list_scan_count = value

static var _hc_shared_goal_cache: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_goal_cache
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_goal_cache = value

static var _hc_shared_goal_cache_order: Array:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_goal_cache_order
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_goal_cache_order = value

static func reset_runtime_map_id_diagnostics() -> void:
	EnemyLegacyContext.owner_context().shared.reset_runtime_map_id_diagnostics()

static func runtime_map_id_diagnostics() -> Dictionary:
	return EnemyLegacyContext.owner_context().shared.runtime_map_id_diagnostics()

static func _record_performance_counter(field: StringName, amount := 1) -> void:
	EnemyLegacyContext.owner_context().shared._record_performance_counter(field, amount)

static var _movement_authority_loaded: bool:
	get: return EnemyLegacyContext.owner_context().shared._movement_authority_loaded
	set(value): EnemyLegacyContext.owner_context().shared._movement_authority_loaded = value

static var _movement_authority_load_failed: bool:
	get: return EnemyLegacyContext.owner_context().shared._movement_authority_load_failed
	set(value): EnemyLegacyContext.owner_context().shared._movement_authority_load_failed = value

static var _movement_authority_by_id: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._movement_authority_by_id
	set(value): EnemyLegacyContext.owner_context().shared._movement_authority_by_id = value

static var _attack_range_policy_loaded: bool:
	get: return EnemyLegacyContext.owner_context().shared._attack_range_policy_loaded
	set(value): EnemyLegacyContext.owner_context().shared._attack_range_policy_loaded = value

static var _attack_range_policy_load_failed: bool:
	get: return EnemyLegacyContext.owner_context().shared._attack_range_policy_load_failed
	set(value): EnemyLegacyContext.owner_context().shared._attack_range_policy_load_failed = value

static var _attack_range_policy_by_id: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._attack_range_policy_by_id
	set(value): EnemyLegacyContext.owner_context().shared._attack_range_policy_by_id = value

static var _audio_runtime_service: Node
const AUDIO_SERVICE_NEGATIVE_CACHE_MSEC := 1000
static var _audio_service_retry_after_msec := 0
static var _audio_service_lookup_count := 0
static var _audio_service_now_override_msec := -1

signal died(enemy: EnemyActor, monster_data: Dictionary)
signal target_requested(enemy: EnemyActor)
signal summon_requested(enemy: EnemyActor, monster_ids: Array, count: int, max_active: int)
signal relocation_requested(enemy: EnemyActor, radius_gu: float)
## Pure presentation hook emitted once per frozen fixed-area victim at release.
## The descriptor carries the same immutable snapshot for every victim of one
## area release; consumers must never use this signal as a second damage path.
signal fixed_area_ground_spike_requested(descriptor: Dictionary)
## Telemetry/presentation hook emitted once for every accepted physical ranged
## release. EnemyActor also creates the visual locally; listeners are observers
## and must never submit a second damage transaction.
signal ranged_projectile_requested(descriptor: Dictionary)
signal target_magic_requested(descriptor: Dictionary)
## Presentation-only observer for source-backed monster cell attacks. Damage
## remains owned and settled by this actor against the exact same frozen V2
## snapshot; listeners must never schedule or submit damage.
signal monster_special_delivery_requested(descriptor: Dictionary)

var monster_data: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.monster_data)
	set(value):
		_ensure_enemy_domain()
		domain_model.monster_data = _enemy_ports.to_domain(value)

var monster_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.monster_id)
	set(value):
		_ensure_enemy_domain()
		domain_model.monster_id = _enemy_ports.to_domain(value)

var display_name: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.display_name)
	set(value):
		_ensure_enemy_domain()
		domain_model.display_name = _enemy_ports.to_domain(value)

var max_hp: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.max_hp)
	set(value):
		_ensure_enemy_domain()
		domain_model.max_hp = _enemy_ports.to_domain(value)

var current_hp: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.current_hp)
	set(value):
		_ensure_enemy_domain()
		domain_model.current_hp = _enemy_ports.to_domain(value)

var attack_min: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.attack_min)
	set(value):
		_ensure_enemy_domain()
		domain_model.attack_min = _enemy_ports.to_domain(value)

var attack_max: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.attack_max)
	set(value):
		_ensure_enemy_domain()
		domain_model.attack_max = _enemy_ports.to_domain(value)

var defense: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.defense)
	set(value):
		_ensure_enemy_domain()
		domain_model.defense = _enemy_ports.to_domain(value)

var magic_defense: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.magic_defense)
	set(value):
		_ensure_enemy_domain()
		domain_model.magic_defense = _enemy_ports.to_domain(value)

var direct_spell_stats_valid: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.direct_spell_stats_valid)
	set(value):
		_ensure_enemy_domain()
		domain_model.direct_spell_stats_valid = _enemy_ports.to_domain(value)

var direct_spell_anti_magic_points: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.direct_spell_anti_magic_points)
	set(value):
		_ensure_enemy_domain()
		domain_model.direct_spell_anti_magic_points = _enemy_ports.to_domain(value)

var direct_spell_magic_defense_min: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.direct_spell_magic_defense_min)
	set(value):
		_ensure_enemy_domain()
		domain_model.direct_spell_magic_defense_min = _enemy_ports.to_domain(value)

var direct_spell_magic_defense_max: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.direct_spell_magic_defense_max)
	set(value):
		_ensure_enemy_domain()
		domain_model.direct_spell_magic_defense_max = _enemy_ports.to_domain(value)

var agility: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.agility)
	set(value):
		_ensure_enemy_domain()
		domain_model.agility = _enemy_ports.to_domain(value)

var accuracy: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.accuracy)
	set(value):
		_ensure_enemy_domain()
		domain_model.accuracy = _enemy_ports.to_domain(value)

var life_type: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.life_type)
	set(value):
		_ensure_enemy_domain()
		domain_model.life_type = _enemy_ports.to_domain(value)

var undead: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.undead)
	set(value):
		_ensure_enemy_domain()
		domain_model.undead = _enemy_ports.to_domain(value)

var _feature_capabilities: RefCounted:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._feature_capabilities)
	set(value):
		_ensure_enemy_domain()
		domain_model._feature_capabilities = _enemy_ports.to_domain(value)

const CANONICAL_PERCEPTION_SOURCE := "hc.source.monster.canonical.perception"
var anti_stealth: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.anti_stealth)
	set(value):
		_ensure_enemy_domain()
		domain_model.anti_stealth = _enemy_ports.to_domain(value)

var anti_poison: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.anti_poison)
	set(value):
		_ensure_enemy_domain()
		domain_model.anti_poison = _enemy_ports.to_domain(value)

var level: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.level)
	set(value):
		_ensure_enemy_domain()
		domain_model.level = _enemy_ports.to_domain(value)

var move_speed_gu_per_sec: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.move_speed_gu_per_sec)
	set(value):
		_ensure_enemy_domain()
		domain_model.move_speed_gu_per_sec = _enemy_ports.to_domain(value)

var aggro_radius_gu: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.aggro_radius_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model.aggro_radius_gu = _enemy_ports.to_domain(value)

var attack_range_gu: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.attack_range_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model.attack_range_gu = _enemy_ports.to_domain(value)

var target: Node2D:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.target)
	set(value):
		_ensure_enemy_domain()
		domain_model.target = _enemy_ports.to_domain(value)

var primary_target: PlayerCharacter:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.primary_target)
	set(value):
		_ensure_enemy_domain()
		domain_model.primary_target = _enemy_ports.to_domain(value)

var is_boss: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.is_boss)
	set(value):
		_ensure_enemy_domain()
		domain_model.is_boss = _enemy_ports.to_domain(value)

var runtime_map_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.runtime_map_id)
	set(value):
		_ensure_enemy_domain()
		domain_model.runtime_map_id = _enemy_ports.to_domain(value)

var runtime_ground_gu_to_screen_position_px: Callable:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.runtime_ground_gu_to_screen_position_px)
	set(value):
		_ensure_enemy_domain()
		domain_model.runtime_ground_gu_to_screen_position_px = _enemy_ports.to_domain(value)

var runtime_screen_to_ground_position_px: Callable:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.runtime_screen_to_ground_position_px)
	set(value):
		_ensure_enemy_domain()
		domain_model.runtime_screen_to_ground_position_px = _enemy_ports.to_domain(value)

var combat_spatial_index: RuntimeCombatSpatialIndexScript:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.combat_spatial_index)
	set(value):
		_ensure_enemy_domain()
		domain_model.combat_spatial_index = _enemy_ports.to_domain(value)

var spatial_actor_runtime_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.spatial_actor_runtime_id)
	set(value):
		_ensure_enemy_domain()
		domain_model.spatial_actor_runtime_id = _enemy_ports.to_domain(value)

var missing_projection_rejection_count: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.missing_projection_rejection_count)
	set(value):
		_ensure_enemy_domain()
		domain_model.missing_projection_rejection_count = _enemy_ports.to_domain(value)

var projection_rejection_reason: StringName:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.projection_rejection_reason)
	set(value):
		_ensure_enemy_domain()
		domain_model.projection_rejection_reason = _enemy_ports.to_domain(value)

var poison_time: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.poison_time)
	set(value):
		_ensure_enemy_domain()
		domain_model.poison_time = _enemy_ports.to_domain(value)

var poison_damage: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.poison_damage)
	set(value):
		_ensure_enemy_domain()
		domain_model.poison_damage = _enemy_ports.to_domain(value)

var poison_tick_interval_seconds: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.poison_tick_interval_seconds)
	set(value):
		_ensure_enemy_domain()
		domain_model.poison_tick_interval_seconds = _enemy_ports.to_domain(value)

var poison_tick_elapsed_seconds: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.poison_tick_elapsed_seconds)
	set(value):
		_ensure_enemy_domain()
		domain_model.poison_tick_elapsed_seconds = _enemy_ports.to_domain(value)

var control_time: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.control_time)
	set(value):
		_ensure_enemy_domain()
		domain_model.control_time = _enemy_ports.to_domain(value)

var charm_time: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.charm_time)
	set(value):
		_ensure_enemy_domain()
		domain_model.charm_time = _enemy_ports.to_domain(value)

var dormant: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.dormant)
	set(value):
		_ensure_enemy_domain()
		domain_model.dormant = _enemy_ports.to_domain(value)

var life_steal_ratio: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.life_steal_ratio)
	set(value):
		_ensure_enemy_domain()
		domain_model.life_steal_ratio = _enemy_ports.to_domain(value)

var control_on_hit_seconds: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.control_on_hit_seconds)
	set(value):
		_ensure_enemy_domain()
		domain_model.control_on_hit_seconds = _enemy_ports.to_domain(value)

var control_chance_denominator_base: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.control_chance_denominator_base)
	set(value):
		_ensure_enemy_domain()
		domain_model.control_chance_denominator_base = _enemy_ports.to_domain(value)

var is_targeted: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.is_targeted)
	set(value):
		_ensure_enemy_domain()
		domain_model.is_targeted = _enemy_ports.to_domain(value)

var facing: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.facing)
	set(value):
		_ensure_enemy_domain()
		domain_model.facing = _enemy_ports.to_domain(value)

var movement_facing: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.movement_facing)
	set(value):
		_ensure_enemy_domain()
		domain_model.movement_facing = _enemy_ports.to_domain(value)

var visual: MonsterVisual
var name_label: Label
var overhead: Variant
var ground_runtime_diagnostic_overlay: Node2D
var combat_radius_gu: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.combat_radius_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model.combat_radius_gu = _enemy_ports.to_domain(value)

var collision_radius_px: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.collision_radius_px)
	set(value):
		_ensure_enemy_domain()
		domain_model.collision_radius_px = _enemy_ports.to_domain(value)

var combat_body_profile: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.combat_body_profile)
	set(value):
		_ensure_enemy_domain()
		domain_model.combat_body_profile = _enemy_ports.to_domain(value)

var environment_blocker: Node:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.environment_blocker)
	set(value):
		_ensure_enemy_domain()
		domain_model.environment_blocker = _enemy_ports.to_domain(value)

var _dying: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._dying)
	set(value):
		_ensure_enemy_domain()
		domain_model._dying = _enemy_ports.to_domain(value)

var _death_pending: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._death_pending)
	set(value):
		_ensure_enemy_domain()
		domain_model._death_pending = _enemy_ports.to_domain(value)

var boss_rule: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.boss_rule)
	set(value):
		_ensure_enemy_domain()
		domain_model.boss_rule = _enemy_ports.to_domain(value)

var behavior_profile: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.behavior_profile)
	set(value):
		_ensure_enemy_domain()
		domain_model.behavior_profile = _enemy_ports.to_domain(value)

var _published_birth_inputs: RefCounted:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._published_birth_inputs)
	set(value):
		_ensure_enemy_domain()
		domain_model._published_birth_inputs = _enemy_ports.to_domain(value)

var combat_enabled: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.combat_enabled)
	set(value):
		_ensure_enemy_domain()
		domain_model.combat_enabled = _enemy_ports.to_domain(value)

var service_ai_code: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.service_ai_code)
	set(value):
		_ensure_enemy_domain()
		domain_model.service_ai_code = _enemy_ports.to_domain(value)

var service_move_interval_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.service_move_interval_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model.service_move_interval_ms = _enemy_ports.to_domain(value)

var stationary: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.stationary)
	set(value):
		_ensure_enemy_domain()
		domain_model.stationary = _enemy_ports.to_domain(value)

var area_attack_rule: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.area_attack_rule)
	set(value):
		_ensure_enemy_domain()
		domain_model.area_attack_rule = _enemy_ports.to_domain(value)

var summon_rule: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.summon_rule)
	set(value):
		_ensure_enemy_domain()
		domain_model.summon_rule = _enemy_ports.to_domain(value)

var attack_delivery_rule: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.attack_delivery_rule)
	set(value):
		_ensure_enemy_domain()
		domain_model.attack_delivery_rule = _enemy_ports.to_domain(value)

var _attack_timer: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_timer = _enemy_ports.to_domain(value)

var _attack_interval: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_interval)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_interval = _enemy_ports.to_domain(value)

var _attack_animation_duration: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_animation_duration)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_animation_duration = _enemy_ports.to_domain(value)

var _attack_hit_delay: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_hit_delay)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_hit_delay = _enemy_ports.to_domain(value)

var _pending_attack_time: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pending_attack_time)
	set(value):
		_ensure_enemy_domain()
		domain_model._pending_attack_time = _enemy_ports.to_domain(value)

var _pending_attack_damage: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pending_attack_damage)
	set(value):
		_ensure_enemy_domain()
		domain_model._pending_attack_damage = _enemy_ports.to_domain(value)

var _pending_attack_target: Node2D:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pending_attack_target)
	set(value):
		_ensure_enemy_domain()
		domain_model._pending_attack_target = _enemy_ports.to_domain(value)

var _pending_attack_release_record: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pending_attack_release_record)
	set(value):
		_ensure_enemy_domain()
		domain_model._pending_attack_release_record = _enemy_ports.to_domain(value)

var last_magic_attack_resolution: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.last_magic_attack_resolution)
	set(value):
		_ensure_enemy_domain()
		domain_model.last_magic_attack_resolution = _enemy_ports.to_domain(value)

var last_physical_hit_resolution: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.last_physical_hit_resolution)
	set(value):
		_ensure_enemy_domain()
		domain_model.last_physical_hit_resolution = _enemy_ports.to_domain(value)

var last_special_delivery_accuracy_resolution: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.last_special_delivery_accuracy_resolution)
	set(value):
		_ensure_enemy_domain()
		domain_model.last_special_delivery_accuracy_resolution = _enemy_ports.to_domain(value)

var _retarget_timer: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._retarget_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._retarget_timer = _enemy_ports.to_domain(value)

var _target_stable_remaining_seconds: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_stable_remaining_seconds)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_stable_remaining_seconds = _enemy_ports.to_domain(value)

var _crowd_steering_timer: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._crowd_steering_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._crowd_steering_timer = _enemy_ports.to_domain(value)

var _cached_crowd_separation: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._cached_crowd_separation)
	set(value):
		_ensure_enemy_domain()
		domain_model._cached_crowd_separation = _enemy_ports.to_domain(value)

var _crowd_neighbor_scratch: Array[Node]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._crowd_neighbor_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._crowd_neighbor_scratch = _enemy_ports.to_domain(value)

var _safe_zone_candidate_stamp: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._safe_zone_candidate_stamp)
	set(value):
		_ensure_enemy_domain()
		domain_model._safe_zone_candidate_stamp = _enemy_ports.to_domain(value)

var _background_ai_timer: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_ai_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_ai_timer = _enemy_ports.to_domain(value)

var _background_wakeup_timer: Timer:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_wakeup_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_wakeup_timer = _enemy_ports.to_domain(value)

var _background_deep_sleeping: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_deep_sleeping)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_deep_sleeping = _enemy_ports.to_domain(value)

var _background_last_wakeup_game_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_last_wakeup_game_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_last_wakeup_game_s = _enemy_ports.to_domain(value)

var _background_maintenance_running: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_maintenance_running)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_maintenance_running = _enemy_ports.to_domain(value)

var _background_accumulated_delta: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._background_accumulated_delta)
	set(value):
		_ensure_enemy_domain()
		domain_model._background_accumulated_delta = _enemy_ports.to_domain(value)

var _passive_wake_pending: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_wake_pending)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_wake_pending = _enemy_ports.to_domain(value)

var _passive_wake_candidate_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_wake_candidate_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_wake_candidate_id = _enemy_ports.to_domain(value)

var _passive_wake_candidate_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_wake_candidate_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_wake_candidate_life = _enemy_ports.to_domain(value)

var _passive_wake_candidate_map_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_wake_candidate_map_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_wake_candidate_map_id = _enemy_ports.to_domain(value)

var _passive_wake_candidate_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_wake_candidate_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_wake_candidate_generation = _enemy_ports.to_domain(value)

var _passive_mode_active: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._passive_mode_active)
	set(value):
		_ensure_enemy_domain()
		domain_model._passive_mode_active = _enemy_ports.to_domain(value)

var _boss_skill_cooldown: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_skill_cooldown)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_skill_cooldown = _enemy_ports.to_domain(value)

var _boss_warning: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_warning)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_warning = _enemy_ports.to_domain(value)

var _boss_phase_two: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_phase_two)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_phase_two = _enemy_ports.to_domain(value)

var _boss_phase_enabled: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_phase_enabled)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_phase_enabled = _enemy_ports.to_domain(value)

var _boss_skill_enabled: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_skill_enabled)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_skill_enabled = _enemy_ports.to_domain(value)

var _boss_skill_direction_ground: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_skill_direction_ground)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_skill_direction_ground = _enemy_ports.to_domain(value)

var _boss_skill_footprint_snapshot: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_skill_footprint_snapshot)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_skill_footprint_snapshot = _enemy_ports.to_domain(value)

var _last_boss_skill_hit: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_boss_skill_hit)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_boss_skill_hit = _enemy_ports.to_domain(value)

var _boss_health_stage: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_health_stage)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_health_stage = _enemy_ports.to_domain(value)

var _boss_rage_health_stage: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_rage_health_stage)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_rage_health_stage = _enemy_ports.to_domain(value)

var _boss_search_clock_anchor_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_search_clock_anchor_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_search_clock_anchor_s = _enemy_ports.to_domain(value)

var _boss_rage_time: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_rage_time)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_rage_time = _enemy_ports.to_domain(value)

var _boss_base_move_speed_gu_per_sec: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_base_move_speed_gu_per_sec)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_base_move_speed_gu_per_sec = _enemy_ports.to_domain(value)

var _boss_base_attack_interval: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_base_attack_interval)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_base_attack_interval = _enemy_ports.to_domain(value)

var _burrowed: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._burrowed)
	set(value):
		_ensure_enemy_domain()
		domain_model._burrowed = _enemy_ports.to_domain(value)

var _rng: RandomNumberGenerator:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._rng)
	set(value):
		_ensure_enemy_domain()
		domain_model._rng = _enemy_ports.to_domain(value)

var _audio_rng: RandomNumberGenerator
var _audio_rng_initialized := false
var _audio_appear_emitted := false
var _audio_death_emitted := false
var _audio_combat_session_active := false
## This is the gameplay-entry latch, not a playback-success flag. Once the
## actor has crossed the real target edge, an audio rejection is still a
## completed entry attempt; retry only after a real disengagement.
var _audio_combat_entry_seen := false
var _audio_combat_session_serial := 0
var _audio_owner_key := ""
var _audio_attack_sequence := 0
var _audio_attack_frame_sequence := -1
# HC-MONSTER-COMBAT-R2 T3: true once the attack STATE was observed for the
# current audio sequence; gates the cold/hot frame-sound recovery so a
# monster without attack art stays silent.
var _audio_attack_presented_seen := false
# HC-MONSTER-COMBAT-R2 T3: parent action identity of the attack that committed
# most recently. The presentation, the audio stream and the delayed release
# all bind to this one serial and its logic start timestamp.
var _attack_logic_serial: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_logic_serial)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_logic_serial = _enemy_ports.to_domain(value)

var _attack_logic_started_at_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_logic_started_at_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_logic_started_at_ms = _enemy_ports.to_domain(value)

var _combat_action_time_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._combat_action_time_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._combat_action_time_s = _enemy_ports.to_domain(value)

var _attack_action_start_time_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_action_start_time_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_action_start_time_s = _enemy_ports.to_domain(value)

var _attack_action_duration_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_action_duration_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_action_duration_s = _enemy_ports.to_domain(value)

var _attack_action_source_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_action_source_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_action_source_life = _enemy_ports.to_domain(value)

var _attack_action_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_action_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_action_generation = _enemy_ports.to_domain(value)

var _attack_action_active: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_action_active)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_action_active = _enemy_ports.to_domain(value)

var _source176_decision_serial: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_serial)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_serial = _enemy_ports.to_domain(value)

var _source176_pursuit_permission: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_pursuit_permission)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_pursuit_permission = _enemy_ports.to_domain(value)

var _source176_decision_now_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_now_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_now_ms = _enemy_ports.to_domain(value)

var _source176_decision_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_tick = _enemy_ports.to_domain(value)

var _source176_decision_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_generation = _enemy_ports.to_domain(value)

var _source176_decision_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_life = _enemy_ports.to_domain(value)

var _source176_decision_granted: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source176_decision_granted)
	set(value):
		_ensure_enemy_domain()
		domain_model._source176_decision_granted = _enemy_ports.to_domain(value)

var _source_committed_step_serial: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._source_committed_step_serial)
	set(value):
		_ensure_enemy_domain()
		domain_model._source_committed_step_serial = _enemy_ports.to_domain(value)

var _pursuit_process_budget_handles: Array[Dictionary]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pursuit_process_budget_handles)
	set(value):
		_ensure_enemy_domain()
		domain_model._pursuit_process_budget_handles = _enemy_ports.to_domain(value)

var _pursuit_observation_deferred: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._pursuit_observation_deferred)
	set(value):
		_ensure_enemy_domain()
		domain_model._pursuit_observation_deferred = _enemy_ports.to_domain(value)

static var _pursuit_process_budget_mode: String:
	get: return EnemyLegacyContext.owner_context().shared._pursuit_process_budget_mode
	set(value): EnemyLegacyContext.owner_context().shared._pursuit_process_budget_mode = value

static var _pursuit_process_budget_stats: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._pursuit_process_budget_stats
	set(value): EnemyLegacyContext.owner_context().shared._pursuit_process_budget_stats = value

static var _new_step_decision_interval_ms: int:
	get: return EnemyLegacyContext.owner_context().shared._new_step_decision_interval_ms
	set(value): EnemyLegacyContext.owner_context().shared._new_step_decision_interval_ms = value

static func _hardcore_int_setting(path: String, fallback: int, allowed: Array[int]) -> int:
	return EnemyLegacyContext.owner_context().shared._hardcore_int_setting(path, fallback, allowed)

static func _hardcore_bool_setting(path: String, fallback: bool) -> bool:
	return EnemyLegacyContext.owner_context().shared._hardcore_bool_setting(path, fallback)

static var _owner_decision_interval_ms: Variant:
	get: return EnemyLegacyContext.owner_context().shared._owner_decision_interval_ms
	set(value): EnemyLegacyContext.owner_context().shared._owner_decision_interval_ms = value

static var _owner_optional_budget_enabled: Variant:
	get: return EnemyLegacyContext.owner_context().shared._owner_optional_budget_enabled
	set(value): EnemyLegacyContext.owner_context().shared._owner_optional_budget_enabled = value

static var _ordinary_contact_instant_settle_enabled: Variant:
	get: return EnemyLegacyContext.owner_context().shared._ordinary_contact_instant_settle_enabled
	set(value): EnemyLegacyContext.owner_context().shared._ordinary_contact_instant_settle_enabled = value

static var _ordinary_attack_visual_move_override_enabled: Variant:
	get: return EnemyLegacyContext.owner_context().shared._ordinary_attack_visual_move_override_enabled
	set(value): EnemyLegacyContext.owner_context().shared._ordinary_attack_visual_move_override_enabled = value

static var _residual_phase_probe_enabled: bool:
	get: return EnemyLegacyContext.owner_context().shared._residual_phase_probe_enabled
	set(value): EnemyLegacyContext.owner_context().shared._residual_phase_probe_enabled = value

static var _residual_phase_probe_totals: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._residual_phase_probe_totals
	set(value): EnemyLegacyContext.owner_context().shared._residual_phase_probe_totals = value

static var _residual_phase_probe_calls: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._residual_phase_probe_calls
	set(value): EnemyLegacyContext.owner_context().shared._residual_phase_probe_calls = value

static var _residual_phase_probe_source: String:
	get: return EnemyLegacyContext.owner_context().shared._residual_phase_probe_source
	set(value): EnemyLegacyContext.owner_context().shared._residual_phase_probe_source = value

var _new_step_decision_next_time_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._new_step_decision_next_time_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._new_step_decision_next_time_s = _enemy_ports.to_domain(value)

var _owner_decision_next_time_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_decision_next_time_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_decision_next_time_s = _enemy_ports.to_domain(value)

var _owner_decision_last_physics_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_decision_last_physics_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_decision_last_physics_tick = _enemy_ports.to_domain(value)

var _owner_decision_granted_physics_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_decision_granted_physics_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_decision_granted_physics_tick = _enemy_ports.to_domain(value)

var _owner_attack_prefilter_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_attack_prefilter_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_attack_prefilter_tick = _enemy_ports.to_domain(value)

var _owner_attack_prefilter_reached: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_attack_prefilter_reached)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_attack_prefilter_reached = _enemy_ports.to_domain(value)

var _owner_attack_prefilter_position: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_attack_prefilter_position)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_attack_prefilter_position = _enemy_ports.to_domain(value)

var _owner_attack_prefilter_target_position: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_attack_prefilter_target_position)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_attack_prefilter_target_position = _enemy_ports.to_domain(value)

var _owner_attack_prefilter_target_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_attack_prefilter_target_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_attack_prefilter_target_id = _enemy_ports.to_domain(value)

var _owner_decision_served_physics_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_decision_served_physics_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_decision_served_physics_tick = _enemy_ports.to_domain(value)

var _owner_decision_committed_physics_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_decision_committed_physics_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_decision_committed_physics_tick = _enemy_ports.to_domain(value)

var _owner_optional_budget_token: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_optional_budget_token)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_optional_budget_token = _enemy_ports.to_domain(value)

var _owner_optional_budget_reused: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_optional_budget_reused)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_optional_budget_reused = _enemy_ports.to_domain(value)

var _owner_optional_budget_suspended: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._owner_optional_budget_suspended)
	set(value):
		_ensure_enemy_domain()
		domain_model._owner_optional_budget_suspended = _enemy_ports.to_domain(value)

var _residual_phase_name: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._residual_phase_name)
	set(value):
		_ensure_enemy_domain()
		domain_model._residual_phase_name = _enemy_ports.to_domain(value)

var _residual_phase_started_usec: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._residual_phase_started_usec)
	set(value):
		_ensure_enemy_domain()
		domain_model._residual_phase_started_usec = _enemy_ports.to_domain(value)

var _last_body_action_commit_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_body_action_commit_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_body_action_commit_tick = _enemy_ports.to_domain(value)

var _canonical_attack_frames: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._canonical_attack_frames)
	set(value):
		_ensure_enemy_domain()
		domain_model._canonical_attack_frames = _enemy_ports.to_domain(value)

var _canonical_attack_frame_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._canonical_attack_frame_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._canonical_attack_frame_ms = _enemy_ports.to_domain(value)

func _try_reserve_source_body_action(incompatible_pending: bool) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_try_reserve_source_body_action", [_enemy_ports.to_domain(incompatible_pending)]))

var _body_admission_resolved: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._body_admission_resolved)
	set(value):
		_ensure_enemy_domain()
		domain_model._body_admission_resolved = _enemy_ports.to_domain(value)

var _body_admission_rejected: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._body_admission_rejected)
	set(value):
		_ensure_enemy_domain()
		domain_model._body_admission_rejected = _enemy_ports.to_domain(value)

var _body_collision_shape: CollisionShape2D = null
# R3 W1: the most recent release record built at a real admission point,
# including its parent action identity (review/verification handle).
var _last_hc_release_record: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_hc_release_record)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_hc_release_record = _enemy_ports.to_domain(value)

var _audio_attack_frame_ready := false
var _audio_attack_start_accepted := false
var _audio_combat_epoch_target_instance_id := 0
var _audio_combat_epoch_method_available := false
var _audio_combat_epoch_property_available := false
var _audio_combat_epoch_probe_complete := false
var _audio_combat_epoch_property_probe_count := 0
var _audio_previous_visual_state := ""
var _audio_previous_visual_frame := -1
var _audio_previous_facing := Vector2.INF
## Spawn presentation uses an instance-local RNG so the one-time direction
## choice cannot advance combat, loot, summon, or status-effect randomness.
var _spawn_facing_rng: RandomNumberGenerator:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._spawn_facing_rng)
	set(value):
		_ensure_enemy_domain()
		domain_model._spawn_facing_rng = _enemy_ports.to_domain(value)

var _spawn_facing_seed_override: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._spawn_facing_seed_override)
	set(value):
		_ensure_enemy_domain()
		domain_model._spawn_facing_seed_override = _enemy_ports.to_domain(value)

var _spawn_facing_seed_override_active: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._spawn_facing_seed_override_active)
	set(value):
		_ensure_enemy_domain()
		domain_model._spawn_facing_seed_override_active = _enemy_ports.to_domain(value)

var _spawn_facing_initialized: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._spawn_facing_initialized)
	set(value):
		_ensure_enemy_domain()
		domain_model._spawn_facing_initialized = _enemy_ports.to_domain(value)

var _threat_table: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._threat_table)
	set(value):
		_ensure_enemy_domain()
		domain_model._threat_table = _enemy_ports.to_domain(value)

var _threat_decay_per_second: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._threat_decay_per_second)
	set(value):
		_ensure_enemy_domain()
		domain_model._threat_decay_per_second = _enemy_ports.to_domain(value)

var _leash_multiplier: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._leash_multiplier)
	set(value):
		_ensure_enemy_domain()
		domain_model._leash_multiplier = _enemy_ports.to_domain(value)

var _control_anchor_ground_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._control_anchor_ground_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._control_anchor_ground_gu = _enemy_ports.to_domain(value)

var _entrapment_controller: EntrapmentBoundaryControllerScript:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._entrapment_controller)
	set(value):
		_ensure_enemy_domain()
		domain_model._entrapment_controller = _enemy_ports.to_domain(value)

var _entrapment_last_end_reason: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._entrapment_last_end_reason)
	set(value):
		_ensure_enemy_domain()
		domain_model._entrapment_last_end_reason = _enemy_ports.to_domain(value)

var _area_attack_cooldown: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_attack_cooldown)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_attack_cooldown = _enemy_ports.to_domain(value)

var _area_attack_warning: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_attack_warning)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_attack_warning = _enemy_ports.to_domain(value)

var _area_attack_footprint_snapshot: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_attack_footprint_snapshot)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_attack_footprint_snapshot = _enemy_ports.to_domain(value)

var _area_attack_release_records: Array[Dictionary]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_attack_release_records)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_attack_release_records = _enemy_ports.to_domain(value)

var _area_magic_warning: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_magic_warning)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_magic_warning = _enemy_ports.to_domain(value)

var _area_magic_footprint_snapshot: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_magic_footprint_snapshot)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_magic_footprint_snapshot = _enemy_ports.to_domain(value)

var _area_magic_release_records: Array[Dictionary]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._area_magic_release_records)
	set(value):
		_ensure_enemy_domain()
		domain_model._area_magic_release_records = _enemy_ports.to_domain(value)

var _last_attack_footprint_snapshot: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_attack_footprint_snapshot)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_attack_footprint_snapshot = _enemy_ports.to_domain(value)

var _spatial_release_serial: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._spatial_release_serial)
	set(value):
		_ensure_enemy_domain()
		domain_model._spatial_release_serial = _enemy_ports.to_domain(value)

var _special_delivery_settled_targets: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._special_delivery_settled_targets)
	set(value):
		_ensure_enemy_domain()
		domain_model._special_delivery_settled_targets = _enemy_ports.to_domain(value)

var _special_delivery_settlement_order: Array[Dictionary]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._special_delivery_settlement_order)
	set(value):
		_ensure_enemy_domain()
		domain_model._special_delivery_settlement_order = _enemy_ports.to_domain(value)

var _special_delivery_settlement_floor_serial: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._special_delivery_settlement_floor_serial)
	set(value):
		_ensure_enemy_domain()
		domain_model._special_delivery_settlement_floor_serial = _enemy_ports.to_domain(value)

var _summon_cooldown: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._summon_cooldown)
	set(value):
		_ensure_enemy_domain()
		domain_model._summon_cooldown = _enemy_ports.to_domain(value)

var _summon_warning: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._summon_warning)
	set(value):
		_ensure_enemy_domain()
		domain_model._summon_warning = _enemy_ports.to_domain(value)

var _environment_guard_timer: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._environment_guard_timer)
	set(value):
		_ensure_enemy_domain()
		domain_model._environment_guard_timer = _enemy_ports.to_domain(value)

var _last_environment_safe_position_px: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_environment_safe_position_px)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_environment_safe_position_px = _enemy_ports.to_domain(value)

var _attack_los_cache: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_los_cache)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_los_cache = _enemy_ports.to_domain(value)

var _last_spatial_index_screen_position_px: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_screen_position_px)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_screen_position_px = _enemy_ports.to_domain(value)

var _last_spatial_index_ground_position_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_ground_position_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_ground_position_gu = _enemy_ports.to_domain(value)

var _last_spatial_index_runtime_map_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_runtime_map_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_runtime_map_id = _enemy_ports.to_domain(value)

var _last_spatial_index_zone_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_zone_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_zone_generation = _enemy_ports.to_domain(value)

var _last_spatial_index_environment_revision: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_environment_revision)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_environment_revision = _enemy_ports.to_domain(value)

var _last_spatial_index_projection: Callable:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_spatial_index_projection)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_spatial_index_projection = _enemy_ports.to_domain(value)

var _target_ground_cache_physics_frame: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_physics_frame)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_physics_frame = _enemy_ports.to_domain(value)

var _target_ground_cache_target_instance_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_target_instance_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_target_instance_id = _enemy_ports.to_domain(value)

var _target_ground_cache_target_screen_position_px: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_target_screen_position_px)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_target_screen_position_px = _enemy_ports.to_domain(value)

var _target_ground_cache_ground_position_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_ground_position_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_ground_position_gu = _enemy_ports.to_domain(value)

var _target_ground_cache_runtime_map_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_runtime_map_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_runtime_map_id = _enemy_ports.to_domain(value)

var _target_ground_cache_zone_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_zone_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_zone_generation = _enemy_ports.to_domain(value)

var _target_ground_cache_projection: Callable:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_ground_cache_projection)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_ground_cache_projection = _enemy_ports.to_domain(value)

var _target_grid_candidate_scratch: Array[Dictionary]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_grid_candidate_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_grid_candidate_scratch = _enemy_ports.to_domain(value)

var _target_grid_candidate_seen: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_grid_candidate_seen)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_grid_candidate_seen = _enemy_ports.to_domain(value)

var actual_ground_motion_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model.actual_ground_motion_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model.actual_ground_motion_gu = _enemy_ports.to_domain(value)

var _movement_cadence: Variant:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_cadence)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_cadence = _enemy_ports.to_domain(value)

var _natural_regen: RefCounted:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._natural_regen)
	set(value):
		_ensure_enemy_domain()
		domain_model._natural_regen = _enemy_ports.to_domain(value)

var _target_acquisition_policy: MonsterTargetAcquisitionPolicyScript:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_acquisition_policy)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_acquisition_policy = _enemy_ports.to_domain(value)

var _target_acquisition_authority_failed_closed: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_acquisition_authority_failed_closed)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_acquisition_authority_failed_closed = _enemy_ports.to_domain(value)

var _target_focus_timeout_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_focus_timeout_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_focus_timeout_ms = _enemy_ports.to_domain(value)

var _target_disengage_axis_cells: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_disengage_axis_cells)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_disengage_axis_cells = _enemy_ports.to_domain(value)

var _target_focus_tick_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._target_focus_tick_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._target_focus_tick_ms = _enemy_ports.to_domain(value)

var _movement_authority_failed_closed: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_authority_failed_closed)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_authority_failed_closed = _enemy_ports.to_domain(value)

var _movement_step_active: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_active)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_active = _enemy_ports.to_domain(value)

var _struck_pause_in_tick_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._struck_pause_in_tick_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._struck_pause_in_tick_s = _enemy_ports.to_domain(value)

var _boss_warning_advanced_this_tick: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._boss_warning_advanced_this_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._boss_warning_advanced_this_tick = _enemy_ports.to_domain(value)

var _movement_step_epoch: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_epoch)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_epoch = _enemy_ports.to_domain(value)

var _movement_step_start_ground_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_start_ground_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_start_ground_gu = _enemy_ports.to_domain(value)

var _movement_step_start_screen_px: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_start_screen_px)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_start_screen_px = _enemy_ports.to_domain(value)

var _movement_step_target_ground_gu: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_target_ground_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_target_ground_gu = _enemy_ports.to_domain(value)

var _movement_step_legs: PackedVector2Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_legs)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_legs = _enemy_ports.to_domain(value)

var _movement_step_leg_index: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_leg_index)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_leg_index = _enemy_ports.to_domain(value)

var _movement_step_distance_gu: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_distance_gu)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_distance_gu = _enemy_ports.to_domain(value)

var _movement_step_neighbor: Vector2i:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_neighbor)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_neighbor = _enemy_ports.to_domain(value)

var _movement_step_engagement_target_instance_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_engagement_target_instance_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_engagement_target_instance_id = _enemy_ports.to_domain(value)

var _movement_step_speed_scale: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_speed_scale)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_speed_scale = _enemy_ports.to_domain(value)

var _movement_step_reason: StringName:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._movement_step_reason)
	set(value):
		_ensure_enemy_domain()
		domain_model._movement_step_reason = _enemy_ports.to_domain(value)

var _continuous_pursuit_active: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._continuous_pursuit_active)
	set(value):
		_ensure_enemy_domain()
		domain_model._continuous_pursuit_active = _enemy_ports.to_domain(value)

var _continuous_pursuit_speed_scale: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._continuous_pursuit_speed_scale)
	set(value):
		_ensure_enemy_domain()
		domain_model._continuous_pursuit_speed_scale = _enemy_ports.to_domain(value)

var _terrain_navigation_context: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_navigation_context)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_navigation_context = _enemy_ports.to_domain(value)

var _terrain_path_waypoints: Array[Vector2i]:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_path_waypoints)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_path_waypoints = _enemy_ports.to_domain(value)

var _terrain_path_target_instance_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_path_target_instance_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_path_target_instance_id = _enemy_ports.to_domain(value)

var _terrain_path_target_cell: Vector2i:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_path_target_cell)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_path_target_cell = _enemy_ports.to_domain(value)

var _terrain_path_has_target_cell: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_path_has_target_cell)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_path_has_target_cell = _enemy_ports.to_domain(value)

var _terrain_no_path_until_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_no_path_until_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_no_path_until_ms = _enemy_ports.to_domain(value)

var _terrain_failed_cell: Vector2i:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_failed_cell)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_failed_cell = _enemy_ports.to_domain(value)

var _terrain_has_failed_cell: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_has_failed_cell)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_has_failed_cell = _enemy_ports.to_domain(value)

var _terrain_failed_cell_until_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._terrain_failed_cell_until_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._terrain_failed_cell_until_ms = _enemy_ports.to_domain(value)

var _last_damaging_pet: WeakRef:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._last_damaging_pet)
	set(value):
		_ensure_enemy_domain()
		domain_model._last_damaging_pet = _enemy_ports.to_domain(value)

func published_monster_inputs_view() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("published_monster_inputs_view", []))

func setup(data: Dictionary, player_target: PlayerCharacter, caller_boss := false, inputs: RefCounted = null) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("setup", [_enemy_ports.to_domain(data), _enemy_ports.to_domain(player_target), _enemy_ports.to_domain(caller_boss), _enemy_ports.to_domain(inputs)]))

func _reset_monster_audio_observer() -> void:
	_retire_cached_audio_owner()
	_audio_appear_emitted = false
	_audio_death_emitted = false
	_audio_combat_session_active = false
	_audio_combat_entry_seen = false
	_audio_combat_session_serial = 0
	_audio_owner_key = ""
	_audio_attack_sequence = 0
	_audio_attack_frame_sequence = -1
	_audio_attack_frame_ready = false
	_audio_attack_start_accepted = false
	_audio_combat_epoch_target_instance_id = 0
	_audio_combat_epoch_method_available = false
	_audio_combat_epoch_property_available = false
	_audio_combat_epoch_probe_complete = false
	_audio_combat_epoch_property_probe_count = 0
	_audio_previous_visual_state = ""
	_audio_previous_visual_frame = -1
	_audio_previous_facing = Vector2.INF


func _retire_cached_audio_owner() -> void:
	if (
		_audio_owner_key.is_empty()
		or not is_instance_valid(_audio_runtime_service)
		or not _audio_runtime_service.has_method("retire_monster_audio_owner")
	):
		return
	_audio_runtime_service.call(
		"retire_monster_audio_owner",
		_audio_owner_key,
		get_instance_id(),
	)


## Test-only deterministic control for the presentation RNG.  Production
## callers never need this; importantly it never aliases `_rng`.
func set_audio_seed_for_test(seed_value: int) -> void:
	if _audio_rng == null:
		_audio_rng = RandomNumberGenerator.new()
	_audio_rng.seed = seed_value
	_audio_rng_initialized = true


## The service is resolved only when a semantic event is ready.  Successful
## lookups are shared by all EnemyActor instances. A miss installs one shared
## one-second negative cache so thousands of actors cannot group-scan every
## frame, while a later service (or a replacement after world teardown) is
## still discovered without a production reset hook.
func _audio_service() -> Node:
	if not is_inside_tree():
		return null
	if (
		is_instance_valid(_audio_runtime_service)
		and _audio_runtime_service.is_inside_tree()
		and _audio_runtime_service.get_tree() == get_tree()
	):
		return _audio_runtime_service
	_audio_runtime_service = null
	var now_msec := _audio_service_cache_now_msec()
	if now_msec < _audio_service_retry_after_msec:
		return null
	_audio_service_retry_after_msec = now_msec + AUDIO_SERVICE_NEGATIVE_CACHE_MSEC
	_audio_service_lookup_count += 1
	for candidate: Node in get_tree().get_nodes_in_group(&"audio_runtime_service"):
		if (
			is_instance_valid(candidate)
			and candidate.is_inside_tree()
			and candidate.has_method("play_monster_event")
		):
			_audio_runtime_service = candidate
			_audio_service_retry_after_msec = 0
			return candidate
	return null


static func _audio_service_cache_now_msec() -> int:
	return (
		_audio_service_now_override_msec
		if _audio_service_now_override_msec >= 0
		else Time.get_ticks_msec()
	)


static func set_audio_service_cache_clock_for_test(now_msec: int) -> void:
	_audio_service_now_override_msec = now_msec


static func audio_service_lookup_count_for_test() -> int:
	return _audio_service_lookup_count


func _audio_owner_key_for_actor() -> String:
	if _audio_owner_key.is_empty():
		_audio_owner_key = "monster:%d:%d" % [monster_id, get_instance_id()]
	return _audio_owner_key


func _audio_target_changed(_next_target: Node2D) -> void:
	# Compatibility only: discovery/combat-state sound is retired.
	return


func _audio_player_target() -> Node:
	if is_instance_valid(primary_target):
		return primary_target
	if is_instance_valid(target) and target is PlayerCharacter:
		return target
	return null


func _audio_combat_transition_is_active() -> bool:
	# W3 adds this optional player contract after the audio branch baseline. The
	# has_method guard keeps this branch compatible with the current checkout and
	# rejects audio before service admission once the method is present.
	var player_target := _audio_player_target()
	if player_target == null or not player_target.has_method("combat_transition_is_active"):
		return false
	var active: Variant = player_target.call("combat_transition_is_active")
	return active is bool and bool(active)


func _audio_combat_epoch() -> int:
	var player_target := _audio_player_target()
	if player_target == null:
		return -1
	var target_instance_id := player_target.get_instance_id()
	if (
		not _audio_combat_epoch_probe_complete
		or _audio_combat_epoch_target_instance_id != target_instance_id
	):
		_audio_combat_epoch_target_instance_id = target_instance_id
		_audio_combat_epoch_method_available = player_target.has_method("combat_epoch")
		_audio_combat_epoch_property_available = false
		_audio_combat_epoch_probe_complete = true
		if not _audio_combat_epoch_method_available:
			_audio_combat_epoch_property_probe_count += 1
			for property_info: Dictionary in player_target.get_property_list():
				if str(property_info.get("name", "")) == "combat_epoch":
					_audio_combat_epoch_property_available = true
					break
	var epoch: Variant = null
	if _audio_combat_epoch_method_available:
		epoch = player_target.call("combat_epoch")
	elif _audio_combat_epoch_property_available:
		epoch = player_target.get("combat_epoch")
	return int(epoch) if epoch is int or epoch is float else -1


func audio_combat_epoch_property_probe_count_for_test() -> int:
	return _audio_combat_epoch_property_probe_count


func _audio_is_listenable(allow_death := false) -> bool:
	if not is_inside_tree() or process_mode == Node.PROCESS_MODE_DISABLED:
		return false
	if _audio_combat_transition_is_active():
		return false
	if not allow_death and not is_physics_processing():
		return false
	if not visible or not is_visible_in_tree() or _background_deep_sleeping:
		return false
	if _burrowed and not allow_death:
		return false
	if not allow_death and (_dying or _death_pending or current_hp <= 0):
		return false
	var viewport := get_viewport()
	if viewport == null:
		return false
	# The viewport is the existing client listener/audibility boundary.  Do not
	# invent a second gameplay distance or wake off-screen actors for SFX.
	return viewport.get_visible_rect().has_point(
		get_global_transform_with_canvas().origin
	)


func _audio_context(semantic_event: String) -> Dictionary:
	var context := {
		"source": "enemy_actor",
		"monster_id": monster_id,
		"runtime_map_id": runtime_map_id,
		"semantic_event": semantic_event,
		"audio_owner_key": _audio_owner_key_for_actor(),
		"source_instance_id": get_instance_id(),
		"source_life": _hc_life(self),
	}
	var combat_epoch := _audio_combat_epoch()
	if combat_epoch >= 0:
		context["combat_epoch"] = combat_epoch
	if semantic_event in ["attack_start", "attack_frame"]:
		context["release_id"] = "attack:%d" % _audio_attack_sequence
	if semantic_event == "combat_prompt":
		context["session_id"] = "combat:%d" % _audio_combat_session_serial
	return context


func _emit_monster_audio(
	semantic_event: String,
	allow_death := false,
	context_overrides: Dictionary = {},
) -> bool:
	if not combat_enabled and semantic_event in ["combat_prompt", "attack_start", "attack_frame"]:
		return false
	if monster_id <= 0 or not _audio_is_listenable(allow_death):
		return false
	var service := _audio_service()
	if service == null:
		return false
	# The service owns exact ID mapping, resource availability, voice pooling
	# and fail-closed status.  EnemyActor never resolves names/appearances.
	var context := _audio_context(semantic_event)
	context.merge(context_overrides, true)
	var result: Variant = service.call(
		"play_monster_event",
		monster_id,
		semantic_event,
		context,
	)
	return result is Dictionary and str((result as Dictionary).get("status", "")) == "played"


func _emit_player_physical_contact(attacker: Node2D, damage_context: Dictionary) -> bool:
	if (
		str(damage_context.get("damage_kind", "")) != "player_physical"
		or not bool(damage_context.get("confirmed_hit", false))
		or not attacker is PlayerCharacter
		or not _audio_is_listenable()
	):
		return false
	var player_attacker := attacker as PlayerCharacter
	if (
		player_attacker.visual == null
		or not is_instance_valid(player_attacker.visual)
		or not player_attacker.visual.has_method("audio_classic_weapon_shape")
	):
		return false
	var classic_shape := int(player_attacker.visual.call("audio_classic_weapon_shape"))
	if classic_shape < 0:
		return false
	var service := _audio_service()
	if service == null or not service.has_method("play_player_physical_contact"):
		return false
	var context := _audio_context("player_physical_contact")
	context.merge(damage_context, true)
	context["classic_weapon_shape"] = classic_shape
	var result: Variant = service.call(
		"play_player_physical_contact",
		classic_shape,
		context,
	)
	return result is Dictionary and str((result as Dictionary).get("status", "")) == "played"


func _audio_try_emit_appear() -> void:
	# Compatibility shim for old test fixtures. Spawn/appear is intentionally
	# silent in the W4 production whitelist.
	return


func _audio_try_enter_combat_session() -> bool:
	# Compatibility only. No service lookup, context or session on pursuit.
	return false


func _audio_end_combat_session(_reason := "explicit_disengage") -> void:
	_audio_combat_session_active = false
	_audio_combat_entry_seen = false


func _audio_attack_started(action_serial := -1) -> void:
	if not combat_enabled:
		return
	# HC-MONSTER-COMBAT-R2 T3: the audio stream binds to the SAME parent
	# action identity as the presentation. The enemy allocates the serial at
	# the attack commit tick; presentation start and attack-start audio share
	# it, so a superseded action can neither emit nor replay audio.
	_audio_attack_sequence = action_serial if action_serial > 0 else _audio_attack_sequence + 1
	_audio_attack_frame_sequence = -1
	_audio_attack_frame_ready = false
	_audio_attack_start_accepted = false
	_audio_attack_presented_seen = false
	# Attack start is emitted only by accepted actions below, never by target
	# acquisition or an AI preview.
	_audio_attack_start_accepted = _emit_monster_audio("attack_start")


## HC-MONSTER-COMBAT-R3 W1: the parent action identity is allocated at the
## real admission point, BEFORE the release record is built and before any
## presentation is requested. The identity is a four-tuple anchored on the
## combat game clock: monotonic serial x source life x world generation, with
## `_attack_action_start_time_s` as the timing origin. Returns the serial.
## HC-MONSTER-COMBAT-R3 W1/W2: the single combat action clock. Advanced ONLY
## here (the Actor's own physics entry point calls it with exactly one physics
## delta): pause freezes it, background fast-path ticks accumulate to the same
## total. The active-action flag closes on the combat clock itself - it must
## not outlive the action's logical window.
func _advance_combat_action_clock(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_advance_combat_action_clock", [_enemy_ports.to_domain(delta)]))

func _allocate_attack_action(duration: float) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_allocate_attack_action", [_enemy_ports.to_domain(duration)]))

func _combat_action_time_getter() -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_combat_action_time_getter", []))

var _struck_paused_time_s: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._struck_paused_time_s)
	set(value):
		_ensure_enemy_domain()
		domain_model._struck_paused_time_s = _enemy_ports.to_domain(value)

func _movement_action_time_ms() -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_movement_action_time_ms", []))

func _play_attack_animation(duration: float, parent_action_id := -1) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_play_attack_animation", [_enemy_ports.to_domain(duration), _enemy_ports.to_domain(parent_action_id)]))

func _audio_observe_visual_state() -> void:
	# R14-B5: only observe MonsterVisual while this attack sequence's frame
	# audio is still pending. Once the frame sound has settled (or no accepted
	# attack is running), return immediately without touching the visual node.
	if _audio_attack_sequence <= 0 or _audio_attack_frame_sequence == _audio_attack_sequence:
		return
	if visual == null or not is_instance_valid(visual):
		return
	# HC-MONSTER-COMBAT-R3 W2: phase observation is bound to the CURRENT
	# parent action. Cached draw state that belongs to another action (or a
	# finished one) can never ready or commit THIS action's audio phases.
	if visual.current_attack_action_id() != _audio_attack_sequence:
		return
	# R3 W2: the strike phase crossing comes from the action's OWN logical
	# age, not from a drawn frame index. A rejected start sound does not
	# erase the phase - the marking happens before the callback, exactly once.
	if not visual.attack_frame_phase_reached():
		return
	_audio_attack_frame_ready = true
	_audio_attack_presented_seen = true
	_audio_attack_frame_sequence = _audio_attack_sequence
	_emit_monster_audio("attack_frame")
	# R3 W2: EXPIRY, not supplementary playback. If the action finishes before
	# its frame phase fired, the phase expires with the action - there is no
	# post-action attack_frame emission (the R2 branch that replayed the frame
	# sound after the action ended was removed with its test contract).
	_audio_previous_visual_state = str(visual.current_state)
	_audio_previous_visual_frame = int(visual.current_frame)
	_audio_previous_facing = facing


func _reset_direct_spell_runtime_stats() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_reset_direct_spell_runtime_stats", []))

func _direct_spell_integer(value: Variant) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_direct_spell_integer", [_enemy_ports.to_domain(value)]))

func _direct_spell_integer_value_valid(value: Variant) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_direct_spell_integer_value_valid", [_enemy_ports.to_domain(value)]))

func _direct_spell_alias_value(
	source: Dictionary,
	keys: Array[String],
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_direct_spell_alias_value", [_enemy_ports.to_domain(source), _enemy_ports.to_domain(keys)]))

func _compile_direct_spell_runtime_stats(canonical_entry: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_compile_direct_spell_runtime_stats", [_enemy_ports.to_domain(canonical_entry)]))

func effective_physical_defense() -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("effective_physical_defense", []))

func direct_spell_runtime_stats_into(output: Dictionary) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("direct_spell_runtime_stats_into", [_enemy_ports.to_domain(output)]))

func _apply_behavior_profile() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_behavior_profile", []))

func _hold_combat_disabled() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hold_combat_disabled", []))

func _apply_attack_range_policy() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_attack_range_policy", []))

static func _load_attack_range_policy_once() -> void:
	EnemyLegacyContext.owner_context().shared._load_attack_range_policy_once()

static func _attack_range_policy_record_for_id(requested_monster_id: int) -> Dictionary:
	return EnemyLegacyContext.owner_context().shared._attack_range_policy_record_for_id(requested_monster_id)

func _apply_source_locked_special_delivery_override() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_source_locked_special_delivery_override", []))

static func _load_movement_authority_once() -> void:
	EnemyLegacyContext.owner_context().shared._load_movement_authority_once()

static func _movement_authority_record_for_id(
	requested_monster_id: int
) -> Dictionary:
	return EnemyLegacyContext.owner_context().shared._movement_authority_record_for_id(requested_monster_id)

func _configure_target_acquisition() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_configure_target_acquisition", []))

func _initial_acquisition_contains_ground_delta_gu(delta_ground_gu: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_initial_acquisition_contains_ground_delta_gu", [_enemy_ports.to_domain(delta_ground_gu)]))

func passive_acquisition_extent_gu() -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("passive_acquisition_extent_gu", []))

func request_passive_target_wakeup(
	candidate: Node2D,
	expected_map_id: int,
	expected_generation: int,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("request_passive_target_wakeup", [_enemy_ports.to_domain(candidate), _enemy_ports.to_domain(expected_map_id), _enemy_ports.to_domain(expected_generation)]))

func request_passive_player_wakeup(
	candidate: PlayerCharacter,
	expected_map_id: int,
	expected_generation: int,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("request_passive_player_wakeup", [_enemy_ports.to_domain(candidate), _enemy_ports.to_domain(expected_map_id), _enemy_ports.to_domain(expected_generation)]))

func _passive_target_identity_valid(
	candidate: Node2D,
	expected_map_id: int,
	expected_generation: int,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_passive_target_identity_valid", [_enemy_ports.to_domain(candidate), _enemy_ports.to_domain(expected_map_id), _enemy_ports.to_domain(expected_generation)]))

func _passive_target_owner_scope_valid(
	owner: Object,
	expected_map_id: int,
	expected_generation: int,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_passive_target_owner_scope_valid", [_enemy_ports.to_domain(owner), _enemy_ports.to_domain(expected_map_id), _enemy_ports.to_domain(expected_generation)]))

func _passive_target_is_hidden(candidate: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_passive_target_is_hidden", [_enemy_ports.to_domain(candidate)]))

func _passive_wake_is_valid() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_passive_wake_is_valid", []))

func _clear_passive_wake() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_clear_passive_wake", []))

func _refresh_target_focus(now_ms_override := -1) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_refresh_target_focus", [_enemy_ports.to_domain(now_ms_override)]))

func _target_should_disengage(
	candidate: Node2D,
	now_ms_override := -1,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_should_disengage", [_enemy_ports.to_domain(candidate), _enemy_ports.to_domain(now_ms_override)]))

func _birth_movement_authority_record() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_birth_movement_authority_record", []))

func _configure_movement_cadence() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_configure_movement_cadence", []))

func _request_autonomous_step(
	desired_direction_ground_gu: Vector2,
	speed_scale: float,
	use_crowd_steering: bool,
	reason: StringName,
	now_ms_override := -1,
	engagement_target: Node2D = null
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_request_autonomous_step", [_enemy_ports.to_domain(desired_direction_ground_gu), _enemy_ports.to_domain(speed_scale), _enemy_ports.to_domain(use_crowd_steering), _enemy_ports.to_domain(reason), _enemy_ports.to_domain(now_ms_override), _enemy_ports.to_domain(engagement_target)]))

func _begin_autonomous_step_without_cadence(
	desired_direction_ground_gu: Vector2,
	speed_scale: float,
	use_crowd_steering: bool,
	reason: StringName,
	engagement_target: Node2D = null,
	now_ms_override := -1,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_begin_autonomous_step_without_cadence", [_enemy_ports.to_domain(desired_direction_ground_gu), _enemy_ports.to_domain(speed_scale), _enemy_ports.to_domain(use_crowd_steering), _enemy_ports.to_domain(reason), _enemy_ports.to_domain(engagement_target), _enemy_ports.to_domain(now_ms_override)]))

func _locomotion_segment_clear(a: Vector2, b: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_locomotion_segment_clear", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _terrain_neighbor_for_pursuit(
	current_ground_gu: Vector2,
	engagement_target: Node2D,
	direct_neighbor: Vector2i,
) -> Vector2i:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_terrain_neighbor_for_pursuit", [_enemy_ports.to_domain(current_ground_gu), _enemy_ports.to_domain(engagement_target), _enemy_ports.to_domain(direct_neighbor)]))

func _clear_terrain_route_cache() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_clear_terrain_route_cache", []))

func _reset_terrain_navigation_state() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_reset_terrain_navigation_state", []))

func _clear_continuous_pursuit_intent() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_clear_continuous_pursuit_intent", []))

func _live_continuous_pursuit_target() -> Node2D:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_live_continuous_pursuit_target", []))

func _continue_continuous_pursuit_from_current_target() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_continue_continuous_pursuit_from_current_target", []))

func _clear_autonomous_step_state() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_clear_autonomous_step_state", []))

func _cancel_autonomous_step(preserve_current_position := true) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_cancel_autonomous_step", [_enemy_ports.to_domain(preserve_current_position)]))

func _movement_step_engagement_target() -> Node2D:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_movement_step_engagement_target", []))

func _movement_step_engagement_ready() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_movement_step_engagement_ready", []))

func _fail_autonomous_step_blocked() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_fail_autonomous_step_blocked", []))

func _advance_autonomous_step(delta: float, frame_delta := -1.0) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_advance_autonomous_step", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(frame_delta)]))

func _advance_autonomous_step_internal(delta: float, frame_delta := -1.0) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_advance_autonomous_step_internal", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(frame_delta)]))

func _apply_boss_rule() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_boss_rule", []))

static func legal_spawn_facing_directions() -> Array[Vector2]:
	return EnemyLegacyContext.owner_context().shared.legal_spawn_facing_directions()

func set_spawn_facing_seed_for_test(seed_value: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("set_spawn_facing_seed_for_test", [_enemy_ports.to_domain(seed_value)]))

func _initialize_spawn_facing_once() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_initialize_spawn_facing_once", []))

func resolve_body_for_admission() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("resolve_body_for_admission", []))

func _ready() -> void:
	if monster_id < 0 or bool(get_meta("canonical_rejected", false)):
		queue_free()
		return
	MonsterVisualScript.configure_actor_y_sort_item(self, "actor_root")
	# R3 W3: the world group join moved below the body resolution - a
	# body-policy-rejected actor must never become an "enemies" member.
	input_pickable = true
	collision_layer = WorldSpatialRulesScript.ENEMY_LAYER
	# Crowd steering still chooses routes and reduces contention, while the
	# physics mask is the final hard occupancy authority. Ground monsters must
	# not tunnel through WORLD, players, summons (PLAYER_LAYER), or one another.
	collision_mask = ENEMY_MOTION_MASK
	if not bool(behavior_profile.get("worldCollision", true)):
		# 飞行怪参与攻击和选取，但不作为人物移动的实体墙。
		collision_layer = 0
		collision_mask = WorldSpatialRulesScript.WORLD_MASK
	motion_mode = CharacterBody2D.MOTION_MODE_FLOATING
	safe_margin = 0.35
	max_slides = 6
	_rng.randomize()
	_initialize_spawn_facing_once()
	# HC-MONSTER-COMBAT-R2 T2: resolution is identity-bound. A production
	# profile must match the current policy bytes, the exact tier radius and
	# the assignment rule owned by this monster_id. A rejected profile never
	# falls back to the small tier to keep fighting: the enemy stays visible
	# but combat is disabled, no fighting footsole is created, and the small
	# radius below only feeds spawn-overlap push-out (placement hygiene).
	# HC-MONSTER-COMBAT-R3 W3 (R3-04): the body resolves BEFORE the world
	# group joins. A rejected actor is not an "enemies" member - it is never
	# targeted, never damaged, never drops loot; it only joins a diagnostic
	# group so tooling can see it, and the reserved CollisionShape2D is freed
	# instead of leaking as an orphan node.
	# R4 T3: the resolution itself is a public idempotent admission step so
	# the spawn factory can obtain the verdict BEFORE it joins the scene,
	# occupies the respawn slot, registers the spatial index or the activity
	# cache. _ready runs it exactly once; an earlier factory precheck wins.
	resolve_body_for_admission()
	if not _body_admission_rejected and _body_collision_shape != null:
		add_child(_body_collision_shape)
		_body_collision_shape = null
	# R4 T3-A: the GU radius was already derived from the FINAL pixel radius
	# inside the successful admission resolution (before the spawn factory
	# registers the actor into the spatial index). _ready must never produce
	# a second, different value - it only verifies consistency.
	var ready_radius_gu := MonsterUnitAdapterScript.footprint_radius_px_to_combat_radius_gu(
		collision_radius_px
	)
	assert(
		is_equal_approx(combat_radius_gu, ready_radius_gu),
		"body admission GU radius must match the final pixel radius"
	)
	if not is_boss:
		_background_wakeup_timer = Timer.new()
		_background_wakeup_timer.name = "BackgroundAIWakeupTimer"
		_background_wakeup_timer.one_shot = true
		_background_wakeup_timer.process_callback = Timer.TIMER_PROCESS_PHYSICS
		_background_wakeup_timer.timeout.connect(_on_background_wakeup_timeout)
		add_child(_background_wakeup_timer)
	_resolve_invalid_spawn_overlap()
	_last_environment_safe_position_px = global_position
	_environment_guard_timer = ENVIRONMENT_GUARD_INTERVAL_SECONDS * float(posmod(get_instance_id(), 11)) / 11.0
	visual = MonsterVisualScript.new()
	visual.name = "MonsterVisual"
	visual.setup(self)
	# Every production posture uses the owner clock, including hits before the
	# monster's first attack. Preview visuals remain explicitly unbound.
	visual._combat_clock_s = Callable(self, "_combat_action_time_getter")
	add_child(visual)
	overhead = MonsterOverheadScript.new()
	overhead.name = "MonsterOverhead"
	MonsterVisualScript.configure_actor_y_sort_item(overhead, "overhead_root")
	overhead.setup(display_name, is_boss, current_hp, max_hp)
	add_child(overhead)
	name_label = overhead.name_label
	MonsterVisualScript.configure_actor_y_sort_item(name_label, "name_label")
	refresh_name_label_position()
	if MonsterGroundRuntimeDiagnosticOverlayScript.enabled_for_runtime():
		ground_runtime_diagnostic_overlay = (
			MonsterGroundRuntimeDiagnosticOverlayScript.new()
		)
		ground_runtime_diagnostic_overlay.name = "GroundRuntimeDiagnosticOverlay"
		ground_runtime_diagnostic_overlay.setup(self)
		add_child(ground_runtime_diagnostic_overlay)
	if _burrowed:
		visual.visible = false
		overhead.visible = false
	if boss_rule.is_empty():
		_retarget_timer = FAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 11))
		_crowd_steering_timer = CROWD_STEERING_INTERVAL_SECONDS * float(posmod(get_instance_id(), 7)) / 7.0
		_background_ai_timer = BACKGROUND_AI_INTERVAL_SECONDS * float(posmod(get_instance_id(), 13)) / 13.0
		if _can_use_background_ai():
			_enter_background_deep_sleep(true)
	_record_performance_counter(&"actor_redraw_requests")
	queue_redraw()


func _resolve_invalid_spawn_overlap() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_resolve_invalid_spawn_overlap", []))

func set_targeted(value: bool) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("set_targeted", [_enemy_ports.to_domain(value)]))

func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		target_requested.emit(self)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		target_requested.emit(self)


func _update_natural_regen(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_natural_regen", [_enemy_ports.to_domain(delta)]))

func _physics_process(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_physics_process", [_enemy_ports.to_domain(delta)]))

func _physics_process_internal(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_physics_process_internal", [_enemy_ports.to_domain(delta)]))

func _handle_safe_zone_target_return(physics_delta: float) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_handle_safe_zone_target_return", [_enemy_ports.to_domain(physics_delta)]))

func _hold_pursuit_at_current_position() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hold_pursuit_at_current_position", []))

func _enter_background_deep_sleep(initial_phase: bool) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_enter_background_deep_sleep", [_enemy_ports.to_domain(initial_phase)]))

func _background_wakeup_interval_seconds() -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_background_wakeup_interval_seconds", []))

func _background_wakeup_phase_slot() -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_background_wakeup_phase_slot", []))

func _leave_background_deep_sleep() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_leave_background_deep_sleep", []))

func _on_background_wakeup_timeout() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_on_background_wakeup_timeout", []))

func _spatial_index_update() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_spatial_index_update", []))

func _spatial_index_projection_cache_matches() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_spatial_index_projection_cache_matches", []))

func spatial_index_position() -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("spatial_index_position", []))

func set_combat_position(
	position_px: Vector2,
	reason: StringName = &""
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("set_combat_position", [_enemy_ports.to_domain(position_px), _enemy_ports.to_domain(reason)]))

func try_screen_position_px_to_ground_position_gu(
	screen_position_px: Vector2
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("try_screen_position_px_to_ground_position_gu", [_enemy_ports.to_domain(screen_position_px)]))

func projection_ready() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("projection_ready", []))

func _screen_position_px_to_ground_position_gu(screen_position_px: Vector2) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_screen_position_px_to_ground_position_gu", [_enemy_ports.to_domain(screen_position_px)]))

func _screen_position_px_to_ground_position_gu_vector2(
	screen_position_px: Vector2
) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_screen_position_px_to_ground_position_gu_vector2", [_enemy_ports.to_domain(screen_position_px)]))

func _target_ground_projection_cache_matches(
	screen_position_px: Vector2
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_ground_projection_cache_matches", [_enemy_ports.to_domain(screen_position_px)]))

func _write_target_ground_projection_cache_if_current_target(
	screen_position_px: Vector2,
	ground_position_gu: Vector2,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_write_target_ground_projection_cache_if_current_target", [_enemy_ports.to_domain(screen_position_px), _enemy_ports.to_domain(ground_position_gu)]))

func _screen_position_px_to_ground_position_gu_internal(
	screen_position_px: Vector2
) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_screen_position_px_to_ground_position_gu_internal", [_enemy_ports.to_domain(screen_position_px)]))

func _ground_gu_to_screen_position_px(ground_position_gu: Vector2) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_ground_gu_to_screen_position_px", [_enemy_ports.to_domain(ground_position_gu)]))

static func _ground_delta_gu_between_screen_positions(
	origin_screen_position_px: Vector2,
	target_screen_position_px: Vector2,
) -> Vector2:
	return EnemyLegacyContext.owner_context().shared._ground_delta_gu_between_screen_positions(origin_screen_position_px, target_screen_position_px)

static func _screen_facing_for_ground_direction(direction_ground: Vector2) -> Vector2:
	return EnemyLegacyContext.owner_context().shared._screen_facing_for_ground_direction(direction_ground)

func ground_velocity_gu_per_sec() -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("ground_velocity_gu_per_sec", []))

static func _safe_zone_point_ground_gu_from_screen_reference(
	point_screen_px: Vector2,
	zone: Dictionary,
) -> Vector2:
	return EnemyLegacyContext.owner_context().shared._safe_zone_point_ground_gu_from_screen_reference(point_screen_px, zone)

static func _packed_vector2_array_from_variant(raw_points: Variant) -> PackedVector2Array:
	return EnemyLegacyContext.owner_context().shared._packed_vector2_array_from_variant(raw_points)

func _point_inside_safe_zone(point_screen_px: Vector2, known_hc_cache := false) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_point_inside_safe_zone", [_enemy_ports.to_domain(point_screen_px), _enemy_ports.to_domain(known_hc_cache)]))

func _point_inside_safe_zone_uncached(point_screen_px: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_point_inside_safe_zone_uncached", [_enemy_ports.to_domain(point_screen_px)]))

func _move_with_spatial_rules(delta := 1.0 / 60.0) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_move_with_spatial_rules", [_enemy_ports.to_domain(delta)]))

func _movement_collision_count() -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_movement_collision_count", []))

func _movement_collision(index: int) -> KinematicCollision2D:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_movement_collision", [_enemy_ports.to_domain(index)]))

func _attack_engagement_ready(
	hit_target: Node2D,
	offset_ground_gu: Vector2,
	distance_gu: float,
	contact_distance_gu: float,
	default_engagement_distance_gu: float,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_engagement_ready", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(offset_ground_gu), _enemy_ports.to_domain(distance_gu), _enemy_ports.to_domain(contact_distance_gu), _enemy_ports.to_domain(default_engagement_distance_gu)]))

func _attack_world_path_is_clear_for_target(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_world_path_is_clear_for_target", [_enemy_ports.to_domain(hit_target)]))

func _world_attack_path_is_clear(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	source_world_px: Vector2 = Vector2.INF,
	target_world_px: Vector2 = Vector2.INF,
	allow_cache := true,
	target_instance_id := 0,
	record_request := true,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_world_attack_path_is_clear", [_enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu), _enemy_ports.to_domain(source_world_px), _enemy_ports.to_domain(target_world_px), _enemy_ports.to_domain(allow_cache), _enemy_ports.to_domain(target_instance_id), _enemy_ports.to_domain(record_request)]))

func _world_attack_path_is_clear_uncached(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	source_world_px: Vector2 = Vector2.INF,
	target_world_px: Vector2 = Vector2.INF,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_world_attack_path_is_clear_uncached", [_enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu), _enemy_ports.to_domain(source_world_px), _enemy_ports.to_domain(target_world_px)]))

func _finish_attack_los_diagnostic(started_usec: int, result: bool) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_finish_attack_los_diagnostic", [_enemy_ports.to_domain(started_usec), _enemy_ports.to_domain(result)]))

func _clear_attack_los_cache() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_clear_attack_los_cache", []))

func _attack_los_cache_context() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_los_cache_context", []))

func _attack_los_cache_matches(
	cache_context: Dictionary,
	target_instance_id: int,
	source_world_px: Vector2,
	target_world_px: Vector2,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_los_cache_matches", [_enemy_ports.to_domain(cache_context), _enemy_ports.to_domain(target_instance_id), _enemy_ports.to_domain(source_world_px), _enemy_ports.to_domain(target_world_px)]))

func _world_direct_space_state() -> PhysicsDirectSpaceState2D:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_world_direct_space_state", []))

func _world_attack_path_is_clear_for_release(
	release_record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_world_attack_path_is_clear_for_release", [_enemy_ports.to_domain(release_record)]))

func _uses_target_magic_delivery() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_target_magic_delivery", []))

func _uses_special_magic_melee_delivery() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_special_magic_melee_delivery", []))

func _uses_area_magic_delivery() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_area_magic_delivery", []))

func _special_magic_melee_condition_met(offset_ground_gu: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_special_magic_melee_condition_met", [_enemy_ports.to_domain(offset_ground_gu)]))

func _target_magic_condition_met(offset_ground_gu: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_magic_condition_met", [_enemy_ports.to_domain(offset_ground_gu)]))

func _current_attack_interval() -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_current_attack_interval", []))

func _update_pending_attack(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_pending_attack", [_enemy_ports.to_domain(delta)]))

func _uses_physical_projectile_delivery() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_physical_projectile_delivery", []))

func _uses_monster_special_cell_delivery() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_monster_special_cell_delivery", []))

func _valid_directional_spit_rule() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_directional_spit_rule", []))

func _valid_gas_rule() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_gas_rule", []))

func _valid_line_magic_rule() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_line_magic_rule", []))

func _valid_mixed_target_tile_rule() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_mixed_target_tile_rule", []))

func _valid_guard_direct_projectile_rule() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_guard_direct_projectile_rule", []))

func _valid_special_status_rule(
	expected_kind: String,
	expected_denominator_owner: String,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_special_status_rule", [_enemy_ports.to_domain(expected_kind), _enemy_ports.to_domain(expected_denominator_owner)]))

func _valid_special_integer_number(
	value: Variant,
	minimum: int,
	maximum := 2147483647,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_valid_special_integer_number", [_enemy_ports.to_domain(value), _enemy_ports.to_domain(minimum), _enemy_ports.to_domain(maximum)]))

func _observe_special_contact_admission(victim: Node2D, damage: int, parent_action: int) -> Variant:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_observe_special_contact_admission", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(damage), _enemy_ports.to_domain(parent_action)]))

func _launch_monster_special_cell_delivery(
	hit_target: Node2D,
	rolled_damage: int,
	parent_release: Variant = null,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_launch_monster_special_cell_delivery", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(rolled_damage), _enemy_ports.to_domain(parent_release)]))

func _freeze_monster_special_delivery_contract(kind: String) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_freeze_monster_special_delivery_contract", [_enemy_ports.to_domain(kind)]))

func _special_delivery_release_condition_met(delta_ground_gu: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_special_delivery_release_condition_met", [_enemy_ports.to_domain(delta_ground_gu)]))

func _monster_special_presentation_delay_seconds(
	kind: String,
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
) -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_monster_special_presentation_delay_seconds", [_enemy_ports.to_domain(kind), _enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu)]))

func _detonate_explosion_spider(selected_target: Node2D, rolled_damage: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_detonate_explosion_spider", [_enemy_ports.to_domain(selected_target), _enemy_ports.to_domain(rolled_damage)]))

func _create_monster_special_cell_snapshot(
	kind: String,
	release_id: String,
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_create_monster_special_cell_snapshot", [_enemy_ports.to_domain(kind), _enemy_ports.to_domain(release_id), _enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu)]))

func _monster_special_delivery_targets(
	snapshot: Dictionary,
	selected_target: Node2D,
) -> Array[Node2D]:
	_ensure_enemy_domain()
	var result: Array[Node2D] = []
	result.assign(_enemy_ports.to_legacy(domain_model.callv("_monster_special_delivery_targets", [_enemy_ports.to_domain(snapshot), _enemy_ports.to_domain(selected_target)])))
	return result

func _append_special_delivery_candidate(
	candidates: Array[Node2D],
	raw_candidate: Variant,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_append_special_delivery_candidate", [_enemy_ports.to_domain(candidates), _enemy_ports.to_domain(raw_candidate)]))

func _special_delivery_target_is_live(victim: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_special_delivery_target_is_live", [_enemy_ports.to_domain(victim)]))

func _freeze_monster_special_delivery_records(
	kind: String,
	victims: Array[Node2D],
	snapshot: Dictionary,
	rolled_damage: int,
	release_serial: int,
	delivery_contract: Dictionary,
	parent_release: Variant = null,
) -> Array[Dictionary]:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_freeze_monster_special_delivery_records", [_enemy_ports.to_domain(kind), _enemy_ports.to_domain(victims), _enemy_ports.to_domain(snapshot), _enemy_ports.to_domain(rolled_damage), _enemy_ports.to_domain(release_serial), _enemy_ports.to_domain(delivery_contract), _enemy_ports.to_domain(parent_release)]))

func _settle_monster_special_cell_release(release_record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_monster_special_cell_release", [_enemy_ports.to_domain(release_record)]))

func _claim_special_delivery_settlement(
	target_instance_id: int,
	release_serial: int,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_claim_special_delivery_settlement", [_enemy_ports.to_domain(target_instance_id), _enemy_ports.to_domain(release_serial)]))

func _monster_special_release_target_is_valid(
	victim: Node2D,
	record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_monster_special_release_target_is_valid", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(record)]))

func _special_delivery_release_target_is_live(
	victim: Node2D,
	kind: String,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_special_delivery_release_target_is_live", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(kind)]))

func _settle_monster_special_victim(
	victim: Node2D,
	record: Dictionary,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_monster_special_victim", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(record)]))

func _apply_monster_special_magic_damage(
	victim: Node2D,
	raw_damage: int,
	kind: String,
	release_record: Variant = null,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_apply_monster_special_magic_damage", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(raw_damage), _enemy_ports.to_domain(kind), _enemy_ports.to_domain(release_record)]))

func _monster_special_accuracy_succeeds(
	victim: Node2D,
	delivery_contract: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_monster_special_accuracy_succeeds", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(delivery_contract)]))

func _apply_monster_special_status(
	victim: Node2D,
	kind: String,
	delivery_contract: Dictionary,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_monster_special_status", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(kind), _enemy_ports.to_domain(delivery_contract)]))

func _special_delivery_target_is_undead(victim: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_special_delivery_target_is_undead", [_enemy_ports.to_domain(victim)]))

func _emit_monster_special_delivery_descriptor(release_record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_emit_monster_special_delivery_descriptor", [_enemy_ports.to_domain(release_record)]))

func _canonical_attack_frame_count(minimum: int) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_canonical_attack_frame_count", [_enemy_ports.to_domain(minimum)]))

func _queue_physical_projectile(hit_target: Node2D, dealt_damage: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_queue_physical_projectile", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage)]))

func _queue_guard_projectile(
	hit_target: Node2D,
	dealt_damage: int,
	parent_release: Variant,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_queue_guard_projectile", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage), _enemy_ports.to_domain(parent_release)]))

func _physical_projectile_flight_duration_seconds(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
) -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_physical_projectile_flight_duration_seconds", [_enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu)]))

func _launch_physical_projectile(hit_target: Node2D, dealt_damage: int) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_launch_physical_projectile", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage)]))

func _physical_projectile_path_is_clear(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	target_world_px: Vector2 = Vector2.INF,
	target_instance_id := 0,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_physical_projectile_path_is_clear", [_enemy_ports.to_domain(source_ground_gu), _enemy_ports.to_domain(target_ground_gu), _enemy_ports.to_domain(target_world_px), _enemy_ports.to_domain(target_instance_id)]))

func _on_physical_projectile_contact(
	release_record: Dictionary,
	hit_target: Node2D,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_on_physical_projectile_contact", [_enemy_ports.to_domain(release_record), _enemy_ports.to_domain(hit_target)]))

func _on_guard_projectile_contact(
	release_record: Dictionary,
	hit_target: Node2D,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_on_guard_projectile_contact", [_enemy_ports.to_domain(release_record), _enemy_ports.to_domain(hit_target)]))

func _on_guard_projectile_miss(release_record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_on_guard_projectile_miss", [_enemy_ports.to_domain(release_record)]))

func _body_release_life_is_current(hit_target: Node2D, record: Dictionary) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_body_release_life_is_current", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(record)]))

func _physical_projectile_release_target_is_valid(
	hit_target: Node2D,
	release_record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_physical_projectile_release_target_is_valid", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(release_record)]))

func _emit_physical_projectile_descriptor(release_record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_emit_physical_projectile_descriptor", [_enemy_ports.to_domain(release_record)]))

func _target_magic_recipient_admissible(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_magic_recipient_admissible", [_enemy_ports.to_domain(hit_target)]))

func _launch_target_magic(hit_target: Node2D, raw_damage: int) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_launch_target_magic", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(raw_damage)]))

func _settle_target_magic_release(release_record: Dictionary, admission_world_clear := false) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_target_magic_release", [_enemy_ports.to_domain(release_record), _enemy_ports.to_domain(admission_world_clear)]))

func _emit_target_magic_descriptor(release_record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_emit_target_magic_descriptor", [_enemy_ports.to_domain(release_record)]))

func _deal_special_magic_melee_hit(
	hit_target: Node2D,
	dealt_damage: int,
	release_record: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_deal_special_magic_melee_hit", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage), _enemy_ports.to_domain(release_record)]))

func _deal_melee_hit(
	hit_target: Node2D,
	dealt_damage: int,
	center_tolerance_gu := 0.0,
	force_los_recheck := false,
	release_record: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_deal_melee_hit", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage), _enemy_ports.to_domain(center_tolerance_gu), _enemy_ports.to_domain(force_los_recheck), _enemy_ports.to_domain(release_record)]))

func _target_agility_for_monster_hit(hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_agility_for_monster_hit", [_enemy_ports.to_domain(hit_target)]))

func _monster_physical_hit_succeeds(hit_target: Node2D, forced_roll := -1) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_monster_physical_hit_succeeds", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(forced_roll)]))

func _apply_attack_damage(
	hit_target: Node2D,
	dealt_damage: int,
	use_accuracy := true,
	forced_roll := -1,
	force_struck_reaction := false,
	forced_control_roll := -1,
	ranged := false,
	release_record: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_attack_damage", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage), _enemy_ports.to_domain(use_accuracy), _enemy_ports.to_domain(forced_roll), _enemy_ports.to_domain(force_struck_reaction), _enemy_ports.to_domain(forced_control_roll), _enemy_ports.to_domain(ranged), _enemy_ports.to_domain(release_record)]))

func _apply_attack_damage_impl(
	hit_target: Node2D,
	dealt_damage: int,
	use_accuracy := true,
	forced_roll := -1,
	force_struck_reaction := false,
	forced_control_roll := -1,
	ranged := false,
	ledger_ctx: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_attack_damage_impl", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(dealt_damage), _enemy_ports.to_domain(use_accuracy), _enemy_ports.to_domain(forced_roll), _enemy_ports.to_domain(force_struck_reaction), _enemy_ports.to_domain(forced_control_roll), _enemy_ports.to_domain(ranged), _enemy_ports.to_domain(ledger_ctx)]))

func _apply_on_hit_control(hit_target: Node2D, forced_control_roll := -1) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_on_hit_control", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(forced_control_roll)]))

func _target_anti_poison_for_control(hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_anti_poison_for_control", [_enemy_ports.to_domain(hit_target)]))

func configure_runtime_map_projection(
	map_id: int,
	ground_gu_to_screen_position_px: Callable,
	screen_position_px_to_ground_gu: Callable = Callable()
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("configure_runtime_map_projection", [_enemy_ports.to_domain(map_id), _enemy_ports.to_domain(ground_gu_to_screen_position_px), _enemy_ports.to_domain(screen_position_px_to_ground_gu)]))

func configure_terrain_navigation_context(context: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("configure_terrain_navigation_context", [_enemy_ports.to_domain(context)]))

func terrain_navigation_context_ready() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("terrain_navigation_context_ready", []))

func _initial_acquisition_static_los_clear(candidate: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_initial_acquisition_static_los_clear", [_enemy_ports.to_domain(candidate)]))

func configure_spatial_index(
	index: RuntimeCombatSpatialIndexScript,
	actor_runtime_id: int
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("configure_spatial_index", [_enemy_ports.to_domain(index), _enemy_ports.to_domain(actor_runtime_id)]))

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# The source-owned pending will cease to exist with this Node. A tree
		# exit/reparent alone may resume it, so observe only actual destruction.
		_observe_pending_attack_cancellation("SOURCE_DESTROYED")


func _exit_tree() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_exit_tree", []))

func _snapshot_coordinate_context() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_snapshot_coordinate_context", []))

func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_snapshot_strict_ok", [_enemy_ports.to_domain(snapshot)]))

func _snapshot_intersects_target(snapshot: Dictionary, hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_snapshot_intersects_target", [_enemy_ports.to_domain(snapshot), _enemy_ports.to_domain(hit_target)]))

func _monster_attack_id(kind: String) -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_monster_attack_id", [_enemy_ports.to_domain(kind)]))

func _next_spatial_release_id(kind: String) -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_next_spatial_release_id", [_enemy_ports.to_domain(kind)]))

func _decorate_attack_footprint_snapshot(
	snapshot: Dictionary,
	projection_relationship_id: String,
	hit_target: Node2D = null,
	center_reach_gu := 0.0,
	center_tolerance_gu := 0.0,
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_decorate_attack_footprint_snapshot", [_enemy_ports.to_domain(snapshot), _enemy_ports.to_domain(projection_relationship_id), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(center_reach_gu), _enemy_ports.to_domain(center_tolerance_gu)]))

func _uses_ranged_projectile_sweep_contract() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_ranged_projectile_sweep_contract", []))

func _target_is_safe_player(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_is_safe_player", [_enemy_ports.to_domain(hit_target)]))

func _player_combat_is_available(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_player_combat_is_available", [_enemy_ports.to_domain(hit_target)]))

func _typed_player_combat_epoch(hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_typed_player_combat_epoch", [_enemy_ports.to_domain(hit_target)]))

func _release_player_combat_epoch_is_current(
	hit_target: Node2D,
	release_record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_release_player_combat_epoch_is_current", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(release_record)]))

func _update_area_magic_delivery(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_area_magic_delivery", [_enemy_ports.to_domain(delta)]))

func _create_area_magic_footprint_snapshot() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_create_area_magic_footprint_snapshot", []))

func _area_magic_targets(snapshot: Dictionary) -> Array[Node2D]:
	_ensure_enemy_domain()
	var result: Array[Node2D] = []
	result.assign(_enemy_ports.to_legacy(domain_model.callv("_area_magic_targets", [_enemy_ports.to_domain(snapshot)])))
	return result

func _area_magic_victim_is_valid(victim: Node2D, snapshot: Dictionary) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_magic_victim_is_valid", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(snapshot)]))

func _freeze_area_magic_release_records(
	victims: Array[Node2D],
	footprint_snapshot: Dictionary,
) -> Array[Dictionary]:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_freeze_area_magic_release_records", [_enemy_ports.to_domain(victims), _enemy_ports.to_domain(footprint_snapshot)]))

func _area_release_life_is_current(victim: Node2D, record: Dictionary) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_release_life_is_current", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(record)]))

func _settle_area_magic_release_records() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_area_magic_release_records", []))

func _area_magic_release_target_is_valid(
	victim: Node2D,
	release_record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_magic_release_target_is_valid", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(release_record)]))

func _deal_area_magic_damage(victim: Node2D, dealt_damage: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_deal_area_magic_damage", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(dealt_damage)]))

func _apply_area_magic_status(victim: Node2D) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_area_magic_status", [_enemy_ports.to_domain(victim)]))

func _update_area_attack(delta: float) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_update_area_attack", [_enemy_ports.to_domain(delta)]))

func _area_attack_visual_duration() -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_attack_visual_duration", []))

func _create_area_attack_footprint_snapshot() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_create_area_attack_footprint_snapshot", []))

func _area_attack_targets(snapshot := {}) -> Array[Node2D]:
	_ensure_enemy_domain()
	var result: Array[Node2D] = []
	result.assign(_enemy_ports.to_legacy(domain_model.callv("_area_attack_targets", [_enemy_ports.to_domain(snapshot)])))
	return result

func _area_attack_victim_is_valid(
	victim: Node2D,
	snapshot: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_attack_victim_is_valid", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(snapshot)]))

func _freeze_area_attack_release_records(
	victims: Array[Node2D],
	footprint_snapshot: Dictionary,
) -> Array[Dictionary]:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_freeze_area_attack_release_records", [_enemy_ports.to_domain(victims), _enemy_ports.to_domain(footprint_snapshot)]))

func _settle_area_attack_release_records() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_area_attack_release_records", []))

func _area_attack_release_target_is_valid(
	victim: Node2D,
	release_record: Dictionary,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_area_attack_release_target_is_valid", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(release_record)]))

func _runtime_map_id_for_area_target(victim: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_runtime_map_id_for_area_target", [_enemy_ports.to_domain(victim)]))

func _uses_fixed_area_ground_spike_effect() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_fixed_area_ground_spike_effect", []))

func _target_approved_ground_footpoint_world_px(victim: Node2D) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_approved_ground_footpoint_world_px", [_enemy_ports.to_domain(victim)]))

func _emit_fixed_area_ground_spike_descriptor(
	release_record: Dictionary,
	footprint_snapshot: Dictionary,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_emit_fixed_area_ground_spike_descriptor", [_enemy_ports.to_domain(release_record), _enemy_ports.to_domain(footprint_snapshot)]))

func _update_behavior_summon(delta: float) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_update_behavior_summon", [_enemy_ports.to_domain(delta)]))

func _target_combat_radius_gu(target_node: Node2D) -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_combat_radius_gu", [_enemy_ports.to_domain(target_node)]))

func _contact_distance_gu_to_target(target_node: Node2D) -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_contact_distance_gu_to_target", [_enemy_ports.to_domain(target_node)]))

func _uses_player_melee_contact_contract(target_node: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_uses_player_melee_contact_contract", [_enemy_ports.to_domain(target_node)]))

func _crowd_separation() -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_crowd_separation", []))

func _crowd_separation_for_motion(delta: float) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_crowd_separation_for_motion", [_enemy_ports.to_domain(delta)]))

func _ensure_target_grid(force_refresh := false) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_ensure_target_grid", [_enemy_ports.to_domain(force_refresh)]))

static func _target_grid_cell(screen_position_px: Vector2) -> Vector2i:
	return EnemyLegacyContext.owner_context().shared._target_grid_cell(screen_position_px)

func _target_grid_candidates(max_range_gu: float) -> Array[Node2D]:
	_ensure_enemy_domain()
	var result: Array[Node2D] = []
	result.assign(_enemy_ports.to_legacy(domain_model.callv("_target_grid_candidates", [_enemy_ports.to_domain(max_range_gu)])))
	return result

func _append_live_target_candidate(candidates: Array, raw_candidate: Variant) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_append_live_target_candidate", [_enemy_ports.to_domain(candidates), _enemy_ports.to_domain(raw_candidate)]))

static func reset_performance_diagnostics() -> void:
	EnemyLegacyContext.owner_context().shared.reset_performance_diagnostics()

static func performance_diagnostics() -> Dictionary:
	return EnemyLegacyContext.owner_context().shared.performance_diagnostics()

func _can_use_background_ai() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_can_use_background_ai", []))

func apply_life_steal(dealt_damage: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("apply_life_steal", [_enemy_ports.to_domain(dealt_damage)]))

func apply_source_magic_life_steal(post_magic_defense_damage: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("apply_source_magic_life_steal", [_enemy_ports.to_domain(post_magic_defense_damage)]))

func take_damage(
	amount: int,
	attacker: Node2D = null,
	damage_context: Dictionary = {},
	delivery_identity: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("take_damage", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(damage_context), _enemy_ports.to_domain(delivery_identity)]))

func take_ground_tick_damage(amount: int, attacker: Node2D = null, damage_context: Dictionary = {}) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("take_ground_tick_damage", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(damage_context)]))

func has_actor_capability(id: String) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("has_actor_capability", [_enemy_ports.to_domain(id)]))

func replace_actor_capability_source(handle: String, capabilities: Array) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("replace_actor_capability_source", [_enemy_ports.to_domain(handle), _enemy_ports.to_domain(capabilities)]))

func take_feature_periodic_damage(amount: int, attacker: Node2D, historical_credit: Dictionary, receipt: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("take_feature_periodic_damage", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(historical_credit), _enemy_ports.to_domain(receipt)]))

func take_feature_periodic_chain_damage(amount: int, attacker: Node2D, historical_credit: Dictionary, receipt: Dictionary, batch: RefCounted) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("take_feature_periodic_chain_damage", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(historical_credit), _enemy_ports.to_domain(receipt), _enemy_ports.to_domain(batch)]))

func take_feature_child_damage(amount: int, attacker: Node2D, historical_credit: Dictionary, receipt: Dictionary, batch: RefCounted) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("take_feature_child_damage", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(historical_credit), _enemy_ports.to_domain(receipt), _enemy_ports.to_domain(batch)]))

func _wake_dormant_from_received_damage(
	attacker: Node2D,
	actual_damage: int,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_wake_dormant_from_received_damage", [_enemy_ports.to_domain(attacker), _enemy_ports.to_domain(actual_damage)]))

func _apply_damage_core(
	amount: int,
	attacker: Node2D,
	damage_context: Dictionary,
	causes_struck: bool,
	delivery_identity: Variant = null,
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_damage_core", [_enemy_ports.to_domain(amount), _enemy_ports.to_domain(attacker), _enemy_ports.to_domain(damage_context), _enemy_ports.to_domain(causes_struck), _enemy_ports.to_domain(delivery_identity)]))

func consume_direct_magic_compatibility_roll() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("consume_direct_magic_compatibility_roll", []))

func _apply_poison_tick_damage() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_poison_tick_damage", []))

func can_receive_damage() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("can_receive_damage", []))

func _mark_death_pending() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_mark_death_pending", []))

func _begin_death() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_begin_death", []))

func _finish_death_after_animation(animation_seconds: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_finish_death_after_animation", [_enemy_ports.to_domain(animation_seconds)]))

func apply_poison(
	tick_damage: int,
	seconds: float,
	interval_seconds := 1.0
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("apply_poison", [_enemy_ports.to_domain(tick_damage), _enemy_ports.to_domain(seconds), _enemy_ports.to_domain(interval_seconds)]))

func apply_control(seconds: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("apply_control", [_enemy_ports.to_domain(seconds)]))

func apply_entrapment(
	effect: Dictionary,
	boundary_snapshot: Dictionary,
	caster_actor: Node2D
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("apply_entrapment", [_enemy_ports.to_domain(effect), _enemy_ports.to_domain(boundary_snapshot), _enemy_ports.to_domain(caster_actor)]))

func clear_entrapment(reason := "cleared") -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("clear_entrapment", [_enemy_ports.to_domain(reason)]))

func entrapment_active() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("entrapment_active", []))

func entrapment_state_snapshot() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("entrapment_state_snapshot", []))

func accepts_external_attack_from(source_actor: Node) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("accepts_external_attack_from", [_enemy_ports.to_domain(source_actor)]))

func control_immunity_snapshot() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("control_immunity_snapshot", []))

static func _explicit_control_immunity(source: Dictionary) -> bool:
	return EnemyLegacyContext.owner_context().shared._explicit_control_immunity(source)

func _update_entrapment_state(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_entrapment_state", [_enemy_ports.to_domain(delta)]))

func apply_charm(seconds: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("apply_charm", [_enemy_ports.to_domain(seconds)]))

func canonical_red_poison_active() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("canonical_red_poison_active", []))

func _update_status_effects(delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_status_effects", [_enemy_ports.to_domain(delta)]))

func _apply_health_stage_mechanics() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_health_stage_mechanics", []))

func _apply_health_stage_rage_on_damage() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_health_stage_rage_on_damage", []))

func _boss_stage_search_due() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_boss_stage_search_due", []))

func _boss_stage_search_action_legal() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_boss_stage_search_action_legal", []))

func _retarget(delta := 0.0, safe_checked_player: Node2D = null) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_retarget", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(safe_checked_player)]))

func _hc_owner_optional_budget_scope_valid(scope: Array) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_owner_optional_budget_scope_valid", [_enemy_ports.to_domain(scope)]))

func _hc_owner_optional_budget_runnable() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_owner_optional_budget_runnable", []))

func _owner_optional_budget_try_begin() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_owner_optional_budget_try_begin", []))

func _owner_optional_budget_suspend() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_owner_optional_budget_suspend", []))

func _owner_optional_budget_resume() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_owner_optional_budget_resume", []))

func _owner_optional_budget_end() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_owner_optional_budget_end", []))

func _owner_decision_window_due() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_owner_decision_window_due", []))

func _owner_decision_commit_deadline() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_owner_decision_commit_deadline", []))

func _owner_decision_record_served() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_owner_decision_record_served", []))

func _owner_decision_record_boss_stage_served() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_owner_decision_record_boss_stage_served", []))

func _ordinary_attack_visual_move_override_allowed() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_ordinary_attack_visual_move_override_allowed", []))

func _retarget_internal(delta := 0.0, safe_checked_player: Node2D = null) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_retarget_internal", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(safe_checked_player)]))

func _add_threat(source:Node2D,amount:float)->void:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_add_threat", [_enemy_ports.to_domain(source), _enemy_ports.to_domain(amount)]))

func _target_switch_challenge_wins(
	current_target: Node2D,
	challenger: Node2D,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_switch_challenge_wins", [_enemy_ports.to_domain(current_target), _enemy_ports.to_domain(challenger)]))

func _target_candidate_is_live(candidate: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_target_candidate_is_live", [_enemy_ports.to_domain(candidate)]))

func _summon_intercepts_current_pursuit(
	candidate: SummonActor,
	distance_gu: float,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_summon_intercepts_current_pursuit", [_enemy_ports.to_domain(candidate), _enemy_ports.to_domain(distance_gu)]))

func _slide_collision_intercepting_summon() -> SummonActor:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_slide_collision_intercepting_summon", []))

func _threat_for(source:Node2D)->float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_threat_for", [_enemy_ports.to_domain(source)]))

func _decay_threat(delta:float)->void:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_decay_threat", [_enemy_ports.to_domain(delta)]))

func _return_to_spawn(
	delta := 1.0 / 60.0
) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_return_to_spawn", [_enemy_ports.to_domain(delta)]))

func _draw() -> void:
	var radius_px := 27.0 if is_boss else 16.0
	var ground_center_px := ground_indicator_center()
	var draw_procedural_fallback := should_draw_synthetic_ground_shadow()
	# Authored WIL actors may briefly wait for their asynchronously loaded
	# atlases. They already own a direction-aware source shadow, so that waiting
	# window must not leave a cached procedural ellipse under the final sprite.
	if draw_procedural_fallback:
		draw_ellipse_shadow(radius_px, ground_center_px)
	if _dying:
		return
	if is_targeted and (visual == null or not visual.uses_final_art()):
		# 细线选中圈与脚底接触阴影共面，避免形成托起Boss的发光平台。
		_draw_ground_indicator_ellipse(
			ground_center_px,
			ground_indicator_radii(),
			Color(1.0, 0.78, 0.18, 0.78),
			2.0,
		)
	var fallback_attacking := draw_procedural_fallback and visual != null and visual.is_fallback_attacking()
	var body_center_px := Vector2(0, -5) + (visual.fallback_lunge_offset_px(facing) if fallback_attacking else Vector2.ZERO)
	if draw_procedural_fallback:
		var body_color := Color(0.55, 0.11, 0.09) if is_boss else Color(0.30, 0.48, 0.18)
		var attack_scale:=visual.fallback_attack_scale() if visual!=null else Vector2.ONE
		var attack_angle:=visual.fallback_attack_angle(facing) if visual!=null else 0.0
		draw_set_transform(body_center_px,attack_angle,attack_scale)
		draw_circle(Vector2.ZERO, radius_px, body_color.lightened(0.18) if fallback_attacking else body_color)
		draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)
		if fallback_attacking:
			var strike_angle := facing.angle()
			var progress:=visual.fallback_attack_progress();var tip_px:=body_center_px+facing.normalized()*(radius_px+6.0+sin(progress*PI)*10.0)
			draw_arc(tip_px, radius_px + 8.0, strike_angle - 0.82, strike_angle + 0.82, 12, Color(1.0, 0.78, 0.26, 0.90), 4.0)
			draw_circle(tip_px,4.0+sin(progress*PI)*3.0,Color(1.0,0.9,0.5,0.82))
	# Phase two remains fully active for stats, skills and AI. Its former
	# persistent red ground outline is controlled independently and permanently
	# disabled; temporary attack telegraphs and the selected-target ring remain.
	if BOSS_PHASE_GROUND_RING_VISIBLE and is_boss and _boss_phase_two:
		draw_circle(
			Vector2(0, -5),
			radius_px + 7.0,
			Color(0.90, 0.15, 0.05, 0.22),
			false,
			4.0,
		)
	if poison_time > 0.0:
		# One compact green dot denotes the damage-over-time poison. Keeping it
		# below the HP bar avoids both the former three-diamond cluster and any
		# ground-ring/portal ambiguity.
		draw_circle(
			poison_indicator_center(),
			POISON_INDICATOR_DOT_RADIUS,
			Color(0.36, 0.92, 0.28, 0.90)
		)
	if canonical_red_poison_active():
		# Red poison shares the same row and uses one dot of its own. The fixed
		# center gap keeps both states distinct without forming a badge stack.
		draw_circle(
			red_poison_indicator_center(),
			POISON_INDICATOR_DOT_RADIUS,
			Color(0.92, 0.16, 0.12, 0.95)
		)
	if control_time > 0.0 or charm_time > 0.0:
		draw_circle(Vector2(0, -5), radius_px + 8.0, Color(0.35, 0.65, 1.0, 0.55), false, 3.0)
	# No dormant ground marker: dormancy is an AI state only. The former gray
	# translucent disc was never an authored affordance and duplicated the
	# normal contact shadow under every sleeping monster.
	if _boss_warning > 0.0:
		_draw_boss_warning_ground_projection()
	if draw_procedural_fallback:
		draw_circle(body_center_px + Vector2(-radius_px * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))
		draw_circle(body_center_px + Vector2(radius_px * 0.35, -3), 3.0, Color(0.95, 0.75, 0.25))


func _draw_boss_warning_ground_projection() -> void:
	var special: Dictionary = boss_rule.get("specialSkill", {})
	var warning_polygon_px := boss_warning_polygon_px(special)
	if warning_polygon_px.size() < 3:
		return
	var is_cone := (
		str(_boss_skill_footprint_snapshot.get("shape_type", ""))
		== SkillFootprintSnapshotScript.SHAPE_SECTOR_ARC
	)
	draw_colored_polygon(
		warning_polygon_px,
		Color(0.95, 0.12, 0.04, 0.22) if is_cone else Color(0.95, 0.18, 0.06, 0.16),
	)
	var outline_px := warning_polygon_px.duplicate()
	outline_px.append(warning_polygon_px[0])
	draw_polyline(
		outline_px,
		Color(1.0, 0.34, 0.08, 0.92) if is_cone else Color(1.0, 0.36, 0.12, 0.85),
		5.0,
		true,
	)


func boss_warning_polygon_px(special: Dictionary) -> PackedVector2Array:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("boss_warning_polygon_px", [_enemy_ports.to_domain(special)]))

func _create_boss_skill_footprint_snapshot(
	special: Dictionary,
	release_id: String,
) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_create_boss_skill_footprint_snapshot", [_enemy_ports.to_domain(special), _enemy_ports.to_domain(release_id)]))

func health_bar_anchor_y() -> float:
	var radius_px := 27.0 if is_boss else 16.0
	var fallback_y := -92.0 if bool(behavior_profile.get("largeClientBoss", false)) else -radius_px - 24.0
	return visual.health_bar_anchor_y(fallback_y) if visual != null else fallback_y


func name_label_anchor_y() -> float:
	return health_bar_anchor_y() - NAME_LABEL_SIZE.y - NAME_LABEL_HEALTH_BAR_GAP


func refresh_name_label_position() -> void:
	if overhead != null:
		overhead.set_anchor_y(health_bar_anchor_y())


func _refresh_overhead_health() -> void:
	_record_performance_counter(&"overhead_health_refreshes")
	if overhead != null:
		overhead.set_health(current_hp, max_hp)


func _request_actor_redraw() -> void:
	_record_performance_counter(&"actor_redraw_requests")
	queue_redraw()


## Parent CanvasItem redraw is only needed when this actor owns procedural
## fallback geometry. Final textured actors keep their Sprite2D/MonsterVisual
## redraw ownership; stateful one-shot callers above still use the explicit
## _request_actor_redraw() path.
func _request_actor_redraw_if_dynamic() -> void:
	var visual_started_usec := RuntimeDiagnostics.begin_timed_segment(
		&"enemy_visual_update_calls"
	)
	_request_actor_redraw_if_dynamic_internal()
	RuntimeDiagnostics.end_timed_segment(
		&"enemy_visual_update_usec",
		visual_started_usec,
	)


## Enemy-owned visual invalidation gate. MonsterVisual's separate `_process`
## remains outside this file; this probe covers only redraw work requested by
## EnemyActor physics/state transitions.
func _request_actor_redraw_if_dynamic_internal() -> void:
	if visual != null and visual.uses_final_art():
		return
	var draws_procedural_fallback := should_draw_synthetic_ground_shadow()
	var fallback_attack_active := visual != null and visual.is_fallback_attacking()
	if not draws_procedural_fallback and not fallback_attack_active:
		return
	_request_actor_redraw()


func poison_indicator_anchor_y() -> float:
	return health_bar_anchor_y() + MonsterOverheadScript.HEALTH_BAR_HEIGHT + 5.0


func red_poison_indicator_anchor_y() -> float:
	return poison_indicator_anchor_y()


func poison_indicator_center() -> Vector2:
	return Vector2(-POISON_INDICATOR_DOT_CENTER_OFFSET_X, poison_indicator_anchor_y())


func red_poison_indicator_center() -> Vector2:
	return Vector2(POISON_INDICATOR_DOT_CENTER_OFFSET_X, red_poison_indicator_anchor_y())


func poison_indicator_rect() -> Rect2:
	var center := poison_indicator_center()
	return Rect2(
		center - Vector2.ONE * POISON_INDICATOR_DOT_RADIUS,
		Vector2.ONE * POISON_INDICATOR_DOT_RADIUS * 2.0
	)


func red_poison_indicator_rect() -> Rect2:
	var center := red_poison_indicator_center()
	return Rect2(
		center - Vector2.ONE * POISON_INDICATOR_DOT_RADIUS,
		Vector2.ONE * POISON_INDICATOR_DOT_RADIUS * 2.0
	)


func ground_indicator_center() -> Vector2:
	# Targeting geometry owns an actor-local coordinate contract. Grounded
	# monsters always target the physics origin; visual alignment data may move
	# the sprite around that origin but must never move gameplay/UI targeting.
	# Flying/hovering profiles keep their explicit ground projection.
	var fallback := Vector2.ZERO
	return visual.target_ring_position(fallback) if visual != null else fallback


func should_draw_synthetic_ground_shadow() -> bool:
	return visual == null or visual.should_draw_procedural_fallback()


func ground_indicator_radii() -> Vector2:
	# Presentation-only crawling scale; never changes collision or attack reach.
	return MonsterTargetRingGeometryScript.resolve(monster_id, ground_footprint_indicator_radii())


func ground_footprint_indicator_radii() -> Vector2:
	return (
		WorldSpatialRulesScript.actor_footprint_radii_px(collision_radius_px)
		* TARGET_RING_FOOTPRINT_SCALE
	)


func _draw_ground_indicator_ellipse(
	center_px: Vector2,
	radii_px: Vector2,
	color: Color,
	width_px: float,
) -> void:
	var points := PackedVector2Array()
	for index in range(49):
		var angle := TAU * float(index) / 48.0
		points.append(
			center_px + Vector2(cos(angle) * radii_px.x, sin(angle) * radii_px.y)
		)
	draw_polyline(points, color, width_px, true)


func draw_ellipse_shadow(radius_px: float, center_px := Vector2.ZERO) -> void:
	draw_set_transform(center_px, 0.0, Vector2(1.0, 0.36))
	draw_circle(Vector2.ZERO, radius_px, Color(0, 0, 0, 0.30))
	draw_circle(Vector2(0, -radius_px * 0.08), radius_px * 0.56, Color(0, 0, 0, 0.58))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _update_boss_skill(delta: float, distance_gu: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_update_boss_skill", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(distance_gu)]))

func _settle_boss_skill_activation(special: Dictionary, skill_radius_gu: float, damage_multiplier: int) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_settle_boss_skill_activation", [_enemy_ports.to_domain(special), _enemy_ports.to_domain(skill_radius_gu), _enemy_ports.to_domain(damage_multiplier)]))

func _boss_skill_targets(radius_gu: float, snapshot := {}) -> Array[Node2D]:
	_ensure_enemy_domain()
	var result: Array[Node2D] = []
	result.assign(_enemy_ports.to_legacy(domain_model.callv("_boss_skill_targets", [_enemy_ports.to_domain(radius_gu), _enemy_ports.to_domain(snapshot)])))
	return result

func _apply_boss_skill_status(victim: Node2D, special: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_apply_boss_skill_status", [_enemy_ports.to_domain(victim), _enemy_ports.to_domain(special)]))

func request_surrounded_relocation(blocking_neighbor_count: int) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("request_surrounded_relocation", [_enemy_ports.to_domain(blocking_neighbor_count)]))

const HCPolicy := preload("res://scripts/monster_ai_package/policy.gd")
const HCSearch := preload("res://scripts/monster_ai_package/path_search.gd")
const HCScheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
## ATTACK_START_FRAME_AB is a throwaway experiment.  It owns only admission
## scheduling for a new ordinary melee attack; committed actions and all
## physics/status work remain on the production path.
static var _attack_ab_mode: String:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_mode
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_mode = value

static var _attack_ab_epoch: int:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_epoch
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_epoch = value

static var _attack_ab_epoch_attempts: int:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_epoch_attempts
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_epoch_attempts = value

static var _attack_ab_epoch_starts: int:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_epoch_starts
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_epoch_starts = value

static var _attack_ab_prune_epoch: int:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_prune_epoch
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_prune_epoch = value

static var _attack_ab_stats: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_stats
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_stats = value

static var _attack_ab_queue: Array[Dictionary]:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_queue
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_queue = value

static var _attack_ab_test_epoch_override: int:
	get: return EnemyLegacyContext.owner_context().shared._attack_ab_test_epoch_override
	set(value): EnemyLegacyContext.owner_context().shared._attack_ab_test_epoch_override = value

var _attack_ab_pending_target: WeakRef:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_target)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_target = _enemy_ports.to_domain(value)

var _attack_ab_pending_target_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_target_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_target_id = _enemy_ports.to_domain(value)

var _attack_ab_pending_target_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_target_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_target_life = _enemy_ports.to_domain(value)

var _attack_ab_pending_source_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_source_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_source_life = _enemy_ports.to_domain(value)

var _attack_ab_pending_map: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_map)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_map = _enemy_ports.to_domain(value)

var _attack_ab_pending_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_generation = _enemy_ports.to_domain(value)

var _attack_ab_pending_started_usec: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_started_usec)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_started_usec = _enemy_ports.to_domain(value)

var _attack_ab_pending_requested_epoch: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._attack_ab_pending_requested_epoch)
	set(value):
		_ensure_enemy_domain()
		domain_model._attack_ab_pending_requested_epoch = _enemy_ports.to_domain(value)

var _hc_last_start_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_last_start_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_last_start_tick = _enemy_ports.to_domain(value)

var _hc_release_seq: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_release_seq)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_release_seq = _enemy_ports.to_domain(value)

var _hc_settled_seq: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_settled_seq)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_settled_seq = _enemy_ports.to_domain(value)

var _hc_active_release_id: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_active_release_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_active_release_id = _enemy_ports.to_domain(value)

var _hc_attack_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_attack_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_attack_scratch = _enemy_ports.to_domain(value)

var _hc_motion_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_scratch = _enemy_ports.to_domain(value)

var _hc_last_reason: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_last_reason)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_last_reason = _enemy_ports.to_domain(value)

var _hc_blocker_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_blocker_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_blocker_id = _enemy_ports.to_domain(value)

var _hc_starts: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_starts)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_starts = _enemy_ports.to_domain(value)

var _hc_settlements: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_settlements)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_settlements = _enemy_ports.to_domain(value)

var _hc_legal_slides: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_legal_slides)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_legal_slides = _enemy_ports.to_domain(value)

var _hc_damage_dirty: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_damage_dirty)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_damage_dirty = _enemy_ports.to_domain(value)

var _hc_damage_observations: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_damage_observations)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_damage_observations = _enemy_ports.to_domain(value)

var _hc_known_target_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_known_target_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_known_target_id = _enemy_ports.to_domain(value)

var _hc_known_ground: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_known_ground)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_known_ground = _enemy_ports.to_domain(value)

var _hc_observed: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_observed)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_observed = _enemy_ports.to_domain(value)

var _hc_investigation_arrived: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_investigation_arrived)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_investigation_arrived = _enemy_ports.to_domain(value)

var _hc_next_observation_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_next_observation_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_next_observation_ms = _enemy_ports.to_domain(value)

var _hc_observation_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_observation_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_observation_scope = _enemy_ports.to_domain(value)

var _hc_pursuit_session: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_pursuit_session)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_pursuit_session = _enemy_ports.to_domain(value)

var _hc_step_override: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_step_override)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_step_override = _enemy_ports.to_domain(value)

var _hc_flank_waypoint: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_waypoint)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_waypoint = _enemy_ports.to_domain(value)

var _hc_flank_anchor: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_anchor)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_anchor = _enemy_ports.to_domain(value)

var _hc_surround_anchor: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_surround_anchor)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_surround_anchor = _enemy_ports.to_domain(value)

var _hc_surround_goal: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_surround_goal)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_surround_goal = _enemy_ports.to_domain(value)

var _hc_surround_slot: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_surround_slot)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_surround_slot = _enemy_ports.to_domain(value)

var _hc_surround_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_surround_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_surround_scope = _enemy_ports.to_domain(value)

var _hc_route: PackedVector2Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_route)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_route = _enemy_ports.to_domain(value)

var _hc_route_index: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_route_index)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_route_index = _enemy_ports.to_domain(value)

var _hc_path_token: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_token)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_token = _enemy_ports.to_domain(value)

var _hc_path_pending: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_pending)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_pending = _enemy_ports.to_domain(value)

var _hc_path_status: String:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_status)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_status = _enemy_ports.to_domain(value)

var _hc_path_anchor: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_anchor)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_anchor = _enemy_ports.to_domain(value)

var _hc_path_retry_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_retry_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_retry_ms = _enemy_ports.to_domain(value)

var _hc_path_context: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_context)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_context = _enemy_ports.to_domain(value)

var _hc_path_map: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_map)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_map = _enemy_ports.to_domain(value)

var _hc_path_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_generation = _enemy_ports.to_domain(value)

var _hc_path_revision: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_path_revision)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_path_revision = _enemy_ports.to_domain(value)

var _hc_failed_edges: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_failed_edges)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_failed_edges = _enemy_ports.to_domain(value)

var _hc_scheduler: HCScheduler:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_scheduler)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_scheduler = _enemy_ports.to_domain(value)

var _hc_motion_window: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_window)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_window = _enemy_ports.to_domain(value)

var _hc_window_remaining: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_window_remaining)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_window_remaining = _enemy_ports.to_domain(value)

const HC_BLOCKED_SIDE_RETRY_MS := 200
var _hc_next_side_retry_ms: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_next_side_retry_ms)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_next_side_retry_ms = _enemy_ports.to_domain(value)

var _hc_blocked_wait_target_id: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_blocked_wait_target_id)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_blocked_wait_target_id = _enemy_ports.to_domain(value)

var _hc_blocked_wait_self: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_blocked_wait_self)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_blocked_wait_self = _enemy_ports.to_domain(value)

var _hc_blocked_wait_target: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_blocked_wait_target)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_blocked_wait_target = _enemy_ports.to_domain(value)

var _hc_owned_movement_call: bool:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_owned_movement_call)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_owned_movement_call = _enemy_ports.to_domain(value)

var _hc_world_collision_count: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_world_collision_count)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_world_collision_count = _enemy_ports.to_domain(value)

static var _hc_shared_static_query_tick: int:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_static_query_tick
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_static_query_tick = value

static var _hc_shared_safe_zone_tick_cache: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_safe_zone_tick_cache
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_safe_zone_tick_cache = value

static var _hc_shared_world_tick_cache: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_world_tick_cache
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_world_tick_cache = value

var _hc_world_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_world_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_world_scope = _enemy_ports.to_domain(value)

var _hc_safe_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_safe_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_safe_scope = _enemy_ports.to_domain(value)

var _hc_local_world_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_world_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_world_scope = _enemy_ports.to_domain(value)

var _hc_local_safe_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_safe_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_safe_scope = _enemy_ports.to_domain(value)

var _hc_local_world_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_world_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_world_tick = _enemy_ports.to_domain(value)

var _hc_local_safe_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_safe_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_safe_tick = _enemy_ports.to_domain(value)

var _hc_local_world_cache: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_world_cache)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_world_cache = _enemy_ports.to_domain(value)

var _hc_local_safe_cache: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_safe_cache)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_safe_cache = _enemy_ports.to_domain(value)

static var _hc_shared_walkable_tick_cache: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared._hc_shared_walkable_tick_cache
	set(value): EnemyLegacyContext.owner_context().shared._hc_shared_walkable_tick_cache = value

var _hc_local_walkable_scope: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_scope)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_scope = _enemy_ports.to_domain(value)

var _hc_local_walkable_context: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_context)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_context = _enemy_ports.to_domain(value)

var _hc_local_walkable_radius: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_radius)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_radius = _enemy_ports.to_domain(value)

var _hc_local_walkable_radius_px: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_radius_px)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_radius_px = _enemy_ports.to_domain(value)

var _hc_local_walkable_tick: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_tick)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_tick = _enemy_ports.to_domain(value)

var _hc_local_walkable_cache: Dictionary:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_local_walkable_cache)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_local_walkable_cache = _enemy_ports.to_domain(value)

static func configure_attack_ab_mode(mode: String) -> bool:
	return EnemyLegacyContext.owner_context().shared.configure_attack_ab_mode(mode)

static func attack_ab_test_reset_epoch() -> void:
	EnemyLegacyContext.owner_context().shared.attack_ab_test_reset_epoch()

static func attack_ab_test_attempt(process_epoch: int) -> String:
	return EnemyLegacyContext.owner_context().shared.attack_ab_test_attempt(process_epoch)

static func _attack_ab_claim_quota(limited: bool) -> bool:
	return EnemyLegacyContext.owner_context().shared._attack_ab_claim_quota(limited)

static func reset_attack_ab_diagnostics() -> void:
	EnemyLegacyContext.owner_context().shared.reset_attack_ab_diagnostics()

static func attack_ab_diagnostics() -> Dictionary:
	return EnemyLegacyContext.owner_context().shared.attack_ab_diagnostics()

static func _attack_ab_stat(name: String, amount := 1) -> void:
	EnemyLegacyContext.owner_context().shared._attack_ab_stat(name, amount)

static func _attack_ab_sync_epoch() -> void:
	EnemyLegacyContext.owner_context().shared._attack_ab_sync_epoch()

func _attack_ab_clear_pending() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_attack_ab_clear_pending", []))

func _attack_ab_remove_self_from_queue() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_attack_ab_remove_self_from_queue", []))

func _attack_ab_prune_queue() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_attack_ab_prune_queue", []))

func _attack_ab_queue_head_is_self() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_ab_queue_head_is_self", []))

func _attack_ab_cancel(reason: String) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_attack_ab_cancel", [_enemy_ports.to_domain(reason)]))

func _attack_ab_defer(hit_target: Node2D, reason: String) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_attack_ab_defer", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(reason)]))

func _attack_ab_pending_matches(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_ab_pending_matches", [_enemy_ports.to_domain(hit_target)]))

func _attack_ab_admission_gate(hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_ab_admission_gate", [_enemy_ports.to_domain(hit_target)]))

func _attack_ab_admission_gate_internal(hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_attack_ab_admission_gate_internal", [_enemy_ports.to_domain(hit_target)]))

func _source176_ordinary_melee() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_source176_ordinary_melee", []))

func _source176_melee_reach_ok(offset_gu: Vector2, tolerance: float) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_source176_melee_reach_ok", [_enemy_ports.to_domain(offset_gu), _enemy_ports.to_domain(tolerance)]))

func _source176_basic_melee_geometry_clear(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_source176_basic_melee_geometry_clear", [_enemy_ports.to_domain(hit_target)]))

func _hc_standard_melee() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_standard_melee", []))

func _hc_optional_pursuit_melee() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_optional_pursuit_melee", []))

func _hc_exclusion_reason() -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_exclusion_reason", []))

func hc_package_policy_snapshot() -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("hc_package_policy_snapshot", []))

func _hc_preferred(hit_target: Node2D) -> float:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_preferred", [_enemy_ports.to_domain(hit_target)]))

func _hc_target_usable(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_target_usable", [_enemy_ports.to_domain(hit_target)]))

func _hc_access(hit_target: Node2D, tolerance := 0.0, fresh_world := false) -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_access", [_enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(tolerance), _enemy_ports.to_domain(fresh_world)]))

func _hc_frontline_at(a: Vector2, b: Vector2, hit_target: Node2D) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_frontline_at", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b), _enemy_ports.to_domain(hit_target)]))

var _hc_motion_candidate_index: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_index)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_index = _enemy_ports.to_domain(value)

var _hc_motion_candidate_revision: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_revision)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_revision = _enemy_ports.to_domain(value)

var _hc_motion_candidate_map: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_map)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_map = _enemy_ports.to_domain(value)

var _hc_motion_candidate_generation: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_generation)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_generation = _enemy_ports.to_domain(value)

var _hc_motion_candidate_life: int:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_life)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_life = _enemy_ports.to_domain(value)

var _hc_motion_candidate_radius: float:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_radius)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_radius = _enemy_ports.to_domain(value)

var _hc_motion_candidate_low: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_low)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_low = _enemy_ports.to_domain(value)

var _hc_motion_candidate_high: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_high)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_high = _enemy_ports.to_domain(value)

var _hc_motion_candidate_buckets: Rect2i:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_candidate_buckets)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_candidate_buckets = _enemy_ports.to_domain(value)

static var compute_optimization_test_mode: int:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_test_mode
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_test_mode = value

static var compute_optimization_shadow_checks: int:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_checks
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_checks = value

static var compute_optimization_shadow_missing_identities: int:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_missing_identities
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_missing_identities = value

static var compute_optimization_shadow_mismatches: int:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_mismatches
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_mismatches = value

static var compute_optimization_shadow_supersets: int:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_supersets
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_supersets = value

static var compute_optimization_shadow_first_mismatch: Dictionary:
	get: return EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_first_mismatch
	set(value): EnemyLegacyContext.owner_context().shared.compute_optimization_shadow_first_mismatch = value

var _hc_motion_shadow_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_motion_shadow_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_motion_shadow_scratch = _enemy_ports.to_domain(value)

func _hc_motion_clear(a: Vector2, b: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_motion_clear", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _hc_motion_clear_internal(a: Vector2, b: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_motion_clear_internal", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _hc_motion_shadow_check(a: Vector2, b: Vector2, candidate_result: bool) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_motion_shadow_check", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b), _enemy_ports.to_domain(candidate_result)]))

static func _hc_motion_shadow_original_core(a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float) -> bool:
	return EnemyLegacyContext.owner_context().shared._hc_motion_shadow_original_core(a, b, c, ra, rb)

func _delivery_observation_identity(record: Variant, victim: Node, child: String) -> Variant:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_delivery_observation_identity", [_enemy_ports.to_domain(record), _enemy_ports.to_domain(victim), _enemy_ports.to_domain(child)]))

func _hc_life(node: Node) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_life", [_enemy_ports.to_domain(node)]))

func _observe_pending_attack_cancellation(reason: String) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_observe_pending_attack_cancellation", [_enemy_ports.to_domain(reason)]))

func _hc_try_start(hit_target: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_try_start", [_enemy_ports.to_domain(hit_target)]))

func _hc_settle(record: Dictionary) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_settle", [_enemy_ports.to_domain(record)]))

func _hc_release_id() -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_release_id", []))

func _hc_finalize_boss_facing() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_finalize_boss_facing", []))

func _source176_take_tick_decision() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_source176_take_tick_decision", []))

func _source176_pursuit_permission_valid() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_source176_pursuit_permission_valid", []))

func _retain_source176_pursuit_permission() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_retain_source176_pursuit_permission", []))

func _hc_tick_melee(delta: float, physics_delta: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_tick_melee", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(physics_delta)]))

func _hc_step_can_end() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_step_can_end", []))

func _hc_world_between(a: Vector2, b: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_world_between", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _hc_refresh_static_query_cache() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_refresh_static_query_cache", []))

func _hc_static_query_scope(include_safe_zone_owner: bool) -> Array:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_static_query_scope", [_enemy_ports.to_domain(include_safe_zone_owner)]))

func _hc_point_inside_safe_zone(point_screen_px: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_point_inside_safe_zone", [_enemy_ports.to_domain(point_screen_px)]))

func _hc_decision_scope() -> Array:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_decision_scope", []))

static func configure_pursuit_process_budget_mode(mode: String) -> bool:
	return EnemyLegacyContext.owner_context().shared.configure_pursuit_process_budget_mode(mode)

static func configure_new_step_decision_interval_for_test(interval_ms: int) -> bool:
	return EnemyLegacyContext.owner_context().shared.configure_new_step_decision_interval_for_test(interval_ms)

static func configure_owner_decision_interval_for_test(interval_ms: int) -> bool:
	return EnemyLegacyContext.owner_context().shared.configure_owner_decision_interval_for_test(interval_ms)

static func configure_owner_optional_budget_for_test(enabled: bool) -> void:
	EnemyLegacyContext.owner_context().shared.configure_owner_optional_budget_for_test(enabled)

static func configure_attack_visual_policy_for_test(
	instant_contact_settle: bool,
	visual_move_override: bool,
) -> void:
	EnemyLegacyContext.owner_context().shared.configure_attack_visual_policy_for_test(instant_contact_settle, visual_move_override)

static func configure_residual_phase_probe(enabled: bool) -> void:
	EnemyLegacyContext.owner_context().shared.configure_residual_phase_probe(enabled)

static func reset_residual_phase_probe() -> void:
	EnemyLegacyContext.owner_context().shared.reset_residual_phase_probe()

static func residual_phase_probe_snapshot() -> Dictionary:
	return EnemyLegacyContext.owner_context().shared.residual_phase_probe_snapshot()

func _residual_phase_probe_begin(phase: StringName) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_residual_phase_probe_begin", [_enemy_ports.to_domain(phase)]))

func _residual_phase_probe_close() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_residual_phase_probe_close", []))

static func configure_pursuit_process_trace(enabled: bool) -> void:
	EnemyLegacyContext.owner_context().shared.configure_pursuit_process_trace(enabled)

static func reset_pursuit_process_budget_diagnostics() -> void:
	EnemyLegacyContext.owner_context().shared.reset_pursuit_process_budget_diagnostics()

static func reset_pursuit_process_budget_state_for_test() -> void:
	EnemyLegacyContext.owner_context().shared.reset_pursuit_process_budget_state_for_test()

static func _pursuit_process_stat(name: String, amount := 1) -> void:
	EnemyLegacyContext.owner_context().shared._pursuit_process_stat(name, amount)

static func pursuit_process_budget_diagnostics() -> Dictionary:
	return EnemyLegacyContext.owner_context().shared.pursuit_process_budget_diagnostics()

func _hc_pursuit_budget_scope() -> Array:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_pursuit_budget_scope", []))

func _hc_pursuit_budget_kind_runnable(kind: StringName) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_pursuit_budget_kind_runnable", [_enemy_ports.to_domain(kind)]))

func _pursuit_process_budget_begin(kind: StringName) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_pursuit_process_budget_begin", [_enemy_ports.to_domain(kind)]))

func _pursuit_process_budget_finish(result: bool) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_pursuit_process_budget_finish", [_enemy_ports.to_domain(result)]))

func _pursuit_process_new_step_result(
	result: bool,
	pursuit_process_budgeted: bool,
	frequency_applies: bool,
) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_pursuit_process_new_step_result", [_enemy_ports.to_domain(result), _enemy_ports.to_domain(pursuit_process_budgeted), _enemy_ports.to_domain(frequency_applies)]))

func _pursuit_process_budget_end() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_pursuit_process_budget_end", []))

func _hc_dispatch_pursuit_process(kind: StringName) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_dispatch_pursuit_process", [_enemy_ports.to_domain(kind)]))

func _hc_refresh_observation() -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_refresh_observation", []))

func _acquire_cold_damage_target(source: Node2D) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_acquire_cold_damage_target", [_enemy_ports.to_domain(source)]))

func _hc_existing_target_activation_valid(candidate: Node2D) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_existing_target_activation_valid", [_enemy_ports.to_domain(candidate)]))

func _hc_received_damage(source: Node2D, amount: float) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_received_damage", [_enemy_ports.to_domain(source), _enemy_ports.to_domain(amount)]))

func _hc_forget(candidate: Node2D) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_forget", [_enemy_ports.to_domain(candidate)]))

func _hc_cancel_path() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_cancel_path", []))

func _hc_environment_revision() -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_environment_revision", []))

func _hc_sync_navigation() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_sync_navigation", []))

func _hc_edge_key(a: Vector2i, b: Vector2i) -> String:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_edge_key", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _hc_edge_blocked(a: Vector2i, b: Vector2i) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_edge_blocked", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b)]))

func _hc_point_walkable(p: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_point_walkable", [_enemy_ports.to_domain(p)]))

func _hc_point_walkable_uncached(p: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_point_walkable_uncached", [_enemy_ports.to_domain(p)]))

func _hc_goal_points(anchor: Vector2) -> Dictionary:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_goal_points", [_enemy_ports.to_domain(anchor)]))

func _hc_goal_cache_key(anchor: Vector2) -> Array:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_goal_cache_key", [_enemy_ports.to_domain(anchor)]))

func _hc_submit_path(anchor: Vector2) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_submit_path", [_enemy_ports.to_domain(anchor)]))

func _hc_path_job_current(token: int) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_path_job_current", [_enemy_ports.to_domain(token)]))

func _hc_path_completed(token: int, status: String, route: PackedVector2Array) -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_path_completed", [_enemy_ports.to_domain(token), _enemy_ports.to_domain(status), _enemy_ports.to_domain(route)]))

func _hc_crowd_position_goal(hit_target: Node2D) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_crowd_position_goal", [_enemy_ports.to_domain(hit_target)]))

func _hc_crowd_position_goal_internal(hit_target: Node2D) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_crowd_position_goal_internal", [_enemy_ports.to_domain(hit_target)]))

func _hc_publish_crowd_goal(previous_goal: Vector2, new_goal: Vector2) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_publish_crowd_goal", [_enemy_ports.to_domain(previous_goal), _enemy_ports.to_domain(new_goal)]))

func _hc_neighbor(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_neighbor", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(direct)]))

func _hc_neighbor_internal(current: Vector2, hit_target: Node2D, direct: Vector2i) -> Vector2i:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_neighbor_internal", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(direct)]))

func _hc_direct_source_route_clear(origin: Vector2, destination: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_direct_source_route_clear", [_enemy_ports.to_domain(origin), _enemy_ports.to_domain(destination)]))

func _hc_fail_step() -> void:
	_ensure_enemy_domain()
	_enemy_ports.to_legacy(domain_model.callv("_hc_fail_step", []))

func _hc_track_motion(delta: float, remaining_before: float, remaining_after: float) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_track_motion", [_enemy_ports.to_domain(delta), _enemy_ports.to_domain(remaining_before), _enemy_ports.to_domain(remaining_after)]))

var _hc_flank_starts: PackedVector2Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_starts)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_starts = _enemy_ports.to_domain(value)

var _hc_flank_ends: PackedVector2Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_ends)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_ends = _enemy_ports.to_domain(value)

var _hc_flank_expansions: PackedFloat64Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_expansions)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_expansions = _enemy_ports.to_domain(value)

var _hc_flank_option_offsets: PackedInt32Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_option_offsets)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_option_offsets = _enemy_ports.to_domain(value)

var _hc_flank_outputs: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_outputs)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_outputs = _enemy_ports.to_domain(value)

var _hc_flank_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_scratch = _enemy_ports.to_domain(value)

func _hc_choose_blocked_neighbor(current: Vector2, anchor: Vector2, victim_anchor: Vector2, hit_target: Node2D, cell: Vector2i, far_approach: bool) -> Vector2i:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_choose_blocked_neighbor", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(anchor), _enemy_ports.to_domain(victim_anchor), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(cell), _enemy_ports.to_domain(far_approach)]))

func _hc_frontline_candidates(a: Vector2, b: Vector2, hit_target: Node2D, candidates: Array) -> int:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_frontline_candidates", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(candidates)]))

func _hc_motion_candidates(a: Vector2, b: Vector2, candidates: Array) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_motion_candidates", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b), _enemy_ports.to_domain(candidates)]))

var _hc_flank_destination_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_flank_destination_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_flank_destination_scratch = _enemy_ports.to_domain(value)

func _hc_flank_destination_clear(point: Vector2) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_flank_destination_clear", [_enemy_ports.to_domain(point)]))

func _hc_flank_destination_candidates_clear(point: Vector2, candidates: Array) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_flank_destination_candidates_clear", [_enemy_ports.to_domain(point), _enemy_ports.to_domain(candidates)]))

const HC_APPROACH_DIRECTIONS: Array[Vector2i] = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1)]
const HC_APPROACH_SIDE_ORDER: Array[int] = [1,-1,2,-2,3,-3,4]

func _hc_far_approach_waypoint(current: Vector2, anchor: Vector2, cell: Vector2i, preferred_sign: float) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_far_approach_waypoint", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(anchor), _enemy_ports.to_domain(cell), _enemy_ports.to_domain(preferred_sign)]))

var _hc_contact_flank_scratch: Array:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_contact_flank_scratch)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_contact_flank_scratch = _enemy_ports.to_domain(value)

func _hc_contact_flank(current: Vector2, anchor: Vector2, victim_anchor: Vector2, hit_target: Node2D, cell: Vector2i, preferred_sign: float) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_contact_flank", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(anchor), _enemy_ports.to_domain(victim_anchor), _enemy_ports.to_domain(hit_target), _enemy_ports.to_domain(cell), _enemy_ports.to_domain(preferred_sign)]))

func _hc_flank_leg_endpoint(current: Vector2, waypoint: Vector2) -> Vector2:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_flank_leg_endpoint", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(waypoint)]))

func _hc_prepare_flank_batch(current: Vector2, anchor: Vector2, cell: Vector2i) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_prepare_flank_batch", [_enemy_ports.to_domain(current), _enemy_ports.to_domain(anchor), _enemy_ports.to_domain(cell)]))

const HCPPolyRuntime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const HCPPolyPursuit := preload("res://scripts/map_editor/polygon/poly_pursuit_driver.gd")
var _hc_polygon_step_override: Vector2:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_polygon_step_override)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_polygon_step_override = _enemy_ports.to_domain(value)

var _hc_polygon_pursuit: HCPPolyPursuit:
	get:
		_ensure_enemy_domain()
		return _enemy_ports.to_legacy(domain_model._hc_polygon_pursuit)
	set(value):
		_ensure_enemy_domain()
		domain_model._hc_polygon_pursuit = _enemy_ports.to_domain(value)

func _hc_polygon_neighbor_clear(a: Vector2, b: Vector2, from_cell: Vector2i, to_cell: Vector2i) -> bool:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_polygon_neighbor_clear", [_enemy_ports.to_domain(a), _enemy_ports.to_domain(b), _enemy_ports.to_domain(from_cell), _enemy_ports.to_domain(to_cell)]))

func _hc_polygon_nonhc_neighbor(current_ground_gu: Vector2, engagement_target: Node2D) -> Vector2i:
	_ensure_enemy_domain()
	return _enemy_ports.to_legacy(domain_model.callv("_hc_polygon_nonhc_neighbor", [_enemy_ports.to_domain(current_ground_gu), _enemy_ports.to_domain(engagement_target)]))
