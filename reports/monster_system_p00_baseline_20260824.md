# Monster System P00 Baseline — 2026-08-24

## Decision

```text
P00 = PASS
M00 = ALLOWED_FROM_THE_PUSHED_MONSTER_BASE_SHA
M01 = NOT_STARTED

INTEGRATION_SOURCE_SHA = c93ff50bcfce5e1c29c83eec89fc4830bc591e93
MONSTER_SOURCE_SHA = 722bf580e64bbcfd2fbcfeee95f0def2182d7b64
INTEGRATION_MONSTER_MERGE_BASE = 402011a7a914c96512c793ec15064292eb07b7d1
MONSTER_MERGE_COMMIT = 1eca8b61460a8e1cff65ed0774a9013b72597982
MAPS_ORIGIN_SHA = ff96ceaf8920666e309039091e76f58428f3761d
MAPS_MONSTER_DELTA_VERDICT = NONE

BOOTSTRAP_PASS = YES
CANONICAL_CHECK_PASS = YES
MONSTER_SUITE_PASS = YES
MONSTER_SUITE_FAILED = 0
GROUND_CRITICAL_PASS = YES
PROJECTION_CRITICAL_PASS = YES
FORMAL_MAP_PROJECTION_PASS = YES
MAP_RUNTIME_PASS = YES
SNAPSHOT_PRODUCTION_PASS = YES
FROZEN_ASSETS_UNCHANGED = YES
ALL_PERSISTENT_BOSS_ELITE_HAVE_EXPLICIT_STABLE_SPAWN_GROUP_ID = PASS
```

`MONSTER_BASE_SHA` is the pushed `codex/integration` HEAD containing this P00E report. It is resolved and verified after the report commit so the report does not attempt an impossible self-referential Git hash.

## P00-A evidence and dirty-worktree disposition

No existing dirty worktree was reset, cleaned, stashed, overwritten, or used as the merge target. Integration work was performed in the independent clean clone `C:\Users\Administrator\Documents\HardCore-P00-integration`.

| Worktree | Branch / HEAD | Remote | Tracked dirty | Untracked files | Disposition |
| --- | --- | --- | ---: | ---: | --- |
| existing integration | `codex/integration` / `c93ff50b` | equal | 1 | 254 | tracked map catalog is `UNRELATED_CURRENT_WORK`; recognized generated `.uid`/translation outputs are `GENERATED_REBUILDABLE`; all remaining user or uncertain files are `USER_AUTHORED_KEEP` or `UNKNOWN_DO_NOT_TOUCH` |
| monsters | `codex/monsters` / `722bf580` | equal | 0 | 17 | generated `.uid`/translation outputs are `GENERATED_REBUILDABLE`; preserved in place |
| maps | `codex/maps` / `cef66165` | behind audited remote by 32 | 246 | 1248 | authored maps/assets are `USER_AUTHORED_KEEP`; previews/caches are `GENERATED_REBUILDABLE`; unrelated production is `UNRELATED_CURRENT_WORK`; unresolved items are `UNKNOWN_DO_NOT_TOUCH` |

Binary-safe tracked evidence was captured under ignored `outputs/monster_p00/`:

- `integration_tracked.patch` SHA-256 `5198311631d57aad7af6c5bcde224fbbe90f5f9f4327d4e0a06a73b9956e2c39`
- `maps_tracked.patch` SHA-256 `6fc471dddd3e59dadd0cd915c2a4b90da18d43a83c13be8931500afb3593fadf`
- `monsters_tracked.patch` SHA-256 `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (empty, confirming tracked clean)

## P00-B monster integration

The complete `722bf580` line was merged with `--no-ff`; no last-commit cherry-pick or monster-line reconstruction was used. The merge retained canonical ID/fail-closed runtime authority, map-editor monster authority, physical projectiles, the 220/222 visual split, monsters 70/124 delivery, collision gates, Red Moon user-approved art, and the fixed-area spike delivery.

## P00-C maps semantic audit

The first 31 committed maps changes after local `cef66165` changed 22 editor documents, but those documents contain exactly 0 `monster_spawn` and 0 `boss_spawn` entries. During final push verification, maps advanced once more to `ff96ceaf` (`feat(maps): canonicalize formal map network`). That commit changes no `assets/data/runtime/**`, `game_root`, runtime bridge, or map runtime release path; it adds 0 numeric canonical monster spawns and 0 numeric canonical Boss spawns. Its only Boss-layer change removes three legacy string-identified Orc Tomb entries already absent from the integrated `722bf580` authority. Therefore the latest maps HEAD adds no monster runtime semantic delta. The remaining changes are map identity/network, layouts, art, entrances, annotations, or portal-note behavior and do not enter the monster baseline.

The dirty maps tree has 22 tracked changed editor documents and 45 untracked editor documents. It adds 0 monster spawns and 0 Boss spawns. Its removal of three legacy string-identified Orc Tomb Boss entries is already represented in the integrated `722bf580` authority line. No dirty maps file was copied into staging.

The formal runtime registry contains one currently published persistent Boss/Elite spawn: monster 76 in map 315. P00 assigned the explicit stable identity:

```text
editor:315:boss:wooma_leader
```

The authoring document was rebuilt through the formal candidate/publish transaction. Published build SHA-256 is `d036e58703eaea1a503dc8925f22661a31b842579919181388cc784de9a6e6f2`, release revision 4. `map_persistent_boss_spawn_identity_test` prevents a return to array-index fallback.

## P00-D bootstrap and test closure

Bootstrap metadata was reconstructed from current `AGENTS.md`, current Git state, current formal contracts, and current ownership. `tools/agent_bootstrap.ps1 -Compact` passes on exact branch `codex/integration`; branch validation was not relaxed.

Four handoff tests were registered in the formal monster suite:

- `monster_physical_projectile_visual_source_test`
- `monster_target_magic_primary_visual_test`
- `monster_special_delivery_contract_test`
- `monster_special_delivery_runtime_test`

Old tests were repaired only at the fixture layer: fake/name-only targets, obsolete name-keyed rules, stale stats, negative/placeholder IDs, and headless world boots were replaced by current positive canonical IDs and current APIs. No production name lookup, negative-ID runtime, or legacy fallback was restored.

### Acceptance results

```text
py -3.12 tools/build_canonical_monster_catalog.py --check
CANONICAL_MONSTER_CATALOG_CHECK_PASS: identities=156 runtime_allowed=153

monster                                  23 passed / 0 failed / 0 engine errors
combat_absolute_ground_critical           9 passed / 0 failed / 0 engine errors
combat_projection_fail_closed_critical    6 passed / 0 failed / 0 engine errors
formal_map_projection_critical            8 passed / 0 failed / 0 engine errors
map_runtime_release_critical               4 passed / 0 failed / 0 engine errors
snapshot_production_critical               9 passed / 0 failed / 0 engine errors
```

The original 12-test monster handoff selection also passed 12/12 with 0 engine errors after the merge.

## Frozen asset proof

The following Git blobs match the pre-merge values exactly:

| Frozen object | Git blob |
| --- | --- |
| `monster_ground_alignment_manual_v1.json` | `1354ca4c378647afd7bce2336cec2a421e1f1843` |
| `redmoon_generated_animation_sources.json` | `04d9bb58874cb2e182a2bb716a31c62d38c70d24` |
| `fixed_area_ground_spike_sources.json` | `3ea379a3c398ba4a607fb1d7af83b65ac443a223` |
| `fixed_area_ground_spike_rgba_v1.png` | `b1f38697a9badc70237061490a57db202cbb5868` |
| Red Moon attack atlas | `5440114196046524dc4ada844c4a894df531ef5e` |
| Red Moon death atlas | `616a5423bfef09689cac736a9c03a30cb2d6353a` |
| Red Moon hit atlas | `bd92a27f49b292c7bfa7c95659b79c15f36356bf` |
| Red Moon idle atlas | `5506133b342bf002a1e0e3d14e6722ec892f8112` |
| Red Moon walk atlas | `5506133b342bf002a1e0e3d14e6722ec892f8112` |

No old bulk generator was run against frozen monster assets.

## Scope stop

P00-A through P00-E are complete. This baseline does not implement M00, M01, MonsterWorldState, Boss durable persistence, or later movement/target-policy stages.
