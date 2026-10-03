f765d249 独立二审完整结果，供施工对话直接读取

固定版本：f765d249f7f6128028ce882b13643302b8d75b75
父版本：8664ef242edcd8bfeca3f599e6478636c0a75ca3

结论：上轮四个具体反例的修复与对应证据成立，可以保留这些成果。但人物创建还存在一条“候选已经非法，却继续正常保存成功”的相邻 P1 路径；目录绑定还有一处未知 kind 静默通过。因此暂不能把人物候选/可信目录发布整体标为闭合

本次新增反例是固定源码静态推导，未由我运行 Godot，不得标为新原生 RED

1. 已关闭的四个原问题

- 强制保存失败回滚：创建使用独立 candidate_copy；快照/恢复包含 _feature_base_stats、原 loadout 和 feature_errors；原 bundle、compile_count 不再被临时人物编译污染。内部 RefCounted 在 item wire 校验前剥离
- 延迟 A 被最新 B 动作遮蔽：每个 accepted producer 在回调前登记；READY 同时检查最新槽及全部未退休 producer。A 不再因 B 动作结束而被漏掉
- 非 Dictionary module 条目：明确累积错误、拒绝整候选，没有继续发布空或部分目录
- 默认启用依赖：统一发布入口检查 requires，覆盖默认/手动启用及撤销，不会暗中开启依赖 B

对应原生记录核对为：创建 12项/4FAIL→12PASS；非法 module 25项/18FAIL→25PASS；默认依赖 16项/3FAIL→16PASS；延迟 producer 20项/2FAIL→最终31PASS。前三项 RED 与最终测试文件字节一致；延迟测试保留原20条检查文字并扩展覆盖

2. P1：人物候选非法时，正常创建路径仍可能落盘并返回成功

这个反例直接反转现有 creation_rollback 夹具，不需要新功能数据，也不注入磁盘失败：
- 创建1级法师 A，基础 max_mp=18
- 使用已有 creation_rollback_registry，仅启用已有 hc.creation_rollback_probe，对 max_mp 加−16；法师有效 MP2，启用合法
- 正常创建1级战士 B，I/O 正常
- 战士候选实际为15−16=−1，recalculate_stats 多次检测到非法值，却只 void return，保留旧 computed_stats
- create_character 没有检查人物候选失败，继续生成装备、save_game、更新主档/index，最终返回空字符串表示成功

我核对了初始装备，中间检查挡不住这个反例：木剑、布衣都是等级1要求，没有MP要求；重量7/5未超过相应上限。保存载荷不含派生 stats/bundle/feature_errors，也没有相应候选失败门禁

最终可能形成 B 的身份/装备、A 的旧 MP2属性与旧来源 bundle、B 的 pre-feature MP15及非空 feature_errors，同时创建接口宣告成功

这是当前创建范围内的既有调用者遗漏，不是 candidate_copy 新引入的问题，也不是另列待办的职业切换/临时 buff 回滚。强制写失败已修复，不代表“重算候选自身失败”已覆盖

最小整改：创建调用者必须显式取得并检查候选结果；任何非法候选都应在写入 B 或更新 index 前恢复旧事务并拒绝。不要只看磁盘是否保存成功，也不要让 stale computed_stats 成为失败后的可用候选

新增正式入口测试：上述法师→战士、正常 I/O；要求返回失败，旧身份、装备、cache、bundle、编译代次、错误状态与磁盘字节保持，没有 B 主档或 index 孤儿

[数值拒绝与 void 返回](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/player_state.gd#L3724-L3734)
[创建与成功返回](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/player_state.gd#L9375-L9406)
[保存路径](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/player_state.gd#L6421-L6526)

3. P2：未知 binding.kind 仍可静默发布

最小反例：复制现有 publication_registry，模块与其他字段保持合法，只将绑定 kind 从 rule 改成 unknown

loader 在 kind 分支直接 continue，没有追加错误；之后仍把原始 bindings 交给发布。模块启用后，contribution_provider 的 match 没有未知类型错误分支，可能返回成功但没有来源贡献

因此 malformed module 已拒绝，malformed binding 仍能替换旧目录。这也是原有相邻 fail-open 缺口，不否定已修的六类 module 条目

最小整改：未知或缺失 kind 明确追加错误，提交前拒绝整个 registry；补单个未知 kind、合法/非法混合绑定，检查旧目录、人物装配、代次与通知保持。不要静默剔除坏绑定后部分发布

[绑定解析与发布](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/layers/runtime/content_layer_registry.gd#L133-L163)
[来源收集](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/features/adapters/contribution_provider.gd#L14-L58)

4. accepted producer 生命周期修复的准确范围

原 A→B 门禁问题可关闭。实际31项记录里，A=1、B=2、latest_active=false、old_valid=true 时 published=false；正常退休、暂停转场、旧Timer返回和退出都有覆盖

动作序号在 Player 生命周期内不重置；转场/死亡/退出推进 epoch，旧Timer不能在新生命周期释放，也不会误删较新动作。Root planner、HP writer、begin_release/begin_plan 和 reservation 能力实现未改

“恰好一次”应表述为所有权退休效果恰好一次，而不是 finish_producer 函数绝不会再被调用。旧Timer可能再次调用收尾，但 reservation.close 的 _closed 和 runtime 存在性检查使其幂等。正式死亡和 invalid-lease 分支本轮是源码核验，不冒充31项场景逐个原生覆盖

另有一项条件性重入测试建议，不列为已证实的现有游戏阻断：若 resources_changed 的同步观察者在已经开始的 ticketed release 内触发转场，新批量退休可能提前关闭 producing reservation；Root 随后继续基础伤害但提交派生 batch 被拒绝。我找到的实际监听者仅做 HUD 更新，没有找到这种生产转场监听者，原 RFC 也未明确允许任意 mid-commit 转场。因此目前只列协议边界待测，不以假设宣布现有玩法损坏

在将来宣称任意重入安全之前，可区分等待中的 producer 与正在同步提交的 release：取消前者，后者保留所有权/发布屏障直到明确终态，并补一个正式资源信号转场反例；不要放宽 begin_release 或改变合法动作覆盖

[producer 退休](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/player.gd#L1450-L1468)
[READY 门禁](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/scripts/player_state.gd#L9310-L9332)

5. 证据与原始字节核验

- 18个 invocation、64次场景尝试，10条原FAIL保持
- 最终采用35唯一场景：32份完整framework回执共990项PASS，另3项普通场景按原runner合同正常退出
- 全部59份历史framework回执，包括失败，逐项与命令、超时、场景、run/invocation/source、检查编号和结果、退出观察及handoff哈希对应，无不一致
- 四条live/cold链都关联本轮同源同invocation成功producer及精确回执，不借用历史成功
- resource diagnostic 在最终指纹仍为3项检查/1FAIL，明确不在采用集合。它仍在施工，不是本报告关闭项

NATIVE_EVIDENCE：7000627字节，365成员全部长度/哈希符合清单并对应远端Git文件；TESTED_SOURCE：15153524字节，3612源码清单成员全部匹配，重算内容指纹为：
38ec41d299455904882003ce2a874320b98e53d9018ede9b67306952477df1f3

父到最终差量正好是声明的30路径。原31组既有采用场景/脚本、3个runner/回执/指纹工具及cooldown断言保持不变

原RFC已实际取得，归档62142字节，SHA256为4d4ddfac6b52e705ec91fb42dfc78f3cbec6a438b169a0a1932510b560664781。此前“原文未提供”的材料缺口可关闭；取得原文不等于整个RFC已经验收

[证据索引](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/docs/review/framework_publication_followup_20261004/RUN_INDEX.json)
[源差量](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/docs/review/framework_publication_followup_20261004/SOURCE_DELTA.json)
[原RFC](https://github.com/watermarkpp/HardCore/blob/f765d249f7f6128028ce882b13643302b8d75b75/docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md)

6. 下一步与验收限制

优先补第2节“非法创建候选、正常保存”的原生RED和最小拒绝路径，再补第3节未知绑定校验。保留原四项修复及通过记录，无需把它们重做一遍

本次只有远端源码/归档检查和独立重算，没有重新执行Godot，也未在本地重新测量主树/第二树保护状态。child引擎哈希仍是文件声明，不是逐进程已加载二进制见证；cooldown MP仍是观测；ObjectDB原警告不支持零泄漏结论

资源、异构组合、职业切换临时恢复等未完成施工继续分别跟踪。原B缺失、Android/GPU/热机、掉电、主树/APK等边界不因本轮990项PASS而关闭
