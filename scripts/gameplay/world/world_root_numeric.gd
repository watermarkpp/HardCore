extends "res://scripts/gameplay/world/world_root_death_owner.gd"

## Source-bound World root numerical continuation. One shared fields authority.
const LootPickupModel := preload("res://scripts/gameplay/world/world_loot_pickup_model.gd")
const DEFAULT_NORMAL_RESPAWN_SECONDS := preload("res://scripts/monster_respawn_policy.gd").BEGINNER_OUTDOOR_SECONDS

var _audio_runtime_service: Variant:
	get: return _fields.read_source_field(&"_audio_runtime_service")
	set(value): _fields.write_source_field(&"_audio_runtime_service", value)

var _world_camera_presented_center: Variant:
	get: return _fields.read_source_field(&"_world_camera_presented_center")
	set(value): _fields.write_source_field(&"_world_camera_presented_center", value)

var current_zone: Variant:
	get: return _fields.read_source_field(&"current_zone")
	set(value): _fields.write_source_field(&"current_zone", value)

var _respawn_wakeups: Variant:
	get: return _fields.read_source_field(&"_respawn_wakeups")
	set(value): _fields.write_source_field(&"_respawn_wakeups", value)

var _monster_terrain_navigation_context: Variant:
	get: return _fields.read_source_field(&"_monster_terrain_navigation_context")
	set(value): _fields.write_source_field(&"_monster_terrain_navigation_context", value)

var locked_target: Variant:
	get: return _fields.read_source_field(&"locked_target")
	set(value): _fields.write_source_field(&"locked_target", value)

var manual_target_lock: Variant:
	get: return _fields.read_source_field(&"manual_target_lock")
	set(value): _fields.write_source_field(&"manual_target_lock", value)

var magic_locked_target: Variant:
	get: return _fields.read_source_field(&"magic_locked_target")
	set(value): _fields.write_source_field(&"magic_locked_target", value)

var manual_magic_target_lock: Variant:
	get: return _fields.read_source_field(&"manual_magic_target_lock")
	set(value): _fields.write_source_field(&"manual_magic_target_lock", value)

var _queued_mobile_attack_tickets: Variant:
	get: return _fields.read_source_field(&"_queued_mobile_attack_tickets")
	set(value): _fields.write_source_field(&"_queued_mobile_attack_tickets", value)

var _keyboard_bound_skill_token: Variant:
	get: return _fields.read_source_field(&"_keyboard_bound_skill_token")
	set(value): _fields.write_source_field(&"_keyboard_bound_skill_token", value)

var _magic_shield_auto_enabled: Variant:
	get: return _fields.read_source_field(&"_magic_shield_auto_enabled")
	set(value): _fields.write_source_field(&"_magic_shield_auto_enabled", value)

var _warrior_hud_timer: Variant:
	get: return _fields.read_source_field(&"_warrior_hud_timer")
	set(value): _fields.write_source_field(&"_warrior_hud_timer", value)

var _movement_target_refresh_remaining: Variant:
	get: return _fields.read_source_field(&"_movement_target_refresh_remaining")
	set(value): _fields.write_source_field(&"_movement_target_refresh_remaining", value)

var _active_safe_zones: Variant:
	get: return _fields.read_source_field(&"_active_safe_zones")
	set(value): _fields.write_source_field(&"_active_safe_zones", value)

var _safe_zone_context: Variant:
	get: return _fields.read_source_field(&"_safe_zone_context")
	set(value): _fields.write_source_field(&"_safe_zone_context", value)

var _safe_zone_candidate_scratch: Variant:
	get: return _fields.read_source_field(&"_safe_zone_candidate_scratch")
	set(value): _fields.write_source_field(&"_safe_zone_candidate_scratch", value)

var _safe_zone_query_scratch: Variant:
	get: return _fields.read_source_field(&"_safe_zone_query_scratch")
	set(value): _fields.write_source_field(&"_safe_zone_query_scratch", value)

var _safe_zone_candidate_stamp_serial: Variant:
	get: return _fields.read_source_field(&"_safe_zone_candidate_stamp_serial")
	set(value): _fields.write_source_field(&"_safe_zone_candidate_stamp_serial", value)

var _runtime_spawn_serial: Variant:
	get: return _fields.read_source_field(&"_runtime_spawn_serial")
	set(value): _fields.write_source_field(&"_runtime_spawn_serial", value)

var _collecting_staged_actor_plan: Variant:
	get: return _fields.read_source_field(&"_collecting_staged_actor_plan")
	set(value): _fields.write_source_field(&"_collecting_staged_actor_plan", value)

var _staged_actor_source_index: Variant:
	get: return _fields.read_source_field(&"_staged_actor_source_index")
	set(value): _fields.write_source_field(&"_staged_actor_source_index", value)

var _staged_actor_spawn_failure_reason: Variant:
	get: return _fields.read_source_field(&"_staged_actor_spawn_failure_reason")
	set(value): _fields.write_source_field(&"_staged_actor_spawn_failure_reason", value)

var _active_enemy_cache: Variant:
	get: return _fields.read_source_field(&"_active_enemy_cache")
	set(value): _fields.write_source_field(&"_active_enemy_cache", value)

var _player_combat_enemy_ids: Variant:
	get: return _fields.read_source_field(&"_player_combat_enemy_ids")
	set(value): _fields.write_source_field(&"_player_combat_enemy_ids", value)

var _active_boss_cache: Variant:
	get: return _fields.read_source_field(&"_active_boss_cache")
	set(value): _fields.write_source_field(&"_active_boss_cache", value)

var _safe_zone_enforcement_remaining: Variant:
	get: return _fields.read_source_field(&"_safe_zone_enforcement_remaining")
	set(value): _fields.write_source_field(&"_safe_zone_enforcement_remaining", value)

var _passive_wake_dirty: Variant:
	get: return _fields.read_source_field(&"_passive_wake_dirty")
	set(value): _fields.write_source_field(&"_passive_wake_dirty", value)

var _passive_wake_query_pending: Variant:
	get: return _fields.read_source_field(&"_passive_wake_query_pending")
	set(value): _fields.write_source_field(&"_passive_wake_query_pending", value)

var _passive_wake_candidates: Variant:
	get: return _fields.read_source_field(&"_passive_wake_candidates")
	set(value): _fields.write_source_field(&"_passive_wake_candidates", value)

var _passive_wake_cursor: Variant:
	get: return _fields.read_source_field(&"_passive_wake_cursor")
	set(value): _fields.write_source_field(&"_passive_wake_cursor", value)

var _passive_wake_max_extent_gu: Variant:
	get: return _fields.read_source_field(&"_passive_wake_max_extent_gu")
	set(value): _fields.write_source_field(&"_passive_wake_max_extent_gu", value)

var _passive_wake_extent_map_id: Variant:
	get: return _fields.read_source_field(&"_passive_wake_extent_map_id")
	set(value): _fields.write_source_field(&"_passive_wake_extent_map_id", value)

var _passive_wake_extent_generation: Variant:
	get: return _fields.read_source_field(&"_passive_wake_extent_generation")
	set(value): _fields.write_source_field(&"_passive_wake_extent_generation", value)

var _passive_wake_pump_epoch: Variant:
	get: return _fields.read_source_field(&"_passive_wake_pump_epoch")
	set(value): _fields.write_source_field(&"_passive_wake_pump_epoch", value)

var _passive_wake_candidates_used: Variant:
	get: return _fields.read_source_field(&"_passive_wake_candidates_used")
	set(value): _fields.write_source_field(&"_passive_wake_candidates_used", value)

var _passive_wake_emitters: Variant:
	get: return _fields.read_source_field(&"_passive_wake_emitters")
	set(value): _fields.write_source_field(&"_passive_wake_emitters", value)

var _passive_wake_emitter_queue: Variant:
	get: return _fields.read_source_field(&"_passive_wake_emitter_queue")
	set(value): _fields.write_source_field(&"_passive_wake_emitter_queue", value)

var _passive_wake_active_emitter_id: Variant:
	get: return _fields.read_source_field(&"_passive_wake_active_emitter_id")
	set(value): _fields.write_source_field(&"_passive_wake_active_emitter_id", value)

var _ground_effect_manager: Variant:
	get: return _fields.read_source_field(&"_ground_effect_manager")
	set(value): _fields.write_source_field(&"_ground_effect_manager", value)

var _loot_pickup_runtime_manager: Variant:
	get: return _fields.read_source_field(&"_loot_pickup_runtime_manager")
	set(value): _fields.write_source_field(&"_loot_pickup_runtime_manager", value)

var missing_projection_rejection_count: Variant:
	get: return _fields.read_source_field(&"missing_projection_rejection_count")
	set(value): _fields.write_source_field(&"missing_projection_rejection_count", value)

var _portal_guard_state: Variant:
	get: return _fields.read_source_field(&"_portal_guard_state")
	set(value): _fields.write_source_field(&"_portal_guard_state", value)

var _map_transition_in_progress: Variant:
	get: return _fields.read_source_field(&"_map_transition_in_progress")
	set(value): _fields.write_source_field(&"_map_transition_in_progress", value)

var _pending_main_pet_arrivals: Variant:
	get: return _fields.read_source_field(&"_pending_main_pet_arrivals")
	set(value): _fields.write_source_field(&"_pending_main_pet_arrivals", value)

var _skill_cast_target: Variant:
	get: return _fields.read_source_field(&"_skill_cast_target")
	set(value): _fields.write_source_field(&"_skill_cast_target", value)

var _melee_diagnostic_serial: Variant:
	get: return _fields.read_source_field(&"_melee_diagnostic_serial")
	set(value): _fields.write_source_field(&"_melee_diagnostic_serial", value)

var _enemy_death_flush_queued: Variant:
	get: return _fields.read_source_field(&"_enemy_death_flush_queued")
	set(value): _fields.write_source_field(&"_enemy_death_flush_queued", value)

var _enemy_death_sequence: Variant:
	get: return _fields.read_source_field(&"_enemy_death_sequence")
	set(value): _fields.write_source_field(&"_enemy_death_sequence", value)

var _pending_loot_collections: Variant:
	get: return _fields.read_source_field(&"_pending_loot_collections")
	set(value): _fields.write_source_field(&"_pending_loot_collections", value)

var _prepared_loot_collection: Variant:
	get: return _fields.read_source_field(&"_prepared_loot_collection")
	set(value): _fields.write_source_field(&"_prepared_loot_collection", value)

var _first_long_frame_diagnosed: Variant:
	get: return _fields.read_source_field(&"_first_long_frame_diagnosed")
	set(value): _fields.write_source_field(&"_first_long_frame_diagnosed", value)

var _first_combat_probe_armed: Variant:
	get: return _fields.read_source_field(&"_first_combat_probe_armed")
	set(value): _fields.write_source_field(&"_first_combat_probe_armed", value)

var _loot_collection_flush_queued: Variant:
	get: return _fields.read_source_field(&"_loot_collection_flush_queued")
	set(value): _fields.write_source_field(&"_loot_collection_flush_queued", value)

var _loot_collection_origin_rejection_count: Variant:
	get: return _fields.read_source_field(&"_loot_collection_origin_rejection_count")
	set(value): _fields.write_source_field(&"_loot_collection_origin_rejection_count", value)

var _active_physical_hit_diagnostics: Variant:
	get: return _fields.read_source_field(&"_active_physical_hit_diagnostics")
	set(value): _fields.write_source_field(&"_active_physical_hit_diagnostics", value)

var _world_bootstrap_in_progress: Variant:
	get: return _fields.read_source_field(&"_world_bootstrap_in_progress")
	set(value): _fields.write_source_field(&"_world_bootstrap_in_progress", value)

var _player_input_enabled: Variant:
	get: return _fields.read_source_field(&"_player_input_enabled")
	set(value): _fields.write_source_field(&"_player_input_enabled", value)

var _death_experience_penalty_applied: Variant:
	get: return _fields.read_source_field(&"_death_experience_penalty_applied")
	set(value): _fields.write_source_field(&"_death_experience_penalty_applied", value)

var _death_event_serial: Variant:
	get: return _fields.read_source_field(&"_death_event_serial")
	set(value): _fields.write_source_field(&"_death_event_serial", value)

var _active_death_id: Variant:
	get: return _fields.read_source_field(&"_active_death_id")
	set(value): _fields.write_source_field(&"_active_death_id", value)

var _death_revival_request_in_flight: Variant:
	get: return _fields.read_source_field(&"_death_revival_request_in_flight")
	set(value): _fields.write_source_field(&"_death_revival_request_in_flight", value)

var _world_bootstrap_coordinator: Variant:
	get: return _fields.read_source_field(&"_world_bootstrap_coordinator")
	set(value): _fields.write_source_field(&"_world_bootstrap_coordinator", value)

var _gameplay_input_locks: Variant:
	get: return _fields.read_source_field(&"_gameplay_input_locks")
	set(value): _fields.write_source_field(&"_gameplay_input_locks", value)

var _feature_target_bound: Variant:
	get: return _fields.read_source_field(&"_feature_target_bound")
	set(value): _fields.write_source_field(&"_feature_target_bound", value)

var _hc_m30_summon_queue: Variant:
	get: return _fields.read_source_field(&"_hc_m30_summon_queue")
	set(value): _fields.write_source_field(&"_hc_m30_summon_queue", value)

var _hc_m30_landing_scratch: Variant:
	get: return _fields.read_source_field(&"_hc_m30_landing_scratch")
	set(value): _fields.write_source_field(&"_hc_m30_landing_scratch", value)

const PASSIVE_WAKE_BUDGET_CATEGORY := "monster_passive_wakeup"

const HCDecisionBudget := preload("res://scripts/monster_ai_package/decision_budget.gd")

const BICH_RUNTIME_MAP_ID := 910001

const LootVisualEffectScript := preload("res://scripts/loot_visual_effect.gd")

const MapEditorRuntimeBridgeScript := preload("res://scripts/layers/runtime/map_editor_runtime_bridge.gd")

const MapPortalTravelGuardScript := preload("res://scripts/map_editor/map_portal_travel_guard.gd")

const MapRuntimeCollisionGeometryScript := preload(
	"res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd"
)

const MonsterGroundSpikeEffectScript := preload(
	"res://scripts/monster_ground_spike_effect.gd"
)

const WorldSpatialRulesScript := preload("res://scripts/world_spatial_rules.gd")

const GroundUnitSpaceScript := preload("res://scripts/ground_unit_space.gd")

const CombatUnitLegacyAdapterScript := preload(
	"res://scripts/skills/combat_unit_legacy_adapter.gd"
)

const WarriorMeleeGeometryScript := preload("res://scripts/skills/warrior_melee_geometry.gd")

const WarriorMeleeDiagnosticScript := preload("res://scripts/skills/warrior_melee_diagnostic.gd")

const LootPickupRuntimeManagerScript := preload(
	"res://scripts/loot_pickup_runtime_manager.gd"
)

const UIItemTextureCacheScript := preload("res://scripts/ui_item_texture_cache.gd")

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

const LOOT_FALLBACK_RADII := [0.0, 0.25, 0.5, 0.75, 1.0, 1.5, 2.0]

const INPUT_LOCK_PLAYER_DEATH := &"player_death"

const DEATH_REVIVAL_CONTRACT_ID := "ui.death.revival.v1"

const DEATH_REVIVAL_FLOW_ID := "player.death.lifecycle.ui_gated.v1"

const HCM30SummonQueueScript := preload("res://scripts/gameplay/world/world_summon_queue_model.gd")


func _set_player_world_position(position_px: Vector2, reset_camera_follow := true) -> void:
	if not _world.skill_actors.is_runtime_present(_world.skills.player):
		return
	_world.skills.player.global_position = position_px
	if reset_camera_follow:
		_world_camera_presented_center = Vector2.INF
	_refresh_player_safe_zone_cache(true)
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.player_position_changed(position_px)


func _safe_zone_context_is_valid() -> bool:
	return bool(_safe_zone_context.get("valid", false))


func _acquire_gameplay_input_lock(reason: StringName) -> void:
	_reset_attack_action_lifecycle(reason)
	var _count: int = int(_gameplay_input_locks.get(reason, 0))
	_gameplay_input_locks[reason] = _count + 1
	_refresh_gameplay_input_state()
	if _world.diagnostics.input_gate_enabled():
		print("[GameplayInputGate] enabled=false locks=", _gameplay_input_locks)


func _refresh_gameplay_input_state() -> void:
	_player_input_enabled = _gameplay_input_locks.is_empty() and _world.skill_actors.is_runtime_present(_world.skills.player)


func _physics_process(delta: float) -> void:
	if _world.feature.runtime != null and _world.feature.runtime.has_work():
		_world.time_domains.advance_simulation(delta)
		_world.feature.runtime.pump()
	var physics_started_usec: Variant = _world.diagnostics.timing_start()
	if not _pending_main_pet_arrivals.is_empty() and not _map_transition_in_progress:
		_retry_pending_main_pet_arrivals()
	# Q2-B: generic persistent ground effects are scheduled once per physics
	# frame by the shared manager (old per-effect _physics_process cadence).
	if _ground_effect_manager != null:
		_ground_effect_manager.tick_frame(delta)
	_world.diagnostics.record_timing_ms(&"physics_process_ms", physics_started_usec)


func _process(delta: float) -> void:
	_recover_equipment_stealth_if_out_of_combat()
	var full_process_started_usec: Variant = _world.diagnostics.timing_start()
	# Real frame pacing (perf-smoothness-r1 Phase A): `_process(delta)` is
	# clamped by the engine (8/60 = 0.133s default) and was provably blind to
	# real stalls (PERF-02 of the 2026-09-18 audit). Measure wall-clock time
	# between process callbacks instead. -1.0 marks a measurement boundary
	# (first frame or pause/resume discard), never a gameplay stall.
	var wall_interval_ms: Variant = -1.0
	if OS.is_debug_build():
		wall_interval_ms = _world.diagnostics.wall_frame_interval_ms()
	# AOE first-engagement window (see AoeEngagementWindow): bounded ring of real
	# frame intervals between the first fire wall cast and first batch death.
	if wall_interval_ms >= 0.0 and _world.engagement.window_active():
		_world.engagement.record_frame_interval_ms(wall_interval_ms)
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
				_world.clock_ports.get_process_frames(),
				_world.required_owner_service(&"CasterVisual").frame_texture_cache_diagnostics(),
				_world.required_owner_service(&"PresentationAssets").cached_resource_count(),
				_world.required_owner_service(&"SourceFrames").diagnostics(),
			]
		)
	_world.required_owner_service(&"SourceFrames").poll()
	# perf-smoothness-r1 Phase C: drain combat texture misses through the
	# bounded threaded warm-up channel (no synchronous decode in combat).
	_ports.callv(&"_pump_pending_warm_textures",[])
	if not _prepared_loot_collection.is_empty(): _poll_prepared_loot_collection()
	var process_started_usec: Variant = _world.diagnostics.timing_start()
	# R3X-4: advance deferred death settlement/materialization in bounded main
	# thread slices.  The queue is deliberately pumped before ordinary world
	# presentation so a non-empty queue cannot starve behind unrelated UI work.
	_pump_enemy_death_work_queue()
	_pump_passive_monster_wakeup()
	_world.required_owner_service(&"UIItemTextureCache").poll_threaded_paths()
	# Q2-D: the single formal MonsterVisual streaming poll (once per frame).
	if _world.streaming != null:
		_world.streaming.poll_once(_world.clock_ports.get_process_frames())
	if _world.owner_services.HCDecisionBudget.pursuit_dispatch_enabled():
		_world.owner_services.HCDecisionBudget.dispatch_pursuit_process_batch(self)
	# Effect work participates in the same frame rotation as resource/death
	# consumers. Physics alone cannot use the turn they release later in this
	# frame. Pumping here never advances simulation or grants another budget.
	if _world.feature.runtime != null and _world.feature.runtime.has_work():
		_world.feature.runtime.pump()
	_expire_canonical_fire_charge_if_needed()
	_constrain_player_foot_to_runtime_ground()
	_refresh_player_safe_zone_cache()
	_ports.callv(&"_update_town_music_presence",[])
	_ports.get("background").set_focus_position(_world.skills.player.global_position)
	_ports.callv(&"_update_world_camera_constraint",[delta])
	_update_portal_arrival_guard()
	_tick_bich_safe_zone_enforcement(delta)
	_update_boss_world_mechanics(delta)
	_record_player_world_location()
	_validate_locked_target()
	_ports.callv(&"_update_target_hud",[])
	_process_skill_input_actions(delta)
	_process_magic_shield_auto_refresh(delta)
	_tick_ongoing_heals(delta)
	_ports.callv(&"_update_stealth_alpha",[])
	_ports.callv(&"_update_taoist_buff_hints",[])
	_warrior_hud_timer -= delta
	_movement_target_refresh_remaining = maxf(0.0, _movement_target_refresh_remaining - delta)
	if _warrior_hud_timer <= 0.0:
		_warrior_hud_timer = 0.2
		_world.profile.apply_warrior_runtime_state(_world.skills.player.warrior_runtime_state_for_save())
		hud.update_warrior_states(_world.skills.player.warrior_state_snapshot())
	var bound_attack_skill: Variant = _world.profile.skill_name_for_slot(
		_world.profile.SKILL_SLOT_GROUP_ATTACK,
		0
	)
	var attack_action_lifecycle: Variant = _poll_attack_action_lifecycle(_ports.callv(&"gameplay_input_is_enabled",[]))
	if bound_attack_skill.is_empty():
		_process_ordinary_attack_input(attack_action_lifecycle)
	else:
		_queued_mobile_attack_tickets.clear()
		if bool(attack_action_lifecycle.get("started", false)):
			_keyboard_bound_skill_token = _allocate_synthetic_attack_token()
			_on_skill_input_started(
				_world.profile.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
		if bool(attack_action_lifecycle.get("ended", false)) and _keyboard_bound_skill_token != 0:
			_on_skill_input_ended(
				_world.profile.SKILL_SLOT_GROUP_ATTACK,
				0,
				_keyboard_bound_skill_token,
				-4,
				&"keyboard"
			)
			_keyboard_bound_skill_token = 0
	if _world.input.is_action_just_pressed("interact"):
		_try_interact()
	for index in range(4):
		if _world.input.is_action_just_pressed("skill_%d" % (index + 1)):
			_use_quick_slot(index)
	_world.diagnostics.record_timing_ms(&"process_ms", process_started_usec)
	var full_process_usec: Variant = _world.diagnostics.timing_elapsed_usec(full_process_started_usec)
	if full_process_usec > 0:
		_world.diagnostics.record_performance_max(&"full_process_max_ms", float(full_process_usec) / 1000.0)


func _constrain_player_foot_to_runtime_ground() -> bool:
	if (
		not _world.skill_actors.is_runtime_present(_world.skills.player)
		or current_map_id == -1
		or not _world.environment_factory.runtime_maps.has_runtime_map(current_map_id)
	):
		return false
	var runtime: Variant = _world.environment_factory.runtime_maps.load_map(current_map_id)
	var raw_size: Array = runtime.get("design", {}).get("design_size", [])
	if raw_size.size() != 2:
		return false
	var design_size: Variant = Vector2i(int(raw_size[0]), int(raw_size[1]))
	var corrected: Variant = (
		MapRuntimeCollisionGeometryScript.project_player_foot_inside_boundary(
			_world.skills.player.global_position, design_size
		)
	)
	if corrected.is_equal_approx(_world.skills.player.global_position):
		return false
	_set_player_world_position(corrected, false)
	_world.skills.player.velocity = Vector2.ZERO
	_world.profile.update_world_location(
		current_map_id,
		corrected,
		_canonical_screen_px_to_ground_gu(corrected)
	)
	return true


func _update_portal_arrival_guard() -> void:
	var locked_key: Variant = str(_portal_guard_state.get("locked_portal_id", ""))
	if locked_key.is_empty() or bool(_portal_guard_state.get("travel_in_flight", false)):
		return
	var runtime: Variant = _world.environment_factory.runtime_maps.load_map(current_map_id)
	if runtime.is_empty():
		return
	MapPortalTravelGuardScript.clear_lock_after_departure(
		_portal_guard_state,
		locked_key,
		_world.environment_factory.runtime_maps.screen_position_px_to_ground_position_gu(
			runtime,
			_world.skills.player.global_position
		)
	)


func _tick_bich_safe_zone_enforcement(delta: float) -> void:
	if current_map_id != BICH_RUNTIME_MAP_ID:
		_safe_zone_enforcement_remaining = 0.0
		return
	_safe_zone_enforcement_remaining -= delta
	if _safe_zone_enforcement_remaining > 0.0:
		return
	_safe_zone_enforcement_remaining = SAFE_ZONE_ENFORCEMENT_INTERVAL_SECONDS
	_enforce_bich_safe_zone()


func _enforce_enemy_outside_bich_safe_zone(enemy: Object) -> void:
	var safe_zone_started_usec: Variant = _world.diagnostics.timing_start()
	_world.diagnostics.increment_performance_counter(&"safe_zone_queries")
	if (
		current_map_id != BICH_RUNTIME_MAP_ID
		or not _world.skill_actors.is_runtime_present(enemy)
		or _world.skill_actors.is_queued_for_retirement(enemy)
	):
		_world.diagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)
		return
	var current_ground_gu: Variant = _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var legal_ground_gu: Vector2 = hc_m30_stable_enemy_ground_point(
		current_ground_gu, float(enemy.combat_radius_gu), enemy.runtime_map_id
	)
	if not legal_ground_gu.is_finite():
		_world.diagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)
		return
	if not legal_ground_gu.is_equal_approx(current_ground_gu):
		enemy.set_combat_position(
			_canonical_ground_gu_to_screen_px(legal_ground_gu),
			&"safe_zone_enforcement",
		)
		enemy.velocity = Vector2.ZERO
	_world.diagnostics.record_timing_usec(&"safe_zone_usec", safe_zone_started_usec)


func _enforce_bich_safe_zone() -> void:
	if (
		current_map_id != BICH_RUNTIME_MAP_ID
		or not _safe_zone_context_is_valid()
		or _active_safe_zones.is_empty()
		or _world.spatial == null
		or not is_instance_valid(_world.spatial)
	):
		return
	_safe_zone_candidate_scratch.clear()
	_safe_zone_candidate_stamp_serial += 1
	if _safe_zone_candidate_stamp_serial <= 0:
		_safe_zone_candidate_stamp_serial = 1
	for zone_variant: Variant in _active_safe_zones:
		if not zone_variant is Dictionary:
			continue
		var zone: Variant = zone_variant as Dictionary
		var zone_aabb: Variant = zone.get("aabb_ground_gu", null)
		if not zone_aabb is Rect2:
			continue
		_world.spatial.query_enemy_nodes_aabb_into(
			current_map_id,
			zone_aabb as Rect2,
			_safe_zone_query_scratch,
		)
		for value: Variant in _safe_zone_query_scratch:
			if not _world.skill_actors.is_kind(value, &"enemy"):
				continue
			var enemy: Variant = value
			if not _world.skill_actors.is_runtime_present(enemy) or _world.skill_actors.is_queued_for_retirement(enemy):
				continue
			if enemy._safe_zone_candidate_stamp == _safe_zone_candidate_stamp_serial:
				continue
			enemy._safe_zone_candidate_stamp = _safe_zone_candidate_stamp_serial
			_append_safe_zone_candidate_sorted(enemy)
	for enemy: Object in _safe_zone_candidate_scratch:
		_enforce_enemy_outside_bich_safe_zone(enemy)
	_safe_zone_query_scratch.clear()


func _append_safe_zone_candidate_sorted(enemy: Object) -> void:
	var candidate_order: Variant = int(
		enemy.read_meta("spawn_serial", _world.skill_actors.runtime_actor_id(enemy))
	)
	var insert_at: Variant = _safe_zone_candidate_scratch.size()
	while insert_at > 0:
		var previous: Variant = _safe_zone_candidate_scratch[insert_at - 1]
		var previous_order: Variant = int(
			previous.read_meta("spawn_serial", _world.skill_actors.runtime_actor_id(previous))
		)
		if previous_order < candidate_order:
			break
		if (
			previous_order == candidate_order
			and _world.skill_actors.runtime_actor_id(previous) < _world.skill_actors.runtime_actor_id(enemy)
		):
			break
		insert_at -= 1
	_safe_zone_candidate_scratch.insert(insert_at, enemy)


func _submit_staged_actor_descriptor(
	actor_type: String,
	payload: Dictionary,
	stable_actor_id := ""
) -> bool:
	if not _collecting_staged_actor_plan or not _world_bootstrap_coordinator.actor_collection_is_open():
		return false
	var source_index: Variant = _staged_actor_source_index
	var actor_id: Variant = stable_actor_id
	if actor_id.is_empty():
		actor_id = "%s:%d:%06d" % [actor_type, current_map_id, source_index]
	var descriptor: Variant = {"actor_id": actor_id, "actor_type": actor_type,
		"source_index": source_index, "payload": payload}
	# The existing queue owner preflights stable identity before cold compilation.
	if not _world_bootstrap_coordinator.actor_descriptor_is_admissible(descriptor):
		return false
	if actor_type == "enemy":
		var monster_id: Variant = _strict_runtime_monster_id(payload)
		var position: Variant = payload.get("position")
		var seconds: Variant = payload.get("respawn_seconds", -1.0)
		var raw_context: Variant = payload.get("spawn_context", {})
		if monster_id <= 0 or not position is Vector2 or not position.is_finite() \
			or (not seconds is int and not seconds is float) or not is_finite(float(seconds)) \
			or not raw_context is Dictionary:
			return false
		var spawn_context: Dictionary = raw_context
		var slot: Variant = str(spawn_context.get("spawn_slot_id", spawn_context.get("spawn_group_id", "")))
		if slot.is_empty() or not str(spawn_context.get("summoner_spawn_slot", "")).is_empty():
			return false
		_feature_target_bound.sync_world(_world.world_context.capture_world())
		if not _feature_target_bound.declare_base(slot, monster_id, position, float(seconds), spawn_context, actor_id):
			return false
	var accepted: Variant = _world_bootstrap_coordinator.submit_actor_descriptor(descriptor)
	if accepted:
		_staged_actor_source_index += 1
	return accepted


func _spawn_enemy(
	monster_data: Dictionary,
	spawn_position: Vector2,
	is_boss: bool,
	respawn_seconds := -1.0,
	spawn_context: Dictionary = {}
) -> Object:
	_feature_target_bound.sync_world(_world.world_context.capture_world())
	if _collecting_staged_actor_plan:
		var monster_id_for_plan: Variant = _strict_runtime_monster_id(monster_data)
		var slot_id_for_plan: Variant = str(spawn_context.get(
			"spawn_slot_id",
			spawn_context.get("spawn_group_id", "")
		))
		var planned: Variant = _submit_staged_actor_descriptor(
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
	var monster_id: Variant = _strict_runtime_monster_id(monster_data)
	var summoner_slot: Variant = str(spawn_context.get("summoner_spawn_slot", ""))
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
		var spawn_ground_result: Variant = _try_canonical_screen_px_to_ground_gu(
			spawn_position
		)
		if not bool(spawn_ground_result.get("success", false)):
			# FREEZE-P0.1: mapped world without a loadable runtime projection
			# must never register an enemy at fake/delta coordinates.
			missing_projection_rejection_count += 1
			_staged_actor_spawn_failure_reason = "missing_spawn_projection"
			return null
	var explicit_slot: Variant = str(spawn_context.get("spawn_slot_id",spawn_context.get("spawn_group_id","")))
	if not explicit_slot.is_empty() and str(spawn_context.get("summoner_spawn_slot","")).is_empty() \
		and _spawn_slot_is_alive(explicit_slot,_zone_generation,true):
		# The old body owns its base slot until queued retirement. A deferred
		# death/revival callback cannot reopen it alongside a replacement.
		_staged_actor_spawn_failure_reason = "occupied_base_spawn_slot"
		return null
	_runtime_spawn_serial += 1
	# The original job is a synchronous factory capability, never actor/save data.
	var context: Variant = spawn_context.duplicate(false)
	context.erase("_m30_job")
	context = context.duplicate(true)
	var respawn_enabled: Variant = bool(context.get("respawn_enabled", true))
	var slot_id: Variant = str(context.get("spawn_slot_id", context.get("spawn_group_id", "")))
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
	var spawn_classification: Variant = str(
		canonical_monster.get("spawn_classification", "")
	)
	var policy: Dictionary = {}
	var effective_respawn: Variant = maxf(0.0, float(respawn_seconds))
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

	var clear_persisted_respawn_after_spawn: Variant = false
	if respawn_enabled:
		var persisted: Variant = _world.profile.monster_respawn_entry(current_map_id, slot_id)
		if not persisted.is_empty():
			if int(persisted.get("monster_id", -1)) != monster_id:
				# The map slot was deliberately re-authored to another
				# canonical identity. A stale death record must not suppress it.
				_world.profile.clear_monster_respawn_slot(current_map_id, slot_id)
			else:
				var remaining: Variant = maxf(
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
	var enemy: Variant = _world.create_unconfigured_enemy_model(inputs)
	enemy.setup(monster_data, _world.player_handle(), is_boss, inputs)
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
		_world.spatial,
		_runtime_spawn_serial
	)
	enemy.write_meta("spawn_serial", _runtime_spawn_serial)
	enemy.set_combat_position(spawn_position, &"spawn")
	_world.spatial.register(
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
	enemy.write_meta("spawn_position", spawn_position)
	enemy.write_meta("spawn_is_boss", is_boss)
	enemy.write_meta("respawn_seconds", effective_respawn)
	enemy.write_meta("respawn_random_seconds", float(context["respawn_random_seconds"]))
	enemy.write_meta("respawn_enabled", respawn_enabled)
	enemy.write_meta("respawn_policy_id", str(context.get("respawn_policy_id", "")))
	enemy.write_meta("respawn_policy_source", str(context.get("respawn_policy_source", "")))
	enemy.write_meta("respawn_policy_requires_authored_policy", bool(context.get("respawn_policy_requires_authored_policy", false)))
	enemy.write_meta("spawn_slot_id", slot_id)
	enemy.write_meta("spawn_group_id", str(context.get("spawn_group_id", slot_id)))
	enemy.write_meta("spawn_context", context)
	if enemy.has_method("passive_acquisition_extent_gu"):
		var passive_extent: Variant = float(enemy.call("passive_acquisition_extent_gu"))
		if is_finite(passive_extent) and passive_extent >= 0.0:
			enemy.write_meta("passive_wake_extent_gu", passive_extent)
			var extent_was_unavailable: Variant = (
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
	enemy.write_meta(
		"death_runtime_snapshot",
		_build_enemy_death_runtime_snapshot(canonical_monster)
	)
	enemy.write_meta("summoner_spawn_slot", str(context.get("summoner_spawn_slot", "")))
	enemy.write_meta("zone_generation", _zone_generation)
	# All actors on a loaded map share the compiled context. Do not deep-copy
	# polygon geometry per EnemyActor; realtime checks remain actor-owned while
	# consuming this map-lifetime immutable value.
	enemy.write_meta("safe_zone_context", _safe_zone_context)
	enemy.write_meta("safe_zones", _active_safe_zones)
	enemy.environment_blocker = _world.environment
	enemy.lifetime.add_to_group("zone_content")
	_world.connect_original_actor_signal(enemy, &"died", _on_enemy_died)
	_world.connect_original_actor_signal(enemy, &"combat_target_changed", _on_enemy_combat_target_changed)
	_on_enemy_combat_target_changed(enemy, enemy.target)
	_world.connect_original_actor_signal(enemy, &"target_requested", Callable(_ports,"_on_enemy_target_requested"))
	_world.connect_original_actor_signal(enemy, &"summon_requested", _on_boss_summon_requested)
	_world.connect_original_actor_signal(enemy, &"relocation_requested", _on_boss_relocation_requested)
	_world.connect_original_actor_signal(enemy, &"fixed_area_ground_spike_requested",
		_on_enemy_fixed_area_ground_spike_requested.bind(enemy)
	)
	_world.enter_spawned_enemy_at_original_child_boundary(enemy)
	var enemy_instance_id: Variant = _world.skill_actors.runtime_actor_id(enemy)
	_active_enemy_cache[enemy_instance_id] = enemy
	if is_instance_valid(_hc_m30_summon_queue):
		_hc_m30_summon_queue.track_child(enemy)
	if enemy.is_boss:
		_active_boss_cache[enemy_instance_id] = enemy
	_world.connect_actor_exit_once(enemy,
		_on_cached_enemy_tree_exiting.bind(enemy_instance_id),
		Object.CONNECT_ONE_SHOT
	)
	# Authored placement is corrected before the first rendered frame. Runtime
	# movement also enforces safe-zone targeting/motion; the 10 Hz cache sweep is
	# a bounded safety net rather than an all-enemy scan on every render frame.
	_enforce_enemy_outside_bich_safe_zone(enemy)
	if clear_persisted_respawn_after_spawn:
		_world.profile.clear_monster_respawn_slot(current_map_id, slot_id)
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
		var numeric_id: Variant = float(raw_id)
		if (
			is_finite(numeric_id)
			and numeric_id > 0.0
			and numeric_id == floorf(numeric_id)
			and numeric_id <= 9007199254740991.0
		):
			return int(numeric_id)
	return -1


func _build_enemy_death_runtime_snapshot(canonical_monster: Dictionary) -> Dictionary:
	var monster_id: Variant = _strict_runtime_monster_id(canonical_monster)
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


func _build_melee_input_diagnostic(
	target: Object,
	mode: String,
	attack_direction: Vector2,
	release_geometry: Dictionary,
	has_hittable_target: bool,
	facing_before: Vector2,
	touch_before: Vector2,
	movement_was_active: bool
) -> Dictionary:
	_melee_diagnostic_serial += 1
	var target_valid: Variant = _world.skill_actors.is_runtime_present(target)
	var target_world: Variant = target.global_position if target_valid else Vector2.ZERO
	var target_ground_gu: Variant = (
		_canonical_screen_px_to_ground_gu(target_world)
		if target_valid
		else Vector2.ZERO
	)
	var input_direction_index: Variant = _melee_direction_index(
		attack_direction,
		release_geometry
	)
	var actor_ground_gu: Variant = _canonical_screen_px_to_ground_gu(_world.skills.player.global_position)
	var target_candidate: Variant = (
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
		"action_id": "_world.skills.player:%d:melee:%d" % [
			_world.skill_actors.runtime_actor_id(_world.skills.player),
			_melee_diagnostic_serial,
		],
		"map_id": current_map_id,
		"requested_mode": mode,
		"actor_id": _world.skill_actors.runtime_actor_id(_world.skills.player),
		"actor_screen_px_at_input": _world.skills.player.global_position,
		"actor_ground_gu_at_input": actor_ground_gu,
		"locked_target_id": _world.skill_actors.runtime_actor_id(target) if target_valid else 0,
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
		"visual_row_before_input": _world.skills.player.visual.current_direction if _world.skills.player.visual != null else -1,
		"has_hittable_target_at_input": has_hittable_target,
		"release_policy_at_input": release_geometry.duplicate(true),
	}


func _update_boss_world_mechanics(delta: float) -> void:
	# Only bosses can own these mechanics. The spawn/exit cache keeps this
	# per-frame path independent of the total number of ordinary monsters.
	for value: Variant in _active_boss_cache.values():
		if not _world.skill_actors.is_kind(value, &"enemy"):
			continue
		var enemy: Variant = value
		if not enemy.is_boss or _world.skill_actors.is_queued_for_retirement(enemy):
			continue
		var relocation: Dictionary = enemy.boss_rule.get("mechanics", {}).get("surroundedRelocation", {})
		if not bool(relocation.get("enabled", false)):
			continue
		var remaining: Variant = float(enemy.read_meta("relocation_check_remaining", 0.0)) - delta
		if remaining > 0.0:
			enemy.write_meta("relocation_check_remaining", remaining)
			continue
		enemy.write_meta("relocation_check_remaining", maxf(0.25, float(relocation.get("checkSeconds", 10.0))))
		enemy.request_surrounded_relocation(_blocking_neighbor_count(enemy))


func _blocking_neighbor_count(enemy: Object) -> int:
	var seen: Dictionary = {}
	var count: Variant = 0
	var blocking_radius_gu: Variant = maxf(
		BOSS_SURROUNDED_NEIGHBOR_RADIUS_GU,
		enemy.combat_radius_gu * 2.5
	)
	var enemy_ground_gu: Variant = _canonical_screen_px_to_ground_gu(
		enemy.global_position
	)
	var candidates: Array = _world.skills._actors.actors_in_group("enemies") + _world.skills._actors.actors_in_group("combat_targets")
	candidates.append(_world.skills.player)
	for value: Variant in candidates:
		if not _world.skill_actors.is_runtime_present(value) or value == enemy or not _world.skill_actors.is_runtime_present(value):
			continue
		var node: Variant = value
		var instance_key: Variant = str(_world.skill_actors.runtime_actor_id(node))
		if seen.has(instance_key):
			continue
		var node_ground_gu: Variant = _canonical_screen_px_to_ground_gu(
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


func _on_boss_summon_requested(enemy: Object, monster_ids: Array, count: int, max_active: int) -> void:
	if not _world.skill_actors.is_runtime_present(enemy) or _world.skill_actors.is_queued_for_retirement(enemy) or monster_ids.is_empty():
		return
	if enemy.current_hp <= 0 or enemy._dying or enemy._death_pending:
		return
	if enemy.runtime_map_id != current_map_id or int(enemy.read_meta("zone_generation", -1)) != _zone_generation:
		return
	if _map_transition_in_progress or _world_bootstrap_in_progress:
		return
	var original_queue: RefCounted=_hc_m30_get_summon_queue()
	if original_queue==null: return # actual constructor/admission fault is recorded
	original_queue.enqueue(enemy, monster_ids, count, max_active)


func _on_boss_relocation_requested(enemy: Object, radius_gu: float) -> void:
	if not _world.skill_actors.is_runtime_present(enemy) or _world.skill_actors.is_queued_for_retirement(enemy):
		return
	if int(enemy.read_meta("zone_generation", -1)) != _zone_generation:
		return
	var destination: Variant = _find_valid_enemy_landing(
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
	enemy: Object,
) -> void:
	if not _world.skill_actors.is_runtime_present(enemy) or _world.skill_actors.is_queued_for_retirement(enemy):
		return
	if int(enemy.read_meta("zone_generation", -1)) != _zone_generation:
		return
	if str(descriptor.get("effect_id", "")) != MonsterGroundSpikeEffectScript.EFFECT_ID:
		return
	if str(descriptor.get("release_id", "")).is_empty():
		return
	if int(descriptor.get("source_instance_id", 0)) != _world.skill_actors.runtime_actor_id(enemy):
		return
	if int(descriptor.get("source_monster_id", -1)) != enemy.monster_id:
		return
	var target_world_px: Variant = descriptor.get("target_world_px", null)
	if not target_world_px is Vector2 or not (target_world_px as Vector2).is_finite():
		return
	_world.emit_original_main_event(&"original_enemy_ground_spike_visual", [descriptor])


func _find_valid_enemy_landing(
	origin_screen_px: Vector2,
	minimum_distance_gu: float,
	maximum_distance_gu: float,
	combat_radius_gu: float,
	ignored_enemy: Object
) -> Vector2:
	# Relocation retains its old synchronous 96-attempt API and origin sentinel.
	# Enemy summons instead call ONE probe through the global frame-budget queue.
	var origin_gu: Vector2 = _canonical_screen_px_to_ground_gu(origin_screen_px)
	if not origin_gu.is_finite():
		return origin_screen_px
	for _attempt: int in range(96):
		var candidate_gu: Vector2 = origin_gu + Vector2.from_angle(_world.random.randf_range(0.0, TAU)) * _world.random.randf_range(minimum_distance_gu, maximum_distance_gu)
		if _hc_m30_landing_clear(candidate_gu, combat_radius_gu, ignored_enemy):
			return _canonical_ground_gu_to_screen_px(candidate_gu)
	return origin_screen_px


func _on_player_moved(_position: Vector2, _facing: Vector2) -> void:
	_refresh_player_safe_zone_cache()
	if _loot_pickup_runtime_manager != null:
		_loot_pickup_runtime_manager.player_position_changed(_position)
	_validate_locked_target()
	_mark_passive_monster_wakeup_dirty()
	_pump_passive_monster_wakeup()


func _passive_wake_emitter_current(emitter: Object) -> bool:
	if (
		not _world.skill_actors.is_runtime_present(emitter)
		or _world.skill_actors.is_queued_for_retirement(emitter)
		or current_map_id < 0
	):
		return false
	if emitter == _world.skills.player:
		return not _world.skills.player._dead and _world.skills.player.current_hp > 0 and not _world.skills.player.is_stealthed()
	if _world.skill_actors.is_kind(emitter, &"summon"):
		var summon: Variant = emitter
		return (
			is_instance_valid(summon.owner_player)
			and summon.owner_player == _world.skills.player
			and not summon.owner_player._dead
			and summon.owner_player.current_hp > 0
			and summon.runtime_map_id == current_map_id
			and summon.current_hp > 0
			and summon.state not in [preload("res://scripts/gameplay/actors/summon_actor_model.gd").SummonState.DEAD, preload("res://scripts/gameplay/actors/summon_actor_model.gd").SummonState.EXPIRED]
			and not summon.owner_teleport_pending
			and not summon.is_stealthed()
		)
	return false


func _register_passive_wake_emitter(emitter: Object) -> void:
	# Deferred events from a pet leaving the old map must not recreate its
	# registry entry after the map generation has been replaced.
	if (
		not _world.skill_actors.is_runtime_present(emitter)
		or _world.skill_actors.is_queued_for_retirement(emitter)
		or not _world.is_inside_world()
		or not _world.skill_actors.is_inside_world(emitter)
		or _world.is_queued_for_retirement()
	):
		return
	var id: Variant = _world.skill_actors.runtime_actor_id(emitter)
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
	var changed_callback: Variant = Callable(_ports,"_on_passive_wake_emitter_changed").bind(id)
	if (
		emitter.has_signal("passive_wakeup_changed")
		and not _world.original_actor_signal_is_connected(emitter, &"passive_wakeup_changed", changed_callback)
	):
		_world.connect_original_actor_signal(emitter, &"passive_wakeup_changed", changed_callback, CONNECT_DEFERRED)
	var exiting_callback: Variant = Callable(_ports,"_on_passive_wake_emitter_exiting").bind(id)
	if not _world.original_actor_signal_is_connected(emitter, &"tree_exiting", exiting_callback):
		_world.connect_original_actor_signal(emitter, &"tree_exiting", exiting_callback, Object.CONNECT_ONE_SHOT)
	if _world.skill_actors.is_kind(emitter, &"summon"):
		var summon: Variant = emitter
		var state_callback: Variant = Callable(_ports,"_on_passive_wake_summon_state_changed").bind(id)
		if not _world.original_actor_signal_is_connected(summon, &"summon_state_changed", state_callback):
			_world.connect_original_actor_signal(summon, &"summon_state_changed", state_callback, CONNECT_DEFERRED)
	_passive_wake_emitter_queue.append(id)
	_passive_wake_dirty = true
	_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, true, true, false, _world.original_source_scope("game_root"), false)


func _mark_passive_wake_emitters_for_extent_availability() -> void:
	# A deferred/dynamic first enemy can establish the spawn-time extent after
	# the initial emitter query. Re-arm the small registered emitter set once;
	# this is a birth-time event, never a per-frame scan.
	var emitter_ids: Array = _passive_wake_emitters.keys()
	for raw_id: Variant in emitter_ids:
		_mark_passive_monster_wakeup_dirty(int(raw_id))


func _mark_passive_monster_wakeup_dirty(emitter_id := 0) -> void:
	if not _world.skill_actors.is_runtime_present(_world.skills.player) or _world.skills.player._dead or current_map_id < 0:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		_passive_wake_active_emitter_id = 0
		_passive_wake_emitter_queue.clear()
		_passive_wake_dirty = false
		_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	if emitter_id <= 0:
		emitter_id = _world.skill_actors.runtime_actor_id(_world.skills.player)
	var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
	if entry.is_empty():
		var emitter: Variant = _model_for_runtime_actor_id(emitter_id)
		if not _world.skill_actors.is_runtime_present(emitter):
			return
		_register_passive_wake_emitter(emitter)
		return
	if not bool(entry.get("dirty", false)):
		entry["dirty"] = true
		_passive_wake_emitter_queue.append(emitter_id)
	var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
	if _world.skill_actors.is_runtime_present(raw_emitter) and _world.skill_actors.is_runtime_present(raw_emitter) and not _passive_wake_emitter_current(raw_emitter):
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
	_world.frame_budget.mark_pending(
		PASSIVE_WAKE_BUDGET_CATEGORY,
		true,
		true,
		false,
		_world.original_source_scope("game_root"),
		false,
	)


func _passive_wake_candidate_current(enemy: Object) -> bool:
	return (
		_world.skill_actors.is_runtime_present(enemy)
		and not _world.skill_actors.is_queued_for_retirement(enemy)
		and not enemy._dying
		and not enemy._death_pending
		and enemy.current_hp > 0
		and enemy.runtime_map_id == current_map_id
		and int(enemy.read_meta("zone_generation", -1)) == _zone_generation
	)


func _begin_passive_monster_wakeup_batch() -> bool:
	if (
		not _world.skill_actors.is_runtime_present(_world.skills.player)
		or _world.skills.player._dead
		or current_map_id < 0
		or _world.spatial == null
		or not is_instance_valid(_world.spatial)
	):
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_query_pending = false
		return false
	var emitter: Object = null
	# Emitter events are necessary acquisition work, even when optional AI
	# has spent its allowance. This finite queue is drained up to a live event.
	while not _passive_wake_emitter_queue.is_empty():
		var emitter_id: int = int(_passive_wake_emitter_queue.pop_front())
		var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
		var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
		if not _world.skill_actors.is_runtime_present(raw_emitter) or not _world.skill_actors.is_runtime_present(raw_emitter):
			_passive_wake_emitters.erase(emitter_id)
			continue
		var candidate_emitter: Variant = raw_emitter
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
	var emitter_ground: Variant = _canonical_screen_px_to_ground_gu(emitter.global_position)
	if not emitter_ground.is_finite():
		_retain_passive_wake_active_event()
		return false
	var max_extent: Variant = _passive_wake_max_extent_gu
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
	var bounds: Variant = Rect2(
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
	var emitter_id: Variant = _passive_wake_active_emitter_id
	var entry: Dictionary = _passive_wake_emitters.get(emitter_id, {})
	var raw_emitter: Variant = entry.get("ref").get_ref() if entry.has("ref") else null
	if (
		_world.skill_actors.is_runtime_present(raw_emitter)
		and _world.skill_actors.is_runtime_present(raw_emitter)
		and _passive_wake_emitter_current(raw_emitter)
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
	if not _world.skill_actors.is_runtime_present(_world.skills.player) or _world.skills.player._dead or current_map_id < 0:
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		_passive_wake_dirty = false
		_passive_wake_query_pending = false
		_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	var process_epoch: Variant = _world.clock_ports.get_process_frames()
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
		_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
		return
	_world.frame_budget.mark_pending(
		PASSIVE_WAKE_BUDGET_CATEGORY,
		true,
		true,
		false,
		_world.original_source_scope("game_root"),
		false,
	)
	# Consume the finite emitter events present at entry. Acquisition cannot
	# wait behind optional AI or resource work; new events stay for the next
	# callback, and failed map queries are retried once rather than spun here.
	var event_count: Variant = _passive_wake_emitter_queue.size() + (1 if _passive_wake_active_emitter_id != 0 else 0)
	for _event: int in maxi(1, event_count):
		if not _service_passive_monster_wakeup_batch():
			break
		if not _passive_wake_query_pending:
			break


func _service_passive_monster_wakeup_batch() -> bool:
	if _passive_wake_query_pending:
		var query_token: Variant = _world.frame_budget.begin(PASSIVE_WAKE_BUDGET_CATEGORY, true)
		if not _begin_passive_monster_wakeup_batch():
			_passive_wake_dirty = not _passive_wake_emitter_queue.is_empty()
			_passive_wake_query_pending = _passive_wake_dirty
			_passive_wake_active_emitter_id = 0
			if not _passive_wake_dirty:
				_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
			_world.frame_budget.end(query_token)
			return false
		_passive_wake_dirty = false
		_world.frame_budget.end(query_token)
	var processed: Variant = 0
	var token: Variant = _world.frame_budget.begin(PASSIVE_WAKE_BUDGET_CATEGORY, true)
	while _passive_wake_cursor < _passive_wake_candidates.size():
		var raw_enemy: Variant = _passive_wake_candidates[_passive_wake_cursor]
		_passive_wake_cursor += 1
		processed += 1
		if not _world.skill_actors.is_runtime_present(raw_enemy) or not _world.skill_actors.is_kind(raw_enemy, &"enemy"):
			continue
		var enemy: Variant = raw_enemy
		var emitter_entry: Dictionary = _passive_wake_emitters.get(
			_passive_wake_active_emitter_id,
			{}
		)
		var raw_emitter: Variant = emitter_entry.get("ref").get_ref() if emitter_entry.has("ref") else null
		if (
			_passive_wake_candidate_current(enemy)
			and _world.skill_actors.is_runtime_present(raw_emitter)
			and _world.skill_actors.is_runtime_present(raw_emitter)
			and _passive_wake_emitter_current(raw_emitter)
		):
			var emitter: Variant = raw_emitter
			if enemy.has_method("request_passive_target_wakeup"):
				enemy.call("request_passive_target_wakeup", emitter, current_map_id, _zone_generation)
			elif emitter == _world.skills.player and enemy.has_method("request_passive_player_wakeup"):
				enemy.call("request_passive_player_wakeup", _world.skills.player, current_map_id, _zone_generation)
	_world.frame_budget.end(token)
	_passive_wake_candidates_used += processed
	if _passive_wake_cursor >= _passive_wake_candidates.size():
		_passive_wake_candidates.clear()
		_passive_wake_cursor = 0
		var finished_emitter_id: Variant = _passive_wake_active_emitter_id
		_passive_wake_active_emitter_id = 0
		var finished_entry: Dictionary = _passive_wake_emitters.get(finished_emitter_id, {})
		if not finished_entry.is_empty() and not bool(finished_entry.get("dirty", false)):
			finished_entry["dirty"] = false
			_passive_wake_emitters[finished_emitter_id] = finished_entry
		_passive_wake_query_pending = not _passive_wake_emitter_queue.is_empty()
		_passive_wake_dirty = _passive_wake_query_pending
		if not _passive_wake_query_pending:
			_world.frame_budget.mark_pending(PASSIVE_WAKE_BUDGET_CATEGORY, false)
	return true


func _on_player_death_requested() -> void:
	# Death is a lifecycle event, not gameplay input. The input gate correctly
	# rejects zero HP before this delayed notification is delivered.
	if not _world.skill_actors.is_runtime_present(_world.skills.player) or not _active_death_id.is_empty():
		return
	if not _world.skills.player._dead or _world.skills.player.current_hp > 0 or _world.skills.player.combat_transition_is_active():
		return
	# _world.skills.player.gd emits this only after the automatic-revival branch has failed,
	# making it the formal-death boundary.  This boundary opens the gameplay-
	# owned revival choices; no map transition may start before the _world.skills.player
	# explicitly selects one of those choices.
	if not _death_experience_penalty_applied:
		_world.profile.apply_death_experience_penalty()
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


func _try_interact() -> void:
	if not _ports.callv(&"gameplay_input_is_enabled",[]): return
	var nearest: Object
	var origin_ground_gu: Variant = _canonical_screen_px_to_ground_gu(
		_world.skills.player.global_position
	)
	var nearest_distance_gu: Variant = (
		CombatUnitLegacyAdapterScript.legacy_isometric_screen_scalar_px_to_gu(
			105.0
		)
	)
	for node: Object in _world.skills._actors.actors_in_group("interactable"):
		if not _world.skill_actors.is_runtime_present(node):
			continue
		var distance_gu: Variant = GroundUnitSpaceScript.distance_gu(
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
	if not _ports.callv(&"gameplay_input_is_enabled",[]): return
	_use_skill_slot(_world.profile.SKILL_SLOT_GROUP_ATTACK_RING, index)


func _record_melee_release_diagnostic(
	diagnostic: Dictionary,
	context: Dictionary,
	release_geometry: Dictionary,
	origin: Vector2,
	direction: Vector2,
	selection_mode: String,
	effect_mode: String,
	primary_targets: Array[Object],
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
	if diagnostic.is_empty() and _world.profile.test_mode:
		return
	if diagnostic.is_empty():
		_melee_diagnostic_serial += 1
		diagnostic = {
			"action_id": "_world.skills.player:%d:melee:%d" % [
				_world.skill_actors.runtime_actor_id(_world.skills.player),
				_melee_diagnostic_serial,
			],
			"actor_id": _world.skill_actors.runtime_actor_id(_world.skills.player),
			"map_id": current_map_id,
			"trace_origin": "release_without_input_trace",
		}
	var release_direction_index: Variant = _melee_direction_index(
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
		_world.skills.player.visual.current_direction if _world.skills.player.visual != null else -1
	)
	diagnostic["visual_geometry_direction_match"] = (
		_world.skills.player.visual == null
		or _world.skills.player.visual.current_direction == ArtSpec.mir2_client_direction_row(direction)
	)
	diagnostic["player_facing_at_release"] = _world.skills.player.facing
	diagnostic["player_facing_index_at_release"] = ArtSpec.direction_index(_world.skills.player.facing)
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


func _on_enemy_combat_target_changed(enemy: Object, new_target: Object) -> void:
	if not _world.skill_actors.is_runtime_present(enemy): return
	var id: Variant = _world.skill_actors.runtime_actor_id(enemy)
	if not enemy._dying and not enemy._death_pending and enemy.current_hp > 0 and is_instance_valid(new_target) and (new_target == _world.skills.player or _world.skill_actors.is_kind(new_target, &"summon")):
		_player_combat_enemy_ids[id] = true
	else:
		_player_combat_enemy_ids.erase(id)
		if not is_instance_valid(new_target):
			_mark_passive_monster_wakeup_dirty()


func _recover_equipment_stealth_if_out_of_combat() -> void:
	if not _world.skill_actors.is_runtime_present(_world.skills.player) or not _world.skills.player._stealth_break_override or not _player_combat_enemy_ids.is_empty():
		return
	if not _ports.callv(&"gameplay_input_is_enabled",[]) or _world.skills.player._dead or _world.skills.player._pending_combat_action_active or _world.skills.player._attack_action_timer > 0.0:
		return
	_world.skills.player.recover_equipment_stealth_after_combat_exit()


func _try_safe_ring_teleport() -> bool:
	var direction_screen_px: Variant = _world.skills.player.facing.normalized()
	if direction_screen_px == Vector2.ZERO:
		direction_screen_px = Vector2.DOWN
	var direction_ground: Variant = (
		GroundUnitSpaceScript.screen_delta_px_to_ground_delta_gu(
			direction_screen_px
		).normalized()
	)
	for distance_gu: float in SAFE_RING_TELEPORT_DISTANCES_GU:
		var motion_screen_px: Variant = (
			GroundUnitSpaceScript.ground_delta_gu_to_screen_delta_px(
				direction_ground * distance_gu
			)
		)
		if not _world.skills.player.test_move(_world.skills.player.global_transform, motion_screen_px):
			_world.skills.player.global_position += motion_screen_px
			_world.skills.player.velocity = Vector2.ZERO
			_world.skills.player.movement_performed.emit(_world.skills.player.global_position, _world.skills.player.facing)
			return true
	return false


func _wire_canonical_main_pet_persistence(summon: Object) -> void:
	_world.connect_original_actor_signal(summon, &"summon_state_changed",
		Callable(self, "_on_canonical_main_pet_state_changed").bind(summon)
	)


func _record_player_world_location() -> void:
	if not _world.skill_actors.is_runtime_present(_world.skills.player):
		return
	var ground_gu: Variant = _ground_position_gu_for_map(
		current_map_id,
		_world.skills.player.global_position
	)
	if not ground_gu.is_finite():
		# FREEZE-P0.2: never write Vector2.INF into _world.profile.
		return
	_world.profile.update_world_location(
		current_map_id,
		_world.skills.player.global_position,
		ground_gu
	)


func _show_attack_flash(origin: Vector2, direction: Vector2, hit: bool, color: Color) -> void:
	# Removed: the prototype drew a three-point V on every attack and also
	# overlaid the final Magic.wil skill effects.  Finished combat art is owned
	# by PlayerVisual; attacks without formal art deliberately show no fallback.
	return


func _on_enemy_died(enemy: Object, monster_data: Dictionary) -> void:
	_player_combat_enemy_ids.erase(_world.skill_actors.runtime_actor_id(enemy))
	var queued_at_usec: Variant = Time.get_ticks_usec()
	if _world.spatial != null:
		_world.spatial.unregister(
			int(enemy.read_meta("spawn_serial", 0))
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
	var monster_id: Variant = _strict_runtime_monster_id(monster_data)
	var raw_snapshot: Variant = enemy.read_meta("death_runtime_snapshot", {})
	var death_runtime_snapshot: Dictionary = (
		raw_snapshot as Dictionary if raw_snapshot is Dictionary else {}
	)
	if int(death_runtime_snapshot.get("monster_id", -1)) != monster_id:
		var canonical_monster: Variant = _world.owner_services.GameData.get_monster_by_id(monster_id)
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
	var raw_death_origin: Variant = enemy.read_meta("death_origin", {})
	var death_origin: Dictionary = (
		raw_death_origin.duplicate(true)
		if raw_death_origin is Dictionary
		else {}
	)
	var origin_captured: Variant = bool(death_origin.get("captured", false))
	var origin_map_id: Variant = int(death_origin.get("map_id", -1))
	var origin_generation: Variant = int(death_origin.get("generation", -1))
	if not origin_captured:
		var snapshot_map_id: Variant = int(
			death_runtime_snapshot.get("death_runtime_map_id", -1)
		)
		var snapshot_generation: Variant = int(
			death_runtime_snapshot.get("death_zone_generation", -1)
		)
		if snapshot_map_id >= 0 or snapshot_generation >= 0:
			origin_map_id = snapshot_map_id
			origin_generation = snapshot_generation
			origin_captured = true
	if not origin_captured:
		var actor_map_id: Variant = int(enemy.runtime_map_id)
		var actor_generation: Variant = int(enemy.read_meta("zone_generation", -1))
		if actor_map_id >= 0 or actor_generation >= 0:
			origin_map_id = actor_map_id
			origin_generation = actor_generation
			origin_captured = true
	var raw_death_position: Variant = death_origin.get(
		"death_position", enemy.global_position
	)
	var death_position: Variant = (
		raw_death_position as Vector2
		if raw_death_position is Vector2
		else enemy.global_position
	)
	var raw_spawn_position: Variant = death_origin.get(
		"spawn_position", enemy.read_meta("spawn_position", death_position)
	)
	var spawn_position: Variant = (
		raw_spawn_position as Vector2
		if raw_spawn_position is Vector2
		else death_position
	)
	var raw_spawn_context: Variant = death_origin.get(
		"spawn_context", enemy.read_meta("spawn_context", {})
	)
	var spawn_context: Dictionary = (
		raw_spawn_context.duplicate(true)
		if raw_spawn_context is Dictionary
		else {}
	)
	_enemy_death_sequence += 1
	var sequence: Variant = _enemy_death_sequence
	var canonical_snapshot: Variant = death_runtime_snapshot.duplicate(true)
	var canonical_monster: Variant = {
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
			_world.skill_actors.runtime_actor_id(enemy),
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
			"enabled": bool(enemy.read_meta("respawn_enabled", true)),
			"configured_seconds": float(
				enemy.read_meta("respawn_seconds", -1.0)
			),
			"was_boss": bool(enemy.read_meta("spawn_is_boss", false)),
			"spawn_context": spawn_context,
		},
		"was_boss": bool(enemy.read_meta("spawn_is_boss", false)),
		"generation": origin_generation,
		"configured_respawn": float(enemy.read_meta("respawn_seconds", -1.0)),
		"respawn_enabled": bool(enemy.read_meta("respawn_enabled", true)),
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
	_world.diagnostics.record_performance_max(
		&"drop_queue_depth_max",
		float(_pending_enemy_deaths.size()),
	)
	_schedule_enemy_death_work()


func _schedule_enemy_death_work() -> void:
	if _enemy_death_flush_queued or _enemy_death_pipeline_running:
		return
	_enemy_death_flush_queued = true
	_world.defer_original_root_member("_flush_enemy_deaths", true)


func _flush_enemy_deaths(spread_across_frames := true) -> void:
	_enemy_death_flush_queued = false
	if spread_across_frames:
		_pump_enemy_death_work_queue()
		return
	# Tests and a few synchronous compatibility callers explicitly request the
	# old completion boundary.  Use the same state machine without yielding.
	var guard: Variant = 0
	while not _pending_enemy_deaths.is_empty() and guard < 4096:
		var progressed: Variant = _pump_enemy_death_work_queue(true)
		guard += 1
		if not progressed and not _pending_enemy_deaths.is_empty():
			# A future retry deadline is ignored by the synchronous compatibility
			# path; a malformed item is terminally observable rather than silently
			# stranded in the queue.
			var head: Dictionary = _pending_enemy_deaths[0]
			_set_enemy_death_state(head, DEATH_STATE_FAILED)
			head["last_error"] = "death_queue_no_progress"
			_world.diagnostics.increment_performance_counter(
				&"death_queue_failed_count"
			)
			_compact_enemy_death_queue()


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
		_world.diagnostics.increment_performance_counter(
			&"death_queue_materialization_failures"
		)
		_world.diagnostics.increment_performance_counter(
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
		_world.diagnostics.increment_performance_counter(
			&"death_queue_materialization_failures"
		)
		_world.diagnostics.increment_performance_counter(
			&"death_queue_failed_count"
		)
		return {"complete": true, "progressed": true, "nodes": 0}
	if not _death_origin_matches_current(death):
		death["last_error"] = "origin_map_generation_mismatch_after_roll"
		death["remaining_requests"] = raw_requests.duplicate(true)
		death["remaining_request_count"] = raw_requests.size()
		death["reward_status"] = "cancelled_after_roll"
		_set_enemy_death_state(death, DEATH_STATE_CANCELLED)
		_world.diagnostics.increment_performance_counter(
			&"death_queue_cancelled_count"
		)
		return {"complete": true, "progressed": true, "nodes": 0}
	var requests: Array = raw_requests
	var request_index: Variant = int(death.get("materialized_node_index", 0))
	var nodes: Variant = 0
	var progressed: Variant = false
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
			_world.diagnostics.increment_performance_counter(
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
			_world.diagnostics.increment_performance_counter(
				&"death_queue_materialization_failures"
			)
			_world.diagnostics.increment_performance_counter(
				&"death_queue_failed_count"
			)
			return {"complete": true, "progressed": true, "nodes": nodes}
		var request: Dictionary = request_value
		var placement_search: Dictionary = death.get("placement_search", {})
		if int(placement_search.get("request_index", request_index)) != request_index:
			placement_search = {}
		placement_search["request_index"] = request_index
		var placement: Variant = _advance_loot_ground_position(
			request.get("position", death.get("death_position", Vector2.ZERO)),
			death.get("death_position", Vector2.INF),
			placement_search,
			slice_started_usec,
			budget_usec,
			force_synchronous or _world.profile.test_mode,
		)
		if not bool(placement.get("complete", false)):
			death["placement_search"] = placement_search
			return {"complete": false, "progressed": true, "nodes": nodes}
		death.erase("placement_search")
		var resolved_position: Vector2 = placement.get("position", Vector2.INF)
		var materialized: Variant = false
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
			_world.diagnostics.increment_performance_counter(
				&"death_queue_materialization_failures"
			)
			if int(death["materialization_retry_count"]) >= DEATH_QUEUE_MAX_RETRIES:
				death["reward_status"] = "materialization_failed"
				_set_enemy_death_state(death, DEATH_STATE_FAILED)
				_world.diagnostics.increment_performance_counter(
					&"death_queue_failed_count"
				)
				return {"complete": true, "progressed": true, "nodes": nodes}
			death["retry_at_msec"] = (
				Time.get_ticks_msec() + DEATH_QUEUE_RETRY_DELAY_MSEC
			)
			return {"complete": false, "progressed": true, "nodes": nodes}
		request_index += 1
		nodes += 1
		if not force_synchronous and not _world.profile.test_mode:
			_last_drop_node_frame = _world.clock_ports.get_process_frames()
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


func _loot_world_segment_clear(
	origin_px: Vector2,
	target_px: Vector2,
	reusable_query: PhysicsRayQueryParameters2D = null,
) -> bool:
	if not origin_px.is_finite() or not target_px.is_finite() or not is_instance_valid(_world.environment):
		return false
	var origin_gu: Variant = _canonical_screen_px_to_ground_gu(origin_px)
	var target_gu: Variant = _canonical_screen_px_to_ground_gu(target_px)
	if _world.environment.is_environment_segment_blocked_ground(origin_gu, target_gu, 0.125):
		return false
	var query: Variant = reusable_query
	if query == null:
		query = PhysicsRayQueryParameters2D.create(origin_px, target_px, WorldSpatialRulesScript.WORLD_MASK)
	else:
		query.from = origin_px
		query.to = target_px
	query.hit_from_inside = true
	var result: Dictionary = _world.native_world.intersect_ray(query.from, query.to, query.collision_mask,
		query.exclude, query.collide_with_bodies, query.collide_with_areas, query.hit_from_inside)
	if result.get("ok") != true:
		_world.fault("original_loot_ray_query_rejected", result)
		return false
	return result.collided == false


func _loot_ground_point_clear(
	position_px: Vector2,
	reusable_query: PhysicsShapeQueryParameters2D = null,
) -> bool:
	if not position_px.is_finite() or not is_instance_valid(_world.environment):
		return false
	if _world.environment.is_environment_actor_blocked(position_px, 6.0):
		return false
	var query: Variant = reusable_query
	if query == null:
		var shape: Variant = CircleShape2D.new()
		shape.radius = 5.0
		query = PhysicsShapeQueryParameters2D.new()
		query.shape = shape
	query.transform = Transform2D(0.0, position_px)
	query.collision_mask = WorldSpatialRulesScript.WORLD_MASK
	var result: Dictionary = _world.native_world.intersect_shape_empty(query)
	if result.get("ok") != true:
		_world.fault("original_loot_shape_query_rejected", result)
		return false
	return result.empty == true


func _resolve_loot_ground_position(desired_px: Vector2, death_origin := Vector2.INF) -> Vector2:
	var search: Dictionary = {}
	var result: Variant = _advance_loot_ground_position(
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
	var anchor_gu: Variant = _canonical_screen_px_to_ground_gu(anchor)
	var reusable_point_query: Variant = search.get("point_query") as PhysicsShapeQueryParameters2D
	if reusable_point_query == null:
		var shape: Variant = CircleShape2D.new()
		shape.radius = 5.0
		reusable_point_query = PhysicsShapeQueryParameters2D.new()
		reusable_point_query.shape = shape
		search["point_query"] = reusable_point_query
	var reusable_segment_query: Variant = search.get("segment_query") as PhysicsRayQueryParameters2D
	if reusable_segment_query == null:
		reusable_segment_query = PhysicsRayQueryParameters2D.create(
			anchor, anchor, WorldSpatialRulesScript.WORLD_MASK
		)
		search["segment_query"] = reusable_segment_query
	var candidate_index: Variant = int(search.get("candidate_index", -1))
	var checked: Variant = 0
	# Resume the original deterministic candidate order without repeating prior physics queries.
	var fallback_count: Variant = 1 + (LOOT_FALLBACK_RADII.size() - 1) * 8
	while candidate_index < fallback_count:
		if (
			not force_synchronous
			and checked > 0
			and Time.get_ticks_usec() - slice_started_usec >= budget_usec
		):
			search["candidate_index"] = candidate_index
			return {"complete": false, "progressed": true}
		var candidate: Variant = desired_px
		if candidate_index >= 0:
			var radius_index: Variant = 0 if candidate_index == 0 else 1 + int((candidate_index - 1) / 8)
			var direction: Variant = 0 if candidate_index == 0 else (candidate_index - 1) % 8
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


func _loot_collection_path_is_clear(pickup: Object) -> bool:
	if not _world.skill_actors.is_runtime_present(pickup) or not _world.skill_actors.is_runtime_present(_world.skills.player) or not _ports.callv(&"gameplay_input_is_enabled",[]):
		return false
	if pickup.filtered or _world.skill_actors.is_queued_for_retirement(pickup):
		return false
	var origin_gu: Variant = _canonical_screen_px_to_ground_gu(_world.skills.player.global_position)
	var target_gu: Variant = _canonical_screen_px_to_ground_gu(pickup.global_position)
	if origin_gu.distance_to(target_gu) >= LootPickupRuntimeManagerScript.COLLECTION_RADIUS_GU:
		return false
	return _loot_world_segment_clear(_world.skills.player.global_position, pickup.global_position)


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
	var loot: Variant = _world.create_unconfigured_loot_model()
	if item_record.is_empty():
		loot.setup(item_name, _world.skills.player)
	else:
		loot.setup_item_record(item_record, _world.skills.player)
	loot.global_position = position
	loot.add_to_group("zone_content")
	_world.connect_original_actor_signal(loot, &"collected", _on_loot_collected)
	_world.connect_original_actor_signal(loot, &"collection_rejected", _on_loot_collection_rejected)
	var spawn_started_usec: Variant = _world.diagnostics.timing_start()
	_world.enter_spawned_loot_at_original_child_boundary(loot)
	var registered: Variant = (
		_loot_pickup_runtime_manager != null
		and _loot_pickup_runtime_manager.register_pickup(loot)
	)
	if not registered:
		# A formal loot node without a map-scoped registration is not collectible;
		# remove it synchronously so materialization cannot leave dead ground loot.
		loot.free()
		return false
	_world.diagnostics.increment_performance_counter(&"drop_node_spawn_count")
	_world.diagnostics.record_timing_usec(&"drop_node_spawn_usec", spawn_started_usec)
	return _world.skill_actors.is_runtime_present(loot)


func _spawn_gold_loot(amount: int, position: Vector2, death_origin := Vector2.INF, placement_resolved := false) -> bool:
	if _test_force_loot_materialization_failure_count > 0:
		_test_force_loot_materialization_failure_count -= 1
		return false
	if not placement_resolved:
		position = _resolve_loot_ground_position(position, death_origin)
	if not position.is_finite():
		return false
	var loot: Variant = _world.create_unconfigured_loot_model()
	loot.setup_gold(amount, _world.skills.player)
	loot.global_position = position
	loot.add_to_group("zone_content")
	_world.connect_original_actor_signal(loot, &"gold_collected", _on_gold_loot_collected)
	_world.connect_original_actor_signal(loot, &"collection_rejected", _on_loot_collection_rejected)
	var spawn_started_usec: Variant = _world.diagnostics.timing_start()
	_world.enter_spawned_loot_at_original_child_boundary(loot)
	var registered: Variant = (
		_loot_pickup_runtime_manager != null
		and _loot_pickup_runtime_manager.register_pickup(loot)
	)
	if not registered:
		loot.free()
		return false
	_world.diagnostics.increment_performance_counter(&"drop_node_spawn_count")
	_world.diagnostics.record_timing_usec(&"drop_node_spawn_usec", spawn_started_usec)
	return _world.skill_actors.is_runtime_present(loot)


func _on_gold_loot_collected(amount: int, pickup: Object) -> void:
	_queue_loot_collection({"gold": true, "amount": amount, "pickup": pickup})


func _on_loot_collected(item_name: String, pickup: Object) -> void:
	var candidate: Variant = {"item_name": item_name, "pickup": pickup}
	if _world.skill_actors.is_runtime_present(pickup) and pickup.item_id >= 0:
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
	var queued_candidate: Variant = candidate.duplicate(true)
	var pickup: Variant = queued_candidate.get("pickup")
	if not pickup is LootPickupModel or not _world.skill_actors.is_runtime_present(pickup):
		_loot_collection_origin_rejection_count += 1
		_world.diagnostics.increment_performance_counter(
			&"loot_collection_origin_rejections"
		)
		return false
	var pickup_object: Variant = pickup
	var raw_map_id: Variant = null
	var raw_generation: Variant = null
	if pickup_object.has_meta("loot_runtime_map_id"):
		raw_map_id = pickup_object.get_meta("loot_runtime_map_id")
	if pickup_object.has_meta("loot_zone_generation"):
		raw_generation = pickup_object.get_meta("loot_zone_generation")
	var formal_origin_valid: Variant = (
			raw_map_id is int
			and raw_generation is int
			and int(raw_map_id) >= 0
			and int(raw_generation) >= 0
		)
	if not formal_origin_valid:
		if not (_world.profile.test_mode and _loot_legacy_reference_fallback_test_enabled):
			_loot_collection_origin_rejection_count += 1
			_world.diagnostics.increment_performance_counter(
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
		_world.diagnostics.increment_performance_counter(
			&"loot_collection_origin_rejections"
		)
		pickup_object.reject_collection("拾取来源无效，无法入账。")
		return false
	# Reachability decides admission. Once this real source is accepted, its
	# ordered transaction survives ordinary _world.skills.player movement while IO finishes.
	if not pickup_object.collection_pending():
		return false
	if not _loot_collection_path_is_clear(pickup_object):
		pickup_object.reject_collection("暂时无法到达该物品。")
		return false
	_pending_loot_collections.append(queued_candidate)
	if not _loot_collection_flush_queued:
		_loot_collection_flush_queued = true
		_world.defer_original_root_member("_flush_loot_collections", true)
	return true


func _flush_loot_collections(allow_background := false) -> Dictionary:
	if not _prepared_loot_collection.is_empty():
		if allow_background:
			# This deferred call has been consumed. The in-flight completion must
			# be allowed to schedule the next cohort queued during its write.
			_loot_collection_flush_queued = false
			return {"pending": true}
		var finished: Variant = _poll_prepared_loot_collection(true)
		if not bool(finished.get("success", false)) and not bool(finished.get("retry", false)): return finished
	var profile_started_usec: Variant = Time.get_ticks_usec()
	_loot_collection_flush_queued = false
	if _pending_loot_collections.is_empty():
		return {"success": true, "candidate_count": 0, "saved": false}
	var pending: Variant = _pending_loot_collections
	_pending_loot_collections = []
	var candidates: Array = []
	var transaction_pending: Array[Dictionary] = []
	var stale_count: Variant = 0
	for candidate: Dictionary in pending:
		var origin_matches: Variant = (
			int(candidate.get("origin_map_id", -1)) == current_map_id
			and int(candidate.get("origin_generation", -1)) == _zone_generation
		)
		var pickup: Variant = candidate.get("pickup")
		if not origin_matches:
			stale_count += 1
			if pickup is LootPickupModel and _world.skill_actors.is_runtime_present(pickup):
				(pickup).reject_collection("地图已切换，无法拾取。")
			continue
		if not pickup is LootPickupModel or not _world.skill_actors.is_runtime_present(pickup) or not pickup.collection_pending():
			continue
		transaction_pending.append(candidate)
		candidates.append(candidate.duplicate(true))
	if allow_background and not _world.profile.test_mode and not candidates.is_empty():
		var inventory_bucket: Variant = -1
		if _world.diagnostics.performance_timing_enabled():
			var occupied_slots: Variant = 0
			for item: Variant in _world.profile.inventory:
				if item is Dictionary and not (item as Dictionary).is_empty():
					occupied_slots += 1
			inventory_bucket = mini(4, floori(float(occupied_slots) / 25.0))
			_world.diagnostics.set_performance_value(&"loot_inventory_occupied_last", float(occupied_slots))
			_world.diagnostics.increment_performance_counter(StringName("loot_prepare_bucket_%d_count" % inventory_bucket))
		var prepare_started_usec: Variant = _world.diagnostics.timing_start()
		var plan: Variant = _world.profile.prepare_loot_save(candidates)
		var prepare_usec: Variant = _world.diagnostics.timing_elapsed_usec(prepare_started_usec)
		if prepare_usec > 0:
			_world.diagnostics.record_performance_max(&"loot_prepare_max_ms", float(prepare_usec) / 1000.0)
			_world.diagnostics.record_performance_max(StringName("loot_prepare_bucket_%d_max_ms" % inventory_bucket), float(prepare_usec) / 1000.0)
		if not plan.has("immediate"):
			_prepared_loot_collection = {"plan": plan, "pending": transaction_pending, "candidate_count": pending.size(), "stale_count": stale_count, "inventory_bucket": inventory_bucket}
			return {"pending": true}
		return _finish_loot_collection_outcomes(transaction_pending, plan.immediate, pending.size(), stale_count, profile_started_usec)
	var result: Dictionary = (
		_world.profile.receive_loot_batch_partial(candidates)
		if not candidates.is_empty()
		else {"success": true, "saved": false, "outcomes": [], "success_count": 0}
	)
	return _finish_loot_collection_outcomes(transaction_pending, result, pending.size(), stale_count, profile_started_usec)


func _poll_prepared_loot_collection(wait := false) -> Dictionary:
	if _prepared_loot_collection.is_empty(): return {"success": true}
	var cohort: Variant = _prepared_loot_collection
	var started_usec: Variant = Time.get_ticks_usec()
	var valid: Variant = true
	for candidate: Dictionary in cohort.pending:
		var pickup: Variant = candidate.get("pickup")
		if (int(candidate.get("origin_map_id", -1)) != current_map_id
			or int(candidate.get("origin_generation", -1)) != _zone_generation
			or not pickup is LootPickupModel or not _world.skill_actors.is_runtime_present(pickup)
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
			result = _world.profile.finish_prepared_loot_save(cohort.plan, true)
	else:
		var commit_started_usec: Variant = _world.diagnostics.timing_start()
		result = _world.profile.finish_prepared_loot_save(cohort.plan, wait)
		if not bool(result.get("pending", false)):
			if cohort.plan.has("bytes"):
				_world.diagnostics.set_performance_value(&"loot_save_bytes_last", float((cohort.plan.bytes as PackedByteArray).size()))
			var commit_usec: Variant = _world.diagnostics.timing_elapsed_usec(commit_started_usec)
			if commit_usec > 0:
				var field: Variant = &"loot_gold_commit_max_ms" if int(cohort.plan.gold_after) != int(cohort.plan.gold_before) else &"loot_item_commit_max_ms"
				_world.diagnostics.record_performance_max(field, float(commit_usec) / 1000.0)
				var inventory_bucket: Variant = int(cohort.get("inventory_bucket", -1))
				if inventory_bucket >= 0:
					_world.diagnostics.increment_performance_counter(StringName("loot_commit_bucket_%d_count" % inventory_bucket))
					_world.diagnostics.record_performance_max(StringName("loot_commit_bucket_%d_max_ms" % inventory_bucket), float(commit_usec) / 1000.0)
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
		_world.defer_original_root_member("_flush_loot_collections", true)
	return result


func _finish_loot_collection_outcomes(transaction_pending: Array, result: Dictionary, candidate_count: int, stale_count: int, profile_started_usec: int) -> Dictionary:
	var transaction_finished_usec: Variant = Time.get_ticks_usec()
	_world.diagnostics.increment_performance_counter(&"loot_collection_authority_checks", candidate_count)
	var outcomes: Array = result.get("outcomes", [])
	var loot_feedback_names: Array = []
	var collected_gold: Variant = 0
	var processed_count: Variant = mini(transaction_pending.size(), outcomes.size())
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
				var display_item_id: Variant = LootVisualEffectScript.exact_item_id(pickup.item_record) if pickup is LootPickupModel and _world.skill_actors.is_runtime_present(pickup) else int(candidate.get("item_id", -1))
				var display_name: Variant = ("★" if pickup is LootPickupModel and _world.skill_actors.is_runtime_present(pickup) and LootVisualEffectScript.affix_is_valid(pickup.item_record) else "") + str(candidate.get("item_name", ""))
				loot_feedback_names.append({"item_name": display_name, "item_id": display_item_id})
			if pickup is LootPickupModel and _world.skill_actors.is_runtime_present(pickup) and (pickup).collection_pending():
				pickup.confirm_collect()
		elif pickup is LootPickupModel and _world.skill_actors.is_runtime_present(pickup) and (pickup).collection_pending():
			pickup.reject_collection(str(outcome.get("message", "超过负重，无法拾取。")))
	var outcomes_complete: Variant = processed_count == transaction_pending.size()
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
			_world.defer_original_root_member("_flush_loot_collections", true)
	if collected_gold > 0 and is_instance_valid(_audio_runtime_service):
		_audio_runtime_service.play_item_event("currency:gold", "loot_success", {"map_id": current_map_id})
	if hud != null and not loot_feedback_names.is_empty():
		hud.show_loot_batch(loot_feedback_names)
	var feedback_usec: Variant = _world.diagnostics.timing_elapsed_usec(transaction_finished_usec)
	if feedback_usec > 0:
		_world.diagnostics.record_performance_max(&"loot_feedback_max_ms", float(feedback_usec) / 1000.0)
	if CombatDiagnosticLogScript.capture_enabled():
		print("[LootPickupProfile] ", JSON.stringify({
			"candidate_count": candidate_count,
			"transaction_ms": float(transaction_finished_usec - profile_started_usec) / 1000.0,
			"feedback_ms": float(Time.get_ticks_usec() - transaction_finished_usec) / 1000.0,
			"total_ms": float(Time.get_ticks_usec() - profile_started_usec) / 1000.0,
			"transaction": _world.profile._last_loot_batch_profile.duplicate(true),
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
	if not _world.is_inside_world() or generation != _zone_generation or not is_finite(seconds) or seconds < 0.0:
		return
	if not _world.world_context.matches_world(_feature_target_bound.snapshot().get("world", {})):
		return
	var raw_base_seconds: Variant = spawn_context.get("respawn_base_seconds", seconds)
	if not raw_base_seconds is int and not raw_base_seconds is float:
		return
	var base_seconds: float = float(raw_base_seconds)
	var admission: Variant = _feature_target_bound.admit_base(
		_strict_runtime_monster_id(monster_data), spawn_position, base_seconds, spawn_context)
	if not bool(admission.get("accepted", false)):
		return
	var wakeup: Variant = _world.create_timer(seconds)
	var identity: Variant = wakeup.get_instance_id()
	_respawn_wakeups[identity] = wakeup
	await wakeup.timeout
	# A retired owner may have re-entered the tree before the cancelled timer
	# is reclaimed. Only a still-owned wakeup can attempt the original spawn.
	if not _respawn_wakeups.erase(identity):
		return
	if not _world.is_inside_world() or generation != _zone_generation:
		return
	var slot_id: Variant = str(spawn_context.get("spawn_slot_id", ""))
	if not slot_id.is_empty() and _spawn_slot_is_alive(slot_id, generation):
		return
	_spawn_enemy(
		monster_data,
		spawn_position,
		is_boss,
		float(spawn_context.get("respawn_base_seconds", seconds)),
		spawn_context
	)


func _spawn_slot_is_alive(slot_id: String, generation: int, owned_only := false) -> bool:
	# Fatal HP removes the receiver from `enemies` immediately; its body and
	# deferred callbacks still belong to this factory until queued retirement.
	var candidates: Array=_ports.original_owned_root_actor_models() if owned_only else _world.skills._actors.actors_in_group("enemies")
	for value: Variant in candidates:
		if _world.skill_actors.is_kind(value, &"enemy") and not _world.skill_actors.is_queued_for_retirement(value):
			if str(value.read_meta("spawn_slot_id", "")) == slot_id and int(value.read_meta("zone_generation", -1)) == generation:
				if not owned_only or _ports.original_root_is_ancestor_of_actor(value):
					return true
	return false


func _hc_m30_get_summon_queue() -> RefCounted:
	if not _world.service_registry.service_model_runtime_present(_hc_m30_summon_queue):
		_hc_m30_summon_queue = _world.create_unconfigured_original_m30_summon_queue(self)
		if _hc_m30_summon_queue==null:
			_world.fault("MISSING_actual_M30_constructor_scope",{});return null
		_hc_m30_summon_queue.configure(self)
		if _world.is_faulted() or not _world.enter_original_m30_summon_queue_at_child_boundary(_hc_m30_summon_queue): return null
	return _hc_m30_summon_queue


func _hc_m30_landing_clear(candidate_gu: Vector2, radius_gu: float, ignored_enemy: Object) -> bool:
	if not candidate_gu.is_finite() or not is_finite(radius_gu) or radius_gu < 0.0:
		return false
	if not is_instance_valid(_world.environment) or _world.spatial == null or current_map_id < 0:
		return false
	if not bool(_safe_zone_context.get("valid", false)):
		return false
	if WorldSpatialRulesScript.point_inside_safe_zones_ground_gu(candidate_gu, _active_safe_zones):
		return false
	var candidate_px: Vector2 = _canonical_ground_gu_to_screen_px(candidate_gu)
	var radius_px: float = WorldSpatialRulesScript.actor_screen_radius_px_from_combat_radius_gu(radius_gu)
	if not candidate_px.is_finite() or WorldSpatialRulesScript.environment_blocks_actor_screen_px(_world.environment, candidate_px, radius_px):
		return false
	if _world.skill_actors.is_runtime_present(_world.skills.player):
		var player_gu: Vector2 = _canonical_screen_px_to_ground_gu(_world.skills.player.global_position)
		var player_radius: float = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.PLAYER_COLLISION_RADIUS_PX)
		if not player_gu.is_finite() or player_gu.distance_to(candidate_gu) < radius_gu + player_radius + ACTOR_LANDING_CLEARANCE_GU:
			return false
	# Degenerate segment = point AABB. The index itself adds max actor bounds.
	# Use the unsorted API: occupancy is existence, not a selected damage victim.
	_world.spatial.query_enemy_nodes_segment_unsorted_into(
		current_map_id, candidate_gu, candidate_gu,
		radius_gu + ENEMY_LANDING_CLEARANCE_GU, _hc_m30_landing_scratch)
	for raw: Variant in _hc_m30_landing_scratch:
		if not is_instance_valid(raw) or not _world.skill_actors.is_kind(raw, &"enemy"):
			continue
		var other: Object = raw
		if other == ignored_enemy or _world.skill_actors.is_queued_for_retirement(other) or other.current_hp <= 0 or other._death_pending or other._dying:
			continue
		if other.runtime_map_id != current_map_id or int(other.read_meta("zone_generation", -1)) != _zone_generation:
			continue
		var other_gu: Vector2 = other.spatial_index_position()
		if not other_gu.is_finite():
			return false
		if other_gu.distance_to(candidate_gu) < radius_gu + other.combat_radius_gu + ENEMY_LANDING_CLEARANCE_GU:
			return false
	return true


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


func _allocate_synthetic_attack_token() -> int:
	return _world.skills.callv(&"_allocate_synthetic_attack_token", [])


func _cancel_all_combat_targets() -> void:
	_world.skills.callv(&"_cancel_all_combat_targets", [])


func _cancel_all_mobile_attack_inputs(_clear_tickets := false) -> void:
	_world.skills.callv(&"_cancel_all_mobile_attack_inputs", [_clear_tickets])


func _cancel_all_skill_inputs(clear_tickets := false) -> void:
	_world.skills.callv(&"_cancel_all_skill_inputs", [clear_tickets])


func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2:
	return _world.skills.callv(&"_canonical_ground_gu_to_screen_px", [ground_position_gu])


func _canonical_screen_px_to_ground_gu(screen_position_px: Vector2) -> Vector2:
	return _world.skills.callv(&"_canonical_screen_px_to_ground_gu", [screen_position_px])


func _enemy_instance_ids(enemies: Array[Object]) -> Array[int]:
	return _world.skills.callv(&"_enemy_instance_ids", [enemies])


func _expire_canonical_fire_charge_if_needed() -> void:
	_world.skills.callv(&"_expire_canonical_fire_charge_if_needed", [])


func _ground_position_gu_for_map(
	map_id: int,
	screen_position_px: Vector2
) -> Vector2:
	return _world.skills.callv(&"_ground_position_gu_for_map", [map_id, screen_position_px])


func _melee_candidate_diagnostics(
	origin: Vector2,
	direction_index: int,
	mode: String,
	primary_targets: Array[Object]
) -> Array[Dictionary]:
	return _world.skills.callv(&"_melee_candidate_diagnostics", [origin, direction_index, mode, primary_targets])


func _melee_diagnostic_result_code(
	has_eligible_target: bool,
	canonical_resolution: String,
	hit_any: bool,
	hit_attempts: Array[Dictionary]
) -> String:
	return _world.skills.callv(&"_melee_diagnostic_result_code", [has_eligible_target, canonical_resolution, hit_any, hit_attempts])


func _melee_direction_index(
	direction: Vector2,
	release_geometry: Dictionary = {}
) -> int:
	return _world.skills.callv(&"_melee_direction_index", [direction, release_geometry])


func _on_skill_input_ended(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	_source: StringName
) -> void:
	_world.skills.callv(&"_on_skill_input_ended", [slot_group, slot_index, press_token, touch_id, _source])


func _on_skill_input_started(
	slot_group: String,
	slot_index: int,
	press_token: int,
	touch_id: int,
	source: StringName
) -> void:
	_world.skills.callv(&"_on_skill_input_started", [slot_group, slot_index, press_token, touch_id, source])


func _poll_attack_action_lifecycle(input_enabled: bool) -> Dictionary:
	return _world.skills.callv(&"_poll_attack_action_lifecycle", [input_enabled])


func _process_magic_shield_auto_refresh(delta: float) -> void:
	_world.skills.callv(&"_process_magic_shield_auto_refresh", [delta])


func _process_ordinary_attack_input(attack_action_lifecycle: Dictionary) -> void:
	_world.skills.callv(&"_process_ordinary_attack_input", [attack_action_lifecycle])


func _process_skill_input_actions(delta: float) -> void:
	_world.skills.callv(&"_process_skill_input_actions", [delta])


func _refresh_player_safe_zone_cache(force := false) -> bool:
	return _world.skills.callv(&"_refresh_player_safe_zone_cache", [force])


func _reset_attack_action_lifecycle(reason: StringName) -> void:
	_world.skills.callv(&"_reset_attack_action_lifecycle", [reason])


func _retry_pending_main_pet_arrivals() -> void:
	_world.skills.callv(&"_retry_pending_main_pet_arrivals", [])


func _target_spatial_query_aabb_into(
	bounds_ground_gu: Rect2,
	output: Array[Object],
	stable_order: bool = true,
) -> bool:
	return _world.skills.callv(&"_target_spatial_query_aabb_into", [bounds_ground_gu, output, stable_order])


func _tick_ongoing_heals(delta: float) -> void:
	_world.skills.callv(&"_tick_ongoing_heals", [delta])


func _try_canonical_screen_px_to_ground_gu(
	screen_position_px: Vector2
) -> Dictionary:
	return _world.skills.callv(&"_try_canonical_screen_px_to_ground_gu", [screen_position_px])


func _use_skill_slot(slot_group: String, slot_index: int) -> void:
	_world.skills.callv(&"_use_skill_slot", [slot_group, slot_index])


func _validate_locked_target() -> void:
	_world.skills.callv(&"_validate_locked_target", [])

func _model_for_runtime_actor_id(runtime_id: int) -> Object:
	var handle: Object = _world.registry.resolve_runtime_actor(runtime_id)
	return handle.model() if handle != null and handle.runtime_object_is_present() else null

func required_owner_service(name: StringName) -> RefCounted:
	return _world.required_owner_service(name)

func defer_original_actor_callback(_runtime_id: int, callback: Callable) -> void:
	assert(_world._host.source_deferred_queue_configured())
	callback.call_deferred()

func defer_original_root_member(member: StringName, argument: Variant) -> void:
	assert(_world._host.source_deferred_queue_configured())
	Callable(self, member).call_deferred(argument)

func original_deferred_message_queue_flush(domain: StringName, boundary: StringName) -> bool:
	return _world._host.flush_source_deferred(domain, boundary)

func _hc_m30_probe_landing(origin_screen_px: Vector2) -> Vector2:
	var origin_gu: Vector2 = _canonical_screen_px_to_ground_gu(origin_screen_px)
	if not origin_gu.is_finite():
		return Vector2.INF
	# Preserve the existing angle/radius distribution (NOT uniform-area sampling).
	var candidate_gu: Vector2 = origin_gu + Vector2.from_angle(_rng.randf_range(0.0, TAU)) * _rng.randf_range(1.5, 6.0)
	# This is deliberately the SAME radius as the original summon call site.
	var radius_gu: float = WorldSpatialRulesScript.actor_combat_radius_gu_from_screen_radius_px(ArtSpec.MONSTER_COLLISION_RADIUS_PX)
	return _canonical_ground_gu_to_screen_px(candidate_gu) if _hc_m30_landing_clear(candidate_gu, radius_gu, null) else Vector2.INF


func _hc_m30_materialize(monster: Dictionary, candidate_px: Vector2, context: Dictionary) -> Object:
	# Return through the canonical spawn authority; no parallel Object factory.
	return _spawn_enemy(monster, candidate_px, false, DEFAULT_NORMAL_RESPAWN_SECONDS, context)


func _hc_m30_summon_request_valid(source: Object, ids: Array, count: int, maximum: int) -> bool:
	if not is_instance_valid(source):
		return false
	return _feature_target_bound.summon_request_valid(
		str(source.read_meta("spawn_slot_id", "")), source.monster_id, ids, count, maximum)


func _hc_m30_resolve_monster(raw_id: Variant) -> Dictionary:
	if not raw_id is int and not raw_id is float:
		return {}
	if float(raw_id) != floorf(float(raw_id)):
		return {}
	var inputs: RefCounted = _feature_target_bound.monster_inputs(int(raw_id))
	return inputs.view().entry if inputs != null else {}


func hc_m30_summon_snapshot() -> Dictionary:
	return _hc_m30_summon_queue.snapshot() if is_instance_valid(_hc_m30_summon_queue) else {"pending_batches": 0}
