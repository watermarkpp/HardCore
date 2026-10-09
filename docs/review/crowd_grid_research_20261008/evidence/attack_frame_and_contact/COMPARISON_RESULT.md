# ATTACK_START_FRAME_AB offline comparison (corrected)

Date: 2026-10-09

Offline correction of the first comparison. Retained raw per-process arrays are now used for p99; no engine rerun was performed.

## Result

Queued admission produced 2 frame-budget deferrals with waits of 15.092 ms and 14.354 ms. Enemy physics CPU totals were 2161.960 ms (A05 immediate), 2170.136 ms (queued), and 2256.584 ms (A06 immediate). Under this bounded 34-actor / 300-physics-tick diagnostic load, queued admission shows no CPU benefit. This does not prove a general queued-contact or passive-contact solution.

## Per-run metrics

| run | mode | enemy CPU total | per-process enemy CPU p50/p95/p99/max ms | process interval p50/p95/p99/max ms | starts/settlements/completed | damage | waits |
|---|---|---:|---|---|---:|---:|---|
| immediate_05 | immediate | 2161.960 | 7.020/9.458/10.990/13.212 | 16.564/19.429/20.951/21.341 | 18/18/16 | 257 | [] µs |
| queued_01 | queued | 2170.136 | 7.004/9.495/10.890/12.944 | 16.629/19.059/20.778/21.699 | 18/18/16 | 257 | [15092, 14354] µs |
| immediate_06 | immediate | 2256.584 | 7.118/11.129/14.922/17.299 | 16.680/19.558/21.639/22.997 | 19/19/17 | 269 | [] µs |

Per-process p99 uses nearest-rank over retained raw arrays. Summary-only process CPU, whole-physics CPU, and process interval p99 remain `MISSING`; they do not retain raw vectors.

Each report has three pre-window starts (`total_starts - admission starts`); those are excluded from the window. `catchup_epochs=1` for all three runs. `process_counter_alignment` and 300-tick/34-actor cohort alignment are retained in the JSON artifact.

## Evidence limits

- A05 receipt was recovered from the isolated workspace and copied unchanged to `immediate_05/native_logs/runner_results_adhoc_20261009_102456_145_14772.json` (effective exit `0`, result `PASS`, engine errors `0`, SHA256 `026dfb2922273744c54806c268664d493b144a1f3c038bedbdad12f764739e70`). Full A05 stdout/engine logs remain `MISSING`.
- Queued receipt: `queued_01/native_logs/runner_results_adhoc_20261009_102627_364_8928.json`, effective exit 0, result PASS, engine errors 0.
- A06 receipt: `immediate_06/native_logs/runner_results_adhoc_20261009_102928_070_23580.json`, effective exit 0, result PASS, engine errors 0; A06 remains missing-evidence follow-up, not cherry-picked.
- Prior immediate_02 parse, immediate_03 import-metadata, and immediate_04 preload/environment plus grantsource mismatch failures remain classified. Full failed logs remain `MISSING`.
- Android/GPU FPS is `NOT_RUN`. This diagnostic comparison is not a 50% performance claim or acceptance of a future queue/contact design.
