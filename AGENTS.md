# 项目协作与工作树规则

本项目使用一个集成分支和五个专业工作树。开始工作前必须运行 `git branch --show-current`，根据当前分支遵守下面的文件所有权。

## 分支职责

### `codex/integration`

- 当前主目录，负责基线、跨系统接口、合并、冲突处理和完整验收。
- 独占跨系统文件：`project.godot`、`AGENTS.md`、`scripts/game_root.gd`、`scripts/game_data.gd`、`scripts/region_content.gd`、存档格式、全局服务注册和跨系统测试入口。
- 地图刷新怪物、怪物掉落装备、任务引用地图/怪物/装备等映射，只能在这里最终接入。

### `codex/ui-art`

- 负责 `assets/ui/**`、`scripts/hud.gd`、`scripts/*_panel.gd`、`scripts/equipment_character_preview.gd`、UI 专属素材和 UI 测试。
- 只读取玩法数据；不得修改装备属性、怪物数值、地图内容、掉落和存档格式。
- 公共 UI 视觉规范必须集中复用，禁止每个面板自行复制一套主题。

### `codex/maps`

- 负责 `assets/art/maps/**`、`assets/maps/**`、地图资源目录、`map_editor_workspace/**`、`scripts/map_*.gd`、`scripts/map_assets/**`、`scripts/map_editor/**`、环境目录/验证器，以及地图相关工具和测试。
- 地图只定义位置、碰撞、门点、区域和 `spawn_group_id`；不得直接修改怪物属性或装备掉落。

### `codex/monsters`

- 负责 `assets/art/monsters/**`、怪物/Boss 专属数据、`scripts/enemy.gd`、`scripts/monster_visual.gd`、怪物动画策略、Boss 机制，以及怪物相关工具和测试。
- 使用稳定的 `monster_id` 输出外观、动画、AI 和战斗行为；不得修改地图几何、装备定义或 UI。

### `codex/equipment`

- 负责 `assets/art/items/**`、物品/装备专属数据、`scripts/equipment_rules.gd`、装备美术构建工具和装备相关测试。
- 使用稳定的 `item_id` 输出图像、属性、穿戴和耐久规则；不得修改背包布局、地图内容或怪物刷新。

### `codex/professions-skills`

- 负责职业成长、玩家技能、技能投射物、召唤物、职业战斗公式、技能状态机、技能特效，以及对应数据、构建工具和测试。
- 主要所有权包括 `scripts/profession_rules.gd`、`scripts/skill_projectile.gd`、`scripts/summon_actor.gd`、`scripts/warrior_combat_math.gd`、`assets/data/vanilla_176/skills.json`、`assets/data/vanilla_176/profession_growth.json` 和职业/技能专项测试。
- 玩家职业技能特效可写入 `assets/art/characters/**/effects/**`；`paper_doll`、`wear` 和装备图像仍归装备分支。
- `scripts/skill_panel.gd` 和 `scripts/profession_panel.gd` 的视觉布局仍归 UI 分支；本分支只提供稳定数据与行为接口。
- `scripts/layers/runtime/combat_runtime_service.gd` 属于跨怪物/职业共享运行时，最终修改由集成分支接入。
- 不得修改怪物 AI、地图刷新、装备定义、UI 布局或全局存档格式。

## 品牌与命名规则

- 正式游戏品牌和安装后的应用名称统一为 `HardCore`。
- Android 玩家可见应用名称统一为 `HardCore`；内部包 ID `com.personal.mafaoffline` 为旧安装与存档升级兼容标识，不得仅因品牌改名而变更。
- 玩家可见标题、按钮、世界总称、通用提示和新建内容不得再使用“玛法”“传奇”“MafaOffline”等旧品牌名称。
- 原始客户端/服务端来源说明、历史验收记录、`legend176_data.json` 等内部溯源路径，以及 `mafa_world` 等既有稳定 ID 允许保留；它们不得直接作为玩家可见文案，也不得仅为改名而破坏兼容性。
- 各专业分支新增 UI 文案、数据展示名或导出配置时，必须以 `HardCore` 为品牌基线。

## 跨工作树协作

- 需要修改其他分支所有权内的文件时，不得直接修改；在交付说明中记录所需接口、字段/ID、原因和验收方式。
- 大型原始素材目录 `dev_art_sources`、本地 Godot 工具和 DepotDownloader 不进入 Git；它们由各工作树中的本地目录联接共享，并视为只读输入。
- `.godot` 和 `outputs` 在每个工作树中独立生成，禁止跨工作树共享缓存或输出目录。
- 每个专业分支只提交本领域文件。提交前运行相关专项测试并记录结果。
- 集成分支一次只合并一个专业提交；每次合并后运行冒烟测试，再合并下一个。
- 禁止破坏既有数据可追溯、玩法可扩展、资源可替换、系统可测试的原则。

## 交付格式

每个工作树完成任务时必须给出：

1. 修改文件列表。
2. 测试命令与结果。
3. 新增或变更的稳定 ID。
4. 需要集成分支处理的跨系统接入事项。
5. 当前提交哈希。
