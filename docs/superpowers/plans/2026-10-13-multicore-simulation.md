# HardCore 多核模拟 Implementation Plan

> Ruling 2026-10-14: user authorized delayed ordinary pursuit intent and choosing a shorter backend-supported period. This supersedes the earlier no-one-tick-delay constraint for ordinary pursuit only. Attack eligibility uses current positions and original windup; collisions, HP and save/warehouse correctness remain exact. LIVE S does not wait on ordinary planning or optional Main resource receipts. Final Pro decision/evidence: docs/review/multicore_v114_20261013/CURRENT_IMPL_20261014_1735.md.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. 本文是施工计划，不是已运行结果。主控分配独占文件并冻结受测源；共享生产文件只由集成者写入。

**Goal:** 把现有群怪真实重计算与战斗提交移出画面线程，用独立模拟所有者和有限批量工作池支持同负载流畅性及后续效果扩展。

**Architecture:** M负责输入、UI与呈现；常驻S拥有全部可变玩法状态、原序提交和时钟；W使用冻结数据并行数值工作。默认Godot 2D物理主循环依赖必须由明确引擎适配解除，不能用空PhysicsPort或普通SUB_THREAD冒充独立模拟。

**Tech Stack:** 固定Godot 4.7源码/模板，C++原生模块及薄GD桥，Godot Thread/WorkerThreadPool，现有PowerShell受控headless runner；ARM64与当前其他受支持ABI。

**Spec:** `docs/review/multicore_v114_20261013/ARCHITECTURE_DECISION.md`、`SOURCE_BOUND_DESIGN.md`、`PRO_ROUND2_DESIGN.md`、`PRO_PHYSICS_CLOSURE_FINAL.md`、`PRO_CLOCK_CLOSURE_FINAL.md`。四轮官方Pro原文已完整回读。用户已授权施工及115交付；候选独占分工推进，尚未运行的门保持NOT_RUN。

## Global Constraints

- 主树 `codex/integration`，HEAD `45170d0eaf4d2c642d4a03de392f64fa2b1e25bf`；113冻结树只读。实施前重新记录dirty、index、工作区哈希，保留当前APK和备份。
- `com.personal.mafaoffline`、原签名、旧schema和应用数据不变；仓库/装备/等级/技能/钱等全部存档字段保留。
- 不降怪数、碰撞、动作/攻击频率、服务完成量，不延迟一tick换并行、不改候选顺序或算法制造提升。
- 现有ActorRef/world/release/fact/credit/chain/death/drop合同沿用；一个会话一个所有者，M没有第二HP/Planner/保存提交。
- 无关dirty保留；引擎源码/SDK/工具下载不进Git，项目只保存自有module、最小patch和可复现构建脚本。
- 普通测试30秒，已知heavy60秒；只用runner、独立appdata和outputs/test_logs，不用GUI或真实用户数据。
- 原生/PC/Android/设备证据分列；设计或静态PASS不等于性能PASS。重复测试只因本次相关输入/依赖变化或失败修复。
- 原生batch与physics协议、同源token/patch有专项PASS，不能代替真实Godot引擎、S全会话、Android/设备。实际115尚未打包。施工与打包沿用户授权持续；未经验证的阶段不得标完整完成。

## Review Focus

1. 暂停中的已接受前摇/治疗、恢复后一次释放，physics/process/timer交错与新timer扣时边界。
2. 死亡/换图/复活/动态出生时旧life、旧world、投射物/历史credit/worker晚到，不允许重复事实。
3. durable成功后旧profile切换、拾取期间立即消耗、保存失败，不提前发奖或整快照覆盖新消耗。
4. 同bucket移动、新候选进入、首选方向阻挡消失与高冲突堵口，不能只修原获选方向。
5. 窗口/缓冲/事件容量耗尽、worker在跑时补算、相机所见状态与输入身份，不丢已接受输入、不混版本。

## 文件结构和独占边界

| 拟建单元 | 文件/现有消费者 | 独占责任 |
|---|---|---|
| 引擎构建与所有权钩子 | `engine_patches/godot-4.7/hardcore_simulation.patch`；`tools/build_hardcore_simulation_engine.ps1` | 固定source/build指纹、唯一physics推进及模板；不同时改玩法GD |
| 模拟所有者与时钟 | `native/hardcore_simulation/simulation_host.{h,cpp}`、`world_state.{h,cpp}`、`simulation_clock.{h,cpp}` | S、registry、时钟、原序控制、事务邮箱 |
| 物理适配 | `native/hardcore_simulation/physics_port.{h,cpp}`、`motion_adapter.{h,cpp}` | 同Godot后端、无Node的原motion/slide；仅S访问space |
| 数值工作 | `native/hardcore_simulation/combat_kernels.{h,cpp}`、`batch_executor.{h,cpp}` | 原数学/分块/readset/claim；不写HP或调用Node |
| 输入和表现 | `native/hardcore_simulation/presentation_bridge.{h,cpp}`；`scripts/layers/runtime/simulation/simulation_bridge.gd` | 原输入路由→命令、snapshot/events→原UI/视觉 |
| 原链迁移/集成 | player/enemy/summon/projectile/GameRoot/PlayerState、features contracts/runtime | 仅集成者改共享入口；关闭旧writer与Node consumer |
| 受控验证 | `tests/framework/multicore_*_20261013.{gd,tscn}`；`tools/run_godot_tests.ps1` | 真实source差分、竞态/事务、可选固定engine路径；不弱化runner门禁 |

引擎适配方式、模块注册及所需hook以最终物理封口报告为准。不得直接new第二singleton，不对默认server重复step。未满足该门前不批量修改player/enemy/GameRoot。

## Task 1: 引擎与物理边界可闭合

**Files:** 上表引擎/物理单元；新增 `tests/framework/multicore_physics_ownership_20261013.{gd,tscn}`；runner增加可选 `GodotExecutable` 绝对路径，默认引擎不变，保留用户数据/超时/tracked path/receipt门禁。

**Interfaces:** `PhysicsPort.begin_tick(TickContext)`、`test_motion(MotionInput)->MotionResult`、`query_ray(RayInput)->RayResult`、`end_tick(TickContext)`；唯一S step owner。无活动Node/DirectSpaceState指针跨M/S/W。

- [ ] 写失败验证：旧模式原step顺序；新模式M不step、不读space、不回调玩法Node；S每tick仅一次sync/flush/query/commit/end_sync/step；M延迟不停止S。
- [ ] 固定实际engine源码、模板、backend、精度和NDK，按最小patch构建Windows受控console及Android模板；不把vendor源码纳入项目。
- [ ] 保留Godot原motion/slide算法、layer/mask、16点footsole、margin0.35、max_slides6、零recovery、body/area ray flags和原pose更新相位；先串行适配，无并行server查询。
- [ ] runner专项：`tools/run_godot_tests.ps1 -GodotExecutable <固定custom-console> -TestPaths tests/framework/multicore_physics_ownership_20261013.tscn -TimeoutSeconds 30`。比较solver输出、事件次序、space读写与step count；失败止于此门。

**交付:** 引擎patch/build receipt、支持的API边界、solver差分和唯一owner证据；不是群怪性能通过。

## Task 2: 唯一world/actor身份和时钟所有者

**Files:** simulation_host/world_state/simulation_clock，现有ActorRef/world_context/time_domains的模式适配；新增 `multicore_identity_clock_20261013.{gd,tscn}`。

**Interfaces:** `start_world(WorldSeed,ClockPolicy)->StartReceipt`、`set_clock_policy(ClockPolicy)->PolicyReceipt`、`submit_command(CommandEnvelope)->EnqueueReceipt`、`request_quiesce(Reason)->QuiesceToken`。S registry使用唯一SimActorHandle ObjectID及既有ActorRef字典，M proxy ID不进玩法。

- [ ] 失败验证：完整64位身份、出生/死亡/复活的life、旧world拒绝、旧handle存活但dead资格失效、历史credit保留、相同actor slot顺序。
- [ ] 按封口时钟矩阵实现独立release、原physics/process/timer相位、pause/always receipt、到期timer一次释放、windup替代动作不取消已接受release、生命周期取消。
- [ ] 正式输入signal处生成带时间戳/顺序/token/相机身份命令；移动状态仅按采样区间合并，技能边沿不得丢。
- [ ] 同合法时钟/命令序列对照旧状态机；复用 `player_pause_movement_contract_20261009`、`action_configuration_production`、`paused_persistence_receipt` 相关回归。所有测试走runner30秒，相关源变更是复测理由。

## Task 3: 当前完整战斗闭环的串行原生参考

**Files:** world_state、combat_kernels原算法串行部分；共享GD入口由集成者改；新增 `multicore_combat_serial_20261013.{gd,tscn}`。

**Interfaces:** 内部 `step_tick(TickContext)`、`prepare_range/evaluate_range/repair_changed`，S唯一移动、动作、HP、死亡、资格、RNG和正式空间索引；W仍未启用。

- [ ] 写失败验证：玩家+地面/飞行怪+召唤+投射物、即时攻击/既有技能、障碍绕路、第一接触、死亡奖励/刷新、目标失效与同步回调的完整闭包。
- [ ] 迁移现有planner和canonical release消费者，不创建第二planner；逐项清除S路径的Node调用/instance_from_id/共享mutable resource。纯GD规则若保留，须S独占且不访问活动Node，配置装配后冻结。
- [ ] 保留原actor和candidate遍历、数学精度/分支/EPS/float转换/RNG调用次序；不fast-math、不新索引算法。
- [ ] 同输入/时钟序列比轨迹、碰撞、选取、伤害、死亡、release与credit facts。物理身份按life对应归一，不比较跨进程ObjectID常量。

**交付:** 真实重工作和真实提交运行于S的隔离世界闭环；当前完整会话未闭合前不对用户启用。不能靠禁用原技能完成切片。

## Task 4: 保存、奖励、背包和仓库的事务闭合

**Files:** SimulationHost事务邮箱；PlayerState原prepare/receipt和保存入口；新增 `multicore_persistence_receipt_20261013.{gd,tscn}`。

**Interfaces:** `persist(FrozenSave,SaveToken)->SaveReceipt`，receipt→S校验/commit→通知；不在M completion改live状态。

- [ ] 失败验证：磁盘/校验失败不奖励；旧profile durable成功不改当前profile；拾取promote并发消耗delta保留；暂停后receipt确认；重复receipt不重复death/loot。
- [ ] 移植原prepared plan/identity/revision、affected_before、watermarks和reservation，I/O只持不可变计划。原保存成功条件、仓库物品、等级技能金币全部保留。
- [ ] 相关回归：`mobile_save_upgrade_restart_test`、`character_identity_save_test`、`periodic_credit_safe_logout_test`、`paused_persistence_receipt_test`；不使用真实手机存档。

## Task 5: 批量工作池与原序局部修复

**Files:** combat_kernels/batch_executor；原索引增加唯一变更账本；新增 `multicore_batch_order_20261013.{gd,tscn}`。

**Interfaces:** `dispatch_ready(BatchTicket,Blocks,Deadline)`、`poll_published()->ReadyMask`、同一原子 `claim_block`、`retire_completed`。readset绑定world/life/pose/radius/qualification/action与原查询范围。

- [ ] 失败验证Review Focus 4/5：同bucket/new entrant/死亡/半径变化/首选放行、高冲突后缀、running块补算、取消未claim块、晚到结果与输入lease。
- [ ] 按真实独立工作范围拆块，worker共享领取ready块；复用Godot池，S非pool驻留任务。pool不执行HP/RNG/Node/server，也不在worker间等待。
- [ ] 从原首选候选恢复短路，受影响查询重走原Index顺序；密集区缩短投机窗口并用同一串行native后缀，不换玩法规则。
- [ ] 与Task 3串行参考差分，确认数值结果和事实完全一致；然后才做一次正式同负载大改动比较，保留113已存模拟输入，30/40、clustered/scattered和同期入战完成量均记录。

## Task 6: 原输入和批量呈现交接

**Files:** presentation_bridge/simulation_bridge、GameRoot/HUD/visual消费者；新增 `multicore_presentation_watermark_20261013.{gd,tscn}`。

**Interfaces:** `acquire_frame(min_tick)->FrameLease或NotReady`、`drain_events/ack_events/release_frame`；共同last_effect_ordinal水位，3槽owner状态。

- [ ] 失败验证：快照跳过不丢受击/死亡，慢M不覆写READING，换图event不能施到新世界，lease延迟退休，input view身份合法。
- [ ] 批算动画帧/方向/绘制参数/排序键，M只消费并提交；保持原等距遮挡、连续线技能几何和原反馈时序。
- [ ] min_tick提前定合同，状态过旧独立记录FAIL；不改min_tick、插值、少怪或假ready制造60fps。

## Task 7: 完整会话、切图和下一会话回退

**Files:** SimulationHost、GameRoot/PlayerState生命周期集成；新增 `multicore_session_transition_20261013.{gd,tscn}`。

- [ ] 失败验证：原释放取消/完成、暂停windup、待receipt、在途worker、M水位ack、profile切换/复活、旧world迟到输出；不能暂停后等timer自然完成而死锁。
- [ ] 逐项关闭全部当前玩法旧writer；每个迁移入口登记owner/phase/事实与纯表现，不只检查Enemy。
- [ ] 模式在完整会话加载前确定；故障不自动退档，完整保存退出后下一会话可用旧模式。原模式APK/source备份仍可随时重建。
- [ ] 跑必要相关critical回归一次，保留已知历史FAIL分类，不增加无依据重复测试。

## Task 8: 截止、Android与设备交付

**Files:** 正式本轮receipt和构建脚本，原export/signing链；必要诊断默认关闭。

- [ ] 同负载计M/S/W、实际完成量/延迟、原序修复、状态年龄、队列/内存、GPU/driver和持续热状态。原模型只作下界，不将线程数当p_effective。
- [ ] 确定有来源的REA-AN00有效并行度/块成本；所有必要路径按期，而非只主线程耗时下降。过载记FAIL，不自动降载/终止/清档。
- [ ] 固定最终source SHA、引擎/模板/ABI/NDK/精度；审diff和scoped检查后导出。核验包名、版本界面、versionCode、签名、内容SHA和16KB要求，保留覆盖安装兼容。
- [ ] Android/设备是独立验收；PC通过不提前报手机60fps。最终用户确认群怪操作/画面及保存均正常后才称升级完成。

## 计划自审与当前门

已映射规则、数据权威、输入/输出、claim、共同水位、durable事务和回退。物理源码/API已查明普通扩展缺口；Pro正给最终engine路线。physics/process timer最终释放交错尚未封口。因此本计划可以作为准备底稿，当前不能跳过Task 1启动批量玩法迁移。封口后补精确engine hook和时钟矩阵，重新审该两项即可，不重做已闭合研究或性能实验。
