# DPV2 A0.5 Authority Binding Report

## 状态

`PARTIAL — PAUSED AT A0.5`

- `BASE_SHA`: `041343432ec8e4e7960aded9524a1c146a23241a`
- Frozen canonical active: `156`
- `runtime_allowed`: `153`
- Current active projection slots: `7032`
- Unique normalized drop items: `233`

本报告只完成 Authority 审计和 candidate seed，不构成 Production 激活。

## Item Identity

- Positive canonical item ID: `180`
- Missing/non-positive canonical item ID: `53`
- Service index unique/duplicate/collision/unstable: `53 / 0 / 0 / 0`
- Service index cross-distribution unproven: `53`
- Formal service-index runtime-safe/persistence-safe: `0 / 0`
- Current name-based runtime resolution: `53/53`（不等于 service key 获认证）
- `RESOLVE_NUMERIC_ID / CERTIFY_STABLE_KEY / BLOCK`: `0 / 0 / 53`

## Item Tier Candidate

- Deterministically resolved: `225`
- Unresolved: `8`
- Missing item identity: `53`
- Identity conflicts: `0`

未解析且未默认归入 COMMON：`沃玛号角`、`祖玛头像`、`肉`、`蛆卵`、`蜘蛛牙`、`蝎尾`、`食人花叶`、`食人花果`。

DPV2 生效覆盖：`MYSTERY_SIGNATURE=9600`、`HIGH_CLASS_WEAPON=48000`、`EXPANDED_HIGH_WEAPON=96000`、`LEGENDARY_WEAPON=192000`、`NEW_CLOTHES=8000`。

## Monster Role Candidate

- Canonical rows: `156`
- Runtime allowed rows: `153`
- Deterministically resolved: `124`
- `ROLE_BINDING_CONFLICT`: `32`
- Unresolved outside explicit conflicts: `0`
- `VETERAN` count: `0`
- Action: `REMOVE_UNUSED_VETERAN_ROLE`
- `UNIQUE_GEAR_BOSS`: disabled for DPV2 Production

冲突均来自同一 current canonical identity 对应多个 V1/historical role seed 且角色不同；候选矩阵不自动选边。

## NEW_CLOTHES 专项

| Boss ID | Boss | Item ID | Clothing |
|---:|---|---:|---|
| 235 | 暗之双头血魔 | 140 | 天魔神甲 |
| 236 | 暗之双头金刚 | 144 | 天尊道袍 |
| 237 | 暗之黄泉教主 | 142 | 法神披风 |
| 238 | 暗之骷髅精灵 | 141 | 圣战宝甲 |
| 239 | 暗之沃玛教主 | 145 | 天师长袍 |
| 240 | 暗之虹魔教主 | 143 | 霓裳羽衣 |

- Boss count: `6`
- Item count: `6`
- Boss-to-item / item-to-boss cardinality: `1 / 1`
- 1:1 violations: `0`
- 暗之牛魔王 canonical ID: `225`
- 暗之牛魔王 role candidate: `ENDGAME_BOSS @ 16`
- 暗之牛魔王 NEW_CLOTHES eligible: `false`

## Audit Tooling

工具入口以独立提交 `bd034440`（`tooling(drop-audit): repair P1A audit entrypoints`）修复，仅改动两个审计工具文件。Fresh P1A 结果：PowerShell parse PASS；6 个 analyzer tests PASS；runtime contract PASS；exporter 输出 `profiles=156`, `slots=7032`, `reward_unresolved=0`, `reachable=7031`；最终 `MONSTER_DROP_P1A_ALL_PASS`。

## 输出与暂停

机器可读输出：

- `outputs/drop/dpv2_item_identity_audit_53.json`
- `outputs/drop/dpv2_item_tier_seed_candidate.json`
- `outputs/drop/dpv2_monster_role_seed_candidate.json`

A0.5 到此暂停。禁止自动开始 Phase 1，禁止修改 Production Drop Runtime、7032 槽、概率、地图编辑器或地图数据；等待下一次 Authority 裁决。
