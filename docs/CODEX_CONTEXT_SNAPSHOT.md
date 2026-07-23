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
- 分支/运行时代码基线：`codex/integration` @ `23e14745f8f0971e57c323b74653e90e2903dbec`（其后的快照提交只改本文档）。
- tracked 状态：clean。
- 未跟踪状态：77 个 Godot 生成的 `*.gd.uid`；没有用户授权时不得删除。
- 当前无待合并专业提交。
- 用户已确认此前截图来自当时最新 APK；不要再次怀疑或重复核验安装版本。用户已实机确认碰撞、装饰物遮挡、地图错位和视角全部解决，四项正式冻结；除非出现新的明确证据，后续任务不得顺带调整。
- 当前进行中：修正怪物脚下光圈的真实脚底锚点；生成战士/法师/道士 × 沃玛/祖玛/赤月的 9 个独立满技能测试人物存档。

## 最终 APK

- 文件：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-debug.apk`
- 构建时间：`2026-07-23 11:45:25`
- 大小：`1,619,623,450` 字节
- SHA-256：`7dee0f52605bb3601927d4515f4d07f70fe88abe98989326df97eb1267ed745a`
- 本包新增逐 `monster_id` 身体顶点锚定，以及人物优先柔性镜头、边缘动态缩放和不可行走渐暗裙边；尚待用户覆盖安装后实机验收。

## 最近已集成结果

| 集成提交 | 领域 | 结果 |
|---|---|---|
| `23e14745` | integration | 接入人物中心 ±14% 柔性镜头与帧率无关的 1.06–1.16 动态缩放 |
| `8f522258` | monsters | 214 个怪物逐 ID 使用八方向 idle 真实身体顶点固定头顶锚点 |
| `f7165027` | maps/docs | 明确人物位于屏幕坐标 36%–64% 的中央带 |
| `aa75736a` | maps | 柔性边缘相机 v2 与不可行走渐暗地图外裙边 |
| `956393cf` | integration | Camera2D 以视口侵蚀后的地图菱形约束中心，避免暴露地图外区域 |
| `c4af44a1` | monsters | 怪物物理脚底改为 2:1 等距椭圆，战斗/AI 标量半径不变 |
| `1b7e53da` | skills/player | 玩家物理脚底改为 18×9 等距椭圆 |
| `46cfcd27` | maps | 统一真实地图边界、遮挡深度 v5 与菱形相机约束服务 |
| `1a67e76f` | integration | 新增共享等距脚底契约 `world.actor_footprint.iso_ellipse.v1` |
| `4e022999` | monsters | 冷启动异步贴图激活后重新计算固定头顶层 |
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

- integration：`world.actor_footprint.iso_ellipse.v1`。
- maps：`map_editor_runtime_collision_geometry_v2`、`published_blocked_cells_after_erasure_v1`、`map_editor_runtime_visual_geometry_v5`、`map_actor_occlusion_sort_v5`、`map_diamond_camera_center_constraint_v2`、`player_priority_soft_edge_v1`、`map_runtime_nonwalkable_edge_skirt_v1`。
- monsters：`monster.overhead_anchor.v4`、`monster.overhead_layout.v3`；214 个 `monster_id` 各自使用稳定身体顶点，贴图异步激活后必须刷新。
- UI：`ui.hud.resource_orb.hole_fill.v1`、`skill_button_assignment_contract_v2`。

## 已通过的必要验收

- 总回归：`SMOKE_TEST_PASS`。
- integration：共享 36×18 等距脚底契约通过；运行时 Camera2D 菱形视口约束通过。
- camera：2664×1200 下人物屏幕偏移≤全尺寸 14%，动态缩放为 1.06–1.16；80×80 与 38×38 地图外露均由 1536px 不可行走裙边覆盖。
- monsters：逐 ID 锚点数据生成检查、214 怪物数据契约、全动作/方向/帧稳定和小/中/大/Boss 冷启动通过。
- physics：玩家 18×9、普通怪物 16×8、Boss 28×14 的真实物理与软件探针通过；战斗/AI 半径未改。
- occlusion：11 张已发布地图、52 个交叉、4 类装饰物和 3 个比奇回归点通过；碰撞区、脚底深度点、装饰物遮挡基线已分离。
- maps：比奇真实源 E2E（180 个阻挡格）；11 张地图真实 `CharacterBody2D` 脚点可达可见边缘且外环阻挡。
- monsters：真实名字/血条节点覆盖 4 类怪物、8 方向、idle/walk/attack/hit/death 全帧和 Camera2D 缩放；214 种怪物加载通过。
- UI：2664×1200 HUD 血蓝球尺寸/对称/安全区通过；技能配置与拾取提示专项通过。
- skills：快捷槽 v2 换槽、烈火自动开关和战士技能状态机通过。

只在相关代码再次变化时重跑对应专项；跨域接线或发布前再跑一次 smoke。

## 永久工作树状态

| 工作树 | 分支/HEAD | dirty | 集成状态 |
|---|---|---:|---|
| `HardCore-worktrees/maps` | `codex/maps` @ `599717ce` | 31 tracked + 41 untracked | 已集成为 `aa75736a`、`f7165027` |
| `HardCore-worktrees/monsters` | `codex/monsters` @ `da00ca86` | clean | 已集成为 `8f522258` |
| `HardCore-worktrees/ui-art` | `codex/ui-art` @ `40f9312e` | clean | 已等价集成为 `e0165bef` |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` @ `075958e5` | clean | 已集成为 `1b7e53da` |
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

1. 已冻结：碰撞、装饰物遮挡、地图错位和视角均由用户实机确认通过。
2. 待验收：怪物脚下光圈必须与最终贴图真实脚底重合，不因体型、方向、动作或冷启动漂移。
3. 待验收：角色选择页出现 9 个独立测试人物；三职业各有沃玛、祖玛、赤月三档完整装备，并学习本职业全部技能。
4. 怪物名字固定在血条上方；各体型血条位于各自真实身体顶点上方约 8px，不再统一过高或随动作抖动。
5. 血球/蓝球恢复孔径尺寸且左右对称。
6. 拾取提示居中；技能配置弹窗背景不越界；快捷技能可置换；烈火自动开关正常。

用户实测结果优先级高于内部测试；若实机失败，先保存截图和 APK 哈希，再按所属专业工作树返修。
