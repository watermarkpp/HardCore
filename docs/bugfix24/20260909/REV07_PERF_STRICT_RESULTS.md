> 当前结论见 [FINAL_REVIEW.md](FINAL_REVIEW.md)：最终生产 909821c9，输入专项通过；最终性能 12/12 未达标，旧阶段记录不得作为最终性能通过。APK 核验另见交付记录。

# REV07 严格性能对照

日期：2026-09-09。探针在两树使用相同字节：

- `tests/hc_monster_ai/performance_comparison_test.gd` SHA-256 `44255E029F12B2B6D248E2D827D41B6ABD47C7D49C4FC3DEAD378AA00A16CEC1`
- `tests/hc_monster_ai/performance_comparison_test.tscn` SHA-256 `CE5BA79361EC9993B7BFDEBD2DC65B0EF4CC2A68CC6EF34869A12508AB513F13`
- baseline：`cf1d2718befdef7e6cc2fb274fd91ce0759d105f`，保留既有 W4 overlay；candidate 工作树生产 `scripts/assets` 逐项等于 `675005cd`，探针提交前 HEAD `db66073a2e7f55078318cf0661e3652e3d5e0f47`
- 每次固定同一 `MAP_ID=1`、`MONSTER_ID=64`、seed `20260909`、warmup `45`、sample `150`、数量 `10/20/30`，四场景串行；`full_frame_ms` 是相邻 process callback 的 `Time.get_ticks_usec` 墙钟间隔。

执行命令（每次只替换 label/head/scenario）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -TestPaths @('tests/hc_monster_ai/performance_comparison_test.tscn') -TimeoutSeconds 60
```

8 次 runner 均自然退出并 PASS，`engine_log_errors=0`。下表是 12 档 `full_frame_ms.p95`，阈值为 `max(baseline*1.05, baseline+0.5ms)`；性能阈值判定全部 FAIL，保留原始结果，不据此宣称优化或设备收益。

| 场景 | 怪物数 | baseline p95 ms | candidate p95 ms | 阈值 ms | 阈值内 |
|---|---:|---:|---:|---:|:---:|
| open_pursuit | 10 | 8.851 | 11.182 | 9.351 | 否 |
| open_pursuit | 20 | 10.274 | 18.229 | 10.788 | 否 |
| open_pursuit | 30 | 11.909 | 20.490 | 12.504 | 否 |
| sustained_close_attacks | 10 | 8.644 | 12.974 | 9.144 | 否 |
| sustained_close_attacks | 20 | 10.253 | 23.577 | 10.766 | 否 |
| sustained_close_attacks | 30 | 11.703 | 195.682 | 12.288 | 否 |
| world_obstacles | 10 | 9.255 | 10.468 | 9.755 | 否 |
| world_obstacles | 20 | 10.799 | 12.875 | 11.339 | 否 |
| world_obstacles | 30 | 13.528 | 15.583 | 14.204 | 否 |
| dense_crowd | 10 | 8.763 | 12.076 | 9.263 | 否 |
| dense_crowd | 20 | 10.242 | 21.029 | 10.754 | 否 |
| dense_crowd | 30 | 11.789 | 177.512 | 12.378 | 否 |

每个 JSON 保留 p50/p95/p99、实际 actor/motion/attack、scheduler service/expansion、逐 actor proof 和原始诊断。旧 baseline 不含 `path_search.gd`，探针改为运行时可选读取并将该诊断标为不可用；baseline 的旧 Enemy 仍按真实 physics 路径运行，未向 baseline 添加生产寻路代码。

candidate JSON：

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-rev07-perf-20260909\outputs\hc_monster_ai_package\rev07_strict_candidate_open.json`

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-rev07-perf-20260909\outputs\hc_monster_ai_package\rev07_strict_candidate_sustained_close_attacks.json`

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-rev07-perf-20260909\outputs\hc_monster_ai_package\rev07_strict_candidate_world_obstacles.json`

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-rev07-perf-20260909\outputs\hc_monster_ai_package\rev07_strict_candidate_dense_crowd.json`

baseline JSON 与 runner 原始日志位于：

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-audio-baseline-20260909\outputs\hc_monster_ai_package\` 和 `C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-audio-baseline-20260909\outputs\test_logs\`

candidate runner 原始日志位于：

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-rev07-perf-20260909\outputs\test_logs\`

首次 baseline 缺资源的 preflight 原始失败已归档至：

`C:\Users\Administrator\Documents\HardCore-worktrees\bugfix24-audio-baseline-20260909\outputs\hc_monster_ai_package\rev07_strict_raw\baseline_open_preflight_missing_path_search\`

这是 headless Windows CPU/墙钟采样；未做 Android 或设备混音验收。
