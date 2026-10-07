# 怪物系统接线审计与 v105 用户反馈

本文件保留修改前诊断和中间失败，不是最终候选验收表。当前结果及证据见 `CURRENT_RESULT.md`；逐行为覆盖见 `SPECIAL_CURRENT_ACCEPTANCE_REVIEW.md`。

核验日期：2026-10-07。生产基线为 `codex/integration` / `aa75c5bc9845b49ee3ce67ce064442cc3fb3c43c`。本轮审计与后续修复、APK 和设备验收分开记录。

## 用户反馈和本轮合同

- v105：进入战斗的怪物越多，帧率持续下降；蜈蚣洞最明显，其他地图也出现。约 30 只时用户体感最多约 20 FPS。地图总怪物数的影响尚未确认；手机型号尚未提供。
- 用户确认雷电停步是普遍现象，并明确选择：受击只能延后怪物攻击，不能推迟移动。长时间延迟不可直接转移到攻击。
- 祖玛教主在五级火墙中掉血快，并在受击后立即召唤；要求核查伤害与固定行为的接线。
- 范围扩展到所有怪物特殊行为。注册、静态校验与 actor 分支通过不能代替完整特殊行为验收。
- 已批准受击修复：取消直接魔法移动延迟；保留来源等级公式的小额下一攻击延迟、受击表现和已提交攻击；核对连续命中、不同等级、零伤害、闪避、火墙、毒素以及高频累积。
- 已批准祖玛阶段召唤按来源行动/寻敌检查周期消费，有目标8秒、无目标1秒；保留当前4–7只、15只上限及阶段算法。Boss基础攻击间隔读21CQ主属性，显式狂暴仍可改变节奏。
- 用户随后明确授权群怪放弃原有复杂站位规则，以有效追击、有效包围为目标，尽量简化。取消轴位/角位互等与长期预占属于本轮授权；真实地形、碰撞、怪物数量、攻击及HP合同继续验证。

## APK 与主树关系

`outputs/pro_v105_final_20261007/build_plan.json` 和 `DELIVERY_FILE.json` 绑定 v105 构建源码 `f6b70d55def70d98639003da5b90d6d0b7cd3587`，APK SHA256 `e65366c437c1d2778a45083ad4448eed4647c21ca024d4c2cc22fe18fe10064c`，491805682 bytes，versionCode 105，包名 `com.personal.mafaoffline`。

v105 到审计基线的生产差异仅为 `effect_runtime.gd`、`presentation_port.gd`、`skill_cast_request.gd` 和 `skill_runtime_router.gd`。本报告所查怪物受击、AI、Boss、空间索引和火墙主链没有在第三树迁移中变化。后续修复必须另绑实际文件内容，不能归入 v105。

## 正式主线与状态归属

| 环节 | 当前所有者 / 接线 | 本轮需要确认的边界 |
| --- | --- | --- |
| 身份、属性、出生输入 | `MonsterIdentity` → `PublishedMonsterInputs` → `WorldTargetBound` → `EnemyActor.setup` | 稳定 ID、精确属性来源、世界发布输入与实际 actor 一致 |
| 普通 AI 和行动时钟 | `EnemyActor._physics_process`、`_combat_action_time_s`、`MonsterMovementCadence` | 前景战斗、后台休眠、移动段提交与受击相互独立 |
| 伤害 | `CombatRuntimeService` → 正式防御结算 → `EnemyActor.take_damage` / 既有 HP 权威 | 零伤害、闪避、STRUCK、MINE、POISON、DOT 不混同 |
| 表现 | `MonsterVisual`、`MonsterOverhead`、单帧 `MonsterVisualStreamingCoordinator` | 表现不修改游戏移动时钟，不把动画队列当成控制状态 |
| 特殊行为决策 | 已发布行为 profile / Boss rule → `EnemyActor` 对应入口 | 来源规则、检查周期、释放与生命边界需要逐行为覆盖 |
| 召唤出生 | `summon_requested` → `GameRoot._on_boss_summon_requested` → `HCM30SummonQueue` → 正式出生资格 | 决策不能绕过队列、上限、世界与生命资格，不新增出生权威 |
| 持续地面伤害 | 正式技能 definition / plan → `FireWallFieldController` → 共享空间索引 → 精确命中 → 正式伤害 | 实际 tick、施法者/目标 claim、MAC、raw power 和 HP 事实 |
| 死亡及刷新 | 既有死亡边界 / `GameRoot` 死亡工作队列 / `MonsterRespawnPolicy` | 不在多目标释放中途撤销已接受工作；出生槽、死亡与物理退休分开 |

## 修改前审计：受击已确认的冲突

审计基线保留 `DIRECT_MAGSTRUCK → apply_source_direct_magic_walk_delay → MonsterMovementCadence.postpone_walk_tick_ms → 下一自主移动段拒绝`。延迟 `800 + Random(1000)`，即 800–1799ms，适用于等级低于 50 且非豁免怪物；MAC 压成零伤害仍会进入该移动延迟。直接魔法来源规则已被用户本轮明确覆盖。

普通有效受击另外添加攻击延迟：`150 − min(130, level × 4)` ms。Lv1=146ms，Lv10=110ms，Lv25=50ms，Lv32=22ms，Lv33+=20ms。只影响下一攻击 deadline，已提交攻击不取消。ID79 的 50ms 占其主属性 3000ms 攻击间隔约 1.67%；ID160 的 20ms 占其主属性 1000ms 间隔约 2%。这说明单次惩罚较小，不证明任意多来源命中频率下不会累积。

`MonsterVisual` 的受击队列等待命中时已经提交的那个移动段结束；审计未发现它独立制造全等级逻辑停走。近战攻击释放和接触距离内的站立是另一条合同。必须新增多等级连续追击验证，不能仅证明当前移动段没有取消，也不能用低于 50 的门槛解释用户的全部观察。

## 修改前审计：祖玛同步伤害接线与来源周期不同

祖玛正式稳定 ID 为 `160`；ID161 属版本差异，不允许正式 runtime 出生。主属性 HP3000、AC20、MAC20、等级60，攻击间隔1000ms、移动间隔300ms。

当前 `_apply_damage_core` 每次有效掉血后同步调用 `_apply_health_stage_mechanics`，进而直接发出召唤信号。正式 primary `dev_art_sources/reference/original_gameofmir/M2Server/ObjMon.pas:1511-1555` 把 danger-level 检查放在 Run 的非石化、非死亡、非控制行动周期，并与 `targetSearch` 的有目标 8000ms / 无目标 1000ms 检查相连。数据中已登记 `targetSearch`，但该召唤生产入口没有使用它。

原始源码构造时 danger level 为 5；`5 > HP / MaxHP × 5` 在任意小额掉血后成立。**首伤满足第一阶段条件本身符合来源；需要修的是检查/释放接线，不能把阈值擅自改成八成血。** 当前项目召唤规则4–7只/次、15只活跃上限，原来源6–11只/次、30只上限；本轮保留项目已有数量合同。

Boss 基础攻击间隔还有双来源：`_apply_behavior_profile` 先读主属性，`_apply_boss_rule` 又覆盖为兼容 timing。ID160 当前被覆盖到1200ms。移动最终已由正式 cadence 重绑为300ms；兼容 Boss timing 的800ms不是最终移动间隔。需要逐字段核对所有 Boss，不能机械同步旧描述。

## 五级火墙：尚不能定性的伤害反馈

正式 primary `skills_source_of_truth_v1.json` 的火墙为1000ms一跳，精确3×3，明确 MAC 防御、同一施法者同一目标单 tick claim；旧 `profession_combat_rules.json` / profession package 描述3000ms、五格十字，并带候选来源标记。数值不同需要查实际消费者，不能把旧候选定义机械升为正式权威。

现有控制器具备单目标单 tick claim。尚缺用户现场角色魔法属性、实际释放/施法者身份以及每跳 `raw_power → MAC resolution → HP loss` 和时间戳。原始祖玛自己的魔法攻击通道不能证明它应该对火墙免疫。火墙掉血过快保持 `MISSING`（因果证据），不能用提高 Boss HP、降低技能伤害或减少 tick 取得通过。

实际正式链为 `WizardSkillRuntime → FireWallFieldController → GameRoot._apply_canonical_ground_tick → CombatRuntimeService.apply_enemy_direct_spell_damage(MAGSTRUCK_MINE) → GameRoot._resolve_magic_defense → EnemyActor.take_damage`，没有通过 feature periodic damage。五级按基础三级公式计算后乘 `1.1² = 1.21`，而不是把公式等级直接改为5。ID160的canonical标量MAC20被编译为min=max=20，每次有效命中应减去固定20。不同controller同施法者同技能同目标仍受全局tick claim约束。

## 修改前审计：数量性能的热路径与证据缺口

- 前景战斗逐 actor 运行完整物理、重评估、移动碰撞和表现更新；远处空闲怪物可关闭物理回调进入后台休眠。因此 total、engaged、visible 必须分开记录。
- 密集邻居查询虽然用空间桶，但候选逐项插入排序最坏 O(k²)；普通近战包围站位还多次遍历同一组 peers。技能关闭时这些路径仍存在。
- 当前 10/20/30 微基准只手动驱动60次 `_physics_process`，缺少正式 GameRoot、地图、真实渲染和实际物理时钟；不能证明手机帧率。
- 现有 `DeviceLabRuntime` 已能提供 total / engaged / visible / physics_enabled / deep_sleeping 及模块计时，无需另建测量权威。实际设备 CPU/GPU、热机和正式地图计时保持 `MISSING`。

## 本轮修改前原生基线

源码集合 SHA256 `c1f6b675d9c5ab2d76f0936f4ff0ddf85680c4ec37498d9c853f68a1801e7d86`；两次 controller 均确认受测源前后相同。

| 基线 | 场景数 | 结果 | 证据 |
| --- | --- | --- | --- |
| 受击、经典Boss、Boss区域结算、10/20/30微基准 | 4 | PASS；原生退出0，engine错误0 | `outputs/monster_upgrade_20261007/baseline/` |
| 特殊投递、W1投递、尸王、骷髅精灵、状态、MFC2、休眠受伤唤醒 | 8 | PASS；原生退出0，engine错误0 | `outputs/monster_upgrade_20261007/special_baseline/` |

微基准实测10/20/30怪平均 frame-equivalent CPU成本分别0.673 / 1.453 / 2.348ms，最大2.313 / 5.176 / 8.771ms。该值不是 wall frame、GPU 或设备 FPS。

这些 PASS 仅是旧合同基线：受击测试明确期望直接魔法停步，经典 Boss 测试只验证大额伤害后同步召唤。当前新受击合同、召唤周期和用户设备性能不因这12个场景变为 PASS。

## 实施中发现的额外接线缺陷

首轮Boss修改把阶段函数移到寻敌入口，但该入口已有 `BOSS_TARGET_REEVALUATION_MAX_SECONDS=0.35` 夹限；`_hc_received_damage` 又会清零维护timer；无目标分支没有对应timer门禁。两项首轮actor场景PASS仅覆盖基础攻击间隔和手动强制重选，不能证明8秒周期，首轮阶段时钟验收仍为FAIL。

阶段耗尽后，原函数的 `stage<=0` 早退还会阻挡满血恢复为5阶。后续修复需要让阶段寻敌周期读取现有唯一combat action clock；普通目标维护、受击威胁反应和正式阶段消费分别验证，不能让维护timer的重置偷放召唤。

## 成熟群体移动方法的适用边界

[Supreme Commander 2流场章节](https://www.gameaipro.com/GameAIPro/GameAIPro_Chapter23_Crowd_Pathfinding_and_Steering_Using_Flow_Field_Tiles.pdf)将目标路径工作共享，并把局部转向作为独立步骤。这支持减少重复寻路与重复局部判断，但不是本项目已启用流场的证据。

本项目67张正式地图使用polygon导航；每个需要绕墙的actor有独立poly search，开放群怪的现有path指标为0。当前先简化局部包围，而不改未在正式地图启用的旧grid流场。[Godot导航性能文档](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_optimizing_performance.html)也建议避免无必要地重置路径和重复导航查询。引擎RVO的计算空间与实际物理/地形约束不同，不能直接替换现有碰撞；见[官方NavigationAgents说明](https://docs.godotengine.org/en/stable/tutorials/navigation/navigation_using_navigationagents.html)。

## 待闭合

- 受击修复的独立 FAIL、最终固定源码回归与 RNG 续流证据。
- 全部特殊 profile → 稳定 ID → actor入口 → 正式服务 → 实际行为测试矩阵。
- Boss基础 timing 主源与显式特殊变化分开；阶段召唤按正式行动/寻敌周期接入。
- 同负载稳定邻居排序与密集站位性能、真实物理时钟基线。
- 五级火墙的实际伤害事实链，以及当前候选 APK / 用户物理设备验收。

本报告不宣布 P0–P6 架构升级完成；不把 APK 导出或桌面原生 PASS 等同于手机验收。

## 当前专项接线验证（最终群怪源码复验前）

受击追击场景以真实 `CombatRuntimeService` 正伤害和实际物理帧检查Lv1/43/50/80连续移动、攻击累计及已提交攻击结算，91项检查通过；首个runner输出缺PASS marker，因此原FAIL保留，修正输出后原生PASS。R1/R2/phase trace旧测试曾仅消费兼容RNG，现已改为实际HP下降的direct hit；三场专项PASS。三个seed的phase trace与独立cadence oracle一致，不据此宣布设备动画验收。

`classic_boss_order_test` 已通过真实连续受击8.2秒、每个8秒边界前不得召唤且stage anchor不得重置的检查。无目标1秒、已到期控制/休眠/死亡门禁和满血阶段恢复分别验证；普通维护timer仍按既有快速策略运行，阶段检查和普通寻敌维护不能混称同一个8秒timer。首次合并真实测试后无目标断言错误地从目标清除计时，而不是从最后源搜索计时；原FAIL保留，改用独立新actor无目标fixture。修改期间不同content SHA结果不合并为最终通过。

五级火墙正式测试使用 `main.tscn` / 正式世界发布ID160 / 正式施法plan / 实际field callback / CombatRuntime / 唯一Enemy HP，不mock结算，不改祖玛HP3000/MAC20。基础技能3级加实际装备词条2级形成rank5。显式MC40/40夹具：rank3 raw46，rank5 round(46×1.21)=56，MAC20后每跳扣36。三个真实physics tick间隔60帧，同施法者同中心刷新而不新增owner、异中心两field覆盖只扣一次，扣血回调不发即时召唤。最初按process_frame取样会跨多个physics catch-up帧，不能当实际tick；现改为每个controller后physics observation，未改变生产时序。runner `special_field_gap/172055_942363`火墙和ID183各PASS；用户现场MC仍未给定，现场异常因果保持MISSING。

ID193新测试曾自行假设按实际HP损失吸血，输入30/AC后扣19/回9导致FAIL。源审查证明当前runtime使用pre-AC输入；profile仅登记0.33，没有basis、盾吸收或过量规则，primary/auxiliary未找到对应ID语义权威。不能把新测试自拟期望冒充来源或擅改数值。继续记录输入/防御/实际HP/回血事实与miss/zero，MISSING_AUTHORITY保持；见 `outputs/monster_upgrade_20261007/SPECIAL_LIFESTEAL_SOURCE_AUDIT.md`。ID222目标魔法已有独立post-MAC回血路径，不能和193混同。

## 群怪实物理修改前对照

`outputs/monster_upgrade_20261007/crowd_before/172328_695492/` controller PASS，native0、source stable，content SHA `c418834bcb85365a291b999339b69981c6192c214056dd8331d2a937365a1392`。四场景×10/20/30怪，seed20260909，warm45、sample150，真实Enemy physics+WORLD body+spatial+HP。首10open实际153physics ticks，其余150；CPU必须按实际tick/call归一，不能固定除150。30怪open/close/obstacle/dense CPU每physics tick为6.335/7.431/5.309/7.191ms；close攻击8次HP164、dense攻击5次HP101。actual layout/count/progress/attacks/path/queue/full-frame分位数保留全部12行。headless process callback frame间隔是uncapped，不换算Android FPS；本fixture全部path queries0，world_obstacles证明局部physical wall处理，不证明共享polygon寻路。
