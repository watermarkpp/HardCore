# DPV2 A0.5 — 53 Item Identity Blocker

## 结论

7032 个掉落槽规范化为 233 种物品：180 种已有正数 `canonical_item_id`，53 种为 `canonical_item_id <= 0`。53 种均能在当前冻结 service catalog 中以唯一 `service_index` 定位，也都能被当前基于名称的 runtime 解析；但是正式 runtime、背包、装备和存档链没有使用 `service_index` 作为身份键，且跨 catalog/distribution 稳定性未被证明。

因此按 A0.5“六问任一项无法证明不得升格”的门禁：

- `RESOLVE_NUMERIC_ID = 0`
- `CERTIFY_STABLE_KEY = 0`
- `BLOCK = 53`

`BLOCK` 不表示当前名称解析失败；它表示这些 `service_index` 不能在本轮被升格为正式 canonical/persistence key。

## Service index 六问

| 问题 | 结果 | 结论 |
|---|---:|---|
| 233 范围内全局唯一 | 53/53 | PASS |
| 来自稳定源字段而非数组顺序/行号 | 53/53 | PASS；来自 Server.MirDB 内嵌 Int32 字段 |
| 同源重新导入、重排是否保持不变 | 53/53 | PASS；parser 直接读取字段 |
| Loot Runtime 是否实际以 service_index 识别 | 0/53 | FAIL；实际使用 normalized item name |
| Inventory / Equipment / Save-Load 是否稳定使用 | 0/53 | FAIL；实际保存/识别 name |
| 与既有 180 ID 一一映射或独立 namespace | 仅当前快照无碰撞 | FAIL；53 项没有 numeric master match，跨 distribution 未证明 |

当前统计：unique `53`，duplicate `0`，namespace collision `0`，同源不稳定 `0`，cross-distribution unproven `53`，正式 service-index runtime-safe `0`，正式 persistence-safe `0`。

## 53 项

| normalized item | service_index | source slots | current ID | resolution |
|---|---:|---:|---:|---|
| 万年雪霜 | 673 | 29 | -1 | BLOCK |
| 冰咆哮 | 1005 | 13 | -1 | BLOCK |
| 刺杀剑术 | 975 | 12 | -1 | BLOCK |
| 半月弯刀 | 976 | 26 | -1 | BLOCK |
| 召唤神兽 | 1032 | 13 | -1 | BLOCK |
| 召唤骷髅 | 1020 | 15 | -1 | BLOCK |
| 回城卷 | 719 | 39 | -1 | BLOCK |
| 困魔咒 | 1027 | 40 | -1 | BLOCK |
| 圣言术 | 1003 | 21 | -1 | BLOCK |
| 地狱火 | 994 | 16 | -1 | BLOCK |
| 地狱雷光 | 1001 | 31 | -1 | BLOCK |
| 基本剑术 | 973 | 10 | -1 | BLOCK |
| 大火球 | 993 | 15 | -1 | BLOCK |
| 太阳水 | 670 | 301 | -1 | BLOCK |
| 幽灵盾 | 1023 | 14 | -1 | BLOCK |
| 强效太阳水 | 671 | 487 | -1 | BLOCK |
| 心灵启示 | 1024 | 11 | -1 | BLOCK |
| 战神油 | 707 | 9 | -1 | BLOCK |
| 抗拒火环 | 991 | 10 | -1 | BLOCK |
| 攻杀剑术 | 974 | 12 | -1 | BLOCK |
| 施毒术 | 1018 | 13 | -1 | BLOCK |
| 沃玛号角 | 870 | 1 | -1 | BLOCK |
| 治愈术 | 1016 | 10 | -1 | BLOCK |
| 火墙 | 998 | 12 | -1 | BLOCK |
| 火球术 | 990 | 9 | -1 | BLOCK |
| 灵魂火符 | 1019 | 17 | -1 | BLOCK |
| 烈火剑法 | 980 | 13 | -1 | BLOCK |
| 爆裂火焰 | 997 | 14 | -1 | BLOCK |
| 疾光电影 | 999 | 11 | -1 | BLOCK |
| 瞬息移动 | 996 | 15 | -1 | BLOCK |
| 祖玛头像 | 871 | 1 | -1 | BLOCK |
| 祝福油 | 709 | 22 | -1 | BLOCK |
| 神圣战甲术 | 1025 | 12 | -1 | BLOCK |
| 精神力战法 | 1017 | 10 | -1 | BLOCK |
| 群体治疗术 | 1029 | 21 | -1 | BLOCK |
| 肉 | 855 | 4 | -1 | BLOCK |
| 蛆卵 | 872 | 1 | -1 | BLOCK |
| 蜘蛛牙 | 868 | 2 | -1 | BLOCK |
| 蝎尾 | 873 | 1 | -1 | BLOCK |
| 诱惑之光 | 992 | 16 | -1 | BLOCK |
| 超级金创药 | 666 | 307 | -1 | BLOCK |
| 超级魔法药 | 667 | 308 | -1 | BLOCK |
| 野蛮冲撞 | 977 | 28 | -1 | BLOCK |
| 金创药(中量) | 660 | 84 | -1 | BLOCK |
| 金创药(小量) | 658 | 11 | -1 | BLOCK |
| 隐身术 | 1021 | 14 | -1 | BLOCK |
| 集体隐身术 | 1022 | 14 | -1 | BLOCK |
| 雷电术 | 995 | 16 | -1 | BLOCK |
| 食人花叶 | 866 | 1 | -1 | BLOCK |
| 食人花果 | 867 | 1 | -1 | BLOCK |
| 魔法盾 | 1002 | 20 | -1 | BLOCK |
| 魔法药(中量) | 661 | 84 | -1 | BLOCK |
| 魔法药(小量) | 659 | 11 | -1 | BLOCK |

逐项 source path、catalog/master record、raw token、alias、runtime/inventory/save key 与稳定性证据见 `outputs/drop/dpv2_item_identity_audit_53.json`。
