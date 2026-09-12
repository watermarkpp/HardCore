# R3.2 阶段交付与剩余布局阻断报告

分支 `codex/r3-2-space-budget`，基线 `3468de45f49adb2cbe30da2b08bfeebe17c7de0e`。
本报告为「阶段交付 + 剩余布局阻断」，不是「修复完成」，不是「联合验收通过」。

## 0. 单位与坐标口径（关键）

- 诊断场景固定分辨率 **1598×720**（`viewport=[0,0,1598,720]`，`window=[64,64]`）。
- 下方 `availH / minReqH / shortfall` 来自 `diagnose_geometry.py` 对 `r32_geometry.json` 的 `region` 与观察值，
  单位为 **诊断视口坐标单位（viewport px @1598×720）**。
- 几何原始 JSON 中 **`screen_scale` 与 `pixel_scope` 字段均为 `null`**（headless 诊断未采集物理像素比例）；
  每行保留 `viewport`/`window`/`screen_transform`/`owner_canvas_transform`/`panel_rect` 供换算。
- 因此 217.6 / 244.0 / 278.6 / 284.0 **不是**可直接判定用户要求 30 物理屏px净空的数字；
  必须经窗口化原尺寸渲染换算。**原始尺寸视觉/截图验收 = NOT_RUN**。

## 1. 安装与代码身份（已完成并保留）

| 步骤 | 结果 |
|---|---|
| 01_check | PASS |
| 02_diagnostics | APPLIED（presenter 默认关闭候选记录） |
| 03_tests | APPLIED（shop_space_matrix.gd 旧 API 迁移；2 诊断/预算测试） |
| 06_apply | APPLIED（ui_shop_detail_space.gd 按钮行预算修正） |
| 09_audit | R32_CORE_INTACT（仅代码身份，非运行时验收） |

生产改动 2 个既有文件 + 1 个测试迁移 + 4 个新增测试；无新全局类/autoload。
运行时关键文件 SHA256 见 `geometry/before/launch_identity.json` 与 `geometry/after/*/r32_geometry.json.source_hashes`。
补丁件：`patches/core_candidate.patch` / `instrumentation.patch` / `test_migration.patch`。

## 2. 红绿测试

| 夹具 | 修改前 | 修改后 |
|---|---|---|
| space_diagnostic（48 条采集） | CAPTURE_COMPLETE_NOT_LAYOUT_PASS | CAPTURE_COMPLETE_NOT_LAYOUT_PASS |
| 稳定案例 fit | 16 中 8 fit / 8 无 fit | 16 中 8 fit / 8 无 fit |
| drawn_budget_test | FAIL（feasible 横排误纵排 / gap lost / 左右边界越界） | **PASS** |

`CAPTURE_COMPLETE_NOT_LAYOUT_PASS` = 采集完整，不是布局通过。诊断在 test_mode 下抑制已知布局
push_error 以收全数据；正式矩阵不抑制。

## 3. 剩余 8 个稳定失败案例

单位 = 诊断视口坐标（1598×720），`shortfall = minReqH - availH`，向上取整展示。
这些数字表示「当前候选尺寸在当前合法区域内放不下完整正文」，**不等于**唯一解法是加等额高度。

| 商人上下文 | 物品 | 域 | 可用高 availH | 所需高 minReqH | 缺口 shortfall | 候选数 |
|---|---|---|---|---|---|---|
| medicine | 木剑 | sell | 217.6 | 244.0 | 27 | 13 |
| medicine | 匕首 | sell | 217.6 | 244.0 | 27 | 13 |
| medicine | 超级金创药 | buy | 278.6 | 284.0 | 6 | 13 |
| medicine | 超级魔法药 | buy | 278.6 | 284.0 | 6 | 13 |
| general | 木剑 | sell | 217.6 | 244.0 | 27 | 13 |
| general | 匕首 | sell | 217.6 | 244.0 | 27 | 13 |
| general | 超级金创药 | buy | 278.6 | 284.0 | 6 | 13 |
| general | 超级魔法药 | buy | 278.6 | 284.0 | 6 | 13 |

每个案例的完整正文、标题/正文实测高度、动作区矩形、stage(synchronous/next_frame/settled)、
候选宽高，见 `analysis/07_after_analysis.json` 与该夹具的原始 48 行 `geometry/after/*/r32_geometry.json`。

## 4. 原 R3 回归（局部通过 / 仍然阻断）

- shop_space_1 / shop_space_2 / shop_space_3：**PASS**。
- shop_space_0：**FAIL**（`531` 为错误记录数，非 531 种物品；主体 sell，少量 buy，均为
  `R3_SHOP_MATRIX ... SPACE_PLAN_REQUIRED` + `body not equal independent formatter input`，未逐物品去重）。
- close_selection：`R3_CLOSE_SELECTION_PASS checks=196`（**清选语义通过**），但整场景
  **FAIL**（仍含 1 条布局错误 `HC_UI6_DETAIL_SPACE_PLAN_REQUIRED: 木剑`）。
  口径 = **清选语义通过，整场景因布局错误失败**；非设备实机验证。

## 5. 尚未验证 / 未关闭

- 原始尺寸窗口渲染截图 + 逐张侧车：**NOT_RUN**（本轮未执行 `run_rendered_capture.py`）。
- UI 操作延迟（真实保存/GUI/磁盘增量）：**NOT_RUN**；按钮预算测试通过不替代操作耗时测量。
- M30：**NOT_CLOSED**（本轮未改怪物代码、未重测；待同窗口 Before/After 三轮、12/15/30 原始帧与设备验收）。
- 临时集成组合（b329/9cf）、设备、APK：**NOT_RUN**。

## 6. 证据索引（docs/closure/20260911/r32_space_budget_evidence/）

- `installer/` — check/diagnostics/tests/apply/audit 五份回执
- `geometry/before/`、`geometry/after/` — 两侧 48 条原始采集、launch_identity、测试工作区 patch、原始日志
- `analysis/` — 修改前/后 diagnose_geometry 分析 JSON
- `runner/` — space_diagnostic、drawn_budget、shop_space、close_selection 的 runner 结果 JSON
- `patches/` — core_candidate / instrumentation / test_migration 补丁与包 SHA256SUMS.json

## 7. 结论与主控后续

按钮横向预算修正已通过其目标夹具（`drawn_budget_test` 红→绿），**值得保留**；但它没有解决全部说明框
**高度不足**。剩余 8/16 稳定失败为正文换行导致的高度缺口（sell 缺 27 viewport-px、buy 超级药缺 6 viewport-px）。
本批精确几何证据已随本提交入远端，供主控据实重新协调说明框与操作区（保持文字完整、正常字号与舒适留白），
不走压缩文字路线。执行者未自行增加高度或突破按钮间隔/二级框净空。