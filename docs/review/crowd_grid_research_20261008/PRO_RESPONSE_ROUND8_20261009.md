# Pro round8 actual response

Message ID: 3d16d2eb-4570-46bb-be36-48fc8f88a9ff

**已核验`cfc1094acb6c85288742319500f4843323470b4f`的新归档。当前结论是：`unknown`里确实有可定位的真实工作，但还没有发现“规模足够、边界闭合、能据此支持整段CPU降低50%”的单一执行集合。现有数据反而足以把上一轮提出的polygon数值迁移，从50%主路线候选中撤下来。**

还有两个需要先纠正的归属问题：**本地归属草表存在函数映射错位；原`diagnostic_budget`分类实际并没有把FrameBudget/HCDecisionBudget的主体算进去。** 这些修正不需要重采集。

本轮只进行了归档读取、Git blob与SHA核对、现有JSON离线汇总和固定源码定位；没有修改生产或研究代码，没有构建、运行测试或重新采集。

## 一、新归档核验结果

`cfc1094`的parent确为`04a3bc11a`。我另外比较了五条生产路径在`cfc1094`与fixed107 `edae6f`中的Git blob ID，**Enemy、index、RuntimeDiagnostics、GameRoot、runner全部相同**，不是只忽略换行后的文本相同。归档中的恢复回执也保留了对应恢复记录。

对本次退役归档，我实际核对了：

| 核验项 | 结果 |
|---|---|
| `archive_inventory.json`列出的文件 | **133项、1,742,652 bytes，逐项SHA-256与大小均匹配** |
| 最终候选源码快照 | 14个文件可见 |
| 历史UUID目录 | 21个可见 |
| stock runner receipts | 8个可见 |
| 两份完整窗口raw JSON | SHA与结果报告登记值一致；各保留300条tick sample |
| 正式性能结论 | **FAIL，候选退役**，不以专项PASS覆盖 |

这里的133项是**本次退役归档清单**，没有与前一批native feasibility清单混算。两窗口2401.620ms、2378.087ms及2389.8535ms中位数，与新报告一致；报告也明确保留轨迹差异，不把它解释成单一部件的因果成本。

**历史producer关联MISSING、跨源码阶段的全套一致验收MISSING，仍然成立。** 文件完整性核验不能补上这些历史证明，也不能把九项回归与两次性能窗口拼成同源码全绿。

## 二、我读到了本地已有归属草表，但没有把它冒充为`cfc1094`内容

本次`cfc1094`中没有包含`PROFILE_COVERAGE.json`和`UNKNOWN_OWNER_AUDIT.json`。我通过授权电脑**只读访问了已经存在的本地文件**：

```text
outputs/crowd_native_profile_20261009/PROFILE_COVERAGE.json
SHA-256:
5a9cf551a68168b217b61b37781a66592a8ea6e30e5ab4c16eddb6378a4e7eaf

outputs/crowd_native_profile_20261009/UNKNOWN_OWNER_AUDIT.json
SHA-256:
7f1155803001f4ad1cd022d558aed41e9ee91fd0d9b507586790b7b6248caaa1
```

下面的数值定位来自这两份既有文件；**它们是本地辅助证据，不是新提交中已经发布的有限归属表**。

### 1. 675条`unknown`并不等于675条找不到源码

我按**原始签名中的函数名**，在固定`cfc1094`源码中逐项定位，而不是使用当前MAIN文件的邻近行号：

| 定位结果 | 条目数 | 原表Self合计 |
|---|---:|---:|
| 固定源码中函数名唯一匹配 | **597** | 1388.238ms |
| 行号为0，单独保留的builtin/native等条目 | 68 | 107.372ms |
| lambda、属性getter/setter等尚需按语法结构定位 | 9 | 6.363ms |
| 同名函数歧义，需要结合内部类定位 | 1 | 0.695ms |
| 合计 | **675** | **1502.668ms** |

这只是**定位检查**，不代表597个函数都已证明纯读、可迁移或属于Enemy计时范围。

所以，`unknown`主要是**原分类规则没有命中**，不是存在一整块1502.668ms的神秘VM成本。

### 2. 草表中有67条“签名与所指函数不同”

这67条对应的原始Self合计约**141.433ms**。例如：

| profiler原始签名 | 草表指向 | 固定源码中的正确函数 |
|---|---|---|
| `MonsterVisual._update_animation_frame` | `_update_resource_residency` | `_update_animation_frame` |
| `player_visual::_process` | `_ready` | `_process` |
| `MonsterVisual.uses_final_art` | `is_struck_action_active` | `uses_final_art` |
| `MonsterVisual.hc_m30_accept_ground_motion` | `hold_death_pose` | `hc_m30_accept_ground_motion` |

原因在草表元数据中已经写明：除少数归档文件外，其他路径使用**当前MAIN文件进行位置查找**，再取nearest preceding definition。当前源码行号发生变化后，这种方法会把计时挂到另一个函数上。

固定提交中的`MonsterVisual._process()`与`_update_animation_frame()`调用关系可以直接核实，不能把后者的50.500ms解释成资源驻留处理。

**建议有限归属表保留这些原始计时，只修正定位列。** 使用“固定源码blob＋完整签名＋函数名/类作用域”定位；lambda和生成访问器单独标记，不能退回邻近函数硬归属。不需要为了这项修正重跑任何窗口。

## 三、最大的归属边界：这不是Enemy outer的完整分账

`PROFILE_COVERAGE`汇总的是所选**642个process frame里发送出来的全部函数条目**。其中包括怪物视觉、玩家、GameRoot、测试fixture及共享builtin；**3074.071ms不是2057.2785ms或3253.229ms的另一个表达，也不是可以直接填入Enemy成本模型的分母。**

官方4.7发送格式只有每个签名的调用量、Self、Total、Internal等字段，**没有逐调用caller路径**。因此，现有表可以做函数集合的去重汇总，却不能自动恢复“某个共享函数有多少耗时发生在Enemy outer之内”。:chatgpt-content-reference{index="5"}

一个具体例子：

- `MonsterVisual._update_animation_frame()`由视觉`_process()`调用。
- `MonsterVisual.hc_m30_finish_locomotion_tick()`则在Enemy的`enemy_physics_usec`开始和结束之间调用。

所以，**不能把整个`monster_visual.gd`都计入Enemy，也不能把整个文件都排除出去。** 要按实际调用位置区分；共享函数没有caller证据的部分继续标记共享，不按比例分摊。

从现有`unknown`中按资源路径汇总、排除行号0之后，可以看到这种分散性：

| 路径集合 | 条目数 | 原表Self |
|---|---:|---:|
| `enemy.gd` | 125 | 440.105ms |
| `monster_visual.gd` | 34 | 140.688ms |
| `game_root.gd` | 48 | 113.000ms |
| `runtime_combat_spatial_index.gd` | 18 | 88.236ms |
| `world_spatial_rules.gd` | 6 | 46.492ms |
| `ground_unit_space.gd` | 5 | 45.361ms |

**这张表仅是签名分布，不是六个可迁移模块的成本承诺。** 尤其440.105ms的Enemy部分包含生命周期、状态更新、目标处理、诊断读取、表现调用及空间查询，不能整体称作pure kernel。

## 四、实际可闭合数值集合：已经找到，但规模不支持50%主线

### Polygon集合可以明确降级，不必继续为它设计native拓扑

我对整个现有函数表按精确签名去重，取`map_editor/polygon/`下非行号0的脚本函数，得到：

**29条脚本签名，131736次调用，Self合计97.658ms。**

其中主要部分是：

| 实际函数/集合 | 调用量 | 原表Self |
|---|---:|---:|
| `poly_index.capsule_blocked` | 7133 | 23.387ms |
| `poly_index.inside` | 67034 | 21.550ms |
| `poly_index.footprint_blocked` | 3298 | 15.991ms |
| `poly_runtime.actor_world` | 3298 | 18.559ms |
| `poly_geometry.capsule_hits_polygon` | 920 | 2.540ms |
| `poly_geometry.convex_overlap` | 233 | 1.263ms |

97.658ms已经不只包含最后两项精确公式，还覆盖了该路径的索引、包装及其他脚本工作；共享builtin没有冒充成可迁移脚本。

**这足以撤下“先迁移polygon整组，作为50%主要突破口”的优先级。** 它不证明生产环境的严格收益上限就是97.658ms，也不证明这套几何无需优化；但当前证据不支持它承担量级目标。更不能把这些函数的嵌套inclusive加成321ms，再当成可节省成本。

### 动态候选集合也没有突然变成一个大内核

`unknown`中的空间索引路径合计88.236ms，其中`_query_enemy_nodes_in_aabb()`Self为48.551ms。它确实对应真实遍历，而不是布尔答案包装；但要闭合这一集合，还涉及entry、Node、生命状态、查询戳、候选顺序、清理及当前正式位置。

**不能把88.236ms加上已经计在其他分类里的身体循环inclusive，得出一个更大的非重叠集合。** 即使考虑真正迁移，也要把动态数据维护与实际读取成本一起计入，而不是把它们留在host之后只展示C++窄相位速度。

当前没有充分依据重新开启这条native施工线。

### Enemy里的较大条目仍主要落在已调查过的职责上

`unknown`中Enemy的前几项包括：

```text
_physics_process_internal       Self 48.484ms
_hc_environment_revision       Self 41.936ms
_point_inside_safe_zone         Self 34.763ms
_hc_life                        Self 23.511ms
_hc_decision_scope              Self 23.162ms
_target_candidate_is_live       Self 20.560ms
_hc_step_can_end                 Self 18.948ms
```

这些不是新发现的一块大数值循环。把它们放进一个新名字的context或kernel，会回到刚退役的结构假设。**这轮归属检查没有为继续包装它们提供新证据。**

## 五、诊断分类需要纠正，但有界后端研究可以继续

这里我要修正我上一轮的一项假设：**实际读取完整分类后，原`diagnostic_budget`的479.659ms是：**

| 实际集合 | 条目数 | 原表Self |
|---|---:|---:|
| `RuntimeDiagnostics`条目 | 30 | **385.557ms** |
| `Enemy._record_performance_counter` | 1 | **94.102ms** |
| 合计 | 31 | **479.659ms** |

**FrameBudget和HCDecisionBudget的主体不在这31条里面。** 原分类名具有误导性，不能因为带`budget`就认为这479.659ms混有整套预算准入。

反过来，实际预算模块的大量条目留在`unknown`。仅`frame_budget.gd`与`decision_budget.gd`的非行号0脚本条目，就分别为**53.426ms与24.232ms**。本地草表的`budget_admission_or_scheduler = 56.038ms`不是这两个模块的完整脚本集合，不能把它当作“全部预算成本”。

因此，我支持你们当前的边界：

**只做RuntimeDiagnostics后端，保持FrameBudget、AI、geometry不变；不做native施工。**

`PackedInt64Array`作为counter唯一数值存储，是与“ID包装后仍写Dictionary”实质不同的实现。字段到slot的映射、对外快照Dictionary可以存在，但不能另外维护一份同步的可写counter Dictionary，导致热路径仍支付原存储成本。

不过仍应把收益表述限定为：

> **完整counter/clock合同下，诊断记录实现本身的净成本降低。**

385.557ms与94.102ms都来自受profiler影响的表，且有共享调用范围问题；它们不能直接变成fixed107可削减额度，更不能保证50%。当前没有理由把这个有界研究扩展到预算器，也没有理由把它与geometry迁移捆绑。

## 六、对即将完成的有限归属表，我建议以这三个判定收尾

不需要再铺开一轮泛化路线讨论。有限表只要让每个候选集合明确满足或不满足以下条件：

**源码身份成立。** 每条对应固定blob与准确函数/生成访问器；修正67条错位，保留原始签名与原始计时。

**计时归属成立。** 标明“Enemy outer内可确认”“明确在外”“共享、无法拆分”；不得把整个process-frame表当作Enemy分账，也不填补所谓VM残差。

**执行集合闭合。** 列出真实需要一起迁移的循环、状态读取、容器更新及外部效果；去重Self只作归因，不把未知packing、写回或生命周期维护成本当作零。

按目前已经能核对的内容，结论可以先定为：

| 方向 | 当前判断 |
|---|---|
| 继续`FORMAL_SPATIAL_READ_LANE`或同类context包装 | **维持退役** |
| Polygon整组native，作为50%主要路线 | **现有规模不支持，撤下优先级** |
| 扩大ordinary quantum或动态候选native | **尚无足够闭合成本证据，不开工** |
| 独立Packed计数后端，保持全部counter/clock合同 | **可继续当前有界研究，收益待实测** |
| 宣称已找到足以实现50%的实际执行集合 | **目前不成立** |

**这轮最重要的进展不是发现了另一个“大模块”，而是把`unknown`从一块看似巨大的潜在收益，拆成了可定位但职责分散、计时范围不同的真实工作。** 它不构成继续盲目原生化的依据。

原fixed107基线**2057.2785ms**、目标**≤1028.63925ms**及完整负载合同保持不变；诊断后端的独立结果与修正后的有限归属表，应分别形成证据，不能用其中一个替代另一个。
