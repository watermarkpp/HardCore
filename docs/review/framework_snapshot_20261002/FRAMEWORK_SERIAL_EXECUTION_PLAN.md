# 可插接框架串行施工计划

核验时间：2026-10-01；依据用户 RFC v2 与本地生产调用链。此文件是施工计划，全部框架实现目前 NOT_RUN，不能作为完成证据。唯一主控串行实施，不派发工程决策或 reviewer。原对话建议仅为待核验设计材料。

## 固定范围

保留主树 v97 现场和第二树 R3/反馈修复；创建新的第三树，固定第二树受测的真实 dirty/new 文件字节。第三树不继承缓存、用户数据或运行日志。P0—P6 全部属于本次源码目标；设备、GPU、APK、安装、发布分别记录，不以 PC headless 外推。

默认关闭点燃、数值词缀和测试宝石包。新增接口必须由现有生产消费者调用。禁止第二 planner、第二 HP/物品/存档权威、任意脚本加载、旧 RNG 消耗、旧公式重算顺序变化及范围外地图/数值修改。

## 按最小纵向闭环实施

| 顺序 | 所有者与生产入口 | 改动和不变量 | 必须先失败再通过的证据 |
|---|---|---|---|
| P0 | 新树镜像清单、既有 runner 与 R3 证据 | 固定源 HEAD/dirty 集合/内容 SHA/引擎；空扩展真实伤害、目标顺序、RNG、掉落和保存字节基线；主循环 epoch 实测 | 坏断言、零检查、source changed 均不可判 PASS；同一 process epoch 的多个 physics/deferred/process 入口可识别 |
| P1a | execution/frame_budget.gd，独立于 WorldContext | 单主循环共享余额；开放外层 scope 耗时立即计余额，嵌套扣账一次；scope 不跨 await；必要工作计费但不拒绝 | 三入口、多物理步、换世界、嵌套、诊断关闭、余额耗尽和模拟暂停 |
| P1b | path_scheduler.gd / path_search.gd | 保留现有 job、token、稳定优先级与请求替换；有界 frontier 重建游标，完成前不发布半堆；公平连续服务年龄不被目标更新清零 | 完整路径/稳定 tie-break 等价、取消和换图、续算最终终止、有积压时各 runnable 类获得小量子 |
| P1c | game_root._pump_enemy_death_work_queue / streaming.poll_once | 原死亡与显示队列阶段不变；共享预算限制可选量子，已就绪不可取消回执优先且计费；runtime ready-only 顺序和 prefetch 顺序各保留 | 同帧死亡/资源/路径竞争、奖励只一次、回执延迟与 oldest-age、旧 streaming 排序与生命周期 |
| P1d | json_persistence_job.stage_result / service.pump / PlayerState writer | worker 真完成才 join；正常帧 pending 不等待；完成回调不可重入下一 writer；大 JSON 的纯解析/候选部分留 worker，Node 验证留主线程；不拷贝两次完整结果 | finished flag 提前但 task 未结束时不阻塞、回调 submit 不抢先执行、暂停仍消费回执且不推进 buff、纯候选失败与身份失效 |
| P2a | ContentLayers → feature_catalog/compiler | 正式内容入口；可信内置能力/处理器映射；严格 schema、稳定 ID、依赖/冲突/权限/生命周期/成本/资源闭包；候选原子发布，失败保留旧目录 | 未知字段/算子/能力/ID、隐式覆盖、环、缺资源、超组合成本拒绝；默认关闭零热扫描 |
| P2b | ContributionProvider → LoadoutCompiler → PlayerState | 三类贡献按独立 source handle 撤销；递归冻结只允许 plain values；编译只在相关版本/有效资格变化；旧 EquipmentRules 为旧数值唯一计算器 | 两来源撤一仍有效；嵌套输入/getter 修改无效；10k 未激活定义每击检查数不增；纯耐久不编译，破损边界编译 |
| P2c | player 请求 → game_root preflight → SkillRuntimeRouter → contract → 已接受释放 | 单份 ActionConfigLease 覆盖目标、报价、公式、几何、时序和表现；接受前陈旧拒绝且零 MP/RNG/许可；接受后使用旧 lease，但目标/方向仍在原释放边界锁定 | 版本切换两侧、有效范围/MP/伤害全链一致、原技能差分；不存在第二 planner 或 eager fallback 读取 |
| P3a | CombatRuntime / EnemyActor 的实际 HP 提交点 | 事实在 sole HP write 后、信号/治疗/复活前生成，actual_loss 限 overkill；基础 AOE batch 完成才派生，稳定 BFS、跨批次去重、alive/life/world 重检 | overkill/零伤害/回调治疗/同步复活、多目标基础顺序、重复 receipt、嵌套 batch 不提前 flush、depth/cost 限制 |
| P3b | MechanicHandler → CommandWriter → EffectRuntime | 处理器仅产命令；独立确定性随机域；每效果一个有效 due 节点；保留刷新 phase、强度和最终 tick-before-expiry；ActorRef 与历史 credit 分离 | 100 基础 actual loss → 1/2/3/4 秒各 5；来源死亡/卸装持续至期；换图/目标换代拒旧；强弱刷新、暂停、免疫、无直接命中递归 |
| P3c | PresentationPort / 既有资源缓存和 VFX 入口 | cue start/refresh/stop 含 effect handle；资源闭包在准入处理；热路径同步加载为零；表现缺失按声明拒绝或降级，不改伤害时刻 | 冷/热/缺 VFX、失效 handle、停止/重入、零新增同步 I/O |
| P4 | 选定怪物 anti-stealth 既有消费者 | 一次移交一个副作用所有者；旧 bool 对外兼容视图委托唯一能力集合；只绕 invisibility 条件，不绕距离、WORLD、安全区、life 或 phase | 老新差分及组合；不存在 bool OR capability 双权威；默认装配结果保持旧资格 |
| P5a | 正式物品 codec → 保存/加载/备份/仓库/掉落/出售/锻造/提示消费者 | 新版本容器明确路由，base 仍由旧严格白名单验证；已生成词缀与原掉落规则不重洗；UNKNOWN 保留原字节并锁 aggregate write；空扩展保持旧保存版本/字节 | KNOWN_VALID / OPAQUE_UNSUPPORTED / INVALID 分界、未来版 terminal 不读旧备份覆盖、旧新 roundtrip 与未知载荷零变化 |
| P5b | ItemTransactionPort → 既有 ordered writer → durable delta apply | 角色/实例/相关版本/规则 revision 报价、局部预留、operation journal、确定一次结果；后台 writer 轮次重建当前快照，不把旧整档回写内存；回执跨世界仍消费，ambiguous commit 进入 recovery | 双击/同 operation 重试/重启、镶嵌和取出唯一所有权、药水/金币/仓库并发期间不丢变化、落盘失败/晚回执/备份恢复 |
| P6 | 发布边界、组合测试、性能/时效证据、功能模板 | 正式依赖/资源/成本组合门禁；30 目标×3 状态＝90 状态至少 360 ticks，末期与真实死亡/奖励/资源/持久化并发；队列最终排空，完成次数/顺序/延迟都验证 | 静态零违规、生成式组合、过载可见、匹配检查数、量子/oldest age、原始帧样本/慢帧；设备门槛 NOT_RUN 时不声称发布通过 |

## 逐阶段验证

每一步按静态/解析 → 因果窄测试 → 直接生产适配器 → 相关回归推进。常规 30 秒、重场景最多 60 秒；只暂存精确新增 tscn 以满足 runner 门禁。任何失败由同一主控分类、追溯、修复和复测。阶段结束自审 diff，不进行自动 commit/merge/push。

P0 的数值基线不能凭理论构造：复制完成后从空扩展的真实入口采集，再对加入框架后的相同 fixture 比较。必要业务次数、内容数量、碰撞、攻击节拍和 RNG 不得减少以获得性能结果。共享账本只证明所治理工作，不宣称整个引擎帧被硬限制。

最终交付逐项列出 R3 与用户追加修复、P0—P6、真实当前 Git/文件身份、stable IDs、新 schema、跨系统消费者、测试失败分类和设备边界。待完成项仍写 NOT_RUN，不能用某阶段 PASS 覆盖完整目标。
