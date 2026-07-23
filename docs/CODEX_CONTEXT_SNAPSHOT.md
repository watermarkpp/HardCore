# Codex 精简上下文快照

更新时间：2026-07-23（Asia/Shanghai）

用途：给主任务和专业工作树提供快速、可核实的启动索引，减少重复扫描和重复测试。
准确性规则：本文件不是代码或 Git 状态的替代品；只核实本次任务实际触及的分支、文件、接口和专项测试。

## 30 秒启动顺序

1. 完整读取根目录 `AGENTS.md`。
2. 运行 `git branch --show-current` 和 `git status --short`。
3. 阅读本快照对应专业段落，只打开“最小必读”中与当前问题有关的文件。
4. 专业修改在永久工作树完成；集成主树只调度、审查、逐项合并和验收。
5. 不因本快照而跳过当前证据核实；也不在未触及领域重复全量扫描或旧测试。

## 当前集成基线

- 主目录：`C:\Users\Administrator\Documents\HardCore`
- 分支/HEAD：`codex/integration` @ `e0165bef78054b5f5b2b465382798510fafdb89d`
- tracked 状态：clean。
- 未跟踪状态：67 个 Godot 生成的 `*.gd.uid`；没有用户授权时不得删除。
- 当前无待合并专业提交。
- 下一项外部验收：用户将手动安装并测试最终 APK；在收到实机结果前不推断通过或失败。

## 最终 APK

- 文件：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-debug.apk`
- 构建时间：`2026-07-22 23:59:06`
- 大小：`1,619,606,733` 字节
- SHA-256：`caaf580f1aa872f15886a3aa7a359c98a1a803ad59ef47cb98dc60f56300c912`
- 此最终包尚未覆盖安装到手机；手机最后安装的是上一包，不能用手机当前画面判断本包结果。

## 最近已集成结果

| 集成提交 | 领域 | 结果 |
|---|---|---|
| `e0165bef` | UI | 血球/蓝球恢复到框体孔径；2664×1200 安全区布局 |
| `4957b340` | maps | 房屋/树木遮挡阈值修正；角色脚点可达可见地图边缘 |
| `4ffe67eb` | monsters | 最终复合头顶层固定为身体→血条→名字 |
| `72ad3e46` | maps | 编辑器画面几何统一应用到运行时实例 |
| `ce42d172` | UI | 拾取提示按安全视口居中 |
| `a56e65e1` | UI | 技能配置弹窗背景约束到弹窗范围 |
| `48fea9bc` | skills | 烈火冷却归零立即恢复 ready |
| `f82717f6` | integration | 快捷技能配置接线与烈火自动开关运行时 |
| `8860c012` | rules | 除删除现有文件/数据外直接执行，不再询问 |

当前关键契约：

- maps：`map_editor_runtime_collision_geometry_v2`、`published_blocked_cells_after_erasure_v1`、`map_editor_runtime_visual_geometry_v3`、`map_visible_edge_actor_clearance_v1`、`map_actor_occlusion_sort_v4`。
- monsters：`monster.overhead_anchor.v3`、`monster.overhead_layout.v3`。
- UI：`ui.hud.resource_orb.hole_fill.v1`、`skill_button_assignment_contract_v2`。

## 已通过的必要验收

- 总回归：`SMOKE_TEST_PASS`。
- maps：比奇真实源 E2E（180 个阻挡格）；11 张地图真实 `CharacterBody2D` 脚点可达可见边缘且外环阻挡。
- monsters：真实名字/血条节点覆盖 4 类怪物、8 方向、idle/walk/attack/hit/death 全帧和 Camera2D 缩放；214 种怪物加载通过。
- UI：2664×1200 HUD 血蓝球尺寸/对称/安全区通过；技能配置与拾取提示专项通过。
- skills：快捷槽 v2 换槽、烈火自动开关和战士技能状态机通过。

只在相关代码再次变化时重跑对应专项；跨域接线或发布前再跑一次 smoke。

## 永久工作树状态

| 工作树 | 分支/HEAD | dirty | 集成状态 |
|---|---|---:|---|
| `HardCore-worktrees/maps` | `codex/maps` @ `30cef051` | 31 tracked + 41 untracked | 已等价集成为 `4957b340` |
| `HardCore-worktrees/monsters` | `codex/monsters` @ `e8d0739f` | clean | 已等价集成为 `4ffe67eb` |
| `HardCore-worktrees/ui-art` | `codex/ui-art` @ `40f9312e` | clean | 已等价集成为 `e0165bef` |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` @ `362ec7ca` | clean | 最近交付已集成 |
| `HardCore-worktrees/equipment` | `codex/equipment` @ `6a28f394` | clean | 已等价集成为 `846e602f`；不要重复合并 ahead 提交 |

### maps 保护红线

maps 的 72 项 dirty 全部视为用户进行中的地图编辑器内容，禁止清理、还原、覆盖或批量暂存。重点包括 `project.godot`、`map_asset_overrides.json`、地图 editor JSON/备份、ground chunks/manifests/state/preview、新地图工作区和 UID。开始新 maps 任务时只暂存本次明确修改的文件。

## 各领域最小必读

- maps：`AGENTS.md`；`scripts/map_editor/map_editor_runtime_collision_geometry_service.gd`；`scripts/map_editor/map_editor_runtime_visual_geometry_service.gd`；`scripts/world_background.gd`；对应地图 E2E 测试。
- monsters：`AGENTS.md`；`scripts/enemy.gd`；`scripts/monster_overhead.gd`；`scripts/monster_visual.gd`；`tests/monster_health_bar_anchor_test.gd`。
- UI：`AGENTS.md`；`scripts/gothic_ui_theme.gd`；目标面板或 `scripts/hud.gd`；对应 UI 专项测试。
- skills：`AGENTS.md`；`scripts/player.gd`；`scripts/profession_rules.gd`；`scripts/skill_loadout_rules.gd`；对应状态机测试。
- equipment：`AGENTS.md`；`scripts/equipment_rules.gd`；`assets/data/equipment_actor_sort_contract.json`；对应排序契约测试。

## 下次实机验收清单

1. 比奇房屋/树木可见底座与角色碰撞、前后遮挡是否一致。
2. 地图可见外沿：脚点可达地面边缘，角色与怪物不能进入黑区。
3. 怪物名字固定在血条上方，任何方向/动作/帧不偏移、不重合。
4. 血球/蓝球恢复孔径尺寸且左右对称。
5. 拾取提示居中；技能配置弹窗背景不越界；快捷技能可置换；烈火自动开关正常。

用户实测结果优先级高于内部测试；若实机失败，先保存截图和 APK 哈希，再按所属专业工作树返修。
