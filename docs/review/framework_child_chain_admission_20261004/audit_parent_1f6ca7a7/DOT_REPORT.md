1f6ca7a7 二审完成：真实Root子动作入口、负地图修复及伪造parent资格修复都有证据；整链容量与分支生命周期仍有两项P2，需要补原生反例和修复。本轮不能关闭“接受后完整兑现”的保证

请求：child-execution-1f6ca7a7-20261004
固定 SHA：1f6ca7a78e2163c3365bbcb38710018e6eee4dbf
父 SHA：171bffbb69aa7d59b7f0ab30238e8032d67a6ad7
[本轮入口](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/docs/review/framework_child_execution_20261004/README.md)

1. P2：分支部分消费时，仍承诺给该链的fact容量被短暂让给其他根

累计与驻留的数学拆分本身正确。N=85、B=1、G=2时，累计facts为85＋7225＋614125＝621435，child命令7310；串行驻留保守取170 facts／170 receipts，也不是把全部累计工作同时放进内存

问题在记账转换：submit把fact预留转为pending；每消费一条，pending立即减一；但只有整个分支最后一条结束，才把整批fact名额加回预留。中间这些名额看起来已经空闲，实际根还要依靠它兑现后续child

reserve_action恰好用pending＋reserved_facts判断新根是否可接受，因此可能超卖

一个全部receiver bound不超过85的确定性数值反例：
- 接受一条上述链，驻留fact预留170
- 保留94个合法、零持续状态的单binding吸血票据，每个预留85；总fact占用8160
- 提交该链85条事实：reserved=8075、pending=85
- 消费53条，其中至少一条致死并排出child：reserved=8075、pending=32
- 此时另一85-fact根会被接受，因为8075＋32＋85＝8192
- 再消费剩余32条，分支结尾返还85：reserved=8245、pending=0，超过8192上限
- 队列中的child继续持有根，不能靠终态回收立即消除这个超额

其他门禁不会挡住该反例：receipt承诺8245仍低于65536，state为0，child承诺7310低于8192，root记录数也未到上限

[准入检查](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/features/runtime/effect_runtime.gd#L81-L129)，[提交、逐fact消费及整批返还](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/features/runtime/effect_runtime.gd#L274-L371)

后果超过统计数字：下一非空child先通过真实HP循环，再提交事实；submit_batch此时会因超额拒绝，可能丢失后续事实／派生动作。_finish_feature_damage_batch只记录错误和关闭producer，而child返回值不包含submit成功与否，child_actions还可能计作成功

[HP之后才提交及返回结果](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/game_root.gd#L14957-L15013)

这是已核实的runtime准入API／源码反例，未运行引擎；没有证明普通单Player当前能自然积累这种极端保留票据数。它检验的是本轮明确声称的同世界全局容量不变量

修复方向：活链的驻留承诺在部分消费期间必须持续计费，不能先让别人使用、再无条件加回来。包括同步回调中的准入也必须遵守。不要提高容量，不要在已提交HP后拒绝已接受child作为补救

新增RED应覆盖“部分drain→竞争根准入→分支最后返还→排队child继续”，逐步断言总承诺不越界、额外根在不可承诺时提前拒绝、已接受child事实恰好完整交付。submit失败不能继续被汇总成正常child成功

2. P2：同步重入pump可在外层消费者结束前回收分支

当前_dispatch_one_fact在调用_deliver_fact之前就推进cursor并减少pending。最后一条被内层pump取出并返回后，代码认为所有消费者已经完成，但外层第一条事实可能仍停在同步通知里

最小反例：
- 一个有限根有两条已提交事实，binding顺序为lifesteal后death_burst
- 第一条致死，第二条不致死；来源为可合法恢复的Player
- 第一条lifesteal调用restore_health，触发同步stats_changed／resources_changed
- 一个只调用一次的观察者再调用runtime.pump
- 内层处理第二条并回收根分支／reservation
- 外层回来继续处理第一条death_burst时，记录feature_dispatch_reservation_missing并退出，本应产生的child丢失

FrameBudget允许预算有余时的嵌套LIFO scope，并没有同runtime的重入互斥，所以不能把它当作防护

[分支消费与回收](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/features/runtime/effect_runtime.gd#L324-L398)，[同步恢复通知](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/player.gd#L1647-L1661)，[嵌套预算scope](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/layers/runtime/execution/frame_budget.gd#L90-L168)

这是同步观察者＋公开pump的源码反例，未原生复现，也未确认当前自然生产观察者会这样调用。父版普通非链回收已有类似形状，本轮新分支回收和串行驻留证明继承了该弱点，不能说全部由本提交新引入

建议用真实Player通知＋一次性重入观察者补RED，断言第一条死亡child恰好产生并执行一次、无reservation丢失错误、最终根／分支／receipt／容量全部排空。修复可以明确强制串行消费，或在回收前正确计入尚未返回的消费者；不能吞掉错误来伪装成功

这与第1项不是同一个反例：第1项无需重入，普通预算切片就足够；第2项用很小的两事实场景检验生命周期

3. 已完成的两个窄修复可以关闭

负地图：ChildActionLease工厂增加非负地图拒绝，旧玩家未映射兼容路径不变。原生46检查／2FAIL对应原第44–45项，最终46/46。父171的地图P2可以关闭

伪造parent：Root在planner之前验证当前runtime、确切票据和已登记ChildActionLease实例身份。纯语法相同、计划hash相同或伪造parent_fact都不能取得真正分支资格

probe用真正票据配上新建伪造lease，parent_fact为:hp:999，先调用伪造请求、再调用真实请求。原22检查／4FAIL是同一抢资格缺陷的连带结果；最终26/26，两次真实波次都完成

[地图工厂修复](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/features/contracts/child_action_lease.gd#L23-L28)，[身份授权](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/features/runtime/effect_runtime.gd#L158-L164)，[伪造请求先行probe](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/tests/framework/fixtures/child_execution_probe_root.gd#L7-L19)

4. 真实立即链执行和动态目标证据成立，但边界要准确

本轮确实安装了原Root到同一个EffectRuntime的执行入口，经同一canonical planner、STRICT_V2快照、释放时空间查询和精确相交，再走Combat→Enemy原HP权威。未发现第二planner／HP写者，也没有把子动作再扣一次Player MP。child使用独立确定性RNG和非direct STRUCK通道

目标来自实际释放时查询，没有发现固定截成30个目标。原生夹具中根只命中第一怪，后续怪不是根命中目标；接受后第三怪在已声明factory槽被销毁并重新创建，旧ActorRef失效，新life移动到第二波范围，第二波命中它。世界上界仍85

最终验证包括第一波目标4→0、换代目标1000→998、两次child释放、即时死亡撤碰撞、Root／Player RNG与MP保持，以及普通路径下最终无根／分支／receipt残留

[真实Root执行路径](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/scripts/game_root.gd#L14974-L15013)，[两波与换代测试](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/tests/framework/feature_child_execution_test.gd#L73-L113)

不能扩大成任意新槽无限出生、自然复活计时、OS／UI输入、完整奖励或持续战斗证明。该夹具关闭AI／自动process，通过手动pump观察真实生产API

另外，末尾旧票据断言针对root票据，不等于真实child票据退休后重放；排队child跨真实world替换、source life替换和重入多根的原生集成覆盖仍有限。静态身份／代次防护可保留，但不要把这些写成已经全部原生通过

5. 原生证据及字节身份复算通过

- 3733份源码逐项哈希和聚合指纹一致：9efaa6abf58436350b65354856476d635059e6d28d26502dba2b92f3ecb5f404
- 父到当前17路径变化：5新增、12修改；Git854份字节一致、2879份仅CRLF，零其他差异
- 源码ZIP15802560字节，SHA256 5a120b31c108507a5e98a323e2fdfa40e43ed825ac86c72f37846bbc9af71770
- 原生ZIP4315981字节，SHA256 28e8178e5e7c315d657a258f12b48230ecce44729e1e697dd1db4258f7d47739；287份成员与清单及Git字节一致
- 10组56次原生尝试＝51 PASS＋5 FAIL，原失败保留
- 最终direct30场景／25回执719检查，world8场景／8回执394检查；共38唯一场景、33完整receipt、1113项通过检查，另5项普通场景按runner合同验证
- 最终原生退出0、无超时，两组运行前后源码一致；实际APPDATA、project、user-dir、native PID、run、invocation、source和完整handoff回执哈希相符
- 六组live／cold均绑定本轮producer，producer退出先于cold启动，原生PID不同；它们验证既有业务，不补充第1、2项尚未运行的新反例

最终原始日志无ERROR／SCRIPT ERROR；16份stderr仍有ObjectDB退出告警，14份为8实例、2份为10实例，child_execution自身也有8实例告警。部分中间PASS还保留CanvasItem／resource-in-use清理诊断，因此功能PASS不能外推无告警或无泄漏

[运行索引](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/docs/review/framework_child_execution_20261004/RUN_INDEX.json)，[当前原生关联](https://github.com/watermarkpp/HardCore/blob/1f6ca7a78e2163c3365bbcb38710018e6eee4dbf/docs/review/framework_child_execution_20261004/FINAL_RUN_ASSOCIATION.json)

观察index原件复算正常，历史连续性FAIL／旧原始备份MISSING不变。父版READY失败的原因仍未证实，后续PASS不倒推它的归因。现场保护只按已归档记录核对，我未访问用户电脑

6. 后续施工建议

先做两项独立原生RED：部分drain的并发容量守恒，以及同步重入时在途消费者退休；随后最小修复并验证已接受child最终事实不丢、提交失败不被计作成功。不要提高上限、晚截断AOE或靠TTL／LRU替代所有权

已认可的负地图、实际lease授权、同一planner／HP和声明槽动态释放查询无需重复施工。周期致死→child→再点燃、A／B刷新归属／credit／预算、历史状态并发、完整producer退休仍未闭合；单个child目标循环作为一个quantum的最坏服务成本也尚未证明

本轮保持限定结论，完整Task3—5／P6R3、APK／设备、原v97B和破坏式监督器安全均不据此结案。以上为远端源码和原生档案审查，两个新增P2未独立运行引擎复现。完整结果留在本对话供原主控拉取
