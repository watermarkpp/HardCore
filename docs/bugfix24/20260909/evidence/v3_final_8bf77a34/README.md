# REV07 final strict raw archive

source_anchor=8bf77a341b2ab866622d8ee5b74376f6f93fd1ca
fixture_gd_sha256=44255E029F12B2B6D248E2D827D41B6ABD47C7D49C4FC3DEAD378AA00A16CEC1
fixture_tscn_sha256=CE5BA79361EC9993B7BFDEBD2DC65B0EF4CC2A68CC6EF34869A12508AB513F13
runner_contract=8 serial runners; each scenario has counts 10,20,30; warmup45; sample150; timeout60
runner_command=powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/hc_monster_ai/performance_comparison_test.tscn -TimeoutSeconds 60
runner_gate=8/8 natural PASS; effective exit 0; process exited; engine_log_errors 0
performance_gate=12/12 threshold FAIL; see RESULTS.md for all p95 values and limits
candidate_tree_head=e98cb656cbadc47fc5067d57322365ffa6c08484
baseline_tree_head=cf1d2718befdef7e6cc2fb274fd91ce0759d105f
candidate_production_anchor=8bf77a341b2ab866622d8ee5b74376f6f93fd1ca
raw_policy=each runner stdout/stderr/godot logs, runner result, metrics and console copied immediately before the next runner
headless_limit=Windows headless wall callback measurements; no Android device or mixed-audio claim
prior_archive=docs/bugfix24/20260909/evidence/v3_main_integration/rev07_strict_675005cd (including initial baseline parse failure)
- Measurement boundary: the strict runners executed against source anchor 8bf77a341b2ab866622d8ee5b74376f6f93fd1ca. After this window, integration applied 909821c9 with a GameRoot pause/focus input-boundary change (clear touch vector and unify menu cancellation). That boundary path is not exercised by this monster performance fixture, so these numbers are not claimed as a new performance measurement of 909821c9.
- Source sync spot checks: delivery_geometry.gd d7d940c7ce8d5cc43b3dd192f7622b9c9229d167; monster_source_poison_state.gd b48226e4076f4d6c9d766610a06aa4c1ce5003c4; device_lab_patch_bootstrap.gd 2f2775047586bce6380f32ebe79b47ba051668a5; virtual_joystick.gd 97a4b7e0fe7bcd2ce3613b1263d727b51a5bfc04; game_root.gd 794a3d869d9d88c23dbc25fffd2bac67733aee8c. These are source-anchor Git blob checks in the candidate worktree.