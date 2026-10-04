# 第三树功能包发布与组合闭包增量

依据：用户 RFC v2 §5、§8、§16、§20—23，以及原 FRAMEWORK_SERIAL_EXECUTION_PLAN 的 P2/P3/P6。2026-10-03 用户明确授权继续串行施工直到完成，并在完成源码后构建 APK 交小可爱安卓检测。只在第三树工作，保护主树/第二树和真实存档。

原受测审查基线 3a1b781b4b10ddb918f6abca955ae4c33985f2e0；实际工作树 HEAD 5d9ceb0121980ca9636d9d1cc2e19982949fbf63 加固定内容 b234e922。本计划不改写旧原生证据，不重复已闭 lease/journal/UI 修复。

## 串行任务

1. 数据包接入：正式 registry 读取项目内可信 JSON 包；handler 仍为受控内置实现。新包只增定义/注册/测试可到达正式 PlayerState。负例覆盖路径越界、脚本/外部路径、缺文件、未知字段、重复 ID、身份错配及候选失败保留旧目录/装配。先 RED，再实现，再跑 compiler/loadout/空扩展回归。
2. 生命周期发布：明确启动/活动世界受控边界；验证包目录切换和启用不可暴露半配置，停用只撤后续来源，保留已接受动作、效果和不可取消经济回执。与已有世界/lease 唯一所有者接合，不创造第二世界权威。
3. 非空资源闭包：从定义/子效果构建真实依赖，复用现有资源加载/租约和统一预算；发布前必须就绪，缺依赖明确拒绝。覆盖冷/热、失败、撤销、共享租约和已接受效果持续兑现，不修改冻结 MonsterStreaming 实现。
4. 组合协议：通过正式来源编译测试词缀/嵌入/符文贡献和受约束异构机制，覆盖吸血、死亡子连锁、防自激、RNG 和完整接受前容量。新原语默认关闭，只用测试数值；不添加正式符文收费或平衡，不截断 AOE，不回滚 HP。
5. 交付闭包：新增功能模板、生成式/重点组合、自然移动战斗/恢复和预算/时效/有限耐久，最终同源码必要回归、自审、固定 SHA 双审计。之后构建同包/同签名且高于实际旧 APK 版本的验证 APK，校验内容/身份/哈希后交小可爱安卓系统检测；云端与手机结果分别记录。

## 接口与裁决

- 1→2：registry 发布和 enabled 集合必须同一候选；reload 默认保持原调用兼容，增加明确 authoring registry 输入。可信边界是打包在 res://assets/data/features 下的 JSON，不接受 user://、脚本、路径穿越或任意远程文件。
- 2→3：资源准备不得先发布目录/扣资源；就绪候选只在合法生命周期边界提升。旧装配和在途接受 lease 保留。
- 3→4：资源、容量和来源 closure 都在可拒绝接受边界证明；基础 HP 写入后不能为了扩展失败回滚。
- 4→5：所有新增 test primitive 默认关闭，测试走唯一 planner/HP/writer，阶段证据不冒充手机或最终全部源码实跑。
- Ruling：本任务已获 RFC、既有书面串行计划和用户继续施工授权；沿用现有工作区与 CONTROLLER_WORKLOG/证据账本，不重新创建工作树或本地 reviewer，不自动合主树。
- Ruling：原生 runner 需要 tracked 场景。新场景在本增量专属 GIT_INDEX_FILE 中登记，真实 index 不改动；记录 index 身份并验证用户原 index SHA 保持。

## 证据位置

本轮机械预检/原字节备份：outputs/framework_v2/publication_closure_20261003。
原生 RED/GREEN/回归：现有 tools/source176_r3_validation.py，显式 --timeout 30（重场景依既有授权）。未执行写 NOT_RUN，失败保留原始结果，不以 marker 代替最终回执。

Task 1：PASS（本增量受控数据接入范围）。原生反例 feature_registry_publication_red_230829_300978：3检查、1 FAIL，旧接口不能引入新包；最小修复后 feature_registry_publication_green_231153_442676：20检查 PASS。补身份/重复/缺包负例后的 feature_registry_publication_related_231455_810549：5场景全部 PASS、原生退出0、运行期间源码指纹保持。各完整回执与前后指纹保留在 outputs/r3_takeover/20260930/validation；这不是 Task 2—5 或最终发布通过。

Task 2：PASS（本增量原子发布与生命周期范围，整套框架仍未完成）。feature_publication_atomic_red_233123_164923：14检查/8 FAIL，正式启用与默认启用目录能先暴露无效人物候选，发布观察者可重入；修复后14项通过，最终补技能耗蓝范围与重入 reload 后19项通过。feature_publication_lifecycle_red_233728_069955：27检查/12 FAIL；最终30项通过，含无保存身份的真实世界、启动包、输入锁、暂停、多所有者、真实 accepted 技能及非空票据、停用后兑现和 queued-free 收尾。

fixture Ruling：旧 fire_cooldown_configuration 关闭人物 physics 后不等待动作终态，且在活世界内恢复目录。原34项/11 FAIL保留于 feature_publication_related_234146_073565；只修改夹具让真实 physics 完成动作、观察测量后的单次释放，并在退出世界后恢复目录。原伤害与冷却断言、MP观测保留，现41项通过；该夹具原无独立精确MP期望断言，不单称MP公式验收。feature_publication_cooldown_fixture_green_234533_265241：3场景 PASS。

最终直接同指纹 4bbd5374b510b64aa24cc2b8c875c98f1d16e1b81e6826f52e12328bdd2b31a3：feature_publication_final_direct_234845_516247 的15采用场景/400检查 PASS；两 journal 恢复因默认 APPDATA 根不满足夹具要求原 FAIL 保留。按正式 wrapper 的 HARDCORE_AUDIT_RUNTIME_APPDATA 指定新隔离子目录后 feature_publication_journal_isolated_235316_172622 两场景/39检查 PASS，未改源码或断言，producer/cold仍依本轮原生 handoff。

生命周期 Ruling：定义/代码目录替换只在未附着世界或世界完全退休后进行；已注册可信 world_ready 包的来源启用在原世界输入 READY、未暂停、无未结束动作、所有登记 owner 合格的同步事务中进行。startup 包不允许活世界启用。停用撤后续来源，并保留旧 accepted lease/效果/事务的既有去向。此边界委托唯一 PlayerState 世界登记与原 Root/Player 状态，不设置第二生命周期或更改战斗节拍。若 scope 解读或后续资源准备要求更严格，先由固定 SHA 双审计复核。

Task 3：开始 RED；Task 4—5：NOT_RUN。既有 ObjectDB 8 warning 原样保留；本轮原生业务结果不将其当作 Android 或无限耐久证明。

2026-10-04资源续施工：原两条声明/就绪缺口已原生修复，异步准备、typed租约和action→batch→state持有及共享预算应用已实施；原失败和精确RED/GREEN见RESOURCE_CLOSURE_WORKLOG_20261004.md。Texture2D首条声明范围专项通过不替代Task3整体：活世界异步启用、线程已开始后的取消/失败token原生负例、多请求/有限耐久与最终自然链仍继续；Task4—5保持NOT_RUN。

2026-10-04下一固定资源增量：活世界异步启用29检查、实际IN_PROGRESS后的取消13检查、多请求有界交付及四轮持有退休25检查已完成。最终同52beda670内容36场景852检查PASS，具体原始RED/GREEN、原生退出和未覆盖范围见docs/review/framework_resource_closure_20261004。Task3完整范围仍NOT_RUN，继续terminal FAILED清理、更广cue/audio/子资源和资源开启的自然／渲染验证；Task4异构组合、Task5模板／整体验收与APK尚未关闭。

2026-10-04资源后续：声明失败不得发布8/4FAIL→8PASS；Pro本轮通知取消14/6FAIL→最终16PASS，持续两个合法调用者8/2FAIL→8PASS（原就绪未完成/退休峰174→就绪后1帧完成/峰1）；真实主源AudioStream与required图标闭包6/2FAIL→17PASS，声明负例25PASS。最终同7acfe4aef内容41正常场景/926完整框架检查PASS，另15业务检查的真实THREAD_LOAD_FAILED负例：原通用runner保留FAIL、精确预期错误/身份/终态/字节恢复门禁PASS，未放宽allowlist。详情见RESOURCE_FOLLOWUP_WORKLOG_20261004.md及docs/review/framework_resource_followup_20261004。Task3的实际关键cue/子效果消费与资源启用自然/渲染继续，Task4—5/APK未关闭。

最终自然链 feature_publication_final_world_235850_550131：六场景全部 PASS、独立本轮 producer/cold、同4bbd指纹。合并直接最终采用23唯一场景/682完整检查；58原生尝试中的7失败原样保留。原字节源码与完整回执见 docs/review/framework_publication_20261003。

2026-10-04 检查点：已创建并推送受测快照 8664ef242edcd8bfeca3f599e6478636c0a75ca3，父3a1，157总路径中23源码/测试/作者数据增量，其余为原字节证据和计划；远端确认同 SHA。真实第三树 HEAD/index 未切换或覆盖；主树119/第二树249 status 指纹仍与保护记录一致。Pro原6abbcea3与小可爱原01a0f143（durable）均经官方入口实际接到该范围请求，既有dots每10分钟双拉取ACTIVE，完整读取后各自停扫，两份读到后PAUSED。请求记录在 outputs/framework_v2/publication_closure_20261003/AUDIT_REQUEST_8664.json。

资源闭包首个反例 feature_resource_publication_red_001532_569172：真实 GameData 疗伤药图标确实存在；合法非空资源声明无法在正式 Authority/Compiler 目录闭合；旧目录/装配未改变。该测试只定位入口缺口，不作为完整资源功能验收。后续必须补发布前实际线程准备、失败/撤销、已接受动作和状态的租约、共享资源、冷热时序及子效果依赖，不以放宽 resource_paths 枚举就关闭 Task 3。

Task 3 诊断反例 feature_resource_publication_diagnostic_red_002004_334986：3检查/1 FAIL、原生退出1、运行源码固定ff66e4f4。真实路径 res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png；Compiler返回精确 missing_declared_resource。目录/人物保留检查 PASS。还未实现准备与租约，不把此定位当完整闭合。

2026-10-04 续施工：8664两位完整报告已从原对话实际读取并保存，来源消息和正文在 outputs/framework_v2/publication_closure_20261003/audit_8664，旧双拉取任务已官方PAUSED。四项发布边界均先原生证伪再补修：隔离真实建角失败使旧角色base/bundle遗漏恢复（12检查/4 FAIL→12 PASS）；合法旧治疗A待释放、新攻击B已真实结束时仅查最新槽位（20/2 FAIL→含转场/退出31 PASS）；六类错误目录条目被静默跳过（25/18 FAIL→25 PASS）；默认启用依赖与手动路径不一致（16/3 FAIL→16 PASS）。来源是独立审计，根因及修复由单主控核验，保持原HP/planner/writer/动作时序。

本轮最终同内容35场景分组回归及固定增量证据见 docs/review/framework_publication_followup_20261004。此处不预先宣称完整资源/异构组合、模板/整体验收或APK通过；Task 3仍有公开失败反例，Task 4—5继续施工。角色职业切换的临时属性预览也存在直接恢复computed_stats路径，后续需独立核验派生输入一致性，不能把此次建角反例外推为所有属性回滚证明。

2026-10-04 后续检查点：f765两份完整独立报告已从原对话实际读取并保存，自动拉取官方PAUSED。新增正常I/O非法建角（17/8 FAIL→17 PASS）、未知/缺失/错误类型与混合binding（31/18 FAIL→31 PASS）、真实带票据烈火HP提交后同步死亡（19/7 FAIL→19 PASS）、最后批次所有者（11/1 FAIL→11 PASS）均已有原生反例与最小修复。成功claim把容量交给批次，消费者接收后独占queued；未claim取消仍即时，空/拒绝/销毁批次明确终态，无TTL/LRU。最终同73fdf024内容26唯一场景/25完整框架回执658检查PASS；35原生尝试8 FAIL和另1次wrapper启动前错误路径FAIL原样保留。资源诊断仍在同内容FAIL，Task 3—5未关闭。证据见 docs/review/framework_publication_validation_20261004，原生业务结果不外推普通UI自然触发、Android或所有属性回滚。

2026-10-04 Task4第一异构增量：hc.lifesteal.v1、trusted handler成本/生命周期注册、同步派发退休已完成有界原生验证；最终54唯一场景/53receipt/1409检查同内容通过。正式词缀/已嵌宝石/符文组合、死亡子连锁及完整生成式组合仍未完成；Task4整体NOT_RUN，Task5和APK仍继续，不把第一异构命令当整套架构完成。证据见docs/review/framework_heterogeneous_20261004。

2026-10-04 Task4来源增量：正式登记词缀与原宝石经济归属/贡献组合、独立本轮producer绑定cold，以及自身恢复增量在通知前冻结，已原生RED/GREEN和最终同d82f0011内容28场景/1123检查。父6ae8双报告已实际读取保存，当前index原始备份补为可远端核对的ZIP，历史连续性FAIL/MISSING保留。符文、死亡子连锁、防自激与动态完整承诺、生成式组合、Task5与APK仍未关闭，见docs/review/framework_source_composition_20261004。

2026-10-04 Task4符文增量：两个正式登记验证符文共用同一数据creator，hc.runes v1与原Gem扩展共存，经唯一ItemTransactionPort/Journal/writer持久插拔；词缀/宝石/符文三个来源实际受控释放及独立cold/replay通过。父08cc P2伪造affix来源与销毁入口先drain预留事务两项均有原生RED→最小修复→GREEN。最终同5b996731内容40唯一场景/36完整receipt1537检查PASS，原113尝试16FAIL全部保留；原1240身份业务字段保持。证据见docs/review/framework_rune_sources_20261004。死亡子连锁、防自激、动态完整接受承诺、生成式组合、Task5/P6R3/设备/APK仍未完成，继续串行施工。

2026-10-04 Rune guard检查点：37612双审计两缺口已原生证伪并最小修复。未来身份优先分类有效754/117FAIL→754PASS；待取出槽销毁入口有效119/38FAIL→119PASS。实际APPDATA/native用户根/run/process关联由4组owned账户逐份验证；父历史隔离关联MISSING保留。原子链纯容量29与死亡子命令28项通过，但handler未正式发布、Root/runtime未执行。最终同8d6d10f1内容42唯一场景/38完整receipt2150检查PASS；79尝试12FAIL原样保留，详见docs/review/framework_rune_guard_20261004及RUNE_GUARD_WORKLOG_20261004.md。完整Task3资源消费、Task4生产子连锁/动态全承诺/生成组合、Task5模板/P6R3/设备/APK仍未完成，继续原串行目标。

2026-10-04 子链提交基础：父e22两份完整报告已读取并保存，双拉取PAUSED。有限身份/正式投影/提交前拒绝与提交后不可变事实经真实Enemy/Combat端口原生验证，原周期公共签名保持；四个原生失败原样保留。最终同3a10de2c4c889a74b642a865e1430bcee595bf5e59fa714eb513d082c6439322内容28场景/28receipt/885检查PASS，57尝试53PASS/4FAIL，两组owned APPDATA逐份关联。纯根技能身份31检查补证，不要求后代技能等于根；handler仍不可发布。Root子planner、整链动态/逐目标容量、全生产者退休、防自激/生成组合及Task3/5/P6/APK仍未完成，继续CHILD_CHAIN_PLAN；证据见docs/review/framework_child_commit_20261004。

2026-10-04 子动作正式规划：父5b两份完整报告已读取保存。注册子输入经过原唯一planner/STRICT_V2，44项专项通过；误direct入口68/8FAIL→68PASS，并补Combat错误投影不丢资格。最终同bad34a53内容34唯一场景/29完整receipt/937检查PASS，56原生尝试50PASS/6FAIL原样保留。一次canonical READY失败归因未明，两文件旧字节对照和新源码重试通过不改原FAIL。Root真实子执行、整链动态及逐目标容量、全生产者退休、防自激/生成组合、Task3/5/P6/APK仍未完成，继续CHILD_CHAIN_PLAN。证据见docs/review/framework_child_planner_20261004。


2026-10-04 Root子动作续施工：实际同Root规划/查询/HP入口、完整finite immediate链预留、累计工作与串行驻留分离、封口消费分支receipt退休已实施。真实85槽、接受后声明槽换代/晚进入范围、负地图46/2FAIL→46PASS、伪造parent22/4FAIL→合法后续各一次均原生验证。最终同9efaa6ab内容38唯一场景、33receipt1113检查PASS；56原生51PASS/5FAIL保留。详情docs/review/framework_child_execution_20261004及CHILD_EXECUTION_WORKLOG_20261004.md。周期致死→子动作→再点燃、A/B刷新credit与根容量所有权、子资源表现/模板/生成式与自然P6R3/APK仍开放，不关闭Task4整体。


2026-10-04 活链容量/单消费者续施工：父1f6两份完整独立报告已读。正式35检查7FAIL原生证伪后，同35项通过，并补未封口兄弟分支/合法空命中/真实转移。逐事实连续记账、同runtime同步pump重入返回0、Root传播转移与owner_retired均已实施；最终同572286d5c4b82eeae9e9cb270b98c136e264ad47565f051b474d137ae0981ea3内容42唯一场景/1379检查，见CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md及docs/review/framework_child_chain_admission_20261004。周期链有效unsupported_trigger_chain与child_state_capacity RED均保留，临时开放端口已恢复父字节，不发布不完整功能。Task3/4/5、自然P6R3、APK仍未完成。


2026-10-04 周期回调与出生槽检查点：父2b4 Pro完整报告已实际读取；小可爱该请求平台终止FAIL/报告MISSING，不宣称双通过。正式周期HP回调clear原32检查4FAIL→32PASS；同base slot重复出生原9/2FAIL→9PASS，补死亡离group的身体窗口11/1FAIL→11PASS。最终同d94ee4b474239cd21ccdc07080ea713db712cbb69122708b3e3527b164ebe0ba内容45场景/1420检查，见PERIODIC_RETIREMENT_WORKLOG_20261004.md及docs/review/framework_periodic_retirement_20261004。地图formal respawn audit FAIL和父Root单文件对照同FAIL保留，未改authoring。N*S池/完整periodic child、Task3/4/5/P6/设备/APK均继续，不关闭整体目标。
