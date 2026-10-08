# Causal observer verification — 2026-10-09

This is an offline diagnostic comparison. It does not modify production sources, does not claim an optimization, and does not substitute for a no-profiler performance run. All three arms use the real `crowd_observer_causality_20261009.tscn` workload with 34 active / 30 engaged actors and 300 physics ticks.

## Evidence and source binding

- Engine: `Godot Engine v4.7.stable.official.5b4e0cb0f; physics_tps=60; renderer=gl_compatibility; max_physics_steps=8`.
- Fixed research HEAD: `edae6fdef6a6551a951fab1ea8c6ade43359d603`.
- Scene/test/helper and corrected Enemy archive hashes are in `CAUSAL_OBSERVER_VERIFICATION.json`; corrected archive SHA256 is `d171e56abbc91d4f2e0455470bc4fe055913c1005c5ed18cfa5d57bbd60aedba`.
- Each run records the workload JSON, runner receipt, native result, UUID log, source hashes, and runtime appdata.

## Runs

| arm | detail mode | outer calls | observer CPU | workload | native exit | runner verdict |
|---|---|---:|---:|---|---:|---|
| full_boundary_fail | full | 10166 | 2085.917 ms | FAIL | 1 | FAIL |
| full_pass | full | 10200 | 2160.993 ms | PASS | 0 | PASS |
| frame_only_pass | frame_only | 10200 | 1850.120 ms | PASS | 0 | PASS |

The first full-detail boundary failure is retained: `causal_full_30_01` has 10,166 outer calls, 2,085.917 ms observer time, and `causal_outer_clock_incomplete_10166`; its runner is **FAIL** (missing pass marker, exit code 1). It is not replaced by the later corrected PASS.

## Diagnostic delta

The corrected full-detail PASS has 10,200 calls and 2,160.993 ms; frame-only PASS has 10,200 calls and 1,850.120 ms. Their paired elapsed difference is **310.873 ms** (14.3857% of full-detail observer time), but strict causal attribution is **UNKNOWN**. The realized trajectories differ: full PASS has 123 player-moving ticks / 2.968486611 GU, 16 attack starts, player HP end 168, 29 distinct movers / 24 ending; frame-only has 115 player-moving ticks / 2.854997543 GU, 16 attack starts, player HP end 179, 29 distinct movers / 25 ending. Potion/event timing also differs (including a use at tick 195 versus tick 165). Therefore the delta is a paired diagnostic measurement only; it cannot be called pure observer contribution, stable optimization, or evidence for 50% CPU reduction.

## Realized trajectory and static-count mismatches

| arm | player moving ticks / GU | attack starts | player HP end | distinct movers / ending | enemy physics / engaged / foreground | motion clears / neighbors / retarget / projection |
|---|---|---:|---:|---|---|---|
| full boundary FAIL | 126 / 3.717940380 | 12 | 137 | 30 / 25 | 10200 / 8757 / 8757 | 9414 / 687 / 8797 / 16607 |
| full PASS | 123 / 2.968486611 | 16 | 168 | 29 / 24 | 10200 / 8655 / 8655 | 9143 / 946 / 8695 / 15964 |
| frame-only PASS | 115 / 2.854997543 | 16 | 179 | 29 / 25 | disabled / disabled / disabled | disabled / disabled / disabled / disabled |

Potion/event schedules also differ (including a use at tick 195 in full PASS versus tick 165 in frame-only). These mismatches make strict causal attribution **UNKNOWN**, even though both PASS arms share the fixed input schedule, map, actor count, identity order and 300 physics ticks.

## Workload and verdict boundaries

- Both PASS arms: native process exit 0, pass marker found, stderr 0, engine-log errors 0, 300 physics ticks.
- Boundary FAIL: native exit 1, missing pass marker; preserved as the first failure.
- Detail counters were disabled only for the frame-only causal arm. The fixed workload contract matched on inputs, map, actor count, identity order and 300 physics ticks, while realized motion/attack/HP phase outcomes did not match; independently always-enabled Enemy counts are preserved in JSON for comparison.
- No arm is promoted to a production optimization or performance green. Production improvement still requires a fixed-candidate full-instrumentation comparable accepted workload evidence; this report is not a no-profiler requirement.

Machine-readable evidence: `outputs/crowd_v107_practice_20261008/CAUSAL_OBSERVER_VERIFICATION.json`.
