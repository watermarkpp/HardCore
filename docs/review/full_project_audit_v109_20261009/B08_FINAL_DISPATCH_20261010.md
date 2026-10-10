继续 B08：跨模块生产链和剩余真实职责的精细只读审查。在当前续接对话使用极高，不使用 Pro。用户授权继续全部审计、修复、最终主树集成及109；不要只给计划。

仓库 watermarkpp/HardCore，分支 codex/v108-runtime-bug-review-20261009。本轮唯一固定完整源码 SHA：dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5，Git tree fef3e786da2a7462abdc069f48615215407f6a11。实际读取这个Git对象，不能用主树215f、旧684/b09、当前施工目录或以后远端HEAD替代。本批不可修改生产、测试、资料、配置，不运行Godot/导出，不读取凭据/实际玩家存档。

先读 docs/review/full_project_audit_v109_20261009 中 STANDARD_AUDIT_PROMPT.md、BATCH_08.md、SCOPE.md、AUDIT_SCOPE_MANIFEST.json、CROSS_BATCH_RESPONSIBILITY_GAPS.json、AUDIT_PROGRESS.md，根AGENTS.md、PROJECT_CORE_CONTRACTS.md；再读B01–B07原始 SOURCE_BINDING/COVERAGE/VALIDATION_GAPS 和主控最终台账。B07A原报告在根external/B07A，精确镜像在审计目录external/B07A；B07B在审计目录external/B07B，不混路径。

刚完成的修复是限定职责证据：B07A_FINAL_DISPOSITION/FINAL_EVIDENCE_LEDGER保留GameData加载拒绝传播、失败reload unloaded，native55直接64checks和未改消费者native54的58checks，原53/54失败保留；equipment15、guard9及另外3项I/O，编译器当前两项精确故障和126张/4876具名行完整正例。较早四项编译器故障绑定425817，只是历史，不当当前全部PASS。生成器40函数、persistence44函数、world/targeting/portal63函数补审有逐函数表，依赖与动态边界仍要核实，不以函数数或全部blob读取冒称语义完成。

B07B_FINAL_DISPOSITION/FINAL_EVIDENCE_LEDGER记录Windows suspended process/Job Object ownership、物理路径保护、缺失source失败关闭、实际console/native engine hashes、独立warning分类、immutable HC receipt。native56有13checks clean PASS/native0及完整独立PASS/FAIL自定义checks，2537实际输入未变。Windows helper7、receipt9、log分类最终4项PS范围分开。Assign失败注入/PID reuse/Linux/Android尚未运行；初始6项ownership receipt在代理修正时覆盖，原文件MISSING，不能补造。非framework通用PASS仅功能兼容，正式证据MISSING，不把它与framework/外部冻结台账混为一谈。R2脚本引用仅静态修复，两个diag脚本缺失仍为不可运行历史残留；不能制造空实现、删除证据或称原生通过。

重点新待查生产问题：B08_MODE_RELOAD_CONSUMER_TRACE.json/.md。runtime_service_facade:set_expansion_enabled、game_mode_service:apply_mode、PlayerState读档都可能先提交ContentLayers/模式/字段/信号，再忽略GameData.load_database失败。请实际追启动autoload未READY合法边界、各真实UI/读档caller、唯一状态owner、失败传播/回滚/存档提交，给最小完整修复建议和必须的新负例；报告不能自行当作产品授权，也不能用单个bool修复掩盖半提交状态。

正式跨模块链逐段追输入→攻击/施法提交→HP/MP/防御/受击pause时序→死亡唯一奖励→延后掉落/拾取/物品事务→存档/退出；地图epoch/异步租约失败取消→READY/Loading/UI/音频；玩家及未隐身召唤物6/9/12静态墙LOS激活、远距离正伤害/火墙唤醒→必要攻击与300ms可选规划→实际每帧预算/服务延迟；Boss必要法术与非紧急维护；人工源→稳定ID/正式生成→registry/capability→运行消费者和特殊属性面板。资料总数6083不能改成减少负载的证明，保护/概率/派生索引不得跨历史源恢复fallback。

保持用户已确定合同：300ms只降低非紧急思考，进入范围必要攻击立即且已提交伤害不可取消；近战/锁定/AOE发动或正式跳点结算，只有真实飞行投射物可移动躲避；受击pause与实际动画一致并保留跑步衔接、人物保护窗口；6/9/12槽及当前掉落保护不重设计；复活戒300s免经验仅戒指复活、麻痹普通5s/精英Boss2.5s、戴戒授予技能/脱下移除、隐身/技巧/神秘/探测项链移除/虹魔、价格、祝福油5倍与JP3倍、已验收HUD/图标/血条/金边保留。召唤蝙蝠ID127掉落仍待人类选择，不擅自补概率。

剩余测试语义职责包括formal_world_skill_fixture地图发布/取消、map_runtime_transaction_test_fixtures故障恢复、loot_runtime_pre_slice历史oracle权威、cadence_reference_r2旧节拍、m30_sampling_copy75函数、墙遮挡31函数、UI校准45函数、suite registration顶层。分清正式/兼容/编辑器/微基准/历史角色，用实际函数体与调用者补审，按模块列完整/部分/未审职责；已闭合且源/输入未变不重复跑。大型生产文件同样不能只扫函数签名。优先处理真实跨链接口和重复状态/HP/移动/保存权威，不以无关历史fixture阻断已证明的生产范围。

冗余须核查autoload/class_name/scenes/resources/signals/Callable/动态call/生成器/编辑器/兼容/存档入口；没有普通调用不是可删证明。只报告有证据候选和风险，不删除，不恢复26个退役格子实验，不批量重写人工源/素材。构建核对实际Java consumer四行hook、包com.personal.mafaoffline/原签名/存档兼容/source/engine/seal/内容；最终109与设备由主控负责，当前NOT_RUN。

交付仅新增 docs/review/full_project_audit_v109_20261009/external/B08/ 下七标准文件 SUMMARY.md、FINDINGS.json、FINDINGS.csv、COVERAGE.json、REDUNDANCY.md、VALIDATION_GAPS.md、SOURCE_BINDING.json，另给CROSS_BATCH_CLOSURE.json列每个真实剩余职责。每finding绑定固定SHA、文件/函数/行、正式触发/状态owner/短调用链、事实与推断/未证边界、最小修复和必要验证。不能授予全项目/发布通过；重要缺口明确MISSING/BLOCKED/NOT_RUN，不靠目录/数量闭合。

报告完成时读取远端最新HEAD，在最新HEAD只追加本目录报告，正常push、不force；审查固定源码绑定保持dbb1bd。回读全部blob交报告commit/parent/固定SHA/hash和剩余具体职责。请现在实际读取仓库和固定Git对象开始，不以旧报告、计划或假想读源代替；权限/工具确实缺失立即如实报告。
