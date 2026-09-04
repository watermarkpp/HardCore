# DPV2 A0.6 Authority Closure Report

## Status

`PARTIAL — A0.6 COMPLETE / WAITING 8 ITEM TIER + 32 MONSTER ROLE HUMAN DECISIONS / PHASE 1 FORBIDDEN`

- A0.6 construction base: `ca4908b1ea3dc6d4a75dd081b18dc28960570c7b`
- P1A profiles/runtime allowed/slots: `156 / 153 / 7032`
- Production Runtime, 7032 drop slots, probability logic, map data and map editor were not modified.

## A. Item identity closure

- Unique drop items: `233`
- Existing positive canonical IDs: `180`
- Unique existing formal IDs found for the 53 missing items: `0`
- New explicit project IDs: `53`
- Reserved interval: `920001–920053`
- Structured namespace scan: `73` JSON namespaces / `376` existing formal IDs / `0` collisions
- Final positive unique overlay: `233/233`
- `service_index`: legacy/source locator plus provenance only; canonical/runtime/persistence usage all forbidden
- Runtime/persistence consumers of the new table: `false / false`

The tracked Authority is `assets/data/drop/dpv2_item_identity_authority_v1.json`. Every record explicitly binds canonical ID, normalized identity, legacy names, legacy service locator, source key, slot count and monster count. No ID is derived from name, order or service index.

## B. Eight unresolved Item Tiers

All eight identities are now closed, but their Tier remains `WAITING_HUMAN_AUTHORITY`. V1 has no exact item/group hit for any row; no denominator is active and no item defaults to COMMON.

| Canonical ID | Item | Current drops | Candidate Tiers only |
|---:|---|---|---|
| 920023 | 沃玛号角 | 76 沃玛教主；1 slot，1/4 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920032 | 祖玛头像 | 160 祖玛教主；1 slot，1/1 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920037 | 肉 | 96 羊、100 狼；4 slots | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920038 | 蛆卵 | 46 洞蛆；1 slot，1/5 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920039 | 蜘蛛牙 | 18 毒蜘蛛、185 剧毒蜘蛛；2 slots | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920040 | 蝎尾 | 45 蝎子；1 slot，1/1 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920049 | 食人花叶 | 30 食人花；1 slot，1/1 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |
| 920050 | 食人花果 | 30 食人花；1 slot，1/5 | FUNCTIONAL_SPECIAL / COLLECTOR_LOW |

These candidates are alternatives for human review, not assignments. A subsequent Authority may instead create an explicit material/quest-material Tier or declare a non-Tier material policy.

## C. 32 Monster Role conflicts

Each row contains every V1 candidate with exact workbook row/historical identity plus current canonical classification, combat/profile evidence, a recommendation, alternatives and confidence. Final role/factor remain null; `highest-role-wins` was not used.

| ID | Canonical name | Recommendation only | Confidence |
|---:|---|---|---|
| 39 | 半兽勇士1 | STRONG_COMMON@1.5 | MEDIUM |
| 41 | 半兽勇士9 | ELITE@3 | MEDIUM |
| 55 | 骷髅战将0 | ELITE@3 | MEDIUM |
| 57 | 骷髅精灵1 | MINOR_BOSS@6 | MEDIUM |
| 59 | 骷髅精灵9 | NON_LOOT@0 | HIGH |
| 74 | 沃玛卫士1 | ELITE@3 | MEDIUM |
| 75 | 沃玛卫士2 | ELITE@3 | MEDIUM |
| 77 | 沃玛教主1 | NON_LOOT@0 | LOW |
| 78 | 沃玛教主9 | NON_LOOT@0 | HIGH |
| 90 | 尸王1 | MINOR_BOSS@6 | MEDIUM |
| 91 | 尸王2 | ELITE@3 | HIGH |
| 121 | 邪恶钳虫1 | MINOR_BOSS@6 | MEDIUM |
| 122 | 邪恶钳虫2 | ELITE@3 | MEDIUM |
| 123 | 邪恶钳虫9 | ELITE@3 | MEDIUM |
| 131 | 红野猪3 | OFFICIAL_JP@4 | HIGH |
| 133 | 黑野猪0 | STRONG_COMMON@1.5 | MEDIUM |
| 134 | 黑野猪3 | OFFICIAL_JP@4 | HIGH |
| 136 | 白野猪0 | ELITE@3 | MEDIUM |
| 137 | 白野猪1 | NON_LOOT@0 | LOW |
| 140 | 蝎蛇3 | OFFICIAL_JP@4 | HIGH |
| 142 | 邪恶毒蛇1 | NON_LOOT@0 | LOW |
| 152 | 祖玛弓箭手3 | OFFICIAL_JP@4 | HIGH |
| 155 | 祖玛雕像3 | OFFICIAL_JP@4 | HIGH |
| 157 | 祖玛卫士0 | ELITE@3 | MEDIUM |
| 158 | 祖玛卫士3 | OFFICIAL_JP@4 | HIGH |
| 159 | 祖玛卫士00 | OFFICIAL_SUPER_JP@5 | HIGH |
| 161 | 祖玛教主9 | NON_LOOT@0 | HIGH |
| 189 | 虹魔猪卫0 | ELITE@3 | MEDIUM |
| 190 | 虹魔猪卫9 | ELITE@3 | MEDIUM |
| 192 | 虹魔蝎卫0 | ELITE@3 | MEDIUM |
| 199 | 恶灵尸王0 | BOSS@8 | HIGH |
| 209 | 黄泉教主0 | MAJOR_BOSS@12 | HIGH |

Recommendation distribution: `ELITE 12`, `NON_LOOT 6`, `OFFICIAL_JP 6`, `MINOR_BOSS 3`, `STRONG_COMMON 2`, `BOSS 1`, `MAJOR_BOSS 1`, `OFFICIAL_SUPER_JP 1`. Low-confidence rows are IDs `77`, `137`, `142`.

## Frozen role decisions

- Formal DPV2 `VETERAN` role definitions: `0`
- Canonical `VETERAN` assignments: `0`
- Removal tombstone: `1`
- Unrelated NPC/service veteran reference sites: `4`; these are not Monster Drop Roles and remain unchanged
- `UNIQUE_GEAR_BOSS`: removed from formal DPV2 roles
- NEW_CLOTHES: `6 bosses / 6 items / 0 bijection violations`
- Monster `225 暗之牛魔王`: `ENDGAME_BOSS @ 16`, `new_clothes_eligible=false`

## Verification

- `tools/dpv2_a06_item_identity_validator.py`: PASS (`233/233`, 53 records, 0 collisions)
- Item identity validator unit tests: `3/3 PASS`
- `tools/validate_dpv2_a06_role_design.py`: PASS
- `tools/validate_dpv2_a06_authority_closure.py`: PASS
- Fresh P1A: 6 analyzer tests PASS; runtime contract PASS; `profiles=156`, `slots=7032`, `reward_unresolved=0`, `reachable=7031`; `MONSTER_DROP_P1A_ALL_PASS`

## Pause

A0.6 ends here. The 53 technical identity blockers are closed. The only remaining human Authority inputs are eight Tier decisions and 32 canonical Monster Role decisions. No Phase 1 work is authorized or started.
