# R3.3-P2A 冻结矩阵合同迁移 · 验收报告

BASE 9beefcdf4f1c4a011cc8ded661b1ea0c96420cbe · 改动仅 `tests/r6_3/shop_space_matrix.gd`（零生产文件）

## 实施（按 HardCore_R33_P2A_matrix_contract_patch.diff 语义逐条落实）
1. 同时读取 `region` 与 `expanded_region`；
2. 卡片必须包含于 preferred 或 legal expanded 之一（`outside all legal reading regions`）；
3. 仅当不在 preferred 时标记 `used_fallback`；
4. fallback 时强制 `layout_policy == preferred_then_legal_minimum`，否则报
   `fallback used without two-tier layout contract`；
5. 结果行新增 `expanded_region` 与 `used_fallback` 字段。
独立硬门槛未动、未删：frame ≥30px（0.05 容差）、detail→action ≥32px、禁与可见操作控件/标题重叠、
字号 20/14、内边距≥16、正文逐字节全等、无滚动/溢出。

## 验收（顺序执行，全部 0 引擎/script 错误）
| 步骤 | 结果 |
|---|---|
| 1. shop_space_0 | **PASS**（400 记录 0 失败；原 110 个 preferred-only 假失败全部消失） |
| 2. used_fallback 统计 | buy **200/200 全 preferred**（零无故 fallback）；sell 90 preferred + **110 fallback**——与 P2 证据完全同级，全部为装备长正文 sell（罗刹/修罗/炼狱/井中月/裁决之杖/屠龙/命运之刃/落魄神兵…） |
| 3. shop_space_1/2/3 | **PASS** ×3 |
| 4. header_session / close_selection / prewarm / hidden_views | **PASS** ×4 |

## 状态
- **R3.3/P2 商店详情布局 blocker：CLOSED**（按主控标准，全部验收绿）。
- UI 操作延迟：**NOT_RUN**。M30：**NOT_CLOSED**。Android/APK：**NOT_RUN**。
- 未修改正文、字号、MARGIN、TITLE_GAP、30/32 硬门槛或任何生产布局。
