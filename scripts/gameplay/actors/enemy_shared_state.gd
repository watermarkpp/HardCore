extends RefCounted

var services: Dictionary
var actor_links: Object
var _owner_thread := OS.get_thread_caller_id()
var _configured := false
const CombatActionStateScript := preload("res://scripts/gameplay/actors/enemy_combat_action_state.gd")
# Serial legacy adapter and S both use this exact rule/state instance.
const HCM30ContextTokenScript := preload("res://scripts/monster_ai_package/m30/context_token.gd")
const DamageLedgerObserverScript := preload("res://scripts/damage_ledger_observer.gd")
const FeatureDamageBatchScript := preload("res://scripts/features/runtime/damage_batch.gd")
const AttackTimingScript := preload("res://scripts/monster_attack_timing.gd")
# Exact transaction fault seam, callable only in an explicit test fixture.
const HCM30WalkPhaseScript := preload("res://scripts/monster_ai_package/m30/walk_phase.gd")
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
const AUDIO_SERVICE_NEGATIVE_CACHE_MSEC := 1000
const CANONICAL_PERCEPTION_SOURCE := "hc.source.monster.canonical.perception"
const HCPolicy := preload("res://scripts/monster_ai_package/policy.gd")
const HCSearch := preload("res://scripts/monster_ai_package/path_search.gd")
const HCScheduler := preload("res://scripts/monster_ai_package/path_scheduler.gd")
const FrameBudget := preload("res://scripts/layers/runtime/execution/frame_budget.gd")
## ATTACK_START_FRAME_AB is a throwaway experiment.  It owns only admission
## scheduling for a new ordinary melee attack; committed actions and all
## physics/status work remain on the production path.
const HC_BLOCKED_SIDE_RETRY_MS := 200
const HC_APPROACH_DIRECTIONS: Array[Vector2i] = [Vector2i(1,0),Vector2i(1,1),Vector2i(0,1),Vector2i(-1,1),Vector2i(-1,0),Vector2i(-1,-1),Vector2i(0,-1),Vector2i(1,-1)]
const HC_APPROACH_SIDE_ORDER: Array[int] = [1,-1,2,-2,3,-3,4]
const HCPPolyRuntime := preload("res://scripts/map_editor/polygon/poly_runtime.gd")
const HCPPolyPursuit := preload("res://scripts/map_editor/polygon/poly_pursuit_driver.gd")
var _crowd_query_candidate_count := 0
var _crowd_steering_evaluation_count := 0
var _retarget_full_scan_count := 0
var _retarget_decision_count := 0
var _target_grid_last_refresh_msec := -1
var _target_grid: Dictionary = {}
var _target_grid_node_ids: Dictionary = {}
var _target_grid_group_scan_count := 0
var _target_grid_candidate_count := 0
var _background_ai_evaluation_count := 0
var _background_fast_path_skip_count := 0
var _foreground_ai_tick_count := 0
var _background_deep_sleep_entry_count := 0
var _background_deep_sleep_wakeup_count := 0
var _physics_move_count := 0
var _environment_guard_check_count := 0
var _runtime_map_id_property_list_scan_count := 0
var _hc_shared_goal_cache: Dictionary = {}
var _hc_shared_goal_cache_order: Array = []

var _movement_authority_loaded := false
var _movement_authority_load_failed := false
var _movement_authority_by_id: Dictionary = {}
var _attack_range_policy_loaded := false
var _attack_range_policy_load_failed := false
var _attack_range_policy_by_id: Dictionary = {}
## Monster SFX is an observer of the existing actor/visual lifecycle.  Keep a
## shared lifecycle-aware service lookup; per-actor group scans in the physics
## hot path would turn a presentation hook into a scaling cost.
var _pursuit_process_budget_mode := "immediate"
var _pursuit_process_budget_stats: Dictionary = {}
var _new_step_decision_interval_ms := 0
var _owner_decision_interval_ms: Variant

var _owner_optional_budget_enabled: Variant

var _ordinary_contact_instant_settle_enabled: Variant

var _ordinary_attack_visual_move_override_enabled: Variant

var _residual_phase_probe_enabled := false
var _residual_phase_probe_totals: Dictionary = {}
var _residual_phase_probe_calls: Dictionary = {}
var _residual_phase_probe_source := "disabled"
var _attack_ab_mode := "immediate"
var _attack_ab_epoch := -1
var _attack_ab_epoch_attempts := 0
var _attack_ab_epoch_starts := 0
var _attack_ab_prune_epoch := -1
var _attack_ab_stats: Dictionary = {}
var _attack_ab_queue: Array[Dictionary] = []
var _attack_ab_test_epoch_override := -1
var _hc_shared_static_query_tick := -1
var _hc_shared_safe_zone_tick_cache: Dictionary = {}
var _hc_shared_world_tick_cache: Dictionary = {}
var _hc_shared_walkable_tick_cache: Dictionary = {}
var compute_optimization_test_mode := 1
var compute_optimization_shadow_checks := 0
var compute_optimization_shadow_missing_identities := 0
var compute_optimization_shadow_mismatches := 0
var compute_optimization_shadow_supersets := 0
var compute_optimization_shadow_first_mismatch: Dictionary = {}
func configure(bindings: Dictionary, links: Object) -> bool:
	if _configured or OS.get_thread_caller_id() != _owner_thread:
		push_error("Enemy shared state must be configured exactly once by its owner")
		return false
	services = bindings
	actor_links = links
	_owner_decision_interval_ms = _hardcore_int_setting(
		"hardcore/performance/owner_decision_interval_ms", 300, [100, 200, 300]
	)
	_owner_optional_budget_enabled = _hardcore_bool_setting(
		"hardcore/performance/owner_optional_budget_enabled", true
	)
	_ordinary_contact_instant_settle_enabled = _hardcore_bool_setting(
		"hardcore/performance/ordinary_contact_instant_settle", true
	)
	_ordinary_attack_visual_move_override_enabled = _hardcore_bool_setting(
		"hardcore/performance/ordinary_attack_visual_move_override", true
	)
	_configured = true
	return true

func owner_thread_id() -> int:
	return _owner_thread

func _live(value: Variant) -> bool:
	return actor_links.is_present(value)

func _supports(value: Object, method: StringName) -> bool:
	return actor_links.supports(value, method)

func reset_runtime_map_id_diagnostics() -> void:
	_runtime_map_id_property_list_scan_count = 0

func runtime_map_id_diagnostics() -> Dictionary:
	return {
		"property_list_scans": _runtime_map_id_property_list_scan_count,
	}

func _record_performance_counter(field: StringName, amount := 1) -> void:
	services.RuntimeDiagnostics.increment_performance_counter(field, amount)
	match field:
		&"crowd_query_candidates":
			_crowd_query_candidate_count += amount
		&"crowd_steering_evaluations":
			_crowd_steering_evaluation_count += amount
		&"retarget_full_scans":
			_retarget_full_scan_count += amount
		&"retarget_decisions":
			_retarget_decision_count += amount
		&"retarget_target_group_scans":
			_target_grid_group_scan_count += amount
		&"retarget_target_candidates":
			_target_grid_candidate_count += amount
		&"background_ai_evaluations":
			_background_ai_evaluation_count += amount
		&"background_fast_path_skips":
			_background_fast_path_skip_count += amount
		&"foreground_ai_ticks":
			_foreground_ai_tick_count += amount
		&"background_deep_sleep_entries":
			_background_deep_sleep_entry_count += amount
		&"background_deep_sleep_wakeups":
			_background_deep_sleep_wakeup_count += amount
		&"physics_moves":
			_physics_move_count += amount
		&"environment_guard_checks":
			_environment_guard_check_count += amount

func _hardcore_int_setting(path: String, fallback: int, allowed: Array[int]) -> int:
	var configured = int(services.ProjectSettings.get_setting(path, fallback))
	return configured if allowed.has(configured) else fallback

func _hardcore_bool_setting(path: String, fallback: bool) -> bool:
	var configured: Variant = services.ProjectSettings.get_setting(path, fallback)
	return bool(configured) if configured is bool else fallback

## Owner decision window for ordinary foreground pursuit.  This is deliberately
## separate from the source cadence and from the existing new-step probe: it
## only suppresses rich observation/retarget/planning, never attack admission,
## committed actions, or the physics movement/collision lane.
## The 300 ms window is the accepted production contract. It never gates
## attack admission, committed damage, physics movement, or collision.
func _load_attack_range_policy_once() -> void:
	if _attack_range_policy_loaded or _attack_range_policy_load_failed:
		return
	var file = services.source_text.open_published(MONSTER_ATTACK_RANGE_POLICY_PATH)
	if file == null:
		_attack_range_policy_load_failed = true
		push_error("EnemyActor: cannot open attack range policy: ", MONSTER_ATTACK_RANGE_POLICY_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not (parsed is Dictionary):
		_attack_range_policy_load_failed = true
		push_error("EnemyActor: invalid JSON in attack range policy")
		return
	var root = parsed as Dictionary
	if str(root.get("contractId", "")) != "monster.attack_range_policy.v1":
		_attack_range_policy_load_failed = true
		push_error("EnemyActor: attack range policy contract mismatch")
		return
	var records: Variant = root.get("records", null)
	if records == null or not (records is Array):
		_attack_range_policy_load_failed = true
		push_error("EnemyActor: missing records array in attack range policy")
		return
	var seen_ids: Dictionary = {}
	for record_variant: Variant in (records as Array):
		if not (record_variant is Dictionary):
			_attack_range_policy_load_failed = true
			push_error("EnemyActor: malformed attack range policy record")
			return
		var record = record_variant as Dictionary
		var monster_id_value = int(record.get("monsterId", -1))
		var range_gu_value: Variant = record.get("attackRangeGu", null)
		if monster_id_value <= 0 or seen_ids.has(monster_id_value):
			_attack_range_policy_load_failed = true
			push_error("EnemyActor: invalid or duplicate attack range policy monsterId: ", monster_id_value)
			return
		if range_gu_value is bool or not (range_gu_value is int or range_gu_value is float):
			_attack_range_policy_load_failed = true
			push_error("EnemyActor: non-numeric attackRangeGu for monsterId: ", monster_id_value)
			return
		var range_gu = float(range_gu_value)
		if not is_finite(range_gu) or range_gu <= 0.0:
			_attack_range_policy_load_failed = true
			push_error("EnemyActor: invalid attackRangeGu for monsterId: ", monster_id_value)
			return
		seen_ids[monster_id_value] = true
		_attack_range_policy_by_id[monster_id_value] = record.duplicate(true)
	_attack_range_policy_loaded = true
	_attack_range_policy_load_failed = false


func _attack_range_policy_record_for_id(requested_monster_id: int) -> Dictionary:
	_load_attack_range_policy_once()
	if _attack_range_policy_load_failed:
		return {}
	var raw: Variant = _attack_range_policy_by_id.get(requested_monster_id, null)
	if raw == null or not (raw is Dictionary):
		return {}
	return (raw as Dictionary).duplicate(true)


func _load_movement_authority_once() -> void:
	if _movement_authority_loaded or _movement_authority_load_failed:
		return
	var file = services.source_text.open_published(MONSTER_RUNTIME_AUTHORITY_PATH)
	if file == null:
		_movement_authority_load_failed = true
		push_error("EnemyActor: cannot open movement authority: ", MONSTER_RUNTIME_AUTHORITY_PATH)
		return
	var json_text = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or not (parsed is Dictionary):
		_movement_authority_load_failed = true
		push_error("EnemyActor: invalid JSON in movement authority")
		return
	var root: Dictionary = parsed
	var records: Variant = root.get("records", null)
	if records == null or not (records is Array):
		_movement_authority_load_failed = true
		push_error("EnemyActor: missing records array in movement authority")
		return
	var seen_ids: Dictionary = {}
	for record_variant: Variant in (records as Array):
		if not (record_variant is Dictionary):
			continue
		var record: Dictionary = record_variant
		var raw_id: Variant = record.get("monster_id", null)
		if raw_id == null:
			continue
		var monster_id_value = int(raw_id)
		if monster_id_value <= 0:
			continue
		if seen_ids.has(monster_id_value):
			_movement_authority_load_failed = true
			push_error("EnemyActor: duplicate monster_id in movement authority: ", monster_id_value)
			return
		seen_ids[monster_id_value] = true
		_movement_authority_by_id[monster_id_value] = record
	_movement_authority_loaded = true
	_movement_authority_load_failed = false


func _movement_authority_record_for_id(
	requested_monster_id: int
) -> Dictionary:
	_load_movement_authority_once()
	if _movement_authority_load_failed:
		return {}
	var raw: Variant = _movement_authority_by_id.get(requested_monster_id, null)
	if raw == null or not (raw is Dictionary):
		return {}
	return (raw as Dictionary).duplicate(true)


func legal_spawn_facing_directions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for neighbor: Vector2i in MonsterNeighborStepPolicyScript.NEIGHBOR_DELTAS:
		result.append(
			_screen_facing_for_ground_direction(
				MonsterNeighborStepPolicyScript.desired_ground_direction(neighbor)
			)
		)
	return result


func _ground_delta_gu_between_screen_positions(
	origin_screen_position_px: Vector2,
	target_screen_position_px: Vector2,
) -> Vector2:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
		target_screen_position_px - origin_screen_position_px
	)


func _screen_facing_for_ground_direction(direction_ground: Vector2) -> Vector2:
	if direction_ground.length_squared() <= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		return Vector2.DOWN
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		direction_ground.normalized()
	).normalized()


func _safe_zone_point_ground_gu_from_screen_reference(
	point_screen_px: Vector2,
	zone: Dictionary,
) -> Vector2:
	# Absolute screen positions include the map design-centre projection, while
	# GroundUnitSpace only converts deltas. Anchor the conversion to the same
	# formal safe-zone point in both spaces so the design-centre translation
	# cancels before any GU geometry is evaluated.
	if zone.has("center") and zone.has("center_ground_gu"):
		var center_screen_px: Vector2 = zone.get("center", Vector2.ZERO)
		var center_ground_gu: Vector2 = zone.get("center_ground_gu", Vector2.ZERO)
		return center_ground_gu + GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
			point_screen_px - center_screen_px
		)
	var polygon_screen_px = _packed_vector2_array_from_variant(zone.get("polygon", []))
	var polygon_ground_gu = _packed_vector2_array_from_variant(zone.get("polygon_ground_gu", []))
	if not polygon_screen_px.is_empty() and polygon_screen_px.size() == polygon_ground_gu.size():
		return polygon_ground_gu[0] + GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
			point_screen_px - polygon_screen_px[0]
		)
	return Vector2.INF


func _packed_vector2_array_from_variant(raw_points: Variant) -> PackedVector2Array:
	if raw_points is PackedVector2Array:
		return raw_points as PackedVector2Array
	var result = PackedVector2Array()
	if not raw_points is Array:
		return result
	for raw_point: Variant in raw_points:
		if raw_point is Vector2:
			result.append(raw_point)
		elif raw_point is Array and raw_point.size() >= 2:
			result.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return result


func _target_grid_cell(screen_position_px: Vector2) -> Vector2i:
	return Vector2i(
		floori(screen_position_px.x / TARGET_GRID_CELL_SIZE_PX.x),
		floori(screen_position_px.y / TARGET_GRID_CELL_SIZE_PX.y),
	)


func reset_performance_diagnostics() -> void:
	_target_grid_last_refresh_msec = -1
	_target_grid.clear()
	_target_grid_node_ids.clear()
	_crowd_query_candidate_count = 0
	_crowd_steering_evaluation_count = 0
	_retarget_full_scan_count = 0
	_retarget_decision_count = 0
	_target_grid_group_scan_count = 0
	_target_grid_candidate_count = 0
	_background_ai_evaluation_count = 0
	_background_fast_path_skip_count = 0
	_foreground_ai_tick_count = 0
	_background_deep_sleep_entry_count = 0
	_background_deep_sleep_wakeup_count = 0
	_physics_move_count = 0
	_environment_guard_check_count = 0
	services.RuntimeDiagnostics.reset_performance_window()


func performance_diagnostics() -> Dictionary:
	var result = {
		"crowd_grid_builds": 0,
		"crowd_grid_actor_scans": 0,
		"crowd_query_candidates": _crowd_query_candidate_count,
		"crowd_steering_evaluations": _crowd_steering_evaluation_count,
		"retarget_full_scans": _retarget_full_scan_count,
		"retarget_decisions": _retarget_decision_count,
		"retarget_target_group_scans": _target_grid_group_scan_count,
		"retarget_target_candidates": _target_grid_candidate_count,
		"background_ai_evaluations": _background_ai_evaluation_count,
		"background_fast_path_skips": _background_fast_path_skip_count,
		"foreground_ai_ticks": _foreground_ai_tick_count,
		"background_deep_sleep_entries": _background_deep_sleep_entry_count,
		"background_deep_sleep_wakeups": _background_deep_sleep_wakeup_count,
		"physics_moves": _physics_move_count,
		"environment_guard_checks": _environment_guard_check_count,
	}
	if services.RuntimeDiagnostics.performance_enabled():
		var merged_counters = services.RuntimeDiagnostics.performance_counters()
		for field: String in services.RuntimeDiagnostics.PERFORMANCE_FIELDS:
			if merged_counters.has(field):
				result[field] = merged_counters[field]
	return result


func _explicit_control_immunity(source: Dictionary) -> bool:
	for key: String in [
		"control_immune", "controlImmune", "immune_to_control", "immuneToControl"
	]:
		if source.has(key) and bool(source.get(key, false)):
			return true
	for value: Variant in source.values():
		if value is Dictionary and _explicit_control_immunity(value):
			return true
	return false


func configure_attack_ab_mode(mode: String) -> bool:
	var normalized = mode.strip_edges().to_lower()
	if normalized not in ["immediate", "queued"]:
		return false
	_attack_ab_mode = normalized
	_attack_ab_epoch = -1
	_attack_ab_epoch_attempts = 0
	_attack_ab_queue.clear()
	_attack_ab_test_epoch_override = -1
	return true

func attack_ab_test_reset_epoch() -> void:
	reset_attack_ab_diagnostics()

func attack_ab_test_attempt(process_epoch: int) -> String:
	_attack_ab_test_epoch_override = process_epoch
	return "STARTED" if _attack_ab_claim_quota(true) else "DEFERRED"

func _attack_ab_claim_quota(limited: bool) -> bool:
	_attack_ab_sync_epoch()
	if limited and _attack_ab_epoch_attempts >= 1:
		return false
	_attack_ab_epoch_attempts += 1
	_attack_ab_stat("admission_attempts")
	return true

func reset_attack_ab_diagnostics() -> void:
	_attack_ab_epoch_starts = 0
	_attack_ab_prune_epoch = -1
	_attack_ab_epoch = -1
	_attack_ab_epoch_attempts = 0
	_attack_ab_queue.clear()
	_attack_ab_test_epoch_override = -1
	_attack_ab_stats = {
		"mode": _attack_ab_mode, "ordinary_clear_calls": 0,
		"admission_attempts": 0, "reserve_attempts": 0, "starts": 0, "settlement_attempts": 0,
		"settlements": 0, "completed": 0,
		"deferred": 0, "budget_denied": 0, "cancelled": 0,
		"cancel_reasons": {}, "defer_reasons": {}, "wait_usec": [], "process_epochs": 0,
		"max_attempts_per_process": 0,
	}

func attack_ab_diagnostics() -> Dictionary:
	if _attack_ab_stats.is_empty():
		reset_attack_ab_diagnostics()
	var result = _attack_ab_stats.duplicate(true)
	result["mode"] = _attack_ab_mode
	result["process_epoch"] = _attack_ab_epoch
	result["epoch_attempts"] = _attack_ab_epoch_attempts
	result["max_starts_per_process"] = maxi(int(result.get("max_starts_per_process", 0)), _attack_ab_epoch_starts)
	result["queue_length"] = _attack_ab_queue.size()
	result["max_attempts_per_process"] = maxi(
		int(result.get("max_attempts_per_process", 0)), _attack_ab_epoch_attempts)
	return result

func _attack_ab_stat(name: String, amount := 1) -> void:
	if _attack_ab_stats.is_empty():
		reset_attack_ab_diagnostics()
	_attack_ab_stats[name] = int(_attack_ab_stats.get(name, 0)) + amount

func _attack_ab_sync_epoch() -> void:
	var epoch = _attack_ab_test_epoch_override if _attack_ab_test_epoch_override >= 0 else services.Engine.get_process_frames()
	if epoch == _attack_ab_epoch:
		return
	if _attack_ab_epoch >= 0:
		_attack_ab_stats["max_attempts_per_process"] = maxi(
			int(_attack_ab_stats.get("max_attempts_per_process", 0)), _attack_ab_epoch_attempts)
		_attack_ab_stats["max_starts_per_process"] = maxi(
			int(_attack_ab_stats.get("max_starts_per_process", 0)), _attack_ab_epoch_starts)
	_attack_ab_epoch_starts = 0
	_attack_ab_epoch = epoch
	_attack_ab_epoch_attempts = 0
	_attack_ab_stat("process_epochs")

func _hc_motion_shadow_original_core(a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float) -> bool:
	# Frozen bd73a256 predicate, independent of the optimized policy function.
	var r = maxf(0.0, ra + rb)
	var before = a.distance_squared_to(c)
	var after = b.distance_squared_to(c)
	if before < r * r:
		return (b - a).dot(a - c) < -HCPolicy.EPS or after < before - HCPolicy.EPS
	var q = Geometry2D.get_closest_point_to_segment(c, a, b)
	return q.distance_squared_to(c) < r * r - HCPolicy.EPS

func configure_pursuit_process_budget_mode(mode: String) -> bool:
	var normalized = mode.strip_edges().to_lower()
	if normalized not in ["immediate", "budgeted", "dispatched"]:
		return false
	_pursuit_process_budget_mode = normalized
	services.HCDecisionBudget.configure_pursuit_dispatch_enabled(normalized == "dispatched")
	_pursuit_process_budget_stats = {}
	return true

func configure_new_step_decision_interval_for_test(interval_ms: int) -> bool:
	if interval_ms not in [0, 200]:
		return false
	_new_step_decision_interval_ms = interval_ms
	_pursuit_process_budget_stats = {}
	return true

func configure_owner_decision_interval_for_test(interval_ms: int) -> bool:
	if interval_ms not in [0, 100, 200, 300]:
		return false
	_owner_decision_interval_ms = interval_ms
	return true

func configure_owner_optional_budget_for_test(enabled: bool) -> void:
	_owner_optional_budget_enabled = enabled

func configure_attack_visual_policy_for_test(
	instant_contact_settle: bool,
	visual_move_override: bool,
) -> void:
	_ordinary_contact_instant_settle_enabled = instant_contact_settle
	_ordinary_attack_visual_move_override_enabled = visual_move_override

func configure_residual_phase_probe(enabled: bool) -> void:
	_residual_phase_probe_enabled = enabled
	_residual_phase_probe_source = "env_enabled" if enabled else "disabled"

func reset_residual_phase_probe() -> void:
	_residual_phase_probe_totals = {}
	_residual_phase_probe_calls = {}

func residual_phase_probe_snapshot() -> Dictionary:
	return {
		"enabled": _residual_phase_probe_enabled,
		"source": _residual_phase_probe_source,
		"totals_usec": _residual_phase_probe_totals.duplicate(),
		"calls": _residual_phase_probe_calls.duplicate(),
	}

func configure_pursuit_process_trace(enabled: bool) -> void:
	services.HCDecisionBudget.configure_pursuit_process_trace(enabled)

func reset_pursuit_process_budget_diagnostics() -> void:
	_pursuit_process_budget_stats = {
		"requests": 0, "grants": 0, "fifo_denied": 0, "budget_denied": 0,
		"observation_deferred": 0, "new_step_deferred": 0,
		"new_step_attempts": 0, "new_step_due_wait": 0,
		"new_step_success": 0, "new_step_fail": 0,
		"owner_decision_due": 0, "owner_decision_opportunities": 0, "owner_decision_wait": 0,
		"owner_decision_served": 0,
		"service_timeline": [],
	}
	services.HCDecisionBudget.reset_pursuit_process_diagnostics()

func reset_pursuit_process_budget_state_for_test() -> void:
	services.HCDecisionBudget.reset_pursuit_process_state()

func _pursuit_process_stat(name: String, amount := 1) -> void:
	if _pursuit_process_budget_stats.is_empty():
		reset_pursuit_process_budget_diagnostics()
	_pursuit_process_budget_stats[name] = int(_pursuit_process_budget_stats.get(name, 0)) + amount

func pursuit_process_budget_diagnostics() -> Dictionary:
	if _pursuit_process_budget_stats.is_empty():
		reset_pursuit_process_budget_diagnostics()
	var result = _pursuit_process_budget_stats.duplicate(true)
	result["mode"] = _pursuit_process_budget_mode
	result["new_step_decision_interval_ms"] = _new_step_decision_interval_ms
	result["owner_decision_interval_ms"] = _owner_decision_interval_ms
	result["owner_optional_budget_enabled"] = _owner_optional_budget_enabled
	result["ordinary_contact_instant_settle"] = _ordinary_contact_instant_settle_enabled
	result["ordinary_attack_visual_move_override"] = _ordinary_attack_visual_move_override_enabled
	result["decision_budget"] = services.HCDecisionBudget.pursuit_process_snapshot()
	return result

