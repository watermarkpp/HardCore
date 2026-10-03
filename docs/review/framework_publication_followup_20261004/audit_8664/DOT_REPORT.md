8664ef24 独立二审完整结果，供施工对话直接读取

固定版本：8664ef242edcd8bfeca3f599e6478636c0a75ca3
父版本：3a1b781b4b10ddb918f6abca955ae4c33985f2e0

结论：本轮暂不接受“人物原子发布与生命周期门禁已闭合”。发现一项阻断性的失败回滚缓存问题、一项未结束动作门禁缺口，以及两个由新接入路径暴露的既有目录校验缺口。提交的测试证据能对应，但没有覆盖这些反例

以下反例来自固定源码的静态推导，我没有运行引擎，不能标成已完成原生 RED

1. P1：角色创建失败回滚后，pre-feature 缓存仍属于被拒绝的新角色

新的候选准备直接使用 _feature_base_stats，但创建角色会先试算新人物；保存失败时，回滚恢复了原人物和 computed_stats，没有恢复新缓存

可直接扩展现有 new_character_starter_loadout_test 的原子写入失败夹具：
- 初始为 1 级战士、没有附着世界、没有已启用功能包，基础 max_mp=15
- 注册一个默认关闭、通过 rule 绑定的数值包，对 max_mp 做 add −16。负加法是现有 schema 允许的
- 尝试创建 1 级法师，并通过现有测试失败入口让原子保存失败
- 临时法师试算得到 max_mp=18；回滚后人物又是战士，computed_stats.max_mp=15，但 _feature_base_stats.max_mp 仍为 18
- 此时启用该包，候选按 18−16=2 校验通过，提交启用集合、bundle、stats=2，并增加 compile_count
- 发布通知随后触发真实战士重新汇总：15−16=−1，被 feature_stat_range:max_mp 拒绝，返回时没有替换刚提交的 stats
- 外层发布仍返回 true，最终留下“包已启用、新 bundle/编译次数已提交、stats=2、feature_errors 非空”的不一致状态，而且通知已经发出

战士 15、法师 18 来自现有等级公式；初始木剑、布衣没有 MP 加成。不是通过修改生产属性公式构造的反例

最小整改：让派生缓存纳入与 computed_stats 相同的事务回滚范围，检查其他直接恢复人物/属性的分支，或在候选准备时通过唯一现有汇总权威取得与当前人物一致的快照。不要新增第二套属性公式，也不能仅在通知后发现错误就返回 false，因为此时状态和通知已经发布

必须新增“真实创建失败→回滚→启用候选”检查：启用应失败，旧目录、启用集、bundle、人物属性、compile_count、原错误状态均保持，通知次数为零

[缓存使用](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/player_state.gd#L3743-L3763)
[创建与失败回滚](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/player_state.gd#L9373-L9400)
[恢复函数](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/player_state.gd#L9708-L9780)
[提交与通知](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/layers/runtime/content_layer_registry.gd#L163-L185)

2. P2：最新动作槽结束，不代表所有已接受的延迟动作都已结束

feature_publication_context 只检查 combat_action_snapshot().active。这个快照代表最新动作，而 Player 明确保留被后续动作覆盖的旧延迟释放

合法数据与真实动作链可以形成以下窗口：
- 世界附着前，启用可信测试数值包，对 hc.skill.taoist.healing 的 timing.effect_resolve_ms_from_cast_start 加 4200，使释放从 800ms 变成 5000ms。该字段在白名单内，数值通过现有 effective-definition 校验
- 身体动作仍为 600ms、动作锁仍为 1500ms；t=0 在正常 READY 世界接受治愈术，保留真实 lease
- t≈1.6s 正常普通攻击通过原门禁，覆盖最新动作槽；默认 +0.17s 释放、+0.51s 身体动作结束
- 约 t=2.12s 后，最新槽 active=false，但旧治愈术的 accepted producer 尚未在 t=5s 兑现
- 此时另一个已注册 world_ready 包能通过新门禁启用，违反本轮声明的“无未结束动作”边界

这不是旧 lease 被丢弃的证据。问题是新发布进入得太早，不能用“旧释放仍然保留”证明门禁正确

最小整改：从现有 Player 生命周期提供覆盖所有尚未终结 accepted producer 的只读状态，不只查看最新动作展示槽；在完成、拒绝、取消、死亡、换图、退出时按真实终态退休。不要禁止已有合法动作覆盖，也不要改战斗节拍

新增真实双动作测试：第二动作结束后仍拒绝启用；旧延迟 producer 完成后才允许；旧释放/治疗事实仍恰好一次

[门禁](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/player_state.gd#L9311-L9330)
[旧延迟释放与最新动作槽](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/player.gd#L1276-L1451)

3. 新目录接入路径还需两个 fail-closed 反例

这两处逻辑在父版本已存在，本轮允许新的打包 registry 输入后成为本次接入范围内的问题，不能说是本轮新改坏的解析语句

- modules 中的非 Dictionary 项被静默跳过。例如 schema_version=1、modules 只有一个 null、bindings 为空时，会发布空目录，替换旧装配，而不是拒绝格式错误
- reload 收集默认启用集合时，没有复用单独 enable 的依赖启用校验。合法定义 A 依赖 B、A 默认开启而 B 默认关闭时，目录编译只确认 B 存在，结果仍可以发布只有 A 启用的集合

建议：非法模块项明确报错；默认启用集合也经过统一依赖闭包校验。两类失败都必须保持旧目录、启用集、人物、bundle、编译次数和通知不变。这里不要求扩大到任意第三方脚本沙箱

[目录解析、默认启用及独立 enable 校验](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/scripts/layers/runtime/content_layer_registry.gd#L92-L237)

4. 已确认成立的边界

没有把所有实现都判为失败。当前源码中这些部分是有依据的：
- 普通候选拒绝使用复制的 loadout，保留旧不可变 bundle 和编译代次
- 负技能 MP 会在提交前经过既有 effective-definition 校验
- 配置赋值与 PlayerState commit 区间没有 yield/回调；发布期间的 enable/reload 观察者重入被拒绝
- 空 profile 世界仍登记；多个 live owner 都检查；暂停、输入锁、当前动作 active、queued-free 都会拒绝新启用
- startup 包不在活世界启用；有登记世界时目录 reload 拒绝
- Root 在效果、死亡结算和拾取 writer 收尾后才注销精确 owner；本轮没有改旧 accepted lease 释放或经济 writer 实现

但这里确认的是 PlayerState 配置提交边界。实际 Player 节点仍经已有 profile_changed 回调刷新，不能笼统扩大成所有场景节点在通知前同时更新

原始 RFC v2 文件未在本次固定仓库已查入口取得。新 closure plan 是施工解释，不能代替 RFC 原文。因此我不凭记忆制造 RFC 违规，也暂不签署“已逐条符合原 RFC”的结论；如果需要这一项，请提供固定可读的原 RFC 路径

5. 原生证据核验结果

证据计数与身份核验通过，不存在把失败改写为成功的发现：
- 12 次 runner、58 次原生尝试、7 次失败保留
- 最终同 4bbd5374… 内容采用 23 个独立场景、682 项检查
- direct 组仍为 15 PASS/2 FAIL：通过场景 400 项，加独立 journal 39 项为 439；六个 world 场景再加 243，合计 682
- 58 份回执逐项对应 scene/run/invocation/source、连续检查编号、结果、退出及 before/after 稳定性；成功 handoff 的原始回执哈希对应
- 四条 live→cold 均关联同 invocation 的本轮成功 producer，没有借用历史产物
- NATIVE_EVIDENCE 的 310 个成员长度/哈希与清单一致；TESTED_SOURCE 的 3585 文件哈希及源码集指纹重算一致，并全部与固定 Git tree 原字节或 CRLF→LF 规范化对应

这些通过记录没有覆盖前述创建失败后缓存污染、旧延迟 producer 被最新槽遮蔽及两类 registry 输入反例，因此不能据此关闭问题

[运行索引](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/docs/review/framework_publication_20261003/RUN_INDEX.json)
[源码清单](https://github.com/watermarkpp/HardCore/blob/8664ef242edcd8bfeca3f599e6478636c0a75ca3/docs/review/framework_publication_20261003/SOURCE_MANIFEST.json)

6. 夹具与报告措辞修正

cooldown 夹具原伤害与冷却断言保留，MP 测量值也保留；先记录测量，再让真实 physics 完成动作，退出后恢复目录，这个调整有依据。最终四项冷却为 8000/4000/4000/4000ms，MP 均记录 93，均有伤害且一次释放

但该场景原来和现在都没有单独 MP 断言，应写“保留 MP 测量”，不要写成“MP 断言通过”

ObjectDB 日志是每条警告提示 8 个实例；共有 23 次尝试的 stderr 保留该警告，其中 10 次为最终采用记录。不能理解为总共仅 8 条警告，更不能说零泄漏

子引擎 SHA 目前只在 SCOPED_EVIDENCE 声明，在 310 个原始成员里没有找到逐 invocation 绑定。console SHA 有 before/after 记录，日志有 Godot 4.7 身份；这不等于独立验证了每次子引擎二进制哈希。后续可补实际执行进程对应见证，现有声明应保留这个限制

施工顺序建议：先在现有失败夹具补第 1 项原生 RED；并行准备第 2、3 项最小反例，确认后做最小修复。保留本轮已通过证据，不改旧失败标签。修复后给新的固定 SHA，再审差量与相关回归；资源闭包、异构组合等其他施工继续与这些结论分开，不把本轮当作整框架、真机或 APK 验收
