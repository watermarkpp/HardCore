# HardCore 多核源码落地合同

基线：主树 `codex/integration` / `45170d0eaf4d2c642d4a03de392f64fa2b1e25bf`，114发布源 `10daa4d20e3be0dac1161f45b6be94e44a0bfc50`。更新2026-10-14。物理与时钟四轮官方Pro原文已完整回读；本文是施工合同，不能解释成全部接口已经存在。实际施工位于隔离候选 `multicore-v115`，主树生产和113备份保留。当前原生协议、批处理单元有专项证据，真实引擎及完整玩法迁移仍须各自验收。

## 1. 唯一所有者

| 当前真实入口 | 拟迁移后的唯一写者 | M保留的职责 |
|---|---|---|
| `player.gd:273` 玩家移动/动作/状态；`865`起HP/受击 | S的PlayerRecord及原序动作状态机 | 玩家视觉、相机、输入路由 |
| `enemy.gd:3103`物理推进；`7623`起伤害/死亡 | S的EnemyRecord；生命期、空间索引和死亡事务同一提交 | 只读怪物位置/动画、视觉子节点 |
| `summon_actor.gd:1601`起伤害/状态；召唤追击 | S的SummonRecord及现有主人credit | 召唤视觉 |
| `skill_projectile.gd:374`投射物分段和第一接触 | S的ProjectileRecord；原release/首接触顺序 | 飞行/爆炸表现 |
| `game_root.gd:13897`起死亡回调；`14891`起掉落/刷新 | S的有序死亡、奖励、掉落/刷新事实 | 创建/释放表现节点；节点完成不决定奖励事实 |
| `player_state.gd:3271`起装备/背包；`7115`起仓库 | S的原PlayerState兼容数据，原事务和revision | UI提命令并显示已确认版本 |
| `player_state.gd:6894`保存、`7261`加载、`8223`退出；`3107`死亡奖励receipt、`9281`拾取receipt | S一致快照，原存储服务原子持久化并返回receipt；S收到durable receipt后才提交相应live数据 | 选择/加载UI、I/O进度；不提前报保存成功、不在M回调改奖励/背包 |

原同步 gameplay callback 属于S闭包，不能先丢给M再等M答复。表现事件可以晚于事实消费；生命资格、死亡移除、奖励和拾取归属不能因此延后。现有技能规划、HP、空间索引和保存服务继续各只有一份权威。

`ActorRef`身份沿当前 `{world,runtime_id,life_generation}`。world沿 `contract_id/world_runtime_id/world_epoch/runtime_map_id/profile_id` 精确比较；生命、换图、profile切换均使旧结果失效。S使用Node-free registry，不能从S解引用Node。旧类型的 `resolve()->Node` 不能在S原样调用；迁移消费者改为registry的只读记录/提交接口，M展示适配保留Node解析。身份字典本身不改。release_id、fact_id、credit、chain、reservation和death/drop keys沿原合同。

新模式的动态出生不等待M创建表现Node：S创建唯一 `SimActorHandle`（不在SceneTree中的非RefCounted Object，由S人工lease拥有生命周期），其真实完整正ObjectID填入已有runtime_id；RefCounted ObjectID高位会使Variant int为负，不能直接用于现有正ID合同。领域core可以RefCounted，canonical身份handle不能借此扩schema、取绝对值、截高位或另造ID。M后来创建的proxy只绑定canonical身份，自身ObjectID不进入玩法索引/credit。world runtime owner同理采用独立逻辑owner，字典仍保持现有合同字段与一次epoch语义。旧模式保留原Node身份；会话启动选模式，不把新旧capture混在同一链里。同输入replay必须复用原接受身份及seed，身份参与RNG时不能事后归一消除差异。独立实例生命周期测试则不要求跨进程ObjectID常量相等。ObjectDB分配/析构的目标版本线程安全与Node消费者清零列为编译/源码门；不能采用伪造integer或等待M回写身份。

这是运行对象类型与resolver后端的显式适配，不能宣称内部语义完全未变。runtime_id保留完整64位和原Variant int表示，不当持久业务ID；S registry唯一判断life/alive/membership，handle存活不表示actor可受伤。所有 `instance_from_id(... ) as Node`、target_instance_id、release/death/credit/index消费者必须迁到同一resolver，不以新ObjectID排序替代原actor slot/候选顺序。handle最终释放需同时等W输入、receipt、历史credit、事件和M lease退休。当前官方 `object.cpp:2450-2491/2494-2524`证实ObjectDB add/remove有spin_lock，不等于任意Script/Node可跨线程；纯原生handle生命周期仍有构建验证门。

## 2. 模拟时钟与原相位

S按单调时钟绝对释放tick。ClockPolicy包含 `version/start_monotonic_usec/physics_step/time_scale/pause_epoch`；M仅在开始、暂停、设置变化和切图时更新策略，不逐帧授权。physics_step读取固定引擎/项目有效值，不为了迁移另选频率。

| 原时钟 | 迁移合同 |
|---|---|
| physics delta /动作timer | 使用原有效delta和原actor顺序，S唯一推进；不等同于规划300ms |
| Engine physics frame缓存/去重 | 映射S tick身份，缓存还需world/life/revision；M引擎frame不再代表模拟frame |
| simulation_usec累计 | 原累计后取整，暂停不推进；迁移 `time_domains.gd` 的main断言和Node owner依赖 |
| monotonic wall到期 | 保留原到期时间和服务相位，不把暂停全部冻结 |
| persistent Unix /离线恢复 | 沿原ledger与加载校验，不受worker或显示时间替代 |
| process-frame budget | `FrameBudget`继续管M呈现；S独立任务截止账本，不复用main-thread断言或render epoch |
| process里的输入/死亡/技能服务 | 分类迁移到原先因果相位；如果玩法真以render frame计数，先单列语义冲突，不机械改tick |

每tick固定physics阶段：接受到截止的命令 → 原physics到期状态/动作 → 需要的数值准备 → 原actor/候选顺序提交及依赖修复 → 原同步伤害/死亡事务 → 物理后端原相位收尾。具体物理sync/step位置以封口合同为准，不随手互换原回调与step次序。

Pro时钟封口（`PRO_CLOCK_CLOSURE_FINAL.md`，SHA256 `1a7a1f32912cc7c9018c03e3a8eeb6a5d6110340c97db6b1d7c19d6a6d1f3bc4`）：S拥有H physics与P logic-process两个服务域。正常新运行按原有效频率F绝对释放 `origin+n/F`，每个完整H后一个P；P与render脱钩是显式服务合同变化，不能称旧process本来恒为F。对照采用同一合法时钟transcript（0/1/multiple H→P、raw/clipped delta、输入及wall读点），另验新正常模式按期完成。

相位固定 `Ubegin → H输入/prep(sync/flush) → Hgroup → Htimer/deferred → end_sync/唯一STEP/post → P输入/group → Ptimer/accepted release → Uend/publish`。P/Ptimer原先合法的LOS仍允许S在STEP后查询，不额外sync/step，也不推迟到下一H。`GameRoot`治疗保留独立tick回调；timer保留原flags、扫描截尾、新创建首次扣时和callback现场pause资格。默认0.8秒death always timer与pause-aware windup不能统一暂停。time_scale每epoch采样，simulation时间只由H推进一次，ignore_scale用原raw字段，不做除零或倒推。U durable receipt即使pause/time_scale=0也处理，不能调用process(0)/timer(0)伪造服务。已接受release保留各自token和life/world；新动作或worker晚到不取消旧release。

短期迟到只按原小H/P逐对补账，单turn上界沿原M并在每epoch检查U；超限返回显式fault及保留未处理债，不清队列、丢事实或自动退出制造性能通过。OS suspend独立rebase，不补造后台攻击。精确实现与行为用例见候选clock/timer交付；完整玩法时钟对照仍NOT_RUN。

状态和表现事件仅在完整合法服务边界发布；持久化后奖励另受receipt门控，不与伤害事实同时投机发布。

攻击、碰撞、HP和RNG不依据worker完成顺序生效。原已接受动作继续按原windup/release推进。提前算好不提前造成伤害；迟到不假装已按期生效。

## 3. 模块接口

接口跨M/S/W只传冻结数据、句柄和状态，不传活动Node/Resource/Callable。下列C++签名是待建接口；`WorldIdentity`/`ActorIdentity`内部编码保持原字典字段，不增加平行业务身份。

| 模块 | 输入与输出 |
|---|---|
| SimulationHost | `start_world(WorldSeed, ClockPolicy)->StartReceipt`；`submit_command(CommandEnvelope)->EnqueueReceipt`；`set_clock_policy(ClockPolicy)->PolicyReceipt`；`request_transaction(TransactionCommand)->TransactionToken`；`request_quiesce(Reason)->QuiesceToken`；`poll_receipt(token)->Receipt` |
| CombatKernels | `prepare_range(const TickInputs&, Range, OutputSpan)`；`evaluate_range(const FrozenBlock&, OutputSpan)`；`repair_changed(const LiveRecords&, ReadSet, OutputSpan)`；仅数值，不提交事实 |
| BatchExecutor | `dispatch_ready(BatchTicket, Blocks, Deadline)`；`poll_published(BatchTicket)->ReadyMask`；`claim_block(BlockId, Owner)->ClaimResult`；`retire_completed(BatchTicket)`；固定阶段与有界在途 |
| PresentationBridge | `acquire_frame(min_tick)->FrameLease或NotReady`；`release_frame(FrameLease)`；`drain_events(ack_ordinal, EventCapacity)->EventLease`；`ack_events(last_ordinal)` |
| PhysicsPort | 唯一模拟物理所有者，显式begin/query/move/end phases；精确实现由封口设计约束，不能调任意活动Node |
| TransactionPort | `persist(FrozenSave, SaveToken)->SaveReceipt`；原schema/atomic write；成功只在原落盘条件满足后确认 |

保存协议沿原事务：S先建立prepared plan与冻结identity/revision/affected_before → I/O仅序列化/落盘，不读取live状态、不调用旧M的玩法completion → immutable durable receipt进入S事务邮箱 → S按原context/sequence条件校验并恰好一次提交live watermarks、respawn/reward/inventory/gold → 先完成状态变更再发可重入的表现/通知事件。失败不发原本需receipt门控的奖励；旧profile成功receipt只能记为旧profile已落盘，不改当前profile。拾取promote期间允许的物品消耗delta沿`_loot_inventory_after_immediate_uses`原精确规则合并，不能整张inventory快照覆盖。事务barrier、receipt身份与sequence沿原合同，SaveToken只作传输句柄。

暂停不停止接受已发生的durable receipt：沿 `paused_receipt_pump.gd:11-18` 的always-service合同，S暂停的是玩法时钟和动作，事务控制服务仍可醒来消费receipt。UI暂停时不能把不可逆落盘receipt丢掉，也不能等模拟resume才确认安全退出。

`CommandEnvelope`包含已有world/actor身份、单调到达时间、source_seq、输入token/touch/source、UI路由及所见相机版本、kind/payload。邮箱容量在世界装配时按支持实体/释放上界确定，有界不代表丢合法命令。连续移动状态可按明确采样区间合并最后值；press/release/cancel、技能、拾取和事务边沿绝不合并或丢弃。满队列显式失败并停止新接受；不能静默吞掉已接受输入。

## 4. 分块、取消和补算

分块单元是独立数值工作范围：actor候选范围、peer关系范围、地图边范围、表现参数范围。任务数可多于worker数，空闲worker领取ready块；不创建“每10怪永远占一条线程”。需要前置数据的块由S完成前阶段后释放，W内部不等待其他W。

每块状态唯一迁移 `UNCLAIMED → RUNNING(owner) → READY → CONSUMED → RETIRED`，取消只允许 `UNCLAIMED → CANCELLED`。S参与补算须用同一claim路径；不能与已running的W写同槽。running输出迟到后按ticket/version隔离，保留输入直至完成，不强杀、不复用其内存、不重复提交。

S的必要后缀只使用已完成且经验证结果；缺少块由S领取剩余未claim的必要工作，running块若是必要输入，其完成时间计入真实关键路径。此时没有“无等待保证”；不把等待转回M，也不把迟到记PASS。停止无用投机不能取消必要事实。

当前tick一个在途窗口；最多一份同tick前瞻，不积压多个任务tick。有界内存按支持实体/事件上界装配，耗尽显式失败。截止失败保留诊断，不丢已接受动作或重写deadline；持续超限属于性能FAIL，不能无限建catch-up任务、悄悄降低频率、自动退档或自动中止会话来制造通过。正常安全退出沿现有流程；生产异常政策若要新增暂停/终止，须作为独立产品决定，当前设计不引入。

## 5. 原序一致性与读集合

保持原actor遍历slot及候选顺序。较早actor移动发布后，较晚actor读取正式新位置；不使用统一旧位置并行最终写回。

每份建议记录其实际读取的world、life、pose/radius、target/action/资格、静态几何和索引范围版本。S提交前对照变更日志；新进入者、同bucket移动、死亡、复活/传送、半径或mask变化均可使查询失效。需要时重跑原索引查询、恢复原candidate次序，再从原首选方向重新短路。修复所有影响分支的谓词，不只修旧时获选结果。HP/RNG/回调不投机。

高冲突区缩短前瞻窗口，沿同一串行原生实现执行必要后缀；静态和未变关系继续并行。不能换flow-field、KD-tree或群体新solver来冒称仅组织线程，因为那些是额外算法/行为变更。

## 6. 输出缓冲和事件

3槽状态 `FREE/WRITING/PUBLISHED/READING`；lease引用计数与generation保护，producer不覆写READING。M获取最近符合min_tick的完整状态，无合格状态返回NotReady。事件单独有序且ack后才能回收；同tick多个受击/死亡不能被快照覆盖抹去。

每份snapshot附 `last_effect_ordinal`；M取得snapshot lease及覆盖至此ordinal的事件范围，按原序消费后才能显示与该水位对应的生命周期状态。跳过旧snapshot不跳过事件，状态与事件的可见水位同时发布；M ack确认后才能回收事件/代理和相应身份retire。若事件容量/到达不满足水位，整份presentation bundle返回NotReady，不先显示新世界再把旧世界死亡事件补进来。纯显示状态可按同实体version去重，原伤害/死亡事件不能按“最终状态一样”丢掉。

`min_tick`由既定采样/呈现时序确定，不依据“目前算到了哪”回退。插值若沿已有呈现合同，只用于显示；不补造模拟完成。buffer满和状态年龄过限分别计失败。暂停/恢复重置释放基准但保留原合法到期语义，不把游戏状态墙钟倒退。

## 7. 切换、事务和回退

开发期间旧/新模式在加载会话前确定，不能按技能、actor或HP字段混用。新模式需要当前全部实装技能/召唤/投射物/物理/保存写入口闭合才对用户开放；早期切片在隔离测试世界验证，不禁用正式玩法来通过。

正常切图：锁输入并切换命令epoch → S执行原生命周期取消/已接受事务完成规则 → 必要I/O确认并S提交receipt → S停止释放新工作并退休所有在途输入/结果 → M消费至切换event watermarks → 返回最终snapshot与quiesce receipt → 原世界与物理域退休 → 原正式生成链装配新world → 原身份epoch生效 → 激活新S → 解锁。不能要求暂停后的windup“自然倒计时完成”而陷入死等；是否取消/完成沿原map/death/logout规则。非法中途断开不得提交来自旧world的迟到输出。

回退仅在下一次完整加载前选择旧模式，加载同schema一致存档，不能将两套owner同时跑。故障中不能悄悄装回旧存档、抛弃未durable的已接受事实或切换owner；必须完成原安全保存/退出合同。新运行时发布对外前固定版本、engine/API与数据指纹；保存完成必须沿原确认合同。仓库、装备、等级、技能、钱等全部现有存档字段保持，不以重置/重建账号逃避兼容。

## 8. 截止验收与后续扩展

60fps显示期限为16.67ms，但模拟频率按原有效配置。每条数据有release/input sample、worker deadline、S commit deadline、presentation deadline，分别记录；不把W ready当画面/玩法完成。

保守下界是 `pool >= max(W/p_effective, longest_dependency_chain)`；实际完整模型还计S准备/原序/修复、M提交、GPU尾部和系统干扰。worker数量与p_effective不同，不把8核当8颗等速独占核。不预设没有来源的手机每函数毫秒预算。施工后用真实已迁移闭环确定有效并行度/块大小；总负载、碰撞、完成量与旧基线一致。

未来buff/debuff接入S的原状态组件与到期账本，纯结算数值可批算、HP/死亡仍S提交。每种效果的叠层/覆盖/刷新和结算周期由用户数据设计决定，不统一擅改为1秒。当前效果范围按用户说明：局部AOE/光环，通常最多10–15目标、单怪最多6种；不为30–40怪同帧全中预先建庞大通用系统。此次迁移先解决现有群怪，不顺带实装新效果。

验证顺序：确定engine/physics适配可闭合 → 原生串行参考规则一致 → 工作池输出与原序修复一致 → 完整会话与事务回归 → 同负载截止/资源 → Android构建校验 → REA-AN00实机。研究和设计阶段本轮不运行这些实验；它们是施工验收门。小的可逆改动只执行必要专项，大迁移必须有对照证据。
