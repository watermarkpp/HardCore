# Native profiler coverage reclassification

## Clip audit

- Window: frames 321..962, 642 frames; function count min/max 210/601.
- Requested `max_frame_functions`: 1024; observed maximum: 601; official default `debug/settings/profiler/max_functions`: 16384; project override: none found. **Status: PASS**.
- This PASS means no selected frame reached either configured limit; it does not prove uninstrumented functions do not exist outside the selected set.
- Raw packet SHA256: `90892f4a11f79e10f363ed337d22c4d879482d93a2510bfee79837e6f043a74e`. decode errors 0; trailing bytes 0; validation failures 0.

## Non-overlapping Self coverage

| category | functions | calls | Self ms | total ms | internal ms |
|---|---:|---:|---:|---:|---:|
| control_state | 12 | 225376 | 274.751 | 6952.747 | 0.014 |
| geometry_candidates_space | 21 | 377907 | 266.070 | 4302.809 | 9.236 |
| diagnostic_budget | 31 | 1409589 | 479.659 | 1371.794 | 0.006 |
| external_native_shared | 31 | 216593 | 550.923 | 550.926 | 439.462 |
| unknown | 675 | 3871172 | 1502.668 | 12616.379 | 644.932 |

Self subtotals are disjoint; `internal_ms` is retained as a field and is not added to Self.

## control_state

- `res://scripts/enemy.gd::8685::EnemyActor._hc_standard_melee`: calls 124437, Self 73.264 ms, total 137.829 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::9175::EnemyActor._hc_tick_melee`: calls 8677, Self 53.175 ms, total 2174.455 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::2338::EnemyActor._advance_autonomous_step_internal`: calls 7350, Self 40.393 ms, total 1129.117 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::8847::EnemyActor._hc_motion_clear_internal`: calls 9106, Self 23.826 ms, total 343.523 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::7774::EnemyActor._retarget_internal`: calls 8717, Self 21.711 ms, total 447.975 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::9533::EnemyActor._hc_refresh_observation`: calls 17518, Self 21.604 ms, total 231.081 ms, internal 0.014 ms.
- `res://scripts/enemy.gd::1660::EnemyActor._target_should_disengage`: calls 8677, Self 16.564 ms, total 189.529 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::2266::EnemyActor._movement_step_engagement_ready`: calls 14677, Self 6.273 ms, total 129.238 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::8841::EnemyActor._hc_motion_clear`: calls 9106, Self 4.898 ms, total 397.489 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::7759::EnemyActor._retarget`: calls 8717, Self 4.724 ms, total 497.439 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::2325::EnemyActor._advance_autonomous_step`: calls 7350, Self 4.677 ms, total 1175.507 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::8763::EnemyActor._hc_access`: calls 1044, Self 3.642 ms, total 99.565 ms, internal 0.000 ms.

## geometry_candidates_space

- `res://scripts/enemy.gd::3286::EnemyActor._spatial_index_projection_cache_matches`: calls 117657, Self 66.280 ms, total 161.026 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::10303::EnemyActor._hc_motion_candidates`: calls 9810, Self 39.757 ms, total 225.245 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3378::EnemyActor._screen_position_px_to_ground_position_gu`: calls 74041, Self 35.773 ms, total 413.959 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3669::EnemyActor._move_with_spatial_rules`: calls 7327, Self 33.500 ms, total 544.675 ms, internal 0.524 ms.
- `res://scripts/enemy.gd::3262::EnemyActor._spatial_index_update`: calls 16566, Self 14.813 ms, total 201.063 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3454::EnemyActor._write_target_ground_projection_cache_if_current_target`: calls 16097, Self 11.580 ms, total 13.141 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3433::EnemyActor._target_ground_projection_cache_matches`: calls 18636, Self 8.962 ms, total 10.818 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3914::EnemyActor._world_attack_path_is_clear_uncached`: calls 2334, Self 8.905 ms, total 86.275 ms, internal 8.195 ms.
- `res://scripts/enemy.gd::9663::EnemyActor._hc_point_walkable`: calls 2268, Self 7.254 ms, total 188.315 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3500::EnemyActor._ground_delta_gu_between_screen_positions`: calls 39631, Self 7.037 ms, total 22.151 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3304::EnemyActor.spatial_index_position`: calls 38266, Self 6.911 ms, total 76.193 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::9936::EnemyActor._hc_neighbor_internal`: calls 970, Self 6.284 ms, total 487.255 ms, internal 0.012 ms.
- `res://scripts/enemy.gd::9428::EnemyActor._hc_world_between`: calls 2734, Self 6.223 ms, total 159.776 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3413::EnemyActor._screen_position_px_to_ground_position_gu_vector2`: calls 16097, Self 3.532 ms, total 162.087 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3869::EnemyActor._world_attack_path_is_clear`: calls 2334, Self 2.463 ms, total 99.608 ms, internal 0.000 ms.

## diagnostic_budget

- `res://scripts/enemy.gd::210::EnemyActor._record_performance_counter`: calls 93803, Self 94.102 ms, total 281.239 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::354::RuntimeDiagnostics.performance_detail_enabled`: calls 308888, Self 86.314 ms, total 168.729 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::373::RuntimeDiagnostics.increment_performance_counter`: calls 134617, Self 82.771 ms, total 236.966 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::675::RuntimeDiagnostics.end_timed_segment`: calls 62530, Self 46.976 ms, total 124.563 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::666::RuntimeDiagnostics.begin_timed_segment`: calls 62530, Self 44.775 ms, total 143.340 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::278::RuntimeDiagnostics.performance_enabled`: calls 310473, Self 31.155 ms, total 31.155 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::306::RuntimeDiagnostics.performance_timing_enabled`: calls 171171, Self 25.137 ms, total 150.403 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::362::RuntimeDiagnostics._ensure_performance_window`: calls 200212, Self 23.521 ms, total 23.521 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::725::RuntimeDiagnostics.performance_counters`: calls 303, Self 14.386 ms, total 21.089 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::648::RuntimeDiagnostics.timing_elapsed_usec`: calls 15370, Self 6.574 ms, total 47.966 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::654::RuntimeDiagnostics.record_timing_usec`: calls 12966, Self 5.869 ms, total 74.426 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::636::RuntimeDiagnostics.timing_start`: calls 15370, Self 5.023 ms, total 24.022 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::642::RuntimeDiagnostics.timing_now`: calls 15370, Self 4.773 ms, total 20.379 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::399::RuntimeDiagnostics.record_performance_max`: calls 1462, Self 2.406 ms, total 4.320 ms, internal 0.000 ms.
- `res://scripts/runtime_diagnostics.gd::514::RuntimeDiagnostics.record_device_lab_frame_interval`: calls 642, Self 1.551 ms, total 4.853 ms, internal 0.000 ms.

## external_native_shared

- `res://scripts/player.gd::0::PhysicsBody2D.move_and_collide`: calls 15254, Self 174.662 ms, total 174.662 ms, internal 174.662 ms.
- `res://scripts/monster_visual_streaming_coordinator.gd::0::Object.call`: calls 95813, Self 138.494 ms, total 138.494 ms, internal 138.494 ms.
- `res://tests/crowd_native_profile_20261009.gd::8::_physics_process`: calls 300, Self 111.442 ms, total 111.443 ms, internal 0.001 ms.
- `res://scripts/monster_ai_package/decision_budget.gd::0::Object.call`: calls 51036, Self 108.224 ms, total 108.224 ms, internal 108.224 ms.
- `res://scripts/hud.gd::0::Object.call`: calls 7108, Self 14.690 ms, total 14.690 ms, internal 14.690 ms.
- `res://scripts/monster_ai_package/path_scheduler.gd::0::Object.call`: calls 424, Self 0.744 ms, total 0.744 ms, internal 0.744 ms.
- `res://scripts/monster_ai_package/decision_budget.gd::0::Node.is_inside_tree`: calls 16007, Self 0.656 ms, total 0.656 ms, internal 0.656 ms.
- `res://scripts/enemy.gd::0::Node.get_physics_process_delta_time`: calls 7327, Self 0.524 ms, total 0.524 ms, internal 0.524 ms.
- `res://scripts/game_root.gd::0::Node.get_viewport`: calls 6883, Self 0.398 ms, total 0.398 ms, internal 0.398 ms.
- `res://scripts/monster_visual.gd::0::Node.is_processing`: calls 6217, Self 0.280 ms, total 0.280 ms, internal 0.280 ms.
- `res://scripts/game_root.gd::0::Node.get_tree`: calls 1659, Self 0.211 ms, total 0.211 ms, internal 0.211 ms.
- `res://scripts/monster_ai_package/decision_budget.gd::0::Node.can_process`: calls 3142, Self 0.190 ms, total 0.190 ms, internal 0.190 ms.
- `res://scripts/monster_visual.gd::0::Node.is_inside_tree`: calls 4669, Self 0.189 ms, total 0.189 ms, internal 0.189 ms.
- `res://scripts/player_visual.gd::0::Node.move_child`: calls 72, Self 0.137 ms, total 0.137 ms, internal 0.137 ms.
- `res://scripts/hud.gd::1347::GameHUD._layout_native_item_icon`: calls 3, Self 0.020 ms, total 0.022 ms, internal 0.000 ms.

## unknown

- `res://scripts/monster_visual.gd::504::MonsterVisual._update_animation_frame`: calls 21828, Self 50.500 ms, total 160.356 ms, internal 0.000 ms.
- `res://scripts/runtime_combat_spatial_index.gd::382::RuntimeCombatSpatialIndex._query_enemy_nodes_in_aabb`: calls 4500, Self 48.551 ms, total 74.056 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::2786::EnemyActor._physics_process_internal`: calls 10200, Self 48.484 ms, total 3178.545 ms, internal 0.000 ms.
- `res://scripts/game_root.gd::12140::_resolve_projection_profile_for_map`: calls 23768, Self 42.844 ms, total 66.677 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::9639::EnemyActor._hc_environment_revision`: calls 137030, Self 41.936 ms, total 83.726 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::3563::EnemyActor._point_inside_safe_zone`: calls 57755, Self 34.763 ms, total 63.551 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::0::Object.get_meta`: calls 286646, Self 32.061 ms, total 32.061 ms, internal 32.061 ms.
- `res://scripts/ground_unit_space.gd::66::GroundUnitSpace.screen_delta_px_to_ground_delta_gu`: calls 154098, Self 24.728 ms, total 24.728 ms, internal 0.000 ms.
- `res://tests/crowd_engagement_scaling_20261008.gd::37::_physics_process`: calls 300, Self 24.043 ms, total 110.389 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::8910::EnemyActor._hc_life`: calls 69249, Self 23.511 ms, total 28.132 ms, internal 0.000 ms.
- `res://scripts/map_editor/polygon/poly_index.gd::86::capsule_blocked`: calls 7133, Self 23.387 ms, total 52.986 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::9528::EnemyActor._hc_decision_scope`: calls 20815, Self 23.162 ms, total 84.227 ms, internal 2.096 ms.
- `res://scripts/map_editor/polygon/poly_index.gd::72::inside`: calls 67034, Self 21.550 ms, total 21.550 ms, internal 0.000 ms.
- `res://scripts/layers/runtime/map_editor_runtime_bridge.gd::452::MapEditorRuntimeBridge.screen_position_px_to_ground_position_gu`: calls 27424, Self 20.757 ms, total 55.435 ms, internal 0.000 ms.
- `res://scripts/enemy.gd::8044::EnemyActor._target_candidate_is_live`: calls 19916, Self 20.560 ms, total 48.643 ms, internal 0.000 ms.

## Unknown and native interpretation

Unknown signatures are listed under `unknown` in JSON and were not guessed into a migratable group. A global builtin signature whose first script name happens to be `enemy.gd` is not assigned to Enemy; only known shared/native signatures are in `external_native_shared`. The external Self fraction is diagnostic only and cannot substitute for a no-profiler measurement or claim a native port will achieve it.

Official source: https://raw.githubusercontent.com/godotengine/godot/4.7-stable/servers/debugger/servers_debugger.cpp, especially lines 175-253 (`max_frame_functions`, sort, `MIN(ofs,max_frame_functions)`, and `GLOBAL_GET("debug/settings/profiler/max_functions")`).
