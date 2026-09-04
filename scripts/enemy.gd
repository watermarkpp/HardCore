class_name EnemyActor
extends CharacterBody2D

const MonsterVisualScript := preload("res://scripts/monster_visual.gd")
const MonsterOverheadScript := preload("res://scripts/monster_overhead.gd")
const MonsterGroundRuntimeDiagnosticOverlayScript := preload(
	"res://scripts/monster_ground_runtime_diagnostic_overlay.gd"
)
const GroundUnitSpace := preload("res://scripts/ground_unit_space.gd")
const MonsterIdentityScript := preload("res://scripts/monster_identity.gd")
const MonsterUnitAdapterScript := preload("res://scripts/monster_unit_adapter.gd")
const SkillFootprintSnapshotScript := preload(
	"res://scripts/skills/skill_footprint_snapshot.gd"
)
const EntrapmentBoundaryControllerScript := preload(
	"res://scripts/entrapment_boundary_controller.gd"
)
const RuntimeCombatSpatialIndexScript := preload(
	"res://scripts/runtime_combat_spatial_index.gd"
)
const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")
const MonsterRangedProjectileEffectScript := preload(
	"res://scripts/monster_ranged_projectile_effect.gd"
)
const MonsterTargetMagicEffectScript := preload(
	"res://scripts/monster_target_magic_effect.gd"
)
const MonsterMovementCadenceScript := preload(
	"res://scripts/monster_movement_cadence.gd"
)
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
const MONSTER_RUNTIME_AUTHORITY_PATH := (
	"res://assets/data/monster_runtime_authority_v1.json"
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
const ENEMY_MOTION_MASK := WorldSpatialRulesScript.WORLD_LAYER | WorldSpatialRulesScript.PLAYER_LAYER
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
const LAST_SAFE_REFRESH_DISTANCE_GU := 2.0
const PROJECTILE_OBSTACLE_SAMPLE_STEP_GU := 0.25
const ATTACK_PATH_OBSTACLE_SAMPLE_STEP_GU := PROJECTILE_OBSTACLE_SAMPLE_STEP_GU
const CORPSE_HOLD_SECONDS := 2.0

static var _crowd_grid_physics_frame := -1
static var _crowd_grid: Dictionary = {}
static var _crowd_grid_build_count := 0
static var _crowd_grid_actor_scan_count := 0
static var _crowd_query_candidate_count := 0
static var _crowd_steering_evaluation_count := 0
static var _retarget_full_scan_count := 0
static var _retarget_decision_count := 0
static var _target_grid_last_refresh_msec := -1
static var _target_grid: Dictionary = {}
static var _target_grid_node_ids: Dictionary = {}
static var _target_grid_group_scan_count := 0
static var _target_grid_candidate_count := 0
static var _background_ai_evaluation_count := 0
static var _background_fast_path_skip_count := 0
static var _foreground_ai_tick_count := 0
static var _background_deep_sleep_entry_count := 0
static var _background_deep_sleep_wakeup_count := 0
static var _physics_move_count := 0
static var _environment_guard_check_count := 0

static var _movement_authority_loaded := false
static var _movement_authority_load_failed := false
static var _movement_authority_by_id: Dictionary = {}

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

var monster_data: Dictionary = {}
var monster_id := -1
var display_name := "怪物"
var max_hp := 20
var current_hp := 20
var attack_min := 1
var attack_max := 2
var defense := 0
var magic_defense := 0
var agility := WarriorCombatMath.BASE_AGILITY
var accuracy := WarriorCombatMath.BASE_HIT
var life_type := ""
var undead := false
var anti_stealth := false
var anti_poison := 0
var level := 1
var move_speed_gu_per_sec := MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(55.0)
var aggro_radius_gu := 12.0
var attack_range_gu := MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(38.0)
var target: Node2D:
	set(value):
		var changed := target != value
		target = value
		if changed:
			_reset_terrain_navigation_state()
			_target_stable_remaining_seconds = (
				TARGET_SWITCH_MIN_STABLE_SECONDS
				if is_instance_valid(target)
				else 0.0
			)
		if not is_instance_valid(target):
			_target_focus_tick_ms = 0
		elif changed:
			_refresh_target_focus()
			if not _background_maintenance_running:
				_leave_background_deep_sleep()
var primary_target: PlayerCharacter
var is_boss := false
var runtime_map_id: int = -1
var runtime_ground_gu_to_screen_position_px := Callable()
var runtime_screen_to_ground_position_px := Callable()
var combat_spatial_index: RuntimeCombatSpatialIndexScript
var spatial_actor_runtime_id: int = -1
## FREEZE-P0.1: fail-closed projection diagnostics.
var missing_projection_rejection_count := 0
var projection_rejection_reason := &""
var poison_time := 0.0
var poison_damage := 0
var poison_tick_interval_seconds := 1.0
var poison_tick_elapsed_seconds := 0.0
var control_time := 0.0:
	set(value):
		if value > 0.0 and control_time <= 0.0:
			_control_anchor_ground_gu = _screen_position_px_to_ground_position_gu(global_position)
			if _movement_step_active:
				_cancel_autonomous_step(true)
		control_time = value
var charm_time := 0.0:
	set(value):
		if value > 0.0 and charm_time <= 0.0 and _movement_step_active:
			_cancel_autonomous_step(true)
		charm_time = value
var dormant := false
var life_steal_ratio := 0.0
var control_on_hit_seconds := 0.0
var control_chance_denominator_base := 0
var is_targeted := false
var facing := Vector2.DOWN
var movement_facing := Vector2.DOWN
var visual: MonsterVisual
var name_label: Label
var overhead: Variant
var ground_runtime_diagnostic_overlay: Node2D
var combat_radius_gu := MonsterUnitAdapterScript.footprint_radius_px_to_combat_radius_gu(
	ArtSpec.MONSTER_COLLISION_RADIUS_PX
)
var collision_radius_px := float(ArtSpec.MONSTER_COLLISION_RADIUS_PX)
var environment_blocker: Node
var _dying := false
var _death_pending := false
var boss_rule: Dictionary = {}
var behavior_profile: Dictionary = {}
var service_ai_code := -1
var service_move_interval_ms := 0
var stationary := false
var area_attack_rule: Dictionary = {}
var summon_rule: Dictionary = {}
var attack_delivery_rule: Dictionary = {}

var _attack_timer := 0.0
var _attack_interval := 1.55
var _attack_animation_duration := 0.46
var _attack_hit_delay := 0.0
var _pending_attack_time := -1.0
var _pending_attack_damage := 0
var _pending_attack_target: Node2D
var _pending_attack_release_record: Dictionary = {}
var last_magic_attack_resolution: Dictionary = {}
var last_physical_hit_resolution: Dictionary = {}
var _retarget_timer := 0.0
var _target_stable_remaining_seconds := 0.0
var _crowd_steering_timer := 0.0
var _cached_crowd_separation := Vector2.ZERO
var _background_ai_timer := 0.0
var _background_wakeup_timer: Timer
var _background_deep_sleeping := false
var _background_last_wakeup_msec := 0
var _background_maintenance_running := false
var _background_accumulated_delta := 0.0
var _boss_skill_cooldown := 3.0
var _boss_warning := 0.0
var _boss_phase_two := false
var _boss_phase_enabled := true
var _boss_skill_enabled := true
var _boss_skill_direction_ground := Vector2.DOWN
var _boss_skill_footprint_snapshot: Dictionary = {}
var _last_boss_skill_hit := false
var _boss_health_stage := -1
var _boss_rage_time := 0.0
var _boss_base_move_speed_gu_per_sec := 0.0
var _boss_base_attack_interval := 0.0
var _burrowed := false
var _rng := RandomNumberGenerator.new()
## Spawn presentation uses an instance-local RNG so the one-time direction
## choice cannot advance combat, loot, summon, or status-effect randomness.
var _spawn_facing_rng := RandomNumberGenerator.new()
var _spawn_facing_seed_override := 0
var _spawn_facing_seed_override_active := false
var _spawn_facing_initialized := false
var _threat_table := {}
var _threat_decay_per_second := 4.0
var _leash_multiplier := 1.5
var _control_anchor_ground_gu := Vector2.INF
var _entrapment_controller: EntrapmentBoundaryControllerScript
var _entrapment_last_end_reason := ""
var _area_attack_cooldown := 0.0
var _area_attack_warning := 0.0
var _area_attack_footprint_snapshot: Dictionary = {}
var _area_attack_release_records: Array[Dictionary] = []
var _area_magic_warning := 0.0
var _area_magic_footprint_snapshot: Dictionary = {}
var _area_magic_release_records: Array[Dictionary] = []
var _last_attack_footprint_snapshot: Dictionary = {}
var _spatial_release_serial := 0
var _summon_cooldown := 0.0
var _summon_warning := 0.0
var _environment_guard_timer := 0.0
var _last_environment_safe_position_px := Vector2.INF
## The combat index already owns a live-position provider for narrow phase.
## Re-submit only actual position changes; static/background actors otherwise
## performed an identical projection + dictionary update on every physics tick.
var _last_spatial_index_screen_position_px := Vector2.INF
var actual_ground_motion_gu := Vector2.ZERO

var _movement_cadence
var _natural_regen := MonsterNaturalRegenPolicyScript.new()
var _target_acquisition_policy: MonsterTargetAcquisitionPolicyScript
var _target_acquisition_authority_failed_closed := true
var _target_focus_timeout_ms := 0
var _target_disengage_axis_cells := 0
var _target_focus_tick_ms := 0
var _movement_authority_failed_closed := false
var _movement_step_active := false
var _movement_step_start_ground_gu := Vector2.INF
var _movement_step_start_screen_px := Vector2.INF
var _movement_step_target_ground_gu := Vector2.INF
var _movement_step_distance_gu := 0.0
var _movement_step_neighbor := Vector2i.ZERO
var _movement_step_engagement_target_instance_id := 0
## Retain the existing caller scale as part of the step state for diagnostics
## and call-site compatibility. Runtime GU speed owns interpolation; this is
## the sole behavior multiplier applied by return/retreat paths.
var _movement_step_speed_scale := 1.0
var _movement_step_reason: StringName = &""
## A cadence grant creates a high-level pursuit intent. Once granted, the
## actor may chain neighbor cells at its runtime speed; cell completion reads
## only the already-selected live target and never calls retarget/broadphase.
var _continuous_pursuit_active := false
var _continuous_pursuit_speed_scale := 1.0
var _terrain_navigation_context: Dictionary = {}
var _terrain_path_waypoints: Array[Vector2i] = []
var _terrain_path_target_instance_id := 0
var _terrain_path_target_cell := Vector2i.ZERO
var _terrain_path_has_target_cell := false
var _terrain_no_path_until_ms := 0
var _terrain_failed_cell := Vector2i.ZERO
var _terrain_has_failed_cell := false
var _terrain_failed_cell_until_ms := 0


func setup(data: Dictionary, player_target: PlayerCharacter, caller_boss := false) -> void:
	var requested_id := MonsterIdentityScript.monster_id(data)
	if requested_id in RETIRED_SOURCE_ONLY_MONSTER_IDS:
		monster_data = {"monster_id": requested_id}
		monster_id = -1
		set_meta("retired_source_only", true)
		set_meta("canonical_rejected", true)
		return
	var canonical_entry := MonsterIdentityScript.require_catalog_entry(requested_id, "runtime")
	if canonical_entry.is_empty():
		monster_data = {"monster_id": requested_id}
		monster_id = -1
		set_meta("canonical_rejected", true)
		return
	var classification := str(canonical_entry.get("classification", ""))
	# Keep only canonical fields on the actor payload.  Legacy caller fields
	# (including combat stats, control flags, names, and aliases) must not leak
	# into later combat/death consumers.
	monster_data = {
		"monster_id": requested_id,
		"canonical_name": str(canonical_entry.get("canonical_name", "")),
		"classification": classification,
		"appearance_profile_id": str(canonical_entry.get("appearance_profile_id", "")),
		"drop_profile_id": str(canonical_entry.get("drop_profile_id", "")),
	}
	monster_id = requested_id
	# M02A: primary_target is the searchable player reference. A current combat
	# target exists only after the exact monster-id acquisition policy accepts it.
	target = null
	primary_target = player_target
	is_boss = classification == "boss"
	set_meta("caller_boss_ignored", bool(caller_boss) != is_boss)
	display_name = str(canonical_entry.get("canonical_name", ""))
	var combat: Dictionary = canonical_entry.get("combat", {})
	var stats: Dictionary = combat.get("stats", {})
	var runtime_projection: Dictionary = combat.get("runtime_projection", {})
	max_hp = maxi(1, int(stats.get("hp", 0)))
	current_hp = max_hp
	_natural_regen = MonsterNaturalRegenPolicyScript.new()
	defense = maxi(0, int(stats.get("defense", 0)))
	magic_defense = maxi(0, int(stats.get("magic_defense", 0)))
	attack_min = maxi(1, int(stats.get("attack_min", 0)))
	attack_max = maxi(attack_min, int(stats.get("attack_max", attack_min)))
	agility = maxi(1, int(runtime_projection.get("agility", WarriorCombatMath.BASE_AGILITY)))
	accuracy = maxi(0, int(runtime_projection.get("accuracy", WarriorCombatMath.BASE_HIT)))
	life_type = str(runtime_projection.get("life_type", ""))
	undead = bool(runtime_projection.get("undead", life_type == "不死系"))
	anti_stealth = bool(runtime_projection.get("anti_stealth", false))
	anti_poison = maxi(0, int(runtime_projection.get("anti_poison", 0)))
	level = maxi(1, int(stats.get("level", 0)))
	# Keep the existing canonical payload boundary while exposing only the
	# detail flags needed by current skill/runtime consumers.  Caller-provided
	# combat fields still never enter this dictionary.
	monster_data["level"] = level
	monster_data["accuracy"] = accuracy
	monster_data["life_type"] = life_type
	monster_data["undead"] = undead
	monster_data["anti_stealth"] = anti_stealth
	move_speed_gu_per_sec = MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(
		40.0 if is_boss else 58.0
	)
	behavior_profile = MonsterIdentityScript.behavior_profile(monster_data)
	_apply_behavior_profile()
	_apply_source_locked_special_delivery_override()
	if is_boss:
		boss_rule = MonsterIdentityScript.boss_rule(monster_data, GameData.boss_service_rules)
		# The generated canonical catalog is rebuilt by integration. Until that
		# rebuild lands, the exact ID-keyed service rule remains the authoritative
		# runtime override for this newly split special delivery.
		if monster_id == 124:
			var configured_rules: Variant = GameData.boss_service_rules.get(
				"runtimeRulesByMonsterId",
				{},
			)
			if configured_rules is Dictionary:
				var configured_rule: Variant = (configured_rules as Dictionary).get("124", {})
				if configured_rule is Dictionary and not (configured_rule as Dictionary).is_empty():
					boss_rule = (configured_rule as Dictionary).duplicate(true)
		if not boss_rule.is_empty():
			_apply_boss_rule()
	if stationary:
		move_speed_gu_per_sec = 0.0
	_configure_target_acquisition()
	_configure_movement_cadence()


func _apply_behavior_profile() -> void:
	var projection_gu := MonsterUnitAdapterScript.runtime_projection_gu(
		behavior_profile,
		move_speed_gu_per_sec,
		attack_range_gu,
		aggro_radius_gu,
	)
	move_speed_gu_per_sec = float(projection_gu.move_speed_gu_per_sec)
	attack_range_gu = float(projection_gu.attack_range_gu)
	aggro_radius_gu = float(projection_gu.aggro_radius_gu)
	var timing: Dictionary = behavior_profile.get("timing", {})
	if int(timing.get("attackIntervalMs", 0)) > 0:
		_attack_interval = float(timing.get("attackIntervalMs")) / 1000.0
	service_move_interval_ms = int(timing.get("moveIntervalMs", 0))
	service_ai_code = int(behavior_profile.get("serviceBehavior", {}).get("aiCode", -1))
	stationary = bool(behavior_profile.get("movement", {}).get("stationary", false))
	area_attack_rule = behavior_profile.get("areaAttack", {}).duplicate(true)
	attack_delivery_rule = behavior_profile.get("attackDelivery", {}).duplicate(true)
	_area_attack_cooldown = float(area_attack_rule.get("initialCooldownSeconds", 0.0))
	summon_rule = behavior_profile.get("summonRule", {}).duplicate(true)
	_summon_cooldown = float(summon_rule.get("initialCooldownSeconds", 0.0))
	if stationary:
		move_speed_gu_per_sec = 0.0
	life_steal_ratio = float(behavior_profile.get("lifeStealRatio", life_steal_ratio))
	dormant = bool(behavior_profile.get("dormant", dormant))
	var on_hit: Dictionary = behavior_profile.get("onHit", {})
	control_on_hit_seconds = float(on_hit.get("controlSeconds", control_on_hit_seconds))
	control_chance_denominator_base = maxi(
		0,
		int(on_hit.get("controlChanceDenominatorBase", control_chance_denominator_base)),
	)


func _apply_source_locked_special_delivery_override() -> void:
	# Keep the exact ID contract live even while integration is rebuilding the
	# generated canonical catalog from the edited source profiles.
	if monster_id != 70:
		return
	attack_range_gu = 1.0
	attack_delivery_rule = {
		"kind": "special_melee",
		"effectId": MONSTER_MAGIC_MELEE_EFFECT_ID,
		"damageChannel": "magic_defense",
		"bodyOnly": true,
		"rangeShape": "chebyshev_square",
		"rangeTiles": 1,
		"range_gu": 1.0,
		"hitDelaySeconds": 0.0,
		"presentationDelaySeconds": 0.3,
		"obstaclePolicy": "environment_adjacent_only",
	}


static func _load_movement_authority_once() -> void:
	if _movement_authority_loaded or _movement_authority_load_failed:
		return
	var file := FileAccess.open(MONSTER_RUNTIME_AUTHORITY_PATH, FileAccess.READ)
	if file == null:
		_movement_authority_load_failed = true
		push_error("EnemyActor: cannot open movement authority: ", MONSTER_RUNTIME_AUTHORITY_PATH)
		return
	var json_text := file.get_as_text()
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
		var monster_id_value := int(raw_id)
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


static func _movement_authority_record_for_id(
	requested_monster_id: int
) -> Dictionary:
	_load_movement_authority_once()
	if _movement_authority_load_failed:
		return {}
	var raw: Variant = _movement_authority_by_id.get(requested_monster_id, null)
	if raw == null or not (raw is Dictionary):
		return {}
	return (raw as Dictionary).duplicate(true)


func _configure_target_acquisition() -> bool:
	_target_acquisition_policy = MonsterTargetAcquisitionPolicyScript.new()
	var authority_record := _movement_authority_record_for_id(monster_id)
	var ok := _target_acquisition_policy.configure(authority_record, monster_id)
	var targeting: Dictionary = authority_record.get("targeting", {})
	_target_focus_timeout_ms = int(targeting.get("focus_timeout_ms", 0))
	_target_disengage_axis_cells = int(targeting.get("disengage_axis_cells", 0))
	ok = (
		ok
		and _target_focus_timeout_ms > 0
		and _target_disengage_axis_cells > 0
	)
	_target_acquisition_authority_failed_closed = not ok
	if not ok:
		set_meta("target_acquisition_authority_rejected", true)
		set_meta(
			"target_acquisition_authority_rejection_reason",
			(
				_target_acquisition_policy.rejection_reason
				if _target_acquisition_policy.failed_closed
				else "invalid_target_retention_authority"
			),
		)
		return false
	remove_meta("target_acquisition_authority_rejected")
	remove_meta("target_acquisition_authority_rejection_reason")
	return true


func _initial_acquisition_contains_ground_delta_gu(delta_ground_gu: Vector2) -> bool:
	return (
		not _target_acquisition_authority_failed_closed
		and _target_acquisition_policy != null
		and _target_acquisition_policy.contains_ground_delta_gu(delta_ground_gu)
	)


func _refresh_target_focus(now_ms_override := -1) -> void:
	_target_focus_tick_ms = (
		now_ms_override
		if now_ms_override >= 0
		else Time.get_ticks_msec()
	)


func _target_should_disengage(
	candidate: Node2D,
	now_ms_override := -1,
) -> bool:
	if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return true
	if _target_focus_timeout_ms <= 0 or _target_disengage_axis_cells <= 0:
		return true
	var now_ms := (
		now_ms_override
		if now_ms_override >= 0
		else Time.get_ticks_msec()
	)
	if _target_focus_tick_ms <= 0:
		_refresh_target_focus(now_ms)
	elif now_ms - _target_focus_tick_ms > _target_focus_timeout_ms:
		return true
	var origin_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		candidate.global_position
	)
	if not origin_ground_gu.is_finite() or not target_ground_gu.is_finite():
		return true
	var origin_cell := Vector2i(
		floori(origin_ground_gu.x),
		floori(origin_ground_gu.y),
	)
	var target_cell := Vector2i(
		floori(target_ground_gu.x),
		floori(target_ground_gu.y),
	)
	var axis_delta := (target_cell - origin_cell).abs()
	return (
		axis_delta.x > _target_disengage_axis_cells
		or axis_delta.y > _target_disengage_axis_cells
	)


func _configure_movement_cadence() -> bool:
	if monster_id <= 0:
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		return false
	var authority_record := _movement_authority_record_for_id(monster_id)
	if authority_record.is_empty():
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		return false
	var new_cadence := MonsterMovementCadenceScript.new()
	var now_ms := Time.get_ticks_msec()
	var ok: bool = new_cadence.configure(authority_record, now_ms)
	if not ok:
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		return false
	var movement: Dictionary = authority_record.get("movement", {})
	var raw_speed: Variant = movement.get("base_move_speed_gu_per_sec", null)
	if raw_speed == null or typeof(raw_speed) not in [TYPE_INT, TYPE_FLOAT]:
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		set_meta("movement_authority_rejection_reason", "missing_base_move_speed_gu_per_sec")
		return false
	var authority_speed := float(raw_speed)
	if not is_finite(authority_speed) or authority_speed < 0.0:
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		set_meta("movement_authority_rejection_reason", "invalid_base_move_speed_gu_per_sec")
		return false
	var authority_movement_enabled := bool(movement.get("movement_enabled", false))
	var authority_stationary := bool(movement.get("stationary", false))
	if (not authority_movement_enabled or authority_stationary) and not is_zero_approx(authority_speed):
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		set_meta("movement_authority_rejection_reason", "stationary_speed_must_be_zero")
		return false
	if authority_movement_enabled and not authority_stationary and authority_speed <= 0.0:
		_movement_authority_failed_closed = true
		set_meta("movement_authority_rejected", true)
		set_meta("movement_authority_rejection_reason", "active_speed_must_be_positive")
		return false
	_movement_cadence = new_cadence
	# The effective interval is the source of the actual continuous motor
	# speed.  Bind it once at setup; behavior/boss compatibility projections may
	# still describe historical data, but cannot replace this formal value.
	move_speed_gu_per_sec = authority_speed
	stationary = authority_stationary
	service_move_interval_ms = int(movement.get("walk_interval_ms", 0))
	if is_boss:
		# _apply_boss_rule() runs before this method and may have captured a
		# compatibility speed. Re-anchor all temporary boss multipliers to the
		# formal per-monster base after the final authority is bound.
		_boss_base_move_speed_gu_per_sec = move_speed_gu_per_sec
	_movement_authority_failed_closed = false
	remove_meta("movement_authority_rejected")
	remove_meta("movement_authority_rejection_reason")
	return true


func _request_autonomous_step(
	desired_direction_ground_gu: Vector2,
	speed_scale: float,
	use_crowd_steering: bool,
	reason: StringName,
	now_ms_override := -1,
	engagement_target: Node2D = null
) -> bool:
	if _movement_step_active:
		return false
	if _movement_authority_failed_closed:
		return false
	if _movement_cadence == null:
		return false
	if stationary:
		return false
	if dormant:
		return false
	if control_time > 0.0:
		return false
	if charm_time > 0.0:
		return false
	if not desired_direction_ground_gu.is_finite():
		return false
	if desired_direction_ground_gu.length() <= GroundUnitSpace.EPSILON_GU:
		return false
	var now_ms := now_ms_override
	if now_ms < 0:
		now_ms = Time.get_ticks_msec()
	var cadence_result: Dictionary = _movement_cadence.evaluate(now_ms)
	if cadence_result.authority_contract_violation:
		_movement_authority_failed_closed = true
		velocity = Vector2.ZERO
		return false
	if not cadence_result.granted:
		return false
	var creates_continuous_pursuit := (
		reason == &"pursuit"
		and is_instance_valid(engagement_target)
		and engagement_target == target
	)
	if creates_continuous_pursuit:
		_continuous_pursuit_active = true
		_continuous_pursuit_speed_scale = maxf(0.0, speed_scale)
	else:
		_clear_continuous_pursuit_intent()
	var started := _begin_autonomous_step_without_cadence(
		desired_direction_ground_gu,
		speed_scale,
		use_crowd_steering,
		reason,
		engagement_target,
	)
	if not started:
		_clear_continuous_pursuit_intent()
	return started


func _begin_autonomous_step_without_cadence(
	desired_direction_ground_gu: Vector2,
	speed_scale: float,
	use_crowd_steering: bool,
	reason: StringName,
	engagement_target: Node2D = null,
) -> bool:
	if _movement_step_active:
		return false
	if _movement_authority_failed_closed or stationary or dormant:
		return false
	if control_time > 0.0 or charm_time > 0.0:
		return false
	if not desired_direction_ground_gu.is_finite():
		return false
	if desired_direction_ground_gu.length() <= GroundUnitSpace.EPSILON_GU:
		return false
	var pursuit_ground := desired_direction_ground_gu.normalized()
	var steering_ground := pursuit_ground
	if use_crowd_steering:
		# The timer is advanced once from _physics_process. Step creation only
		# consumes the cached result, so several actors/step retries cannot bypass
		# the established 10 Hz per-actor steering ceiling.
		var separation_ground := _crowd_separation_for_motion(0.0)
		steering_ground = pursuit_ground + separation_ground * 0.72
		if steering_ground.dot(pursuit_ground) < 0.12:
			steering_ground += pursuit_ground * (
				0.12 - steering_ground.dot(pursuit_ground)
			)
	var neighbor := MonsterNeighborStepPolicyScript.neighbor_for_desired_ground_direction(
		steering_ground
	)
	if neighbor == Vector2i.ZERO:
		return false
	var current_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	if not current_ground_gu.is_finite():
		return false
	if reason == &"pursuit" and is_instance_valid(engagement_target):
		neighbor = _terrain_neighbor_for_pursuit(
			current_ground_gu,
			engagement_target,
			neighbor,
		)
		if neighbor == Vector2i.ZERO:
			return false
	var step := MonsterNeighborStepPolicyScript.build_neighbor_step(
		current_ground_gu,
		neighbor
	)
	if not bool(step.get("valid", false)):
		return false
	var target_ground_gu: Vector2 = step.get("target_ground_gu", Vector2.INF)
	if not target_ground_gu.is_finite():
		return false
	_movement_step_start_ground_gu = current_ground_gu
	_movement_step_start_screen_px = global_position
	_movement_step_target_ground_gu = target_ground_gu
	_movement_step_distance_gu = current_ground_gu.distance_to(target_ground_gu)
	_movement_step_neighbor = neighbor
	_movement_step_speed_scale = maxf(0.0, speed_scale)
	_movement_step_reason = reason
	_movement_step_engagement_target_instance_id = (
		engagement_target.get_instance_id()
		if is_instance_valid(engagement_target)
		else 0
	)
	_movement_step_active = true
	var step_direction_ground := (
		MonsterNeighborStepPolicyScript.desired_ground_direction(neighbor)
	)
	movement_facing = _screen_facing_for_ground_direction(step_direction_ground)
	facing = movement_facing
	return true


func _terrain_neighbor_for_pursuit(
	current_ground_gu: Vector2,
	engagement_target: Node2D,
	direct_neighbor: Vector2i,
) -> Vector2i:
	if runtime_map_id < 0:
		return direct_neighbor
	if not MonsterTerrainNavigationPolicyScript.context_valid(
		_terrain_navigation_context,
		runtime_map_id,
	):
		# A formal map without its exact release collision context must not start
		# a blind pursuit that can only be corrected by repeated physics rollback.
		return Vector2i.ZERO
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		engagement_target.global_position
	)
	if not target_ground_gu.is_finite():
		return Vector2i.ZERO
	var current_cell := MonsterNeighborStepPolicyScript.temporary_cell(current_ground_gu)
	var goal_cell := MonsterNeighborStepPolicyScript.temporary_cell(target_ground_gu)
	var target_instance_id := engagement_target.get_instance_id()
	if (
		_terrain_path_target_instance_id != target_instance_id
		or not _terrain_path_has_target_cell
		or _terrain_path_target_cell != goal_cell
	):
		_clear_terrain_route_cache()
		_terrain_path_target_instance_id = target_instance_id
		_terrain_path_target_cell = goal_cell
		_terrain_path_has_target_cell = true
	var now_ms := Time.get_ticks_msec()
	if _terrain_has_failed_cell and now_ms >= _terrain_failed_cell_until_ms:
		_terrain_has_failed_cell = false
	var direct_cell := current_cell + direct_neighbor
	var direct_is_recent_physics_failure := (
		_terrain_has_failed_cell and direct_cell == _terrain_failed_cell
	)
	while not _terrain_path_waypoints.is_empty() and _terrain_path_waypoints[0] == current_cell:
		_terrain_path_waypoints.pop_front()
	if not _terrain_path_waypoints.is_empty():
		var direct_los_clear := MonsterTerrainNavigationPolicyScript.static_line_of_sight_clear(
			_terrain_navigation_context,
			current_ground_gu,
			target_ground_gu,
		)
		if (
			direct_los_clear
			and not direct_is_recent_physics_failure
			and MonsterTerrainNavigationPolicyScript.can_traverse_neighbor(
				_terrain_navigation_context,
				current_cell,
				direct_cell,
				combat_radius_gu,
			)
		):
			_terrain_path_waypoints.clear()
			return direct_neighbor
		var cached_cell := _terrain_path_waypoints[0]
		if MonsterTerrainNavigationPolicyScript.can_traverse_neighbor(
			_terrain_navigation_context,
			current_cell,
			cached_cell,
			combat_radius_gu,
			_terrain_failed_cell if _terrain_has_failed_cell else Vector2i(-2147483648, -2147483648),
		):
			_terrain_path_waypoints.pop_front()
			return cached_cell - current_cell
		_terrain_path_waypoints.clear()
	if (
		not direct_is_recent_physics_failure
		and MonsterTerrainNavigationPolicyScript.can_traverse_neighbor(
			_terrain_navigation_context,
			current_cell,
			direct_cell,
			combat_radius_gu,
		)
	):
		# The overwhelming open-ground case remains the existing O(1) neighbor
		# selection. A* is strictly a wall-detour fallback.
		return direct_neighbor
	if now_ms < _terrain_no_path_until_ms:
		return Vector2i.ZERO
	var path_result := MonsterTerrainNavigationPolicyScript.find_bounded_path(
		_terrain_navigation_context,
		current_cell,
		goal_cell,
		combat_radius_gu,
		_terrain_failed_cell if _terrain_has_failed_cell else Vector2i(-2147483648, -2147483648),
	)
	if not bool(path_result.get("accepted", false)):
		# Frame budget exhaustion is not a path failure. Another actor gets the
		# next frame; no animation starts while this actor waits.
		return Vector2i.ZERO
	if not bool(path_result.get("found", false)):
		_terrain_no_path_until_ms = (
			now_ms + MonsterTerrainNavigationPolicyScript.NO_PATH_COOLDOWN_MS
			+ int(posmod(get_instance_id(), 7)) * 17
		)
		return Vector2i.ZERO
	var raw_waypoints: Variant = path_result.get("waypoints", [])
	if raw_waypoints is Array:
		for raw_cell: Variant in raw_waypoints:
			if raw_cell is Vector2i:
				_terrain_path_waypoints.append(raw_cell)
	if _terrain_path_waypoints.is_empty():
		return Vector2i.ZERO
	var next_cell: Vector2i = _terrain_path_waypoints.pop_front()
	if not MonsterTerrainNavigationPolicyScript.can_traverse_neighbor(
		_terrain_navigation_context,
		current_cell,
		next_cell,
		combat_radius_gu,
		_terrain_failed_cell if _terrain_has_failed_cell else Vector2i(-2147483648, -2147483648),
	):
		_terrain_path_waypoints.clear()
		return Vector2i.ZERO
	return next_cell - current_cell


func _clear_terrain_route_cache() -> void:
	_terrain_path_waypoints.clear()
	_terrain_path_target_instance_id = 0
	_terrain_path_target_cell = Vector2i.ZERO
	_terrain_path_has_target_cell = false


func _reset_terrain_navigation_state() -> void:
	_clear_terrain_route_cache()
	_terrain_no_path_until_ms = 0
	_terrain_failed_cell = Vector2i.ZERO
	_terrain_has_failed_cell = false
	_terrain_failed_cell_until_ms = 0


func _clear_continuous_pursuit_intent() -> void:
	_continuous_pursuit_active = false
	_continuous_pursuit_speed_scale = 1.0
	_clear_terrain_route_cache()


func _live_continuous_pursuit_target() -> Node2D:
	if not _continuous_pursuit_active:
		return null
	if not is_instance_valid(target) or target.is_queued_for_deletion():
		return null
	if target is PlayerCharacter and target.current_hp <= 0:
		return null
	if target is EnemyActor and (target._dying or target.current_hp <= 0):
		return null
	if target is SummonActor and target.current_hp <= 0:
		return null
	return target


func _continue_continuous_pursuit_from_current_target() -> void:
	var live_target := _live_continuous_pursuit_target()
	if live_target == null:
		_clear_continuous_pursuit_intent()
		return
	if _target_is_safe_player(live_target) or _point_inside_safe_zone(live_target.global_position):
		_clear_continuous_pursuit_intent()
		return
	var desired_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		live_target.global_position,
	)
	if (
		not desired_ground_gu.is_finite()
		or _movement_step_engagement_ready()
	):
		_clear_continuous_pursuit_intent()
		return
	# Cell continuation deliberately omits crowd/target-grid evaluation. The
	# current target reference is the only actor read on this hot path.
	if not _begin_autonomous_step_without_cadence(
		desired_ground_gu,
		_continuous_pursuit_speed_scale,
		false,
		&"pursuit",
		live_target,
	):
		_clear_continuous_pursuit_intent()


func _clear_autonomous_step_state() -> void:
	_movement_step_active = false
	_movement_step_start_ground_gu = Vector2.INF
	_movement_step_start_screen_px = Vector2.INF
	_movement_step_target_ground_gu = Vector2.INF
	_movement_step_distance_gu = 0.0
	_movement_step_neighbor = Vector2i.ZERO
	_movement_step_engagement_target_instance_id = 0
	_movement_step_speed_scale = 1.0
	_movement_step_reason = &""


func _cancel_autonomous_step(preserve_current_position := true) -> void:
	velocity = Vector2.ZERO
	actual_ground_motion_gu = Vector2.ZERO
	_clear_autonomous_step_state()
	_clear_continuous_pursuit_intent()
	_reset_terrain_navigation_state()


func _movement_step_engagement_target() -> Node2D:
	if _continuous_pursuit_active:
		return _live_continuous_pursuit_target()
	if _movement_step_engagement_target_instance_id <= 0:
		return null
	var candidate: Object = instance_from_id(
		_movement_step_engagement_target_instance_id
	)
	if not (candidate is Node2D):
		return null
	var target_node := candidate as Node2D
	if (
		not is_instance_valid(target_node)
		or target_node.is_queued_for_deletion()
	):
		return null
	return target_node


func _movement_step_engagement_ready() -> bool:
	var hit_target := _movement_step_engagement_target()
	if hit_target == null:
		return false
	if _target_is_safe_player(hit_target):
		return false
	var offset_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		hit_target.global_position,
	)
	var distance_gu := offset_ground_gu.length()
	var contact_distance_gu := _contact_distance_gu_to_target(hit_target)
	var engagement_distance_gu := maxf(
		attack_range_gu,
		contact_distance_gu,
	)
	return _attack_engagement_ready(
		hit_target,
		offset_ground_gu,
		distance_gu,
		contact_distance_gu,
		engagement_distance_gu,
	)


func _fail_autonomous_step_blocked() -> void:
	var failed_reason := _movement_step_reason
	var failed_target_ground_gu := _movement_step_target_ground_gu
	if _movement_step_start_screen_px.is_finite() and _movement_step_start_screen_px != Vector2.INF:
		set_combat_position(
			_movement_step_start_screen_px,
			&"autonomous_step_rollback"
		)
		_last_environment_safe_position_px = _movement_step_start_screen_px
	velocity = Vector2.ZERO
	actual_ground_motion_gu = Vector2.ZERO
	_clear_autonomous_step_state()
	_clear_continuous_pursuit_intent()
	if failed_reason == &"pursuit" and failed_target_ground_gu.is_finite():
		var now_ms := Time.get_ticks_msec()
		_terrain_failed_cell = MonsterNeighborStepPolicyScript.temporary_cell(
			failed_target_ground_gu
		)
		_terrain_has_failed_cell = true
		_terrain_failed_cell_until_ms = (
			now_ms + MonsterTerrainNavigationPolicyScript.NO_PATH_COOLDOWN_MS
			+ 250 + int(posmod(get_instance_id(), 7)) * 17
		)
		_terrain_no_path_until_ms = (
			now_ms + MonsterTerrainNavigationPolicyScript.NO_PATH_COOLDOWN_MS
			+ int(posmod(get_instance_id(), 7)) * 17
		)


func _advance_autonomous_step(delta: float) -> void:
	if not _movement_step_active:
		return
	if stationary:
		_cancel_autonomous_step(true)
		return
	if dormant:
		_cancel_autonomous_step(true)
		return
	if control_time > 0.0:
		_cancel_autonomous_step(true)
		return
	if charm_time > 0.0:
		_cancel_autonomous_step(true)
		return
	var current_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	if not current_ground_gu.is_finite():
		_cancel_autonomous_step(true)
		return
	if _continuous_pursuit_active:
		var live_target := _live_continuous_pursuit_target()
		if live_target == null:
			_cancel_autonomous_step(true)
			return
		var live_offset_ground_gu := _ground_delta_gu_between_screen_positions(
			global_position,
			live_target.global_position,
		)
		if (
			_target_is_safe_player(live_target)
			or _point_inside_safe_zone(live_target.global_position)
			or not live_offset_ground_gu.is_finite()
		):
			_cancel_autonomous_step(true)
			return
	# A pursuit step is allowed to finish early when the already-selected
	# combat target becomes attack-ready. This preserves the existing attack
	# geometry and prevents a full-cell attempt from colliding with the target
	# and rolling back outside melee/ranged engagement distance.
	if _movement_step_engagement_ready():
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
		_clear_autonomous_step_state()
		_clear_continuous_pursuit_intent()
		return
	var remaining := _movement_step_target_ground_gu - current_ground_gu
	if remaining.length_squared() <= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		var target_screen := _ground_gu_to_screen_position_px(_movement_step_target_ground_gu)
		if target_screen.is_finite():
			set_combat_position(target_screen, &"autonomous_step_arrival")
		velocity = Vector2.ZERO
		_clear_autonomous_step_state()
		_continue_continuous_pursuit_from_current_target()
		return
	# Runtime movement speed is a true Ground-GU/s scalar.  Every neighbor uses
	# the same scalar; a diagonal neighbor therefore travels sqrt(2) GU and
	# takes sqrt(2) times as long as an axis neighbor instead of gaining a hidden
	# diagonal speed multiplier.
	var presentation_speed := (
		move_speed_gu_per_sec
		* _movement_step_speed_scale
		if move_speed_gu_per_sec > 0.0 and _movement_step_speed_scale > 0.0
		else 0.0
	)
	if presentation_speed <= 0.0:
		_cancel_autonomous_step(true)
		return
	var remaining_distance := remaining.length()
	var very_small := 0.0001
	var max_frame_distance := presentation_speed * maxf(delta, 0.0)
	var frame_speed := minf(presentation_speed, remaining_distance / maxf(delta, very_small))
	var frame_direction := remaining.normalized()
	var frame_start_ground := current_ground_gu
	var frame_start_screen := global_position
	velocity = GroundUnitSpace.desired_screen_velocity_px_per_sec(
		frame_direction,
		frame_speed,
	)
	_move_with_spatial_rules(delta)
	var after_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	# The step target itself remains immutable, but an autonomous pursuit may
	# stop before that center once the frozen combat target becomes attack-ready.
	# This is a successful movement event, not a blocked-step rollback.
	if after_ground_gu.is_finite() and _movement_step_engagement_ready():
		velocity = Vector2.ZERO
		_clear_autonomous_step_state()
		_clear_continuous_pursuit_intent()
		return
	var blocked := false
	if get_slide_collision_count() > 0:
		blocked = true
	elif not after_ground_gu.is_finite():
		blocked = true
	else:
		var motion_ground_gu := after_ground_gu - frame_start_ground
		if motion_ground_gu.length() > GroundUnitSpace.EPSILON_GU:
			var forward_dot := motion_ground_gu.normalized().dot(frame_direction)
			if forward_dot < -0.5:
				blocked = true
			elif forward_dot < 0.5:
				var side_dot := motion_ground_gu.normalized().dot(
					Vector2(-frame_direction.y, frame_direction.x)
				)
				if absf(side_dot) > 0.8:
					blocked = true
		else:
			blocked = true
	if blocked:
		# A live summon that physically intercepts pursuit is a combat decision,
		# not terrain.  Consume only the slide-collision set already produced by
		# move_and_slide(); never add a combat-target group scan to this hot path.
		var intercepting_summon := _slide_collision_intercepting_summon()
		_fail_autonomous_step_blocked()
		if intercepting_summon != null:
			target = intercepting_summon
			_retarget_timer = 0.0
			_refresh_target_focus()
		return
	if after_ground_gu.distance_squared_to(_movement_step_target_ground_gu) <= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		var exact_target_screen := _ground_gu_to_screen_position_px(_movement_step_target_ground_gu)
		if exact_target_screen.is_finite():
			set_combat_position(exact_target_screen, &"autonomous_step_arrival")
		velocity = Vector2.ZERO
		_clear_autonomous_step_state()
		_continue_continuous_pursuit_from_current_target()
		return


func _apply_boss_rule() -> void:
	var timing: Dictionary = boss_rule.get("timing", {})
	var projection_gu := MonsterUnitAdapterScript.runtime_projection_gu(
		boss_rule,
		move_speed_gu_per_sec,
		attack_range_gu,
		aggro_radius_gu,
	)
	move_speed_gu_per_sec = float(projection_gu.move_speed_gu_per_sec)
	attack_range_gu = float(projection_gu.attack_range_gu)
	aggro_radius_gu = float(projection_gu.aggro_radius_gu)
	_attack_interval = float(timing.get("attackIntervalMs", 1550)) / 1000.0
	_attack_animation_duration = float(timing.get("attackAnimationMs", 460)) / 1000.0
	_attack_hit_delay = float(timing.get("hitDelayMs", 0)) / 1000.0
	var configured_delivery: Variant = boss_rule.get("attackDelivery", {})
	if configured_delivery is Dictionary and not (configured_delivery as Dictionary).is_empty():
		attack_delivery_rule = (configured_delivery as Dictionary).duplicate(true)
	var special: Dictionary = boss_rule.get("specialSkill", {})
	_boss_skill_enabled = bool(special.get("enabled", false))
	_boss_skill_cooldown = float(special.get("initialCooldownSeconds", _boss_skill_cooldown))
	_boss_phase_enabled = bool(boss_rule.get("phaseTwo", {}).get("enabled", false))
	var mechanics: Dictionary = boss_rule.get("mechanics", {})
	var burrow: Dictionary = mechanics.get("burrowAmbush", {})
	_burrowed = bool(burrow.get("enabled", false))
	if _burrowed:
		dormant = true
	var summon: Dictionary = mechanics.get("healthStageSummon", {})
	var rage: Dictionary = mechanics.get("healthStageRage", {})
	_boss_health_stage = int(summon.get("stages", rage.get("stages", -1)))
	_boss_base_move_speed_gu_per_sec = move_speed_gu_per_sec
	_boss_base_attack_interval = _attack_interval


static func legal_spawn_facing_directions() -> Array[Vector2]:
	var result: Array[Vector2] = []
	for neighbor: Vector2i in MonsterNeighborStepPolicyScript.NEIGHBOR_DELTAS:
		result.append(
			_screen_facing_for_ground_direction(
				MonsterNeighborStepPolicyScript.desired_ground_direction(neighbor)
			)
		)
	return result


func set_spawn_facing_seed_for_test(seed_value: int) -> void:
	if _spawn_facing_initialized or is_node_ready():
		return
	_spawn_facing_seed_override = seed_value
	_spawn_facing_seed_override_active = true


func _initialize_spawn_facing_once() -> void:
	if _spawn_facing_initialized:
		return
	_spawn_facing_initialized = true
	if _spawn_facing_seed_override_active:
		_spawn_facing_rng.seed = _spawn_facing_seed_override
	else:
		_spawn_facing_rng.randomize()
	var neighbors := MonsterNeighborStepPolicyScript.NEIGHBOR_DELTAS
	var selected_neighbor: Vector2i = neighbors[
		_spawn_facing_rng.randi_range(0, neighbors.size() - 1)
	]
	var selected_facing := _screen_facing_for_ground_direction(
		MonsterNeighborStepPolicyScript.desired_ground_direction(selected_neighbor)
	)
	facing = selected_facing
	movement_facing = selected_facing


func _ready() -> void:
	if monster_id < 0 or bool(get_meta("canonical_rejected", false)):
		queue_free()
		return
	MonsterVisualScript.configure_actor_y_sort_item(self, "actor_root")
	add_to_group("enemies")
	input_pickable = true
	collision_layer = WorldSpatialRulesScript.ENEMY_LAYER
	# The crowd grid/separation policy is authoritative for monster-to-monster
	# spacing. Keeping ENEMY_LAYER in this mask makes the physics server solve the
	# same dense crowd again for every moving actor, which scales disastrously.
	# World and player remain hard physics collisions.
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
	var collision := CollisionShape2D.new()
	collision.name = "CollisionShape2D"
	combat_radius_gu = (
		MonsterUnitAdapterScript.footprint_radius_px_to_combat_radius_gu(
			ArtSpec.BOSS_COLLISION_RADIUS_PX
		)
		if is_boss
		else MonsterUnitAdapterScript.collision_radius_gu(
			behavior_profile,
			ArtSpec.MONSTER_COLLISION_RADIUS_PX,
		)
	)
	collision_radius_px = MonsterUnitAdapterScript.combat_radius_gu_to_footprint_radius_px(
		combat_radius_gu
	)
	collision.shape = WorldSpatialRules.actor_footprint_shape_px(collision_radius_px)
	add_child(collision)
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
	queue_redraw()


func _resolve_invalid_spawn_overlap() -> void:
	if not is_instance_valid(primary_target):
		return
	var offset_px := global_position - primary_target.global_position
	var offset_ground_gu := GroundUnitSpace.screen_delta_px_to_ground_delta_gu(offset_px)
	var minimum_distance_gu := (
		combat_radius_gu
		+ _target_combat_radius_gu(primary_target)
		+ PLAYER_MELEE_CONTACT_GAP_GU
	)
	if offset_ground_gu.length() >= minimum_distance_gu:
		return
	if offset_ground_gu.length_squared() < GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		var angle := float(posmod(get_instance_id(), 32)) / 32.0 * TAU
		offset_ground_gu = Vector2.from_angle(angle)
	set_combat_position(
		primary_target.global_position
		+ GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			offset_ground_gu.normalized() * minimum_distance_gu
		),
		&"resolve_spawn_overlap"
	)


func set_targeted(value: bool) -> void:
	is_targeted = value
	queue_redraw()
	if visual != null:
		visual.refresh_target_ring()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventScreenTouch and event.pressed:
		target_requested.emit(self)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		target_requested.emit(self)


func _update_natural_regen(delta: float) -> void:
	var regen_result: Dictionary = _natural_regen.advance(delta, current_hp, max_hp)
	if int(regen_result.get("healed", 0)) <= 0:
		return
	current_hp = int(regen_result.get("hp", current_hp))
	_refresh_overhead_health()


func _physics_process(delta: float) -> void:
	if _dying:
		return
	# Match the original server's object-cycle boundary: damage may reduce HP to
	# zero during a multi-target release, but death teardown must not interrupt
	# that release's remaining targets. Resolve the queued death on the next
	# actor tick instead.
	if _death_pending or current_hp <= 0:
		_begin_death()
		return
	# actual_ground_motion_gu describes this physics tick only. A monster that
	# does not move this tick must never retain the previous tick's motion.
	actual_ground_motion_gu = Vector2.ZERO
	var physics_delta := delta
	var use_background_ai := _can_use_background_ai()
	if use_background_ai:
		if _background_wakeup_timer != null:
			_background_fast_path_skip_count += 1
			_enter_background_deep_sleep(false)
			return
		# Lightweight fixtures that intentionally override _ready() have no wake
		# timer. Preserve the first-pass cadence path for those isolated actors.
		_background_ai_timer -= delta
		_background_accumulated_delta += delta
		if _background_ai_timer > 0.0:
			_background_fast_path_skip_count += 1
			return
		delta = _background_accumulated_delta
		_background_accumulated_delta = 0.0
	else:
		delta += _background_accumulated_delta
		_background_accumulated_delta = 0.0
	_crowd_steering_timer = maxf(0.0, _crowd_steering_timer - delta)
	_spatial_index_update()
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_update_status_effects(delta)
	# Poison/status damage and natural regeneration are independent. Resolve
	# status first, but never allow a lethal status tick to be resurrected by
	# a natural-regeneration tick in the same physics frame.
	if _dying or _death_pending:
		return
	_update_natural_regen(delta)
	_update_entrapment_state(delta)
	_update_pending_attack(delta)
	if use_background_ai:
		_background_ai_timer = BACKGROUND_AI_INTERVAL_SECONDS
		_background_ai_evaluation_count += 1
		_retarget(BACKGROUND_AI_INTERVAL_SECONDS)
		if not is_instance_valid(target):
			_return_to_spawn(physics_delta)
		return
	_background_ai_timer = 0.0
	_foreground_ai_tick_count += 1
	if _handle_safe_zone_target_return(physics_delta):
		return
	_retarget(delta)
	if _update_area_attack(delta):
		if _movement_step_active:
			_cancel_autonomous_step(true)
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if _update_behavior_summon(delta):
		if _movement_step_active:
			_cancel_autonomous_step(true)
		velocity = Vector2.ZERO
		queue_redraw()
		return
	# Keep the established retarget/attack/summon timing, but immobilization must
	# win over the no-target return path after an actor is relocated beyond its
	# authored spawn leash.
	if control_time > 0.0 or charm_time > 0.0:
		if _movement_step_active:
			_cancel_autonomous_step(true)
		if _control_anchor_ground_gu == Vector2.INF:
			_control_anchor_ground_gu = _screen_position_px_to_ground_position_gu(global_position)
		else:
			set_combat_position(
				_ground_gu_to_screen_position_px(_control_anchor_ground_gu),
				&"control_anchor"
			)
		velocity = Vector2.ZERO
		queue_redraw()
		return
	_control_anchor_ground_gu = Vector2.INF
	if not is_instance_valid(target):
		_return_to_spawn(physics_delta)
		return
	var offset_px := target.global_position - global_position
	var offset_ground_gu := GroundUnitSpace.screen_delta_px_to_ground_delta_gu(offset_px)
	var distance_gu := offset_ground_gu.length()
	if _burrowed:
		var burrow: Dictionary = boss_rule.get("mechanics", {}).get("burrowAmbush", {})
		var emerge_range_gu := MonsterUnitAdapterScript.range_gu(
			burrow,
			"emerge_range_gu",
			"emergeRange",
			4.0,
		)
		if distance_gu <= emerge_range_gu:
			_burrowed = false
			dormant = false
			if bool(burrow.get("healToFullOnEmerge", false)):
				current_hp = max_hp
				_refresh_overhead_health()
			if visual != null:
				visual.visible = true
			if overhead != null:
				overhead.visible = true
		else:
			velocity = Vector2.ZERO
			return
	if _movement_step_active:
		_advance_autonomous_step(physics_delta)
		queue_redraw()
		return
	var contact_distance_gu := _contact_distance_gu_to_target(target)
	var engagement_distance_gu := maxf(attack_range_gu, contact_distance_gu)
	var engagement_ready := _attack_engagement_ready(
		target,
		offset_ground_gu,
		distance_gu,
		contact_distance_gu,
		engagement_distance_gu,
	)
	if offset_ground_gu.length_squared() > GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		facing = _screen_facing_for_ground_direction(offset_ground_gu)
	if _pending_attack_time >= 0.0:
		velocity = Vector2.ZERO
		queue_redraw()
		return
	if dormant:
		var wake_range_gu := MonsterUnitAdapterScript.range_gu(
			behavior_profile,
			"wake_range_gu",
			"wakeRange",
			MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(190.0),
		)
		var stone_wake: Dictionary = boss_rule.get("mechanics", {}).get("stoneWake", {})
		wake_range_gu = MonsterUnitAdapterScript.range_gu(
			stone_wake,
			"wake_range_gu",
			"wakeRange",
			wake_range_gu,
		)
		if distance_gu <= wake_range_gu:
			dormant = false
		else:
			velocity = Vector2.ZERO
			queue_redraw()
			return
	if (
		target.has_method("is_stealthed")
		and target.is_stealthed()
		and not anti_stealth
		and distance_gu > MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(35.0)
	):
		velocity = Vector2.ZERO
		return
	if _uses_area_magic_delivery():
		_update_area_magic_delivery(delta)
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
		queue_redraw()
		return
	if is_boss and _boss_skill_enabled:
		_update_boss_skill(delta, distance_gu)
	if (
		move_speed_gu_per_sec > 0.0
		and distance_gu < contact_distance_gu - CONTACT_RETREAT_EPSILON_GU
		and distance_gu > GroundUnitSpace.EPSILON_GU
		and not target is PlayerCharacter
	):
		# 怪物和召唤物重叠时可以自行分离；玩家普通移动不能迫使怪物后退。
		var started := _request_autonomous_step(
			-offset_ground_gu,
			0.72,
			false,
			&"overlap_retreat"
		)
		if started:
			_advance_autonomous_step(physics_delta)
		else:
			velocity = Vector2.ZERO
			actual_ground_motion_gu = Vector2.ZERO
	elif engagement_ready:
		velocity = Vector2.ZERO
		if _attack_timer <= 0.0:
			_attack_timer = _current_attack_interval()
			_refresh_target_focus()
			if visual != null:
				visual.play_attack(maxf(_attack_animation_duration,0.62))
			var dealt_damage := _rng.randi_range(attack_min, attack_max)
			if _uses_special_magic_melee_delivery():
				_deal_special_magic_melee_hit(target, dealt_damage)
			elif _uses_physical_projectile_delivery():
				_launch_physical_projectile(target, dealt_damage)
			elif (
				_uses_target_magic_delivery()
				and _target_magic_condition_met(offset_ground_gu)
			):
				_launch_target_magic(target, dealt_damage)
			elif _attack_hit_delay > 0.0:
				_pending_attack_time = _attack_hit_delay
				_pending_attack_target = target
				_pending_attack_damage = dealt_damage
				_pending_attack_release_record = {}
			else:
				_deal_melee_hit(target, dealt_damage)
	else:
		var pursuit_ground := offset_ground_gu.normalized()
		var started := _request_autonomous_step(
			pursuit_ground,
			1.0,
			true,
			&"pursuit",
			-1,
			target
		)
		if started:
			_advance_autonomous_step(physics_delta)
		else:
			velocity = Vector2.ZERO
			actual_ground_motion_gu = Vector2.ZERO
	if is_boss and is_instance_valid(target):
		var fresh_offset_ground_gu := _ground_delta_gu_between_screen_positions(
			global_position,
			target.global_position,
		)
		if fresh_offset_ground_gu.length_squared() > GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
			facing = _screen_facing_for_ground_direction(fresh_offset_ground_gu)
	if visual != null and visual.is_fallback_attacking():
		queue_redraw()


func _handle_safe_zone_target_return(physics_delta: float) -> bool:
	if not (
		is_instance_valid(target)
		and target is PlayerCharacter
		and _point_inside_safe_zone(target.global_position)
	):
		return false
	_pending_attack_time = -1.0
	_pending_attack_target = null
	_pending_attack_damage = 0
	_pending_attack_release_record = {}
	if _movement_step_active:
		_cancel_autonomous_step(true)
	velocity = Vector2.ZERO
	var spawn_position: Vector2 = get_meta("spawn_position", global_position)
	var spawn_delta_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		spawn_position,
	)
	if (
		_point_inside_safe_zone(global_position)
		and spawn_delta_ground_gu.length() > SAFE_ZONE_RETURN_EPSILON_GU
	):
		var started := _request_autonomous_step(
			spawn_delta_ground_gu,
			1.0,
			false,
			&"safe_zone_return"
		)
		if started:
			_advance_autonomous_step(physics_delta)
		else:
			velocity = Vector2.ZERO
			actual_ground_motion_gu = Vector2.ZERO
	queue_redraw()
	return true


func _enter_background_deep_sleep(initial_phase: bool) -> void:
	if is_boss or _background_wakeup_timer == null:
		return
	if not _background_deep_sleeping:
		_background_deep_sleeping = true
		_background_deep_sleep_entry_count += 1
	set_physics_process(false)
	velocity = Vector2.ZERO
	actual_ground_motion_gu = Vector2.ZERO
	_background_last_wakeup_msec = Time.get_ticks_msec()
	var delay_seconds := BACKGROUND_AI_INTERVAL_SECONDS
	if initial_phase:
		var phase_slot := _background_wakeup_phase_slot()
		delay_seconds = (
			BACKGROUND_AI_INTERVAL_SECONDS
			* float(phase_slot + 1)
			/ float(BACKGROUND_WAKE_PHASE_SLOTS)
		)
	_background_ai_timer = delay_seconds
	_background_wakeup_timer.start(delay_seconds)


func _background_wakeup_phase_slot() -> int:
	var stable_serial := int(get_meta("spawn_serial", get_instance_id()))
	return posmod(stable_serial * 7 + monster_id * 11, BACKGROUND_WAKE_PHASE_SLOTS)


func _leave_background_deep_sleep() -> void:
	if not _background_deep_sleeping:
		return
	_background_deep_sleeping = false
	_background_ai_timer = 0.0
	if _background_wakeup_timer != null:
		_background_wakeup_timer.stop()
	set_physics_process(true)


func _on_background_wakeup_timeout() -> void:
	if not _background_deep_sleeping or _dying:
		return
	_background_deep_sleep_wakeup_count += 1
	var now_msec := Time.get_ticks_msec()
	var elapsed_seconds := clampf(
		float(maxi(1, now_msec - _background_last_wakeup_msec)) / 1000.0,
		1.0 / 120.0,
		BACKGROUND_AI_INTERVAL_SECONDS * 2.0,
	)
	_background_last_wakeup_msec = now_msec
	if _death_pending or current_hp <= 0:
		_leave_background_deep_sleep()
		return
	if not _can_use_background_ai():
		_leave_background_deep_sleep()
		return
	_crowd_steering_timer = maxf(0.0, _crowd_steering_timer - elapsed_seconds)
	_spatial_index_update()
	_attack_timer = maxf(0.0, _attack_timer - elapsed_seconds)
	_update_status_effects(elapsed_seconds)
	if _dying or _death_pending:
		_leave_background_deep_sleep()
		return
	_update_natural_regen(elapsed_seconds)
	_update_entrapment_state(elapsed_seconds)
	_update_pending_attack(elapsed_seconds)
	_background_ai_evaluation_count += 1
	_background_maintenance_running = true
	_retarget(elapsed_seconds)
	_background_maintenance_running = false
	if not is_instance_valid(target):
		_return_to_spawn(1.0 / 60.0)
	if _can_use_background_ai():
		_background_ai_timer = BACKGROUND_AI_INTERVAL_SECONDS
		_background_last_wakeup_msec = Time.get_ticks_msec()
		_background_wakeup_timer.start(BACKGROUND_AI_INTERVAL_SECONDS)
	else:
		_leave_background_deep_sleep()


func _spatial_index_update() -> void:
	if (
		combat_spatial_index == null
		or not is_instance_valid(combat_spatial_index)
		or spatial_actor_runtime_id <= 0
	):
		return
	if _last_spatial_index_screen_position_px == global_position:
		return
	combat_spatial_index.update_actor(
		spatial_actor_runtime_id,
		_screen_position_px_to_ground_position_gu(global_position)
	)
	_last_spatial_index_screen_position_px = global_position


func spatial_index_position() -> Vector2:
	return _screen_position_px_to_ground_position_gu(global_position)


## Q2-A.1: the only sanctioned way to force an enemy's world position. The
## position write and the spatial-index bucket update happen in the same
## transaction, so a projectile querying later in the same physics frame can
## never observe a stale bucket for a forced relocation.
func set_combat_position(
	position_px: Vector2,
	reason: StringName = &""
) -> void:
	if _movement_step_active:
		var internal_reasons: Array[StringName] = [
			&"autonomous_step_arrival",
			&"autonomous_step_rollback",
			&"entrapment_boundary_revert",
			&"safe_zone_revert",
			&"environment_revert",
		]
		if not internal_reasons.has(reason):
			_cancel_autonomous_step(true)
	global_position = position_px
	_spatial_index_update()


func try_screen_position_px_to_ground_position_gu(
	screen_position_px: Vector2
) -> Dictionary:
	## FREEZE-P0.1: explicit fail-closed result for the formal position
	## conversion. Mapped world without a screen_to_ground projection never
	## falls back to identity.
	if runtime_screen_to_ground_position_px.is_valid():
		var ground_position_gu: Variant = (
			runtime_screen_to_ground_position_px.call(screen_position_px)
		)
		if ground_position_gu is Vector2:
			return GroundUnitSpace.projection_result(
				true,
				&"",
				ground_position_gu
			)
	if runtime_map_id < 0:
		return GroundUnitSpace.projection_result(
			true,
			&"",
			GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
				screen_position_px
			)
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpace.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
	)
	return GroundUnitSpace.projection_result(
		false,
		GroundUnitSpace.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
	)


func projection_ready() -> bool:
	if runtime_map_id < 0:
		return true
	return runtime_screen_to_ground_position_px.is_valid()


func _screen_position_px_to_ground_position_gu(screen_position_px: Vector2) -> Vector2:
	var result := try_screen_position_px_to_ground_position_gu(screen_position_px)
	if bool(result.get("success", false)):
		return result.get("value", Vector2.ZERO)
	return Vector2.INF


func _ground_gu_to_screen_position_px(ground_position_gu: Vector2) -> Vector2:
	if runtime_ground_gu_to_screen_position_px.is_valid():
		var screen_position_px: Variant = (
			runtime_ground_gu_to_screen_position_px.call(ground_position_gu)
		)
		if screen_position_px is Vector2:
			return screen_position_px
	if runtime_map_id < 0:
		return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
			ground_position_gu
		)
	missing_projection_rejection_count += 1
	projection_rejection_reason = (
		GroundUnitSpace.REASON_MISSING_GROUND_TO_SCREEN_PROJECTION
	)
	return Vector2.INF


static func _ground_delta_gu_between_screen_positions(
	origin_screen_position_px: Vector2,
	target_screen_position_px: Vector2,
) -> Vector2:
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
		target_screen_position_px - origin_screen_position_px
	)


static func _screen_facing_for_ground_direction(direction_ground: Vector2) -> Vector2:
	if direction_ground.length_squared() <= GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		return Vector2.DOWN
	return GroundUnitSpace.ground_delta_gu_to_screen_delta_px(
		direction_ground.normalized()
	).normalized()


func ground_velocity_gu_per_sec() -> Vector2:
	# CharacterBody2D owns a PX/s velocity at the physics boundary. Any gameplay
	# or animation-state consumer must cross back through the formal GU service.
	return GroundUnitSpace.screen_delta_px_to_ground_delta_gu(velocity)


static func _safe_zone_point_ground_gu_from_screen_reference(
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
	var polygon_screen_px := _packed_vector2_array_from_variant(zone.get("polygon", []))
	var polygon_ground_gu := _packed_vector2_array_from_variant(zone.get("polygon_ground_gu", []))
	if not polygon_screen_px.is_empty() and polygon_screen_px.size() == polygon_ground_gu.size():
		return polygon_ground_gu[0] + GroundUnitSpace.screen_delta_px_to_ground_delta_gu(
			point_screen_px - polygon_screen_px[0]
		)
	return Vector2.INF


static func _packed_vector2_array_from_variant(raw_points: Variant) -> PackedVector2Array:
	if raw_points is PackedVector2Array:
		return raw_points as PackedVector2Array
	var result := PackedVector2Array()
	if not raw_points is Array:
		return result
	for raw_point: Variant in raw_points:
		if raw_point is Vector2:
			result.append(raw_point)
		elif raw_point is Array and raw_point.size() >= 2:
			result.append(Vector2(float(raw_point[0]), float(raw_point[1])))
	return result


func _point_inside_safe_zone(point_screen_px: Vector2) -> bool:
	var zones: Array = get_meta("safe_zones", [])
	for zone_variant: Variant in zones:
		if not zone_variant is Dictionary:
			continue
		var zone := zone_variant as Dictionary
		var point_ground_gu := _safe_zone_point_ground_gu_from_screen_reference(
			point_screen_px,
			zone,
		)
		var has_formal_shape := zone.has("radius_gu")
		if str(zone.get("shape", "circle")) == "polygon":
			has_formal_shape = (
				_packed_vector2_array_from_variant(zone.get("polygon_ground_gu", [])).size()
				>= 3
			)
		if point_ground_gu == Vector2.INF or not has_formal_shape:
			continue
		var formal_zone := zone
		if str(zone.get("shape", "circle")) == "polygon":
			formal_zone = zone.duplicate(false)
			formal_zone["polygon_ground_gu"] = _packed_vector2_array_from_variant(
				zone.get("polygon_ground_gu", [])
			)
		if WorldSpatialRulesScript.point_inside_safe_zone_ground_gu(point_ground_gu, formal_zone):
			return true
	return false


func _move_with_spatial_rules(delta := 1.0 / 60.0) -> void:
	var position_before_move := global_position
	move_and_slide()
	actual_ground_motion_gu = GroundUnitSpace.actual_ground_motion_gu_from_screen_positions(
		position_before_move,
		global_position,
	)
	_physics_move_count += 1
	if entrapment_active():
		var before_ground_gu := _screen_position_px_to_ground_position_gu(
			position_before_move
		)
		var candidate_ground_gu := _screen_position_px_to_ground_position_gu(
			global_position
		)
		if (
			before_ground_gu == Vector2.INF
			or candidate_ground_gu == Vector2.INF
			or _entrapment_controller.movement_candidate_blocked(
				before_ground_gu,
				candidate_ground_gu,
				combat_radius_gu
			)
		):
			set_combat_position(position_before_move, &"entrapment_boundary_revert")
			actual_ground_motion_gu = Vector2.ZERO
			velocity = Vector2.ZERO
			return
	var entered_safe_zone := not _point_inside_safe_zone(position_before_move) and _point_inside_safe_zone(global_position)
	if entered_safe_zone:
		set_combat_position(position_before_move, &"safe_zone_revert")
		actual_ground_motion_gu = Vector2.ZERO
		velocity = Vector2.ZERO
		return
	# Physics chunks are the per-frame wall authority. The imported occupancy
	# provider is a deterministic fallback, sampled at a staggered 10 Hz instead
	# of doing five script calls for every moving monster on every physics tick.
	# A failed sample rolls back to the last verified point, so a rebuilding or
	# temporarily absent chunk cannot let an actor tunnel through map occupancy.
	if (
		_last_environment_safe_position_px == Vector2.INF
		or _ground_delta_gu_between_screen_positions(
			_last_environment_safe_position_px,
			position_before_move,
		).length_squared() > LAST_SAFE_REFRESH_DISTANCE_GU * LAST_SAFE_REFRESH_DISTANCE_GU
	):
		_last_environment_safe_position_px = position_before_move
		_environment_guard_timer = 0.0
	_environment_guard_timer = maxf(0.0, _environment_guard_timer - maxf(0.0, delta))
	if _environment_guard_timer > 0.0:
		return
	_environment_guard_timer = ENVIRONMENT_GUARD_INTERVAL_SECONDS
	_environment_guard_check_count += 1
	if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
		environment_blocker,
		global_position,
		collision_radius_px,
	):
		set_combat_position(
			_last_environment_safe_position_px,
			&"environment_revert"
		)
		actual_ground_motion_gu = GroundUnitSpace.actual_ground_motion_gu_from_screen_positions(
			position_before_move,
			global_position,
		)
		velocity = Vector2.ZERO
	else:
		_last_environment_safe_position_px = global_position


func _attack_engagement_ready(
	hit_target: Node2D,
	offset_ground_gu: Vector2,
	distance_gu: float,
	contact_distance_gu: float,
	default_engagement_distance_gu: float,
) -> bool:
	if _uses_special_magic_melee_delivery():
		return (
			is_instance_valid(hit_target)
			and _special_magic_melee_condition_met(offset_ground_gu)
			and _attack_world_path_is_clear_for_target(hit_target)
		)
	if _uses_area_magic_delivery():
		# The area delivery owns its target snapshot and release cycle. It must
		# never fall through to the ordinary single-target attack branch.
		return false
	if _uses_target_magic_delivery():
		return (
			is_instance_valid(hit_target)
			and _attack_world_path_is_clear_for_target(hit_target)
			and (
				_target_magic_condition_met(offset_ground_gu)
				or distance_gu
				<= contact_distance_gu + GroundUnitSpace.EPSILON_GU
			)
		)
	return (
		is_instance_valid(hit_target)
		and distance_gu
		<= default_engagement_distance_gu + GroundUnitSpace.EPSILON_GU
		and _attack_world_path_is_clear_for_target(hit_target)
	)


func _attack_world_path_is_clear_for_target(hit_target: Node2D) -> bool:
	if not is_instance_valid(hit_target):
		return false
	var source_ground_gu := _screen_position_px_to_ground_position_gu(
		global_position
	)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		hit_target.global_position
	)
	if source_ground_gu == Vector2.INF or target_ground_gu == Vector2.INF:
		return false
	return _world_attack_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		global_position,
		hit_target.global_position,
	)


func _world_attack_path_is_clear(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	source_world_px: Vector2 = Vector2.INF,
	target_world_px: Vector2 = Vector2.INF,
) -> bool:
	if not source_ground_gu.is_finite() or not target_ground_gu.is_finite():
		return false
	var has_map_query := (
		is_instance_valid(environment_blocker)
		and environment_blocker.has_method("is_environment_point_blocked")
	)
	var physics_space := _world_direct_space_state()
	# A missing map provider is only acceptable when the physics server can
	# provide the second, authoritative WORLD-layer path check. Never turn a
	# missing environment hookup into an open attack corridor.
	if not has_map_query and physics_space == null:
		return false
	if has_map_query:
		var distance_gu := source_ground_gu.distance_to(target_ground_gu)
		var sample_count := maxi(
			1,
			int(ceil(distance_gu / ATTACK_PATH_OBSTACLE_SAMPLE_STEP_GU)),
		)
		for sample_index: int in range(sample_count + 1):
			var progress := float(sample_index) / float(sample_count)
			var sample_world_px := _ground_gu_to_screen_position_px(
				source_ground_gu.lerp(target_ground_gu, progress)
			)
			if not sample_world_px.is_finite():
				return false
			if bool(environment_blocker.call(
				"is_environment_point_blocked",
				sample_world_px,
			)):
				return false
	if physics_space == null:
		return true
	var ray_source_px := source_world_px
	var ray_target_px := target_world_px
	if not ray_source_px.is_finite():
		ray_source_px = _ground_gu_to_screen_position_px(source_ground_gu)
	if not ray_target_px.is_finite():
		ray_target_px = _ground_gu_to_screen_position_px(target_ground_gu)
	if not ray_source_px.is_finite() or not ray_target_px.is_finite():
		return false
	var query := PhysicsRayQueryParameters2D.create(
		ray_source_px,
		ray_target_px,
		WorldSpatialRulesScript.WORLD_MASK,
	)
	query.collide_with_bodies = true
	query.collide_with_areas = true
	return physics_space.intersect_ray(query).is_empty()


func _world_direct_space_state() -> PhysicsDirectSpaceState2D:
	var world := get_world_2d()
	if world == null:
		return null
	return world.direct_space_state


func _world_attack_path_is_clear_for_release(
	release_record: Dictionary,
) -> bool:
	var source_ground_value: Variant = release_record.get(
		"source_ground_gu",
		Vector2.INF,
	)
	var target_ground_value: Variant = release_record.get(
		"target_ground_gu",
		Vector2.INF,
	)
	if not source_ground_value is Vector2 or not target_ground_value is Vector2:
		return false
	var source_world_value: Variant = release_record.get(
		"origin_world_px",
		Vector2.INF,
	)
	var target_world_value: Variant = release_record.get(
		"target_world_px",
		Vector2.INF,
	)
	var source_world_px: Vector2 = Vector2.INF
	if source_world_value is Vector2:
		source_world_px = source_world_value
	var target_world_px: Vector2 = Vector2.INF
	if target_world_value is Vector2:
		target_world_px = target_world_value
	var source_ground_gu: Vector2 = source_ground_value
	var target_ground_gu: Vector2 = target_ground_value
	return _world_attack_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		source_world_px,
		target_world_px,
	)


func _uses_target_magic_delivery() -> bool:
	return (
		str(attack_delivery_rule.get("kind", "")) == "target_magic"
		and str(attack_delivery_rule.get("effectId", ""))
		== MonsterTargetMagicEffectScript.EFFECT_ID
		and str(attack_delivery_rule.get("damageChannel", ""))
		== "magic_defense"
	)


func _uses_special_magic_melee_delivery() -> bool:
	return (
		str(attack_delivery_rule.get("kind", "")) == "special_melee"
		and str(attack_delivery_rule.get("effectId", ""))
		== MONSTER_MAGIC_MELEE_EFFECT_ID
		and str(attack_delivery_rule.get("damageChannel", ""))
		== "magic_defense"
		and bool(attack_delivery_rule.get("bodyOnly", false))
	)


func _uses_area_magic_delivery() -> bool:
	return (
		str(attack_delivery_rule.get("kind", "")) == "area_magic"
		and str(attack_delivery_rule.get("effectId", ""))
		== MONSTER_AREA_MAGIC_EFFECT_ID
		and str(attack_delivery_rule.get("damageChannel", ""))
		== "magic_defense"
		and bool(attack_delivery_rule.get("bodyOnly", false))
	)


func _special_magic_melee_condition_met(offset_ground_gu: Vector2) -> bool:
	if not _uses_special_magic_melee_delivery():
		return false
	if str(attack_delivery_rule.get("rangeShape", "")) != "chebyshev_square":
		return false
	var range_gu := MonsterUnitAdapterScript.range_gu(
		attack_delivery_rule,
		"range_gu",
		"rangePixels",
		1.0,
	)
	return (
		absf(offset_ground_gu.x) <= range_gu + GroundUnitSpace.EPSILON_GU
		and absf(offset_ground_gu.y) <= range_gu + GroundUnitSpace.EPSILON_GU
	)


func _target_magic_condition_met(offset_ground_gu: Vector2) -> bool:
	if not _uses_target_magic_delivery():
		return false
	if str(attack_delivery_rule.get("rangeShape", "")) != "chebyshev_square":
		return false
	var range_gu := MonsterUnitAdapterScript.range_gu(
		attack_delivery_rule,
		"range_gu",
		"rangePixels",
		0.0,
	)
	var abs_x := absf(offset_ground_gu.x)
	var abs_y := absf(offset_ground_gu.y)
	if (
		abs_x > range_gu + GroundUnitSpace.EPSILON_GU
		or abs_y > range_gu + GroundUnitSpace.EPSILON_GU
	):
		return false
	var activation: Dictionary = attack_delivery_rule.get("activation", {})
	var low_health := (
		max_hp > 0
		and float(current_hp) / float(max_hp)
		< float(activation.get("hpBelowRatio", 0.5))
	)
	var boundary_gu := maxf(
		0.0,
		float(activation.get("orAxisBoundaryTiles", range_gu)),
	)
	var on_axis_boundary := (
		abs_x >= boundary_gu - GroundUnitSpace.EPSILON_GU
		or abs_y >= boundary_gu - GroundUnitSpace.EPSILON_GU
	)
	return low_health or on_axis_boundary


func _current_attack_interval() -> float:
	if not boss_rule.is_empty():
		var phase: Dictionary = boss_rule.get("phaseTwo", {})
		return _attack_interval * (float(phase.get("attackIntervalMultiplier", 1.0)) if _boss_phase_two else 1.0)
	return (0.78 if _boss_phase_two else 1.15) if is_boss else _attack_interval


func _update_pending_attack(delta: float) -> void:
	if _pending_attack_time < 0.0:
		return
	_pending_attack_time -= delta
	if _pending_attack_time > 0.0:
		return
	var hit_target := _pending_attack_target
	var damage := _pending_attack_damage
	var release_record := _pending_attack_release_record
	_pending_attack_time = -1.0
	_pending_attack_target = null
	_pending_attack_damage = 0
	_pending_attack_release_record = {}
	if str(release_record.get("kind", "")) == "physical_projectile":
		_settle_physical_projectile_release(release_record)
		return
	if str(release_record.get("kind", "")) == "target_magic":
		_settle_target_magic_release(release_record)
		return
	if not is_instance_valid(hit_target):
		return
	if _target_is_safe_player(hit_target):
		return
	var offset_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		hit_target.global_position,
	)
	var hit_distance_gu := (
		maxf(attack_range_gu, _contact_distance_gu_to_target(hit_target))
		+ DELAYED_HIT_TOLERANCE_GU
	)
	if offset_ground_gu.length() > hit_distance_gu + GroundUnitSpace.EPSILON_GU:
		return
	if offset_ground_gu.length_squared() > GroundUnitSpace.EPSILON_GU * GroundUnitSpace.EPSILON_GU:
		facing = _screen_facing_for_ground_direction(offset_ground_gu)
	_deal_melee_hit(hit_target, damage, DELAYED_HIT_TOLERANCE_GU)


func _uses_physical_projectile_delivery() -> bool:
	return (
		str(attack_delivery_rule.get("kind", "")) == "physical_projectile"
		and str(attack_delivery_rule.get("effectId", ""))
		== MonsterRangedProjectileEffectScript.EFFECT_ID
	)


func _launch_physical_projectile(hit_target: Node2D, dealt_damage: int) -> bool:
	if (
		not _uses_physical_projectile_delivery()
		or not is_instance_valid(hit_target)
		or not hit_target.has_method("take_damage")
		or _target_is_safe_player(hit_target)
		or _runtime_map_id_for_area_target(hit_target) != runtime_map_id
	):
		return false
	var source_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		hit_target.global_position
	)
	if source_ground_gu == Vector2.INF or target_ground_gu == Vector2.INF:
		return false
	var release_distance_gu := source_ground_gu.distance_to(target_ground_gu)
	if release_distance_gu > attack_range_gu + GroundUnitSpace.EPSILON_GU:
		return false
	if not _physical_projectile_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		hit_target.global_position,
	):
		return false
	var release_id := _next_spatial_release_id("physical_projectile")
	var snapshot := SkillFootprintSnapshotScript.create_swept_capsule_path(
		_monster_attack_id("physical_projectile"),
		release_id,
		source_ground_gu,
		target_ground_gu,
		0.0,
		SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
		"",
		-1,
		_snapshot_coordinate_context(),
	)
	snapshot = _decorate_attack_footprint_snapshot(
		snapshot,
		PROJECTION_RELATIONSHIP_PROJECTILE_SWEEP,
		hit_target,
		attack_range_gu,
	)
	if not _snapshot_strict_ok(snapshot):
		return false
	var delay_rule: Dictionary = attack_delivery_rule.get("impactDelay", {})
	var chebyshev_distance_gu := maxf(
		absf(target_ground_gu.x - source_ground_gu.x),
		absf(target_ground_gu.y - source_ground_gu.y),
	)
	var duration_seconds := maxf(
		0.001,
		float(delay_rule.get("baseSeconds", 0.6))
		+ chebyshev_distance_gu
		* float(delay_rule.get("perChebyshevGuSeconds", 0.05)),
	)
	var target_world_px := _target_approved_ground_footpoint_world_px(hit_target)
	var release_record := {
		"kind": "physical_projectile",
		"release_id": release_id,
		"source_instance_id": get_instance_id(),
		"source_monster_id": monster_id,
		"target_instance_id": hit_target.get_instance_id(),
		"runtime_map_id": runtime_map_id,
		"source_ground_gu": source_ground_gu,
		"target_ground_gu": target_ground_gu,
		"origin_world_px": global_position,
		"target_world_px": target_world_px,
		"duration_seconds": duration_seconds,
		"damage": maxi(0, dealt_damage),
		"footprint_snapshot": snapshot,
	}
	release_record.make_read_only()
	_pending_attack_time = duration_seconds
	_pending_attack_target = hit_target
	_pending_attack_damage = maxi(0, dealt_damage)
	_pending_attack_release_record = release_record
	_last_attack_footprint_snapshot = snapshot
	_emit_physical_projectile_descriptor(release_record)
	return true


func _physical_projectile_path_is_clear(
	source_ground_gu: Vector2,
	target_ground_gu: Vector2,
	target_world_px: Vector2 = Vector2.INF,
) -> bool:
	if str(attack_delivery_rule.get("obstaclePolicy", "")) != "environment_can_fly_line":
		return false
	return _world_attack_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		global_position,
		target_world_px,
	)


func _settle_physical_projectile_release(release_record: Dictionary) -> void:
	var target_instance_id := int(release_record.get("target_instance_id", 0))
	if target_instance_id <= 0:
		return
	var candidate: Object = instance_from_id(target_instance_id)
	if not (candidate is Node2D):
		return
	var hit_target := candidate as Node2D
	if not _physical_projectile_release_target_is_valid(hit_target, release_record):
		return
	if not _world_attack_path_is_clear_for_release(release_record):
		return
	_apply_attack_damage(hit_target, int(release_record.get("damage", 0)))


func _physical_projectile_release_target_is_valid(
	hit_target: Node2D,
	release_record: Dictionary,
) -> bool:
	if (
		not is_instance_valid(hit_target)
		or hit_target.is_queued_for_deletion()
		or not hit_target.has_method("take_damage")
		or int(release_record.get("runtime_map_id", -1)) != runtime_map_id
		or _runtime_map_id_for_area_target(hit_target) != runtime_map_id
		or _target_is_safe_player(hit_target)
	):
		return false
	var dying_value: Variant = hit_target.get("_dying")
	if dying_value != null and bool(dying_value):
		return false
	var dead_value: Variant = hit_target.get("_dead")
	if dead_value != null and bool(dead_value):
		return false
	var current_hp_value: Variant = hit_target.get("current_hp")
	return current_hp_value == null or int(current_hp_value) > 0


func _emit_physical_projectile_descriptor(release_record: Dictionary) -> void:
	var descriptor := {
		"effect_id": MonsterRangedProjectileEffectScript.EFFECT_ID,
		"release_id": str(release_record.get("release_id", "")),
		"source_monster_id": monster_id,
		"source_instance_id": get_instance_id(),
		"target_instance_id": int(release_record.get("target_instance_id", 0)),
		"runtime_map_id": int(release_record.get("runtime_map_id", -1)),
		"origin_world_px": release_record.get("origin_world_px", global_position),
		"target_world_px": release_record.get("target_world_px", global_position),
		"duration_seconds": float(release_record.get("duration_seconds", 0.6)),
		"footprint_snapshot": release_record.get("footprint_snapshot", {}),
		"damage": maxi(0, int(release_record.get("damage", 0))),
		"damage_owner": "enemy.physical_projectile_release",
	}
	descriptor.make_read_only()
	ranged_projectile_requested.emit(descriptor)
	var host := get_parent()
	if not is_instance_valid(host):
		return
	var effect: Node2D = MonsterRangedProjectileEffectScript.create_visual(descriptor)
	host.add_child(effect)


func _launch_target_magic(hit_target: Node2D, raw_damage: int) -> bool:
	if (
		not _uses_target_magic_delivery()
		or not is_instance_valid(hit_target)
		or not hit_target.has_method("take_direct_spell_damage")
		or _target_is_safe_player(hit_target)
		or _runtime_map_id_for_area_target(hit_target) != runtime_map_id
	):
		return false
	var source_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		hit_target.global_position
	)
	if source_ground_gu == Vector2.INF or target_ground_gu == Vector2.INF:
		return false
	if not _target_magic_condition_met(target_ground_gu - source_ground_gu):
		return false
	if not _world_attack_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		global_position,
		hit_target.global_position,
	):
		return false
	var release_id := _next_spatial_release_id("target_magic")
	var snapshot := SkillFootprintSnapshotScript.create_circle(
		_monster_attack_id("target_magic"),
		release_id,
		target_ground_gu,
		0.0,
		SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
		_snapshot_coordinate_context(),
	)
	snapshot = _decorate_attack_footprint_snapshot(
		snapshot,
		PROJECTION_RELATIONSHIP_GROUND_EXACT,
		hit_target,
		0.0,
	)
	if not _snapshot_strict_ok(snapshot):
		return false
	var release_record := {
		"kind": "target_magic",
		"release_id": release_id,
		"source_instance_id": get_instance_id(),
		"source_monster_id": monster_id,
		"target_instance_id": hit_target.get_instance_id(),
		"runtime_map_id": runtime_map_id,
		"source_ground_gu": source_ground_gu,
		"target_ground_gu": target_ground_gu,
		"origin_world_px": global_position,
		"target_world_px": _target_approved_ground_footpoint_world_px(hit_target),
		"duration_seconds": maxf(
			0.001,
			float(attack_delivery_rule.get("hitDelaySeconds", 0.2)),
		),
		"damage": maxi(0, raw_damage),
		"damage_channel": "magic_defense",
		"footprint_snapshot": snapshot,
	}
	release_record.make_read_only()
	_pending_attack_time = float(release_record.get("duration_seconds", 0.2))
	_pending_attack_target = hit_target
	_pending_attack_damage = maxi(0, raw_damage)
	_pending_attack_release_record = release_record
	_last_attack_footprint_snapshot = snapshot
	_emit_target_magic_descriptor(release_record)
	return true


func _settle_target_magic_release(release_record: Dictionary) -> void:
	var target_instance_id := int(release_record.get("target_instance_id", 0))
	if target_instance_id <= 0:
		return
	var candidate: Object = instance_from_id(target_instance_id)
	if not (candidate is Node2D):
		return
	var hit_target := candidate as Node2D
	if (
		not _physical_projectile_release_target_is_valid(hit_target, release_record)
		or not hit_target.has_method("take_direct_spell_damage")
	):
		return
	if not _world_attack_path_is_clear_for_release(release_record):
		return
	var raw_resolution: Variant = hit_target.call(
		"take_direct_spell_damage",
		"",
		maxi(0, int(release_record.get("damage", 0))),
	)
	if not raw_resolution is Dictionary:
		last_magic_attack_resolution = {
			"success": false,
			"failure_reason": "invalid_magic_damage_resolution",
		}
		return
	last_magic_attack_resolution = (raw_resolution as Dictionary).duplicate(true)
	last_magic_attack_resolution["source_monster_id"] = monster_id
	last_magic_attack_resolution["release_id"] = str(
		release_record.get("release_id", "")
	)
	last_magic_attack_resolution["damage_channel"] = "magic_defense"
	last_magic_attack_resolution["success"] = true
	apply_life_steal(int(last_magic_attack_resolution.get("applied_damage", 0)))


func _emit_target_magic_descriptor(release_record: Dictionary) -> void:
	var descriptor := {
		"effect_id": MonsterTargetMagicEffectScript.EFFECT_ID,
		"release_id": str(release_record.get("release_id", "")),
		"source_monster_id": monster_id,
		"source_instance_id": get_instance_id(),
		"target_instance_id": int(release_record.get("target_instance_id", 0)),
		"runtime_map_id": int(release_record.get("runtime_map_id", -1)),
		"target_ground_gu": release_record.get("target_ground_gu", Vector2.INF),
		"target_world_px": release_record.get("target_world_px", Vector2.INF),
		"duration_seconds": float(release_record.get("duration_seconds", 0.2)),
		"damage": maxi(0, int(release_record.get("damage", 0))),
		"damage_channel": "magic_defense",
		"footprint_snapshot": release_record.get("footprint_snapshot", {}),
		"damage_owner": "enemy.target_magic_release",
	}
	descriptor.make_read_only()
	target_magic_requested.emit(descriptor)
	var host := get_parent()
	if not is_instance_valid(host):
		return
	var effect: Node2D = MonsterTargetMagicEffectScript.create_visual(descriptor)
	host.add_child(effect)


func _deal_special_magic_melee_hit(
	hit_target: Node2D,
	dealt_damage: int,
) -> void:
	# TMagCowMonster applies its magic-defense damage immediately. The source
	# RM_STRUCK message is a 300ms body presentation notification, not a delayed
	# damage transaction and not an independent projectile/effect.
	if (
		not _uses_special_magic_melee_delivery()
		or not is_instance_valid(hit_target)
		or not hit_target.has_method("take_direct_spell_damage")
		or _target_is_safe_player(hit_target)
		or _runtime_map_id_for_area_target(hit_target) != runtime_map_id
	):
		return
	var offset_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		hit_target.global_position,
	)
	if not _special_magic_melee_condition_met(offset_ground_gu):
		return
	var source_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		hit_target.global_position
	)
	if (
		source_ground_gu == Vector2.INF
		or target_ground_gu == Vector2.INF
		or not _world_attack_path_is_clear(
			source_ground_gu,
			target_ground_gu,
			global_position,
			hit_target.global_position,
		)
	):
		return
	var raw_resolution: Variant = hit_target.call(
		"take_direct_spell_damage",
		"",
		maxi(0, dealt_damage),
	)
	if not raw_resolution is Dictionary:
		last_magic_attack_resolution = {
			"success": false,
			"failure_reason": "invalid_magic_damage_resolution",
			"source_monster_id": monster_id,
			"damage_channel": "magic_defense",
		}
		return
	last_magic_attack_resolution = (raw_resolution as Dictionary).duplicate(true)
	last_magic_attack_resolution["source_monster_id"] = monster_id
	last_magic_attack_resolution["damage_channel"] = "magic_defense"
	last_magic_attack_resolution["delivery_kind"] = "special_melee"
	last_magic_attack_resolution["presentation_delay_seconds"] = float(
		attack_delivery_rule.get("presentationDelaySeconds", 0.3)
	)
	last_magic_attack_resolution["success"] = true
	apply_life_steal(int(last_magic_attack_resolution.get("applied_damage", 0)))


func _deal_melee_hit(
	hit_target: Node2D,
	dealt_damage: int,
	center_tolerance_gu := 0.0,
) -> void:
	if not is_instance_valid(hit_target) or not hit_target.has_method("take_damage") or _target_is_safe_player(hit_target):
		return
	var target_radius_gu := _target_combat_radius_gu(hit_target)
	var center_reach_gu := maxf(
		attack_range_gu,
		_contact_distance_gu_to_target(hit_target),
	)
	var source_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		hit_target.global_position
	)
	if (
		source_ground_gu.distance_to(target_ground_gu)
		> (
			center_reach_gu
			+ maxf(0.0, center_tolerance_gu)
			+ GroundUnitSpace.EPSILON_GU
		)
	):
		return
	if not _world_attack_path_is_clear(
		source_ground_gu,
		target_ground_gu,
		global_position,
		hit_target.global_position,
	):
		return
	var snapshot: Dictionary
	if _uses_ranged_projectile_sweep_contract():
		# These formal ranged profiles currently bake their projectile into the
		# monster attack presentation.  Gameplay still receives an exact GU sweep
		# from release footpoint to target footpoint; no invented visual width is
		# allowed, so the path radius remains exactly zero.
		snapshot = SkillFootprintSnapshotScript.create_swept_capsule_path(
			_monster_attack_id("projectile_sweep"),
			_next_spatial_release_id("projectile_sweep"),
			source_ground_gu,
			target_ground_gu,
			0.0,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS / 2,
			"",
			-1,
			_snapshot_coordinate_context(),
		)
		snapshot = _decorate_attack_footprint_snapshot(
			snapshot,
			PROJECTION_RELATIONSHIP_PROJECTILE_SWEEP,
			hit_target,
			center_reach_gu,
			center_tolerance_gu,
		)
	else:
		# release_contact starts at the attacker footpoint.  Subtracting the
		# selected target radius preserves the established centre-reach boundary
		# when the attack projection is intersected with the target footprint.
		var contact_projection_radius_gu := maxf(
			0.0,
			center_reach_gu
			+ maxf(0.0, center_tolerance_gu)
			- target_radius_gu,
		)
		snapshot = SkillFootprintSnapshotScript.create_circle(
			_monster_attack_id("release_contact"),
			_next_spatial_release_id("release_contact"),
			source_ground_gu,
			contact_projection_radius_gu,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
			_snapshot_coordinate_context(),
		)
		snapshot = _decorate_attack_footprint_snapshot(
			snapshot,
			PROJECTION_RELATIONSHIP_RELEASE_CONTACT,
			hit_target,
			center_reach_gu,
			center_tolerance_gu,
		)
	_last_attack_footprint_snapshot = snapshot
	if not _snapshot_intersects_target(snapshot, hit_target):
		return
	_apply_attack_damage(hit_target, dealt_damage)


func _target_agility_for_monster_hit(hit_target: Node2D) -> int:
	var target_agility_value: Variant = hit_target.get("agility")
	if target_agility_value != null:
		return maxi(1, int(target_agility_value))
	if hit_target is PlayerCharacter:
		return maxi(1, int(PlayerState.computed_stats.get("agility", WarriorCombatMath.BASE_AGILITY)))
	return WarriorCombatMath.BASE_AGILITY


func _monster_physical_hit_succeeds(hit_target: Node2D, forced_roll := -1) -> bool:
	var target_agility := _target_agility_for_monster_hit(hit_target)
	var random_roll := int(forced_roll)
	if random_roll < 0:
		# Existing test mode is a deterministic presentation harness used by the
		# geometry suites.  Production still follows the primary strict-< rule.
		if PlayerState.test_mode:
			last_physical_hit_resolution = {
				"policy_id": WarriorCombatMath.PHYSICAL_HIT_POLICY_ID,
				"accuracy": accuracy,
				"target_agility": target_agility,
				"random_roll": null,
				"success": true,
				"test_mode_bypass": true,
			}
			return true
		random_roll = _rng.randi_range(0, target_agility - 1)
	var success := WarriorCombatMath.hit_succeeds(accuracy, target_agility, random_roll)
	last_physical_hit_resolution = {
		"policy_id": WarriorCombatMath.PHYSICAL_HIT_POLICY_ID,
		"accuracy": accuracy,
		"target_agility": target_agility,
		"random_roll": random_roll,
		"success": success,
		"test_mode_bypass": false,
	}
	return success


func _apply_attack_damage(
	hit_target: Node2D,
	dealt_damage: int,
	use_accuracy := true,
	forced_roll := -1,
	force_struck_reaction := false,
	forced_control_roll := -1,
) -> void:
	if use_accuracy and not _monster_physical_hit_succeeds(hit_target, forced_roll):
		# A miss consumes the existing attack event/timer and damage roll but
		# submits no damage or on-hit side effects.
		return
	if force_struck_reaction and hit_target is PlayerCharacter:
		(hit_target as PlayerCharacter).take_damage(dealt_damage, true, {}, true)
	else:
		hit_target.take_damage(dealt_damage)
	apply_life_steal(dealt_damage)
	_apply_on_hit_control(hit_target, forced_control_roll)
	var on_hit: Dictionary = behavior_profile.get("onHit", {})
	var poison_damage_value := int(on_hit.get("poisonDamage", 0))
	if poison_damage_value > 0 and hit_target.has_method("apply_poison"):
		hit_target.apply_poison(poison_damage_value, float(on_hit.get("poisonSeconds", 0.0)))


func _apply_on_hit_control(hit_target: Node2D, forced_control_roll := -1) -> void:
	if control_on_hit_seconds <= 0.0 or not hit_target.has_method("apply_control"):
		return
	var denominator := control_chance_denominator_base
	if denominator > 0:
		denominator += _target_anti_poison_for_control(hit_target)
		var roll := (
			clampi(forced_control_roll, 0, denominator - 1)
			if forced_control_roll >= 0
			else _rng.randi_range(0, denominator - 1)
		)
		if roll != 0:
			return
	hit_target.apply_control(control_on_hit_seconds)


func _target_anti_poison_for_control(hit_target: Node2D) -> int:
	if hit_target is PlayerCharacter:
		# The original server reads the struck target's m_btAntiPoison here.
		# HardCore does not yet project a player equipment anti-poison stat, so
		# the missing-key default deliberately preserves the original base 0.
		return maxi(0, int(PlayerState.computed_stats.get("anti_poison", 0)))
	for property: Dictionary in hit_target.get_property_list():
		if str(property.get("name", "")) == "anti_poison":
			return maxi(0, int(hit_target.get("anti_poison")))
	return 0


func configure_runtime_map_projection(
	map_id: int,
	ground_gu_to_screen_position_px: Callable,
	screen_position_px_to_ground_gu: Callable = Callable()
) -> void:
	runtime_map_id = int(map_id)
	runtime_ground_gu_to_screen_position_px = (
		ground_gu_to_screen_position_px
		if ground_gu_to_screen_position_px is Callable
		else Callable()
	)
	runtime_screen_to_ground_position_px = (
		screen_position_px_to_ground_gu
		if screen_position_px_to_ground_gu is Callable
		else Callable()
	)


func configure_terrain_navigation_context(context: Dictionary) -> void:
	_terrain_navigation_context = context
	_reset_terrain_navigation_state()


func terrain_navigation_context_ready() -> bool:
	if runtime_map_id < 0:
		return true
	return MonsterTerrainNavigationPolicyScript.context_valid(
		_terrain_navigation_context,
		runtime_map_id,
	)


func _initial_acquisition_static_los_clear(candidate: Node2D) -> bool:
	if runtime_map_id < 0:
		return true
	if not terrain_navigation_context_ready() or not is_instance_valid(candidate):
		return false
	var start_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	var end_ground_gu := _screen_position_px_to_ground_position_gu(candidate.global_position)
	return MonsterTerrainNavigationPolicyScript.static_line_of_sight_clear(
		_terrain_navigation_context,
		start_ground_gu,
		end_ground_gu,
	)


func configure_spatial_index(
	index: RuntimeCombatSpatialIndexScript,
	actor_runtime_id: int
) -> void:
	combat_spatial_index = index
	spatial_actor_runtime_id = actor_runtime_id
	_last_spatial_index_screen_position_px = Vector2.INF


func _exit_tree() -> void:
	_cancel_autonomous_step(true)
	clear_entrapment("exit_tree")
	if combat_spatial_index != null and is_instance_valid(combat_spatial_index):
		combat_spatial_index.unregister(spatial_actor_runtime_id)
	combat_spatial_index = null


func _snapshot_coordinate_context() -> Dictionary:
	if runtime_map_id >= 0 and not runtime_screen_to_ground_position_px.is_valid():
		missing_projection_rejection_count += 1
		projection_rejection_reason = (
			GroundUnitSpace.REASON_MISSING_SCREEN_TO_GROUND_PROJECTION
		)
		return {}
	var origin_ground_gu := _screen_position_px_to_ground_position_gu(
		global_position
	)
	return SkillFootprintSnapshotScript.make_absolute_runtime_context(
		runtime_map_id,
		origin_ground_gu,
		origin_ground_gu,
		runtime_ground_gu_to_screen_position_px
	)


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_snapshot_coordinate_context(),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


func _snapshot_intersects_target(snapshot: Dictionary, hit_target: Node2D) -> bool:
	return (
		is_instance_valid(hit_target)
		and _snapshot_strict_ok(snapshot)
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			snapshot,
			_screen_position_px_to_ground_position_gu(hit_target.global_position),
			_target_combat_radius_gu(hit_target),
		)
	)


func _monster_attack_id(kind: String) -> String:
	return "monster.%d.%s" % [monster_id, kind]


func _next_spatial_release_id(kind: String) -> String:
	_spatial_release_serial += 1
	return "monster:%d:instance:%d:%s:release:%d" % [
		monster_id,
		get_instance_id(),
		kind,
		_spatial_release_serial,
	]


func _decorate_attack_footprint_snapshot(
	snapshot: Dictionary,
	projection_relationship_id: String,
	hit_target: Node2D = null,
	center_reach_gu := 0.0,
	center_tolerance_gu := 0.0,
) -> Dictionary:
	var decorated: Dictionary = snapshot.duplicate(true)
	decorated["monster_attack_contract_id"] = ATTACK_FOOTPRINT_CONTRACT_ID
	decorated["projection_relationship_id"] = projection_relationship_id
	decorated["source_instance_id"] = get_instance_id()
	decorated["target_instance_id"] = (
		hit_target.get_instance_id() if is_instance_valid(hit_target) else 0
	)
	decorated["center_reach_gu"] = maxf(0.0, center_reach_gu)
	decorated["center_tolerance_gu"] = maxf(0.0, center_tolerance_gu)
	decorated.make_read_only()
	return decorated


func _uses_ranged_projectile_sweep_contract() -> bool:
	return attack_range_gu >= RANGED_ATTACK_RANGE_FLOOR_GU


func _target_is_safe_player(hit_target: Node2D) -> bool:
	return hit_target is PlayerCharacter and _point_inside_safe_zone(hit_target.global_position)


func _update_area_magic_delivery(delta: float) -> void:
	if not _uses_area_magic_delivery():
		return
	if _area_magic_warning > 0.0:
		_area_magic_warning = maxf(0.0, _area_magic_warning - delta)
		if _area_magic_warning <= 0.0:
			_settle_area_magic_release_records()
			_last_attack_footprint_snapshot = _area_magic_footprint_snapshot
			_area_magic_footprint_snapshot = {}
			_area_magic_release_records.clear()
		return
	if _attack_timer > 0.0:
		return
	var candidate_snapshot := _create_area_magic_footprint_snapshot()
	var candidate_targets := _area_magic_targets(candidate_snapshot)
	if candidate_targets.is_empty():
		return
	_area_magic_footprint_snapshot = candidate_snapshot
	_area_magic_release_records = _freeze_area_magic_release_records(
		candidate_targets,
		candidate_snapshot,
	)
	if _area_magic_release_records.is_empty():
		_area_magic_footprint_snapshot = {}
		return
	# The Monster.DB ATTACK_SPD is the complete cycle interval. Freeze the
	# target set at release and do not enter the normal single-target branch.
	_attack_timer = _current_attack_interval()
	_area_magic_warning = maxf(
		0.001,
		float(attack_delivery_rule.get("hitDelaySeconds", 0.6)),
	)
	if visual != null:
		# Only the authored monster body attack is presented. There is no
		# unproven client warning circle or independent projectile/effect.
		visual.play_attack(maxf(_attack_animation_duration, _area_magic_warning))


func _create_area_magic_footprint_snapshot() -> Dictionary:
	var range_gu := MonsterUnitAdapterScript.range_gu(
		attack_delivery_rule,
		"range_gu",
		"rangePixels",
		6.0,
	)
	var source_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	if source_ground_gu == Vector2.INF or range_gu <= 0.0:
		return {}
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		_monster_attack_id("area_magic"),
		_next_spatial_release_id("area_magic"),
		source_ground_gu - Vector2(range_gu, 0.0),
		Vector2.RIGHT,
		range_gu * 2.0,
		range_gu * 2.0,
		0.0,
		0.0,
		0.0,
		"",
		_snapshot_coordinate_context(),
	)
	var decorated := _decorate_attack_footprint_snapshot(
		snapshot,
		PROJECTION_RELATIONSHIP_GROUND_EXACT,
		null,
		range_gu,
	)
	var square_snapshot := decorated.duplicate(true)
	square_snapshot["range_shape"] = "chebyshev_axis_aligned_square_exclusive"
	square_snapshot["range_gu"] = range_gu
	square_snapshot["attack_source_ground_gu"] = source_ground_gu
	square_snapshot["obstacle_policy"] = "none_no_los"
	square_snapshot.make_read_only()
	return square_snapshot


func _area_magic_targets(snapshot: Dictionary) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if snapshot.is_empty() or not _snapshot_strict_ok(snapshot):
		return result
	var candidates: Array[Node] = []
	var seen_instance_ids: Dictionary = {}
	if is_instance_valid(primary_target):
		candidates.append(primary_target)
		seen_instance_ids[primary_target.get_instance_id()] = true
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if not is_instance_valid(node):
			continue
		var instance_id := node.get_instance_id()
		if seen_instance_ids.has(instance_id):
			continue
		seen_instance_ids[instance_id] = true
		candidates.append(node)
	for node: Node in candidates:
		if node is Node2D and _area_magic_victim_is_valid(node, snapshot):
			result.append(node)
	result.sort_custom(func(left: Node2D, right: Node2D) -> bool:
		return left.get_instance_id() < right.get_instance_id()
	)
	return result


func _area_magic_victim_is_valid(victim: Node2D, snapshot: Dictionary) -> bool:
	if (
		not is_instance_valid(victim)
		or victim.is_queued_for_deletion()
		or not victim.has_method("take_direct_spell_damage")
		or _target_is_safe_player(victim)
		or _point_inside_safe_zone(victim.global_position)
		or _runtime_map_id_for_area_target(victim) != runtime_map_id
	):
		return false
	var dying_value: Variant = victim.get("_dying")
	if dying_value != null and bool(dying_value):
		return false
	var dead_value: Variant = victim.get("_dead")
	if dead_value != null and bool(dead_value):
		return false
	var current_hp_value: Variant = victim.get("current_hp")
	if current_hp_value != null and int(current_hp_value) <= 0:
		return false
	var source_ground_gu: Vector2 = snapshot.get(
		"attack_source_ground_gu",
		_screen_position_px_to_ground_position_gu(global_position),
	)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		victim.global_position
	)
	if source_ground_gu == Vector2.INF or target_ground_gu == Vector2.INF:
		return false
	var range_gu := maxf(0.0, float(snapshot.get("range_gu", 0.0)))
	var delta_ground_gu := target_ground_gu - source_ground_gu
	# ObjMon2's strict source comparison is abs(x) < 6 && abs(y) < 6;
	# equality on either edge is outside the frozen target set.
	return absf(delta_ground_gu.x) < range_gu and absf(delta_ground_gu.y) < range_gu


func _freeze_area_magic_release_records(
	victims: Array[Node2D],
	footprint_snapshot: Dictionary,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var release_id := str(footprint_snapshot.get("release_id", ""))
	for victim: Node2D in victims:
		if not _area_magic_victim_is_valid(victim, footprint_snapshot):
			continue
		var target_ground_gu := _screen_position_px_to_ground_position_gu(
			victim.global_position
		)
		if target_ground_gu == Vector2.INF:
			continue
		var record := {
			"release_id": release_id,
			"release_target_id": "%s:target:%d" % [
				release_id,
				victim.get_instance_id(),
			],
			"target_instance_id": victim.get_instance_id(),
			"runtime_map_id": _runtime_map_id_for_area_target(victim),
			"target_ground_gu": target_ground_gu,
			"target_world_px": _target_approved_ground_footpoint_world_px(victim),
			"damage": _rng.randi_range(attack_min, attack_max),
			"damage_channel": "magic_defense",
		}
		record.make_read_only()
		records.append(record)
	return records


func _settle_area_magic_release_records() -> void:
	for release_record: Dictionary in _area_magic_release_records:
		var target_instance_id := int(release_record.get("target_instance_id", 0))
		if target_instance_id <= 0:
			continue
		var candidate: Object = instance_from_id(target_instance_id)
		if not (candidate is Node2D):
			continue
		var victim := candidate as Node2D
		if not _area_magic_release_target_is_valid(victim, release_record):
			continue
		_deal_area_magic_damage(victim, int(release_record.get("damage", 0)))


func _area_magic_release_target_is_valid(
	victim: Node2D,
	release_record: Dictionary,
) -> bool:
	if (
		not is_instance_valid(victim)
		or victim.is_queued_for_deletion()
		or not victim.has_method("take_direct_spell_damage")
		or runtime_map_id != int(release_record.get("runtime_map_id", -1))
		or _runtime_map_id_for_area_target(victim) != runtime_map_id
		or _target_is_safe_player(victim)
		or _point_inside_safe_zone(victim.global_position)
	):
		return false
	var dying_value: Variant = victim.get("_dying")
	if dying_value != null and bool(dying_value):
		return false
	var dead_value: Variant = victim.get("_dead")
	if dead_value != null and bool(dead_value):
		return false
	var current_hp_value: Variant = victim.get("current_hp")
	return current_hp_value == null or int(current_hp_value) > 0


func _deal_area_magic_damage(victim: Node2D, dealt_damage: int) -> void:
	var raw_resolution: Variant = victim.call(
		"take_direct_spell_damage",
		"",
		maxi(0, dealt_damage),
	)
	if not raw_resolution is Dictionary:
		return
	last_magic_attack_resolution = (raw_resolution as Dictionary).duplicate(true)
	last_magic_attack_resolution["source_monster_id"] = monster_id
	last_magic_attack_resolution["damage_channel"] = "magic_defense"
	last_magic_attack_resolution["delivery_kind"] = "area_magic"
	last_magic_attack_resolution["success"] = true
	apply_life_steal(int(last_magic_attack_resolution.get("applied_damage", 0)))
	_apply_area_magic_status(victim)


func _apply_area_magic_status(victim: Node2D) -> void:
	var status_value: Variant = attack_delivery_rule.get("status", {})
	if not status_value is Dictionary:
		return
	var status := status_value as Dictionary
	if _rng.randf() >= float(status.get("statusChance", 0.25)):
		return
	var poison_weight := maxi(0, int(status.get("poisonWeight", 2)))
	var control_weight := maxi(0, int(status.get("controlWeight", 1)))
	if poison_weight + control_weight <= 0:
		return
	if _rng.randi_range(1, poison_weight + control_weight) <= poison_weight:
		if victim.has_method("apply_poison"):
			victim.apply_poison(
				int(status.get("poisonDamage", 4)),
				float(status.get("poisonSeconds", 8.0)),
			)
	elif victim.has_method("apply_control"):
		victim.apply_control(float(status.get("controlSeconds", 1.2)))


func _update_area_attack(delta: float) -> bool:
	if not bool(area_attack_rule.get("enabled", false)):
		return false
	if _area_attack_warning > 0.0:
		_area_attack_warning -= delta
		if _area_attack_warning <= 0.0:
			_area_attack_warning = 0.0
			_settle_area_attack_release_records()
			_last_attack_footprint_snapshot = _area_attack_footprint_snapshot
			_area_attack_footprint_snapshot = {}
			_area_attack_release_records.clear()
			_area_attack_cooldown = _attack_interval
	elif _area_attack_cooldown > 0.0:
		_area_attack_cooldown = maxf(0.0, _area_attack_cooldown - delta)
	else:
		var candidate_snapshot := _create_area_attack_footprint_snapshot()
		var candidate_targets := _area_attack_targets(candidate_snapshot)
		if not candidate_targets.is_empty():
			_area_attack_footprint_snapshot = candidate_snapshot
			_area_attack_release_records = _freeze_area_attack_release_records(
				candidate_targets,
				candidate_snapshot,
			)
			for release_record: Dictionary in _area_attack_release_records:
				_emit_fixed_area_ground_spike_descriptor(
					release_record,
					candidate_snapshot,
				)
			_area_attack_warning = maxf(0.001, float(area_attack_rule.get("hitDelaySeconds", 0.2)))
			if visual != null:
				visual.play_attack(maxf(
					_area_attack_visual_duration(),
					_area_attack_warning,
				))
	return true


func _area_attack_visual_duration() -> float:
	# Fixed-body full-area attackers have no populated boss timing rule. Their
	# exact client action still carries the authored frame cadence, so do not
	# collapse six 120 ms frames into the generic 460 ms fallback.
	var appearance := MonsterIdentityScript.appearance_profile(monster_id)
	var actions: Variant = appearance.get("actions", {})
	if not actions is Dictionary:
		return _attack_animation_duration
	var attack: Variant = (actions as Dictionary).get("attack", {})
	if not attack is Dictionary:
		return _attack_animation_duration
	var frame_count := int((attack as Dictionary).get("framesPerDirection", 0))
	var frame_ms := int((attack as Dictionary).get("frameMs", 0))
	if frame_count <= 0 or frame_ms <= 0:
		return _attack_animation_duration
	return maxf(
		_attack_animation_duration,
		float(frame_count * frame_ms) / 1000.0,
	)


func _create_area_attack_footprint_snapshot() -> Dictionary:
	var range_gu := MonsterUnitAdapterScript.range_gu(
		area_attack_rule,
		"range_gu",
		"rangePixels",
		attack_range_gu,
	)
	var source_ground_gu := _screen_position_px_to_ground_position_gu(
		global_position
	)
	# TBigHeartMonster compares X and Y independently. The resulting footprint
	# is the Chebyshev square [source-range, source+range], not a radial circle.
	var snapshot := SkillFootprintSnapshotScript.create_directed_rectangle(
		_monster_attack_id("area_square"),
		_next_spatial_release_id("area_square"),
		source_ground_gu - Vector2(range_gu, 0.0),
		Vector2.RIGHT,
		range_gu * 2.0,
		range_gu * 2.0,
		0.0,
		0.0,
		0.0,
		"",
		_snapshot_coordinate_context(),
	)
	var decorated := _decorate_attack_footprint_snapshot(
		snapshot,
		PROJECTION_RELATIONSHIP_GROUND_EXACT,
		null,
		range_gu,
	)
	var square_snapshot := decorated.duplicate(true)
	square_snapshot["range_shape"] = "chebyshev_axis_aligned_square"
	square_snapshot["range_gu"] = range_gu
	square_snapshot["attack_source_ground_gu"] = source_ground_gu
	square_snapshot.make_read_only()
	return square_snapshot


func _area_attack_targets(snapshot := {}) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var resolved_snapshot: Dictionary = snapshot
	if resolved_snapshot.is_empty():
		resolved_snapshot = _create_area_attack_footprint_snapshot()
	if not _snapshot_strict_ok(resolved_snapshot):
		# A supplied release snapshot is authoritative. Never replace an
		# invalid/non-projectable release with a guessed footprint, otherwise a
		# fixed-area attack could damage without a valid visual geometry source.
		return result
	var target_mode := str(area_attack_rule.get("targetMode", ""))
	var scope := str(area_attack_rule.get("scope", ""))
	if scope not in ["visible_actors", "current_map"]:
		return result
	var candidates: Array[Node] = []
	var seen_instance_ids: Dictionary = {}
	if target_mode == "all_combat_targets":
		if is_instance_valid(primary_target):
			candidates.append(primary_target)
			seen_instance_ids[primary_target.get_instance_id()] = true
		for node: Node in get_tree().get_nodes_in_group("combat_targets"):
			if not is_instance_valid(node):
				continue
			var instance_id := node.get_instance_id()
			if seen_instance_ids.has(instance_id):
				continue
			seen_instance_ids[instance_id] = true
			candidates.append(node)
	elif target_mode == "current_target":
		if is_instance_valid(target):
			candidates.append(target)
	else:
		return result
	for node: Node in candidates:
		if (
			node is Node2D
			and _area_attack_victim_is_valid(node, resolved_snapshot)
		):
			result.append(node)
	result.sort_custom(func(left: Node2D, right: Node2D) -> bool:
		return left.get_instance_id() < right.get_instance_id()
	)
	return result


func _area_attack_victim_is_valid(
	victim: Node2D,
	snapshot: Dictionary,
) -> bool:
	if (
		not is_instance_valid(victim)
		or victim.is_queued_for_deletion()
		or not victim.has_method("take_damage")
	):
		return false
	# Enemy death is guarded by _dying; PlayerCharacter uses _dead. The HP
	# check also covers SummonActor and test fixtures without relying on a
	# class-specific branch.
	var dying_value: Variant = victim.get("_dying")
	if dying_value != null and bool(dying_value):
		return false
	var dead_value: Variant = victim.get("_dead")
	if dead_value != null and bool(dead_value):
		return false
	var current_hp_value: Variant = victim.get("current_hp")
	if current_hp_value != null and int(current_hp_value) <= 0:
		return false
	if _point_inside_safe_zone(victim.global_position):
		return false
	if _runtime_map_id_for_area_target(victim) != runtime_map_id:
		return false
	var source_ground_gu: Vector2 = snapshot.get(
		"attack_source_ground_gu",
		_screen_position_px_to_ground_position_gu(global_position),
	)
	var target_ground_gu := _screen_position_px_to_ground_position_gu(
		victim.global_position
	)
	if target_ground_gu == Vector2.INF:
		return false
	var range_gu := maxf(0.0, float(snapshot.get("range_gu", 0.0)))
	var delta_ground_gu := target_ground_gu - source_ground_gu
	return (
		absf(delta_ground_gu.x) <= range_gu + GroundUnitSpace.EPSILON_GU
		and absf(delta_ground_gu.y) <= range_gu + GroundUnitSpace.EPSILON_GU
	)


func _freeze_area_attack_release_records(
	victims: Array[Node2D],
	footprint_snapshot: Dictionary,
) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	var release_id := str(footprint_snapshot.get("release_id", ""))
	for victim: Node2D in victims:
		if not _area_attack_victim_is_valid(victim, footprint_snapshot):
			continue
		var target_ground_gu := _screen_position_px_to_ground_position_gu(
			victim.global_position
		)
		if target_ground_gu == Vector2.INF:
			continue
		var target_instance_id := victim.get_instance_id()
		var record := {
			"release_id": release_id,
			"release_target_id": "%s:target:%d" % [
				release_id,
				target_instance_id,
			],
			"target_instance_id": target_instance_id,
			"runtime_map_id": _runtime_map_id_for_area_target(victim),
			"target_ground_gu": target_ground_gu,
			"target_world_px": _target_approved_ground_footpoint_world_px(victim),
			"target_actor_origin_world_px": victim.global_position,
			"damage": _rng.randi_range(attack_min, attack_max),
		}
		record.make_read_only()
		records.append(record)
	return records


func _settle_area_attack_release_records() -> void:
	for release_record: Dictionary in _area_attack_release_records:
		var target_instance_id := int(release_record.get("target_instance_id", 0))
		if target_instance_id <= 0:
			continue
		var candidate: Object = instance_from_id(target_instance_id)
		if not (candidate is Node2D):
			continue
		var victim := candidate as Node2D
		if not _area_attack_release_target_is_valid(victim, release_record):
			continue
		# Fixed-area magic is a separate delivery path; preserve its existing
		# damage semantics and do not apply physical accuracy to it.
		_apply_attack_damage(
			victim,
			int(release_record.get("damage", 0)),
			false,
			-1,
			_uses_fixed_area_ground_spike_effect(),
		)


func _area_attack_release_target_is_valid(
	victim: Node2D,
	release_record: Dictionary,
) -> bool:
	if (
		not is_instance_valid(victim)
		or victim.is_queued_for_deletion()
		or not victim.has_method("take_damage")
	):
		return false
	if runtime_map_id != int(release_record.get("runtime_map_id", -1)):
		return false
	if _runtime_map_id_for_area_target(victim) != runtime_map_id:
		return false
	var dying_value: Variant = victim.get("_dying")
	if dying_value != null and bool(dying_value):
		return false
	var dead_value: Variant = victim.get("_dead")
	if dead_value != null and bool(dead_value):
		return false
	var current_hp_value: Variant = victim.get("current_hp")
	if current_hp_value != null and int(current_hp_value) <= 0:
		return false
	return not _point_inside_safe_zone(victim.global_position)


func _runtime_map_id_for_area_target(victim: Node2D) -> int:
	if victim.has_meta("runtime_map_id"):
		return int(victim.get_meta("runtime_map_id", runtime_map_id))
	for property: Dictionary in victim.get_property_list():
		if str(property.get("name", "")) != "runtime_map_id":
			continue
		var target_map_id := int(victim.get("runtime_map_id"))
		return target_map_id if target_map_id >= 0 else runtime_map_id
	return runtime_map_id


func _uses_fixed_area_ground_spike_effect() -> bool:
	return monster_id in FIXED_AREA_GROUND_SPIKE_MONSTER_IDS


func _target_approved_ground_footpoint_world_px(victim: Node2D) -> Vector2:
	# Area geometry and damage remain bound to victim.global_position. Only the
	# presentation descriptor follows the original user-approved ground point.
	if victim.has_method("approved_ground_footpoint_world_px"):
		var point: Variant = victim.call("approved_ground_footpoint_world_px")
		if point is Vector2 and point.is_finite():
			return point
	return victim.global_position


func _emit_fixed_area_ground_spike_descriptor(
	release_record: Dictionary,
	footprint_snapshot: Dictionary,
) -> void:
	if not _uses_fixed_area_ground_spike_effect():
		return
	var target_ground_gu: Vector2 = release_record.get(
		"target_ground_gu",
		Vector2.INF,
	)
	if target_ground_gu == Vector2.INF:
		return
	var target_world_px: Vector2 = release_record.get(
		"target_world_px",
		Vector2.INF,
	)
	if target_world_px == Vector2.INF:
		return
	var target_instance_id := int(release_record.get("target_instance_id", 0))
	if target_instance_id <= 0:
		return
	var source := {
		"monster_id": monster_id,
		"instance_id": get_instance_id(),
	}
	var target := {
		"instance_id": target_instance_id,
		"ground_gu": target_ground_gu,
		"world_px": target_world_px,
		"actor_origin_world_px": release_record.get(
			"target_actor_origin_world_px",
			target_world_px,
		),
		"runtime_map_id": int(release_record.get("runtime_map_id", -1)),
	}
	var descriptor := {
		"effect_id": FIXED_AREA_GROUND_SPIKE_EFFECT_ID,
		"release_id": str(footprint_snapshot.get("release_id", "")),
		"release_target_id": str(release_record.get("release_target_id", "")),
		"source": source,
		"source_monster_id": monster_id,
		"source_instance_id": get_instance_id(),
		"target": target,
		"target_instance_id": target_instance_id,
		"runtime_map_id": int(release_record.get("runtime_map_id", -1)),
		"target_ground_gu": target_ground_gu,
		"target_world_px": target_world_px,
		"target_actor_origin_world_px": release_record.get(
			"target_actor_origin_world_px",
			target_world_px,
		),
		"damage": maxi(0, int(release_record.get("damage", 0))),
		# The release snapshot is already read-only at construction. Do not
		# duplicate or rebuild it per victim: all descriptors for one release
		# must point at the same immutable geometry object.
		"footprint_snapshot": footprint_snapshot,
	}
	source.make_read_only()
	target.make_read_only()
	descriptor.make_read_only()
	fixed_area_ground_spike_requested.emit(descriptor)


func _update_behavior_summon(delta: float) -> bool:
	if not bool(summon_rule.get("enabled", false)):
		return false
	if _summon_warning > 0.0:
		_summon_warning -= delta
		if _summon_warning <= 0.0:
			var ids: Array = summon_rule.get("monsterIds", []).duplicate()
			if not ids.is_empty():
				summon_requested.emit(
					self,
					ids,
					maxi(1, int(summon_rule.get("count", 1))),
					maxi(1, int(summon_rule.get("maxActive", 15)))
				)
			_summon_cooldown = _attack_interval
	elif _summon_cooldown > 0.0:
		_summon_cooldown = maxf(0.0, _summon_cooldown - delta)
	elif is_instance_valid(target):
		_summon_warning = maxf(0.001, float(summon_rule.get("delaySeconds", 0.5)))
		if visual != null:
			visual.play_attack(maxf(_attack_animation_duration, _summon_warning))
	return true


func _target_combat_radius_gu(target_node: Node2D) -> float:
	if target_node is PlayerCharacter:
		return WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
	if target_node is EnemyActor:
		return target_node.combat_radius_gu
	if target_node is SummonActor:
		return target_node.combat_radius_gu
	return WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(16.0)


func _contact_distance_gu_to_target(target_node: Node2D) -> float:
	return (
		combat_radius_gu
		+ _target_combat_radius_gu(target_node)
		+ PLAYER_MELEE_CONTACT_GAP_GU
	)


func _uses_player_melee_contact_contract(target_node: Node2D) -> bool:
	return (
		target_node is PlayerCharacter
		and move_speed_gu_per_sec > 0.0
		and attack_range_gu < RANGED_ATTACK_RANGE_FLOOR_GU
	)


func _crowd_separation() -> Vector2:
	_ensure_crowd_grid()
	var separation_ground := Vector2.ZERO
	var center_cell := _crowd_grid_cell(global_position)
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var bucket: Array = _crowd_grid.get(center_cell + Vector2i(offset_x, offset_y), [])
			for value: Variant in bucket:
				_crowd_query_candidate_count += 1
				if not is_instance_valid(value):
					continue
				var node := value as Node
				if node == self or not node is EnemyActor or node.is_queued_for_deletion():
					continue
				var other := node as EnemyActor
				var away_ground_gu := _ground_delta_gu_between_screen_positions(
					other.global_position,
					global_position,
				)
				var desired_gu := (
					combat_radius_gu
					+ other.combat_radius_gu
					+ CROWD_SEPARATION_GAP_GU
				)
				var distance_gu := away_ground_gu.length()
				if distance_gu >= desired_gu:
					continue
				if distance_gu < GroundUnitSpace.EPSILON_GU:
					var angle := float(posmod(get_instance_id(), 16)) / 16.0 * TAU
					away_ground_gu = Vector2.from_angle(angle)
					distance_gu = GroundUnitSpace.EPSILON_GU
				separation_ground += away_ground_gu.normalized() * (
					1.0 - distance_gu / desired_gu
				)
	return separation_ground.limit_length(1.0)


func _crowd_separation_for_motion(delta: float) -> Vector2:
	_crowd_steering_timer = maxf(0.0, _crowd_steering_timer - delta)
	if _crowd_steering_timer > 0.0:
		return _cached_crowd_separation
	_crowd_steering_timer = CROWD_STEERING_INTERVAL_SECONDS
	_crowd_steering_evaluation_count += 1
	_cached_crowd_separation = _crowd_separation()
	return _cached_crowd_separation


func _ensure_crowd_grid() -> void:
	var physics_frame := Engine.get_physics_frames()
	if _crowd_grid_physics_frame >= 0 and physics_frame - _crowd_grid_physics_frame < CROWD_GRID_REFRESH_FRAMES:
		return
	_crowd_grid_physics_frame = physics_frame
	_crowd_grid.clear()
	_crowd_grid_build_count += 1
	for node: Node in get_tree().get_nodes_in_group("enemies"):
		if not node is EnemyActor or node.is_queued_for_deletion():
			continue
		_crowd_grid_actor_scan_count += 1
		var enemy := node as EnemyActor
		var cell := _crowd_grid_cell(enemy.global_position)
		var bucket: Array = _crowd_grid.get(cell, [])
		bucket.append(enemy)
		_crowd_grid[cell] = bucket


func _ensure_target_grid(force_refresh := false) -> void:
	if not is_inside_tree():
		return
	var now_msec := Time.get_ticks_msec()
	if (
		not force_refresh
		and _target_grid_last_refresh_msec >= 0
		and now_msec - _target_grid_last_refresh_msec
			< int(TARGET_GRID_REFRESH_SECONDS * 1000.0)
	):
		return
	_target_grid_last_refresh_msec = now_msec
	_target_grid.clear()
	_target_grid_node_ids.clear()
	# Keep the established diagnostic name, but count actual group walks now;
	# per-actor candidate decisions are no longer misreported as full scans.
	_retarget_full_scan_count += 1
	_target_grid_group_scan_count += 1
	# One shared group walk per 250 ms window replaces one group walk per
	# retargeting actor.  Group order is retained in each record because equal
	# Manhattan-distance first acquisitions are order-stable by contract.
	var group_order := 0
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if node is Node2D and is_instance_valid(node) and not node.is_queued_for_deletion():
			var target_node := node as Node2D
			if target_node.global_position.is_finite():
				var cell := _target_grid_cell(target_node.global_position)
				var bucket: Array = _target_grid.get(cell, [])
				bucket.append({"node": target_node, "order": group_order})
				_target_grid[cell] = bucket
				_target_grid_node_ids[target_node.get_instance_id()] = true
				_target_grid_candidate_count += 1
		group_order += 1


static func _target_grid_cell(screen_position_px: Vector2) -> Vector2i:
	return Vector2i(
		floori(screen_position_px.x / TARGET_GRID_CELL_SIZE_PX.x),
		floori(screen_position_px.y / TARGET_GRID_CELL_SIZE_PX.y),
	)


func _target_grid_candidates(max_range_gu: float) -> Array[Node2D]:
	var result: Array[Node2D] = []
	if not is_finite(max_range_gu) or max_range_gu <= 0.0:
		return result
	var half_extents := TARGET_GRID_HALF_EXTENTS_PER_GU * max_range_gu
	var min_cell := _target_grid_cell(global_position - half_extents)
	var max_cell := _target_grid_cell(global_position + half_extents)
	var records: Array[Dictionary] = []
	var seen: Dictionary = {}
	for cell_y in range(min_cell.y, max_cell.y + 1):
		for cell_x in range(min_cell.x, max_cell.x + 1):
			var bucket: Array = _target_grid.get(Vector2i(cell_x, cell_y), [])
			for raw_record: Variant in bucket:
				if not raw_record is Dictionary:
					continue
				var record: Dictionary = raw_record
				var raw_node: Variant = record.get("node")
				if not is_instance_valid(raw_node) or not raw_node is Node2D:
					continue
				var node := raw_node as Node2D
				if node.is_queued_for_deletion():
					continue
				var instance_id := node.get_instance_id()
				if seen.has(instance_id):
					continue
				seen[instance_id] = true
				records.append({"node": node, "order": int(record.get("order", 0))})
	records.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("order", 0)) < int(b.get("order", 0))
	)
	for record: Dictionary in records:
		var raw_node: Variant = record.get("node")
		if is_instance_valid(raw_node) and raw_node is Node2D:
			var node := raw_node as Node2D
			if node.is_queued_for_deletion():
				continue
			result.append(node)
	return result


func _append_live_target_candidate(candidates: Array, raw_candidate: Variant) -> void:
	if not is_instance_valid(raw_candidate) or not raw_candidate is Node2D:
		return
	var candidate := raw_candidate as Node2D
	if candidate.is_queued_for_deletion() or candidates.has(candidate):
		return
	candidates.append(candidate)


func _crowd_grid_cell(world_position: Vector2) -> Vector2i:
	var ground_position_gu := _screen_position_px_to_ground_position_gu(world_position)
	return Vector2i(
		floori(ground_position_gu.x / CROWD_GRID_CELL_SIZE_GU),
		floori(ground_position_gu.y / CROWD_GRID_CELL_SIZE_GU),
	)


static func reset_performance_diagnostics() -> void:
	_crowd_grid_physics_frame = -1
	_crowd_grid.clear()
	_target_grid_last_refresh_msec = -1
	_target_grid.clear()
	_target_grid_node_ids.clear()
	_crowd_grid_build_count = 0
	_crowd_grid_actor_scan_count = 0
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


static func performance_diagnostics() -> Dictionary:
	return {
		"crowd_grid_builds": _crowd_grid_build_count,
		"crowd_grid_actor_scans": _crowd_grid_actor_scan_count,
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


func _can_use_background_ai() -> bool:
	if is_boss or not is_instance_valid(primary_target):
		return false
	if (
		is_instance_valid(target)
		and target is PlayerCharacter
		and _point_inside_safe_zone(target.global_position)
	):
		return false
	# Movement/collision must continue at physics rate. Only truly idle actors
	# may use the low-frequency background maintenance path.
	if _movement_step_active:
		return false
	if target != primary_target and is_instance_valid(target):
		return false
	if not _threat_table.is_empty() or poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0:
		return false
	if (
		_pending_attack_time >= 0.0
		or _area_attack_warning > 0.0
		or _area_magic_warning > 0.0
		or _summon_warning > 0.0
		or entrapment_active()
	):
		return false
	if not is_instance_valid(target):
		return true
	var activation_distance_gu := maxf(
		BACKGROUND_AI_MIN_DISTANCE_GU,
		aggro_radius_gu + MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(256.0),
	)
	return (
		_ground_delta_gu_between_screen_positions(
			global_position,
			primary_target.global_position,
		).length_squared()
		> activation_distance_gu * activation_distance_gu
	)


func apply_life_steal(dealt_damage: int) -> void:
	if life_steal_ratio <= 0.0 or dealt_damage <= 0:
		return
	current_hp = mini(max_hp, current_hp + maxi(1, int(dealt_damage * life_steal_ratio)))
	_refresh_overhead_health()


func take_damage(amount: int, attacker: Node2D = null) -> void:
	if _dying or _death_pending:
		return
	_leave_background_deep_sleep()
	if is_instance_valid(attacker):
		_add_threat(attacker, float(maxi(1,amount))*5.0+25.0)
	current_hp = maxi(0, current_hp - amount)
	_refresh_overhead_health()
	if is_boss and not boss_rule.is_empty():
		_apply_health_stage_mechanics()
	if visual != null and current_hp > 0:
		visual.play_hit()
	if is_boss and _boss_phase_enabled and not _boss_phase_two and current_hp <= max_hp / 2:
		_boss_phase_two = true
		var phase: Dictionary = boss_rule.get("phaseTwo", {})
		move_speed_gu_per_sec *= float(phase.get("moveSpeedMultiplier", 1.0))
		attack_range_gu = MonsterUnitAdapterScript.range_gu(
			phase,
			"attack_range_gu",
			"attackRange",
			attack_range_gu,
		)
		_boss_skill_cooldown = minf(_boss_skill_cooldown, float(phase.get("skillCooldownSeconds", _boss_skill_cooldown)))
	queue_redraw()
	if current_hp == 0:
		_mark_death_pending()


func can_receive_damage() -> bool:
	return (
		current_hp > 0
		and not _death_pending
		and not _dying
		and not is_queued_for_deletion()
	)


func _mark_death_pending() -> void:
	if _dying or _death_pending:
		return
	_death_pending = true
	# The heavyweight death signal/persistence/drop work is deferred, but a
	# zero-HP actor must stop participating in collision and target queries now.
	# Otherwise a second projectile in the same frame can be consumed by this
	# already-dead actor before its next physics tick.
	input_pickable = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	if combat_spatial_index != null and is_instance_valid(combat_spatial_index):
		combat_spatial_index.unregister(spatial_actor_runtime_id)
	# Tests, paused actors and temporarily disabled physics processing must still
	# commit death after the current damage/AOE call stack has fully unwound.
	call_deferred("_begin_death")


func _begin_death() -> void:
	if _dying:
		return
	_death_pending = false
	if current_hp > 0:
		return
	clear_entrapment("death")
	_dying = true
	_cancel_autonomous_step(true)
	_pending_attack_time = -1.0
	_pending_attack_target = null
	_pending_attack_damage = 0
	_pending_attack_release_record = {}
	_area_attack_warning = 0.0
	_area_attack_footprint_snapshot = {}
	_area_attack_release_records.clear()
	_area_magic_warning = 0.0
	_area_magic_footprint_snapshot = {}
	_area_magic_release_records.clear()
	input_pickable = false
	collision_layer = 0
	collision_mask = 0
	remove_from_group("enemies")
	if overhead != null:
		overhead.visible = false
	var has_death_art := visual != null and visual.uses_final_art()
	var death_animation_seconds := 0.0
	if has_death_art:
		death_animation_seconds = visual.play_death()
	died.emit(self, monster_data)
	if has_death_art:
		_finish_death_after_animation(death_animation_seconds)
	else:
		queue_free()


func _finish_death_after_animation(animation_seconds: float) -> void:
	await get_tree().create_timer(maxf(0.01, animation_seconds)).timeout
	if not is_instance_valid(self):
		return
	visual.hold_death_pose()
	await get_tree().create_timer(CORPSE_HOLD_SECONDS).timeout
	if is_instance_valid(self):
		queue_free()


func apply_poison(
	tick_damage: int,
	seconds: float,
	interval_seconds := 1.0
) -> void:
	_leave_background_deep_sleep()
	poison_damage = maxi(poison_damage, maxi(1, tick_damage))
	poison_time = maxf(poison_time, seconds)
	poison_tick_interval_seconds = maxf(0.01, float(interval_seconds))
	queue_redraw()


func apply_control(seconds: float) -> void:
	if seconds > 0.0:
		_leave_background_deep_sleep()
	# Re-applying control after a scripted relocation must pin the new position,
	# not an obsolete anchor captured before teleport/knockback resolution.
	if seconds > 0.0:
		_control_anchor_ground_gu = _screen_position_px_to_ground_position_gu(global_position)
		_pending_attack_time = -1.0
		_pending_attack_target = null
		_pending_attack_damage = 0
		_pending_attack_release_record = {}
		velocity = Vector2.ZERO
	control_time = maxf(control_time, seconds)
	queue_redraw()


func apply_entrapment(
	effect: Dictionary,
	boundary_snapshot: Dictionary,
	caster_actor: Node2D
) -> Dictionary:
	_leave_background_deep_sleep()
	var immunity := control_immunity_snapshot()
	if bool(immunity.get("immune", false)):
		_entrapment_last_end_reason = "target_control_immune"
		return {
			"valid": false,
			"reason": "target_control_immune",
			"control_immunity_snapshot": immunity,
		}
	var raw_target_ids: Variant = effect.get("target_instance_ids", [])
	if (
		not raw_target_ids is Array
		or not (raw_target_ids as Array).has(get_instance_id())
	):
		_entrapment_last_end_reason = "target_instance_not_declared"
		return {"valid": false, "reason": "target_instance_not_declared"}
	var next_controller := EntrapmentBoundaryControllerScript.new()
	var result := next_controller.configure(
		effect,
		boundary_snapshot,
		runtime_map_id,
		caster_actor,
		runtime_ground_gu_to_screen_position_px
	)
	if not bool(result.get("valid", false)):
		_entrapment_last_end_reason = str(
			result.get("reason", "entrapment_controller_rejected")
		)
		return result
	var current_ground_gu := _screen_position_px_to_ground_position_gu(global_position)
	if (
		current_ground_gu == Vector2.INF
		or next_controller.movement_candidate_blocked(
			current_ground_gu,
			current_ground_gu,
			combat_radius_gu
		)
	):
		next_controller.reset("target_not_inside_open_center")
		_entrapment_last_end_reason = "target_not_inside_open_center"
		return {"valid": false, "reason": "target_not_inside_open_center"}
	clear_entrapment("replaced")
	_entrapment_controller = next_controller
	_entrapment_last_end_reason = ""
	return result


func clear_entrapment(reason := "cleared") -> void:
	if _entrapment_controller != null:
		_entrapment_controller.reset(reason)
	_entrapment_controller = null
	_entrapment_last_end_reason = reason


func entrapment_active() -> bool:
	return (
		_entrapment_controller != null
		and _entrapment_controller.is_active()
	)


func entrapment_state_snapshot() -> Dictionary:
	if _entrapment_controller != null:
		return _entrapment_controller.state_snapshot()
	return {
		"contract_id": EntrapmentBoundaryControllerScript.CONTRACT_ID,
		"active": false,
		"runtime_map_id": -1,
		"caster_instance_id": 0,
		"remaining_seconds": 0.0,
		"boundary_cell_count": 0,
		"last_end_reason": _entrapment_last_end_reason,
	}


func accepts_external_attack_from(source_actor: Node) -> bool:
	return not (
		entrapment_active()
		and is_instance_valid(source_actor)
		and source_actor is SummonActor
	)


func control_immunity_snapshot() -> Dictionary:
	var reasons: Array[String] = []
	if is_boss:
		reasons.append("boss")
	if _explicit_control_immunity(monster_data):
		reasons.append("monster_data_explicit")
	if _explicit_control_immunity(behavior_profile):
		reasons.append("behavior_profile_explicit")
	for metadata_key: StringName in [
		&"control_immune", &"controlImmune", &"immune_to_control", &"immuneToControl"
	]:
		if has_meta(metadata_key) and bool(get_meta(metadata_key)):
			reasons.append("metadata_explicit")
			break
	return {
		"contract_id": "monster.control_immunity.explicit_snapshot.v1",
		"immune": not reasons.is_empty(),
		"reasons": reasons,
		"boss": is_boss,
		"monster_id": monster_id,
		"instance_id": get_instance_id(),
	}


static func _explicit_control_immunity(source: Dictionary) -> bool:
	for key: String in [
		"control_immune", "controlImmune", "immune_to_control", "immuneToControl"
	]:
		if source.has(key) and bool(source.get(key, false)):
			return true
	for value: Variant in source.values():
		if value is Dictionary and _explicit_control_immunity(value):
			return true
	return false


func _update_entrapment_state(delta: float) -> void:
	if not entrapment_active():
		return
	var caster := _entrapment_controller.caster_actor()
	var caster_center_ground_gu := Vector2.INF
	var caster_radius_gu := 0.0
	if is_instance_valid(caster):
		caster_center_ground_gu = _screen_position_px_to_ground_position_gu(
			caster.global_position
		)
		caster_radius_gu = _target_combat_radius_gu(caster)
	var end_reason := _entrapment_controller.advance(
		delta,
		runtime_map_id,
		caster_center_ground_gu,
		caster_radius_gu
	)
	if not end_reason.is_empty():
		clear_entrapment(end_reason)


func apply_charm(seconds: float) -> void:
	if seconds > 0.0:
		_leave_background_deep_sleep()
	charm_time = maxf(charm_time, seconds)
	queue_redraw()


func canonical_red_poison_active() -> bool:
	if not has_meta("canonical_red_poison"):
		return false
	var poison_data: Variant = get_meta("canonical_red_poison")
	if not poison_data is Dictionary:
		return false
	return Time.get_ticks_msec() < int(
		(poison_data as Dictionary).get("expires_at_ms", 0)
	)


func _update_status_effects(delta: float) -> void:
	var had_visible_status := poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0
	var poison_active_delta := minf(maxf(0.0, delta), poison_time)
	if poison_active_delta > 0.0:
		poison_tick_elapsed_seconds += poison_active_delta
	poison_time = maxf(0.0, poison_time - delta)
	control_time = maxf(0.0, control_time - delta)
	charm_time = maxf(0.0, charm_time - delta)
	if _boss_rage_time > 0.0:
		_boss_rage_time = maxf(0.0, _boss_rage_time - delta)
		if _boss_rage_time <= 0.0:
			move_speed_gu_per_sec = _boss_base_move_speed_gu_per_sec
			_attack_interval = _boss_base_attack_interval
	while poison_tick_elapsed_seconds + 0.000001 >= poison_tick_interval_seconds:
		poison_tick_elapsed_seconds = maxf(
			0.0,
			poison_tick_elapsed_seconds - poison_tick_interval_seconds
		)
		take_damage(poison_damage)
	if poison_time <= 0.0:
		poison_damage = 0
		poison_tick_interval_seconds = 1.0
		poison_tick_elapsed_seconds = 0.0
	var has_visible_status := poison_time > 0.0 or control_time > 0.0 or charm_time > 0.0
	if had_visible_status != has_visible_status:
		queue_redraw()
	if has_meta("canonical_red_poison") and not canonical_red_poison_active():
		remove_meta("canonical_red_poison")
		queue_redraw()


func _apply_health_stage_mechanics() -> void:
	if _boss_health_stage <= 0 or max_hp <= 0:
		return
	var mechanics: Dictionary = boss_rule.get("mechanics", {})
	var summon: Dictionary = mechanics.get("healthStageSummon", {})
	var rage: Dictionary = mechanics.get("healthStageRage", {})
	var stage_count := int(summon.get("stages", rage.get("stages", _boss_health_stage)))
	var current_stage := int(floor(float(current_hp) / float(max_hp) * float(stage_count)))
	if current_stage >= _boss_health_stage:
		return
	_boss_health_stage -= 1
	if bool(summon.get("enabled", false)):
		var count := _rng.randi_range(int(summon.get("minCount", 6)), int(summon.get("maxCount", 11)))
		var ids: Array = summon.get("monsterIds", []).duplicate()
		summon_requested.emit(self, ids, count, int(summon.get("maxActive", 30)))
	if bool(rage.get("enabled", false)):
		_boss_rage_time = float(rage.get("durationSeconds", 8.0))
		move_speed_gu_per_sec = (
			_boss_base_move_speed_gu_per_sec
			* float(rage.get("moveSpeedMultiplier", 1.0))
		)
		_attack_interval = float(rage.get("attackIntervalSeconds", _boss_base_attack_interval))


func _retarget(delta := 0.0) -> void:
	_target_stable_remaining_seconds = maxf(
		0.0,
		_target_stable_remaining_seconds - delta,
	)
	if charm_time > 0.0:
		return
	_decay_threat(delta)
	_retarget_timer = maxf(0.0, _retarget_timer - delta)
	# Release invalid, protected, or disengaged targets before the cadence gate.
	# They can remain valid Godot Objects during a death presentation, and a
	# Boss timer must never pin combat to an unusable target for several seconds.
	if is_instance_valid(target) and (
		not _target_candidate_is_live(target)
		or _point_inside_safe_zone(target.global_position)
		or _target_should_disengage(target)
	):
		target = null
		_retarget_timer = 0.0
		if _movement_step_active:
			_cancel_autonomous_step(true)
	if not boss_rule.is_empty():
		if is_instance_valid(target) and _retarget_timer > 0.0:
			return
	else:
		# Ordinary monsters keep their current target between decision ticks.
		# Damage threat still switches immediately in _add_threat(), so rebuilding
		# the target set for every actor decision adds CPU cost without improving
		# reaction latency; the shared broadphase refreshes within 250 ms instead.
		# delta == 0 is the explicit decision API used when the target set changes
		# immediately (for example, a newly summoned combat target). Physics calls
		# always pass delta and remain rate-limited.
		if _retarget_timer > 0.0 and delta > 0.0:
			return
	var acquiring_without_current_target := not is_instance_valid(target)
	var reevaluating_player_pursuit := (
		is_instance_valid(target) and target is PlayerCharacter
	)
	var chosen: Node2D
	var best_score := -INF
	var best_initial_manhattan_gu := INF
	var intercepting_summon: SummonActor
	var intercepting_summon_distance_gu := INF
	# Once a real blocker has taken over pursuit, retain it only while it remains
	# inside the same live/contact contract. This prevents a high player threat
	# from flipping the target back every decision tick.
	if target is SummonActor:
		var current_summon := target as SummonActor
		var current_summon_distance_gu := _ground_delta_gu_between_screen_positions(
			global_position,
			current_summon.global_position,
		).length()
		if _summon_intercepts_current_pursuit(
			current_summon,
			current_summon_distance_gu,
		):
			intercepting_summon = current_summon
			intercepting_summon_distance_gu = current_summon_distance_gu
	var chose_threat_candidate := false
	var spawn_position:Vector2=get_meta("spawn_position",global_position)
	var leash_radius_gu := aggro_radius_gu * _leash_multiplier
	var candidates:Array=[]
	if is_instance_valid(primary_target):candidates.append(primary_target)
	_ensure_target_grid(delta == 0.0)
	var candidate_range_gu := aggro_radius_gu
	if acquiring_without_current_target:
		candidate_range_gu = float(
			_target_acquisition_policy.view_range_cells
			if _target_acquisition_policy != null
			else 0
		)
	elif not _threat_table.is_empty():
		candidate_range_gu = leash_radius_gu
	var target_grid_has_only_primary := (
		_target_grid_node_ids.size() == 1
		and is_instance_valid(primary_target)
		and _target_grid_node_ids.has(primary_target.get_instance_id())
	)
	if not target_grid_has_only_primary:
		for node: Node2D in _target_grid_candidates(candidate_range_gu):
			if not candidates.has(node):
				candidates.append(node)
	# The current target and live threat entries are always retained even when a
	# target moved or spawned after the last shared cache refresh.  This preserves
	# immediate threat handoff and prevents a stale broadphase from clearing it.
	_append_live_target_candidate(candidates, target)
	for raw_record: Variant in _threat_table.values():
		if not raw_record is Dictionary:
			continue
		var record: Dictionary = raw_record
		var raw_ref: Variant = record.get("node")
		if raw_ref is WeakRef:
			_append_live_target_candidate(candidates, raw_ref.get_ref())
	for node:Node2D in candidates:
		if not _target_candidate_is_live(node):continue
		if _point_inside_safe_zone(node.global_position):continue
		var distance_gu := _ground_delta_gu_between_screen_positions(
			global_position,
			node.global_position,
		).length()
		var spawn_distance_gu := _ground_delta_gu_between_screen_positions(
			spawn_position,
			node.global_position,
		).length()
		var threat:=_threat_for(node)
		if (
			reevaluating_player_pursuit
			and node is SummonActor
			and _summon_intercepts_current_pursuit(node, distance_gu)
			and distance_gu < intercepting_summon_distance_gu
		):
			intercepting_summon = node
			intercepting_summon_distance_gu = distance_gu
		var retaining_current_target := (
			not acquiring_without_current_target
			and is_instance_valid(target)
			and node == target
		)
		# A damage record keeps an attacker in the candidate set between shared
		# grid refreshes, but it does not grant unlimited pursuit. Ranged summons
		# participate without body contact only while they remain inside the
		# existing leash-sized combat engagement envelope.
		if threat > 0.0 and not retaining_current_target and distance_gu > leash_radius_gu:
			continue
		if threat <= 0.0:
			if acquiring_without_current_target:
				var acquisition_delta_ground_gu := (
					_ground_delta_gu_between_screen_positions(
						global_position,
						node.global_position,
					)
				)
				if not _initial_acquisition_contains_ground_delta_gu(
					acquisition_delta_ground_gu
				):
					continue
				if not _initial_acquisition_static_los_clear(node):
					continue
				# M02A first acquisition is centered on the actor's current cell.
				# Spawn return/leash does not narrow this exact ViewRange branch.
				# Preserve stable first-seen ordering for equal Manhattan distance.
				var manhattan_gu := (
					absf(acquisition_delta_ground_gu.x)
					+ absf(acquisition_delta_ground_gu.y)
				)
				if (
					not chose_threat_candidate
					and manhattan_gu < best_initial_manhattan_gu
				):
					best_initial_manhattan_gu = manhattan_gu
					chosen = node
				continue
			elif not retaining_current_target and distance_gu > aggro_radius_gu:
				continue
		# First acquisition is centered on the actor's current cell.  A stale
		# spawn position must not narrow the exact per-monster ViewRange; the
		# leash resumes once a target or threat already exists.
		if (
			not acquiring_without_current_target
			and not retaining_current_target
			and spawn_distance_gu > leash_radius_gu
		):
			continue
		var distance_score := (
			maxf(0.0, 1.0 - distance_gu / maxf(aggro_radius_gu, GroundUnitSpace.EPSILON_GU))
			* 100.0
		)
		var score:=threat+distance_score
		if score>best_score:
			best_score=score
			chosen=node
			if acquiring_without_current_target and threat > 0.0:
				chose_threat_candidate = true
	# Threat remains authoritative at ordinary distances, with target stability
	# and a score-independent threat margin preventing alternating hits from
	# ping-ponging the actor. Only a live summon already inside the monster's
	# physical contact envelope may bypass that hysteresis and intercept pursuit.
	if intercepting_summon != null:
		chosen = intercepting_summon
	elif (
		is_instance_valid(target)
		and chosen != target
		and not _target_switch_challenge_wins(target, chosen)
	):
		chosen = target
	target = chosen
	_retarget_decision_count += 1
	if not boss_rule.is_empty():
		var search: Dictionary = boss_rule.get("targetSearch", {})
		var authored_interval_seconds := (
			float(search.get(
				"withTargetMs" if is_instance_valid(target) else "withoutTargetMs",
				1000,
			)) / 1000.0
		)
		_retarget_timer = (
			clampf(
				authored_interval_seconds,
				NEAR_RETARGET_MIN_SECONDS,
				BOSS_TARGET_REEVALUATION_MAX_SECONDS,
			)
			+ BOSS_TARGET_REEVALUATION_STAGGER_SECONDS
			* float(posmod(get_instance_id(), 11))
		)
	elif is_instance_valid(target):
		_retarget_timer = NEAR_RETARGET_MIN_SECONDS + NEAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 7))
	else:
		_retarget_timer = FAR_RETARGET_MIN_SECONDS + FAR_RETARGET_STAGGER_SECONDS * float(posmod(get_instance_id(), 11))


func _add_threat(source:Node2D,amount:float)->void:
	if not _target_candidate_is_live(source):
		return
	_leave_background_deep_sleep()
	var key:=source.get_instance_id()
	_threat_table[key]={"node":weakref(source),"score":float(_threat_table.get(key,{}).get("score",0.0))+maxf(0.0,amount)}
	# Damage records participation only. Target changes are resolved by the
	# existing bounded retarget cadence so one low hit cannot steal focus.
	if source == target:
		_refresh_target_focus()


func _target_switch_challenge_wins(
	current_target: Node2D,
	challenger: Node2D,
) -> bool:
	if (
		not _target_candidate_is_live(current_target)
		or not _target_candidate_is_live(challenger)
	):
		return true
	if _target_stable_remaining_seconds > 0.0:
		return false
	var current_threat := maxf(0.0, _threat_for(current_target))
	var challenger_threat := maxf(0.0, _threat_for(challenger))
	var required_advantage := maxf(
		TARGET_SWITCH_MIN_THREAT_ADVANTAGE,
		current_threat * TARGET_SWITCH_THREAT_ADVANTAGE_RATIO,
	)
	return challenger_threat >= current_threat + required_advantage


func _target_candidate_is_live(candidate: Node2D) -> bool:
	if not is_instance_valid(candidate) or candidate.is_queued_for_deletion():
		return false
	# Production combat targets have explicit typed life-state contracts. Avoid
	# Object.get() probes for optional properties: generic test/runtime target
	# nodes are valid candidates and missing-property probes emit engine errors.
	if candidate is PlayerCharacter and (candidate._dead or candidate.current_hp <= 0):
		return false
	if candidate is EnemyActor and (candidate._dying or candidate.current_hp <= 0):
		return false
	if candidate is SummonActor and (
		candidate.current_hp <= 0
		or candidate.state in [SummonActor.SummonState.DEAD, SummonActor.SummonState.EXPIRED]
	):
		return false
	return _runtime_map_id_for_area_target(candidate) == runtime_map_id


func _summon_intercepts_current_pursuit(
	candidate: SummonActor,
	distance_gu: float,
) -> bool:
	return (
		_target_candidate_is_live(candidate)
		and candidate.is_in_group("combat_targets")
		and candidate.has_method("take_damage")
		and not _point_inside_safe_zone(candidate.global_position)
		and distance_gu
			<= _contact_distance_gu_to_target(candidate)
			+ SUMMON_INTERCEPT_CONTACT_EPSILON_GU
	)


func _slide_collision_intercepting_summon() -> SummonActor:
	if _movement_step_reason != &"pursuit" or not target is PlayerCharacter:
		return null
	var closest: SummonActor
	var closest_distance_gu := INF
	for collision_index in range(get_slide_collision_count()):
		var collision := get_slide_collision(collision_index)
		if collision == null:
			continue
		var raw_collider: Variant = collision.get_collider()
		if not raw_collider is SummonActor:
			continue
		var candidate := raw_collider as SummonActor
		var distance_gu := _ground_delta_gu_between_screen_positions(
			global_position,
			candidate.global_position,
		).length()
		if (
			_summon_intercepts_current_pursuit(candidate, distance_gu)
			and distance_gu < closest_distance_gu
		):
			closest = candidate
			closest_distance_gu = distance_gu
	return closest


func _threat_for(source:Node2D)->float:
	return float(_threat_table.get(source.get_instance_id(),{}).get("score",0.0))


func _decay_threat(delta:float)->void:
	for key:Variant in _threat_table.keys():
		var record:Dictionary=_threat_table[key];var ref:WeakRef=record.get("node")
		var node:Node = null
		if ref!=null:node=ref.get_ref() as Node
		if not is_instance_valid(node):_threat_table.erase(key);continue
		record["score"]=maxf(0.0,float(record.get("score",0.0))-_threat_decay_per_second*delta)
		if float(record.score)<=0.0:_threat_table.erase(key)
		else:_threat_table[key]=record


func _return_to_spawn(
	delta := 1.0 / 60.0
) -> void:
	var spawn_position:Vector2=get_meta("spawn_position",global_position)
	var return_direction_ground_gu := _ground_delta_gu_between_screen_positions(
		global_position,
		spawn_position,
	)
	if _movement_step_active:
		_advance_autonomous_step(delta)
		return
	if return_direction_ground_gu.length() <= SPAWN_RETURN_EPSILON_GU:
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
		return
	var return_facing_px := _screen_facing_for_ground_direction(return_direction_ground_gu)
	facing = return_facing_px
	movement_facing = return_facing_px
	var started := _request_autonomous_step(
		return_direction_ground_gu,
		0.75,
		false,
		&"return_to_spawn"
	)
	if started:
		_advance_autonomous_step(delta)
	else:
		velocity = Vector2.ZERO
		actual_ground_motion_gu = Vector2.ZERO
	queue_redraw()


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
	if dormant:
		draw_circle(Vector2(0, -5), radius_px + 3.0, Color(0.52, 0.50, 0.46, 0.72))
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
	if not bool(special.get("enabled", false)):
		return PackedVector2Array()
	var snapshot := _boss_skill_footprint_snapshot
	if not _snapshot_strict_ok(snapshot):
		snapshot = _create_boss_skill_footprint_snapshot(
			special,
			"monster:%d:preview" % monster_id,
		)
	return SkillFootprintSnapshotScript.project_ground_polygon_to_screen_offsets_px(
		SkillFootprintSnapshotScript.ground_polygon_gu(snapshot),
		_screen_position_px_to_ground_position_gu(global_position)
	)


func _create_boss_skill_footprint_snapshot(
	special: Dictionary,
	release_id: String,
) -> Dictionary:
	var radius_gu := MonsterUnitAdapterScript.range_gu(
		special,
		"radius_gu",
		"radius",
		MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(155.0),
	)
	var snapshot: Dictionary
	if str(special.get("shape", "circle")) == "cone":
		snapshot = SkillFootprintSnapshotScript.create_sector_arc(
			_monster_attack_id("boss_sector_arc"),
			release_id,
			_screen_position_px_to_ground_position_gu(global_position),
			_boss_skill_direction_ground,
			radius_gu,
			float(special.get("coneHalfAngleRadians", 0.68)),
			24,
			_snapshot_coordinate_context(),
		)
		return _decorate_attack_footprint_snapshot(
			snapshot,
			PROJECTION_RELATIONSHIP_DIRECTED_CORE,
			target if is_instance_valid(target) else null,
			radius_gu,
		)
	snapshot = SkillFootprintSnapshotScript.create_circle(
		_monster_attack_id("boss_circle"),
		release_id,
		_screen_position_px_to_ground_position_gu(global_position),
		radius_gu,
		48,
		_snapshot_coordinate_context(),
	)
	return _decorate_attack_footprint_snapshot(
		snapshot,
		PROJECTION_RELATIONSHIP_GROUND_EXACT,
		target if is_instance_valid(target) else null,
		radius_gu,
	)


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
	if overhead != null:
		overhead.set_health(current_hp, max_hp)


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
	# The targeting ring is the physics footprint enlarged uniformly around the
	# same foot point. Per-monster collision radii therefore keep small monsters
	# small and large monsters/Bosses large without inventing another body-size
	# or vertical-squash coordinate system.
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
	var special: Dictionary = boss_rule.get("specialSkill", {})
	var phase: Dictionary = boss_rule.get("phaseTwo", {})
	var skill_radius_gu := MonsterUnitAdapterScript.range_gu(
		special,
		"radius_gu",
		"radius",
		MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(155.0),
	)
	var damage_multiplier := int(special.get("damageMultiplier", 1))
	if _boss_phase_two:
		damage_multiplier = int(phase.get("skillDamageMultiplier", damage_multiplier))
	if _boss_warning > 0.0:
		queue_redraw()
		_boss_warning -= delta
		if _boss_warning <= 0.0:
			_last_boss_skill_hit = false
			var release_snapshot := _boss_skill_footprint_snapshot
			if not _snapshot_strict_ok(release_snapshot):
				release_snapshot = _create_boss_skill_footprint_snapshot(
					special,
					_next_spatial_release_id("boss_fallback"),
				)
			if str(special.get("shape", "circle")) == "cone" and is_instance_valid(target):
				if (
					_snapshot_intersects_target(release_snapshot, target)
					and not _target_is_safe_player(target)
				):
					target.take_damage(_rng.randi_range(attack_min, attack_max) * damage_multiplier)
					_last_boss_skill_hit = true
			else:
				var target_mode := str(special.get("targetMode", "current_target"))
				var victims: Array[Node2D] = []
				if target_mode == "all_combat_targets":
					victims = _boss_skill_targets(skill_radius_gu, release_snapshot)
				elif (
					is_instance_valid(target)
					and _snapshot_intersects_target(release_snapshot, target)
				):
					victims.append(target)
				for victim: Node2D in victims:
					if _target_is_safe_player(victim):
						continue
					victim.take_damage(_rng.randi_range(attack_min, attack_max) * damage_multiplier)
					_apply_boss_skill_status(victim, special)
					_last_boss_skill_hit = true
			_last_attack_footprint_snapshot = release_snapshot
			_boss_skill_footprint_snapshot = {}
			_boss_skill_cooldown = float(phase.get("skillCooldownSeconds", special.get("cooldownSeconds", 4.6))) if _boss_phase_two else float(special.get("cooldownSeconds", 4.6))
	elif _boss_skill_cooldown > 0.0:
		_boss_skill_cooldown -= delta
	else:
		var trigger_range_gu := MonsterUnitAdapterScript.range_gu(
			special,
			"trigger_range_gu",
			"triggerRange",
			MonsterUnitAdapterScript.legacy_screen_scalar_px_to_gu(250.0),
		)
		if distance_gu > trigger_range_gu:
			return
		_boss_skill_direction_ground = (
			_ground_delta_gu_between_screen_positions(global_position, target.global_position).normalized()
			if is_instance_valid(target)
			else GroundUnitSpace.screen_delta_px_to_ground_delta_gu(facing).normalized()
		)
		_boss_skill_footprint_snapshot = _create_boss_skill_footprint_snapshot(
			special,
			_next_spatial_release_id("boss_special"),
		)
		_boss_warning = maxf(0.001, float(special.get("warningSeconds", 0.85)))
		if visual != null:
			visual.play_attack(float(special.get("animationSeconds", _attack_animation_duration)))


func _boss_skill_targets(radius_gu: float, snapshot := {}) -> Array[Node2D]:
	var result: Array[Node2D] = []
	var resolved_snapshot: Dictionary = snapshot
	if not _snapshot_strict_ok(resolved_snapshot):
		resolved_snapshot = SkillFootprintSnapshotScript.create_circle(
			_monster_attack_id("boss_circle"),
			"monster:%d:boss_target_query" % monster_id,
			_screen_position_px_to_ground_position_gu(global_position),
			radius_gu,
			SkillFootprintSnapshotScript.DEFAULT_CURVE_SEGMENTS,
			_snapshot_coordinate_context(),
		)
		resolved_snapshot = _decorate_attack_footprint_snapshot(
			resolved_snapshot,
			PROJECTION_RELATIONSHIP_GROUND_EXACT,
			null,
			radius_gu,
		)
	var candidates: Array[Node] = []
	if is_instance_valid(primary_target):
		candidates.append(primary_target)
	for node: Node in get_tree().get_nodes_in_group("combat_targets"):
		if not candidates.has(node):
			candidates.append(node)
	for node: Node in candidates:
		if (
			node is Node2D
			and node.has_method("take_damage")
			and not _target_is_safe_player(node)
			and _snapshot_intersects_target(resolved_snapshot, node)
		):
			result.append(node)
	return result


func _apply_boss_skill_status(victim: Node2D, special: Dictionary) -> void:
	if _rng.randf() > float(special.get("statusChance", 0.0)):
		return
	var poison_weight := maxi(0, int(special.get("poisonWeight", 0)))
	var control_weight := maxi(0, int(special.get("controlWeight", 0)))
	if poison_weight + control_weight <= 0:
		return
	if _rng.randi_range(1, poison_weight + control_weight) <= poison_weight and victim.has_method("apply_poison"):
		victim.apply_poison(int(special.get("poisonDamage", 1)), float(special.get("poisonSeconds", 1.0)))
	elif victim.has_method("apply_control"):
		victim.apply_control(float(special.get("controlSeconds", 1.0)))


func request_surrounded_relocation(blocking_neighbor_count: int) -> bool:
	var relocation: Dictionary = boss_rule.get("mechanics", {}).get("surroundedRelocation", {})
	if not bool(relocation.get("enabled", false)) or blocking_neighbor_count < int(relocation.get("blockingNeighbors", 5)):
		return false
	relocation_requested.emit(
		self,
		MonsterUnitAdapterScript.relocation_radius_gu(relocation, 4.0),
	)
	return true
