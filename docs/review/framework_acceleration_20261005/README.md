# 资源退休、票据身份与持续自然战斗集中增量

2026-10-05（Asia/Shanghai）。第三树单主控的限定施工与验收记录。父提交为 `5c34cd5acdd0e7d98ff46965479555a6a708c4c4`；本次受测施工 HEAD 仍为 `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` 的保护现场，不声称是在审查提交的干净 checkout 执行。

最终受测内容指纹：`7d048ed9b2d83053b8c24b7ea7bff3d27f3e2b9805c1046d1eae853611794242`，3855 个明确运行文件。正式引擎 `4.7.stable.official.5b4e0cb0f`；console 文件 SHA-256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。receipt 版本字符串是 `4.7-stable (official)`，保留其与 manifest 的字面差异，不把格式相等当作引擎身份。

## 本轮生产差异

相对父提交共 81 个 clean blob 差异：生产脚本 5、测试文件 69、default-off 验证数据 6、已有 runner 1。原字节和 Git clean blob 分别登记，不把 CRLF/LF 归一化称为原字节一致。完整差异清单见 [SOURCE_DELTA.json](SOURCE_DELTA.json)。

1. `scripts/game_root.gd`：先收取已接纳纹理结果，再拒绝 queued-free 世界的新工作；世界最终退出时只回收其已接纳的有界原生请求；FAILED 状态需一次正式 get 释放原生 token，INVALID 不额外 get；每帧新准入量同时受剩余 inflight 容量约束，保持原容量 4、每帧 2。
2. `scripts/character_select.gd`：A→B→A 回到已有原路径时只更换观察 generation，不再次领取 native 请求；非 OK 新请求 fail-closed，不借用其他所有者的请求；FAILED 正式取回一次后从所有权字典移除，最终退出同样处理 FAILED。
3. `effect_reservation.gd` / `effect_runtime.gd`：签发时捕获真实票据对象 ID。伪造同 sequence 对象不能 claim 或 close 正式生产者；析构使用签发时 ID，不在零引用时调用自身身份方法。真实空子批次可能在 domain call 内退休最后 root，成功计数归属不变的 delivery generation，不遗漏完成，也不跨 clear generation 计数。
4. `scripts/hud.gd`：保留已冻结、此前核验的 opaque Loading 阶段主线程面板 Script 预热候选，两个 Script 之间 yield；background/live 路径仍异步。其限定诊断与当前世界回归不能替代完整 GPU/设备评价。当前角色大厅的 ObjectDB 警告仍开放，不因该候选直接宣布所有线程脚本资源退休完成。

保持单一 HP、技能 planner、存档 writer。没有修改主树、第二树、用户真实存档、冻结地图或协调器，没有新增玩法上限、截断 AOE、修改原周期、回滚已提交 HP 或发布 APK。

## 最终同字节原生回归

[RUN_INDEX.json](RUN_INDEX.json)逐次保存实际命令、scene、run/invocation、source、native/wrapper exit、隔离 APPDATA、完整 receipt 哈希、成功 producer handoff 与原始失败。五个最终批次的 before/after 3855 文件映射相同，归档前后再次全量复算与当前原字节一致。

| 最终批次 | 正常场景 | 完整 checks | 结果 |
|---|---:|---:|---|
| acceleration_bundle_final | 33 | 880 | PASS |
| acceleration_release_critical_final | 9 | 202 | PASS |
| sustained_resource_mp_cap_accounting（live/cold） | 2 | 342 | PASS |
| sustained_chain_mp_cap_accounting（live/cold） | 2 | 343 | PASS |
| 合计 | 46 | 1767 | PASS |

所有 46 场原生退出 0、无超时、完整连续检查 ID、最终 receipt PASS、成功 handoff 的 receipt 哈希一致。本轮没有改 runner 的原生错误允许名单。

另有两个最终同源故障注入场景：Root 14 checks、大厅 24 checks，业务断言全部成立，native exit 0。每场仅两条精确归属本轮 `user://` 文件的加载错误；取回后原 token 状态 0、fixture 额外 cleanup get 0，随后同路径正式新请求成功。**官方 runner 仍是 0 PASS / 2 FAIL / exit 1**，没有成功 producer；不得供 cold 重用。主控分类见 [mechanical/ROOT_OWNED_NEGATIVE_CLASSIFICATION.json](mechanical/ROOT_OWNED_NEGATIVE_CLASSIFICATION.json)，完整候选和原日志一并保存。

唯一正常最终 stderr 警告为 `character_launch_resource_lifecycle_test` 的 `46 ObjectDB instances were leaked at exit`。其他 45 场正常最终 stderr 无 ERROR/WARNING。本证据不能写成无泄漏或无限耐久通过。

额外关键场景包含真实带非空票据的烈火近战、冷却配置租约、动作租约与生产配置、接受前准入、队列消费回收、周期伤害合法退出及绑定本轮 producer 的独立 cold，避免只用冰咆哮证明所有入口。

## 真实音频与退出补证

`feature_cue_native_finish_reuse_test` 52 项：实际 AudioStreamPlayer 自然 finished，服务完成事件和池释放；随后复用同 pool，并证明旧 handle 的 stop 不影响新音频。没有人为发 finished 或把正常完成替成 stop。

`feature_cue_active_world_exit_test` 20 项：已接受逻辑、Cue、真实音频和 lease 仍活动时，直接正式 Root 退出；清理不是先由 fixture 调用 runtime.clear。相关 owner、队列、状态、receipt、声音和资源引用均在限定等待后退休。与已有同步 attach 重入、音频替代、池复用共同构成本轮覆盖，不外推 GPU 像素。

## 持续自然输入范围

两个 live 均使用同一个真实世界连续两轮，每轮 30 个真实、非重叠、AI 活跃 receiver，30 个指定 ActorRef 各 3 个合法 ignition source，同时 90 状态。实际输入每 250ms 尝试、每 1200ms 移动；每轮 35000ms 截止、原 1 秒周期、完成量与实际消费迟到 `<1sec` 门槛不变。保存、奖励和资源闭包使用生产链；是受控生产 API 输入，不称 OS/触摸端到端。

按用户 B 授权仅将这两个 live 外层窗口置 90 秒，同 invocation 的 cold 保持 30 秒。没有重置第二轮 HP/MP/冷却/模拟钟。初始 20 个登记的 `hc.service_item.000663` 通过正式 receive 与 baseline writer 入包，随后通过正式快捷槽输入使用延迟恢复药水：第二轮满 180 缺口时的首次正常剂量或低 MP 触发；每次扣实际库存，Player 正式 tick 恢复，不能把直接退款算供给。

实际观察区分了 profile 同步裁剪与技能耗蓝：首次真实 42 MP 起手后 MP 4958→1333，裁剪 3625 单独登记；不把初始 5000 上限变更计作技能消费。每轮资源信号仍严格对账，实际 HP 提交与 profile cap 同样分别归集，观察不增加 RNG、伤害、输入或调度权威。

| 本轮 live | 第一轮耗时 | 第二轮耗时 | 实际 ticks | 真实消费最大迟到 | 药水使用 |
|---|---:|---:|---:|---:|---:|
| resource | 20835ms | 29476ms | 888 / 922 | 100000us | 2 |
| chain | 17578ms | 21255ms | 772 / 720 | 450000us | 1 |

两轮各 30 死亡，状态/实际效果/死亡收益/指定五纹理新任务/持久化及退出终止。chain 的 40 次成功子请求含 2 次 periodic parent；不把全量 request 数冒称 periodic 数。

这些是两次有限 PC headless 持续运行，**不是性能优化比较或完整 P6/R3 验收**。旧 resource 35 秒期限不足、旧 chain 真实受伤/供给/periodic-parent 覆盖失败均保留在阶段原始记录中，不因本轮成功改标签。不得挑随机通过结果宣称期限始终可靠。

## 原始阶段证据与退休警告定位范围

归档共有 81 个原生尝试：最终 48（46 正常 + 2 负例），历史阶段 33；14 个原 runner FAIL 完整保留。阶段各自 source 指纹单列，不能合并成最终字节通过。两场旧非 framework UI 阶段没有完整 framework receipt，明确 MISSING，不加入 checks 总数。

票据身份另附独立的 [TICKET_IDENTITY_RED_GREEN.json](TICKET_IDENTITY_RED_GREEN.json) / [原始 ZIP](TICKET_IDENTITY_RED_GREEN.zip)：旧实现81项14FAIL，新实现同81项0FAIL，并保存新实现同批另外4个Cue回归。补充包为6次阶段尝试、1个原 runner FAIL；与上述本体合计87次、15个原FAIL，最终同源仍严格是46正常/1767项，不把这6个旧指纹阶段加入最终通过数。主控追加归档时没有重跑或重标记原失败。

同 `source` 内每个 native_logs 与 raw 副本哈希相同。trace 缺少 invocation 字段时只通过 run/source 关联，缺失字段保持 MISSING；最终 receipt/runner/handoff 三方的完整 invocation 关联另行核验。冷启动期望由本轮成功 producer 及 native handoff 绑定，不自认旧成功文件有效。

Git 中的文本镜像可经既有换行过滤器转为 LF；核对原始日志字节时以 ZIP member 与对应 native manifest 为准，不以远端文本的换行差异声称原生记录相同或失配。

冷线程加载完整 main PackedScene，即使正式 request/get/null/等待后，阶段仍可出现 161 个零引用 ObjectDB 实例；主线程预载 Root Script 的对照没有同类警告。三个空 Node/原生 RefCounted/WeakRef 小夹具均未复现该警告。这个差异尚未确定具体生产或引擎原因，不能通过随意清缓存、提前全量同步加载或吞警告关闭。另三个 custom GDScript Ref 对照只在 outputs 起草，没有纳入本提交/受测源。

## 稳定 ID 与未闭合项

新增仅为 default-off 验证模块/机制 ID：`hc.validation.natural_periodic_chain` / `.death`、`hc.validation.periodic_cadence_probe` / `.ignite`。后者 version 1/2 用同一登记 ID 验证配置替换；没有新生产物品或职业/技能身份，服务药水 ID 已存在。名称只作展示。

- 1 微秒扩展周期的四次交付数量已实测正确，逐次迟到无法保证 `<1us`；接受前拒绝超出已验证服务能力或允许有时限的异步积压，仍需用户产品决定。本轮没有自动选规则。
- 冷线程 GDScript 退出 ObjectDB 警告与偶发纹理诊断仍开放。
- 旧 V4 完整格性能/DeviceLab 基线 FAIL、完整自然 P6/R3 和 Android/GPU/热机仍分别开放；不能以本 46 专项覆盖。
- 原 v97 B 故障的原始输入 MISSING；新角色成功不能证明原故障因果已闭。
- 冻结地图中 respawn 政策问题、物理掉电、有效旧 primary 外部整体替换、主树接入分别按原边界处理。
- 小可爱新安卓安装信息正在核对确切线程/执行器与 ABI；历史容器缺入口不能否定另一执行器，用户确认安装也不替代本轮安装/渲染证据。尚无新 APK，DEVICE TEST: NOT_RUN。

## 可复核归档

- [SOURCE_MANIFEST.json](SOURCE_MANIFEST.json)：3855 原始文件 SHA-256。
- [TESTED_SOURCE.zip](TESTED_SOURCE.zip)：对应原字节及用户 RFC，15459256 bytes，SHA-256 `3116784ef1a80751a000f0791b295625b00e4b6d8a34d011da41294f2d856541`。
- [NATIVE_EVIDENCE.zip](NATIVE_EVIDENCE.zip)：所有明确阶段/最终原始 native、receipt、runner 与 trace，11995339 bytes，SHA-256 `25099535a5c357460407227b2fccf37a49be3c044dadd0bdde96c89c9c8b64cd`。
- [NATIVE_MANIFEST.json](NATIVE_MANIFEST.json)：逐个文件大小和哈希；[SCOPED_EVIDENCE.json](SCOPED_EVIDENCE.json)限定统计。
- 机械助手结果均为 CANDIDATE_EVIDENCE。GLM29 实际 `/api/coding/v3/responses` 请求耗时 175.688sec、usage 9237 input/12000 output/21237 total，HTTP200 但 complete=false/incomplete，主控不采纳为完整清单、不自动重试。Luna 清单经主控回到全部本机原始文件复核；不由模型标签批准工程。

真实第三树 index 前后 SHA-256 均为 `df5a01dd0d87c14620e0021d70c25a830eb2cc37aa7b012eeb14ee1f2c58c5fb`。发布使用独立临时 index；实际树现场、主树 v97 与第二树不切换、不覆盖。
