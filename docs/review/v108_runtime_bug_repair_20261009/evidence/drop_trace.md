# v108 mobile zero-drop / logout-failure trace

Status: `BLOCKED` for a device-root-cause claim because the mobile receipt containing the terminal death record is not present in this tree. The static chain does identify the only production failure boundaries and one independent authority coverage defect.

## Authoritative death-to-ground chain

1. `scripts/enemy.gd:7709-7775` captures `death_origin` at the lethal boundary, disables collision and queues `_begin_death`.
2. `scripts/enemy.gd:7800-7830` emits `died` from `_begin_death` after setting `_dying`, stopping physics, and clearing attack state. `scripts/game_root.gd:5376` connects this to `_on_enemy_died`.
3. `scripts/game_root.gd:13609-13765` snapshots the monster and appends one `DEATH_STATE_QUEUED` record to `_pending_enemy_deaths`; it schedules `_flush_enemy_deaths` by deferred callback.
4. `scripts/game_root.gd:13800-13980` drains the queue through a mandatory `death_receipt` scope, then an optional `death_optional` `FrameBudget` scope. The queue head must pass `_death_origin_matches_current` before settlement and before rolling.
5. `scripts/game_root.gd:14172-14310` performs PlayerState settlement. A failed save moves the death to retry and eventually `FAILED`; a map/generation mismatch moves it to `CANCELLED` before any drop roll.
6. `scripts/game_root.gd:14309-14428` calls `LootRuntime.begin_monster_drop_roll_job`/`advance_monster_drop_roll_job` when slicing is enabled, or `roll_monster_drops` otherwise. It converts `items` and `gold_drops` into `drop_plan.requests`.
7. `scripts/game_root.gd:14431-14600` resolves each request's placement, then calls `_spawn_loot` or `_spawn_gold_loot`. A non-finite placement or a false spawn result retries the same request; after `DEATH_QUEUE_MAX_RETRIES` it records `loot_node_materialization_failed` and terminally fails the death.
8. `scripts/game_root.gd:14771-14824` searches the death anchor plus fallback candidates. Every candidate must pass `background.is_environment_actor_blocked`, a world shape query, and a world segment query.
9. `scripts/game_root.gd:14842-14908` creates the pickup, then requires `_loot_pickup_runtime_manager.register_pickup(loot)`. A missing/invalid map projection, invalid world position, null manager, or registration rejection frees the node and returns `false`.
10. `scripts/loot_pickup_runtime_manager.gd:146-190` converts the pickup position through `_screen_to_ground`, registers it in the map-scoped spatial index, and immediately performs the registration collection check. `scripts/game_root.gd:4487-4494` configures this manager only during `_load_zone` and ignores the boolean result.

## Strong static finding: sheet/profile coverage gap

`scripts/layers/runtime/loot_runtime_service.gd:249-280` uses the compiled user sheet as the sole production profile/probability/reward authority. `_production_profile()` calls `_sheet_authority.profile(monster_id)`; an ID absent from the user sheet becomes an empty profile and `advance_monster_drop_roll_job()` returns `dpv2_direct_profile_unresolved` with no requests.

The current authoring data contains 156 canonical/direct baseline profiles but only 126 user-sheet profiles. The 30 IDs absent from the sheet are:

`33, 41, 55, 59, 75, 78, 91, 122, 123, 127, 131, 133, 134, 136, 140, 145, 146, 147, 157, 161, 183, 186, 187, 189, 190, 192, 194, 199, 209`.

Of those, the direct baseline marks 18 as `DIRECT_21CQ` and `drop_enabled=true` (41, 55, 75, 91, 122, 123, 127, 131, 133, 134, 136, 140, 157, 189, 190, 192, 199, 209). They nevertheless resolve to zero drops through the production user-sheet path. Existing `tests/dpv2_drop_runtime_policy_test.gd:137-153` deliberately checks only absent non-loot IDs 145 and 33 and invalid 999999; it does not cover an absent but drop-enabled ID. The existing positive case is only ID 76, which is present in the sheet.

This is sufficient to explain zero drops for any mobile spawn cohort composed of those enabled IDs, but it does not explain logout failure by itself: an empty profile completes with zero requests and can commit cleanly.

## Logout failure and the required runtime evidence

`scripts/game_root.gd:14085-14108` stores every terminal death record. `_last_death_logout_failure` is set when a death reaches `FAILED`, and `_drain_enemy_death_queue_for_logout` rejects safe exit if that ledger is non-empty. Therefore the device receipt must report, per first failed death:

- `state`, `last_error`, `retry_count`, `materialization_retry_count`
- `transaction_result.reason`
- `drop_plan.roll.reason`, `drop_plan.roll.configured`, `drop_plan.roll.source_entry_count`, `drop_plan.roll.items`, and `gold_drops`
- `remaining_request_count`, `death_origin` map/generation, current map/generation
- placement search completion/position and `loot_manager_registration_checks`
- `death_queue_cancelled_count`, `death_queue_materialization_failures`, `death_queue_failed_count`, `drop_roll_count`, `drop_request_count`, and `drop_node_spawn_count`

Interpretation is deterministic:

- `dpv2_direct_profile_unresolved` with no requests: authority/profile coverage problem; no placement or manager failure.
- `origin_map_generation_mismatch_*`: deferred death crossed a map generation; it is an intentional fail-closed cancellation, but it cannot be presented as a dropped death.
- `spb_effective_probability_fail_closed` or another roll reason: authority validation/reward resolution failure before placement.
- `loot_node_materialization_failed` after retries: inspect whether placement returned `Vector2.INF` or manager registration returned `false`; this is the direct common cause of zero ground nodes plus logout refusal.
- `save_failed`/`death_queue_no_progress`: settlement or optional budget lifecycle failure before rolling.

## Minimum complete repair and regression scope

1. Preserve the existing fail-closed authority contract. Add a formal data test covering every runtime-spawn-allowed, drop-enabled canonical ID and asserting the production sheet/profile resolves non-empty slots. Either compile the missing enabled rows into the user sheet through its authoring generator or explicitly mark them non-runtime-spawnable in the authoritative spawn source; do not fall back to retired probability data at runtime.
2. Add a real GameRoot death scene using the production map bootstrap and manager wiring. Kill one sheet-present monster, one absent-enabled monster, and one gold-producing monster; let the normal deferred queue drain over actual process frames. Assert roll reason, request count, placement completion, manager registration, node spawn, queue commit, and safe logout.
3. Add a forced real map/projection readiness boundary only if the device receipt identifies it: `configure_map()` currently returns `bool` at `scripts/loot_pickup_runtime_manager.gd:90-121`, but `_load_zone` ignores that result at `scripts/game_root.gd:4487-4494`. A production repair must either prove the callback is ready before deaths are admitted or retain the death request until the real map binding is ready; it must not silently convert registration failure into a terminal drop loss.
4. Do not classify a zero RNG result as the mobile bug. The first failing death's retained roll/queue record is required to distinguish probability zero, profile absence, origin cancellation, settlement failure, placement failure, and manager rejection.

## Existing coverage gap

The direct DPV2 contract test validates one positive sheet profile and two expected zero profiles. It does not exercise the actual Enemy `died` signal, deferred GameRoot queue, PlayerState settlement, map-scoped placement, pickup registration, or logout drain. The APK payload verification proves assets are packaged, but it does not prove the runtime authority loads, the death queue commits, or a ground node registers on a device.

## Natural-frame versus test-pump finding

The production path is process-driven: `scripts/game_root.gd:1871-1914` calls `_pump_enemy_death_work_queue()` once from `_process`, while `scripts/game_root.gd:13767-13778` only schedules the first pass with `call_deferred("_flush_enemy_deaths", true)`. A normal pass first charges the necessary `death_receipt` scope and then admits at most one optional `death_work` scope (`scripts/game_root.gd:13798-13830`). `_death_optional_pump_frame` prevents another optional admission in the same process epoch (`13817-13827`); a denied optional scope leaves the queue pending and republishes its FrameBudget owner (`13833-13840`). Thus a real `GameRoot.set_process(false)` or a permanently ineligible owner can strand work and later make `_last_death_logout_failure` block safe logout, even though a synchronous test pump drains it.

The existing slicing contract intentionally disables `GameRoot`, every enemy, the pickup manager, and the player at `tests/crowd_death_roll_slicing_contract_20261009.gd:158-180`, then calls `_pump_enemy_death_work_queue()` directly at `218-240`; its natural phase later re-enables only `GameRoot` and waits for actual process frames at `198-216`. That fixture is useful for roll equivalence, but its initial manual phase cannot expose production process-owner eligibility, manager processing, or deferred callback ordering. The older queue tests use the same disabled/manual pattern (`tests/death_drop_budget_queue_test.gd:55-67, 153-154`). This is a coverage limitation, not evidence that the production queue itself fails.

`LootPickupRuntimeManager.configure_map()` returns `_refresh_player_ground()` (`scripts/loot_pickup_runtime_manager.gd:86-108`). The only false branches are an invalid player (`461-466`), an invalid/non-finite canonical projection (`469-480`), or a missing projection callable; with a mapped runtime ID it deliberately refuses the delta fallback. `_load_zone()` calls it at `scripts/game_root.gd:4487-4493` but discards the boolean. Therefore a false result can leave the manager configured yet unable to register every pickup; `_spawn_loot`/`_spawn_gold_loot` then free the node and retry (`scripts/game_root.gd:14842-14908`). The first retained death record must distinguish this from queue starvation by recording the manager result and projection rejection reason.

The APK line-ending/source-hash hypothesis is unlikely to explain an all-profile zero result. `scripts/drop/user_loot_sheet_provider.gd:47-72` reads the sheet, normalizes CRLF to LF for JSON parsing, and only validates that the declared `source.sheet_sha256` is a 64-hex string; it does not compare that declaration with the packaged file. A malformed/missing sheet would make `_sheet_authority.valid` false and return `user_loot_sheet_authority_unavailable` (`scripts/layers/runtime/loot_runtime_service.gd:89-94`), but ordinary CRLF versus LF does not. The direct GameData manifest hash checks at `scripts/game_data.gd:605-658` cover the separate direct baseline artifacts, not the user sheet used by LootRuntime. This must be verified from the first device roll reason, not inferred from APK text encoding.
