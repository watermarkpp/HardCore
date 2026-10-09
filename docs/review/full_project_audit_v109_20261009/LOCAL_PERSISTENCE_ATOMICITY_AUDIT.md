# Local Persistence Atomicity Audit (v109)

**Scope:** local source audit only. No engine, test, crash injection, or data mutation was run for this note.

**Source fingerprint:** requested fixed source `ba97849bfe3a9fe11f12904bfa26b41fc8c7f06a` (`Preserve Android build preflight sources and bind whole-project audit scope`). The checkout is a dirty integration tree at `215f0b2f651a51e6855ee813ddd99221690311a1`; the production files below were read from the current checkout. Their current SHA256 values are recorded here so this report does not silently treat the historical commit as the live file image:

| file | current SHA256 |
|---|---|
| `scripts/json_persistence_service.gd` | `581D09246EF6E9991C35BB3563C90FD4F4CF3A098F56BB95D31B5A543DCD06C0` |
| `scripts/json_persistence_job.gd` | `8C016948356196EC7D777585B1E303F431AEAC84F58F25A16CC44CB742757242` |
| `scripts/player_state.gd` | `13CCCB4CFF55EDA54C858C69EA8A0DA16C33AF44F19EC43B7199CF3DDF4D80A6` |
| `scripts/game_root.gd` | `D3ED6E93748C131106E589E84E08E01E22A94C6A8509D5219C283281F071D694` |
| `scripts/loot_pickup_runtime_manager.gd` | `EA5DA023EB5A1BBCFA3951EDC1B1058A5AAE9ACD305D958E069402C19B5AF36B` |
| `scripts/loot_pickup.gd` | `945E0A8A924237B5D6CCA1CA65352B914BAD27095E252713F72843C5A616CED2` |

## Ownership and formal chains

| domain | state owner | durable boundary | post-boundary in-memory work |
|---|---|---|---|
| death XP/quest/respawn | `PlayerState` plan; `GameRoot` queue/state | one create-only world-clock death event | drop roll, item-instance creation, placement, node materialization |
| JSON promotion | `JsonPersistenceService` + `JsonPersistenceJob` | verified temporary -> primary rename and backup rotation | owner callback consumes receipt |
| ground pickup | `GameRoot` queue and `PlayerState` inventory plan | profile JSON promotion | `LootPickup.confirm_collect()` and node retirement |
| logout | `GameRoot._prepare_safe_logout` | final `PlayerState.save_safe_logout` | no gameplay work is accepted after the drain succeeds |

The shortest death chain is `Enemy` death signal -> `GameRoot._queue_enemy_death` (around line 13718) -> `_settle_pending_enemy_death_batch` (14181) -> `PlayerState.prepare_death_settlement` (2813) -> `JsonPersistenceService.submit` (44) -> worker `PREPARE/READ_PREVIOUS/PROMOTE` -> `_complete_background_death` (2872) -> `DEATH_STATE_SETTLING` in `_finish_enemy_death_settlement_batch` (14284) -> `_plan_enemy_death_item` (14331) -> `_materialize_enemy_death_nodes` (14450) -> `_commit_enemy_death_item` (14610).

The shortest pickup chain is `LootPickup` collection signal -> `GameRoot._queue_loot_collection` (14946) -> deferred `_flush_loot_collections` (15002) -> `PlayerState.prepare_loot_save` (8887) -> `JsonPersistenceService.submit` with `prepare_only=true` (8923) -> `_poll_prepared_loot_collection` (15062) authorizes or cancels -> `PlayerState._complete_background_loot` (8945) -> `_finish_loot_collection_outcomes` (15115) -> `LootPickup.confirm_collect` (15139). The pickup itself carries only `_collection_pending`, not a durable transaction record.

## What is proven in the current source

### Async writer success, failure, and reentrancy

`JsonPersistenceService.pump` refuses a second pump while `_pump_active` (104-130), and `finish(wait=true)` returns `writer_reentrant_barrier` while the callback is being consumed (251-264). `_complete` writes the immutable response, marks the job finished, removes the queue head, then invokes the owner callback (311-334). This ordering prevents a callback from seeing an uncommitted queue entry and prevents the callback from being run by a worker.

`JsonPersistenceJob._promote` verifies the temporary bytes and both previous primary/backup byte images before moving anything (186-239). It rotates the previous primary to `.bak`, renames the temporary into the primary, verifies readback, and attempts rollback/quarantine on failure. A normal promotion failure returns `success=false`; no owner reward callback is supposed to apply that result.

For a death save failure, `_finish_enemy_death_settlement_batch` restores the captured world mutation only when a synchronous mutation snapshot exists, increments retry state, and eventually records `DEATH_STATE_FAILED` (14284-14321). The asynchronous path deliberately calls `_prepare_queued_enemy_respawn(death, false)` so world state is not applied before the durable receipt. `PlayerState._complete_background_death` applies XP, quest state, and respawn changes only after a successful receipt and only while the profile/generation still matches (2872-2911). This is the source basis for the v108 `PERSISTING -> SETTLING` repair; `CURRENT_RESULT.md` and `INDEPENDENT_REVIEW_FOLLOWUP.md` record the related local/native PASS evidence without upgrading it to crash recovery.

For loot, `_complete_background_loot` applies inventory/gold only after a successful promotion and checks profile/generation/write-generation context (8945-8994). Failure converts successful simulated outcomes to `save_failed`; request-context cancellation is requeueable. `_finish_loot_collection_outcomes` confirms a pickup only for a successful outcome and requeues unacknowledged tail outcomes instead of dropping them (15115-15173).

### Map changes and exit

`GameRoot._cancel_pending_enemy_deaths_for_generation_change` cancels a prepared writer before compacting old-origin deaths (14129-14146). If promotion has already started, the writer refuses cancellation and the code consumes the real receipt instead of fabricating cancellation. The death request guard includes profile/generation and the frozen origin guard (2860-2863), so a receipt from an old role cannot mutate the current role.

`GameRoot._prepare_safe_logout` drains deaths first, then pickup-manager and pickup transaction queues, then calls `PlayerState.save_safe_logout` (2750-2790). `_drain_enemy_death_queue_for_logout` treats a still-running queue as `safe_logout_death_queue_pending`, while only `DEATH_STATE_FAILED` enters `_last_death_logout_failure` (2885-2940). `_drain_loot_collection_queue_for_logout` rejects unresolved manager/projection or collection work rather than writing a misleading successful logout (2798-2849). This preserves the v108 pending-latch repair: temporary pending is retryable; a real terminal failure remains blocking.

The current evidence is bounded. `f03_native_death_lifecycle_test.gd` covers prepared receipt, generation cancellation, teardown, and reload assertions; `safe_logout_pending_retry_repair_20260909.gd`/`20261009.gd` covers pending retry and exactly-once terminal behavior; `death_natural_process_repair_20261009.gd` covers a test_mode=false natural death through durable receipt, materialization, and logout; `loot_accepted_movement_test.gd` and `loot_continuous_cohorts_test.gd` cover accepted movement and retry/FIFO. The v108 records classify these as PASS for their executed contract. None injects a process kill at each worker stage or proves Android/power-loss recovery.

## Findings

### P1 — durable death receipt can outlive the in-memory drop plan (inferred, concrete loss boundary)

**Source:** `PlayerState._complete_background_death` applies the durable event and clears `_background_death` at `scripts/player_state.gd:2872-2911`; `GameRoot._finish_enemy_death_settlement_batch` moves the death to `SETTLING` at `scripts/game_root.gd:14284-14321`; only later does `_plan_enemy_death_item` create the runtime drop plan at `scripts/game_root.gd:14331-14442`. The durable document generated at `player_state.gd:2845-2847` contains level/experience/quests/world delta, but no drop roll, item records, gold rolls, placement cursor, or death queue record.

**Trigger chain:** durable world event promotion succeeds -> receipt callback applies XP/quest/respawn -> process terminates before `_plan_enemy_death_item`, or during `_materialize_enemy_death_nodes` -> restart loads the profile/world event through `_read_world_clock_replay` (`player_state.gd:5392-5440`) -> the event is replayed, but there is no persisted drop job to resume.

**Assessment:** the source proves XP/quest/world replay, but it does not prove drop replay. This is an inferred P1 loss boundary for a product contract that treats a death's ground reward as part of the reward. It is not a claim that a crash was observed; the existing v108 tests do not kill the process between receipt and drop materialization. A normal uninterrupted run can PASS while this boundary remains open.

**Minimum verification:** an isolated process-interruption matrix at (a) after world-event PROMOTE before owner callback, (b) after callback before first drop roll, (c) after roll before first node, and (d) between materialization nodes. Restart with the same profile and map must compare XP, respawn state, item instance IDs, gold, and ground-drop receipts exactly once. If the contract intentionally allows drops to be lost after a saved death, document that as an explicit product rule; otherwise persist a replayable drop intent/result before applying the XP event or add a durable post-receipt death record. Do not use a second RNG authority.

### P1 — accepted pickup has no durable source when the process stops before profile promotion (inferred, concrete loss boundary)

**Source:** `GameRoot._queue_loot_collection` admits a live `LootPickup` and stores it only in `_pending_loot_collections` (`game_root.gd:14946-15001`). `_flush_loot_collections` moves the candidate to `_prepared_loot_collection` and `PlayerState.prepare_loot_save` (`game_root.gd:15002-15055`, `player_state.gd:8887-8935`). `LootPickup` only stores `_collection_pending` and clears it on confirm/reject (`loot_pickup.gd:32`, `363-386`). No pickup ID, source item record, or pending collection is included in the profile save payload by this path.

**Trigger chain:** pickup is accepted and marked pending -> process terminates before profile PROMOTE -> in-memory node/queue disappears -> restart loads profile without the item and has no persistent ground-loot transaction to replay. The opposite ordering (promotion succeeds, then process terminates before `confirm_collect`) can leave the item already in inventory while the old node is gone; that is safe against duplication but is also untested.

**Assessment:** this is an inferred P1 item-loss boundary for abrupt process interruption. Safe logout is protective only when it runs; `_prepare_safe_logout` cannot run for a kill, native crash, OS termination, or power loss. Existing pickup PASS evidence proves ordinary async success/retry/FIFO, not crash recovery.

**Minimum verification:** kill/restart at pre-PROMOTE, post-PROMOTE/pre-callback, and post-confirm points; verify profile inventory, item instance ownership, pickup node/source identity, and retry behavior. Either persist accepted ground loot in a replayable world-lifecycle journal or explicitly define accepted-but-unsaved pickup as cancelable before promotion. The test must prove no duplicate item instance and no lost accepted item under the chosen contract.

### P2 — multi-file commit is ordered but not a crash-atomic transaction across profile/index/world cleanup

**Source:** `PlayerState.save_game` promotes the profile, then updates `_profile_saved_death_event_sequence`, queues world-clock cleanup, and updates the profile index (`player_state.gd:6597-6637`). Background profile completion separately submits the profile index after profile promotion (`player_state.gd:10146-10216`). World checkpoint and cleanup are separate jobs (`player_state.gd:5524-5559`, `5590-5670`).

**Trigger chain:** profile promotion succeeds -> process terminates before index promotion or world checkpoint/cleanup -> restart sees a new profile but old index, or a durable event plus old checkpoint/cleanup state.

**Assessment:** source has validators, backups, sequence watermarks, and replay checks; `_read_world_clock_replay` rejects gaps and replays event files. That is strong recovery scaffolding, but no single commit marker spans profile, index, world snapshot, and cleanup. The source cannot prove power-loss durability because worker `flush()` and rename sequences are not exercised under interruption in the retained evidence. This is P2/MISSING validation, not a demonstrated corruption.

**Minimum verification:** kill at every rename boundary and reload with primary/backup/index/event-directory combinations. Require either a consistent recoverable state or an explicit recovery status; retain quarantined files and never silently delete an event needed to bridge a sequence.

### P2 — prepared pickup cancellation is safe in-memory, but post-promotion lifecycle is only conditionally observable

**Source:** `_poll_prepared_loot_collection` validates origin, pickup validity, and pending state before finishing; if cancellation is accepted it requeues with `pickup_origin_changed`, otherwise it consumes the real receipt (`game_root.gd:15062-15114`). `_complete_background_loot` can mark `saved=true, active_state_applied=false` when profile/generation changed after promotion (`player_state.gd:8960-8977`).

**Assessment:** this avoids a false cancellation and avoids applying an old profile receipt to a new role. However, after the durable profile has already received the item, the old pickup node may no longer be live and no explicit cross-session receipt ledger is emitted for the UI/world cleanup. The source path is safe against duplicate inventory application but lacks a crash/reload proof that the old ground node cannot be regenerated or that a failed visual cleanup cannot confuse a second collection.

**Minimum verification:** change map/profile after PROMOTE but before callback, then reload; assert the durable inventory owns the exact instance once and the old pickup is rejected/retired exactly once. Keep this separate from the ordinary movement/FIFO tests.

### P2 — callback reentrancy is guarded, but owner callbacks are not an external receipt journal

**Source:** `_complete` removes the service queue entry before calling `on_complete` (`json_persistence_service.gd:311-334`), and `finish(wait=true)` returns a barrier during `_pump_active` (`251-264`). Owner plans are in-memory dictionaries (`player_state.gd:2831-2864`, `8899-8935`).

**Assessment:** same-process reentrancy is explicitly guarded and existing tests cover the barrier. A process stop after promotion but before callback has no in-memory plan/callback replay mechanism; recovery therefore relies on the profile/world event path where one exists, and has no equivalent path for pickup plans or post-receipt drop plans.

**Minimum verification:** a fault-injection harness must record phase-specific receipts externally, restart the service, and assert each owner either consumes the durable result or reconstructs a safe retry. Do not treat a callback-count assertion as crash recovery.

## Validation matrix

| boundary | current source/evidence | status | gap |
|---|---|---|---|
| normal async death receipt, reentrancy barrier | `f03_native_death_lifecycle_test.gd`; v108 evidence | PASS (bounded) | no forced process stop |
| death failure/retry/terminal logout latch | `safe_logout_pending_retry_repair_20261009.gd`; v108 evidence | PASS (bounded) | no crash during worker failure/rollback |
| natural test_mode=false death -> drop -> logout | `death_natural_process_repair_20261009.gd`; v108 evidence | PASS (bounded) | no restart between receipt and drop |
| pickup async success, movement, retry/FIFO | `loot_accepted_movement_test.gd`, `loot_continuous_cohorts_test.gd` | PASS (bounded) | no restart before/after profile promotion |
| death event replay after process kill | `_read_world_clock_replay` exists | MISSING | no kill/restart evidence |
| drop replay after saved death | no durable drop plan/record in source | MISSING | contract decision and implementation/verification required |
| pickup replay after accepted pre-promote kill | no durable pending pickup source | MISSING | contract decision and implementation/verification required |
| profile/index/world rename crash matrix | backup/replay code exists | MISSING | no interruption evidence |
| Android/OS power-loss durability | no device evidence in v108 docs | NOT_RUN | requires device-specific acceptance |

## Scope conclusion

The v108 persistence fixes are real for the tested uninterrupted lifecycle: prepared death receipts now leave `PERSISTING`, failures remain retryable/terminal as specified, and pickup cohorts preserve order without duplicating an acknowledged outcome. The remaining atomicity boundary is process interruption: the death event journal can recover XP/quest/respawn state, while the subsequent drop plan is runtime-only; accepted pickup state is also runtime-only until profile promotion. These are concrete validation/contract gaps, not evidence to relabel the retained PASS records. No production change was made by this audit.
