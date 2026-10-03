# 非法人物候选、绑定枚举与结算容量交接

父审查版本：f765d249f7f6128028ce882b13643302b8d75b75。第三树仍使用原施工HEAD加受测文件字节；本增量不切换主树、第二树或真实index，不接触真实存档。独立报告全文及来源身份保存在audit_f765。报告是远端审查材料，不等同于审计者原生复跑。

## 原生反例与最小修复

1. **非法人物候选、正常写盘**：隔离目录先通过正式创建/保存链建立一级法师A，基础MP18；启用既有默认关闭测试贡献MP−16，A结果MP2。无磁盘失败注入，正式创建一级战士B。旧路径实际报告成功、写入B，留下B身份/base MP15、A旧computed MP2和非空feature_errors；17检查中8项FAIL。现唯一原属性公式返回显式成功状态，创建调用者在基础候选和初始装备候选两处检查；失败在写B/index前恢复原事务并报告character_stats_rejected。创建不发布中间默认职业，事务恢复同步纳入base_stats。GREEN17检查PASS，包括旧身份/装备/两类属性输入、原bundle对象和编译代次、整专属目录文件字节及索引不变。原生负例覆盖的是基础候选MP范围失败；初始装备后同一检查分支此轮仅静态核对，不冒称另一个原生负例。

2. **绑定kind错误**：可信JSON目录包含未知、缺失、null、数值、数组及合法/非法混合绑定。旧字符串/缺失/null/混合输入静默发布；数值与数组还在比较时产生脚本类型错误。原31检查/18FAIL均保留，类型错误不冒充普通业务拒绝。现先检查String类型和合法枚举，错误明确积累并拒绝整个目录，不跳过后发布部分来源。GREEN31检查PASS，旧catalog/authority/bindings/enabled、stats/bundle/代次及通知保持，原生无脚本错误。

3. **HP已提交、批次尚未转移时玩家死亡**：复用真实Root/Player近战、非空点燃票据、正式映射目标及既有吸血路径。测试仅固定已有吸血数值，资源通知中的一次受控观察者在确认真实目标HP已提交后调用正式take_damage致死；不直接造Batch、写HP或塞队列，不改变Root世界身份。精确RED19检查/7FAIL，容量从producing消失，Root后续提交拒绝，点燃没有安装。现reservation成功claim将同步生产交给DamageBatch；取消旧动作只回收未claim预留，不能抢走producing或queued所有权。Root原封口/空批次/拒绝/提交尾部显式结束批次生产；批次最后引用释放也收尾，随后消费者独占queued容量。GREEN19检查PASS：基础HP一次、实际事实一次、源死亡后until_expired效果四次真实周期投递、无回滚/重复，最终队列/预留/去重回执排空。

4. **已claim批次的最后所有者**：补独立所有权反例，原11检查/1FAIL；生产者关闭不得抢已claim批次的容量，旧票据不得第二次claim。GREEN11检查PASS；销毁最后一个未封口批次，即使旧已关闭票据仍被持有也立即释放容量；未claim取消仍即时，重复关闭不重开。不是让所有producing票据永久保留，不使用TTL/LRU或清空历史去重。

早期死亡夹具直接以Dictionary点语法添加新吸血键，生成StringName键，ActionConfigLease的既有plain-graph门禁正确拒绝；这些三次夹具/诊断失败原样保留。现夹具用明确String键，取得真实非空票据，再形成上述精确HP后死亡RED。没有放宽plain-graph门禁。回归首次命令写错既有空扩展场景路径，被wrapper启动前拒绝；该非原生失败另列，改正实际路径后运行，不削弱tracked-path门禁。

## 同内容回归与证据

RUN_INDEX逐项关联原生退出、timeout、命令、source/invocation/run、完整receipt与本轮live/cold handoff；SOURCE_DELTA限定父版本到本次20条生产/测试/作者数据路径。SOURCE_MANIFEST、TESTED_SOURCE.zip与NATIVE_EVIDENCE.zip保存原字节；SCOPED_EVIDENCE提供最终采用场景/检查数和哈希。原FAIL不改标签，早期成功不冒称最终内容执行。

最终受测内容73fdf0241ad837ab781efc802d73195917cc6076b219cdfe5a12312e7d5b96fc：四个直接专项、16项相关回归及六个组合/合法退出/自然效果live与独立cold场景均原生退出0，同内容且无测试期间改源；保留本轮所有原生失败以及wrapper启动前失败。66000事实退休是既有结构测试，不外推本次Android或总内存耐久。ObjectDB原警告按每次日志保留；引擎child哈希只是文件声明，不新增逐进程映射见证。

## 后续施工边界

资源诊断仍在本最终内容上明确FAIL，不进入采用PASS集合；真实非空资源准备/失败取消/共享与在途持有继续施工。异构来源组合、职业预览派生缓存、模板/生成式组合与整体验收没有由本增量关闭。原v97 B输入MISSING、Android/GPU/热机、物理掉电及外部有效旧primary整体替换、主树接入/APK按各自证据推进。此轮不增加玩法、正式词缀数值或第二HP/planner/writer。
