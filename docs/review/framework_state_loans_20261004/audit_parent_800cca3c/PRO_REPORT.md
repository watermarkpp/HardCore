# periodic-retirement-800cca3c-20261004 独立只读复审

已核对固定 **`800cca3cdb7cf21bc0802ae2650d982ec6cc0c9e`**，父提交确为 `2b4ab20a142fe09117b9b996c2d85bc1d6d742f9`。**支持有界关闭本轮两项具体缺陷：周期HP回调退休后旧tick重新入堆，以及同一声明base slot存在未退休身体时仍能重复出生。已读范围内，未发现需要撤回本次修正或追加生产整改的新确证缺陷。**失败端口／替代state的更细组合、完整自然重生及 \(N\times S\) 状态复用证明，不能由这两项通过自动外推。

本轮完成了固定源码、ZIP成员、最终回执及运行关联的独立复算。**没有运行Godot、修改工程或真实HEAD/index，也没有启动第二施工主控。**以下定位均为仓库源码原始行号。

## 一、周期回调退休：修复发生在正确的所有权交接位置

核心在 `scripts/features/runtime/effect_runtime.gd` **L472–509**。

| 原始源码位置 | 当前行为 | 判断 |
|---|---|---|
| **L476–477** | 在调用HP端口前保存原state对象及 `_delivery_generation`。 | 保存的是本次tick实际执行上下文，不是返回后重新找到的同名状态。 |
| **L494–497** | 原HP端口返回后，同时核对代次、handle是否存在及 `is_same(_states[handle], state)`。 | clear、状态移除、同handle替代对象均不能被当作原调度所有者。 |
| **L498–503** | 失败仍计失败，但只有原所有者有效才 `_stop()`；成功仍累计实际损失及成功tick，随后才决定是否继续调度。 | 不回滚已提交HP，不因旧调用返回而停止替代状态，也不把实际成功投递漏记。 |
| **L504–509** | 只有所有权仍有效，才推进 `next_due`、检查终态或重新入堆。 | 原孤立heap节点的产生路径已经切断，不是通过修改 `has_work()`隐藏残留。 |

周期、到期、原RNG派生和伤害公式未被改变；变化只在原HP调用返回后的资格重验。

### 原生反例与最终结果确实对应

`periodic_callback_retirement_test.gd` 使用真实Enemy四参数周期方法override：先执行 `super.take_feature_periodic_damage()`，再一次性clear同runtime并尝试嵌套公共pump。它没有先修改HP或伪造receipt，也没有把clear挪到周期调用外。

我比较了该测试RED与GREEN的受测源码清单：**差异仅为 `effect_runtime.gd`，32项测试字节相同**。RED的四条失败分别是带／不带ticket两条路径中的heap残留与后续mismatch；首次5HP损失、成功投递计数和嵌套pump拒绝本来就通过。最终32项全部通过，包含：

```text
首次实际损失5、成功tick及delivery各增加1
→ 原state／heap／cue／owner清空
→ 嵌套pump返回0
→ 原预算scope关闭
→ 再过一个原period不再写HP、没有heap mismatch
→ 退休完成后可以重新configure
```

因此，父轮指出的这条具体生命周期缺陷可以关闭；四条RED失败不是四个互不相关的生产故障。

### 仍需准确区分的证明深度

本轮原生反例走的是**成功HP调用之后clear**。新增代码对“失败返回不能误停同handle替代state”的处理有明确静态依据，但32项没有独立构造失败返回或同handle替代对象。

这不构成新的实现缺陷，也不要求为本轮关闭再改生产代码。若后续要把这两个分支也标成原生闭环，最小补证是在同一夹具中分别制造“原state被替换后成功返回／失败返回”，检查替代state不被旧调用推进或停止。不能用目前的clear正例代替这两种原生结果。

## 二、出生槽守卫：阻止重叠身体，但保留queued替代出生

### 前置位置与作用范围正确

`game_root.gd` **L5023–5029** 在 `_runtime_spawn_serial += 1`、Enemy分配和注册之前检查：

```text
有明确slot
且不是summoner子出生
且本Root当前代次仍有该slot的未queued身体
→ occupied_base_spawn_slot，直接拒绝
```

这避免了“拒绝了第二个返回值，但serial、空间索引或新身体已经发生变化”的半次出生。原投影合法性检查仍在更前面，原政策解析和factory主体仍在后面。

`_spawn_slot_is_alive()` **L14785–14794** 的新 `owned_only=true` 路径使用本Root直属子节点，匹配slot和world generation，并排除queued节点。默认调用仍保留旧的enemies-group检查，没有把所有调用者都换成新的身体保留语义。

实际factory在 **L5164、L5172、L5187** 先写slot／generation，再将Enemy作为Root直属节点加入。因此，当前登记方式与新的查询范围相符。新guard不查看别的Root子节点，也不要求已经queued的旧身体真正完成内存析构后才能创建替代者。

### 为什么只查enemies group不够

原Enemy真实致死时会立即推进life、清collision、移出enemies group，随后deferred完成死亡。该身体在此期间仍可能存在且尚未queued。

本轮早期group版本通过9项活体重复测试，但扩展到死亡窗口后仍有1项失败；最终改为实际直属身体检查后，同11项通过。**这个演进说明最终守卫保护的是尚未退休的身体所有权，而不是把零HP身体重新视为可被攻击目标。**死亡碰撞即时清除的原逻辑没有改动。 

最终11项检查覆盖了：

| 场景 | 实际断言 |
|---|---|
| 同槽已有活体 | 第二次出生返回null；serial、group数量、原HP及世界上界保持。 |
| 真实致死、身体未queued | 已清碰撞，但再次同槽出生仍拒绝，serial不变。 |
| 旧身体queue_free后、尚未等下一帧 | 新life可以立即通过原factory创建；原ActorRef不可用，世界槽位上界不增长，新对象身份不同。 |

这些结果支持当前窄边界。

### 没有证据要求放松原guard，但不能称完整重生时序已测

新测试采用 `respawn_enabled=false` 的明确测试slot，主动执行死亡／queue_free／再出生；它不是等待完整自然respawn政策到期的测试。原 `_respawn_later()` **L14745–14772** 的Timer、wakeup资格和代次判断未改，召唤子槽也继续绕过这个base-slot专用检查。 

因此，当前可以确认**合法queued替代没有被挡住**，不能扩大成所有异常长尸体、跨图、自然respawn到期交错均已运行验证。

另外，新的owned检查会枚举Root当前子节点。它解决身份上界前提，不等于已证明高频出生时的最坏扫描成本；本轮没有据此取得额外性能结论。

## 三、\(N\times S\) 仍不能由这次出生修复推出

本轮只补齐了一个必要条件：

> 同一当前base slot不能同时拥有两个未queued的正式身体。

但旧身体queue_free使ActorRef立即失效，**不代表引用该旧life的所有状态、待派发事实和资源lease已经同步终态**。新life允许出生后，这些旧状态仍可能等到原调度边界才被清理。当前周期代码也明确是在处理状态时判断target是否失效。

所以，后续从累计 \(F\times S\) 改为驻留 \(N\times S\)，仍需证明旧life状态尾部与新life槽位交接；A/B刷新时多个root持有、credit及累计tick身份配额也仍是独立问题。**本轮没有修改 `child_capacity_proof.gd` 或开放periodic-child编译合同，我核对了它们与父版字节相同。**不应把这些待实现范围写成这次修复失败，也不能提前写成容量证明已完成。

## 四、地图policy FAIL必须保留，父控制不等于全父基线

我读取了两次 `monster_formal_respawn_policy_audit_test` 的原始失败记录和测试源码。该测试直接调用Bridge、Policy和WorldState，并不实例化GameRoot；失败包括缺失policy及政策身份／旧预期差异。日志尾部的：

```text
formal_ordinary_slots_requiring_authored_policy=203
```

是**汇总数量203**，不是“地图ID203”。不能把这一字段误当成具体地图定位。

`RESPAWN_PARENT_CONTROL.json` 记录仅将Root恢复为父版精确字节，原生仍退出1；我核对了控制阶段的Root哈希确实等于父受测Root，运行前后内容稳定，随后归档中的候选Root又恢复为本轮精确字节。

这支持两个结论：

**该policy FAIL没有证据归因于本次Root出生guard；但该数据门禁本身仍未关闭。**控制不是全父checkout，也没有为修正地图数据／旧预期提供最终裁决。原FAIL、原日志和单文件控制范围均应保留。

## 五、1420检查的变化可以解释，但360应写成门禁而非实际总量

我独立比较了父版和本轮的原 `natural_effect_lifecycle_test.gd`：字节相同。再比较resource-backed两份完整回执，得到：

| 项目 | 父阶段 | 本轮 |
|---|---:|---:|
| 完整检查数 | 141 | 139 |
| `world death signal is unique`检查次数 | 34 | 33 |
| 按实际唯一死亡计算的XP | 512 | 497 |

每个观测到的死亡确实追加两项检查，所以少一个额外世界受害者，恰好少两项；固定30个测试目标仍全部存在。整体计数为：

\[
1379+32+11-2=1420
\]

与本轮实际完整回执总数一致，不是把理论加算1422强行改成1420。

还有一个措辞应保持精确：脚本 **L228–246** 要求指定30目标各3个来源，并检查：

```gdscript
runtime.metrics().ticks >= 360
tick_delivery_count == ticks
```

因此自然场景中的360是**至少360次实际成功周期投递的门禁**，不是“该自然场景恰好总共执行360次”。本轮没有删减该门禁，也不能把额外世界死亡数减少或检查数减少称作性能优化。

## 六、本次独立复算与采用记录

本次从固定Git对象读取，并在内存中解包计算；没有用正在施工的工作树文件替代本SHA。

| 核验对象 | 独立结果 |
|---|---|
| 3746份受测源码 | 逐文件SHA256一致；重算内容指纹为指定 `d94ee4b4…`。 |
| Git／受测字节映射 | **867 exact、2879 CRLF-only、0其他差异。** |
| 6项source delta | 恰为2个生产文件及2个新测试脚本／2个场景文件。 |
| 源码ZIP | **3750成员**：3746源码＋3原媒体＋RFC；附加成员与父／当前Git原字节一致。 |
| 原生ZIP | **315成员**逐项大小、SHA256及固定Git字节匹配。 |
| 观察index ZIP | 两个成员大小／哈希匹配；仅核验，未恢复或重建。 |
| source-only diff-check | 本次实际返回0。 |

三个ZIP整体哈希也已独立重算，均与清单一致：

```text
TESTED_SOURCE.zip
15818972 bytes
453d0184031bf0fe90724e94781e98a1be4969e66c94bcb553c051a3dfa2ef1d

NATIVE_EVIDENCE.zip
4361931 bytes
6d9e9f894087bb38436fafcbdbd397a42a7fef6a2acd782d10c8e1ac64f3a449

INDEX_OBSERVED_BYTES.zip
2575546 bytes
1fe862794a3c16c2e3e471b95b58396f2654e5ad4867a38e0817e48cb6aa6de6
```

### 最终原生关联

| 最终组 | 唯一场景 | 完整framework回执 | 检查数 | 上限 |
|---|---:|---:|---:|---:|
| DIRECT | 37 | 31 | 1028 | 30秒 |
| WORLD | 8 | 8 | 392 | 60秒 |
| **合计** | **45** | **39** | **1420** | — |

逐份检查了39个receipt的编号／计数、布尔结果、scene、run、invocation、source和实际APPDATA／user_data_dir，并核对runner、原生PID关联及handoff回执哈希。最终各场景退出0、无timeout，两个组的before／after源码集合与引擎文件哈希一致。六个普通场景仍按原runner合同验证，没有补造framework receipt。

本轮实际invocation为：

```text
DIRECT
7e64d672-dcec-4082-807e-e454d38d02b4

WORLD
a8e6b95c-7733-452e-8b82-291626fc3d79
```

两个新专项的最终run分别为：

```text
周期退休32项
c8adbfbb-7a6c-437b-b1fc-59f00cf93587

出生身份11项
3c3b978a-312f-49dd-bbf6-448234952451
```

均与完整原生回执对应。六对旧业务live／cold的指定producer、同轮source及独立cold run也已核对；**它们不构成尚未开放的周期子链cold证明。** 

64次原生尝试逐行对应 **58 PASS＋6 FAIL**。六条FAIL包括周期反例、活体重复出生反例、两次死亡身体窗口失败，以及候选／父Root控制下的policy audit失败；均保留原标签。最终18份stderr仍有ObjectDB告警，其中两份canonical各10个，其余各8个，不声明零告警或长期内存证明。

父小可爱请求的归档状态仍是**终态FAIL／完整报告MISSING**，不是双审计通过。本轮读取了该记录，没有自动重发旧请求。历史index连续性FAIL和旧原件MISSING也不因当前观察ZIP核验通过而恢复。

## 主控交接

> 支持有界关闭周期回调clear后旧tick重插heap，以及同base slot未queued身体重叠出生。32项保持原实际HP／成功统计／scope收尾，11项保持拒绝前无serial变化和queued后合法替代。未发现新增确证生产整改项。失败端口与同handle替代state目前主要是静态保护，不冒称已单独原生复现；完整自然respawn与 \(N\times S\) 仍未由出生guard证明。地图policy原FAIL和单文件父控制保留。自然360是至少投递门禁，检查少2来自额外世界死亡少1，不是优化。45／39／1420及全量字节关联已复核，不批准主树或APK。

**实际语义审查范围：**两个生产增量、原周期HP／状态／heap收尾、Root factory与死亡／respawn相关调用、两份新测试、policy测试及控制记录、最终原生回执与关联。字节和计数完成上述全量复算，但**未对3746文件进行全仓语义验收，未执行Godot或故障supervisor，未审查未推送的状态池候选，也未重新裁定实时工作树的跨时段保护历史。**本报告仅针对 **`periodic-retirement-800cca3c-20261004`**；Task3／4／5、自然P6R3、原v97 B、掉电、Android／GPU及APK继续分项开放。
