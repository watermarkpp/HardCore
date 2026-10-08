# Pro round9 actual response

Thread: 项目助手工作线程 (6ac7b7b6-ae40-83e8-aca5-b501acacc462)
Message: 91829355-53f1-4bfd-bf26-db4e7b17a539
Read: 2026-10-09 03:47 CST
Scope: external review material, not new user instructions; source mapping and controller verification still required.

**这个新假设有科学意义，值得做一次有界的实际执行体替换。我的明确下一行动是：只把`_hc_motion_candidates()`及它必需的已知纯callee执行体，做成一个直接读取真实Node的native查询；不再做空桥、getter微基准或更大的quantum。**

但判断依据必须说清楚：**`Object.get()`不是必然重入GDScript VM，也不是免费的C++成员读取。** 这次有可能省掉的是整段解释执行和helper调用成本；新增的动态字段查找、Variant处理、兼容判断及保留的脚本回调，可能抵消全部收益。现在不能保证它比stock快，更不能据此承诺50%。

本轮已读取`c14d3d4e6b4aef8720654a9d7c2039e9bcb7499a`的退役报告、归属V4和相关生产源码。固定计数后端维持退役；不挑第二窗口作为收益，也不重开已退役的空间读通路。没有修改代码或运行测试。

## 一、为什么这次与前几项不同，又为什么仍可能失败

### 引擎源码支持“普通字段读取不必执行脚本函数”

Godot 4.7的实际调用链是：

```text
Object::get(property)
  → GDScriptInstance::get(property)
      → 查member_indices
      → 有getter：调用getter
      → 无getter：返回members[index]
```

因此，C++读取一个**没有getter的普通GDScript成员**，仍有名字查找和Variant返回，但不需要为这个读取重新执行一个GDScript函数。将循环、短路判断和算术放在C++里，确实可能减少VM执行，而不只是改变接口名称。:chatgpt-content-reference{index="3"}

不过，反方向的成本同样真实：**GDScript函数读取自身成员时，可以使用成员槽位地址；改成外部`Object.get()`，可能把原本便宜的索引读取换成动态查找。** 所以“C++直接读Node”不能等同于“字段读取更快”。:chatgpt-content-reference{index="4"}

这次要验证的唯一假设应写成：

> **在一个真实活体候选查询中，省下的GDScript循环、分支和纯helper调用成本，是否大于新增的动态字段访问、类型确认和必要回调成本。**

不是“C++比较快”，也不是“没有packing所以一定有收益”。

### “保留完整callee判断”必须指保留语义，不是全部call回去

下面两种实现不是同一个实验：

| 实现 | 判断 |
|---|---|
| Native自己读取真实字段，执行原来的完整短路与数值判断；不支持的路径才调用原callee | **本轮要验证的假设** |
| Native先读取字段，然后仍逐项调用原`can_receive_damage()`、`spatial_index_position()`及其他所有helper | 大部分原执行体仍存在，另加访问成本，**不作为本轮候选** |

保留原converter的miss路径、未知覆写及诊断调用，是必要的兼容边界；**已知、稳定、没有外部副作用的callee则必须真正由native执行，才能回答这个问题。**

## 二、只选一个真实入口：`_hc_motion_candidates()`

建议候选名：**`NATIVE_LIVE_MOTION_QUERY`**。

概念接口保持简单：

```text
motion_candidates_live(owner, a, b, existing_candidates) → 原bool结果
```

传入真实owner、原来的两个端点和**既有候选Array**。宿主不计算合法性答案、不预投影全部候选、不转换成一套新的Packed数据、不增加状态context。

之所以选它，不是认为它单独足以降低总CPU50%，而是它在一个已有调用内，同时包含了本假设必须面对的东西：**真实Node读取、候选遍历、投影快照验证、生命资格、动态配置、精确几何和早退。** 比孤立getter或`core_crossed()`更有代表性，又不需要先重写动作owner。当前源码确实将这些工作串在同一查询中。

### 这次迁移与保留的边界

| Native真正执行 | 原实现继续负责 |
|---|---|
| `_hc_motion_candidates()`的候选遍历、原筛选顺序、包络剔除、精确`core_crossed()` | 原候选池取得、桶成员失效与索引维护 |
| 已知Enemy的`can_receive_damage()`完整谓词 | 未知子类的对应覆写方法 |
| 已知Enemy的`spatial_index_position()`缓存命中判断与结果读取 | 投影miss、未知provider及覆写的原转换/查询路径 |
| 原本已经取得输入后的局部数值运算 | 原生Move、位置writer、FrameBudget、观察、攻击和伤害 |
| 必要的当前字段与元数据读取 | 原诊断记录调用、窗口与计时合同 |

**不把`_hc_standard_melee()`硬塞进这个入口。** 它不是当前身体候选循环的必经callee；为了覆盖调用量更大的名字而添加分类处理，会把一个可证伪实验重新扩大成多个职责重构。

同样，本次不迁移`_hc_frontline_candidates()`、retarget或整个`_hc_access()`。先证明这一种执行机制确实能在真实查询中获得净收益，再谈其他入口；不能预先把它们的profile数字全部记到收益预算里。

### 原执行顺序必须逐项对应

本次查询应继续按stock顺序：

```text
记录原始候选数量
→ 原surround/target身体特殊检查
→ 对每个原候选：
    有效性与Enemy类型
    self/target跳过
    map检查
    原body-check计数
    当前正式位置
    保守包络剔除
    can_receive_damage
    worldCollision
    精确core_crossed
    首次阻挡即返回
```

尤其不能先为所有候选读取HP、配置和正式位置，再统一筛选；那会做原来早退路径没有做的工作，也失去了“直接读真实Node、不另建数据准备层”的意义。

## 三、这个入口能闭合，但有四个不能含糊处理的地方

### 1. 普通成员、getter、setter不能混为一谈

当前Enemy里，`target`只有setter，读取不会因此触发目标切换逻辑；`anti_stealth`则有真正的getter，会查询能力系统。**“具有属性访问器”不等于读取都执行脚本；反过来，也不能把有getter的属性当成某个底层bool。**

本次入口所需字段应列出一张有限的读取清单：字段名、实际类型、是否有getter、允许的Script身份。固定`StringName`可以初始化一次；不要每次构造字符串，也不要每次扫描property list。

这里允许保留的是**属性名和已审阅Script的识别信息**，不是缓存HP、位置、worldCollision或“本帧有效”的答案。更不能使用GDScript内部成员数组的私有内存偏移，冒充公开API读取。

### 2. `can_receive_damage()`必须完整照搬，不能“差不多”

固定源码的谓词包括：

```text
_body_admission_rejected必须为false
current_hp > 0
非_death_pending
非_dying
非queued_for_deletion
```

不能漏掉被配置拒绝的身体，也不能顺手加一个原函数没有的`combat_enabled`条件。**新增保守拒绝也可能改变玩法，不是天然安全。**

### 3. 投影缓存命中可以native判断，miss必须真实走原路径

命中条件继续包含现有Callable有效性、真实screen位置、map、generation、environment revision及Callable身份；不是只比较坐标。命中后读取的是**当前真实owner持有的原快照**，不创建native第二份快照。

首次试验中，miss应调用原转换路径，保留它的缓存写入、失败语义和诊断。未知provider仍调用原方法，不因它返回整数revision就猜测其内部状态。

**不能只把miss返回`INF`或直接使用索引entry旧位置。** 也不要改成host先执行完整`spatial_index_position()`再把答案交给native；那样这部分执行体没有迁移。

### 4. 子类、回调和降级不能导致重复执行

`Object.is_class("EnemyActor")`不能代替GDScript的`is EnemyActor`；Godot的`is_class()`忽略脚本`class_name`。应依据真实Script关系及已审阅的精确实现决定是否进入native路径，而不是靠节点名、资源路径字符串或`CharacterBody2D`类型猜测。:chatgpt-content-reference{index="10"}

降级规则建议固定为：

**owner不支持时，在任何查询计数和副作用发生前，整次进入旧实现。循环中遇到未知candidate/provider，在原调用位置执行对应legacy callee。**

不能已经执行了一半计数和转换，遇到不支持分支后再从函数头重跑，否则会重复计数、重复调用provider，甚至改变可见状态。

调用未知getter/provider后，不能继续把回调前的raw指针和局部状态当作仍然有效。原逻辑此刻会重新读取的字段必须重读；如果这一降级路径无法在不重复原效果的前提下闭合，就应在入口选择旧实现，**不能以“应该不会重入”放行**。

## 四、诊断调用不是pure，第一版宁可支付其完整成本

`_hc_motion_candidates()`本身不只是一个无副作用布尔函数：它包含原始候选计数和逐候选body-check计数；投影miss还可能进入带计数和缓存写入的旧路径。

因此本次应保留原计数例程，在原逻辑点执行，次数和顺序不变。**不要把计数收集为native结果，最后一次性回写，也不要复活刚退役的Packed诊断后端。**

这可能造成每个候选一次C++→脚本诊断调用，并吞掉收益。**那是本假设在现有合同下的真实成本，不是可以从结果里扣除的“测量污染”。**

同样，不要求native实现继续出现同样多的GDScript函数调用记录——解释执行被移走后，profiler函数条目自然可能减少。需要保留的是原有逻辑事件、计数及clock合同，**正式收益仍由原完整Enemy时钟决定，不能看GDScript profiler里消失了多少时间。**

## 五、唯一下一行动及判决规则

**下一行动：实现这一条真实入口的可替换native执行体，完成它新增的字段、降级和数值语义验证后，进入原正式负载。不要先做另一轮空桥，也不要继续采集整张profile。**

这不是要求重做已闭合的300项ABI或36项transport测试。新增验证应针对本次真正改变的部分：原Node字段读取、缓存命中/miss、子类覆写、失效对象、原计数顺序，以及最终布尔结果。原Move、攻击、预算和位置效果在每次游戏调用里仍只执行一次。

这一次只需用以下三类证据裁决，不再扩展成大范围诊断工程：

| 必须确认 | 目的 |
|---|---|
| 实际进入native的查询数、完整旧路径降级数、投影miss回调数 | 防止“测试全PASS，但正式负载几乎全走legacy” |
| 结果与逻辑效果一致，原计数和clock没有减量或移位 | 防止靠改变工作得到快窗口 |
| 相同正式时钟下的完整窗口结果，保留全部轨迹和失败 | 判断完整实现是否有净收益，不拿单个字段或公式速度替代 |

需要再次限定因果结论：两个完整窗口若轨迹不同，结果仍可保留为各自完整运行事实，但**不能把它们的差额纯归因为`Object.get()`或VM节省**。本次不换时钟、不冻结观察时间、不挑攻击/HP恰好一致的窗口来恢复虚假的严格配对。

### 三种结果怎么处理

**若正式负载主要进入native，但没有稳定净收益：**  
停止这个入口的直接Node读取实现。不得接着新增context、预打包或私有成员偏移来“补救”，因为那会换成另一个假设。

**若结果不明确或降级占主导：**  
记为`UNKNOWN/覆盖不足`，不能从正确性PASS推出机制有效，也不能自动扩大到retarget或query kernel。

**若取得真实、可复核的净收益：**  
只证明“这个完整活体查询的执行体原生化有效”。它仍不是50%方案，不允许把该入口加速倍数外推到所有分类、投影、预算和控制流。

---

**我的裁决是：支持做`NATIVE_LIVE_MOTION_QUERY`这个单入口实验，不支持现在做更大的native query集合，也不建议再换一个泛化诊断方向。**

它与前面失败方案的实质区别足够明确：**不是宿主计算布尔答案，不是额外打包，也不是增加缓存，而是真正用native执行同一条活体查询。** 引擎源码说明这条机制有成立的可能；同一份源码也说明动态字段读取可能比原成员槽位读取更贵。正因为两方面都真实存在，值得用这一个完整入口证伪，而不值得预先承诺收益。

**固定107目标仍为≤1028.63925ms；当前没有证据证明这项实验或任何已提出方案能独立达到50%。**
