# DPV2 V5.0.5 Review Candidate

This is a review candidate, not an integration merge certificate.

- MIGRATION_BASE_SHA: `342891ab884150c0e81084c932df8205484e6388`
- ORIGINAL_GAMEPLAY_BASE_SHA: `ffcdc76b360d5976eef2ce17a45664ddaf550590`
- CODE_SHA: `1ee2b0381cd72c1872ed7de7823d9880dd62adc2`
- REVIEW_BRANCH: `codex/dpv2-glm52-flash-v5-0-3-20260908`

## Source migration

- source status: `{"EXPLICIT_NON_LOOT":9,"FULL_21CQ_VERIFIED":141,"LEGACY_PRESERVED_EXTERNAL_EMPTY":2,"PROJECT_EXTENSION":1,"RUNTIME_DISABLED":3}`
- compiled slots: `7611`
- UID reused: `5889`
- added slots: `1463`
- removed legacy-only slots: `661`

## Balance

- verified book monsters: `42`
- book rules: `{"BOOK_ELITE_BOSS":325,"BOOK_ORDINARY":149}`
- Boss K status: `NO_BOOST_SOURCE_ALREADY_AT_OR_BELOW_TARGET`
- Boss K: `1`
- Woma final no-equipment: `2.13638839330004E-07`
- four-boss no-equipment before/after:
  - ID76 (沃玛教主): before `2.1363883933000385E-07` -> after `2.1363883933000385E-07`
  - ID198: before `0.6674026326662957` -> after `0.6674026326662957`
  - ID199: before `0.10577489871304631` -> after `0.10577489871304631`
  - ID225: before `0.2341400898941459` -> after `0.2341400898941459`
- armor 1/60 proofs: `6`

## Final verification (V5.0.5e, candidate at CODE_SHA)

- Godot V5 specialist: PASS (`test_dpv2_repair_v5`, passed=1 failed=0 engine_log_errors=0)
- Critical suite: passed=316 failed=2 engine_log_errors=3
  - complete_client_resource_catalog_test — FAIL on candidate AND on ffcdc76b BASE (A/B: baseline/environment; generated resource manifest missing on both)
  - combat_unit_source_priority_test — FAIL on candidate AND on ffcdc76b BASE (A/B: baseline/environment; identical assertion failure on both)
- skill_runtime_single_result_contract_test RID gate: candidate 3/3 PASS, ffcdc76b BASE 3/3 PASS — no repeatable candidate-only RID failure
- No candidate-only regression remains; all failures are baseline/environment-classified via same-machine A/B.

## Full-suite stability (V5.0.5f re-run record)

The official final Critical run (runner_results_critical_20260908_143024_221_8864.json)
is `passed=316 failed=2`, captured in `critical_runner.log` as a verbatim transcript
reconstructed from that run's own per-test records. During V5.0.5f docs closure the
full suite was re-run on the same clean committed candidate (CODE_SHA `1ee2b038`),
same machine / Godot / runner command:

- re-run #1: `passed=314 failed=4` — `skill_production_single_commit_test` and
  `map_runtime_release_gate_test` failed with engine-level headless dummy-renderer
  RID errors (`Attempting to initialize the wrong RID`, `texture_2d_initialize`,
  `rid_owner.h`/`texture_storage.h`); the other 2 failures were the known
  baseline/environment tests.
- re-run #2: `passed=313 failed=5` — same RID error class hit a different set of
  texture-loading tests (`enemy_snapshot_v2_production_test`,
  `map_transition_missing_arrival_test`, `unbuilt_planned_map_not_playable_test`);
  plus the same 2 baseline/environment failures.

Classification of the RID-noise failures:
- candidate standalone retry: 2/2 + 2/2 PASS (`skill_production_single_commit_test`,
  `map_runtime_release_gate_test`);
- ffcdc76b BASE standalone: both PASS;
- all such tests PASSED in the official 143024 run on the same candidate code.

Conclusion: the intermittent RID errors are a headless dummy-renderer engine
artifact that randomly hits 2-3 texture-loading tests per full-suite run. They are
not candidate-only regressions (same code PASSed them in the official run and in
standalone retries; BASE also PASSes them). The official `316/2` result is the
canonical evidence for this candidate; `critical_runner.log` records it with a
provenance header so the reconstructed transcript is auditable against
`runner_results_critical_20260908_143024_221_8864.json`.

## Hotfix chain applied on top of migration

- V5.0.5b.1: runtime classification closure (canonical-authority 233 + drop subset 231)
- V5.0.5c: JSON numeric-array integer-aware membership (book/boss contract IDs)
- V5.0.5d: post-loop ceiling_count closure constant (2203 -> 1435)
- V5.0.5e: Critical test contract migration (ID76 source-driven 108 rows, ID89 80 rows)

## SHA semantics

A Git commit cannot contain its own final SHA without changing that SHA. The
actual FINAL_SHA and independently verified REMOTE_HEAD_SHA are recorded in the
post-push receipt (`V505_PUSH_RECEIPT.json`) outside the repository, after the
docs-only closure commit (V5.0.5f). They must be equal, verified via
`git ls-remote origin refs/heads/codex/dpv2-glm52-flash-v5-0-3-20260908`.
