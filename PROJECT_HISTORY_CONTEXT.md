# HardCore PROJECT_HISTORY_CONTEXT
# 核心工程历史、已裁决设计与 Freeze 上下文
# Codex / GPT-5.6 Sol 必读

> 当前事实核验基线：`codex/integration` @ `ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c`（2026-08-08）。
>
> 本文中的阶段 HEAD、测试数量和待办状态如果带有明确历史日期，表示当时证据；当前状态必须以 `PROJECT_CURRENT_STATUS.md` 为准。

> 本文件不是代码架构教程。
>
> 它记录 HardCore 项目已经发生过的重要工程整改、已经做出的设计裁决、曾经踩过的错误路线，以及当前哪些合同已经冻结。
>
> 后续模型不得因为没有看到历史对话，就重新推翻已经经过验证的核心设计。
>
> 当前源码与当前证据永远高于旧文档；如果本文路径/函数与当前 HEAD 不一致，应验证当前源码并更新本文，而不是根据本文强行修改代码。

---

# 1. 项目核心目标

HardCore 是基于 Godot 的《传奇》1.76 风格复刻/扩展项目。

当前工程阶段不是重新设计游戏，而是：

```text
CORE STABILITY FREEZE
```

当前核心目标：

> 核心框架没有结构性错误；
> 当前已经制作的内容稳定可玩；
> 后续增加地图、怪物、装备和技能时，不需要再次推翻底层。

因此现在评价代码的标准不是：

```text
能否继续抽象
能否更加优雅
GameRoot是否足够小
是否还能消除重复
```

而是：

```text
有没有真实生产Bug？
有没有结构性错误？
有没有真实性能瓶颈？
未来正常扩展是否被当前架构阻塞？
```

如果答案都是否：

```text
DO NOT REFACTOR
```

---

# 2. 游戏世界基础合同

游戏地图采用：

```text
64 × 32 tile
2:1 isometric
Godot Iso View
固定摄像机
```

正式地面逻辑单位：

```text
GU = Ground Unit
```

一个非常重要的历史问题是：

项目曾长期混用：

```text
Screen Position
Screen Delta
Ground Delta
Map-relative Ground
Map-global Ground
```

导致：

```text
动画覆盖目标
但伤害判定不到

不同方向技能长度不同

Enemy / Projectile / GroundEffect
使用不同空间语义
```

这个问题已经经过 FREEZE-P0 系列系统整改。

当前冻结合同：

```text
POSITION
=
runtime map absolute / map-global Ground GU

DELTA / DIRECTION
=
Ground Delta
```

任何模型不得重新把：

```text
screen delta
```

当成：

```text
absolute ground position
```

使用。

---

# 3. 直线技能正式设计决定

当前正式参数：

```text
战士刺杀：
2.5 × 1 GU

法师地狱火：
5 × 1 GU

法师疾光电影：
8 × 1 GU
```

宽度：

```text
1 GU
中心线 ±0.5 GU
```

用户已经明确决定：

## 刺杀

保留：

```text
全局锁定
自动转向
```

当前效果已经可接受。

位置站错导致打不到：

```text
属于合理玩法
```

不得为了“百分百自动命中”加入释放前自动移动。

---

## 地狱火 / 疾光电影（历史决策，已被后续正式设计取代）

最终决定：

```text
按玩家当前面向方向释放
```

`SUPERSEDED BY CURRENT DEVICE-ACCEPTED DESIGN`：该段只保留为历史记录，不再代表当前 Gameplay 或 Presentation 方向合同。当前正式合同见本文件第 46 节与 `PROJECT_CORE_CONTRACTS.md`。

不做全系统16方向改造。

原因：

这两个技能原作本身就是需要：

```text
玩家站位
队友拉怪
手动瞄准
```

的难用技能。

这种操作难度属于技能本质，不是Bug。

因此：

```text
不要因为技能不好瞄准
重新建立16方向世界系统。
```

---

# 4. Q0：测试可信度与 Safe Logout

## Q0-A Test Trust Gate

曾发现：

```text
测试Runner自身可信度不足
```

因此建立：

```text
Runner self-test
正式suite registration
错误识别
timeout识别
```

最终阶段 HEAD：

```text
0969a7ff...
```

2026-08-08 的后续 Runner Allowlist Gate 又由 `9a174d14...` 完成 suite identity、adhoc 隔离、timeout 硬范围与注册集合守卫，并由 `ec057c52...` 正式记录为 `CLOSED`。

其核心意义：

> 测试系统本身必须可信，否则“全绿”没有意义。

---

## Q0-B / Q0-B.1 Safe Logout

历史问题：

安全退出失败时曾允许：

```text
current position fallback
```

这意味着：

正式安全点解析失败后仍可能保存危险位置。

最终删除该fallback。

正式合同：

```text
安全位置解析失败
=
明确失败
```

不得静默保存当前危险位置。

最终阶段 HEAD：

```text
4d5e41fdbd656a78933be566d585434c88657294
```

Runner也不得通过ERROR allowlist掩盖Safe Logout真实失败。

---

# 5. Q1：Snapshot V2

## Q1-A

建立严格Snapshot validator。

最终：

```text
8a26c30f
```

---

## Q1-B / Q1-B.1

将正式生产Snapshot统一迁移至：

```text
Schema V2
```

正式核心合同：

```text
schema_version = 2

runtime_map_id
=
typed integer

coordinate_space
=
runtime_map_absolute_ground_gu
```

正式mapped world：

```text
STRICT_V2
```

不得重新启用：

```text
Schema V1 production fallback
legacy_ground_gu
silent conversion
```

最终：

```text
44ba2303...
```

---

# 6. Q2：Combat Runtime 收口

## Q2-A Projectile BroadPhase

历史问题：

Projectile可能通过：

```text
get_nodes_in_group("enemies")
```

进行敌人全扫描。

最终改成：

```text
scripts/runtime_combat_spatial_index.gd
RuntimeCombatSpatialIndex
→ BroadPhase
→ Snapshot exact Narrow Phase
```

并处理：

```text
same-frame actor movement
```

一致性。

最终：

```text
19524313...
```

---

## Q2-B Persistent GroundEffect

持续地面效果统一：

```text
scripts/persistent_ground_effect_manager.gd
PersistentGroundEffectManager
→ Shared RuntimeCombatSpatialIndex
→ exact Snapshot
→ Damage
```

正式GroundEffect不得恢复通用全敌扫描。

最终：

```text
b77fb2c4...
```

---

## Q2-C FireWall

FireWall曾存在多Visual Cell共同参与Gameplay的风险。

最终正式架构：

```text
FireWallFieldController
=
唯一Gameplay owner

每个tick：
一次BroadPhase
→ canonical 2×2 snapshot exact
→ claim
→ damage
```

四个Visual Cell：

```text
PURE VISUAL
```

不得：

```text
自己tick伤害
自己claim
自己扫描enemy
```

最终：

```text
97f47286...
```

---

## Q2-D Monster Streaming

历史问题：

每个MonsterVisual可能各自进行全局streaming poll。

最终：

```text
GameRoot
→ scripts/monster_visual_streaming_coordinator.gd
→ one MonsterVisualStreamingCoordinator
→ one global poll per frame
```

MonsterVisual：

```text
不得恢复per-instance global poll
```

最终：

```text
d6cd31c6...
```

注意：

历史上曾记录与 Streaming 有关的 apply-order race，详见第 20 节。当前正式状态已更新为 `HOLD`：它不是 active must-fix 或 next gate，不授权自动 20-run，也不授权生产修改。

---

# 7. Q3：Canonical Skill Runtime

这是整个技能系统最重要的一次收口。

阶段：

```text
Q3-A
Q3-B
Q3-C
```

最终正式架构：

```text
Input
→ GameRoot
→ SkillRuntimeRouter
→ one canonical planner
→ Canonical Skill Execution Plan
→ Gameplay Commit
→ CasterSkillRuntime
→ SkillExecutionResult
```

旧的正式Production Legacy APIs已经删除。

最终阶段：

```text
Q3-A
bafdaf0d...

Q3-B
c1bc7a15...

Q3-C
9ceb2f61...
```

冻结原则：

```text
ONE Planner
ONE release geometry
ONE canonical execution plan
ONE execution result
```

不得因为增加一个新技能：

```text
创建第二Planner
建立第二套技能几何
建立特殊release path
恢复legacy production API
```

---

# 8. FREEZE-P0：全局坐标语义冲突

在第一次完整外部源码审计中发现：

虽然大量测试已经全绿，

但存在真正的P0结构问题：

```text
MapEditor / GameRoot
使用真正absolute Ground GU

Enemy / Projectile / Summon
部分路径却使用screen delta inverse
然后声明成absolute Ground GU
```

因此：

```text
RuntimeCombatSpatialIndex
实际上被喂入混合坐标语义
```

这是典型：

> 测试全绿，但架构语义仍然错误。

---

## FREEZE-P0

Enemy / Projectile / Summon / Plan：

改为正式map-aware absolute conversion。

FireWall旧delta compatibility shim删除。

增加：

```text
nonzero map design center
```

验证。

最终：

```text
83f17aa7...
```

---

# 9. FREEZE-P0.1：Projection Fail-Closed

随后又发现：

mapped world缺projection时，

部分路径仍可能静默fallback。

因此：

```text
Enemy
Projectile
Summon
FireWall
Plan
GameRoot
Caster
```

统一：

```text
missing mapped projection
=
REJECT
```

不得默默使用delta/raw值。

最终：

```text
ad843730...
```

---

# 10. FREEZE-P0.2：一次错误方向，以及后来的纠正

P0.2曾尝试：

给大量 authored/reference maps 建 projection profiles。

最终：

```text
9f75a084...
```

但随后用户明确指出：

> 很多地图只是原版资料/规划数据，并没有真正制作。

典型：

```text
338 毒蛇山谷
```

当前实际上是：

```text
UNBUILT
```

不能因为：

```text
WorldContent有记录
地图ID存在
原版spawn数据存在
```

就把它定义为正式可玩地图。

这是项目中非常重要的一次纠偏。

---

# 11. FREEZE-P0.2R：正式地图状态重新定义

最终建立：

```text
REFERENCE_ONLY
PLANNED_UNBUILT
IMPLEMENTED_STAGING
IMPLEMENTED_PLAYABLE
```

等语义。

正式Gameplay只接受真正：

```text
runtime-built
+
formal playable
```

地图。

当时确认正式制作完成的地图共11张：

```text
4    比奇省
217  兽人古墓一层
218  兽人古墓二层
221  兽人古墓三层
268  沃玛森林
313  沃玛寺庙一层
314  沃玛寺庙二层
315  沃玛教主大厅
406  矿区一层
408  矿区二层
1578 尸王殿
```

注意：

这个“11”不是永远硬编码的数字。

后续正式地图数量必须：

```text
动态读取Release Registry
```

而不是写死11。

最终：

```text
7ff18f2e...
```

---

# 12. FREEZE-P0.3：Map Release Registry

随后发现：

正式地图列表仍硬编码在：

```text
MAP_CONFIG
```

未来新增地图仍然需要改核心代码。

因此建立正式：

```text
map_runtime_release_registry.json
```

正式可玩状态开始由数据驱动。

正式地图要求：

```text
registry state正确
runtime有效
build hash一致
map key一致
```

旧manual-ready marker不再是正式Authority。

最终：

```text
fec9c6fa...
```

---

# 13. FREEZE-P0.3R：Build Candidate 与 Publish 正式分离

P0.3再次外部审计后发现：

MSE Build仍可能直接写正式runtime。

这意味着：

```text
Build
```

有可能意外替换：

```text
Published Runtime
```

这是不可接受的。

最终正式建立：

```text
MSE Edit
↓
Build Runtime Candidate
↓
Validate
↓
Publish Runtime Release
↓
Release Registry
↓
formal gameplay
```

Candidate输出：

```text
outputs/map_runtime_candidates/<key>/<hash>.runtime.json
```

Build：

```text
不得改变正式runtime
不得改变registry
不得改变formal playable状态
```

Publish：

```text
candidate promotion
+
registry transaction
```

如果registry commit或postcondition失败：

```text
rollback runtime
+
rollback registry
```

同时：

正式Registry loader必须先：

```text
validate_release_registry
```

非法Registry：

```text
fail closed
```

MSE UI最终也建立真实：

```text
构建 Runtime 候选
发布为正式地图
```

两步流程。

最终阶段：

```text
8ac4b9a3...
```

这个架构现在是地图系统的重要冻结合同。

---

# 14. 地图Authority正式结论

正式地图真值：

```text
Map Runtime Release Registry
```

以下内容不得作为：

```text
formal playable authority
```

包括：

```text
WorldContent
RegionContent
maps.json
map_design_catalog
legacy map_connections
原版地图资料
原版spawn资料
```

它们可能是：

```text
reference
planning
authoring input
```

但：

```text
REFERENCE != IMPLEMENTED
```

尤其不要再次因为：

```text
地图ID存在
```

就判定该地图必须进入当前Freeze。

---

# 15. FREEZE-G0：45个失败的真正意义

第一次Freeze G0时，

两个已知Wizard旧测试修复后，

完整非Critical扫描出现：

```text
45 failures
```

不能简单得出：

```text
项目还有45个Bug
```

因此进行了专门分类。

最终结果：

```text
大量obsolete / future / editor / test infra
```

不属于当前Gameplay Freeze。

经过G0.1/G0.1V后，

真正当前Production Defect只剩：

```text
B030
B038
```

---

# 16. B004 / B037

## B004

Character Select touch scroll测试失败。

最后证明：

生产正式路径：

```text
shared TouchScrollSupport
```

工作正常。

旧测试却直接：

```text
inject launcher._input
```

而STABLE_ID策略下该旧路径本来就主动return。

最终：

```text
B004
=
CONFIRMED_TEST_INFRASTRUCTURE_DEFECT
```

不得修改生产Character Select代码来迁就这个旧测试。

---

## B037

HUD Inventory touch scroll测试失败。

生产实际：

```text
Inventory采用lazy load
```

正式打开Inventory之后：

```text
InventoryScroll存在
Touch scroll正常
```

旧测试在：

```text
GameHUD.new()
```

后立即扫描错误树范围，

没有经过正式lazy-load路径。

最终：

```text
B037
=
CONFIRMED_TEST_INFRASTRUCTURE_DEFECT
```

同样：

不得修改生产HUD来迁就Fixture。

---

# 17. B030 PlayerVisual遮挡层

真实生产Bug：

```text
PassiveProcSkillEffect
z_index = 1
```

而正式：

```text
equipment_actor_visual_sort_unit_v3
```

要求所有actor composite visual：

```text
z = 0
```

否则可能：

```text
人物已经被墙遮挡
但Passive Proc特效浮在墙前
```

最终：

```text
z_index
1 → 0
```

并增加：

```text
passive_proc_actor_plane_contract_test
```

正式进入：

```text
player_visual_contract_critical
```

Critical：

```text
241 → 242
```

最终相关HEAD：

```text
e6786c35...
```

这个合同已经冻结。

---

# 18. B038 SkillPanel AssignmentHint

真实Production UI Bug：

1280×720时：

```text
AssignmentHint.right = 1234
parent.right = 1224

overflow = 10 px
```

根因不是简单：

```text
文字太长
```

而是：

```text
Label autowrap OFF
+
font theme variation在size之后才建立
```

导致size计算时仍按16pt最小宽度钳制。

正式修复：

```text
theme variation
先于 size

AUTOWRAP_WORD_SMART
```

没有：

```text
clip text
全局缩字体
magic 10px修补
```

增加：

```text
skill_panel_assignment_hint_layout_contract_test
```

并进入：

```text
skill_panel_layout_critical
```

Critical：

```text
242 → 243
```

最终：

```text
7e3d5fde42e5aeedf422a5eb1d54905e12649ec0
```

---

# 19. FREEZE-G0.3 当前完成内容验收

在：

```text
7e3d5fde...
```

进行了只读验收。

结论：

```text
Confirmed Current Production Blockers = 0
```

当前正式地图：

```text
11 / 11 static acceptance PASS
```

代表性Combat地图：

```text
4
218
1578
```

spawn、Spatial registration、absolute snapshot context正确。

Critical：

```text
243 / 243 PASS
```

已有不止一次完整干净运行。

---

# 20. Monster Streaming 历史Race与当前HOLD

专项20次历史证据：

```text
17 PASS
3 FAIL
```

失败：

```text
apply order mismatch at 0
```

已有证据表明：

```text
request sequence稳定

thread completion / application order
偶发变化
```

当时曾暂时分类为：

```text
PRODUCTION_RACE
```

但最终资源结果正确，因此不能看到“PRODUCTION_RACE”四个字就直接改代码。若未来有正式状态重新激活该问题，仍必须先判断：

```text
这个race是否造成玩家可见最终错误？
```

当时允许的最终分类边界为：

```text
FREEZE_BLOCKING_PRODUCTION_RACE

NON_BLOCKING_PRESENTATION_ORDER_RACE

TEST_CONTRACT_TOO_STRICT

TEST_INFRA_RACE
```

如果只是内部 callback apply 顺序不稳定，但每个 Visual 最终资源、动作、方向和帧都正确，不应为了测试顺序重构 Streaming。只有会造成错误纹理、动作、方向、死亡动画重启、资源串到其他 Visual 或最终 visual 错误时，才可能成为 Core Freeze blocker。

当前正式状态（2026-08-08）：

```text
Monster Streaming = HOLD
NOT_NEXT_GATE
NOT_ACTIVE_MUST_FIX
20_RUN_NOT_AUTHORIZED
PRODUCTION_CHANGE_NOT_AUTHORIZED
```

保留 17/20 与 3/20 的历史证据，但不得写成 `CLOSED`，也不得自动重新执行或修改生产代码。只有更晚的正式状态明确 re-activate 后，才重新进入裁决。
---

# 21. Orc Tomb / World Bootstrap Flake

曾在完整批跑偶发出现：

```text
shutdown
prefetch
dummy renderer RID
```

问题。

专项：

```text
20 / 20 PASS
0 engine error
```

测试断言本身稳定。

当前分类：

```text
RENDERER_ENVIRONMENT_NOISE
```

属于：

```text
headless dummy renderer shutdown
```

环境噪声。

不要无证据修改WorldBootstrap production architecture。

---

# 22. Runner Audit已关闭，剩余守卫债非阻断

Runner过去已经整改过，并于 2026-08-08 完成 Allowlist Gate：

```text
RUNNER_ALLOWLIST_GATE = CLOSED
commit = 9a174d14015268e570bf687ddf3e14aad440f314
formal documentation HEAD = ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c
confirmed_runner_blockers = 0
```

当前正式合同：

```text
23 public suites
TestPaths = adhoc only
TimeoutSeconds = 1..60
formal suite identity isolation = PASS
monster_streaming_critical = direct suite available
monster_streaming_critical excluded from default critical while HOLD
```

历史正式 smoke：

```text
player_visual_contract_critical
PASS / EXIT_CODE_0 / 1_OF_1
```

Registration guard 仍有：

```text
NON_BLOCKING_TEST_INFRA_DEBT
```

它不是当前 Runner blocker。未来若继续检查 Engine ERROR allowlist，仍不得增加新的全局宽泛 allowlist；应优先使用 fixture scoped、renderer scoped、shutdown scoped 规则。
---

# 23. Test执行成本规则

项目曾出现：

```text
TimeoutSeconds = 1800
```

这种错误施工方式。

正式规则：

普通Fixture：

```text
30秒
```

确有证据的重Fixture：

```text
最多60秒
```

不要通过：

```text
1800秒
```

隐藏hang。

---

## 完整Critical

正常最终回归：

```text
Critical × 1
```

即可。

不要机械：

```text
Critical × 5
```

因为当前一次完整Critical约20分钟。

明确怀疑的flake：

```text
只单跑对应测试
10～20次
```

这样更高效。

---

# 24. World Actor Spawn

目前存在一个可能的架构债：

```text
部分正式actor spawn
可能仍为同步生成
```

不要预设这是Bug。

正确下一步：

```text
MEASURE FIRST
```

在：

```text
当前最重正式地图
普通地图
地下城
Boss房
```

测：

```text
actor count
spawn total ms
largest synchronous chunk
world load time
```

如果实际没有明显长帧：

```text
ACCEPT
```

不得因为“异步更先进”建立新的spawn架构。

---

# 25. RuntimeCombatSpatialIndex 已知非阻断债

曾注意：

```text
_max_actor_bounds_gu
```

可能只增长。

理论上可能导致：

```text
经历一个特别大的actor后
BroadPhase候选范围长期偏大
```

目前没有真实性能证据。

因此：

```text
ACCEPTED PERFORMANCE DEBT
```

不是当前Freeze blocker。

只有profiling证明真实性能问题才施工。

---

# 26. GameRoot

GameRoot目前仍然较大。

这是：

```text
ACCEPTED ARCHITECTURAL DEBT
```

不属于：

```text
必须Freeze前拆分
```

不要为了：

```text
Single Responsibility美观
```

把GameRoot重新拆成大量Manager。

除非发现：

```text
真实ownership冲突
真实Bug
实际扩展阻塞
```

---

# 27. Canonical Runtime 内部兼容

当前内部仍可能有少量：

```text
legacy-shaped compatibility
```

但正式public production legacy APIs已经清除。

因此：

```text
ACCEPTED DEBT
```

不要为了完全消灭“legacy”字样重新做Q3。

---

# 28. GroundEffect旧扫描分支

历史审计曾发现：

GroundEffect内部可能仍保留一个旧式full enemy scan分支。

当前正式manager-owned production路径不可达。

因此：

```text
future cleanup
```

而不是Freeze blocker。

如果要处理：

必须先证明：

```text
production reachable
```

---

# 29. 地图编辑器长期扩展合同

未来制作新地图的正确方式：

```text
MSE Edit
→ Build Candidate
→ Validate
→ Publish
→ Release Registry
```

不是：

```text
修改GameRoot
修改Enemy
修改Projectile
修改GroundEffect
修改FireWall
修改Skill Runtime
```

才能支持新地图。

如果新增正常地图必须修改这些核心系统：

才说明当前地图架构存在问题。

---

# 30. 地图参考资料与Runtime必须分开

旧设计文档可能包含：

```text
原版尺寸
原版地图规划
旧地图scale
旧MSE方案
```

这些可作为：

```text
reference / audit
```

但不能覆盖当前正式Runtime。

例如：

历史文档曾有旧Bich尺寸。

当前Runtime如果已经采用新的正式尺寸：

```text
当前Runtime + Registry
```

优先。

---

# 31. 资产制作规则与地图Runtime不是同一问题

项目美术地图资产采用：

```text
64×32
2:1 isometric
```

大型地图资产长期生产规则包括：

```text
一批次
=
一张源图
=
一次生成

方向相关素材：
NW / NE / SE / SW
完整四方向

禁止用镜像/旋转冒充方向版本
```

这些属于：

```text
CONTENT PRODUCTION
```

不要把美术资产规则与：

```text
Map Runtime coordinate architecture
```

混为一谈。

---

# 32. 用户明确不希望的工程风格

用户不希望Codex：

```text
为了学习而制造练习
为了架构纯洁而重构
让用户人工阅读大量代码找Bug
为了两个技能重构整个方向系统
为了未来可能发生的问题提前造复杂框架
```

用户真正评价标准：

```text
我要的效果实现了吗？
当前系统稳定吗？
后面加内容需要推翻吗？
```

---

# 33. Token使用原则

HardCore项目非常大。

禁止默认：

```text
全仓全文扫描
```

标准工作方式：

```text
PROJECT_CURRENT_STATUS.md
↓
PROJECT_HISTORY_CONTEXT.md
↓
PROJECT_INDEX.md
↓
找到Subsystem
↓
rg精准检索
↓
读取真实调用链
↓
只打开相关源码
```

只有发现：

```text
跨系统证据
```

才扩大读取范围。

---

# 34. Freeze证据合同

所有正式施工继续使用：

```text
artifacts/construction_evidence/<task_id>/<final-short-head>/
```

必须记录：

```text
baseline HEAD
branch
tracked dirty
untracked

before reproduction
真实调用链

changed files
functions
reasons

diff

所有test command
results

suite registration

after scans

remaining risks

final HEAD
status
```

---

# 35. 状态词

只能使用：

```text
NOT_STARTED
IN_PROGRESS
BLOCKED
PARTIAL
CLOSED
```

不能：

```text
大概完成
应该没问题
基本关闭
```

---

# 36. CLOSED条件

不得仅因为：

```text
修改完成
单测PASS
```

就写CLOSED。

正式关闭需要：

```text
最终修改已commit

FINAL HEAD确定

tracked clean

在FINAL HEAD重新跑最终测试

runner evidence：
git_head == final HEAD

suite registration正确

remaining risk诚实记录
```

---

# 37. Frozen Target原则

已经进入Freeze合同的对象：

不得：

```text
为了另一个任务顺手改
```

跨领域问题应该：

```text
STOP
→ 单独task
```

不得一次任务把：

```text
Streaming
Runner
Map
Combat
UI
```

全部顺手改掉。

---

# 38. 当前正式Freeze状态

截至当前核验基线：

```text
HEAD:
ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c
```

已确认：

```text
FREEZE-G0.3 = CLOSED
RUNNER_ALLOWLIST_GATE = CLOSED

Current Confirmed Production Blockers = 0
Confirmed Runner Blockers = 0
New Must-Fix = 0
```

问题状态：

```text
B030 = CLOSED
B038 = CLOSED
B004 = CONFIRMED_TEST_INFRA
B037 = CONFIRMED_TEST_INFRA
```

Monster Streaming：

```text
HOLD
NOT_NEXT_GATE
NOT_ACTIVE_MUST_FIX
20_RUN_NOT_AUTHORIZED
PRODUCTION_CHANGE_NOT_AUTHORIZED
```

Runner：

```text
23 public suites
formal suite identity isolation = PASS
registration guard weakness = NON_BLOCKING_TEST_INFRA_DEBT
```

新的正式 Pending Freeze Gates：

```text
1. World Actor Spawn performance measurement
2. Final G1 audit
3. Android device acceptance
```

但当前用户已明确暂停全部 Freeze 工作，因此上述 Gates 只表示正式顺序，不表示已授权开始。
---

# 39. 当前不要做的新功能

在CORE FREEZE关闭之前，

不要开始：

```text
新地图大批制作
装备系统扩展
圣物系统
徽章系统
大量新技能
大量新怪物
```

当前优先：

```text
把核心Freeze真正闭口。
```

---

# 40. CORE FREEZE之后

只有：

```text
Final G1 PASS
Android Device Acceptance PASS
Confirmed Production Blockers = 0
```

后，

才允许：

```text
CORE STABILITY FREEZE = CLOSED
```

然后正式转向：

```text
地图内容
怪物
Boss
装备
圣物
徽章
词缀
技能内容
掉落
美术
平衡
```

核心框架转入：

```text
MAINTENANCE MODE
```

---

# 41. Codex每次接任务前必须问自己的4个问题

```text
1. 这是当前真实生产Bug吗？

2. 有可重复证据吗？

3. 当前Frozen Contract真的无法满足需求吗？

4. 还是代码仅仅“可以写得更漂亮”？
```

如果只是第4种：

```text
DO NOT MODIFY.
```

---

# 42. Codex标准接管阅读顺序

每次新会话：

```text
1.
PROJECT_CURRENT_STATUS.md

2.
PROJECT_HISTORY_CONTEXT.md

3.
PROJECT_INDEX.md

4.
如果涉及核心合同：
PROJECT_CORE_CONTRACTS.md

5.
根据PROJECT_INDEX只读目标Subsystem文件

6.
使用rg寻找直接caller/callee

7.
再决定是否扩大读取范围
```

禁止：

```text
新会话
→ 从scripts/开始全仓扫描
```

---

# 43. 当前下一项正式Gate与授权边界

历史上 Monster Streaming Race 曾被列为下一项只读裁决，但该状态已被更晚正式记录覆盖。

当前正式下一门：

```text
WORLD_ACTOR_SPAWN_PERFORMANCE
```

正确方式仍是：

```text
MEASURE FIRST
```

不得预设同步 spawn 是 Bug，也不得因为“异步更先进”先建立新架构。

当前执行授权：

```text
ALL FREEZE WORK = PAUSED BY USER
WORLD ACTOR SPAWN = NOT_STARTED
MONSTER STREAMING = HOLD
```

在用户重新授权前，不开始 World Actor Spawn，不自动执行 Monster Streaming 20-run，也不修改相关生产代码。
---

# 44. 最终原则

这个项目已经经历过多轮：

```text
发现问题
→ 修复
→ 外部审计
→ 再发现深层问题
→ 收紧合同
```

最大的经验是：

> 测试全绿不代表架构一定正确；
> 但代码还能优化，也不代表必须继续重构。

当前阶段必须同时避免两个极端：

```text
看到全绿就完全不审计

以及

因为还能找到技术债就永远不Freeze
```

现在的正确标准是：

```text
真实生产Blocker
=
必须解决

真实性能问题
=
必须解决

结构性扩展阻塞
=
必须解决

Test Infra
=
单独处理

环境噪声
=
正确隔离

Accepted Debt
=
记录，不施工

代码美化
=
Freeze后再说
```

---

# 45. Recent Wizard Skill Rehydration Findings

本节记录 2026-08-08 依据当前 Git ancestry、局部 diff、当前文件与 blame 完成的技能施工复原。它只记录仓库事实，不替代正式运行测试或设备验收。

## 雷电术

```text
PREVIOUS_FIX_PRESENT_IN_CURRENT_HEAD

width_scale = 0.62
height_scale = 1.0

active visual profile = sky_strike
```

当前无 Git 证据证明该修复后来被覆盖。当前状态：

```text
PRESENT / NOT CURRENTLY VERIFIED ON DEVICE
```

## 疾光电影

当前 HEAD 中仍存在：

```text
8×1 canonical geometry
Beam restore
visible-axis-start anchor
snapshot-origin alignment
presentation override
```

关键修复仍存在于 HEAD。构建边界必须明确区分：

```text
v64 build commit 551b21d8
predates later Beam restore / E-W anchor fixes

old v64 APK != evidence of current HEAD behavior
```

当前状态：

```text
PREVIOUS_FIX_PRESENT_IN_CURRENT_HEAD
DEVICE_BUILD_VERSION_REQUIRES_VERIFICATION
```

## 地狱火

历史提交 `546c3a70` 曾对 `CONTINUOUS_WIZARD_LINE_SKILLS` 强制：

```text
maximum_targets = -1
```

后续提交 `d33b0e0d` 将生产目标上限重新改为：

```text
maximum_targets =
int(effect.get("maximum_targets", -1))
```

当前 `wizard.hellfire` effect 仍生成：

```text
maximum_targets = 0

target_limit_policy =
all_intersecting_effect_cells
```

当前 canonical target selection 中：

```text
maximum_targets = 0

if maximum_targets == 0:
    return targets
```

该提前返回发生在连续条带 candidate / intersection scan 之前。因此当前正式仓库级分类为：

```text
HELLFIRE_CANONICAL_TARGET_REGRESSION
=
REPOSITORY_PATH_REGRESSION_PROVEN
RUNTIME_EFFECT_PENDING_VERIFICATION
```

不得直接写成：

```text
CONFIRMED_PLAYER_VISIBLE_BUG
```

因为尚未运行正式释放测试；也不得写成：

```text
NOT_A_BUG
```

因为代码路径冲突已经有直接证据。

2026-08-08 用户随后在当前 Android 实机版本确认了玩家可见现象：地狱火能够释放动画和 Gameplay Geometry，但没有造成伤害。集成测试改用生产 effect 的真实组合：

```text
maximum_targets = 0
target_limit_policy = all_intersecting_effect_cells
```

修复前该测试在“地狱火未命中连续五格直线内首个目标”处稳定失败。提交 `13821799` 在 canonical target selection 中先解析显式 `all_intersecting_effect_cells` 策略，再处理通用 `maximum_targets = 0` 禁用语义。修复后确认：条带内前后两个目标均受伤、条带外目标不受伤；缺少显式策略的 `maximum_targets = 0` 仍返回空目标。

当前分类更新为：

```text
HELLFIRE_CANONICAL_TARGET_REGRESSION
=
FIX_IMPLEMENTED
AUTOMATED_VERIFICATION_PASS
DEVICE_ACCEPTANCE_PENDING
```

---

# 46. Wizard Line Presentation Alignment

2026-08-08 的当前正式设计取代了“地狱火 / 疾光电影按玩家面向方向释放”的旧决策：

```text
Hellfire / Laser:
Target-Aligned Continuous Canonical Geometry

Direction source:
current valid locked target

Gameplay:
continuous / arbitrary direction

Presentation:
must consume the same canonical release geometry

Character animation:
may remain 8-direction

Gameplay line geometry:
must not be quantized to character directions
```

本轮专业提交 `14bb52f5` 只修正 Presentation：地狱火去除源帧世界锚点偏移，疾光电影用 16 路源素材的逐帧可见 alpha 轴作为源基底，再连续映射到同一 canonical snapshot 的投影轴、起点与实际长度。Gameplay origin / axis / length / width、锁定、目标选择、伤害和半透明 Geometry Debug Band 均未修改。

当前自动验证：focused arbitrary-angle alignment `PASS`；既有 wizard line suite 与相关 caster visual tests `PASS`。最终状态仍需新的 Debug APK 实机肉眼验收，因此当前为：

```text
IMPLEMENTATION_PRESENT
AUTOMATED_ALIGNMENT_PASS
DEVICE_ACCEPTANCE_PENDING
```

Wizard Line Presentation 施工本身没有修改 `maximum_targets`；随后独立提交 `13821799` 已修复其 canonical target-selection 顺序，并通过自动验证。最终仍需新 APK 实机确认伤害恢复。
