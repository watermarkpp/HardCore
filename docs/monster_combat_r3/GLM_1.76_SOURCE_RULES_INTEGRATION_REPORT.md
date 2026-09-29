# HardCore 1.76 来源规则复核与 GLM 施工 · 镜像工作树集成报告

- 工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\glm53-r1-20260929`（分支 `codex/glm53-r1-20260929`）
- 基线：主树 `codex/integration` @ `8181f197b09b0aafc8ed8de0c5604c5edacbed7f`（v97），全程未改动
- 本树 HEAD：`6d7cf8fe3`（施工提交清单见 §7）

## §I 实施报告（按施工包任务序）

### Task 1 消息分类
来源规则消息 → 基线三分类通道建立：`BASELINE_EXISTING / FAIL_CHANGED / REGRESSION`，证据只取 `outputs/test_logs/runner_results_*.json`。

### Task 2 来源行动门（决策门）
`scripts/enemy.gd`：`_source176_take_tick_decision()`（L8783 区域）接入 `_hc_tick_melee`；普通近战 in-zone 起手必须经 `MonsterMovementCadence.evaluate()` 的 GRANT（`SOURCE_DECISION_WAIT` / `COOLDOWN_HOLD` 除外）；`_source176_decision_now_ms` 按 wall-ms 缓存（M01A 口径）；特快（Boss/特殊投递 kind）保持原即时起手路径（L8883）。

### Task 3 统一普通近战几何
`Source176Melee.continuous_adjacent`（L∞ 盒，EPSILON 0.0001 / HALF_EXTENT 1.0）成为普通近战唯一准入几何：`_source176_melee_reach_ok`、`_hc_step_can_end`（L8940）、`_deal_melee_hit`、`_hc_frontline_at` 等全部走盒；特殊投递（CowKing 类 76/239）按包规则保留旧 1.5 圆。

### Task 4 稳定八向步
`SourceStepPlan.next_leg`（一次一步 8 向）接入 F-leg（L1854-1895）：普通追击腿 = 8 向单步；接触上限（L1867-1885）按 `_contact_distance_gu_to_target` 截断；`_hc_neighbor` 普通分支（L9356+）采用"先静态合法则采用、否则回退旧任意角 1-GU 锚切"的契约保持策略（修 REPATH_PENDING 回归，commit `9d1fae616`）。

### Task 5 父动作准入
`SourceActionBoundary.can_reserve_body_action`（每真实引擎帧一次提交，`Engine.get_physics_frames()`）接入 `_try_reserve_source_body_action`（L466），三个调用点（2932/8219/8598）统一 reserve→commit；`BODY_ACTION_BUSY` 为唯一拒绝原因。

### Task 6 验收与分类（docs/03 §6 终表）
Level 1（新增/修改测试）全部 PASS；Level 2 相关回归修复后 PASS；Level 3 首轮 full critical 538 项中 41 FAIL → Level 4 基线对照（detached 8181f197b）分类：

| 判定 | 数量 | 说明 |
|---|---|---|
| REGRESSION（已修 PASS） | 5 | d3_boundary（spawn grounding + 通道判定）、skeleton_spirit（相位+0.98 锚定）、census（settle 内 GRANT 写回，二次盖相位）、w1_exact_ranged（T06 同帧拒绝生效后需跨帧）、production_snapshot/enemy_snapshot_v2（E1 盒外拒结算 → victim 迁 0.98）、body_multitarget/parent_release/combat_epoch（同模式摆位迁移）、audio_w4（时序敏感，观察项） |
| FAIL_CHANGED（夹具迁移） | 同上合并 | E1 盒几何的预期行为变化，全部夹具侧修复，生产零回退 |
| BASELINE_EXISTING | 24+ | bich_environment(911001)、orc_tomb×2、source_collision(911001/401/402/911103)、vertical_slice、natural_cave(248)、phase1、wooma、town_music、ui_error、warrior_visual、equipment(护身戒指)、game_root(magic_evaded)、canonical_summon(zero-MP)、death_revival(gameplay input)、service_home、player_poison、player_level_up、loot、mobile_targeting、audit_39fe(签名老债)、melee_blocked_query_order(null-target)、natural_cadence_24/76、all_damage_lost(60s)——全部在基线 8181f197b 上同断言同文本复现，为 v97 主树既有债务，与本任务无关 |
| runtime_test 基线组 | 6 | T01/T02/T06/C02×3：基线同名同文本失败（T06 在本任务中已被 Task 5 修复为 PASS；w1 因此需要跨帧，见上） |

## NOT adopted / 债务清单（按包约定）
1. target-magic 与 area-magic 的 admission gating 未纳入本包（保持现状）。
2. F1 sub-step budget 未尝试。
3. E2：0.25 命中容差保持原样。
4. 决策时钟按 M01A 采用 wall-ms。
5. C02 的 GU 停留带检查按 E1 退役（源邻接 0.959 GU 为精确恢复；实体阻挡由碰撞层承担）。
6. runtime_test 的 T01/T02/C02 组、24+ BASELINE_EXISTING 项为主树既有债务，未擅自动。

## §7 冻结与提交清单
- 主树 `8181f197b` 全程字节级未动；未合并、未推送、未构建/安装 APK。
- 本树施工提交（基线之上）：`14697c0e4` 夹具 → `9d1fae616` 邻居契约 → `f8f0b8266` 接触上限+运行夹具 → `b6f327ca7` d3+骷髅 → `963df7e11` census 相位 → `c2276fb1e` 身体对/父身份/epoch 夹具 → `10430232b` no-legacy victim → `4cc2f7fdb` w1 跨帧 → `6d7cf8fe3` snapshot v2 victim。
- 确认性 full critical（第二次，Level 3 允许）：`runner_results_critical_*.json`（outputs/test_logs/），终态数字见 §6 更新。

## §6 终态（full critical 确认轮）
- 首轮 critical（HEAD `9c9f5da8` 段）：TOTAL=579 PASSED=538 FAILED=41（`runner_results_critical_20260929_141809_347_7904.json`）→ Level 4 全部完成三分类。
- **确认轮（第二次 critical，HEAD `3f07c4ab5`）：TOTAL=579 PASSED=552 FAILED=27**（`outputs/test_logs/runner_results_critical_20260929_171850_411_19568.json`，git_head 字段为准）。
- 27 项 FAIL 逐项核对 = 全部 BASELINE_EXISTING（v97 主树 8181f197b 上同断言同文本复现）：runtime_test（T01/T02/T06/C02×3 基线组）、canonical_summon(zero-MP)、service_home、death_revival(gameplay input)、audit_39fe(Parse 签名老债)、warrior_visual(windup)、mobile_targeting、wooma、phase1(911101)、orc_tomb×2(911001)、source_collision(911001/401/402/911103)、natural_cave(248)、bich_environment、vertical_slice(911001)、equipment_special_effects(护身戒指)、game_root_combat_resolution(magic_evaded)、loot_stable_identity、player_level_up、warrior_melee_entry、all_damage_lost(60s)、natural_cadence_24/76(60s)、ui_error、player_poison、town_music、melee_blocked_query_order(null-target 61×)。
- **REGRESSION = 0**：本任务全部相关测试 PASS——w1_exact_ranged、real_admission_census、d3_boundary、d3_motion_pressure、body_multitarget、attack_parent_release_identity、combat_epoch_delivery、crowd_surround、skeleton_spirit_boss、audio_w4、production_snapshot_no_legacy、enemy_snapshot_v2_production、monster_continuous_step_facing、monster_movement_cadence 全系、source176_delivery/decision_gate、corpse_king_boss、natural_cadence_238/239/24_chase。
