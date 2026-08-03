# COMBAT-UNIT-V1.0 最终战斗几何审计

## 结论

全项目正式玩法坐标已统一为 `combat.unit.gu_gs_px.v1`：

- `GU` 负责连续地面欧氏距离、方向、速度和占地。
- `GS` 只负责离散网格拓扑与明确的相邻步数。
- `PX` 只负责屏幕投影、物理呈现、精灵、特效和 UI。

正式运行时代码已删除无单位的兼容别名；旧数据字段只允许在带版本号的单向适配入口读取，并在进入运行时前转换为带单位后缀的字段。

## 已迁移系统

| 系统 | 正式合同 |
|---|---|
| 64×32 正反投影 | `GroundUnitSpace` 的 GU↔PX 可逆转换 |
| 玩家移动 | 地面方向归一化、`move_speed_gu_per_sec`，PX 仅作为物理求解边界 |
| 怪物移动与 AI | GU 警戒、追击、接敌、返巢、群体分离与攻击几何 |
| 玩家/怪物占地 | `combat_radius_gu`；屏幕物理半径为显式 `*_px` |
| 攻击/法术锁定 | 半径 `10 GU` / `12 GU` 的地面欧氏圆 |
| 普通/烈火/半月/刺杀 | `1.5 / 1.5 / 1.5 / 2.5 GU`；怪物占地相交后再做准确判定 |
| 地狱火/疾光电影 | `5×1 GU` / `8×1 GU` 连续条带，伤害与视觉共用地面端点 |
| 投射物 | `speed_gu_per_sec`、`max_travel_distance_gu` 与逐帧线段扫掠 |
| 地图运行时 | 同时输出 `*_ground_gu` 与 `*_screen_position_px`，不再输出模糊 `position` |
| 地图安全区与刷新 | 地面 GU 圆/多边形；包含单位占地半径 |
| UI 技能详情 | 只读 `maximum_range_gu`，显示精确 GU 数值 |

## 明确保留的表现层

以下内容继续使用 PX，且不参与玩法距离判定：精灵锚点、人物和怪物人工视觉脚点、头顶 UI、阴影、光圈绘制、地图遮挡与相机、技能原始像素、地狱火已验收动画、疾光电影已验收帧宽。

## 冻结数据证明

施工前后 SHA-256 完全一致：

| 文件 | SHA-256 |
|---|---|
| `assets/data/helmet_calibration_drafts/item_236.json` | `21B622C0461A81D3C98122864DABB84F14A9C10A9CA4AF7225E1EA8CFECE4BEC` |
| `assets/data/helmet_calibration_drafts/item_240.json` | `81BBFE246C76D734434529BBFDA674264E4980CCFC5ECE05EA24065BF462A457` |
| `assets/data/runtime/monster_ground_alignment_manual_v1.json` | `DD8BB683A59F280B3F0FAF5E399ABDF69634C0EB9CC469659414A6FEA6C501A7` |
| `assets/data/runtime/monster_ground_contacts.json` | `AC70A9D821F64D0EB1D8388415D0F469E97F7F417F616B127448C40A438CA597` |
| `assets/data/runtime/monster_ground_contact_calibrations.json` | `36955BAB6FF77AAEE6B32656EEC933410C9D09FB81F227304F21AADEC3D3DC75` |

## 自动验收

- 正式运行时静态单位审计：`1/1 PASS`
- 职业技能 GU 专项：`16/16 PASS`
- UI/GU 接口专项：`5/5 PASS`
- 战士/法师/锁定/投射物集成套件：`25/25 PASS`
- 地图与比奇套件：`32/32 PASS`
- 怪物与 AI 套件：`18/18 PASS`
- 装备、存档与 Android 布局套件：`17/17 PASS`
- 最终去重关键套件：`86/86 PASS`

全部 Godot 自动化均通过 `tools/run_godot_tests.ps1` 在项目内隔离日志和用户数据目录运行。

## 释放投影统一补充审计（2026-08-03）

- 正式职业技能关系矩阵合同：`skills.spatial_projection.relationship_matrix.v1`，33 个技能一一对应且无遗漏、无重复。
- 正式空间执行门禁：`caster_skill_execution.spatial_snapshot_gate.v1`。需要空间投影的技能若缺少同一技能、同一释放 ID 的只读快照，生产路径不得继续结算。
- 精确地面技能保存完整格区并集，不以包围盒或外接圆代替；单体技能保存目标实例与释放帧战斗脚印；持续/附着视觉只读取脚点锚点，不制造虚假伤害区。
- 投射物使用两层合同：释放帧完整飞行走廊母快照用于锁定固定路径，每物理帧实际扫掠子快照用于碰撞和伤害；三种正式投射物均通过相同回归。
- 怪物、Boss、骷髅与神兽攻击使用各自释放者脚点创建快照，不复用玩家脚点；延迟伤害与预警共享同一冻结快照。
- 本轮回归：职业技能 `27/27`、怪物 `18/18`、Warrior `25/25`、最终关键套件 `87/87`。

## 已知非本次回归

额外旧场景 `gothic_bich_camp_test` 的 GU 安全区断言已经通过，随后失败于既存的“仓库管理员”NPC 缺失。该断言不属于单位系统，也不在标准比奇 32 项或最终关键 86 项套件中；本次未越权修改地图内容。

## Android 交付

- 固定构建提交：`665c21beb894297617fdac6bccc342b4c052c4b1`
- APK：`outputs/hardcore/HardCore-v63-combat-unit-gu-debug.apk`
- 版本：`63 / 1.18.0-combat-unit-gu`
- 大小：`244,485,554` 字节
- SHA-256：`C380B2F050E8053D282B9740162A8D8C39D6A1CB4341DF6AB0ECCEA24ABC7F63`
- 验证：HardCore / arm64-v8a / minSdk 24 / targetSdk 36 / 横屏 / 可调整窗口 / APK v2、v3 签名 / 运行时资源探针全部通过。
