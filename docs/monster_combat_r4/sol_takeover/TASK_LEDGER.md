# 原 R4 收口台账

| 项目 | 状态 | 当前证据 / 下一步 |
| --- | --- | --- |
| 现场、fetch、完整 SHA、备份、保护独有内容 | PASS | TAKEOVER.md / 外部 manifest |
| 完整候选本地集成 | PASS | 无源码冲突；候选仍未验收 |
| 观察器纯只读 / 测试故障注入隔离 | NOT_RUN | 已确认 record_hp_mutation 写 victim.current_hp，须行为反例再修 |
| 同步嵌套未知来源、异步冻结身份 | NOT_RUN | 当前 stack 无调用边界，复核真实应用入口 |
| 移除最近 release 推导投递身份 | NOT_RUN | enemy 三处从 _last_hc_release_record 取 parent；逐调用追踪 |
| 默认关闭无构造、开启有界、on/off 等价 | NOT_RUN | 当前 buffers 无界；actor 关闭仍调用记录函数 |
| 统一验收器完整身份 / 合法多目标 / 守恒 | NOT_RUN | 当前只按 release 前缀与 source instance 匹配，不足 |
| 真实减伤、miss/reject、替补、重复、全漏、嵌套、跨代 | NOT_RUN | 旧减伤在采样后设置，全漏判据不充分 |
| 24/76/238/239 至少 20 自然起手逐终态与24追击 | NOT_RUN | 先重现 76/239 18/20 并逐 release 裁定 |
| BASE/CAND 共用观察工具与原始 PASS/FAIL 身份 | NOT_RUN | R3 固定生产基线 1381d2838；不改旧生产 |
| D3 八向边界/横移/墙/受击/身体/暂停/迟绘 | NOT_RUN | 保留中心 1.5GU、16px/0.5GU/18px及召唤档 |
| 受击、休眠、死亡复活、毒、盾、召唤回归 | NOT_RUN | 定向后扩相关回归 |
| 两快照失败与历史直接相关失败、33/183/241来源 | NOT_RUN | 逐断言/权威消费者裁定，不能旧归属免责 |
| T6 有效负载 A/A 噪声、3 A/B、600热帧、冷首技能 | NOT_RUN | 真实负载与 counters 先固定，拒绝伪P95/P99 |
| 正式注册、实际执行集合、最终 full critical | NOT_RUN | 稳定后执行，timeout 不以 marker 覆盖 |
| 最终 SHA 干净检出与保护哈希 | NOT_RUN | 缓存/用户数据独立，保留未解决失败 |
| 最终审查、原始证据索引、SHA256、远端状态 | NOT_RUN | 未更新远端 integration，未打包 |

## 续接约束

当前最窄任务：给观察器与验收器写行为反例并复现，然后改生产伤害观察接线。不得先按奇偶第二攻击族补终态；金额不能判来源；不得调自然冷却/时钟/防重。此前 F03/F05 长帧优化仍未完成，保留 docs/performance_20260926/CONTINUE_HERE.md，R4 当前优先。
