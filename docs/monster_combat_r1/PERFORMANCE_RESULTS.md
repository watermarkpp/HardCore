# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 性能结果（PERFORMANCE_RESULTS）

## 1. 桌面 headless 采样（本轮证据）

- 场景：`tests/hc_monster_combat_r1/monster_crowd_scale_performance_probe_test.tscn`
- 方法：真实 `EnemyActor`（monsterId 18）围玩家 3.5 GU 环形出生，钉住追击目标，驱动 60 个全帧等效（每帧对每怪调用完整 `_physics_process(1/60)`），`Time.get_ticks_usec()` 计时；10/20/30 三档。
- 证据：`outputs/test_logs/runner_results_adhoc_20260926_013131_120_5272.json`（PASS）+ `outputs/test_logs/monster_crowd_scale_performance_probe_test.stdout.log`。

| 规模 | 追击数 | 每帧等效均值 | 每帧等效最大 | 占 33ms 帧预算 |
|---|---|---|---|---|
| 10 | 10/10 | 0.582 ms | 0.911 ms | ~1.8% |
| 20 | 20/20 | 1.156 ms | 1.821 ms | ~3.5% |
| 30 | 30/30 | 1.752 ms | 2.707 ms | ~5.3% |

- 缩放近似线性（10→30 均值 ×3.0），30 怪全帧等效占用 <6% 帧预算；两档身体（16px/22.627px 多边形脚底）未引入超线性成本。
- 护栏断言（松）：各档均值 <33ms；追击数 ≥ 半数。护栏是回归闸，不是设备指标。

## 2. 与既有基线的关系

- 未做"改前/改后"对比：本包身体变更（boss 28px 圆→0.5GU 多边形；神兽 21px 圆→22.627px）属正确性整改；采样数字为本包提交 `5401a0bc` 的绝对水平记录。基线树（`mct-r1-baseline-check`）同样可跑该探针作对照，属后续可选复核，不在本轮授权内重复消耗。
- 既有 `monster_crowd_performance_test`（96 怪 crowd 索引断言）在 Level 2 保持 PASS（`runner_results_adhoc_20260926_001720` 中 m30/r1_core 与 crowd 相关项 PASS；96 怪 crowd 套件归 monster streaming 域，critical 内执行结果见 TEST_RESULTS）。

## 3. 设备验证

- **DEVICE TEST: NOT_RUN**（无 APK/模拟器授权；按任务边界记录，不与桌面采样互相替代）。
