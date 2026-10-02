# 自然战斗、连续世界退出与恢复的有界验收

父提交 `93b75aef8d05ff6277b8495e63f1d8fb501c25ff`。Pro 已支持有界关闭父提交两条释放分支覆盖；原回复保存在 `PARENT_PRO_REVIEW_RECEIVED.md`。本增量继续原第三树施工，18 个源码/测试增量，生产改动仅 4 个文件。主树、第二树及真实用户存档未参与测试或修改。

受测内容 SHA256：`ddedfaffe7671f31c3d5b05ed446a2af1644f0265cde4f677dc54a6b3f8ae510`，3538 文件。引擎 4.7.stable.official.5b4e0cb0f，SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。完整原字节源码在 `FINAL_NATIVE_SOURCE.zip`，哈希见 `SCOPED_EVIDENCE.json`；另含两个既有辅助工具。Git 文本可能归一 CRLF/LF，原生 ZIP 和 manifest 保留真正受测字节。

## 生产生命周期改动与反例

1. `scripts/game_root.gd`：真实世界退出后，MonsterVisual 静态入口仍持有旧资源协调器。四轮自然移动/战斗/保存退出中，弱引用证明 streaming owner 每轮仍存活。现在只在全局入口仍等于本世界实例时解除引用；旧世界退出不能清除较新世界入口。退出顺序在子视觉注销之后，不增加资源所有者。
2. `scripts/ui_selection_dismiss_guard.gd`、`scripts/touch_scroll_support.gd`：旧世界控制节点已销毁，但根部服务的 WeakRef 容器等待后续输入才清理。无点击/拖动的真实退出循环约每轮积累 700 个对象。现在在节点移除事务结束后合并执行一次只清理空 weak target 的清扫；仍活着的移出/重挂节点保留注册。原输入路由、手势和显示数据不变。直接反例 15 检查有 7 个业务失败，最终专项及原触控回归通过。
3. `scripts/ui_runtime_layout_overrides.gd`：进程级 `_target_tokens` 字典逐世界留下 11 个已销毁目标 ID。布局申请代次改为属于该 Control 的内部 metadata；仍活着的控件重挂保留代次，销毁同时释放。真实布局应用的 21 检查中原有 3 个业务失败；最终通过。沿用原 Device Lab 的外部字段/动态子项保护、竞争申请回滚、正式背包面板 checkpoint 回滚断言，专用入口只运行这三个已有测试，不改它们的预期。
4. `scripts/game_root.gd`：退出/地图换代后的 300 秒及 3600 秒 SceneTreeTimer 仍由 SceneTree 留到原期限。原生聚焦反例对象数 2125→2127→2129→2131。保留活跃世界原 SceneTreeTimer 时钟；退出或换代先撤销这些 wakeup 的所有权，再将已撤销 timer 的剩余时间设为零以便下一轮回收。迟到回调必须成功消费仍属于自己的记录后才能走原 spawn。最终同一热基线各轮 2125，无提前刷怪；世界重挂后旧回调不能抢新 wakeup，原 Boss 离图/回图期限和刷怪规则通过。

没有新增 HP、规划、存档或刷怪权威，没有 TTL/LRU 清 receipt，没有改怪物数量、伤害周期、移动碰撞、地图人工数据或布局数值。新增 `_hc_layout_application_token` 仅为内部运行时 metadata；没有新增物品/技能/怪物实体 ID。

## 自然战斗与恢复范围

`natural_effect_lifecycle_test` 在启动前隔离 APPDATA、test_mode=false 的正式账号和原地图上执行。原地图 94 个怪物保持实际 AI；另以真实工厂建立 30 个移动目标，初始 HP1500。测试声明初始 Player HP100000、MP5000、魔法180，之后不逐帧补血/回蓝。经真实装备/技能/规则三种来源资格、编译和默认 OFF 模块启用路径，实际移动输入和技能请求进入原冷却/起手/几何/票据/单一伤害权威；没有直接构造伤害 batch 或冻结命中目标。

最终 14 次接受施法，峰值 90 状态，899 次实际周期投递；效果净伤害8985，不把最后目标剩余 HP 小于10的结算强算为完整10。30 测试怪及4个原地图怪均死亡，独立唯一死亡信号按 canonical 经验逐项合计512，正式死亡任务数量相同、经验准确，完整保存及独立冷启动仍512。实际消费最大迟到733333us，严格小于既有1000000us周期；死亡/持久化/资源/受管receipt/容量预留最终排空。死亡队列峰值16、持久化峰值2，**不是30个死亡任务同时积压的证明**。

完整有界 raw 帧样本及独立 nearest-rank 重算在 `SCOPED_EVIDENCE.json`：P50/P95/P99/max 为5770/16383/20794/33488us。队列 oldest age 与 runnable service age 分列保留；它们不能替代逐次消费迟到。阶段 trace 标注 before final save，最终以完整 receipt、runner、source/engine 和 native exit 共同判定。这里报告真实测量，没有凭本次观测另立全游戏或设备帧时间 SLA。

`natural_effect_recovery_cycles_test` 同进程连续4轮各30目标、正常移动和施法，每轮4秒后在效果仍活跃时通过正式退出/保存链退休世界，再正式读取角色。只拦截最终视觉场景导航，不替换 HP/AI/planner/保存。所有 Root/effect/world/clock/streaming 弱引用释放、容器和预算 owner 排空、UI dead weak refs为0；ObjectDB 为3953/3957/3957/3957，资源均935，orphans为0。

这是四次活跃世界退休，**不是四轮全部击杀**。静态分配约919.58/919.76/919.79/920.07MB，包含测试累计回执/观测以及最多64项的既有地图上下文缓存；并未因 ObjectDB 稳定而声称总字节不增长或无限时长内存有界。中途怀疑地图对象缓存造成每轮+1的解释被反例否定；探索性扣除缓存后的统计也失败，最终恢复严格 ObjectDB 原门禁并修复实际 timer 所有权。原失败和探索记录全部保留。

## journal 小覆盖及最终同源码回归

两项先前已采纳的测试补强无生产 journal 变更：直接提交缓存的原成功 `old_quote`（不先重报价）应 `stale_item_quote`，无新 job/writer/物品/文件变化；另分别移除本夹具拥有的 primary，走实际缺失-v2/缺失-v3 主档恢复。保留损坏 primary 和 temp open 注入，不把它们外推为全故障矩阵。同进程99检查及独立 seed/cold/restart均通过。

最终同一源码26个唯一原生场景 PASS，其中18个 framework场景591项完整检查，另8个既有 assert 场景单列，不虚增591。实际执行29次，其中3次失败保留：同进程 journal测试和seed在同一账户重建固定角色名导致seed失败，后续cold/restart依本轮producer门禁拒绝。给seed/cold/restart链单独的启动前隔离APPDATA后3项通过，生产和测试字节均未改变。`FINAL_ACCEPTED_ROWS.json` 逐行指定采用哪次PASS，不把失败组合runner的FAIL改为PASS。

回归覆盖自然live/cold、四轮世界恢复、UI注册退休、world wakeup、journal、原组合live/cold、合法退出live/cold、活跃profile所有权、消费容器回收、三项释放边界、streaming注册与换代、输入先后顺序和触控、Boss回图及respawn政策。普通场景30秒，三项自然重场景60秒；执行命令/场景/run/invocation/receipt/handoff/native exit和前后指纹在 `RUN_INDEX.json` 各条记录与日志包。

全 Device Lab 测试 `device_lab_runtime_test` 在本次及四个生产文件回放93b75ae基线时，都在既有旧角色写入夹具第231行失败；保存了对照及恢复当前四文件精确字节的哈希。它仍是基线FAIL，布局子范围PASS不能冒充整个Device Lab通过。其他阶段 fixture路径错误、布局反例解析错误、错误地只预计30测试怪450经验等均保留原始FAIL，不当作生产缺陷。某些自然/组合/退出/Boss进程仍有既有ObjectDB关闭警告，零引擎错误不等于无警告；本轮没有宣称整机零泄漏。

## 保留的工作与证据边界

本轮为PC headless自然战斗和生命周期的有界增量。第二树R3 V4 18条件中的14项尾部退步继续处理；不能拿本轮绝对帧数覆盖其可比性能FAIL。Android/GPU/真机 NOT_RUN，精确v97故障角色B输入 MISSING，原故障因果修复 NOT_RUN。物理强杀/掉电、外部有效旧primary整体替换、任意长时运行不在这份证明范围。主树集成、APK构建/签名/发布/安装未执行。

每个阶段保留其指纹、完整日志与回执；只提供最终全部原字节源码，不声称每个早期试验都有完整源码ZIP。下一步继续R3同场景性能比较，审计等待不暂停独立工作。
