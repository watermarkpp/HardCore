# Shared budget epoch increment — scoped review

Parent: `e7b3e06c53fb5ec2c4c84c321f0fec6725b4564c`.
Native content: `a607400e0d745852ac41e8bbbfc5d169ecc916e71fe9c5e286a118a0673211ca`; 3566 fingerprinted source files.
Console engine SHA256: `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`. Full engine identity, native source ZIP hash and size are in `SCOPED_EVIDENCE.json`.

This increment fixes unused optional allowance being withheld by a resource owner which already completed its once-per-process poll. It also supplies stable same-phase production API input for the strict expiry/death boundary. Scoped gates PASS; overall framework/R3, integration, APK and device acceptance remain NOT_RUN on these bytes.

## Production change and exact guarantee

Only `scripts/layers/runtime/execution/frame_budget.gd` changes production behavior. Eligible owners not yet served in the actual epoch retain oldest-service-first admission. An owner already served in that epoch does not withhold residual allowance from an available caller. The next actual epoch restores priority using preserved service ages/sequences. This is **first-service fairness plus opportunity use**, not equal shares or strict round-robin. An explicit two-owner case records 1:9 throughput per epoch while both receive service. No owner is permanently removed; resource submissions can still acquire a same-epoch real callback.

The original 1200us optional budget, one actual Engine process epoch, in-flight accounting, nested outer-only total, legal atomic overrun, necessary callbacks, pause and owner lifetime guards remain. Denials retain their original total plus budget/fairness/unrunnable counts and one scalar last-denial record per category/epoch; there is no growing hot-path sample log. Pending categories and this ledger are not effect receipts or journal identities.

The frozen resource coordinator, Player timers, Root simulation/pump order, period, duration, capacity, HP/planner/writer authorities and target count are unchanged relative to the parent. No business ID is added.

## Native cause, RED and GREEN

`BUDGET_DENIAL_FINAL_RED_RECOMPUTED.json` contains 16 bounded observations of an actual already-polled resource blocker in the same epoch. One records 88 due states, 665us remaining, resource poll epoch277 and a fairness denial to effects after their first quantum. Native old-rule delivery lateness remains2966667us and the strict original-period gate FAILs. Physics observations also retain preceding-epoch blocks. This supports the budget-stranding mechanism; it does not attribute every expensive quantum to fairness.

Earlier 51-check RED has3 failures. The expanded69-check RED has5 failures. Final direct unit code adds24 callback permutations, detach/queued-free/readd and an explicit unequal-share case;126 checks PASS. Every old failure is retained under its own source fingerprint. Only the rows in `SCOPED_ACCEPTED_ROWS.json` are adopted for these bytes: 118 successful native attempts, 98 unique scenes; 42 full framework receipts with 3354 checks. Attempt count is not unique scene count.

Final groups: budget/producer/actual-lateness/world-retirement/paused-persistence5, the original streaming suite13, the selected critical list80, and10 strict overlap live/cold pairs. The unit includes new same-epoch pending work, rejected resource later getting a turn, continuing effect pressure with resource/death/save service, all24 four-owner callback orders under one over-budget atomic quantum per epoch, preserved age, nesting and lifecycle boundaries. It does not promise equal throughput or finite wall-clock latency for arbitrary unbounded necessary work.

## Strict time boundary and wall-clock scope

`death_burst_lifecycle_test.gd` emits both complete Root inputs from its explicit process callback after Root. For overlap, the original state's4s duration is checked to be exactly240 fixed60 steps. Actual inputs and actual `Player.skill_requested` signals record process/physics frames and simulation clock. Original expiry must strictly equal death snapshot; due backlog must independently be nonempty; actual delivery must remain less than the unchanged1s period. No tolerance, synthetic Batch, HP rollback, extra pump or alternate clock is introduced. Player's production method is `_emit_skill_after_windup`.

Godot fixed_fps returns before OS frame delay. Test-owned wall pacing waits only with no open scopes, records real monotonic intervals and retains original timers/delta/TPS/scale. It is limited to two stationary disjoint-receiver boundary fixtures, not natural movement, CPU/GPU performance or Android proof. Full burst still requires90 states/360 deliveries; overlap reports only actual delivered work plus expiry/death invalidation. Live materialized ground-node counts and450XP cold restore are distinct; cold does not build a world or prove ground-drop recovery. Generation scope here does not replace the earlier nonempty production generation test.

## Existing streaming fixture correction

The original single-poll test fails with both old and candidate budgets. Setup probe records necessary startup persistence spending4700us in epoch0 against the unchanged1200us allowance. Its synthetic frame loop calls into that exhausted epoch twice, obtains598 polls for600 requested frames, then fails its exact-count gate. Necessary work is properly charged and optional polling properly refuses.

Only `tests/monster_streaming_single_poll_per_frame_test.gd` changes: measure after actual Engine epoch transition, use actual process frame IDs, and additionally call twice per epoch to assert no duplicate heavy poll. All original1/100/300 receivers and600/180/120 sampling frames remain, as does exact one poll per sampled epoch. No ledger reset, allowance increase, delayed production poll, workload reduction or frozen coordinator edit. Old failure, old-budget comparison and setup probe are separately preserved; final13 original streaming scenes PASS.

## Source and evidence transport

Four source/test paths differ from the parent; only the shared budget is production. `NATIVE_DELTA_MANIFEST.json`, source ZIP, `SOURCE_INCREMENT.zip`, raw native logs, complete receipts, handoffs, commands and before/after fingerprints are provided. Stage preimages and original Pro report are separately zipped. `RUN_INDEX.json` explicitly identifies different-byte stages and preserved failures; they cannot be promoted to final results. The independent Git index verifies every source/supplemental blob as exact native bytes or CRLF-to-LF, and preserves construction HEAD/index. Mainv97, second tree and real userdata are not modified by this increment.

## Remaining work and limits

Full final-byte natural P6/R3 movement/combat/recovery, remaining regressions, crash-boundary repeats and final ABBA are continuing independently. Earlier E/F successful records remain at their own fingerprints, not acceptance of this content. CPU-only ABBA movement fixtures, frame-interval exceptions and fixed-step boundary statistics must retain distinct scope. Original v97B input remains MISSING; physical power loss, external valid old primary replacement, Android/GPU/thermal and main integration/APK remain separate. No new30-target gameplay limit, no AOE truncation or equal-budget contract is adopted.
