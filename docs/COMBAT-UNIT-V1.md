# COMBAT-UNIT-V1.0：全项目统一单位合同

## 1. 合同身份

- 稳定合同 ID：`combat.unit.gu_gs_px.v1`
- 地面投影：固定 `64×32` 等距投影，半格基向量为 `32×16 PX`
- 权威来源：用户在 2026-08-02 明确批准的 `COMBAT-UNIT-V1.0`
- 射程修订：2026-09-06 用户明确调整全职业普通攻击、烈火、半月与刺杀；仅修改下列射程，不改变单位、投影及冻结美术。
- 适用范围：玩家、怪物、技能、投射物、移动、AI、锁定、冲锋、击退、寻路距离与运行时调试几何

本合同只统一单位、距离度量和坐标转换。它不得重建或修改用户人工脚点、怪物校准、装备校准、技能原始像素、已验收的地狱火动画或疾光电影视觉宽度。

## 2. 正式单位

### GU：Ground Unit

`GU` 是连续地面空间中的欧氏长度单位。地面坐标从 `(x,y)` 移动到 `(x+1,y)` 或 `(x,y+1)` 的长度均为 `1 GU`。

以下系统必须使用 GU：攻击距离、法术距离、技能长度与宽度、爆炸半径、单位占地半径、玩家与怪物速度、投射物速度和最大飞行距离、冲锋、击退、锁定、AI 警戒、追击和攻击距离。

正式字段必须使用单位后缀，例如：`range_gu`、`cast_range_gu`、`effect_length_gu`、`radius_gu`、`half_width_gu`、`combat_radius_gu`、`move_speed_gu_per_sec`、`projectile_speed_gu_per_sec`、`max_travel_distance_gu`。

### GS：Grid Step

`GS` 只表示离散地图相邻节点步数，不表示实际地面长度。在八邻接网格中，位移 `(1,0)` 是 `1 GS / 1 GU`，位移 `(1,1)` 是 `1 GS / √2 GU`。

GS 仅用于寻路节点数、离散格触发器、地图拓扑和明确要求经典相邻步数的特殊机制。正式字段使用 `grid_steps`、`path_step_count` 或 `maximum_grid_steps`。

### PX：Screen Pixel

`PX` 只用于屏幕位置、精灵偏移、动画挂点、视觉高度、特效尺寸和 UI。PX 不得参与攻击、法术、锁定、移动、投射物、AI、碰撞射程等玩法距离判定。

正式字段使用 `screen_position_px`、`visual_offset_px`、`visual_height_px` 或 `sprite_anchor_px`。

## 3. 唯一距离和方向规则

地面距离统一为：

```gdscript
var delta_ground_gu := target_ground_gu - source_ground_gu
var distance_squared_gu := delta_ground_gu.length_squared()
var in_range := distance_squared_gu <= range_gu * range_gu
```

所有方向必须先在地面空间归一化：

```gdscript
var direction_ground := delta_ground_gu.normalized()
var endpoint_ground_gu := source_ground_gu + direction_ground * effect_length_gu
```

正式等长技能、锁定和移动禁止使用 Chebyshev 距离。屏幕像素只能由正式 GU 几何投影得到。

## 4. 64×32 投影

地面增量到屏幕增量：

```text
screen_x_px = (ground_x_gu - ground_y_gu) × 32
screen_y_px = (ground_x_gu + ground_y_gu) × 16
```

屏幕增量到地面增量：

```text
horizontal = screen_x_px / 32
vertical   = screen_y_px / 16
ground_x_gu = (horizontal + vertical) / 2
ground_y_gu = (vertical - horizontal) / 2
```

屏幕正东的 `8 GU` 对应地面方向 `(1/√2,-1/√2)`，屏幕长度约 `362.04 PX`。旧规则 `(8,-8)` 是 `8 GS / 8√2 GU`，屏幕长度为 `512 PX`，不得再称为 `8 GU`。

## 5. 移动与碰撞

玩家、怪物、冲锋和投射物先在地面空间计算期望位移：

```gdscript
desired_ground_delta_gu = direction_ground.normalized() * speed_gu_per_sec * delta
```

将期望地面位移投影到屏幕空间后交给现有物理碰撞求解器。碰撞完成后，必须把实际屏幕位移反投影为实际 GU 位移；不得用被阻挡前的期望 GU 位移覆盖实际结果。

## 6. 正式技能基线

| 系统 | 正式距离 |
|---|---:|
| 普通攻击（全部职业） | `2.0 GU` |
| 烈火剑法（禁止无有效目标起手） | `2.0 GU` |
| 半月弯刀（120 度扇形） | `2.0 GU` |
| 刺杀剑术（末端 1.5 GU 忽略防御） | `3.0 GU` |
| 地狱火 | `5.0 GU` |
| 疾光电影 | `8.0 GU` |
| 攻击锁定 | `10.0 GU` |
| 法术锁定 | `12.0 GU` |

技能视觉尺寸仍属于 PX 表现层；伤害几何、锁定和调试范围必须来自 GU。疾光电影已验收的视觉宽度与地狱火原始动画保持冻结，只有其摆放路径和伤害几何迁移到 GU。

## 7. 寻路

八方向寻路中，地面坐标轴相邻节点成本为 `1 GU`，坐标对角相邻节点成本为 `√2 GU`。可以额外记录 GS 数量，但正式路程、移动时间和 AI 距离必须由 GU 决定。

## 8. 兼容与迁移

- 旧字段只允许在版本化适配层读取，进入正式运行时后必须立即转换为带单位后缀的字段。
- 旧 `*_tiles` 字段必须按其历史语义明确标记为 GU、GS 或旧 Chebyshev 距离；禁止只改字段名而不转换数值或几何。
- 旧存档的世界 PX 坐标必须由版本化迁移器保留或转换，禁止静默把 PX 数值解释为 GU。
- 未带单位的 `range`、`distance`、`speed`、`width`、`radius` 不得作为新的正式运行时字段。

## 9. 施工顺序

1. 完成全项目单位审计。
2. 修正不对称坐标转换回退路径。
3. 建立统一 GU 坐标和距离服务。
4. 迁移玩家与怪物移动。
5. 迁移攻击和法术锁定。
6. 迁移战士攻击几何。
7. 迁移地狱火和疾光电影。
8. 迁移投射物速度与扫掠碰撞。
9. 迁移怪物攻击、追击与 AI 距离。
10. 删除已证明无调用的旧距离实现。

## 10. 冻结边界

必须原样保留：

- 最新人工人物与怪物脚点；
- 怪物占地形状；
- 释放帧脚点重读；
- 动画与伤害几何分离；
- 先几何、后准确/敏捷判定；
- 正确的 `64×32` 主投影；
- 已验收的地狱火原始动画；
- 已验收的疾光电影固定视觉宽度；
- 装备、头盔和纸娃娃人工校准数据。

## 11. 最终验收

- 32 个采样方向移动相同时间后，地面 GU 距离相同。
- 所有方向普通攻击、刺杀、地狱火、疾光电影分别为 `2 / 3 / 5 / 8 GU`。
- 法术锁定是半径 `12 GU` 的地面圆，攻击锁定是半径 `10 GU` 的地面圆。
- 投射物使用 `GU/s`，并对一帧内的完整扫掠线段执行碰撞。
- AI 距离、追击和攻击距离使用 GU。
- 正式战斗代码不存在 PX 距离判定。
- 正式等长技能不存在 Chebyshev 距离。
- 冻结数据施工前后 SHA-256 完全一致。
