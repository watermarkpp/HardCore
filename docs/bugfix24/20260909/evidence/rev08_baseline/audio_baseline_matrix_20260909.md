# 音频基线固定矩阵

- 工作树：`HardCore-worktrees/bugfix24-audio-baseline-20260909`
- 基线：`cf1d2718befdef7e6cc2fb274fd91ce0759d105f`
- 引擎 SHA：见 `godot-4.7-stable.sha256.txt`
- 命令（每次独立执行，`-TimeoutSeconds 60`）：
  `.\tools\run_godot_tests.ps1 -TestPaths <scene> -TimeoutSeconds 60`
- 每次结果均复制为 `<scene>_r<1..3>.stdout.log`、`.stderr.log`、`.godot.log`、`.runner.json`；没有超过 3 次尝试。

| 场景 | r1 | r2 | r3 | 汇总 |
|---|---|---|---|---|
| `smoke_test` | FAIL，marker=true，engine=2 | PASS，engine=0 | PASS，engine=0 | 2/3 runner PASS |
| `warrior_visual_test` | PASS，engine=0 | PASS，engine=0 | PASS，engine=0 | 3/3 PASS |
| `player_movement_respawn_test` | PASS，engine=0 | PASS，engine=0 | PASS，engine=0 | 3/3 PASS |

9 次均 `marker=true`、自然退出、`timeout=false`；失败仅为 smoke r1 的 runner 未允许错误，不是超时或缺 marker。

## 原始错误摘要

- `smoke_test_r1`：7 条原始 `ERROR:`，含 dummy `texture_2d_initialize`（`enemy.gd:2467`、`warehouse_panel.gd:484`、`game_root.gd:1745`、`ui_item_texture_cache.gd:54`）、`Initializing already initialized RID` 与 `mem is null`；后两类导致 runner `engine_log_errors=2`。
- `smoke_test_r2/r3`：各有 dummy `texture_2d_initialize`（分别 `inventory_panel.gd:584`、`warehouse_panel.gd:484`）及退出时资源仍在使用；runner allowlist 后为 PASS。
- `warrior_visual_test`：三次仅见退出时 ObjectDB 泄漏/1 resource still in use，runner allowlist 后 PASS。
- `player_movement_respawn_test_r1/r2`：仅退出资源提示；r3 另见 dummy `texture_2d_initialize`，栈为 `world_bootstrap_coordinator.gd:645` → `game_root.gd:2815`，runner allowlist 后 PASS。

这些 raw stderr 与 engine log 均已按轮次保留；本矩阵不修改 runner allowlist，也不据此宣称修复 race。基线现场保留既有 staged `tests/audio_w4_performance_probe_test.{gd,tscn}` 和未跟踪 UID。
