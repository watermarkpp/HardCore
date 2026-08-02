# COMBAT-UNIT-V1.0 全项目施工审计

## 0. 完工结论（2026-08-03）

审计列出的底层混用现已完成迁移：玩家、怪物、AI、锁定、战士几何、法师连续直线、投射物、地图安全区和运行时地图输出均使用正式 GU/GS/PX 合同。旧字段只保留在带版本号的单向数据适配入口，正式运行时静态门禁已通过。

最终证据见 `docs/combat/combat_geometry_audit.md`。集成回归结果为：职业技能 `16/16`、UI 接口 `5/5`、战士/法师 `25/25`、地图 `32/32`、怪物 `18/18`、装备 `17/17`、最终去重关键套件 `86/86`，全部通过。五份用户冻结数据的 SHA-256 与施工前完全一致。

## 1. 审计身份与保护边界

- 初始集成基线：`967d7981625c79fb7c5c4e67a583337f1a510a25`
- 统一单位接口基线：`159398c1`（`combat.unit.gu_gs_px.v1`）
- 审计日期：`2026-08-02`
- 审计原则：先证明当前活跃调用链和单位，再迁移；禁止用画面猜测代替函数证据。

施工前冻结哈希：

| 冻结对象 | SHA-256 |
|---|---|
| `assets/data/helmet_calibration_drafts/item_236.json` | `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` |
| `assets/data/helmet_calibration_drafts/item_240.json` | `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457` |
| `assets/data/runtime/monster_ground_alignment_manual_v1.json` | `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7` |
| `assets/data/runtime/monster_ground_contacts.json` | `AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597` |
| `assets/data/runtime/monster_ground_contact_calibrations.json` | `36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75` |

地图永久工作树存在 72 项用户 dirty/untracked 内容，装备与主树也存在用户人工内容。它们不是本次单位迁移的输入，禁止清理、回退、批量暂存或重建。

## 2. 来源优先级裁决

旧技能主合同 `assets/data/vanilla_176/skills_source_of_truth_v1.json` 的默认距离度量包含 `chebyshev_for_8_direction_grid_unless_skill_overrides`。用户随后明确批准 `COMBAT-UNIT-V1.0`，要求正式等长技能、锁定、移动、AI 和投射物统一为地面欧氏 GU。

该冲突不能通过静默修改旧技能主表解决。`159398c1` 已新增唯一主源 lane `combat_units`，只覆盖：

- 默认距离单位；
- 正式等长几何的度量；
- 移动、AI、投射物的运行时距离单位。

技能成员、数值、伤害公式、时序、素材与状态机仍由原 `skills` lane 管理。服务端其他战斗规则仍由 `server_rules` lane 管理。

## 3. 已确认正确、必须保留的基础

1. `MapCoordinateMapper` 与 `MapEditorCoordinate` 的主公式都是正确 `64×32` 投影。
2. 11 张正式 runtime 地图通过 `MapEditorRuntimeBridge` 委托 `MapEditorCoordinate`，主链投影正确。
3. `cell_center = tile + (0.5,0.5)` 是格顶点与格心的正式语义差，不是漂移；它在屏幕 S 方向产生 16 PX 的正确格心偏移。
4. 地图碰撞、遮挡、相机、精灵偏移和视觉锚点属于 PX 表现/物理接口，继续使用 PX。
5. 人物与怪物人工脚点是权威精灵脚点；战斗系统必须读取它们对应的 actor `global_position`，不得重算人工数据。
6. 怪物占地多边形、释放帧脚点重读、先几何后准确判定继续保留。
7. 地狱火源动画与播放时序、疾光电影已验收视觉宽度继续作为冻结 PX 表现。

## 4. 集成运行时确认的问题

### 4.1 锁定域使用旧 Chebyshev 方形

`scripts/game_root.gd`：

- `_attack_lock_tile_distance` 对取整 tile 使用 `max(abs(dx),abs(dy))`，10“格”实际是 Chebyshev 方形。
- `_spell_lock_tile_distance` 委托 `SpellTargetLockPolicy.chebyshev_distance`，12“格”同样是方形。
- `_attack_lock_candidates` 先按 Chebyshev GS 排序，再用地面坐标平方和、最后用屏幕 PX 距离打破平局，三个单位同时进入一个选择规则。
- `_spell_definition_allows_target` 仍读取 `maximum_range_tiles` 并按 Chebyshev 判定。

迁移目标：攻击锁定为半径 `10 GU` 的地面圆；法术锁定为半径 `12 GU` 的地面圆；排序只按 `distance_squared_gu` 和稳定实例 ID。

### 4.2 无 runtime 回退前后变换不互逆

`_canonical_world_to_fractional_tile` 使用正确 `/32,/16` 逆投影，但 `_canonical_fractional_tile_to_world` 与 `_canonical_tile_to_world` 使用错误 `*16,*8` 正投影，产生严格半比例。无 runtime 地图、兼容路径和部分验收/技能回退会发生 2 倍误差。

迁移目标：正反变换只委托统一 `GroundUnitSpace`/地图坐标接口，禁止第三套公式。

### 4.3 技能执行上下文混入 PX 搜索距离

`_canonical_target_context` 仍从旧 profile 读取无单位 `range/search_range`（例如 105、370），使用屏幕 `distance_to` 搜索附近单位，并用 `origin + normalized_screen_direction * pixels` 生成回退目标。投射物创建仍把相同旧 profile range 作为 PX travel range，同时又配置 `maximum_range_tiles`。

迁移目标：正式上下文只输出 `*_gu`；旧字段在版本化适配入口转换一次。目标选择、技能范围、投射物最大行程不得读取 PX。

### 4.4 战士候选排序与冲锋仍使用旧度量

- `_sort_melee_targets` 使用 `WarriorMeleeGeometry.chebyshev_distance`。
- 野蛮冲撞邻接、走廊和推动按未归一化八方向 tile step/整数步处理。
- 道士推离等旧路径直接把 `push_distance_tiles * 50 PX` 当位移。

迁移目标：候选按 GU 排序；冲锋/击退方向在地面空间归一化，距离以 GU 表达，再投影给现有碰撞求解器。

### 4.5 遗留范围函数仍接受无单位 PX

`_nearest_enemy`、`_damage_enemies`、`_world_circle_intersects_enemy_footprint`、旧 ground effect fallback 等函数使用 `global_position.distance_to`、屏幕圆和无单位 `radius/range`。必须逐调用点证明为活跃或死代码；活跃路径迁为 GU，确认无调用的路径才可删除。

## 5. 地图域确认的问题

### 5.1 正式语义半径被投影成屏幕圆

- 比奇安全区把 9 `radius_tiles` 硬乘 32，随后用屏幕欧氏圆判定；它不是 9 GU 地面圆。
- 怪物刷新 `radius_tiles=3` 在 `game_root` 中乘 20 PX，并用 `Vector2.from_angle` 生成屏幕圆；方向地面半径不同。
- 非比奇 runtime safe area 只转换中心，没有正式 `radius_gu/polygon_ground_gu`。

迁移目标：runtime v2 输出 `radius_gu` 与 `polygon_ground_gu`；旧 v1 字段只允许由内存适配器读取。显示形状可投影成 PX，判定必须在 GU 地面空间。

### 5.2 runtime 缺少单位合同版本

当前 runtime schema 不验证 GU/GS/PX 合同，`radius_tiles`、`return_unlock_distance_tiles` 等字段可在无单位解释的情况下进入运行时。

迁移目标：runtime 写入 `unit_contract_id=combat.unit.gu_gs_px.v1` 和 `projection_contract_id=world.ground_projection.iso_64x32.v1`。加载器内存适配 v1，不批量改写用户地图文件。

### 5.3 门点与寻路

门点解锁当前对 tile 坐标调用欧氏 `distance_to`，数学上已经等价 GU；只需把正式字段改为 `return_unlock_distance_gu`，兼容旧名。项目目前没有正式 AStar/Navigation 路径成本实现；未来轴邻居成本必须为 1 GU，对角为 √2 GU，并调用 `GroundUnitSpace.path_step_cost_gu`。

### 5.4 不应迁移的 PX

地图碰撞多边形、不可行走外裙、遮挡、相机、chunk 像素矩形、`offset_px/anchor_px`、旧环境图像采样都属于合法 PX。它们只需要更明确的字段名，不能按 GU 重算或改变像素结果。

## 6. 职业技能域

### 6.1 坐标与玩家移动

`CombatDirectionSpace` 的 `64×32` 线性变换正确，但 `CANONICAL_TILE_STEPS` 是 GS：坐标对角一步为 `√2 GU`。`projected_world_direction` 是归一化屏幕 PX 方向，只能用于视觉朝向，不能驱动玩法长度。

`player.gd` 当前把屏幕输入向量归一化后乘固定 PX/s，再交给 `move_and_slide`。相同屏幕速度在不同地面方向产生不同 GU/s，且碰撞后的实际位移没有反投影为 GU。

迁移目标：屏幕输入增量反投影为 GU、在地面空间归一化、以 `GU/s` 计算期望运动、投影到 PX 物理边界、最后把碰撞后的实际 PX 位移反投影回 GU。现有释放帧重新读取人物/目标脚点必须原样保留。

### 6.2 技能几何与投射物

`warrior_melee_geometry.gd` 虽声称使用逻辑 tile，实质是 GS/Chebyshev：

- 对角 facing step 未归一化；
- 普通/烈火/半月 sector 是 Chebyshev 方形裁剪；
- 刺杀 forward/side 未按 GU 归一，对角 `2.5` 实际达到 `3.536 GU`，宽度也随方向变化。

目标 footprint 由正式脚点投影到地面并做 SAT、边界相切算命中、几何先于准确、范围内多目标语义都是正确结构，必须保留。迁移后普通/烈火/半月为精确 `1.5 GU`，刺杀为 `2.5 GU × 1 GU` 地面条带。

`caster_spell_geometry.gd` 对地狱火/疾光使用 Chebyshev-normalized 轴：对角长度分别放大为 `7.071 / 11.314 GU`；旧 `0.5..N+0.5` 线段还把接触容错偷偷加到技能长度。迁移后 forward 必须 GU 归一，条带长度精确 `5 / 8 GU`，半宽 `0.5 GU`；接触容错由目标 footprint 承担，不延长端点。

投射物同时维护 `520 PX/s`、PX `remaining_range`、`24 PX` hit radius 与旧 `maximum/traveled_range_tiles`。每帧先走 PX，再以 Chebyshev 累积“格”，任一上限先到即销毁；固定 24 PX 起点偏移也不计入行程。结果是不同方向射程不同，且只检查终帧点碰撞，没有 sweep，低帧率可穿透。

迁移目标：`speed_gu_per_sec`、`max_travel_distance_gu`、GU 分段运动与 segment-vs-footprint 扫掠碰撞；枪口视觉偏移单列 `muzzle_offset_px`，不得增加玩法射程。

### 6.3 法师范围入口

爆裂火焰、冰咆哮会生成 3×3 `geometry_cells` 并用于视觉，但 `_apply_canonical_spell_damage` 没有把它们纳入正式几何入口，实际伤害退回 120 PX 屏幕圆。火墙逐 coverage cell + footprint SAT、地狱雷光 ring scanner 的结构正确。

迁移目标：所有声明离散 GS cell 几何的技能统一走 cells + footprint resolver；等长 GU 线和 GU 半径不得复用 GS cell 计数。geometry plan 必须声明自己的 domain。

### 6.4 锁定与释放

攻击锁当前先把脚点取整再做 10 Chebyshev，法术锁对 fractional tile 做 12 Chebyshev；候选排序混用 GS、GU 平方和与 PX 平方。迁移后两个锁定域继续独立，但都只使用最新脚点的地面欧氏距离：攻击 `10 GU`、法术 `12 GU`，排序只按 `distance_squared_gu + instance_id`。

`combat_release_geometry` 必须同时明确输出 `origin_ground_gu/direction_ground_gu` 和表现 `direction_screen_px`。释放帧重新读取人物与目标脚点的既有行为保持冻结。

## 7. 怪物域

### 7.1 数据入口与正式字段

`enemy.gd` 的 `move_speed`、`aggro_radius`、`attack_range`、`collision_radius`，以及怪物行为/Boss 数据中的 `moveSpeed/attackRange/aggroRadius/wakeRange/emergeRange/rangePixels/rangeTiles/radius/triggerRange` 都是旧无单位字段，实际混用 PX、PX/s 与 Chebyshev。

迁移目标：旧 profile 只由版本化 `monster.runtime.units.gu.v1` 适配器单向读取；正式运行时输出 `move_speed_gu_per_sec`、`attack_range_gu`、`aggro_radius_gu`、`combat_radius_gu` 等带单位字段。旧值不能直接改名当 GU。

当前 2:1 屏幕物理脚印必须像素零变化。若屏幕椭圆半径为 `(r_px, r_px/2)`，其正确逆投影是地面欧氏圆：

```text
combat_radius_gu = r_px / (32 × √2)
```

禁止把它错误地按 `r_px/32` 转换。

### 7.2 AI、移动和接敌

怪物钻地出现、休眠唤醒、隐身感知、追击、警戒、Boss 触发、返巢和接敌都使用屏幕 `offset.length()`；移动用屏幕 `offset.normalized() * move_speed`。接敌还串联屏幕接触阈值与 Chebyshev tile 距离，形成双门限。

迁移目标：所有玩法距离和方向进入 GU；`move_and_slide` 继续作为 PX 物理求解边界，移动前投影期望 GU 速度，移动后反投影实际位移。视觉 `facing` 与正式 `facing_ground` 分离，避免破坏八方向动画行。

### 7.3 延迟命中、Boss 与群体分离

- 延迟命中帧当前用屏幕 `hit_distance` 复核，必须改为最新脚点与 GU 占地判定。
- 固定范围怪物攻击、Boss 圆形攻击和 cone 都在屏幕空间；伤害几何必须迁为地面 GU，warning 只投影显示。
- 群体分离当前使用 96 PX hash、屏幕欧氏间距和 PX steering；必须迁为 ground-space hash 与 GU narrow phase。
- safe zone 当前也是屏幕 circle/polygon，需消费 maps/integration 的 ground-space 查询接口。

### 7.4 明确保留的怪物 PX

`monster_visual.gd` 的人工视觉 origin、foot/contact/ring、overhead、sprite anchor、影子与资源流送距离均是表现 PX；它们不得成为战斗脚点来源，也不得随 GU 迁移重建。

## 8. 分阶段验收门槛

每一阶段必须同时满足：

1. 专业工作树在指定接口基线 `159398c1` 上通过专项测试并提交。
2. 集成分支一次只合并一个专业提交，合并后复跑该域测试。
3. 32 方向 GU 长度、端点和时间一致。
4. 地图投影、碰撞和人工脚点像素/数据不变。
5. 运行时正式字段带单位后缀；旧字段只存在于有版本号的适配器。
6. 冻结哈希逐项复核一致。
7. 最终静态审计中，正式战斗路径不存在 Chebyshev 等长距离和 PX 玩法距离判定。
