# Root 有限死亡子动作执行增量

父固定提交 `171bffbb69aa7d59b7f0ab30238e8032d67a6ad7`。第三树真实 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`；审查使用独立 index，不切换施工树。最终受测内容 `9efaa6abf58436350b65354856476d635059e6d28d26502dba2b92f3ecb5f404`，3733 源文件、17 增量。

## 实际改动与范围

1. 原 Root 安装同一 EffectRuntime 的子执行入口。它在规划前验证实际 ChildActionLease 实例与该分支票据，再经过唯一 SkillRuntimeRouter、既有 STRICT_V2 几何、实际释放时的空间查询和既有 Combat/Enemy HP 端口。纯 handler 不递归调用 Root；子动作不重扣 MP、不消费原 Root/Player RNG、不产生直接 STRUCK。
2. 默认关闭的可信验证包 `hc.validation.child_execution` 声明两代有限死亡子动作。原 33 玩家技能和默认 registry 保持。整链在 Player 接受前预留；保存累计工作承诺，同时区分串行驻留 facts/receipt 和完整广度队列。真实 85 槽世界的两代最坏累计事实 621435，fact/receipt 驻留各170、子命令预留7310。没有将目标冻结或截断为30，也没有调大既有容量。
3. 每个分支的 batch 封口、生产者票据关闭且消费者全部结束后，回收该分支 receipt；根持有者继续保留后续子队列和状态。旧分支不能重新铸造或进入。状态仍按保守累计成本预留，周期→死亡→再点燃链尚未闭合，不用本轮 immediate 结果替代。
4. 父 Pro/小可爱指出负地图 child 可走旧兼容路径：原生46检查/2 FAIL；只在 ChildActionLease 工厂拒绝负地图，最终46 PASS，原玩家未映射兼容路径保持。
5. 原生反例证明语法合法的伪造 parent fact 会抢走真正分支资格：22检查/4 FAIL；改用实际注册的 ChildActionLease 对象身份验证后，错误请求在规划、MP/RNG/HP 前拒绝，随后两次真正分支各完成一次。计划 hash 不用作授权依据。

## 原生回归及原始失败

最终直接组 `child_execution_final_direct_134059_228800` 30场景与世界组 `child_execution_final_world_134656_014362` 8场景全部退出0、无超时。两组受测文件映射相同且运行中稳定；33完整框架回执1113项检查，其余5普通场景按 runner/原生退出验证。各 producer/cold、隔离 APPDATA、run/invocation/native PID 的实际关联在 `FINAL_RUN_ASSOCIATION.json`。

`RUN_INDEX.json` 保留56次原生尝试：51 PASS、5 FAIL。解析失败无有效功能回执，不充作功能 RED；缺 Root 入口、将累计工作误当全部驻留造成实际85槽接受拒绝、负地图、伪造 parent 资格各原始 FAIL 均保留。不要抹除旧失败或把连带检查写成多个独立生产缺陷。

真实 Player windup 后，根仅命中首怪；后续受击怪不属于根命中。根接受后，已声明 factory 槽的旧实体销毁、正式 factory 创建新 life、新怪移动到第二波范围，实际子释放查询命中它，旧 ActorRef 无效且世界上界仍85。两代 HP、死亡碰撞即时消失、两次子释放、原 RNG/MP、根/分支/receipt 排空及旧票据拒绝均有门禁。

这个夹具使用真实 Root/Player/SceneTreeTimer/空间索引/planner/HP 的受控生产 API。它关闭 AI/自动 process，以手动 runtime pump 观察分波；不是 OS/UI 自然输入、自然复活计时、完整奖励、持续战斗或 Android 证明。动态出生证据限定于接受前已声明槽的换代，不扩大成任意新槽无限出生。

## 字节、身份和现场

`SOURCE_MANIFEST.json`、`SOURCE_DELTA.json`、`GIT_TESTED_SOURCE_MAP.json`、原字节 `TESTED_SOURCE.zip` 和 `NATIVE_EVIDENCE.zip` 可独立复算。引擎4.7 official版本及两exe SHA见 `SCOPED_EVIDENCE.json`。所有原始失败、命令、退出、完整回执和样本路径均归档。

`PROTECTION.json` 核对主树/第二树 HEAD/index/dirty清单、第三树观察到的真实index和冻结MonsterStreaming保持。历史index连续性仍 FAIL、原始历史备份 MISSING；观测备份仅保存已留存文件，不恢复或重建。主源媒体和原RFC字节保持。源码 diff-check PASS；原始日志/审计正文空白按 `DIFF_CHECK_BOUNDARY.json` 保留。

父171两份完整独立报告和来源身份在 `audit_parent_171bffbb`，它们不是本增量通过证明。本轮需要对新固定 SHA 再审。

## 继续施工

周期伤害致死→子动作→再点燃、两根来源刷新所有权/credit/预算、历史状态与并发逐目标容量、延迟/换世界/重复分支边界、防自激生成式组合、子资源表现消费、模板、完整自然P6/R3和设备仍开放。单个子动作全部目标为一个原子 quantum 的最坏服务成本尚未证明；不能用本轮功能 PASS 宣称完整预算验收。原v97 B输入 MISSING；APK NOT_RUN，尚未合入主树。
