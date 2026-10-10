# B07B log evidence disposition

This is a standalone helper for the runner's later 004/006 integration. It does not modify `tools/run_godot_tests.ps1`, the receipt validator, production code, or historical raw evidence. Godot/Linux/Android execution is **NOT_RUN**.

The helper classifies the four current allowlisted engine error categories independently: string-formatting errors, resources still in use, dummy-renderer RID leaks, and the null `t` parameter. It also reports ObjectDB leak warning lines, unknown `ERROR:` lines, and their raw text. Unknown errors produce helper `FAIL`; the helper never converts that result into an upstream runner decision.

Formal evidence requires a receipt whose scene ID and invocation ID match the requested pair, whose check list and count are nonzero and consistent, and whose status is `PASS` with zero failures. A legacy PASS marker without that uniform receipt is reported as `formal_evidence_status=MISSING` with `legacy_run_bound_checks_missing`. A receipt for a different scene or invocation is also formal `MISSING` even when it says PASS.

## Evidence

Command:

`powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools/tests/native_log_evidence_20261010_test.ps1`

Exit code: `0`

Receipt: `outputs/wake_drop_v108_review_followup_20261009/b07b_log_evidence/9758cf87c20642088bf6795b23a045b5/native_log_evidence_test.json`

Receipt SHA256: `477de873238fedd18677eea9c1d2061aa23084638beefd3237cd841d7063d56c`

The three helper cases passed: all four allowlist categories plus one ObjectDB warning were returned with raw lines and counts; an unknown error with only a legacy marker failed the log classification and remained formal MISSING; and a foreign PASS receipt remained formal MISSING. The output directory contains a nonce to avoid overwriting prior evidence.

The helper source hash is `503f1762b2f8f8294c4239f137a88851b5c33e5ab97003a8cbe2fdc4792ee568` (4,232 bytes). The owned test hash is `2b2284dbc4c795eecc03bb079ff70af69f706760b24513a5e08d10f01ed52a9e` (3,727 bytes).

No real runner scene was replayed, no upstream formal PASS was granted, and no historical raw evidence was changed. Runner integration remains for the root agent.
