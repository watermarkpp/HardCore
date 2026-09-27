# Native overhead reflection closure

Production input SHA3705228893d26105ddaa404464eb3df755871510. The new test extends the real EnemyActor only to count its native `_get_property_list` requests; actual MonsterOverhead refresh and existing formatter functions execute unchanged. No fake name/rank implementation or production counter was introduced.

Actual RED `overhead_scan_red/runner_results_adhoc_20260928_013448_740_11184.json`: normal native exit1, errors0, three identities39/41/199 each perform4 complete property enumerations per native overhead refresh and800 over200 repeated name/rank queries. Durations332193/323670/315221us. Presentation assertions themselves passed; failures identify redundant reflection.

Production fix: `_has_property` accepts the three declared EnemyActor fields without constructing the complete property list. Generic/legacy Node callers retain reflection. No identity, name normalization, rank, layout, body, damage, RNG, clock or art change.

Actual GREEN `overhead_scan_green`: durations1337/1309/1288us, enumeration0; actual ordinary/elite/Boss names and marks unchanged. This is a lookup microbenchmark, not a device frame-rate claim or complete constructor benchmark. First related run5/7 preserved two historical fixture failures.

Those failures reproduced with the original formatter bytes from370522 (no optimization): `overhead_legacy_baseline/runner_results_adhoc_20260928_013934_586_12988.json`,0/2, errors6. The aggregate wrapper was inside a restoration `finally`; use the runner's actual FAIL rows, not its enclosing shell exit. The original formatter was restored byte-for-byte after this comparison.

Return failure: the read-only trace records ID31's canonical1500ms movement cadence, only383ms elapsed, no granted step/no actual motion. The old fixture incorrectly expected immediate motion. It now waits native physics ticks for real motion, bounded4s, without altering cooldowns, clocks or pending values. The original facing/walk-row/name/health-bar/safe-zone damage assertions remain, plus actual-motion assertion.

Cold activation failure: obsolete MonsterVisual static APIs no longer own streaming. The fixture now calls the real coordinator and establishes map generation before the visual subscribes. The four profiles, asynchronous load, failed-job count, fallback-to-real anchor transition, all-action/all-direction/all-frame alpha checks and stable8px body gap remain. No production fallback was restored.

Actual final related `overhead_legacy_green/runner_results_adhoc_20260928_014117_327_14100.json`:4/4 PASS, native normal exits, no timeout, errors0 (return, cold activation, exact enumeration counterexample, streaming subscription lifecycle). Three repaired/new scenes registered in critical. Earlier related passes include W6 name/rank, species body crown, body admission and actual D3 movement/pressure.

Next: fixed-source AoE frame-pacing and actual constructor trace to quantify complete-path benefit. Full final critical/clean/forge/protection/push/retirement remain NOT_RUN. APK/device NOT_RUN.
