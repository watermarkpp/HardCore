# heterogeneous-6ae8a441-20261004 独立复审

已直接核对固定 **`6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd`**，父提交为 `87400315b1accc87dc0592b091dbfcef876453d5`，源码增量清单为15条路径。**支持保留第一条即时恢复机制、即时回执与持续状态容量分离、正式混合释放，以及三来源同步退休的已测成果。已读路径中，没有发现必须撤回这些改动的新玩法执行缺陷；但新增 `actual_healing` 存在同步通知后的统计归因问题，不能把它直接当作每条恢复命令的原子实际恢复量。**

以下定位均为**仓库源码原始行号**。本会话没有运行Godot；已有原生回执与新增源码反例分别说明。

## 一、同步退休：上一轮多binding缺陷可以有界关闭

关键改动位于 `scripts/features/runtime/effect_runtime.gd`：

| 位置 | 当前行为 | 审查结论 |
|---|---|---|
| **L42–49**，`configure()` | 成功替换运行时配置时推进 `_delivery_generation`。 | 旧同步派发栈不能继续使用替换后的执行上下文。 |
| **L262–273**，`_deliver_fact()` | 保存本次派发代次；每个binding写receipt之前，先检查代次及原世界身份。 | 同一世界内的 `clear()` 也能终止余下旧binding，不依赖地图代次改变。 |
| **L272–273** | 代次仍有效，但对应reservation缺失或不再为queued时，明确报告 `feature_dispatch_reservation_missing`。 | 没有把所有票据丢失一律当作正常取消。 |
| **L376起**，`clear()` | 先推进派发代次，再清状态、展示、队列、receipt和reservation。 | 同步回血／音频通知返回后，旧循环先发现自己已退休，不再访问已清除的票据。 |

这个检查发生在下一条receipt写入之前，直接对应父版 `_deliver_fact()` 的缺失reservation访问，不是只在错误之后补一个空值判断。  

我读取了父生产字节反例的原始Godot日志：确实存在 `_deliver_fact` 中访问reservation的 **SCRIPT ERROR**，并有“退休后heap／producer／receipt应清空”的业务失败。最终三来源场景则保留真实rule、item、skill资格、Root冰咆哮接受、非空票据、实际音频通知中clear，以及scope关闭检查，**24项完整回执通过**。因此，上一轮提出的具体组合缺口已有对应证据，可以关闭。  

无票据双恢复反例也有意义：它排除了“只是缺失ticket恰好挡住第二次执行”的假阳性。最终运行时测试中，首次真实恢复通知clear之后，来源只恢复一次，第二个旧binding不再执行，**78项回执通过**。 

**边界仍是当前两个trusted handler。**它们每次最多产生一条命令；现在检查设在binding之间，足以覆盖本轮实现，不能顺带宣称未来单个handler内的多命令链或死亡子连锁已经验证。后者仍属Task4后续范围，不算本轮遗漏的已承诺成果。

## 二、即时恢复：实际损失、来源身份和唯一HP写入链成立

### 恢复基数没有重新读取受害者HP

`lifesteal_handler.gd` **L8–17** 只接受直接命中的正 `fact.actual_loss` 和非空来源身份，计算：

```text
恢复请求量 = floor(已提交实际HP损失 × fraction)
```

它不读取Node、不写HP、不调用其他handler、不消费RNG，也不要求受害者在派发时仍存活。`damage_batch.gd` **L98–134** 仍在原HP写入之后捕获不可变事实与ActorRef。因此，过量攻击不能按请求伤害额外吸血；受害者死亡、随后移除，也不必抹掉已经成立的损失。 

现有运行时反例的数值很明确：目标只剩20HP，受到100点请求伤害，25%恢复使来源从50升到55，而不是75；目标随后queue_free的变体也保持这个结果。原生回执支持保留这两项。 

### 恢复对象来自原ActorRef，不靠当前角色替换

`combat_runtime_service.gd` **L180–193** 核对ActorRef脚本、recipient身份及正数量，再调用 `source_ref.resolve()`；来源不可用、缺少原恢复接口或处于combat transition时，返回零恢复，不另找“当前玩家”代替。

ActorRef **L34–48** 检查原世界、对象身份、是否仍在原owner下面、生命代次与存活资格。实际HP仍由 `Player.restore_health()` **L1647–1656** 写入，正式死亡的 `_dead` 防线保留。**没有新增第二HP authority，也没有把恢复请求当作复活。**  

当前测试应按实际构造表述：

- “死源”用的是来源HP为0的隔离输入，证明不会把零HP来源恢复为正数。
- “换life”调用正式 `begin_combat_transition()`／`finish_combat_transition()`，证明原捕获生命身份失效。
- “换世界”推进的是该运行时夹具自己的 `_zone_generation`，由原WorldContext识别；它不是完整Root跨地图流程的新增测试。

这三项都有效，但不能合写成所有死亡复活、换图、换角时序已穷尽。

### 原燃烧没有被新恢复链改写

trusted registry给两者规定了不同权限与生命周期：ignite为持续状态，lifesteal为即时恢复。compiler仍要求 `source_classes == ["direct"]` 和原dedup规则；lifesteal不能借用周期cue，不能声明periodic来源。原ignite handler继续要求受害者在提交时存活，原周期公式和独立随机域未改。  

正式混合测试确实经Player请求、原windup和唯一planner，接受后撤回两个来源；一个基础fact随后产生一次恢复和一个ignite状态。四次原周期伤害逐次检查，来源HP不再随周期上涨，Root与Player原RNG保持，**26项完整回执通过**。 

该场景后续显式推进模拟钟并驱动pump，属于受控生产API／结算语义证明，不是自然异构持续战斗的性能证明。

## 三、容量分离：实现正确区分“需要去重”与“需要占持续槽位”

`effect_runtime.gd` **L70–99、L137–155、L197–218** 已将两类成本分开：

设合法接收者上界为 \(R\)，全部binding数为 \(B\)，持续binding数为 \(P\)，新增承诺为：

| 项目 | 本轮计算 |
|---|---:|
| 基础fact空间 | \(R\) |
| 回执空间 | \(R \times B\) |
| 持续状态空间 | \(R \times P\) |

未受管旧队列的既有成本也分开计入states／receipts；逐目标source检查只计持续handler，不再把即时恢复硬塞进16个持续状态槽。上述计算仍沿用原合法接收者上界，未新增30目标限制，也没有截断释放时的AOE结果。

17个即时来源测试因此可以得到**17份receipt预留、0个持续状态预留**。但准确地说，该检查完成了编译和预留，然后关闭票据，**没有实际派发17次恢复**。一份即时＋一份持续的真实执行由26项混合生产场景支持；更广饱和排列不能由这两项相加推定完成。 

本轮没有看到接受后因为把恢复错误计作持续状态而拒绝的路径。更广混合容量矩阵仍应按README保持开放，不把计划内待测写成已经发现的生产失败。

## 四、新的统计归因缺口：`actual_gain`不是原子恢复回执

**分类：源码可达的统计归因问题；本会话未运行新反例。已读路径中，它只进入恢复统计，未发现据此再次写HP或发放奖励。**

`combat_runtime_service.gd` **L188–193** 当前顺序是：

```text
读取 before
→ source.restore_health(amount)
→ 同步stats/resources通知全部返回
→ 再读取 after
→ actual_gain = max(0, after − before)
```

而 `Player.restore_health()` **L1653–1655** 在写HP之后同步发出通知。随后runtime **L292–294** 把返回值累加为 `actual_healing`。**通知中的其他合法恢复、伤害或生命变化，会混入这条命令的归因。**  

最小反例不必新增handler：

```text
来源HP50，最大HP100
→ 本次lifesteal经原接口恢复25，HP变75
→ 一次性stats_changed观察者再调用原restore_health(10)
→ 最终HP85
→ 当前端口把本次actual_gain记成35，而不是25
```

HP85本身是两次合法写入的结果，**错误在于把额外10也归给这条lifesteal命令**。换成通知中受到伤害，则可能少计。当前78项主要检查最终HP、资格和排空，没有这条归因断言，所以原PASS与此问题并不矛盾。

建议补一个有一次性重入保护的原生变体，分别断言最终HP85与本条命令实际恢复25。需要准确统计时，应让**原HP写入authority在第一次外部通知前冻结只读恢复结果**，而不是在端口复制一套HP公式或再写一次HP。

在补齐之前，`actual_healing`至多可解释为“本次调用前后观察到的净增量”，**不能用作每命令恢复量守恒或跨机制归因证据**。这不要求回滚本次新handler，也不改变25%的测试数值。

## 五、原生证据、index与本轮边界

我已逐项读取三份新增核心最终receipt：

| 场景 | 最终完整检查 | 证据性质 |
|---|---:|---|
| `feature_lifesteal_runtime_test` | 78 PASS | 真实Player／Enemy端口、受控batch及身份／退休边界 |
| `feature_lifesteal_production_test` | 26 PASS | 正式Root／Player接受与混合结算，周期显式推进 |
| `feature_resource_multi_reentry_test` | 24 PASS | 正式三来源冰咆哮、非空资源票据、同步音频clear |

三者均绑定最终内容 **`86b48f60…`**，对应runner记录实际退出0、有效receipt、无timeout及零引擎错误。父版reservation SCRIPT ERROR仍在原失败日志中，没有被归档文字洗成正常业务拒绝。    

最终采用总量仍是**46直接＋8世界＝54唯一场景、53份framework回执、1409检查**。我读取了世界组8条runner结果，但没有逐份复验全部53个receipt或73次尝试。mutex拒绝明确为**0个原生场景启动**，不算8个场景失败，也不进入通过数。  

当前index备份记录保持 `df5a01…`，完整staged输出为 `58f820…`、39611条；同时继续明示历史 `66c505…` 连续性FAIL、原备份MISSING。**本轮新备份不修复过去的证据缺口，也不能据hash差异擅自认定代码丢失原因。**我读取了该记录，没有独立重算本地备份字节。

### 主控交接

> 支持关闭父版三来源音频clear后继续访问旧reservation，以及无票据双恢复clear后继续执行旧binding的具体缺陷。保留即时恢复的实际损失基数、来源身份校验、原HP authority、状态／receipt分离及78／26／24项成果。补一条统计反例：lifesteal写HP后的同步通知另行恢复，当前after−before会多计本条actual_healing；在原写点冻结只读结果，不新增HP写入或公式权威。17即时来源目前证明预留，不是17次真实执行；更广混合／词缀／符文／死亡子连锁仍继续施工。历史index连续性、原B、supervisor安全复用及设备／APK保持开放。

**实际审查范围：**读取新增handler与registry、authority、compiler相关校验、完整DamageBatch和EffectRuntime、Combat恢复入口、ActorRef／WorldContext、原Player恢复与生命转换段、三个核心测试及最终完整回执、父版多来源失败日志、最终runner相关记录和index／范围清单。**未运行Godot、改源码或HEAD/index、启动第二施工主控、解包逐项重算3692文件／Git映射／完整原生ZIP，也未将旧自然场景PASS外推为新lifesteal自然混合性能。**结论仅针对请求 **`heterogeneous-6ae8a441-20261004`**。
