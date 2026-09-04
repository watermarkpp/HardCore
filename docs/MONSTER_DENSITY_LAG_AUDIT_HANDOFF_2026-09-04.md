# HardCore 怪物密度卡顿审计交接

日期：2026-09-04

审计基线：`codex/integration` / `7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8`

当前结论：**手机实机鉴定“没有任何改变”，现有性能修复不得视为验收通过。**

## 1. 文档目的

本文不是新的修复方案，也不把尚未测量的推测写成结论。它用于把当前怪物密度卡顿问题、复现条件、地图刷新数据、运行时对象结构、每帧函数链、空间索引、视觉资源、诊断数据、已经做过但无效的优化，以及下一轮审计必须回答的问题完整交给审计者。

审计者应以手机实机表现为最终判据。自动化测试只能证明合同没有被破坏，不能证明 Android 帧时间已经改善。

## 2. 用户报告与可复现现象

### 2.1 已确认的现象

- 比奇原来约 42 只怪，现已增加到 82 条正式刷新记录。
- 沃玛森林现有 50 条普通怪刷新、4 条 Boss 刷新，共 54 条。
- 增加地图怪物刷新以后，即使只拉约 5 只怪，体验也从原先不卡变成明显卡顿。
- 玩家周围、视野内或正在追逐玩家的怪物越多，卡顿越严重。
- 用户最近缩短过怪物动作/决策间隔；怪物转向反应确实变快，不能简单把间隔改回很长来掩盖性能问题。
- 第一轮性能修复在手机上只被评价为“有改善，但改善不多”。
- 第二轮累计修复 `7f0d9f2d` 安装后，用户手机实测结论是“没有任何改变”。
- 问题不是单纯的进图首帧卡顿；核心症状是进入地图后，随附近活动怪物数量增长的持续掉帧。

### 2.2 建议使用的固定复现口径

为了避免每次跑图和拉怪数量不同导致误判，审计和后续验收应固定：

1. 同一台手机、同一 APK 配置、同一角色和同一地图位置。
2. 比奇或沃玛森林选择一条固定移动路线。
3. 分别记录附近活动怪为 0、5、10、20 只时的连续帧时间。
4. 每个档位至少采集 20–30 秒，覆盖静止、移动、转向、怪物追逐和攻击。
5. 同时记录 Godot 进程时间、物理时间、绘制调用、活动视觉数、物理移动次数、群体网格重建和候选扫描次数。
6. 比较 P50、P95、P99 帧时间和超过 16.67 ms、33.33 ms 的帧占比，不能只看某一瞬间的 FPS。

## 3. 当前正式版本与设备交付

### 3.1 Git 基线

- 本地 HEAD：`7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8`
- 远端 `origin/codex/integration`：`7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8`
- 当前性能补丁链：
  - `5bfae5eb` — `perf: stage world actor spawning`
  - `82aa5c83` — `perf(monsters): bound inactive map actor work`
  - `7f0d9f2d` — `perf(monsters): deep sleep inactive actors`
- 相关但目的不同的选敌修复：
  - `70a50cba` — `fix(monsters): stabilize threat target switching`

### 3.2 已安装的第二轮累计补丁

- Patch ID：`monster-density-performance-final-7f0d9f2d-cumulative`
- Base：`a90e405aad17e5600731f86ac44d8140c6bd79e5`
- Patch commit：`7f0d9f2d4c48a5ae6d05987b70f4088bb59ff9b8`
- 大小：`18,254,664` bytes
- SHA-256：`68E240580C6D1F163D112083507C63FA44F0E400F2AC3132381980A064F5C411`
- 设备序列号：`AADMVB3602042319`
- 安装后已确认活动 manifest 指向该补丁；应用可启动，启动阶段未发现 Godot、`AndroidRuntime` 或 `libc` 致命错误。
- 实机验收结果：**无改善。**

## 4. 地图刷新数据结构与当前数量

### 4.1 正式运行时地图

| 地图 | 运行时文件 | 普通刷新 | Boss 刷新 | 合计 | 唯一物种 | 唯一 `semantic_id` | 唯一 `spawn_group_id` |
|---|---|---:|---:|---:|---:|---:|---:|
| 比奇 | `assets/data/runtime/map_editor/world_bich_province.runtime.json` | 82 | 0 | 82 | 8 | 82 | 82 |
| 沃玛森林 | `assets/data/runtime/map_editor/world_wooma_forest.runtime.json` | 50 | 4 | 54 | 6 | 54 | 54 |

这些计数来自当前正式运行时 JSON，而不是编辑器备份文件。

### 4.2 单条刷新记录的关键字段

```text
authority_ref
classification
count
max_alive
monster_id
radius_gu
respawn_policy_id
respawn_seconds
respawn_random_seconds
semantic_id
spawn_group_id
tile
runtime_export
```

稳定身份示例：

```text
semantic_id:    mse.placement.v1.world_bich_province.monster_spawn.000001
spawn_group_id: mse.group.v1.world_bich_province.monster_spawn.000001
spawn_slot_id:  <spawn_group_id>:<copy_index>
```

### 4.3 身份问题已经独立解决

比奇新增记录过去曾复用 `spawn_group_id`。现在两张地图的 `semantic_id` 和 `spawn_group_id` 都按记录唯一，构建、保存和发布会拒绝缺失或重复身份。

结论：

- 新增怪物现在拥有合法、稳定、可追踪的编辑身份。
- 运行时个体槽位由 `spawn_group_id + copy_index` 构成。
- 旧的身份冲突是数据隐患，但不是本次持续掉帧的已证实原因。
- 不应为性能优化删除、复用或弱化稳定 ID。

## 5. 怪物权威数据结构

正式怪物目录：`assets/data/runtime/canonical_monster_catalog.json`

当前目录约 156 条怪物记录，顶层主要包含：

```text
entries
entries_by_id
appearance_profiles
drop_profiles
```

单个怪物的关键字段：

```text
monster_id
canonical_name
classification
combat.stats
combat.ai
combat.timing
combat.runtime_projection
combat.behavior_profile
appearance_profile_id
drop_profile_id
spawn_contexts
```

`GameRoot._spawn_enemy()` 使用 `monster_id` 严格读取正式目录并配置运行时 actor。性能审计不得绕过或用名称模糊匹配替代该 ID 合同。

## 6. 从地图数据到运行中怪物的创建链

```text
正式 runtime map JSON
  -> GameRoot._run_map_transition()
  -> GameRoot._run_world_build_pipeline()
  -> GameRoot._spawn_editor_runtime_content()
  -> GameRoot._submit_staged_actor_descriptor()
  -> WorldBootstrapCoordinator.submit_actor_descriptor()
  -> WorldBootstrapCoordinator.process_actor_queue()
  -> GameRoot._spawn_staged_actor_descriptor()
  -> GameRoot._spawn_enemy()
  -> EnemyActor._ready()
     -> CollisionShape2D
     -> MonsterVisual + Sprite2D
     -> MonsterOverhead
     -> 空间索引注册
     -> 普通怪后台唤醒 Timer
```

### 6.1 `scripts/game_root.gd`

关键入口：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_begin_initial_world_bootstrap()` | 1370 | 初始世界启动 |
| `_run_map_transition()` | 1461 | 地图切换、预取、构建计划 |
| `_run_world_build_pipeline()` | 1604 | 执行地图构建流水线 |
| `_spawn_database_zone_content()` | 2070 | 数据库区域内容入口 |
| `_spawn_editor_runtime_content()` | 2115 | 读取地图编辑器正式 runtime 刷新记录，按 `count/max_alive` 生成副本位置和槽位 |
| `_spawn_authored_map_content()` | 2213 | 处理手工 authored 内容 |
| `_submit_staged_actor_descriptor()` | 2438 | 提交延迟 actor 描述符 |
| `_spawn_staged_actor_descriptor()` | 2456 | 消费描述符并创建实体 |
| `_spawn_enemy()` | 2575 | 建立 `EnemyActor`、读取正式怪物数据、配置重生/地形/空间索引/信号和缓存 |
| `_respawn_later()` | 9719 | 延迟重生 |
| `_spawn_slot_is_alive()` | 9742 | 重生前检查同槽个体 |

延迟 actor 描述符结构：

```text
actor_id
actor_type
source_index
payload
```

`_spawn_enemy()` 还为节点记录出生位置、重生策略、`spawn_slot_id`、`spawn_group_id`、地图上下文、死亡快照、世界 generation 和安全区信息，并把存活敌人加入 `_active_enemy_cache`；Boss 同时进入 `_active_boss_cache`。

### 6.2 `scripts/world_bootstrap_coordinator.gd`

主要队列：

```text
_map_build_queue
_collision_build_queue
_actor_spawn_queue
```

关键配置：

```text
DEFAULT_SLICE_BUDGET_MS = 3.0
DEFAULT_MAX_ITEMS_PER_FRAME = 12
```

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `submit_actor_descriptor()` | 487 | 拒绝空 ID 和重复 ID，将描述符入队 |
| `process_actor_queue()` | 519 | 按帧处理 actor 队列 |
| `_process_staged_queue()` | 544 | 队列总调度 |
| `_process_staged_queue_slice()` | 557 | 达到单帧数量或 3 ms 预算后让出到下一帧 |

重要边界：该协调器只把“进图时一次性创建大量节点”的尖峰摊开。它不减少怪物已创建以后每帧执行的 AI、移动、物理和动画成本，因此不能单独解决稳定运行阶段“附近怪越多越卡”。

## 7. 主循环结构

### 7.1 `GameRoot`

`scripts/game_root.gd`：

- `_physics_process()`（635）主要推进持久地面效果。
- `_process()`（642）每个渲染帧执行 UI 贴图轮询、怪物视觉流式协调器、玩家约束/焦点/相机、传送保护、安全区、Boss 世界机制、目标 HUD、技能和状态等。
- 怪物视觉协调器由根节点每个渲染帧调用一次 `poll_once()`。

比奇安全区还有独立周期任务：

| 函数 | 当前行 | 频率/行为 |
|---|---:|---|
| `_tick_bich_safe_zone_enforcement()` | 2324 | 约每 0.10 秒触发 |
| `_enforce_bich_safe_zone()` | 2362 | 遍历 `_active_enemy_cache.values()` |

它已经不再每次从 SceneTree 取 group，但仍然是比奇地图上约 10 Hz 的全怪物 O(N) 扫描，属于需要测量的密度成本。

### 7.2 单个 `EnemyActor`

`scripts/enemy.gd` 中 `EnemyActor extends CharacterBody2D`。

节点大致结构：

```text
EnemyActor (CharacterBody2D)
  CollisionShape2D
  MonsterVisual (Node2D)
    Sprite2D
  MonsterOverhead
    名称/等级/血条等绘制或子节点
  BackgroundAIWakeupTimer   # 非 Boss，按需深睡唤醒
  其他机制节点/效果         # 依怪物行为而定
```

`_ready()`（1298）完成：

- 加入敌人 group。
- 设置 `CharacterBody2D` 碰撞层/掩码。
- 怪物移动掩码仅包含世界和玩家层，不做怪物之间的物理碰撞对。
- 创建碰撞形状、视觉和头顶信息。
- 普通怪创建后台唤醒 Timer。
- 初始化选敌、群体转向和后台 AI 的错峰计时。
- 满足条件时进入深睡。

`_physics_process()`（1424）是活动怪物的主热路径，包含：

```text
死亡/失效检查
后台 AI 条件判断
空间索引同步
攻击计时、状态、再生、困魔边界、延迟攻击
目标重评
Boss 机制/状态
控制和诱惑状态
目标距离与朝向
追逐、攻击或自主移动
CharacterBody2D.move_and_slide()
```

附近、已有仇恨、正在追逐或战斗的怪物不会进入后台深睡，仍以物理帧频执行这条主路径。这与用户报告的“拉到身边的怪物越多越卡”直接相关。

## 8. AI、选敌和移动节奏

### 8.1 当前主要常量

| 常量 | 值 | 含义 |
|---|---:|---|
| `CROWD_GRID_CELL_SIZE_GU` | 3.0 GU | 群体分离网格单元 |
| `CROWD_GRID_REFRESH_FRAMES` | 3 物理帧 | 共享群体网格刷新间隔 |
| `CROWD_STEERING_INTERVAL_SECONDS` | 0.10 s | 单 actor 群体转向计算间隔 |
| `NEAR_RETARGET_MIN_SECONDS` | 0.18 s | 近距离普通怪最短重评间隔 |
| `FAR_RETARGET_MIN_SECONDS` | 0.28 s | 远距离普通怪最短重评间隔 |
| `BOSS_TARGET_REEVALUATION_MAX_SECONDS` | 0.35 s | Boss 重评上限，另加实例错峰 |
| `TARGET_GRID_REFRESH_SECONDS` | 0.25 s | 战斗目标共享网格刷新间隔 |
| `ENVIRONMENT_GUARD_INTERVAL_SECONDS` | 0.10 s | 环境/安全区保护检查 |
| `BACKGROUND_AI_INTERVAL_SECONDS` | 0.25 s | 远处非活动怪后台维护间隔 |
| `BACKGROUND_AI_MIN_DISTANCE_GU` | 37.5 GU | 后台 AI 最短距离门槛 |
| `BACKGROUND_WAKE_PHASE_SLOTS` | 15 | 后台唤醒错峰槽数 |

### 8.2 选敌规则

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_retarget()` | 4256 | 候选搜集、初次选敌、仇恨与距离评分、召唤物拦截、切换迟滞 |
| `_add_threat()` | 4466 | 累加伤害来源仇恨并唤醒怪物，不再直接把当前目标改成最后攻击者 |
| `_target_switch_challenge_wins()` | 4478 | 判断挑战者是否达到稳定时间和仇恨优势门槛 |

当前切换迟滞：

```text
TARGET_SWITCH_MIN_STABLE_SECONDS = 0.45 s
TARGET_SWITCH_MIN_THREAT_ADVANTAGE = 100
TARGET_SWITCH_THREAT_ADVANTAGE_RATIO = 20%
```

选敌大致过程：

1. 当前目标失效时立即释放。
2. 已知玩家作为直接候选。
3. 从共享目标网格加入附近 `combat_targets`。
4. 保留当前目标和仇恨表中的有效弱引用目标。
5. 首次发现目标按 Ground GU 曼哈顿距离选择。
6. 战斗中以累计仇恨与距离共同评分。
7. 召唤物真实进入身体接触/挡路范围时可以强制拦截。
8. 一般挑战者必须跨过稳定窗口与绝对/相对仇恨优势后才能替换当前目标。

这套规则是为了避免人物与远程神兽交替命中时每一击都切换目标。性能修复不能恢复“最后一次受伤者立即覆盖目标”的粗暴规则，也不能以显著降低重评频率的方式让怪物再次显得笨重。

### 8.3 移动与寻路

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_request_autonomous_step()` | 689 | 移动节奏门控 |
| `_begin_autonomous_step_without_cadence()` | 747 | 开始一步移动 |
| `_terrain_neighbor_for_pursuit()` | 822 | 追逐时选择可行相邻地块 |
| `_advance_autonomous_step()` | 1100 | 推进当前移动步 |
| `_move_with_spatial_rules()` | 1971 | 应用空间规则并调用 `move_and_slide()` |

即使怪物之间不做物理碰撞，每只正在移动的附近怪物仍然是一个 `CharacterBody2D`，仍会对世界/玩家碰撞进行 `move_and_slide()`，并进行地形邻居、阻挡和空间规则判断。

## 9. 共享空间结构

当前不是只有一个统一索引，而是至少存在三套用途不同、可能重复维护的数据结构。

### 9.1 运行时战斗空间索引

文件：`scripts/runtime_combat_spatial_index.gd`

结构：

```text
_buckets: Dictionary<Cell, actor ids>
_entries: Dictionary<actor id, entry>
bucket_size: 4 GU
max bounds / diagnostics
```

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `register()` | 52 | 注册 actor |
| `update_actor()` | 99 | actor 位置变化时更新桶 |
| `query_segment_candidates()` | 135 | 线段候选查询 |
| `query_aabb_candidates()` | 156 | AABB 候选查询 |

`EnemyActor._spatial_index_update()`（1775）会在位置确实变化时更新，`set_combat_position()`（1799）用于事务式改变战斗位置。

### 9.2 怪物群体分离网格

文件：`scripts/enemy.gd`

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_crowd_separation()` | 3653 | 查询周围 3×3 网格桶并计算分离向量 |
| `_crowd_separation_for_motion()` | 3690 | 单 actor 最多约 10 Hz 计算群体转向 |
| `_ensure_crowd_grid()` | 3700 | 建立/刷新所有怪物的共享群体网格 |

当前高优先级疑点：`_ensure_crowd_grid()` 每 3 个物理帧允许重建一次，并通过 `get_nodes_in_group("enemies")` 扫描整张地图的全部怪物。60 Hz 下理论上可达约 20 次/秒的全怪物扫描。即使只有少量附近怪物请求群体分离，一次刷新仍可能扫描比奇全部 82 个 actor。

这不是已经用实机 A/B 隔离证明的根因，但它在结构上同时符合两个现象：

- 地图总怪物从 42 增至 82 后，少量附近怪物也比以前更卡。
- 附近参与移动/分离的怪物越多，卡顿继续增加。

### 9.3 目标候选网格

文件：`scripts/enemy.gd`

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_ensure_target_grid()` | 3718 | 约每 250 ms 扫描 `combat_targets` group 并刷新网格 |
| `_target_grid_candidates()` | 3760 | 按保守屏幕矩形查询网格并按稳定顺序排序 |

它减少每只怪物独立扫描目标 group 的次数，但自身仍有周期性 group 全扫描和候选排序成本。

### 9.4 需要审计的问题

- `RuntimeCombatSpatialIndex` 是否能在不改变准确性的前提下复用到 crowd/target broadphase，避免维护三套结构？
- 群体网格是否可由 actor 注册/移动时增量更新，而不是每 3 个物理帧从 SceneTree 全量重建？
- 目标网格是否能由 combat target 生命周期事件增量维护？
- 当前全量扫描、候选排序、弱引用清理各自在 Android 上占多少真实时间？

## 10. 后台 AI 与深睡

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_can_use_background_ai()` | 3861 | 判断普通怪是否足够远且没有前台战斗责任 |
| `_enter_background_deep_sleep()` | 1697 | 关闭物理处理，启动一次性 Timer |
| `_leave_background_deep_sleep()` | 1724 | 恢复前台物理处理 |
| `_on_background_wakeup_timeout()` | 1734 | 低频维护、重评并决定继续睡眠或唤醒 |

深睡会排除以下 actor：

- Boss。
- 缺少玩家上下文。
- 正在执行安全区返回。
- 正在移动。
- 当前目标不是玩家。
- 有仇恨、状态、延迟动作或其他前台责任。
- 距离没有超过后台门槛。

因此 `7f0d9f2d` 主要削减远处、空闲、未参与战斗怪物的 60 Hz 回调。用户真正感到卡顿的恰好是附近、追逐、战斗中的怪物；它们仍走完整 `_physics_process()`。这是“第二轮修复测试合同通过，但手机无体感改善”的最直接结构性解释之一。

## 11. 怪物视觉与资源常驻

### 11.1 `MonsterVisual`

文件：`scripts/monster_visual.gd`

关键参数：

```text
动作集合: idle / walk / attack / hit / death
逻辑缓存预算: 64 MiB decoded RGBA8
进入视觉资源距离: 视口外扩 320 px
释放视觉资源距离: 视口外扩 640 px
资源常驻检查周期: 0.12 s
```

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `_ready()` | 113 | 创建 Sprite2D、注册协调器、决定是否激活资源 |
| `_process()` | 280 | 活跃可见时推进动作计时、动画帧和 region |
| `_update_resource_residency()` | 305 | 判断激活或释放资源 |
| `_inside_visual_distance_px()` | 347 | 用 canvas transform 和扩展视口计算距离 |
| `streaming_residency_poll()` | 372 | 由中央协调器轮询视觉常驻 |
| `_sync_process_tier()` | 388 | 无资源的正式美术可关闭 process |
| `_activate_resources()` | 414 | 申请并绑定完整外观 profile |
| `_release_resources()` | 456 | 清理纹理/profile/lease |

关键事实：屏幕内或屏幕附近怪物仍然保留视觉资源，并在每个渲染帧执行动画状态和帧区域更新。第二轮“远处资源释放/轮询限额”不会降低当前画面中 5–20 只活动怪物的动画与渲染成本。

### 11.2 `MonsterVisualStreamingCoordinator`

文件：`scripts/monster_visual_streaming_coordinator.gd`

主要结构：

```text
request dictionary / request queue
profile cache / LRU / decoded byte accounting
prefetch pins / generation
visual subscriptions
subscriber cleanup order + cursor
visual residency order + cursor
waiters / leases / reverse maps
```

关键限制：

```text
profile cache logical budget: 64 MiB decoded RGBA8
concurrent profile loads: 2
visual residency visits per rendered frame: 12
subscriber cleanup visits per rendered frame: 8
```

关键函数：

| 函数 | 当前行 | 责任 |
|---|---:|---|
| `request_client_profile()` | 118 | 请求外观 profile |
| `poll_once()` | 223 | 每渲染帧推进异步状态、提交、加载、常驻和清理 |
| `register_visual()` | 664 | 建立视觉订阅记录 |
| `request_visual_resources()` | 719 | 请求视觉资源 |
| `declare_visual_need()` | 754 | `registered -> waiting` |
| `notify_visual_applied()` | 791 | `waiting -> leased` |
| `release_visual_resource()` | 826 | `leased/waiting -> registered` |
| `_poll_visual_residency()` | 1120 | 有界轮询常驻状态 |
| `monster_streaming_diagnostics()` | 1263 | 返回资源/轮询诊断 |

订阅记录主要字段：

```text
weakref
monster_runtime_id
runtime_map_id
world_generation
resource_key
resource_paths
stable_visual_order
resource_state
```

## 12. 当前设备诊断证据

现有快照：`outputs/device_lab/post_perf_82aa5c83_snapshot.json`

这是第一轮性能补丁后的一个瞬时快照，不是同路线、同怪物数量的完整前后对照，因此只能作为规模线索。

### 12.1 怪物活动

| 指标 | 数值 |
|---|---:|
| 当前地图 | 比奇，map 910001 |
| 检查到的怪物 | 67 |
| 1600 px 内 | 34 |
| 2000 px 内 | 49 |
| 判定可后台 AI | 65 |
| 活动视觉资源 | 12 |
| 群体网格构建 | 18 |
| 群体网格 actor 扫描 | 1362 |
| 群体候选 | 32 |
| 群体转向计算 | 20 |
| 旧式选敌全扫描 | 197 |
| 后台 AI 计算 | 13568 |
| 物理移动 | 6539 |
| 环境保护检查 | 936 |

`1362 / 18 ≈ 75.7`，说明当时每次群体网格重建接近扫描地图上的全部怪物，而不是只扫描玩家附近的活动怪物。

### 12.2 引擎和渲染指标

| 指标 | 数值 |
|---|---:|
| FPS（瞬时） | 59 |
| process time | 35.734 ms |
| physics process time | 14.854 ms |
| node count | 2618 |
| object count | 9204 |
| resource count | 909 |
| render objects | 872 |
| render primitives | 6033 |
| draw calls | 226 |
| texture memory | 919,175,337 bytes |
| video memory | 927,946,593 bytes |
| buffer memory | 8,771,256 bytes |

注意：64 MiB 是怪物流式协调器的逻辑 RGBA8 预算，不等于引擎总纹理显存。约 919/928 MB 的总纹理/视频内存也包含地图、角色、UI 等资源，不能在未做资源归因前全部算到怪物头上。但它足以说明必须审计实际 GPU 资源常驻、上传和带宽，而不能只看协调器的逻辑预算。

### 12.3 流式资源指标

| 指标 | 数值 |
|---|---:|
| registered visuals | 67 |
| leased visuals | 12 |
| leased profiles | 4 |
| decoded RGBA8 | 141,983,744 bytes |
| protected overbudget | 74,874,880 bytes |
| ready resources | 5 |
| pin rejections | 6 |

即使逻辑预算为 64 MiB，快照中的 decoded RGBA8 已是约 135.4 MiB，并有约 71.4 MiB protected overbudget。需要核对预取 pin、活跃 lease 和完整五动作 atlas 的保护关系，以及 Android 上真实纹理是否能及时释放。

## 13. 诊断盲区

`scripts/device_lab_runtime.gd` 的诊断桥接使用字段白名单。

### 13.1 当前能导出的 Enemy 字段

```text
crowd_grid_builds
crowd_grid_actor_scans
crowd_query_candidates
crowd_steering_evaluations
retarget_full_scans
background_ai_evaluations
physics_moves
environment_guard_checks
```

### 13.2 `EnemyActor.performance_diagnostics()` 已有但设备快照未导出的关键字段

```text
retarget_decisions
retarget_target_group_scans
retarget_target_candidates
background_fast_path_skips
foreground_ai_ticks
background_deep_sleep_entries
background_deep_sleep_wakeups
```

### 13.3 流式协调器已有但设备快照未导出的关键字段

```text
coordinator_poll_count
heavy_poll_execution_count
subscriber_cleanup_visit_count
subscriber_cleanup_max_visits_per_poll
visual_residency_visit_count
visual_residency_max_visits_per_poll
map pin / generation 相关计数
```

因此现有手机快照无法回答第二轮补丁最核心的问题：到底有多少怪物真正进入深睡、每秒唤醒多少、前台 actor tick 是否下降、视觉常驻与清理是否真的被限额。下一轮应先补齐测量，再判断实现，而不是继续凭测试中的模拟计数推断实机收益。

## 14. 已做优化、作用范围与实机结论

### 14.1 `5bfae5eb`：分帧创建世界 actor

修改：

- `scripts/game_root.gd`
- `scripts/world_bootstrap_coordinator.gd`
- 对应启动测试

作用：将地图进入时的 actor 构建限制为每帧最多 12 项或 3 ms。

边界：改善启动/切图尖峰，不直接处理进入地图后附近怪物的持续每帧成本。

### 14.2 `82aa5c83`：限制非活动地图 actor 工作

修改：

- `scripts/enemy.gd`
- `scripts/monster_visual.gd`
- `scripts/monster_visual_streaming_coordinator.gd`
- 密度和流式专项测试

作用：远处非活动怪物进入 0.25 s 后台路径、共享缓存、有界资源清理/常驻处理。

实机结论：用户评价只有轻微改善。

### 14.3 `7f0d9f2d`：远处非活动 actor 深睡

修改：

- `scripts/enemy.gd`
- `scripts/monster_visual.gd`
- `scripts/monster_visual_streaming_coordinator.gd`
- 对应密度/群体/流式测试

作用：远处空闲普通怪关闭 60 Hz `_physics_process()`，由 Timer 低频唤醒；中央视觉常驻每帧最多访问 12 个订阅，清理最多访问 8 个订阅，并延迟创建部分辅助对象。

实机结论：用户明确鉴定“没有任何改变”。

### 14.4 为什么自动化通过仍可能完全无体感

- 测试证明深睡状态、轮询上限和合同存在，不证明用户附近的追逐怪进入了这些路径。
- 用户的卡顿 cohort 是前台活动怪；深睡优化主要作用于远处空闲怪。
- 启动分帧不处理稳定运行热路径。
- 流式访问限额不减少当前屏幕上活跃视觉每帧动画和绘制。
- 现有设备快照字段缺失，不能验证第二轮补丁的核心计数。

## 15. 当前测试证据与限制

在 `7f0d9f2d` 上运行的 7 个专项测试全部通过，Godot 引擎错误为 0：

```text
monster_runtime_density_performance_test
monster_cadence_runtime_integration_test
monster_crowd_performance_test
monster_target_acquisition_test
monster_retarget_spatial_cache_test
monster_streaming_scaling_test
monster_streaming_registration_lifecycle_test
```

结果文件：`outputs/test_logs/runner_results_adhoc_20260904_151259.json`

局限：

- 这些测试主要检查函数合同、计数上限、行为正确性和模拟规模。
- 它们不是 Android GPU/CPU profile。
- 它们没有复现同一手机、同一路线、0/5/10/20 活动怪的帧时间曲线。
- 测试通过与用户手机“无改善”不矛盾；后者说明优化没有击中真正瓶颈。

## 16. 按优先级排列的待审计假设

以下均为**待验证假设**，不是已经确认的根因。

### P0：附近活动怪仍是完整 60 Hz 热路径

每只附近追逐/战斗怪仍执行：

```text
EnemyActor._physics_process()
  + 目标/状态/环境判断
  + 移动步推进
  + CharacterBody2D.move_and_slide()
MonsterVisual._process()
  + 动作计时
  + 动画帧推进
  + Sprite2D region/状态更新
```

需要分别测出单只活动怪增加的物理时间、脚本时间和渲染时间。

### P0：群体网格约 20 Hz 全地图重建

`_ensure_crowd_grid()` 的 `get_nodes_in_group("enemies")` 全量扫描是最明显的结构性 O(N) 热点之一。需要用 Android profile 或可控开关证明它的时间占比，并验证改成增量索引后 5/10/20 只附近怪的帧时间是否下降。

### P0：活动怪视觉/纹理/绘制成本

屏幕附近怪物保留五动作资源并每帧更新。需要拆分：

- GDScript 动画推进成本。
- Sprite/CanvasItem 提交与批处理情况。
- 不同怪物 atlas/材质是否破坏批处理。
- 实际纹理常驻和上传峰值。
- 关闭怪物视觉但保留 AI/物理时，卡顿是否显著消失。

### P1：比奇安全区 10 Hz 全怪扫描

`_enforce_bich_safe_zone()` 仍遍历 82 个缓存 actor。单独看数量不大，但与群体网格、目标网格、环境保护叠加后可能造成周期性尖峰。

### P1：每个活动 actor 的环境、地形和 `move_and_slide()`

需要判断主要成本来自：

- `CharacterBody2D` 物理移动。
- 地形邻居/阻挡选择。
- 安全区几何检查。
- 拥挤状态下重复尝试失败移动。

### P1：重复空间结构和 group 扫描

战斗空间索引、群体网格、目标网格分别维护。审计应量化重复注册、位置转换、桶构建、group 扫描和排序，而不是只看单个函数。

### P1：节点/对象规模

快照为 2618 个节点、9204 个对象。每只怪物不仅是一个逻辑条目，而是 `CharacterBody2D + CollisionShape2D + Visual + Sprite + Overhead + Timer/机制节点`。需要按类统计对象数与 process/physics_process 启用数。

### P2：重生检查

`_spawn_slot_is_alive()` 会调用 `get_nodes_in_group("enemies")`，但只在重生路径发生，不符合“拉 5 只持续卡”的第一嫌疑，除非现场同时存在大量集中重生。

### P2：设备实验室轮询

设备实验室本身有低频轮询和按命令生成快照，但在没有持续发快照命令时不应是主要热路径；仍可在 release/关闭实验室的对照包中排除。

## 17. 下一轮审计必须做的可证伪实验

不应直接再写第三版“可能更快”的代码。建议先制作只用于审计的可控构建，在相同场景逐项二分隔离：

| 实验 | 保留 | 暂时关闭 | 可以回答的问题 |
|---|---|---|---|
| A | AI + 物理 | 怪物视觉绘制/动画 | 卡顿主要是否来自渲染 |
| B | 视觉 + AI | 怪物 `move_and_slide()` | 卡顿主要是否来自物理移动 |
| C | 视觉 + 物理 | crowd steering/grid rebuild | 全量群体网格占比 |
| D | 正常前台怪 | 远处全部怪 actor | 地图总量与附近 cohort 的耦合程度 |
| E | 正常怪物 | 比奇安全区全怪 sweep | 10 Hz 周期尖峰占比 |
| F | 正常逻辑 | 仅换低资源占位视觉 | atlas/材质/纹理带宽占比 |

要求：

- 每个实验只改变一个维度。
- 不把实验开关合入正式玩法。
- 每档采集 0/5/10/20 只附近活动怪。
- 同时记录 CPU/GPU 帧时间，不能只看 FPS。
- 在测量完成前不改变怪物反应间隔、选敌规则、地图刷新数量和稳定 ID。

## 18. 建议补充的计数与采样

下一轮诊断至少应输出以下“每采样窗口增量”，不能只输出进程启动以来的累计值：

```text
foreground_ai_ticks / second
background_deep_sleep_entries / exits / wakeups
active physics_process EnemyActor count
active MonsterVisual process count
physics_moves / second
move_and_slide total time / call count
crowd_grid_builds / second
crowd_grid_actor_scans / second
crowd_query_candidates / second
retarget_decisions / second
retarget_target_group_scans / second
retarget_target_candidates / second
environment_guard_checks / second
safe_zone_actor_scans / second
visual animation updates / second
visual residency visits / second
draw calls / render primitives
CPU process / physics time
GPU frame time if available
texture/video memory
```

采样数据还必须同时带：

```text
map_id
total monster actors
nearby monster count by fixed distance
moving monster count
combat/aggro monster count
active visual count
player position
camera zoom
build commit and patch id
```

## 19. 不可破坏的约束

- 不得通过把怪物 AI、转向、选敌刷新重新拉长到明显迟钝来换帧率。
- 保持当前仇恨累计、切换迟滞和召唤物身体拦截规则。
- 保持怪物绕过碰撞/地形的现有正确行为。
- 不删除用户新增的比奇和沃玛森林刷新。
- 保持所有新增刷新拥有唯一合法 `semantic_id`、`spawn_group_id` 和稳定运行时 slot。
- 不修改怪物属性、掉落或地图几何来伪造性能改善。
- 不把自动化测试通过等同于手机验收。
- 性能改动必须在同设备、同路线、同怪物档位下证明 P95/P99 帧时间改善。

## 20. 给审计者的核心问题

请审计者基于代码和实际 profile 回答，而不是泛泛给出“减少 AI 频率”建议：

1. 当比奇总怪物从 42 增至 82 后，为什么只拉 5 只怪也从不卡变卡？是哪条全地图 O(N) 工作被附近活动怪触发？
2. `_ensure_crowd_grid()` 每 3 个物理帧全量扫描 `enemies` 是否是主要热点？能否用已有 `RuntimeCombatSpatialIndex` 或生命周期增量结构替代？
3. 对 5、10、20 只活动怪，`EnemyActor._physics_process()`、`move_and_slide()`、crowd、retarget、environment guard 各占多少毫秒？
4. 对同一批怪，`MonsterVisual._process()`、CanvasItem 提交、draw call、纹理带宽和 atlas 切换各占多少？
5. 为什么协调器逻辑预算为 64 MiB，快照 decoded RGBA8 为约 135 MiB、protected overbudget 约 71 MiB，而引擎总 texture/video memory 接近 0.9 GiB？哪些资源实际不能驱逐？
6. 远处深睡为什么没有改变用户体验？是因为真正卡顿 cohort 全部处于前台，还是深睡根本没有在手机运行？现有诊断盲区如何先补齐？
7. 比奇安全区 10 Hz 全怪扫描、目标网格 250 ms group 扫描和群体网格约 20 Hz 全怪扫描是否产生叠加尖峰？
8. 能否把怪物逻辑更新分层为“感知/决策低频、移动/动画按需、碰撞连续”，同时保持当前转向和选敌手感？
9. 哪个最小实验能在一次手机运行中明确区分 AI/物理瓶颈与视觉/GPU 瓶颈？
10. 第三轮正式修复的验收指标应是什么，怎样证明优化击中了附近活动怪而不是只优化了远处空闲怪？

## 21. 当前结论

当前已经能够排除两种错误判断：

1. **不是刷新身份重复导致的卡顿。** 身份已经合法唯一，身份修复应保留。
2. **不能认为远处深睡已经解决问题。** 手机实测明确无改善，而且现有诊断还没有证明第二轮核心路径在设备上实际发生。

目前最需要验证的不是“再把某个间隔调大一点”，而是附近活动怪的完整热路径，以及地图总怪物数量如何通过全量 crowd/target/safe-zone 扫描影响少量附近怪。下一步必须用固定场景、分档怪物数和可证伪的二分实验，把 AI/物理与视觉/GPU 成本拆开后再决定正式实现。
