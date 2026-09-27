# HC-MONSTER-COMBAT-R2 交付单（DELIVERY）

- 交付 HEAD：`ec7ac6cb`（分支 `codex/monster-combat-r1-20260925`，施工树 `mct-r1-f5d6308f`）
- 基准：BASE `f5d6308f`（主树 `codex/integration` 未动）；R1 审查对象 `9a399c24`
- 审查结论：CHANGES_REQUIRED 十项（R2-01..R2-10）全部整改，开放 REGRESSION=0
- 边界：未 merge 主树；push 于本交付单提交后执行

## 1. 提交链（11 个 R2 提交）

| 提交 | 内容 |
|---|---|
| `ab7b0bc0` | T0：性能探针脚本交付 + `.gitignore` 两条精确例外（修复 probe .gd 被吞） |
| `3d3b845e` | T0：需求账本 / 基线登记 / 原始要求归档（三来源对账，1 份 SOURCE_UNAVAILABLE 如实登记） |
| `22086d04` | T2：生成器唯一烘焙路径恢复 + 注入器退役 + 严格档位身体校验（坏 profile fail-closed） |
| `c4be5126` | T5：复活耐久恰一次（致死物理击派发恰一次耐久 + 恰一次复活消耗） |
| `66204ba8` | T3：攻击表现链重做（动作 ID/逻辑年龄/朝向/音频阶段 + 最新受击 + 持续背压） |
| `930cec43` | T4：direct-magic 延期真实下一步位移 + 毒自然过期重挂验证 |
| `49ae4879` | T1：全 ID runtime 普查（156 条 = 147 战斗 + 9 合同禁战）+ 真 Boss 20 起手 |
| `ad981dce` | T6：召唤 spawn 快照严格化 + 真实身体对八方向门（1.5 GU start reach） |
| `2ba6dadf` | T7：基线/候选配对性能探针（3 组 workload × 10/20/30） |
| `aa25866a` | T7：critical 新失败 Level 4 分类 → 5 项测试夹具回归修复（T3 时钟缝 / T2 身份绑定 fixture 对齐） |
| `ec7ac6cb` | T7：failure_register / coverage R2 重裁决回填 + .uid 侧车补交 |

## 2. Full critical（R2 正式证据）

`runner_results_critical_20260926_213740_693_4912.json`（head=`2ba6dadf`，修复提交前）：

- total=491，passed=457，failed=34
- 失败构成（Level 4 逐项分类，证据链在 `failure_register.json`）：
  - **28 项 BASELINE_EXISTING**：R1 登记失败同断言/同因/同文本复现（caster 动画 ready 期 add_child、MFC1 ID 33/183/241 权威缺失、V2 快照族、经典 boss 断言等）
  - **2 项转绿**：`bich_monster_visual`（R1 :78 钉耙猫）、`vertical_slice_loop`（R1 负载抖动定性获 R2 复证）
  - **5 项夹具回归（已修复）**：`monster_struck_visual_queue`、`monster_streaming_animation_continuity`、`placeholder_attack_animation`（T3 逻辑时钟年龄制下手动 delta 推进不消耗墙钟 → fixture 注入 `_clock_ms` 缝 / 改用 `_start_attack_visual` 稳定原语）；`monster_audio_hook`、`audio_w4_actor_service`（T2 身份绑定 fail-closed 使裸 fixture 战斗关闭 → fixture 绑定真实烘焙 body_profile）。基线复证 `runner_results_adhoc_20260926_213912_331_14040.json`（R1 提交 6/6 PASS）；修复复跑 `runner_results_adhoc_20260926_214506_675_18720.json` + `runner_results_adhoc_20260926_214753_858_3272.json`
  - **1 项负载敏感**：`bich_common_client_art`（critical 序列 FAIL，隔离 PASS `runner_results_adhoc_20260926_214219_432_22688.json`；与 R1 `vertical_slice_loop` 同族）

## 3. R2 十项验收

| 项 | 内容 | 状态 | 测试 |
|---|---|---|---|
| R2-01 | 复活耐久恰一次 + 恰一次复活消耗 | PASS | `revival_durability_test` |
| R2-02 | 攻击动作身份/逻辑时钟/朝向/音频阶段 | PASS | `attack_presentation_identity_test` + `attack_clock_red_test`（行为级 RED→GREEN） |
| R2-03 | 保留最新受击 + 持续背压 | PASS | `attack_presentation_identity_test`（双受击 0.39s 场景）+ struck 队列有界收缩 |
| R2-04 | 严格档位身体校验 + 坏 profile 拒绝 | PASS | `monster_body_rejection_test`（fail-closed + meta `body_policy_rejected`） |
| R2-05 | 生成器唯一路径 + 注入器退役 + 漂移真语义 | PASS | T2 生成链（classification 哈希漂移显式拒绝） |
| R2-06 | 性能探针脚本交付 + 忽略规则修复 | PASS | `paired_perf_probe_test.gd` tracked + `.gitignore` 例外 |
| R2-07 | 全 ID 普查 + 真 Boss 20 起手 | PASS | `monster_runtime_census_test`（147+9=156；238/239/76×20） |
| R2-08 | 召唤快照严格化 + 真实身体对 | PASS | `summon_body_spawn_consistency_test` + `body_pair_eight_direction_test`（8 方向×1.499/1.5/1.501，checked=32） |
| R2-09 | 29+1 失败逐项重裁决 | PASS | `failure_register.json`（30 entries，`r2_re_adjudication.status=DONE`） |
| R2-10 | ≥3 组基线/候选 10/20/30 配对 | PASS | `r2_paired_perf_9028.json`（候选）/ `r2_paired_perf_baseline_R1.json`（R1 同探针） |

## 4. 性能配对结论

P50 差异 -2.8%..+11.3%（最小档噪声区间）；n=30 全档持平或更优：small_swarm 1.66→1.64ms、large_and_pet 2.91→2.97ms、aoe_mass_death 1.69→1.64ms。原始数据见 `outputs/test_logs/r2_paired_perf_9028.json`（候选 HEAD）与 `r2_paired_perf_baseline_R1.json`（R1 `9a399c24` 同探针），配套 runner 证据 `runner_results_adhoc_20260926_201710_412_3900.json` / `runner_results_adhoc_20260926_201817_021_2636.json`。

## 5. 测试命令

```powershell
# full critical（已跑，本轮 1 次）
& tools\run_godot_tests.ps1 -Suite critical

# 定向（示例）
& tools\run_godot_tests.ps1 -TestPaths @('tests/hc_monster_combat_r2/attack_presentation_identity_test.tscn')
```

正式结论只认 `outputs/test_logs/runner_results_*.json`。

## 6. integration 接入注意

1. 本包继续改动 `scripts/enemy.gd`、`scripts/monster_visual.gd`（专业树所有权）+ `scripts/monster_ai_package/policy.gd`；共享文件冲突以 integration 串行裁决。
2. T3 逻辑时钟合同：测试 fixture 若手动推进时间必须注入 `_clock_ms` 缝或走 `_start_attack_visual` 原语（本轮 3 个夹具回归即此因）。
3. T2 fail-closed 合同：无 `combat_body_profile` 的战斗类 EnemyActor 战斗关闭——战斗类测试 fixture 须绑定 `MonsterIdentityScript.body_profile(id)`。
4. T6 召唤快照字段为 `target_combat_radius_gu`（非 `radius_gu`）；FREEZE-P0.1 缺投影拒路径保留。
5. 既有 28 项 BASELINE_EXISTING 与本包修改链无交集，留证待所有者（详见 `failure_register.json`）。

## 7. 未解决风险与遗留

1. **干净检出运行验证：NOT_VERIFIED**（实施说明：验证进行中遭遇 Windows 系统故障，进程创建层崩溃；已完成的验证为干净检出 HEAD=`aa25866a` 零 dirty + probe .gd/.tscn 均 tracked + runner/R1 探针文件存在性核对；Godot 运行级验证因导入步骤触发系统级故障而中止，未重试）。probe 源码本身在施工树与 R2 critical 中均以同一 tracked 路径运行 PASS。
2. 28 项 BASELINE_EXISTING（同 R1 交付单第 4 节清单，本包零交集）。
3. 生成器既有源漂移（R1 遗留，T2 已恢复生成器唯一路径并显式拒绝漂移，authority 修复仍属所有者）。
4. 临时树 `mct-r1-f5d6308f`、基线树 `mct-r1-baseline-check`、干净验证树 `mct-r2-clean-check` 保留待验收后清理（逐树安全门禁）。
5. 证据归档：`outputs/test_logs/` 全部 `runner_results_*` + `r2_paired_perf_*` JSON 已随树保存；SHA256 清单见 `DELIVERY_MANIFEST.sha256`。

## 8. 原始要求对账

见 `REQUEST_LEDGER.md`（三来源：两份已恢复原文 + 1 份 SOURCE_UNAVAILABLE 如实登记）与 `coverage.json`（R2-01..R2-10 全 DONE + protected_paths_zero_diff 5 文件）。
