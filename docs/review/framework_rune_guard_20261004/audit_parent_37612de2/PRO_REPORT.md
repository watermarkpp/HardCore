# rune-sources-37612de2-20261004 独立复审

已直接核对固定 **`37612de204c42fe3b4fd6a89137e90f3449bc0c2`**，父提交确为 `08ccdf29e1be5897fa1ffdb6964f58300ad55c3b`。**本轮符文独立资产、共用事务写入、namespace保留、三来源组合、伪造词缀拒绝及销毁前置保护的已测成果应保留；但发现一处未来Rune识别顺序缺口：独立Rune记录带有未来合同及当前保留字段时，可能被降级为可恢复损坏，允许旧备份成为当前主档。**这是源码条件链判断，本会话尚未运行新的原生反例。

以下定位均为**仓库源码原始行号**。归档PASS不表述为本会话重新执行的结果。

## 一、优先补证／修正：独立未来Rune可能绕过terminal识别

### 当前顺序存在两条绕行路径

`scripts/items/item_extension_codec.gd`先按“是否像容器”分类，并检查当前私有字段，之后才识别独立Rune合同：

| 源码位置 | 当前行为 |
|---|---|
| **L26–39** | 先调用 `_is_wire_container()`，处理当前容器及其扩展。 |
| **L40–41** | 只要记录带 `_hc_item_extension`，立即返回 `INVALID/private_runtime_item_field_on_wire`。 |
| **L42–48** | **仅在不是容器时**，识别 `rune_instance_contract_id`；未来Rune合同或未知Rune身份才返回 `OPAQUE_UNSUPPORTED`。 |
| **L340–342** | 单凭存在 `base`、`extensions` 或 `format_version`，就认定记录属于容器。 |

所以，以下输入虽然具有明确的未来Rune标记，却不会得到当前安全策略要求的terminal结果。 

| 以正常Rune实例为起点的变体 | 当前源码推导结果 |
|---|---|
| 合同改为 `hc.runes.fixture.rune.v2`，另带 `_hc_item_extension` 字段 | 在读取Rune合同前，返回私有字段 `INVALID`。 |
| 合同改为上述未来版本，另带 `base:{}` 或 `extensions:{}` | 被归到容器分支，跳过独立Rune识别，最终成为当前容器版本／结构 `INVALID`。 |

这里不要求当前版本理解未来字段的含义。问题恰好是：**既然已经有不支持的所有权合同，就不应让当前字段规则把它降级为“可以用旧备份替换”的已知损坏。**

### 后续确实存在旧备份恢复入口

这不是只有错误名称不准确：

- `player_state.gd` **L5010–5018** 仅在codec结果为 `OPAQUE_UNSUPPORTED` 时，将该物品失败标成terminal。
- 同文件 **L5706–5734** 对非terminal主档失败继续调用 `_restore_json_backup()`。
- 恢复函数会隔离原主档，再提升合法旧备份；不是只报告错误而保持原运行态。  

因此，在其他外层合同正常、旧备份有效的条件下，**该未来Rune记录可能被从当前角色状态中回退掉**。原文件可能仍在quarantine中，不能把它夸大成“原字节已不可恢复地删除”；但这已经违背“未知所有权默认整aggregate只读、不得借旧备份覆盖”的边界。

### 最小原生反例

直接扩展现有 `future_item_ownership_terminal_test.gd`，不新建恢复体系：

```gdscript
var future := Rune.create_instance("future-owner:rune-extra", true)
future.rune_instance_contract_id = "hc.runes.fixture.rune.v2"
future[Codec.RUNTIME_EXTENSION] = "future-owned field"
```

再分别测试增加 `base`／`extensions` 的变体。沿用该文件已有的 `_verify_profile()`、`_verify_shared_item()`：要求codec为 `OPAQUE_UNSUPPORTED`，角色／仓库validator为terminal，真实加载拒绝，主备字节及旧内存状态不变，后续写入口继续封锁。

现有 **L95–115** 新增的是未来Rune扩展、嵌入Rune合同、未知嵌入身份和普通未知Rune；没有上述“独立未来Rune＋当前保留字段”组合。原有这些通过结果不应撤销，也不能代替本反例。

**修正边界：**在当前结构分类／私有字段拒绝之前，先保守识别明确的不支持Rune所有权。不要为通过测试放宽当前v1字段白名单，不要解析未知payload，不要将所有普通损坏都改成未来版本，更不要修改原备份writer。

## 二、Rune与Gem：同一经济权威、不同资产身份，namespace保留成立

### 实例与默认关闭边界

`rune_item_rules.gd` **L14–42、L46–65** 核对作者数据、primary来源及证据哈希，通过原身份注册和类别规则解析记录；creator只有显式fixture启用时才创建，实例固定独立 `instance_id`、count=1和Rune合同。两个Rune记录共用这套入口，不按显示名称分叉处理。

这些是验证资产，不表示正式掉落、收费、孔数或平衡已经投放。

### 请求兼容与持久结果兼容没有混为一谈

`item_transaction_port.gd` **L13–17、L45–54** 用操作表选择module、namespace及输入字段。旧Gem请求仍使用 `gem_instance_id`，Rune使用 `rune_instance_id`；请求摘要仍按：

```text
[profile_id, action, target_instance_id, 本操作输入实例ID]
```

生成。`item_transaction_journal.gd` **L10–13、L74–88** 据action选择原结果字段，因此旧Gem持久结果的字段与摘要结构保留，新Rune结果不会冒用Gem字段。 

端口内部quote字段已统一成 `input_digest/input_instance_id`；所以这里支持的是**旧Gem命令及持久结果重试兼容**，不是承诺跨代码版本保存的一份内部quote对象仍可直接提交。

### 每个操作保留另一namespace

`_compose_target()`先取得完整已验证extensions，再只替换本操作的namespace；不是重新构造一个只含Rune或只含Gem的容器。`_build_document()`仍把物品增量与journal放入原角色候选，经唯一ordered writer提交；回执消费仍核对当前job，再发布相关内存增量。 

当前codec还让两个namespace共享实例去重集合，纳入宿主自身ID；`ownership_ids()`同时枚举宿主、Gem和Rune。`can_release_ownership()`不再只看Gem socket，而是要求两个namespace的嵌入记录都为空。

最终 **`rune_transaction_test` 35检查PASS**实际覆盖了Rune先插、Gem后插、分别取出／重插、满背包拒绝取出、原base与gold不变、保存恢复及唯一所有权。这个有限往返链可以保留，不需要因为第一节的未知版本问题重做整个事务设计。

## 三、伪造affix与预留资产销毁：两个原反例已有对应修复

### 伪造词缀：新来源入口没有借旧装备兼容性授权

`contribution_provider.gd` **L23–35** 在识别affix来源时，对带 `drop_affix` 的记录调用原 `GameData.validate_item_drop_instance()`；失败写入明确错误，不访问缺失的 `instance_id`，也不发布部分来源。

这没有改旧装备读取器：无affix的历史普通装备仍能沿原资格使用，只是不凭空获得affix订阅。

最终 **29检查PASS**分别覆盖缺完整drop合同、重复／伪造modifier、错误／缺失实例身份，且检查拒绝后目录、bundle、stats和compile_count保持；普通旧装备及正常真实affix还能继续启用。**支持关闭这组指定伪造来源反例，不外推为全存档防篡改系统。**

### 销毁：拒绝发生在drain之前，旧RED没有证明Rune被销毁

`player_state.gd` **L1448–1457** 现在先检查所选记录是否被原事务端口预留，命中即返回 `item_transaction_pending`；原 `_before_state_transaction()`仍在这之后。合法完成的嵌入宿主，继续由后面的 `can_release_ownership()`保护。

我读取的原RED日志明确是：

```text
reserved_before=true
destroyed=0
reason=invalid_inventory_index
inventory_unchanged=false
writer_finished=true
```

它证明**被拒绝的销毁调用先完成了另一条已接受事务**，不是证明Rune被销毁。最终35项中的原Rune、混合选择和宿主选择均检查拒绝后库存不变、writer未完成、reservation仍在；随后原事务又能正常durable完成。该修复范围成立。 

这也不意味着所有被拒绝的库存操作都不能触发任何保存屏障；本次具体修正的是**所选资产已经被这条事务预留**的入口时序。

## 四、三来源与独立cold：实际链路成立，完整wire没有删字段

### 三个来源有独立归属

provider通过 `Items.embedded_records()`读取两类嵌入资产，来源句柄保留：

```text
affix：宿主实例＋登记affix＋modifier序号
Gem：Gem实例＋宿主实例＋hc.socketing.primary
Rune：Rune实例＋宿主实例＋hc.runes.primary
```

最终expectation中的三条句柄与源码一致。取出某资产只撤回其来源，重新放回同一位置重建原句柄；不是重新生成一个随机来源身份。 

`rune_source_composition_test.gd`实际先以正常写盘完成插入和装备，再通过Root捕获配置、Player接受非空容量票据和真实Timer释放。一个基础命中启动三个ignite状态；撤回后续订阅后，三份状态继续完成原四次周期，旧Root／Player RNG不变。最终 **35检查PASS**与这条路径相符。 

准确边界是：**控制夹具停用了AI和自动处理，后续显式推进原模拟钟／pump。**它不是自然UI输入、持续P6/R3压力或设备测试；非空容量票据也不能直接称为“新增三来源全部使用非空音画资源”的证明。

### cold比较的是完整合法wire，不是挑字段相等

`rune_source_composition_cold_test.gd` **L35–49** 对恢复装备和expectation装备分别执行原 `encode_runtime()`，要求均为 `KNOWN_VALID`，再将**完整编码结果**经过同一JSON边界比较。base、modifiers、耐久、两个扩展及其中资产字段没有为通过断言而删掉。

因此，运行时int与JSON解析float的表示差异不应被误报为资产变化；反过来，这也不是原文件文本逐字节相同或整个账户所有字段相同的证明。

本轮对应关系已对上：

```text
live：98cb0b56-9a04-447b-89f9-9eef991b182e
cold：0fe24563-65e3-4ec2-a44d-1567021dbb14
invocation：65b99757-53d1-49ca-946a-78692bce500e
source：5b996731…
```

expectation绑定上述live，cold先检查原producer门禁再加载；最终 **14检查PASS**包括完整wire、三来源句柄，以及旧Gem和Rune请求均返回durable记录、不新增writer、不改变资产。测试明确在新进程重新启用验证模块，**不声称模块启用状态自动持久化，也不恢复战斗状态或地面掉落。**  

## 五、身份生成与最终证据范围

身份增量通过原authoring source新增两个item及一个类别；生成索引的差异包含对应新记录和类别数组插入引起的证据pointer移动。`IDENTITY_PRESERVATION.json`列明 **1240旧身份的非来源证据字段保持、3个新身份、21个类别pointer更新、生成器检查与27项单元检查通过**。 

我核对了这些差异和保留报告，**没有独立重算整份1240记录对比或重新运行生成器**。因此，保留其有范围说明的归档结论，不称为本会话新取得的全量生成证明。

最终采用四组的计数一致：

| 最终组 | 原生场景数 |
|---|---:|
| clean direct | 28 |
| journal single | 1 |
| journal seed／cold／restart | 3 |
| final world | 8 |
| **合计** | **40唯一场景** |

四份validation均记录退出0、源码运行期间稳定；直接组核心receipt绑定最终 `5b996731…`。36份framework回执、1537检查及113次尝试中的97 PASS／16 FAIL仍应按原阶段保存。**本轮实际读取了四份核心完整回执、直接组部分runner、四组validation及阶段索引；没有逐份复验全部113次执行、四组进程环境或全部1537项。**    

两次账户分组污染／同名建角失败继续按README的原始分类保留；没有依据将它们改成Rune业务PASS，也没有依据从这些隔离夹具失败推断真实用户存档被修改。

### 主控交接

> 保留Rune/Gem共用端口与journal、另一namespace保持、三来源35／cold14、伪造affix29及事务35项成果。优先补“独立未来Rune＋`_hc_item_extension`或base/extensions字段”反例：当前提前按私有字段／容器结构判INVALID，可能非terminal进入旧备份恢复。应先识别明确未知所有权，保持整aggregate只读，不放宽v1白名单、不修改writer。旧销毁RED只证明拒绝调用完成了另一事务，不证明Rune被毁。完整wire比较未删字段，JSON数值类型归一合理。死亡子连锁、动态承诺、Task5/P6R3及设备/APK继续独立开放。

**实际审查范围：**读取Rune规则、完整codec／journal／事务端口、贡献来源接入、PlayerState销毁及验证／恢复关键函数、Rune事务和组合live/cold、未来资产测试、新affix测试的diff、四份核心最终完整回执、旧销毁RED日志、身份保留报告及执行记录。**未运行Godot、修改源码或真实HEAD/index、启动第二工程主控、重算3716文件／完整ZIP，也未恢复或重建index。**历史index连续性FAIL、旧原件MISSING及原v97B缺失维持原边界；本结论仅针对 **`rune-sources-37612de2-20261004`**。
