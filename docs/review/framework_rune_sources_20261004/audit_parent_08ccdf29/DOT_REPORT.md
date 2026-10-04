本轮独立二审完成：正常词缀＋宝石组合、回血回执修复及归档补证可以按限定范围采纳；发现 1 个需要补修的 P2 词缀来源准入缺口，本轮暂不能整体结案

请求身份：source-composition-08ccdf29-20261004
固定 SHA：08ccdf29e1be5897fa1ffdb6964f58300ad55c3b
父版本：6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd
[本轮源码和证据入口](https://github.com/watermarkpp/HardCore/tree/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/docs/review/framework_source_composition_20261004)

1. 新发现 P2：旧装备兼容入口可以绕过正式词缀来源校验

新 affix 分支先调用 PlayerState._feature_item_eligible。这个既有方法为了兼容旧装备，对没有 drop_instance_contract_id 的物品直接放行。随后新 selector 只核对 drop_affix 的 v3/applied 标记，以及正数 magic_max/add 修饰，没有要求完整的正式掉落实例验证

因此，“这件旧装备可以继续使用”被扩大成了“它附带的字段可以授权新的正式词缀机制”

定位：
- [新来源收集入口，第25–32行](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/features/adapters/contribution_provider.gd#L25-L32)
- [词缀匹配，第16–25行](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/features/adapters/contribution_source_rules.gd#L16-L25)
- [既有装备兼容准入，第3779–3785行](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/player_state.gd#L3779-L3785)

最小反例，供施工方补原生 RED：
- 取本轮真实 item85 的 base，移除 drop_instance_contract_id
- 保留 drop_affix 的 v3、applied=true、有效耐久和 instance_id，把 modifiers 改成两个 magic_max/add/+1
- 使用本轮 composition registry，经隔离装备或 save/load 路径重算来源
- GameData.validate_item_drop_instance 应拒绝该记录，但当前 provider 会按 ordinal 0、1生成两个不同句柄，授予两个燃烧来源

这条路径可从存档数据到达：普通非 gem 旧格式 codec 接受记录；保存装备检查把没有 drop 标记、无扩展、非 relic 的记录按旧装备处理；加载时复制字段并补耐久，没有补做词缀合同校验。进一步删除 instance_id，新 provider 会在正常 compiler 校验之前直接访问 base.instance_id，形成同根的脚本错误路径

[普通旧格式 codec 入口](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/items/item_extension_codec.gd#L38-L47)，[保存装备检查与实例身份判定](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/player_state.gd#L4845-L4888)

此结论来自源码推导，我没有运行该原生反例。影响范围是启用相关注册表后的旧格式／异常存档准入；目前没有证据表明正常生成资产已经损坏，也不能把它认作原 v97 背包故障原因

建议最小修复：在 affix 专用来源匹配前，使用现有 GameData／DropRules 严格验证完整 base。补缺合同标记、伪造或重复 modifier、缺 instance_id 三类负例，明确不得授予来源或产生脚本错误，并验证失败候选保持旧配置。合法非词缀旧装备仍应兼容，不需要全局收紧旧存档 codec

2. 正常词缀与嵌入宝石链路可以采纳

注册表会拒绝未知 affix，定义经过递归只读捕获。词缀来源使用装备实例、注册词缀和 modifier ordinal；宝石来源使用自身实例、所属装备及 socket，来源身份相互独立

live 测试走既有 quote_new→commit→唯一持久化 writer→装备→保存→load_save；移除原宝石只撤它的来源，重插原资产恢复对应句柄，未发现新增 writer 或绕开经济事务提交的路径

最终 live 34项、独立 cold 12项。cold 与本轮 live 的 run、invocation、source、完整 receipt 哈希及原生成功退出均相连，旧 expectation 本身不能充当本轮成功证据

完整 wire 比较也核过：双方先通过原 codec 合法编码，再对整个 encoded.item 做 JSON 边界归一化，没有挑字段或删除资产字段。该测试实际使用的 item ID、roll、耐久数值没有相关精度边界；JSON int/float 表示差异不构成资产变化

[独立 cold 的完整 wire 比较](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/tests/framework/feature_source_composition_cold_test.gd#L35-L48)

3. 回血归因修复正确，17个即时来源也已实际派发

Player.restore_health 在原 HP 写入之后、两个同步通知之前冻结 actual_gain；CombatRuntimeService 直接消费权威返回值，不再在观察者执行之后重读 HP。原写点、钳制和通知顺序保留

原生 RED 的初始 HP50，外层恢复25，观察者独立恢复10，最终 HP85本来就是正确的；错误在于外层被归因为35。保留日志中累计 actual_healing 为40→75。最终修复后仍为 HP85，累计统计改为40→65，只把25归给外层命令

[Player 权威回执](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/player.gd#L1647-L1661)，[桥接消费](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/scripts/layers/runtime/combat_runtime_service.gd#L180-L191)

17来源最终证据：HP50→475，healing_commands 7→24，actual_healing 65→490，即17次命令、425实际增量；peak_receipts=17，peak_states=0。测试确实创建新 batch 并完成派发，已超出父版仅编译／预留17份回执的范围。提高 max_hp 仅在夹具中，正式数值未改

本轮 runtime 94/94、原 production 26/26，绑定同一最终源码。ActorRef 身份／life／world 校验、已关闭的同步退休代次保护、原 planner、实际伤害依据和周期不自激路径保持。此处未发现新增阻断问题

[最终回血与17来源原始日志](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/docs/review/framework_source_composition_20261004/native/source_composition_delivery_direct_083349_171132/raw/feature_lifesteal_runtime_test.godot.log#L10-L15)

保留范围：旧 GameRoot._apply_canonical_friendly_heal 仍有通知后计算差值的既有写法，但目前生产调用者未使用其返回值；本轮不据此增加阻断，也不宣称所有旧回血记账入口都已经迁移

4. 源码、原生档案及阶段计数核对通过

独立核对结果：
- 与父版本正好13个源码／配置增量
- 3700份受测源码全部哈希匹配，内容指纹为 d82f0011f0dd581c0468e8fcad2a460f270cc97caf63003890fb45c8121c1bff
- Git 对照827份原字节一致、2873份仅 CRLF 差异，零其他差异
- 原生 ZIP 的416份文件与清单和远端 Git 字节一致
- 13次调用共82次原生尝试：77 PASS、5原始 FAIL保留
- 最终采用两个调用，共28唯一场景＝20直接＋8世界；24份完整 framework receipt、1123检查，另外4项为普通场景
- 最终运行前后源码一致；原生退出0、无超时，原始日志扫描未发现 SCRIPT ERROR、ERROR、解析错误或断言失败

仍有10个最终场景保留 ObjectDB 退出告警：9个报告8个实例，summon_actor_state_machine_test 报告10个实例。因此可以说本轮无引擎错误，不能说无告警或无泄漏

阶段口径补充：最早1检查1FAIL是“已注册词缀入口未被接纳”；早期绿色 live 为32项，其中第3项包含未知词缀拒绝。最终增加 expectation 所有权／写入检查后变为34项，cold另计12项。不要把这几个阶段混成同一个计数

三份 ZIP 的大小和 SHA256 均已复算，与本轮 SCOPED_EVIDENCE 一致：[运行索引](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/docs/review/framework_source_composition_20261004/RUN_INDEX.json)，[归档身份](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/docs/review/framework_source_composition_20261004/SCOPED_EVIDENCE.json)

5. 当前 index 原件缺口已补齐，历史连续性仍未恢复

INDEX_OBSERVED_BYTES.zip 已实际读取并复算：
- ZIP：2575546字节，SHA256 1fe862794a3c16c2e3e471b95b58396f2654e5ad4867a38e0817e48cb6aa6de6
- index 原件：6407024字节，SHA256 df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb
- staged 文本：5678323字节，SHA256 58f820e21ad45db9ee7606bcf143de644314f2b70b7551548475756dfd0f7733

解析结果为 DIRC v3、39611个 stage-0 条目，尾部 SHA-1有效；按 mode／blob／stage／path 重序列化，与提供的 staged 文本逐字节吻合

这关闭的是父报告“当前观察值没有可读原件供独立复算”的缺口。历史66c505期望值与现值不同，连续性仍为 FAIL，旧备份仍为 MISSING，原因仍未建立。不得用当前归档替代历史证据，也不需要为了审计去 restore、reset 或重建真实 index

[当前观察原件](https://github.com/watermarkpp/HardCore/blob/08ccdf29e1be5897fa1ffdb6964f58300ad55c3b/docs/review/framework_source_composition_20261004/INDEX_OBSERVED_BYTES.zip)

6. 本轮结论与下一步

请先对第1项补最小原生负例及 affix 专用准入修复，推送固定增量复审。已认可的回血归因、17来源实际派发、完整 wire 比较和当前 index 补证无需重复施工

本轮是远端源码及既有原生档案的独立复核，没有重新运行 Godot。组合夹具使用受控 Root API、停 AI、手动推进 clock／pump；cold证明资产、来源、所有权和原操作重试，不证明战斗状态或地面掉落恢复。主树／第二树的现场保护属于生产方归档记录，我未直接检查用户电脑

正式符文、死亡子连锁、生成式组合、Task5、自然P6/R3、旧故障supervisor安全复用、原v97B输入、Android／GPU／APK继续保持开放。以上完整报告留在本对话，供施工主控直接拉取
