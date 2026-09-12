# R3.3-P2 铂金戒指 sell 布局闭环 · 施工与验收报告

BASE 1b56c5821e4021de2fca978cdeaffd2157865af7 · 生产改动仅 `scripts/ui_shop_detail_space.gd`

## 1. 实施
- 按 `HardCore_R33_P2_layout_patch.diff` 语义人工实现（diff 为空 @@ 语义块）：
  - 常量拆两级：`FRAME_CLEAR_PX 32.0`（preferred）/ `FRAME_CLEAR_MIN_PX 30.0`（legal floor）；
    `ACTION_CLEAR_PX 36.0`（preferred）/ `ACTION_CLEAR_MIN_PX 32.0`（legal floor）。
  - `region()` 同步计算 `expanded_region`（minimum_safe + 30/32 floor），先 preferred 后 floor；
    返回字典新增 `expanded_region / minimum_frame_safe_rect / minimum_action_gap_px /
    minimum_frame_gap_px / layout_policy=preferred_then_legal_minimum`。
- **一处必要的精度归一化（超出 diff 字面、在授权文件内）**：变换链浮点累计误差使 expanded
  高度 = 263.999969（真实精确值 264.0），`floorf` 后差 3.1e-5px 造成幻影缺口，Presenter 判
  SPACE_PLAN_REQUIRED。对 expanded_region 终值做 1e-3px 网格量化（偏差 ≤0.0005px，远小于
  0.05px 验收容差；不改变任何真实净空；preferred region 路径字节级不变）。已在提交信息与
  代码注释中说明。
- Presenter 未改（实证其原生两级候选顺序：line 346 先 region，347-348 仅失败且有面积才追加
  expanded，352-388 首个 fit 即停）。shop_panel/item_detail_docked_presenter/ui_item_player_copy
  零改动；字号 20/14、MARGIN 18、TITLE_GAP 12、MEASURE_PAD、正文、风险行、数量加减行全部未动。

## 2. 验收结果
| 项 | 结果 |
|---|---|
| A. header_session_test | **PASS**（checks 全过，0 引擎错误；无 SPACE_PLAN_REQUIRED；铂金 sell valid/visible/no-scroll；独立量得 frame≥30、action≥32） |
| B. space_diagnostic 48 行 | PASS · CAPTURE_COMPLETE_NOT_LAYOUT_PASS；buy 仅在 preferred（availH 唯一档 318）；sell 先 preferred(257.9) 失败 → 仅落 expanded(264.0)；settle 检查过，无持续 relayout（引擎 0 错误） |
| C. shop matrix 4 shards | shard1/2/3 **PASS**；**shard0 FAIL：110/400，全部且仅为**冻结断言 `region.grow(0.1).encloses(actual)`（shop_space_matrix.gd:52-53，卡在 preferred 带内）vs P2 fallback 政策冲突；该 110 行其余 8 项断言（valid/visible/正文全等/无滚动/无溢出/字号/内边距）全绿 |
| C. close_selection / prewarm / hidden_views | **PASS** |
| D. 窗口化原尺寸截图 | 1598×720：铂金 sell（双商人）、超级金创药 buy、超级魔法药 buy、木剑 sell —— 不顶二级框、不贴按钮、无滚动条、无透明隐藏；「出售提示：高价值」保留 |

## 3. 触发 fallback 的案例（实测）
- 铂金戒指 sell（medicine+general 两商人）—— natural 264.0 vs preferred 257.9（差 6.1px）→ expanded 264.0 恰好容纳。
- shard0 目录段（装备为主）110 个 sell 案例 —— 同为 9 行结构正文，均落入 expanded。
- buy 全部（含铂金）与短正文 sell：preferred 内容纳，expanded 未使用。

## 4. P1 正文不变证据
header_session `body lost/rewritten` 检查 PASS（正文逐字节断言）；r33p2_platinum_trace：
sell body_lines=9 / content_h=180.0 与 P1 after 完全一致；「出售提示：高价值」在图与正文中保留。

## 5. 遗留与未关闭
- **需主控裁决**：冻结矩阵 shop_space_matrix.gd:52-53 断言卡片必须包含于 preferred region（32px 带），
  与 P2 两级净空政策对 fallback 案例天然互斥（110 例）。矩阵文件已冻结、断言未动；请主控裁定
  该断言按新合同更新（如：卡片须包含于其实际采用的 region 或 expanded_region）或维持现状记录。
- UI 操作延迟：**NOT_RUN**。M30：**NOT_CLOSED**。Android/APK/设备：**NOT_RUN**。本轮未改 AI/性能阈值。
- 临时取证脚本 `outputs/live_preview/r33p2_platinum_trace.*`（未跟踪 scratch）随证据归档后可删。
