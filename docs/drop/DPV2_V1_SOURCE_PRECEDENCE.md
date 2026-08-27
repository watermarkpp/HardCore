# DPV2 V1 Source Precedence

## 冻结基线

- `BASE_SHA`: `041343432ec8e4e7960aded9524a1c146a23241a`
- V1 workbook: `HardCore_怪物变体与掉率母版_V1_审核稿.xlsx`
- V1 workbook SHA-256: `BC64C096528D43E314CB5E01446F15DB53418C0AD10A7A66497FC4DB66C3418C`

## Authority 顺序

1. Current Monster Identity 只由冻结的 Canonical Monster Authority / Monster Final Closure 决定。
2. 上述 V1 workbook 的正式定位是 `V1 DROP DESIGN BASIS`。它仅提供 Item Tier taxonomy、Tier denominator、Monster Drop Role taxonomy、217 历史源角色种子、关键物品锚点和经济设计依据。
3. `HardCore_1.76_怪物掉落与爆率母版_审查版_v1.xlsx` 的定位是 `HISTORICAL_REVIEW_ONLY`；本轮未找到该文件，它也不是 A0.5 的阻塞依赖。
4. V1 不能重新决定当前 156 个 canonical identity 或 153 个 runtime identity。绑定链固定为 `Frozen Canonical -> frozen historical/source mapping -> V1 role seed -> candidate DPV2 role`。
5. 任一 V1 角色多源冲突均保留为 `ROLE_BINDING_CONFLICT`，不得自行选边。

## DPV2 显式覆盖

- `MYSTERY_SIGNATURE = 9600`。只允许骷髅精灵/神秘头盔、邪恶钳虫/神秘腰带、白野猪/神秘戒指；沃玛卫士、沃玛教主不得成为 runtime source。
- `HIGH_CLASS_WEAPON = 48000`。
- `EXPANDED_HIGH_WEAPON`: V1 `38400`，DPV2 `96000`。
- `LEGENDARY_WEAPON`: V1 `51200`，DPV2 `192000`。
- `UNIQUE_GEAR_BOSS` 禁止成为 DPV2 Production Role；由 `NEW_CLOTHES_BOSS = 16` 取代。
- `NEW_CLOTHES_BOSS` 必须恰好 6 个 boss、6 件 40 级新衣、严格 1:1。
- 暗之牛魔王不得获得新衣资格；当前正式存在时采用 `ENDGAME_BOSS = 16`。

## A0.5 边界

本阶段输出均为审计结果或候选 seed，不激活 Drop Master，不修改 Production Runtime、Canonical/Data、7032 槽、概率、地图编辑器或地图数据，不新增 canonical item ID。
