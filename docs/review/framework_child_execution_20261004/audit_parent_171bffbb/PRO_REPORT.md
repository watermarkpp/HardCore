# child-planner-171bffbb-20261004 独立只读复审

**本轮发现一项新增 P2：未映射的负地图 ID 可以让 child 计划绕过 STRICT_V2，仍被 canonical planner 标记为 accepted。**这是源码确认的纯规划合同缺口，尚未在本会话原生重放；不能描述为已经发生的游戏伤害故障。

其余重点中，**父报告的错误直接入口 P2 修复、Combat 错误投影后的同批次恢复，以及合法映射下的子动作规划接入，可以按范围采纳。**本次还完成了源码、ZIP、完整回执和原生关联的独立重算，不再沿用上轮“未逐文件复算”的审查限制。

```text
REQUEST
child-planner-171bffbb-20261004

REVIEWED_COMMIT
171bffbb69aa7d59b7f0ab30238e8032d67a6ad7

PARENT
5b8288f773d0659b2d1e45538f93fc9a2556dfba

TESTED_CONTENT_SHA256
bad34a5317297c53c3f827dd208efdc482f2b35a868c4efa2fee0e3a0ca2e673
```

Git 提交父关系与请求一致。本次也读取了固定提交中保存的两份父报告及其来源记录，但以下结论依据的是本轮源码与证据，不用父报告替代本轮审查。**本会话没有运行 Godot，没有修改源码、工作树、HEAD、index 或存档，没有启动第二施工线程。**  

## 一、新增 P2：child 的负地图 ID 会落入原未映射兼容分支

### 问题位置与完整路径

`ChildActionLease.planning_context()` 的**源码 L94–112**检查了地图字段是整数，并且等于命令所持世界的地图，但没有检查它是非负的有效映射 ID。因此，当世界、命令和规划上下文都持有 `runtime_map_id=-1` 时，这里的相等性校验仍会通过。

这不是必须篡改内部私有字段才能构造的输入。原 `WorldContext.capture_world()`直接读取世界 owner 的 `current_map_id`；`matches_world()`只检查当前快照非空、与传入身份相等，没有拒绝负地图 ID。使用现有测试风格的世界 owner，并令其 `current_map_id=-1`，即可通过正常接口获得这份世界身份。

随后形成以下路径：

| 环节 | 固定源码的行为 |
|---|---|
| `ChildActionLease.create()` | 命令其余字段合法、父世界与当前世界一致时，没有因地图为 `-1`而拒绝。 |
| `planning_context()` | 地图整数类型和相等性成立；有效双向 converter 可以正常完成原点投影检查。 |
| 同一 canonical snapshot builder | 按现有 circle 分支生成绝对坐标快照，其中地图 ID 仍为 `-1`。 |
| `SkillExecutionPlanContract._snapshot_valid_for_context()` | 认为 `expected_runtime_map_id < 0`是未映射上下文，进入旧兼容分支。 |
| 旧兼容分支 | `has_legacy_base_contract(snapshot)`成立后直接返回 `true`，没有执行 STRICT_V2。 |

关键是原计划合同**源码 L780–782**：

```gdscript
if not runtime_map_bound:
    if SkillFootprintSnapshotScript.has_legacy_base_contract(snapshot):
        return true
```

这是原玩家 home／未映射测试保留的兼容语义，不能直接等同于新 child 的严格映射合同。

与之相对，真正的 STRICT_V2 校验在 `skill_footprint_snapshot.gd` **源码 L976–982**明确拒绝绝对坐标快照中的负地图 ID，报告 `absolute_missing_runtime_map_id`。因此，这条路径会出现：

```text
canonical plan.rejection.accepted = true
但该计划的 canonical_snapshot 不满足 STRICT_V2
```

这是沿固定源码得出的反例结果，**不是我新增运行取得的原生输出**。

### 最小反例与修复边界

复用 `feature_child_planner_test.gd`现有 `_command(world)`、`_context(release)`和合法双向投影，在独立 fixture 中让世界自身的 `current_map_id=-1`，再创建命令与 child request。其他字段保持合法，子 release 仍与根、父 release 不同。检查应当要求：

> 工厂直接拒绝，或者 canonical 计划拒绝；任何被接受的 child 计划，都必须通过 STRICT_V2。

当前44项测试覆盖了“另一个正地图”“缺失 converter”“外来世界”“旧快照覆盖”等情况，**没有覆盖世界本身就是负地图、且所有地图字段相互一致的反例**。

最小整改应限制在 **child 输入边界**：拒绝未映射的负地图 ID，并补上述原生 RED／修复后 PASS；合法地图的原44项保持通过。**不要全局删除原 canonical 的 home／未映射兼容分支，也不要为 child 新建另一套 planner。**

这项 P2 阻止的是“child accepted 必然满足 STRICT_V2”的完整关闭，不推翻已成立的合法映射正例，也不把尚未接入的真实游戏链判成运行故障。

## 二、父 P2 与投影恢复补证：本轮修复成立

### 错误入口现在绑定实际 STRUCK 语义

本轮 `enemy.gd`的生产增量非常窄：在已有合法 chain batch 分支中、正式投影预检和 HP 处理之前增加：

```gdscript
if causes_struck and damage_context.get("source_class") != "direct":
    return
```

因此，正确的 periodic／child batch 即使附带同类别 label，也不能通过固定具有 `causes_struck=true`语义的 `Enemy.take_damage()`冒充正确周期／子伤害入口。若反过来把 label 写成 direct，又会与批次内部类别不符，被后续批次校验拒绝。没有新增 HP 权威，也没有把旧空链 direct 路径改成新合同。

### RED→最终采用版本具有单变量源码对应

我独立比较了：

```text
child_planner_entry_class_red_124108_522428 的受测源码清单
vs
最终 bad34a53… 的受测源码清单
```

**差异只有 `scripts/enemy.gd`。**RED 使用的 Enemy 受测字节与父版一致，68项测试本身与最终版本一致。归档结果为 **68检查／8FAIL → 68检查／0FAIL**。这足以支持此次窄修复，不是将其他改动后的通过结果笼统归因于这一行。

八项失败包含错误入口后的 facts、资格和恢复提交连带失败，**不能说成八个独立生产缺陷**。本轮README也保持了这一分类。

### 同一个 batch 的拒绝后恢复确实得到验证

测试**源码 L151–180**分别对 periodic、child执行：

```text
合法 batch
→ 错误进入 take_damage：HP、攻击计时、actor RNG、facts、errors不变
→ 破坏投影，经正确Combat端口调用：独立RNG、HP、facts、errors不变
→ 恢复合法投影
→ 同一个batch经正确端口提交一次，实际损失30、恰好一个fact
→ 真正死亡立即清除碰撞
```

这补齐了我父报告提出的跨 Combat 投影恢复检查，而不是重新创建一个批次掩盖资格被消费的问题。原 Enemy 四参数周期接口、Combat 五参数周期接口没有被迫迁移；立即撤碰撞仍沿原死亡权威完成。

**结论：父 P2 的这一具体入口分类问题可以关闭，投影恢复补证也可采纳。**

## 三、子动作复用同一正式 planner，身份与内容冻结基本成立

### 没有另建 planner，也没有伪装成第34个玩家技能

新增工厂 `SkillRuntimeRouter.create_child_request()`只创建 `ChildActionLease`拥有的输入。真正规划仍走：

```text
SkillRuntimeRouter.build_canonical_plan
→ 原 _plan
→ 原 SkillExecutionPlanContract.build_canonical_plan
→ 原 release snapshot builder
```

新增的是 `_plan`内部的 `child_action`分支，不是独立规划器。原 warrior、wizard、taoist分支以及原资源报价、目标验证入口保留。child使用独立 `hc.child.death_burst.v1`描述，不通过中文名、根技能别名或原玩家技能表制造身份。

本次核对的纯规划44项包括：同一canonical envelope只构建一次、同一snapshot builder新增一次快照、实际child ID不变、原玩家技能表仍为33项、没有额外MP或冷却承诺。**这是这些检查的覆盖范围，不是声称本轮重新跑完了33技能的所有行为组合。**

### 冻结范围与拒绝规则

`ChildActionLease`拥有的命令包含根／父／子关联、父fact、父目标旧life、来源handle、mechanic、历史credit、提交原点、半径、实际损失派生伤害和有限代次。创建时检查字段集合、合法根技能、父fact格式、代次关系、有限整数、可表示的几何、世界一致性，再通过 `Graph.capture()`捕获独立只读内容。

外层request也固定为只读，`from_request()`重新校验typed owner及字段。篡改skill、rank、seed、client claim，或移除lease后只留下child ID，不会进入玩家技能回退路径。独立seed根据根release、父fact、来源handle、动作、代次和子release派生，不依赖一次全局随机抽样。

有效映射下，`planning_context()`将中心重新投影自命令持有的提交原点，移除调用者提供的旧snapshot、line-strip builder及effective-cells builder。原44项验证了晚到的屏幕位置及外部旧快照不能把中心 `(12.5,-3.0)`、半径 `2.0`替换掉。**负地图漏检是前述例外，需要单独补上。** 

### hash保护与“可信”的边界

新 `chain_context`、`historical_credit`、`child_command`在生成最终plan hash前附入计划，并加入原hash保护字段。普通计划没有这些字段时，不会凭空添加新的hash输入；child descriptor另以SHA256形成版本指纹。 

需要准确区分：

**描述版本的SHA256、原plan hash、真实执行授权是三件事。**原plan hash仍沿用已有 `hash(_canonicalize(...))`，不是新加的密码学授权机制。typed lease证明这份纯输入与其捕获内容一致，尚不证明父fact确实来自某个已接纳的真实根链，也不证明已预留执行该链的全部容量。

本轮测试从纯handler命令进入planner，仍未从Root真实死亡派发子动作。这一范围说明与源码一致。

## 四、源码与归档字节：本次完成独立逐项重算

我从固定Git对象读取源文件及ZIP，在内存中解包校验，没有用正在施工的第三树文件替换固定提交内容。

| 核验对象 | 本次独立结果 |
|---|---|
| 3728份受测源码 | 逐文件SHA256与源码清单一致，重算内容集合指纹为指定 `bad34a53…`。 |
| 受测字节 ↔ 固定Git原字节 | **849 exact、2879 CRLF-only、0其他差异。** |
| 八项源码／测试／数据delta | 逐项核对前后哈希；旧内容与父受测ZIP及父Git换行映射相符，新增路径父版不存在。 |
| 源码ZIP | 3732成员：3728源码＋3个原媒体文件＋RFC；无重复成员、CRC错误。四个附加成员与固定Git原字节一致。 |
| 原生ZIP | **286成员**逐项大小、SHA256和固定Git归档原字节一致。 |
| 观察index ZIP | 两个成员大小、SHA256与清单一致；只读取，未恢复或重建index。 |
| 八项source-only diff-check | 本次实际执行返回 **0**。 |

八项增量清单正确。另有两份说明文档变更，不应误算为额外生产源码：`CHILD_PLANNER_WORKLOG_20261004.md`与 `FRAMEWORK_PUBLICATION_CLOSURE_PLAN.md`。

以下三个ZIP的整体大小、哈希也已独立重算，与提交清单一致：

```text
TESTED_SOURCE.zip
bytes  = 15792534
SHA256 = c82dd5f7c02465940c5ced33fe73bb0c1f402fc8d6abe68a920db5e18c2de4de

NATIVE_EVIDENCE.zip
bytes  = 4619964
SHA256 = a47df1cfbfd698a557b8772c6d52e4fb319a02f06ba14b684614f5b55d9b4f72

INDEX_OBSERVED_BYTES.zip
bytes  = 2575546
SHA256 = 1fe862794a3c16c2e3e471b95b58396f2654e5ad4867a38e0817e48cb6aa6de6
```

**这些是本次重新计算的结果，但不是全项目3728份源码的语义审计。**语义审查集中在八项增量及其调用、验证、容量和退休依赖。

## 五、原生关联、937检查与六次FAIL：采用范围核验通过

### 最终两组数据能够闭合对应

| 最终组 | 唯一场景 | 完整framework receipt | 检查数 | 超时上限 |
|---|---:|---:|---:|---:|
| DIRECT | 26 | 21 | 547 | 30秒 |
| WORLD | 8 | 8 | 390 | 60秒 |
| **合计** | **34** | **29** | **937** | — |

五个普通场景没有framework receipt，依runner记录、原生退出和marker验证；没有将它们补写成不存在的framework检查。34／29／937的口径与本轮清单一致。

本次逐份核对了29份完整回执的检查ID、布尔结果、count／passed／reported_checks、失败计数，以及scene、run、invocation、source。全部最终runner行均记录原生退出0、`process_exited=true`、无超时；每组before／after源文件哈希集合一致。原生PID、项目路径、请求APPDATA及引擎实际 `user_data_directory`也与对应关联记录吻合。

两组身份分别为：

```text
DIRECT invocation
704bc0c3-e9af-4713-a681-3c001c35a85c
APPDATA末级
child_planner_final_direct_8f9b84198ca04a54bff07678d0b14ae6

WORLD invocation
8c21e6f7-2470-4c0f-9fa3-5a7ef0eb6702
APPDATA末级
child_planner_final_world_db317102cc8c4bb5bf024a35b9bea7f7
```

核心最终run中，chain68为 `22471f4a-e800-4f23-8dbe-bfb48e5a9bbf`，child planner44为 `dd24bc0e-7d0d-481e-88e8-0ae9913da383`。这里说的是**归档原生结果经本次复核成立**，不是本会话新增跑出了68／44 PASS。

### 六组producer／cold关联成立，但不属于新child执行

本次核对了装备来源组合、符文组合、组合效果、安全退出、自然效果、自然资源六对live／cold。expected中的producer run、同轮invocation与source，均对应成功原生producer；handoff中的完整receipt SHA256与实际归档回执一致，cold具有不同run及PID。

**它们支持原有业务和持久化回归，不证明Root真实child链的cold闭环。**这与本轮声明的未完成范围一致。

### 56次尝试确为50 PASS＋6 FAIL

我逐行对照了11组原生归档的runner结果与RUN_INDEX，并核对了各组before／after源码不变。六次失败的原件均在，没有被最终采用的通过结果覆盖。

| 原始失败 | 本次保留的判断 |
|---|---|
| `child_planner_red_122807_529063` | fixture将实例方法当静态方法调用，解析失败、无有效framework receipt；**不是有效功能RED**。 |
| `child_planner_entry_red_122915_169984` | 1检查／1FAIL，原router缺少child输入工厂。 |
| `child_planner_green_123208_702616` | 5检查／1FAIL，中间版本的规划／snapshot校验未通过。 |
| `child_planner_diagnostic_123342_686363` | 5检查／1FAIL，诊断仍为invalid snapshot；最终补齐validation converter。 |
| `child_planner_related_123641_364370` | canonical场景在等待READY及随后WORLD路径断言失败；**归因未证实**。 |
| `child_planner_entry_class_red_124108_522428` | 68检查／8FAIL，错误直接入口及其连带资格／恢复检查失败。 |

上述分类与本轮记录一致。

**READY失败不能洗成基线问题或无害波动。**原日志确实有READY等待断言和随后clear-WORLD-path断言；runner记录的是强制终止、有效退出−1，`timeout=false`。它不是“已证明只是30秒超时”。

两文件旧字节对照我也复算了：该对照与最终受测内容的差异**仅两份planner文件**，且两文件确实对应父受测原字节；新实现恢复后的哈希也匹配。对照PASS和新码重试PASS成立，**但对照不是完整父checkout，更不能单凭两个PASS确定原FAIL的原因**。

### 告警和保护边界仍保留

最终13份非空stderr中，11份记录8个ObjectDB退出实例告警，另两份canonical测试各记录10个。没有将它们计成此次runner失败，也没有据此声称零告警、零泄漏或长期耐久已证明；两份多出的实例亦未归因于本次child代码。

完整diff-check的失败与source-only通过继续分开。观察index原件可以复核，**历史index连续性FAIL、历史原始备份MISSING不变**。本次没有用当前观察副本补造过去的连续性，也没有对仍在施工的工作树作跨时段保护承诺。

## 六、真实链接入前：三项最小、可证伪的研究建议

以下是基于当前源码的后续研究建议，**不是本轮已实现内容，也不是另起施工授权**。

### 1. 先补child专属严格映射门禁，不动原玩家兼容路径

先完成第一节的负地图RED及窄修复。长期应保持一个明确不变量：

> 任意返回accepted的child计划，其快照必须满足该child当前世界的STRICT_V2；不能依赖某个未来consumer再替planner补拒绝。

同时保留原44项合法规划、68项HP边界，以及原未映射玩家测试，避免修child却破坏旧公共合同。

### 2. 证明根batch结束不等于整条链退休

目前 `EffectRuntime._dispatch_one_fact()`在一个batch的最后fact派发后就调用 `_retire_reservation(admission_id)`。这对现有一次性生产者成立，却不能直接承接尚有child、周期状态或异步生产者的整条链。

最小研究场景是：根batch已排空，但仍有一个延迟child和一个能产生致死事实的周期状态。随后分别让它们正常完成、取消、遇到换世界，再投递一次重复旧回调。

需要证伪的断言是：**根batch一空，所有容量与去重资格就提前释放。**正确的链级退休应由实际所有权终结决定：相关生产者、排队／执行中工作、仍能派生动作的状态都已经终结。可以研究向现有权威增加明确的所有权交接，但不要另设第二套链planner或用TTL／LRU删除“看起来够旧”的资格记录。

这不禁止玩法状态本身具有作者定义的持续时间；禁止的是用任意过期时间代替执行资格的真实退休。

### 3. 把保守成本接到真实接受边界，并覆盖周期与动态出生

已有纯成本模型：

\[
F=N\sum_{g=0}^{G}(NB)^g
\]

可作为有限一次性派生的保守事实成本。这里的 \(N\)必须来自可证明的合法接收者上界，\(B\)为每个致死事实可派生的child绑定数，\(G\)为最大代次。**它不是释放时目标列表的长度，也不是新增“最多30只”的理由。**

最低限度应在一个组合场景中加入：两条根链并发争用同一目标槽、已有历史状态、接受后但child释放前动态出生的新目标、延迟周期致死，以及换世界取消。验收观察点应是“容量不足在相应HP承诺前拒绝”“已接受且合法的工作不被运行时悄悄截断”“最终真实退休后占用归零”，而不是只看队列没有报错。

尤其当前周期状态仍调用旧五参数 `apply_feature_periodic_damage()`，没有派生child所需的链fact；`_apply_command()`也没有执行 `RequestChildAction`的正式分支。**周期状态未来一旦能再次生产链事实，必须把它的生产次数上界、来源身份与生命周期计入容量及退休证明，不能只套一次性 \(F\)就宣布完整。**

冻结父事实的死亡原点是正确的；它与“冻结后续各次释放的接收目标”是两回事。后者仍应保持原正式几何与目标查询语义。

## 最终交接结论

**本轮窄审结果：一项新增P2待处理；已证实部分保留，不要求重复施工。**

父报告指出的periodic／child误入直接STRUCK入口已经有单变量原生RED→PASS对应，Combat坏投影后同batch恢复补证成立。合法映射下的纯child输入确实进入同一canonical planner，身份、有限代次、credit和命令内容得到拥有与hash保护。3728源码映射、八项delta、三个ZIP、34场景／29完整回执／937检查及六对cold关联，本次独立核验通过。

**新增事项只针对child负地图ID落入旧兼容分支，导致accepted与STRICT_V2不一致。**建议由唯一主控在原串行流程中先补最小原生反例，再实施child专属拒绝门禁；不要改写六次旧FAIL，不要把两文件对照升级成完整父基线。

Root真实child执行、整链逐目标／历史并发／动态出生容量、全部状态与生产者退休、防自激、Task3／5／P6、设备／GPU、原v97 B及APK继续保持原开放边界。本报告不构成合并、发布或全工程完成裁决。
