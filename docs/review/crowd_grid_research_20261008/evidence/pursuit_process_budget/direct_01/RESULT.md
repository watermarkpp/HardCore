# Pursuit budget contract direct_01

Status: FAIL. First native execution of the isolated candidate; no performance result.

Command: `tools/run_godot_tests.ps1 -TestPaths tests/crowd_pursuit_budget_contract_20261009.tscn -TimeoutSeconds 30`.

The engine rejected decision_budget.gd at lines 69 and 89: an untyped Array element assigned using inferred `id` has no fixed type. The scene could not enter its contract checks. Neither the nested-lease assertion nor other behavioral assertions ran. Native completion is MISSING: early_script_error caused forced termination, effective exit -1, not a normal native exit and not a timeout.

Receipt: `native_logs/runner_results_adhoc_20261009_112549_518_22372.json`; invocation `5509c132-506c-4365-b4b8-a5c2c3964e35`; engine error count 2. INPUTS.json and the three copied sources bind the candidate before this invocation. Post-run source equality was not retained before implementation was released for repairs; do not imply a verified post-run hash audit.

Retest reason: fix actual parser failure and identified production admission/diagnostic ownership defects, then rerun the contract on a newly frozen source. Preserve this failure evidence.
