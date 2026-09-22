# R3.1.1 结果 (docs/closure/20260911/r311_typed_fix_evidence/RESULTS.md)

HEAD fde1050e73dbc0c648285266336c6c86c607eb71 (codex/r3-1-1-typed-array-fix, 基线 c0afa4b3).
生产唯一改动: scripts/ui_style_visual_bounds.gd `var states: Array[StringName] = []` +
states.assign(STATES)/append(&panel) 类型分支初始化 (3->7 行, 见 core_candidate.patch)。
- 01_check PASS; 02_tests 2 文件按 receipt 暂存; 03_apply 唯一生产文件 (before/after sha 留证); 04_audit R311_CORE_INTACT.
- --phase branch 红灯留证: type_branch_smoke FAIL (旧生产无类型 [] 赋值)。
- --phase core 三连测 PASS: type_branch_smoke / style_bounds_smoke / selection_detach_smoke (真实 4.7)。

R3 续跑 (runner_results_adhoc_20260911_215519):
- PASS: hud_background_prewarm_test, hidden_views_test (selection release_focus 修复解除)。
- close_selection_test: R3_CLOSE_SELECTION_PASS checks=196 (语义清选通过), 但 FAIL = 1 处非清选错误
  HC_UI6_DETAIL_SPACE_PLAN_REQUIRED: 木剑 (shop 详情布局, presenter._fail_layout:405)。
- shop_space_0..3: FAIL, 两类:
  (a) 测试侧陈旧 API: tests/r6_3/shop_space_matrix.gd:79 inspect_row 调 style.get_draw_rect()
      (R3 时代测试遗留, 不在 R3.1.1 白名单; 生产 ui_shop_detail_space.gd 已不再调 get_draw_rect)。
  (b) 生产布局: HC_UI6_DETAIL_SPACE_PLAN_REQUIRED (shop 物品无候选布局适配测量 region)。

M30: 本轮未执行 (complete-samples 副本 + Before/After 三轮矩阵 为独立后续工作; 原 R3.1 第1轮
摘要持久于 c0afa4b3, 无逐帧原始数组)。视觉原始尺寸截图 / UI 端到端种子延迟 / 临时组合 b329/9cf
/ 设备: NOT_RUN。
