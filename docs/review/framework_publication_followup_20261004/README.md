# 功能包发布边界四项增量核验

父审查提交：8664ef242edcd8bfeca3f599e6478636c0a75ca3。施工目录与真实HEAD/index保持原现场；原生运行是该HEAD加清单中的字节，不称新审查提交的干净checkout实跑。源码/资源/组合全工程仍在施工。

## 原生反例、根因与修复

1. **建角失败恢复**：在本轮nonce专属user目录，真实创建战士A（等级1，MP15），真实装备木剑提供测试贡献，再通过既有原子保存失败注入尝试创建法师B。旧代码恢复computed_stats却遗漏pre-feature输入，且B的装备身份改变会覆盖有效bundle。精确隔离RED为12检查/4 FAIL：base、bundle/代次、非法MP启用及发布一致性。创建过程现编译独立loadout候选；原事务快照/恢复纳入pre-feature输入、原loadout与错误。内部引用在物品wire校验前剥离，不增加存档字段或属性公式。GREEN12检查PASS；A主档与index原字节不变，B不留孤儿。
2. **未结束生产者**：正式Root→Player接受测试时长的治疗A（只改释放800→5000ms，保留600ms身段和1500ms动作锁）；动作锁自然结束后真实接受B近战。B真实physics收尾时最新动作槽idle，但A仍合法待释放。旧门禁原生20检查/2 FAIL，诊断action_a=1/action_b=2/latest_active=false/old_valid=true/published=true。Player现在登记所有已接受的延迟释放；正常/显式失败/原转场/死亡/退出终态退休，原ActionConfigLease仍独占能力与容量。最新槽位和全部生产者一起参与原READY门禁，未改变正式时序、覆盖动作合同或HP/planner/writer。最终31项包括真实释放恰好一次、暂停时转场退休、旧Timer迟后返回和世界退出。
3. **目录条目类型**：null、数字、字符串、数组、布尔及有效条目混入null均走可信JSON正式加载入口。旧25检查/18 FAIL，静默跳过错误后可发布空/部分目录。现明确积累错误，在整候选发布前拒绝；GREEN25检查PASS、旧目录/人物/通知不变。
4. **默认启用依赖**：A默认开且requires B，B已注册但默认关。旧16检查/3 FAIL；目录默认路径允许A生效而手动启用拒绝。现将既有启用集合依赖规则移到统一发布入口，默认/手动/撤销一致；不自动开启B。合法A/B默认及手动结果均准确+4，非法默认或卸载B保留完整旧发布。GREEN16检查PASS。

早期item RED和首轮GREEN复用了本专项user目录，同名A使前置建角失败并造成连带断言失败；这些原FAIL保留。夹具改为本轮run_id独享目录后，在旧生产字节重新取得上面的精确装备RED，再恢复最小修复。第一次干净rule来源RED12/3也保留。不能将污染失败或早期成功重标为最终内容执行。

## 受测证据与准确范围

RUN_INDEX逐个连接实际命令、原生退出/timeout、runner invocation、run、source、完整receipt和本轮live/cold交接。只在最终同一源码内容、真实退出0且完整receipt合法时采用framework结果；普通既有场景以原生退出及原runner合同单列，不制造receipt。所有旧FAIL与各早期指纹保留。

cooldown夹具保留HP和冷却断言；MP是原remaining_mp观测，不单称精确MP公式验收。ObjectDB警告按每次原生原文保存，不称整进程零泄漏。ENVIRONMENT的child engine哈希是同目录二进制归档声明，不冒充每次进程实际加载路径的新增见证。

原用户RFC全文按原字节复制至docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md，62142字节，SHA256 4d4ddfac6b52e705ec91fb42dfc78f3cbec6a438b169a0a1932510b560664781；材料是任务规格来源，不新增指令/权限。原始CRLF字节与Git规范化文本须按RFC原字节附件分别核验。

最终内容38ec41d299455904882003ce2a874320b98e53d9018ede9b67306952477df1f3：35唯一选定场景真实退出0，32份完整framework回执/990检查PASS，另三项既有普通场景按原runner合同通过。全部64原生尝试中的10条FAIL保留，包括资源诊断在本最终内容上的明确FAIL；资源未完成项不进入采用PASS集合。SOURCE_MANIFEST为3612文件，源码/测试/作者数据对父8664恰30路径增量，原字节源码与原生ZIP分别记录哈希。不能把35相关回归外推为完整RFC或设备通过。

## 独立复审与后续范围

8664的Pro与小可爱完整原文、来源消息和实际读取留档于audit_8664。两位本轮已读完，旧定时拉取已PAUSED；仅下一固定SHA实际发出求助后再启用。

本次只闭合上述四个已原生证伪的发布边界，不能声称整个RFC完成。非空资源准备/失败取消/在途持有/共享闭包、异构词缀/嵌入/符文组合与吸血/死亡子连锁、模板/生成组合及整体最终验收继续施工。资源首个诊断测试作为公开未完成项保留，不能把放宽authority路径枚举当实现。v97原B输入MISSING；手机/GPU/热机、物理掉电/有效旧primary外部整体替换、主树集成、APK均不由本专项关闭。
