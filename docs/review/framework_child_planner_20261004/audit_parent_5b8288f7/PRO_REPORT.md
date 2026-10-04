# child-commit-5b8288f7-20261004 独立复审

已直接核对固定 **`5b8288f773d0659b2d1e45538f93fc9a2556dfba`**，父提交确为 `e22fe0951f28c55620399b453f116cb09120af4b`。**支持保留有限链身份、提交时几何与credit冻结、HP事实前置采集、错误回调无副作用拒绝，以及原周期接口兼容修复。已读范围内，未发现必须追加生产整改的新确证缺陷。**建议补强一条跨Combat入口的坏投影测试，但它是覆盖补强，不是已经复现的新故障。

以下定位均为**仓库源码原始行号**。本会话没有运行Godot；归档PASS不表述为我的新增原生测试。

## 一、事实采集顺序：确实早于同步观察者，未新增HP权威

### 有限链与credit在批次创建时拥有独立快照

`scripts/features/runtime/damage_batch.gd` **L29–85** 在领取reservation之前验证有限链，再用原 `Graph.capture()`一起捕获bindings、credit和chain。

实际约束包括：release与根技能匹配、字段集合完整、代次为有限非负整数且不超过最大代次；根代次不能自称child，非根代次不能自称direct。原空链只保留direct语义，没有用空链为child提供默认身份。调用者随后修改原Dictionary，不会扩大已捕获的最大代次或换掉credit。

**这里仍是root-scoped批次。**批次的 `skill_id` 与 `chain.root_skill_id`一致；它没有开始承接独立child descriptor的完整技能规划，不能据此认为“根技能与后代实际技能的生产表示”已经全部完成。

### 提交几何来自原Enemy地图投影，不采用调用者伪造坐标

同文件 **L93–109** 的 `prepare_commit_context()`检查原世界、目标身份、目标地图、分类和批次可用性，然后调用目标既有：

```gdscript
try_screen_position_px_to_ground_position_gu(target.global_position)
```

取得有效有限的Ground GU坐标，并覆盖调用上下文中的 `commit_ground_origin`与 `historical_credit`。它没有采样一份新的目标列表，也没有将缺失投影降级为屏幕坐标或零点。

### 唯一HP写入后的实际顺序正确

`enemy.gd` **L7163–7198** 的关键顺序是：

```text
链上下文／投影预检
→ 原HP写入
→ 冻结周期或child的实际损失回执
→ DamageBatch.capture_commit
→ DamageLedger及后续受击处理
→ _refresh_overhead_health
→ 后续死亡处理
```

其中HP写入在 **L7174–7175**，批次采集在 **L7183–7184**，血条刷新在 **L7198**。`capture_commit()`再将事实深复制／冻结，保留提交时目标life与原credit，不在回调返回后重读HP。 

新测试的干扰是真实发生的：`MovingObserverEnemy._refresh_overhead_health()`把目标移到 `(777,888)`，并将HP恢复到max_hp；direct、periodic、child三条路径的已捕获事实仍为 **30→0、实际损失30、原投影 `(12.5,-3.0)`**。最终56项完整回执确认了这些结果。**这支持关闭“回调后的HP／位置污染提交事实”的具体问题。** 

该观察者是对抗性测试钩子，不是新增的合法复活规则；测试证明的是事实不能被后续改写，不证明任意复活／死亡收益交错已经验收。

## 二、错误类别先拒绝，合法批次未被抢占；坏投影可补一条跨入口反例

### 类别预检发生在MAC随机数之前

`combat_runtime_service.gd` **L193–244** 将旧周期入口、新periodic-chain和child入口分开。带批次路径在取得防御随机数之前，先检查批次脚本、有限链上下文，并调用 `batch.prepare_commit_context()`；失败立即返回明确的失败结果。

批次预检本身不会向 `errors`追加错误，也不会增加fact或消费批次。Enemy进入原HP核心时又执行相同预检，之后才开始伤害处理。 

这次测试没有只检查“坏请求失败”：

- 三种分类分别先调用不匹配的入口，检查HP与独立RNG不变、batch errors／facts仍为空；
- 随后复用**同一批次**进行原合法提交，取得且只取得一个事实；
- 周期免疫和零伤害之后，也复用同一合法周期批次完成实际致死提交。

最终56项中的对应检查均通过，因此中间版本“坏回调污染合法批次”的回归已有直接反证修复。 

### 小型补强：坏投影目前只直接测试Enemy入口

`feature_chain_commit_test.gd`末段将正式投影配置成无效Callable，再调用 `actor.take_damage()`，核对HP及facts不变。这覆盖了**直接Enemy提交前拒绝**；但没有像坏分类那样，同时检查：

> 经Combat的periodic-chain／child入口拒绝时，独立RNG未动、batch未污染；恢复合法投影后，同批次仍能提交一次。

源码顺序已经支持上述结果，因此**不应把它列为新生产缺陷或拒绝本轮成果**。最小补强只需复用当前目标和批次，分别通过两个Combat链入口调用一次，记录HP、RNG、facts和errors，再恢复原合法投影重试；不改正式伤害、周期或投影权威。 

## 三、周期公共合同与死亡碰撞：原调用者没有被迫迁移

| 核验项 | 固定源码 | 结论 |
|---|---|---|
| Enemy原周期接口 | `enemy.gd` **L7087–7089** | 仍为 `amount、attacker、historical_credit、receipt`四参数。 |
| Combat原周期接口 | `combat_runtime_service.gd` **L193–195** | 仍为目标、原伤害、来源actor、tick RNG、historical credit五参数。 |
| 新链接口 | Enemy **L7092–7101**；Combat **L197–211** | 另行命名，不向原公共方法追加参数破坏合法override。 |
| 同帧死亡退出碰撞 | `enemy.gd` **L7366–7383** | 原 `_mark_death_pending()`推进life，清collision layer／mask，移出enemies并注销空间索引，再deferred进入死亡表现。 |

原periodic／child路径仍使用 `causes_struck=false`。最终56项检查了它们不改原攻击计时、不消耗Enemy直接魔法走路延迟的RNG，并在真实致死调用返回时检查碰撞和活目标组已经撤销。child事实记录旧life，而死亡权威将该life推进一次，二者未混用。  

这里“立即撤碰撞”指**本次伤害调用完成、deferred死亡表现之前**，不是把完整死亡、掉落、奖励和写盘都改成同步完成。

中途公共签名回归也保留了正确标签：`FAILURE_CLASSIFICATION.json`明确记录原合法子类因签名变化解析失败，退出−1且旧receipt的run/source不匹配，未采纳该旧receipt。错误回调版本的37检查／14FAIL同样保留。**这些不是父版本本来就坏，也没有被最终PASS改写。**

## 四、纯handler根技能校验成立，但生产子链仍不能发布

`death_burst_handler.gd` **L33–40** 要求实际fact的 `skill_id`为非空字符串；generation0的direct事实必须与已捕获 `root_skill_id`相同。后代事实仍以根技能标识确定这条链，但允许它自身实际技能不同，没有把后代强行改回根技能。

其余有限代次、提交损失、旧目标身份、原点及credit检查保留；该函数只构造只读 `RequestChildAction`，不调用planner或HP入口。

最终 **31检查PASS**明确包含：

> 缺失实际根技能拒绝；generation0冒用根技能拒绝；明确分类的后代不同技能身份正例通过。

这组结果来自纯Dictionary输入，不是从本轮Enemy事实自动派发完整子技能。原纯handler的31检查／2FAIL仍作为独立阶段保留。 

**本轮没有将这项“后代不同技能允许”偷偷接进Root。**新HP测试创建的是空bindings、空reservation的root-scoped批次；它能证明事实生产与传递，却不证明完整链容量、逐目标预留、子planner接纳或长期退休。handler仍未进入正式可发布合同，当前提交说明和README也明确保留这一界限。 

## 五、最终证据与源码核对范围

### 最终核心回执与本轮身份对应

已读取的两份核心完整receipt均绑定最终内容 **`3a10de2c4c889a74b642a865e1430bcee595bf5e59fa714eb513d082c6439322`**：

| 场景 | 完整检查 | 原生run |
|---|---:|---|
| `feature_chain_commit_test` | 56 PASS | `fa2994b9-5297-4aa7-abdb-b4e52783c985` |
| `feature_death_child_command_test` | 31 PASS | `948676b2-d205-4668-85e7-8ca2889877d4` |

两者使用DIRECT invocation `9711e940-cf64-4b5e-853a-53796eeaee0e`，原生自报APPDATA、user_data_dir、project和不同PID均在回执中。 

WORLD使用另一owned根及 invocation `a1182044-2fcc-4e6b-b5c8-1893caf501ab`。我核对了该组成功handoff与自然cold完整回执：实际producer、独立cold run、同源码和环境关联相符，handoff记录原生正常退出0；cold明确要求本轮成功producer并保持原奖励／保存结果。**它验证的是既有业务回归，不是新死亡子链的cold。**  

归档采用关系为 **DIRECT20／30秒＋WORLD8／60秒＝28唯一场景、28份framework回执、885检查**。57次尝试中53PASS、4FAIL仍分阶段保存。我没有逐份重新复验全部885条或57次执行，也不将四个阶段FAIL重标为PASS。 

### 七项增量已核对，3724份全量映射未独立复算

`SOURCE_DELTA.json`列出的确是**四个生产文件＋三个测试路径**：Enemy、DamageBatch、CombatRuntime、纯death handler，以及两份测试脚本和一个场景文件；没有Root planner、writer或FrameBudget增量。

本轮大体量 `GIT_TESTED_SOURCE_MAP.json` 的文件接口未返回正文，随后blob接口报错。因此，**我没有完成3724份原字节／CRLF映射及源码ZIP的独立逐成员复算**；这属于本轮审查范围限制，不是认定归档映射失败或源码文件缺失。已读取的固定源码、manifest清单和关键原生回执可以继续支持上述有界结论，但不能被表述成“本次Pro已全量重算所有源文件”。

## 主控交接

> 支持保留本轮有限链／credit冻结、原投影提交位置、HP写入后通知前事实采集、错误类别无副作用拒绝、周期4／5参数兼容及原死亡碰撞退休。56项提交与31项纯handler成果成立；已读范围未发现新增确证生产整改。顺手补坏投影经Combat periodic-chain／child入口拒绝后，同批次恢复投影再成功的RNG／资格反例，属于覆盖补强。空bindings无票据提交测试不等于完整子链承诺；WORLD cold仍是旧业务回归。全量源码ZIP／3724映射未由本会话复算，Task3—5、P6与设备/APK继续独立。

**实际审查范围：**读取四个生产增量的相关完整函数、两个测试脚本、56／31项完整最终回执、原失败分类、七项源码清单、两组关联与WORLD handoff／cold证据。**未运行Godot、修改源码或真实HEAD/index、启动第二工程主控，也未恢复或重建任何index或存档。**历史index连续性FAIL、原历史字节MISSING、原v97B缺失及其他既定开放项保持原边界；本报告只针对 **`child-commit-5b8288f7-20261004`**。
