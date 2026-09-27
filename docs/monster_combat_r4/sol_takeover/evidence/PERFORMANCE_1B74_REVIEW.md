# R4 native performance decision at candidate 1b74e698

BASE `1381d2838a3736f4a06699dd24a8cf4a10714950` and CAND
`1b74e698728af725595118d0a30ab59c0f0ac58b` were compared in one
process at a time, with the same test-only probe and random inputs. The four
completed matrices each contain two BASE A/A runs and three paired A/B runs.
Every run exited normally and observed 600 consecutive native physics ticks.
The three full-detail matrices cover small30, large30+two pets and 30 live
monsters with actual AoE casts, death persistence and materialized loot. The
fourth matrix repeats large30+two pets in `frame_only` mode. Original logs,
per-tick samples, runner results and source identities are retained beside
each matrix. The exact execution checks all report collection `PASS`.

## Paired observations

| Case / observer | Physics P99 CAND−BASE, three pairs | Physics callbacks >50ms, BASE→CAND | Per-enemy CPU mean CAND−BASE |
| --- | --- | --- | --- |
| small30 / full | −1.33 / −2.92 / −4.18ms | 0→0 in every pair | −0.038 / −0.127 / −0.241ms |
| AoE+death+loot30 / full | −30.19 / −35.87 / −40.61ms | 10→3, 9→4, 9→4 | +0.544 / +0.788 / +0.272ms |
| large30+two pets / full | +8.39 / +11.01 / +4.50ms | 0→0 in every pair | −0.603 / −0.402 / −0.273ms |
| large30+two pets / frame_only | +1.48 / +1.78 / −0.52ms | 0→0 in every pair | `NOT_RUN` |

The frame-only pet process-callback P99 deltas are +2.41 / +3.07 / −0.48ms;
all six paired process runs have zero callbacks >50ms. BASE A/A frame-only
mean-interval difference is 0.01545ms. Paired mean-interval differences are
+0.02745 / +0.01273 / −0.00367ms. The candidate therefore still has a
small pet-scene tail cost in two pairs. Actor start and pet-hit counts differ
between executions, so these are comparable live scenarios, not identical
completed work. No percentage improvement is inferred from unequal deaths.

`full` explicitly turns on hot-path per-actor micro timers and Dictionary
counters. `frame_only` disables those counters while retaining the native
callback timestamps. The production Release gate is closed in
`scripts/runtime_diagnostics.gd::refresh_performance_gate`. The full-detail
pet P99 warning must not be silently discarded, but it is not a measured
Release-frame regression. The earlier e367 CPU warning is likewise retained:
all three new AoE full-detail CPU deltas are positive, although no three-pair
regression exceeds its own 0.673ms BASE A/A spread. An increase in A/A noise
is not proof that CPU improved.

The new AoE phase counters place +0.415/+0.189/−0.061ms per callback in the
movement-strategy segment and +0.365/+0.227/−0.043ms in its nested
move-and-slide segment; death settlement saves 0.503/0.603/0.578ms per
callback. These segments overlap and execution counts differ (movement
strategy calls CAND−BASE +224/−252/−127); they cannot be summed into a
causal explanation or used to justify changing the protected collision and
combat behavior.

## Decision and limits

- `PASS`: desktop native severe-long-frame target for this fixed candidate:
  all three paired AoE executions improve physics and process tails; the
  frame-only 30-large+pet case adds no >50ms callback, and small30 improves.
- `FAIL`: claim that every measured CPU component or pet-scene percentile
  improved. Full AoE enemy inclusive CPU remains directionally higher and two
  frame-only pet P99 pairs are 1–3ms higher.
- `NOT_RUN`: GPU render and installed-device comparison. This is a source
  performance gate, not an APK or phone acceptance claim.

This conclusion applies only to the fixed CAND source above. A later forge
integration needs its own final relevant performance gate before push.

Raw matrices: `native_t6_aoe30_1b74_20260928_0556/`,
`native_t6_small30_1b74_20260928_0604/`,
`native_t6_large_pets30_1b74_20260928_0604/`,
`native_t6_large_pets30_frame_1b74_20260928_0614/`.
