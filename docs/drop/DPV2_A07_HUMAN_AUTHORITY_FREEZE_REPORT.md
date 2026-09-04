# DPV2 A0.7 Human Authority Freeze Report

## Status

`CLOSED — HUMAN AUTHORITY FROZEN / PRODUCTION INACTIVE / PHASE 1 NOT STARTED`

- Construction base: `4b6db9555c4529126f20d8e113ad5fbb4bae6697`
- Final commit: reported from Git HEAD at delivery
- Canonical item count: `233`
- Positive unique item ID count: `233`
- Active canonical monster count: `156`
- Runtime allowed count: `153`
- Source slot count: `7032`

## Item Tier Authority

- Resolved: `233`
- Unresolved: `0`
- `BOSS_KEY_ITEM @ 32`: `[920023, 920032]`
- `MONSTER_MATERIAL @ 32`: `[920037, 920038, 920039, 920040, 920049, 920050]`
- The two boss key items are protected with overflow priority `200`.
- The six monster materials are not protected and use overflow priority `100`.
- No per-item denominator override exists for these eight items.
- `FUNCTIONAL_SPECIAL` and `COLLECTOR_LOW` are not used for these eight items.
- Historical `source_rate` remains provenance only.

## Monster Role Authority

- `drop_enabled=true`: `131`
- Disabled `NON_LOOT`: `25`
- Unresolved/waiting: `0 / 0`
- Factor-zero probability roles: `0`

| Final Drop Role | Factor | Monster count |
|---|---:|---:|
| COMMON | 1 | 41 |
| STRONG_COMMON | 1.5 | 32 |
| ELITE | 3 | 16 |
| OFFICIAL_JP | 4 | 6 |
| OFFICIAL_SUPER_JP | 5 | 1 |
| MINOR_BOSS | 6 | 13 |
| BOSS | 8 | 4 |
| MAJOR_BOSS | 12 | 8 |
| ENDGAME_BOSS | 16 | 4 |
| NEW_CLOTHES_BOSS | 16 | 6 |

The 25 disabled rows have exactly `drop_enabled=false`, `drop_role=null`, `role_factor=null`, `reporting_label=NON_LOOT`. This includes the A0.6 PRESENTATION/SYSTEM/NON_LOOT zero-factor sources and conflict IDs 59, 78 and 161; it is a state-contract normalization, not a monster identity rewrite.

## Final 32 conflict decisions

| Monster ID | Canonical name | Final role | Final factor | Authority | Reporting label |
|---:|---|---|---:|---|---|
| 39 | 半兽勇士1 | STRONG_COMMON | 1.5 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 41 | 半兽勇士9 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 55 | 骷髅战将0 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 57 | 骷髅精灵1 | MINOR_BOSS | 6 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 59 | 骷髅精灵9 | null | null | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | NON_LOOT |
| 74 | 沃玛卫士1 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 75 | 沃玛卫士2 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 77 | 沃玛教主1 | MAJOR_BOSS | 12 | HUMAN_FROZEN | — |
| 78 | 沃玛教主9 | null | null | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | NON_LOOT |
| 90 | 尸王1 | MINOR_BOSS | 6 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 91 | 尸王2 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 121 | 邪恶钳虫1 | MINOR_BOSS | 6 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 122 | 邪恶钳虫2 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 123 | 邪恶钳虫9 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 131 | 红野猪3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 133 | 黑野猪0 | STRONG_COMMON | 1.5 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 134 | 黑野猪3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 136 | 白野猪0 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 137 | 白野猪1 | ELITE | 3 | HUMAN_FROZEN | — |
| 140 | 蝎蛇3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 142 | 邪恶毒蛇1 | MINOR_BOSS | 6 | HUMAN_FROZEN | — |
| 152 | 祖玛弓箭手3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 155 | 祖玛雕像3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 157 | 祖玛卫士0 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 158 | 祖玛卫士3 | OFFICIAL_JP | 4 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 159 | 祖玛卫士00 | OFFICIAL_SUPER_JP | 5 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 161 | 祖玛教主9 | null | null | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | NON_LOOT |
| 189 | 虹魔猪卫0 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 190 | 虹魔猪卫9 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 192 | 虹魔蝎卫0 | ELITE | 3 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 199 | 恶灵尸王0 | BOSS | 8 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |
| 209 | 黄泉教主0 | MAJOR_BOSS | 12 | A0_7_HUMAN_ACCEPTED_A0_6_RECOMMENDATION | — |

Human overrides are frozen exactly as follows: ID 77 `MAJOR_BOSS@12`, ID 137 `ELITE@3`, ID 142 `MINOR_BOSS@6`. No independent factor or unknown-dark-palace role exists.

## Continuing freezes

- VETERAN formal definition count: `0`
- VETERAN assignment count: `0`
- NEW_CLOTHES boss/item/one-to-one violations: `6 / 6 / 0`
- ID 225 暗之牛魔王: `ENDGAME_BOSS @ 16`, `new_clothes_eligible=false`

## Protected scope

- Production Runtime changed files: `0`
- 7032 source-slot changed files: `0`
- Map changed files: `0`
- MapEditor changed files: `0`
- Both A0.7 Authorities remain `production_active=false`, have no runtime consumer, and keep Phase 1 disabled.

## Verification

- A0.7 Item Tier Authority validator: PASS
- A0.7 Item Tier tests: `7/7 PASS`
- A0.7 Monster Role Authority validator: PASS
- A0.7 Monster Role tests: `5/5 PASS`
- A0.6 Item Identity validator/tests: PASS after allowing the downstream A0.7 Tier Authority to reference, but not reallocate, the frozen IDs
- A0.7 aggregate freeze validator: PASS
- Fresh P1A must remain `156 active / 153 runtime_allowed / 7032 slots / reward_unresolved=0 / MONSTER_DROP_P1A_ALL_PASS`

## Stop

A0.7 ends here. No Phase 1 implementation, runtime consumption, probability rewrite, slot rewrite or map/editor work is authorized or started.
