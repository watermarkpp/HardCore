# DPV2 A0.7 Human Authority Decision

Date: 2026-08-27

Status: `HUMAN_FROZEN / A0.7 ONLY / PHASE_1_FORBIDDEN`

## Item Tier decisions

- Add `BOSS_KEY_ITEM` with base denominator `32`.
- Add `MONSTER_MATERIAL` with base denominator `32`.
- Canonical items `920023 沃玛号角` and `920032 祖玛头像`: `BOSS_KEY_ITEM`, `protected_drop=true`, `overflow_priority=200`.
- Canonical items `920037 肉`, `920038 蛆卵`, `920039 蜘蛛牙`, `920040 蝎尾`, `920049 食人花叶`, and `920050 食人花果`: `MONSTER_MATERIAL`, `protected_drop=false`, `overflow_priority=100`.
- These eight items may not use `FUNCTIONAL_SPECIAL` or `COLLECTOR_LOW` and may not receive a per-item denominator override.
- Historical `source_rate` remains provenance only and is not final DPV2 probability Authority.

## Monster Role decisions

- For 29 of the 32 A0.6 conflicts, freeze the A0.6 `recommended_role` and factor.
- Override canonical monster `77 沃玛教主1` to `MAJOR_BOSS @ 12`, authority `HUMAN_FROZEN`.
- Override canonical monster `137 白野猪1` to `ELITE @ 3`, authority `HUMAN_FROZEN`.
- Override canonical monster `142 邪恶毒蛇1` to `MINOR_BOSS @ 6`, authority `HUMAN_FROZEN`.
- Do not create independent multipliers or an unknown-dark-palace-specific role for those monsters.
- `NON_LOOT` is a reporting label, not a probability role. Every such entity must have `drop_enabled=false`, `drop_role=null`, `role_factor=null`, `reporting_label=NON_LOOT`; factor zero may not enter probability calculation.
- Every one of the 156 canonical monsters must be either enabled with a non-empty legal role/factor or disabled with the exact NON_LOOT representation above.

## Continuing freezes

- Formal `VETERAN` definitions and assignments remain zero.
- NEW_CLOTHES remains exactly six bosses, six items and zero one-to-one violations.
- Canonical monster `225 暗之牛魔王` remains `ENDGAME_BOSS @ 16`, `new_clothes_eligible=false`.

## Construction boundary

A0.7 establishes `dpv2_item_tier_authority_v1` and `dpv2_monster_role_authority_v1` as non-runtime Authority data. It may add focused Authority validators, tests and reports. It may not modify or activate Production Runtime, the 7032 source slots, map data, map-editor data/code, or actual probability execution. A0.7 must stop after verification and must not enter Phase 1.
