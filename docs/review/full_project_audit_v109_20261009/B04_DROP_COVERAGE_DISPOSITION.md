# B04 drop coverage disposition

## Scope and result

This is a static B04-001 coverage disposition against fixed source `172125ae99e3c4adf19af82da2720934a52f9537`. It does not claim a new Godot or native run. The published-map/direct-profile join is **PASS** from the existing formal receipt: 67 released maps, 2,638 spawn rows, and 120 distinct runtime monster IDs. That receipt is for the historical DPV2 direct baseline, not proof that the current UserLootSheetProvider has every profile. The current UserLootSheetProvider join is recorded separately below. The dynamic summon-path review is **PASS** for ownership and lifecycle tracing. The authoring join has **MISSING** rows for 26 catalog identities; that is a conditional future content gap, not evidence that all 26 currently produce zero drops.

The existing receipt was reused rather than rerun because its source and input evidence are already recorded. Its conclusions are kept separate from the current dirty workspace hashes; the current hashes are recorded in `evidence/B04_drop_coverage/SOURCE_BINDING.json`.

## The 26 fixed-catalog identities absent from the 126-row user sheet

The fixed catalog contains 152 entries that are both runtime allowed and editor placement allowed. The fixed user sheet contains 126 identities. The exact missing join is recorded in `FIXED_172_MISSING_SHEET_IDS.json`.

| ID | Canonical name | Classification | Fixed drop state | Placement evidence |
|---:|---|---|---|---|
| 33 | 雪人王 | elite | no rows; explicit user-sheet no-row exemption | no map contexts |
| 41 | 半兽勇士9 | elite | 50 rows | no map contexts |
| 55 | 骷髅战将0 | elite | 27 rows | no map contexts |
| 75 | 沃玛卫士2 | elite | 78 rows | D022, D023, D024 |
| 91 | 尸王2 | elite | 8 rows | no map contexts |
| 122 | 邪恶钳虫2 | elite | 50 rows | no map contexts |
| 123 | 邪恶钳虫9 | version_difference | 112 rows | no map contexts |
| 127 | 蝙蝠 | ordinary | 5 rows in canonical profile | monster_spawn, no map contexts |
| 131 | 红野猪3 | elite | 18 rows | no map contexts |
| 133 | 黑野猪0 | ordinary | 46 rows | monster_spawn, no map contexts |
| 134 | 黑野猪3 | elite | 18 rows | no map contexts |
| 136 | 白野猪0 | special | 91 rows | monster_spawn, no map contexts |
| 140 | 蝎蛆3 | elite | 18 rows | no map contexts |
| 145 | 变异骷髅0 | special | 74 rows | monster_spawn, no map contexts |
| 146 | 神兽0 | special | 78 rows | monster_spawn, no map contexts |
| 147 | 神兽2 | special | 71 rows | monster_spawn, no map contexts |
| 183 | 爆裂蜘蛛 | ordinary | no rows; explicit user-sheet no-row exemption | monster_spawn, no map contexts |
| 186 | 鹰卫 | special | no rows; wizard-tameable no-drop exemption | 13 explicit map contexts |
| 187 | 虎卫 | special | no rows; wizard-tameable no-drop exemption | no map contexts |
| 189 | 虹魔猪卫0 | elite | 57 rows | no map contexts |
| 190 | 虹魔猪卫9 | version_difference | 57 rows | no map contexts |
| 192 | 虹魔蝎卫0 | elite | 56 rows | no map contexts |
| 194 | 恶魔弓箭手 | non_hostile | no rows; non-hostile/script-object exemption | 0, 1, 2, 4, 5, D601 |
| 199 | 恶灵尸王0 | boss | 72 rows | no map contexts |
| 209 | 黄泉教主0 | boss | 107 rows | no map contexts |
| 241 | 飞火流星 | special | no rows; explicit user-sheet no-row exemption | monster_spawn, no map contexts |

“Rows” above is the fixed catalog's canonical `drop_policy.entry_count`, not a claim that a user-sheet row exists. This distinction matters for ID 127: it has a canonical five-row profile but is absent from the user sheet. IDs 33, 183, 186, 187, 194, and 241 carry explicit no-row exemptions in the fixed catalog; no fallback probability was invented.

## Published map coverage

The reused receipt `outputs/wake_drop_v108_review_followup_20261009/drop_coverage_evidence.json` reports:

- **PASS**: 67 released maps and 2,638 spawn rows.
- **PASS**: 120 unique spawned IDs all have canonical identity, runtime permission, drop source, and direct baseline profile.
- **PASS**: spawned missing canonical = 0, runtime disallowed = 0, missing drop source = 0, missing direct profile = 0, invalid or empty direct profile = 0.
- 36 runtime-allowed IDs were not present in those published spawn rows. The 26 sheet-missing IDs are not therefore equivalent to current live spawn failures.

This receipt is a historical static artifact bound to its own source hashes. The current dirty tree has separate hashes in the source-binding evidence and was not silently substituted for the receipt's inputs.

## Dynamic summons and the drop chain

The dynamic path is a normal canonical EnemyActor path after materialization:

`EnemyActor._update_behavior_summon` (`scripts/enemy.gd:7147-7178`) or the health-stage branch (`scripts/enemy.gd:8069-8090`) emits `summon_requested` → `GameRoot._on_boss_summon_requested` (`scripts/game_root.gd:6468-6477`) → `M30SummonQueue.enqueue/claim_birth` (`scripts/monster_ai_package/m30/summon_queue.gd:138-253`) → `_hc_m30_materialize` and `track_child` (`summon_queue.gd:386-417`) → regular EnemyActor death processing and `LootRuntimeService` profile lookup. The queue records stable child IDs, map/generation, and one-shot lifecycle hooks; it is not a second loot authority.

The current canonical behavior data exposes two ordinary summon pools: owner 126 requests child 127 and owner 182 requests child 183. The boss health-stage rule exposes owner 96/160 data with child pool 156, 153, 150, and 128. In the fixed user sheet, 127 and 183 are absent while 128, 150, 153, and 156 are present. Therefore:

- ID 183 is a dynamically configured child with an explicit no-row exemption; this is an intentional no-reward case unless product rules change.
- ID 127 is a dynamically configured child with a canonical five-row drop profile but no user-sheet identity. This is **MISSING** authoring coverage and needs a product/content decision if the stationary-summoner route is released. The evidence does not show that it is currently spawned on a released map.
- The boss child pool has sheet coverage for all four IDs and does not bypass the normal death/drop chain.

The special profile extensions at `scripts/drop/user_drop_additions_v81.gd:22-45` (ID 76) and `scripts/drop/user_drop_balance.gd:23-39` (ID 159) modify existing profile data. They do not add a new spawn identity or authorize a fallback.

## Boundaries and follow-up

No source or generated data was changed. No engine, native, or Godot test was run (`NOT_RUN`). The only unresolved item is the authoring decision for ID 127 if its dynamic summon route is intended for a released map. A future content fix must update the authoritative user-sheet/source and formal generation chain; it must not restore an old SPB table or guess a probability. The existing published-map PASS remains valid for the exact receipt and scope recorded above.

Evidence:

- [SOURCE_BINDING.json](evidence/B04_drop_coverage/SOURCE_BINDING.json)
- [FIXED_172_MISSING_SHEET_IDS.json](evidence/B04_drop_coverage/FIXED_172_MISSING_SHEET_IDS.json)
- [PUBLISHED_MAP_COVERAGE_REUSE.json](evidence/B04_drop_coverage/PUBLISHED_MAP_COVERAGE_REUSE.json)
- [DYNAMIC_SUMMON_DROP_PATHS.json](evidence/B04_drop_coverage/DYNAMIC_SUMMON_DROP_PATHS.json)
- [B04_DROP_COVERAGE_RECEIPT.json](evidence/B04_drop_coverage/B04_DROP_COVERAGE_RECEIPT.json)

## Current UserLootSheetProvider join correction

The earlier published-map receipt proves coverage against its recorded DPV2 direct baseline inputs. It does not by itself prove current `UserLootSheetProvider` coverage. The new static join in `evidence/B04_drop_coverage/USER_SHEET_LIVE_JOIN.json` compares the exact 120 IDs from `drop_coverage_evidence.json` with the current 6,083-slot, 126-profile `assets/data/drop/dpv2_user_loot_sheet_authority_v1.json` loaded by `scripts/drop/user_loot_sheet_provider.gd`.

The intersection is **PASS**: all 120 previously recorded released spawn IDs have a current UserLootSheet profile. The input fingerprints differ by authority: the prior receipt records `dpv2_direct_baseline_v2.json` SHA256 `a4cd03688418820d4657403da46424ed9bddf0d930d46e4778b54b912555dad7`, while the current UserLootSheet JSON SHA256 is `3C371628C2D0F51023A5C059439020F756A3762C88C3AE6EA4FA4A5790C99AFF`; therefore the result is a new join, not a claim that the old direct table and current sheet are byte-identical. The current document status is `PENDING_ACTIVATION`, while the provider's runtime loader validates the compiled schema, profile IDs and slots fail-closed.

Parent ID 126 is present in the recorded released spawn set and has eight current UserLootSheet slots. Its behavior profile requests child ID 127, but 127 is absent from both the released spawn ID set and the current UserLootSheet profile set. This makes 127 a real dynamic code path in the canonical behavior data, but static evidence does not show current released materialization. If the 126 stationary-summoner behavior is enabled in a released runtime context, 127 needs an authoring profile decision; no fallback is permitted.

ID 75 is absent from the released spawn set and absent from the current UserLootSheet. Its canonical/editor metadata names historical contexts D022, D023 and D024, but the current 67-map runtime release registry does not expose those codes as released map entries, and the current `region_spawn_runtime_catalog.json` has no `monsterId=75` row. Those historical contexts must not be converted into present runtime reachability. The prior receipt correctly lists 75 under `runtime_allowed_not_currently_spawned`.

- [USER_SHEET_LIVE_JOIN.json](evidence/B04_drop_coverage/USER_SHEET_LIVE_JOIN.json)

## ID 127 static reachability correction

The new `127_DYNAMIC_REACHABILITY.json` closes the earlier ambiguity. Parent 126's canonical `behavior_profile.summonRule` is enabled with `monsterIds: [127]`, `count: 1`, and `maxActive: 5`; `PublishedMonsterInputs.capture` includes `Identity.behavior_profile` in the immutable payload and no static disable flag is present.

When a published 126 base slot is admitted, `WorldTargetBound._closure(126)` extracts that enabled rule, canonicalizes 127, captures child inputs, and records 127 in the closure. `admits_child` then requires exactly that closure identity and captured input. `summon_request_valid` checks the exact owner slot, ordered pool `[127]`, count, and cap. `EnemyActor._update_behavior_summon` emits the request after its normal target/life/action gates, and `M30SummonQueue.claim_birth` accepts only an issued job with matching map, generation, source life, serial, candidate and summon context. `_hc_m30_materialize` returns through canonical `_spawn_enemy`.

Therefore ID 127 is **PASS / statically reachable** when the parent is admitted and the normal summon-release conditions hold. It is not disabled by the published capability payload. Its current UserLootSheet profile is **MISSING**: canonical drop policy has five rows, but the current 126-profile sheet has no 127 row. This is an authoring gap on a reachable dynamic path. It still does not prove a current released 127 materialization because 127 is absent from the recorded released spawn set. No fallback or probability was added.

The stale-target fixture now also disables physics on the formally admitted reference actor after selection, so it cannot damage pets while the test yields; this is fixture isolation only and does not alter HP, load, or combat production rules.

Evidence: [127_DYNAMIC_REACHABILITY.json](evidence/B04_drop_coverage/127_DYNAMIC_REACHABILITY.json).
