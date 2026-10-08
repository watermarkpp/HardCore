# Unknown owner audit V2 — fixed107 edae6fde

All mapping uses fixed git bytes from research commit edae6fdef6a6551a951fab1ea8c6ade43359d603. Exact method-name matching only; line numbers are retained profile evidence, never nearest-function inference.

## Group totals

| owner kind | signatures | calls | self ms | inclusive ms | internal ms |
|---|---:|---:|---:|---:|---:|
| budget_admission_or_scheduler | 15 | 70372 | 56.038 | 119.721 | 0.637 |
| poly_index_geometry | 11 | 123580 | 76.209 | 168.895 | 0.327 |
| poly_nav_path_dependency | 15 | 72 | 0.112 | 3.883 | 0.005 |
| poly_runtime_callee | 3 | 8084 | 21.337 | 148.461 | 0 |
| script_function_exact | 554 | 2478414 | 1197.321 | 11910.439 | 525.845 |
| shared_builtin_or_native | 68 | 1176471 | 107.372 | 107.372 | 107.361 |
| test_fixture | 9 | 14179 | 44.279 | 157.608 | 10.757 |

Source symbol mapping does not establish caller causality and does not imply all mapped self time is portable. MISSING and generated getters are never proportionally assigned.

The 675 unknown set contains no RuntimeDiagnostics observer signatures; those remain in the existing diagnostic category and are not reassigned. The 15 budget signatures are kept as real admission/scheduler owner mappings.

## Poly boundary

Core poly_index + poly_geometry: 11 signatures, 123580 calls, 76.209 self ms, 168.895 inclusive ms. poly_runtime actual callees: 3 signatures; poly_nav_graph/poly_path_search dependencies: 15 signatures. Kept separate; no 50% claim.

## Exact mapping failures

Failure/unresolved records: 13. No nearest-line fallback.

- `res://tests/crowd_engagement_scaling_20261008.gd::37::_physics_process` — source_present_no_exact_func_name — fixed source=tests/crowd_engagement_scaling_20261008.gd
- `res://tests/crowd_engagement_scaling_20261008.gd::283::_count_scaling_targeting` — source_present_no_exact_func_name — fixed source=tests/crowd_engagement_scaling_20261008.gd
- `res://tests/crowd_engagement_scaling_20261008.gd::97::_run` — source_present_no_exact_func_name — fixed source=tests/crowd_engagement_scaling_20261008.gd
- `res://scripts/map_coordinate_mapper.gd::75::MapCoordinateMapper.<anonymous lambda>(lambda)` — source_present_no_exact_func_name — fixed source=scripts/map_coordinate_mapper.gd
- `res://scripts/enemy.gd::341::EnemyActor.@control_time_setter` — source_present_no_exact_func_name — fixed source=scripts/enemy.gd
- `res://scripts/map_coordinate_mapper.gd::80::MapCoordinateMapper.<anonymous lambda>(lambda)` — source_present_no_exact_func_name — fixed source=scripts/map_coordinate_mapper.gd
- `res://scripts/enemy.gd::348::EnemyActor.@charm_time_setter` — source_present_no_exact_func_name — fixed source=scripts/enemy.gd
- `res://tests/world_crowd_firewall_profile_test.gd::24::PhysicsFrameStart._physics_process` — exact_func_name_multiple_matches — fixed source=tests/world_crowd_firewall_profile_test.gd
- `res://scripts/enemy.gd::307::EnemyActor.@target_setter` — source_present_no_exact_func_name — fixed source=scripts/enemy.gd
- `res://scripts/player_state.gd::175::@profession_id_getter` — generated_property_getter — fixed source=scripts/player_state.gd
- `res://scripts/runtime_combat_spatial_index.gd::527::RuntimeCombatSpatialIndex.<anonymous lambda>(lambda)` — source_present_no_exact_func_name — fixed source=scripts/runtime_combat_spatial_index.gd
- `res://scripts/player_state.gd::233::@attack_skill_slots_getter` — generated_property_getter — fixed source=scripts/player_state.gd
- `res://scripts/game_root.gd::1735::<anonymous lambda>(lambda)` — source_present_no_exact_func_name — fixed source=scripts/game_root.gd

## Exact records

| signature | kind | status | calls | self ms | inclusive ms | exact function |
|---|---|---|---:|---:|---:|---|
| `res://scripts/monster_visual.gd::504::MonsterVisual._update_animation_frame` | script_function_exact | exact_func_name_match | 21828 | 50.5 | 160.356 | 503 func _update_animation_frame(delta: float) -> void: |
| `res://scripts/runtime_combat_spatial_index.gd::382::RuntimeCombatSpatialIndex._query_enemy_nodes_in_aabb` | script_function_exact | exact_func_name_match | 4500 | 48.551 | 74.056 | 374 func _query_enemy_nodes_in_aabb( |
| `res://scripts/enemy.gd::2786::EnemyActor._physics_process_internal` | script_function_exact | exact_func_name_match | 10200 | 48.484 | 3178.545 | 2785 func _physics_process_internal(delta: float) -> void: |
| `res://scripts/game_root.gd::12140::_resolve_projection_profile_for_map` | script_function_exact | exact_func_name_match | 23768 | 42.844 | 66.677 | 12136 func _resolve_projection_profile_for_map(map_id: int) -> Dictionary: |
| `res://scripts/enemy.gd::9639::EnemyActor._hc_environment_revision` | script_function_exact | exact_func_name_match | 137030 | 41.936 | 83.726 | 9638 func _hc_environment_revision() -> int: |
| `res://scripts/enemy.gd::3563::EnemyActor._point_inside_safe_zone` | script_function_exact | exact_func_name_match | 57755 | 34.763 | 63.551 | 3556 func _point_inside_safe_zone(point_screen_px: Vector2, known_hc_cache := false) -> bool: |
| `res://scripts/enemy.gd::0::Object.get_meta` | shared_builtin_or_native | builtin_or_native_line_zero | 286646 | 32.061 | 32.061 | — |
| `res://scripts/ground_unit_space.gd::66::GroundUnitSpace.screen_delta_px_to_ground_delta_gu` | script_function_exact | exact_func_name_match | 154098 | 24.728 | 24.728 | 65 static func screen_delta_px_to_ground_delta_gu(screen_delta_px: Vector2) -> Vector2: |
| `res://tests/crowd_engagement_scaling_20261008.gd::37::_physics_process` | test_fixture | source_present_no_exact_func_name | 300 | 24.043 | 110.389 | — |
| `res://scripts/enemy.gd::8910::EnemyActor._hc_life` | script_function_exact | exact_func_name_match | 69249 | 23.511 | 28.132 | 8909 func _hc_life(node: Node) -> int: |
| `res://scripts/map_editor/polygon/poly_index.gd::86::capsule_blocked` | poly_index_geometry | exact_func_name_match | 7133 | 23.387 | 52.986 | 85 func capsule_blocked(a: Vector2, b: Vector2, radius_gu: float) -> bool: |
| `res://scripts/enemy.gd::9528::EnemyActor._hc_decision_scope` | script_function_exact | exact_func_name_match | 20815 | 23.162 | 84.227 | 9527 func _hc_decision_scope() -> Array: |
| `res://scripts/map_editor/polygon/poly_index.gd::72::inside` | poly_index_geometry | exact_func_name_match | 67034 | 21.55 | 21.55 | 71 func inside(p: Vector2, radius_gu := 0.0) -> bool: |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::452::MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu` | script_function_exact | exact_func_name_match | 27424 | 20.757 | 55.435 | 448 static func screen_position_px_to_ground_position_gu( |
| `res://scripts/enemy.gd::8044::EnemyActor._target_candidate_is_live` | script_function_exact | exact_func_name_match | 19916 | 20.56 | 48.643 | 8043 func _target_candidate_is_live(candidate: Node2D) -> bool: |
| `res://scripts/world_spatial_rules.gd::47::WorldSpatialRules.actor_footprint_offset_px` | script_function_exact | exact_func_name_match | 63040 | 20.228 | 37.522 | 43 static func actor_footprint_offset_px( |
| `res://scripts/enemy.gd::9405::EnemyActor._hc_step_can_end` | script_function_exact | exact_func_name_match | 14902 | 18.948 | 98.216 | 9404 func _hc_step_can_end() -> bool: |
| `res://scripts/map_editor/polygon/poly_runtime.gd::158::actor_world` | poly_runtime_callee | exact_func_name_match | 3298 | 18.559 | 107.186 | 157 static func actor_world(snapshot: Dictionary, center_px: Vector2, offsets_px: PackedVector2Array) -> bool: |
| `res://scripts/map_editor/map_editor_coordinate.gd::122::MapEditorCoordinate.screen_position_px_to_ground_position_gu` | script_function_exact | exact_func_name_match | 80192 | 17.684 | 44.3 | 118 static func screen_position_px_to_ground_position_gu( |
| `res://scripts/monster_visual.gd::390::MonsterVisual._process` | script_function_exact | exact_func_name_match | 21828 | 17.02 | 258.069 | 389 func _process(delta: float) -> void: |
| `res://scripts/enemy.gd::9145::EnemyActor._source176_take_tick_decision` | script_function_exact | exact_func_name_match | 18273 | 16.726 | 59.797 | 9144 func _source176_take_tick_decision() -> bool: |
| `res://scripts/enemy.gd::7018::EnemyActor.performance_diagnostics` | script_function_exact | exact_func_name_match | 301 | 16.092 | 42.149 | 7017 static func performance_diagnostics() -> Dictionary: |
| `res://scripts/map_editor/polygon/poly_index.gd::107::footprint_blocked` | poly_index_geometry | exact_func_name_match | 3298 | 15.991 | 52.308 | 106 func footprint_blocked(footprint_ground_gu: PackedVector2Array) -> bool: |
| `res://scripts/world_spatial_rules.gd::592::WorldSpatialRules.actor_footprint_polygon_px` | script_function_exact | exact_func_name_match | 3940 | 14.809 | 67.1 | 588 static func actor_footprint_polygon_px( |
| `res://scripts/enemy.gd::8654::EnemyActor._source176_ordinary_melee` | script_function_exact | exact_func_name_match | 49126 | 13.823 | 85.002 | 8653 func _source176_ordinary_melee() -> bool: |
| `res://scripts/ground_unit_space.gd::51::GroundUnitSpace.projection_result` | script_function_exact | exact_func_name_match | 23126 | 12.988 | 12.988 | 46 static func projection_result( |
| `res://scripts/game_root.gd::12184::_try_canonical_screen_px_to_ground_gu` | script_function_exact | exact_func_name_match | 16247 | 12.768 | 137.51 | 12177 func _try_canonical_screen_px_to_ground_gu( |
| `res://scripts/enemy.gd::8750::EnemyActor._hc_target_usable` | script_function_exact | exact_func_name_match | 10578 | 12.294 | 67.584 | 8749 func _hc_target_usable(hit_target: Node2D) -> bool: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::145::end` | budget_admission_or_scheduler | exact_func_name_match | 2589 | 11.979 | 17.943 | 144 static func end(token: int) -> void: |
| `res://scripts/enemy.gd::7662::EnemyActor._update_status_effects` | script_function_exact | exact_func_name_match | 9040 | 11.641 | 19.417 | 7661 func _update_status_effects(delta: float) -> void: |
| `res://scripts/enemy.gd::7044::EnemyActor._can_use_background_ai` | script_function_exact | exact_func_name_match | 10280 | 11.594 | 28.363 | 7043 func _can_use_background_ai() -> bool: |
| `res://scripts/monster_source176/source_melee_geometry.gd::13::continuous_adjacent` | script_function_exact | exact_func_name_match | 24672 | 11.379 | 11.379 | 12 static func continuous_adjacent(offset: Vector2, epsilon: float = EPSILON_GU) -> bool: |
| `res://scripts/player_visual.gd::197::_process` | script_function_exact | exact_func_name_match | 642 | 11.351 | 53.524 | 196 func _process(delta: float) -> void: |
| `res://scripts/monster_visual.gd::1465::MonsterVisual.uses_final_art` | script_function_exact | exact_func_name_match | 27053 | 10.757 | 10.757 | 1464 func uses_final_art() -> bool: |
| `res://scripts/monster_visual.gd::405::MonsterVisual._advance_action_timers` | script_function_exact | exact_func_name_match | 21828 | 10.707 | 24.695 | 404 func _advance_action_timers(delta: float) -> void: |
| `res://scripts/game_root.gd::1850::_process` | script_function_exact | exact_func_name_match | 642 | 10.496 | 250.504 | 1849 func _process(delta: float) -> void: |
| `res://tests/world_crowd_firewall_profile_test.gd::0::Time.get_ticks_usec` | shared_builtin_or_native | builtin_or_native_line_zero | 166328 | 10.457 | 10.457 | — |
| `res://scripts/layers/runtime/execution/frame_budget.gd::54::mark_pending` | budget_admission_or_scheduler | exact_func_name_match | 7520 | 10.442 | 24.3 | 53 static func mark_pending(category: String, has_pending: bool, runnable := true, runs_when_paused := false, process_owner: Node = null, physics_owner := false) -> void: |
| `res://scripts/enemy.gd::9460::EnemyActor._hc_static_query_scope` | script_function_exact | exact_func_name_match | 5004 | 10.223 | 16.468 | 9459 func _hc_static_query_scope(include_safe_zone_owner: bool) -> Array: |
| `res://scripts/monster_movement_cadence.gd::228::MonsterMovementCadence.evaluate_grant` | script_function_exact | exact_func_name_match | 10200 | 10.151 | 20.237 | 227 func evaluate_grant(now_ms: Variant) -> bool: |
| `res://scripts/monster_visual_streaming_coordinator.gd::1405::MonsterVisualStreamingCoordinator._poll_visual_residency` | script_function_exact | exact_func_name_match | 518 | 9.75 | 32.455 | 1404 func _poll_visual_residency() -> void: |
| `res://scripts/enemy.gd::2769::EnemyActor._physics_process` | script_function_exact | exact_func_name_match | 10200 | 9.399 | 3253.229 | 2768 func _physics_process(delta: float) -> void: |
| `res://scripts/enemy.gd::6678::EnemyActor._runtime_map_id_for_area_target` | script_function_exact | exact_func_name_match | 19916 | 9.321 | 13.567 | 6677 func _runtime_map_id_for_area_target(victim: Node2D) -> int: |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::371::MapEditorRuntimeBridge.load_map` | script_function_exact | exact_func_name_match | 35587 | 9.161 | 13.038 | 370 static func load_map(runtime_map_id: int) -> Dictionary: |
| `res://scripts/enemy.gd::7335::EnemyActor.can_receive_damage` | script_function_exact | exact_func_name_match | 28330 | 9.118 | 10.254 | 7327 func can_receive_damage() -> bool: |
| `res://scripts/art_spec.gd::63::mir2_client_direction_row` | script_function_exact | exact_func_name_match | 22470 | 8.731 | 19.692 | 61 static func mir2_client_direction_row(direction: Vector2) -> int: |
| `res://scripts/monster_natural_regen_policy.gd::70::MonsterNaturalRegenPolicy._result` | script_function_exact | exact_func_name_match | 9040 | 8.551 | 8.551 | 69 func _result(hp: int, healed: int, ticks: int) -> Dictionary: |
| `res://scripts/monster_visual.gd::958::MonsterVisual._direction_row` | script_function_exact | exact_func_name_match | 21828 | 8.442 | 47.881 | 957 func _direction_row(direction: Vector2) -> int: |
| `res://scripts/monster_natural_regen_policy.gd::27::MonsterNaturalRegenPolicy.advance` | script_function_exact | exact_func_name_match | 9040 | 7.791 | 19.088 | 26 func advance(delta_seconds: float, current_hp: int, max_hp: int) -> Dictionary: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::119::begin` | budget_admission_or_scheduler | exact_func_name_match | 2712 | 7.743 | 24.553 | 118 static func begin(category: String, necessary := false) -> int: |
| `res://scripts/enemy.gd::6087::EnemyActor._uses_ranged_projectile_sweep_contract` | script_function_exact | exact_func_name_match | 124437 | 7.675 | 7.675 | 6086 func _uses_ranged_projectile_sweep_contract() -> bool: |
| `res://scripts/monster_ai_package/decision_budget.gd::74::begin` | script_function_exact | exact_func_name_match | 1051 | 7.525 | 49.905 | 73 static func begin(owner: Node, scope: Array, kind: StringName = &"observation") -> int: |
| `res://scripts/world_background.gd::338::WorldBackground.environment_collision_revision` | script_function_exact | exact_func_name_match | 137030 | 7.147 | 7.147 | 337 func environment_collision_revision() -> int: |
| `res://scripts/enemy.gd::8662::EnemyActor._source176_melee_reach_ok` | script_function_exact | exact_func_name_match | 24623 | 6.973 | 25.155 | 8661 func _source176_melee_reach_ok(offset_gu: Vector2, tolerance: float) -> bool: |
| `res://scripts/game_root.gd::1991::_update_world_camera_constraint` | script_function_exact | exact_func_name_match | 642 | 6.941 | 15.531 | 1990 func _update_world_camera_constraint(delta := 1.0 / 60.0) -> void: |
| `res://scripts/runtime_combat_spatial_index.gd::137::RuntimeCombatSpatialIndex.update_actor` | script_function_exact | exact_func_name_match | 7420 | 6.793 | 13.895 | 136 func update_actor(actor_runtime_id: int, absolute_ground_gu: Vector2) -> void: |
| `res://tests/crowd_engagement_scaling_20261008.gd::283::_count_scaling_targeting` | test_fixture | source_present_no_exact_func_name | 900 | 6.559 | 6.559 | — |
| `res://scripts/monster_visual.gd::1532::MonsterVisual.hc_m30_accept_ground_motion` | script_function_exact | exact_func_name_match | 7831 | 6.497 | 12.829 | 1531 func hc_m30_accept_ground_motion(distance_gu: float) -> void: |
| `res://scripts/monster_visual_streaming_coordinator.gd::0::Object.has_method` | shared_builtin_or_native | builtin_or_native_line_zero | 101917 | 6.428 | 6.428 | — |
| `res://scripts/enemy.gd::8350::EnemyActor._request_actor_redraw_if_dynamic_internal` | script_function_exact | exact_func_name_match | 9000 | 6.403 | 35.603 | 8349 func _request_actor_redraw_if_dynamic_internal() -> void: |
| `res://scripts/enemy.gd::0::PhysicsDirectSpaceState2D.intersect_ray` | shared_builtin_or_native | builtin_or_native_line_zero | 2332 | 6.346 | 6.346 | — |
| `res://scripts/enemy.gd::8739::EnemyActor._hc_preferred` | script_function_exact | exact_func_name_match | 9277 | 6.248 | 28.798 | 8737 func _hc_preferred(hit_target: Node2D) -> float: |
| `res://scripts/game_root.gd::12264::_canonical_screen_px_to_ground_gu` | script_function_exact | exact_func_name_match | 16247 | 6.113 | 153.214 | 12263 func _canonical_screen_px_to_ground_gu(screen_position_px: Vector2) -> Vector2: |
| `res://scripts/art_spec.gd::56::direction_index` | script_function_exact | exact_func_name_match | 22734 | 6.059 | 6.059 | 55 static func direction_index(direction: Vector2) -> int: |
| `res://scripts/monster_visual.gd::556::MonsterVisual._inside_visual_distance_px` | script_function_exact | exact_func_name_match | 6216 | 5.896 | 7.884 | 555 func _inside_visual_distance_px(distance_px: float) -> bool: |
| `res://scripts/monster_visual.gd::1552::MonsterVisual._hc_m30_is_walking` | script_function_exact | exact_func_name_match | 21064 | 5.867 | 10.539 | 1551 func _hc_m30_is_walking() -> bool: |
| `res://scripts/monster_visual_streaming_coordinator.gd::1368::MonsterVisualStreamingCoordinator._cleanup_invalid_subscribers` | script_function_exact | exact_func_name_match | 514 | 5.752 | 8.328 | 1367 func _cleanup_invalid_subscribers() -> void: |
| `res://scripts/world_spatial_rules.gd::33::WorldSpatialRules._actor_footprint_directions` | script_function_exact | exact_func_name_match | 63040 | 5.526 | 5.526 | 32 static func _actor_footprint_directions() -> PackedVector2Array: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::26::_sync_epoch` | budget_admission_or_scheduler | exact_func_name_match | 14518 | 5.422 | 13.573 | 25 static func _sync_epoch() -> bool: |
| `res://scripts/layers/presentation/monster_animation_policy.gd::42::MonsterAnimationPolicy.frame_count` | script_function_exact | exact_func_name_match | 21580 | 5.315 | 12.375 | 41 static func frame_count(profile: Dictionary, action: StringName) -> int: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::20::_current_epoch` | budget_admission_or_scheduler | exact_func_name_match | 19696 | 5.294 | 6.226 | 19 static func _current_epoch() -> int: |
| `res://scripts/runtime_combat_spatial_index.gd::338::RuntimeCombatSpatialIndex.query_enemy_nodes_bucket_segment_into` | script_function_exact | exact_func_name_match | 3505 | 5.241 | 75.929 | 337 func query_enemy_nodes_bucket_segment_into(runtime_map_id: int, a: Vector2, b: Vector2, expansion_gu: float, output: Array) -> Rect2i: |
| `res://scripts/enemy.gd::1856::EnemyActor._begin_autonomous_step_without_cadence` | script_function_exact | exact_func_name_match | 970 | 5.211 | 524.023 | 1847 func _begin_autonomous_step_without_cadence( |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::430::MapEditorRuntimeBridge.ground_position_gu_to_screen_position_px` | script_function_exact | exact_func_name_match | 6879 | 5.188 | 14.294 | 426 static func ground_position_gu_to_screen_position_px( |
| `res://scripts/monster_visual.gd::1516::MonsterVisual.hc_m30_finish_locomotion_tick` | script_function_exact | exact_func_name_match | 10200 | 5.179 | 7.137 | 1515 func hc_m30_finish_locomotion_tick(intent: bool, physics_delta: float) -> void: |
| `res://scripts/enemy.gd::3116::EnemyActor._handle_safe_zone_target_return` | script_function_exact | exact_func_name_match | 8677 | 4.796 | 15.994 | 3115 func _handle_safe_zone_target_return(physics_delta: float) -> bool: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::47::_category` | budget_admission_or_scheduler | exact_func_name_match | 5301 | 4.77 | 5.579 | 46 static func _category(name: String) -> Dictionary: |
| `res://scripts/game_root.gd::0::Object.get_instance_id` | shared_builtin_or_native | builtin_or_native_line_zero | 111064 | 4.75 | 4.75 | — |
| `res://scripts/runtime_combat_spatial_index.gd::680::RuntimeCombatSpatialIndex._bucket_key` | script_function_exact | exact_func_name_match | 33528 | 4.737 | 4.737 | 679 func _bucket_key(absolute_ground_gu: Vector2) -> Vector2i: |
| `res://scripts/game_root.gd::12225::_try_canonical_ground_gu_to_screen_px` | script_function_exact | exact_func_name_match | 6879 | 4.725 | 50.181 | 12222 func _try_canonical_ground_gu_to_screen_px( |
| `res://scripts/loot_pickup_runtime_manager.gd::0::Object.is_queued_for_deletion` | shared_builtin_or_native | builtin_or_native_line_zero | 115575 | 4.597 | 4.597 | — |
| `res://scripts/device_lab_runtime.gd::0::FileAccess.file_exists` | shared_builtin_or_native | builtin_or_native_line_zero | 32 | 4.469 | 4.469 | — |
| `res://scripts/hud_resource_orb.gd::0::CanvasItem.draw_multiline_string` | shared_builtin_or_native | builtin_or_native_line_zero | 28 | 4.435 | 4.435 | — |
| `res://scripts/enemy.gd::8336::EnemyActor._request_actor_redraw_if_dynamic` | script_function_exact | exact_func_name_match | 9000 | 4.379 | 85.951 | 8335 func _request_actor_redraw_if_dynamic() -> void: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::347::MapEditorRuntimeCollisionGeometryService.project_world_envelope_inside_visible_boundary` | script_function_exact | exact_func_name_match | 642 | 4.358 | 11.683 | 342 static func project_world_envelope_inside_visible_boundary( |
| `res://scripts/json_persistence_service.gd::105::pump` | script_function_exact | exact_func_name_match | 1284 | 4.256 | 13.108 | 104 func pump(wait := false) -> bool: |
| `res://scripts/monster_crowd_attack_position_policy.gd::128::contact_leg_with_snapshot` | script_function_exact | exact_func_name_match | 336 | 4.231 | 11.627 | 127 static func contact_leg_with_snapshot(actor: CharacterBody2D, hit_target: Node2D, origin: Vector2, direction: Vector2, snapshot: Array) -> Vector2: |
| `res://scripts/enemy.gd::2176::EnemyActor._live_continuous_pursuit_target` | script_function_exact | exact_func_name_match | 6275 | 4.04 | 4.27 | 2175 func _live_continuous_pursuit_target() -> Node2D: |
| `res://scripts/ground_unit_space.gd::59::GroundUnitSpace.ground_delta_gu_to_screen_delta_px` | script_function_exact | exact_func_name_match | 24934 | 4.017 | 4.017 | 58 static func ground_delta_gu_to_screen_delta_px(ground_delta_gu: Vector2) -> Vector2: |
| `res://scripts/monster_visual.gd::1061::MonsterVisual._apply_render_state` | script_function_exact | exact_func_name_match | 2012 | 4.015 | 9.61 | 1060 func _apply_render_state(texture: Texture2D, region: Rect2) -> void: |
| `res://scripts/player.gd::257::PlayerCharacter._physics_process` | script_function_exact | exact_func_name_match | 300 | 3.994 | 104.424 | 256 func _physics_process(delta: float) -> void: |
| `res://scripts/runtime_combat_spatial_index.gd::783::RuntimeCombatSpatialIndex.query_enemy_nodes_segment_batch_into` | script_function_exact | exact_func_name_match | 82 | 3.978 | 11.537 | 775 func query_enemy_nodes_segment_batch_into( |
| `res://scripts/layers/presentation/monster_animation_policy.gd::11::MonsterAnimationPolicy.direction_row` | script_function_exact | exact_func_name_match | 21828 | 3.931 | 28.349 | 10 static func direction_row(direction: Vector2, mode: StringName) -> int: |
| `res://scripts/monster_ai_package/decision_budget.gd::31::_valid` | script_function_exact | exact_func_name_match | 3127 | 3.859 | 16.629 | 30 static func _valid(owner: Node, scope: Array, caller: Node = null) -> bool: |
| `res://scripts/world_spatial_rules.gd::486::WorldSpatialRules.environment_blocks_actor_screen_px` | script_function_exact | exact_func_name_match | 3298 | 3.79 | 207.129 | 481 static func environment_blocks_actor_screen_px( |
| `res://scripts/runtime_combat_spatial_index.gd::363::RuntimeCombatSpatialIndex._enemy_node_bucket_segment_envelope` | script_function_exact | exact_func_name_match | 8547 | 3.771 | 3.771 | 362 func _enemy_node_bucket_segment_envelope(a: Vector2,b: Vector2,expansion_gu: float) -> Rect2: |
| `res://scripts/runtime_combat_spatial_index.gd::370::RuntimeCombatSpatialIndex._enemy_node_bucket_range` | script_function_exact | exact_func_name_match | 8547 | 3.705 | 10.114 | 369 func _enemy_node_bucket_range(bounds: Rect2) -> Rect2i: |
| `res://scripts/helmet_visual_v2.gd::114::HelmetVisualV2.direction_record` | script_function_exact | exact_func_name_match | 1284 | 3.631 | 14.597 | 113 static func direction_record(item_id: int, direction_row: int) -> Dictionary: |
| `res://scripts/game_root.gd::11425::_status_buff_entries` | script_function_exact | exact_func_name_match | 642 | 3.593 | 6.964 | 11424 func _status_buff_entries() -> Array: |
| `res://scripts/monster_terrain_navigation_policy.gd::109::MonsterTerrainNavigationPolicy.context_valid` | script_function_exact | exact_func_name_match | 2947 | 3.577 | 6.459 | 108 static func context_valid(context: Dictionary, expected_runtime_map_id := -1) -> bool: |
| `res://scripts/hud.gd::2544::GameHUD.update_target` | script_function_exact | exact_func_name_match | 642 | 3.573 | 5.203 | 2543 func update_target(target_name := "", current_hp := 0, max_hp := 0, manual_lock := false, auto_enabled := true, monster_id := -1) -> void: |
| `res://scripts/monster_ai_package/decision_budget.gd::0::Engine.get_physics_frames` | shared_builtin_or_native | builtin_or_native_line_zero | 92284 | 3.508 | 3.508 | — |
| `res://scripts/loot_pickup_runtime_manager.gd::324::LootPickupRuntimeManager._expire_ground_loot` | script_function_exact | exact_func_name_match | 642 | 3.483 | 3.95 | 323 func _expire_ground_loot(delta: float) -> void: |
| `res://scripts/enemy.gd::2761::EnemyActor._update_natural_regen` | script_function_exact | exact_func_name_match | 9040 | 3.459 | 28.184 | 2760 func _update_natural_regen(delta: float) -> void: |
| `res://scripts/loot_pickup_runtime_manager.gd::0::WeakRef.get_ref` | shared_builtin_or_native | builtin_or_native_line_zero | 34543 | 3.458 | 3.458 | — |
| `res://scripts/enemy.gd::10178::EnemyActor._hc_track_motion` | script_function_exact | exact_func_name_match | 7287 | 3.434 | 6.526 | 10177 func _hc_track_motion(delta: float, remaining_before: float, remaining_after: float) -> bool: |
| `res://scripts/game_root.gd::0::Object.has_method` | shared_builtin_or_native | builtin_or_native_line_zero | 55317 | 3.312 | 3.312 | — |
| `res://scripts/monster_source176/source_step_plan.gd::7::next_leg` | script_function_exact | exact_func_name_match | 3379 | 3.2 | 3.2 | 6 static func next_leg(origin: Vector2, stable_waypoint: Vector2, component_budget: float = 1.0, alignment_epsilon: float = EPSILON) -> Vector2: |
| `res://scripts/runtime_combat_spatial_index.gd::356::RuntimeCombatSpatialIndex.enemy_node_segment_bucket_bounds` | script_function_exact | exact_func_name_match | 5042 | 3.141 | 16.586 | 355 func enemy_node_segment_bucket_bounds(a: Vector2,b: Vector2,expansion_gu: float) -> Rect2i: |
| `res://scripts/monster_neighbor_step_policy.gd::152::MonsterNeighborStepPolicy.motion_follows_direction` | script_function_exact | exact_func_name_match | 7627 | 3.139 | 3.139 | 151 static func motion_follows_direction(actual: Vector2, intended: Vector2) -> bool: |
| `res://scripts/monster_visual.gd::325::MonsterVisual.refresh_selection_ring_direction` | script_function_exact | exact_func_name_match | 21828 | 3.121 | 4.656 | 324 func refresh_selection_ring_direction() -> void: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::41::remaining_usec` | budget_admission_or_scheduler | exact_func_name_match | 4286 | 3.088 | 8.455 | 40 static func remaining_usec() -> int: |
| `res://scripts/player_state.gd::3855::_sync_relic_proc_equipment` | script_function_exact | exact_func_name_match | 1284 | 2.937 | 4.25 | 3854 func _sync_relic_proc_equipment() -> bool: |
| `res://scripts/map_editor/map_editor_coordinate.gd::85::MapEditorCoordinate.ground_position_gu_to_screen_position_px` | script_function_exact | exact_func_name_match | 9447 | 2.882 | 6.957 | 81 static func ground_position_gu_to_screen_position_px( |
| `res://scripts/enemy.gd::0::Object.get_script` | shared_builtin_or_native | builtin_or_native_line_zero | 19916 | 2.866 | 2.866 | — |
| `res://scripts/enemy.gd::6091::EnemyActor._target_is_safe_player` | script_function_exact | exact_func_name_match | 6288 | 2.835 | 11.525 | 6090 func _target_is_safe_player(hit_target: Node2D) -> bool: |
| `res://scripts/map_editor/polygon/poly_index.gd::49::_bucket` | poly_index_geometry | exact_func_name_match | 20862 | 2.834 | 2.834 | 48 func _bucket(p: Vector2) -> Vector2i: |
| `res://scripts/enemy.gd::6815::EnemyActor._target_combat_radius_gu` | script_function_exact | exact_func_name_match | 10572 | 2.802 | 7.268 | 6814 func _target_combat_radius_gu(target_node: Node2D) -> float: |
| `res://tests/phone_crowd_baseline_20261008.gd::371::_count_moving` | test_fixture | exact_func_name_match | 600 | 2.802 | 2.802 | 370 func _count_moving(enemies: Array) -> int: |
| `res://scripts/monster_ai_package/policy.gd::110::HCMonsterMeleePolicy.core_crossed` | script_function_exact | exact_func_name_match | 4754 | 2.782 | 3.249 | 107 static func core_crossed(a: Vector2, b: Vector2, c: Vector2, ra: float, rb: float) -> bool: |
| `res://scripts/monster_visual.gd::581::MonsterVisual.streaming_residency_poll` | script_function_exact | exact_func_name_match | 6216 | 2.773 | 15.794 | 580 func streaming_residency_poll(now_msec: int) -> void: |
| `res://scripts/enemy.gd::7557::EnemyActor.entrapment_active` | script_function_exact | exact_func_name_match | 19236 | 2.753 | 2.753 | 7556 func entrapment_active() -> bool: |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::23::HCM30WalkPhase.accept_distance` | script_function_exact | exact_func_name_match | 7154 | 2.739 | 2.739 | 22 func accept_distance(distance_gu: float, physics_tick: int) -> void: |
| `res://scripts/monster_ai_package/decision_budget.gd::40::_prune_front` | script_function_exact | exact_func_name_match | 2158 | 2.737 | 9.695 | 39 static func _prune_front(caller: Node = null) -> void: |
| `res://tests/world_crowd_firewall_profile_test.gd::303::_screen_to_ground` | test_fixture | exact_func_name_match | 10535 | 2.726 | 25.333 | 302 func _screen_to_ground(position: Vector2) -> Vector2: |
| `res://tests/crowd_engagement_scaling_20261008.gd::97::_run` | test_fixture | source_present_no_exact_func_name | 300 | 2.722 | 6.485 | — |
| `res://scripts/map_editor/polygon/poly_geometry.gd::105::bounds` | poly_index_geometry | exact_func_name_match | 3298 | 2.708 | 2.708 | 104 static func bounds(points: PackedVector2Array) -> Rect2: |
| `res://tests/phone_crowd_baseline_20261008.gd::393::_attack_starts` | test_fixture | exact_func_name_match | 601 | 2.7 | 2.7 | 392 func _attack_starts(enemies: Array) -> int: |
| `res://scripts/helmet_visual_v2.gd::78::HelmetVisualV2.visual_asset_for_item` | script_function_exact | exact_func_name_match | 2568 | 2.649 | 5.379 | 77 static func visual_asset_for_item(item_id: int) -> Dictionary: |
| `res://scripts/player_visual.gd::830::_update_equipment_layers` | script_function_exact | exact_func_name_match | 642 | 2.576 | 5.494 | 829 func _update_equipment_layers() -> void: |
| `res://scripts/map_coordinate_mapper.gd::75::MapCoordinateMapper.<anonymous lambda>(lambda)` | script_function_exact | source_present_no_exact_func_name | 16889 | 2.55 | 47.656 | — |
| `res://scripts/map_editor/polygon/poly_geometry.gd::147::capsule_hits_polygon` | poly_index_geometry | exact_func_name_match | 920 | 2.54 | 12.393 | 146 static func capsule_hits_polygon(a: Vector2, b: Vector2, radius_gu: float, polygon: PackedVector2Array) -> bool: |
| `res://scripts/enemy.gd::4055::EnemyActor._world_direct_space_state` | script_function_exact | exact_func_name_match | 2334 | 2.529 | 3.357 | 4054 func _world_direct_space_state() -> PhysicsDirectSpaceState2D: |
| `res://scripts/enemy.gd::3506::EnemyActor._screen_facing_for_ground_direction` | script_function_exact | exact_func_name_match | 7826 | 2.458 | 6.062 | 3505 static func _screen_facing_for_ground_direction(direction_ground: Vector2) -> Vector2: |
| `res://scripts/monster_visual_streaming_coordinator.gd::447::MonsterVisualStreamingCoordinator._poll_admitted` | script_function_exact | exact_func_name_match | 520 | 2.447 | 74.381 | 446 func _poll_admitted(frame_id: int) -> Dictionary: |
| `res://scripts/game_root.gd::12271::_canonical_ground_gu_to_screen_px` | script_function_exact | exact_func_name_match | 6879 | 2.434 | 56.449 | 12270 func _canonical_ground_gu_to_screen_px(ground_position_gu: Vector2) -> Vector2: |
| `res://scripts/monster_visual_streaming_coordinator.gd::864::MonsterVisualStreamingCoordinator.map_prefetch_status` | script_function_exact | exact_func_name_match | 642 | 2.419 | 2.82 | 863 func map_prefetch_status() -> Dictionary: |
| `res://scripts/player.gd::763::PlayerCharacter.combat_transition_is_active` | script_function_exact | exact_func_name_match | 23521 | 2.403 | 2.403 | 762 func combat_transition_is_active() -> bool: |
| `res://scripts/game_root.gd::1963::_constrain_player_foot_to_runtime_ground` | script_function_exact | exact_func_name_match | 642 | 2.389 | 31.502 | 1962 func _constrain_player_foot_to_runtime_ground() -> bool: |
| `res://scripts/monster_ai_package/decision_budget.gd::71::has_pending` | script_function_exact | exact_func_name_match | 16637 | 2.387 | 4.172 | 70 static func has_pending(owner_id: int) -> bool: |
| `res://scripts/monster_ai_package/decision_budget.gd::57::_fill_turns` | script_function_exact | exact_func_name_match | 1018 | 2.353 | 7.228 | 53 static func _fill_turns(caller: Node = null) -> void: |
| `res://scripts/enemy.gd::0::Object.has_meta` | shared_builtin_or_native | builtin_or_native_line_zero | 27762 | 2.326 | 2.326 | — |
| `res://scripts/enemy.gd::6827::EnemyActor._contact_distance_gu_to_target` | script_function_exact | exact_func_name_match | 9277 | 2.302 | 11.533 | 6826 func _contact_distance_gu_to_target(target_node: Node2D) -> float: |
| `res://scripts/monster_ai_package/decision_budget.gd::48::_refresh_pending` | script_function_exact | exact_func_name_match | 3031 | 2.253 | 13.813 | 47 static func _refresh_pending() -> void: |
| `res://scripts/enemy.gd::8400::EnemyActor.should_draw_synthetic_ground_shadow` | script_function_exact | exact_func_name_match | 9000 | 2.223 | 10.696 | 8399 func should_draw_synthetic_ground_shadow() -> bool: |
| `res://scripts/map_editor/polygon/poly_geometry.gd::126::segments_touch` | poly_index_geometry | exact_func_name_match | 4288 | 2.211 | 2.689 | 125 static func segments_touch(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> bool: |
| `res://scripts/runtime_combat_spatial_index.gd::764::RuntimeCombatSpatialIndex._point_in_inclusive_bounds` | script_function_exact | exact_func_name_match | 14738 | 2.176 | 2.176 | 763 static func _point_in_inclusive_bounds(point: Vector2, low: Vector2, high: Vector2) -> bool: |
| `res://scripts/enemy.gd::7622::EnemyActor._update_entrapment_state` | script_function_exact | exact_func_name_match | 9040 | 2.142 | 5.486 | 7621 func _update_entrapment_state(delta: float) -> void: |
| `res://scripts/ground_unit_space.gd::137::GroundUnitSpace.desired_screen_velocity_px_per_sec` | script_function_exact | exact_func_name_match | 7499 | 2.114 | 4.299 | 133 static func desired_screen_velocity_px_per_sec( |
| `res://scripts/enemy.gd::6403::EnemyActor._update_area_attack` | script_function_exact | exact_func_name_match | 8677 | 2.083 | 3.16 | 6402 func _update_area_attack(delta: float) -> bool: |
| `res://scripts/monster_neighbor_step_policy.gd::86::MonsterNeighborStepPolicy.neighbor_for_desired_ground_direction` | script_function_exact | exact_func_name_match | 2516 | 2.078 | 4.558 | 85 static func neighbor_for_desired_ground_direction(direction_ground_gu: Variant) -> Vector2i: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::23::_now_usec` | budget_admission_or_scheduler | exact_func_name_match | 8819 | 2.062 | 2.637 | 22 static func _now_usec() -> int: |
| `res://scripts/player_visual.gd::480::_update_markers` | script_function_exact | exact_func_name_match | 642 | 2.04 | 2.04 | 479 func _update_markers() -> void: |
| `res://scripts/enemy.gd::9451::EnemyActor._hc_refresh_static_query_cache` | script_function_exact | exact_func_name_match | 5002 | 2.001 | 2.257 | 9450 func _hc_refresh_static_query_cache() -> void: |
| `res://scripts/json_persistence_service.gd::32::_refresh_budget_owner` | budget_admission_or_scheduler | exact_func_name_match | 1284 | 2.001 | 7.987 | 31 func _refresh_budget_owner() -> bool: |
| `res://tests/world_crowd_firewall_profile_test.gd::44::_process` | test_fixture | exact_func_name_match | 642 | 1.994 | 2.53 | 43 func _process(_delta: float) -> void: |
| `res://scripts/world_background.gd::389::WorldBackground.is_environment_actor_blocked` | script_function_exact | exact_func_name_match | 3298 | 1.978 | 167.548 | 384 func is_environment_actor_blocked( |
| `res://scripts/monster_visual.gd::1529::MonsterVisual.hc_m30_begin_melee_tick` | script_function_exact | exact_func_name_match | 8677 | 1.953 | 2.236 | 1528 func hc_m30_begin_melee_tick() -> void: |
| `res://scripts/monster_visual.gd::1477::MonsterVisual.should_draw_procedural_fallback` | script_function_exact | exact_func_name_match | 9000 | 1.935 | 6.035 | 1472 func should_draw_procedural_fallback() -> bool: |
| `res://scripts/monster_visual_streaming_coordinator.gd::432::MonsterVisualStreamingCoordinator.poll_once` | script_function_exact | exact_func_name_match | 642 | 1.917 | 97.021 | 431 func poll_once(frame_id: int) -> Dictionary: |
| `res://scripts/monster_visual_streaming_coordinator.gd::0::Time.get_ticks_msec` | shared_builtin_or_native | builtin_or_native_line_zero | 25512 | 1.915 | 1.915 | — |
| `res://scripts/game_root.gd::11397::_update_stealth_alpha` | script_function_exact | exact_func_name_match | 642 | 1.896 | 5.072 | 11396 func _update_stealth_alpha() -> void: |
| `res://scripts/map_editor/polygon/poly_geometry.gd::113::distance_squared_to_segment` | poly_index_geometry | exact_func_name_match | 11912 | 1.894 | 1.894 | 112 static func distance_squared_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float: |
| `res://scripts/enemy.gd::0::PhysicsRayQueryParameters2D.create` | shared_builtin_or_native | builtin_or_native_line_zero | 2332 | 1.849 | 1.849 | — |
| `res://scripts/monster_movement_cadence.gd::272::MonsterMovementCadence._record_evaluation` | script_function_exact | exact_func_name_match | 10200 | 1.844 | 1.844 | 271 func _record_evaluation(action: String, reason: String) -> bool: |
| `res://scripts/enemy.gd::1077::EnemyActor._advance_combat_action_clock` | script_function_exact | exact_func_name_match | 10200 | 1.839 | 1.839 | 1076 func _advance_combat_action_clock(delta: float) -> void: |
| `res://scripts/enemy.gd::6835::EnemyActor._uses_player_melee_contact_contract` | script_function_exact | exact_func_name_match | 9277 | 1.835 | 1.835 | 6834 func _uses_player_melee_contact_contract(target_node: Node2D) -> bool: |
| `res://scripts/monster_movement_cadence.gd::426::MonsterMovementCadence._is_strict_int` | script_function_exact | exact_func_name_match | 10200 | 1.784 | 1.784 | 425 static func _is_strict_int(value: Variant) -> bool: |
| `res://scripts/monster_neighbor_step_policy.gd::170::MonsterNeighborStepPolicy.build_neighbor_step` | script_function_exact | exact_func_name_match | 476 | 1.774 | 4.382 | 166 static func build_neighbor_step( |
| `res://scripts/runtime_combat_spatial_index.gd::286::RuntimeCombatSpatialIndex.query_enemy_nodes_segment_into` | script_function_exact | exact_func_name_match | 913 | 1.721 | 18.049 | 278 func query_enemy_nodes_segment_into( |
| `res://scripts/map_editor/polygon/poly_runtime.gd::179::segment_walkable` | poly_runtime_callee | exact_func_name_match | 2810 | 1.708 | 26.242 | 178 static func segment_walkable(context_value: Dictionary, a: Vector2, b: Vector2, radius_gu: float) -> bool: |
| `res://scripts/enemy.gd::1142::EnemyActor._audio_observe_visual_state` | script_function_exact | exact_func_name_match | 10200 | 1.701 | 3.136 | 1138 func _audio_observe_visual_state() -> void: |
| `res://scripts/enemy.gd::7742::EnemyActor._boss_stage_search_due` | script_function_exact | exact_func_name_match | 8717 | 1.694 | 1.694 | 7741 func _boss_stage_search_due() -> bool: |
| `res://scripts/game_root.gd::0::Engine.get_process_frames` | shared_builtin_or_native | builtin_or_native_line_zero | 42809 | 1.693 | 1.693 | — |
| `res://scripts/runtime_combat_spatial_index.gd::442::RuntimeCombatSpatialIndex._finish_enemy_node_query` | script_function_exact | exact_func_name_match | 4500 | 1.684 | 1.684 | 441 func _finish_enemy_node_query(output: Array) -> void: |
| `res://scripts/player_visual.gd::429::_update_optional_helmet_layer` | script_function_exact | exact_func_name_match | 1284 | 1.639 | 1.639 | 423 func _update_optional_helmet_layer( |
| `res://scripts/enemy.gd::9090::EnemyActor._hc_finalize_boss_facing` | script_function_exact | exact_func_name_match | 8677 | 1.625 | 1.625 | 9083 func _hc_finalize_boss_facing() -> void: |
| `res://scripts/game_root.gd::15257::_reconcile_ordinary_attack_button_owners` | script_function_exact | exact_func_name_match | 642 | 1.598 | 2.227 | 15254 func _reconcile_ordinary_attack_button_owners() -> void: |
| `res://scripts/monster_ai_package/decision_budget.gd::21::_sync_epoch` | script_function_exact | exact_func_name_match | 1051 | 1.568 | 1.62 | 20 static func _sync_epoch() -> void: |
| `res://scripts/monster_visual.gd::1297::MonsterVisual._try_start_next_presentation` | script_function_exact | exact_func_name_match | 21828 | 1.562 | 1.562 | 1296 func _try_start_next_presentation() -> void: |
| `res://scripts/monster_neighbor_step_policy.gd::44::MonsterNeighborStepPolicy.temporary_cell` | script_function_exact | exact_func_name_match | 4336 | 1.543 | 2.868 | 43 static func temporary_cell(position_ground_gu: Variant) -> Vector2i: |
| `res://scripts/game_root.gd::5816::_poll_attack_action_lifecycle` | script_function_exact | exact_func_name_match | 642 | 1.54 | 1.896 | 5815 func _poll_attack_action_lifecycle(input_enabled: bool) -> Dictionary: |
| `res://scripts/monster_visual.gd::1481::MonsterVisual.is_fallback_attacking` | script_function_exact | exact_func_name_match | 9000 | 1.529 | 5.16 | 1480 func is_fallback_attacking() -> bool: |
| `res://scripts/ground_unit_space.gd::148::GroundUnitSpace.actual_ground_motion_gu_from_screen_positions` | script_function_exact | exact_func_name_match | 7627 | 1.514 | 4.313 | 144 static func actual_ground_motion_gu_from_screen_positions( |
| `res://scripts/world_background.gd::439::WorldBackground.is_environment_segment_blocked_ground` | script_function_exact | exact_func_name_match | 2334 | 1.512 | 21.54 | 433 func is_environment_segment_blocked_ground( |
| `res://scripts/monster_visual.gd::496::MonsterVisual._update_resource_residency` | script_function_exact | exact_func_name_match | 6216 | 1.508 | 11.386 | 495 func _update_resource_residency() -> void: |
| `res://scripts/monster_struck_policy.gd::81::MonsterStruckPolicy.struck_speed_multiplier` | script_function_exact | exact_func_name_match | 21828 | 1.5 | 1.5 | 80 static func struck_speed_multiplier(pending_count: int) -> float: |
| `res://scripts/enemy.gd::8805::EnemyActor._hc_frontline_at` | script_function_exact | exact_func_name_match | 913 | 1.499 | 23.733 | 8804 func _hc_frontline_at(a: Vector2, b: Vector2, hit_target: Node2D) -> int: |
| `res://scripts/map_editor/polygon/poly_geometry.gd::143::_separated_segment_distance_squared` | poly_index_geometry | exact_func_name_match | 2617 | 1.491 | 5.238 | 142 static func _separated_segment_distance_squared(a: Vector2, b: Vector2, c: Vector2, d: Vector2) -> float: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::71::_eligible` | budget_admission_or_scheduler | exact_func_name_match | 612 | 1.491 | 1.775 | 70 static func _eligible(item: Dictionary, is_calling_owner := false) -> bool: |
| `res://scripts/player_status_marker_strip.gd::51::PlayerStatusMarkerStrip._poison_active` | script_function_exact | exact_func_name_match | 642 | 1.475 | 2.055 | 50 func _poison_active() -> bool: |
| `res://scripts/monster_source_frames.gd::44::poll` | script_function_exact | exact_func_name_match | 642 | 1.447 | 1.475 | 43 static func poll() -> void: |
| `res://scripts/game_root.gd::2112::_pump_pending_warm_textures` | script_function_exact | exact_func_name_match | 642 | 1.438 | 2.795 | 2111 func _pump_pending_warm_textures() -> void: |
| `res://scripts/map_editor/map_diamond_camera_constraint_service.gd::318::MapDiamondCameraConstraintService._entry_black` | script_function_exact | exact_func_name_match | 642 | 1.417 | 1.417 | 314 static func _entry_black(entry: Dictionary, point: Vector2) -> float: |
| `res://scripts/equipment_rules.gd::78::EquipmentRules.weapon_draws_behind_actor` | script_function_exact | exact_func_name_match | 642 | 1.407 | 1.998 | 77 static func weapon_draws_behind_actor(direction_row: int, action_name := "idle", frame := 0, gender := "男") -> bool: |
| `res://scripts/world_spatial_rules.gd::537::WorldSpatialRules.actor_combat_radius_gu_from_screen_radius_px` | script_function_exact | exact_func_name_match | 10572 | 1.376 | 1.376 | 534 static func actor_combat_radius_gu_from_screen_radius_px( |
| `res://scripts/monster_ai_package/policy.gd::18::HCMonsterMeleePolicy.valid` | script_function_exact | exact_func_name_match | 9721 | 1.374 | 1.374 | 17 static func valid() -> bool: |
| `res://scripts/enemy.gd::5985::EnemyActor._notification` | script_function_exact | exact_func_name_match | 17355 | 1.357 | 1.357 | 5984 func _notification(what: int) -> void: |
| `res://scripts/layers/runtime/execution/paused_receipt_pump.gd::12::_process` | script_function_exact | exact_func_name_match | 642 | 1.328 | 1.428 | 11 func _process(_delta: float) -> void: |
| `res://scripts/map_editor/map_diamond_camera_constraint_service.gd::239::MapDiamondCameraConstraintService.apply_player_visibility_guard` | script_function_exact | exact_func_name_match | 642 | 1.326 | 3.822 | 219 static func apply_player_visibility_guard( |
| `res://scripts/enemy.gd::6779::EnemyActor._update_behavior_summon` | script_function_exact | exact_func_name_match | 8677 | 1.313 | 2.244 | 6778 func _update_behavior_summon(delta: float) -> bool: |
| `res://scripts/map_editor/polygon/poly_geometry.gd::163::convex_overlap` | poly_index_geometry | exact_func_name_match | 233 | 1.263 | 1.263 | 161 static func convex_overlap(a: PackedVector2Array, b: PackedVector2Array) -> bool: |
| `res://scripts/enemy.gd::3775::EnemyActor._movement_collision_count` | script_function_exact | exact_func_name_match | 7313 | 1.251 | 1.251 | 3774 func _movement_collision_count() -> int: |
| `res://scripts/enemy.gd::10441::EnemyActor._hc_prepare_flank_batch` | script_function_exact | exact_func_name_match | 82 | 1.245 | 79.942 | 10440 func _hc_prepare_flank_batch(current: Vector2, anchor: Vector2, cell: Vector2i) -> bool: |
| `res://scripts/enemy.gd::4207::EnemyActor._update_pending_attack` | script_function_exact | exact_func_name_match | 9040 | 1.245 | 1.245 | 4206 func _update_pending_attack(delta: float) -> void: |
| `res://scripts/enemy.gd::6903::EnemyActor._ensure_target_grid` | script_function_exact | exact_func_name_match | 697 | 1.23 | 1.554 | 6902 func _ensure_target_grid(force_refresh := false) -> void: |
| `res://scripts/player_status_marker_strip.gd::43::PlayerStatusMarkerStrip._paralysis_active` | script_function_exact | exact_func_name_match | 642 | 1.225 | 1.424 | 42 func _paralysis_active() -> bool: |
| `res://scripts/audio_runtime_service.gd::0::AudioStreamPlayer.play` | shared_builtin_or_native | builtin_or_native_line_zero | 32 | 1.167 | 1.167 | — |
| `res://scripts/game_root.gd::13389::_pump_enemy_death_work_queue` | script_function_exact | exact_func_name_match | 642 | 1.166 | 17.282 | 13388 func _pump_enemy_death_work_queue(force_synchronous := false) -> bool: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::91::_fair_blocker` | budget_admission_or_scheduler | exact_func_name_match | 1081 | 1.135 | 3.324 | 90 static func _fair_blocker(category: String) -> Variant: |
| `res://scripts/game_root.gd::11376::_set_actor_stealth_alpha` | script_function_exact | exact_func_name_match | 642 | 1.128 | 1.285 | 11375 func _set_actor_stealth_alpha(actor: Node2D, stealthed: bool) -> void: |
| `res://scripts/monster_visual_streaming_coordinator.gd::238::MonsterVisualStreamingCoordinator._pump_threaded_profile_queue` | script_function_exact | exact_func_name_match | 519 | 1.117 | 11.419 | 237 func _pump_threaded_profile_queue() -> void: |
| `res://scripts/monster_ai_package/decision_budget.gd::130::cancel` | script_function_exact | exact_func_name_match | 1140 | 1.108 | 8.642 | 129 static func cancel(owner_id: int) -> void: |
| `res://scripts/monster_neighbor_step_policy.gd::210::MonsterNeighborStepPolicy._is_finite_ground_position` | script_function_exact | exact_func_name_match | 7328 | 1.082 | 1.082 | 209 static func _is_finite_ground_position(value: Variant) -> bool: |
| `res://scripts/player.gd::420::PlayerCharacter._keyboard_movement_vector` | script_function_exact | exact_func_name_match | 300 | 1.081 | 1.606 | 419 func _keyboard_movement_vector() -> Vector2: |
| `res://scripts/map_editor/polygon/poly_runtime.gd::173::point_walkable` | poly_runtime_callee | exact_func_name_match | 1976 | 1.07 | 15.033 | 172 static func point_walkable(context_value: Dictionary, point_gu: Vector2, radius_gu: float) -> bool: |
| `res://scripts/loot_pickup_runtime_manager.gd::299::LootPickupRuntimeManager._process` | script_function_exact | exact_func_name_match | 642 | 1.058 | 6.571 | 298 func _process(delta: float) -> void: |
| `res://scripts/enemy.gd::341::EnemyActor.@control_time_setter` | script_function_exact | source_present_no_exact_func_name | 9040 | 1.055 | 1.055 | — |
| `res://scripts/enemy.gd::0::Object.get_property_list` | shared_builtin_or_native | builtin_or_native_line_zero | 4 | 1.052 | 1.052 | — |
| `res://scripts/player.gd::1935::PlayerCharacter.is_stealthed` | script_function_exact | exact_func_name_match | 2911 | 1.039 | 2.955 | 1934 func is_stealthed() -> bool: |
| `res://scripts/runtime_combat_spatial_index.gd::187::RuntimeCombatSpatialIndex._maybe_refresh_max_actor_bounds` | script_function_exact | exact_func_name_match | 9542 | 1.035 | 1.035 | 186 func _maybe_refresh_max_actor_bounds() -> void: |
| `res://scripts/monster_terrain_navigation_policy.gd::508::MonsterTerrainNavigationPolicy.point_walkable` | script_function_exact | exact_func_name_match | 1976 | 1.032 | 21.321 | 507 static func point_walkable(context: Dictionary, ground_gu: Vector2, combat_radius_gu: float) -> bool: |
| `res://scripts/map_coordinate_mapper.gd::80::MapCoordinateMapper.<anonymous lambda>(lambda)` | script_function_exact | source_present_no_exact_func_name | 6879 | 1.024 | 17.371 | — |
| `res://scripts/enemy.gd::348::EnemyActor.@charm_time_setter` | script_function_exact | source_present_no_exact_func_name | 9040 | 1.022 | 1.022 | — |
| `res://scripts/monster_visual.gd::0::CanvasItem.get_global_transform_with_canvas` | shared_builtin_or_native | builtin_or_native_line_zero | 6235 | 1.016 | 1.016 | — |
| `res://scripts/device_lab_runtime.gd::175::DeviceLabRuntime._debug_enabled` | script_function_exact | exact_func_name_match | 642 | 1.01 | 1.075 | 174 func _debug_enabled() -> bool: |
| `res://scripts/player_state.gd::413::_process` | script_function_exact | exact_func_name_match | 642 | 1.001 | 21.557 | 412 func _process(delta: float) -> void: |
| `res://scripts/game_root.gd::6102::_uses_magic_lock_domain` | script_function_exact | exact_func_name_match | 642 | 0.987 | 4.447 | 6101 func _uses_magic_lock_domain() -> bool: |
| `res://scripts/monster_visual_streaming_coordinator.gd::562::MonsterVisualStreamingCoordinator._commit_loaded_profiles` | script_function_exact | exact_func_name_match | 519 | 0.985 | 0.985 | 560 func _commit_loaded_profiles() -> void: |
| `res://scripts/monster_crowd_attack_position_policy.gd::13::margin_gu` | script_function_exact | exact_func_name_match | 7412 | 0.978 | 0.978 | 10 static func margin_gu(actor: CharacterBody2D) -> float: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::448::MapEditorRuntimeCollisionGeometryService._signed_area` | script_function_exact | exact_func_name_match | 642 | 0.959 | 1.888 | 447 static func _signed_area(polygon: PackedVector2Array) -> float: |
| `res://scripts/monster_ai_package/policy.gd::84::HCMonsterMeleePolicy.frontline_blocks` | script_function_exact | exact_func_name_match | 484 | 0.954 | 0.994 | 79 static func frontline_blocks( |
| `res://scripts/monster_visual.gd::0::Engine.get_physics_frames` | shared_builtin_or_native | builtin_or_native_line_zero | 29840 | 0.935 | 0.935 | — |
| `res://scripts/game_root.gd::11412::_update_taoist_buff_hints` | script_function_exact | exact_func_name_match | 642 | 0.932 | 8.368 | 11411 func _update_taoist_buff_hints() -> void: |
| `res://scripts/game_root.gd::12064::_record_player_world_location` | script_function_exact | exact_func_name_match | 642 | 0.923 | 7.823 | 12063 func _record_player_world_location() -> void: |
| `res://scripts/enemy.gd::9644::EnemyActor._hc_sync_navigation` | script_function_exact | exact_func_name_match | 971 | 0.921 | 1.815 | 9643 func _hc_sync_navigation() -> void: |
| `res://scripts/game_root.gd::1407::gameplay_input_is_enabled` | script_function_exact | exact_func_name_match | 1297 | 0.914 | 1.457 | 1406 func gameplay_input_is_enabled() -> bool: |
| `res://scripts/audio_runtime_service.gd::457::AudioRuntimeService._play_event_internal` | script_function_exact | exact_func_name_match | 44 | 0.893 | 3.195 | 450 func _play_event_internal( |
| `res://scripts/enemy.gd::3516::EnemyActor.ground_velocity_gu_per_sec` | script_function_exact | exact_func_name_match | 2568 | 0.886 | 2.025 | 3513 func ground_velocity_gu_per_sec() -> Vector2: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::275::MapEditorRuntimeCollisionGeometryService.tile_polygon_world` | script_function_exact | exact_func_name_match | 642 | 0.872 | 3.283 | 271 static func tile_polygon_world( |
| `res://scripts/player_visual.gd::399::_update_visibility` | script_function_exact | exact_func_name_match | 642 | 0.838 | 0.838 | 398 func _update_visibility() -> void: |
| `res://scripts/monster_visual_streaming_coordinator.gd::344::MonsterVisualStreamingCoordinator._retry_eligible_failed_jobs` | script_function_exact | exact_func_name_match | 519 | 0.835 | 0.887 | 343 func _retry_eligible_failed_jobs() -> void: |
| `res://scripts/enemy.gd::0::CanvasItem.get_world_2d` | shared_builtin_or_native | builtin_or_native_line_zero | 2334 | 0.828 | 0.828 | — |
| `res://scripts/identity/entity_registry.gd::112::resolve` | script_function_exact | exact_func_name_match | 819 | 0.825 | 1.859 | 111 static func resolve(id: String, kind := "") -> Dictionary: |
| `res://scripts/loot_feedback_layer.gd::44::LootFeedbackLayer._process` | script_function_exact | exact_func_name_match | 642 | 0.804 | 0.804 | 43 func _process(delta: float) -> void: |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::259::MapEditorRuntimeBridge.has_runtime_map` | script_function_exact | exact_func_name_match | 1284 | 0.802 | 3.027 | 258 static func has_runtime_map(runtime_map_id: int) -> bool: |
| `res://scripts/enemy.gd::6989::EnemyActor._append_live_target_candidate` | script_function_exact | exact_func_name_match | 697 | 0.772 | 1.036 | 6988 func _append_live_target_candidate(candidates: Array, raw_candidate: Variant) -> void: |
| `res://scripts/world_spatial_rules.gd::527::WorldSpatialRules.actor_footprint_radii_px` | script_function_exact | exact_func_name_match | 3993 | 0.763 | 0.763 | 526 static func actor_footprint_radii_px(collision_radius_px: float) -> Vector2: |
| `res://scripts/monster_crowd_attack_position_policy.gd::112::_free_ray_extent` | script_function_exact | exact_func_name_match | 2458 | 0.739 | 0.739 | 111 static func _free_ray_extent(origin: Vector2, direction: Vector2, center: Vector2, radius: float, extent: float) -> float: |
| `res://scripts/player_visual.gd::364::_resolved_direction_row` | script_function_exact | exact_func_name_match | 642 | 0.732 | 2.328 | 361 func _resolved_direction_row() -> int: |
| `res://scripts/player_visual.gd::897::_update_skill_effect` | script_function_exact | exact_func_name_match | 642 | 0.714 | 0.76 | 896 func _update_skill_effect() -> void: |
| `res://scripts/game_root.gd::6973::_update_target_hud` | script_function_exact | exact_func_name_match | 642 | 0.711 | 11.815 | 6972 func _update_target_hud() -> void: |
| `res://scripts/layers/presentation/monster_animation_policy.gd::46::MonsterAnimationPolicy.loop_fps` | script_function_exact | exact_func_name_match | 5126 | 0.705 | 1.315 | 45 static func loop_fps(action: StringName) -> float: |
| `res://scripts/runtime_combat_spatial_index.gd::455::RuntimeCombatSpatialIndex._next_enemy_query_stamp` | script_function_exact | exact_func_name_match | 4500 | 0.704 | 0.704 | 454 func _next_enemy_query_stamp() -> int: |
| `res://scripts/player.gd::1671::PlayerCharacter._tick_badge_recovery` | script_function_exact | exact_func_name_match | 300 | 0.702 | 0.83 | 1670 func _tick_badge_recovery(delta: float) -> void: |
| `res://tests/world_crowd_firewall_profile_test.gd::24::PhysicsFrameStart._physics_process` | test_fixture | exact_func_name_multiple_matches | 300 | 0.695 | 0.767 | 23 func _physics_process(_delta: float) -> void:<br>38 func _physics_process(_delta: float) -> void: |
| `res://scripts/enemy.gd::10433::EnemyActor._hc_flank_leg_endpoint` | script_function_exact | exact_func_name_match | 1794 | 0.693 | 6.782 | 10427 func _hc_flank_leg_endpoint(current: Vector2, waypoint: Vector2) -> Vector2: |
| `res://scripts/monster_ai_package/policy.gd::68::HCMonsterMeleePolicy.preferred` | script_function_exact | exact_func_name_match | 9277 | 0.688 | 0.688 | 67 static func preferred(physical_contact_gu: float) -> float: |
| `res://scripts/game_root.gd::0::Input.is_action_just_pressed` | shared_builtin_or_native | builtin_or_native_line_zero | 3210 | 0.664 | 0.664 | — |
| `res://scripts/enemy.gd::2223::EnemyActor._clear_autonomous_step_state` | script_function_exact | exact_func_name_match | 1326 | 0.663 | 0.663 | 2222 func _clear_autonomous_step_state() -> void: |
| `res://scripts/game_root.gd::12084::_ground_position_gu_for_map` | script_function_exact | exact_func_name_match | 642 | 0.648 | 6.091 | 12080 func _ground_position_gu_for_map( |
| `res://scripts/caster_skill_visual_registry.gd::97::CasterSkillVisualRegistry.take_pending_warm_paths` | script_function_exact | exact_func_name_match | 642 | 0.646 | 0.646 | 96 static func take_pending_warm_paths(limit := 4) -> Array[String]: |
| `res://scripts/enemy.gd::8928::EnemyActor._hc_try_start` | script_function_exact | exact_func_name_match | 147 | 0.645 | 13.254 | 8927 func _hc_try_start(hit_target: Node2D) -> bool: |
| `res://scripts/monster_ai_package/m30/context_token.gd::13::HCM30ContextToken.token` | script_function_exact | exact_func_name_match | 935 | 0.638 | 0.638 | 12 static func token(context: Dictionary) -> int: |
| `res://scripts/player_status_marker_strip.gd::29::PlayerStatusMarkerStrip.active_status_markers` | script_function_exact | exact_func_name_match | 642 | 0.636 | 4.548 | 28 func active_status_markers() -> Array[String]: |
| `res://scripts/enemy.gd::10348::EnemyActor._hc_flank_destination_candidates_clear` | script_function_exact | exact_func_name_match | 303 | 0.613 | 2.148 | 10347 func _hc_flank_destination_candidates_clear(point: Vector2, candidates: Array) -> bool: |
| `res://scripts/monster_neighbor_step_policy.gd::37::MonsterNeighborStepPolicy.is_valid_neighbor` | script_function_exact | exact_func_name_match | 1577 | 0.603 | 0.603 | 36 static func is_valid_neighbor(neighbor: Variant) -> bool: |
| `res://scripts/runtime_loot_spatial_index.gd::153::RuntimeLootSpatialIndex.query_nearby_into` | script_function_exact | exact_func_name_match | 142 | 0.58 | 0.856 | 147 func query_nearby_into( |
| `res://scripts/enemy.gd::10394::EnemyActor._hc_contact_flank` | script_function_exact | exact_func_name_match | 42 | 0.579 | 63.906 | 10393 func _hc_contact_flank(current: Vector2, anchor: Vector2, victim_anchor: Vector2, hit_target: Node2D, cell: Vector2i, preferred_sign: float) -> Vector2: |
| `res://scripts/player_state.gd::379::_notification` | script_function_exact | exact_func_name_match | 642 | 0.573 | 0.573 | 378 func _notification(what: int) -> void: |
| `res://scripts/device_lab_runtime.gd::192::DeviceLabRuntime._process` | script_function_exact | exact_func_name_match | 642 | 0.57 | 11.87 | 191 func _process(delta: float) -> void: |
| `res://scripts/game_root.gd::15243::_process_ordinary_attack_input` | script_function_exact | exact_func_name_match | 642 | 0.569 | 3.998 | 15242 func _process_ordinary_attack_input(attack_action_lifecycle: Dictionary) -> void: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::244::MapEditorRuntimeCollisionGeometryService.map_inner_boundary_tile_polygon` | script_function_exact | exact_func_name_match | 642 | 0.569 | 0.569 | 238 static func map_inner_boundary_tile_polygon( |
| `res://scripts/game_root.gd::0::Camera2D.force_update_scroll` | shared_builtin_or_native | builtin_or_native_line_zero | 642 | 0.557 | 0.557 | — |
| `res://scripts/game_root.gd::2660::_update_town_music_presence` | script_function_exact | exact_func_name_match | 642 | 0.543 | 1.903 | 2659 func _update_town_music_presence() -> void: |
| `res://scripts/helmet_visual_v2.gd::110::HelmetVisualV2.canonical_direction` | script_function_exact | exact_func_name_match | 3852 | 0.539 | 0.539 | 109 static func canonical_direction(direction_row: int) -> String: |
| `res://scripts/game_root.gd::1806::_notification` | script_function_exact | exact_func_name_match | 942 | 0.538 | 0.538 | 1805 func _notification(what: int) -> void: |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::250::MapEditorRuntimeBridge._readiness` | script_function_exact | exact_func_name_match | 1284 | 0.536 | 0.742 | 249 static func _readiness(runtime_map_id: int) -> Dictionary: |
| `res://scripts/enemy.gd::0::Time.get_ticks_msec` | shared_builtin_or_native | builtin_or_native_line_zero | 6903 | 0.531 | 0.531 | — |
| `res://scripts/player_state.gd::7400::skill_name_for_slot` | script_function_exact | exact_func_name_match | 642 | 0.527 | 1.576 | 7399 func skill_name_for_slot(slot_group: String, slot_index: int) -> String: |
| `res://scripts/monster_visual_streaming_coordinator.gd::248::MonsterVisualStreamingCoordinator._start_threaded_profile_jobs` | script_function_exact | exact_func_name_match | 519 | 0.527 | 0.527 | 247 func _start_threaded_profile_jobs() -> void: |
| `res://scripts/enemy.gd::3317::EnemyActor.set_combat_position` | script_function_exact | exact_func_name_match | 199 | 0.525 | 2.902 | 3313 func set_combat_position( |
| `res://scripts/game_root.gd::0::Viewport.get_visible_rect` | shared_builtin_or_native | builtin_or_native_line_zero | 6883 | 0.524 | 0.524 | — |
| `res://scripts/game_root.gd::7959::_recover_equipment_stealth_if_out_of_combat` | script_function_exact | exact_func_name_match | 642 | 0.513 | 0.513 | 7958 func _recover_equipment_stealth_if_out_of_combat() -> void: |
| `res://scripts/hud_resource_orb.gd::36::HUDResourceOrb._draw` | script_function_exact | exact_func_name_match | 14 | 0.509 | 5.51 | 35 func _draw() -> void: |
| `res://scripts/game_root.gd::13418::_refresh_death_budget_owner` | budget_admission_or_scheduler | exact_func_name_match | 1284 | 0.508 | 3.226 | 13417 func _refresh_death_budget_owner() -> void: |
| `res://scripts/monster_ai_package/policy.gd::0::Geometry2D.get_closest_point_to_segment` | shared_builtin_or_native | builtin_or_native_line_zero | 5182 | 0.507 | 0.507 | — |
| `res://scripts/player_state.gd::3896::advance_relic_proc` | script_function_exact | exact_func_name_match | 642 | 0.504 | 3.502 | 3895 func advance_relic_proc(delta: float) -> void: |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::57::HCM30WalkPhase.action_frame_index` | script_function_exact | exact_func_name_match | 764 | 0.499 | 0.499 | 56 static func action_frame_index(remaining: float, duration: float, frame_count: int) -> int: |
| `res://scripts/game_data.gd::3873::_item_record_for_read` | script_function_exact | exact_func_name_match | 39 | 0.492 | 1.203 | 3872 func _item_record_for_read(item_ref: Variant) -> Dictionary: |
| `res://scripts/player_visual.gd::533::_frame_count_for_action` | script_function_exact | exact_func_name_match | 642 | 0.489 | 1.551 | 532 func _frame_count_for_action(action_key: String) -> int: |
| `res://scripts/player_state.gd::5644::_advance_world_clock_cleanup` | script_function_exact | exact_func_name_match | 642 | 0.488 | 0.488 | 5643 func _advance_world_clock_cleanup() -> void: |
| `res://scripts/player_status_marker_strip.gd::0::Object.get` | shared_builtin_or_native | builtin_or_native_line_zero | 3047 | 0.487 | 0.487 | — |
| `res://scripts/monster_visual.gd::446::MonsterVisual._attack_age_seconds` | script_function_exact | exact_func_name_match | 1355 | 0.469 | 1.009 | 440 func _attack_age_seconds() -> float: |
| `res://scripts/player_visual.gd::936::_update_passive_proc_effect` | script_function_exact | exact_func_name_match | 642 | 0.468 | 0.468 | 935 func _update_passive_proc_effect(delta: float) -> void: |
| `res://scripts/enemy.gd::3998::EnemyActor._finish_attack_los_diagnostic` | script_function_exact | exact_func_name_match | 2334 | 0.466 | 14.439 | 3997 func _finish_attack_los_diagnostic(started_usec: int, result: bool) -> bool: |
| `res://scripts/monster_crowd_attack_position_policy.gd::35::snapshot_peers` | script_function_exact | exact_func_name_match | 42 | 0.465 | 1.403 | 32 static func snapshot_peers(actor: CharacterBody2D, peers: Array) -> Array: |
| `res://scripts/monster_neighbor_step_policy.gd::217::MonsterNeighborStepPolicy._sign_component` | script_function_exact | exact_func_name_match | 4302 | 0.46 | 0.46 | 216 static func _sign_component(value: float) -> int: |
| `res://scripts/game_root.gd::1836::_physics_process` | script_function_exact | exact_func_name_match | 300 | 0.457 | 4.856 | 1835 func _physics_process(delta: float) -> void: |
| `res://scripts/enemy.gd::10367::EnemyActor._hc_far_approach_waypoint` | script_function_exact | exact_func_name_match | 100 | 0.455 | 43.927 | 10366 func _hc_far_approach_waypoint(current: Vector2, anchor: Vector2, cell: Vector2i, preferred_sign: float) -> Vector2: |
| `res://scripts/ui_item_texture_cache.gd::76::UIItemTextureCache.poll_threaded_paths` | script_function_exact | exact_func_name_match | 642 | 0.446 | 0.637 | 75 static func poll_threaded_paths() -> int: |
| `res://scripts/game_root.gd::0::SceneTree.get_nodes_in_group` | shared_builtin_or_native | builtin_or_native_line_zero | 662 | 0.445 | 0.445 | — |
| `res://scripts/player_visual.gd::511::_default_body_texture` | script_function_exact | exact_func_name_match | 642 | 0.444 | 0.77 | 510 func _default_body_texture(action_key: String) -> Texture2D: |
| `res://scripts/monster_ai_package/decision_budget.gd::125::end` | script_function_exact | exact_func_name_match | 906 | 0.442 | 7.75 | 124 static func end(token: int) -> void: |
| `res://scripts/profession_rules.gd::236::ProfessionRules.profession_id` | script_function_exact | exact_func_name_match | 642 | 0.442 | 3.069 | 235 static func profession_id(value: String) -> String: |
| `res://scripts/hud.gd::0::ShaderMaterial.set_shader_parameter` | shared_builtin_or_native | builtin_or_native_line_zero | 642 | 0.441 | 0.441 | — |
| `res://scripts/world_camera_follow.gd::8::advance` | script_function_exact | exact_func_name_match | 642 | 0.432 | 0.432 | 7 static func advance(center: Vector2, target: Vector2, delta: float) -> Vector2: |
| `res://scripts/game_root.gd::2057::_player_display_extent_world_px` | script_function_exact | exact_func_name_match | 642 | 0.426 | 0.426 | 2056 func _player_display_extent_world_px() -> Vector3: |
| `res://scripts/helmet_visual_v2.gd::28::HelmetVisualV2.contract` | script_function_exact | exact_func_name_match | 2568 | 0.426 | 0.426 | 27 static func contract() -> Dictionary: |
| `res://scripts/runtime_combat_spatial_index.gd::475::RuntimeCombatSpatialIndex.query_neighbor_enemy_nodes_into` | script_function_exact | exact_func_name_match | 7 | 0.416 | 0.505 | 469 func query_neighbor_enemy_nodes_into( |
| `res://scripts/player_visual.gd::495::_visual_action_key` | script_function_exact | exact_func_name_match | 1284 | 0.41 | 0.41 | 494 func _visual_action_key() -> String: |
| `res://scripts/enemy.gd::1773::EnemyActor._request_autonomous_step` | script_function_exact | exact_func_name_match | 175 | 0.402 | 11.231 | 1765 func _request_autonomous_step( |
| `res://scripts/helmet_visual_v2.gd::94::HelmetVisualV2.calibration_item_id_for_item` | script_function_exact | exact_func_name_match | 1284 | 0.396 | 3.027 | 93 static func calibration_item_id_for_item(item_id: int) -> int: |
| `res://scripts/game_root.gd::5916::_process_skill_input_actions` | script_function_exact | exact_func_name_match | 642 | 0.394 | 0.403 | 5915 func _process_skill_input_actions(delta: float) -> void: |
| `res://scripts/game_root.gd::531::_refresh_player_safe_zone_cache` | script_function_exact | exact_func_name_match | 757 | 0.394 | 0.639 | 528 func _refresh_player_safe_zone_cache(force := false) -> bool: |
| `res://scripts/device_lab_runtime.gd::215::DeviceLabRuntime._notification` | script_function_exact | exact_func_name_match | 642 | 0.394 | 0.394 | 212 func _notification(what: int) -> void: |
| `res://scripts/game_root.gd::6619::_validate_locked_target` | script_function_exact | exact_func_name_match | 757 | 0.392 | 0.392 | 6618 func _validate_locked_target() -> void: |
| `res://scripts/game_root.gd::6290::_update_boss_world_mechanics` | script_function_exact | exact_func_name_match | 642 | 0.384 | 0.384 | 6287 func _update_boss_world_mechanics(delta: float) -> void: |
| `res://scripts/player_status_marker_strip.gd::61::PlayerStatusMarkerStrip._process` | script_function_exact | exact_func_name_match | 642 | 0.381 | 5.642 | 60 func _process(_delta: float) -> void: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::0::OS.get_thread_caller_id` | shared_builtin_or_native | builtin_or_native_line_zero | 3996 | 0.37 | 0.37 | — |
| `res://scripts/player_state.gd::3913::relic_proc_status` | script_function_exact | exact_func_name_match | 642 | 0.358 | 2.377 | 3912 func relic_proc_status() -> Dictionary: |
| `res://scripts/game_root.gd::0::Input.is_action_pressed` | shared_builtin_or_native | builtin_or_native_line_zero | 642 | 0.356 | 0.356 | — |
| `res://scripts/town_music_controller.gd::180::TownMusicController.set_town_presence` | script_function_exact | exact_func_name_match | 642 | 0.348 | 0.348 | 179 func set_town_presence(in_town: bool, _area_id := "") -> void: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::288::MapEditorRuntimeCollisionGeometryService.map_inner_boundary_world` | script_function_exact | exact_func_name_match | 642 | 0.342 | 4.789 | 285 static func map_inner_boundary_world( |
| `res://scripts/hud_resource_orb.gd::0::CanvasItem.draw_arc` | shared_builtin_or_native | builtin_or_native_line_zero | 28 | 0.342 | 0.342 | — |
| `res://scripts/game_root.gd::4260::_update_portal_arrival_guard` | script_function_exact | exact_func_name_match | 642 | 0.341 | 0.57 | 4259 func _update_portal_arrival_guard() -> void: |
| `res://scripts/map_editor/polygon/poly_index.gd::83::circle_blocked` | poly_index_geometry | exact_func_name_match | 1985 | 0.34 | 13.032 | 82 func circle_blocked(p: Vector2, radius_gu: float) -> bool: |
| `res://scripts/player.gd::1916::PlayerCharacter._update_monster_source_poison` | script_function_exact | exact_func_name_match | 300 | 0.339 | 0.733 | 1915 func _update_monster_source_poison(delta: float) -> void: |
| `res://scripts/player_state.gd::3932::has_special_effect` | script_function_exact | exact_func_name_match | 2924 | 0.332 | 0.819 | 3931 func has_special_effect(effect_id: String) -> bool: |
| `res://scripts/loading_transition_overlay.gd::90::LoadingTransitionOverlay._process` | script_function_exact | exact_func_name_match | 642 | 0.331 | 0.331 | 89 func _process(delta: float) -> void: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::337::MapEditorRuntimeCollisionGeometryService.project_player_foot_inside_boundary` | script_function_exact | exact_func_name_match | 642 | 0.329 | 25.67 | 333 static func project_player_foot_inside_boundary( |
| `res://scripts/map_editor/polygon/poly_geometry.gd::0::Geometry2D.is_point_in_polygon` | shared_builtin_or_native | builtin_or_native_line_zero | 1832 | 0.327 | 0.327 | — |
| `res://scripts/map_editor/map_diamond_camera_constraint_service.gd::160::MapDiamondCameraConstraintService._ensure_entry` | script_function_exact | exact_func_name_match | 642 | 0.326 | 0.326 | 155 static func _ensure_entry( |
| `res://scripts/equipment_rules.gd::107::EquipmentRules.world_helmet_is_visible` | script_function_exact | exact_func_name_match | 642 | 0.323 | 1.109 | 106 static func world_helmet_is_visible() -> bool: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::444::MapEditorRuntimeCollisionGeometryService._cross` | script_function_exact | exact_func_name_match | 2568 | 0.315 | 0.315 | 443 static func _cross(a: Vector2, b: Vector2) -> float: |
| `res://scripts/helmet_visual_v2.gd::134::HelmetVisualV2.source_direction_row` | script_function_exact | exact_func_name_match | 642 | 0.31 | 9.323 | 133 static func source_direction_row(item_id: int, direction_row: int) -> int: |
| `res://scripts/monster_display_formatter.gd::22::MonsterDisplayFormatter.display_name` | script_function_exact | exact_func_name_match | 642 | 0.308 | 0.787 | 21 static func display_name(raw_name: String, monster_id := -1) -> String: |
| `res://scripts/game_data.gd::3784::get_item_record` | script_function_exact | exact_func_name_match | 27 | 0.304 | 1.205 | 3783 func get_item_record(item_ref: Variant) -> Dictionary: |
| `res://scripts/enemy.gd::9658::EnemyActor._hc_edge_blocked` | script_function_exact | exact_func_name_match | 1543 | 0.302 | 0.302 | 9657 func _hc_edge_blocked(a: Vector2i, b: Vector2i) -> bool: |
| `res://scripts/player_visual.gd::537::_layer_frame` | script_function_exact | exact_func_name_match | 1284 | 0.302 | 0.461 | 536 func _layer_frame(action_key: String, frame_counts: Dictionary) -> int: |
| `res://tests/world_crowd_firewall_profile_test.gd::0::Performance.get_monitor` | shared_builtin_or_native | builtin_or_native_line_zero | 1242 | 0.29 | 0.29 | — |
| `res://scripts/player.gd::0::Input.get_vector` | shared_builtin_or_native | builtin_or_native_line_zero | 300 | 0.287 | 0.287 | — |
| `res://scripts/enemy.gd::307::EnemyActor.@target_setter` | script_function_exact | source_present_no_exact_func_name | 697 | 0.284 | 0.284 | — |
| `res://scripts/equipment_rules.gd::115::EquipmentRules.world_helmet_head_mask_enabled` | script_function_exact | exact_func_name_match | 642 | 0.283 | 0.8 | 114 static func world_helmet_head_mask_enabled() -> bool: |
| `res://scripts/player_visual.gd::541::_warrior_or_default_frames` | script_function_exact | exact_func_name_match | 642 | 0.279 | 0.588 | 540 func _warrior_or_default_frames(state: StringName) -> int: |
| `res://scripts/monster_neighbor_step_policy.gd::70::MonsterNeighborStepPolicy.neighbor_target_from_cell` | script_function_exact | exact_func_name_match | 476 | 0.278 | 0.656 | 69 static func neighbor_target_from_cell(cell: Variant, neighbor: Variant) -> Vector2: |
| `res://scripts/player_state.gd::9059::_start_item_save` | script_function_exact | exact_func_name_match | 642 | 0.277 | 0.277 | 9058 func _start_item_save(retry_failed := false) -> bool: |
| `res://scripts/player_state.gd::390::_pump_persistence_receipts` | script_function_exact | exact_func_name_match | 642 | 0.274 | 14.246 | 389 func _pump_persistence_receipts() -> void: |
| `res://scripts/loot_pickup_runtime_manager.gd::374::LootPickupRuntimeManager._run_collection_pass` | script_function_exact | exact_func_name_match | 142 | 0.272 | 2.444 | 373 func _run_collection_pass(delta_seconds: float) -> void: |
| `res://scripts/profession_rules.gd::225::ProfessionRules.import_profession_identity` | script_function_exact | exact_func_name_match | 642 | 0.27 | 2.335 | 223 static func import_profession_identity(value: String) -> String: |
| `res://scripts/monster_neighbor_step_policy.gd::76::MonsterNeighborStepPolicy.desired_ground_direction` | script_function_exact | exact_func_name_match | 625 | 0.267 | 0.609 | 75 static func desired_ground_direction(neighbor: Variant) -> Vector2: |
| `res://scripts/identity/entity_registry.gd::17::ensure_loaded` | script_function_exact | exact_func_name_match | 983 | 0.264 | 0.264 | 16 static func ensure_loaded() -> bool: |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::74::MapEditorRuntimeBridge._load_release_registry` | script_function_exact | exact_func_name_match | 1284 | 0.26 | 0.26 | 73 static func _load_release_registry() -> void: |
| `res://scripts/enemy.gd::10287::EnemyActor._hc_frontline_candidates` | script_function_exact | exact_func_name_match | 75 | 0.258 | 1.161 | 10286 func _hc_frontline_candidates(a: Vector2, b: Vector2, hit_target: Node2D, candidates: Array) -> int: |
| `res://scripts/player_state.gd::7391::skill_slots_for_group` | script_function_exact | exact_func_name_match | 642 | 0.257 | 0.75 | 7390 func skill_slots_for_group(slot_group: String) -> Array[String]: |
| `res://scripts/game_root.gd::6109::_magic_target_domain_is_active` | script_function_exact | exact_func_name_match | 642 | 0.255 | 5.037 | 6108 func _magic_target_domain_is_active() -> bool: |
| `res://scripts/helmet_visual_v2.gd::244::HelmetVisualV2.final_position_delta` | script_function_exact | exact_func_name_match | 642 | 0.254 | 6.474 | 237 static func final_position_delta( |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::32::HCM30WalkPhase.moving_on` | script_function_exact | exact_func_name_match | 2042 | 0.252 | 0.252 | 31 func moving_on(physics_tick: int) -> bool: |
| `res://scripts/equipment_rules.gd::94::EquipmentRules.world_helmet_runtime_policy` | script_function_exact | exact_func_name_match | 1284 | 0.25 | 0.25 | 93 static func world_helmet_runtime_policy() -> Dictionary: |
| `res://scripts/player_visual.gd::997::_update_action_audio` | script_function_exact | exact_func_name_match | 642 | 0.248 | 0.336 | 996 func _update_action_audio() -> void: |
| `res://scripts/player.gd::1912::PlayerCharacter.poison_status_remaining` | script_function_exact | exact_func_name_match | 642 | 0.248 | 0.248 | 1911 func poison_status_remaining() -> float: |
| `res://scripts/enemy.gd::10137::EnemyActor._hc_direct_source_route_clear` | script_function_exact | exact_func_name_match | 107 | 0.245 | 20.488 | 10136 func _hc_direct_source_route_clear(origin: Vector2, destination: Vector2) -> bool: |
| `res://scripts/world_background.gd::238::WorldBackground.set_focus_position` | script_function_exact | exact_func_name_match | 642 | 0.241 | 0.241 | 237 func set_focus_position(world_position: Vector2) -> void: |
| `res://scripts/player.gd::0::InputMap.has_action` | shared_builtin_or_native | builtin_or_native_line_zero | 1200 | 0.238 | 0.238 | — |
| `res://scripts/monster_visual.gd::457::MonsterVisual._attack_logic_active` | script_function_exact | exact_func_name_match | 783 | 0.224 | 0.62 | 456 func _attack_logic_active() -> bool: |
| `res://scripts/monster_neighbor_step_policy.gd::51::MonsterNeighborStepPolicy.cell_center_ground_gu` | script_function_exact | exact_func_name_match | 952 | 0.219 | 0.219 | 50 static func cell_center_ground_gu(cell: Variant) -> Vector2: |
| `res://scripts/helmet_visual_v2.gd::40::HelmetVisualV2.calibration_overrides` | script_function_exact | exact_func_name_match | 1284 | 0.218 | 0.218 | 39 static func calibration_overrides() -> Dictionary: |
| `res://scripts/enemy.gd::936::EnemyActor._audio_is_listenable` | script_function_exact | exact_func_name_match | 25 | 0.214 | 0.365 | 935 func _audio_is_listenable(allow_death := false) -> bool: |
| `res://scripts/game_root.gd::13735::_poll_prepared_enemy_death_settlement` | script_function_exact | exact_func_name_match | 642 | 0.212 | 0.212 | 13734 func _poll_prepared_enemy_death_settlement(wait := false) -> bool: |
| `res://scripts/hud.gd::2986::GameHUD.update_warrior_states` | script_function_exact | exact_func_name_match | 44 | 0.206 | 0.206 | 2985 func update_warrior_states(snapshot: Dictionary) -> void: |
| `res://scripts/player.gd::1535::PlayerCharacter.warrior_state_snapshot` | script_function_exact | exact_func_name_match | 44 | 0.203 | 1.852 | 1534 func warrior_state_snapshot() -> Dictionary: |
| `res://scripts/ui_level_up_preview.gd::201::UILevelUpPreview._process` | script_function_exact | exact_func_name_match | 642 | 0.197 | 0.603 | 200 func _process(delta: float) -> void: |
| `res://scripts/equipment_granted_skill_rules.gd::58::definition` | script_function_exact | exact_func_name_match | 132 | 0.197 | 0.389 | 57 static func definition(skill_id: String) -> Dictionary: |
| `res://scripts/enemy.gd::9922::EnemyActor._hc_publish_crowd_goal` | script_function_exact | exact_func_name_match | 846 | 0.195 | 0.195 | 9921 func _hc_publish_crowd_goal(previous_goal: Vector2, new_goal: Vector2) -> Vector2: |
| `res://scripts/player_visual.gd::632::_v2_layer_texture` | script_function_exact | exact_func_name_match | 1926 | 0.195 | 0.195 | 626 func _v2_layer_texture( |
| `res://scripts/monster_crowd_attack_position_policy.gd::0::Object.get` | shared_builtin_or_native | builtin_or_native_line_zero | 2690 | 0.193 | 0.193 | — |
| `res://scripts/monster_visual_streaming_coordinator.gd::405::MonsterVisualStreamingCoordinator._retire_stale_loaded_jobs` | script_function_exact | exact_func_name_match | 519 | 0.19 | 0.19 | 404 func _retire_stale_loaded_jobs() -> void: |
| `res://scripts/enemy.gd::3216::EnemyActor._on_background_wakeup_timeout` | script_function_exact | exact_func_name_match | 40 | 0.189 | 2.577 | 3215 func _on_background_wakeup_timeout() -> void: |
| `res://scripts/monster_unit_adapter.gd::18::MonsterUnitAdapter.legacy_screen_scalar_px_to_gu` | script_function_exact | exact_func_name_match | 1589 | 0.186 | 0.186 | 17 static func legacy_screen_scalar_px_to_gu(value_px: float) -> float: |
| `res://scripts/player_state.gd::175::@profession_id_getter` | script_function_exact | generated_property_getter | 1328 | 0.185 | 0.185 | — |
| `res://scripts/monster_display_formatter.gd::140::MonsterDisplayFormatter._ensure_catalog` | script_function_exact | exact_func_name_match | 642 | 0.18 | 0.18 | 139 static func _ensure_catalog() -> void: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::0::OS.get_main_thread_id` | shared_builtin_or_native | builtin_or_native_line_zero | 3996 | 0.174 | 0.174 | — |
| `res://scripts/enemy.gd::1649::EnemyActor._refresh_target_focus` | script_function_exact | exact_func_name_match | 725 | 0.172 | 0.174 | 1648 func _refresh_target_focus(now_ms_override := -1) -> void: |
| `res://scripts/runtime_combat_spatial_index.gd::328::RuntimeCombatSpatialIndex.query_enemy_nodes_segment_unsorted_into` | script_function_exact | exact_func_name_match | 913 | 0.171 | 18.721 | 321 func query_enemy_nodes_segment_unsorted_into( |
| `res://scripts/player_notice_presenter.gd::189::PlayerNoticePresenter._process` | script_function_exact | exact_func_name_match | 642 | 0.17 | 0.17 | 188 func _process(delta: float) -> void: |
| `res://scripts/identity/entity_registry.gd::118::from_legacy` | script_function_exact | exact_func_name_match | 125 | 0.17 | 0.456 | 117 static func from_legacy(kind: String, old: Variant) -> String: |
| `res://scripts/hud.gd::2451::GameHUD.update_resources` | script_function_exact | exact_func_name_match | 35 | 0.168 | 0.257 | 2450 func update_resources(current_hp: int, max_hp: int, current_mp: int, max_mp: int) -> void: |
| `res://scripts/loot_pickup_runtime_manager.gd::462::LootPickupRuntimeManager._refresh_player_ground` | script_function_exact | exact_func_name_match | 150 | 0.167 | 2.257 | 461 func _refresh_player_ground() -> bool: |
| `res://scripts/map_editor/map_editor_runtime_collision_geometry_service.gd::328::MapEditorRuntimeCollisionGeometryService.default_player_foot_envelope_world` | script_function_exact | exact_func_name_match | 642 | 0.165 | 13.012 | 325 static func default_player_foot_envelope_world() -> PackedVector2Array: |
| `res://scripts/aoe_engagement_window.gd::109::AoeEngagementWindow.window_active` | script_function_exact | exact_func_name_match | 642 | 0.163 | 0.163 | 108 static func window_active() -> bool: |
| `res://scripts/runtime_combat_spatial_index.gd::527::RuntimeCombatSpatialIndex.<anonymous lambda>(lambda)` | script_function_exact | source_present_no_exact_func_name | 276 | 0.163 | 0.273 | — |
| `res://scripts/enemy.gd::3162::EnemyActor._enter_background_deep_sleep` | script_function_exact | exact_func_name_match | 1200 | 0.161 | 0.161 | 3161 func _enter_background_deep_sleep(initial_phase: bool) -> void: |
| `res://scripts/audio_runtime_service.gd::1207::AudioRuntimeService._on_event_finished` | script_function_exact | exact_func_name_match | 29 | 0.161 | 0.184 | 1206 func _on_event_finished(pool_index: int) -> void: |
| `res://scripts/game_root.gd::4745::_tick_bich_safe_zone_enforcement` | script_function_exact | exact_func_name_match | 642 | 0.157 | 0.157 | 4744 func _tick_bich_safe_zone_enforcement(delta: float) -> void: |
| `res://scripts/player_state.gd::9372::advance_temporary_item_buffs` | script_function_exact | exact_func_name_match | 642 | 0.156 | 0.156 | 9371 func advance_temporary_item_buffs(delta: float) -> void: |
| `res://scripts/persistent_ground_effect_manager.gd::179::PersistentGroundEffectManager.tick_frame` | script_function_exact | exact_func_name_match | 300 | 0.155 | 0.155 | 178 func tick_frame(delta: float) -> void: |
| `res://scripts/enemy.gd::905::EnemyActor._audio_combat_epoch` | script_function_exact | exact_func_name_match | 25 | 0.155 | 1.285 | 904 func _audio_combat_epoch() -> int: |
| `res://scripts/device_lab_runtime.gd::0::OS.is_debug_build` | shared_builtin_or_native | builtin_or_native_line_zero | 1286 | 0.149 | 0.149 | — |
| `res://scripts/monster_ai_package/path_scheduler.gd::63::HCMonsterPathScheduler.pump` | script_function_exact | exact_func_name_match | 237 | 0.147 | 2.996 | 62 func pump(soft_budget_usec: int = SOFT_BUDGET_USEC) -> void: |
| `res://scripts/player_state.gd::4410::apply_durability_event` | script_function_exact | exact_func_name_match | 13 | 0.144 | 0.365 | 4409 func apply_durability_event(event_id: String, context := {}) -> Dictionary: |
| `res://scripts/device_lab_runtime.gd::221::DeviceLabRuntime._poll_inbox` | script_function_exact | exact_func_name_match | 32 | 0.14 | 4.706 | 220 func _poll_inbox() -> void: |
| `res://scripts/enemy.gd::5172::EnemyActor._canonical_attack_frame_count` | script_function_exact | exact_func_name_match | 777 | 0.139 | 0.139 | 5167 func _canonical_attack_frame_count(minimum: int) -> int: |
| `res://scripts/runtime_combat_spatial_index.gd::713::RuntimeCombatSpatialIndex._take_bucket_ref` | script_function_exact | exact_func_name_match | 125 | 0.137 | 0.303 | 708 func _take_bucket_ref( |
| `res://scripts/hud.gd::1098::GameHUD.update_item_quick_slots` | script_function_exact | exact_func_name_match | 3 | 0.137 | 0.779 | 1097 func update_item_quick_slots() -> void: |
| `res://scripts/game_root.gd::9669::_expire_canonical_fire_charge_if_needed` | script_function_exact | exact_func_name_match | 642 | 0.135 | 0.135 | 9668 func _expire_canonical_fire_charge_if_needed() -> void: |
| `res://scripts/enemy.gd::1097::EnemyActor._combat_action_time_getter` | script_function_exact | exact_func_name_match | 1355 | 0.135 | 0.135 | 1096 func _combat_action_time_getter() -> float: |
| `res://scripts/player.gd::1010::PlayerCharacter._apply_resolved_damage` | script_function_exact | exact_func_name_match | 13 | 0.134 | 3.007 | 999 func _apply_resolved_damage( |
| `res://scripts/skills/skill_footprint_snapshot.gd::1498::SkillFootprintSnapshot._create_polygon_snapshot` | script_function_exact | exact_func_name_match | 13 | 0.131 | 0.924 | 1488 static func _create_polygon_snapshot( |
| `res://scripts/game_root.gd::5619::_refresh_mobile_attack_held` | script_function_exact | exact_func_name_match | 642 | 0.129 | 0.129 | 5618 func _refresh_mobile_attack_held() -> void: |
| `res://scripts/enemy.gd::9030::EnemyActor._hc_settle` | script_function_exact | exact_func_name_match | 13 | 0.129 | 3.825 | 9029 func _hc_settle(record: Dictionary) -> void: |
| `res://scripts/monster_visual.gd::858::MonsterVisual._manual_alignment_profile_for_actor` | script_function_exact | exact_func_name_match | 106 | 0.126 | 0.302 | 857 func _manual_alignment_profile_for_actor() -> Dictionary: |
| `res://scripts/loot_pickup_runtime_manager.gd::218::LootPickupRuntimeManager.player_position_changed` | script_function_exact | exact_func_name_match | 115 | 0.125 | 4.208 | 217 func player_position_changed(position_px: Vector2) -> void: |
| `res://scripts/game_root.gd::11335::_tick_ongoing_heals` | script_function_exact | exact_func_name_match | 642 | 0.122 | 0.122 | 11334 func _tick_ongoing_heals(delta: float) -> void: |
| `res://scripts/hud_resource_orb.gd::0::CanvasItem.draw_line` | shared_builtin_or_native | builtin_or_native_line_zero | 836 | 0.122 | 0.122 | — |
| `res://scripts/enemy.gd::6070::EnemyActor._decorate_attack_footprint_snapshot` | script_function_exact | exact_func_name_match | 13 | 0.121 | 0.157 | 6063 func _decorate_attack_footprint_snapshot( |
| `res://scripts/hud.gd::1165::GameHUD._notification` | script_function_exact | exact_func_name_match | 642 | 0.12 | 0.12 | 1164 func _notification(what: int) -> void: |
| `res://scripts/player_state.gd::7875::update_world_location` | script_function_exact | exact_func_name_match | 642 | 0.12 | 0.12 | 7870 func update_world_location( |
| `res://scripts/enemy.gd::981::EnemyActor._emit_monster_audio` | script_function_exact | exact_func_name_match | 25 | 0.115 | 4.253 | 976 func _emit_monster_audio( |
| `res://scripts/player.gd::1710::PlayerCharacter._process_potion_restore` | script_function_exact | exact_func_name_match | 300 | 0.114 | 0.114 | 1709 func _process_potion_restore(delta: float) -> void: |
| `res://scripts/runtime_combat_spatial_index.gd::700::RuntimeCombatSpatialIndex._bucket_set` | script_function_exact | exact_func_name_match | 125 | 0.112 | 0.142 | 699 func _bucket_set(runtime_map_id: int, bucket_key: Vector2i) -> Dictionary: |
| `res://scripts/player_state.gd::7646::apply_warrior_runtime_state` | script_function_exact | exact_func_name_match | 25 | 0.112 | 0.253 | 7645 func apply_warrior_runtime_state(snapshot: Dictionary, persist := false) -> bool: |
| `res://scripts/enemy.gd::8121::EnemyActor._return_to_spawn` | script_function_exact | exact_func_name_match | 40 | 0.111 | 0.16 | 8118 func _return_to_spawn( |
| `res://scripts/enemy.gd::959::EnemyActor._audio_context` | script_function_exact | exact_func_name_match | 25 | 0.111 | 1.613 | 958 func _audio_context(semantic_event: String) -> Dictionary: |
| `res://scripts/skills/skill_data_loader.gd::134::SkillDataLoader.stable_skill_id` | script_function_exact | exact_func_name_match | 88 | 0.11 | 0.77 | 133 static func stable_skill_id(skill_name_or_id: String) -> String: |
| `res://scripts/game_root.gd::13664::_compact_enemy_death_queue` | script_function_exact | exact_func_name_match | 642 | 0.109 | 0.109 | 13663 func _compact_enemy_death_queue() -> void: |
| `res://scripts/enemy.gd::1996::EnemyActor._locomotion_segment_clear` | script_function_exact | exact_func_name_match | 476 | 0.106 | 4.304 | 1995 func _locomotion_segment_clear(a: Vector2, b: Vector2) -> bool: |
| `res://scripts/monster_visual.gd::802::MonsterVisual.ground_contact_position` | script_function_exact | exact_func_name_match | 53 | 0.106 | 0.862 | 801 func ground_contact_position(fallback: Vector2) -> Vector2: |
| `res://scripts/player_state.gd::4519::_durability_roll` | script_function_exact | exact_func_name_match | 143 | 0.106 | 0.141 | 4518 func _durability_roll(context: Dictionary, key: String, minimum: int, maximum: int) -> int: |
| `res://scripts/monster_visual.gd::831::MonsterVisual.visual_foot_offset` | script_function_exact | exact_func_name_match | 46 | 0.104 | 0.523 | 830 func visual_foot_offset() -> Vector2: |
| `res://scripts/audio_runtime_service.gd::1090::AudioRuntimeService._valid_event_runtime_paths` | script_function_exact | exact_func_name_match | 32 | 0.104 | 0.122 | 1089 func _valid_event_runtime_paths(raw_paths: Variant) -> Array[String]: |
| `res://scripts/hud_resource_orb.gd::0::CanvasItem.draw_circle` | shared_builtin_or_native | builtin_or_native_line_zero | 28 | 0.102 | 0.102 | — |
| `res://scripts/caster_skill_visual_registry.gd::69::CasterSkillVisualRegistry.is_loading_window_active` | script_function_exact | exact_func_name_match | 642 | 0.101 | 0.101 | 68 static func is_loading_window_active() -> bool: |
| `res://scripts/audio_runtime_service.gd::988::AudioRuntimeService._active_monster_event_count` | script_function_exact | exact_func_name_match | 13 | 0.101 | 0.134 | 987 func _active_monster_event_count() -> int: |
| `res://scripts/loot_pickup_runtime_manager.gd::470::LootPickupRuntimeManager._screen_position_to_ground` | script_function_exact | exact_func_name_match | 150 | 0.1 | 2.004 | 469 func _screen_position_to_ground(position_px: Vector2) -> Vector2: |
| `res://scripts/ui_level_up_preview.gd::151::UILevelUpPreview.advance_preview` | script_function_exact | exact_func_name_match | 642 | 0.099 | 0.099 | 150 func advance_preview(delta_seconds: float) -> void: |
| `res://scripts/player.gd::0::Object.has_meta` | shared_builtin_or_native | builtin_or_native_line_zero | 1207 | 0.098 | 0.098 | — |
| `res://scripts/player_health_bar.gd::0::CanvasItem.draw_string` | shared_builtin_or_native | builtin_or_native_line_zero | 14 | 0.094 | 0.094 | — |
| `res://scripts/game_root.gd::0::Time.get_ticks_msec` | shared_builtin_or_native | builtin_or_native_line_zero | 1232 | 0.093 | 0.093 | — |
| `res://scripts/enemy.gd::6843::EnemyActor._crowd_separation` | script_function_exact | exact_func_name_match | 7 | 0.092 | 1.082 | 6842 func _crowd_separation() -> Vector2: |
| `res://scripts/monster_source_poison_state.gd::28::advance` | script_function_exact | exact_func_name_match | 300 | 0.091 | 0.091 | 27 func advance(delta: float) -> int: |
| `res://scripts/town_music_controller.gd::92::TownMusicController.is_main_city_map` | script_function_exact | exact_func_name_match | 642 | 0.089 | 0.278 | 91 static func is_main_city_map(map_id: int) -> bool: |
| `res://scripts/player_health_bar.gd::106::PlayerHealthBar._draw` | script_function_exact | exact_func_name_match | 14 | 0.089 | 0.279 | 105 func _draw() -> void: |
| `res://scripts/monster_visual_streaming_coordinator.gd::1346::MonsterVisualStreamingCoordinator.protected_overbudget_bytes` | budget_admission_or_scheduler | exact_func_name_match | 642 | 0.088 | 0.088 | 1345 func protected_overbudget_bytes() -> int: |
| `res://scripts/player_state.gd::430::_advance_durability_runtime` | script_function_exact | exact_func_name_match | 642 | 0.086 | 0.086 | 429 func _advance_durability_runtime(delta: float) -> void: |
| `res://scripts/game_root.gd::5962::_process_magic_shield_auto_refresh` | script_function_exact | exact_func_name_match | 642 | 0.086 | 0.086 | 5961 func _process_magic_shield_auto_refresh(delta: float) -> void: |
| `res://scripts/layers/runtime/execution/frame_budget.gd::0::Engine.get_main_loop` | shared_builtin_or_native | builtin_or_native_line_zero | 612 | 0.085 | 0.085 | — |
| `res://scripts/game_root.gd::6469::_on_player_moved` | script_function_exact | exact_func_name_match | 115 | 0.083 | 4.618 | 6468 func _on_player_moved(_position: Vector2, _facing: Vector2) -> void: |
| `res://scripts/monster_ai_package/path_scheduler.gd::0::Time.get_ticks_usec` | shared_builtin_or_native | builtin_or_native_line_zero | 1519 | 0.081 | 0.081 | — |
| `res://scripts/audio_runtime_service.gd::1136::AudioRuntimeService._reject_event` | script_function_exact | exact_func_name_match | 12 | 0.08 | 0.161 | 1135 func _reject_event(reason: String, event_id: String, context: Dictionary, runtime_path := "") -> Dictionary: |
| `res://scripts/enemy.gd::3191::EnemyActor._background_wakeup_interval_seconds` | script_function_exact | exact_func_name_match | 40 | 0.078 | 0.123 | 3190 func _background_wakeup_interval_seconds() -> float: |
| `res://scripts/identity/entity_registry.gd::138::_legacy_key` | script_function_exact | exact_func_name_match | 125 | 0.078 | 0.078 | 137 static func _legacy_key(kind: String, old: Variant) -> String: |
| `res://scripts/game_data.gd::3918::_valid_explicit_item_reference` | script_function_exact | exact_func_name_match | 39 | 0.078 | 0.224 | 3917 func _valid_explicit_item_reference(value: Variant, runtime_membership := true) -> bool: |
| `res://scripts/monster_ai_package/path_scheduler.gd::60::HCMonsterPathScheduler._physics_process` | script_function_exact | exact_func_name_match | 237 | 0.077 | 3.208 | 59 func _physics_process(_delta: float) -> void: |
| `res://scripts/audio_runtime_service.gd::568::AudioRuntimeService.play_monster_event` | script_function_exact | exact_func_name_match | 25 | 0.076 | 1.994 | 567 func play_monster_event(monster_id: int, semantic_event: String, context: Dictionary = {}) -> Dictionary: |
| `res://scripts/player_state.gd::233::@attack_skill_slots_getter` | script_function_exact | generated_property_getter | 642 | 0.075 | 0.075 | — |
| `res://scripts/monster_visual.gd::489::MonsterVisual.attack_frame_phase_reached` | script_function_exact | exact_func_name_match | 137 | 0.075 | 0.291 | 488 func attack_frame_phase_reached() -> bool: |
| `res://scripts/enemy.gd::832::EnemyActor._audio_service` | script_function_exact | exact_func_name_match | 25 | 0.074 | 0.076 | 831 func _audio_service() -> Node: |
| `res://scripts/enemy.gd::5675::EnemyActor._deal_melee_hit` | script_function_exact | exact_func_name_match | 13 | 0.073 | 3.412 | 5668 func _deal_melee_hit( |
| `res://scripts/hud.gd::255::GameHUD._process` | script_function_exact | exact_func_name_match | 642 | 0.07 | 0.07 | 254 func _process(_delta: float) -> void: |
| `res://scripts/enemy.gd::897::EnemyActor._audio_combat_transition_is_active` | script_function_exact | exact_func_name_match | 25 | 0.069 | 0.105 | 893 func _audio_combat_transition_is_active() -> bool: |
| `res://scripts/player_visual.gd::1013::_dispatch_player_reaction_action_start_audio` | script_function_exact | exact_func_name_match | 8 | 0.069 | 1.143 | 1012 func _dispatch_player_reaction_action_start_audio(animation_name: String) -> void: |
| `res://scripts/skills/skill_footprint_snapshot.gd::119::SkillFootprintSnapshot._call_vector2_result` | script_function_exact | exact_func_name_match | 65 | 0.069 | 0.599 | 115 static func _call_vector2_result( |
| `res://scripts/monster_visual.gd::888::MonsterVisual._refresh_actor_ground_indicator` | script_function_exact | exact_func_name_match | 53 | 0.066 | 1.325 | 887 func _refresh_actor_ground_indicator() -> void: |
| `res://scripts/monster_visual.gd::472::MonsterVisual.current_attack_action_id` | script_function_exact | exact_func_name_match | 137 | 0.066 | 0.297 | 471 func current_attack_action_id() -> int: |
| `res://scripts/runtime_loot_spatial_index.gd::246::RuntimeLootSpatialIndex._bucket_key` | script_function_exact | exact_func_name_match | 284 | 0.062 | 0.062 | 245 func _bucket_key(ground_gu: Vector2) -> Vector2i: |
| `res://scripts/enemy.gd::2190::EnemyActor._continue_continuous_pursuit_from_current_target` | script_function_exact | exact_func_name_match | 198 | 0.062 | 0.351 | 2189 func _continue_continuous_pursuit_from_current_target() -> void: |
| `res://scripts/player_health_bar.gd::81::PlayerHealthBar.layout_snapshot` | script_function_exact | exact_func_name_match | 14 | 0.062 | 0.062 | 80 func layout_snapshot() -> Dictionary: |
| `res://scripts/game_data.gd::4067::_stable_identity` | script_function_exact | exact_func_name_match | 39 | 0.062 | 0.198 | 4066 func _stable_identity(item_ref: Variant) -> Dictionary: |
| `res://scripts/player.gd::1558::PlayerCharacter.warrior_runtime_state_for_save` | script_function_exact | exact_func_name_match | 25 | 0.06 | 0.06 | 1557 func warrior_runtime_state_for_save() -> Dictionary: |
| `res://scripts/player_state.gd::7840::_normalized_warrior_runtime_state` | script_function_exact | exact_func_name_match | 25 | 0.057 | 0.093 | 7839 func _normalized_warrior_runtime_state(snapshot: Variant) -> Dictionary: |
| `res://scripts/skills/skill_footprint_snapshot.gd::203::SkillFootprintSnapshot.project_ground_polygon_to_screen_offsets_px` | script_function_exact | exact_func_name_match | 13 | 0.055 | 0.714 | 198 static func project_ground_polygon_to_screen_offsets_px( |
| `res://scripts/device_lab_runtime.gd::256::DeviceLabRuntime._external_mirror_pending_path` | script_function_exact | exact_func_name_match | 32 | 0.053 | 0.074 | 255 func _external_mirror_pending_path() -> String: |
| `res://scripts/audio_runtime_service.gd::1014::AudioRuntimeService._find_event_player_candidate` | script_function_exact | exact_func_name_match | 32 | 0.052 | 0.052 | 1013 func _find_event_player_candidate(new_priority: int) -> int: |
| `res://scripts/audio_runtime_service.gd::1188::AudioRuntimeService._emit_diagnostic` | script_function_exact | exact_func_name_match | 12 | 0.052 | 0.061 | 1187 func _emit_diagnostic(reason: String, details: Dictionary) -> void: |
| `res://scripts/skills/skill_data_loader.gd::485::SkillDataLoader._equipment_granted_definition` | script_function_exact | exact_func_name_match | 44 | 0.051 | 0.226 | 484 static func _equipment_granted_definition(skill_name_or_id: String) -> Dictionary: |
| `res://scripts/player.gd::0::Time.get_ticks_msec` | shared_builtin_or_native | builtin_or_native_line_zero | 489 | 0.051 | 0.051 | — |
| `res://scripts/equipment_granted_skill_rules.gd::13::ensure_loaded` | script_function_exact | exact_func_name_match | 132 | 0.05 | 0.05 | 12 static func ensure_loaded() -> bool: |
| `res://scripts/hud_resource_orb.gd::26::HUDResourceOrb.set_values` | script_function_exact | exact_func_name_match | 70 | 0.049 | 0.053 | 25 func set_values(current: int, maximum: int) -> void: |
| `res://scripts/monster_visual.gd::778::MonsterVisual.manual_alignment_replay_displacement` | script_function_exact | exact_func_name_match | 53 | 0.048 | 0.138 | 777 func manual_alignment_replay_displacement() -> Vector2: |
| `res://scripts/skills/skill_data_loader.gd::153::SkillDataLoader.entity_skill_id` | script_function_exact | exact_func_name_match | 44 | 0.047 | 0.781 | 152 static func entity_skill_id(skill_name_or_id: String) -> String: |
| `res://scripts/enemy.gd::6054::EnemyActor._next_spatial_release_id` | script_function_exact | exact_func_name_match | 13 | 0.047 | 0.048 | 6053 func _next_spatial_release_id(kind: String) -> String: |
| `res://scripts/audio_runtime_service.gd::1110::AudioRuntimeService._stream_for` | script_function_exact | exact_func_name_match | 32 | 0.047 | 0.073 | 1109 func _stream_for(runtime_path: String) -> AudioStream: |
| `res://scripts/monster_target_ring_geometry.gd::11::resolve` | script_function_exact | exact_func_name_match | 53 | 0.046 | 0.07 | 10 static func resolve(monster_id: int, physics_radii: Vector2) -> Vector2: |
| `res://scripts/skills/skill_footprint_snapshot.gd::394::SkillFootprintSnapshot.create_centered_rectangle` | script_function_exact | exact_func_name_match | 13 | 0.046 | 0.989 | 387 static func create_centered_rectangle( |
| `res://scripts/map_editor/polygon/poly_path_search.gd::86::advance` | poly_nav_path_dependency | exact_func_name_match | 2 | 0.045 | 1.929 | 85 func advance(limit := 384, deadline_usec := 0) -> String: |
| `res://scripts/enemy.gd::5797::EnemyActor._monster_physical_hit_succeeds` | script_function_exact | exact_func_name_match | 13 | 0.044 | 0.108 | 5796 func _monster_physical_hit_succeeds(hit_target: Node2D, forced_roll := -1) -> bool: |
| `res://scripts/quick_item_icon_layout.gd::0::Object.get_instance_id` | shared_builtin_or_native | builtin_or_native_line_zero | 1081 | 0.044 | 0.044 | — |
| `res://scripts/special_consumable_stacks.gd::6::split_available` | script_function_exact | exact_func_name_match | 3 | 0.042 | 0.196 | 5 static func split_available(records: Array, capacity: int, page_size: int) -> Array: |
| `res://scripts/audio_runtime_service.gd::1002::AudioRuntimeService._owner_release_key` | script_function_exact | exact_func_name_match | 32 | 0.041 | 0.08 | 1001 func _owner_release_key(event_id: String, context: Dictionary) -> String: |
| `res://tests/phone_crowd_baseline_20261008.gd::364::_active_loot_count` | test_fixture | exact_func_name_match | 1 | 0.038 | 0.043 | 363 func _active_loot_count() -> int: |
| `res://scripts/player_visual.gd::491::_is_warrior_attack_action` | script_function_exact | exact_func_name_match | 92 | 0.037 | 0.054 | 490 func _is_warrior_attack_action(animation_name: String) -> bool: |
| `res://scripts/player_state.gd::3308::is_skill_learned` | script_function_exact | exact_func_name_match | 44 | 0.037 | 1.556 | 3307 func is_skill_learned(skill_name: String) -> bool: |
| `res://scripts/audio_runtime_service.gd::1039::AudioRuntimeService._acquire_event_player` | script_function_exact | exact_func_name_match | 32 | 0.036 | 0.036 | 1038 func _acquire_event_player(new_priority: int) -> int: |
| `res://scripts/enemy.gd::0::Timer.start` | shared_builtin_or_native | builtin_or_native_line_zero | 40 | 0.035 | 0.035 | — |
| `res://scripts/skills/skill_data_loader.gd::58::SkillDataLoader.document` | script_function_exact | exact_func_name_match | 88 | 0.035 | 0.035 | 57 static func document() -> Dictionary: |
| `res://scripts/monster_visual.gd::1228::MonsterVisual._start_attack_visual` | script_function_exact | exact_func_name_match | 13 | 0.035 | 0.161 | 1227 func _start_attack_visual(duration: float) -> void: |
| `res://scripts/game_data.gd::3790::get_entity_record` | script_function_exact | exact_func_name_match | 27 | 0.035 | 0.992 | 3789 func get_entity_record(entity_id: String) -> Dictionary: |
| `res://scripts/monster_ai_package/path_scheduler.gd::0::Engine.get_physics_frames` | shared_builtin_or_native | builtin_or_native_line_zero | 958 | 0.035 | 0.035 | — |
| `res://scripts/monster_visual.gd::875::MonsterVisual._manual_alignment_manifest` | script_function_exact | exact_func_name_match | 106 | 0.034 | 0.034 | 874 static func _manual_alignment_manifest() -> Dictionary: |
| `res://scripts/monster_target_acquisition_policy.gd::50::MonsterTargetAcquisitionPolicy.contains_ground_delta_gu` | script_function_exact | exact_func_name_match | 36 | 0.033 | 0.033 | 49 func contains_ground_delta_gu(delta_ground_gu: Vector2) -> bool: |
| `res://scripts/player.gd::809::PlayerCharacter.take_damage` | script_function_exact | exact_func_name_match | 13 | 0.033 | 3.064 | 802 func take_damage( |
| `res://scripts/identity/entity_registry.gd::141::_numeric_id` | script_function_exact | exact_func_name_match | 81 | 0.033 | 0.033 | 140 static func _numeric_id(value: Variant) -> bool: |
| `res://scripts/enemy.gd::495::EnemyActor._try_reserve_source_body_action` | script_function_exact | exact_func_name_match | 13 | 0.032 | 0.049 | 494 func _try_reserve_source_body_action(incompatible_pending: bool) -> bool: |
| `res://scripts/enemy.gd::1085::EnemyActor._allocate_attack_action` | script_function_exact | exact_func_name_match | 13 | 0.032 | 0.048 | 1084 func _allocate_attack_action(duration: float) -> int: |
| `res://scripts/monster_ai_package/path_scheduler.gd::77::HCMonsterPathScheduler._pump_slice` | script_function_exact | exact_func_name_match | 2 | 0.032 | 2.036 | 76 func _pump_slice(soft_budget_usec: int) -> void: |
| `res://scripts/enemy.gd::8405::EnemyActor.ground_indicator_radii` | script_function_exact | exact_func_name_match | 53 | 0.031 | 0.221 | 8403 func ground_indicator_radii() -> Vector2: |
| `res://scripts/audio_runtime_service.gd::960::AudioRuntimeService._admission_reason` | script_function_exact | exact_func_name_match | 32 | 0.031 | 0.293 | 952 func _admission_reason( |
| `res://scripts/game_root.gd::14738::_sync_player_runtime_snapshot_to_hud` | script_function_exact | exact_func_name_match | 19 | 0.031 | 0.901 | 14737 func _sync_player_runtime_snapshot_to_hud() -> void: |
| `res://scripts/enemy.gd::5788::EnemyActor._target_agility_for_monster_hit` | script_function_exact | exact_func_name_match | 13 | 0.031 | 0.055 | 5787 func _target_agility_for_monster_hit(hit_target: Node2D) -> int: |
| `res://scripts/game_data.gd::4096::_stable_item_id` | script_function_exact | exact_func_name_match | 48 | 0.031 | 0.068 | 4095 func _stable_item_id(record: Dictionary) -> int: |
| `res://scripts/enemy.gd::9707::EnemyActor._hc_goal_points` | script_function_exact | exact_func_name_match | 1 | 0.031 | 1.303 | 9706 func _hc_goal_points(anchor: Vector2) -> Dictionary: |
| `res://scripts/enemy.gd::8395::EnemyActor.ground_indicator_center` | script_function_exact | exact_func_name_match | 53 | 0.029 | 0.983 | 8390 func ground_indicator_center() -> Vector2: |
| `res://scripts/player_health_bar.gd::71::PlayerHealthBar.set_health` | script_function_exact | exact_func_name_match | 16 | 0.029 | 0.031 | 70 func set_health(current_value: int, maximum_value: int) -> void: |
| `res://scripts/enemy.gd::5856::EnemyActor._apply_attack_damage_impl` | script_function_exact | exact_func_name_match | 13 | 0.029 | 3.257 | 5846 func _apply_attack_damage_impl( |
| `res://scripts/player_state.gd::7555::use_quick_item_slot` | script_function_exact | exact_func_name_match | 3 | 0.029 | 3.129 | 7554 func use_quick_item_slot(index: int, expected_item_id := "") -> Dictionary: |
| `res://scripts/monster_ai_package/path_scheduler.gd::0::GDScript.new` | shared_builtin_or_native | builtin_or_native_line_zero | 3 | 0.029 | 0.029 | — |
| `res://scripts/audio_runtime_service.gd::273::AudioRuntimeService._now_msec` | script_function_exact | exact_func_name_match | 39 | 0.028 | 0.033 | 272 func _now_msec() -> int: |
| `res://scripts/enemy.gd::1101::EnemyActor._play_attack_animation` | script_function_exact | exact_func_name_match | 13 | 0.027 | 3.816 | 1100 func _play_attack_animation(duration: float, parent_action_id := -1) -> void: |
| `res://scripts/player_visual.gd::383::uses_final_art` | script_function_exact | exact_func_name_match | 28 | 0.026 | 0.026 | 382 func uses_final_art() -> bool: |
| `res://scripts/player_visual.gd::329::play_action` | script_function_exact | exact_func_name_match | 13 | 0.025 | 1.173 | 328 func play_action(animation_name: String, duration: float) -> void: |
| `res://scripts/enemy.gd::10156::EnemyActor._hc_fail_step` | script_function_exact | exact_func_name_match | 13 | 0.025 | 0.107 | 10155 func _hc_fail_step() -> void: |
| `res://scripts/audio_runtime_service.gd::941::AudioRuntimeService._select_event_variant` | script_function_exact | exact_func_name_match | 32 | 0.025 | 0.038 | 935 func _select_event_variant( |
| `res://scripts/audio_runtime_service.gd::0::Time.get_ticks_msec` | shared_builtin_or_native | builtin_or_native_line_zero | 415 | 0.025 | 0.025 | — |
| `res://scripts/items/rune_item_rules.gd::47::record_for_id` | script_function_exact | exact_func_name_match | 45 | 0.024 | 0.055 | 46 static func record_for_id(item_id: int) -> Dictionary: |
| `res://scripts/game_data.gd::4106::_service_index` | script_function_exact | exact_func_name_match | 39 | 0.024 | 0.033 | 4105 func _service_index(record: Dictionary) -> int: |
| `res://scripts/enemy.gd::1641::EnemyActor._initial_acquisition_contains_ground_delta_gu` | script_function_exact | exact_func_name_match | 36 | 0.023 | 0.08 | 1640 func _initial_acquisition_contains_ground_delta_gu(delta_ground_gu: Vector2) -> bool: |
| `res://scripts/player_state.gd::2323::use_inventory_index_result` | script_function_exact | exact_func_name_match | 3 | 0.023 | 2.383 | 2322 func use_inventory_index_result(index: int, save_in_background := false) -> Dictionary: |
| `res://scripts/player.gd::1512::PlayerCharacter.skill_cooldown_remaining_ms` | script_function_exact | exact_func_name_match | 44 | 0.022 | 0.032 | 1511 func skill_cooldown_remaining_ms(stable_skill_id: String) -> int: |
| `res://scripts/enemy.gd::875::EnemyActor._audio_owner_key_for_actor` | script_function_exact | exact_func_name_match | 25 | 0.022 | 0.022 | 874 func _audio_owner_key_for_actor() -> String: |
| `res://scripts/skills/skill_progression_service.gd::96::SkillProgressionService.is_learned` | script_function_exact | exact_func_name_match | 44 | 0.021 | 0.841 | 95 func is_learned(skill_name_or_id: String) -> bool: |
| `res://scripts/device_lab_runtime.gd::0::OS.get_name` | shared_builtin_or_native | builtin_or_native_line_zero | 32 | 0.021 | 0.021 | — |
| `res://scripts/skills/skill_footprint_snapshot.gd::82::SkillFootprintSnapshot.make_absolute_runtime_context` | script_function_exact | exact_func_name_match | 13 | 0.021 | 0.038 | 76 static func make_absolute_runtime_context( |
| `res://scripts/skills/skill_footprint_snapshot.gd::154::SkillFootprintSnapshot._coordinate_fields_from_context` | script_function_exact | exact_func_name_match | 13 | 0.02 | 0.043 | 151 static func _coordinate_fields_from_context( |
| `res://scripts/enemy.gd::2170::EnemyActor._clear_continuous_pursuit_intent` | script_function_exact | exact_func_name_match | 28 | 0.019 | 0.037 | 2169 func _clear_continuous_pursuit_intent() -> void: |
| `res://scripts/enemy.gd::5835::EnemyActor._apply_attack_damage` | script_function_exact | exact_func_name_match | 13 | 0.019 | 3.284 | 5825 func _apply_attack_damage( |
| `res://scripts/monster_source_frames.gd::29::profile_for_id` | script_function_exact | exact_func_name_match | 13 | 0.019 | 0.064 | 28 static func profile_for_id(monster_id: int) -> Dictionary: |
| `res://scripts/player.gd::1945::PlayerCharacter._draw` | script_function_exact | exact_func_name_match | 14 | 0.019 | 0.06 | 1941 func _draw() -> void: |
| `res://scripts/player.gd::0::RandomNumberGenerator.randi_range` | shared_builtin_or_native | builtin_or_native_line_zero | 169 | 0.019 | 0.019 | — |
| `res://scripts/enemy.gd::6050::EnemyActor._monster_attack_id` | script_function_exact | exact_func_name_match | 13 | 0.019 | 0.019 | 6049 func _monster_attack_id(kind: String) -> String: |
| `res://scripts/profession_rules.gd::442::ProfessionRules.player_struck_damage_threshold` | script_function_exact | exact_func_name_match | 13 | 0.019 | 0.072 | 441 static func player_struck_damage_threshold(max_hp_value: int) -> int: |
| `res://scripts/player.gd::1205::PlayerCharacter._incoming_red_poison_active` | script_function_exact | exact_func_name_match | 13 | 0.018 | 0.024 | 1204 func _incoming_red_poison_active(context: Dictionary) -> bool: |
| `res://scripts/player_health_bar.gd::0::CanvasItem.draw_rect` | shared_builtin_or_native | builtin_or_native_line_zero | 28 | 0.018 | 0.018 | — |
| `res://scripts/monster_visual.gd::815::MonsterVisual.target_ring_position` | script_function_exact | exact_func_name_match | 53 | 0.017 | 0.921 | 811 func target_ring_position(fallback: Vector2) -> Vector2: |
| `res://scripts/enemy.gd::6002::EnemyActor._snapshot_coordinate_context` | script_function_exact | exact_func_name_match | 13 | 0.017 | 0.093 | 6001 func _snapshot_coordinate_context() -> Dictionary: |
| `res://scripts/player_state.gd::10242::_commit_save` | script_function_exact | exact_func_name_match | 3 | 0.017 | 0.225 | 10241 func _commit_save(update_profile_index := true, checkpoint_world := false) -> bool: |
| `res://scripts/ui_selection_dismiss_guard.gd::250::UISelectionDismissGuard._move_observer_last` | script_function_exact | exact_func_name_match | 1 | 0.017 | 0.019 | 247 func _move_observer_last() -> void: |
| `res://scripts/monster_visual.gd::437::MonsterVisual._now_ms` | script_function_exact | exact_func_name_match | 13 | 0.016 | 0.016 | 436 func _now_ms() -> int: |
| `res://scripts/enemy.gd::9627::EnemyActor._hc_cancel_path` | script_function_exact | exact_func_name_match | 20 | 0.015 | 0.015 | 9626 func _hc_cancel_path() -> void: |
| `res://scripts/player.gd::1435::PlayerCharacter._start_struck_reaction` | script_function_exact | exact_func_name_match | 13 | 0.015 | 1.293 | 1434 func _start_struck_reaction() -> void: |
| `res://scripts/monster_visual.gd::1161::MonsterVisual.begin_attack_presentation` | script_function_exact | exact_func_name_match | 13 | 0.015 | 0.198 | 1154 func begin_attack_presentation( |
| `res://scripts/monster_visual.gd::847::MonsterVisual.ground_projection_strategy` | script_function_exact | exact_func_name_match | 60 | 0.014 | 0.055 | 846 func ground_projection_strategy() -> String: |
| `res://scripts/profession_rules.gd::486::ProfessionRules.player_struck_reaction_seconds` | script_function_exact | exact_func_name_match | 13 | 0.014 | 0.073 | 485 static func player_struck_reaction_seconds(character_level: int) -> float: |
| `res://scripts/items/item_extension_codec.gd::29::decode_wire` | script_function_exact | exact_func_name_match | 6 | 0.014 | 0.043 | 26 static func decode_wire(record: Dictionary) -> Dictionary: |
| `res://scripts/hud.gd::0::Object.set_meta` | shared_builtin_or_native | builtin_or_native_line_zero | 48 | 0.014 | 0.014 | — |
| `res://scripts/ui_selection_dismiss_guard.gd::0::Object.is_queued_for_deletion` | shared_builtin_or_native | builtin_or_native_line_zero | 328 | 0.014 | 0.014 | — |
| `res://scripts/map_editor/polygon/poly_path_search.gd::66::_prepare_goal_one` | poly_nav_path_dependency | exact_func_name_match | 9 | 0.014 | 0.088 | 65 func _prepare_goal_one() -> void: |
| `res://scripts/enemy.gd::4287::EnemyActor._uses_monster_special_cell_delivery` | script_function_exact | exact_func_name_match | 13 | 0.013 | 0.016 | 4286 func _uses_monster_special_cell_delivery() -> bool: |
| `res://scripts/profession_rules.gd::184::ProfessionRules._data` | script_function_exact | exact_func_name_match | 52 | 0.012 | 0.012 | 183 static func _data() -> Dictionary: |
| `res://scripts/enemy.gd::6890::EnemyActor._crowd_separation_for_motion` | script_function_exact | exact_func_name_match | 7 | 0.012 | 1.197 | 6889 func _crowd_separation_for_motion(delta: float) -> Vector2: |
| `res://scripts/player_state.gd::7631::item_count_by_entity_id` | script_function_exact | exact_func_name_match | 3 | 0.012 | 0.297 | 7630 func item_count_by_entity_id(item_id: String) -> int: |
| `res://scripts/identity/entity_registry.gd::134::service_for_item` | script_function_exact | exact_func_name_match | 39 | 0.012 | 0.029 | 133 static func service_for_item(id: String) -> int: |
| `res://scripts/map_editor/polygon/poly_nav_graph.gd::109::locate` | poly_nav_path_dependency | exact_func_name_match | 9 | 0.012 | 0.02 | 108 func locate(point: Vector2) -> int: |
| `res://scripts/audio_runtime_service.gd::423::AudioRuntimeService.play_event` | script_function_exact | exact_func_name_match | 44 | 0.011 | 3.249 | 422 func play_event(event_id: String, context: Dictionary = {}) -> Dictionary: |
| `res://scripts/hud.gd::2445::GameHUD.update_hp` | script_function_exact | exact_func_name_match | 16 | 0.011 | 0.234 | 2444 func update_hp(current_hp: int, max_hp: int) -> void: |
| `res://scripts/enemy.gd::6113::EnemyActor._release_player_combat_epoch_is_current` | script_function_exact | exact_func_name_match | 13 | 0.011 | 0.027 | 6109 func _release_player_combat_epoch_is_current( |
| `res://scripts/player.gd::990::PlayerCharacter._commit_observed_hp_write` | script_function_exact | exact_func_name_match | 13 | 0.011 | 0.011 | 989 func _commit_observed_hp_write(amount: int, damage_type: String, delivery_identity: Variant, mp_before := -1, mp_after := -1) -> void: |
| `res://scripts/enemy.gd::1050::EnemyActor._audio_attack_started` | script_function_exact | exact_func_name_match | 13 | 0.011 | 3.569 | 1049 func _audio_attack_started(action_serial := -1) -> void: |
| `res://scripts/audio_runtime_service.gd::977::AudioRuntimeService._refresh_monster_budget_window` | budget_admission_or_scheduler | exact_func_name_match | 26 | 0.011 | 0.051 | 976 func _refresh_monster_budget_window() -> void: |
| `res://scripts/player_state.gd::1421::_consume_inventory_index` | script_function_exact | exact_func_name_match | 3 | 0.011 | 1.189 | 1420 func _consume_inventory_index(index: int, amount := 1, save_in_background := false) -> bool: |
| `res://scripts/game_root.gd::1459::_on_gameplay_movement` | script_function_exact | exact_func_name_match | 10 | 0.01 | 0.042 | 1458 func _on_gameplay_movement(value: Vector2) -> void: |
| `res://scripts/enemy.gd::8078::EnemyActor._slide_collision_intercepting_summon` | script_function_exact | exact_func_name_match | 13 | 0.01 | 0.019 | 8077 func _slide_collision_intercepting_summon() -> SummonActor: |
| `res://scripts/player_visual.gd::375::play_hit` | script_function_exact | exact_func_name_match | 13 | 0.01 | 1.191 | 374 func play_hit(duration := 0.24) -> void: |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::47::HCM30WalkPhase.attack_clip_seconds` | script_function_exact | exact_func_name_match | 13 | 0.01 | 0.01 | 43 static func attack_clip_seconds(authored_seconds: float, interval_seconds: float, hit_delay_seconds: float) -> float: |
| `res://scripts/monster_visual.gd::734::MonsterVisual.ground_contact_offset` | script_function_exact | exact_func_name_match | 7 | 0.01 | 0.079 | 733 func ground_contact_offset() -> Vector2: |
| `res://scripts/skills/skill_footprint_snapshot.gd::1141::SkillFootprintSnapshot._vector2_is_finite` | script_function_exact | exact_func_name_match | 65 | 0.01 | 0.01 | 1140 static func _vector2_is_finite(value: Vector2) -> bool: |
| `res://scripts/quick_item_icon_layout.gd::34::visible_center` | script_function_exact | exact_func_name_match | 3 | 0.01 | 0.01 | 33 static func visible_center(texture: Texture2D) -> Vector2: |
| `res://scripts/enemy.gd::2293::EnemyActor._fail_autonomous_step_blocked` | script_function_exact | exact_func_name_match | 13 | 0.009 | 0.14 | 2292 func _fail_autonomous_step_blocked() -> void: |
| `res://scripts/profession_rules.gd::458::ProfessionRules.player_struck_reaction_frame_milliseconds` | script_function_exact | exact_func_name_match | 13 | 0.009 | 0.034 | 457 static func player_struck_reaction_frame_milliseconds(character_level: int) -> int: |
| `res://scripts/enemy.gd::886::EnemyActor._audio_player_target` | script_function_exact | exact_func_name_match | 50 | 0.009 | 0.009 | 885 func _audio_player_target() -> Node: |
| `res://scripts/game_root.gd::14750::_on_consumable_used` | script_function_exact | exact_func_name_match | 3 | 0.009 | 0.463 | 14749 func _on_consumable_used(entity_id: String) -> void: |
| `res://scripts/game_data.gd::3808::item_entity_id` | script_function_exact | exact_func_name_match | 9 | 0.009 | 0.318 | 3807 func item_entity_id(item_ref: Variant) -> String: |
| `res://scripts/game_data.gd::3852::get_item_art_display_size` | script_function_exact | exact_func_name_match | 3 | 0.009 | 0.085 | 3851 func get_item_art_display_size(item_ref: Variant, field := "inventoryIcon") -> Vector2: |
| `res://scripts/game_data.gd::4116::_parse_stable_number` | script_function_exact | exact_func_name_match | 54 | 0.009 | 0.009 | 4115 func _parse_stable_number(value: Variant) -> int: |
| `res://scripts/monster_ai_package/path_scheduler.gd::24::HCMonsterPathScheduler.for_tree` | script_function_exact | exact_func_name_match | 1 | 0.009 | 0.037 | 23 static func for_tree(tree: SceneTree) -> HCMonsterPathScheduler: |
| `res://scripts/enemy.gd::9812::EnemyActor._hc_path_job_current` | script_function_exact | exact_func_name_match | 3 | 0.009 | 0.049 | 9810 func _hc_path_job_current(token: int) -> bool: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::150::_heuristic` | poly_nav_path_dependency | exact_func_name_match | 6 | 0.009 | 0.013 | 149 func _heuristic(face: int) -> float: |
| `res://scripts/monster_natural_regen_policy.gd::64::MonsterNaturalRegenPolicy.heal_amount` | script_function_exact | exact_func_name_match | 29 | 0.009 | 0.009 | 63 static func heal_amount(max_hp: int) -> int: |
| `res://scripts/enemy.gd::8409::EnemyActor.ground_footprint_indicator_radii` | script_function_exact | exact_func_name_match | 53 | 0.008 | 0.053 | 8408 func ground_footprint_indicator_radii() -> Vector2: |
| `res://scripts/enemy.gd::6938::EnemyActor._target_grid_cell` | script_function_exact | exact_func_name_match | 20 | 0.008 | 0.008 | 6937 static func _target_grid_cell(screen_position_px: Vector2) -> Vector2i: |
| `res://scripts/profession_rules.gd::453::ProfessionRules.player_struck_action_lock_seconds` | script_function_exact | exact_func_name_match | 13 | 0.008 | 0.022 | 452 static func player_struck_action_lock_seconds() -> float: |
| `res://scripts/game_root.gd::8009::_on_item_audio_committed` | script_function_exact | exact_func_name_match | 3 | 0.008 | 0.323 | 8008 func _on_item_audio_committed(identity_domain: String, identity_id: int, semantic_event: String) -> void: |
| `res://scripts/player_state.gd::7620::_inventory_index_by_entity_id` | script_function_exact | exact_func_name_match | 3 | 0.008 | 0.283 | 7619 func _inventory_index_by_entity_id(item_id: String) -> int: |
| `res://scripts/identity/item_binding_codec.gd::8::is_candidate` | script_function_exact | exact_func_name_match | 3 | 0.008 | 0.146 | 7 static func is_candidate(id: String) -> bool: |
| `res://scripts/enemy.gd::6998::EnemyActor.reset_performance_diagnostics` | script_function_exact | exact_func_name_match | 1 | 0.007 | 0.224 | 6997 static func reset_performance_diagnostics() -> void: |
| `res://scripts/hud_resource_orb.gd::0::CanvasItem.queue_redraw` | shared_builtin_or_native | builtin_or_native_line_zero | 48 | 0.007 | 0.007 | — |
| `res://scripts/monster_source_frames.gd::23::data` | script_function_exact | exact_func_name_match | 26 | 0.007 | 0.007 | 22 static func data() -> Dictionary: |
| `res://scripts/enemy.gd::4198::EnemyActor._current_attack_interval` | script_function_exact | exact_func_name_match | 13 | 0.007 | 0.007 | 4192 func _current_attack_interval() -> float: |
| `res://scripts/player_state.gd::2262::_item_audio_identity` | script_function_exact | exact_func_name_match | 3 | 0.007 | 0.123 | 2261 func _item_audio_identity(item_ref: Variant) -> Dictionary: |
| `res://scripts/items/item_extension_codec.gd::229::embedded_records` | script_function_exact | exact_func_name_match | 3 | 0.007 | 0.039 | 228 static func embedded_records(record: Dictionary) -> Array[Dictionary]: |
| `res://scripts/ui_item_texture_cache.gd::29::UIItemTextureCache.texture_at_path` | script_function_exact | exact_func_name_match | 3 | 0.007 | 0.01 | 28 static func texture_at_path(path: String) -> Texture2D: |
| `res://scripts/quick_item_icon_layout.gd::11::prepare_texture` | script_function_exact | exact_func_name_match | 3 | 0.007 | 0.01 | 10 static func prepare_texture(source: Texture2D, item_id: String) -> Texture2D: |
| `res://scripts/inventory_panel.gd::965::InventoryPanel._refresh_inventory_action_states` | script_function_exact | exact_func_name_match | 6 | 0.007 | 0.007 | 964 func _refresh_inventory_action_states() -> void: |
| `res://scripts/items/rune_item_rules.gd::15::ensure_loaded` | script_function_exact | exact_func_name_match | 45 | 0.007 | 0.007 | 14 static func ensure_loaded() -> bool: |
| `res://scripts/monster_ai_package/path_scheduler.gd::37::HCMonsterPathScheduler.submit` | script_function_exact | exact_func_name_match | 1 | 0.007 | 0.014 | 36 func submit(owner: Node, token: int, search: Search) -> void: |
| `res://scripts/game_root.gd::14733::_on_player_stats_changed` | script_function_exact | exact_func_name_match | 16 | 0.006 | 0.254 | 14732 func _on_player_stats_changed(current_hp: int, max_hp: int) -> void: |
| `res://scripts/profession_rules.gd::449::ProfessionRules.should_player_stagger` | script_function_exact | exact_func_name_match | 13 | 0.006 | 0.088 | 448 static func should_player_stagger(actual_damage: int, max_hp_value: int) -> bool: |
| `res://scripts/player_visual.gd::0::SceneTree.get_first_node_in_group` | shared_builtin_or_native | builtin_or_native_line_zero | 8 | 0.006 | 0.006 | — |
| `res://scripts/enemy.gd::4113::EnemyActor._uses_special_magic_melee_delivery` | script_function_exact | exact_func_name_match | 13 | 0.006 | 0.008 | 4112 func _uses_special_magic_melee_delivery() -> bool: |
| `res://scripts/audio_runtime_service.gd::732::AudioRuntimeService.play_item_event` | script_function_exact | exact_func_name_match | 3 | 0.006 | 0.31 | 731 func play_item_event(stable_item_key: String, semantic_event: String, context: Dictionary = {}) -> Dictionary: |
| `res://scripts/player.gd::1652::PlayerCharacter.restore_health` | script_function_exact | exact_func_name_match | 3 | 0.006 | 0.217 | 1648 func restore_health(amount: int) -> int: |
| `res://scripts/player_state.gd::1437::_consume_inventory_index_without_commit` | script_function_exact | exact_func_name_match | 3 | 0.006 | 0.108 | 1436 func _consume_inventory_index_without_commit(index: int, amount := 1) -> bool: |
| `res://scripts/items/item_extension_codec.gd::345::_is_wire_container` | script_function_exact | exact_func_name_match | 21 | 0.006 | 0.014 | 344 static func _is_wire_container(record: Dictionary) -> bool: |
| `res://scripts/inventory_panel.gd::453::InventoryPanel._on_inventory_data_changed` | script_function_exact | exact_func_name_match | 6 | 0.006 | 0.015 | 448 func _on_inventory_data_changed() -> void: |
| `res://scripts/enemy.gd::9781::EnemyActor._hc_submit_path` | script_function_exact | exact_func_name_match | 1 | 0.006 | 0.106 | 9780 func _hc_submit_path(anchor: Vector2) -> void: |
| `res://scripts/map_editor/polygon/poly_nav_graph.gd::117::attach` | poly_nav_path_dependency | exact_func_name_match | 9 | 0.006 | 0.107 | 116 func attach(point: Vector2, collision_index: Index, exact_radius: float) -> Dictionary: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::174::_assemble_one` | poly_nav_path_dependency | exact_func_name_match | 3 | 0.006 | 0.007 | 173 func _assemble_one() -> void: |
| `res://scripts/player.gd::402::PlayerCharacter.set_touch_vector` | script_function_exact | exact_func_name_match | 10 | 0.005 | 0.005 | 401 func set_touch_vector(value: Vector2) -> void: |
| `res://scripts/enemy.gd::2151::EnemyActor._clear_terrain_route_cache` | script_function_exact | exact_func_name_match | 28 | 0.005 | 0.005 | 2150 func _clear_terrain_route_cache() -> void: |
| `res://scripts/game_root.gd::1735::<anonymous lambda>(lambda)` | script_function_exact | source_present_no_exact_func_name | 19 | 0.005 | 0.921 | — |
| `res://scripts/enemy.gd::7091::EnemyActor.apply_life_steal` | script_function_exact | exact_func_name_match | 13 | 0.005 | 0.005 | 7090 func apply_life_steal(dealt_damage: int) -> void: |
| `res://scripts/enemy.gd::6102::EnemyActor._typed_player_combat_epoch` | script_function_exact | exact_func_name_match | 13 | 0.005 | 0.005 | 6101 func _typed_player_combat_epoch(hit_target: Node2D) -> int: |
| `res://scripts/items/item_extension_codec.gd::225::can_release_ownership` | script_function_exact | exact_func_name_match | 3 | 0.005 | 0.099 | 222 static func can_release_ownership(record: Dictionary) -> bool: |
| `res://scripts/player_state.gd::9080::_before_state_transaction` | script_function_exact | exact_func_name_match | 6 | 0.005 | 0.009 | 9076 func _before_state_transaction(include_world := false) -> void: |
| `res://scripts/items/item_extension_codec.gd::360::_success` | script_function_exact | exact_func_name_match | 9 | 0.005 | 0.005 | 359 static func _success(item: Dictionary) -> Dictionary: |
| `res://scripts/monster_ai_package/path_search.gd::392::HCMonsterPathSearch.configure_deferred` | script_function_exact | exact_func_name_match | 1 | 0.005 | 0.023 | 390 func configure_deferred(ctx: Dictionary, from: Vector2i, builder: Callable, r: float, edge: Callable, static_scope: Array = []) -> void: |
| `res://scripts/ui_selection_dismiss_guard.gd::97::UISelectionDismissGuard._register_node` | script_function_exact | exact_func_name_match | 1 | 0.005 | 0.009 | 91 func _register_node(node: Node) -> void: |
| `res://scripts/map_editor/polygon/poly_nav_graph.gd::0::Geometry2D.is_point_in_polygon` | shared_builtin_or_native | builtin_or_native_line_zero | 39 | 0.005 | 0.005 | — |
| `res://tests/crowd_engagement_scaling_20261008.gd::0::CharacterBody2D.get_instance_id` | shared_builtin_or_native | builtin_or_native_line_zero | 34 | 0.004 | 0.004 | — |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::16::HCM30WalkPhase.configure_cycle` | script_function_exact | exact_func_name_match | 7 | 0.004 | 0.004 | 15 func configure_cycle(distance_per_cycle_gu: float) -> void: |
| `res://scripts/enemy.gd::5889::EnemyActor._apply_on_hit_control` | script_function_exact | exact_func_name_match | 13 | 0.004 | 0.004 | 5888 func _apply_on_hit_control(hit_target: Node2D, forced_control_roll := -1) -> void: |
| `res://scripts/monster_source176/action_boundary.gd::19::can_reserve_body_action` | script_function_exact | exact_func_name_match | 13 | 0.004 | 0.004 | 15 static func can_reserve_body_action(physics_tick: int, last_body_commit_tick: int, has_incompatible_pending_release: bool, gameplay_locked: bool) -> bool: |
| `res://scripts/player_state.gd::2293::_emit_item_audio_committed` | script_function_exact | exact_func_name_match | 3 | 0.004 | 0.462 | 2292 func _emit_item_audio_committed(item_ref: Variant, semantic_event: String) -> void: |
| `res://scripts/items/item_extension_codec.gd::101::normalize_runtime` | script_function_exact | exact_func_name_match | 3 | 0.004 | 0.049 | 100 static func normalize_runtime(record: Dictionary) -> Dictionary: |
| `res://scripts/identity/entity_registry.gd::130::canonical` | script_function_exact | exact_func_name_match | 15 | 0.004 | 0.031 | 129 static func canonical(id: String) -> String: |
| `res://scripts/items/item_extension_codec.gd::124::extensions` | script_function_exact | exact_func_name_match | 3 | 0.004 | 0.03 | 123 static func extensions(record: Dictionary) -> Dictionary: |
| `res://scripts/ui_item_texture_cache.gd::18::UIItemTextureCache.texture_for` | script_function_exact | exact_func_name_match | 3 | 0.004 | 0.017 | 17 static func texture_for(record: Dictionary, field := "inventoryIcon") -> Texture2D: |
| `res://scripts/items/item_extension_codec.gd::357::_integer` | script_function_exact | exact_func_name_match | 12 | 0.004 | 0.004 | 356 static func _integer(value: Variant) -> bool: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::38::configure` | poly_nav_path_dependency | exact_func_name_match | 1 | 0.004 | 0.008 | 37 func configure(context_value: Dictionary, start_gu: Vector2, builder: Callable, radius_gu: float) -> void: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::0::@implicit_new` | shared_builtin_or_native | builtin_or_native_line_zero | 1 | 0.004 | 0.004 | — |
| `res://scripts/monster_ai_package/path_scheduler.gd::0::HCMonsterPathScheduler.@implicit_new` | shared_builtin_or_native | builtin_or_native_line_zero | 1 | 0.004 | 0.004 | — |
| `res://scripts/monster_ai_package/path_search.gd::435::HCMonsterPathSearch.advance` | script_function_exact | exact_func_name_match | 2 | 0.004 | 1.934 | 433 func advance(limit := 384, deadline_usec := 0) -> String: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::53::_prepare` | poly_nav_path_dependency | exact_func_name_match | 1 | 0.004 | 1.308 | 52 func _prepare() -> void: |
| `res://scripts/monster_terrain_navigation_policy.gd::435::MonsterTerrainNavigationPolicy._claim_path_query_budget` | budget_admission_or_scheduler | exact_func_name_match | 2 | 0.004 | 0.004 | 434 static func _claim_path_query_budget() -> bool: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::156::_reconstruct_one` | poly_nav_path_dependency | exact_func_name_match | 3 | 0.004 | 0.299 | 155 func _reconstruct_one() -> void: |
| `res://scripts/skills/skill_footprint_snapshot.gd::104::SkillFootprintSnapshot.normalize_runtime_map_id` | script_function_exact | exact_func_name_match | 26 | 0.003 | 0.003 | 103 static func normalize_runtime_map_id(value: Variant) -> int: |
| `res://scripts/enemy.gd::0::CanvasItem.is_visible_in_tree` | shared_builtin_or_native | builtin_or_native_line_zero | 25 | 0.003 | 0.003 | — |
| `res://scripts/player.gd::1666::PlayerCharacter.restore_mana` | script_function_exact | exact_func_name_match | 3 | 0.003 | 0.087 | 1665 func restore_mana(amount: int) -> void: |
| `res://scripts/shop_panel.gd::1133::ShopPanel._on_inventory_changed` | script_function_exact | exact_func_name_match | 3 | 0.003 | 0.003 | 1132 func _on_inventory_changed() -> void: |
| `res://scripts/player_state.gd::2308::_use_item_success` | script_function_exact | exact_func_name_match | 3 | 0.003 | 0.003 | 2307 func _use_item_success(message: String) -> Dictionary: |
| `res://scripts/warehouse_panel.gd::374::WarehousePanel._on_inventory_changed` | script_function_exact | exact_func_name_match | 3 | 0.003 | 0.003 | 373 func _on_inventory_changed() -> void: |
| `res://scripts/ui_selection_dismiss_guard.gd::55::UISelectionDismissGuard._flush_observer_order_refresh` | script_function_exact | exact_func_name_match | 1 | 0.003 | 0.023 | 54 func _flush_observer_order_refresh() -> void: |
| `res://scripts/monster_ai_package/path_search.gd::0::HCMonsterPathSearch.@implicit_new` | shared_builtin_or_native | builtin_or_native_line_zero | 1 | 0.003 | 0.003 | — |
| `res://scripts/enemy.gd::9762::EnemyActor._hc_goal_cache_key` | script_function_exact | exact_func_name_match | 1 | 0.003 | 0.012 | 9761 func _hc_goal_cache_key(anchor: Vector2) -> Array: |
| `res://scripts/enemy.gd::9831::EnemyActor._hc_path_completed` | script_function_exact | exact_func_name_match | 1 | 0.003 | 0.024 | 9830 func _hc_path_completed(token: int, status: String, route: PackedVector2Array) -> void: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::219::_push` | poly_nav_path_dependency | exact_func_name_match | 6 | 0.003 | 0.006 | 218 func _push(item: Array) -> void: |
| `res://tests/crowd_engagement_scaling_20261008.gd::0::CharacterBody2D.set_physics_process` | shared_builtin_or_native | builtin_or_native_line_zero | 35 | 0.002 | 0.002 | — |
| `res://scripts/monster_ai_package/m30/walk_phase.gd::41::HCM30WalkPhase.interrupt_pose` | script_function_exact | exact_func_name_match | 13 | 0.002 | 0.002 | 39 func interrupt_pose() -> void: |
| `res://scripts/monster_visual.gd::1196::MonsterVisual._merge_pending_struck_feedback` | script_function_exact | exact_func_name_match | 13 | 0.002 | 0.002 | 1195 func _merge_pending_struck_feedback() -> int: |
| `res://scripts/player_state.gd::9042::_commit_item_use` | script_function_exact | exact_func_name_match | 3 | 0.002 | 0.229 | 9041 func _commit_item_use(save_in_background: bool) -> bool: |
| `res://scripts/quick_item_icon_layout.gd::0::Texture2D.get_size` | shared_builtin_or_native | builtin_or_native_line_zero | 9 | 0.002 | 0.002 | — |
| `res://scripts/player_state.gd::2283::_item_audio_nonnegative_integer` | script_function_exact | exact_func_name_match | 3 | 0.002 | 0.002 | 2282 func _item_audio_nonnegative_integer(value: Variant) -> int: |
| `res://scripts/enemy.gd::0::CanvasItem.get_global_transform_with_canvas` | shared_builtin_or_native | builtin_or_native_line_zero | 6 | 0.002 | 0.002 | — |
| `res://scripts/ui_selection_dismiss_guard.gd::48::UISelectionDismissGuard._queue_observer_order_refresh` | script_function_exact | exact_func_name_match | 1 | 0.002 | 0.003 | 47 func _queue_observer_order_refresh() -> void: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::188::_smooth_one` | poly_nav_path_dependency | exact_func_name_match | 6 | 0.002 | 0.095 | 187 func _smooth_one() -> void: |
| `res://scripts/items/item_extension_codec.gd::84::encode_runtime` | script_function_exact | exact_func_name_match | 6 | 0.001 | 0.055 | 83 static func encode_runtime(record: Dictionary) -> Dictionary: |
| `res://scripts/skill_panel.gd::476::SkillPanel._on_panel_data_changed` | script_function_exact | exact_func_name_match | 3 | 0.001 | 0.001 | 475 func _on_panel_data_changed() -> void: |
| `res://scripts/map_editor/polygon/poly_nav_graph.gd::21::key_for_radius` | poly_nav_path_dependency | exact_func_name_match | 1 | 0.001 | 0.001 | 19 static func key_for_radius(value: float) -> String: |
| `res://scripts/monster_ai_package/path_search.gd::546::HCMonsterPathSearch.detach_shared_goal_field` | script_function_exact | exact_func_name_match | 2 | 0.001 | 0.001 | 545 func detach_shared_goal_field() -> void: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::212::_less` | poly_nav_path_dependency | exact_func_name_match | 3 | 0.001 | 0.001 | 211 static func _less(a: Array, b: Array) -> bool: |
| `res://scripts/map_editor/polygon/poly_nav_graph.gd::106::_bucket` | poly_nav_path_dependency | exact_func_name_match | 9 | 0.001 | 0.001 | 105 func _bucket(point: Vector2) -> Vector2i: |
| `res://scripts/player_state.gd::2304::_last_item_commit_succeeded` | script_function_exact | exact_func_name_match | 3 | 0 | 0.002 | 2303 func _last_item_commit_succeeded() -> bool: |
| `res://scripts/json_persistence_service.gd::74::pending_count` | script_function_exact | exact_func_name_match | 6 | 0 | 0 | 73 func pending_count() -> int: |
| `res://scripts/player_state.gd::10062::_finish_pending_durability_save` | script_function_exact | exact_func_name_match | 3 | 0 | 0 | 10061 func _finish_pending_durability_save(started_usec: int) -> void: |
| `res://scripts/monster_ai_package/path_search.gd::642::HCMonsterPathSearch.set_polygon_origin` | script_function_exact | exact_func_name_match | 1 | 0 | 0 | 641 func set_polygon_origin(origin_ground_gu: Vector2) -> void: |
| `res://scripts/map_editor/polygon/poly_path_search.gd::230::_pop` | poly_nav_path_dependency | exact_func_name_match | 4 | 0 | 0 | 229 func _pop() -> Array: |

