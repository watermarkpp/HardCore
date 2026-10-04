# 死亡子连锁：原 RFC Task4 的串行接入

原批准来源为 RFC v2 §9—11、§17、§20、§23 和 FRAMEWORK_PUBLICATION_CLOSURE_PLAN Task4；父受测固定提交37612de204c42fe3b4fd6a89137e90f3449bc0c2。沿用第三树、唯一主控及原HP/技能planner/writer，不增加正式掉落、技能收费或平衡。此文件细化已经授权的架构实现，不修改玩法上限。

## 当前生产断点

damage_batch在Enemy现有HP提交后冻结actual_loss和target_survived_commit，当前只接direct；periodic只经CombatRuntime回传HP receipt。EffectRuntime只识别ApplyStatus和ModifyResource，父票据在基础batch消费完后退休。编译器只接受direct的damage_committed。现状不能声称已支持点燃→死亡爆炸→再点燃。

## 接入不变量

1. 内容声明有限的子动作代次和每个可信处理器的最大子动作扇出，编译时验证；运行时执行该声明。未知、无终止条件或零时间自激配置在发布/接受前拒绝。有限验证原语默认关闭，正式参数仍不投放。
2. 每次查询仍在该子动作实际释放时使用既有空间索引和精确几何，不预取/冻结目标、不新增任意30目标上限。世界合法receiver上界来自既有factory/summon证明；动态出生、换代及历史状态和并发预留分别验证。
3. 完整成本包含根命中、全部潜在子命中、状态、receipt和异步持有。仅“根动作有票”不能代替后续承诺。容量不足必须在扣资源/冷却/HP前拒绝；不得回滚已经提交HP。
4. RequestChildAction携带root/parent release及fact身份、明确代次、历史credit和死亡提交时的地图位置值。实际子攻击仍由唯一SkillRuntimeRouter合法端口计划，最终HP由现有CombatRuntime/Enemy提交。纯handler不写HP、不发信号递归进入Root。
5. 基础释放完成后，受控队列按广度和稳定次序处理子命令；周期致死也冻结事实。保留既有多目标death-pending保护，死亡碰撞仍立即消失，死亡/奖励只提交一次。
6. 根票据的退休扩展到所有生产者、子消费者、状态和异步引用都终态之后；旧identity不能重新进入。换世界、生命代次失效和重复回调均有反例；不使用TTL/LRU或简单清空。

## 串行实施与证据

先实现纯的容量上界证明并原生证伪：按N个合法receiver、L个绑定、S个持久绑定、B个每事实子动作和G个明确子代次，保守上界为F=N×sum((N×B)^g,g=0..G)、receipt=L×F、state=S×F；child action=B×N×sum((N×B)^g,g=0..G-1)。N=0和B=0必须正确；计算不得对巨大G迭代，也不得整数溢出误接受。容量数字由现有runtime调用方提供，不新增一份全局容量权威。多来源同槽刷新可能让实际成本更低，初版不能拿这种可能性削减承诺。

这项纯证明先作为Compiler的独立派生成本工具，不启用新handler、不给动作票据、也不自称已在Root保证兑现。随后接入可信child描述、唯一planner端口和原生事实；再将完整预留生命周期接入runtime，最后跑点燃/致死/再点燃、真实几何变化、并发历史状态、RNG/原死亡集合、暂停/卸装/换图/换代/重复提交与容量反例。每一步RED→最小实现→GREEN，生产完整接入前不发布半成品玩法。

首项测试须能发现漏算下一代、漏乘独立来源或状态、巨大代次溢出/挂死、非法类型和缺少容量字段。literal期望独立手算；只用测试owned APPDATA和正式wrapper。其后最终同源码回归、固定SHA、原Pro/小可爱双审计；本文件不代表已完成。


2026-10-04 Root子动作续施工：实际同Root规划/查询/HP入口、完整finite immediate链预留、累计工作与串行驻留分离、封口消费分支receipt退休已实施。真实85槽、接受后声明槽换代/晚进入范围、负地图46/2FAIL→46PASS、伪造parent22/4FAIL→合法后续各一次均原生验证。最终同9efaa6ab内容38唯一场景、33receipt1113检查PASS；56原生51PASS/5FAIL保留。详情docs/review/framework_child_execution_20261004及CHILD_EXECUTION_WORKLOG_20261004.md。周期致死→子动作→再点燃、A/B刷新credit与根容量所有权、子资源表现/模板/生成式与自然P6R3/APK仍开放，不关闭Task4整体。


2026-10-04 活链容量/单消费者续施工：父1f6两份完整独立报告已读。正式35检查7FAIL原生证伪后，同35项通过，并补未封口兄弟分支/合法空命中/真实转移。逐事实连续记账、同runtime同步pump重入返回0、Root传播转移与owner_retired均已实施；最终同572286d5c4b82eeae9e9cb270b98c136e264ad47565f051b474d137ae0981ea3内容42唯一场景/1379检查，见CHILD_CHAIN_ADMISSION_WORKLOG_20261004.md及docs/review/framework_child_chain_admission_20261004。周期链有效unsupported_trigger_chain与child_state_capacity RED均保留，临时开放端口已恢复父字节，不发布不完整功能。Task3/4/5、自然P6R3、APK仍未完成。


2026-10-04 周期回调与出生槽检查点：父2b4 Pro完整报告已实际读取；小可爱该请求平台终止FAIL/报告MISSING，不宣称双通过。正式周期HP回调clear原32检查4FAIL→32PASS；同base slot重复出生原9/2FAIL→9PASS，补死亡离group的身体窗口11/1FAIL→11PASS。最终同d94ee4b474239cd21ccdc07080ea713db712cbb69122708b3e3527b164ebe0ba内容45场景/1420检查，见PERIODIC_RETIREMENT_WORKLOG_20261004.md及docs/review/framework_periodic_retirement_20261004。地图formal respawn audit FAIL和父Root单文件对照同FAIL保留，未改authoring。N*S池/完整periodic child、Task3/4/5/P6/设备/APK均继续，不关闭整体目标。
