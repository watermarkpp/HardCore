# M30-R4R1 证据归档索引

归档自 R4 现场（分支 codex/m30-r4-flash @ fcc85acd）实际存在的原始文件。`.log` 被全局忽略，日志以 `.log.txt` 原字节副本归档。缺失项明确标注 MISSING。

## perf/（12 组整帧 6+6 轮）
- `rev07_v72_r1..r6.json`、`rev07_cand_r1..r6.json`：REV07 原始输出（未四舍五入），基线=909821c9（v72），候选=fcc85acd 生产（6116e85b，与 fcc85acd 生产代码相同，仅差测试文件）
- `analyze_rev07.py` / `analyze_rev07_final.py`：聚合脚本；`run_rev07_alternating.ps1` / `run_rev07_extra.ps1`：采集命令（标签、HEAD、树路径内嵌）
- `rev07_final_table.txt`：最终聚合表
- 命令：`tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/hc_monster_ai/performance_comparison_test.tscn`，env `HARDCORE_REV07_HEAD=<sha>`、`HARDCORE_REV07_LABEL=<label>`，cwd=各树根
- runner 逐轮 stdout：v72 侧 `…\m30r4-v72-baseline\outputs\m30r4_evidence\rev07_run_v72_r*.log`、候选侧 `…\m30-r4-flash\outputs\m30r4_evidence\rev07_run_cand_r*.log`（outputs 未跟踪，仅此处 JSON+脚本归档；MISSING：runner stdout 逐轮归档，如需可补 .txt）

## repro/（母体复现）
- `test_m30_summon_reproduction.stdout.log.txt`：M30_MOTHER_REPRO_PASS 23/23 + 快照证据
- `runner_results_repro.json`：runner 结果（exit 0）

## steps_ablation/（八方向 + 消融 D）
- `test_m30_eight_direction_steps.stdout.log.txt`：M30_EIGHT_DIRECTION_STEPS_PASS 24/24，5 方向采样 + 3 方向地形阻挡
- `test_m30_ablation_d.stdout.log.txt`：M30_ABLATION_D_PASS 冷/热生与持续战斗计量
- `runner_results_steps.json`、`runner_results_ablation_d.json`

## game_root_adaptation/（R4 适配证据）
- `game_root_adapted_vs_reference.diff`：适配后 game_root 与参考安装器输出的差集
- `aia2_game_root_delta.diff`：AIA2 delta（1cbf61af→4f9faaf1）；11↔11 hunk 对应结论见 DELIVERY_REPORT

## ground_contact/（预存失败隔离证据）
- `main_tree_c91781bd_count_fail.json`：主树 c91781bd 行 31 断言失败（目录 156 vs 写死 214）
- `r4_original_count_fail.json`：R4 树计数修正后行 62 monsterId=18 预取超时（R4 生产代码）
- `isolated_baseline_production_monster18.*`：四个生产文件还原 c91781bd 后同样失败（隔离证明）
- `r4_runtime_monster33_missing.*`：runtime 变体行 67 monsterId=33 gameplay data missing（canonical status=unresolved，运行时 153/156 载入）
- 注：`.godot.log` 单文件被每次运行覆盖，以上 .godot.log.txt 为对应最后一次运行的原字节；更早轮次仅 runner JSON 保留（MISSING：更早轮完整 stdout）

## 404 背景
R4 报告原在 `outputs/`（仓库忽略），审查方经固定 commit 读取 404。本目录为显式跟踪归档。
