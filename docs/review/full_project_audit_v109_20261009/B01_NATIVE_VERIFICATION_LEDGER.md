# B01 native verification ledger

## Evidence binding

This ledger records retained executions; it does not rerun them. The freeze
manifest is
`outputs/wake_drop_v108_review_followup_20261009/B01_REPAIR_FREEZE_13.json`.
Its candidate tree is `93d989012c55e087fa73486c56120ce01ce9fa8f`, parent
`ed2d87121de80c84caaa3f096c3a5acb71d4946f`, and the tested main worktree
head is `215f0b2f651a51e6855ee813ddd99221690311a1`. The engine fingerprint is
`d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`.

The receipts below report that same main head. Their `runtime_appdata`
directories are retained per run, so the result is bound to the run rather
than to a later working-tree state. The freeze manifest's fixture hash is
the candidate snapshot hash; later local fixture edits are not silently
substituted into these results.

The follow-up raw binding record
`outputs/wake_drop_v108_review_followup_20261009/B01_GIT_WORKTREE_BINDING.json`
compares all 19 indexed files separately as raw bytes and normalized Git
blobs. Every raw snapshot matches the freeze input and every
newline-normalized comparison is equal. A few Git blob SHA values differ from
raw SHA values only because the Git representation uses LF while the frozen
working snapshot uses CRLF; this does not invalidate the native source
binding.

## Run ledger

| Run | Receipt | Scope and result | Native/engine status | Cleanup distinction |
|---|---|---|---|---|
| direct12 resource owners | `outputs/wake_drop_v108_review_followup_20261009/direct12_resource_owners/logs/runner_results_adhoc_20261009_224657_611_21472.json` | 5 tests: `retired_threaded_resource_claims_20261009` PASS; `world_bootstrap_generation_prefetch_contract_20261009` PASS; `monster_source_frames_terminal_get_contract_test` PASS; `monster_visual_streaming_terminal_get_contract_test` FAIL; `startup_loading_terminal_get_contract_test` FAIL | The three PASS cases exited 0. Visual coordinator was forced-terminated after its marker with a null-instance notification. Startup exited 1, had no pass marker, and had two contract `push_error`s. Receipt aggregate: `passed=3`, `failed=2`, `engine_log_errors=3`. | Startup also reported `118 ObjectDB instances leaked`; this is retained with the failed receipt and is not a functional PASS. |
| direct13 resource owners fix | `outputs/wake_drop_v108_review_followup_20261009/direct13_resource_owners_fix/logs/runner_results_adhoc_20261009_224951_367_13948.json` | Changed probes: `monster_visual_streaming_terminal_get_contract_test` PASS and `startup_loading_terminal_get_contract_test` PASS | Both native exits 0, markers present, `engine_log_errors=0`, framework receipts valid | Startup stderr retained `WARNING: 118 ObjectDB instances were leaked at exit`. This warning did not produce an engine-log failure in the runner. |
| related14 resource lifecycle | `outputs/wake_drop_v108_review_followup_20261009/related14_resource_lifecycle/logs/runner_results_adhoc_20261009_225354_473_6892.json` | Six PASS: feature preparation, foreign request, bootstrap stage order/failure, startup failure recovery, and startup terminal get | All six native exits 0, markers present, `failed=0`, `engine_log_errors=0` | Startup stderr retained `WARNING: 94 ObjectDB instances were leaked at exit`; startup stdout contains 94 `Leaked instance: RefCounted:<id> - Reference count: 0` lines. No `resource in use` evidence was emitted. |
| integration15 initial ready | `outputs/wake_drop_v108_review_followup_20261009/integration15_initial_ready/logs/runner_results_adhoc_20261009_225532_716_18552.json` | Real `initial_world_bootstrap_test` PASS | Native exit 0, marker present, `failed=0`, `engine_log_errors=0` | No ObjectDB leak warning. It did retain the pre-existing nonfatal `Loading ended with item icons still prewarming in background` warning. |

The direct13 receipt is the direct13 receipt above; the related14 receipt is
the separately named related14 receipt above. They must not be interchanged
when reproducing the evidence chain.

## What the positive claim fixture actually proved

The direct12 stdout marker was:

`RETIRED_THREADED_RESOURCE_CLAIMS_PASS: transferred claim bounded, second owner retained, INVALID recorded`

The fixture source also records the concrete checks: two same-path engine
claims are accepted, one claim is transferred while the other owner retains
and later gets its claim, a separate two-claim transfer is consumed one get
per quantum, and an INVALID path increments `missing` without calling
`load_threaded_get`. Related14 independently passed the preparation and
foreign-request service probes. These are the bounded existing-service
handoff behaviors; there is no second request/get owner or second loader.

## Explicitly unproven cases

* An engine-accepted request reaching `THREAD_LOAD_FAILED` was **NOT_RUN**.
  The fixture queries an unrequested INVALID path directly; it no longer
  issues an intentionally missing native request. This proves INVALID bookkeeping, not a terminal FAILED claim.
* The separate 60-second asynchronous timeout/race scenario was **NOT_RUN**.
* The direct12 failed visual-disposal and startup receipts remain failures;
  later direct13/related14 passes are scoped reruns and do not erase them.

## Source and command scope

The production handoff remains in the existing `FeatureResourcePreparation`
service and `ContentLayers.retire_threaded_resource_claims(path,
claim_count)`. The freeze manifest binds the service and registry hashes,
fixture hashes, startup/world sources, runner hash, and engine hash. No
production or test file was changed while creating this ledger, and no native
or engine command was run for this documentation update.

## Durable receipt retention

`evidence/B01/RECEIPT_RETENTION.json` records each run, exact scene arguments,30-second timeout, runtime profile, and whether its complete framework receipt still matches the original producer run ID. The runner result remains authoritative for its observed validation outcome. Complete receipts overwritten by a later run are recorded MISSING; a later matching scene name is never substituted. In particular startup direct13 and failed direct12 fixtures retain their logs/runner verdicts but their complete receipts are not claimed to have survived. Non-framework scenes have runner-native evidence and no framework receipt requirement. Current matching receipts, logs, freeze and raw/Git binding are copied into evidence/B01.

Every run used tools/run_godot_tests.ps1 with explicit TestPaths from that JSON and TimeoutSeconds30, GIT_INDEX_FILE=b01_final_review.index, HARDCORE_AUDIT_LOG_ROOT=<run>/logs, and HARDCORE_AUDIT_RUNTIME_APPDATA=<recorded isolated profile>. Related14 additionally used -Verbose for the retained cleanup diagnosis. Direct12 predates the direct13 repairs; its candidate is75e1c2e9a4cbd3008683c5e3ee17472b0dbaf45d. No new run was performed to collect these copies.
