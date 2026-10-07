# PERFORMANCE_CURRENT_RESULT

Source HEAD: `aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`

All five benchmark sets contain 12 rows (10/20/30 actors × 4 scenarios). Values below are sealed evidence fields; `physics/tick` is `enemy_physics_usec / sample_physics_ticks`, not phone FPS.

| set | scenario | n | physics us/tick | ticks | motion frames | attacks | damage apps | target dmg | frame p95 ms |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| crowd_before | open_pursuit | 10 | 2497.7 | 153 | 1480 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_before | open_pursuit | 20 | 4585.7 | 150 | 2854 | 0 | 0 | 0 | 7.57575757575758 |
| crowd_before | open_pursuit | 30 | 6334.9 | 150 | 4272 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_before | sustained_close_attacks | 10 | 2648.2 | 150 | 1130 | 4 | 4 | 82 | 6.9 |
| crowd_before | sustained_close_attacks | 20 | 4871.1 | 150 | 1949 | 8 | 8 | 166 | 6.896 |
| crowd_before | sustained_close_attacks | 30 | 7431.0 | 150 | 3376 | 8 | 8 | 164 | 7.40740740740741 |
| crowd_before | world_obstacles | 10 | 1906.8 | 150 | 702 | 0 | 0 | 0 | 6.896 |
| crowd_before | world_obstacles | 20 | 3762.3 | 150 | 1119 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_before | world_obstacles | 30 | 5309.4 | 150 | 1430 | 0 | 0 | 0 | 7.14285714285714 |
| crowd_before | dense_crowd | 10 | 2275.1 | 150 | 1178 | 4 | 4 | 86 | 6.896 |
| crowd_before | dense_crowd | 20 | 4469.2 | 150 | 2355 | 7 | 7 | 146 | 6.896 |
| crowd_before | dense_crowd | 30 | 7191.1 | 150 | 3967 | 5 | 5 | 101 | 6.94444444444444 |
| crowd_after | open_pursuit | 10 | 2056.1 | 150 | 1480 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after | open_pursuit | 20 | 5563.0 | 150 | 2834 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after | open_pursuit | 30 | 6743.4 | 151 | 4331 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after | sustained_close_attacks | 10 | 2740.8 | 150 | 969 | 7 | 7 | 136 | 6.9 |
| crowd_after | sustained_close_attacks | 20 | 5277.8 | 150 | 2338 | 8 | 8 | 166 | 6.896 |
| crowd_after | sustained_close_attacks | 30 | 7322.7 | 150 | 3756 | 8 | 8 | 161 | 6.94444444444444 |
| crowd_after | world_obstacles | 10 | 1814.8 | 150 | 752 | 0 | 0 | 0 | 6.896 |
| crowd_after | world_obstacles | 20 | 3692.5 | 150 | 1130 | 0 | 0 | 0 | 6.896 |
| crowd_after | world_obstacles | 30 | 5298.7 | 150 | 1436 | 0 | 0 | 0 | 7.14285714285714 |
| crowd_after | dense_crowd | 10 | 2514.6 | 150 | 1138 | 4 | 4 | 78 | 6.896 |
| crowd_after | dense_crowd | 20 | 4803.6 | 150 | 2329 | 7 | 7 | 154 | 6.94444444444444 |
| crowd_after | dense_crowd | 30 | 7361.0 | 150 | 3830 | 7 | 7 | 152 | 6.94444444444444 |
| crowd_after_opt | open_pursuit | 10 | 2036.9 | 150 | 1480 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after_opt | open_pursuit | 20 | 4051.7 | 150 | 2834 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after_opt | open_pursuit | 30 | 6438.5 | 150 | 4272 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after_opt | sustained_close_attacks | 10 | 2733.4 | 150 | 969 | 7 | 7 | 155 | 6.94444444444444 |
| crowd_after_opt | sustained_close_attacks | 20 | 4913.0 | 150 | 2338 | 8 | 8 | 164 | 6.896 |
| crowd_after_opt | sustained_close_attacks | 30 | 7344.5 | 150 | 3757 | 8 | 8 | 175 | 6.94444444444444 |
| crowd_after_opt | world_obstacles | 10 | 1805.4 | 150 | 702 | 0 | 0 | 0 | 6.896 |
| crowd_after_opt | world_obstacles | 20 | 3601.7 | 150 | 1119 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_after_opt | world_obstacles | 30 | 5342.4 | 150 | 1742 | 0 | 0 | 0 | 6.896 |
| crowd_after_opt | dense_crowd | 10 | 2461.1 | 150 | 1138 | 4 | 4 | 85 | 6.896 |
| crowd_after_opt | dense_crowd | 20 | 4823.8 | 150 | 2328 | 7 | 7 | 131 | 6.94444444444444 |
| crowd_after_opt | dense_crowd | 30 | 7409.5 | 150 | 3819 | 7 | 7 | 146 | 6.94444444444444 |
| crowd_diagnostic_full | open_pursuit | 10 | 2273.7 | 150 | 1480 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_diagnostic_full | open_pursuit | 20 | 4547.6 | 150 | 2834 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_diagnostic_full | open_pursuit | 30 | 7185.0 | 150 | 4242 | 0 | 0 | 0 | 7.57575757575758 |
| crowd_diagnostic_full | sustained_close_attacks | 10 | 2946.7 | 150 | 969 | 7 | 7 | 167 | 6.94444444444444 |
| crowd_diagnostic_full | sustained_close_attacks | 20 | 5403.2 | 150 | 2338 | 8 | 8 | 156 | 6.94444444444444 |
| crowd_diagnostic_full | sustained_close_attacks | 30 | 8277.2 | 150 | 3779 | 8 | 8 | 163 | 6.94444444444444 |
| crowd_diagnostic_full | world_obstacles | 10 | 1999.0 | 150 | 702 | 0 | 0 | 0 | 6.896 |
| crowd_diagnostic_full | world_obstacles | 20 | 4065.8 | 150 | 1119 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_diagnostic_full | world_obstacles | 30 | 5932.6 | 150 | 1430 | 0 | 0 | 0 | 6.896 |
| crowd_diagnostic_full | dense_crowd | 10 | 2732.4 | 150 | 1144 | 4 | 4 | 74 | 6.94444444444444 |
| crowd_diagnostic_full | dense_crowd | 20 | 5244.9 | 150 | 2328 | 7 | 7 | 153 | 6.94444444444444 |
| crowd_diagnostic_full | dense_crowd | 30 | 8362.8 | 150 | 3850 | 7 | 7 | 160 | 6.94444444444444 |
| crowd_cost_pruned_parsed | open_pursuit | 10 | 2212.2 | 150 | 1480 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_cost_pruned_parsed | open_pursuit | 20 | 4541.6 | 150 | 2834 | 0 | 0 | 0 | 6.94444444444444 |
| crowd_cost_pruned_parsed | open_pursuit | 30 | 7191.8 | 150 | 4242 | 0 | 0 | 0 | 7.57575757575758 |
| crowd_cost_pruned_parsed | sustained_close_attacks | 10 | 2773.7 | 150 | 969 | 7 | 7 | 161 | 6.94444444444444 |
| crowd_cost_pruned_parsed | sustained_close_attacks | 20 | 5472.0 | 150 | 2350 | 8 | 8 | 163 | 6.94444444444444 |
| crowd_cost_pruned_parsed | sustained_close_attacks | 30 | 8101.2 | 150 | 3752 | 8 | 8 | 160 | 8.33333333333333 |
| crowd_cost_pruned_parsed | world_obstacles | 10 | 2006.4 | 150 | 702 | 0 | 0 | 0 | 6.896 |
| crowd_cost_pruned_parsed | world_obstacles | 20 | 4276.6 | 150 | 1119 | 0 | 0 | 0 | 6.896 |
| crowd_cost_pruned_parsed | world_obstacles | 30 | 6139.3 | 150 | 1742 | 0 | 0 | 0 | 7.14285714285714 |
| crowd_cost_pruned_parsed | dense_crowd | 10 | 2331.2 | 150 | 1144 | 4 | 4 | 81 | 6.94444444444444 |
| crowd_cost_pruned_parsed | dense_crowd | 20 | 5107.2 | 150 | 2341 | 7 | 7 | 140 | 6.94444444444444 |
| crowd_cost_pruned_parsed | dense_crowd | 30 | 8154.6 | 150 | 3820 | 7 | 7 | 146 | 6.94444444444444 |

## Evidence interpretation

- `crowd_before`, `crowd_after`, and `crowd_after_opt` are separate source stages/runs with the same recorded HEAD but different runtime instrumentation/changes; do not merge rows or select the best run.
- `crowd_diagnostic_full` adds detailed goal/neighbor/motion counters and timing wrappers. Its physics totals are diagnostic-instrumented and are not directly comparable to the lighter before/after totals.
- `crowd_cost_pruned_parsed` is a later parsed cost-prune run. Treat its CPU and combat totals as a separate run until the fixed-source receipt is revalidated; it is not proof of phone performance.
- Path fields and post-sample drain are retained. Existing rows show `completed_within_limit: true` and no pending jobs after drain; path counters vary by scenario and must remain attached to each row. Queue/memory fields exposed by these benchmark rows are zero/absent; this is `MISSING` evidence for process memory, not a claim of zero memory.
- Attack starts, damage applications, target damage, motion frames, and total motion are reported together. A lower damage value is not an optimization success.

## Formal map profiles

`formal_map_frame_only/181636_840877/world_profile.json` and `formal_map_detailed/181734_772641/world_profile.json` use the same formal map layout. The reported values are approximately 62 actors, 14 engaged, 5 actual settlements, P50 3.871 ms vs 4.472 ms. The observation detail differs, so this delta cannot be treated as a product improvement.

## Acceptance boundary

- Mobile/device FPS: `NOT_RUN`.
- Phone drop fix: `MISSING`.
- Final fixed-source 12-case rerun: `NOT_RUN` (root will run after source freeze).
- No production or test files were modified in this aggregation.
