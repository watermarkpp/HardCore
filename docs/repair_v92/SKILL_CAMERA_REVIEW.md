# v92 技能、受击与镜头专项静态复核

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

复核时间：2026-09-22 15:50（Asia/Shanghai）。工作目录：`C:/Users/Administrator/Documents/HardCore`。主控提供的 HEAD：`b961cedff8040c9fc81534e094241ad9fa2330ad`，分支 `codex/integration`；本报告复核的是该 HEAD 上持续编辑中的工作树，不是干净提交。行号以本次读取为准，主控仍在编辑 `game_root.gd`，函数名是稳定检索锚点。

本次任务为独立、只读、有界复核。仅新增本报告；未修改生产源码、测试、素材或配置，未执行 Git 操作、bootstrap、Godot、构建或设备操作。主控已有现场预检并串行运行 critical；本报告不复述主控动态结果，也不把静态推导算作 Godot 或设备 PASS。

## 结论

本轮魔法盾与普通一次性特效改为由实际动画完成/盾状态结束来控制父节点，符合动画子节点的异步驻留等待合同。受击队列等待当前动作真实提交后再消费，也修复了物理动作计时先归零、释放 SceneTreeTimer 尚未回调的直接时序窗口。未发现镜头生产调用链会修改盾状态、特效帧时钟、受击锁或技能释放状态。

仍有两项可复核的生命周期边界候选交主控裁决，其中第一项可直接触发玩家可见盾视觉丢失，第二项限于同一玩家节点离树再入树。两项均未在本复核中动态复现，不能视作已确认的本轮新增回归或设备根因。

## 候选一：活跃魔法盾跨图后 Buff 与视觉失去对应

优先级建议：P2。动态复现：`NOT_RUN`。

触发条件：玩家已有活跃魔法盾，剩余时间较长且容量高于自动补盾阈值，随后实际切换地图。相同地图的 `_load_zone` 提前返回不触发此路径。

静态证据：

- `scripts/caster_skill_visual_effect.gd:227-239`：`_ready()` 无条件把所有该类特效加入 `zone_content`，魔法盾另加持久盾组。
- `scripts/game_root.gd:4166`，`_load_zone()` 内 `4206-4208`：实际换图会把所有 `zone_content` 节点 `queue_free()`；没有持久魔法盾例外。
- `scripts/player.gd:650-664`：`begin_combat_transition()` 清除 pending 动作，但保留 `shield_time`、`shield_capacity`、`damage_reduction`。
- `scripts/player.gd:1465-1479`：`magic_shield_snapshot().active` 仅由剩余时间与容量决定。因此换图清理视觉不使 Buff 失活。
- `scripts/game_root.gd:5668`，`_process_magic_shield_auto_refresh()`：只用 `magic_shield_requires_refresh()` 的容量与到期条件判定重施，没有缺失视觉的恢复分支。
- 直接生产链中，魔法盾的 `apply_magic_shield()` 位于 `refreshable_damage_reduction_buff` 消费分支；特效通过 `CasterSkillRuntime.create_cast_nodes_from_canonical_plan()` 在正式释放后创建。未在 `_load_zone()`、转图完成或玩家位置设置链找到活跃盾视觉重建。

状态所有者不一致：Buff 属于跨图保留的 PlayerCharacter，视觉却被归为旧地图内容。结果可以是盾仍减伤/显示 Buff，但人物外观上的盾消失，直到下一次到期或容量触发重施。

建议最窄验证：沿正式施法入口获得盾；记录 Buff 剩余时间/容量、玩家实例 ID 与持久盾组节点；通过正式地图转移入口跨图并等待 READY；确认同一玩家的盾仍 active，且恰好一个可见盾视觉仍绑定该玩家，随后验证容量耗尽/到期会清除。应同时断言这不是一次新施法，不能因此重复扣 MP、刷新容量/持续时间或重新计入释放。

建议修复边界由主控决定：统一持久 Buff 视觉跨图所有权，或在转图完成时从实际 Buff 状态重建缺失的表现。不要用自动重施技能来补视觉，也不要保留所有旧地图特效。本报告不实施该改动。

## 候选二：离树失效动作残留 active，新增受击 guard 会一直等待

优先级建议：P3，需先确认是否覆盖正式支持的玩家节点复用生命周期。动态复现：`NOT_RUN`。

触发条件：同一 PlayerCharacter 接受有 windup 的动作，在释放前遭受应排队的受击；随后节点 `remove_child()` 再 `add_child()`，不立刻接受一个新动作覆盖 pending 槽。

静态证据：

- `scripts/player.gd:179-184`：`_exit_tree()` 只增加 `combat_epoch`，不清当前 active/committed/queued 状态。
- `scripts/player.gd:1054-1078`：旧 `_emit_skill_after_windup()` 因旧 epoch 不再匹配而不提交；这是正确的防跨生命周期释放行为。
- `scripts/player.gd:247-248`：动作计时归零后，只有 `active && committed` 才结束 pending 动作。
- `scripts/player.gd:251-252`：本轮新增 `not _pending_combat_action_active` 后，旧动作无法提交又无法结束时，排队受击无法开始。
- `scripts/player.gd:933-936`：此后新命中也因 active 为真继续走排队分支。
- `tests/player_combat_release_lifecycle_test.gd:102` 的 D 场景已明确覆盖同对象离树再入树，但只断言旧技能没有释放，未检查 pending 与受击队列清理。`rv14_release_reentry_test` 对攻击重入的检查会立刻接受新动作覆盖槽，无法暴露该残留状态。

建议最窄验证：扩展已有 lifecycle D 场景，在离树前加一次确定触发硬直的命中；重入并跨过旧 windup 后断言旧释放计数仍为零，旧动作不再 active，旧受击队列按明确生命周期合同清除，或新的有效命中能播放一次受击。不能通过恢复旧动作释放来让队列完成。

建议修复边界：生命周期终止时同时失效相关动作/排队状态，保留本轮等待真实释放的 guard。当前普通转图 `begin_combat_transition()` 会清 active，死亡路径也清 active 与 queued；未在正式地图转移调用链发现 remove/readd 玩家，因此不把此项描述为已确认的手机故障根因。

## 已完成的静态复核

| 范围 | 状态 | 依据与限制 |
|---|---|---|
| 冷加载等待不消耗父特效生命周期 | PASS | `CasterSkillVisualEffect._process()` 对未驻留子节点返回；普通动画的完成权归 child；盾由真实 Buff active 决定移除。 |
| 子动画原子驻留与帧时钟 | PASS | `CasterSkillAnimationPlayer.configure/_retry_after_warm` 保留 accepted waiter，整序列驻留后从既有 committed frame 开始，等待分支不消费 delta。 |
| 资源 lease 取得与释放 | PASS | `_sequence_lease_held` 防重复取得与虚假释放；一次动画完成释放 sequence lease，退出树再次调用释放是幂等；最后一帧 texture 仍由 Sprite2D 引用。 |
| 重施盾旧节点释放 | PASS | `_replace_existing_magic_shield_visual()` 隐藏后 `queue_free()`；代理与动画均是 effect 子节点，删除会进入 animation `_exit_tree()`，没有脱离树外的视觉代理。 |
| Hellfire 等待时序 | PASS | 父 tick 等所有子节点 `visual_loaded` 后再推进轨迹时钟；manual sprite 的 lease 在 effect teardown 时释放。长帧跳到最终逻辑状态仍遵守现有 catch-up 合同，本报告不声称每个中间帧都一定被设备显示。 |
| 当前普通特效不存在循环动画完成死锁 | PASS | 只读解析 `caster_skill_visuals.json`：排除 projectile/ground_effect/summon_actor_visual 后 20 个普通特效 profile，全部默认 `playback=once`；322 个唯一默认动画源帧路径全部存在。未检查 APK 内导入资源。 |
| 受击等待真实释放 | PASS | 物理 action timer 可先归零；新 guard 不抢占尚未 committed 的释放事务。转图与死亡会取消旧 pending，epoch 挡住跨生命周期回调；同对象离树重入残留问题见候选二。 |
| 镜头权威与坐标链 | PASS | `GameRoot._update_world_camera_constraint` 从正式 runtime map 的 design_size、固定 ArtSpec zoom、当前玩家位置与角色显示边界输入 guard；边界由 `map_inner_boundary_world → tile_polygon_world → MapEditorCoordinate → GroundUnitSpace` 正式投影链得到。无身份/坐标 fallback 扩充。 |
| 镜头缓存与受击隔离 | PASS | `MapEditorRuntimeBridge.load_map:370-382` 先返回 runtime_cache；camera 区域缓存按 design_size/viewport/zoom 失效，玩家位置不触发重建；镜头更新只写 camera transform/zoom，没有写受击或技能时钟。 |
| 镜头测试计时修改 | PASS | `_settle_camera()` 从固定 process-frame 次数改用单调时钟 2500ms；提前退出仍要求中心距离 ≤1px，后续 canvas/zoom/可见范围断言未通过此改动被放宽。这里只评审测试逻辑，不认定设备视觉结果。 |
| Godot 动态复现与回归 | NOT_RUN | 主控串行运行，不由本复核重复启动。 |
| Android 实机动画、卡顿及镜头触感 | NOT_RUN | 无设备操作、截图或运行采样。 |

两个新增回归测试直接覆盖本轮被修窗口，但 `skill_visual_cold_lifecycle_test` 通过测试显式把真实源纹理加入 registry 再推进 animation，证明的是生命周期与驻留完成之间的接口；它不证明生产 threaded pump 的实际加载延迟，也没有覆盖实际跨图盾视觉连续性。`player_struck_release_order_test` 证明长物理 tick 先于 SceneTreeTimer 的顺序，不覆盖取消后同对象重入。

另一个明确验证限制：普通父特效现在会持续等待合法但未驻留的序列。`GameRoot._pump_pending_warm_textures()` 对 FAILED/INVALID_RESOURCE 只移除 in-flight 项，而子节点会重新排队；终止性资源失败没有向 effect 传播。本次所有 322 个受检源帧均存在，未发现现实坏资源，因此未把它列为已确认缺陷或要求恢复任意 lifetime 超时。包内缺失/坏导入与持续缓存准入失败需专门故障注入才能判定。

## 采样身份

以下 SHA-256 是本复核结束前读取的工作树文件身份，不等同于源码提交或最终 APK 身份。主控后续修改后须以新的提交/最终验证源为准。

| 文件 | SHA-256 |
|---|---|
| scripts/caster_skill_visual_effect.gd | FA46772E14125F601ABED91BFD40DF74BD9E329AA9BCF87B892AED0636E8597B |
| scripts/caster_skill_animation_player.gd | 7ABA2614D202E7EC36484521A646A74D755B1EFB1A32436621CF88EA79FCF8D8 |
| scripts/player.gd | 05170138E3533D144BE9747F63E1BEB235B7FE34A69F1B3E639C7889728AD97B |
| scripts/game_root.gd | 21C726CB45D1A365F73B029E77CA8F8D729B8D879B82142960476E919AD43671 |
| scripts/map_editor/map_diamond_camera_constraint_service.gd | F973B6980DA7157C80EA16F7784A57BCE7124677D27EA556F602988E9F3D857A |
| tests/skill_visual_cold_lifecycle_test.gd | C3FFD8CFCD8F59A86F5297A2D09A9279DEED9E1B9926579E9487D2A461128FF6 |
| tests/player_struck_release_order_test.gd | A970BF29751AADDB4AC76D1D9928B3EC1EAD485B7C842E14834042832D778494 |
| tests/game_root_diamond_camera_constraint_test.gd | 15BE9C2205A1EB4C91970DC31523D0D51DCF2EEBC6AFE254947476241425D0C2 |

稳定 ID：本复核无新增、删除或变更。跨系统接入：仅上述候选待主控裁决；本报告不批准发布、合入或最终验收。
