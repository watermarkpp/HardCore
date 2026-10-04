6ae8a441 独立复审完整结果
请求身份：heterogeneous-6ae8a441-20261004
固定 SHA：6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd
父 SHA：87400315b1accc87dc0592b091dbfcef876453d5

结论：本轮即时吸血原语、两handler容量拆分，以及clear/configure后旧派发停止的限定整改可接受；未发现新的阻断性玩法缺陷。父版多binding同步clear问题可关闭。当前index备份已在文档中声明，但原始备份尚不可远端读取，因此这一部分只能确认声明，不能独立确认备份字节；历史连续性仍FAIL/MISSING

1. 吸血使用已提交损失，沿用唯一恢复权威

Enemy在既有HP赋值后、回调前捕获事实；DamageBatch保存hp_before−hp_after。新handler计算floor(actual_loss×fraction)，不使用请求伤害

恢复路径为EffectRuntime→CombatRuntimeService.apply_feature_source_restore→既有Player.restore_health。command的source必须匹配；ActorRef重新核验世界、owner、同一actor/life、在树和存活资格，combat port拒绝正在转场的来源

恢复不要求目标仍存活或仍可解析，因此“致死后移除目标，仍按刚才实际损失恢复合法来源”符合本轮设计。它没有借目标移除放宽来源资格

原生日志中，致死及移除致死目标两例都为请求100、实际loss20、恢复5。78项runtime和26项真实Root混合场景的回执、run/invocation/source及退出对应

periodic不会递归触发：编译与handler都限定direct来源，原周期伤害入口没有feature_damage_batch。Player、GameRoot、Enemy、ActorRef和ignite_handler与父版blob相同，既有装备吸血公式、HP writer、planner和燃烧公式没有改写

[吸血handler](https://github.com/watermarkpp/HardCore/blob/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/scripts/features/handlers/lifesteal_handler.gd#L6-L17)
[唯一恢复入口](https://github.com/watermarkpp/HardCore/blob/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/scripts/layers/runtime/combat_runtime_service.gd#L180-L193)

2. 权限、生命周期和容量没有混算

lifesteal要求combat.post_hit与combat.heal、至少一个command预算、immediate生命周期、零持续状态且无cue。fraction需有限且0<f≤1，未知handler/不合权限声明在编译边界拒绝

receipt按最大receiver×binding数预留；state按handler实际成本预留，lifesteal为0，ignite为1。未票据队列和每目标来源槽也按此区分，没有让17个即时来源占用16个持续状态槽

接受前预留、原AOE receiver bound和begin_release/begin_plan不变。producing仍归DamageBatch，action取消不能夺走已提交HP的批次；Root完成base scope后才提交，非空提交失败仍显式报错

验证模块默认关闭，正式module_registry不包含它，没有把本轮测试偷偷变成线上默认玩法

[预算与提交](https://github.com/watermarkpp/HardCore/blob/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/scripts/features/runtime/effect_runtime.gd#L70-L179)
[可信handler合同](https://github.com/watermarkpp/HardCore/blob/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/scripts/features/handlers/handler_registry.gd)

3. 父版多binding同步clear问题已关闭

clear/configure推进派发失效代次。旧调用在下一个binding写receipt和生成命令之前检查，退休后退出，不再访问已经移除的reservation

如果没有发生退休、却意外丢失queued票据，仍记录feature_dispatch_reservation_missing，没有把所有异常都吞成成功。当前两个handler每个binding最多生成一个命令，因此此检查覆盖本轮实际同步回调点

原三来源冰咆哮音频RED是23项/1FAIL，原stderr确有_deliver_fact字典索引错误；最终24PASS，包括只一次播放、heap/receipt/producer清空、停止音频、释放资源、原base HP/RNG保持，以及budget scope归零

同世界unticketed双恢复的原78项/1FAIL，确实失败于第二次多恢复；最终78PASS。混合生产26PASS走真实Player接受非空票据，在windup期间撤销两个模块，仍完成原base伤害、一次恢复和一个ignite状态的四次原周期，不发生周期递归回血

[派发代次与缺票处理](https://github.com/watermarkpp/HardCore/blob/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/scripts/features/runtime/effect_runtime.gd#L246-L298)

4. 不扩大原生覆盖

- 17即时来源场景证明编译及预留17个receipt、0个state，不是实际派发17次回血
- mixed production目前是单目标、一次heal加一次ignite；满receipt/满state混排、反向handler顺序、clear后立即configure并创建新工作的完整原生组合仍未覆盖
- dead-source测试直接设置HP=0；换life测试使用真实转场begin/finish，不是完整死亡复活流程
- zero-loss及更广恢复故障组合没有在本轮独立证明
- actual_healing是恢复回调后的HP差，不是提交瞬间的不可变治疗回执，不能用于声明任意嵌套回血/死亡/复活回调下的精确记账

这些是后续组合范围，当前没有据此建立一个应否定本轮窄修复的失败反例。不要为扩写“全异构已完成”而把它们悄悄算入PASS

5. 原生记录与原始字节

最终46直接+8世界=54唯一采用场景，53份完整framework回执共1409项，其余一项为普通starter-loadout。全部采用记录退出0、无超时，回执检查数组、scene/run/invocation/source和handoff哈希一致

12次原生调用的before/after源码表保持。73次尝试、8个FAIL留存；另一次wrapper启动被mutex拒绝，退出1且没有原生场景，正确不计入native尝试

最终原始日志没有SCRIPT ERROR/ERROR/FATAL，但stderr仍有21次“8 ObjectDB instances were leaked at exit”警告，不能写成无警告或零泄漏

独立字节核验：
- TESTED_SOURCE.zip：15734586字节，3692受测文件全部符合清单
- 源码集重算：86b48f605b4de129b528dd8bc5649ce85233c2503b2503d573ad7cf304310c91
- 与固定Git对象对应：819原字节相同、2873仅CRLF差异，零其他不匹配
- 父到子准确15个源码/配置路径，before/after哈希对应
- NATIVE_EVIDENCE.zip：5410341字节，372成员逐项符合清单且与已提交Git原字节一致

这核实了已记录执行的源码身份，不表示我重新运行Godot，也不表示干净6ae8 checkout已经原生复跑

[运行与归档入口](https://github.com/watermarkpp/HardCore/tree/6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd/docs/review/framework_heterogeneous_20261004)

6. 当前index备份与历史连续性须分开

INDEX_OBSERVATION记录当前df5a01…、39611个staged条目及输出哈希58f820…，说明主控已声明进行了本轮留存。但其中引用的原始备份不在两份ZIP里，固定提交对应路径也不可读取。因此我尚未独立重算实际index备份及staged输出的字节

准确状态应是“本轮备份已报告；远端独立字节核验待可读原件”，不要写成本轮审计已经验证备份内容。若要关闭这一证据项，只需提供已经留存原件的授权可读归档与方法，不需要再次改真实index

历史66c505连续性FAIL、原字节备份MISSING仍保留。新备份不能重建过去，不能据此认定没有发生暂存变化，也不能归因或直接reset/restore

7. 后续建议

本轮可关闭父版多binding同步退休缺陷，并接受当前两个handler的有限混合范围；继续原Task4正式词缀/嵌入/符文来源、死亡子连锁和组合覆盖，不必重做已闭专项

Task5、旧故障supervisor安全复用、设备/GPU/Android、主树/APK和原v97B缺失仍独立开放。墙钟帧间隔不等于CPU时间，有限场景资源排空不等于无限运行内存上界

全程远端只读源码、原始归档和独立重算；未操作本机工作树/index、执行引擎、改工程、发送队列或创建第二施工主控
