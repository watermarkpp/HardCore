extends Node2D

const BICH_RUNTIME_MAP_ID := 910001
const ORC_TOMB_F3_RUNTIME_MAP_ID := 911003
const INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC := 60000
const TownMusicControllerScript := preload("res://scripts/town_music_controller.gd")
const AudioRuntimeServiceScript := preload("res://scripts/audio_runtime_service.gd")
const LevelUpEffectScript := preload("res://scripts/ui_level_up_preview.gd")

var _town_music_controller: Node
var _audio_runtime_service: Node
var _player_level_up_effect: Node2D

const EquipmentRulesScript := preload("res://scripts/equipment_rules.gd")
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
const ATTACK_INPUT_TICKET_CONTRACT_ID := "combat.input.attack_ticket.touch_lifecycle.v1"
const MAX_BUFFERED_MOBILE_ATTACK_TICKETS := 32
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
const RANDOM_TELEPORT_ACTOR_CLEARANCE_GU := 0.25
const CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU := 2.0
const CANONICAL_SUMMON_ACTOR_CLEARANCE_GU := 0.05
const DEATH_DROP_WORK_BUDGET_USEC := 1200
const DEATH_JOBS_MAX_PER_FRAME := 4
const DROP_NODES_MAX_PER_FRAME := 8
const DEATH_QUEUE_MAX_RETRIES := 3
const DEATH_QUEUE_RETRY_DELAY_MSEC := 100
const DEATH_TERMINAL_LEDGER_MAX := 64
const DEATH_STATE_QUEUED := "QUEUED"
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
var hud: GameHUD
var background: WorldBackground
var current_zone := ""
var current_map_id := -1
var current_map_data: Dictionary = {}
var _zone_generation := 0
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
var _active_boss_cache: Dictionary = {}
var _safe_zone_enforcement_remaining := 0.0
var _combat_spatial_index: RuntimeCombatSpatialIndexScript
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
var _map_transition_in_progress := false
var _map_transition_serial := 0
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
var _enemy_death_flush_queued := false
var _enemy_death_pipeline_running := false
var _enemy_death_target_refresh_pending := false
var _enemy_death_sequence := 0
var _enemy_death_terminal_jobs: Array[Dictionary] = []
var _enemy_death_terminal_total_count := 0
var _last_death_logout_failure: Dictionary = {}
var _death_settled_jobs_last_batch := 0
var _death_drop_work_budget_usec_override := -1
var _death_jobs_max_per_frame_override := -1
var _drop_nodes_max_per_frame_override := -1
var _test_force_loot_materialization_failure_count := 0
var _pending_loot_collections: Array = []
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
	_player_safe_zone_cache = {
		"player_instance_id": (
			player.get_instance_id()
			if is_instance_valid(player)
			else 0
		),
		"map_id": current_map_id,
		"revision": int(_safe_zone_context.get("revision", -1)),
		"generation": _zone_generation,
		"ground_position_gu": Vector2.INF,
		"inside": false,
		"valid": false,
	}


func _refresh_player_safe_zone_cache(force := false) -> bool:
	if not is_instance_valid(player):
		_invalidate_player_safe_zone_cache()
		return false
	var context_valid := bool(_safe_zone_context.get("valid", false))
	var ground_position_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var context_revision := int(_safe_zone_context.get("revision", -1))
	var player_instance_id := player.get_instance_id()
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
	var inside := (
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
	return _refresh_player_safe_zone_cache()


func _set_player_world_position(position_px: Vector2) -> void:
	if not is_instance_valid(player):
		return
	player.global_position = position_px
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
	return reference_audit_mode or _aoe_reference_fallback_test_enabled


func _aoe_reference_enemy_nodes_into(output: Array[EnemyActor]) -> bool:
	output.clear()
	if not _aoe_reference_fallback_allowed():
		return false
	RuntimeDiagnostics.increment_performance_counter(
		&"aoe_full_enemy_group_scans"
	)
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if (
			value is EnemyActor
			and is_instance_valid(value)
			and not (value as EnemyActor).is_queued_for_deletion()
			and not bool((value as EnemyActor)._dying)
			and not bool((value as EnemyActor)._death_pending)
			and (value as EnemyActor).current_hp > 0
		):
			output.append(value as EnemyActor)
	RuntimeDiagnostics.increment_performance_counter(
		&"aoe_spatial_candidates",
		output.size(),
	)
	return true


func _target_spatial_query_ready() -> bool:
	## Player target/occupancy paths are formal mapped-world consumers.  A
	## missing index or projection is a rejection, never an implicit group scan.
	if (
		_combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
		or current_map_id < 0
	):
		projection_rejection_reason = &"target_spatial_index_unavailable"
		return false
	var profile := _resolve_projection_profile_for_map(current_map_id)
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


func _target_spatial_enemy_is_current(enemy: EnemyActor) -> bool:
	return (
		is_instance_valid(enemy)
		and not enemy.is_queued_for_deletion()
		and not enemy._dying
		and not enemy._death_pending
		and enemy.current_hp > 0
		and enemy.runtime_map_id == current_map_id
		and enemy.projection_ready()
		and int(enemy.get_meta("zone_generation", -1)) == _zone_generation
	)


func _target_spatial_query_aabb_into(
	bounds_ground_gu: Rect2,
	output: Array[EnemyActor],
) -> bool:
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
	_combat_spatial_index.query_enemy_nodes_aabb_into(
		current_map_id,
		bounds_ground_gu,
		output,
	)
	var write_index := 0
	for raw_enemy: Variant in output:
		if not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		if not _target_spatial_enemy_is_current(enemy):
			continue
		output[write_index] = enemy
		write_index += 1
	output.resize(write_index)
	return true


func _target_spatial_query_segment_into(
	start_ground_gu: Vector2,
	end_ground_gu: Vector2,
	expansion_gu: float,
	output: Array[EnemyActor],
) -> bool:
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
	_combat_spatial_index.query_enemy_nodes_segment_into(
		current_map_id,
		start_ground_gu,
		end_ground_gu,
		expansion_gu,
		output,
	)
	var write_index := 0
	for raw_enemy: Variant in output:
		if not raw_enemy is EnemyActor:
			continue
		var enemy := raw_enemy as EnemyActor
		if not _target_spatial_enemy_is_current(enemy):
			continue
		output[write_index] = enemy
		write_index += 1
	output.resize(write_index)
	return true


func _aoe_build_query_plan(
	skill_id: String,
	release_id: String,
	snapshot: Dictionary,
	validation_context: Dictionary,
	options: Dictionary,
	release_cache: Dictionary,
) -> Dictionary:
	if snapshot.is_empty() or skill_id.is_empty() or release_id.is_empty():
		return {}
	var was_cached := release_cache.has(release_id)
	var strict_count_before := SkillFootprintQueryPlanScript.strict_validation_count
	var plan := SkillFootprintQueryPlanScript.build_once(
		release_cache,
		release_id,
		skill_id,
		current_map_id,
		snapshot,
		validation_context,
		options,
	)
	if not was_cached:
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_query_plan_builds"
		)
		if SkillFootprintQueryPlanScript.strict_validation_count > strict_count_before:
			RuntimeDiagnostics.increment_performance_counter(
				&"aoe_snapshot_validation_calls"
			)
	return plan


func _aoe_plan_snapshot(plan: Dictionary) -> Dictionary:
	var raw_snapshot: Variant = plan.get("validated_snapshot_reference", {})
	return raw_snapshot as Dictionary if raw_snapshot is Dictionary else {}


func _aoe_plan_is_ready(plan: Dictionary) -> bool:
	if (
		plan.is_empty()
		or not bool(plan.get("valid", false))
		or _combat_spatial_index == null
		or not is_instance_valid(_combat_spatial_index)
		or current_map_id < 0
		or int(plan.get("runtime_map_id", -1)) != current_map_id
	):
		return false
	var snapshot := _aoe_plan_snapshot(plan)
	return str(snapshot.get("coordinate_space", "")) == str(
		SkillFootprintSnapshotScript.COORDINATE_SPACE_RUNTIME_MAP_ABSOLUTE_GROUND_GU
	)


func _aoe_record_query_rejection(reason: String) -> void:
	projection_rejection_reason = reason


func _aoe_query_enemy_candidates_aabb(
	plan: Dictionary,
	bounds_ground_gu: Rect2,
	allow_reference_fallback := true,
) -> bool:
	_aoe_candidate_scratch.clear()
	if _aoe_plan_is_ready(plan):
		_combat_spatial_index.query_enemy_nodes_aabb_into(
			current_map_id,
			bounds_ground_gu,
			_aoe_candidate_scratch,
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_spatial_queries"
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_spatial_candidates",
			_aoe_candidate_scratch.size(),
		)
		return true
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
	allow_reference_fallback := true,
) -> bool:
	_aoe_candidate_scratch.clear()
	if _aoe_plan_is_ready(plan):
		_combat_spatial_index.query_enemy_nodes_segment_into(
			current_map_id,
			start_ground_gu,
			end_ground_gu,
			expansion_gu,
			_aoe_candidate_scratch,
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_spatial_queries"
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_spatial_candidates",
			_aoe_candidate_scratch.size(),
		)
		return true
	if allow_reference_fallback and _aoe_reference_fallback_allowed():
		return _aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
	_aoe_record_query_rejection(
		"aoe_spatial_index_unavailable_or_runtime_map_mismatch"
	)
	return false


func _aoe_validated_snapshot_intersects(
	plan: Dictionary,
	enemy: EnemyActor,
) -> bool:
	if not _aoe_plan_is_ready(plan) or not is_instance_valid(enemy):
		return false
	var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
	if not target_ground_gu.is_finite():
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		_aoe_plan_snapshot(plan),
		target_ground_gu,
		enemy.combat_radius_gu,
	)


func _aoe_insert_by_instance_id(
	targets: Array[EnemyActor],
	ids: Array[int],
	enemy: EnemyActor,
) -> void:
	var enemy_id := enemy.get_instance_id()
	var insert_at := targets.size()
	for index: int in range(ids.size()):
		if enemy_id < ids[index]:
			insert_at = index
			break
	ids.insert(insert_at, enemy_id)
	targets.insert(insert_at, enemy)


func _aoe_insert_by_distance(
	targets: Array[EnemyActor],
	distances: Array[float],
	ids: Array[int],
	enemy: EnemyActor,
	distance_along_line_gu: float,
) -> void:
	var enemy_id := enemy.get_instance_id()
	var insert_at := targets.size()
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
	if cells.is_empty():
		return Rect2()
	var minimum := Vector2(cells[0]) - Vector2.ONE * 0.5
	var maximum := Vector2(cells[0]) + Vector2.ONE * 0.5
	for cell: Vector2i in cells:
		var center := Vector2(cell)
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
	var resolved_skill_id := skill_id if not skill_id.is_empty() else "legacy_damage"
	var snapshot := SkillFootprintSnapshotScript.create_circle(
		resolved_skill_id,
		"legacy_damage",
		origin_ground_gu,
		maxf(0.0, radius_gu),
		32,
		_canonical_snapshot_absolute_context(origin_ground_gu),
	)
	var options := {
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
	var hit_any := false
	var geometry_matches := 0
	for enemy: EnemyActor in candidates:
		if (
			not is_instance_valid(enemy)
			or enemy.is_queued_for_deletion()
			or enemy.current_hp <= 0
		):
			continue
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_exact_intersection_tests"
		)
		var target_ground_gu := _canonical_screen_px_to_ground_gu(
			enemy.global_position
		)
		var offset_ground_gu := target_ground_gu - origin_ground_gu
		var in_arc := (
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
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_selected_targets"
		)
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_damage_target_count"
		)
		if physical_accuracy and not PlayerState.test_mode:
			var accuracy := int(PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT))
			if not WarriorCombatMath.roll_hit(accuracy, enemy.agility, _rng):
				continue
		var resolved_damage := damage
		if CombatResolutionRulesScript.anti_magic_eligible(source_skill_id):
			var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
				enemy,
				source_skill_id,
				damage,
				player,
				_rng,
				Callable(self, "_resolve_magic_defense"),
				-1,
				_direct_spell_target_stats_scratch,
			)
			resolved_damage = int(resolution.get("final_damage", 0))
			if resolved_damage > 0:
				hit_any = true
			continue
		if resolved_damage <= 0:
			continue
		hit_any = _combat_runtime.apply_enemy_physical_damage(
			enemy,
			resolved_damage,
			player,
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
	var snapshot := melee_release_snapshot
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
	var release_id := str(release_geometry.get("release_id", ""))
	if release_id.is_empty() and not snapshot.is_empty():
		release_id = str(snapshot.get("release_id", ""))
	if release_id.is_empty():
		release_id = "melee:preflight:%s" % mode
	if snapshot.is_empty():
		var direction_index := _melee_direction_index(direction, release_geometry)
		snapshot = WarriorMeleeGeometryScript.attack_release_footprint_snapshot_ground_gu(
			skill_id,
			release_id,
			origin_ground_gu,
			direction_index,
			mode,
			0.0,
			_canonical_snapshot_absolute_context(origin_ground_gu),
		)
	var options := {
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
	for enemy: EnemyActor in candidates:
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
	if not bool(target_plan.get("target_axis_eligible", false)):
		return -1
	var raw_snapshot: Variant = target_plan.get("skill_footprint_snapshot", {})
	if not raw_snapshot is Dictionary:
		return -1
	var snapshot := raw_snapshot as Dictionary
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
	var effective_reach_gu := WarriorMeleeGeometryScript.reach_gu(
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
	var snapshot := _aoe_spell_snapshot(
		skill_release_snapshot,
		continuous_line_strip_ground_gu,
	)
	if snapshot.is_empty():
		return {}
	var resolved_skill_id := stable_skill_id
	if resolved_skill_id.is_empty():
		resolved_skill_id = str(snapshot.get("skill_id", ""))
	if resolved_skill_id.is_empty():
		resolved_skill_id = "canonical_aoe"
	var release_id := str(snapshot.get("release_id", ""))
	if release_id.is_empty():
		release_id = str(continuous_line_strip_ground_gu.get("release_id", ""))
	if release_id.is_empty():
		return {}
	var maximum_targets := int(effect.get("maximum_targets", -1))
	var is_continuous_line := (
		resolved_skill_id in CONTINUOUS_WIZARD_LINE_SKILLS
		and _is_supported_continuous_line_contract(
			str(continuous_line_strip_ground_gu.get("contract_id", ""))
		)
	)
	if is_continuous_line and str(effect.get("target_limit_policy", "")) == "all_intersecting_effect_cells":
		maximum_targets = -1
	var ordering_policy := SkillFootprintQueryPlanScript.ORDERING_STABLE_COMBAT_INSTANCE
	if str(snapshot.get("shape_type", "")) == SkillFootprintSnapshotScript.SHAPE_CELL_UNION:
		ordering_policy = SkillFootprintQueryPlanScript.ORDERING_CELL_INSTANCE
	elif raw_geometry_cells is Array and not (raw_geometry_cells as Array).is_empty():
		ordering_policy = SkillFootprintQueryPlanScript.ORDERING_CELL_INSTANCE
	var options := {
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
	var validation_origin := (
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

# --- P1-A: Gameplay Input Gate (counted runtime locks) ---

const INPUT_LOCK_INITIAL_BOOTSTRAP := &"initial_world_bootstrap"
const INPUT_LOCK_MAP_TRANSITION := &"map_transition"
const INPUT_LOCK_PLAYER_DEATH := &"player_death"
const DEATH_REVIVAL_CONTRACT_ID := "ui.death.revival.v1"
const DEATH_REVIVAL_FLOW_ID := "player.death.lifecycle.ui_gated.v1"


func gameplay_input_is_enabled() -> bool:
	return _player_input_enabled


func _acquire_gameplay_input_lock(reason: StringName) -> void:
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
		_combat_spatial_index
	)
	# Q2-D: one MonsterVisual streaming coordinator; MonsterVisual instances
	# register needs and the coordinator owns the single global streaming poll.
	_streaming_coordinator = MonsterVisualStreamingCoordinatorScript.new()
	MonsterVisualScript.set_streaming_coordinator(_streaming_coordinator)
	# Q0-B: make the window close request interceptable so a failed safe logout
	# can cancel the normal shutdown instead of silently quitting.
	get_tree().auto_accept_quit = false
	_bich_camp_layout = GothicBichCampBuilderScript.load_layout()
	_register_input_actions()
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
	player.skill_cast_started.connect(_on_skill_cast_audio_started)
	player.warrior_skill_state_changed.connect(_on_warrior_skill_state_changed)
	player.stats_changed.connect(_on_player_stats_changed)
	player.movement_performed.connect(_on_player_moved)
	player.death_requested.connect(_on_player_death_requested)
	PlayerState.consumable_requested.connect(_on_consumable_used)
	PlayerState.scroll_requested.connect(_on_scroll_used)
	PlayerState.item_audio_committed.connect(_on_item_audio_committed)
	add_child(player)
	_player_level_up_effect = LevelUpEffectScript.new()
	_player_level_up_effect.name = "PlayerLevelUpEffect"
	_player_level_up_effect.z_index = 0
	player.add_child(_player_level_up_effect)
	_player_level_up_effect.process_mode = Node.PROCESS_MODE_INHERIT
	_player_level_up_effect.set_meta("preview_only", false)
	_player_level_up_effect.set_meta("gameplay_event_source", "PlayerState.levels_gained")
	PlayerState.levels_gained.connect(_on_player_levels_gained)
	_loot_pickup_runtime_manager = LootPickupRuntimeManagerScript.new()
	_loot_pickup_runtime_manager.name = "LootPickupRuntimeManager"
	_loot_pickup_runtime_manager.configure_player(player)
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
	_world_camera.position_smoothing_enabled = true
	_world_camera.position_smoothing_speed = 7.0
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
	hud.special_action_pressed.connect(_on_special_action_pressed)
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
	# bounded ADB mailbox service; release builds never create the node.
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
	if is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.stop_all_audio("world_exited")
	if PlayerState.levels_gained.is_connected(_on_player_levels_gained):
		PlayerState.levels_gained.disconnect(_on_player_levels_gained)
	if PlayerState.item_audio_committed.is_connected(_on_item_audio_committed):
		PlayerState.item_audio_committed.disconnect(_on_item_audio_committed)
	if is_instance_valid(_town_music_controller):
		_town_music_controller.cancel("world_exited")
	PlayerState.clear_taoist_main_pets_persistence_provider()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		# Android's WM back notification does not travel through ui_cancel, so
		# defer the same toggle used by the keyboard path.  This also lets a
		# paused tree close the WHEN_PAUSED menu cleanly on the next idle tick.
		call_deferred("_toggle_system_menu")
	elif what in [NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if is_instance_valid(hud):
			hud.cancel_attack_inputs(&"application_interrupted")
			hud.cancel_skill_inputs(&"application_interrupted")
		_cancel_all_mobile_attack_inputs(true)
		_cancel_all_skill_inputs(true)
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_cancel_all_mobile_attack_inputs(true)
		_cancel_all_skill_inputs(true)
		var close_logout_result := _prepare_safe_logout()
		if not bool(close_logout_result.get("success", false)):
			_handle_safe_logout_failure(&"wm_close_request", close_logout_result)
			return
		get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_system_menu()
		get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	var physics_started_usec := RuntimeDiagnostics.timing_start()
	# Q2-B: generic persistent ground effects are scheduled once per physics
	# frame by the shared manager (old per-effect _physics_process cadence).
	if _ground_effect_manager != null:
		_ground_effect_manager.tick_frame(delta)
	RuntimeDiagnostics.record_timing_ms(&"physics_process_ms", physics_started_usec)


func _process(delta: float) -> void:
	var process_started_usec := RuntimeDiagnostics.timing_start()
	# R3X-4: advance deferred death settlement/materialization in bounded main
	# thread slices.  The queue is deliberately pumped before ordinary world
	# presentation so a non-empty queue cannot starve behind unrelated UI work.
	_pump_enemy_death_work_queue()
	UIItemTextureCacheScript.poll_threaded_paths()
	# Q2-D: the single formal MonsterVisual streaming poll (once per frame).
	if _streaming_coordinator != null:
		_streaming_coordinator.poll_once(Engine.get_process_frames())
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
	if bound_attack_skill.is_empty():
		if Input.is_action_just_pressed("attack"):
			_submit_mobile_attack_ticket(_allocate_synthetic_attack_token())
		if not _queued_mobile_attack_tickets.is_empty():
			_drain_next_mobile_attack_ticket()
		elif _mobile_attack_held or Input.is_action_pressed("attack"):
			_request_mobile_attack()
	else:
		_queued_mobile_attack_tickets.clear()
		if Input.is_action_just_pressed("attack"):
			_keyboard_bound_skill_token = _allocate_synthetic_attack_token()
			_on_skill_input_started(
				PlayerState.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
		if Input.is_action_just_released("attack") and _keyboard_bound_skill_token != 0:
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
	_set_player_world_position(corrected)
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
		return
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		_world_camera.zoom = base_zoom
		_world_camera.position = Vector2.ZERO
		return
	var design_size := Vector2i(int(raw_size[0]), int(raw_size[1]))
	var viewport_half := get_viewport().get_visible_rect().size * 0.5
	var target := MapDiamondCameraConstraintScript.resolve_soft_follow(
		design_size, viewport_half, base_zoom, player.global_position
	)
	var target_zoom: Vector2 = target.get("recommended_zoom", base_zoom)
	var zoom_alpha := 1.0 - exp(-6.0 * maxf(0.0, delta))
	var resolved_zoom := _world_camera.zoom.lerp(target_zoom, zoom_alpha)
	resolved_zoom.x = clampf(
		resolved_zoom.x, ArtSpec.CAMERA_ZOOM,
		MapDiamondCameraConstraintScript.DEFAULT_MAXIMUM_ZOOM
	)
	resolved_zoom.y = resolved_zoom.x
	# Re-resolve the position at the zoom actually displayed this frame. This
	# keeps the player inside the +/-14% screen band even while zoom is easing.
	var result := MapDiamondCameraConstraintScript.resolve_soft_follow(
		design_size, viewport_half, resolved_zoom, player.global_position,
		resolved_zoom.x
	)
	_world_camera.zoom = resolved_zoom
	_world_camera.global_position = Vector2(
		result.get("center", player.global_position)
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
	_system_menu_panel.set_audio_settings(
		_audio_bus_enabled("Music"),
		_audio_bus_enabled("SFX")
	)


func _show_system_menu() -> void:
	if _system_menu_panel == null:
		return
	_system_menu_pause_owned = true
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
	_system_menu_pause_owned = false
	get_tree().paused = false


func _on_player_levels_gained(previous_level: int, new_level: int) -> void:
	if new_level <= previous_level or not is_instance_valid(_player_level_up_effect):
		return
	# PlayerState emits once per successful experience settlement, outside its
	# level loop. The approved visual follows the actor rather than a world point.
	_player_level_up_effect.replay(player.approved_ground_footpoint_local_px())


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
	if str(request.get("contract_id", "")) != "ui.audio.setting.v1":
		return
	var setting_id := str(request.get("setting_id", ""))
	var bus_name := "Music" if setting_id == "audio.music.enabled" else "SFX"
	if setting_id not in ["audio.music.enabled", "audio.sfx.enabled"]:
		return
	var bus_index := AudioServer.get_bus_index(bus_name)
	if bus_index >= 0:
		AudioServer.set_bus_mute(bus_index, not bool(request.get("enabled", true)))


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
		hud.apply_warehouse_sort_result(PlayerState.sort_warehouse())


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
	if _pending_loot_collections.is_empty():
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
		_last_death_logout_failure = pending_result.duplicate(true)
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
	if is_instance_valid(hud) and hud.has_method("show_message"):
		hud.show_message(
			"安全退出失败：%s" % str(result.get("reason", "")),
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
	if is_instance_valid(hud) and hud.has_method("show_message"):
		hud.show_message(
			"目标位置解析失败：%s" % str(result.get("reason", "")),
			2.0
		)


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
			hud.show_message(str(rule.get("reason", "传送条件已经失效")))
		return
	var destination_map_id := int(rule.get("destination_map_id", -1))
	var travel_profile := _resolve_projection_profile_for_map(destination_map_id)
	if not bool(travel_profile.get("success", false)):
		missing_projection_rejection_count += 1
		projection_rejection_reason = str(travel_profile.get("reason", ""))
		hud.show_message("map_projection_unavailable:%d" % destination_map_id)
		return
	var map_data := GameData.get_map_by_id(destination_map_id)
	if map_data.is_empty():
		hud.show_message("地图数据不存在：%d" % destination_map_id)
		return
	var operation := Callable(self, "_teleport_to_map_immediate").bind(
		destination_map_id,
		str(rule.get("arrival_anchor_id", "")),
	)
	if not _begin_map_transition(operation, destination_map_id):
		hud.show_message("当前无法开始传送")


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
		hud.show_message("map_projection_unavailable:%d" % map_id)
		return false
	var map_data := GameData.get_map_by_id(map_id)
	if map_data.is_empty():
		hud.show_message("地图数据不存在：%d" % map_id)
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
	if str(portal.portal_data.get("portal_contract_id", "")) != MapPortalRuntimeServiceScript.PORTAL_CONTRACT_ID:
		return _request_map_travel(portal.target_map_id)
	var portal_id := str(portal.portal_data.get("source_portal_id", ""))
	var current_runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		current_runtime, portal_id
	)
	if endpoint.is_empty():
		hud.show_message("传送节点端点不存在", 1.5)
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
		hud.show_message("传送节点尚未稳定，请稍候或先离开入口", 1.5)
		return false
	var request := MapPortalRuntimeServiceScript.travel_request(endpoint)
	if not _valid_portal_request(request):
		hud.show_message("传送节点配置无效", 1.5)
		return false
	if not MapPortalTravelGuardScript.begin_travel(_portal_guard_state):
		return false
	var target_map_id := int(request.get("target_map_id", -1))
	var map_data := GameData.get_map_by_id(target_map_id)
	if map_data.is_empty():
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("地图数据不存在：%d" % target_map_id)
		return false
	var target_runtime := MapEditorRuntimeBridgeScript.load_map(target_map_id)
	var target_portal_id := str(request.get("target_portal_id", ""))
	var target_endpoint := MapPortalRuntimeServiceScript.endpoint_by_id(
		target_runtime, target_portal_id
	)
	if target_runtime.is_empty() or target_endpoint.is_empty():
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标地图或目标门点不可用", 1.5)
		return false
	if str(target_runtime.get("source", {}).get("map_id", "")) != str(request.get("target_map_key", "")):
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标地图标识不匹配", 1.5)
		return false
	var target_tile := _portal_tile(target_endpoint.get("tile", []))
	if target_tile == Vector2.INF or target_tile != _portal_tile(request.get("target_tile", [])):
		_portal_guard_state["travel_in_flight"] = false
		hud.show_message("目标门点坐标不匹配", 1.5)
		return false
	map_data = _runtime_named_map_data(map_data)
	var operation := Callable(self, "_complete_portal_travel").bind(
		target_map_id,
		map_data,
		target_runtime,
		target_portal_id,
		target_tile
	)
	if _should_animate_map_transition(false):
		if _begin_map_transition(operation, target_map_id):
			return true
		_portal_guard_state["travel_in_flight"] = false
		return false
	return bool(operation.call())


func _complete_portal_travel(
	target_map_id: int,
	map_data: Dictionary,
	target_runtime: Dictionary,
	target_portal_id: String,
	target_tile: Vector2
) -> bool:
	_load_zone(str(map_data.get("name", "未命名地图")), false, map_data)
	if current_map_id != target_map_id:
		_portal_guard_state["travel_in_flight"] = false
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
		target_tile
	)
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
	_on_player_stats_changed(player.current_hp, player.max_hp)
	_world_bootstrap_in_progress = false
	_release_gameplay_input_lock(INPUT_LOCK_INITIAL_BOOTSTRAP)


func _begin_map_transition(operation: Callable, target_map_id := -1) -> bool:
	if _map_transition_in_progress or not operation.is_valid():
		return false
	_map_transition_serial += 1
	_world_bootstrap_coordinator.begin_map_transition(target_map_id)
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.SHOW_LOADING)
	_active_map_transition_id = "map:%d:%d" % [
		Time.get_ticks_msec(),
		_map_transition_serial,
	]
	_map_transition_in_progress = true
	if is_instance_valid(_town_music_controller):
		_town_music_controller.begin_map_transition(target_map_id, _active_map_transition_id)
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
	if not PlayerState.test_mode:
		while _map_transition_in_progress and _active_map_transition_id == transition_id:
			var request: Dictionary = await hud.loading_transition_covered
			if (
				str(request.get("contract_id", "")) == LoadingTransitionOverlay.CONTRACT_ID
				and str(request.get("transition_id", "")) == transition_id
			):
				break
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	# Initial entry deliberately does not prewarm every reusable panel. That
	# work is not part of the world-ready contract and made the first Loading
	# screen wait for unrelated UI layout/action preparation. Panels remain
	# on-demand and are created only when the player opens them.
	_last_monster_prefetch_status.clear()
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
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	# HC-P1-004: stage the world build through the coordinator budget queues
	# (resource scope -> threaded prefetch -> map items -> collisions). The
	# operation below only performs zone arrival (content spawn + player
	# placement); WorldBackground.set_zone_data() skips the rebuild because the
	# environment was already staged-built for the same map.
	var built_ok := await _run_world_build_pipeline(target_map_id, transition_id)
	if not built_ok or not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	_collecting_staged_actor_plan = true
	_staged_actor_source_index = 0
	_staged_actor_spawn_failure_reason = ""
	operation.call()
	_collecting_staged_actor_plan = false
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
		_active_map_transition_id = ""
		_map_transition_in_progress = false
		_world_bootstrap_coordinator.finish(false, "actor_spawn_plan_failed")
		return
	if not PlayerState.test_mode:
		await get_tree().process_frame
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
	if not _map_transition_in_progress or _active_map_transition_id != transition_id:
		return
	_world_bootstrap_coordinator.advance(WorldBootstrapCoordinator.Stage.FINALIZE)
	if _check_world_ready_contract():
		_relocate_main_pets_after_map_arrival()
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
		hud.finish_loading_transition()
		if PlayerState.test_mode and hud.loading_transition_overlay != null:
			# Test-mode fast path hides the fade overlay immediately so tests
			# can assert the bootstrap completed without waiting the fade tween.
			hud.loading_transition_overlay.hide()
			hud.loading_transition_overlay.modulate.a = 1.0
		_active_map_transition_id = ""
		_map_transition_in_progress = false
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
		_release_gameplay_input_lock(INPUT_LOCK_MAP_TRANSITION_LOCAL)
		if not PlayerState.test_mode and hud.has_method("start_budgeted_panel_prewarm"):
			hud.start_budgeted_panel_prewarm(_system_menu_panel)
	else:
		# READY contract failed: keep the input lock and Loading overlay so the
		# player never acts on an incomplete world.
		_active_map_transition_id = ""
		_map_transition_in_progress = false
		_world_bootstrap_coordinator.finish(false, "ready_contract_failed")


func _run_world_build_pipeline(map_id: int, transition_id: String) -> bool:
	var coordinator := _world_bootstrap_coordinator
	if coordinator == null or not is_instance_valid(background):
		return false
	var generation := coordinator.generation
	if not coordinator.is_generation_current(generation):
		return false

	# 1) COLLECT_REQUIREMENTS: background registers only target-map resources
	# and builds the ordered map/collision descriptors (no SceneTree writes).
	coordinator.advance(WorldBootstrapCoordinator.Stage.COLLECT_REQUIREMENTS)
	var target_map_data: Dictionary = {}
	if map_id >= 0:
		target_map_data = GameData.get_map_by_id(map_id)
	if target_map_data.is_empty():
		target_map_data = {"mapId": map_id, "name": "未命名地图"}
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
	background.submit_staged_build()

	# 2) REQUEST_RESOURCES -> 3) WAIT_RESOURCES
	coordinator.advance(WorldBootstrapCoordinator.Stage.REQUEST_RESOURCES)
	coordinator.request_threaded_prefetch()
	coordinator.advance(WorldBootstrapCoordinator.Stage.WAIT_RESOURCES)
	if PlayerState.test_mode:
		if not coordinator.poll_threaded_prefetch_blocking():
			coordinator.finish(false, "prefetch_timeout")
			return false
	else:
		while not coordinator.poll_threaded_prefetch():
			if not coordinator.is_generation_current(generation):
				return false
			await get_tree().process_frame
	if coordinator.has_failed_required_resource():
		coordinator.finish(false, "prefetch_failed_required_resource")
		return false
	if not coordinator.is_generation_current(generation):
		return false

	# 4) BUILD_MAP: one atomic map unit per queue task, frame-budgeted.
	coordinator.advance(WorldBootstrapCoordinator.Stage.BUILD_MAP)
	var max_items := _bootstrap_max_items_per_frame()
	var budget_ms := _bootstrap_slice_budget_ms()
	coordinator.defer_between_slices = not PlayerState.test_mode
	await coordinator.process_map_queue(
		Callable(background, "build_one_map_item"), max_items, budget_ms
	)
	if not coordinator.is_generation_current(generation):
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
	if not coordinator.is_generation_current(generation):
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
	background.finish_map_build()
	return true


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
	if declares_content and get_tree().get_nodes_in_group("zone_content").is_empty():
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
	_cancel_pending_enemy_deaths_for_generation_change()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.clear_map(current_map_id)
	_active_safe_zones.clear()
	_active_enemy_cache.clear()
	_active_boss_cache.clear()
	_safe_zone_enforcement_remaining = 0.0
	_cancel_all_combat_targets()
	if _combat_spatial_index != null and current_map_id >= 0:
		# Actors are queued for deletion below; clear the old map partition now so
		# a transition cannot expose stale candidates before their exit callbacks.
		_combat_spatial_index.clear_map(current_map_id)
	# Preserve the live summon before zone_content is queued for deletion. The
	# destination map restores the same gameplay state beside the owner.
	PlayerState.apply_taoist_main_pet_runtime_states(
		_capture_taoist_main_pet_runtime_states()
	)
	for node: Node in get_tree().get_nodes_in_group("zone_content"):
		if is_instance_valid(node):
			node.queue_free()
	if _ground_effect_manager != null:
		# Every zone_content node (including ground effect visuals) is freed
		# above; their manager registrations must not survive into the next map.
		_ground_effect_manager.clear_all()
	current_zone = zone_name
	current_map_data = map_data.duplicate(true)
	current_map_id = int(map_data.get("mapId", -1)) if not map_data.is_empty() else -1
	if map_data.is_empty():
		# Q1-B: legacy zones without a database map entry (for example the
		# outskirts playground) belong to the client 0.map home realm (runtime
		# map 4). Snapshot consumers receive a formal runtime map id instead of
		# -1, so STRICT_V2 absolute snapshots stay valid.
		current_map_id = GameData.service_runtime_map_id(0)
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
			"books": stock = _build_skill_book_stock(PlayerState.profession)
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
			"books": stock = _build_skill_book_stock(PlayerState.profession)
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
	var padding_gu: float = (
		float(enemy.combat_radius_gu) + SAFE_ZONE_ACTOR_PADDING_GU
	)
	var legal_ground_gu := (
		WorldSpatialRulesScript.project_outside_safe_zones_ground_gu(
			current_ground_gu,
			_active_safe_zones,
			padding_gu
		)
	)
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
	var book_stock := _build_skill_book_stock(PlayerState.profession)
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
	var source_index := _staged_actor_source_index
	_staged_actor_source_index += 1
	var actor_id := stable_actor_id
	if actor_id.is_empty():
		actor_id = "%s:%d:%06d" % [actor_type, current_map_id, source_index]
	return _world_bootstrap_coordinator.submit_actor_descriptor({
		"actor_id": actor_id,
		"actor_type": actor_type,
		"source_index": source_index,
		"payload": payload,
	})


func _spawn_staged_actor_descriptor(descriptor: Dictionary) -> Dictionary:
	var actor_type := str(descriptor.get("actor_type", ""))
	var payload: Dictionary = descriptor.get("payload", {})
	match actor_type:
		"enemy":
			var monster_id := int(payload.get("monster_id", -1))
			var monster := GameData.get_monster_by_id(monster_id)
			if monster.is_empty():
				return {"ok": false, "reason": "missing_monster"}
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
	if _collecting_staged_actor_plan:
		var monster_id_for_plan := _strict_runtime_monster_id(monster_data)
		var slot_id_for_plan := str(spawn_context.get(
			"spawn_slot_id",
			spawn_context.get("spawn_group_id", "")
		))
		_submit_staged_actor_descriptor(
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
		return null
	var monster_id := _strict_runtime_monster_id(monster_data)
	var canonical_monster := GameData.get_monster_by_id(monster_id)
	if canonical_monster.is_empty():
		_staged_actor_spawn_failure_reason = "missing_canonical_monster"
		return null
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
	_runtime_spawn_serial += 1
	var context := spawn_context.duplicate(true)
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
	var classification := str(canonical_monster.get("classification", ""))
	var spawn_classification := str(
		canonical_monster.get("spawn_classification", "")
	)
	var policy: Dictionary = {}
	var effective_respawn := maxf(0.0, float(respawn_seconds))
	if respawn_enabled:
		policy = MonsterRespawnPolicyScript.resolve(
			str(context.get("respawn_policy_id", "")),
			classification,
			float(respawn_seconds),
			spawn_classification
		)
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
	enemy.setup(monster_data, player, is_boss)
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
	enemy.target_requested.connect(_on_enemy_target_requested)
	enemy.summon_requested.connect(_on_boss_summon_requested)
	enemy.relocation_requested.connect(_on_boss_relocation_requested)
	enemy.fixed_area_ground_spike_requested.connect(
		_on_enemy_fixed_area_ground_spike_requested.bind(enemy)
	)
	add_child(enemy)
	var enemy_instance_id := enemy.get_instance_id()
	_active_enemy_cache[enemy_instance_id] = enemy
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
	return enemy


func _on_cached_enemy_tree_exiting(enemy_instance_id: int) -> void:
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
	_activate_physical_attack_domain()
	var target := _ensure_attack_locked_target()
	var facing_before := player.facing
	var touch_before := player.touch_vector
	var movement_was_active := player.movement_input_active
	if not player.can_start_attack():
		return false
	var attack_direction := player.facing.normalized()
	if is_instance_valid(target):
		attack_direction = _face_locked_target()
	var melee_mode := _selected_warrior_melee_mode()
	var target_instance_id := target.get_instance_id() if is_instance_valid(target) else 0
	var input_release_geometry := CombatReleaseGeometryScript.resolve(
		player.global_position,
		attack_direction,
		target_instance_id,
		target.global_position if is_instance_valid(target) else Vector2.ZERO,
		is_instance_valid(target),
		true,
		CombatReleaseGeometryScript.FACING_POLICY_LOCKED_INPUT_EIGHT_DIRECTION,
		target.combat_radius_gu if is_instance_valid(target) else 0.0
	)
	attack_direction = Vector2(
		input_release_geometry.get("direction_screen_px", attack_direction)
	).normalized()
	var input_has_hittable_target := _has_melee_hittable_target(
		attack_direction,
		melee_mode,
		input_release_geometry
	)
	var diagnostics_enabled := CombatDiagnosticLogScript.capture_enabled()
	var diagnostic: Dictionary = {}
	if diagnostics_enabled:
		diagnostic = _build_melee_input_diagnostic(
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
	var accepted := player.request_attack_toward(
		attack_direction,
		input_has_hittable_target,
		target_instance_id
	)
	if accepted and diagnostics_enabled:
		diagnostic["event"] = "attack_input_accepted"
		diagnostic["facing_after_input"] = player.facing
		diagnostic["facing_after_input_index"] = ArtSpec.direction_index(player.facing)
		_pending_melee_diagnostic = diagnostic.duplicate(true)
		CombatDiagnosticLogScript.record(diagnostic)
	elif not accepted and diagnostics_enabled:
		diagnostic["event"] = "attack_input_rejected"
		diagnostic["reject_code"] = "PLAYER_REQUEST_REJECTED"
		CombatDiagnosticLogScript.record(diagnostic)
	return accepted


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
	var bound_skill := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	if bound_skill.is_empty():
		_request_mobile_attack()
		return
	_use_skill_slot(PlayerState.SKILL_SLOT_GROUP_ATTACK, 0)


func _selected_warrior_melee_mode() -> String:
	if player.fire_sword_enabled:
		return WarriorMeleeGeometryScript.SKILL_FIRE
	if player.half_moon_enabled and PlayerState.is_skill_learned("warrior.half_moon"):
		return WarriorMeleeGeometryScript.SKILL_HALF_MOON
	if player.thrusting_enabled and PlayerState.is_skill_learned("warrior.thrusting"):
		return WarriorMeleeGeometryScript.SKILL_THRUST
	return WarriorMeleeGeometryScript.SKILL_NORMAL


func _has_melee_hittable_target(
	direction: Vector2,
	mode := "",
	release_geometry: Dictionary = {}
) -> bool:
	if direction.length_squared() <= 0.01:
		return false
	var resolved_mode := mode if not mode.is_empty() else _selected_warrior_melee_mode()
	var release_origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var melee_release_cache: Dictionary = {}
	var melee_query_plan := _aoe_melee_query_plan(
		resolved_mode,
		release_origin_ground_gu,
		direction.normalized(),
		release_geometry,
		{},
		release_geometry.get("skill_footprint_snapshot", {}),
		release_geometry.get("target_aligned_plan", {}),
		melee_release_cache,
	)
	var primary_targets := _physical_primary_targets(
		player.global_position,
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
			player.global_position,
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
			player.global_position,
			direction.normalized(),
			primary_targets,
			release_geometry,
		release_geometry.get("skill_footprint_snapshot", {}),
		melee_query_plan,
		).is_empty()
	return false


func _allocate_synthetic_attack_token() -> int:
	var token := _next_synthetic_attack_token
	_next_synthetic_attack_token -= 1
	return token


func _submit_mobile_attack_ticket(press_token: int) -> void:
	if press_token == 0 or press_token in _queued_mobile_attack_tickets:
		return
	if _queued_mobile_attack_tickets.is_empty() and _request_mobile_attack():
		return
	if _queued_mobile_attack_tickets.size() >= MAX_BUFFERED_MOBILE_ATTACK_TICKETS:
		return
	_queued_mobile_attack_tickets.append(press_token)


func _drain_next_mobile_attack_ticket() -> bool:
	if _queued_mobile_attack_tickets.is_empty():
		return false
	if not _request_mobile_attack():
		return false
	_queued_mobile_attack_tickets.pop_front()
	return true


func _refresh_mobile_attack_held() -> void:
	_mobile_attack_held = false
	for value in _active_mobile_attack_tokens.values():
		if bool(value):
			_mobile_attack_held = true
			return


func _on_mobile_attack_input_started(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not gameplay_input_is_enabled(): return
	if press_token == 0 or _active_mobile_attack_tokens.has(press_token):
		return
	var ordinary_attack := PlayerState.skill_name_for_slot(
		PlayerState.SKILL_SLOT_GROUP_ATTACK,
		0
	).is_empty()
	if not ordinary_attack:
		_on_skill_input_started(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source
		)
		return
	_active_mobile_attack_tokens[press_token] = true
	_refresh_mobile_attack_held()
	if ordinary_attack:
		_submit_mobile_attack_ticket(press_token)
		return
	_queued_mobile_attack_tickets.clear()
	_request_primary_attack_action()


func _on_mobile_attack_input_ended(
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_ended(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source
		)
		return
	_active_mobile_attack_tokens.erase(press_token)
	_refresh_mobile_attack_held()


func _on_mobile_attack_input_cancelled(
	press_token: int,
	touch_id: int,
	source: StringName,
	reason: StringName
) -> void:
	if not _active_mobile_attack_tokens.has(press_token):
		_on_skill_input_cancelled(
			PlayerState.SKILL_SLOT_GROUP_ATTACK,
			0,
			press_token,
			touch_id,
			source,
			reason
		)
		return
	_active_mobile_attack_tokens.erase(press_token)
	_queued_mobile_attack_tickets.erase(press_token)
	_refresh_mobile_attack_held()


func _cancel_all_mobile_attack_inputs(clear_tickets := false) -> void:
	_active_mobile_attack_tokens.clear()
	_mobile_attack_held = false
	_legacy_mobile_attack_token = 0
	if clear_tickets:
		_queued_mobile_attack_tickets.clear()


func _skill_input_key(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int
) -> String:
	return "%s:%d:%d:%d" % [slot_group, slot_index, press_token, touch_id]


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	if not gameplay_input_is_enabled(): return
	if press_token == 0:
		return
	var input_key := _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	if _active_skill_inputs.has(input_key):
		return
	var skill_name := PlayerState.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		hud.show_message("技能栏为空")
		return
	var metadata := SkillInputPolicyScript.metadata(skill_name)
	if metadata.is_empty() or bool(metadata.get("passive", false)):
		return
	_activate_magic_skill_domain()
	var entry := {
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
		"started_at_ms": Time.get_ticks_msec(),
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
	var input_key := _skill_input_key(
		slot_group, slot_index, press_token, touch_id
	)
	_active_skill_inputs.erase(input_key)


func _cancel_all_skill_inputs(clear_tickets := false) -> void:
	_active_skill_inputs.clear()
	_keyboard_bound_skill_token = 0
	# Kept as an API-compatible argument for callers that clear attack and skill
	# input together. Skill clicks are no longer buffered past their physical
	# lifetime, so there are no deferred skill tickets to clear.
	if clear_tickets:
		_skill_input_retry_remaining = 0.0


func _submit_skill_input_ticket(entry: Dictionary) -> void:
	# One physical DOWN makes exactly one immediate attempt. A busy cast gate
	# coalesces all additional taps during that interval instead of storing them
	# for forced release later. Continuous casting is owned exclusively by the
	# still-active press in _process_skill_input_actions().
	_try_release_skill(str(entry.get("skill_name", "")), true)


func _process_skill_input_actions(delta: float) -> void:
	_skill_input_retry_remaining = maxf(
		0.0, _skill_input_retry_remaining - delta
	)
	if _skill_input_retry_remaining > 0.0:
		return
	_skill_input_retry_remaining = 0.05
	var repeat_entry: Dictionary = {}
	var now_ms := Time.get_ticks_msec()
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
		_try_release_skill(str(repeat_entry.get("skill_name", "")), false)


func _handle_toggle_skill_input(skill_name: String) -> void:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if stable_skill_id != "wizard.magic_shield":
		_try_release_skill(skill_name, true)
		return
	_magic_shield_auto_enabled = not _magic_shield_auto_enabled
	if not _magic_shield_auto_enabled:
		hud.show_message("魔法盾自动补盾：关", 1.5)
		return
	hud.show_message("魔法盾自动补盾：开", 1.5)
	_magic_shield_auto_retry_remaining = 0.0
	_process_magic_shield_auto_refresh(
		MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	)


func _process_magic_shield_auto_refresh(delta: float) -> void:
	if not _magic_shield_auto_enabled or not is_instance_valid(player):
		return
	_magic_shield_auto_retry_remaining = maxf(
		0.0, _magic_shield_auto_retry_remaining - delta
	)
	if _magic_shield_auto_retry_remaining > 0.0:
		return
	_magic_shield_auto_retry_remaining = MAGIC_SHIELD_AUTO_REFRESH_CHECK_SECONDS
	if not player.magic_shield_requires_refresh(
		PlayerCharacter.MAGIC_SHIELD_AUTO_REFRESH_RATIO,
		MAGIC_SHIELD_AUTO_REFRESH_EXPIRY_LEAD_SECONDS
	):
		return
	_try_release_skill(
		SkillDataLoaderScript.display_name("wizard.magic_shield"),
		false
	)


func _on_mobile_attack_pressed() -> void:
	if not gameplay_input_is_enabled(): return
	if _legacy_mobile_attack_token != 0:
		return
	_legacy_mobile_attack_token = _allocate_synthetic_attack_token()
	_on_mobile_attack_input_started(
		_legacy_mobile_attack_token,
		-3,
		&"legacy"
	)


func _on_mobile_attack_released() -> void:
	if _legacy_mobile_attack_token == 0:
		_cancel_all_mobile_attack_inputs(false)
		return
	var press_token := _legacy_mobile_attack_token
	_legacy_mobile_attack_token = 0
	_on_mobile_attack_input_ended(press_token, -3, &"legacy")


func _ensure_attack_locked_target(excluded: EnemyActor = null) -> EnemyActor:
	if not is_instance_valid(locked_target):
		locked_target = null
		manual_target_lock = false
	if _is_attack_target_in_range(locked_target) and locked_target != excluded:
		return locked_target
	if locked_target != null:
		_cancel_target()
	if not auto_target_enabled:
		return null
	var candidates := _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _ensure_combat_target(
	excluded: EnemyActor = null,
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU
) -> EnemyActor:
	return _ensure_attack_locked_target(excluded)


func _refresh_auto_target(
	_maximum_range_gu := ATTACK_LOCK_RANGE_GU,
	excluded: EnemyActor = null
) -> EnemyActor:
	var candidates := _attack_lock_candidates(excluded)
	_set_attack_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	return locked_target


func _set_attack_locked_target(target: EnemyActor, manual := false) -> void:
	if target != null and not _is_attack_target_in_range(target):
		target = null
	locked_target = target
	manual_target_lock = manual and is_instance_valid(target)
	_refresh_target_highlights()
	_update_target_hud()


func _set_locked_target(target: EnemyActor, manual := false) -> void:
	_set_attack_locked_target(target, manual)


func _attack_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var ranked: Array[Dictionary] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
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
	for enemy: EnemyActor in _target_spatial_query_scratch:
		if enemy == excluded or not _is_attack_target_in_range(enemy):
			continue
		var target_ground_gu := _canonical_screen_px_to_ground_gu(
			enemy.global_position
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
			"instance_id": enemy.get_instance_id(),
		})
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_distance_squared_gu := float(
			a.get("distance_squared_gu", INF)
		)
		var b_distance_squared_gu := float(
			b.get("distance_squared_gu", INF)
		)
		if not is_equal_approx(a_distance_squared_gu, b_distance_squared_gu):
			return a_distance_squared_gu < b_distance_squared_gu
		return int(a.get("instance_id", 0)) < int(b.get("instance_id", 0))
	)
	var result: Array[EnemyActor] = []
	for entry: Dictionary in ranked:
		result.append(entry.get("target") as EnemyActor)
	return result


func _uses_magic_lock_domain() -> bool:
	return ProfessionRules.profession_id(PlayerState.profession) in [
		"wizard",
		"taoist",
	]


func _magic_target_domain_is_active() -> bool:
	return _uses_magic_lock_domain() and _active_target_domain_magic


func _set_active_target_domain_magic(active: bool) -> void:
	_active_target_domain_magic = active
	_refresh_target_highlights()
	_update_target_hud()


func _activate_physical_attack_domain() -> void:
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
	return _canonical_screen_px_to_ground_gu(screen_position_px)


func _spell_lock_distance_gu(target: EnemyActor) -> float:
	if not is_instance_valid(target):
		return SpellTargetLockPolicyScript.LOCK_RANGE_GU + 1.0
	return SpellTargetLockPolicyScript.distance_gu(
		_spell_lock_ground_gu(player.global_position),
		_spell_lock_ground_gu(target.global_position)
	)


func _is_magic_target_in_range(target: EnemyActor) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.current_hp > 0
		and SpellTargetLockPolicyScript.is_within_lock_range(
			_spell_lock_ground_gu(player.global_position),
			_spell_lock_ground_gu(target.global_position)
		)
	)


func _spell_lock_candidates(excluded: EnemyActor = null) -> Array[EnemyActor]:
	var raw_candidates: Array[Dictionary] = []
	var origin_ground_gu := _spell_lock_ground_gu(player.global_position)
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
	for enemy: EnemyActor in _target_spatial_query_scratch:
		if enemy == excluded or not _is_magic_target_in_range(enemy):
			continue
		raw_candidates.append({
			"target": enemy,
			"origin_ground_gu": origin_ground_gu,
			"target_ground_gu": _spell_lock_ground_gu(enemy.global_position),
			"instance_id": enemy.get_instance_id(),
		})
	var result: Array[EnemyActor] = []
	for ranked: Dictionary in SpellTargetLockPolicyScript.ordered_candidates(
		raw_candidates
	):
		result.append(ranked.get("target") as EnemyActor)
	return result


func _set_magic_locked_target(target: EnemyActor, manual := false) -> void:
	if target != null and not _is_magic_target_in_range(target):
		target = null
	magic_locked_target = target
	manual_magic_target_lock = manual and is_instance_valid(target)
	_refresh_target_highlights()
	_update_target_hud()


func _active_display_target() -> EnemyActor:
	return magic_locked_target if _magic_target_domain_is_active() else locked_target


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
	if not is_instance_valid(target):
		return ATTACK_LOCK_RANGE_GU + 1.0
	return GroundUnitSpaceScript.distance_gu(
		_canonical_screen_px_to_ground_gu(player.global_position),
		_canonical_screen_px_to_ground_gu(target.global_position)
	)


func _is_attack_target_in_range(target: EnemyActor) -> bool:
	return (
		is_instance_valid(target)
		and not target.is_queued_for_deletion()
		and target.current_hp > 0
		and _attack_lock_distance_gu(target)
		<= ATTACK_LOCK_RANGE_GU + GroundUnitSpaceScript.EPSILON_GU
	)


func _on_enemy_target_requested(enemy: EnemyActor) -> void:
	var magic_domain_active := _magic_target_domain_is_active()
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
	if int(enemy.get_meta("zone_generation", -1)) != _zone_generation:
		return
	var owner_slot := str(enemy.get_meta("spawn_slot_id", ""))
	var active := 0
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and not value.is_queued_for_deletion():
			if str(value.get_meta("summoner_spawn_slot", "")) == owner_slot:
				active += 1
	var allowed := mini(maxi(0, count), maxi(0, max_active - active))
	for index in range(allowed):
		var monster_id := GameData.canonical_monster_id(
			monster_ids[index % monster_ids.size()]
		)
		if monster_id <= 0:
			continue
		var monster := GameData.get_monster_by_id(monster_id)
		if monster.is_empty():
			continue
		var landing := _find_valid_enemy_landing(
			enemy.global_position,
			1.5,
			6.0,
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.MONSTER_COLLISION_RADIUS_PX
			),
			null
		)
		if landing == enemy.global_position:
			continue
		_spawn_enemy(
			monster,
			landing,
			false,
			DEFAULT_NORMAL_RESPAWN_SECONDS,
			{
				"spawn_group_id": "%s:summons" % owner_slot,
				"respawn_enabled": false,
				"summoner_spawn_slot": owner_slot,
				"summon_monster_id": monster_id,
			}
		)


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
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		origin_screen_px
	)
	var footprint_radius_px := (
		WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
			combat_radius_gu
		)
	)
	for _attempt in range(96):
		var candidate_ground_gu := (
			origin_ground_gu
			+ Vector2.from_angle(_rng.randf_range(0.0, TAU))
			* _rng.randf_range(minimum_distance_gu, maximum_distance_gu)
		)
		if WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			candidate_ground_gu,
			_active_safe_zones
		):
			continue
		var candidate_screen_px := _canonical_ground_gu_to_screen_px(
			candidate_ground_gu
		)
		if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			candidate_screen_px,
			footprint_radius_px
		):
			continue
		var player_combat_radius_gu := (
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
		)
		if (
			is_instance_valid(player)
			and GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(player.global_position),
				candidate_ground_gu
			)
			< combat_radius_gu
			+ player_combat_radius_gu
			+ ACTOR_LANDING_CLEARANCE_GU
		):
			continue
		var occupied := false
		for value: Variant in get_tree().get_nodes_in_group("enemies"):
			if not value is EnemyActor or value == ignored_enemy or value.is_queued_for_deletion():
				continue
			var other := value as EnemyActor
			if GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(other.global_position),
				candidate_ground_gu
			) < combat_radius_gu + other.combat_radius_gu + ENEMY_LANDING_CLEARANCE_GU:
				occupied = true
				break
		if not occupied:
			return candidate_screen_px
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
		hud.show_message(
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


func _on_player_death_requested() -> void:
	if not gameplay_input_is_enabled():
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


func _on_revival_requested(request: Dictionary) -> void:
	if _active_death_id.is_empty() or _death_revival_request_in_flight:
		return
	if str(request.get("contract_id", "")) != DEATH_REVIVAL_CONTRACT_ID:
		return
	if str(request.get("death_id", "")) != _active_death_id:
		return
	if (
		str(request.get("option_slot", "")) != "town"
		or str(request.get("method_id", "")) != "revive.nearest_town"
	):
		return
	_death_revival_request_in_flight = true
	var accepted := travel_to_service_home(
		false,
		false,
		"比奇省",
		Callable(self, "_finish_death_revival")
	)
	if accepted:
		return
	_death_revival_request_in_flight = false
	if is_instance_valid(hud):
		hud.apply_revival_result({
			"success": false,
			"message": "复活位置暂不可用",
			"revival_options": _death_revival_context().get("revival_options", []),
		})


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
	locked_target = null
	manual_target_lock = false
	_refresh_target_highlights()
	_update_target_hud()


func _cancel_magic_target() -> void:
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_refresh_target_highlights()
	_update_target_hud()


func _cancel_all_combat_targets() -> void:
	locked_target = null
	manual_target_lock = false
	magic_locked_target = null
	manual_magic_target_lock = false
	_skill_cast_target = null
	_refresh_target_highlights()
	_update_target_hud()


func _validate_locked_target() -> void:
	if not is_instance_valid(locked_target):
		locked_target = null
		manual_target_lock = false
	elif not _is_attack_target_in_range(locked_target):
		_cancel_target()
	if not is_instance_valid(magic_locked_target):
		magic_locked_target = null
		manual_magic_target_lock = false
	elif not _is_magic_target_in_range(magic_locked_target):
		_cancel_magic_target()


func _face_locked_target() -> Vector2:
	if not _is_attack_target_in_range(locked_target):
		return player.facing.normalized()
	var direction_resolution := CombatDirectionSpaceScript.resolve_screen_delta_px(
		locked_target.global_position - player.global_position
	)
	var direction := Vector2(
		direction_resolution.get("projected_screen_direction_px", player.facing)
	).normalized()
	if direction.length_squared() > 0.01:
		player.set_combat_facing(direction)
	return direction


func _ensure_skill_cast_target(excluded: EnemyActor = null) -> EnemyActor:
	_activate_magic_skill_domain()
	if not is_instance_valid(magic_locked_target):
		magic_locked_target = null
		manual_magic_target_lock = false
	if not is_instance_valid(_skill_cast_target):
		_skill_cast_target = null
	if _is_magic_target_in_range(magic_locked_target) and magic_locked_target != excluded:
		_skill_cast_target = magic_locked_target
		return _skill_cast_target
	if magic_locked_target != null:
		_cancel_magic_target()
	if not auto_target_enabled:
		_skill_cast_target = null
		return null
	var candidates := _spell_lock_candidates(excluded)
	_set_magic_locked_target(
		candidates[0] if not candidates.is_empty() else null,
		false
	)
	_skill_cast_target = magic_locked_target
	return _skill_cast_target


func _face_skill_cast_target() -> Vector2:
	if not _is_magic_target_in_range(_skill_cast_target):
		return player.facing.normalized()
	var direction_screen_px := player.global_position.direction_to(
		_skill_cast_target.global_position
	)
	if direction_screen_px.length_squared() > 0.01:
		direction_screen_px = CombatRuntime.face_target_screen_px(
			player,
			_skill_cast_target
		)
	return direction_screen_px


func _select_wild_rush_target() -> EnemyActor:
	if not is_instance_valid(locked_target):
		locked_target = null
		manual_target_lock = false
	if _is_attack_target_in_range(locked_target):
		# A live lock is authoritative. An ineligible, over-level, boss, or
		# out-of-reach lock must make this cast invalid instead of silently
		# redirecting the charge to a different nearby monster.
		return locked_target if _wild_rush_target_is_eligible(locked_target) else null
	var player_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
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
	var best: EnemyActor
	var best_distance_gu := INF
	for enemy: EnemyActor in _target_spatial_query_scratch:
		if not _wild_rush_target_is_eligible(enemy):
			continue
		var enemy_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		var distance_gu := GroundUnitSpaceScript.distance_gu(
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


func _wild_rush_target_is_eligible(target: EnemyActor) -> bool:
	if (
		not is_instance_valid(target)
		or target.is_queued_for_deletion()
		or target.current_hp <= 0
		or target.is_boss
		or bool(target.get_meta("immovable", false))
		or int(target.monster_data.get("level", target.level)) >= PlayerState.level
	):
		return false
	if (
		_player_inside_active_safe_zone()
		or WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(
			_canonical_screen_px_to_ground_gu(target.global_position),
			_active_safe_zones
		)
	):
		return false
	return WarriorMeleeGeometryScript.wild_rush_target_is_adjacent(
		_canonical_screen_px_to_ground_gu(player.global_position),
		_canonical_screen_px_to_ground_gu(target.global_position)
	)


func _build_wild_rush_path_plan(target: EnemyActor, release_id := "") -> Dictionary:
	var result := {
		"contract_id": WarriorMeleeGeometryScript.WILD_RUSH_CONTRACT_ID,
		"unit_contract_id": GroundUnitSpaceScript.CONTRACT_ID,
		"eligible": false,
		"dynamic_blocker_in_corridor": false,
		"static_clear_distance_gu": 0.0,
		"resolved_push_distance_gu": 0.0,
	}
	if not _wild_rush_target_is_eligible(target):
		return result
	var player_ground_gu := _canonical_screen_px_to_ground_gu(player.global_position)
	var target_ground_gu := _canonical_screen_px_to_ground_gu(target.global_position)
	var direction_ground_gu := WarriorMeleeGeometryScript.wild_rush_direction_ground_gu(
		player_ground_gu,
		target_ground_gu
	)
	var direction_index := WarriorMeleeGeometryScript.direction_index_for_ground_delta_gu(
		direction_ground_gu
	)
	var direction_step := WarriorMeleeGeometryScript.facing_tile_step(direction_index)
	var dynamic_blocked := _wild_rush_has_dynamic_blocker(
		target,
		target_ground_gu,
		direction_ground_gu
	)
	var static_clear_distance_gu := _wild_rush_static_clear_distance_gu(
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
	var resolved_release_id := str(release_id)
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
	target: EnemyActor,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> bool:
	var forward_ground_gu := direction_ground_gu.normalized()
	var side_ground_gu := Vector2(-forward_ground_gu.y, forward_ground_gu.x)
	var target_radius_gu := target.combat_radius_gu
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
	):
		return false
	for other: EnemyActor in _target_spatial_query_scratch:
		if other == target:
			continue
		if other.is_queued_for_deletion() or other.current_hp <= 0:
			continue
		var delta_ground_gu := (
			_canonical_screen_px_to_ground_gu(other.global_position)
			- target_ground_gu
		)
		var forward_distance_gu := delta_ground_gu.dot(forward_ground_gu)
		var lateral_distance_gu := absf(delta_ground_gu.dot(side_ground_gu))
		var other_radius_gu := other.combat_radius_gu
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
	target: EnemyActor,
	player_ground_gu: Vector2,
	target_ground_gu: Vector2,
	direction_ground_gu: Vector2
) -> float:
	const SAMPLE_STEP_GU := 0.25
	var maximum_distance_gu := WarriorMeleeGeometryScript.WILD_RUSH_PUSH_DISTANCE_GU
	var sample_count := ceili(maximum_distance_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu := 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu := minf(
			float(sample_index) * SAMPLE_STEP_GU,
			maximum_distance_gu
		)
		var motion_ground_gu := direction_ground_gu * distance_gu
		var player_destination := _canonical_ground_gu_to_screen_px(
			player_ground_gu + motion_ground_gu
		)
		var target_destination := _canonical_ground_gu_to_screen_px(
			target_ground_gu + motion_ground_gu
		)
		if (
			WorldSpatialRulesScript.environment_blocks_actor_screen_px(
				background,
				player_destination,
				ArtSpec.PLAYER_COLLISION_RADIUS_PX
			)
			or WorldSpatialRulesScript.environment_blocks_actor_screen_px(
				background,
				target_destination,
				target.collision_radius_px
			)
		):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _apply_wild_rush_displacement(
	target: EnemyActor,
	effect: Dictionary,
	target_context: Dictionary
) -> bool:
	var distance_gu := clampf(
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
	var motion_ground_gu := direction_ground_gu.normalized() * distance_gu
	var rush_snapshot: Dictionary = target_context.get(
		"skill_footprint_snapshot", {}
	)
	var player_origin_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
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
	var player_destination := _canonical_ground_gu_to_screen_px(
		player_origin_ground_gu
		+ motion_ground_gu
	)
	var target_destination := _canonical_ground_gu_to_screen_px(
		_canonical_screen_px_to_ground_gu(target.global_position)
		+ motion_ground_gu
	)
	if (
		WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			player_destination,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
		or WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			target_destination,
			target.collision_radius_px
		)
	):
		return false
	# Both destinations were preflighted before either actor is mutated. This is
	# one coupled transaction: partial single-actor movement is forbidden.
	target.set_combat_position(target_destination, &"wild_rush_displacement")
	_set_player_world_position(player_destination)
	player.velocity = Vector2.ZERO
	player.movement_performed.emit(player.global_position, player.facing)
	return true


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
			auto_target_enabled
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
		hud.show_message("附近没有可交互目标")
		return
	nearest.interact(self)


func _use_quick_slot(index: int) -> void:
	if not gameplay_input_is_enabled(): return
	_use_skill_slot(PlayerState.SKILL_SLOT_GROUP_ATTACK_RING, index)


func _use_skill_slot(slot_group: String, slot_index: int) -> void:
	if not gameplay_input_is_enabled(): return
	var skill_name := PlayerState.skill_name_for_slot(slot_group, slot_index)
	if skill_name.is_empty():
		var group_label := (
			"攻击键"
			if slot_group == PlayerState.SKILL_SLOT_GROUP_ATTACK
			else "攻击环%d" % (slot_index + 1)
		)
		hud.show_message("%s为空" % group_label)
		return
	var metadata := SkillInputPolicyScript.metadata(skill_name)
	if bool(metadata.get("toggle", false)):
		_handle_toggle_skill_input(skill_name)
		return
	_try_release_skill(skill_name, true)


func _try_release_skill(skill_name: String, show_failure := true) -> StringName:
	if skill_name.is_empty() or not PlayerState.is_skill_learned(skill_name):
		if show_failure:
			hud.show_message("技能尚未学习")
		return &"rejected"
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	if definition.is_empty():
		return &"rejected"
	if not SkillVisibilityPolicyScript.is_skill_castable(stable_skill_id):
		if show_failure:
			hud.show_message("该技能已隐藏，无法使用")
		return &"rejected"
	_activate_magic_skill_domain()
	var input_metadata := SkillInputPolicyScript.metadata(stable_skill_id)
	if (
		PlayerState.profession == "战士"
		and stable_skill_id.begins_with("warrior.")
		and bool(input_metadata.get("toggle", false))
	):
		# Warrior toggles only configure the next melee mode. They do not cast,
		# spend MP, select a target, or commit cooldown/action state here. Keep
		# Player.request_skill as the authority for dead/control/struck locks.
		if not player.request_skill(skill_name):
			if show_failure:
				hud.show_message("技能动作或冷却尚未结束")
			return &"busy"
		_skill_cast_target = null
		return &"accepted"
	if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
		## Friendly healing is selected by the pure support policy BEFORE any
		## action/cooldown/MP commit. Full-HP friendlies remain valid targets
		## (user override 2026-08-09); only an empty/in-range-less pool rejects.
		var heal_selection := _select_taoist_heal_target(
			_canonical_screen_px_to_ground_gu(player.global_position)
		)
		if not bool(heal_selection.get("valid", false)):
			if show_failure:
				hud.show_message("附近没有可治疗的友方")
			_skill_cast_target = null
			_selected_friendly_instance_id = 0
			return &"rejected"
		_selected_friendly_instance_id = int(
			heal_selection.get("selected", {}).get("instance_id", 0)
		)
	var learned_level := PlayerState.effective_skill_level(skill_name)
	var profile := ProfessionRules.skill_combat_profile(skill_name, learned_level)
	var resource_context := _canonical_resource_context(stable_skill_id)
	var resource_quote := SkillResourceServiceScript.quote(
		definition,
		learned_level,
		resource_context,
		resource_context
	)
	var mana_cost := maxi(0, int(resource_quote.get("mp_cost", 0)))
	if player.current_mp < mana_cost:
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			_selected_friendly_instance_id = 0
		if show_failure:
			hud.show_message("魔法不足")
		return &"rejected"
	if not player.can_request_skill(skill_name):
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			_selected_friendly_instance_id = 0
		if show_failure:
			hud.show_message("技能动作或冷却尚未结束")
		return &"busy"
	_skill_cast_target = null
	if stable_skill_id == WILD_RUSH_SKILL_ID:
		_skill_cast_target = _select_wild_rush_target()
		if _skill_cast_target == null:
			if show_failure:
				hud.show_message("附近没有可冲撞的低级普通怪物")
			return &"rejected"
		_face_skill_cast_target()
	elif _skill_needs_target(str(profile.get("cast_type", "melee"))):
		_ensure_skill_cast_target(null)
		_face_skill_cast_target()
	if _definition_requires_hostile_target(definition):
		if not is_instance_valid(_skill_cast_target):
			if show_failure:
				hud.show_message("法术需要有效目标")
			return &"rejected"
		if not _spell_definition_allows_target(definition, _skill_cast_target):
			if show_failure:
				hud.show_message("目标超出该法术的有效范围")
			return &"rejected"
	var locked_skill_target_id := 0
	if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
		locked_skill_target_id = _selected_friendly_instance_id
		_skill_cast_target = null
	else:
		locked_skill_target_id = (
			_skill_cast_target.get_instance_id()
			if is_instance_valid(_skill_cast_target)
			else 0
		)
	if not player.request_skill(skill_name, locked_skill_target_id):
		_selected_friendly_instance_id = 0
		if show_failure:
			hud.show_message("技能动作或冷却尚未结束")
		return &"busy"
	if stable_skill_id.begins_with("warrior."):
		_skill_cast_target = null
	return &"accepted"


func _definition_requires_hostile_target(definition: Dictionary) -> bool:
	if str(definition.get("skill_id", "")) == FIRE_WALL_SKILL_ID:
		return true
	var target: Dictionary = definition.get("target", {})
	var relation := str(target.get("relation", ""))
	if not relation.contains("hostile"):
		return false
	var mode := str(target.get("mode", ""))
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


func _spell_definition_allows_target(
	definition: Dictionary,
	target: EnemyActor
) -> bool:
	if not _is_magic_target_in_range(target):
		return false
	var target_contract: Dictionary = definition.get("target", {})
	if not str(target_contract.get("relation", "")).contains("hostile"):
		return true
	var geometry: Dictionary = definition.get("geometry", {})
	if str(geometry.get("shape", "")) != "projectile":
		return true
	var maximum_range_gu := float(geometry.get("maximum_range_gu", 0.0))
	if maximum_range_gu <= 0.0:
		return true
	return (
		_spell_lock_distance_gu(target)
		<= maximum_range_gu + GroundUnitSpaceScript.EPSILON_GU
	)


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
	item_name: String
) -> void:
	var result := PlayerState.assign_quick_item_slot(slot_index, item_name)
	if not bool(result.get("ok", false)):
		_sync_item_quick_slots_to_hud()
		hud.show_message(str(result.get("message", "快捷物品绑定失败")))
		return
	_sync_item_quick_slots_to_hud()
	hud.show_message(str(result.get("message", "快捷物品已绑定")))


func _on_item_quick_slot_use_requested(
	slot_index: int,
	item_name: String
) -> void:
	if not gameplay_input_is_enabled():
		return
	var result := PlayerState.use_quick_item_slot(slot_index, item_name)
	if not bool(result.get("ok", false)):
		hud.show_message(str(result.get("message", "快捷物品使用失败")))
		return
	# consumable/scroll effects are already surfaced by their existing signal
	# chain; only skill_book needs an immediate visible confirmation.
	if str(result.get("kind", "")) == "skill_book":
		hud.show_message(str(result.get("message", "技能学习成功")))


func _on_skill_button_assignment_requested(request: Dictionary) -> void:
	var result := (
		SkillLoadoutRulesScript.clear_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			request
		)
		if bool(request.get("clear", false))
		else SkillLoadoutRulesScript.assign_button_slot(
			PlayerState.skill_button_assignments_snapshot(),
			PlayerState.learned_skills,
			request
		)
	)
	if not bool(result.get("ok", false)):
		hud.show_message("技能栏配置失败：%s" % str(result.get("reason", "invalid_request")))
		return
	if not PlayerState.apply_skill_button_assignment(result):
		if is_instance_valid(hud) and hud.has_method("set_skill_button_assignments"):
			hud.call(
				"set_skill_button_assignments",
				PlayerState.skill_button_assignments_snapshot()
			)
		hud.show_message("技能栏配置未能保存")
		return
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
	if not gameplay_input_is_enabled(): return
	var context := player.consume_attack_context()
	var diagnostic := _pending_melee_diagnostic.duplicate(true)
	_pending_melee_diagnostic.clear()
	_active_physical_hit_diagnostics.clear()
	var release_geometry: Dictionary = context.get("release_geometry", {})
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
	_expire_canonical_fire_charge_if_needed()
	var body_selection := context.duplicate(true)
	var selection_mode := str(body_selection.get("mode", WarriorMeleeGeometryScript.SKILL_NORMAL))
	if Time.get_ticks_msec() < _canonical_fire_charge_expires_ms:
		selection_mode = WarriorMeleeGeometryScript.SKILL_FIRE
	var melee_release_snapshot := _create_melee_release_footprint_snapshot(
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
	var melee_query_plan := _aoe_melee_query_plan(
		selection_mode,
		release_geometry["origin_ground_gu"],
		direction,
		release_geometry,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		release_geometry.get("target_aligned_plan", {}),
		melee_release_cache,
	)
	var primary_targets := _physical_primary_targets(
		origin,
		direction,
		selection_mode,
		release_geometry,
		thrust_damage_axis_plan,
		melee_release_snapshot,
		release_geometry.get("target_aligned_plan", {}),
		melee_query_plan,
	)
	var thrust_secondary_targets: Array[EnemyActor] = []
	var half_moon_secondary_targets: Array[EnemyActor] = []
	var eligible_target_count := primary_targets.size()
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
	var has_eligible_target := eligible_target_count > 0
	var consumes_armed_fire := false
	if not primary_targets.is_empty() and Time.get_ticks_msec() < _canonical_fire_charge_expires_ms:
		body_selection["mode"] = "fire"
		body_selection["selected_body_mode"] = "fire"
		body_selection["skill_name"] = "烈火剑法"
		body_selection["skill_level"] = PlayerState.effective_skill_level("烈火剑法")
		body_selection["direct_toggle_release"] = false
		consumes_armed_fire = true

	var hit_effect := SkillInputPolicyScript.resolve_warrior_hit_effect(
		body_selection,
		{
			"learned_skills": PlayerState.learned_skills,
			"toggles": {
				"warrior.fire_sword": player.fire_sword_enabled,
				"warrior.half_moon": player.half_moon_enabled,
				"warrior.thrusting": player.thrusting_enabled,
			},
			"has_combat_target": has_eligible_target,
			"current_mp": player.current_mp,
			"fire_rank": PlayerState.effective_skill_level("烈火剑法"),
			"half_moon_rank": PlayerState.effective_skill_level("半月弯刀"),
		}
	)
	var effect_mode := str(hit_effect.get("effect_mode", ""))
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
	if consumes_armed_fire and effect_mode == "fire":
		_set_canonical_fire_charge_expires_at(0)
	var melee_modifiers := SkillRuntimeRouterScript.resolve_warrior_melee_modifiers({
		"body_mode": effect_mode,
		"basic_sword_learned": PlayerState.is_skill_learned("基本剑术"),
		"basic_sword_rank": PlayerState.effective_skill_level("基本剑术"),
		"slaying_learned": PlayerState.is_skill_learned("攻杀剑术"),
		"slaying_rank": PlayerState.effective_skill_level("攻杀剑术"),
		"valid_melee_swing": has_eligible_target,
		"seed": _next_canonical_seed(),
	})
	var modified_base_damage := (
		damage
		+ int(melee_modifiers.get("flat_dc_bonus_before_body_formula", 0))
	)
	var post_body_damage_bonus := int(
		melee_modifiers.get("flat_damage_bonus_after_body_formula", 0)
	)
	var accuracy_bonus := int(melee_modifiers.get("flat_accuracy_bonus", 0))
	var hit_any := false
	var primary_hit := false
	var canonical_resolution := "rejected"
	if effect_mode in ["thrust", "half_moon", "fire"]:
		var melee_resolution := _execute_canonical_melee(
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
			true
		)
		hit_any = bool(melee_resolution.get("hit_any", false))
		primary_hit = bool(melee_resolution.get("primary_hit", false))
		canonical_resolution = str(melee_resolution.get("resolution", "rejected"))
	elif effect_mode == "normal":
		if not primary_targets.is_empty():
			var target := primary_targets[0]
			hit_any = _apply_physical_hit(
				target,
				modified_base_damage + post_body_damage_bonus,
				accuracy_bonus
			)
			primary_hit = hit_any
			canonical_resolution = "hit" if hit_any else "miss"
	# Weapon wear belongs to the physical swing, not to each target struck by
	# that swing. Besides matching the original server, this prevents Half Moon,
	# Thrusting and any future multi-target melee release from performing one
	# synchronous save per victim.
	if primary_hit and is_instance_valid(player):
		player.apply_confirmed_physical_hit_durability(
			maxi(1, modified_base_damage + post_body_damage_bonus)
		)
	_spawn_target_aligned_melee_visual(
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
		SkillExecutionPlanContractScript.cooldown_commit_count += 1
		player.commit_fire_sword_cooldown()
	_commit_warrior_melee_modifier_events(melee_modifiers)
	if (
		bool(melee_modifiers.get("slaying_proc", false))
		and effect_mode == "normal"
		and player.visual != null
		and player.visual.has_method("play_passive_proc_effect")
	):
		player.visual.call("play_passive_proc_effect", "攻杀剑术", 0.24)
	if effect_mode == "fire" and hud != null:
		hud.update_warrior_states(player.warrior_state_snapshot())
	_show_attack_flash(origin, direction, hit_any, Color(1.0, 0.72, 0.25))
	_record_melee_release_diagnostic(
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
	# Explicit diagnostic-only candidate evidence still uses the same mapped
	# broadphase.  Diagnostics must not reintroduce a SceneTree full-group scan
	# into an attack release just because the log is enabled.
	var result: Array[Dictionary] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var resolved_mode := (
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
	var diagnostic_radius_gu := (
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
	for selected: EnemyActor in primary_targets:
		if (
			_target_spatial_enemy_is_current(selected)
			and not _target_spatial_query_scratch.has(selected)
		):
			_target_spatial_query_scratch.append(selected)
	for enemy: EnemyActor in _target_spatial_query_scratch:
		var explanation := WarriorMeleeDiagnosticScript.explain_footprint_candidate(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			enemy.combat_radius_gu,
			direction_index,
			resolved_mode
		)
		explanation["angle_quantization_audit"] = (
			WarriorMeleeDiagnosticScript.audit_ground_delta_gu(
				_canonical_screen_px_to_ground_gu(enemy.global_position) - origin_ground_gu
			)
		)
		explanation["target_id"] = enemy.get_instance_id()
		explanation["target_name"] = enemy.display_name
		explanation["target_world"] = enemy.global_position
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


func _enemy_instance_ids(enemies: Array[EnemyActor]) -> Array[int]:
	var result: Array[int] = []
	for enemy: EnemyActor in enemies:
		if is_instance_valid(enemy):
			result.append(enemy.get_instance_id())
	return result


func _melee_direction_index(
	direction: Vector2,
	release_geometry: Dictionary = {}
) -> int:
	var resolved_index := int(release_geometry.get("direction_index", -1))
	if resolved_index >= 0 and resolved_index < 8:
		return resolved_index
	return ArtSpec.direction_index(direction)


func _melee_diagnostic_result_code(
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool,
	hit_attempts: Array[Dictionary]
) -> String:
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
	## HardCore v2: proficiency is disabled. Canonical melee modifier events are
	## intentionally discarded; they never grow, upgrade or persist skills.
	pass


func _on_special_action_pressed(effect_id: String) -> void:
	if not PlayerState.has_special_effect(effect_id):
		hud.show_message("特殊装备已失效")
		return
	match effect_id:
		"teleport":
			if _try_safe_ring_teleport():
				hud.show_message("传送戒指：安全位移")
			else:
				hud.show_message("前方没有合法传送落点")
		"flame_skill":
			if not player.spend_mana(5):
				hud.show_message("火球需要5点魔法")
				return
			_skill_cast_target = null
			_ensure_skill_cast_target(null)
			var direction := _face_skill_cast_target()
			if direction == Vector2.ZERO:
				direction = player.facing.normalized()
			var low := maxi(1, int(PlayerState.computed_stats.get("magic_min", 0)))
			var high := maxi(low, int(PlayerState.computed_stats.get("magic_max", low)))
			_spawn_projectile(
				player.global_position,
				direction,
				_rng.randi_range(low, high),
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
			hud.show_message("火焰戒指：火球")
		"recovery_skill":
			if not player.spend_mana(5):
				hud.show_message("治愈需要5点魔法")
				return
			var amount := maxi(12, int(PlayerState.level / 2) + int(PlayerState.computed_stats.get("tao_max", 0)) * 2)
			player.restore_health(amount)
			hud.show_message("防御戒指：恢复%d生命" % amount)


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
	if not gameplay_input_is_enabled(): return
	var skill_context := player.consume_skill_context()
	var release_geometry: Dictionary = skill_context.get("release_geometry", {})
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	if not release_geometry.is_empty():
		origin = release_geometry.get("origin_screen_px", origin)
		direction = release_geometry.get("direction_screen_px", direction)
		var release_target := _combat_release_target(release_geometry)
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
			hud.show_message("锁定目标已失效，技能未释放", 1.5)
			return
		_skill_cast_target = release_target
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
	var release_id := str(release_geometry.get("release_id", ""))
	if release_id.is_empty():
		release_id = _next_skill_footprint_release_id(stable_skill_id)
	var execution := _execute_canonical_skill(
		skill_name,
		origin,
		direction,
		damage,
		{"release_id": release_id},
		true,
		not release_geometry.is_empty()
	)
	var hit_any := bool(execution.get("effect_success", false))
	if not bool(execution.get("accepted", false)):
		hud.show_message("技能释放失败：%s" % str(execution.get("reason", "runtime_rejected")), 1.5)
		return
	if hit_any:
		_play_skill_audio_phase(stable_skill_id, "effect")
	var effect_color := Color(1.0, 0.22, 0.05) if PlayerState.profession == "战士" else (Color(0.28, 0.62, 1.0) if PlayerState.profession == "法师" else Color(0.45, 0.92, 0.55))
	_show_attack_flash(origin, direction, hit_any, effect_color)
	if skill_name == "烈火剑法":
		hud.update_warrior_states(player.warrior_state_snapshot())
	hud.show_message("施放：%s" % skill_name, 1.0)


func _execute_canonical_skill(
	skill_name: String,
	origin: Vector2,
	direction: Vector2,
	client_damage: int,
	extra_target_context: Dictionary = {},
	apply_effects := true,
	authoritative_cast_target := false
) -> Dictionary:
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(skill_name)
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	if definition.is_empty():
		_skill_cast_target = null
		return {"accepted": false, "effect_success": false, "reason": "unknown_skill"}
	var rank := PlayerState.effective_skill_level(skill_name)
	var release_context := (extra_target_context as Dictionary).duplicate(true)
	var support_center_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	if TAOIST_SUPPORT_SKILL_IDS.has(stable_skill_id):
		release_context["friendly_candidates"] = _canonical_friendly_candidates()
		release_context["caster_ground_position_gu"] = support_center_ground_gu
		if TAOIST_HEAL_SKILL_IDS.has(stable_skill_id):
			var friendly_resolution := _resolve_release_friendly_target(
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
				var mass_heal_center_tile := (
					TaoistFriendlyTargetingScript.grid_tile(
						selected_ground_gu
					)
				)
				release_context["target_tile"] = mass_heal_center_tile
				release_context["origin_tile"] = mass_heal_center_tile
		else:
			## mass invisibility / defence stay fixed to the caster's
			## release-frame position; never an enemy/ground/facing point.
			var self_center_tile := TaoistFriendlyTargetingScript.grid_tile(
				support_center_ground_gu
			)
			release_context["target_tile"] = self_center_tile
			## The professional geometry service treats target_tile ZERO as
			## "unset" and falls back to the origin tile; pin both to the same
			## floor tile so canonical cells stay centred on the caster.
			release_context["origin_tile"] = self_center_tile
		var support_resource_context := _canonical_resource_context(
			stable_skill_id
		)
		if support_resource_context.has("dual_defense_context"):
			release_context["dual_defense_context"] = (
				support_resource_context.get("dual_defense_context", {})
			)
	var target_context := _canonical_target_context(
		definition,
		origin,
		direction,
		not authoritative_cast_target,
		str(extra_target_context.get("release_id", "")),
		release_context
	)
	var cast_target := _skill_cast_target
	var request_facing := _canonical_facing_for_skill(stable_skill_id, direction)
	if stable_skill_id == WILD_RUSH_SKILL_ID and cast_target != null:
		var rush_plan := _build_wild_rush_path_plan(
			cast_target,
			str(target_context.get("release_id", ""))
		)
		if bool(rush_plan.get("eligible", false)):
			target_context.merge(rush_plan, true)
			request_facing = rush_plan.get("direction_step", request_facing)
	var resource_context := _canonical_resource_context(stable_skill_id)
	var request := SkillCastRequestScript.create(
		stable_skill_id,
		rank,
		PlayerState.level,
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
	# Q3-B: the single canonical plan comes from the router's formal planner
	# entry. No second plan object is ever built by GameRoot or the runtime.
	SkillExecutionPlanContractScript.release_id_generation_count += 1
	var canonical_context := _canonical_execution_context(
		stable_skill_id,
		origin,
		direction,
		target_context,
		cast_target,
		str(target_context.get("release_id", ""))
	)
	var plan := SkillRuntimeRouterScript.build_canonical_plan(
		request,
		canonical_context
	)
	var plan_rejection: Dictionary = plan.get("rejection", {})
	var plan_hash_before := str(plan.get("plan_hash", ""))
	var result := _legacy_result_from_plan(plan)
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
		result["execution_result"] = SkillExecutionPlanScript.build_result(
			plan,
			{"accepted": false}
		)
		return result
	var resource_quote: Dictionary = plan.get("resource_cost", {})
	var needs_resource := (
		int(resource_quote.get("mp_cost", 0)) > 0
		or int(resource_quote.get("material_amount", 0)) > 0
	)
	var resource_commit_required := bool(
		plan.get("resource_commit_required", true)
	)
	var resource_committed := false
	if resource_commit_required and needs_resource:
		resource_committed = _commit_canonical_resources(plan)
	elif resource_commit_required:
		resource_committed = true
	if resource_commit_required and not resource_committed:
		result["accepted"] = false
		result["effect_success"] = false
		result["reason"] = "resource_commit_failed"
		result["execution_result"] = SkillExecutionPlanScript.build_result(
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
			cast_target
		)
	var execution_result := SkillExecutionPlanScript.build_result(
		plan,
		{
			"accepted": true,
			"resource_committed": resource_committed,
			"cooldown_committed": false,
		}.merged(execution_overrides)
	)
	result["execution_result"] = execution_result
	result["plan_immutable"] = SkillExecutionPlanScript.verify_immutable(
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
	target: EnemyActor,
	release_id: String
) -> Dictionary:
	## Q3-B: frozen inputs for the canonical planner. GameRoot only prepares
	## world/projection context; the planner builds the single plan/snapshot.
	var target_position := _canonical_grid_cell_to_screen_px(
		target_context.get(
			"target_tile",
			_canonical_screen_px_to_grid_cell(origin)
		)
	)
	var target_ground_gu := _canonical_screen_px_to_ground_gu(
		target_position
	)
	var context := {
		"release_id": release_id,
		"runtime_map_id": current_map_id,
		"caster_runtime_id": player.get_instance_id(),
		"target_runtime_id": (
			target.get_instance_id()
			if is_instance_valid(target)
			else 0
		),
		"input_mode": "production_canonical",
		"origin_screen_px": origin,
		"direction_screen_px": direction,
		"target_position_screen_px": target_position,
		"summon_spawn_position_screen_px": target_context.get(
			"summon_spawn_position_screen_px",
			player.global_position
		),
		"target": target,
		"fallback_target_actor": player,
		"player_actor": player,
		"player_combat_radius_gu": _actor_combat_radius_gu(player),
		"target_combat_radius_gu": (
			_actor_combat_radius_gu(target)
			if is_instance_valid(target)
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
				direction
			)
		),
		"effective_cells_builder": (
			Callable(self, "_q3b_build_effective_cells").bind(
				stable_skill_id
			)
		),
	}
	return context


func _q3b_build_line_strip(
	effect: Dictionary,
	release_id: String,
	stable_skill_id: String,
	origin: Vector2,
	direction: Vector2
) -> Dictionary:
	return _canonical_continuous_line_strip_ground_gu(
		stable_skill_id,
		effect,
		origin,
		direction,
		release_id
	)


func _q3b_build_effective_cells(
	raw_geometry_cells: Variant,
	effect: Dictionary,
	stable_skill_id: String
) -> Array[Vector2i]:
	return _canonical_effective_spell_geometry_cells(
		stable_skill_id,
		raw_geometry_cells,
		effect
	)


func _legacy_result_from_plan(plan: Dictionary) -> Dictionary:
	## Q3-C: compat return envelope for existing GameRoot callers, sourced
	## entirely from the canonical plan. The formal result truth is
	## skill_execution_result.v1 (result["execution_result"]).
	var rejection: Dictionary = plan.get("rejection", {})
	var accepted := bool(rejection.get("accepted", false))
	var skill_id := str(plan.get("skill_id", ""))
	var result := {
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
	return str(plan.get("proficiency_event", ""))


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
	targets_resolved_at_release := false
) -> Dictionary:
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
	var primary_targets: Array[EnemyActor] = resolved_primary_targets
	var thrust_secondaries: Array[EnemyActor] = resolved_thrust_secondaries
	var half_moon_secondaries: Array[EnemyActor] = resolved_half_moon_secondaries
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
	var eligible_target_count := (
		primary_targets.size()
		+ thrust_secondaries.size()
		+ half_moon_secondaries.size()
	)
	var extra := {
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
		var melee_release_id := str(
			melee_release_snapshot.get("release_id", "")
		)
		if not melee_release_id.is_empty():
			extra["release_id"] = melee_release_id
	var result := _execute_canonical_skill(skill_name, origin, direction, base_damage, extra, false)
	if not bool(result.get("accepted", false)):
		return {"accepted": false, "hit_any": false, "resolution": "rejected"}
	var hit_any := false
	var primary_hit := false
	for raw_effect: Variant in result.get("effects", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		match str(effect.get("type", "")):
			"melee_hit":
				var targets: Array[EnemyActor] = (
					primary_targets
					if int(effect.get("cell", 1)) == 1
					else thrust_secondaries
				)
				for target: EnemyActor in targets:
					var resolved_damage := (
						roundi(float(base_damage) * float(effect.get("multiplier", 1.0)))
						+ post_body_damage_bonus
					)
					if mode == "thrust":
						var physical_resolution := WarriorCombatMath.resolve_enemy_physical_damage(
							resolved_damage,
							target.defense,
							WarriorCombatMath.thrust_segment_ignores_ac(int(effect.get("cell", 1))),
						)
						resolved_damage = int(physical_resolution.get("final_damage", 0))
					var target_hit := _apply_physical_hit(
						target,
						resolved_damage,
						accuracy_bonus
					)
					hit_any = target_hit or hit_any
					if int(effect.get("cell", 1)) == 1:
						primary_hit = target_hit or primary_hit
			"melee_arc":
				for primary: EnemyActor in primary_targets:
					var target_hit := _apply_physical_hit(
						primary,
						roundi(float(base_damage) * float(effect.get("primary_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					)
					primary_hit = target_hit or primary_hit
					hit_any = target_hit or hit_any
				for secondary: EnemyActor in half_moon_secondaries:
					hit_any = _apply_physical_hit(
						secondary,
						roundi(float(base_damage) * float(effect.get("side_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					) or hit_any
			"next_melee_charge":
				if not primary_targets.is_empty():
					var target := primary_targets[0]
					primary_hit = _apply_physical_hit(
						target,
						roundi(float(base_damage) * float(effect.get("damage_multiplier", 1.0)))
						+ post_body_damage_bonus,
						accuracy_bonus
					)
					hit_any = primary_hit
	return {
		"accepted": true,
		"hit_any": hit_any,
		"primary_hit": primary_hit,
		"resolution": "hit" if hit_any else "miss",
	}


func _canonical_basic_sword_bonus(origin: Vector2, direction: Vector2, valid_swing: bool) -> int:
	if not PlayerState.is_skill_learned("基本剑术"):
		return 0
	var result := _execute_canonical_skill(
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
	allow_auto_target := true,
	release_id := "",
	context_overrides: Dictionary = {}
) -> Dictionary:
	var target_contract: Dictionary = definition.get("target", {})
	var stable_skill_id := str(definition.get("skill_id", ""))
	var target_mode := str(target_contract.get("mode", ""))
	var target_relation := str(target_contract.get("relation", ""))
	var friendly_cast := target_relation.contains("friendly") or target_mode in ["self", "self_or_friendly_single"]
	var search_range_gu := SpellTargetLockPolicyScript.LOCK_RANGE_GU
	if allow_auto_target and not friendly_cast and target_mode not in ["self", "self_stat", "self_summon", "self_next_melee_charge", "self_random_destination", "caster_surrounding_area", "surrounding_units"]:
		_ensure_skill_cast_target(null)
	var target := _skill_cast_target if not friendly_cast and is_instance_valid(_skill_cast_target) else null
	var target_within_skill_range := (
		target != null and _spell_definition_allows_target(definition, target)
	)
	var hostile_target_required := _definition_requires_hostile_target(definition)
	var independent_geometry_target := (
		str(definition.get("skill_id", "")) != FIRE_WALL_SKILL_ID
		and not hostile_target_required
		and (
			target_mode == "facing_line"
			or target_mode.contains("surrounding")
			or target_mode.contains("ground")
			or target_mode.begins_with("self")
		)
	)
	var usable_target := (
		target != null
		and (not target_relation.contains("hostile") or target_within_skill_range)
	)
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_ground_gu := GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
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
	var maximum_range_gu := float(
		definition.get("geometry", {}).get("maximum_range_gu", 0.0)
	)
	var fallback_distance_gu := (
		maximum_range_gu
		if maximum_range_gu > 0.0
		else search_range_gu
	)
	var fallback_target_ground_gu := (
		origin_ground_gu + direction_ground_gu * fallback_distance_gu
	)
	var fallback_target_tile := Vector2i(
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
	var context := {
		"input_mode": "production_canonical",
		"runtime_map_id": current_map_id,
		"caster_runtime_id": player.get_instance_id(),
		"has_target": usable_target or independent_geometry_target or friendly_cast,
		"line_of_sight": usable_target or independent_geometry_target or friendly_cast,
		"friendly": friendly_cast,
		"hostile": usable_target and not friendly_cast,
		"spell_lock_contract": SpellTargetLockPolicyScript.CONTRACT_ID,
		"spell_lock_range_gu": SpellTargetLockPolicyScript.LOCK_RANGE_GU,
		"target_within_skill_range": target_within_skill_range,
		"target_tile": _canonical_screen_px_to_grid_cell(
			target.global_position
			if usable_target
			else _canonical_grid_cell_to_screen_px(fallback_target_tile)
		),
		"primary_stat_roll": _canonical_primary_stat_roll(str(definition.get("class", ""))),
		"actual_hp_missing": player.max_hp - player.current_hp,
		"friendly_missing_hp": [player.max_hp - player.current_hp],
		"affected_friendly_count": 1,
		"friendly_targets": [{
			"instance_id": player.get_instance_id(),
			"target_instance_id": player.get_instance_id(),
			"level": PlayerState.level,
		}],
		"friendly_target_instance_ids": [player.get_instance_id()],
		"affected_friendly_target_instance_ids": [player.get_instance_id()],
		"map_allows_random_teleport": true,
		"destination_valid": true,
		"spawn_tile_valid": false,
		"has_main_pet": _canonical_main_pet() != null,
		"active_main_pet_summon_ids": _canonical_main_pet_summon_ids(),
		"requested_main_pet_summon_id": _summon_id_for_skill(stable_skill_id),
		"current_pet_count": get_tree().get_nodes_in_group("summons").size(),
		"caster_max_hp": player.max_hp,
	}
	var snapshot_origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	context["snapshot_coordinate_context"] = (
		_canonical_snapshot_absolute_context(snapshot_origin_ground_gu)
	)
	if stable_skill_id == "wizard.teleport":
		var destination := _find_valid_random_teleport_position(origin)
		context["destination_valid"] = destination != origin
		context["destination_tile"] = _canonical_screen_px_to_grid_cell(destination)
	if target != null:
		var monster_data: Dictionary = target.monster_data
		var target_control_immunity := target.control_immunity_snapshot()
		var service_behavior: Dictionary = target.behavior_profile.get(
			"serviceBehavior", {}
		)
		var target_is_undead := bool(service_behavior.get(
			"undead",
			monster_data.get("undead", monster_data.get("isUndead", false))
		))
		context.merge({
			"target_instance_id": target.get_instance_id(),
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
			"target_within_level_gate": target.level <= PlayerState.level,
		}, true)
	# Caller-provided authoritative values (for example a server-selected
	# teleport destination) must be applied before the immutable release
	# footprint is built.  Merging them afterwards produces a result whose
	# effect destination and footprint snapshot describe different ground
	# positions.
	context.merge(context_overrides, true)
	if stable_skill_id in [
		"taoist.summon_skeleton",
		"taoist.summon_divine_beast",
	]:
		var summon_spawn_plan := _canonical_summon_spawn_plan(stable_skill_id)
		context["spawn_tile_valid"] = bool(
			summon_spawn_plan.get("valid", false)
		)
		context["summon_spawn_position_screen_px"] = summon_spawn_plan.get(
			"position_screen_px",
			player.global_position
		)
		context["summon_spawn_position_ground_gu"] = summon_spawn_plan.get(
			"position_ground_gu",
			_canonical_screen_px_to_ground_gu(player.global_position)
		)
	var resolved_release_id := str(release_id)
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
		var declared_geometry_cells := SkillGeometryServiceScript.cells(
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
		var target_actor: Node2D = target if is_instance_valid(target) else player
		if (
			stable_skill_id == "taoist.healing"
			and int(context.get("selected_friendly_instance_id", 0)) > 0
		):
			var selected_friendly_actor := _canonical_friendly_actor(
				int(context.get("selected_friendly_instance_id", 0))
			)
			if selected_friendly_actor != null:
				target_actor = selected_friendly_actor
		if is_instance_valid(target_actor):
			context["skill_footprint_snapshot"] = (
				SkillFootprintSnapshotScript.create_target_footprint(
					stable_skill_id,
					resolved_release_id,
					_canonical_screen_px_to_ground_gu(target_actor.global_position),
					_actor_combat_radius_gu(target_actor),
					target_actor.get_instance_id(),
					_canonical_snapshot_absolute_context(
						_canonical_screen_px_to_ground_gu(
							target_actor.global_position
						)
					)
				)
			)
	elif ATTACHED_STATE_SKILL_IDS.has(stable_skill_id) and is_instance_valid(player):
		context["skill_footprint_snapshot"] = (
			SkillFootprintSnapshotScript.create_target_footprint(
				stable_skill_id,
				resolved_release_id,
				_canonical_screen_px_to_ground_gu(player.global_position),
				_actor_combat_radius_gu(player),
				player.get_instance_id(),
				_canonical_snapshot_absolute_context(
					_canonical_screen_px_to_ground_gu(player.global_position)
				)
			)
		)
	elif stable_skill_id == "wizard.teleport":
		var teleport_destination_screen_px := _canonical_grid_cell_to_screen_px(
			context.get("destination_tile", Vector2i.ZERO)
		)
		var teleport_destination_ground_gu := _canonical_screen_px_to_ground_gu(
			teleport_destination_screen_px
		)
		context["skill_footprint_snapshot"] = (
			SkillFootprintSnapshotScript.create_target_footprint(
				stable_skill_id,
				resolved_release_id,
				teleport_destination_ground_gu,
				_actor_combat_radius_gu(player),
				player.get_instance_id(),
				_canonical_snapshot_absolute_context(
					teleport_destination_ground_gu
				)
			)
		)
	var exact_snapshot_valid := false
	if (
		not bool(context.get("hostile_targets_pre_resolved", false))
		or friendly_cast
	):
		exact_snapshot_valid = _snapshot_strict_ok(exact_release_snapshot)
	var nearby: Array[Dictionary] = []
	var adjacent_ring_cells: Array[Vector2i] = []
	if str(definition.get("geometry", {}).get("shape", "")) == "adjacent_ring":
		var caster_tile := _canonical_screen_px_to_grid_cell(origin)
		for ring_y: int in range(-1, 2):
			for ring_x: int in range(-1, 2):
				if ring_x != 0 or ring_y != 0:
					adjacent_ring_cells.append(
						caster_tile + Vector2i(ring_x, ring_y)
					)
	if not bool(context.get("hostile_targets_pre_resolved", false)):
		# The broadphase envelope is deliberately conservative; the exact
		# snapshot/range/adjacent-ring checks below remain authoritative.
		var target_query_bounds := Rect2(
			origin_ground_gu - Vector2.ONE * search_range_gu,
			Vector2.ONE * search_range_gu * 2.0,
		)
		if exact_snapshot_valid:
			var snapshot_aabb := SkillFootprintSnapshotScript.ground_aabb(
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
			for node: EnemyActor in _target_spatial_query_scratch:
				if (
					exact_snapshot_valid
					and not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
						exact_release_snapshot,
						_canonical_screen_px_to_ground_gu(node.global_position),
						node.combat_radius_gu,
					)
				):
					continue
				if (
					not exact_snapshot_valid
					and not GroundUnitSpaceScript.is_within_range_gu(
						origin_ground_gu,
						_canonical_screen_px_to_ground_gu(node.global_position),
						search_range_gu
					)
				):
					continue
				if (
					not adjacent_ring_cells.is_empty()
					and not bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
						adjacent_ring_cells,
						_canonical_screen_px_to_ground_gu(node.global_position),
						node.combat_radius_gu
					).get("intersects", false))
				):
					continue
				var node_ground_gu := _canonical_screen_px_to_ground_gu(
					node.global_position
				)
				nearby.append({
					"instance_id": node.get_instance_id(),
					"target_instance_id": node.get_instance_id(),
					"level": node.level,
					"is_boss": node.is_boss,
					"immovable": node.is_boss,
					"path_blocked": background.is_environment_point_blocked(
						_canonical_ground_gu_to_screen_px(
							node_ground_gu + (
								node_ground_gu - origin_ground_gu
							).normalized()
						)
					),
					"hostile_monster": true,
					"control_immune": node.is_boss,
					"within_level_gate": node.level <= PlayerState.level,
				})
	context["targets"] = nearby
	if friendly_cast and exact_snapshot_valid:
		var friendly_targets: Array[Dictionary] = []
		var friendly_missing_hp: Array[int] = []
		var friendly_actors: Array[Node2D] = [player]
		for summon_node: Node in get_tree().get_nodes_in_group("summons"):
			if summon_node is SummonActor and summon_node.owner_player == player:
				friendly_actors.append(summon_node)
		for friendly_actor: Node2D in friendly_actors:
			if not SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
				exact_release_snapshot,
				_canonical_screen_px_to_ground_gu(friendly_actor.global_position),
				_actor_combat_radius_gu(friendly_actor)
			):
				continue
			var actor_level := (
				PlayerState.level
				if friendly_actor == player
				else int((friendly_actor as SummonActor).owner_level)
			)
			var actor_max_hp := int(friendly_actor.get("max_hp"))
			var actor_current_hp := int(friendly_actor.get("current_hp"))
			friendly_targets.append({
				"instance_id": friendly_actor.get_instance_id(),
				"target_instance_id": friendly_actor.get_instance_id(),
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


func _canonical_resource_context(stable_skill_id: String) -> Dictionary:
	var result := PlayerState.canonical_skill_resource_context(
		stable_skill_id,
		player.current_mp
	)
	var requested_summon_id := _summon_id_for_skill(stable_skill_id)
	if not requested_summon_id.is_empty():
		# Live actors are authoritative during play. PlayerState supplies the same
		# typed contract to Player.can_request_skill and old-save restoration.
		result["requested_main_pet_summon_id"] = requested_summon_id
		result["active_main_pet_summon_ids"] = (
			_canonical_main_pet_summon_ids()
		)
	return result


func _commit_canonical_resources(result: Dictionary) -> bool:
	## Q3-B: consumes the canonical plan's frozen resource_cost (legacy
	## resource_quote accepted for compat); commits at most once per release.
	var quote: Dictionary = result.get(
		"resource_quote",
		result.get("resource_cost", {})
	)
	var mana_cost := maxi(0, int(quote.get("mp_cost", 0)))
	var material_id := str(quote.get("material_id", ""))
	var material_amount := maxi(0, int(quote.get("material_amount", 0)))
	var item_name := PlayerState.canonical_material_item_name(material_id)
	if player.current_mp < mana_cost:
		return false
	if material_amount > 0 and (item_name.is_empty() or PlayerState.item_count(item_name) < material_amount):
		return false
	if not player.spend_mana(mana_cost):
		return false
	if material_amount > 0 and not PlayerState.remove_item(item_name, material_amount):
		player.restore_mana(mana_cost)
		return false
	SkillExecutionPlanContractScript.resource_commit_count += 1
	return true


func _apply_canonical_effects_from_plan(
	plan: Dictionary,
	origin: Vector2,
	direction: Vector2,
	target_context: Dictionary,
	target: EnemyActor = null
) -> Dictionary:
	## Q3-B: commits the canonical plan's gameplay actions. Node creation
	## (projectile/ground/summon/visual) comes from the plan's descriptors via
	## create_cast_nodes_from_canonical_plan; this loop only applies direct
	## damage/status/buff side effects. No second plan is ever built.
	var stable_skill_id := str(plan.get("skill_id", ""))
	if not is_instance_valid(target):
		target = null
	var target_position := _canonical_grid_cell_to_screen_px(
		target_context.get(
			"target_tile",
			_canonical_screen_px_to_grid_cell(origin)
		)
	)
	var release_id := str(plan.get("release_id", ""))
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
	var spawned_nodes: Array[Node2D] = _spawn_canonical_cast_nodes_from_plan(
		plan,
		origin,
		direction,
		target,
		target_position
	)
	var spawned_projectiles: Array[int] = []
	var spawned_ground_effects: Array[int] = []
	var spawned_summons: Array[int] = []
	var created_visuals: Array[int] = []
	for node: Node2D in spawned_nodes:
		if node is SkillProjectile:
			spawned_projectiles.append(node.get_instance_id())
		elif node is GroundSkillEffect:
			spawned_ground_effects.append(node.get_instance_id())
		elif node is SummonActor:
			spawned_summons.append(node.get_instance_id())
		else:
			created_visuals.append(node.get_instance_id())
	var friendly_effect_index := 0
	for raw_effect: Variant in plan.get("gameplay_actions", []):
		if not raw_effect is Dictionary:
			continue
		var effect: Dictionary = raw_effect
		var effect_type := str(effect.get("type", ""))
		match effect_type:
			"projectile_damage", "talisman_projectile_damage", "persistent_ground_damage", "main_pet_spawn", "recall_existing_main_pet":
				# Node creation is owned by the canonical descriptors (adapter /
				# summon sink); the gameplay action itself is already committed.
				pass
			"targeted_sky_strike", "line_damage", "piercing_line_damage", "area_damage", "caster_centered_area_damage":
				var raw_power := int(
					effect.get(
						"raw_power_after_race",
						effect.get("raw_power", 0)
					)
				)
				var damage_origin := (
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
				)
			"dedicated_heal":
				var heal_target_id := int(
					effect.get("target_instance_id", 0)
				)
				var heal_actor := (
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
				var repulsion_target := _canonical_effect_enemy(effect)
				if (
					repulsion_target != null
					and bool(effect.get("displaced", false))
					and _skill_snapshot_intersects_enemy(
						skill_release_snapshot,
						repulsion_target
					)
				):
					var source_ground_gu := _canonical_screen_px_to_ground_gu(
						origin
					)
					var target_ground_gu := _canonical_screen_px_to_ground_gu(
						repulsion_target.global_position
					)
					var push_direction_ground_gu := (
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
				_combat_runtime.apply_damage(
					player,
					int(effect.get("amount", 1))
				)
			"server_random_teleport":
				if bool(effect.get("moved", false)):
					var destination := _canonical_grid_cell_to_screen_px(
						effect.get("destination", Vector2i.ZERO)
					)
					var destination_ground_gu := (
						_canonical_screen_px_to_ground_gu(destination)
					)
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
						and _apply_canonical_player_teleport(destination)
					):
						_spawn_canonical_teleport_arrival(
							stable_skill_id,
							destination,
							direction,
							skill_release_snapshot
						)
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
					var stealth_actor := _canonical_friendly_actor(
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
				var defence_stat := str(effect.get("stat", "AC"))
				var defence_duration := float(
					effect.get("duration_seconds", 1)
				)
				var defence_buff_id := str(effect.get("buff_id", ""))
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
					var buff_target_id := int(
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
					_combat_runtime.apply_enemy_physical_damage(
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
					hud.show_message(
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
						var node := instance_from_id(trapped_target_id)
						## The plan's trapped identity and immutable strict-V2
						## release snapshot are authoritative. EnemyActor owns the
						## boundary lifecycle; this integration sink must not
						## degrade entrapment into generic immobilization.
						if node is EnemyActor:
							(node as EnemyActor).apply_entrapment(
								effect,
								skill_release_snapshot,
								player
							)
			"next_melee_charge":
				_set_canonical_fire_charge_expires_at(
					Time.get_ticks_msec()
					+ maxi(1, int(effect.get("charge_lifetime_ms", 10000)))
				)
	return {
		"spawned_projectile_ids": spawned_projectiles,
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
	target: EnemyActor,
	target_position: Vector2
) -> Array[Node2D]:
	## Q3-B: the ONLY formal node creation entry - CasterSkillRuntime consumes
	## the canonical plan (no legacy presentation plan or cast-node entry).
	var stable_skill_id := str(plan.get("skill_id", ""))
	if stable_skill_id == FIRE_WALL_SKILL_ID:
		# Q2-C/Q3-B: the formal fire wall release owns exactly ONE
		# FireWallFieldController plus its 4 pure-visual cells. Never fall back
		# to the generic ground-dot factory or standalone GroundSkillEffect
		# cells; the field controller is the single damage/visual owner.
		var ground_effect := _canonical_plan_ground_effect(plan)
		if not ground_effect.is_empty():
			_spawn_canonical_ground_field(
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
	var nodes: Array[Node2D] = (
		CasterSkillRuntimeScript.create_cast_nodes_from_canonical_plan(
			plan,
			origin,
			direction,
			Color.WHITE,
			target,
			player,
			_canonical_primary_stat_roll("taoist"),
			PlayerState.level,
			Callable(self, "_apply_canonical_main_pet_from_descriptor"),
			{
				"combat_spatial_index": _combat_spatial_index,
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
	for node: Node2D in nodes:
		if is_instance_valid(node):
			add_child(node)
	return nodes


func _canonical_plan_ground_effect(plan: Dictionary) -> Dictionary:
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
	_apply_canonical_main_pet(
		descriptor,
		str(plan.get("skill_id", "")),
		str(plan.get("release_id", ""))
	)


func _canonical_effect_enemy(effect: Dictionary) -> EnemyActor:
	var instance_id := int(effect.get("target_instance_id", 0))
	if instance_id <= 0:
		return null
	var candidate := instance_from_id(instance_id)
	if (
		candidate is EnemyActor
		and is_instance_valid(candidate)
		and candidate.is_inside_tree()
		and not candidate.is_queued_for_deletion()
	):
		return candidate as EnemyActor
	return null


func _set_canonical_fire_charge_expires_at(expires_at_ms: int) -> void:
	_canonical_fire_charge_expires_ms = maxi(0, expires_at_ms)
	if player != null:
		player.set_fire_sword_charge_display(_canonical_fire_charge_expires_ms)


func _expire_canonical_fire_charge_if_needed() -> void:
	if (
		_canonical_fire_charge_expires_ms > 0
		and Time.get_ticks_msec() >= _canonical_fire_charge_expires_ms
	):
		_set_canonical_fire_charge_expires_at(0)


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
) -> bool:
	var resolved_snapshot := _aoe_spell_snapshot(
		skill_release_snapshot,
		continuous_line_strip_ground_gu,
	)
	var context_release_id := str(resolved_snapshot.get("release_id", ""))
	if context_release_id.is_empty():
		context_release_id = str(continuous_line_strip_ground_gu.get("release_id", ""))
	var context_skill_id := stable_skill_id if not stable_skill_id.is_empty() else "canonical_aoe"
	if context_release_id.is_empty():
		context_release_id = context_skill_id
	RuntimeDiagnostics.set_performance_release_context(
		context_release_id,
		context_skill_id,
	)
	RuntimeDiagnostics.increment_performance_counter(&"aoe_release_count")
	var plan := query_plan
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
	var aoe_candidate_started_usec := RuntimeDiagnostics.timing_start()
	if not _aoe_plan_is_ready(plan) and not _aoe_reference_fallback_allowed():
		_aoe_record_query_rejection(
			"aoe_query_plan_invalid_or_spatial_index_unavailable"
		)
		_record_aoe_candidate_timing(aoe_candidate_started_usec)
		return false
	var targets: Array[EnemyActor] = []
	var has_declared_geometry_cells := (
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
				for node: EnemyActor in _aoe_candidate_scratch:
					RuntimeDiagnostics.increment_performance_counter(
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
				for node: EnemyActor in _aoe_candidate_scratch:
					RuntimeDiagnostics.increment_performance_counter(
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
		var radius_gu := maxf(0.0, float(effect.get("radius_gu", 0.0)))
		if not radial or radius_gu <= 0.0:
			_record_aoe_candidate_timing(aoe_candidate_started_usec)
			return false
		if _aoe_plan_is_ready(plan):
			_aoe_query_enemy_candidates_aabb(
				plan,
				plan.get("ground_aabb", Rect2()),
				false,
			)
			for enemy: EnemyActor in _aoe_candidate_scratch:
				RuntimeDiagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _aoe_validated_snapshot_intersects(plan, enemy):
					targets.append(enemy)
		elif _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			for enemy: EnemyActor in _aoe_candidate_scratch:
				RuntimeDiagnostics.increment_performance_counter(
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
			for enemy: EnemyActor in _aoe_candidate_scratch:
				RuntimeDiagnostics.increment_performance_counter(
					&"aoe_exact_intersection_tests"
				)
				if _aoe_validated_snapshot_intersects(plan, enemy):
					targets.append(enemy)
	_record_aoe_candidate_timing(aoe_candidate_started_usec)
	RuntimeDiagnostics.increment_performance_counter(&"aoe_selected_targets", targets.size())
	RuntimeDiagnostics.increment_performance_counter(&"aoe_damage_target_count", targets.size())
	var aoe_exact_started_usec := RuntimeDiagnostics.timing_start()
	var hit_any := false
	for enemy: EnemyActor in targets:
		var resolution: Dictionary = _combat_runtime.apply_enemy_direct_spell_damage(
			enemy,
			stable_skill_id,
			raw_power,
			player,
			_rng,
			Callable(self, "_resolve_magic_defense"),
			-1,
			_direct_spell_target_stats_scratch,
		)
		hit_any = bool(resolution.get("success", false)) or hit_any
	RuntimeDiagnostics.record_timing_usec(&"aoe_exact_phase_usec", aoe_exact_started_usec)
	_record_skill_footprint_release_diagnostic(
		stable_skill_id,
		resolved_snapshot,
		targets.size(),
		hit_any
	)
	return hit_any


func _record_aoe_candidate_timing(started_usec: int) -> void:
	var elapsed_usec := RuntimeDiagnostics.timing_elapsed_usec(started_usec)
	if elapsed_usec <= 0:
		return
	RuntimeDiagnostics.increment_performance_counter(&"aoe_candidate_usec", elapsed_usec)
	RuntimeDiagnostics.record_performance_max(
		&"aoe_max_single_release_candidate_usec",
		float(elapsed_usec),
	)


func _record_skill_footprint_release_diagnostic(
	stable_skill_id: String,
	skill_release_snapshot: Dictionary,
	eligible_target_count: int,
	damage_applied: bool
) -> void:
	if not SkillFootprintDiagnosticLogScript.capture_enabled():
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
	var projected_polygon_px := (
		SkillFootprintSnapshotScript.projected_polygon_screen_offset_px(
			snapshot
		)
	)
	SkillFootprintDiagnosticLogScript.record({
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


func _actor_combat_radius_gu(actor: Node2D) -> float:
	if not is_instance_valid(actor):
		return 0.0
	for property: Dictionary in actor.get_property_list():
		if str(property.get("name", "")) == "combat_radius_gu":
			return maxf(0.0, float(actor.get("combat_radius_gu")))
	return WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
		ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)


func _skill_snapshot_intersects_enemy(
	skill_release_snapshot: Dictionary,
	enemy: EnemyActor
) -> bool:
	return (
		is_instance_valid(enemy)
		and _snapshot_strict_ok(skill_release_snapshot)
		and SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
			skill_release_snapshot,
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			enemy.combat_radius_gu
		)
	)


func _canonical_effective_spell_geometry_cells(
	stable_skill_id: String,
	raw_geometry_cells: Variant,
	effect: Dictionary
) -> Array[Vector2i]:
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
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
	return contract_id in [
		CasterSpellGeometryScript.CONTINUOUS_AIM_LINE_CONTRACT_ID,
		CONTINUOUS_AIM_LINE_CONTRACT_ID_LEGACY
	]


func _canonical_continuous_line_strip_ground_gu(
	stable_skill_id: String,
	effect: Dictionary,
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	release_id := ""
) -> Dictionary:
	if (
		stable_skill_id not in CONTINUOUS_WIZARD_LINE_SKILLS
		or not _is_supported_continuous_line_contract(
			str(effect.get("line_geometry_contract", ""))
		)
	):
		return {}
	var definition := SkillDataLoaderScript.skill(stable_skill_id)
	var geometry: Dictionary = definition.get("geometry", {})
	var effect_length_gu := maxf(
		0.0,
		float(effect.get("effect_length_gu", geometry.get("effect_length_gu", 0.0)))
	)
	var effect_width_gu := maxf(
		0.0001,
		float(effect.get("effect_width_gu", geometry.get("effect_width_gu", 1.0)))
	)
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	var resolved_effect_length_gu := effect_length_gu
	if stable_skill_id == "wizard.laser" and bool(effect.get("stops_on_terrain", geometry.get("stops_on_terrain", false))):
		resolved_effect_length_gu = CasterSpellGeometryScript.resolve_laser_effect_length_gu(
			direction_ground_gu,
			effect_length_gu
		)
	var final_effect_length_gu := resolved_effect_length_gu
	var laser_projection_policy := ""
	if stable_skill_id == "wizard.laser":
		laser_projection_policy = "screen_length_limit_diagonal_reference_v1"
	var resolved_release_id := str(release_id)
	if resolved_release_id.is_empty():
		resolved_release_id = _next_skill_footprint_release_id(stable_skill_id)
	var line_coordinate_context := _canonical_snapshot_absolute_context(
		origin_ground_gu
	)
	var strip_ground_gu := CasterSpellGeometryScript.continuous_line_strip_ground_gu(
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
		var unblocked_length_gu := _canonical_continuous_line_unblocked_length_gu(
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
			var snap := (line_snapshot as Dictionary).duplicate(true)
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
	var effect_length_gu := maxf(
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
	const SAMPLE_STEP_GU := 0.25
	var sample_count := ceili(effect_length_gu / SAMPLE_STEP_GU)
	var last_clear_distance_gu := 0.0
	for sample_index: int in range(1, sample_count + 1):
		var distance_gu := minf(
			float(sample_index) * SAMPLE_STEP_GU,
			effect_length_gu
		)
		var sample_ground_gu := (
			origin_ground_gu + direction_ground_gu * distance_gu
		)
		var sample_cell := Vector2i(
			roundi(sample_ground_gu.x),
			roundi(sample_ground_gu.y)
		)
		if _canonical_spell_cell_is_terrain_blocked(sample_cell):
			return last_clear_distance_gu
		last_clear_distance_gu = distance_gu
	return last_clear_distance_gu


func _canonical_spell_cell_is_terrain_blocked(cell: Vector2i) -> bool:
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	if not runtime.is_empty():
		return runtime.get("collision", {}).get("blocked_tiles", []).has(
			"%d,%d" % [cell.x, cell.y]
		)
	return (
		background != null
		and background.has_method("is_environment_point_blocked")
		and bool(background.call(
			"is_environment_point_blocked",
			_canonical_grid_cell_to_screen_px(cell)
		))
	)


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
	for enemy: EnemyActor in candidates:
		if (
			not is_instance_valid(enemy)
			or enemy.is_queued_for_deletion()
			or enemy.current_hp <= 0
		):
			continue
		RuntimeDiagnostics.increment_performance_counter(
			&"aoe_exact_intersection_tests"
		)
		var intersects := (
			_aoe_validated_snapshot_intersects(plan, enemy)
			if _aoe_plan_is_ready(plan)
			else CasterSpellGeometryScript.target_footprint_intersects_continuous_line_ground_gu(
				line_strip,
				_enemy_footprint_polygon_ground_gu(enemy),
			)
		)
		if not intersects:
			continue
		var enemy_ground_gu := _canonical_screen_px_to_ground_gu(
			enemy.global_position
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
) -> Array[EnemyActor]:
	var geometry_cells: Array[Vector2i] = []
	if raw_geometry_cells is Array:
		for raw_cell: Variant in raw_geometry_cells:
			if raw_cell is Vector2i:
				geometry_cells.append(raw_cell)
	var targets: Array[EnemyActor] = []
	var release_cache: Dictionary = {}
	var plan := query_plan
	if plan.is_empty():
		plan = _aoe_spell_query_plan(
			stable_skill_id,
			geometry_cells,
			effect,
			continuous_line_strip_ground_gu,
			skill_release_snapshot,
			_canonical_screen_px_to_ground_gu(
				player.global_position if is_instance_valid(player) else Vector2.ZERO
			),
			release_cache,
		)
		if not _aoe_spell_snapshot(
			skill_release_snapshot,
			continuous_line_strip_ground_gu,
		).is_empty():
			RuntimeDiagnostics.increment_performance_counter(&"aoe_release_count")
	var broadphase_ready := _aoe_plan_is_ready(plan)
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
	var maximum_targets := int(effect.get("maximum_targets", -1))
	var selects_all_intersecting_effect_cells := (
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
		var line_width_gu := maxf(
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
		for enemy: EnemyActor in _aoe_candidate_scratch:
			RuntimeDiagnostics.increment_performance_counter(
				&"aoe_exact_intersection_tests"
			)
			if _aoe_validated_snapshot_intersects(plan, enemy):
				_aoe_insert_by_instance_id(targets, target_ids, enemy)
		if targets.is_empty() and _aoe_reference_fallback_allowed():
			_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
			for enemy: EnemyActor in _aoe_candidate_scratch:
				RuntimeDiagnostics.increment_performance_counter(
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
		RuntimeDiagnostics.increment_performance_counter(&"aoe_nested_cell_enemy_scans")
		var cell_targets: Array[EnemyActor] = []
		var cell_target_ids: Array[int] = []
		for enemy: EnemyActor in _aoe_candidate_scratch:
			if selected_instance_ids.has(enemy.get_instance_id()):
				continue
			RuntimeDiagnostics.increment_performance_counter(
				&"aoe_exact_intersection_tests"
			)
			var contact := CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
				[cell],
				_canonical_screen_px_to_ground_gu(enemy.global_position),
				enemy.combat_radius_gu
			)
			if bool(contact.get("intersects", false)):
				_aoe_insert_by_instance_id(cell_targets, cell_target_ids, enemy)
		for enemy: EnemyActor in cell_targets:
			targets.append(enemy)
			selected_instance_ids.append(enemy.get_instance_id())
			if maximum_targets > 0 and targets.size() >= maximum_targets:
				return targets
	if targets.is_empty() and broadphase_ready and _aoe_reference_fallback_allowed():
		_aoe_reference_enemy_nodes_into(_aoe_candidate_scratch)
		selected_instance_ids.clear()
		targets.clear()
		for cell: Vector2i in cells_to_visit:
			var cell_targets: Array[EnemyActor] = []
			var cell_target_ids: Array[int] = []
			for enemy: EnemyActor in _aoe_candidate_scratch:
				if selected_instance_ids.has(enemy.get_instance_id()):
					continue
				var contact := CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
					[cell],
					_canonical_screen_px_to_ground_gu(enemy.global_position),
					enemy.combat_radius_gu
				)
				if bool(contact.get("intersects", false)):
					_aoe_insert_by_instance_id(cell_targets, cell_target_ids, enemy)
			for enemy: EnemyActor in cell_targets:
				targets.append(enemy)
				selected_instance_ids.append(enemy.get_instance_id())
				if maximum_targets > 0 and targets.size() >= maximum_targets:
					return targets
	return targets


func _enemy_footprint_polygon_ground_gu(enemy: EnemyActor) -> PackedVector2Array:
	if not is_instance_valid(enemy):
		return PackedVector2Array()
	return CasterSpellGeometryScript.actor_footprint_polygon_ground_gu(
		_canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu
	)


func _ground_circle_intersects_enemy_footprint_gu(
	center_screen_px: Vector2,
	radius_gu: float,
	enemy: EnemyActor
) -> bool:
	if not is_instance_valid(enemy):
		return false
	var center_ground_gu := _canonical_screen_px_to_ground_gu(center_screen_px)
	var enemy_center_ground_gu := _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var enemy_radius_gu := enemy.combat_radius_gu
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
	release_id := "",
	skill_release_snapshot: Dictionary = {}
) -> void:
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
		var field_snapshot_validation_context := (
			_canonical_snapshot_validation_context(
				_canonical_screen_px_to_ground_gu(fallback_position)
			)
		)
		# Q2-C: the formal release owns exactly ONE canonical 2x2 union
		# snapshot. Legacy/test callers that omit one get a deterministic
		# fallback built from the same coverage cells, so the controller never
		# needs per-cell damage geometry.
		var canonical_snapshot := skill_release_snapshot
		if not _snapshot_strict_ok(canonical_snapshot):
			var canonical_origin_ground_gu := Vector2.ZERO
			if not positions.is_empty():
				canonical_origin_ground_gu = (
					_canonical_screen_px_to_ground_gu(positions[0])
				)
			var fallback_release_id := (
				release_id
				if not release_id.is_empty()
				else "wizard.fire_wall:canonical:%d" % Time.get_ticks_usec()
			)
			# The union's geometry_cells_grid_steps are ABSOLUTE grid cells
			# (same convention as the formal release snapshot producer).
			var canonical_cells := coverage_cells
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
		var field_controller := FireWallFieldControllerScript.new()
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
			_combat_spatial_index,
			current_map_id
		)
		add_child(field_controller)
		# Q2-C: the controller owns the 4 GroundSkillVisualCell presentation
		# nodes; no additional standalone GroundSkillEffect cells are spawned,
		# so the base-class enemy-group scan can never run on this path.
		return

	# Generic persistent ground effects share one canonical validation context
	# so the manager can run STRICT_V2 snapshot validation per tick.
	var generic_snapshot_validation_context := (
		_canonical_snapshot_validation_context(
			_canonical_screen_px_to_ground_gu(fallback_position)
		)
	)
	for index: int in range(positions.size()):
		_spawn_canonical_ground_effect(
			stable_skill_id,
			positions[index],
			effect,
			true,
			coverage_cells[index] if index < coverage_cells.size() else null,
			release_id,
			skill_release_snapshot,
			generic_snapshot_validation_context
		)


func _spawn_canonical_ground_effect(
	stable_skill_id: String,
	position: Vector2,
	effect: Dictionary,
	applies_damage := true,
	coverage_cell: Variant = null,
	release_id := "",
	skill_release_snapshot: Dictionary = {},
	snapshot_validation_context: Dictionary = {}
) -> void:
	var ground_effect := GroundSkillEffect.new()
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
	add_child(ground_effect)
	if applies_damage:
		_register_manager_ground_effect(
			ground_effect,
			stable_skill_id,
			release_id,
			skill_release_snapshot,
			snapshot_validation_context
		)


func _register_manager_ground_effect(
	ground_effect: GroundSkillEffect,
	stable_skill_id: String,
	release_id: String,
	skill_release_snapshot: Dictionary,
	snapshot_validation_context: Dictionary
) -> void:
	## Q2-B: the generic damage-bearing ground effect is scheduled by the
	## manager. The node keeps visuals/lifecycle only; the old per-effect
	## enemy-group scan must never run again for this node.
	ground_effect.manager_owned_damage_ticks = true
	if _ground_effect_manager == null:
		ground_effect.runtime_damage_enabled = false
		return
	_ground_effect_runtime_serial += 1
	var effect_runtime_id := _ground_effect_runtime_serial
	var runtime_map_id := int(
		skill_release_snapshot.get("runtime_map_id", current_map_id)
	)
	var registered := _ground_effect_manager.register({
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


func _manager_ground_effect_ended(reason: String, effect: Variant) -> void:
	if effect is Node and is_instance_valid(effect):
		(effect as Node).queue_free()


func _canonical_ground_cell_contains_enemy(
	enemy: EnemyActor,
	coverage_cell: Vector2i
) -> bool:
	return (
		is_instance_valid(enemy)
		and bool(CasterSpellGeometryScript.declared_cells_intersect_actor_footprint(
			[coverage_cell],
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			enemy.combat_radius_gu
		).get("intersects", false))
	)


func _ground_field_snapshot_contains_enemy(
	enemy: EnemyActor,
	skill_release_snapshot: Dictionary
) -> bool:
	if (
		not is_instance_valid(enemy)
		or not _snapshot_strict_ok(skill_release_snapshot)
	):
		return false
	return SkillFootprintSnapshotScript.intersects_target_combat_footprint_ground_gu(
		skill_release_snapshot,
		_canonical_screen_px_to_ground_gu(enemy.global_position),
		enemy.combat_radius_gu
	)


func _ignore_canonical_ground_visual_tick(
	_enemy: EnemyActor,
	_raw_power: int
) -> void:
	pass


func _apply_canonical_ground_tick(enemy: EnemyActor, raw_power: int, stable_skill_id: String) -> void:
	_combat_runtime.apply_enemy_direct_spell_damage(
		enemy,
		stable_skill_id,
		raw_power,
		player,
		_rng,
		Callable(self, "_resolve_magic_defense"),
		-1,
		_direct_spell_target_stats_scratch,
	)


func _apply_canonical_displacement_screen_px(
	actor: Node2D,
	displacement_screen_px: Vector2
) -> bool:
	if not is_instance_valid(actor):
		return false
	var destination_screen_px := actor.global_position + displacement_screen_px
	var collision_radius_px: float = (
		actor.collision_radius_px
		if actor is EnemyActor
		else ArtSpec.PLAYER_COLLISION_RADIUS_PX
	)
	if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
		background,
		destination_screen_px,
		collision_radius_px
	):
		return false
	if actor is EnemyActor:
		(actor as EnemyActor).set_combat_position(
			destination_screen_px,
			&"canonical_displacement",
		)
	else:
		actor.global_position = destination_screen_px
	return true


func _apply_canonical_player_teleport(destination: Vector2) -> bool:
	if destination == Vector2.ZERO or WorldSpatialRulesScript.environment_blocks_actor_screen_px(background, destination, ArtSpec.PLAYER_COLLISION_RADIUS_PX):
		return false
	_set_player_world_position(destination)
	player.velocity = Vector2.ZERO
	_relocate_main_pets_after_map_arrival()
	player.movement_performed.emit(player.global_position, player.facing)
	return true


func _apply_canonical_poison(target: EnemyActor, effect: Dictionary) -> void:
	var duration := float(effect.get("duration_seconds", 1))
	if str(effect.get("poison_type", "")) == "green_poison":
		target.apply_poison(
			int(effect.get("damage_per_tick", 1)),
			duration,
			float(effect.get("tick_interval_ms", 1000)) / 1000.0
		)
	else:
		var previous: Variant = target.get_meta("canonical_red_poison", {})
		var merged: Dictionary = (
			(previous as Dictionary).duplicate(true)
			if previous is Dictionary
			else {}
		)
		for key: Variant in effect:
			if not merged.has(key):
				merged[key] = effect[key]
		var flat_ac := maxi(
			int(merged.get("flat_ac_reduction", 0)),
			int(effect.get("flat_ac_reduction", 0))
		)
		var flat_mac := maxi(
			int(merged.get("flat_mac_reduction", 0)),
			int(effect.get("flat_mac_reduction", 0))
		)
		var extra_durability := maxi(
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
			Time.get_ticks_msec() + roundi(duration * 1000.0)
		)
		target.set_meta("canonical_red_poison", merged)
		RuntimeDiagnostics.increment_performance_counter(&"actor_redraw_requests")
		target.queue_redraw()


func _apply_canonical_temptation(target: EnemyActor, effect: Dictionary) -> void:
	match str(effect.get("outcome", "no_effect")):
		"rooted":
			target.apply_control(float(effect.get("duration_seconds", 1)))
		"confused", "tamed":
			target.apply_charm(float(effect.get("duration_seconds", float(effect.get("loyalty_duration_ms", 1000)) / 1000.0)))
		"instant_kill":
			_combat_runtime.apply_enemy_physical_damage(target, target.current_hp, player)


func _canonical_main_pet(summon_id: String = "") -> SummonActor:
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if (
			node is SummonActor
			and is_instance_valid(node)
			and not node.is_queued_for_deletion()
			and node.owner_player == player
			and bool(node.get_meta("taoist_main_pet", false))
			and (summon_id.is_empty() or node.summon_id == summon_id)
			and node.current_hp > 0
			and node.state not in [
				SummonActor.SummonState.EXPIRED,
				SummonActor.SummonState.DEAD,
			]
		):
			return node
	return null


func _canonical_main_pet_summon_ids() -> Array[String]:
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
	var result := {
		"contract_id": PlayerState.TAOIST_MAIN_PETS_PERSISTENCE_CONTRACT_ID,
		"slots": {},
	}
	var slots := result["slots"] as Dictionary
	# During initial bootstrap/map replacement there can be a short interval in
	# which one or both old nodes are queued. Seed from the already captured
	# document, then overwrite every currently live typed slot.
	if _world_bootstrap_in_progress or _map_transition_in_progress:
		var preserved := PlayerState.taoist_main_pet_runtime_states_for_restore()
		var preserved_slots: Variant = preserved.get("slots", {})
		if preserved_slots is Dictionary:
			slots.merge((preserved_slots as Dictionary).duplicate(true), true)
	for summon_id: String in ["skeleton", "divine_beast"]:
		var summon := _canonical_main_pet(summon_id)
		if summon == null or not summon.has_method("persistence_snapshot"):
			continue
		var snapshot: Variant = summon.persistence_snapshot()
		if snapshot is Dictionary:
			slots[summon_id] = (snapshot as Dictionary).duplicate(true)
	return result


func _on_canonical_main_pet_state_changed(
	_previous_state: int,
	current_state: int,
	summon: SummonActor
) -> void:
	if (
		current_state in [
			SummonActor.SummonState.EXPIRED,
			SummonActor.SummonState.DEAD,
		]
		and is_instance_valid(summon)
		and summon.owner_player == player
		and bool(summon.get_meta("taoist_main_pet", false))
	):
		PlayerState.clear_taoist_main_pet_runtime_state(summon.summon_id)


func _wire_canonical_main_pet_persistence(summon: SummonActor) -> void:
	summon.summon_state_changed.connect(
		Callable(self, "_on_canonical_main_pet_state_changed").bind(summon)
	)


func _restore_persisted_taoist_main_pet_if_needed() -> bool:
	if ProfessionRules.profession_id(PlayerState.profession) != "taoist":
		return false
	var restored_any := false
	for summon_id: String in ["skeleton", "divine_beast"]:
		if _canonical_main_pet(summon_id) != null:
			continue
		var snapshot := PlayerState.taoist_main_pet_runtime_state_for_restore(
			summon_id
		)
		if snapshot.is_empty() or not bool(snapshot.get("alive", false)):
			continue
		var stable_skill_id := str(snapshot.get("skill_id", ""))
		if _summon_id_for_skill(stable_skill_id) != summon_id:
			PlayerState.clear_taoist_main_pet_runtime_state(summon_id)
			continue
		var spawn_plan := _canonical_summon_spawn_plan(stable_skill_id)
		if not bool(spawn_plan.get("valid", false)):
			continue
		var summon := SummonActor.new()
		summon.setup(
			player,
			"神兽" if summon_id == "divine_beast" else "骷髅",
			maxi(1, _canonical_primary_stat_roll("taoist")),
			maxi(0, int(snapshot.get("skill_rank", 0))),
			stable_skill_id,
			maxi(1, int(snapshot.get("owner_level", PlayerState.level))),
			int(snapshot.get("maximum_pet_level", -1))
		)
		if not summon.restore_persistence_snapshot(snapshot):
			summon.free()
			PlayerState.clear_taoist_main_pet_runtime_state(summon_id)
			continue
		summon.set_meta("taoist_main_pet", true)
		summon.set_meta("taoist_main_pet_contract", "skills.taoist_main_pet.v2")
		summon.configure_runtime_map_projection(
			current_map_id,
			Callable(self, "_canonical_ground_gu_to_screen_px"),
			Callable(self, "_canonical_screen_px_to_ground_gu")
		)
		summon.configure_spatial_index(_combat_spatial_index)
		summon.global_position = spawn_plan.get(
			"position_screen_px", player.global_position
		) as Vector2
		summon.configure_spawn_release_footprint(
			"restore:%s:%d" % [stable_skill_id, Time.get_ticks_msec()]
		)
		_wire_canonical_main_pet_persistence(summon)
		add_child(summon)
		restored_any = true
	if restored_any:
		PlayerState.apply_taoist_main_pet_runtime_states(
			_capture_taoist_main_pet_runtime_states()
		)
	return restored_any


func _canonical_friendly_actor(instance_id: int) -> Node2D:
	if instance_id <= 0:
		return null
	var actor := instance_from_id(instance_id)
	if not actor is Node2D or not is_instance_valid(actor):
		return null
	if actor == player:
		return player
	if actor is SummonActor and actor.owner_player == player:
		return actor as SummonActor
	return null


func _apply_canonical_friendly_heal(actor: Node2D, amount: int) -> int:
	if not is_instance_valid(actor) or amount <= 0:
		return 0
	if actor == player:
		var hp_before := player.current_hp
		player.restore_health(amount)
		return maxi(0, player.current_hp - hp_before)
	elif actor is SummonActor:
		return (actor as SummonActor).restore_health(amount)
	return 0


func _register_ongoing_heal(
	target_instance_id: int,
	heal_per_tick: int,
	tick_count: int,
	tick_interval_seconds: float
) -> void:
	if target_instance_id <= 0 or heal_per_tick <= 0 or tick_count <= 0:
		return
	_ongoing_heals.append({
		"target_instance_id": target_instance_id,
		"heal_per_tick": heal_per_tick,
		"remaining_ticks": tick_count,
		"tick_interval_seconds": maxf(0.1, tick_interval_seconds),
		"elapsed": 0.0,
	})


func _tick_ongoing_heals(delta: float) -> void:
	if _ongoing_heals.is_empty():
		return
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _ongoing_heals:
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		var interval := float(entry.get("tick_interval_seconds", 0.8))
		while float(entry.get("elapsed", 0.0)) >= interval:
			entry["elapsed"] = float(entry.get("elapsed", 0.0)) - interval
			var remaining := int(entry.get("remaining_ticks", 0)) - 1
			entry["remaining_ticks"] = remaining
			var actor := _canonical_friendly_actor(
				int(entry.get("target_instance_id", 0))
			)
			if not is_instance_valid(actor):
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
	_ongoing_heals = keep


func _ongoing_heal_remaining_ticks(target_instance_id: int) -> int:
	var total := 0
	for entry: Dictionary in _ongoing_heals:
		if int(entry.get("target_instance_id", 0)) == target_instance_id:
			total += int(entry.get("remaining_ticks", 0))
	return total


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
	var entries: Array[String] = []
	var defence_snapshot := player.defence_buff_snapshot()
	if player.is_stealthed():
		entries.append("隐身 %ds" % int(ceil(maxf(0.0, player.stealth_time))))
	var heal_ticks := _ongoing_heal_remaining_ticks(player.get_instance_id())
	if heal_ticks > 0:
		entries.append("恢复 %ds" % int(ceil(float(heal_ticks) * 0.8)))
	var hint_text := "%s|%d|%d|%d|%d" % [
		"｜".join(entries),
		int(defence_snapshot.get("ac_bonus", 0)),
		int(ceil(float(defence_snapshot.get("ac_remaining_seconds", 0.0)))),
		int(defence_snapshot.get("mac_bonus", 0)),
		int(ceil(float(defence_snapshot.get("mac_remaining_seconds", 0.0)))),
	]
	if hint_text == _last_taoist_buff_hint_text:
		return
	_last_taoist_buff_hint_text = hint_text
	hud.update_taoist_buff_hints(entries, defence_snapshot)


func _canonical_friendly_candidates() -> Array:
	## Candidate pool contract: the caster plus alive, owned, non-queued
	## SummonActors. Positions use the formal map projection.
	var result: Array = []
	if not is_instance_valid(player):
		return result
	result.append(TaoistSupportPolicyScript.make_candidate(
		player.get_instance_id(),
		true,
		player.current_hp,
		player.max_hp,
		_canonical_screen_px_to_ground_gu(player.global_position),
		PlayerState.level,
		"self"
	))
	for node: Node in get_tree().get_nodes_in_group("summons"):
		if not node is SummonActor:
			continue
		var summon := node as SummonActor
		if (
			summon.is_queued_for_deletion()
			or summon.owner_player != player
			or summon.current_hp <= 0
		):
			continue
		result.append(TaoistSupportPolicyScript.make_candidate(
			summon.get_instance_id(),
			false,
			summon.current_hp,
			summon.max_hp,
			_canonical_screen_px_to_ground_gu(summon.global_position),
			maxi(1, summon.owner_level),
			"summon"
		))
	return result


func _select_taoist_heal_target(center_ground_gu: Vector2) -> Dictionary:
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
	## Release-time validation of the identity recorded at input. On failure it
	## reselects exactly once via the same pure policy; a missing result means
	## no canonical plan and no MP commit. The recorded target stays
	## authoritative only while it is still the policy's current best; once it
	## became full while another friendly is injured (or left range / died),
	## the release reselects exactly once. Full-HP pools still resolve validly
	## with self preferred (user override 2026-08-09).
	if requested_instance_id > 0:
		var current_best := TaoistSupportPolicyScript.select_heal_target(
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
	var selection := TaoistSupportPolicyScript.select_heal_target(
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
	actor: Node2D,
	stat: String,
	value: int,
	duration_seconds: float,
	buff_id: String
) -> void:
	if not is_instance_valid(actor) or value <= 0:
		return
	if stat == "MAC":
		if actor == player:
			player.apply_mac_buff(duration_seconds, value)
		elif actor is SummonActor:
			(actor as SummonActor).apply_mac_buff(
				value,
				duration_seconds,
				buff_id
			)
	else:
		if actor == player:
			player.apply_ac_buff(duration_seconds, value)
		elif actor is SummonActor:
			(actor as SummonActor).apply_ac_buff(
				value,
				duration_seconds,
				buff_id
			)


func _apply_friendly_stealth_to_actor(
	actor: Node2D,
	duration_seconds: float,
	buff_id: String
) -> void:
	if not is_instance_valid(actor):
		return
	if actor == player:
		player.apply_stealth(duration_seconds)
	elif actor is SummonActor:
		(actor as SummonActor).apply_stealth(
			duration_seconds,
			buff_id
		)


func _apply_canonical_main_pet(
	descriptor: Dictionary,
	stable_skill_id: String,
	release_id: String
) -> void:
	var operation := str(descriptor.get("operation", ""))
	if operation not in [
		"recall_existing_main_pet",
		"main_pet_spawn",
		"summon",
	]:
		return
	var requested_summon_id := str(
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
	var descriptor_snapshot_id := str(
		descriptor.get("spawn_snapshot_id", "")
	)
	var descriptor_map_id := int(
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
	var spawn_screen_px := _canonical_ground_gu_to_screen_px(spawn_ground_gu)
	var summon_radius_gu := float(
		spawn_snapshot.get(
			"target_combat_radius_gu",
			WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
				21.0
				if requested_summon_id == "divine_beast"
				else 15.0
			)
		)
	)
	var existing := _canonical_main_pet(requested_summon_id)
	if operation == "recall_existing_main_pet":
		if existing == null or not _canonical_summon_position_is_valid(
			spawn_ground_gu,
			summon_radius_gu,
			existing
		):
			return
		existing.global_position = spawn_screen_px
		existing.configure_spawn_release_footprint(release_id)
		existing.set_meta(
			"canonical_spawn_footprint_snapshot",
			spawn_snapshot.duplicate(true)
		)
		return
	if existing != null or not bool(descriptor.get("spawned", false)):
		return
	if not _canonical_summon_position_is_valid(
		spawn_ground_gu,
		summon_radius_gu,
		null
	):
		return
	var summon_name := (
		"神兽"
		if requested_summon_id == "divine_beast"
		else "骷髅"
	)
	var summon := SummonActor.new()
	summon.setup(
		player,
		summon_name,
		maxi(1, _canonical_primary_stat_roll("taoist")),
		int(descriptor.get("initial_pet_level", 0)),
		stable_skill_id,
		PlayerState.level,
		int(descriptor.get("max_pet_level", -1))
	)
	summon.set_meta("taoist_main_pet", true)
	summon.set_meta("taoist_main_pet_contract", "skills.taoist_main_pet.v2")
	summon.configure_runtime_map_projection(
		current_map_id,
		Callable(self, "_canonical_ground_gu_to_screen_px"),
		Callable(self, "_canonical_screen_px_to_ground_gu")
	)
	summon.configure_spatial_index(_combat_spatial_index)
	summon.global_position = spawn_screen_px
	summon.configure_spawn_release_footprint(release_id)
	summon.set_meta(
		"canonical_spawn_footprint_snapshot",
		spawn_snapshot.duplicate(true)
	)
	_wire_canonical_main_pet_persistence(summon)
	add_child(summon)
	PlayerState.apply_taoist_main_pet_runtime_states(
		_capture_taoist_main_pet_runtime_states()
	)


func _relocate_main_pets_after_map_arrival() -> void:
	# _load_zone restores pets before the caller installs its final arrival.
	# Reuse the canonical legal-position search, excluding only the moving pet.
	for summon_id: String in ["skeleton", "divine_beast"]:
		var summon := _canonical_main_pet(summon_id)
		if summon == null:
			continue
		summon.configure_runtime_map_projection(
			current_map_id,
			Callable(self, "_canonical_ground_gu_to_screen_px"),
			Callable(self, "_canonical_screen_px_to_ground_gu"),
		)
		summon.configure_spatial_index(_combat_spatial_index)
		var stable_skill_id := (
			"taoist.summon_skeleton" if summon_id == "skeleton"
			else "taoist.summon_divine_beast"
		)
		var plan := _canonical_summon_spawn_plan(stable_skill_id, summon)
		if bool(plan.get("valid", false)):
			summon.relocate_after_owner_teleport(plan.get("position_screen_px") as Vector2)


func _canonical_summon_spawn_plan(
	stable_skill_id: String,
	ignored_summon: SummonActor = null,
) -> Dictionary:
	if not is_instance_valid(player):
		return {"valid": false, "reason": "player_unavailable"}
	var player_ground_gu := _canonical_screen_px_to_ground_gu(
		player.global_position
	)
	var facing_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			player.facing
		).normalized()
	)
	if (
		facing_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		facing_ground_gu = Vector2(1.0, 1.0).normalized()
	var side_direction_ground_gu := Vector2(
		-facing_ground_gu.y,
		facing_ground_gu.x
	)
	var summon_offset_gu := (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			42.0
		)
	)
	var desired_ground_gu := (
		player_ground_gu + side_direction_ground_gu * summon_offset_gu
	)
	var center_tile := Vector2i(
		roundi(desired_ground_gu.x),
		roundi(desired_ground_gu.y)
	)
	var candidates: Array[Vector2i] = []
	for offset_y: int in range(-2, 3):
		for offset_x: int in range(-2, 3):
			var candidate_tile := center_tile + Vector2i(offset_x, offset_y)
			if Vector2(candidate_tile).distance_to(desired_ground_gu) <= (
				CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU
				+ GroundUnitSpaceScript.EPSILON_GU
			):
				candidates.append(candidate_tile)
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		var a_distance := Vector2(a).distance_squared_to(desired_ground_gu)
		var b_distance := Vector2(b).distance_squared_to(desired_ground_gu)
		if not is_equal_approx(a_distance, b_distance):
			return a_distance < b_distance
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x
	)
	var summon_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			21.0
			if stable_skill_id == "taoist.summon_divine_beast"
			else 15.0
		)
	)
	for candidate_tile: Vector2i in candidates:
		var candidate_ground_gu := Vector2(candidate_tile)
		if not _canonical_summon_position_is_valid(
			candidate_ground_gu,
			summon_radius_gu,
			ignored_summon
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
		"position_screen_px": player.global_position,
		"desired_ground_gu": desired_ground_gu,
		"search_radius_gu": CANONICAL_SUMMON_SPAWN_SEARCH_RADIUS_GU,
	}


func _canonical_summon_position_is_valid(
	candidate_ground_gu: Vector2,
	summon_radius_gu: float,
	ignored_summon: SummonActor
) -> bool:
	if not candidate_ground_gu.is_finite():
		return false
	var candidate_screen_px := _canonical_ground_gu_to_screen_px(
		candidate_ground_gu
	)
	if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
		background,
		candidate_screen_px,
		WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(
			summon_radius_gu
		)
	):
		return false
	if is_instance_valid(player) and player != ignored_summon:
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(player.global_position),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ _actor_combat_radius_gu(player)
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	var enemy_query_radius_gu := (
		summon_radius_gu
		+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
	)
	if not _target_spatial_query_aabb_into(
		Rect2(
			candidate_ground_gu - Vector2.ONE * enemy_query_radius_gu,
			Vector2.ONE * enemy_query_radius_gu * 2.0,
		),
		_target_spatial_query_scratch,
	):
		return false
	for enemy: EnemyActor in _target_spatial_query_scratch:
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(enemy.global_position),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ enemy.combat_radius_gu
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	for raw_summon: Variant in get_tree().get_nodes_in_group("summons"):
		if (
			not raw_summon is Node2D
			or not is_instance_valid(raw_summon)
			or raw_summon == ignored_summon
			or raw_summon.is_queued_for_deletion()
		):
			continue
		var summon := raw_summon as Node2D
		if GroundUnitSpaceScript.distance_gu(
			_canonical_screen_px_to_ground_gu(summon.global_position),
			candidate_ground_gu
		) < (
			summon_radius_gu
			+ _actor_combat_radius_gu(summon)
			+ CANONICAL_SUMMON_ACTOR_CLEARANCE_GU
		):
			return false
	return true


func _summon_spawn_screen_position_px() -> Vector2:
	var spawn_plan := _canonical_summon_spawn_plan(
		"taoist.summon_skeleton"
	)
	return spawn_plan.get("position_screen_px", player.global_position)


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
	var profile := _resolve_projection_profile_for_map(map_id)
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
	var profile := _resolve_projection_profile_for_map(current_map_id)
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
		var unmapped_ground_gu := (
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
	## FREEZE-P0.2R: formal runtime profile in normal gameplay; reference
	## profile only inside an explicit reference_audit_mode context (migration /
	## import audit / test-dev preview). Never inferred from WorldContent.
	if _projection_profile_cache_audit_mode != reference_audit_mode:
		_projection_profile_cache.clear()
		_projection_profile_runtime_identity_cache.clear()
		_projection_profile_cache_audit_mode = reference_audit_mode
	var cache_key := "%d|%d" % [
		map_id,
		1 if reference_audit_mode else 0,
	]
	var profile: Dictionary
	if reference_audit_mode:
		_projection_profile_runtime_identity_cache.clear()
		if _projection_profile_cache.has(cache_key):
			return _projection_profile_cache[cache_key]
		profile = MapCoordinateMapperScript.resolve_reference_projection_profile(
			map_id
		)
	else:
		var runtime_identity := MapEditorRuntimeBridgeScript.load_map(map_id)
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
		profile = MapCoordinateMapperScript.resolve_formal_runtime_projection_profile(
			map_id
		)
		_projection_profile_runtime_identity_cache[cache_key] = runtime_identity
	_projection_profile_cache[cache_key] = profile
	return profile


func _try_canonical_screen_px_to_ground_gu(
	screen_position_px: Vector2
) -> Dictionary:
	## FREEZE-P0.2R: explicit fail-closed result driven by the current map's
	## projection profile (formal runtime in normal gameplay; reference profile
	## only inside an explicit reference_audit_mode context). Never falls back
	## to identity/delta for a mapped id.
	var profile := _resolve_projection_profile_for_map(current_map_id)
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
	var profile := _resolve_projection_profile_for_map(current_map_id)
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
	var result := _try_canonical_screen_px_to_ground_gu(screen_position_px)
	if bool(result.get("success", false)):
		return result.get("value", Vector2.ZERO)
	return Vector2.INF


func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2:
	var result := _try_canonical_ground_gu_to_screen_px(ground_position_gu)
	if bool(result.get("success", false)):
		return result.get("value", Vector2.ZERO)
	return Vector2.INF


func _canonical_grid_cell_to_screen_px(grid_cell: Variant) -> Vector2:
	var tile := Vector2i(grid_cell) if grid_cell is Vector2i else Vector2i.ZERO
	var profile := _resolve_projection_profile_for_map(current_map_id)
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
	var context := _canonical_snapshot_absolute_context(origin_ground_gu)
	context["expected_runtime_map_id"] = current_map_id
	return context


func _snapshot_strict_ok(snapshot: Dictionary) -> bool:
	var origin := Vector2.ZERO
	if is_instance_valid(player):
		origin = _canonical_screen_px_to_ground_gu(player.global_position)
	return bool(SkillFootprintSnapshotScript.validate_for_consumer(
		snapshot,
		_canonical_snapshot_validation_context(origin),
		SkillFootprintSnapshotScript.VALIDATION_STRICT_V2
	).get("valid", false))


func _canonical_facing(direction: Vector2) -> Vector2i:
	if direction.length_squared() < 0.01:
		return Vector2i.DOWN
	return Vector2i(signi(roundi(direction.x)), signi(roundi(direction.y)))


func _canonical_facing_for_skill(skill_id: String, direction: Vector2) -> Vector2i:
	if skill_id in ["warrior.thrusting", "warrior.half_moon", "warrior.fire_sword"]:
		return WarriorMeleeGeometryScript.facing_tile_step(ArtSpec.direction_index(direction))
	if skill_id in CANONICAL_WIZARD_GEOMETRY_SKILLS:
		return CasterSpellGeometryScript.canonical_facing_grid_step_from_screen_direction_px(
			direction
		)
	return _canonical_facing(direction)


func _canonical_primary_stat_roll(profession_id: String) -> int:
	var minimum_key := "tao_min" if profession_id == "taoist" else ("magic_min" if profession_id == "wizard" else "attack_min")
	var maximum_key := "tao_max" if profession_id == "taoist" else ("magic_max" if profession_id == "wizard" else "attack_max")
	var minimum := int(PlayerState.computed_stats.get(minimum_key, 0))
	var maximum := maxi(minimum, int(PlayerState.computed_stats.get(maximum_key, minimum)))
	return _rng.randi_range(minimum, maximum)


func _next_canonical_seed() -> int:
	_canonical_cast_serial += 1
	return hash([Time.get_ticks_msec(), _canonical_cast_serial, PlayerState.active_profile_id])


func _next_skill_footprint_release_id(stable_skill_id: String) -> String:
	_skill_footprint_release_serial += 1
	return "player:%d:skill:%s:release:%d" % [
		player.get_instance_id() if is_instance_valid(player) else 0,
		stable_skill_id,
		_skill_footprint_release_serial,
	]


func _skill_needs_target(cast_type: String) -> bool:
	return cast_type not in ["passive", "heal", "heal_area", "shield", "stealth", "stealth_area", "magic_defense_buff", "defense_buff", "summon", "teleport"]


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
	var stable_skill_id := SkillDataLoaderScript.stable_skill_id(source_skill_id)
	var formal_maximum_distance_gu := maxf(0.0, maximum_distance_gu)
	if not stable_skill_id.is_empty():
		var definition := SkillDataLoaderScript.skill(stable_skill_id)
		var configured_maximum_distance_gu := float(
			definition.get("geometry", {}).get("maximum_range_gu", 0.0)
		)
		if configured_maximum_distance_gu > 0.0:
			formal_maximum_distance_gu = configured_maximum_distance_gu
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	if (
		direction_ground_gu.length_squared()
		<= GroundUnitSpaceScript.EPSILON_GU * GroundUnitSpaceScript.EPSILON_GU
	):
		direction_ground_gu = Vector2(1.0, -1.0).normalized()
	var visual_direction_screen_px := direction_screen_px.normalized()
	if visual_direction_screen_px.length_squared() <= 0.000001:
		visual_direction_screen_px = (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground_gu
			).normalized()
		)
	var projectile := SkillProjectile.new()
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
	projectile.configure_spatial_index(_combat_spatial_index)
	projectile.configure_runtime_resolution(player, Callable(self, "_resolve_magic_defense"))
	add_child(projectile)


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
	var context_skill_id := source_skill_id if not source_skill_id.is_empty() else "legacy_damage"
	RuntimeDiagnostics.set_performance_release_context(
		"legacy_damage",
		context_skill_id,
	)
	RuntimeDiagnostics.increment_performance_counter(&"aoe_release_count")
	var aoe_candidate_started_usec := RuntimeDiagnostics.timing_start()
	var hit_any := false
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin_screen_px)
	var direction_ground_gu := (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	var release_cache: Dictionary = {}
	var plan := query_plan
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
	var pass_result := _aoe_apply_legacy_damage_candidates(
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
	var defense_min := int(
		target_stats.get(
			"magic_defense_min",
			target_stats.get("mdefMin", target_stats.get("MinMAC", 0))
		)
	)
	var defense_max := int(
		target_stats.get(
			"magic_defense_max",
			target_stats.get("mdefMax", target_stats.get("MaxMAC", defense_min))
		)
	)
	defense_min = maxi(0, defense_min)
	defense_max = maxi(defense_min, defense_max)
	return maxi(0, damage_after_anti_magic - _rng.randi_range(defense_min, defense_max))


func _combat_release_target(release_geometry: Dictionary) -> EnemyActor:
	var target_instance_id := int(release_geometry.get("locked_target_instance_id", 0))
	if target_instance_id <= 0 or not bool(
		release_geometry.get("locked_target_valid_at_release", false)
	):
		return null
	var candidate := instance_from_id(target_instance_id)
	if (
		not candidate is EnemyActor
		or not is_instance_valid(candidate)
		or candidate.is_queued_for_deletion()
		or candidate.current_hp <= 0
	):
		return null
	return candidate as EnemyActor


func _create_melee_release_footprint_snapshot(
	origin_screen_px: Vector2,
	direction_screen_px: Vector2,
	mode: String,
	release_geometry: Dictionary = {}
) -> Dictionary:
	var skill_id: String = {
		WarriorMeleeGeometryScript.SKILL_THRUST: "warrior.thrusting",
		WarriorMeleeGeometryScript.SKILL_HALF_MOON: "warrior.half_moon",
		WarriorMeleeGeometryScript.SKILL_FIRE: "warrior.fire_sword",
	}.get(mode, "warrior.normal_attack")
	var release_id := str(release_geometry.get("release_id", ""))
	if release_id.is_empty():
		release_id = _next_skill_footprint_release_id(skill_id)
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin_screen_px)
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
		var plan := WarriorMeleeGeometryScript.target_aligned_melee_release_plan_ground_gu(
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
	mode := "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> EnemyActor:
	var targets := _physical_primary_targets(
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
	mode := "normal",
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	# The attack lock owns facing and priority only. Actual damage rights are
	# rebuilt from live footpoints and the selected melee geometry at release.
	# This deliberately overrides the single-target candidate filter used by
	# caster projectiles without changing their shared release contract.
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var direction_index := _melee_direction_index(direction, release_geometry)
	var resolved_target_plan: Dictionary = target_aligned_plan
	if resolved_target_plan.is_empty():
		resolved_target_plan = release_geometry.get("target_aligned_plan", {})
	var release_cache: Dictionary = {}
	var plan := query_plan
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
	var broadphase_ready := _aoe_plan_is_ready(plan)
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
	targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	release_geometry: Dictionary
) -> void:
	var locked_instance_id := int(release_geometry.get("locked_target_instance_id", 0))
	if (
		locked_instance_id <= 0
		and is_instance_valid(locked_target)
		and _is_attack_target_in_range(locked_target)
	):
		locked_instance_id = locked_target.get_instance_id()
	var ordered: Array[EnemyActor] = []
	var ordered_distances: Array[float] = []
	var ordered_ids: Array[int] = []
	for enemy: EnemyActor in targets:
		var enemy_id := enemy.get_instance_id()
		var enemy_distance_gu := GroundUnitSpaceScript.distance_gu(
			origin_ground_gu,
			_canonical_screen_px_to_ground_gu(enemy.global_position),
		)
		var enemy_locked := enemy_id == locked_instance_id
		var insert_at := ordered.size()
		for index: int in range(ordered.size()):
			var existing_locked := ordered_ids[index] == locked_instance_id
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
	enemy: EnemyActor,
	origin_ground_gu: Vector2,
	direction_index: int,
	mode: String,
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> bool:
	if not is_instance_valid(enemy) or enemy.is_queued_for_deletion() or enemy.current_hp <= 0:
		return false
	var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
	var query_context: Dictionary = query_plan.get(
		"validation_context_reference",
		_canonical_snapshot_validation_context(origin_ground_gu),
	)
	var validated_plan_ready := _aoe_plan_is_ready(query_plan)
	var target_plan: Dictionary = target_aligned_plan
	if not target_plan.is_empty():
		if not bool(target_plan.get("target_axis_eligible", false)):
			return false
		var target_aligned_sector := _aoe_target_aligned_melee_sector(
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


func _apply_physical_hit(enemy: EnemyActor, damage: int, accuracy_bonus := 0) -> bool:
	if (
		enemy == null
		or enemy.is_queued_for_deletion()
		or not enemy.can_receive_damage()
	):
		return false
	var accuracy := int(
		PlayerState.computed_stats.get("accuracy", WarriorCombatMath.BASE_HIT)
	) + accuracy_bonus
	var target_agility := maxi(1, enemy.agility)
	var diagnostics_enabled := CombatDiagnosticLogScript.capture_enabled()
	var hit_roll := -1
	var hit_probability := (
		WarriorCombatMath.hit_probability(accuracy, target_agility)
		if diagnostics_enabled
		else 0.0
	)
	if not PlayerState.test_mode:
		hit_roll = _rng.randi_range(0, target_agility - 1)
		if not WarriorCombatMath.hit_succeeds(accuracy, target_agility, hit_roll):
			if diagnostics_enabled:
				_active_physical_hit_diagnostics.append({
					"target_id": enemy.get_instance_id(),
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
	var hp_before := enemy.current_hp
	if not _combat_runtime.apply_enemy_physical_damage(enemy, maxi(1, damage), player):
		if diagnostics_enabled:
			_active_physical_hit_diagnostics.append({
				"target_id": enemy.get_instance_id(),
				"target_name": enemy.display_name,
				"accuracy": accuracy,
				"accuracy_bonus": accuracy_bonus,
				"target_agility": target_agility,
				"hit_roll": hit_roll,
				"hit_probability": hit_probability,
				"test_mode_bypass": PlayerState.test_mode,
				"requested_damage": maxi(1, damage),
				"hp_before": hp_before,
				"hp_after": enemy.current_hp,
				"result_code": "DAMAGE_COMMIT_FAILED",
			})
		return false
	if diagnostics_enabled:
		_active_physical_hit_diagnostics.append({
			"target_id": enemy.get_instance_id(),
			"target_name": enemy.display_name,
			"accuracy": accuracy,
			"accuracy_bonus": accuracy_bonus,
			"target_agility": target_agility,
			"hit_roll": hit_roll,
			"hit_probability": hit_probability,
			"test_mode_bypass": PlayerState.test_mode,
			"requested_damage": maxi(1, damage),
			"hp_before": hp_before,
			"hp_after": enemy.current_hp,
			"actual_hp_delta": maxi(0, hp_before - enemy.current_hp),
			"result_code": "HIT_COMMITTED",
		})
	var life_steal_percent := int(PlayerState.computed_stats.get("life_steal_percent", 0))
	var recovered := int(float(maxi(1, damage)) * float(life_steal_percent) / 100.0)
	if recovered >= 2:
		player.restore_health(recovered)
	if PlayerState.has_special_effect("paralysis") and EquipmentRulesScript.paralysis_succeeds(enemy.anti_poison, _rng.randi_range(0, maxi(1, enemy.anti_poison + 5) - 1)):
		enemy.apply_control(5.0)
	return true


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
	var query_context: Dictionary = query_plan.get(
		"validation_context_reference",
		release_geometry.get(
			"snapshot_validation_context",
			_canonical_snapshot_validation_context(origin_ground_gu),
		),
	)
	var axis_plan := thrust_damage_axis_plan
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
	for enemy: EnemyActor in candidates:
		if (
			not is_instance_valid(enemy)
			or excluded_targets.has(enemy)
			or enemy.is_queued_for_deletion()
			or enemy.current_hp <= 0
		):
			continue
		var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		var slot := (
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
	candidates: Array[EnemyActor],
	result: Array[EnemyActor],
	excluded_targets: Array[EnemyActor],
	origin_ground_gu: Vector2,
	direction_index: int,
	target_plan: Dictionary,
	query_plan: Dictionary,
	release_geometry: Dictionary,
) -> void:
	for enemy: EnemyActor in candidates:
		if (
			not is_instance_valid(enemy)
			or excluded_targets.has(enemy)
			or enemy.is_queued_for_deletion()
			or enemy.current_hp <= 0
		):
			continue
		var target_ground_gu := _canonical_screen_px_to_ground_gu(enemy.global_position)
		var sector := -1
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
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {},
	thrust_damage_axis_plan: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	target_aligned_plan: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var target_plan: Dictionary = target_aligned_plan if not target_aligned_plan.is_empty() else release_geometry.get("target_aligned_plan", {})
	var direction_index := _melee_direction_index(direction, release_geometry)
	var release_cache: Dictionary = {}
	var plan := query_plan
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
	var broadphase_ready := _aoe_plan_is_ready(plan)
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
	excluded_targets: Array[EnemyActor],
	release_geometry: Dictionary = {},
	melee_release_snapshot: Dictionary = {},
	query_plan: Dictionary = {},
) -> Array[EnemyActor]:
	var result: Array[EnemyActor] = []
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(origin)
	var target_plan: Dictionary = release_geometry.get("target_aligned_plan", {})
	var direction_index := _melee_direction_index(direction, release_geometry)
	var release_cache: Dictionary = {}
	var plan := query_plan
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
	var broadphase_ready := _aoe_plan_is_ready(plan)
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
	# Compatibility/test entrypoint. Production reaches the same planner through
	# the canonical skill router; input direction and rank cannot alter geometry.
	var target := _select_wild_rush_target()
	if target == null:
		return false
	var plan := _build_wild_rush_path_plan(target)
	var resolved_distance_gu := float(plan.get("resolved_push_distance_gu", 0.0))
	return _apply_wild_rush_displacement(
		target,
		{
			"resolved_push_distance_gu": resolved_distance_gu,
			"displaced": resolved_distance_gu > 0.0,
		},
		plan
	)


func _show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	# Removed: the prototype drew a three-point V on every attack and also
	# overlaid the final Magic.wil skill effects.  Finished combat art is owned
	# by PlayerVisual; attacks without formal art deliberately show no fallback.
	return


func _on_enemy_died(enemy: EnemyActor, monster_data: Dictionary) -> void:
	var queued_at_usec := RuntimeDiagnostics.timing_start()
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
	var progressed := false
	var slice_started_usec := RuntimeDiagnostics.timing_start()
	var budget_usec := _death_drop_work_budget_usec()
	var jobs_limit := _death_jobs_max_per_frame()
	var nodes_limit := _drop_nodes_max_per_frame()
	if force_synchronous:
		budget_usec = 2147483647
		jobs_limit = 2147483647
		nodes_limit = 2147483647
	if _enemy_death_target_refresh_pending:
		_enemy_death_target_refresh_pending = false
		RuntimeDiagnostics.increment_performance_counter(&"death_target_refresh_count")
		if is_inside_tree():
			_refresh_target_highlights()
			if is_instance_valid(hud):
				_update_target_hud()
		progressed = true
	_compact_enemy_death_queue()
	if _pending_enemy_deaths.is_empty():
		_enemy_death_pipeline_running = false
		return progressed
	var jobs_processed := 0
	var nodes_processed := 0
	if str(_pending_enemy_deaths[0].get("state", "")) == DEATH_STATE_RETRY:
		var retry_item: Dictionary = _pending_enemy_deaths[0]
		if force_synchronous or _death_retry_ready(retry_item):
			retry_item["retry_at_msec"] = 0
			_set_enemy_death_state(retry_item, DEATH_STATE_QUEUED)
			progressed = true
	if str(_pending_enemy_deaths[0].get("state", "")) == DEATH_STATE_QUEUED:
		if (
			(force_synchronous or _death_retry_ready(_pending_enemy_deaths[0]))
			and (
				force_synchronous
				or jobs_processed == 0
				or RuntimeDiagnostics.timing_elapsed_usec(slice_started_usec) < budget_usec
			)
		):
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
	while not _pending_enemy_deaths.is_empty():
		if (
			not force_synchronous
			and progressed
			and RuntimeDiagnostics.timing_elapsed_usec(slice_started_usec) >= budget_usec
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
			if _settle_pending_enemy_death_batch(jobs_limit - jobs_processed):
				jobs_processed += _death_settled_jobs_last_batch
				progressed = true
				_compact_enemy_death_queue()
				continue
			break
		if state == DEATH_STATE_SETTLING:
			if jobs_processed >= jobs_limit:
				break
			jobs_processed += 1
			if _plan_enemy_death_item(death):
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
	_enemy_death_pipeline_running = false
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
	return {
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



func _settle_pending_enemy_death_batch(
	max_deaths := DEATH_JOBS_MAX_PER_FRAME,
) -> bool:
	_death_settled_jobs_last_batch = 0
	if _pending_enemy_deaths.is_empty():
		return false
	if max_deaths <= 0:
		return false
	var first: Dictionary = _pending_enemy_deaths[0]
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
	for death: Dictionary in _pending_enemy_deaths:
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
		PlayerState.monster_respawn_state_for_restore()
	)
	for death: Dictionary in batch:
		var respawn_preparation := _prepare_queued_enemy_respawn(death)
		death["respawn_preparation"] = respawn_preparation
		var respawn: Dictionary = death.get("respawn", {})
		respawn["preparation"] = respawn_preparation
		death["respawn"] = respawn
		settlements.append({
			"monster_name": str(death.get("monster_name", "")),
			"experience": int(death.get("experience", 0)),
		})
	var settlement_started_usec := RuntimeDiagnostics.timing_start()
	var settlement := PlayerState.record_kills_and_experience_batch(
		settlements,
		true,
	)
	RuntimeDiagnostics.record_timing_usec(
		&"death_settlement_usec", settlement_started_usec
	)
	if not bool(settlement.get("success", false)):
		# Respawn state, quest progress and experience are one save boundary. A
		# failed save restores the pre-attempt state, and the death item remains
		# observable for retry/terminal handling; no drop roll is performed.
		PlayerState.world_monster_respawn_state = respawn_state_before
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
		return true
	for death: Dictionary in batch:
		death["transaction_result"] = settlement.duplicate(true)
		_plan_enemy_death_item(death)
	return true


func _plan_enemy_death_item(death: Dictionary) -> bool:
	if not _death_origin_matches_current(death):
		death["last_error"] = "origin_map_generation_mismatch_before_roll"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		RuntimeDiagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return true
	var started_usec := RuntimeDiagnostics.timing_start()
	var monster_id := int(death.get("monster_id", -1))
	RuntimeDiagnostics.increment_performance_counter(&"drop_roll_count")
	var drop_roll := LootRuntime.roll_monster_drops(monster_id, _rng, false)
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
			and RuntimeDiagnostics.timing_elapsed_usec(slice_started_usec) >= budget_usec
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
		var materialized := false
		if request.has("gold_amount"):
			materialized = _spawn_gold_loot(
				int(request.get("gold_amount", 0)),
				request.get("position", death.get("death_position", Vector2.ZERO)),
			)
		else:
			materialized = _spawn_loot(
				str(request.get("item_name", "")),
				request.get("position", death.get("death_position", Vector2.ZERO)),
				request.get("item_record", {}),
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
	_respawn_later(
		canonical_monster,
		death.get("spawn_position", death.get("death_position", Vector2.ZERO)),
		bool(respawn.get("was_boss", death.get("was_boss", false))),
		float(preparation.get("wait_seconds", 0.0)),
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


func _prepare_queued_enemy_respawn(death: Dictionary) -> Dictionary:
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
	var respawn_marked := PlayerState.mark_monster_respawn_dead(
		respawn_runtime_map_id,
		spawn_slot_id,
		monster_id,
		str(policy.get("policy_id", "")),
		Time.get_unix_time_from_system() + respawn_wait_seconds
	)
	if not respawn_marked:
		push_error(
			"Monster respawn state rejected unstable slot monster_id=%d map_id=%d slot=%s"
			% [monster_id, respawn_runtime_map_id, spawn_slot_id]
		)
		return {"valid": false, "reason": "unstable_respawn_slot"}
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
	}


func _spawn_loot(item_name: String, position: Vector2, item_record: Dictionary = {}) -> bool:
	# A formal but unresolved identity must never become an unrelated valid
	# name-only item at collection time. Legacy callers still pass no record.
	if not item_record.is_empty() and str(item_record.get("identity_status", "")) != "resolved":
		return false
	if _test_force_loot_materialization_failure_count > 0:
		_test_force_loot_materialization_failure_count -= 1
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


func _spawn_gold_loot(amount: int, position: Vector2) -> bool:
	if _test_force_loot_materialization_failure_count > 0:
		_test_force_loot_materialization_failure_count -= 1
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
	_pending_loot_collections.append(queued_candidate)
	if not _loot_collection_flush_queued:
		_loot_collection_flush_queued = true
		call_deferred("_flush_loot_collections")
	return true


func _flush_loot_collections() -> Dictionary:
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
		transaction_pending.append(candidate)
		candidates.append(candidate.duplicate(true))
	var result: Dictionary = (
		PlayerState.receive_loot_batch_partial(candidates)
		if not candidates.is_empty()
		else {"success": true, "saved": false, "outcomes": [], "success_count": 0}
	)
	var transaction_finished_usec := Time.get_ticks_usec()
	RuntimeDiagnostics.increment_performance_counter(&"loot_collection_authority_checks", pending.size())
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
			loot_feedback_names.append(
				"金币 +%d" % int(candidate.get("amount", 0))
				if bool(candidate.get("gold", false))
				else str(candidate.get("item_name", ""))
			)
			if pickup is LootPickup and is_instance_valid(pickup) and (pickup as LootPickup).collection_pending():
				pickup.confirm_collect()
		elif pickup is LootPickup and is_instance_valid(pickup) and (pickup as LootPickup).collection_pending():
			pickup.reject_collection(str(outcome.get("message", "超过负重，无法拾取。")))
	var outcomes_complete := processed_count == transaction_pending.size()
	if not outcomes_complete:
		# Keep unacknowledged candidates pending for a diagnosable retry instead
		# of silently dropping them when a malformed/partial transaction result
		# is returned.
		_pending_loot_collections.append_array(
			transaction_pending.slice(processed_count)
		)
		if not _pending_loot_collections.is_empty() and not _loot_collection_flush_queued:
			_loot_collection_flush_queued = true
			call_deferred("_flush_loot_collections")
	if collected_gold > 0 and is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_item_event("currency:gold", "loot_success", {"map_id": current_map_id})
	if hud != null and not loot_feedback_names.is_empty():
		hud.show_loot_batch(loot_feedback_names)
	if CombatDiagnosticLogScript.capture_enabled():
		print("[LootPickupProfile] ", JSON.stringify({
			"candidate_count": pending.size(),
			"transaction_ms": float(transaction_finished_usec - profile_started_usec) / 1000.0,
			"feedback_ms": float(Time.get_ticks_usec() - transaction_finished_usec) / 1000.0,
			"total_ms": float(Time.get_ticks_usec() - profile_started_usec) / 1000.0,
			"transaction": PlayerState._last_loot_batch_profile.duplicate(true),
		}))
	return {
		"success": bool(result.get("success", false)) and outcomes_complete,
		"saved": bool(result.get("saved", false)),
		"candidate_count": pending.size(),
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
		hud.show_message(message)


func _on_player_stats_changed(current_hp: int, max_hp: int) -> void:
	if hud != null:
		hud.update_hp(current_hp, max_hp)


func _sync_player_runtime_snapshot_to_hud() -> void:
	if hud == null or player == null:
		return
	hud.update_resources(player.current_hp, player.max_hp, player.current_mp, player.max_mp)
	hud.update_warrior_states(player.warrior_state_snapshot())


func _on_consumable_used(item_name: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item := GameData.get_item_record(item_name)
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
	elif "金创药" in item_name:
		player.restore_health(80 if "强效" in item_name else (35 if "中量" in item_name else 20))
	elif "魔法药" in item_name:
		player.restore_mana(100 if "强效" in item_name else (45 if "中量" in item_name else 30))
	elif "太阳水" in item_name:
		var amount := 100 if "强效" in item_name else 50
		player.restore_health(amount)
		player.restore_mana(amount)
	elif item_name == "疗伤药":
		player.restore_health(120)
	elif item_name == "万年雪霜":
		player.restore_health(150)
		player.restore_mana(150)
	elif "神水" in item_name:
		player.restore_health(30)
		player.restore_mana(30)
		player.apply_defense_buff(60.0, 2)
	hud.show_message("使用了%s" % item_name)


func _on_scroll_used(item_name: String) -> void:
	if not gameplay_input_is_enabled(): return
	var item := GameData.get_item_record(item_name)
	var effect := str(item.get("useEffect", ""))
	if effect in ["town_teleport", "dungeon_escape"] or item_name == "回城卷":
		travel_to_service_home(false, false, "比奇省")
	elif effect == "random_teleport" or "随机" in item_name:
		var destination := _find_valid_random_teleport_position(player.global_position)
		if destination == player.global_position:
			hud.show_message("附近没有可用传送落点")
			return
		_set_player_world_position(destination)
		player.velocity = Vector2.ZERO
		_relocate_main_pets_after_map_arrival()
	elif effect == "repair_oil":
		hud.show_message(PlayerState.apply_weapon_repair_oil(false))
		return
	elif effect == "war_god_oil":
		hud.show_message(PlayerState.apply_weapon_repair_oil(true))
		return
	hud.show_message("使用了%s" % item_name)


func _find_valid_random_teleport_position(origin_screen_px: Vector2) -> Vector2:
	# Every candidate goes through the same world boundary/obstacle contract as
	# movement and monster spawning.  A scroll can never bypass black borders.
	var origin_ground_gu := _canonical_screen_px_to_ground_gu(
		origin_screen_px
	)
	if not origin_ground_gu.is_finite() or not _target_spatial_query_ready():
		return origin_screen_px
	# Primary MapRandomMove samples the map dimensions, not a radius around
	# the actor. Use the published map's actual GU extent; collision below
	# rejects black borders, walls and occupied cells without biasing to Home.
	var runtime := MapEditorRuntimeBridgeScript.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2 or int(raw_size[0]) <= 0 or int(raw_size[1]) <= 0:
		return origin_screen_px
	var player_combat_radius_gu := (
		WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		)
	)
	for _attempt in range(RANDOM_TELEPORT_MAX_ATTEMPTS):
		var candidate_ground_gu := Vector2(
			float(_rng.randi_range(0, int(raw_size[0]) - 1)) + 0.5,
			float(_rng.randi_range(0, int(raw_size[1]) - 1)) + 0.5,
		)
		var candidate_screen_px := _canonical_ground_gu_to_screen_px(
			candidate_ground_gu
		)
		if WorldSpatialRulesScript.environment_blocks_actor_screen_px(
			background,
			candidate_screen_px,
			ArtSpec.PLAYER_COLLISION_RADIUS_PX
		):
			continue
		var occupied := false
		var enemy_query_radius_gu := (
			player_combat_radius_gu + RANDOM_TELEPORT_ACTOR_CLEARANCE_GU
		)
		if not _target_spatial_query_aabb_into(
			Rect2(
				candidate_ground_gu - Vector2.ONE * enemy_query_radius_gu,
				Vector2.ONE * enemy_query_radius_gu * 2.0,
			),
			_target_spatial_query_scratch,
		):
			return origin_screen_px
		for enemy: EnemyActor in _target_spatial_query_scratch:
			if GroundUnitSpaceScript.distance_gu(
				_canonical_screen_px_to_ground_gu(enemy.global_position),
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


func _respawn_later(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	seconds: float,
	generation: int,
	spawn_context: Dictionary = {}
) -> void:
	await get_tree().create_timer(seconds).timeout
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


func _spawn_slot_is_alive(slot_id: String, generation: int) -> bool:
	for value: Variant in get_tree().get_nodes_in_group("enemies"):
		if value is EnemyActor and not value.is_queued_for_deletion():
			if str(value.get_meta("spawn_slot_id", "")) == slot_id and int(value.get_meta("zone_generation", -1)) == generation:
				return true
	return false
