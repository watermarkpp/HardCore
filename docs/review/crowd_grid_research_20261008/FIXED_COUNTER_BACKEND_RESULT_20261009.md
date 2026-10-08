# Fixed Counter Backend Result — 2026-10-09

## Scope and evidence boundary

This report archives candidate11 and the existing runner receipts without rerunning detection. The candidate source stage is fixed107 HEAD `edae6fdef6a6551a951fab1ea8c6ade43359d603`; all 11 candidate source hashes are preserved in [CANDIDATE_01_SOURCE.json](../../../outputs/crowd_fixed_counter_backend_20261009/final_evidence/CANDIDATE_01_SOURCE.json) and the exact source files are under `final_evidence/candidate_01_source/`. The source stage is **NOT_RUN** for this archival operation; the runner evidence below is retained as recorded.

The candidate is an independent diagnostic candidate and is retired. It must not be presented as a release, a debug-phone result, or a production performance guarantee. Root owns restoration of Enemy and diagnostics separately.

## Complete-window measurements

Both fixed-counter windows used the same formal fixture: 34 alive actors, 30 engaged actors, 48 loot pickups, 300 physics ticks, and 10,200 enemy physics callbacks. Both raw reports and native receipts recorded **PASS**.

| Window | Enemy physics CPU | Physics CPU p50 / p95 / max | Frame interval p50 / p95 / max | Trajectory | Decision queue |
|---|---:|---:|---:|---|---|
| `fixed_counter_30_01` | 2,211,004 us | 7.321 / 11.024 / 16.619 ms | 4.961 / 15.961 / 21.672 ms | 131 moving ticks, 4.40964037003141 GU, 30 distinct movers, 25 ending, max 28 | queue 0, open scopes 0, max wait 2 frames, admitted 1164 |
| `fixed_counter_30_02` | 1,986,185 us | 6.831 / 9.282 / 11.452 ms | 5.901 / 14.854 / 18.282 ms | 118 moving ticks, 3.00282406617794 GU, 29 distinct movers, 24 ending, max 27 | queue 0, open scopes 0, max wait 1 frame, admitted 1164 |

The two-window median enemy physics CPU is `2,098,594.5 us` (`2,098.5945 ms`). Fixed107 comparison median is `2,057.2785 ms`; the candidate is `(2098.5945 / 2057.2785 - 1) * 100 = 2.0082842454%` slower, reported as **+2.0083% slower**. The performance target is **FAIL**. The second window is not selected as a benefit; both complete windows are retained.

Additional retained metrics include process/frame samples, actor census, targeting, player trajectory, per-tick physics samples, movement candidate checks, strategy calls, attack LOS rays, loot spatial queries, and queue/death/drop counters. The queue and scope counters were zero at the end of both windows; no metric change is treated as a pure backend causal cost.

## Stage and runner evidence

| Evidence slice | Status | Evidence binding |
|---|---|---|
| Fixed counter direct contract and diagnostics window runner | **PASS** | Existing `direct_and_window_01` UUID receipts: `6c49e458-650b-4bf7-ae12-a76c20dedf9c` and `9fc2216e-fb12-482f-b93f-60e0eff24836`; native exit `0` |
| Complete window `fixed_counter_30_01` | **PASS** | UUID `9b74e6a8-f0f2-442b-8a17-8cbf9d03abf3`; native exit `0`; test scene `tests/crowd_formal_grid_comparison_20261008.tscn` |
| Complete window `fixed_counter_30_02` | **PASS** | UUID `89ce1ba3-68e8-4317-b7c1-f5adf03baa7d`; native exit `0`; test scene `tests/crowd_formal_grid_comparison_20261008.tscn` |
| Initial missing-API RED | **FAIL** | UUID `b3406fef-b37c-49c3-bcb3-fc4cd9467f8f`; native exit `1`; preserved in `receipts/red_01/` |
| Static ID-wrapper rejection artifact | **NOT_RUN** | Preserved under `static_id_wrapper_rejection/`; no status upgraded from its recorded result |
| Candidate source archive | **NOT_RUN** | 11 exact source files and hashes preserved; manifest status remains `NOT_RUN` |
| Generic producer/source command metadata | **MISSING** | Receipt producer fields are absent; no command or producer identity is invented |
| Same-source release/device acceptance | **MISSING** | Diagnostic-only candidate; no release or debug-phone claim is made |

The complete five UUID receipt directories, including raw stdout/stderr/Godot logs, native handoffs, RED evidence, and both complete-window receipts, are indexed in [receipt_index.json](../../../outputs/crowd_fixed_counter_backend_20261009/final_evidence/receipt_index.json). The archive inventory is [archive_inventory.json](../../../outputs/crowd_fixed_counter_backend_20261009/final_evidence/archive_inventory.json).

## Decision

The fixed-counter backend candidate is **retired** as an independent diagnostic candidate. Direct contract, diagnostics window, and both complete windows are recorded **PASS** at their own evidence scope. The median comparison target is **FAIL** because the candidate is 2.0083% slower than fixed107, and no release/debug-phone performance claim is supported. Earlier RED and static-wrapper evidence remain preserved and are not overwritten or merged into a same-source all-pass claim.

Production restoration is a root-owned action and is outside this archive.

## Delivery and unresolved items

- Evidence archive: `C:\Users\Administrator\Documents\HardCore\outputs\crowd_fixed_counter_backend_20261009\final_evidence\`
- Candidate source manifest: `final_evidence\CANDIDATE_01_SOURCE.json`
- Raw reports: `final_evidence\raw_reports\fixed_counter_30_01.json` and `fixed_counter_30_02.json`
- UUID receipt index and logs: `final_evidence\receipt_index.json` and `final_evidence\receipts\`
- Static wrapper artifact: `final_evidence\static_id_wrapper_rejection\`
- Archive inventory SHA-256: `25820A98774826EFB142C3AE61D9FB7CFFF38E30B31ABBE05C075E0D0BCDD6C8`
- Scope: archive/reconciliation only; no rerun, build, source restoration, staging, commit, or push.
- Unresolved: performance target **FAIL**; generic producer metadata **MISSING**; release/device evidence **MISSING**; device test **NOT_RUN**.




## Root retirement

Enemy and RuntimeDiagnostics were restored byte-for-byte after final archive; all five production paths match stock107. RESTORATION.json retains before/after hashes. No new test, source promotion, release build or device run was performed.
