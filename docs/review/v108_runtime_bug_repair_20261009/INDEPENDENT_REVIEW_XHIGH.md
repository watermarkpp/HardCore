# HardCore v108 修复版独立代码审查

审查基线：`61d5b03f0568fee0f9c88fa2c20fbe93861c5095` · 只读审查 · 未构建 APK · DEVICE TEST: NOT_RUN

我已实际读取固定提交中的生产源码，不仅是施工报告。 已核对 `enemy.gd`、`game_root.gd`、`audio_preferences.gd`、`system_menu_panel.gd`，以及 `PlayerState`、`JsonPersistenceService` 和相关测试证据。

初步结论：本轮四类修复均有真实源码改动支持，主要根因修复方向成立；但不能直接给出总体PASS。 我发现一处需要优先处理的退出重试风险，以及尚未覆盖的激活和手机音频边界。

## 一、阻塞问题与优先复核项

### P1：保存退出的临时失败可能被永久锁定

`scripts/game_root.gd` · `_drain_enemy_death_queue_for_logout()`

当前函数开头发现 `_last_death_logout_failure` 非空，就直接拒绝后续退出请求。

当死亡队列经过同步清理仍未排空时，代码又把 `safe_logout_death_queue_pending` 写入这个持久失败字段。在固定源码中，我没有找到清除该字段的路径。

这意味着存在一条明确的风险：

1. 第一次点击保存退出时，死亡队列暂时未处理完，退出被安全拒绝。
2. 后台死亡处理随后正常完成。
3. 用户再次点击保存退出，却仍被上一次保存的失败记录直接拒绝。

这里必须区分暂时未完成和真正终结失败。 真正的存档失败、奖励提交失败不能放行；但暂时pending在后续已安全完成时，也不应永久阻止用户退出。

建议主控优先补一个精确定向测试：第一次因pending拒绝、随后异步死亡全部成功提交、第二次保存退出。测试必须证明XP、掉落、存档均只提交一次，不能靠清空整个错误状态绕过真实失败。

这属于源码可证明的重试状态风险，但尚无证据表明用户原先那次手机点击一定进入了这条分支。

### P1：投影暂时不可用时，激活事件可能被消费后丢失

`scripts/game_root.gd` · `_begin_passive_monster_wakeup_batch()`、`_service_passive_monster_wakeup_batch()`

这是一处我从代码控制流中发现的具体漏洞风险。

当前流程先从待激活队列取出发射者，清除其dirty标记，再尝试正式坐标转换：

```
var emitter_ground := _canonical_screen_px_to_ground_gu(emitter.global_position)
if not emitter_ground.is_finite():
    return false
```

如果此时地图投影暂时不可用，外层会结束当前处理，可能把待处理标记也清除。

后果： 后续投影恢复后，如果玩家一直站着，没有发生新的移动、出生或其他唤醒事件，这次未完成的激活可能不再被主动重试。

这不是“地图转换失败时也应该强行让怪物入战”。失败仍应安全拒绝，但一次暂时失败不能永久吞掉合法激活请求。

建议最小修复：保留未完成的发射者身份，待正式投影恢复或地图READY事件到达后重新服务。仍使用原地图和代际验证，不增加每帧全地图扫描，也不允许在投影持续失败时无限紧密重试。

源码：

GameRoot 激活批次与服务状态

。该失效场景目前没有直接专项PASS，属于源码推导出的未覆盖风险。



### P1：必要唤醒已经不受1200微秒optional预算限制，但也不再有严格的单帧时间上限

`scripts/game_root.gd` · `_on_player_moved()`、`_pump_passive_monster_wakeup()`

这次修改实现了用户要求的即时入战：

- 人物真实移动后立即调用唤醒处理；
- 取消旧的每轮8候选限制；
- 使用必要工作记账，一次处理完当前候选，不再排队等待optional余额。

从源码看，正常有限队列不会凭空进入死循环：发射者队列逐项弹出，候选游标单调前进，外层服务次数也根据进入时的队列数量限定。

但存在另一种问题。

如果一次主循环包含多个physics补步，人物在这些补步里持续移动，`_on_player_moved()`可能多次触发唤醒处理。由于不再用同一process epoch直接返回，每次新的移动事件都有机会再次执行空间查询。

同时，`FrameBudget.begin(..., true)`允许必要工作超过1200微秒。

所以现状能够保证候选不会因为optional预算而延迟，却不能保证同一主循环的全部唤醒工作不会超过帧预算。

报告中的30/30目标和单次约1.949ms是有意义的成功证据，但它不是Android长帧上限。

我不建议恢复8候选或300ms等待。建议增加一次有限压力验证：同一process内发生多个physics补步和连续移动时，记录实际查询次数、候选数、去重次数、必要工作总耗时及最大单次耗时。

这项应视为60fps目标的放行风险，而不是已经证明的无限循环BUG。

## 二、已核实成立的关键修复

### 1. 被动入战和火墙唤醒：核心改法成立

`scripts/enemy.gd` · `request_passive_target_wakeup()`、`_acquire_cold_damage_target()`

我确认新实现不再只是记录witness，而是在完成正式合法性检查后执行：

```
target = candidate
_clear_passive_wake()
_retarget_timer = 0.0
_passive_mode_active = false
_leave_background_deep_sleep()
```

这意味着取得target不再依赖之后的300ms追击规划。

正式静态LOS函数使用地图地形导航上下文做直线检测，没有把其他怪物的动态身体当成信号遮挡。原地图、代际、范围、安全区和隐身拒绝仍存在。

火墙通过正式伤害入口进入`_apply_damage_core()`。真正产生正HP损失后，代码会调用`_acquire_cold_damage_target(attacker)`；它直接取得合法Player/Summon目标，而不等待富AI观察服务。

这些调用关系支持本轮根因修复。 30/30同事件入战、30/30受伤取得目标也有专项测试记录。但“立即取得目标”不等于同一帧立即走路或攻击；后者仍服从当前战斗、规划与动作许可。

还有一个边界：当前取得新目标之前检查的是`is_instance_valid(target)`。一个旧目标可能仍是有效Node，却已死亡或不再是合法战斗目标。此时新激活请求会被拒绝，直到其他维护路径清除旧目标。

建议增加“旧目标仍在场景树内但已经失效，新合法目标进入范围”的单独测试；不得为此抢换仍然合法的现有目标。

源码：

被动取得目标

、

正伤害冷怪唤醒

。



### 2. 异步死亡与零掉落：主要死锁点确实已修正

`scripts/game_root.gd` · `_poll_prepared_enemy_death_settlement()`、`_finish_enemy_death_settlement_batch()`、`_plan_enemy_death_item()`

沿实际调用链核对后，死亡处理过程是：

Enemy死亡信号 → GameRoot建立死亡记录

PlayerState准备经验、任务和重生状态 → JsonPersistenceService异步写入

成功回执 → `PERSISTING` 转回 `SETTLING`

正式掉落roll → 放置地面物品 → 注册拾取物 → `COMMITTED`

原问题在于持久化成功后没有重新进入可执行的掉落状态。现在成功回执明确执行：

```
_set_enemy_death_state(death, DEATH_STATE_SETTLING)
```

这项修复是必要且正确的。

当前同一进程内的幂等保护也有明确依据： JsonPersistenceService完成时先移除队首，再调用完成回调；PlayerState保留完成记录；GameRoot只有`QUEUED`进入结算准备，成功后转为掉落阶段；掉落切片保存cursor，已经生成的节点通过materialized index跳过，避免每次从头执行。

相关测试证明了真实`test_mode=false`自然死亡能够完成，32死亡批次的RNG与产物保持一致。这不是仅凭报告文字判断。

但仍须限定证明范围：没有证据证明Android进程在XP已保存、地面物品尚未生成的中间阶段被系统强杀后，也能自动恢复全部未完成掉落。 安全退出会主动清理队列，强制杀进程则不是同一条路径。这属于后续可靠性验证，不应冒充此次零掉落已经复发。

源码：

死亡回执与掉落计划

、

PlayerState异步结算

、

持久化完成回调

。



### 3. 保存退出的可见反馈：主菜单修复成立

`GameRoot._handle_safe_logout_failure()`已将错误文字直接送入`SystemMenuPanel.show_save_exit_failure()`。

菜单内失败Label显示时，正常Footer被隐藏；清除错误后Footer恢复。原安全退出拒绝逻辑没有被取消。真实暂停菜单信号相关测试也有对应PASS。

因此，我没有发现这次修改在正常点击保存退出→返回失败信息路径中存在明显的层级错误。

需要处理的是前面指出的临时pending错误永久锁定，以及Android上的真实文字显示与触控验收。

## 三、音频：当前修复正确，但仍有平台生命周期缺口

`scripts/audio_preferences.gd`、`scripts/audio_runtime_service.gd`、`scripts/game_root.gd`

新的`AudioPreferences._ready()`不再从临时Bus mute状态反推玩家意图，而是先以1.0为默认值，再读取合法的主配置或备份。

`_apply()`负责创建或取得Music/SFX总线，并应用当前音量。`AudioRuntimeService._ready()`在服务创建后又通过`bind_sfx_service()`触发偏好重应用。

因此，启动顺序中“总线尚未创建，偏好就应用了”的问题，在当前源码里有后续补应用路径，并不是明显遗漏。

但是，`AudioPreferences._notification()`目前主要在失焦、暂停时保存配置；`GameRoot`收到`NOTIFICATION_APPLICATION_RESUMED`也主要重置性能帧间隔记录。

没有看到在Android恢复焦点后重新校准音量总线的明确路径。

这不证明Android一定会重新mute总线，却意味着当前测试不足以覆盖：

首次冷启动有声 → 切后台/锁屏 → 恢复游戏 → 无须移动音量滑块仍有声。

建议正式手机验收分别覆盖首次无配置、保存0、保存非零、前后台恢复。若恢复后总线状态确实偏离偏好，才增加受生命周期事件驱动的重应用；不要提前用定时器循环重置音量。

源码：

偏好读取与应用

、

应用恢复通知

。



## 四、其他可选建议

### 掉落资料覆盖范围仍需独立检查

我没有发现本轮修改了掉落概率、槽位或保护规则。但本次自然死亡的正向证明主要集中在已配置的怪物ID 76及特定批次。

此前同一v108基线的只读`drop_trace.md`指出，部分canonical怪物ID在用户掉落Sheet中不存在，而正式掉落服务对于缺失Profile会返回`dpv2_direct_profile_unresolved`。这项资料覆盖风险并不会因为异步死亡状态修好就自动消失。

这不等于已证明手机上所有这些ID都会刷出，也不等于应该新增掉落表。建议只检查当前实际允许刷出的怪物ID与既有用户Sheet是否匹配，保留原概率和槽位，不添加任何自动fallback。

### 修复后证据仍是分阶段专项，而非同源码全量验收

我读取了随提交保留的runner结果。早期相关套件确实有FAIL，后续针对失败项有定向PASS；自然死亡、32死亡和激活拒绝门都有对应成功记录。

但这些发生在不同源码阶段。报告把未变函数的既有证明作为可复用证据，这种做法合理，不能据此声称最终冻结源码的全项目回归、手机测试和APK已经全部PASS。

## 五、建议主控现在的处理顺序

| 优先级   | 下一项                                     | 裁决                     |
| ----- | --------------------------------------- | ---------------------- |
| P1    | `safe_logout_death_queue_pending`后续恢复重试 | 优先补合同，避免临时失败永久阻塞       |
| P1    | 投影暂时失败后激活事件保留与恢复                        | 优先补针对性测试与安全重试          |
| P1验收门 | 同process多次移动唤醒的总时间与Android真实长帧          | 不能仅用单次PC 1.949ms放行稳帧目标 |
| P2    | 旧target仍有效Node、但已失去战斗资格时的重新入战           | 精确负向测试                 |
| P2    | 实际刷怪ID与既有掉落Sheet的覆盖关系                   | 数据核对，不改掉落设计            |
| P2    | Android音频恢复、强制结束应用期间的掉落持久性              | 设备及生命周期专项              |

## 总体结论

本轮主要修复不是假修。 从源码看，原来导致唤醒延迟的optional路径已经被必要事件替代；异步死亡的`PERSISTING`卡死也修在正确的状态转换位置；菜单反馈与音量初始化都有实际效果链支持。

但我不建议把`61d5b03f`直接判为无阻塞的正式发布版本。 至少应先处理保存退出的临时pending锁定问题，并闭合投影暂时失败时的激活事件恢复，随后以冻结源码完成必要回归和真机验收。

所有结论都基于本次固定提交。没有触碰`codex/integration`的HEAD、index或dirty工作，也没有构建APK。

审查状态：核心修复有依据；总体PASS尚未成立；DEVICE TEST: NOT_RUN。