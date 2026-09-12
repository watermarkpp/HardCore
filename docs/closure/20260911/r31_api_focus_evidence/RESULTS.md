# R3.1 执行结果摘要 (docs/closure/20260911/r31_api_focus_evidence)

提交定位: codex/r3-1-api-focus-fix @6c0f1479 基线, apply 后 56ec4f51/31b9265d.
- 01_check: PASS (6c0f1479 blob 一致, dirty=0)
- 02_probe: install-probe 2 文件按 receipt 精确暂存 (engine_api_probe.gd 命中 legacy *_probe*.gd 忽略规则, add -f)
- 03_api: run_quick_smoke --phase api PASS (真实 4.7.stable, 独立 APPDATA, 30s)
- 04_apply: APPLIED (3 修改 + ui_style_visual_bounds.gd 新增), 05_tests: 6 文件按 receipt 暂存
- standard --import 一次, 之后 --phase core STOPPED at style_bounds_smoke (契约: 任一失败即停)

缺陷 (主管新文件, 未自行修):
- #1 ui_shop_detail_space.gd get_draw_rect -> 新测量器 control_bounds(style_bounds)
- #2 ui_item_selection_visual.gd release_focus 保护; lifecycle Viewport/焦点保护
- #3 ui_style_visual_bounds.gd:130 `var states: Array[StringName] = STATES if control is BaseButton else []`
  无类型 `[]` 赋 Array[StringName] -> GDScript 运行时类型错; 子调用中止致父帧 :145 读 .ok on null.
  style_bounds_smoke FAIL(6 script errors); selection_detach_smoke 未达 (契约停). 最小复现: run_quick_smoke --phase core.
- audit: R31_CORE_INTACT_NOT_RUNTIME_ACCEPTANCE (仅代码身份).

M30 (第1轮, headless, 每格真实样本数见下; s30 n=301 <320 采样不足):
pursuit    x12 p50=4.25 p95=16.39 p99=18.78 max=19.72 n=324
pursuit    x15 p50=4.84 p95=17.69 p99=20.02 max=22.56 n=326
pursuit    x30 p50=3.85 p95=23.66 p99=29.26 max=32.33 n=334
sustained  x12 p50=4.36 p95=18.14 p99=22.86 max=23.39 n=323
sustained  x15 p50=4.66 p95=19.07 p99=21.35 max=25.11 n=331
sustained  x30 p50=5.90 p95=27.40 p99=35.84 max=42.42 n=301 (<320)
尾部越线: 仅 sustained x30 p99/max 超 33.3ms 线; pursuit 全档 max<33.3.
12/15 桌面可行 (add_m30_counts.py 副本 COUNTS=[12,15]).
工具缺陷: add_m30_counts.py 生成 candidate.tscn 根 type=Node, 而脚本继承 Node2D -> 场景脚本未挂载,
空转无采样。已对生成测试副本最小机械修正 type=Node2D (非生产/非断言), 原 M30 夹具与断言不变。

NOT_RUN/BLOCKED: R3 shop_space 四分片+close_selection+prewarm/hidden_views/相邻回归 (被 #3 阻断);
视觉窗口30px/净空/截图; UI端到端延迟(seed_builder); B=v74 vs C 三轮 Before/After 矩阵; 0/5 + 扩展场景;
临时组合树 b329/9cf; 设备/APK。
