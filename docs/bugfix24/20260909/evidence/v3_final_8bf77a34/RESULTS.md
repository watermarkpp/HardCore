# REV07 final strict comparison at source anchor 8bf77a34

This is a headless Windows comparison of the real actor/world fixture. full_frame_ms is the wall interval between adjacent Time.get_ticks_usec() process callbacks. It is not Android device CPU time or a device performance claim.

- Source anchor: 8bf77a341b2ab866622d8ee5b74376f6f93fd1ca.
- Baseline tree: bugfix24-audio-baseline-20260909, Git HEAD cf1d2718befdef7e6cc2fb274fd91ce0759d105f, with its pre-existing W4 headless compatibility overlay.
- Candidate tree: bugfix24-rev07-perf-20260909, Git HEAD e98cb656cbadc47fc5067d57322365ffa6c08484; scripts/ and assets/ worktree production content was restored from the source anchor. Probe and evidence files were kept separate.
- Fixture SHA-256: performance_comparison_test.gd 44255E029F12B2B6D248E2D827D41B6ABD47C7D49C4FC3DEAD378AA00A16CEC1; .tscn CE5BA79361EC9993B7BFDEBD2DC65B0EF4CC2A68CC6EF34869A12508AB513F13.
- Fixed layout: seed 20260909; scenarios open_pursuit, sustained_close_attacks, world_obstacles, dense_crowd; counts 10/20/30; warmup 45; sample 150; one serial runner per side and scenario.
- Runner command: powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/hc_monster_ai/performance_comparison_test.tscn -TimeoutSeconds 60 with HARDCORE_REV07_SCENARIOS set to one scenario and HARDCORE_REV07_COUNTS=10,20,30.
- Runner gate: 8/8 natural PASS, effective exit 0, process exited, engine_log_errors 0. Performance threshold rows are evaluated independently below.

Threshold: candidate_p95 <= max(baseline_p95*1.05, baseline_p95+0.5ms).

| scenario | count | base p95 ms | candidate p95 ms | limit ms | threshold | base motion actors/frames | candidate motion actors/frames | base attack actors/starts/damage | candidate attack actors/starts/damage | physics/process ticks | enemy physics callbacks base/candidate | movement callbacks base/candidate | path services/expansions candidate |
|---|---:|---:|---:|---:|---|---|---|---|---|---|---|---|---|
| open_pursuit | 10 | 8.854 | 10.718 | 9.354 | FAIL | 10/1352 | 10/1334 | 0/0/0 | 0/0/0 | 150/150 | 1500/1500 | 1352/1335 | 0/0 |
| open_pursuit | 20 | 10.527 | 15.095 | 11.053 | FAIL | 20/2740 | 20/2245 | 0/0/0 | 0/0/0 | 150/150 | 3000/3000 | 2740/2248 | 0/0 |
| open_pursuit | 30 | 11.933 | 18.584 | 12.530 | FAIL | 30/4128 | 30/3293 | 0/0/0 | 0/0/0 | 150/150 | 4500/4500 | 4128/3299 | 0/0 |
| sustained_close_attacks | 10 | 8.620 | 12.008 | 9.120 | FAIL | 10/590 | 10/381 | 10/10/10 | 10/10/10 | 150/150 | 1500/1500 | 590/381 | 0/0 |
| sustained_close_attacks | 20 | 10.156 | 23.379 | 10.664 | FAIL | 20/1480 | 20/652 | 20/20/20 | 12/14/14 | 150/150 | 3000/3000 | 1480/652 | 0/0 |
| sustained_close_attacks | 30 | 11.962 | 23.451 | 12.560 | FAIL | 30/2744 | 29/645 | 28/28/28 | 12/20/20 | 150/150 | 4500/4500 | 2744/645 | 0/0 |
| world_obstacles | 10 | 8.833 | 9.911 | 9.333 | FAIL | 10/1353 | 5/426 | 0/0/0 | 0/0/0 | 150/150 | 1500/1500 | 1353/426 | 13/171 |
| world_obstacles | 20 | 10.686 | 12.369 | 11.220 | FAIL | 20/2720 | 7/526 | 0/0/0 | 0/0/0 | 150/150 | 3000/3000 | 2720/527 | 26/399 |
| world_obstacles | 30 | 13.113 | 14.828 | 13.769 | FAIL | 30/4101 | 10/747 | 0/0/0 | 0/0/0 | 150/150 | 4500/4500 | 4101/750 | 37/590 |
| dense_crowd | 10 | 8.733 | 11.603 | 9.233 | FAIL | 10/956 | 10/811 | 8/8/8 | 6/8/8 | 150/150 | 1500/1500 | 956/811 | 0/0 |
| dense_crowd | 20 | 10.270 | 17.337 | 10.784 | FAIL | 20/1946 | 19/991 | 15/15/15 | 8/10/10 | 150/150 | 3000/3000 | 1946/991 | 0/0 |
| dense_crowd | 30 | 11.720 | 25.443 | 12.306 | FAIL | 30/3140 | 26/924 | 20/20/20 | 9/15/15 | 161/150 | 4500/4830 | 3140/1023 | 0/0 |

All 12 performance rows are FAIL under the stated threshold. The eight runner process gates are PASS; those are separate results.

The prior 675005cd strict archive and its initial baseline parse failure remain at docs/bugfix24/20260909/evidence/v3_main_integration/rev07_strict_675005cd.

Raw retention: this run archived stdout, stderr, Godot log, outer runner console, runner result JSON, metrics JSON, per-run metadata, and SHA256SUMS immediately after each runner. No raw file was intentionally reconstructed.
- Measurement boundary: the strict runners executed against source anchor 8bf77a341b2ab866622d8ee5b74376f6f93fd1ca. After this window, integration applied 909821c9 with a GameRoot pause/focus input-boundary change (clear touch vector and unify menu cancellation). That boundary path is not exercised by this monster performance fixture, so these numbers are not claimed as a new performance measurement of 909821c9.
- Source sync spot checks: delivery_geometry.gd d7d940c7ce8d5cc43b3dd192f7622b9c9229d167; monster_source_poison_state.gd b48226e4076f4d6c9d766610a06aa4c1ce5003c4; device_lab_patch_bootstrap.gd 2f2775047586bce6380f32ebe79b47ba051668a5; virtual_joystick.gd 97a4b7e0fe7bcd2ce3613b1263d727b51a5bfc04; game_root.gd 794a3d869d9d88c23dbc25fffd2bac67733aee8c. These are source-anchor Git blob checks in the candidate worktree.