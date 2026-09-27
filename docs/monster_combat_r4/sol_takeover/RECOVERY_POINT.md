# 精确续接点（R4 未完成）

## 当前身份与正在执行

2026-09-27，本地主树 `codex/integration`，HEAD `6cd4ed215ba689b9cf1f920693df87604bde2f41`。唯一主控，无工程子代理，无远端推送/APK/安装/清树。

当前工具运行会话 **28280**：`tools/run_monster_r4_t6_pairs.ps1`。固定 R3 BASE `1381d2838a3736f4a06699dd24a8cf4a10714950` 在 `C:/Users/Administrator/.codex/worktrees/r4-fixed-baseline/HardCore`。BASE独立导入已完成；只复制了同一 T6测试gd/tscn与runner，生产源码未改。主树/BASE共享引擎和只读原素材联接，各自独立缓存和user data。

它串行跑小怪/大怪+双宠/火墙AOE，10/20/30，每条件2次BASE A/A再3对AB/BA/AB，共72轮，每轮600真实物理采样。原始结果持续保存 `evidence/t6_pairs/<label>/load.json` 与runner目录，runs.json精确列已完成轮。**不要在该会话结束前提交改HEAD或改T6相关源码，不要运行其他Godot**（runner全局子进程检查会影响别树实例）。用write_stdin session_id=28280查新输出；失败时保留失败目录，诊断而不是继续伪PASS。

## 本轮已经闭合（避免重做）

- 5cbebaef：ID79实际600ms投递在禁战、控制、死亡时取消却漏观察终态。原真实反例cancel_source_red，修原取消点只读记录，cancel_final 3/3。同时_hc_life先is_instance_valid再类型检查。
- 0231b9d8：T6真正工作量门与每回调原始采样。初始ID18只看HC starts错误、无实际掉落节点及actor HP被profile同步夹回等夹具问题已定位；正式固定小怪/群死ID24、大怪ID76。固定PlayerState.computed_stats的测试HP/MP容量，保留所有生产攻击、公式与时钟。30怪AOE最终151死亡/替补，掉落节点实建，600帧，PASS。
- 6cd4ed21：正式固定串行T6协议和来源身份。不把engine窗口monitor做P95；inclusive enemy CPU为回调间隔内累计，若一个回调跨多个physics tick不能叫单physics帧。
- 所有之前观察/归属、20自然起手、D3、MP/盾/毒/受击、异步生命周期、时间0、正式生成44条、召唤半径链均见TASK_LEDGER/TEST_RESULTS及原始evidence。183/241特殊实体用途仍NOT_RUN，时间加载修复不证明自爆/飞火用途。

## 未提交的精确工作

- TASK_LEDGER.md最新进度改动。
- `tools/summarize_monster_r4_t6.py`：标准库分析脚本，已对中间矩阵运行。PASS表示72轮数据完整，不是自动性能验收；有回归flag必须根因分析。
- `tests/hc_monster_combat_r4/r3_common_natural_probe.gd/.tscn`：共用真正record消费边界子类观察工具，**NOT_RUN、尚未stage**。gd可能被ignore，需git add -f。自然攻击不改冷却/钟、不用last_release。只对照actual super同步边界，零HP明确UNCLASSIFIED、不伪造miss。CAND full身份/反例验证另由已注册自然/归属场景承担。子类工厂路径局限在JSON中明确；正式GameRoot工厂另有CAND自然证据。
- `evidence/protection/pre_final_hash_check.json`：13,611保护文件无缺失、六个范围内差异；4,152接管前存档备份全匹配。runtime测试存档async_probe.json一个变化，备份保持。用户AGENTS等dirty文件无变化。
- `evidence/expected_critical_paths.json`：当前正式critical实际523场景，由runner的suite声明独立计算。新取消场景已正式注册，性能/对照探针不凑正确性数量。

## 后续顺序

1. 完成72轮T6，运行summarize脚本、判断AA噪声与三对结果/实际工作量。小怪10最早部分时段有保护哈希扫描，安静窗口复核此条件；不要把单一均值/瞬时最大值称无退化。
2. common natural探针stage后复制**相同字节**到BASE tests并stage；使用current runner 60秒（明确重自然场景），ID24/238/239（必要76），两树相同种子和观察工具，保存原始JSON/runner/源码及测试SHA。不要把R3缺少full ledger称完整终态PASS，不回填旧production observer。
3. 固定R3原25历史场景复核原始错误签名；CAND最终同SHA25项跑一次，逐断言裁定。
4. 11个继承候选tscn的EOF空行仍使累计源码diff --check FAIL，精确修这11文件文本尾部（原始历史证据Markdown不改）。修改SOURCE前先做完固定配对；不要在测试运行中改依赖。
5. 稳定源码/测试/正式注册后本地提交，最终full critical 523实际集合、timeout/exit/log门。发现失败逐项根因修复，不能引用旧PASS。
6. managed同SHA干净检出，独立导入/userdata，对本轮新增正确性和直接相关关键路径执行。禁止同时另树Godot/导入，禁止复制脏缓存/未跟踪脚本。
7. 最终保护哈希、完整差异/状态/check、当前远端fetch身份；PERFORMANCE_RESULTS/FINAL_REVIEW/证据索引/SHA256、最终提交。远端integration/APK/设备/删树仍未授权。

## 保护与现场

外部备份 `D:/HardCoreAudit/r4-takeover-20260927-123453`，备份refs和原dirty/UID/saves都保留；不要重读全仓或重做merge。主树用户AGENTS及列出的untracked原材料保留，不stage。BASE12自动import translation已有精确HEAD字节恢复和generated备份，BASE大量自动uid未删。

## 最新续接覆盖（15:28）

当前运行会话58722：tools/run_monster_r4_common_natural_pairs.ps1，输出common_natural_final。已PASS 24-BASE20自然起手，正在24-CAND；每ID BASE/CAND/CAND_ON验证20实际settle及同种子OFF/ON，最后两次24射程外追击独立1起手。不改源攻击间隔/钟。common_natural_pairs旧证据24-CAND打印PASS却60秒timeout，保留FAIL；旧夹具seed在add_child之前被_ready.randomize覆写，已移到ready以后并固定原有facing/audio接口；旧脚本保存在probe_source，不能当有效同种子对照。

初T6 t6_pairs72轮和quiet10八轮全部实际runnerPASS，但同种子合同FAIL：玩家/召唤物及出生朝向/audio RNG漏固定。原始流水不改，t6_pairs/DATASET_REVIEW.md解释。T6探针v2已补global、player、durability、pet、enemyfacing/audio的确定输入；通过SceneTree.node_added在原工厂_ready前调用既有seed接口，并保存输入表、校验hook。主树和BASE字节相同；v2尚NOT_RUN，不能拿初轮CPU差值作为性能验收。tools/run_monster_r4_t6_pairs.ps1新增v2输入门，未来输出独立t6_pairs_seeded_v2，需要整72轮重跑。当前HEAD仍6cd4ed21，新增/修改仅测试工具与文档，生产未变。

下一步：等58722完成；失败则保留修夹具/源码根因，不认中途marker。随后tools/run_monster_r4_radius_pairs.ps1（BASE真实旧15/21px RED、CAND16px/0.5GU GREEN）、v2 T6矩阵72轮、tools/run_monster_r4_historical_pairs.ps1原25BASE/CAND。不要同时开Godot，不在固定窗口内commit漂移HEAD。随后精确11tscn EOF修正、提交稳定测试/证据，再最终critical523与clean checkout等原后续顺序。

## 15:34进展

58722 common_natural_final已实际完成24、76、238各BASE/CAND/CAND_ON，共9次PASS；三ID逐20次HP/序号/间隔/RNG OFF-ON完全相等。正在239三次，然后24两次真实追击。新T6 probe已通过seed输入静态核对但尚未运行，不提前记PASS。头/生产仍6cd4ed21。

## 15:38实际闭环与新运行

common_natural_final完整14/14 PASS：四ID各BASE/CAND/CAND_ON20次实际结算，R3/CAND HP、敌我RNG、序号/间隔一致，CAND OFF/ON也逐行相等；24两树射程外追击均1起手、225次真实位置变动。summary.json已生成。旧common timeout/RNG错误仍原档FAIL。

r3_radius_pairs完成实际BASE RED（旧15/21px查询和snapshot）、CAND GREEN，same probe bytes，没有BASE生产回填。现在会话86014继续v2 T6全部72轮，目标t6_pairs_seeded_v2；首small10 BASE AA1真实PASS，seedhook门通过。该会话矩阵完成后自动summarize并跑historical_final_pairs原25BASE/CAND。不要并发Godot/做重哈希扫描/变更HEAD；生产仍6cd4ed21，T6及比较测试工具新增/dirty有明示身份。

## 15:49待运行最窄生命周期反例（不能忽略）

静态核对Enemy._exit_tree只清导航/索引，没有 pending伤害取消观察；源79真实600ms pending期间free/queue_free可能没有终态。新tests/hc_monster_combat_r4/source_destroyed_pending_test.gd/.tscn已写但NOT_RUN、未stage/未注册；禁止先当生产漏伤或直接改源码。等86014 T6+历史阶段结束后先stage精确新场景跑真实反例。如确实缺终态，真实销毁边界用NOTIFICATION_PREDELETE观察，仅记录原物理pending随Node销毁取消，不写HP/不改游戏Clock，不在_exit_tree提前取消（remove/reparent可能不是销毁）。需测free、queue_free以及短暂移出/再入对照避免重复终态；若生产新增_notification影响默认OFF通知热路径，最终源码需有性能补验证，不把6cd矩阵当最终新SHA无退化证明。该发现属于R4纯观察生命周期直接相关，不新开R5。

## 16:29恢复点

HEAD27009bcf已关闭实际来源销毁观察缺口：free/queue_free真实待投递RED→GREEN，短暂移出再入对照及五相关场景PASS。生产新PREDELETE只读通知分支，最终性能需重测。原25历史BASE0/25、CAND6cd25/25实际完成，assertion_review逐项裁定；资源全目录测试CAND依赖既有本地outputs审计manifest，不称源修复，不拷贝缓存到clean测试。loot_async报告目录缺失已测试fixture创建目录+文件打开断言，直接PASS，clean仍待执行。

T6v2原72完成但技能nativewall-time独立seed遗漏；v3修seed，三smokePASS仍test_mode绕过正式队列，不作最终perf。v4正式热态test_mode=false首BASE失败no_real_death_drop_work（真实死亡56但未初始化worldclock/save_failed）；原RAW保留。现在独立profile目录+真实save_game(false)初始化，BASEAoE10与CAND AoE10/双宠10实际PASS，CAND55roll/54commit/40nodes、失败队列0；每回调活怪10/600帧。新增gate拒绝任一FAILED terminal，最近两行gate只是静态新增，待最终矩阵执行。两树探针当前byte相同、只测试overlay没有BASE生产回填；v4保存每次canonicalseed，固定nativehash时间/测试profile输入，serial不改。主协议新seed和真实热态/profile/共享掉落装备catalog哈希门。

11tscn EOF已精确trim仅空行；源码diffcheck PASS。工作树另有未提交common自然probe14PASS、三个比較脚本、总结tools、大量原始证据/docs；用户AGENTS等原untracked留原。没有运行任何Godot，所有exec会话已结束。下一步：明确stage/commit稳定code/tests/tools与已闭合证据（.log被ignore，需-f精确本次evidence根，不丢raw）；先full critical524以捕捉可能SOURCE回归，再最终v4矩阵72（固定HEAD，quiet不重哈希/commit）、原R4直接clean checkout独立import/userdata；末尾保护hash/正式生成check/最终diff/台账/远端fetch。该顺序避免fullcritical源修复后再次使perf源码过期。仍未推远端integration、无APK/安装/删树。
