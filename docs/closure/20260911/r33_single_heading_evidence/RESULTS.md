# R3.3 单层标题空间修正 · 阶段交付与剩余阻断

分支 `codex/r3-3-single-heading`，基线 `d2aa9e6ae2feda2723a95edbcaf9e951a475f5b8`。

## 0. 结论（分层，不写"全部修复完成"）
- 单层标题修正**对 4 焦点物品的 16 个稳定案例全部生效**（`FOCUS_GEOMETRY_PASS_NOT_CATALOG_OR_VISUAL`，16/16）。
- 但**另有真实物品「铂金戒指」仍无 fit**（header_session 短测失败），修复**非普适**。
- 故整体 = **局部通过，仍阻断**：店铺目录/视觉/清选整场景尚未全绿。

## 1. 安装与身份
- 01_check PASS；02_tests（6 测试）APPLIED；04_apply（仅 2 生产文件）APPLIED；09_audit R33_CORE_INTACT。
- 生产改动仅 `scripts/ui_shop_detail_space.gd` + `scripts/item_detail_docked_presenter.gd`（与原包 payload 逐字节一致）。
- 运行时关键文件 SHA256 见 `geometry/*/r33_geometry.json.source_hashes`。

## 2. 短测试（run_acceptance -Phase short，首败即停）
- `header_geometry_test`：**PASS**。
- `header_session_test`：**FAIL**（470 检查后）——错误：`HC_UI6_DETAIL_SPACE_PLAN_REQUIRED: 铂金戒指`；`R33_HEADER_SESSION 铂金戒指 invalid layout`、`body lost/rewritten`。
  - 说明单层标题已让 4 焦点物品（木剑/匕首/超级金创药/超级魔法药）通过，但铂金戒指（额外真实物品）仍超出。

## 3. 修改前后几何（space_diagnostic 48 条，4 焦点物品 ×买卖×2 商人×3 阶段；16 稳定案例）
| 阶段 | 稳定案例 |
|---|---|
| 修改前 | `STABLE_LAYOUT_STILL_BLOCKED` 0/16（旧生产未导出 screen_scale/pixel_scope，新分析器拒绝） |
| 修改后 | `FOCUS_GEOMETRY_PASS_NOT_CATALOG_OR_VISUAL` **16/16** |

- 单位：几何坐标为 owner_local_coordinates；screen_scale/pixel_scope 从 snapshot.space_spec 显式导出（新采集器补足可读单位；null 不回退为 1）。
- `CAPTURE_COMPLETE_NOT_LAYOUT_PASS` = 采集完整，非布局/视觉通过。

## 4. 视觉（窗口化原尺寸）
- `run_rendered_capture.py`：**16 PNG + 侧车 JSON 已产出**（`RENDERED_CAPTURE_COMPLETE_NOT_LAYOUT_PASS`），非编辑器。
- 视觉净空/审美判定仍待主控审图；本报告不做设备像素结论。

## 5. 未执行 / 未关闭
- 完整目录 shop_space_0…3、close_selection 整场景、prewarm/hidden_views 相邻：**因短测试 header_session 首败，按合同停止，未跑全量矩阵**（NOT_RUN）。
- UI 操作延迟（真实保存/GUI/磁盘增量）：**NOT_RUN**。
- M30：**NOT_CLOSED**（本轮未改怪物代码；待同窗口 Before/After 三轮、12/15/30 原始帧、设备验收）。

## 6. 证据索引（docs/closure/20260911/r33_single_heading_evidence/）
- installer/、geometry/before/、geometry/after/、analysis/、rendered/（16 PNG+侧车）、runner/、patches/、RESULTS.md