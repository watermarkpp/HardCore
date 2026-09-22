# REV07 strict raw archive
date=2026-09-09
baseline_head=cf1d2718befdef7e6cc2fb274fd91ce0759d105f
candidate_production_anchor=675005cd
candidate_fixture_commit=e37ac922ef263ac8dc749a26e6a96ce8aaa2f034
fixture_gd_sha256=44255E029F12B2B6D248E2D827D41B6ABD47C7D49C4FC3DEAD378AA00A16CEC1
fixture_tscn_sha256=CE5BA79361EC9993B7BFDEBD2DC65B0EF4CC2A68CC6EF34869A12508AB513F13
runner_contract=8 serial runners, each scenario with counts 10,20,30; warmup45; sample150; timeout60
runner_result=all 8 natural PASS; engine_log_errors=0; performance threshold=all 12 rows FAIL
raw_layout=baseline and candidate each contain metrics.json, runner_result.json, runner_console.log per scenario; dense_crowd additionally contains the only surviving performance_comparison_test stdout/stderr/godot logs
raw_limitation=run_godot_tests reuses fixed performance_comparison_test stdout/stderr/godot filenames; open/close/world process logs were overwritten before archival and are unavailable; they are not duplicated or reconstructed
initial_failure=baseline preflight parse failure due missing path_search.gd, archived under initial_baseline_parse_fail
missing_sources=
