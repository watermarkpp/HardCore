# Native profiler offline analysis

Source: `native_01/packets.jsonl`; raw packets unchanged; Godot not rerun.

- Packets 3927; decode errors 0; trailing bytes 0.
- Validated process frame window **321..962 inclusive** (642); selected frames 642.
- Validation failures **0**; any nonzero invalidates ranking. No `res://tests/*` signatures were removed to hide failures.
- Official tuple contract used: `sig_id, call_count, self_time, total_time, internal_time`; flat count divisible by 5 and exact packet consumption.

## Enemy production ranking

| signature | calls | total ms | self ms | internal ms | frames |
|---|---:|---:|---:|---:|---:|
| `res://scripts/enemy.gd::2769::EnemyActor._physics_process` | 10200 | 3253.229 | 9.399 | 0.000 | 294 |
| `res://scripts/enemy.gd::2786::EnemyActor._physics_process_internal` | 10200 | 3178.545 | 48.484 | 0.000 | 294 |
| `res://scripts/enemy.gd::9175::EnemyActor._hc_tick_melee` | 8677 | 2174.455 | 53.175 | 0.000 | 294 |
| `res://scripts/enemy.gd::2325::EnemyActor._advance_autonomous_step` | 7350 | 1175.507 | 4.677 | 0.000 | 294 |
| `res://scripts/enemy.gd::2338::EnemyActor._advance_autonomous_step_internal` | 7350 | 1129.117 | 40.393 | 0.000 | 294 |
| `res://scripts/enemy.gd::3669::EnemyActor._move_with_spatial_rules` | 7327 | 544.675 | 33.500 | 0.524 | 294 |
| `res://scripts/enemy.gd::1856::EnemyActor._begin_autonomous_step_without_cadence` | 970 | 524.023 | 5.211 | 0.000 | 272 |
| `res://scripts/enemy.gd::7759::EnemyActor._retarget` | 8717 | 497.439 | 4.724 | 0.000 | 294 |
| `res://scripts/enemy.gd::2004::EnemyActor._terrain_neighbor_for_pursuit` | 970 | 495.717 | 0.472 | 0.000 | 272 |
| `res://scripts/enemy.gd::9930::EnemyActor._hc_neighbor` | 970 | 493.636 | 0.660 | 0.000 | 272 |
| `res://scripts/enemy.gd::9936::EnemyActor._hc_neighbor_internal` | 970 | 487.255 | 6.284 | 0.012 | 272 |
| `res://scripts/enemy.gd::7774::EnemyActor._retarget_internal` | 8717 | 447.975 | 21.711 | 0.000 | 294 |
| `res://scripts/enemy.gd::3378::EnemyActor._screen_position_px_to_ground_position_gu` | 74041 | 413.959 | 35.773 | 0.000 | 294 |
| `res://scripts/enemy.gd::8841::EnemyActor._hc_motion_clear` | 9106 | 397.489 | 4.898 | 0.000 | 294 |
| `res://scripts/enemy.gd::8847::EnemyActor._hc_motion_clear_internal` | 9106 | 343.523 | 23.826 | 0.000 | 294 |
| `res://scripts/enemy.gd::210::EnemyActor._record_performance_counter` | 93803 | 281.239 | 94.102 | 0.000 | 294 |
| `res://scripts/enemy.gd::9533::EnemyActor._hc_refresh_observation` | 17518 | 231.081 | 21.604 | 0.014 | 294 |
| `res://scripts/enemy.gd::10303::EnemyActor._hc_motion_candidates` | 9810 | 225.245 | 39.757 | 0.000 | 294 |
| `res://scripts/enemy.gd::10203::EnemyActor._hc_choose_blocked_neighbor` | 182 | 205.767 | 1.372 | 0.505 | 138 |
| `res://scripts/enemy.gd::3262::EnemyActor._spatial_index_update` | 16566 | 201.063 | 14.813 | 0.000 | 294 |
| `res://scripts/enemy.gd::1660::EnemyActor._target_should_disengage` | 8677 | 189.529 | 16.564 | 0.000 | 294 |
| `res://scripts/enemy.gd::9663::EnemyActor._hc_point_walkable` | 2268 | 188.315 | 7.254 | 0.000 | 271 |
| `res://scripts/enemy.gd::9701::EnemyActor._hc_point_walkable_uncached` | 1976 | 166.822 | 1.655 | 0.000 | 271 |
| `res://scripts/enemy.gd::3413::EnemyActor._screen_position_px_to_ground_position_gu_vector2` | 16097 | 162.087 | 3.532 | 0.000 | 294 |
| `res://scripts/enemy.gd::3286::EnemyActor._spatial_index_projection_cache_matches` | 117657 | 161.026 | 66.280 | 0.000 | 294 |
| `res://scripts/enemy.gd::9428::EnemyActor._hc_world_between` | 2734 | 159.776 | 6.223 | 0.000 | 294 |
| `res://scripts/enemy.gd::8685::EnemyActor._hc_standard_melee` | 124437 | 137.829 | 73.264 | 0.000 | 294 |
| `res://scripts/enemy.gd::2266::EnemyActor._movement_step_engagement_ready` | 14677 | 129.238 | 6.273 | 0.000 | 294 |
| `res://scripts/enemy.gd::3869::EnemyActor._world_attack_path_is_clear` | 2334 | 99.608 | 2.463 | 0.000 | 294 |
| `res://scripts/enemy.gd::8763::EnemyActor._hc_access` | 1044 | 99.565 | 3.642 | 0.000 | 294 |

## Other production script ranking

| signature | calls | total ms | self ms | internal ms | frames |
|---|---:|---:|---:|---:|---:|
| `res://scripts/monster_visual.gd::390::MonsterVisual._process` | 21828 | 258.069 | 17.020 | 0.000 | 642 |
| `res://scripts/game_root.gd::1850::_process` | 642 | 250.504 | 10.496 | 2.357 | 642 |
| `res://scripts/runtime_diagnostics.gd::373::RuntimeDiagnostics.increment_performance_counter` | 134617 | 236.966 | 82.771 | 0.000 | 642 |

## Errors and acceptance

- Error packets 343; warnings 342; non-warning 1.
- **FAIL retained:** `engine_debugger.cpp:72 profiler_enable`, no profiler `scripts`; runner receipt remains FAIL despite native exit 0.
- Native profiler instrumentation/transport excluded from optimization claims.
Official serialization basis: `servers_debugger.cpp` `ServersProfilerFrame::serialize/deserialize` writes header fields `[frame_number, frame_time, process_time, physics_time, physics_frame_time, script_time, server_count]`; each server has `name, flat_count` with name/time pairs; script data is a flat count followed by five fields per function in 4.7 (`sig_id, call_count, self_time, total_time, internal_time`). The editor consumer assigns `self=p_data[i+2]`, `total=p_data[i+3]`, `internal=p_data[i+4]`. Source URLs: https://raw.githubusercontent.com/godotengine/godot/4.7-stable/servers/debugger/servers_debugger.cpp and https://raw.githubusercontent.com/godotengine/godot/4.7-stable/editor/debugger/script_editor_debugger.cpp. The old result is preserved as `PROFILE_ANALYSIS_invalid_01.json/.md`.
