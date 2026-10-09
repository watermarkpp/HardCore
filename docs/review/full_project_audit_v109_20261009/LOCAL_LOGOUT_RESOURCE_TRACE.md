# LOCAL_LOGOUT_RESOURCE_TRACE 2026-10-09

## Scope and evidence

This is a read-only audit of `direct05_logout` for `safe_logout_pending_retry_repair_20261009`. No engine rerun was performed (`NOT_RUN`). The source reviewed here is bound to the candidate `dbd78d3301c2af6cfd9e070abe8cc847e6353175`; the runner's checkout HEAD `215f0b2f651a51e6855ee813ddd99221690311a1` is only historical checkout metadata, not the tested dirty-source identity. The direct05 source/input fingerprint and final scoped binding preserve the actual test-stage identity. Evidence:

- `outputs/wake_drop_v108_review_followup_20261009/direct05_logout/runner_results_adhoc_20261009_213007_578_840.json`: functional result `PASS`, native exit `0`, engine error count `0`.
- `outputs/wake_drop_v108_review_followup_20261009/direct05_logout/safe_logout_pending_retry_repair_20261009.stdout.log`: 44 checks, reentrant pending path, outer/third logout success marker.
- `outputs/wake_drop_v108_review_followup_20261009/direct05_logout/safe_logout_pending_retry_repair_20261009.stderr.log`: `13 ObjectDB instances were leaked at exit`; `3 resources still in use at exit`.
- The same warning is reported for the older `death_queue_lifecycle` run by the handoff, so the 3-resource count is not attributable to this fixture from the available evidence.

The warning is therefore a real exit-lifecycle defect signal even though the test result is PASS. It must not be folded into the functional PASS.

## Concrete fixture-owned reference

`tests/safe_logout_pending_retry_repair_20261009.gd:47` constructs `LootRuntimeScript.new()` and immediately calls `roll_monster_drops`. `scripts/layers/runtime/loot_runtime_service.gd:1` declares that script as `extends Node`, while `project.godot:40` also installs the same script as the `LootRuntime` autoload. The object made at line 47 is a second, unparented Node. It is never added to a tree and never freed. This is a definite fixture-owned ObjectDB leak candidate. The minimal repair is to bind it and explicitly free it after the preview call, for example `var preview_service := LootRuntimeScript.new()` followed by `preview_service.free()` after the assertions. `queue_free()` would be insufficient for an unparented object when the fixture is exiting immediately.

The preview is otherwise a useful authority availability check; replacing it with the autoload would remove the extra Node but would change the isolation of the check. Explicit `free()` is the smaller semantic change.

## GameRoot and death-object ownership

The production death path is real and reached in this run:

- `scripts/game_root.gd:13618` `_on_enemy_died` accepts the actor snapshot and queues the death work.
- `scripts/game_root.gd:13807` `_pump_enemy_death_work_queue` owns the reentry guard and settlement pump.
- `scripts/game_root.gd:14284` `_finish_enemy_death_settlement_batch` stores the transaction result and moves a successful death to `SETTLING`.
- `scripts/player_state.gd:2872` `_complete_background_death` applies the formal reward plan, clears its background plan, then emits `profile_changed` at line 2908. The fixture's reentrant callback is intentionally connected to this signal.
- `scripts/game_root.gd:1792` `_exit_tree` clears providers, pending warm work, prepared loot collection, and gameplay ownership. It does not retain the fixture's unparented preview Node.
- `tests/safe_logout_pending_retry_repair_20261009.gd:183-201` creates both `EnemyActor` objects and attaches them to `_game`; line 269 queues `_game` for deletion and line 273 waits one process frame. Since both actors are descendants of `_game`, this is the correct ownership path and is not evidence of an unparented actor leak by itself.
- `scripts/enemy.gd:6360` `_exit_tree` cancels decision work, attack state, entrapment, and spatial-index registration. This supports the conclusion that the two fixture actors should be reclaimed when the parent world is freed.

The terminal dictionary is copied at `tests/safe_logout_pending_retry_repair_20261009.gd:241`; it contains serialized dictionaries and strings (the receipt confirms no Node/ObjectID field). It is not retained after `_run` and does not explain an ObjectDB leak.

## Loot manager and resources

`GameRoot` constructs the production `LootPickupRuntimeManager` at `scripts/game_root.gd:1655-1659` and attaches it as a child. The manager owns a `RuntimeLootSpatialIndex` RefCounted object (`scripts/loot_pickup_runtime_manager.gd:29` and `scripts/runtime_loot_spatial_index.gd:2`). Parent teardown should release this child and its RefCounted index. The manager's weak pickup registry (`scripts/loot_pickup_runtime_manager.gd:39`, cleanup paths around lines 111-204) does not hold strong pickup references.

The three-resource warning cannot be mapped to a specific resource because the captured stderr was not produced with Godot's verbose ObjectDB/resource identity dump. Both this run and the older death-queue run report three resources, so the available evidence points to shared main-world/resource-cache teardown rather than the new reentrant fixture. This remains `BLOCKED` for exact attribution. A single verbose reproduction is required to identify resource paths; no such reproduction was run here.

## Findings

1. **FAIL (fixture cleanup):** the unparented `LootRuntimeScript.new()` at test line 47 is a concrete leaked Node candidate and should be explicitly freed. This is the only direct source-level leak found in the owned fixture.
2. **PASS (death ownership static review):** both temporary enemies are parented to `_game`; `_game.queue_free()` plus one frame and `Enemy._exit_tree` cleanup are coherent. No static evidence supports adding manual `free()` to these children, which could double-manage the production death path.
3. **BLOCKED (remaining ObjectDB count):** the warning is 13 rather than the one known preview service, so at least 12 instances cannot be identified from aggregate stderr. Verbose ObjectDB output is needed before claiming the entire warning is fixed.
4. **BLOCKED (3 resources):** repeated count across the older death-queue test suggests shared bootstrap/resource-cache lifetime. Exact ownership is not proven by current logs.

## Minimal verification needed

After explicitly freeing the preview service, run this test once with Godot verbose object/resource cleanup enabled and an isolated runtime appdata directory. Compare the ObjectDB/resource identities against the current 13/3 baseline. Keep the functional assertions and 30-second limit unchanged. If the remaining objects are main-scene children, inspect their owner/exit path; if they are autoload/resource-cache objects, record them as shared teardown evidence rather than changing gameplay cleanup.

Status: functional test `PASS`; source attribution `PASS` for one fixture leak; full leak closure `BLOCKED`; new verification `NOT_RUN`.

## Follow-up direct10 cleanup and verbose result

The owned fixture was minimally changed at line 47 to retain the preview service in a local `Variant` and call `free()` after the formal preview assertions. The runner received one default-off `[switch]$Verbose`; when set, it adds Godot `--verbose` on both Windows and Linux launch paths and does not change timeout, clock, receipt, or failure parsing.

The isolated run used the private index rooted at `dbd78d3301c2af6cfd9e070abe8cc847e6353175`, a separate runtime appdata directory, and `-TimeoutSeconds 30 -Verbose`. Evidence:

- `outputs/wake_drop_v108_review_followup_20261009/direct10_logout_cleanup/logs/runner_results_adhoc_20261009_220313_246_19196.json`: `PASS`, native exit `0`, `engine_log_errors: 0`, pass marker present.
- `outputs/wake_drop_v108_review_followup_20261009/direct10_logout_cleanup/logs/safe_logout_pending_retry_repair_20261009.stdout.log`: `SAFE_LOGOUT_PENDING_RETRY_REPAIR_PASS checks=44`.
- `.../safe_logout_pending_retry_repair_20261009.stderr.log`: no resource warning; five verbose identities remain:
  `RefCounted:9223372906904426219`, `9223372906921213228`, `9223372906937990445`, `9223372906954767662`, and `9223372906971544879`.
  Godot reports each with reference count zero and the generic removed-node hint.

This is a measurable cleanup result: the prior direct05 aggregate was 13 ObjectDB and 3 resources; direct10 is 5 ObjectDB and 0 resources after freeing the preview Node. The reduction is consistent with the unparented preview service retaining its nested authority objects and resources. Functional behavior stayed unchanged at 44 checks/pass.

Static ownership maps the remaining five zero-reference `RefCounted` candidates to the world teardown closure rather than the preview fixture: `GameRoot` owns `_world_context` (`scripts/game_root.gd:9`), `_time_domains` (`:10`), `_world_bootstrap_coordinator` (`:478`), and `_feature_target_bound` (`:15496`); its child `LootPickupRuntimeManager` owns `_spatial_index` (`scripts/loot_pickup_runtime_manager.gd:27`). Their classes are RefCounted (`world_context.gd:1`, `time_domains.gd:1`, `world_bootstrap_coordinator.gd:2`, `world_target_bound.gd:1`, `runtime_loot_spatial_index.gd:2`). This is a bounded candidate set, not proof of identity because the engine prints instance IDs only and no script paths.

Status after direct10: fixture cleanup `PASS`; business contract `PASS`; remaining five production teardown candidates `BLOCKED` for exact identity; resource warning closure `PASS`; repeat functional verification `NOT_RUN` beyond this required direct10 run. No production source was changed.

Current changed-file SHA256:

- `tests/safe_logout_pending_retry_repair_20261009.gd`: `E6603BC8343938ECD6290A5BB38D6E883AC6641D7B70EA74C0BCFB4DC5D2A249`
- `tools/run_godot_tests.ps1`: `7942F83AF625A03BD44A3891F627136E2D3299404C44E5E8BF8ED798FEE0906B`

## direct11 identity follow-up

To avoid treating the aggregate count as an attribution, the fixture was instrumented only with scalar diagnostics before teardown. It records signed `Object.get_instance_id()` values as strings (the IDs exceed JSON's exact integer range), script resource paths, class names, and labels for explicit `GameRoot`, `PlayerState`, `LootRuntime`, `GameData`, manager, and both temporary EnemyActor members. No object reference is retained by the diagnostic.

The clean direct11 run used a newly cleared isolated runtime appdata directory and the private `dbd78d3301c2af6cfd9e070abe8cc847e6353175` index. It completed the 44 checks with native exit `0`. Receipt:

- `outputs/wake_drop_v108_review_followup_20261009/direct11_logout_identity/receipt_16532461_15644.json`
- `outputs/wake_drop_v108_review_followup_20261009/direct11_logout_identity/logs/safe_logout_pending_retry_repair_20261009.stdout.log`
- `outputs/wake_drop_v108_review_followup_20261009/direct11_logout_identity/logs/safe_logout_pending_retry_repair_20261009.stderr.log`

The final stderr contains five leaked IDs:

`9223372905881016043`, `9223372905897803052`, `9223372905914580269`, `9223372905931357486`, `9223372905964911920`.

Exact decimal comparison against every captured pre-teardown GameRoot, PlayerState, LootRuntime, GameData, manager, and EnemyActor ID found no match. The diagnostic therefore closes the earlier overclaim: the five leaked instances cannot be assigned to the listed world members from this run. Those members are static examples of RefCounted ownership, not a bounded identity set. The remaining leak is `BLOCKED` for source attribution. The earlier preview-service attribution remains confirmed by the 13-to-5 and 3-to-0 reduction.

The first identity rerun on the reused runtime directory failed early because the generated character name already existed; that evidence is retained. The final run used a cleared runtime directory and passed. No business assertion was weakened.

Updated source hashes:

- `tests/safe_logout_pending_retry_repair_20261009.gd`: `87E0776F35BE7D02BFC2D0F279F9984D2FBFBEAB3A384A8CC42D8DDD57F0BC71`
- `tools/run_godot_tests.ps1`: `7942F83AF625A03BD44A3891F627136E2D3299404C44E5E8BF8ED798FEE0906B`
