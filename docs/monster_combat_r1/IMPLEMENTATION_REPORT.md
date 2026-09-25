# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 实施报告

- 基准：`codex/integration` @ `f5d6308f`（主树）
- 工作树：`C:\Users\Administrator\Documents\HardCore-worktrees\mct-r1-f5d6308f`，分支 `codex/monster-combat-r1-20260925`
- 提交序列：
  1. `11ae1056` fix(combat): close monster attack timing and dual-direction struck gaps (F01-F05)
  2. `0c5970a3` fix(combat): damage boundary, atomic death commit and deterministic audio fixture (Task 7)
  3. `38affced` feat(combat): two-tier footsole bodies and per-ID body tier table (HC-BODY-2TIER-1P5-V1)
  4. `5401a0bc` test(combat): register monster combat R1 gates and crowd-scale perf probe (Task 8-9)
- 状态总览：F01–F08 PASS（含反例存证）；任务 B 两档碰撞 PASS；任务 8-9 注册+采样 PASS（设备 NOT_RUN）；任务 10 本文档集；full critical 见 TEST_RESULTS。

## 1. F01–F05（攻击时序与双方向受击，`11ae1056`）

- **F02 双开关默认关闭**：`scripts/enemy.gd` 新增 `_boss_skill_enabled := false` 与 `_boss_phase_two := false`（374-380 注释块：仅显式 opt-in 的运行时入口可开启；boss_rule 空对象不再隐式授权）。`_current_attack_interval()` 空规则直接返回 `_attack_interval`；`_apply_boss_rule()` 开头强制 `_boss_phase_two = false`；`_update_boss_skill` 入口 `if not _boss_skill_enabled: return`。
- **F01 展示仲裁**：`scripts/enemy.gd` 攻击入口改为 `MonsterVisualScript.begin_attack_presentation(duration)` 仲裁；音频播报仅在真正开播时发出（受击背压下不再吞音频或重复播报）。
- **F03 节拍门禁**：`scripts/enemy.gd` 新增 `_begin_autonomous_step_without_cadence(..., now_ms_override := -1)`；门禁 `direct_magic_delay_blocks_next_step(Time.get_ticks_msec() if now_ms_override < 0 else now_ms_override)`；`_request_autonomous_step` 传入 now_ms 保持判定与时钟源一致；新增诊断计数器 `monster_direct_magic_walk_delay_blocked_steps`。
- **F01/F03 配套**：`scripts/monster_visual.gd` 新增 `begin_attack_presentation(duration) -> bool`（death 冻结返回 false；受击中合并；`_attack_action_serial` 序号；`_start_attack_visual`）、`_merge_pending_struck_feedback() -> int`（保留最新 STRUCK 到槽 0，`_pending_struck_count` 同步）、诊断计数器 `monster_presentation_struck_merged`；旧 `play_attack` FIFO 保留（预览/测试契约，见 CONTRACT_DELTA）。`scripts/monster_movement_cadence.gd` 新增 `direct_magic_walk_floor_ms := -1`、`postpone_walk_tick_ms` applied>0 时 floor=walk_tick_ms+walk_interval_ms、只读 `direct_magic_delay_blocks_next_step(now_ms)`；`reset()`/`_reset_state()` 清 floor。
- **F04/F05 玩家侧**：`scripts/player_visual.gd` 非受击/死亡分支改为直接赋值 `_action_remaining/_action_duration`（不再被 FIFO 稀释）；`scripts/player.gd` 恢复活硬直与死亡单次触发（详见 §3）。

## 2. F06–F08（伤害边界/死亡原子提交/音频夹具，`0c5970a3`）

- **F06 非正伤害拒绝**：`_apply_damage_core` 顶部 `if amount <= 0: counter("monster_damage_rejected_nonpositive"); return`（位于 threat/sleep 之前；正伤害路径不变）。
- **F08 原子死亡提交**：`scripts/player.gd` `_apply_resolved_damage` 重构——HP 写入后立即取 `hp_after_damage`；致死决策（复活分支保持原 emits+return；死亡分支原子提交 `_dead=true`/毒清除/epoch/输入隔离）先于 durability/struck/stats/resources 广播；struck 条件改用 `hp_after_damage > 0`；末尾死亡演出（`play_death` → 0.8s → `death_requested` 单次）。
- **F07 边界镜像**：`apply_control`/`apply_poison` 增加与既有 `apply_monster_poison` 相同的 `if _dead or current_hp <= 0 or combat_transition_is_active(): return` 守卫（死者拒控/拒毒）。回执重构债务见 CONTRACT_DELTA。
- **音频夹具确定性加固**：`tests/monster_audio_hook_test.gd` 物理帧窗口化（目标存活窗口与启动期地图注册竞速解耦），断言语义未改；4/4 稳定 PASS。根因记录：夹具裸 Node2D 目标存活性与 `_target_candidate_is_live` 的 runtime map 校验竞速，属既有实时竞态夹具被二进制扰动暴露。

## 3. 任务 B：两档脚底碰撞（`38affced`）

- **策略数据**：`assets/data/actor_body_policy_v1.json`（contract `hardcore.actor.body_policy.v1`）：small 16px / large 22.627416997969522px（0.5 GU）；player 18px 冻结；召唤物档位 skeleton=small / divine_beast=large；分配规则 boss→large、设计文档命名大型精英家族 7 ID→large、其余 small；不变量 `max_body_ground_radius_gu = 0.50625`（由 `ra+rt+0.4375+0.05 <= 1.5` 推出）；未知 ID reject_at_build；旧 collisionRadius 降级为 historical_source_only。
- **烘焙**：`tools/build_canonical_monster_catalog.py` 增加 body policy 加载与 `body_profile_for(monster_id, classification)` 闭包，combat dict 写入 `body_profile`（policy_id/contract_id/policy_sha256/tier/assignment_rule/screen_radius_px/ground_radius_gu）。因既有 checked-in 源漂移（special_normal authority 记录 classification 文件 sha256 `BD7D…`，实际文件 lf_text 哈希 `FD7F…`，主树/基线树同样失败，属既有老债未擅修），本次以有界注入脚本 `tools/apply_actor_body_policy_v1.py` 对已检入目录完成同一逻辑盖印（双集合 entries + entries_by_id，拒绝重复盖印，越界即失败）。
- **逐 ID 档位表交付物**：`docs/monster_combat_r1/body_tier_table.json` — 156 条目全量：large 27（boss_rule 20 + named_elite_family 7）、small 129，含 assignment_source 与双半径。
- **运行时**：
  - `scripts/actor_body_policy.gd`（新）：策略加载/严格校验（有限、正、上界、档位枚举、iso 换算一致、assignment_rule 非空）、档位半径、召唤档位、统一 16 点等距脚底形状入口 `footsole_shape_px`；无每帧逻辑（静态缓存，仅初始化期调用）。
  - `scripts/monster_identity.gd`：新增 `body_profile(id)` 访问器（经正式 identity entry，无名称/后缀回退）。
  - `scripts/enemy.gd`：`setup` 捕获 `combat_body_profile` 字段；`_ready` 身体初始化改为策略驱动——删除 `is_boss ? 28px : 行为配置` 竞争覆盖；校验失败 fail-closed 到 small 档 + `body_policy_fallback` meta + `monster_body_policy_fallback` 诊断计数；半径→GU 单向换算（无往返漂移）；形状 = `ActorBodyPolicyScript.footsole_shape_px`；保持"解析半径→形状→`_resolve_invalid_spawn_overlap()`→索引注册"原序（出生检查用最终半径不变量）。
  - `scripts/summon_actor.gd`：屏幕 CircleShape2D 替换为共享 16 点等距脚底；skeleton 15px 圆→small 16px 档；divine_beast 21px 圆（屏幕圆 vs 等距约定错位）→large 22.627px 档；`_ready` 与出生占用快照（347-351）消费同一 `collision_radius_px`；未知召唤 ID fail-closed small 档 + meta。
- **旧权威清理**：`MonsterUnitAdapterScript.collision_radius_gu(profile, default)` 与 `ArtSpec.BOSS_COLLISION_RADIUS_PX` 均无运行时调用者（全仓 grep 证实，仅定义残留）。

## 4. 任务 8-9（`5401a0bc`）

- **正式注册**：`tools/run_godot_tests.ps1` critical suite 新增 11 个本包场景（7 战斗 + 4 身体），成为永久回归门禁。
- **性能采样**：`tests/hc_monster_combat_r1/monster_crowd_scale_performance_probe_test.tscn`——10/20/30 只真实追击怪物全帧等效采样（headless 桌面）；松全帧预算护栏（<33ms/帧等效），数字进 PERFORMANCE_RESULTS；设备采样按任务授权 NOT_RUN。

## 5. 遗留与债务

1. **F07 回执重构**：收据/回执链路超出本次镜像守卫范围，记独立工作包债务（CONTRACT_DELTA）。
2. **生成器既有源漂移**：special_normal authority 与 classification 文件哈希不一致，阻塞完整再生成（主树/基线同样失败）。需要所有者单独裁决（更新记录哈希或修正源文件），本包以有界注入完成本次构建。
3. **基线既有失败**：7 项（TEST_RESULTS §4），全部 BASELINE_EXISTING 逐项留证，未修改。
4. **设备验证**：10/20/30 设备帧采样 NOT_RUN（无 APK/模拟器授权）。
