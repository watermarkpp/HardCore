# FINAL PRODUCTION REVIEW 2（修订）

日期：2026-10-07

审查基线：当前绝对源码 C:/Users/Administrator/Documents/HardCore。只读检查 scripts/enemy.gd、scripts/monster_crowd_attack_position_policy.gd、scripts/layers/runtime/combat_runtime_service.gd、scripts/monster_struck_policy.gd、scripts/monster_movement_cadence.gd；没有修改生产源码、测试或运行 Godot。

## 当前源码核验

直接读取的 C:/Users/Administrator/Documents/HardCore/scripts/layers/runtime/combat_runtime_service.gd 第 10–16 行已经是最新注释：

“DIRECT_MAGSTRUCK and MAGSTRUCK_MINE both resolve MAC normally. Positive damage produces ordinary STRUCK presentation and the level-based attack delay; neither delivery postpones autonomous movement.”

该文件当前 SHA256：

3263C5978E63842CAEE4C9E3D3D912EAEB01170414B01C4A76394777B58868C2

短 hash：3263C597。

因此上一版 report2 关于“CombatRuntime 顶部仍残留旧 800ms movement 注释”的 P2 已确认过时，已撤销。当前 production scripts 中未找到 apply_source_direct_magic_walk_delay、postpone_walk_tick_ms、direct_magic_delay_blocks_next_step 或 direct_magic_walk_floor_ms 的执行引用。剩余 consume_direct_magic_compatibility_roll 只用于保留 actor RNG 序列，不改变 movement、damage、attack timer 或 caller spell RNG。

## Confirmed 静态范围

### STRUCK 与 RNG

- 正 DIRECT：CombatRuntimeService 在 MAC 后仅对 final_damage > 0 调用 take_damage；EnemyActor ordinary struck 只增加下一攻击 deadline。
- MAC final damage 为 0：不调用 take_damage，因此不增加 attack timer、不产生 ordinary STRUCK、不触碰 movement。
- anti-magic evasion：不进入 MAC stage，不消费 compatibility actor RNG，不进入 HP/STRUCK。
- MINE：正伤害共享 ordinary positive damage/attack-delay 路径，不再拥有 direct-magic movement gate。
- poison：causes_struck=false，保持 HP-only。
- compatibility draw 使用 actor 自有 _rng，未把兼容消费混入 caller spell RNG。
- committed attack：_hc_try_start() 建立正式 release record/pending delay；ordinary struck 不清 pending；_update_pending_attack() 仍按正式 record 结算。

这是当前 source diff 的静态确认，不是 Android/device PASS。

### Boss clock、target 与 cursor

- _boss_stage_search_due() 以 _boss_search_clock_anchor_s 和当前 combat clock 判断，按当前 target live 状态选择 withTarget/withoutTarget interval。
- _boss_stage_search_action_legal() 过滤死亡、combat disabled、control/charm、dormant/burrow、active action、pending attack 和 warning 状态。
- 搜索尚未合法消费时 anchor 不前移；合法正式 search 消费召唤阶段后才更新 anchor。
- damage callback 只触发 rage；summon 由正式 target-search/action decision 触发。
- _boss_health_stage 与 _boss_rage_health_stage 分离，避免 summon 和 rage 互相消费 stage。
- rage 到期恢复 base movement speed 与 base attack interval。
- 根代理报告的 Boss clock、formal interval、continuation 和 crowd native 结果属于主控当前源码阶段的中间证据，最终仍需 fixed-source seal 绑定。

### Crowd cost-prune 与 snapshot

- choose_with_snapshot() 的 not cost < best_cost 保持严格小于：NaN cost 不会胜出，严格相等不会替换已有候选。
- snapshot_peers() 保留 node、position、radius；粗包络后再读取当前 can_receive_damage() 与 worldCollision，未把 eligibility 跨 actor 缓存。
- malformed radius 不是当前可由正式生产路径到达的已证实缺陷：ActorBodyPolicy.validate_body_profile()（scripts/actor_body_policy.gd:116-145）拒绝非 finite、非正或超限 ground radius；EnemyActor.resolve_body_for_admission()（scripts/enemy.gd:2600-2647）对非法 body profile fail closed 并禁用 combat；正式 factory 在 index.register 前使用已解析的 combat_radius_gu（scripts/enemy.gd:2633-2641）。任意 helper 手工覆写 radius 不构成生产可达证据。
- 因此此前对 snapshot radius 的 P2 降级为 coverage note：正式 body admission gate 已提供 finite/positive/maximum contract，未确认生产缺陷。

## 唯一保留的 coverage note

Boss summon cursor 在 current_hp >= max_hp 的 search boundary 会恢复 authored stage count（scripts/enemy.gd:7696-7704）；rage cursor 没有对称的 full-heal reset（scripts/enemy.gd:7724-7740）。

这目前只标为 MISSING coverage，不能定性为生产缺陷：

- 未有来源证据证明 revive/full-heal 必须复用同一个 EnemyActor；
- 未有用户批准改变现有 rage 生命周期合同；
- 新增 reset 可能改变已确认的原 damage-driven rage 行为。

如果后续产品合同确认 Boss revive 会复用 actor，再增加针对 rage cursor 生命周期的正式回归。

## 最终门禁

1. source_before/source_after 必须覆盖同一 fixed candidate 的 Boss、struck、crowd production files；
2. tests、outputs 草案和旧中间 evidence 不能混入 final source claim；
3. runner 必须绑定当前 integration HEAD 和同一源码阶段；
4. PC/native PASS 不能替代 APK identity、安装和 device evidence。

## 结论

- STRUCK 正/零/闪避/MINE/poison/committed release：静态 PASS（当前 production diff 范围）。
- actor RNG 与 caller spell RNG 分离：静态 PASS。
- Boss mutable target clock、合法 action gate、summon/rage 分离：静态 PASS（native 结果由主控绑定）。
- Boss full-heal/revive rage cursor：MISSING coverage，当前不定 production issue。
- Crowd cost-prune strict tie/NaN cost：静态 PASS；formal body admission 已覆盖 radius finite/positive/max contract。
- 旧 direct-magic 800ms API：无 production 执行路径。
- 最终 fixed-source seal：NOT_RUN（本轮未运行 Godot）。
- Android/device acceptance：NOT_RUN。
