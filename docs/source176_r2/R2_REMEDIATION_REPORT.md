# HardCore · GLM 来源规则施工 R2 整改报告

分支 `codex/glm53-r1-20260929` · 候选 HEAD `b9717d1da` · 基线 `8181f197b`（codex/integration）
完整提交链 33 个（R1 21 + R2 12），见 `evidence/COMMIT_CHAIN.txt`；逐文件差异见 `evidence/DIFF_NUMSTAT.txt`。

## R1 审计结论的更正

1. R1 报告所列"11 个提交"不是完整提交链——实际 21 个（R1）+ 12 个（R2）= 33 个，全部列于证据目录。
2. R1 的 `source176_decision_gate PASS` 是假 PASS（测试协程未 await，checks=0 空跑）。R01 修复后按真实执行重新取证。
3. R1 报告 Task 1 混淆了伤害投递分类（DIRECT/MINE）与测试分类（BASELINE_EXISTING/FAIL_CHANGED/REGRESSION）两套体系。本报告只使用后者，且逐项以断言文本 + 退出码比对，不使用"同名=同失败"。

## 逐目标真实记录

| 目标 | 状态 | 核心证据 |
|---|---|---|
| R01 验收工具 | PASS | 未修版假 PASS 留档（`R01_unpatched_original_output.txt`，检查数 0）；修复后 `SOURCE176_DECISION_GATE_PASS checks=16 cases=4 failures=0`；变异测试（首断言置 false）→ FAIL + exit 1 + 显式失败清单 |
| R02 共享许可 | PASS | 缓存键改 `(zone_generation, physics tick)`，每物理 tick 只 evaluate 一次；追击腿复用本 tick 决策；四场景运行时测试 11 checks 全过（C: HOLD vs PURSUE、A: 一次授权侧移、D: 不重复收费、B: 隔墙寻路） |
| R03 游戏时钟域 | PASS | 决策门、cadence 构造、direct-magic 下段门、独立路径 evaluate 全部投影 `_combat_action_time_s`；墙钟不再是决策身份（暂停/变速不可能替怪物走完等待）；六个 fixture 迁移到确定性时钟后全 PASS |
| R04 八向端点 | PASS | leg/route 提交真实 `planned_leg` 端点（顶点相等=ADOPTED）；C05 绕墙回归二分定位到分数端点检查过严 → 恢复格心合同采样+真实端点提交；八向 × 整数/分数起点 32 检查全过（锥内 dot>0.7、第二步永不反转） |
| R05 软间隙与快照 | PASS | 普通玩家近战合同 preferred 封顶盒边 1.0（legacy 0.4375 保留出生/物理分离角色）；自然接近测试：普通近战不重叠且进 1.0 盒、尸王不重叠且进自身 START_GU 圆；policy 快照导出 `source_box_half_extent_gu` |
| R06 准入与动画 | PASS | 投掷物 windup 释放帧数改从身份 appearance_profile 读（冷=热、无 blanket 延长、无 visual-gated damage）；`_hc_try_start` 的 `incompatible_pending=false` 经构造确认正确（挂起守卫先行 fail-closed） |
| R07 报告与证据 | 本文件 | 28 个原始 runner_results JSON + 提交链 + numstat 复制进 `docs/source176_r2/evidence/`；`BASELINE_AND_CANDIDATE.json` 记录基线对照 |

## 基线失败对照（三分类）

runtime_test 的 T01/T06/T02/C02×3 六项：当前与 R1 基线**同断言、同原因、同退出码** → `BASELINE_EXISTING`。每个 R2 生产提交后复跑核对，R2 期间出现过且已修复的 REGRESSION：C05-reach（R4 分数端点检查过严，见 R04）。

## 禁止项遵守

未合主树、未构建/安装 APK、未删除工作树；未引入雷电/尸王/地图特例；未加第二个 cadence；未绕过 direct-magic 下段门；未降低怪物数量/更新频率/碰撞精度。
