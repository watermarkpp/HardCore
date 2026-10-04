5b8288f7 二审完成：提交事实冻结、原周期接口兼容及先前根技能校验问题可以按范围采纳；发现一个新的 P2 入口分类缺口，需要补修后再关闭本轮

请求：child-commit-5b8288f7-20261004
固定 SHA：5b8288f773d0659b2d1e45538f93fc9a2556dfba
父 SHA：e22fe0951f28c55620399b453f116cb09120af4b
[本轮源码与证据入口](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/docs/review/framework_child_commit_20261004/README.md)

1. P2：周期／子伤害批次仍可经直接受击入口提交

Enemy.take_damage 固定以 causes_struck=true 调用共享伤害核心。新增链预检只核对调用者填写的 source_class 是否与 batch 内类别一致，没有核对它是否符合实际调用入口

因此，一个合法 periodic／child batch，只要同时填写相同类别，就能经过 take_damage 提交相应类别的事实，却执行直接伤害的 STRUCK 行为

最小反例，使用已有公开 API即可：
- 仿照本轮测试，创建并打开合法 periodic generation=0 或 child generation=1 的 batch
- 使用30HP、正式投影有效、没有治疗观察者的 Enemy
- 经 take_damage 提交10点伤害，context包含该 batch、匹配的 periodic／child source_class 和 magic_defense channel
- 当前预检通过，HP变成20，batch收到同类别事实，之后可封口并消费
- 因入口固定 causes_struck=true，存活目标还会增加原直接受击的下次攻击延迟，并在有visual时请求受击动画

这里准确说的是 STRUCK 的攻击延迟／视觉反馈，不是证明角色移动被锁住

[实际入口及预检](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/enemy.gd#L7070-L7184)，[直接受击分支](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/enemy.gd#L7201-L7217)，[batch只核调用者类别的位置](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/features/runtime/damage_batch.gd#L93-L109)

这是源码确认、尚未原生执行的公共端口反例。当前Root仍产生普通direct批次，原周期调度也使用旧周期端口，未发现自然玩法已经这样误调用。不能把它描述成已观测游戏故障，但当前“错误类别／回调在HP前拒绝”的声明还少这一入口

建议最小修复：将链类别与实际Enemy入口语义绑定，在take_damage的HP、受击副作用之前拒绝非direct链批次。保留旧空链direct语义，不修改周期公式或增加另一HP权威

补周期→直接入口、child→直接入口两类非致死原生负例：HP、攻击计时、RNG、facts及batch errors均不变；随后同一个未被污染的batch经合法命名端口提交恰好一次。当前已有的periodic／child命名端口互相误调检查应继续保留

2. 真实HP提交事实的冻结顺序成立

DamageBatch在领取预留前验证有限链的字段、类别、release／root skill关系、整数代数和上界；credit、bindings、chain及最终事实均经递归复制、只读冻结。调用者随后修改原对象不能改写已捕获的事实

Enemy使用正式地图投影取得Ground GU，覆盖调用者给出的提交位置。原HP写入后立即捕获hp_before、hp_after、actual_loss和旧生命身份，再进入同步健康刷新及后续死亡处理

测试里的观察者把当前位置移到(777,888)、把HP恢复到100，最终事实仍保持原来的30→0、actual_loss=30和Ground GU(12.5,-3)。这是提交事实不受后续观察者污染的有效证据

[唯一写点与事实顺序](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/enemy.gd#L7163-L7198)，[batch事实冻结与一次性转移](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/features/runtime/damage_batch.gd#L151-L210)

命名periodic／child端口的错误类别在防御随机数和HP之前拒绝，且不向合法batch追加错误。原callback RED确实是37项中14失败，问题包括错误调用使后续合法提交失效；最终链测试56/56覆盖拒绝后继续合法提交，原失败没有改标签

投影缺失测试证明不改HP、不产事实；随后恢复投影重试的非污染性，当前还主要由源码支持。两次投影之间的正式地图路径没有yield或信号，未找到自然状态改变触发点，所以不把人为构造的“第一次有效、第二次无效投影函数”列为新增游戏缺陷

有限链身份目前只是结构和当前root-scoped上下文验证，并未证明真实祖先存在、完整子描述、整链接受前容量或异步退休

3. 周期公共合同和真正死亡退休得到保留

Enemy.take_feature_periodic_damage仍是原4参数，CombatRuntime.apply_feature_periodic_damage仍是原5参数；新携带batch的链端口使用另外的名字。既有ObservedEnemy四参数override与父版字节一致，原生产effect_runtime调用也未被迫换签名

原中间版本的签名回归确实导致该override解析失败；档案保留FAIL、有效退出−1、强制结束和无合法本轮回执，未拿错run／错source的旧回执充数。最终periodic boundaries22、runtime13、实际死亡production16，以及chain56等专项均通过

[公共签名与共享实现](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/layers/runtime/combat_runtime_service.gd#L193-L236)，[原始签名失败](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/docs/review/framework_child_commit_20261004/native/child_commit_boundaries_115439_573406/raw/periodic_effect_boundaries_test.stderr.log)

正确路由的周期／child端口共享原MAC和HP路径，保留周期免疫、非正值无操作语义，并使用causes_struck=false

没有被观察者治愈的真实致死用例，通过原_mark_death_pending立即清碰撞layer／mask、移出敌人组及空间登记，并使生命epoch增加。最终chain第52／54项核碰撞退出，第55项核事实仍持旧life、actor只增代一次

这些真实死亡断言与前述“观察者治愈／移动但事实保持”的断言是不同场景，不能混为一种证据

4. 先前纯handler的根技能身份问题已关闭

generation=0／direct的fact.skill_id缺失或与root矛盾，现在会拒绝；后代不同skill仍有明确正例。原identity RED为31项中2失败，对应冒用和缺失；最终31/31，后代不同身份正例保留

[身份门禁](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/scripts/features/handlers/death_burst_handler.gd#L32-L43)，[原生负例与后代正例](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/tests/framework/feature_death_child_command_test.gd#L76-L88)

这关闭的是父报告指定的direct根事实边界。当前Batch对所有链类别都约束root-scoped skill；未来独立child descriptor接入后，仍需明确新的可信身份关系，不能把纯helper当作独立谱系权威

DeathBurst仍不在正式IDS／CONTRACTS，Root未接child planner，EffectRuntime仍无RequestChildAction执行分支。本轮真实HP测试使用受控batch，不能算整链容量接受、生产子链释放或退休已经完成

5. 字节、运行身份和采用范围复核通过

独立复算与核对结果：
- 3724份源码全部SHA256匹配，较父版正好7路径变化
- 内容指纹3a10de2c4c889a74b642a865e1430bcee595bf5e59fa714eb513d082c6439322
- 固定Git对照845份字节一致、2879份仅CRLF，零其他差异
- 源码ZIP15784115字节，SHA256 5892e686e68c7e721825b42fd7d36915f88d3f4d68ed7be29cd6435e468b2318
- 原生ZIP4238745字节，SHA256 a40dea107e45d87ce81418e9e037fe0cf03d3cd19db5c63774aebc56198f5bf7；296份成员长度、哈希及远端Git字节一致
- 原生10组共57尝试＝53 PASS＋4 FAIL，逐行与RUN_INDEX一致
- 最终DIRECT20场景491检查，WORLD8场景394检查，共28唯一场景／28完整receipt／885检查
- 所有最终run、invocation、source、原生PID／project／APPDATA／user_data_dir、handoff完整回执哈希相符；两组独立owned根、退出0、无超时、前后源码稳定
- 6组live／cold关联本轮指定成功producer，cold为不同run／PID；它们验证既有组合和持久化行为，不是新死亡子链的cold证明

四项原FAIL分别是原链合同缺口、错误回调污染回归、公共签名解析回归、纯handler身份缺口，均保持原状态

最终11份stderr仍各有8个ObjectDB实例退出告警，不能称零泄漏。完整diff-check失败与source-only通过仍分开保留。当前index原件可复核，历史连续性FAIL／旧原件MISSING不变

[运行索引](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/docs/review/framework_child_commit_20261004/RUN_INDEX.json)，[最终原生关联](https://github.com/watermarkpp/HardCore/blob/5b8288f773d0659b2d1e45538f93fc9a2556dfba/docs/review/framework_child_commit_20261004/FINAL_RUN_ASSOCIATION.json)

下一步只需针对第1项实际入口分类补原生RED和窄修复，已认可的事实冻结、旧周期合同、根技能身份及证据关联不必重复施工。本报告为远端源码和既有原生证据复核，没有重新运行引擎

完整链、动态／per-target承诺、异步退休、防自激、Task3—5／P6、supervisor安全、设备／APK和原v97B继续开放。完整结果已留在本对话，供主控拉取
