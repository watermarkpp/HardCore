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

最终自然链 feature_publication_final_world_235850_550131：六场景全部 PASS、独立本轮 producer/cold、同4bbd指纹。合并直接最终采用23唯一场景/682完整检查；58原生尝试中的7失败原样保留。原字节源码与完整回执见 docs/review/framework_publication_20261003。

2026-10-04 检查点：已创建并推送受测快照 8664ef242edcd8bfeca3f599e6478636c0a75ca3，父3a1，157总路径中23源码/测试/作者数据增量，其余为原字节证据和计划；远端确认同 SHA。真实第三树 HEAD/index 未切换或覆盖；主树119/第二树249 status 指纹仍与保护记录一致。Pro原6abbcea3与小可爱原01a0f143（durable）均经官方入口实际接到该范围请求，既有dots每10分钟双拉取ACTIVE，完整读取后各自停扫，两份读到后PAUSED。请求记录在 outputs/framework_v2/publication_closure_20261003/AUDIT_REQUEST_8664.json。

资源闭包首个反例 feature_resource_publication_red_001532_569172：真实 GameData 疗伤药图标确实存在；合法非空资源声明无法在正式 Authority/Compiler 目录闭合；旧目录/装配未改变。该测试只定位入口缺口，不作为完整资源功能验收。后续必须补发布前实际线程准备、失败/撤销、已接受动作和状态的租约、共享资源、冷热时序及子效果依赖，不以放宽 resource_paths 枚举就关闭 Task 3。

Task 3 诊断反例 feature_resource_publication_diagnostic_red_002004_334986：3检查/1 FAIL、原生退出1、运行源码固定ff66e4f4。真实路径 res://assets/art/items/service/inventory/client.classic_raw_complete/Items_00014.png；Compiler返回精确 missing_declared_resource。目录/人物保留检查 PASS。还未实现准备与租约，不把此定位当完整闭合。

2026-10-04 续施工：8664两位完整报告已从原对话实际读取并保存，来源消息和正文在 outputs/framework_v2/publication_closure_20261003/audit_8664，旧双拉取任务已官方PAUSED。四项发布边界均先原生证伪再补修：隔离真实建角失败使旧角色base/bundle遗漏恢复（12检查/4 FAIL→12 PASS）；合法旧治疗A待释放、新攻击B已真实结束时仅查最新槽位（20/2 FAIL→含转场/退出31 PASS）；六类错误目录条目被静默跳过（25/18 FAIL→25 PASS）；默认启用依赖与手动路径不一致（16/3 FAIL→16 PASS）。来源是独立审计，根因及修复由单主控核验，保持原HP/planner/writer/动作时序。

本轮最终同内容35场景分组回归及固定增量证据见 docs/review/framework_publication_followup_20261004。此处不预先宣称完整资源/异构组合、模板/整体验收或APK通过；Task 3仍有公开失败反例，Task 4—5继续施工。角色职业切换的临时属性预览也存在直接恢复computed_stats路径，后续需独立核验派生输入一致性，不能把此次建角反例外推为所有属性回滚证明。

2026-10-04 后续检查点：f765两份完整独立报告已从原对话实际读取并保存，自动拉取官方PAUSED。新增正常I/O非法建角（17/8 FAIL→17 PASS）、未知/缺失/错误类型与混合binding（31/18 FAIL→31 PASS）、真实带票据烈火HP提交后同步死亡（19/7 FAIL→19 PASS）、最后批次所有者（11/1 FAIL→11 PASS）均已有原生反例与最小修复。成功claim把容量交给批次，消费者接收后独占queued；未claim取消仍即时，空/拒绝/销毁批次明确终态，无TTL/LRU。最终同73fdf024内容26唯一场景/25完整框架回执658检查PASS；35原生尝试8 FAIL和另1次wrapper启动前错误路径FAIL原样保留。资源诊断仍在同内容FAIL，Task 3—5未关闭。证据见 docs/review/framework_publication_validation_20261004，原生业务结果不外推普通UI自然触发、Android或所有属性回滚。
