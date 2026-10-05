# 可信功能包接入、原子人物发布与生命周期门禁

本轮继续原第三树 RFC P2/P3/P6 范围，父审查提交为 3a1b781b4b10ddb918f6abca955ae4c33985f2e0。实际施工仍为 codex/pluggable-framework-v2 HEAD 5d9ceb0121980ca9636d9d1cc2e19982949fbf63 加固定内容，不声称审查提交的干净 checkout 已原生运行。主树 v97、第二树、真实存档及真实 index 均保留。

## 本轮实际改动

- ContentLayers 从项目打包目录 res://assets/data/features 的可信 JSON 注册新增包。路径拒绝 user://、脚本、穿越、反斜线、非法片段；处理器仍由现有内置白名单控制，不承诺同进程任意 MOD 沙箱。
- 原先只校验定义 schema，先换目录/启用集，再由 PlayerState 拒绝实际属性范围的流程，改为先使用现有属性汇总产生的 pre-feature 快照编译完整人物候选。有效 loadout、目录、绑定、启用集合和人物结果在无 yield/回调区间一起提升；发布观察者不可重入启停或 reload。
- loadout 候选沿用旧不可变 bundle 和编译代次，失败不会改变现有效人物、compile_count 或 feature_errors。技能数值也通过现有 effective-definition 校验，不新增属性公式、技能 planner、HP 或存档 writer。
- 目录替换在无附着世界或旧世界退出屏障完成后进行。startup 包不在活世界启用；已注册 world_ready 包的来源启用要求原 Root 输入 READY、所有登记 owner 合格、未暂停及 Player 无未结束动作。停用撤后续资格，已接受 lease 的伤害事实和既有状态仍按原策略兑现。世界登记也保护没有持久化 profile ID 的世界；queued-free 不提前释放边界。

## 原生反例与失败分类

1. 新包接入：旧 API 正常业务失败回执 3项/1 FAIL；实现后20项 PASS，补四个目录负例后28项 PASS。身份、重复、缺文件等失败均保留原目录/人物。
2. 原子发布：旧实现14项/8 FAIL，包含实际人物范围、默认启用目录及通知重入。修复后原14项 PASS；额外技能负耗蓝和重入 reload 覆盖后19项 PASS。拒绝候选不放出目录变化通知。
3. 生命周期：原27项/12 FAIL，具体失败清单保留，不把后续连带失败都算成独立根因。最终30项覆盖实际空 profile 世界、启动包、输入锁、暂停、额外未准备 owner、真实技能 accepted lease/非空容量票据、停用后单次释放/HP/派生事实和 queued-free 收尾。
4. 首个 lifecycle GREEN 尝试仍1 FAIL：夹具在 accept 前断言预留票据；现有协议在实际 accept 时领取。将同一非空票据断言放在真实 accept 后，另保留 capture 非空断言，不更改生产准入或弱化票据要求。
5. 旧 cooldown 夹具34项/11 FAIL：关闭人物 physics 后，上一刀一直处于 active；且退出前重载目录。仅让真实 actor physics 在原冷却测量后完成动作，并在世界退休后恢复目录。全部原伤害/MP/冷却断言保留，增加动作终态和释放不重复检查，现41项 PASS。
6. journal live/cold 初次各1检查 FAIL：默认隔离 APPDATA 根不带测试要求的子目录。按正式 wrapper 支持的 HARDCORE_AUDIT_RUNTIME_APPDATA 设置新 .godot/runtime_appdata/publication_journal_<nonce>，同源码两项39检查 PASS。原失败不改标签；cold 必须匹配本轮成功 producer/handoff，不接受历史成功产物。

## 证据与验证范围

本增量最终源码内容身份为 4bbd5374b510b64aa24cc2b8c875c98f1d16e1b81e6826f52e12328bdd2b31a3。直接组原生结果15 PASS/2 FAIL，隔离条件修正后二项 PASS：最终采用17唯一直接场景、439项完整检查，二项失败仍留在原组。自然组合/退出 live/cold、自然移动战斗及冷启动六项按相同内容独立通过，最终采用23唯一场景、682项完整检查。全部12次 runner 包含58次原生尝试，7个失败原样保留；不把每次 runner 或早期字节都标为通过。

源码原字节、全部 source hash、Godot4.7 console/child身份、实际命令、原生退出、run/invocation/source/handoff、完整 receipt 及每次失败原始记录归档后由机器索引关联；NATIVE_EVIDENCE.zip 保留原字节，Git 文本规范化映射单独记录。

原 ObjectDB 8 warning 留存，不用场景 PASS 宣称无限内存零增长。现有 R3/critical、空预算类别、lease/journal/UI、五纹理并发和非空 generation 是各自旧指纹成果，不重新标成此增量全跑。

## 独立审查重点与仍未完成范围

请 Pro 与小可爱分别核验：pre-feature 快照确由唯一属性权威产生；失败候选和通知重入是否保留完整原装配；所有 owner、无 profile、暂停、起手与退出阶段的门禁是否闭合；此前合法 accepted 释放及经济 writer 是否保持；world_ready 注册包的同步来源事务与目录重载边界表述是否准确。

本轮不关闭整个框架。真实非空功能包资源闭包/租约、词缀/嵌入/符文贡献及吸血/死亡子连锁等异构组合、标准新增功能模板/组合生成式覆盖仍按原计划继续。原 v97 B 输入 MISSING、Android/GPU/热机、完整物理掉电/外部有效旧主档替换分别开放。没有主树合入或 APK/设备通过；源码闭合后再构建并校验同包同签名升级 APK，交用户指定小可爱安卓环境检测。
