87400315 独立复审完整结果
请求身份：resource-consumption-87400315-20261004
固定 SHA：87400315b1accc87dc0592b091dbfcef876453d5
父 SHA：6aab18ff1588b879e1fad659fba4b71fff6f6c75

结论：两个取消问题可按本轮范围关闭，真实typed资源消费和单cue退休修复有证据支持。但现有多来源效果在同步clear后继续分派的问题仍需原生反例与修复；第三真实index的历史连续性也仍为FAIL/MISSING，不能写成全部保护通过。这两类问题分别属于运行边界与暂存状态保护，不应混为同一根因

1. 两个取消问题已关闭

每个量子先关闭Budget scope，再把cancelled和finished中的全部请求移出_requests，最后才通知任何等待者。因此B取消续体再次取消时，已提交A已经退出可取消集合，不能改写A=true；同ID重复终态只有第一次能取得Request，不会重复送达

reload与module enable共同使用新的await wrapper，取消后仅在producer sequence仍属于自己时释放发布锁。旧调用不会清掉较新producer的锁；已取消旧application在消费前仍被跳过

原promotion 34项/2FAIL→34PASS，queued 14项/4FAIL→14PASS，最终正常退出0、无超时。未增加预算，也未把等待者回调放回开放scope中

覆盖须准确：queued原生场景测试的是reload，live module enable共用路径是源码核验；新producer在旧队列排空后才启动，取消续体立即启动新producer及多等待者重复取消的组合也是源码推导，不说成每种都独立原生覆盖。当前源码未建立这些组合的失败反例

[先移除再通知](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/features/runtime/feature_resource_preparation.gd#L135-L148)
[同producer锁清理](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/layers/runtime/content_layer_registry.gd#L113-L138)

2. 待修：多个binding在第一个音频通知clear后，旧dispatch仍继续

这是已经实现的同效果三来源组合，不是尚未建设的Task4异构机制。resource_natural_registry已经给hc.ignite.ice_storm登记rule/item/skill三个不同来源

最小原生反例建议：使用该合法配置、真实accepted action和非空票据；在第一个音频event_started通知中执行runtime.clear，沿用现有单binding重入测试的同一种观察者

固定源码中的路径：
- _deliver_fact循环entry.bindings，第一个_apply_command启动required cue
- AudioRuntimeService同步发event_started，观察者clear清空状态、receipt、队列和reservation
- presentation_port识别原cue已经退休，正确停止刚返回的确切音频请求
- 但_deliver_fact继续第二个binding
- 第262行重新写入receipt，第265行访问已被clear删除的reservation，产生clear后的状态复活和无效访问风险

本次没有运行Godot，也没有声称已记录的自然场景触发了它；这是明确的源码条件反例。现有重入场景只有一个binding，因此没有第二轮访问，21PASS不能覆盖这个问题

最小整改不应改HP、planner或RNG：在任何可同步回调的命令/表现调用之后，确认旧dispatch仍有合法所有权；后续receipt/state写入前检查原ticket仍存在且是queued。仅检查WorldContext不足以识别同世界clear，可配合轻量clear失效标记，不能另造玩法权威

原生门禁：只发生第一次onset，第二/第三binding不继续；基础HP保留原单次提交，不产生后续周期伤害；batch/state/heap/reservation/receipt/cue/audio handle归零；停止准确旧播放器并释放stream；无脚本错误、无开放预算scope；释放其余合法引用后lease退休

[既有三来源](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/assets/data/features/validation/resource_natural_registry.json#L13-L31)
[分派及回调边界](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/features/runtime/effect_runtime.gd#L251-L306)
[clear](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/features/runtime/effect_runtime.gd#L348-L358)

3. 本轮资源消费成果应保留

Action创建前、Batch领取reservation之前已验证非空required资源；null或真实但空的lease不能花掉合法producer票据。cue获得accepted lease，真实AudioStream直接交给既有播放器，prepared路径不重新查stream cache；确切单样本映射不引入随机变体选择

返回后按cue身份和请求serial检查，避免原cue已退休却晚登记。停止还检查pool槽、prepared所有权、serial及event，不能误停复用槽中的新声音。Action→entry→state→cue强持有保留已接受工作，停用或producer死亡不会偷走它们的资源

完整回执：cue29PASS、单cue重入21PASS、接受资格24PASS、accepted lifetime26PASS，均为最终ad9681fc内容。本轮第2节缺口不推翻它们实际覆盖的范围

90个cue与126次音频启动不代表90路同时可听。声音仍服从原静音偏好和有界音频池；headless实例化CanvasItem与准确stream传递也不等于手机GPU首帧、听感或热机通过

[接受前资源门禁](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/features/contracts/action_config_lease.gd#L20-L43)
[prepared音频消费](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/scripts/audio_runtime_service.gd#L419-L440)

4. 采用证据与自然资源场景

独立核对16个invocation、131条原生记录、10条原FAIL；最终51个唯一场景均正常退出0、无超时，其中50份完整framework回执合计1281项，另一个为原普通starter-loadout

原始回执、命令、退出、source/run/invocation、handoff及live/cold身份对应，无证据完整性阻断。两条解析失败没有伪造回执，其余原失败也保留

资源自然变体原始trace确认：30个具名唯一目标各3来源、90状态/cue、126次确切stream启动、939次投递、最大实际迟到33333us、XP512；141项live与10项cold按本轮producer衔接

3570个墙钟样本的分位数独立重算符合6754/14736/18351/34176us。但采样来自process回调间Time.get_ticks_usec差值，应该写“墙钟帧间隔”，不是CPU执行时间；README的“墙钟CPU”须修正

ObjectDB退出警告仍保留。零orphan及效果/资源排空不能外推为全局无泄漏

全部3683受测文件与固定Git对象对应：810原字节相同、2873仅CRLF/LF差异；重算内容指纹：
ad9681fc02a35ae84ed6d432aa979cad632f5f05b0ee3efd356961147ca529eb

631个native成员与ZIP清单及已提交对象一致；源码ZIP为3683清单文件加3份主源媒体和RFC，共3687成员，不能混算。父到子受测差量准确为31路径

[本轮证据入口](https://github.com/watermarkpp/HardCore/tree/87400315b1accc87dc0592b091dbfcef876453d5/docs/review/framework_resource_consumption_20261004)

5. 第三真实index：历史连续性仍FAIL，不能用新快照补成PASS

远端记录显示：
- 父阶段2026-10-03 21:23:48 UTC：第三真实index为66c505ce…92705
- 本轮22:49:43 UTC：实际为df5a01dd…8c5fb，staged entries指纹58f820e2…f7733
- 原字节备份MISSING；最后写入时间记为21:53:36 UTC；当前保护快照22:49:45 UTC

最后写入时间不等于操作来源。仅凭raw index哈希不同，不能确定哪些暂存项发生变化、是否丢失，也不能归因于某个进程或人

这是用户暂存状态的保护与可追溯性问题，不自动构成游戏运行回归。但必须持续保留FAIL/MISSING，不应写“第三树index始终未变”或“所有保护均通过”

本轮before/after受测源码稳定，不包含真实index/staged条目哈希，因此不能替代历史index证明。远端已查包里没有实际index备份或完整staged export，尚不能独立重建当前暂存内容

最小非破坏性后续：保留现有真实index/stages，不reset、不restore、不重建。由原主控确认是否已留存匹配df5a01/58f820的当前index字节和精确staged清单、时间及哈希方法；若没有，在任何后续改暂存操作前先安全留存。只有存在真实旧备份/清单时才做只读对照，没有就继续标历史不可恢复验证，不猜造旧状态

[历史连续性边界](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/docs/review/framework_resource_consumption_20261004/INDEX_CONTINUITY_BOUNDARY.json)

6. 其他保护与diff-check的准确口径

主树/第二树的branch、HEAD、dirty数量和status哈希与父快照一致：119/249保持；冻结MonsterStreaming哈希亦对应。父阶段文件没有主树/第二树index哈希，因此仅这些相邻材料不能独立证明它们历史index字节连续性

SOURCE_DELTA与source_review.diff同为31路径，记录+736/−30，源码门禁退出0。完整默认及CRLF-aware diff-check均退出2，涉及原审计文字尾空格、失败stdout和字面patch上下文。这些已分类留存，正确写法是“源码差量检查PASS；完整原始证据diff-check FAIL且已披露原因”，不能写全量diff-check通过

[diff-check边界](https://github.com/watermarkpp/HardCore/blob/87400315b1accc87dc0592b091dbfcef876453d5/docs/review/framework_resource_consumption_20261004/DIFF_CHECK_BOUNDARY.json)

7. 下一步

关闭两个旧取消缺陷，保留本轮资源资格和实际消费成果；用现有三来源配置补同步clear的原生RED，然后修复旧dispatch失效边界。先留存当前暂存现场，不擅自修复历史index

旧破坏性supervisor安全复用问题仍开放，本轮没复用旧脚本，不能说已修。Task4/5、GPU/Android、APK及原v97B缺失等仍按原范围处理

本次全程远端只读源码/归档核验与独立重算，没有运行Godot、访问或修改本机index、改工程、发队列或另开施工主控
