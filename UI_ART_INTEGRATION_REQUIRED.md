# UI 美术分支：主树必读接入记录

> 状态：必须由 `codex/integration` 在合并 UI 成果时逐项处理。
>
> 来源分支：`codex/ui-art`
>
> 记录版本：`ui.integration.handoff.v1`
>
> 更新日期：2026-07-18

## 为什么有这份记录

UI 分支只能负责界面、交互请求和稳定契约，不能修改 `project.godot`、`scripts/game_root.gd`、全局服务、存档格式、玩法规则、地图规则或职业技能行为。

因此，下列界面虽然已经完成视觉和 UI 交互，但在主树完成接线前，不能视为对应玩法已经完成。主树不得根据按钮文字猜测规则，应读取本记录列出的 JSON 契约。

状态含义：

- `UI_READY_RUNTIME_MISSING`：界面和请求已完成，正式运行时尚未消费。
- `RULE_DECISION_REQUIRED`：UI 已给出边界，但具体玩法规则必须由主树或对应专业分支决定。
- `INTEGRATION_OWNED_FILE`：完成接入必须修改主树独占文件，UI 分支不能越权处理。

## P0：合并后必须处理

### 1. 正式游戏仍在使用旧暂停菜单

状态：`UI_READY_RUNTIME_MISSING`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- `scripts/system_menu_panel.gd`
- 哥特暂停菜单：继续游戏、游戏设置、返回人物选择、保存并退出。
- 设置页当前仅包含游戏音乐、游戏音效。
- 契约：`assets/ui/gothic_theme/v1/system_menu_audio_contract_v1.json`

当前缺口：

- `scripts/game_root.gd::_build_system_menu()` 仍现场创建旧版纯代码按钮列表。
- 正式游戏没有实例化 `SystemMenuPanel`。
- 设置按钮虽然可以在 UI 样板中操作，但正式运行时未连接任何音频服务。

主树接入：

1. 在 `scripts/game_root.gd` 中用 `SystemMenuPanel` 替换旧菜单。
2. 保持菜单节点 `PROCESS_MODE_WHEN_PAUSED`。
3. 连接：
   - `continue_requested` → 关闭菜单并解除暂停。
   - `return_to_character_select_requested` → 安全保存后返回人物选择。
   - `save_and_exit_requested` → 安全保存后退出。
   - `audio_setting_changed(request)` → 全局音频设置服务。
4. 打开菜单前用 `set_audio_settings(music_enabled, sfx_enabled)` 注入真实设置值。

验收：

- Android 返回键和 `ui_cancel` 都打开新哥特菜单。
- 菜单打开期间游戏暂停，但菜单仍可点击。
- 返回人物选择、保存退出沿用现有安全保存逻辑。

### 2. 音乐和音效开关尚未控制真实音频

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

稳定设置 ID：

- `audio.music.enabled` → `Music` 总线。
- `audio.sfx.enabled` → `SFX` 总线。

当前缺口：

- 项目没有由 UI 分支可管理的全局设置/音频服务。
- `project.godot`、音频总线注册和设置持久化归主树所有。
- UI 不会直接调用 `AudioServer`，也不会自行改变存档格式。

主树接入：

1. 建立或登记 `Music`、`SFX` 音频总线。
2. 将背景音乐播放器路由到 `Music`，技能、攻击、界面等音效路由到 `SFX`。
3. 消费 `ui.audio.setting.v1` 请求并切换对应总线。
4. 持久化两个布尔值。建议使用账号/设备级全局设置，不写入单个人物存档。
5. 启动游戏和打开设置页时回填当前值。

验收：

- 关闭音乐不影响音效；关闭音效不影响音乐。
- 重新启动后保留上次选择。
- 主音量或总线缺失时有安全回退，不导致运行时报错。

### 3. 三职业创建和纯男性规则尚未在玩法层落实

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 创建界面可选战士、法师、道士。
- 不再提供性别选择，创建请求固定 `gender = "男"`。
- 创建请求契约：`ui.character.creation.v1`。
- 角色启动契约：`assets/ui/gothic_theme/v1/character_launch_contract_v1.json`。

当前缺口：

- `scripts/player_state.gd::create_character()` 仍拒绝非战士，返回“当前版本仅开放战士”。
- 同一方法仍接受“女”，与已确定的纯男性新角色规则不一致。

主树接入：

1. 使用 `ProfessionRules.PROFESSIONS` / 稳定职业 ID 校验并允许战士、法师、道士创建。
2. 新建人物只允许男性模型。
3. 对历史女性存档制定兼容策略；不得静默删除或损坏旧档。建议旧档可读取，但运行时使用男性纸娃娃，是否迁移字段由主树决定。
4. 不要在 UI 内复制职业初始属性、技能或成长公式。

验收：

- 三职业都可创建、保存、重新选择并进入游戏。
- 新建请求无法产生女性角色。
- 历史存档仍可安全列出和载入。

### 4. 第二角色 AI 队友目前只生成启动上下文

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 每个角色都可作为主角色。
- 可选择另一个不同角色作为 AI 队友，并可随时关闭携带。
- 启动请求契约：`ui.character.launch.v1`。
- 临时上下文写入场景树根节点 meta：`pending_character_launch_context`。

请求字段：

- `main_profile_id`
- `ai_teammate_enabled`
- `ai_teammate_profile_id`
- `ai_control_mode`，当前值为 `companion_ai` 或 `disabled`

当前缺口：

- `scripts/game_root.gd` 没有读取或清理该启动上下文。
- 游戏没有第二角色载入、生成或 AI 控制运行时。
- UI 不允许把队友档案写成当前主档，也不能决定队友玩法规则。

主树接入：

1. 进入主场景时读取并校验 `pending_character_launch_context`，消费后清理。
2. 主角继续使用 `PlayerState.active_profile_id`。
3. 队友以独立、只读快照载入；不得覆盖主角单例状态。
4. 由主树联合职业技能系统定义：
   - 跟随与脱离距离。
   - 自动选怪、攻击和技能使用。
   - 装备与背包所有权。
   - 药品消耗。
   - 死亡、复活、传送和切图。
   - 经验、掉落和任务归属。
   - 是否及何时把队友状态写回其人物档案。
5. 队友档不存在、与主角相同或读取失败时，应降级为不携带队友并给出提示。

验收：

- 任意角色都能轮流作为主角。
- 不同角色可作为 AI 队友；关闭后不生成。
- 主角和队友档案不会串档或相互覆盖。
- 切图、死亡和退出后行为符合主树确定的规则。

### 5. 商店出售页尚无玩法报价和交易处理

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`

UI 已完成：

- 出售页读取人物背包，不展示已穿戴装备。
- 支持出售单件、出售指定数量。
- 支持高价值、强化、幸运、特殊物品二次确认。
- 契约：`assets/ui/gothic_theme/v1/shop_sell_contract.json`

当前缺口：

- `ShopPanel.sell_quotes_requested(items)` 没有玩法层消费者。
- `ShopPanel.sell_requested(request)` 没有玩法层消费者。
- 正式运行时没有调用 `set_sell_quotes(quotes)` 和 `apply_sell_result(result)`。
- 因 UI 被明确禁止自行计算售价，出售按钮会停留在等待报价/不可用状态。

主树接入：

1. 打开出售页后，根据稳定物品 ID、实例 ID、商店类型和玩法数据生成报价。
2. 返回 `quote_id`、`sellable`、`unit_price`、`max_quantity`、`reason`、`requires_confirmation`、`risk_flags`、`warning`。
3. 收到出售请求后重新验证报价、背包索引、实例 ID、数量和物品状态，避免陈旧报价或重复请求。
4. 玩法层原子地扣除物品并增加金币；UI 不直接修改交易数据。
5. 用 `apply_sell_result` 回传成功/失败消息和刷新后的报价。
6. 建议主树接入时在 `GameHUD` 增加明确的报价/出售转发接口，避免跨层直接依赖面板内部节点。

验收：

- 出售页显示当前人物背包内容和真实售价。
- 已穿戴装备不能出售。
- 高风险装备必须确认。
- 金币与物品数量一次且仅一次地更新。
- 报价失效、数量变化和并发点击均安全失败。

### 6. 七个技能按钮的分配和技能类型行为尚未落到运行时

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 可配置中央 4 个技能按钮和攻击按钮周围 3 个技能按钮。
- 契约：`assets/ui/gothic_theme/v1/skill_button_assignment_contract_v2.json`。
- 稳定槽位：
  - `hud.profession_skill.1` ～ `hud.profession_skill.4`
  - `hud.attack_ring_skill.1` ～ `hud.attack_ring_skill.3`
- UI 支持展示 `toggle`、`click`、`passive`，但不决定技能类型。

当前缺口：

- `scripts/game_root.gd` 没有消费 `GameHUD.skill_button_assignment_requested`。
- 主树没有向 `GameHUD.set_skill_button_assignments(assignments, interaction_modes)` 注入七槽真实配置。
- 现有 `PlayerState.quick_slots` 只有 4 项，无法完整持久化七槽映射。
- 正式战斗仍主要通过旧四快捷槽调用，攻击环三技能未形成完整运行时链路。

主树/职业技能分支接入：

1. 职业技能数据为每个技能提供稳定 `skill_id` 和 `interaction_mode`：
   - 刺杀、半月、烈火等状态技 → `toggle`。
   - 火墙、雷电术等即时技能 → `click`。
   - 魔法盾、召唤物等按技能定义决定 `toggle` 或其他明确模式。
2. 主树验证职业、已学习状态、槽位合法性和重复规则后保存映射。
3. 设计七槽持久化。存档格式由主树独占，UI 不得直接扩展。
4. 载入角色、学习技能、切换职业或修改配置后回填 HUD 和技能面板。
5. 战斗输入按技能数据执行，不能由按钮位置硬编码技能行为。
6. 兼容旧契约 `ui.skill.quick_slot_assignment.v1`，迁移完成后再决定何时废弃。

验收：

- 七个槽位都可独立配置、保存并在重进游戏后恢复。
- 技能图标、名称和开关徽标与真实技能一致。
- `toggle` 技能保持状态，`click` 技能单次释放。
- 未学习、职业不符和不可配置技能被玩法层拒绝并回传提示。

### 7. 世界地图传送规则和落点尚未接入

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 世界树大点、左侧子地图列表和统一“传送”按钮。
- 按地图规则显示亮起或禁用状态。
- 契约：`assets/ui/gothic_theme/v1/world_map_teleport_contract.json`。

当前缺口：

- `scripts/game_root.gd` 没有消费 `GameHUD.map_teleport_availability_requested`。
- 主树没有调用 `GameHUD.set_map_teleport_availability(rules)`。
- `GameHUD.map_teleport_requested(request)` 未接入规则校验和指定门点。
- UI 无权决定哪些地图可传送，也无权创建地图出口锚点。

主树/地图分支接入：

1. 地图数据提供稳定传送规则和 `arrival_anchor_id`。
2. 初期仅开放主城和洞穴入口；例如牛魔寺庙列表可显示全部层级，但只允许传送到牛魔寺庙一层出口位置。
3. 根据当前区域、解锁条件和地图状态返回：
   - `enabled`
   - `destination_map_id`
   - `arrival_anchor_id`
   - `destination_label`
   - `reason`
   - `rule_id`
4. 收到传送请求时由主树再次校验，不能只相信 UI 的按钮禁用状态。
5. 传送必须落到指定安全门点；缺少锚点时拒绝并提示，不能默认为地图原点。

验收：

- 未开放地图按钮保持黑/禁用并显示原因。
- 开放入口按钮亮起。
- 牛魔寺庙等洞穴按规则传送到一层指定出口，不传送到任意层或错误坐标。
- 伪造请求、过期规则和缺失门点均被运行时拒绝。

## 已完成且不应由主树重新设计的 UI 内容

以下内容属于 UI 分支成果，主树接入时应复用，不要重新建立不配套的样式：

- 公共哥特 Theme 与公共组件。
- HUD、人物与背包、商店、任务、地图、仓库、技能、职业面板。
- 哥特人物选择与创建大厅。
- 哥特暂停菜单和双音频开关设置页。

玩法层仍可通过已声明的注入方法更新数据，但不应把规则复制回 UI。

## 主树合并检查表

- [ ] 阅读本文件和 `assets/ui/gothic_theme/v1/integration_handoff_v1.json`。
- [ ] 逐项确认 7 个 P0 接入项的负责人。
- [ ] 不修改稳定契约 ID 和字段含义；如需升级，新增版本并保留兼容层。
- [ ] 先完成运行时接线，再宣布对应功能“已完成”。
- [ ] 运行所有现有 UI 专项测试。
- [ ] 增加主树级集成测试，验证真实数据变化、存档恢复和 Android 返回键。
- [ ] 完成后在集成提交说明中逐项标记已接入或仍阻塞。

## 对用户必须明确提示

在主树完成上述接入前：

- 新哥特暂停菜单尚未出现在正式游戏中。
- 音乐/音效开关尚不改变真实声音，也不会保存。
- 法师、道士创建仍会被玩法层拒绝。
- 选择 AI 第二角色不会在游戏中生成队友。
- 商店出售不会获得真实报价，也不会完成交易。
- 七槽技能分配不会完整保存和驱动战斗。
- 世界地图传送按钮不会获得正式开放规则与指定落点。

这些不是美术遗漏，而是 UI 分支权限边界内无法完成的主树/玩法接入工作。
