# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 交付单（DELIVERY）

- 交付 HEAD：`5401a0bc6e1e8d8836d4b744382788bc7045a398`（分支 `codex/monster-combat-r1-20260925`，工作树干净）
- 基准：`f5d6308f`（主树 `codex/integration`，未动）
- 提交序列：
  | 提交 | 内容 |
  |---|---|
  | `11ae1056` | F01–F05：攻击时序与双方向受击缺口 |
  | `0c5970a3` | Task 7：F06 伤害边界 / F08 原子死亡提交 / F07 边界镜像 / 音频夹具确定性加固 |
  | `38affced` | HC-BODY-2TIER-1P5-V1：两档脚底身体 + 逐 ID 档位表（任务 B） |
  | `5401a0bc` | Task 8-9：正式 suite 注册 + 10/20/30 怪物桌面性能采样探针 |

## 1. 验收清单状态

| 项 | 状态 |
|---|---|
| 任务 0-6（F01-F05 + 7 测试） | PASS |
| 任务 7（F06-F08 + 边界） | PASS |
| 任务 B（两档碰撞 + 档位表交付物 + 4 测试） | PASS |
| 任务 8（正式 suite 注册 11 场景） | PASS |
| 任务 9（Level 3 full critical ×1 + 桌面性能采样） | PASS（482 项 / 452 PASS / 0 REGRESSION） |
| 任务 10（交付文档 6 件） | PASS（本目录） |
| 设备帧采样（10/20/30） | **DEVICE TEST: NOT_RUN**（未授权 APK/模拟器） |
| merge / push | **未执行**（未经用户明确授权） |

## 2. 文档索引

- `IMPLEMENTATION_REPORT.md` — 实现范围与逐项落点
- `CONTRACT_DELTA.md` — 合同变更 / 保留旧契约 / 债务登记
- `INTERFACES.md` — 新增静态接口与数据文件契约
- `TEST_RESULTS.md` — 全部 runner_results 证据与 Level 4 三分类
- `PERFORMANCE_RESULTS.md` — 10/20/30 桌面采样
- `body_tier_table.json` — 逐 ID 档位表（156 条：large 27 / small 129）

## 3. integration 接入注意

1. 本包改动 `scripts/enemy.gd`（专业树所有权文件）+ `scripts/player.gd`/`player_visual.gd`（跨系统共享 combat runtime）+ `scripts/summon_actor.gd`（职业技能域共享）+ 目录数据。共享文件冲突以 integration 串行裁决。
2. `canonical_monster_catalog.json` 为生成物变更；生成器修复 special_normal 漂移后应重新完整生成一次并核对 body_profile 仍被烘焙（生成器内已含同一逻辑）。
3. 新增诊断计数器可用于上线后观察（CONTRACT_DELTA §1）。

## 4. 未解决风险与遗留

1. **生成器既有源漂移**（BLOCKED 非本包范围）：special_normal authority 记录的 classification 哈希与检入文件不一致；本次烘焙经 `tools/apply_actor_body_policy_v1.py` 有界注入完成。需所有者单独裁决。
2. **29 项 BASELINE_EXISTING**（含 caster 动画 ready 期 add_child 生产路径错误、MFC1 ID 33/183/241 权威缺失、V2 快照族、经典 boss 断言等）——留证待所有者，均与本包修改链无交集。
3. **F07 回执重构**：独立工作包债务。
4. **`vertical_slice_loop_test` 负载抖动**：套件满载下引擎日志门禁偶发（dummy renderer RID 噪声 + FRAME-STALL），隔离 3/3 PASS；建议后续为该门禁增加负载补偿或豁免清单（不在本包擅改 runner）。
5. 临时工作树 `mct-r1-f5d6308f` 与基线对照树 `mct-r1-baseline-check` 保留待验收后清理（逐树安全门禁：核对无独有未合并内容后由用户/主控授权删除）。
