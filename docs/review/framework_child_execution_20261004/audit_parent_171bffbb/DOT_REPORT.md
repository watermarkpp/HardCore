171bffbb 本轮二审完成：上一轮错误伤害入口 P2 已关闭；同一正式 planner 的子动作接入有实质证据，但发现一个新的 P2：未绑定地图的子规划可以被接受，却不满足 STRICT_V2。先补这个窄边界，再关闭本轮

请求：child-planner-171bffbb-20261004
固定 SHA：171bffbb69aa7d59b7f0ab30238e8032d67a6ad7
父 SHA：5b8288f773d0659b2d1e45538f93fc9a2556dfba
[固定审查入口](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/README.md)

1. P2：新 child 入口没有隔离旧的未映射兼容分支

ChildActionLease.planning_context 只要求 runtime_map_id 是整数并等于父 world，未排除−1。WorldContext本身也允许捕获该值，没有Root READY或非负地图门禁

由此会出现：child生成绝对Ground GU snapshot，runtime_map_id为−1；共享规划器发现expected_map未绑定，就使用原玩家／旧夹具的has_legacy_base_contract兼容路径返回通过。相同snapshot交给真正STRICT_V2消费端，却会被拒绝，原因为absolute_missing_runtime_map_id

最小反例：在现有feature_child_planner_test中，只把current_map_id从910002改成−1，保留原command、world和双向projection。按当前源码，create_child_request仍可成功，build_canonical_plan仍可accepted，而现有明确STRICT_V2断言应失败

[新child规划上下文](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/features/contracts/child_action_lease.gd#L94-L112)，[旧兼容分支](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/skills/skill_execution_plan_contract.gd#L763-L795)，[STRICT_V2地图校验](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/skills/skill_footprint_snapshot.gd#L976-L1002)

这是源码逐分支确认的纯规划合同反例，尚未原生运行；没有证明Root已经错误执行子动作。旧fallback与父版一致，问题是新增child入口没有把它隔离出去

建议只收紧child：要求有效非负地图绑定，并保证accepted的child snapshot经过明确STRICT_V2验证。补−1／未绑定地图负例和合法地图正例，保留原玩家技能的未映射兼容逻辑，不必全局删fallback

2. 正常child规划接入可以按当前范围采纳

确认仍经过原SkillRuntimeRouter→SkillExecutionPlanContract→原snapshot builder，没有新增第二套planner。child catalog严格限定登记action、handler、revision、operation和伤害策略；它没有被伪装成原33玩家技能中的新增一项

lease对command、definition、credit和有限代次递归复制、冻结；request字段集合、exact script、seed、rank及claims均受校验。没有lease的child ID不能转进旧玩家fallback。提交位置与半径由冻结命令拥有，外部snapshot和自定义geometry builder被移除

原技能表、skill_data_loader、module_registry和contribution_sources的父／子Git blob一致。最终child专项44/44，支持合法地图下的确定性规划、身份冻结、映射和缺owner拒绝；它没有覆盖第1项负地图反例

[当前44项回执](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/native/child_planner_final_direct_124839_685091/framework/feature_child_planner_test.result.json)

Hash有一个不作为本轮第二阻断项的强化线索：既有_canonicalize未对字符串转义或编码类型。纯工厂允许的credit里，“profile_id值为alice,source_id=weapon”与“profile_id值为alice，另有source_id值为weapon”会串化成同一字符串。它不是随机哈希碰撞

但该serializer未在本轮改变，例子也未证明来自可信生产credit；request匹配靠lease字段，Root child尚未执行。因此不能宣称信用归属被盗用或鉴权被绕过。后续若把plan_hash用于强身份／防篡改门禁，应增加带类型、边界明确的序列化回归，而不是把当前hash当成这种保证

3. 父P2实际入口分类已修好，投影恢复也有补证

Enemy在真正causes_struck入口语义下，于prepare、HP和全部副作用前拒绝非direct链标签。把periodic／child批次伪装成direct标签，也会被批次冻结类别检查拒绝。旧空链direct不受新门禁影响

原生RED68检查8失败→最终同样68标签全部通过。3728份RED／GREEN源码清单只差enemy.gd，夹具字节相同；实际生产差异只是三行门禁和注释，Combat与DamageBatch未改

错误入口后，HP、RNG、攻击计时、facts、errors保持；同一batch再经Combat遇到缺投影仍不污染，恢复投影后恰好提交一次并正常死亡撤碰撞。视觉队列未在新夹具中单独读取，其不变由提前return路径支持

[修复位置](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/enemy.gd#L7163-L7171)，[拒绝后恢复验证](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/tests/framework/feature_chain_commit_test.gd#L151-L180)

4. READY失败保留，不能归因成父版问题

canonical_snapshot_identity_production那次失败是真实的：5秒READY断言失败，随后WORLD路径断言失败，记录为early-script-error强制结束、有效退出−1，runner timeout标志为false

两规划文件换回旧字节的控制运行、当前实现重试和最终运行都通过。但控制版本只回退两文件，仍有六个本轮delta与完整父版不同。因此既不能说已经证明旧基线也失败，也不能说已证明新planner导致它；原因继续UNPROVEN

[原失败日志](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/native/child_planner_related_123641_364370/raw/canonical_snapshot_identity_production_test.stderr.log)，[两文件控制范围](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/BASELINE_PLANNER_ASSOCIATION.json)

5. 字节、原生身份和阶段范围核对通过

- 3728份源码逐项哈希及聚合指纹复算一致：bad34a5317297c53c3f827dd208efdc482f2b35a868c4efa2fee0e3a0ca2e673
- 正好8个delta：4新增、4修改；Git对照849份字节一致、2879份仅CRLF，无其他差异
- 源码ZIP15792534字节，SHA256 c82dd5f7c02465940c5ced33fe73bb0c1f402fc8d6abe68a920db5e18c2de4de
- 原生ZIP4619964字节，SHA256 a47df1cfbfd698a557b8772c6d52e4fb319a02f06ba14b684614f5b55d9b4f72；286份成员与清单及Git字节一致
- 11组共56次尝试＝50 PASS＋6 FAIL，原记录完整保留
- 最终直接26场景／21回执547检查，世界8场景／8回执390检查；共34唯一场景、29完整回执937检查，另5项普通场景按runner原合同验证
- 最终退出0、无超时，前后全量源码一致；29回执的实际APPDATA、project、user-dir、PID、run、invocation、source和handoff哈希相符，两组独立owned根
- 六组live→cold均绑定本轮成功producer、相同invocation／源码及不同原生run／PID

最终原始日志未见ERROR／SCRIPT ERROR，但13份stderr有ObjectDB退出告警：11份为8实例、2份为10实例，不能称零泄漏。初始静态／实例方法误用的解析FAIL不算有效功能RED；68／8包含连带检查，不是八个独立缺陷

观察index原件仍可复算，历史66c505连续性FAIL／旧原件MISSING不变。主树、第二树和真实index保护属于归档现场记录；本审计未直接检查用户电脑

[运行索引](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/RUN_INDEX.json)，[最终运行关联](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/docs/review/framework_child_planner_20261004/FINAL_RUN_ASSOCIATION.json)

6. 随后真实链接入，建议先做四个可证伪小实验

一，最后一份即时事实完成，但周期状态仍可能生产child
让根A生成存活周期状态，耗尽即时batch，再让逾期tick致死并派生child；重复旧tick、batch、child回调，并在交付中换world。每个仍能产child的状态／队列／在途batch必须有唯一活跃容量所有者，不能随即时batch结束提前撤销，也不能靠旧回调重新取得资格。单批次回执仍可在其一次性生产者确实关闭后及时退役，无需把所有旧回执拖到整链结束

二，两个根刷新同一周期状态
A建立状态，B增强并刷新同一目标／来源／mechanic；两个即时batch都结束后撤来源，再让tick致死。当前refresh会改变伤害和时间，却保留原command／source／lease。请先明确最终tick的root、generation、credit和未来child容量归属，再用测试证明不借错预算、不双重持有或双重释放

三，保守容量和动态目标的守恒
先用N=3、B=1、G=1的12事实保守例作为oracle；并发多个root、未交付child、逾期tick，交错目标死亡换life、合法召唤、新目标进入释放范围，分别测容量刚好和少一单位。证明已提交工作＋独占承诺从不超限，已接受后不能以晚期截断补救。不要冻结释放时目标，不增加用户要求的目标上限
这里N应来自正式world factory slots和已证明的summon closure；30是已有容量测试的夹具规模，不能拿它冒充一般生产上界，逐目标状态槽16又是另一限制

四，纯规划成功不等于获准执行
同一父fact构造两个不同child release标签，或构造语法合法但不存在的parent fact，纯规划可能成功。真实消费者必须证明来自仍被持有的可信parent fact／binding转移，并且只授权一次；lease、字符串和plan_hash本身不能制造gameplay资格

[当前batch／周期生命周期](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/features/runtime/effect_runtime.gd#L246-L363)，[正式目标上界](https://github.com/watermarkpp/HardCore/blob/171bffbb69aa7d59b7f0ab30238e8032d67a6ad7/scripts/features/adapters/world_target_bound.gd#L3-L60)

这四项是下一步接入建议，不是假定当前已上线的故障。现阶段继续保持DeathBurst不可正式publish，直到生产资格、完整容量和退休闭合

本轮完整结论：修复第1项纯child地图门禁；父P2和已认可证据无需重做。其余Root实际执行、整链动态／逐目标容量、全部生产者退休、防自激、Task3／5／P6、设备／APK及原v97B继续开放。报告留在本对话供原主控直接拉取
