# Unknown symbol audit V4

Root reconciliation keeps all 675 raw signatures and exactly their original calls/Self/Total/Internal/frames fields. Source identity and exact method matching use V3 validated fixed107 blobs; the one missing frozen fixture remains MISSING. V1 nearest-line mappings and V2 missing-blob validation are superseded. V3 markdown inclusive totals of zero were a report-key error; original JSON Total values were retained and are used below. No tests were rerun.

Global signature aggregates do not carry per-call caller paths. Caller attribution to Enemy outer remains MISSING for shared functions; these resource groups are a symbol inventory, not a production CPU partition. Line-zero builtin/native records are shared, independent of the script path shown by the profiler.

| Script resource (line-zero excluded) | Signatures | Calls | Self ms | Nested Total ms (do not sum) |
|---|---:|---:|---:|---:|
| `res://scripts/enemy.gd` | 125 | 915606 | 440.105 | 8360.565 |
| `res://scripts/monster_visual.gd` | 34 | 247454 | 140.688 | 603.419 |
| `res://scripts/game_root.gd` | 48 | 94802 | 113.000 | 870.447 |
| `res://scripts/runtime_combat_spatial_index.gd` | 18 | 106810 | 88.236 | 254.217 |
| `res://scripts/map_editor/polygon/poly_index.gd` | 5 | 100312 | 64.102 | 142.710 |
| `res://scripts/layers/runtime/execution/frame_budget.gd` | 10 | 67134 | 53.426 | 108.365 |
| `res://scripts/world_spatial_rules.gd` | 6 | 147883 | 46.492 | 319.416 |
| `res://scripts/ground_unit_space.gd` | 5 | 217284 | 45.361 | 50.345 |
| `res://scripts/layers/runtime/map_editor_runtime_bridge.gd` | 6 | 73742 | 36.704 | 86.796 |
| `res://scripts/monster_visual_streaming_coordinator.gd` | 11 | 6073 | 26.027 | 229.101 |
| `res://scripts/monster_ai_package/decision_budget.gd` | 9 | 30119 | 24.232 | 119.454 |
| `res://scripts/player_visual.gd` | 20 | 12994 | 22.892 | 74.989 |
| `res://scripts/map_editor/polygon/poly_runtime.gd` | 3 | 8084 | 21.337 | 148.461 |
| `res://scripts/map_editor/map_editor_coordinate.gd` | 2 | 89639 | 20.566 | 51.257 |
| `res://scripts/monster_natural_regen_policy.gd` | 3 | 18109 | 16.351 | 27.648 |

Original unknown Self total: 1502.668ms. Shared line-zero Self: 107.372ms.

Polygon core is only poly_index + poly_geometry. Its script Self76.209ms plus separately listed poly_runtime21.337ms does not substantiate a 50% production route. RuntimeDiagnostics385.557ms and Enemy counter dispatch94.102ms are observer signatures, not FrameBudget/DecisionBudget; full budget modules include additional signatures and shared callbacks outside the earlier subset. No production cost is imputed from inclusive totals, profile perturbation, or missing callers.
