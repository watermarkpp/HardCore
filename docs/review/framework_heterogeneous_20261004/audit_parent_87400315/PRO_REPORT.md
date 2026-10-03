# resource-consumption-87400315-20261004 独立复审

已直接核对固定 **`87400315b1accc87dc0592b091dbfcef876453d5`**，父提交确为 `6aab18ff1588b879e1fad659fba4b71fff6f6c75`。**本轮终态交付、排队取消解锁、接受前资源资格和单来源音频重入修复均有实际代码与最终回执支持，应保留。另发现一条多来源组合下的同步退休遗漏：首个cue回调清空runtime后，同一fact的后续binding仍会访问已清除的reservation。这个组合尚不能结案。**

以下定位均为**仓库源码原始行号**。本会话没有运行Godot；已有原生PASS与本轮新增的静态条件链分别标明。

## 一、优先补证／修正：多binding派发没有承接同步退休结果

### 当前可达的条件链

| 源码位置 | 实际行为 |
|---|---|
| `scripts/features/runtime/effect_runtime.gd` **L251–268** | `_deliver_fact()`逐个执行同一fact的bindings；只在进入函数时验证一次目标，后续没有重新检查本次派发是否已经退休。 |
| 同文件 **L296–306** | 先建立状态，再调用 `_presentation.start()`，因此音频通知发生时，这个fact尚在binding循环内。 |
| `scripts/features/presentation/presentation_port.gd` **L36–46** | 调用真实音频服务；若通知同步退休了原cue，则停止返回的旧请求并返回。这个单cue保护正确。 |
| `effect_runtime.gd` **L348–358** | `clear()`清除状态、receipts、批次和reservations。 |
| 返回 `_deliver_fact()`后的下一次迭代 | **L262**重新写入receipt，随后 **L265–266**直接访问已不存在的 `_reservations[admission_id]`。 |

因此，**单来源情况下返回后可以正常结束；同一fact有第二个合法来源时，会继续进入已经失去所有权的旧派发栈**，存在无效字典访问／脚本错误，并且可能已经留下新的receipt记录。不能仅以 `runtime.errors.is_empty()`判断没有问题，因为这里不是通过 `_error()`报告的正常拒绝。  

这不是需要新造玩法才能达到的来源数量：本SHA的 `resource_natural_registry.json` 已经正式声明 **rule、item、skill三个来源绑定到同一冰咆哮机制**。现有cue重入测试则沿用单来源烈火，在真实 `event_started` 观察者里调用 `runtime.clear()`；两项分别通过，**不等于它们的组合已经覆盖**。 

**分类：这是有明确触发前提的源码缺陷；本会话尚未取得该组合的原生RED，不称为自然UI已复现的新故障。**

### 最小原生反例

复用已有资源自然目录和单来源cue重入方法即可，无须30目标压力：

在隔离世界中，通过正式职业、装备和技能资格取得同一冰咆哮的三个binding，确认真实接受票据非空；只保留一个合法接收者。在**第一个带 `feature_effect_handle` 的实际音频通知**中一次性调用原 `runtime.clear()`，随后让原调用栈正常返回。

验收重点是：基础HP只提交一次；退休后不再产生第二、第三个cue或周期伤害；reservation、receipt、heap及音频句柄按终态排空；没有SCRIPT ERROR，预算scope正常关闭。不要补算尚未执行的状态／伤害，也不要重新提交原HP事实。

修正应识别**“本次派发已被合法退休”**后终止余下旧栈工作。只重读world generation不够，因为这里可以在同一世界内调用 `clear()`。应结合本批次既有reservation身份与派发有效性处理；**不能把所有缺失reservation都静默忽略，也不能把普通来源死亡／停用自动升级成清空runtime**，原 `until_expired`承诺仍须保留。

## 二、取消终态与排队锁：本轮原反例可以有界关闭

### 终态结果先脱离可取消集合，再通知续体

`feature_resource_preparation.gd` **L135–148** 先结束预算scope，再对本轮 `cancelled + finished` 全部执行 `_take_completion()`，最后才通知外部等待者。`_take_completion()`先从 `_requests`删除请求，因而B的失败续体再次取消时，不能再找到已经提交并等待交付成功结果的A。 

当前测试在 `_capture_other()`中真实加入了 `formal_again`与 `service_again`，不是只保留原“通知栈内取消”。最终**34检查PASS**逐项覆盖A仍返回成功、B失败在scope外恢复、外层通知重入拒绝及结果一致性。上一轮指出的这条具体窗口已有对应证据，应关闭。 

准确口径是：**本轮同一量子已经结束的结果先整体分离后交付**；不是将所有尚未完成的准备请求提前变成终态。

### 直接取消排队apply不会永久留下发布锁

`content_layer_registry.gd` **L131–138** 的 `_await_feature_application()`在返回时核对原sequence；只有仍属于该生产者的锁才会被清理，不能解锁较新的异步生产者。原应用回调未开始时，取消保持旧目录、人物和通知不变。

最终**14检查PASS**覆盖正式取消与service直接取消、旧候选不发布、下一次同步／异步发布可用以及队列排空。该场景没有修改业务数值或重新发放动作资格。 

## 三、资源资格和真实消费：已经超出“只准备未使用”，但不能外推设备效果

### 1. 缺资源在动作创建／批次claim之前拒绝

| 接入点 | 固定源码 |
|---|---|
| 已知cue及其资源闭包 | `feature_compiler.gd` **L103–107、L249–268**：检查机制所属模块及required依赖能覆盖cue所需路径。 |
| 动作配置 | `action_config_lease.gd` **L23–39**：验证typed lease，并逐组检查event bindings所需资源，再捕获配置。 |
| 资源内容而非仅类型外壳 | `feature_resource_lease.gd` **L53–63**：每个required路径必须由实际有效资源满足。 |
| 一次性批次资格 | `damage_batch.gd` **L35–44**：先验证bindings资源，之后才调用 `reservation.claim()`。 |

因此，合法但空的lease不会因为类型正确就取得required cue资格；错误资源也不会消耗原票据后才拒绝。原 `begin_release()`／`begin_plan()`的关闭、身份和一次性标志仍保留。    

最终**24检查PASS**实际检验了null／typed空lease拒绝，以及随后用原票据配正确资源仍能claim，且HP、MP、Root RNG不变。应保留这项资格修复，不需要重开此前容量设计。

### 2. 音频消费复用原服务，而非只检查一个AudioStream对象

`audio_runtime_service.gd` **L421–441** 的新入口要求原事件为EXACT单样本，持有stream的路径与该样本一致，再进入原音效偏好、准入和播放器池。停止时核对pool index、request serial和event ID，不凭旧pool位置停止新拥有者。原variant选择在单样本时直接返回0，不重抽随机样本。 

required cue实际建立原生Node2D并持有资源lease；`ignite_cue.gd` **L7–18** 使用内建程序绘制，不在绘制函数里读盘、解码或执行伤害。刷新没有重新起声，原状态终止沿既有presentation停止路径释放。 

最终普通cue场景是**29检查PASS**，单来源音频通知退休场景是**21检查PASS**。前者核对实际播放器持有确切stream、错误serial不能停止它、四次周期结算及终态释放；后者核对晚返回请求被停止、没有迟注册音频句柄。**这些成果不因第一节的多binding遗漏而失效。** 

但required程序cue、音频偏好和播放器池仍是不同层：音效关闭或池准入拒绝不等于取消伤害。当前证据支持headless中的真实节点／播放器调用，**不证明手机上的可读性、听感或GPU首次绘制开销**。

## 四、资源自然变体：141／10成果保留，性能名称需修正

新变体使用正式资源目录预先准备，在真实Player／Root输入和AI移动下运行；并非把三个binding直接塞入运行时。指定30目标各三来源的检查与实际cue、音频观察也分别存在。

我核对了最终live后段回执、cold完整回执和world runner：

- live **141检查PASS**明确检查指定三来源、实际消费迟到 **33333μs**、奖励 **512 XP**、required cue／确切stream及退出后资源退休；
- cold **10检查PASS**绑定本轮成功producer、同源码和独立run，核对正式恢复与奖励保持；
- 报告另记录峰90cue、126次确切stream起声、939次周期投递。**这些具体总量本轮未由我逐条重算原trace。**   

音频观察函数是对实际 `event_started` 回调中的播放器stream与状态持有的lease做 `is_same()`，不是只比较路径字符串；这一证明比“typed准备成功”更进一步。它仍只计实际已起声事件，不意味着音频偏好／池限制在所有工作负载下都不会拒绝声音。

**README中的“墙钟CPU P50/P95/P99/max”应改称“测试process回调的墙钟帧间隔”。**`natural_effect_lifecycle_test.gd` **L71–88** 实际记录的是相邻回调的 `Time.get_ticks_usec()`差，后面以 `wall_frame_usec`输出；不是CPU剖析器记录的工作耗时。原数字可以保留，不需要为措辞修改重跑，但不能用于宣称CPU耗时下降。  

同名建角守卫未改；变体使用独立名称并在失败时立即终止，能够避免后续夹具在建角失败后继续产生无关断言。原失败应保留，不能据此外推v97第二角色故障已经修复。

## 五、index连续性必须独立保持FAIL

`INDEX_CONTINUITY_BOUNDARY.json`明确记录：

```text
历史预期：66c505ce…
当前观察：df5a01dd…
staged entries：58f820e2…
historical_byte_continuity：FAIL
original_index_byte_backup：MISSING
原因：未建立
```

**这项不能因本轮专项通过而改成“真实index一直没变”。**后续观察绑定df5a01和现有stages，也不恢复过去的连续性证明；反过来，仅凭hash不同也不能断言已丢失用户代码或认定本轮修改就是原因。保留现场、不reset／restore未知旧字节，是当前材料所能支持的处理边界。

该问题与固定Git提交源码、受测内容及回执之间的对应关系属于不同证据维度。应同时保存，不用其中一项PASS覆盖另一项FAIL。

## 六、最终采用范围与交接

最终runner的 **43直接相关＋8world＝51唯一场景**可以对应起来；核心回执绑定最终 **`ad9681fc…`**，world各live/cold使用不同run ID。归档总数为50份framework回执、1281检查，131次尝试中的10次FAIL另行保留。**我抽对了相关runner和核心回执，没有逐份复验全部131次执行或1281项。**  

旧破坏性supervisor的安全复用缺口、Task4／5、GPU／Android、原v97B输入MISSING和主树／APK边界继续保持开放，不由这次音画消费专项关闭。

> **主控交接：**支持关闭上一轮“B取消续体改判A终态”及直接取消排队apply的锁泄漏，并保留34／14／24、普通cue29及单源重入21项成果。优先补一个现有能力组合反例：同一fact三来源，首个音频通知同步clear，返回后后续binding仍访问已清reservations。应终止已退休的旧派发栈，不回滚HP、不补伤害、不把普通来源死亡当clear。资源自然141／cold10成果保留；“墙钟CPU”改为帧回调间隔。index历史连续性继续FAIL且原因未建立，整体资源／RFC／设备／APK不结案。

**实际审查范围：**读取本轮资源准备／目录发布、Action／Batch资格、资源lease与registry、compiler闭包、presentation／cue、audio准备消费和池收尾、效果派发／退休相关代码；读取新增取消／cue测试、自然变体相关段、核心最终完整回执、自然live关键回执及cold、两个最终runner相关段和index边界记录。**未运行Godot、修改源码或HEAD/index、启动第二工程主控、解包重算3683文件／全部Git映射／媒体或原生ZIP，也未复用旧破坏性supervisor。**本结论仅针对请求 **`resource-consumption-87400315-20261004`**。
