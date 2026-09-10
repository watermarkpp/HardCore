# M30-R4 交付报告（codex/m30-r4-flash @ fcc85acd）

基线：`codex/integration` = `c91781bd`（AIA2 合并后最新有效提交）。施工分支 `codex/m30-r4-flash`，共 8 个提交，全部为任务文件。未合并回 integration（按流程由 integration 后续接入）。

## 一、核心施工（5b78c7ef）

按施工包 `tools/apply_patch.py` 同一变换函数实施（未重写架构）。三个干净文件（enemy.gd / path_search.gd / monster_visual.gd）与参考安装器在 1cbf61af 的输出**逐字节一致**；game_root.gd 因 AIA2 已改（blob `2ac3fd4f…` ≠ 审计 `2daf815e…`），按执行令 C 条做最小适配：适配差集与 AIA2 delta（1cbf61af→4f9faaf1）11↔11 hunk 对应（`outputs/m30r4_evidence/game_root_adapted_vs_reference.diff`、`aia2_game_root_delta.diff`）。

- 新增生产模块：`scripts/monster_ai_package/m30/{context_token,summon_queue,walk_phase}.gd`（包核心逐字）
- 变更：enemy.gd（身份令牌目标缓存、攻击姿态物理提交、纯门禁步进、近战相位喂入、召唤生产者重写）、game_root.gd（预算化召唤队列接收端、96 次落点搜索、材料化追踪钩子）、path_search.gd（身份令牌缓存键 + frontier 诊断）、monster_visual.gd（走相位表现、攻击收尾取消）
- 预算合同：每物理帧全局探针 ≤8、材料化 ≤1、每子怪尝试 ≤96、预留/容量/世代失效

## 二、性能（REV07 全帧，同机交替采集，6+6 轮）

命令：`tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/hc_monster_ai/performance_comparison_test.tscn`，标签 v72_r1–r6（基线 909821c9）/ cand_r1–r6（候选 fcc85acd 前身 6116e85b，生产代码同）。门禁：`candidate_p95 ≤ max(v72_p95×1.05, v72_p95+0.5ms)`。

| 场景 | n | v72 p95 | 候选 p95 | Δ | 门禁 | 判定 |
|---|---|---|---|---|---|---|
| dense_crowd | 10/20/30 | 17.24/24.64/30.77 | 17.02/24.85/28.93 | -1.2%/+0.8%/-6.0% | 18.10/25.88/32.31 | PASS×3 |
| open_pursuit | 10/20/30 | 16.76/22.45/25.88 | 17.08/22.06/26.39 | +1.9%/-1.7%/+1.9% | 17.59/23.57/27.18 | PASS×3 |
| sustained_close_attacks | 10/20/30 | 18.71/27.05/32.70 | 18.10/23.97/34.47 | -3.3%/-11.4%/+5.4% | 19.64/28.40/34.34 | PASS/PASS/**FAIL** |
| world_obstacles | 10/20/30 | 16.30/19.71/22.59 | 16.24/19.92/22.65 | -0.4%/+1.0%/+0.3% | 17.11/20.70/23.72 | PASS×3 |

- **11/12 PASS；sustained_close_attacks@30 FAIL**（34.468 vs 门禁 34.337，差 0.131ms）。轮值高度重叠（v72 31.6–36.2，候选 27.8–37.1，候选最好轮 27.75 全场最优），但按预声明门槛如实记 FAIL，不得写"已彻底解决"。
- 历史绝对门槛（旧版 11.962/11.720 → 门禁 12.56/12.31）对**基线与候选同时 FAIL**：本机 headless 环境 p95 整体在 ~17–35ms 量级，历史数值不可在本机复现；同环境相对对比为有效度量。机器差异已记录，不作为性能 PASS 依据。
- Plan B（stable-goal-field）：实测 frontier 重建仅 world_obstacles@30 出现 26 次/3.07ms（窗口总量 ≈0.02ms/帧），非热点 → 保留 A 方案，B 无测量依据启用。

## 三、真实世界复现（45ea7884，PASS 23/23）

场景 `tests/m30_r4/test_m30_summon_reproduction.tscn`（正式地图 910001 + 权威出生事务 + 生产召唤队列）：

- 母体=**126 角蝇**（固定体召唤者，summon_rule{monsterIds:[127], count:1, maxActive:15, delay 0.5s}）→ 子怪=**127 蝙蝠**
- 子怪 collision_radius_px=**16.00**（= ArtSpec.MONSTER_COLLISION_RADIUS_PX 默认占地；与目录一致，无阻断）
- 流程：首生 → 玩家立于刷新点旁观察 → 击杀母体 → 生产函数 `_respawn_later` 复活（生产档位最低 300s，测试以 0.1s 调用同一事务，代码路径不变）→ 续召累计 4 只、旧世子怪全部存活 → 清场
- 快照：max_probes_in_tick=1（≤8）、max_materializations_in_tick=1、capacity_rejected=0、reserved 全释放、pending 清空、duplicate_release=0
- **发现（如实）**：单次 `_spawn_enemy` 原子调用冷资源尖峰 43.7ms（新场景首次生成蝙蝠图集）。队列预算无法抢先引擎单次调用；v72 同样存在该成本。包文档已声明此边界——后续改进方向是出生资源准备链，不是继续调队列。

## 四、消融（ACCEPTANCE.md A/B/C/D）

- **B（无母体虫群负载）**：12 组性能场景即直连怪（无母体）负载，已实测（上表）。
- **A（母体存活拦截新增出生）**：test_m30_core 容量拦截检查（queued reservations prevent cap overflow、capacity_rejected 路径）+ 复现场景快照覆盖；未改 summon_rule.enabled。
- **C（母体逻辑停止 vs 动态阻挡）**：复现场景击杀母体后 pending 出生取消（cancels pending births）、子怪存活、复活母体续召——召唤工作与动态阻挡解耦可观察。
- **D（冷/热资源分离计量）**：`test_m30_ablation_d.tscn` PASS——冷生 3.6–6.4ms/次（逐次清缓存）vs 热生 3.3–3.9ms/次；出生后 6 子怪持续战斗 240 物理帧峰值 37.6ms（与性能夹具同量级，独立场景计量）。冷首生 43.7ms 见第三节。
- 临时测试开关均不入正式游戏数据（夹具内）。

## 五、验收矩阵（逐条）

| 条目 | 证据 | 判定 |
|---|---|---|
| 两格近战原有合同不变 | AIA2 三场景（tap/kill_release/kill_retarget）+ warrior_attack_timing + live_attack_resolution 全 PASS | PASS |
| 墙体/前排阻挡、冷却、命中延迟 | geometry_test、world_obstacle_runtime_test、combat_epoch_delivery_test、w1_* 全 PASS | PASS |
| 物理帧攻击姿态提交期 | test_m30_core：0-hit-delay→0.62s 可读姿态、0.4s 周期→0.24s 移动窗口不改冷却、命中延迟不被截断、姿态锁不阻断下一次合法攻击；runtime_test S02（窗口内暂缓 + 就绪后收敛） | PASS |
| 8 方向短步不重放第 0 帧 | `test_m30_eight_direction_steps.tscn` PASS 24/24：5/8 开放方向 walk 相位连续（回绕须落在 cycle_gu 整数倍）、walk 帧仅 phase<1/6 时为 0、攻击姿态同帧样本按 state 排除；3 方向为地形阻挡（记录） | PASS（5 方向实测） |
| 召唤预算/预留/世代失效/容量拒绝 | test_m30_core 31 检查 + 复现快照 | PASS |
| 原 12 组整帧门槛 | 6+6 轮交替采集 | 11/12 PASS，1 组 FAIL（上表） |
| 真机（手机）测试 | 未执行（本会话仅 headless） | NOT_RUN，另行安排 |
| hc_monster_ai 套件 | runtime/path/geometry/world_obstacle/combat_epoch/w1×2/lightning/inventory 全 PASS | PASS |
| 视觉/死亡/区域邻接 | bich_monster_visual、aoe_death_phase_boundary、bich/cangyue_area、输入 5 场景、monster_ground_contact* 等 | PASS（除下述预存失败） |
| monster_ground_contact_* | **预存失败**（c91781bd 主树同败）：怪物退役提交（3b2fd2dd）后动画目录 156 行而测试写死 214；monster 33 canonical status=unresolved 不入运行时 153/156 载入；cold 测试 monster 18 预取超时在基线生产代码下同样复现（隔离证据：还原四文件至 c91781bd 重跑）。已做计数夹具修正，其余归怪物域/integration 修复 | 预存 FAIL，与本任务无关 |

## 六、提交清单（c91781bd → fcc85acd，26 文件 +1297/−133）

5b78c7ef 核心施工 → 6116e85b PASS 标记夹具 → 45ea7884 复现场景 → f2cf6384 既有测试合同适配（path A-walkable 身份令牌、runtime S02 新展示合同、ground_contact 计数）→ 8ceb5797+0d992c52 8 方向短步 → 06248661+fcc85acd 消融 D。未动：掉落/地图/贴图/输入/存档/速度权威/攻击与召唤间隔。`docs/bugfix24/20260909/*.translation` 9 个未跟踪文件非本任务产物，未提交。

## 七、遗留与风险

1. sustained_close_attacks@30 相对门禁差 0.131ms FAIL（噪声量级，需真机或更强隔离环境复测；不得宣称达标）。
2. 冷首生原子尖峰 ~44ms（一次 性/图集/会话）——后续资源准备链优化点。
3. monster_ground_contact 两测试预存数据漂移待怪物域修复（33 号 unresolved、18 号预取）。
4. 真机验证未做；APK 不作为本任务成功依据。
