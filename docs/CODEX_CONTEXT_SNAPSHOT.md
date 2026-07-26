# Codex 精简上下文快照

更新时间：2026-07-26 10:17（Asia/Shanghai）

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
- 分支/运行时代码基线：`codex/integration` @ `345d073`（其后的快照提交只改本文档）。
- tracked 状态：clean。
- 未跟踪状态：既有审计/报告输出与 Godot 生成的 `*.gd.uid` 继续保护，不得顺带清理或提交。
- 当前无待合并专业提交。
- 来源优先级总表为 `assets/data/source_priority_policy.json`；每个 lane 必须先查 `primary`，只有精确目标确实 `missing` 才允许逐级 fallback。主源不可用、不兼容或效果不符合预期时必须修复解析/映射，禁止换用低级来源。
- 完整资料扫描记录位于 `outputs/resource_catalog/complete_local_mir_sources/catalog.sqlite`（SHA-256 `3a133f39e9a0bf0b065b29778ff4f40d33aaa009ba1bed0a3213ae3a33233c79`）与 `manifest.json`：58 个 distribution、38,887 文件、14,595,954,010 字节、0 未哈希、SQLite integrity `ok`。
- 越级使用审计见 `docs/audit/SOURCE_PRECEDENCE_VIOLATION_AUDIT_2026-07-24.md`。未合并装备提交 `7c37b771` 因跳过主库采用未配置 mylgd 数据已拒绝；不得 cherry-pick。
- primary-only 武器返修已集成为 `2b0da07e`：37 件中 35 件可见、隐藏 0、命运之刃/落魄神兵未解析；木剑、乌木剑、罗刹、噬魂法杖、屠龙均有世界外观，低级库采用数为 0。
- 用户已逐项确认武器与男性衣服外观；冻结提交 `c7489047` 将 37 件武器更新为 36 可见、0 隐藏、仅落魄神兵 1 件视觉未解析，并固定命运之刃、屠龙、炼狱等用户确认映射。
- 装备属性不再走 Crystal `server_data`：`2a61617` 新增独立 `equipment_attributes` lane，唯一主源为 `assets/data/equipment_attribute_master.json`（`equipment.attribute.master.v1` / `project.hardcore.equipment_attribute_master.v1`）。该表覆盖 37 武器与 12 男衣；Crystal 仍是其他服务端数据范围的主源，禁止反向覆盖装备属性。
- 上述装备属性合同已由用户审核工作簿正式升级为 `equipment.attribute.master.v2` / `project.hardcore.equipment_attribute_master.v2`：共 163 条唯一装备，其中 114 条头盔、项链、手镯、戒指审核覆盖；证据 SHA-256 为 `CEEB2E68D07E2FFA112C46A954D04AAB68A95A576634199E05AB98FF23ABF83D`。`magicEvasionPercent` 与 `magicEvasionPoints` 分离，准确、敏捷和攻击速度档位均进入正式字段。
- `combat.resolution.openmir2.v1` 已接入运行时：物理命中统一为 `Random(敏捷) < 准确`；玩家基础 AntiMagic 为 1 点且只由 `PlayerState` 注入，怪物/通用空目标默认 0；直接法术固定按 AntiMagic → 随机 MAC → 最终扣血结算；攻击速度按 `max(0, 900 - tier × 60)` 毫秒且只影响物理攻击间隔。施毒继续使用独立 AntiPoison。
- `595e485d` 将反向伤害区间明确为 `legacy_clamp_negative_span`：最终跨度 `max-min`，负跨度钳零，绝不交换端点；幸运/诅咒只影响正跨度分布。
- `fcead306` 新增通用 `roll_primary_stat`：signed 总幸运统一作用于正跨度 DC/MC/SC，`+9/-9` 稳定命中上下限；治愈术使用 SC 掷骰，固定效果与施毒独立成功门不受幸运误影响。
- `b7d0ad7b` 完成 `equipment.blessing_luck.v2`：祝福油三结果、固定 5% 负面、幸运 7/诅咒 10、逐级抵消、全部装备基础 `luck-curse`、武器实例幸运/诅咒、零耐久停用和存档恢复均接入；跨度因子固定为 `R=max(1,floor(abs(DCmax-DCmin)/5))`，命运之刃幸运 +3 后可继续提升。
- `d2b8ab8` 将法师/道士施法身体动作固定为主源 `HA.ActSpell` 的 6 帧×60ms=360ms，并在完整动作期间锁定移动；动作、技能释放点和冷却独立，360ms 动作结束后仍须等待技能自身冷却，施法速度不缩短身体动作。
- `38592e01` + `b779594c` 修正原客户端装备页纸娃娃：Prguse #376 底图按主源码固定绘制于 `(38,52)`，衣服/武器/头盔继续使用 `(31,96)+Hot`；人物选择与装备页各只保留一个纸娃娃，选中存档装备与实时换装均有专项回归。
- `1d74fc72` 将地图外圈由旧圆半径净空升级为 `18×9` 等距椭圆脚底的逐边法向支撑距离；比奇四边真实 CharacterBody 脚点误差统一为 `-0.749978px`，内部碰撞、遮挡、地面坐标、相机和裙边未改。
- 越级审计列出的其余领域尚未返修完成，禁止写成已完成。明日从审计文档按优先级继续：装备图标/属性与旧穿戴、怪物/Boss 数值与外观、掉落、技能、头盔锚点及服务端规则生成器；每一项都必须先修主源解析或映射，再运行对应专项测试并逐项集成。
- 用户已确认此前截图来自当时最新 APK；不要再次怀疑或重复核验安装版本。用户已实机确认碰撞、装饰物遮挡、地图错位和视角全部解决，四项正式冻结；除非出现新的明确证据，后续任务不得顺带调整。
- 用户已实机确认 214 个 `monster_id` 逐个、逐姿态人工复核的 v4 怪物脚下光圈正确，正式冻结；除非出现新的明确证据，禁止顺带修改脚点、光圈中心、椭圆尺寸或投影策略。
- 战士/法师/道士 × 沃玛/祖玛/赤月的 9 个独立满技能测试人物已进入最新 APK；三职业装备外观仍需按原客户端正式素材重新取证，不能再将装备栏缩略图或带窗口背景的 raw stateitem 图当作纸娃娃/世界穿戴层。
- 装备显示已改为男性专用正式管线：原客户端装备页纸娃娃、男性世界衣服、男性世界武器与 12 个男性世界头盔均已集成；新增或重建世界穿戴资源禁止生成女性资产。
- 头盔概念表的格子顺序不可信。每个视觉身份必须保存显式 `sourceSlotDirectionOrder`，再重排为 `N,NE,E,SE,S,SW,W,NW`；方向重复或缺失必须阻断构建，禁止猜测。

## 最终 APK

- 文件：`C:\Users\Administrator\Documents\HardCore\outputs\hardcore\HardCore-debug.apk`
- 构建时间：`2026-07-26 10:11:35`
- 大小：`1,649,596,646` 字节
- SHA-256：`A5442D707659B766C4513DD57D6249486A9D60B2214EA34EC25D5A5CFB8C4325`
- 包信息：`com.personal.mafaoffline`，versionCode `35`，versionName `1.16.0-bich-map-runtime`，应用名 `HardCore`，`arm64-v8a`。
- 签名验证：APK Signature Scheme v2/v3 均通过，签名者 1。
- 本包包含 214 种怪物逐 ID v4 光圈校准、9 个三职业三套装满技能独立测试人物、男性专用正式人物与装备显示管线、primary-only 世界武器兼容合同、正式装备视觉目录、神兽动画、人物列表触摸滚动、法师/道士360ms施法动作与移动锁、原客户端纸娃娃单层坐标修复，以及等距椭圆脚底四边地图边界修复；角色存档只补建缺失项，不覆盖后续测试进度。

## 最近已集成结果

| 集成提交 | 领域 | 结果 |
|---|---|---|
| `345d073` | rules | 专业工作树开工前必须同步/锁定集成基线，交付后必须在当前主树复验，禁止旧基线假通过 |
| `1d74fc72` | maps | 外圈边界按当前等距椭圆脚底逐边求支撑距离；比奇四边与全部发布地图物理边界专项通过 |
| `8c7f6b4a` | maps/tests | 新增比奇四边真实 CharacterBody 边界对称性回归 |
| `b779594c` | UI | 人物选择/装备页单一纸娃娃、选中存档装备读取、实时换装刷新与触摸穿透 |
| `38592e01` | equipment | 按 FState.pas 修正 Prguse #376 `(38,52)` 底图坐标与单层合成合同 |
| `d2b8ab8` | skills/player | 法师/道士360ms施法身体动作与移动锁；释放点、冷却、施法速度和长特效时序完全分离 |
| `c1839b4` | integration/runtime | 玩家受直接法术统一转交 `take_direct_spell_damage`，禁止重复 MAC、物防或二次扣血 |
| `228063c` | integration/runtime | 火球、大火球、雷电、灵魂火符稳定技能 ID 与 AntiMagic/MAC 运行时接线 |
| `3700cd1d` | skills | 直接法术与施毒实际命中闭环；AntiMagic 与 AntiPoison 隔离 |
| `3d84db6c` | UI | 魔法躲避显示百分比，准确/敏捷显示点数，攻击速度显示档位 |
| `f85e6941` | skills/player | 装备 v2 魔闪内部点与攻击速度档位进入玩家聚合 |
| `555080da` | skills/player | 准确/敏捷严格命中、AntiMagic 与物理攻速统一规则 |
| `4130b5ac` | rules/integration | 来源优先级正式提升到装备属性主表 v2 |
| `e28fa1e5` | equipment | 导入用户审核工作簿，163 条正式装备属性与 v2 Schema |
| `b7d0ad7b` | equipment | `equipment.blessing_luck.v2`、R=0 边界修正、全部装备 luck/curse 汇总、消耗/耐久/存档回归 |
| `fcead306` | skills/player | 通用 `roll_primary_stat` 与 DC/MC/SC、治愈术、固定效果、反向区间专项 |
| `2a61617` | rules/integration | 装备属性独立主源 lane、项目正式主表授权、来源守卫与装备测试入口 |
| `26df7993` | equipment | 49 条武器/男衣属性正式主表、结构化需求/定位/性别/负重、反向区间 warning、炼狱 feature22 回归 |
| `595e485d` | skills/player | `legacy_clamp_negative_span` 统一 DC/MC/SC 反向区间、普通攻击与技能实际接线 |
| `c7489047` | equipment | 冻结用户逐项确认的武器与男性衣服世界外观映射 |
| `2b0da07e` | equipment | 主源专用武器兼容合同；35/37 可见、0 隐藏、2 未解析，职业与实体造型双轴分离 |
| `62a7c00` | audit | 固化主库/分级库越级审计，列出 13 类确定违规及逐域返修顺序 |
| `9512dbb` | rules | fallback 收紧为只有 primary 明确 missing 才允许；unusable/incompatible 必须修复而非降级 |
| `3eebf00` | rules | 总纲加入数据库与资料源 primary-first 硬规则 |
| `7bd71d5d` | equipment | 男性世界头盔扩展：12 itemId、11 视觉身份、6 动作、8 方向、2784 逻辑帧；方向显式识别与重排 |
| `a00fb90` | rules | 集成主任务成为唯一项目内审批者，禁止把子任务审批、取舍或测试确认转交用户 |
| `3e3510fa` | integration/tests | Godot 自动化固定使用 console/headless、安全 runner、项目内日志与隔离 APPDATA，避免 Windows c0000005 弹窗 |
| `5543fd9c` | equipment | 男性世界武器合同：37 件正式武器，31 件可见、2 件经典隐藏、4 件待原始证据 |
| `94ebf0a7` | equipment | 男性世界衣服合同：12/12 男性衣服、6 动作、8 方向 |
| `fe539a1d` | equipment | 原客户端男性装备页纸娃娃资源阶段与完整 StateItem 坐标溯源 |
| `c88c6277` | monsters | 214 种怪物逐 ID 独立人工复核脚点、光圈中心、椭圆尺寸与地面/飞行/悬浮策略 |
| `5fd35f07` | integration/tests | 覆盖男女基础外观、实时换装和运行时性别刷新 |
| `ae5e800f` | integration/tests | 更新旧回归断言，法师正式人物层不再隐藏 |
| `edcb989b` | equipment/tests | 装备图集画布与脚点测试改为读取正式视觉目录 |
| `f6290510` | integration | 接入战士、法师、道士正式人物基础、衣服、武器与头盔运行时外观 |
| `5eba6942` | equipment | 175 件正式装备目录、73 个可视穿戴项与 456 张世界穿戴动作图集 |
| `a78222ac` | UI | 人物列表支持整块区域触摸滑动；装备界纸娃娃居中 |
| `466f261a` | skills | 道士神兽正式动画接入 |
| `8165123` | integration | 自动补建 9 个独立三职业三套装满技能测试人物，且不覆盖既有测试进度 |
| `07fe41d4` | equipment | 9 套沃玛/祖玛/赤月正式装备目录，共 72 个装备槽 |
| `b23ed8d0` | monsters | 214 种怪物按动作和方向使用稳定真实脚底接触点 |
| `2809e74a` | skills | 三职业完整 33 技能模板与 9 个稳定人物配置 ID |
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

- integration：`world.actor_footprint.iso_ellipse.v1`、`test.character.roster.full_equipment_skills.v1`。
- maps：`map_editor_runtime_collision_geometry_v2`、`map_visible_edge_actor_footprint_clearance_v2`、`published_blocked_cells_after_erasure_v1`、`map_editor_runtime_visual_geometry_v5`、`map_actor_occlusion_sort_v5`、`map_diamond_camera_center_constraint_v2`、`player_priority_soft_edge_v1`、`map_runtime_nonwalkable_edge_skirt_v1`。
- monsters：`monster.overhead_anchor.v4`、`monster.overhead_layout.v3`、`monster.ground_contact.v4`、`monster.ground_contact.calibration.v4`；214 个 `monster_id` 各自保存人工复核的脚点、光圈中心、椭圆尺寸和投影策略，贴图异步激活后必须刷新。
- UI：`ui.hud.resource_orb.hole_fill.v1`、`skill_button_assignment_contract_v2`。
- equipment：`equipment.attribute.master.v2`、`project.hardcore.equipment_attribute_master.v2`、`equipment.test_loadouts.classic_three_tiers.v1`、`equipment.visual_catalog.formal_wearables.v1`、`equipment.paper_doll.original_client_stage.v1`、`equipment.world_wear.male_dress.v1`、`equipment.world_wear.male_weapon.v1`、`equipment.world_helmet.male.extension.v1` 与 9 个 `test.loadout.{profession}.{tier}.v1`。
- skills：`combat.resolution.openmir2.v1`、`physical.hit.random_agility.strict_lt.v1`、`magic.evasion.anti_magic.direct_spell.v1`、`physical.attack_speed.interval_tier.v1`、`player.direct_spell_damage.openmir2.v1`、法师/道士主动技能 `action_duration=0.36` / `action_frame_count=6` / `action_frame_time_ms=60` 时序字段、`legacy_clamp_negative_span`、`test.characters.full_skills.v1` 与 9 个 `test.character.{profession}.{woma|zuma|chiyue}.v1`。

## 已通过的必要验收

- 总回归：`SMOKE_TEST_PASS`。
- integration：共享 36×18 等距脚底契约通过；运行时 Camera2D 菱形视口约束通过。
- camera：2664×1200 下人物屏幕偏移≤全尺寸 14%，动态缩放为 1.06–1.16；80×80 与 38×38 地图外露均由 1536px 不可行走裙边覆盖。
- monsters：v4 数据生成检查、214/214 人工复核覆盖、214 种怪物五动作八方向运行时坐标链、214/214 冷激活、完整怪物客户端美术通过。
- test roster：9 个独立存档、72 个正式装备槽、99 个角色技能加载项、三职业选择恢复和二次启动不覆盖通过。
- player/equipment：原客户端男性装备页纸娃娃、男性世界衣服、男性世界武器、男性世界头盔、实时换装、正式装备视觉目录、装备纸娃娃居中和战士旧回归通过。
- equipment attributes：163 条唯一正式装备、114 条工作簿覆盖、v2 Schema/来源优先级/幂等构建、魔闪点数拆分、准确/敏捷/攻速档位及 UI 单位均通过。
- combat resolution：严格物理命中、AntiMagic/AntiPoison 隔离、玩家与怪物默认点数边界、直接法术 AntiMagic→MAC→扣血、tier 物理攻击间隔、GameRoot 稳定技能 ID 和共享运行时转交均通过；最终相关回归 9/9，`SMOKE_TEST_PASS`。
- blessing/luck：`equipment.blessing_luck.v2`、三结果、5% 负面、幸运 7、诅咒 10、命运之刃 R=0 修正、全部装备 luck/curse、消耗/存档/零耐久、DC/MC/SC 与治愈术专项通过。
- damage ranges：`legacy_clamp_negative_span`、通用 `roll_primary_stat`、战士公式、攻击时序与法系伤害公式通过；反向区间不会被幸运/诅咒交换端点，恢复正跨度后效果自动恢复。
- equipment helmets：12 itemId/11 视觉身份、66 物理 atlas、2784 逻辑帧、6 动作×8 方向、透明角、Hair 逐帧锚点/SHA 溯源与 StateItem 世界像素零复用通过；Godot 头盔专项、视觉目录与 smoke 通过。
- physics：玩家 18×9、普通怪物 16×8、Boss 28×14 的真实物理与软件探针通过；战斗/AI 半径未改。
- occlusion：11 张已发布地图、52 个交叉、4 类装饰物和 3 个比奇回归点通过；碰撞区、脚底深度点、装饰物遮挡基线已分离。
- maps：比奇真实源 E2E（180 个阻挡格）；11 张地图真实 `CharacterBody2D` 脚点可达可见边缘且外环阻挡。
- monsters：真实名字/血条节点覆盖 4 类怪物、8 方向、idle/walk/attack/hit/death 全帧和 Camera2D 缩放；214 种怪物加载通过。
- UI：2664×1200 HUD 血蓝球尺寸/对称/安全区通过；技能配置与拾取提示专项通过。
- skills：快捷槽 v2 换槽、烈火自动开关、战士技能状态机，以及法师/道士360ms施法动作、移动锁、独立冷却和6帧推进通过。

只在相关代码再次变化时重跑对应专项；跨域接线或发布前再跑一次 smoke。

## 永久工作树状态

| 工作树 | 分支/HEAD | dirty | 集成状态 |
|---|---|---:|---|
| `HardCore-worktrees/maps` | `codex/maps` @ `599717ce` | 72 untracked | 用户地图编辑器内容，继续保护 |
| `HardCore-worktrees/monsters` | `codex/monsters` @ `45781ded` | tracked clean；68 UID | 已集成为 `c88c6277` |
| `HardCore-worktrees/ui-art` | `codex/ui-art` @ `1aff5350` | clean | 已集成为 `a78222ac` |
| `HardCore-worktrees/professions-skills` | `codex/professions-skills` @ `0250935c` | tracked clean；既有 UID 继续保护 | 通用主属性幸运专项已集成为 `fcead306` |
| `HardCore-worktrees/equipment` | `codex/equipment` @ `911487b7` | 4 个既有 monster import 与全部生成 UID 继续保护 | 祝福/诅咒 v2 已集成为 `b7d0ad7b`；属性主表与视觉冻结保持集成 |

### maps 保护红线

maps 的 72 项未跟踪内容全部视为用户进行中的地图编辑器内容，禁止清理、还原、覆盖或批量暂存。重点包括地图 editor JSON/备份、ground chunks/manifests/state/preview、新地图工作区和 UID。开始新 maps 任务时只暂存本次明确修改的文件。

## 各领域最小必读

- maps：`AGENTS.md`；`scripts/map_editor/map_editor_runtime_collision_geometry_service.gd`；`scripts/map_editor/map_editor_runtime_visual_geometry_service.gd`；`scripts/world_background.gd`；对应地图 E2E 测试。
- monsters：`AGENTS.md`；`scripts/enemy.gd`；`scripts/monster_overhead.gd`；`scripts/monster_visual.gd`；`tests/monster_health_bar_anchor_test.gd`。
- UI：`AGENTS.md`；`scripts/gothic_ui_theme.gd`；目标面板或 `scripts/hud.gd`；对应 UI 专项测试。
- skills：`AGENTS.md`；`scripts/player.gd`；`scripts/profession_rules.gd`；`scripts/skill_loadout_rules.gd`；对应状态机测试。
- equipment：`AGENTS.md`；`scripts/equipment_rules.gd`；`assets/data/equipment_actor_sort_contract.json`；对应排序契约测试。

## 下次实机验收清单

1. 已冻结：碰撞、装饰物遮挡、地图错位和视角均由用户实机确认通过。
2. 已冻结：v4 怪物脚下光圈已由用户实机确认正确。
3. 待验收：角色选择页出现 9 个独立测试人物；三职业各有沃玛、祖玛、赤月三档完整装备并学习本职业全部技能；列表整块区域可直接上下滑动。
4. 待验收：法师、道士不再显示占位符；男性基础形象、正式散件/套装换装、装备界纸娃娃居中和神兽动画正常；禁止重新引入女性角色资产。
5. 怪物名字固定在血条上方；各体型血条位于各自真实身体顶点上方约 8px，不再统一过高或随动作抖动。
6. 血球/蓝球恢复孔径尺寸且左右对称。
7. 拾取提示居中；技能配置弹窗背景不越界；快捷技能可置换；烈火自动开关正常。

用户实测结果优先级高于内部测试；若实机失败，先保存截图和 APK 哈希，再按所属专业工作树返修。
