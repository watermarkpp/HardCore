# child-chain-admission-2b4ab20a-20261004 独立只读复审

已核对固定 **`2b4ab20a142fe09117b9b996c2d85bc1d6d742f9`**，父提交确为 `1f6ca7a78e2163c3365bbcb38710018e6eee4dbf`。**本轮活根容量持续记账、公共pump单消费者保护和Root真实结果传播，均有源码与原生反例支持，可以按指定范围关闭。另发现一处相邻的既有生命周期缺口：普通周期伤害回调中clear后，旧tick仍可能重新登记已经退休的heap节点。该路径尚未在本会话原生复现，不是本次改动新引入的回归。**

```text
REQUEST
child-chain-admission-2b4ab20a-20261004

REVIEWED_SHA
2b4ab20a142fe09117b9b996c2d85bc1d6d742f9

PARENT
1f6ca7a78e2163c3365bbcb38710018e6eee4dbf

TESTED_CONTENT
572286d5c4b82eeae9e9cb270b98c136e264ad47565f051b474d137ae0981ea3
```

以下定位均为**仓库源码原始行号**。本轮没有运行Godot、修改工程或真实HEAD/index，没有启动第二施工主控；源码及归档复算使用固定Git对象，不读取未推送候选代替本SHA。

## 一、活根容量持续记账：原部分排空漏洞已堵住

核心改动位于 `scripts/features/runtime/effect_runtime.gd` **L361–371**：每次从队列取出一个属于活链的fact，在 `_pending -= 1`之后，**立即**给原root的 `facts`及全局 `_reserved_facts`各加1，然后才进入handler及其同步观察者。整批结束处不再重复退款。

因此，在原root仍活着、尚可能执行后续分支时，普通事实消费保持：

\[
\Delta(\text{pending}+\text{reserved\_facts})=-1+1=0
\]

这个不变量不仅在整批结束后成立，也在实际治疗／音频等同步回调期间成立。`reserve_action()`仍用当前pending与reserved之和判断新承诺，没有把“刚消费但仍归原root所有”的槽位借给后来者。

### 8160反例的计数对应正确

本轮夹具的算式是：

| 观察点 | pending | reserved facts | 合计 |
|---|---:|---:|---:|
| 根85 facts已提交，另持94份85-fact票据 | 85 | 8075 | 8160 |
| 已消费53，尚余32 | 32 | 8128 | 8160 |
| 原批85全部消费完、根仍需执行child | 0 | 8160 | 8160 |

此时再接纳85份事实会达到8245，超过原8192空间，所以必须在新的HP／资源变化前拒绝。最终回执还检查原已接受child仍能造成10点实际损失、完成转移，关闭94份未使用票据后全部退休。**不是只验证“新竞争者被拒绝”，却漏掉原承诺是否仍能兑现。** 

正确的证据范围仍是：根的85份事实中，84份来自同一个存活目标的真实HP变化；94份票据来自受控runtime API。它证明容量账本，不证明85个唯一目标命中，也不代表自然Player连续94次起手。重复目标的实际HP事实与按目标／release去重的附加效果，不能混成同一个计数单位。

## 二、单消费者及Root结果传播：三项原缺口与兄弟补证均成立

### 1. 公共pump的所有权覆盖到预算scope结束

`effect_runtime.gd` **L333–359** 现在在入口检查 `_pumping`，进入外层消费后才置为true；同步回调再次调用公共 `pump()`立即返回0。每个量子结束后先调用 `Budget.end()`，再检查派发代次；最终由原外层调用清除 `_pumping`。

`configure()` **L47–52**、`configure_child_executor()` **L71–73**同样检查 `_pumping`。`clear()` **L565起**可以撤销工作并推进代次，但不会把 `_pumping`清掉，从而不能在外层scope尚未结束时重新开放第二个消费者。

这解决的是**同步重入**，不是创建线程锁，也不是将所有内部方法都改为可随意公开调用。容量夹具直接执行 `_dispatch_one_fact()`仍是明确的测试观察方式，不能由此把内部入口当作新的生产调度API。

真实Player恢复通知反例最终检查了嵌套pump返回0、外层死亡订阅仍产生一次child、根与receipt最后排空。新增兄弟分支还在第一个child未封口时重入pump，观察到最多一个producing分支；后续兄弟仍能执行。 

### 2. Root不再把“HP端口成功”直接当成“事实转移成功”

`game_root.gd` **L14957–14977** 现在返回明确结果：

| 情形 | 返回 |
|---|---|
| 没有feature batch | `success=true / not_applicable` |
| 封口或batch自身错误 | `success=false / rejected` |
| 原batch owner已退休 | `success=false / owner_retired` |
| 合法空批次 | `success=true / empty` |
| 非空批次提交完成 | 按真实提交结果返回 `transferred`或`rejected` |

`effect_reservation.gd` **L37–40** 查询的是batch当前所有权，不把原action ticket已关闭误解为batch也已经丢失所有权。runtime再检查世界和producing／queued分支阶段。

子执行 **L15020–15023** 将上述返回值纳入最终 `success`，不再只看目标HP调用与 `batch.errors`。没有回滚HP，也没有新增planner或writer。 

本轮受控Root在实际child HP和capture之后、转移之前clear，最终验证HP不回滚、Root返回失败、成功child计数不增加。**这直接补齐了父报告所指的结果传播缺口。**

另须准确理解 `child_actions`：兄弟场景中一次为合法 `empty`，另一次为 `transferred`，两者都算成功完成的child执行，所以计数2**不等于两次实际伤害命中**；目标实际少20HP由另一条断言检查。

### 3. RED/GREEN没有被混写为一份最终字节结果

我核对了正式35项RED的7个失败，以及35项GREEN全部通过。早期34项／8FAIL多出一个“夹具实际槽数不是预期85”的失败，不能用它替代修正前置条件后的有效RED。

最终加入兄弟分支后，该专项是 **44检查PASS**。兄弟分支没有同断言的独立旧版RED，报告明确承认这一点，处理正确。35项RED到GREEN的源码差异还包括fixture返回签名适配和临时compiler修改的撤回，**不能宣传成只有一行代码变化的单变量实验**；三个生产修复的因果解释仍由具体调用链和对应断言支持。 

## 三、新增审查发现：clear后旧周期tick可能留下孤立heap节点

**分类：有明确条件链的既有生命周期缺陷；本会话未运行新原生反例。它存在于普通ignite周期路径，不需要等待“periodic→death→child”开放，也不是本次三项修复新引入的回归。**

### 发生在外层单消费者保护以内

当前 `effect_runtime.gd` **L472–502**：

```text
取出due handle与state
→ 调用真实Combat周期HP端口
→ HP端口及同步观察者返回
→ 更新本地state的ticks／next_due
→ 目标仍可解析且尚未到期时，把handle重新放回heap
```

**L493** 的伤害调用之后，没有重新检查派发代次，也没有确认该state仍在 `_states`中。`clear()`则会在观察者中删除全部state和heap。只要目标本身仍存活、世界身份不变，返回后的 **L502** 仍会 `_heap.put(handle, next_due)`。

外层pump虽然在 `Budget.end()`后发现代次变化并退出，**检查时旧tick已经把节点放回去了**。结果可以是：

```text
active_count == 0
heap_count == 1
has_work() == false
```

因为 `has_work()`当前只看pending、states和reservations，不看heap。后续显式推进到due并pump，才可能报 `feature_heap_state_mismatch`。这证明的是退休后残留和调度状态不一致，**不能据此声称发生了第二次HP写入或奖励重复**。

Combat端口在目标方法返回后使用原写点receipt返回成功；它不会替EffectRuntime判断刚才是否被clear。该分层本身合理，所有权重验应由runtime完成。

### 最小原生反例

复用已有 `periodic_effect_boundaries_test.gd` 的 `ObservedEnemy`四参数override。在第一下真实周期伤害的 `super.take_feature_periodic_damage()`返回后，一次性调用同runtime的 `clear()`；不改HP、不销毁目标、不推进世界代次。

沿用原1秒周期和高HP目标，要求：

> 首次实际HP损失保留；原tick调用返回后state、heap、cue及owner均排空；再过一个原period不发生新HP写入、heap mismatch或重复终态；预算scope正常关闭。

还可在clear后立即尝试一次嵌套pump，验证它确实返回0——这能同时说明**没有第二消费者，不代表原消费者剩余代码仍有资格重新登记状态**。现有测试只在周期调用之外换世界，未覆盖这个窗口。

最小修正不应改period、恢复已clear的状态或回滚已提交伤害。应在伤害端口返回后，确认**原派发代次及该state的当前所有权仍有效**，才推进后续调度；已经成立的实际损失按原统计口径保留。不要仅把 `has_work()`改成包含heap，掩盖孤立节点的产生。

## 四、关于下一步 \(N\times S\) 状态驻留复用：三个必须补的证明条件

以下是基于本SHA的**后续研究候选**，不是对未推送实现的审查，也不把正在施工的周期fixture判成已完成。

### 1. 同时活怪上界不自动等于“尚未退休状态”的life上界

当前 `world_target_bound.gd`保留声明槽，允许旧life退出后新life继续占该槽。状态则只有在 `_tick_one()`发现目标失效或其他明确 `_stop()`路径中才退休。

因此，若旧life死亡后状态仍等待处理，新life已经在同槽受击，**两个life的状态存储可能短暂并存**。从合法活怪数 \(N\)直接推出全部状态存储不超过 \(N S\)，还缺这段交接证明。

最小场景是：同一声明槽的旧life带状态死亡，在旧状态终态处理前生成新life并请求新状态。必须证明槽位转移与旧状态、已提交死亡fact／子命令的所有权交接一致；不能为腾空间提前删掉尚未移交的死亡派生资格。

### 2. 一个状态handle不等于只有一个根owner

当前刷新路径 **L438–451、L517–521** 会把新root加入 `chain_owners`，但仍保留原state及command。反复A/B刷新可以让一个可见状态关联多个被接受根，直到该状态终态才统一减引用。

因此，“状态节点数量降为 \(N S\)”不自动证明根reservation、future child额度、credit与资源lease也有同样上界。需要至少分别测试：

- A提供较强伤害、B只延长到期；
- B增强伤害后，A是否仍有未结束的生产资格；
- 同一handle连续被多个root刷新、撤来源及换life。

**谁对下一次致死事实及其credit负责，需要在既有语义下明确，不能通过释放较旧root来暗中裁决。**本SHA保守保留owner不等于泄漏已证明；未来减少保留范围也不能只凭“现在屏幕上只剩一个状态”。

### 3. 驻留节点上界与累计周期工作、去重身份要分账

当前 \(F\) 的有限链计算与状态成本使用的是保守累计模型。未来周期端口开放后，还需证明：周期生产次数、刷新后的剩余tick数、真正致死tick的身份，以及派生分支的累计承诺如何进入同一账本。

尤其当前 `_deliver_fact()`在调用handler之前登记按release／target／binding区分的receipt。若未来多个周期事实直接复用同一个release身份，必须证伪“较早非致死tick先占用receipt，真正致死tick被去重”的情况。**这是未来接线的身份条件，不是本轮已经开启并失败的周期行为。**

三个条件都应在原接受边界和真实终态交接中证明；不能以TTL/LRU清理资格、提前冻结释放目标、增加30上限或修改周期来取得容量结果。

## 五、未完成周期记录与最终证据没有混用

本轮四个周期准备文件仍在源码包中，但不在最终采用PASS场景中。我核对了相关原始记录：

| 阶段 | 本轮应保留的解释 |
|---|---|
| 错误registry字段／缺 `max_ticks` | 先决夹具不完整，不能当成已经触达生产周期功能的有效RED。 |
| 修正输入后的正式目录拒绝 | 原日志明确为 `unsupported_trigger_chain`，属于真实功能未接通。 |
| 临时开放compiler后的85槽接受失败 | 原日志明确为 `child_state_capacity`，属于实际接受前容量拒绝。 |
| 最终固定源码 | compiler与父版精确字节相同，实验开放已撤回。 |

我对 `feature_compiler.gd`做了父子原字节比较，哈希均为：

```text
29791c9a603a5fa9c5cba1ed6b5712a6274e388cf0fc563d5f67eac5fdddacce
```

因此，**42场景PASS不能用于关闭这条未开放链，原5次周期阶段FAIL也不因保留文件而变成最终采用失败或成功。**

同样，当前代码仍优先处理fact／due，最后才处理child；持续输入下child服务年龄与完整子动作最坏量子成本仍未证明。它们是既定待测项，不是本次容量修复已经完成的性能结论。

## 六、本次独立复算范围

本次从固定Git对象读取并在内存解包核对，完成了下列检查：

| 对象 | 独立结果 |
|---|---|
| 3742份受测源码 | 逐文件SHA256匹配，重算内容指纹为指定 `572286d5…`。 |
| Git／受测字节映射 | **863 exact、2879 CRLF-only、0其他差异。** |
| 12项source delta | 与父受测清单和本轮前后哈希对应；三个生产文件之外为测试及作者数据。 |
| 源码ZIP | **3746成员**：3742源码＋3原媒体＋RFC；附加成员与父／当前Git原字节一致。 |
| 原生ZIP | **306成员**大小、SHA256及固定Git归档字节全部匹配。 |
| 观察index ZIP | 两个成员大小与哈希匹配，只读，未恢复或重建。 |
| source-only diff-check | 本次实际返回0。 |

三个ZIP整体大小与SHA256也已独立重算，与归档一致：

```text
TESTED_SOURCE.zip
15813384 bytes
784983a2e0384d5a5ceddd4f26aa0cc0aa8ce856ffdda35497668ef0f333b0a4

NATIVE_EVIDENCE.zip
5099346 bytes
4f5b189972e9194a38b1a0da88f7d94753a8171e8e26869b39f840260fbfaf03

INDEX_OBSERVED_BYTES.zip
2575546 bytes
1fe862794a3c16c2e3e471b95b58396f2654e5ad4867a38e0817e48cb6aa6de6
```

### 最终原生关联

| 最终组 | 场景 | 完整framework回执 | 检查 | 上限 |
|---|---:|---:|---:|---:|
| DIRECT | 34 | 29 | 985 | 30秒 |
| WORLD | 8 | 8 | 394 | 60秒 |
| **合计** | **42** | **37** | **1379** | — |

本次逐份核对了37个receipt的检查编号／计数、通过状态、scene、run、invocation、source、原生PID和APPDATA／user_data_dir，并与runner、handoff回执哈希对应。最终各场景正常退出0、无timeout；两组before／after源码集合与引擎文件哈希一致。五个普通场景依原runner合同验证，没有补造framework receipt。 

本轮实际invocation为：

```text
DIRECT
068b04ed-a0e4-4cee-bc89-a4c2adf5f4f9

WORLD
6435d0e5-7ada-49f5-bdb0-b887d7b18352
```

六对原业务live/cold的expected、指定producer、成功handoff及独立cold run/PID均已核对；**它们不是未接通周期子链的cold证明。**

58次原生尝试逐行对应 **51 PASS＋7 FAIL**。另一次请求不存在路径的wrapper失败发生在场景启动前，保持 **0 native**。最终17份stderr仍有ObjectDB退出告警：两份canonical各10个，其余各8个；不宣称零告警或长期内存上界已验证。

**更正父报告：**我上一份正文写出的WORLD invocation不正确。此次读取父 `FINAL_RUN_ASSOCIATION.json`确认权威值为 **`8aa110f5-6f87-4f04-9cd4-0eac3618cad4`**；原错误文字不应作为身份凭据。本轮只采用当前原始记录的UUID，不回填或修改旧独立正文。

历史index连续性FAIL、旧原件MISSING继续独立保留。当前观察副本哈希正确，不恢复过去的连续性证明；本次也没有重新裁决正在施工的主树／第二树现场跨时段状态。

## 主控交接

> 支持关闭本轮三个指定缺口：活根fact槽逐条归还、公共pump单消费者、Root真实转移／空／退休结果传播。有效35项RED7FAIL与GREEN、最终44项及兄弟补证均保留。新增相邻P2建议先原生证伪：普通周期HP回调clear后，旧 `_tick_one`仍可重插已退休heap句柄；这是既有路径，不是本次新回归，也不依赖未开放周期子链。修复应重验返回后的state所有权，保留已提交HP。下一步 \(N S\) 证明必须覆盖旧life尾部、A/B多根持有和周期fact／去重身份，不能只数活怪或状态节点。全量字节与42／37／1379关联已复核，周期及全工程／设备/APK仍开放。

**实际语义审查范围：**三个生产增量及其批次、票据、预算、周期HP和heap依赖；新增容量／重入／退休／兄弟测试、相关周期边界测试和原失败记录。字节与采用记录按上节完成全量复算，但**没有对3742文件进行全仓语义验收、没有重新执行Godot或故障supervisor、没有审查未推送的周期候选，也没有批准主树合入或APK。**本报告仅针对 **`child-chain-admission-2b4ab20a-20261004`**。
