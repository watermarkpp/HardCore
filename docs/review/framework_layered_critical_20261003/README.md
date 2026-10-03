# 分层追击、死亡当刻碰撞与critical后续验证

父提交：`dc1ebf3fea1d047d4e18b352140a50b593223cea`。施工仍在第三树，未合入主树v97，未改第二树或真实用户存档，未打包APK。实际原生测试的施工HEAD仍是`5d9ceb0121980ca9636d9d1cc2e19982949fbf63`加明确未提交内容；本次审计提交保存受测内容，不能称新提交的干净checkout已经执行。原字节ZIP与Git换行规范化映射分别可核验。

## 本轮生产增量

1. `scripts/enemy.gd`：修正已录下的分数格拥堵反例，等待点的完整占位与真实第一腿一致；后排接触退出选择合法有界路径。按用户授权，未领取近战站位的较远普通近战怪先选择合法方向接近，停止做近战攻击线排名与16邻格批量站位检查，并完成可用的短途路标。临近后继续争取最多8个攻击站位。实际目标、生命、世界身份及每段地形、活身体仍现场验证。
2. `scripts/game_data.gd`：在现有身份入口登记既有`hc.currency.gold`的精确目录来源，消费者通过同一记录读取；无新增业务身份、数额或生成物覆盖。
3. `scripts/inventory_panel.gd`：装备失败使用已有槽位显示名，避免把`hc.slot.armor`内部身份显示给玩家。
4. `scripts/player_state.gd`：测试角色payload生成器把明确未配置槽位保持为空，避免把合法空槽当缺失装备。此函数是测试输入生成边界，不是第二迁移或生产背包写入权威。
5. `scripts/layers/runtime/execution/frame_budget.gd`：在真实epoch首次服务公平比较中，已经在本epoch获得服务的其他类别不再挡住剩余额度；尚未服务且合格的类别、晚加入类别和跨epoch年龄仍保留优先权。原1200us准入软预算、在途耗时、嵌套外层只计一次、necessary及原子越额规则保持。126项预算协议检查明确包含A/B两epoch为2:18的反例，不将机会式余量使用称为等份或严格轮转。拒绝分类和每类别/epoch一条last_denial为常数空间记录。

分层移动不限制怪物数量，不截断AOE，不改变移动速度、攻击节拍、碰撞半径、技能耗蓝或已接受动作。已经拥有合法近战位置的怪物可保留其绕行，不能笼统称所有几何上较远怪物都被强制切为同一模式。

## 新增反例与边界

- 录下的分数格近场退出、等待点和后排接触反例，RED/GREEN原始记录保留。修正完整目标点时不能因为第一小段暂时清楚，就继续冲入被活怪占用的等待点。
- 远场全路标弦线通过，但实际八方向运动的第一腿被同伴阻挡的独立反例：使用真实分数格位置与当前身体，最短路标选择必须验证运动所有者真正执行的段。禁止缓存身体命中结果。
- 完全关闭的同伴身体笼：诊断RED中正常起步授权前idle，授权后intent/session存在、位置不动且walk帧推进，但新远场失败分支遗漏`FRONTLINE_BLOCKED`记录，仍报`OUT_OF_RANGE`。生产只补该真实阻挡原因；不放开碰撞、不强制动画、不改变节拍。原阻挡、暂停和控制锁断言全部保留。最终对同一身体笼重新验证。

## 死亡碰撞立即消失

此规则已由既有生产`EnemyActor._mark_death_pending()`承担：同步HP归零/失活、关闭collision layer/mask、退出enemies、注销空间索引，再deferred进入死亡动画/信号。peer路径及攻击位置候选继续读取当前资格。没有新增清理计时器，也没有等待掉落、死亡队列或queue_free才开放通路。

旧`aoe_death_phase_boundary`夹具只等两帧、使用旧技能身份并在初始安全区调用伤害；初次未形成有效致死，FAIL保留。夹具改为正式世界READY、明确非安全合法位置和canonical技能/武器记录。新增同步前后对照：活怪原生Physics2D查询确实命中、peer通路确实被挡、近战位置确实被占；同一Root伤害调用后无await，尸体仍在树中且未开始dying/发死亡信号，但原生碰撞查询、peer路径和位置占用立即不再包含它。所有原死亡/AOE伤害断言保留。

旧耐久断言要求命中栈内同步保存，与当前已存在的合并保存合同冲突。第二次FAIL发生在全部死亡即时断言通过之后。按生产`apply_durability_event`/`_advance_durability_runtime`与既有precise durability专项改成更完整的口径：多目标一刀只增加一次耐久mutation revision、命中栈不写盘、真实正常保存间隔恰好提交一次。不修改正式耐久写入服务。`DEATH_DURABILITY_PHASE_MANIFEST`和原始失败日志记录这次预期更新的依据。

## 角色重名与独立账户

正式创建入口先对trim和12字上限后的名字检查重复，检查角色列表及canonical主档，重名在分配新profile、替换状态与创建文件前拒绝；界面显示服务原错误。`new_character_starter_loadout`原有同名拒绝、角色数量/活动身份不变、独立角色装备身份、保存/重新选择及原子失败回滚验证保留并重跑。未增加模糊名称或第二身份体系。

一次journal组合中，同进程恢复夹具已创建“事务回退2”，随后独立seed场景在同隔离账户再次创建同名。整个组保持FAIL，前4个完整PASS独立保留；cold和restart正确拒绝失败producer。修正的是控制器分组：独立seed/cold/restart使用新的隔离APPDATA，链内三个进程继续共用其本轮账户与严格producer关联。没有删除存档、放开同名或弱化handoff。最终所有组都在最终内容指纹执行。

## 持久化与P6

容量接受前保证、原子准入、receipt退休、v2/v3旧备份恢复关闭epoch、原成功quote直接重交、缺失与损坏primary、拒绝零writer/资源/文件变化、真实非空world generation及独立冷启动在各自专项复测。receipt长期身份托管与journal64持续水位协议仍分别处理，不以TTL/LRU或清空去重表替代。

自然输入/玩家与怪物移动/战斗、持续效果、资源线程任务与死亡writer并存、退出与冷启动恢复，继续采用正式Root/Player/planner/唯一HP/模拟钟/writer。30指定ActorRef各3distinct source的快照继续核验；90测试状态不构成玩法目标上限。实际成功投递迟到、剩余积压、队列时效、每状态终态和墙钟帧分布分别统计。四轮退出恢复是活效果退休，不称四轮全部击杀或无限时长内存稳定。

30死亡突发夹具保持真实生产输入，快照所有任务必须QUEUED，最终COMMITTED键集合必须与快照双向相等。live掉落节点与当次计划/实际物化数量核对；先前固定版的26/32不套用到本轮随机掉落。cold检查XP/保存标记/队列，不称地面掉落重建。共同到期tick的投递与目标死亡失效分别计数，取消不是伤害。

共享预算旧规则的原生因果证据独立保留：实际epoch277中资源已轮询、88个due、spent535us/remaining665us、无在途scope，效果被同epoch已服务资源以fairness原因拒绝；16条同类原生记录由原trace重算，原2966667us迟到仍FAIL。修复后同额度可消费多个效果量子，最终因budget耗尽拒绝；合法单个原子量子的越额继续完整计费。该对照是机制证据，不是ABBA性能比较。

严格静态边界的两次完整Root输入固定在同一个测试process回调阶段；从原4秒duration推导240固定帧，并核验实际process/physics与模拟钟间隔。正式Player process Timer配置仍600000us，固定60步进下实际skill_requested偏移583333us是量化观测值，不能写成“实测600ms”。测试只在这两个静态边界中加入有界墙钟节奏；10组重复的最大墙钟观察间隔约1.10–1.20秒，不能称自然60fps、CPU/GPU性能或任意实时输入阶段的相同偏移。严格death==expiry、due>0和实际投递迟到<原period仍分别判定，未扩大容差或改生产pump/clock。

原streaming single-poll夹具在旧预算与候选均失败：启动persistence聚合计费4700us，5个scope中4个necessary，不能说4700us全部来自necessary；人工frame计数前两次调用位于同一已耗尽actual epoch，得到598/600。仅将测试采样移到真实Engine epoch，并核验同epoch第二poll不增加次数；1/100/300目标和600/180/120采样均保留。最终13场景全PASS，不修改冻结资源协调器或重置额度。夹具每个采样epoch一次，不承诺任意necessary压力下每帧必成功。

新增受控独立进程强杀两处可观测业务边界：PREPARED（尚未域消费，正式primary仍旧序列）与PROMOTING（sole worker已成功提交primary，新回执尚未域消费）。外部控制器逐项验证nonce、source/run/invocation、真实子进程PID/创建时间/命令/引擎SHA、隔离profile字节及armed成功checks后，只终止该测试进程。原producer native结果仍FAIL且非timeout；单独控制handoff记PASS。独立cold读取真实正式档，恢复资源/序列一次、旧ID/变更请求不重开writer。

这两项不是rename内部每条指令、物理断电或有效旧primary整档替换矩阵。早期本机SHA helper失败、冷场景PASS文字触发既有Crash日志门禁的尝试均保留；正式runner门禁未被放宽，后者只改测试marker名称。

## 性能口径

正式R3完整75场景与反馈29场景按清单覆盖，只复用同字节已完成场景，剩余逐项补跑。精确清单和採用行见`FINAL_R3_COMPLETION_LIST`/`FINAL_ACCEPTED_ROWS`。

ABBA复用原10/20/30规模、cold/warm、static/lateral/reverse，共18条件，每条件60预热/180原始样本。A/B只一个enemy生产文件不同，其他源字节及引擎相同。原始CPU与frame interval按原floor算法独立复算；CPU门禁仅检查P95/P99尾部分离；P50在20/cold/reverse与20/cold/static分别有+1.020408%与+0.657132%的描述性分离。CPU取enemy_physics_usec回调计数差值，不是整进程CPU。帧间隔例外分别保留，完整数值在`FINAL_LAYERED_ABBA_COMPARISON`，补充范围见`../framework_crash_archive_20261003/PERFORMANCE_SCOPE.json`。这些是PC headless移动策略，starts/HP为0，不能外推战斗CPU、GPU、Android或热机。两轮属于描述性对比，不宣称统计显著或全性能无退步。

R4仅用户授权的all_damage_lost/natural_cadence24/76使用90秒上限；保留20真实起手、原攻击间隔和全部业务断言。真实cadence决定完成时间，窗口不是改变性能。每场记录有界墙钟样本与实际起手模拟钟，60秒前后分布、样本量和不足都在`FINAL_R4_TIMING_RECOMPUTED`，不能用少量尾样本保证无退步。

E阶段90s组合为2PASS/1FAIL，24身份唯一失败是`world_not_ready`，并非timeout，且原20起手/20结算已经完成。原夹具把同步场景加载/创建算入8s异步READY预算，提前记失败后仍继续战斗。修正仅在共享R4测试入口：原8s从场景挂入后观察，原总采样期限/90s总期限均不变；READY仍失败则先落失败证据并退出，不建战斗夹具。新增同步setup/异步READY分别计时，直接GREEN仍20/20，READY观察约4.25s、同步setup约3.35s。`R4_BOOT_READY_*`、旧原字节及E阶段原始失败均保留。未修改生产加载、AI、战斗或20次要求。为保持交付同内容指纹，E阶段已通过的190次另作阶段保留，最终接受清单重新绑定新指纹，不把E记录套为新指纹PASS。

## 原始critical与交付边界

原98f09指纹683场景分成被中断382（360PASS/22FAIL，原生最终退出MISSING）与恢复301（268PASS/33FAIL）。原运行保持FAIL。最终相关回归覆盖所有55失败记录涉及的独立场景及其相关回归；不把旧628个通过场景叫在最终字节全部重新执行，也不把中途marker当验收。

R4等待修正前E阶段80场景完整结束为80PASS/0FAIL、原生退出0、源字节稳定，17个framework完整回执1055检查。`device_lab_runtime_test`完整场景在该阶段PASS；最终通过及源字节由`FINAL_ACCEPTED_ROWS`重新核验。其原先夹具失败保留为历史失败，不再把已通过的完整场景写成未通过。该场景属于PC headless功能回归，不能据此宣称手机设备或GPU已经验收。

本轮代码、测试与最终同字节命令/receipt/run/invocation/native退出逐项归档。阶段B/C及失败性能数据不改标签；尤其首次30秒性能timeout和后续B的CPU分离FAIL保留。场景失败的原始日志、阶段源码清单和最终原字节包均可追溯。

仍独立开放：原v97第二角色B输入MISSING（新角色/v90或架构通过不替代因果验收）；Android/GPU/设备热机与同包前台性能NOT_RUN；旧V4 14FAIL与ObjectDB退出警告保留；物理掉电/内部强杀矩阵/有效旧primary整档替换NOT_RUN。DeviceLab旧完整基线FAIL另作历史保留，当前完整场景已在上述80项中PASS。主树集成/APK发布不属于本次授权。本轮不新增稳定业务ID，既有currency/skill/item/slot身份均保留其正式登记链。

审计请读取本次固定提交、`SCOPED_EVIDENCE`、`RUN_INDEX`、原字节source ZIP和完整receipt。再次审计的结论仍按各项证据范围处理，不能以局部PASS关闭上述材料或设备边界。

最终机器核验计数：

```json
{
  "parent": "dc1ebf3fea1d047d4e18b352140a50b593223cea",
  "construction_head": "5d9ceb0121980ca9636d9d1cc2e19982949fbf63",
  "source_files": 3566,
  "content_sha256": "a607400e0d745852ac41e8bbbfc5d169ecc916e71fe9c5e286a118a0673211ca",
  "engine_sha256": "d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c",
  "engine_child_sha256": "b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8",
  "delta_files": 76,
  "production_files": [
    "scripts/enemy.gd",
    "scripts/game_data.gd",
    "scripts/inventory_panel.gd",
    "scripts/layers/runtime/execution/frame_budget.gd",
    "scripts/player_state.gd"
  ],
  "native_attempts": 239,
  "unique_native_scenes": 215,
  "framework_receipts": 64,
  "framework_checks": 4221,
  "preserved_failed_attempts": 121,
  "original_failure_scenes": 55,
  "source_zip_bytes": 15146752,
  "source_zip_sha256": "142978c9589863e5a47cf2b46c0e1c034deb10812c26d18568dd282963f4a470"
}
```
