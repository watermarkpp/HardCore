# PARALYSIS_PRESENTATION_TRACE — 玩家麻痹状态运行时表现追踪

- BASE SHA: `4a91db49c7ae1738e75fbc114356da4423281cee`（origin/codex/integration）
- 追踪方式：按运行时生产路径逐跳追踪（状态源 → 状态入口 → 表现绘制/UI 条目 → 状态退出），不按文件名猜测。
- 结论：本文件记录"当前运行时真实使用的表现"，是中毒状态标志复用该 presentation lane 的依据。

## 1. 状态源（state source）

| 状态 | 文件 | 位置 | 说明 |
|---|---|---|---|
| 玩家麻痹（控制） | `scripts/player.gd` | L101 `var control_time := 0.0` | 玩家被怪物麻痹（楔蛾/月魔蜘蛛等）或特殊效果控制时的唯一状态计时 |
| 玩家中毒（legacy） | `scripts/player.gd` | L102 `var poison_time := 0.0` | 技能/物品造成的持续毒伤计时 |
| 玩家中毒（monster source） | `scripts/player.gd` | L103 `_monster_source_poison`（`scripts/monster_source_poison_state.gd`） | 怪物来源毒的独立时钟 |

## 2. 状态入口（state entry）

| 入口 | 文件 | 函数 | 行为 |
|---|---|---|---|
| 麻痹 | `scripts/player.gd` | `apply_control(seconds)` L1490-1492 | `control_time = maxf(control_time, seconds)` + `queue_redraw()` |
| 怪物麻痹玩家 | `scripts/game_root.gd` | L9920 `target.apply_control(...)`（怪物特殊技能 delivery）；L11567-11568 玩家麻痹戒指 `enemy.apply_control(5.0)`（作用于怪物） | 玩家侧入口即 `apply_control` |
| 中毒（legacy） | `scripts/player.gd` | `apply_poison(tick_damage, seconds)` L1495-1498 | 只改 gameplay 数值 + `queue_redraw()` |
| 中毒（monster source） | `scripts/player.gd` | `apply_monster_poison(...)` L1501-1507 | `_monster_source_poison.apply(...)` + `queue_redraw()` |

## 3. 状态退出（expiry）

| 状态 | 文件 | 位置 | 条件 |
|---|---|---|---|
| 麻痹 | `scripts/player.gd` | `_physics_process` L244 | `control_time = maxf(0.0, control_time - delta)`，归零即失效 |
| 中毒（legacy） | `scripts/player.gd` | `_physics_process` L246-252 | 战斗切换期间暂停；否则逐帧递减并按秒结算毒伤 |
| 中毒（monster source） | `scripts/player.gd` | `_update_monster_source_poison(delta)` L1510-1526 | 战斗切换暂停；死亡时 `clear()`；`advance(delta)` 归零即失效 |

## 4. 麻痹的实际运行时表现（runtime proof）

### 4.1 唯一存在的麻痹视觉：`player.gd _draw()` 蓝色控制环

- file: `scripts/player.gd`
- function: `PlayerCharacter._draw()`
- node: `PlayerCharacter`（Node2D 自绘，CanvasItem layer）
- state source: `control_time > 0.0`
- active condition: `apply_control()` 设置 `control_time > 0`
- expiry condition: `_physics_process` 将 `control_time` 递减至 0
- layout: `draw_circle(Vector2(0, -4), 37.0, Color(0.42, 0.62, 1.0, 0.75), false, 4.0)`（L1549-1550，人物脚下半径 37px 环，线宽 4）
- texture/source: 无贴图，纯 `_draw()` 矢量绘制
- runtime proof: 全仓 `0.42, 0.62` 颜色仅此一处；`grep control_time` 证明玩家控制状态只被 `_draw()` 消费；`tests/monster_paralysis_attack_test.gd`、`tests/stone_tomb_test.gd` 证明 `control_time` 是运行时麻痹判定状态。

### 4.2 运行时验证过的"不存在项"

- `scripts/player_health_bar.gd`：`_draw()` 仅绘制 `Lv%d` 等级文字与生命条（L91-100），**没有任何状态标志**。
- `scripts/hud.gd update_status_buffs()`（L2208-2241，HUD 底部状态图标条，含倒计时）：当前条目仅由 `game_root.gd _status_buff_entries()`（L10200-10219）提供：`ac`/`mac`/`shield(魔法盾)`/`stealth(隐身术)`/`heal(治愈术)`/`item:*`，**不含麻痹（control）条目**。
- 结论：用户描述的"麻痹血条下标志"在本 BASE 的玩家路径上不存在独立节点；玩家麻痹的实际运行时表现是 4.1 的蓝色控制环。该表现属于麻痹既有正确表现，本轮不修改、不删除。

## 5. 仓库内已存在的"血条下状态标志"表现 lane（复用目标）

| lane | 文件 | 证据 | 说明 |
|---|---|---|---|
| 怪物状态点行（`overhead_green_red_dot_row`） | `scripts/enemy.gd` | L111 `POISON_INDICATOR_STYLE := "overhead_green_red_dot_row"`；L6967-6983 绿毒/红毒点绘制于 `poison_indicator_anchor_y()` = 生命条下（L7130-7131）；`tests/monster_source_status_test.gd` 等覆盖 | 怪物中毒表现为生命条下的紧凑状态点，不画地面环 |
| 玩家 HUD 状态图标条（含倒计时） | `scripts/hud.gd` + `scripts/game_root.gd` | `update_status_buffs()` L2208-2241：`_status_buff_icons` 按条目动态创建图标（`_build_taoist_defence_buff_icon`，尺寸 `TAOIST_BUFF_ICON_SIZE = 26x26`），`seconds` Label 显示 `ceili(remaining)` 倒计时，条目消失即 `hide()`；纹理路径 `entry.skill → HUDSkillIconCatalogScript.SKILL_TEXTURES`（含 `施毒术 → taoist_poison.png`，`scripts/hud_skill_icon_catalog.gd` L27） | 玩家状态标志的现有 presentation lane：图标+秒数、按开始时间排序排列、随状态自动出现/消失 |

## 6. 中毒标志的落点裁决（本轮施工依据）

1. 删除 `scripts/player.gd _draw()` 中 `poison_time > 0.0 or _monster_source_poison.remaining_seconds > 0.0` 的绿色地面圆环（L1551-1552）——只删视觉，不动任何 gameplay。
2. 中毒加入 §5 的玩家 HUD 状态图标条 lane（与魔法盾/隐身术/治愈术同一套图标、尺寸、排列、倒计时、生命周期规则），条目 `id="poison"`、`skill="施毒术"`（复用现有 `taoist_poison.png` 图标，不新增素材）、`remaining = maxf(poison_time, _monster_source_poison.remaining_seconds)`；死亡/两种毒同时结束时条目立即消失。
3. 麻痹（蓝色控制环）与其 gameplay 一字不动；HUD 状态条不新增麻痹条目（保持既有行为）。
4. 中毒图标带秒数倒计时，与该 lane 既有图标（魔法盾/隐身术/治愈术）一致——lane 的既有规则就是带秒数，因此中毒同样带秒数（遵守"完全参照现有方案"）。
