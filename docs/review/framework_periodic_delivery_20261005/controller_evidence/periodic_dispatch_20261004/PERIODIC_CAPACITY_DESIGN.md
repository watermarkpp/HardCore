# 周期连锁容量设计检查点（早期提案与后续状态分开）

2026-10-04早期提案：当时正式Compiler仍拒绝periodic death订阅，以下记录保留原检查点范围。后续已实施同quantum驻留、独立periodic分支、真实Root一代二代及首次死亡状态退休，最终同678e2ba32a5d9f8e57ff12b37d8810f03131960f63a0f47a35f25ca1562bc41e内容30场景／1130检查通过；具体原始证据见docs/source176_r3/PERIODIC_DISPATCH_WORKLOG_20261004.md。极端合法period变化／累计工作时效、atomic量子和完整自然P6R3仍开放；本提案不能代替原生证据或整体验收。

## 已获得的边界证据

原票据类型/上下文反例：28检查13失败；加入根上下文只读断言后31检查16失败。最小修复后34检查通过，额外3检查只在合法领取成功后验证重复领取拒绝。真实Root/状态归还/纯容量三项原138检查组中的其他104检查仍通过。

实际刷新诊断：原1秒周期、4秒duration/max_ticks=4。第0秒接受A（raw10）；不消费tick，测试模拟钟推进到100秒，第100秒接受弱刷新B（raw1）。同一原生实际HP服务兑现due1..100，再兑现101..104，共104次，HP5000-10-1-104*10=3949，历史credit仍A。17检查通过；最大实际迟到99000000us原样报告。这是受控积压诊断，不是自然时效通过。不能用两个max_ticks=4之和8作为这个原合同的总投递上界。

## 下一实施候选与必须证明的条件

1. 原状态拥有不可变的初始root/parent lineage、bindings和资源租约；刷新仍保持原credit/raw strongest/next_due语义，接受过的刷新root共同持有状态，期限和period由现有状态更新规则决定。新接受刷新必须留下有限工作期限的授权；不新增逐tick无界历史数组，不拿固定max_ticks截断既有积压。
2. 每次周期HP前由同一runtime发出仅该tick能领取的periodic分支；身份含状态身份、原parent及scheduled_due。依托刚完成的票据source_class/完整上下文核验。不得沿用根direct ID，也不得用child身份吞掉原合法回调。
3. 优先考察在同一_tick_one预算quantum内冻结、交付和退休一个周期事实，复用DamageBatch/真实Combat periodic-chain HP/同一_deliver_fact。periodic订阅只允许既有DeathBurst只读事实→排队子请求；Ignite不得由periodic触发，不能递归Root或另建队列/HP/planner。若改为普通FIFO排队，必须另外证明多来源和旧批次积压的逐root驻留槽，不能直接假设2N足够。
4. 同步tick事实借用接受前原根持有的一个fact/receipt驻留槽；在HP前核验借用资格，工作结束后归还。HP回调clear、状态替换、目标死亡/queued-free、source撤销和历史credit都必须有原生反例，已经提交的事实与尚未完成分支不能被_stop过早退休。
5. 子工作上界仍需证明“一个direct/child事实里的同一目标life只能产生一次真实首次死亡”；即时fatal与该事实创建的多个状态后来fatal互斥。实际HP冻结hp_before>0、hp_after0、ActorRef life退休可提供证明基础，因此周期次数本身不应盲乘子树前沿。但必须以真实periodic fatal→Root子释放→子命中点燃、复活/换代和多个来源反例核验；未证明前不开放Compiler。
6. work horizon更新、极端合法周期变化、服务延迟、最坏atomic quantum仍需实际边界与同指纹回归。该候选不声称已经闭合累计工作、整体P6或Android。

主控负责以上证明和修改。GLM只处理原始源码/日志机械归集，不决定该方案。完成关联生产路径、容量及刷新边界后，与2c585状态归还增量集中固定SHA双审计，不为这份检查点另起审计轮次。
