# source-composition-08ccdf29-20261004 独立复审

已直接核对固定 **`08ccdf29e1be5897fa1ffdb6964f58300ad55c3b`**，父提交确为 `6ae8a4412bcbf146baf7e9cbe6bfac28e3383fdd`。**本轮支持保留登记词缀与真实嵌入宝石的来源组合、原事务端口的拆卸／重插／独立cold，以及恢复增量归因修复。17个即时来源也已有实际派发证据，不再只是容量预留。已读范围内，未发现需要追加生产整改或撤回本次改动的新确证缺陷。**

以下定位均为**仓库源码原始行号**。本会话没有运行Godot；归档PASS不表述为我的新增原生测试结果。

## 一、来源组合：只读取原装备事实，没有重洗或重复授予原属性

### 登记词缀的资格链成立

`scripts/features/adapters/contribution_source_rules.gd` **L12–25、L28–46** 先读取受控登记定义，再匹配既有记录的：

```text
drop_affix.contract_id
drop_affix.applied == true
modifiers中的stat／op
有限且为正的value
```

本轮唯一登记选择器明确是 **`item.drop.affix.v3`、`magic_max`、`add`、正值**，不是任意带同名属性的Dictionary都自动获得资格。`content_layer_registry.gd` **L205–240** 又在目录发布前核对登记身份与原authority允许的stat，未知affix拒绝整候选。  

来源收集沿用 `PlayerState._feature_item_eligible()` 的原装备资格检查；provider没有掷随机数、修改modifier或直接增加 `magic_max`。它只把满足条件的原修饰转成机制订阅。因此，**“原装备已有+1魔法上限”与“该词缀获得一份ignite订阅”是两件事，原属性没有因新增来源被再加一次。** 

### 两种来源的身份没有混用

`contribution_provider.gd` **L19–47** 分别生成：

| 来源 | 主要身份组成 |
|---|---|
| 登记词缀 | 原装备实例ID、装备槽、机制ID，以及 `["affix", affix_id, modifier ordinal]` |
| 嵌入宝石 | **原宝石实例ID**、装备槽、机制ID，以及 `[宿主装备实例ID, socket_id]` |

这不是给同一机制伪造两个随机ID；宝石仍保留独立资产身份，宿主与socket位置参与其来源定位。归档expectation中，两条句柄分别指向原掉落实例和 `source-composition:gem`，与实现一致。 

**稳定性范围要保持准确：**同一资产重新插入同一宿主、同一socket和同一装备槽，可以重建原句柄；这不承诺换宿主、换槽或改变modifier结构之后仍保持同一来源身份。本轮没有为了追求“句柄永远不变”而丢掉必要的归属维度。

## 二、拆卸／重插仍由原quote、commit和writer负责

本轮13条增量中没有修改item事务writer或codec。新增来源只读取事务已发布的装备状态，不建立第二条宝石移动路径。

我沿当前固定SHA读取了原事务调用链：

| 原始源码位置 | 核验结果 |
|---|---|
| `item_transaction_port.gd` **L15–48** | `quote_new()`签发原序列身份；已有结果先核对请求摘要，再只读返回。 |
| **L87–112** | `commit()`重新报价，核对旧quote、当前active事务及原writer忙状态，随后提交给原 `_json_persistence`。 |
| **L145–174** | 物品增量与journal进入同一候选文档，经原codec及writer提交。 |
| **L176–213** | 仅当前job能消费回执；成功后发布相关物品／journal增量，再调用原属性重算。 |
| **L216–229** | 修改当前宿主的extension；插入时移除原宝石的背包占位，取出时归还原gem记录，不用旧整份装备覆盖当前宿主。 |

因此，宝石撤下后来源消失、重插后来源恢复，发生在原事务完成后的既有重算链中；不是测试直接增删event binding。 

`feature_source_composition_test.gd` **L45–71** 确实以 `test_mode=false` 执行隔离写盘、插入、正式装备、取出、重插和 `load_save()`，检查：

- 两个来源分别存在；
- 取出后只剩词缀来源；
- 取出不改变原base和旧roll；
- 重插同一宝石恢复原两条句柄；
- 保存／加载后宿主与宝石仍各有唯一身份。

最终这份live回执为 **34检查PASS**，不是早期尚未加入cold交接写入检查的32项结果。 

范围也应保留：角色及输入资产前态由隔离夹具建立，不是正式建角UI全链；战斗阶段通过真实Root／Player接受和原planner，但停用AI、显式推进模拟钟及pump。已接受两份ignite状态在模块撤回后完成原周期，**不等于所有战斗中拆宝石、换装备、死亡转场的交错都已测试。**

## 三、完整wire比较没有删字段，JSON类型归一处理合理

这是本轮可以明确确认的部分。

`feature_source_composition_cold_test.gd` **L35–48** 对加载结果和expectation中的装备**分别调用原 `Codec.encode_runtime()`**，要求两者均为 `KNOWN_VALID`，再比较：

```gdscript
JSON.parse_string(JSON.stringify(encoded.item)) \
    == JSON.parse_string(JSON.stringify(expected_encoded.item))
```

它比较的是两个完整编码结果，不是挑选若干字段，也没有删除durability、modifier、宝石、contract或版本字段来绕过失败。

`item_extension_codec.gd` **L66–82** 的映射同样没有丢掉资产数据：完整base被复制，内部 `_hc_item_extension` 被转换为wire的contract／version／extensions，随后再由 `decode_wire()`验证。原base中的修饰和耐久仍在，嵌入gem完整位于extension内。

归档expectation实际包含 `1.0`、`990001.0`、运行时整数format_version等混合表示，正是这次需要统一比较边界的输入。**不能把JSON解析后的float与运行时int标签不同，直接判成资产字段改变。**

准确结论是：

> **指定装备及其嵌入宝石，经过原合法codec后的全部持久化wire内容相等。**

它不是原存档文本逐字节一致，也不是整个profile、仓库和全部物品逐字段比较。旧两次Dictionary诊断FAIL应保留，但不能将其重新解释成已经证实资产损坏。

### 独立cold不是靠expectation自认成功

当前cold在恢复前调用原 `native_producer_gate.accepts()`；该门禁核对runner交接中的scene、成功退出、run、invocation、source及完整receipt哈希，然后逐项验证receipt。

本轮关联已对上：

```text
live run：dca0b9e1-5245-469f-9997-a8acf1dae717
cold run：2143dba5-61fc-40b1-b4a1-d90558fff7f9
共同 invocation：a440370e-0eb0-4f1d-afa4-6e254d1ef429
共同 source：d82f0011…
```

expectation、两份receipt、runner与成功handoff一致。cold的 **12检查PASS**还验证旧插入请求返回durable recorded outcome、不新建pending writer、库存与装备不变。**这组物品／来源／重试恢复成果应保留。**   

cold明确重新加载测试目录并启用对应模块，再恢复物品；它证明持久物品可以重建同一来源，不证明测试模块启用状态本身已持久化，也没有恢复战斗状态或地面掉落。

## 四、恢复增量归因：原问题可以关闭；17来源也已实际执行

### 25点不再被观察者的额外10点污染

`Player.restore_health()` **L1647–1661** 仍执行原HP写入，但在 `stats_changed`／`resources_changed`通知前计算局部 `actual_gain`，最后返回该冻结值。

`CombatRuntimeService.apply_feature_source_restore()` **L180–191** 直接消费原authority返回值，不再在通知之后读取HP差；原来源身份与存活检查保留。**这是增加原写点回执，不是复制一套恢复公式或增加第二次HP写入。** 

我核对了原RED和最终回执：旧86项中仅“本条实际增量应为25”的检查失败；最终版保留最终HP85的断言，同时检查本条 `actual_healing` 增量为25，已经通过。**前轮指出的统计归因缺口可按该同步恢复反例关闭。** 

### 17来源不再只是“reserve成功”

当前 `feature_lifesteal_runtime_test.gd` 在原17份预留检查之后，增加真实Batch、Enemy伤害端口、runtime消费和Player恢复：

```text
一次已提交实际损失100
× 每来源25%
× 17个独立来源
= 425总恢复增量

来源HP50 → 475
持续状态数 = 0
```

它同时检查17条命令、425归因增量、原RNG和队列／producer排空。最终运行时场景为 **94检查PASS**；此前“17来源只证明预留、未实际派发”的限制现在可以更新。 

测试把来源max_hp设为1000以容纳425点，不是修改正式数值。它使用受控Batch与手动pump，也不是17种正式词缀／符文组合或自然吞吐测试。

## 五、当前没有新确证生产缺陷；这些范围仍不能合并外推

在已读路径中，未发现需要为本次增量追加生产修正的确定错误。以下属于**现有证明边界**，不是新的失败裁决：

| 已有证据 | 不能自动推出 |
|---|---|
| 一个登记的v3正magic_max选择器 | 所有词缀类型、符文和任意modifier重排均支持 |
| idle阶段取出／重插＋战斗中模块撤回 | 所有战斗内宝石移动和换装交错均已覆盖 |
| 完整合法codec wire相等 | 原存档文本字节相同、全账户全部字段相同 |
| 94项中的真实17来源派发 | 任意AOE／混合来源饱和都已验收 |
| 世界相关回归同源码通过 | 新“词缀＋嵌入宝石”组合已经自然持续压力或设备实测 |

这些限定与本轮README一致，无需因为它们仍开放而重做已通过的局部链路。

## 六、采用记录与index归档边界

本轮采用集合为 **20直接＋8世界＝28唯一场景、24份framework回执、1123检查**；另4个普通场景不折算进framework检查数。直接组validation记录退出0、源码稳定、20 PASS；世界组8条runner结果均为正常退出、无timeout、有效receipt。82次尝试中的5条原FAIL仍在阶段索引，不应以最终通过覆盖。   

`INDEX_OBSERVED_BYTES.zip`的归档声明给出当前index与staged输出原件及哈希，历史 `66c505…` 连续性FAIL、旧备份MISSING继续明确保留。**新增当前原件，不恢复过去的连续性证明。**

本轮对该ZIP的GitHub文本读取返回 **HTTP400：仅接受UTF-8文本**；我没有继续解包或独立重算ZIP／成员SHA256。因此，**不声称这份二进制补档已由本次Pro完成逐字节复算**，也没有恢复、重建或触碰任何真实index。

### 主控交接

> 支持保留登记词缀和原宝石两个独立来源、原quote/commit/writer拆卸重插、完整合法wire比较及本轮绑定cold。恢复量在原Player写点通知前冻结，25被归因35的具体问题可关闭；17即时来源425恢复现已实际派发。已读范围未发现新增确证生产整改项。完整wire是JSON持久化语义等价，不是删字段或原文件字节等价；冷恢复也不自动持久化测试模块启用。当前index补档未由本会话解包复算，历史连续性FAIL保持。符文、死亡子连锁、自然组合P6/R3、supervisor安全、原B及设备/APK继续各自开放。

**实际审查范围：**读取五个生产增量的相关完整函数、来源登记配置、live/cold与恢复测试全文、原item codec／事务端口关键链、PlayerState资格与重算、三份核心最终完整回执及恢复RED关键段、expectation／handoff／runner和范围清单。**未运行Godot、修改源码或HEAD/index、启动第二reviewer／施工线程、重算3700文件及完整源码／原生ZIP，也未逐份独立复验全部82次执行。**本结论仅针对 **`source-composition-08ccdf29-20261004`**。
