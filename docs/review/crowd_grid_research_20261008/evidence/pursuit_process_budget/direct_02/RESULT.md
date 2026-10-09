# Pursuit budget contract direct_02

Status: FAIL. Native scene parsed and exited normally with code 1; engine errors 0; no timeout. No performance result.

Command: `tools/run_godot_tests.ps1 -TestPaths tests/crowd_pursuit_budget_contract_20261009.tscn -TimeoutSeconds 30`.

Receipt: `native_logs/runner_results_adhoc_20261009_113227_064_21936.json`; invocation `89270614-40c3-4606-9307-e45a6b6058dc`. INPUTS.json, source copies and POST_RUN.json retain hashes.

The two failing assertions are `disabled queued owner does not block valid FIFO service` and `destroyed queued owner does not block the next owner`. Inspection identifies a test-isolation problem: after the thirty-owner FIFO exercise, its valid older waiters remain pending, but the later lifecycle subcases request newer owners and expect them to jump ahead. The implementation correctly retains the older valid FIFO. The lifecycle subcases need fresh explicit setup, plus negative controls that valid older owners still retain priority. This is not permission to weaken production fairness or discard a queue during the tested lifecycle transition.

Retest reason: correct independent lifecycle fixture setup and preserve meaningful valid-head/invalid-head assertions. Production source is unchanged for that fixture correction. Direct_01 parser failure remains retained separately.
