# rune-guards-e22fe095-20261004 独立复审

已直接核对固定 **`e22fe0951f28c55620399b453f116cb09120af4b`**，父提交确为 `37612de204c42fe3b4fd6a89137e90f3449bc0c2`。**支持有界关闭“独立未来Rune/Gem被当前字段分类降级”和“销毁操作在drain后误删提取结果”两项具体缺陷；本轮原生账户关联补充与两个纯child准备模块也有对应证据。已读范围内，没有发现必须追加生产整改的新确证缺陷。**不过，提取测试的保存恢复是同进程reload，child测试是纯函数输入，二者不能分别扩张为六种独立cold或实际死亡子链验收。

以下定位均为**仓库源码原始行号**。本会话没有运行Godot；归档结果与独立源码审查结论分别表述。

## 一、未来所有权优先识别：原绕行路径已堵住

### 关键顺序与原安全边界一致

`scripts/items/item_extension_codec.gd` **L26–35** 现在先识别明确的独立所有权：

```text
不支持的Rune合同／未知Rune身份
或不支持的Gem合同
→ OPAQUE_UNSUPPORTED

之后才解释：
当前容器、当前私有字段、当前v1结构
```

因此，未来Rune附带 `_hc_item_extension`、`base`、`extensions` 或 `format_version`，不再先被当前分类器判成可恢复的普通损坏。**改动没有把当前v1全部放行，也没有开始解析未知payload。**

下游仍沿原路径传播terminal：`player_state.gd` **L5011–5017** 根据codec状态建立terminal结果，**L5707–5730** 在主档terminal失败时直接返回，不进入旧备份恢复。没有新增writer或第二套加载权威。 

### 有效RED不是其他账户错误造成的假阳性

本轮测试的改进有实质作用：

| 测试位置 | 实际控制 |
|---|---|
| `future_item_ownership_terminal_test.gd` **L166–175** | 每个案例恢复角色和共享仓库的主备文件，正式加载，并先要求startup preflight成功。 |
| **L177–217** | 先只替换目标profile物品，检查正常startup拒绝；随后再加入坏known字段，检查terminal、原内存不变和主备字节不变。 |
| **L222–244** | shared案例重新建立独立健康基线，核对目标shared路径、初始化拒绝及原主备字节。 |
| **L247起** | 已知损坏继续走原有效备份恢复，不把所有拒绝都改成opaque。 |

这些检查避免了“先前遗留的坏账户已经让startup失败，所以新future输入看似被保护”的错误归因。 

我抽读的有效RED中，案例13的健康加载与preflight均为PASS，随后“sole future输入拒绝”“terminal”“禁止旧备份发布”“字节保持”等检查才失败；其完整回执尾部仍是 **754检查／117 FAIL**。最终同内容回执为 **754检查PASS**，并保留了已知v1恢复和旧装备导入控制。**这组原缺陷可以按所列21个future候选及恢复边界关闭。**  

profile检查允许错误路径指向profile或shared，是因为原shared迁移验证也会读取profile。这里不能只凭返回路径判定来源；健康前置、唯一改动输入及字节断言共同提供了因果约束，现有表述没有把错误路径伪改成预想值。

## 二、提取目的槽保护：修的是实际误删结果，不只是拒绝码

### 修复位置正确，原事务仍保留完成权

`player_state.gd` **L1448–1458** 在调用 `_before_state_transaction()` 之前，同时检查：

- 所选索引是否是原事务预留的提取目的槽；
- 所选现有记录是否是原事务预留资产。

`item_transaction_port.gd` **L111–113、L130–136** 的目的槽来自原remove接受计划；`slot_reserved()`不要求该索引已经位于当前inventory长度内。因此，**既有空槽与append位置都能在drain之前保护**，混合选择也会整次拒绝，不先删除无关项。 

外层特意保留 `index >= 0`，避免把端口内部负索引的“任意预留槽”查询含义误用为销毁目标。负索引仍走原无效选择处理；本轮没有将所有无效销毁调用都改成新事务规则。

### 本次RED与父轮RED必须区分

本轮原始日志确实记录：

```text
Rune/Gem × empty/append：
    writer_finished=true，destroyed=1，success=true

Rune/Gem × mixed：
    writer_finished=true，destroyed=2，success=true
```

因此，这次能确认的是：**销毁请求先完成待提取事务，再按旧索引删除了刚出现的提取结果；mixed还删掉无关选中物品。**它比父轮“拒绝操作完成了另一事务，但未证明Rune被毁”的证据更进一步，不能混写。

最终六个变体位于 `rune_transaction_test.gd` **L107–178**。检查覆盖了拒绝前后inventory、equipment、journal、原job、目的槽预留及主备文件；之后让原writer正常完成，确认提取资产只有一个所有者、另一个namespace和无关物品仍在，再重交缓存quote检查无新job／资产变化。相关新增检查在最终 **119检查PASS** 回执中均保留。  

**需要收紧一处口径：**这六个变体调用的是同进程 `PlayerState.load_save()`，不是六组独立cold进程。它们支持“正式写盘后重新加载、旧quote只读重放”；不能借其他独立cold场景的PASS，改写成每个目的槽反例都已经跨进程复验。README使用“reload”是准确的，不需要因此撤销119项成果或新增生产改动。

## 三、APPDATA／原生身份关联：当前证据已补到，父历史不能回填

### 记录来源是真实运行环境，而非复制预期路径

`tools/run_godot_tests.ps1` **L84–91** 先将设置的RuntimeAppData规范化为实际路径，再设置进程环境并记录runner PID；新增wrapper PID与启动时间、handoff环境和结果环境都是测试证据字段，没有进入游戏存档或业务身份。相关diff未改PASS判定来迎合新字段。 

`tests/framework/helpers/check_receipt.gd` **L16–20** 则直接读取原生进程的：

```text
OS.get_environment("APPDATA")
OS.get_user_data_dir()
ProjectSettings.globalize_path("res://")
OS.get_process_id()
```

所以现在能比较“runner实际设置了什么”与“Godot实际看到了什么”，不再只有外层launch声明。

### 四个当前owned根的对应关系成立

| 当前组 | 场景数 | framework原生环境回执数 | 本轮抽对示例 |
|---|---:|---:|---|
| direct | 30 | 26 | future、Rune事务、两个child测试 |
| journal single | 1 | 1 | v2备份恢复矩阵 |
| journal chain | 3 | 3 | 独立cold回执 |
| world | 8 | 8 | 自然战斗cold回执 |
| **合计** | **42** | **38** | 四组分别核对 |

关联表列明四个不同owned APPDATA根、launcher／runner身份、invocation及38个原生run；我抽对的原生receipt中，实际APPDATA、user_data_dir、project、PID和run/invocation均与该组对应，source也都是最终 `8d6d10f1…`。     

应继续保留三个限制：

**第一，**4个普通场景没有这份原生framework环境回执，只有wrapper环境／启动证据；不能说42个场景都具有相同深度的原生环境证明。

**第二，**原生PID、run与环境关联不等于逐进程映射验证了引擎二进制哈希。归档文件哈希和实际进程环境是不同证据。

**第三，**当前重跑只能补当前源码的关联，不能恢复父阶段未记录的历史APPDATA。父历史MISSING以及历史index连续性FAIL都应继续独立保存。

本轮我读取了关联表并对四组取样核验，**没有逐份重新计算38个receipt及handoff哈希**，不把交付方的逐份核验声明改称我的全量复算。

## 四、child准备模块：有限成本和封闭命令成立，生产子链仍未接入

### 1. 成本计算是保守模型，不是新增目标上限

`child_capacity_proof.gd` **L9–40** 使用调用方提供的接收者上界、child binding数、最大代数、总binding数和持续binding数。

令 \(N\) 为接收者上界，\(B\) 为child binding数，\(G\) 为最大代数，则事实总量采用：

\[
F=N\sum_{i=0}^{G}(NB)^i
\]

receipt与state成本分别按全部binding和持续binding乘上 \(F\)。**L42–65** 用分块几何级数及饱和算术计算，复杂度随代数的位数增长；达到足以证明拒绝的阈值后，不再构造巨大整数。没有按十亿代逐个循环，也没有将超量结果截断成一个可接纳的小数。

纯测试 **29检查PASS** 包含手算12／129／930 facts、精确容量边界、少一个槽位、巨大有限代数、零接收者、零child producer和非法输入。**这些证明的是给定参数的派生成本计算**，不是证明运行世界已经提供了正确上界，也不是证明逐目标局部槽位、并发预留和动态出生契约已经接入。 

### 2. 命令构造没有写HP或选择真实接收者

`death_burst_handler.gd` **L12–60** 验证有限配置、直接／周期／child分类、根与父release关系、已提交致死损失、旧目标身份及可表示的几何；输出深复制并只读的 `RequestChildAction`。它保留credit与原点，不取得Node，也不调用planner、HP、信号或RNG。

**28检查PASS**支持不可变字段、有限代次、零伤害不抬为最小伤害、几何溢出拒绝和全局RNG不变。不过测试的 `_fact()` 是手工构造的Dictionary；所谓periodic lethal检查只是将这个纯输入分类设为periodic，**不是一次真实火墙／燃烧致死后产生子请求的原生业务链**。此外，纯函数对“首次死亡”字段的核验，不承担重复fact去重或生命身份认证。 

### 3. 发布闸门没有意外打开

`handler_registry.gd`虽然加入了直接纯函数分派分支，但 **L7–13** 的可发布 `IDS/CONTRACTS`仍只有ignite和lifesteal；`feature_compiler.gd` **L71–74**继续要求handler位于该白名单与authority中。当前runtime也只处理已有恢复／状态命令，收到 `RequestChildAction`仍不是一个可执行生产分支。  

因此可以采用的结论是：**两个准备单元及其纯测试已落地；完整死亡子链、动态完整接受保证和防自激集成仍未验收。**本次没有发现需要为这些尚未接入的能力宣告新的生产失败。

## 五、本轮采用结果与最终裁决

四组清单对应 **30＋1＋3＋8＝42唯一场景**；直接组runner明确记录30 PASS、正常退出及零引擎错误，两份child回执的run ID也与该runner一致。总计38份framework回执、2150检查属于最终 `8d6d10f1…`；79次尝试中的12条FAIL继续是原失败记录，不能由最终采用集合覆盖。  

**本轮裁决：**

- **可有界关闭：**未来独立所有权分类绕行，以及Rune/Gem提取目的槽在drain前未受保护的两项具体缺陷。
- **可保留：**当前四组原生环境关联补充、child成本29项和纯命令28项成果。
- **新增确证生产缺陷：**已读范围内未发现。
- **需保持准确：**六个提取变体是同进程reload；child事实是纯测试输入；本轮环境记录不能回填父历史缺失。

> **主控交接：**保留754与119专项修复成果，原RED分别说明未来所有权保护失效和实际删除提取结果，不混写。当前38份framework环境关联已具有原生自报字段，4个普通场景仍仅wrapper层证据；历史关联MISSING不回填。child准备代码保持不可发布，29／28项只证明有限成本和封闭命令，不等于真实链、逐目标承诺或防自激集成。当前没有必须新增生产整改项；按原范围继续后续施工，不据本轮关闭Task3/4/5、P6或设备/APK。

**实际审查范围：**读取本轮codec、销毁入口、原事务目的槽接口和terminal传播链，两份修复测试全文，两个child模块／测试及白名单、runtime命令入口，环境记录helper／runner增量，关键RED/GREEN回执片段、child完整回执、四组关联与跨组原生环境样本。**未运行Godot、修改源码或真实HEAD/index、启动第二施工线程、解包重算3722文件／完整ZIP，也未逐份独立复验全部2150检查。**本结论仅针对 **`rune-guards-e22fe095-20261004`**；原v97 B输入MISSING、旧supervisor安全复用、GPU/Android与主树/APK边界均保持开放。
