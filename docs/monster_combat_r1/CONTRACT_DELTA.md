# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 合同变更（CONTRACT_DELTA）

本文件只记录**对既有合同/行为的可观察变更**与**保留的旧契约**。不变行为不列。

## 1. 新增合同

| 合同 | 内容 | 权威位置 |
|---|---|---|
| `hardcore.actor.body_policy.v1` | 两档脚底身体策略：small 16px / large 0.5 GU（22.627416997969522px）；player 18px 冻结；召唤档位；0.50625 GU 上界不变量；未知 ID reject_at_build | `assets/data/actor_body_policy_v1.json` |
| `combat.body_profile`（目录字段） | 每个怪物条目烘焙：policy_id/contract_id/policy_sha256/tier/assignment_rule/screen_radius_px/ground_radius_gu | `assets/data/runtime/canonical_monster_catalog.json`（唯一烘焙路径：生成器 + 有界注入脚本） |
| 怪物身体半径权威 | 实例半径**只**来自已校验 body_profile；旧 is_boss 28px 常量与行为配置 collisionRadius 不再是半径权威（前者常量保留但无调用者，后者降级 historical_source_only） | `scripts/enemy.gd` `_ready` |
| 召唤物身体约定 | 脚底形状=共享 16 点等距凸多边形（替换屏幕 CircleShape2D）；skeleton=small、divine_beast=large；出生占用快照与物理身体同半径 | `scripts/summon_actor.gd` |
| 诊断计数器 | `monster_damage_rejected_nonpositive`、`monster_direct_magic_walk_delay_blocked_steps`、`monster_presentation_struck_merged`、`monster_body_policy_fallback` | RuntimeDiagnostics |
| 测试门禁 | `tests/hc_monster_combat_r1/` 11 场景进入 critical suite | `tools/run_godot_tests.ps1` |

## 2. 行为变更（可观察）

1. **非正伤害**：`amount <= 0` 的怪物对玩家伤害不再产生 HP 变化、仇恨或睡眠唤醒（原：0 可绕过边界产生仇恨变化）。
2. **死亡原子性**：致死一击的 stats/durability/struck 广播发生在死亡状态提交之后；监听者重入 `take_damage` 不再产生第二次 epoch/第二次 `death_requested`；死者拒绝控制与毒（此前控制可在死亡瞬间落地）。
3. **复活路径硬直**：复活分支不再触发死亡同款 struck 硬直（`hp_after_damage > 0` 判据）；复活分支保持原单次 emit 集（语义差异：复活那次打击不再有受击硬直表现——旧实现为等价触发，属于缺陷面）。
4. **攻击表现**：受击背压下怪物攻击视觉改为合并（保留最新受击槽），不再 FIFO 排队 16 深度；音频播报与实际开播一致。
5. **连续法术走位延迟**：autonomous step 在 direct-magic 延迟窗口内被跳过并计数（时钟源判定一致化；stale fixture 不再误判）。
6. **Boss 身体**：所有 boss 由 28px 屏幕圆改为 0.5 GU 等距脚底（22.627px）；命名大型精英家族 7 ID（56/73/74/75/89/90/91）同档；其余怪物统一 small 16px。**档位只决定物理脚底，不授予能力/射程/属性。**
7. **召唤物身体**：骷髅 15px 圆→16px 等距脚底；神兽 21px 圆→22.627px 等距脚底。

## 3. 保留的旧契约（未删）

- `MonsterVisual.play_attack` FIFO：保留为预览/测试契约入口（`PRESENTATION_QUEUE_CAPACITY` 语义不变）；运行时攻击入口走 `begin_attack_presentation` 仲裁。
- `ArtSpec.MONSTER/BOSS/PLAYER_COLLISION_RADIUS_PX` 常量保留（显示/历史引用）；`WorldSpatialRules` 16 点模板与全部转换函数原样；`MonsterUnitAdapterScript.collision_radius_gu` 定义保留（无运行时调用者）。
- 攻击节奏常量 `START_GU=1.5` / `PREFERRED_GU=1.5` 语义不变（中心到中心门禁；1.5 是中心距，**不**做半径补偿）。
- 召唤物攻击长度常量（155/135px 等）不属于身体档位，未动。

## 4. 债务登记

1. **F07 回执重构**：本次仅镜像既有 `apply_monster_poison` 守卫实现死者拒控/拒毒；完整回执（收据签发/消费/对账）重构记独立工作包。
2. **生成器源漂移**：`special_normal_monster_spawn_authority_v1.json` 记录的 classification 哈希与检入文件不一致（BD7D… vs FD7F…），阻塞 `build_canonical_monster_catalog.py` 完整再生成；本次构建经 `tools/apply_actor_body_policy_v1.py` 有界注入完成。需所有者裁决后恢复生成器为唯一烘焙路径。
3. **divine_beast_animation_test:110**（死亡动作保留断言）：基线同断言同因失败（BASELINE_EXISTING），本包未修。
