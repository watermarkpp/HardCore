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

### 8. 死亡与复活选择尚未接入正式死亡流程

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 简洁死亡遮罩、死亡状态和损失信息。
- 最近城镇复活、特殊复活两个稳定入口。
- 倒计时、可用状态和不可用原因显示。
- 契约：`assets/ui/gothic_theme/v1/death_revival_contract_v1.json`。
- HUD 转发接口：
  - `GameHUD.show_death_screen(context)`
  - `GameHUD.set_revival_options(options)`
  - `GameHUD.update_revival_option(option_slot, state)`
  - `GameHUD.apply_revival_result(result)`
  - `GameHUD.close_death_screen()`
  - `GameHUD.revival_requested(request)`

当前缺口：

- `scripts/player.gd` 当前在死亡动画约 0.8 秒后恢复满血并发出死亡信号。
- `scripts/player.gd` 当前调用 `PlayerState.lose_gold_percent(0.05)`，与已确认规则冲突。
- `scripts/game_root.gd::_on_player_death_requested()` 随后立即把人物送回比奇省并保存。
- 正式运行时不会等待玩家选择复活方式。
- 特殊复活的道具消耗、冷却、原地/安全点规则和失败处理都属于玩法层。

主树接入：

1. 将当前立即回城流程改成明确的死亡等待状态，并显示死亡面板。
2. 生成稳定 `death_id`，向 UI 注入城镇与特殊复活选项。
3. 落实已确认死亡惩罚：扣除当前经验的 10%，不扣金币，不掉落或删除任何物品。具体取整方式由玩法规则统一定义。
4. 删除当前死亡扣除 5% 金币的旧逻辑。
5. 城镇复活倒计时、目的地图和安全落点由玩法层决定。
6. 特殊复活必须重新校验装备、道具、冷却和死亡事件是否仍有效。
7. 消费 `ui.death.revival.v1` 请求后原子执行规则，再通过 `apply_revival_result` 回传结果。
8. 阻止重复点击、过期 `death_id`、多次扣经验、扣道具或多次复活。
9. Android 返回键不能绕过死亡状态或关闭必须选择的死亡面板。

验收：

- 普通死亡在倒计时结束后允许最近城镇复活。
- 特殊复活按真实资源和冷却显示亮起或禁用，并显示准确原因。
- 成功复活只执行一次；失败时保留界面并刷新原因。
- 普通死亡只损失 10% 经验；金币和所有物品保持不变。
- 复活位置和特殊复活物品消耗符合玩法数据。

### 9. 战利品分类、满包失败和 Boss 掉落反馈尚未接入玩法结果

状态：`UI_READY_RUNTIME_MISSING`、`RULE_DECISION_REQUIRED`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 轻量地面物品名称组件，并按金币、任务物品、装备、技能书、消耗品和材料使用不同颜色。
- 普通拾取提示最多保留最近三条。
- 背包已满/无法拾取提示。
- Boss 与高价值掉落强化横幅。
- 契约：`assets/ui/gothic_theme/v1/loot_feedback_contract_v1.json`。
- HUD 入口：`GameHUD.show_loot_feedback(event)`。
- 旧 `GameHUD.show_loot(item_name)` 保留兼容，会生成普通成功提示。

当前缺口：

- `scripts/loot_pickup.gd` 靠近人物后立即发出 `collected` 并删除地面实例，不等待背包写入结果。
- `scripts/game_root.gd::_on_loot_collected()` 先调用无返回值的 `PlayerState.add_item()`，随后无条件显示“获得”。
- `PlayerState.add_item()` 目前没有背包容量失败结果，也没有落实已确定的 100 格上限。
- Boss 身份在怪物死亡时可知，但 `_spawn_loot()` 没有把来源和高价值分类传给地面掉落。
- UI 无权自行根据名称或售价猜测稀有度。

主树/装备/掉落系统接入：

1. 为每个地面掉落生成稳定 `drop_id`，保留 `item_id`、数量、怪物来源和 `source_is_boss`。
2. 落实人物背包总容量 100 格；可堆叠物品按玩法最大堆叠规则判断是否仍可合并。
3. 把拾取改成有明确成功/失败结果的事务：
   - 成功后才删除地面实例并发送 `pickup_success`。
   - 背包已满或规则拒绝时保留地面实例并发送 `pickup_failed`。
4. 不得继续使用“先删除掉落，再无条件增加背包”的流程。
5. 装备/掉落数据提供稳定 `emphasis`：`normal`、`rare`、`high_value`、`boss`。
6. Boss 或高价值物品生成时发送 `rare_drop`，而不是等拾取完成后才提示。
7. 用 `scripts/loot_ground_label.gd` 替换 `loot_pickup.gd` 中现场创建的裸 `Label`，图标和拾取碰撞逻辑保持玩法层所有。
8. 同一个 `drop_id` 的拾取请求必须防止重复入包。

验收：

- 金币、任务物品、装备等地面名称颜色清楚但不遮挡战斗。
- 连续拾取只显示最近三条，自动消失。
- 满 100 格时不可容纳的物品仍留在地面，并显示准确原因。
- 可继续合并的堆叠物品不被错误判定为满包。
- Boss/高价值掉落显示强化横幅，普通掉落不会滥用横幅。
- 物品只增加一次，失败拾取不增加背包也不删除地面掉落。

### 10. 地图切换尚未接入 Loading 过渡

状态：`UI_READY_RUNTIME_MISSING`、`INTEGRATION_OWNED_FILE`

UI 已完成：

- 全屏半透明深灰遮罩。
- 唯一可见文字固定为 `Loading......`。
- 淡入覆盖和淡出完成信号。
- 契约：`assets/ui/gothic_theme/v1/loading_transition_contract_v1.json`。
- HUD 接口：
  - `GameHUD.begin_loading_transition(transition_id)`
  - `GameHUD.finish_loading_transition()`
  - `GameHUD.loading_transition_covered(request)`
  - `GameHUD.loading_transition_finished(request)`

明确禁止：

- 地图名称。
- 区域说明。
- 游戏提示。
- 进度条。
- 装饰框或其他文字。

当前缺口：

- `scripts/game_root.gd::travel_to_map()` 和 `travel_to_service_home()` 会直接同步调用 `_load_zone()`。
- 正式地图切换没有调用 Loading 过渡层，也不会等待遮罩覆盖后再替换地图内容。

主树接入：

1. 每次地图切换生成唯一 `transition_id`。
2. 先调用 `begin_loading_transition(transition_id)`。
3. 等待同一 `transition_id` 的 `loading_transition_covered`，再执行 `_load_zone()`、设置人物落点和生成地图内容。
4. 地图内容与首帧准备完成后调用 `finish_loading_transition()`。
5. 传送、门点切图、死亡回城和特殊回城统一使用同一流程。
6. 同一时间只允许一个地图过渡，拒绝重复传送或过期完成回调。
7. Loading 期间阻止人物移动、攻击、拾取和面板操作。
8. 不得向过渡层注入地图名或其他说明文字。

验收：

- 旧地图先被遮罩覆盖，新地图准备完成后才淡出。
- 全程唯一可见文字为 `Loading......`。
- 人物不会在切图中移动、攻击或重复触发传送。
- Android 宽屏与安全区均完整覆盖，不露出可点击边缘。

## 已完成且不应由主树重新设计的 UI 内容

以下内容属于 UI 分支成果，主树接入时应复用，不要重新建立不配套的样式：

- 公共哥特 Theme 与公共组件。
- 商店高风险出售、任务放弃和职业切换已统一复用 `ui.confirmation.dialog.v1`，不得恢复为系统原生确认框或面板私有弹窗。
- HUD、人物与背包、商店、任务、地图、仓库、技能、职业面板。
- 哥特人物选择与创建大厅。
- 哥特暂停菜单和双音频开关设置页。
- 人物大厅和暂停菜单使用宽屏居中画布；最终一致性测试覆盖 1280×720、1920×1080 宽屏和 2400×1080 Android 挖孔安全区。

玩法层仍可通过已声明的注入方法更新数据，但不应把规则复制回 UI。

## 主树合并检查表

- [ ] 阅读本文件和 `assets/ui/gothic_theme/v1/integration_handoff_v1.json`。
- [ ] 逐项确认 7 个 P0 接入项的负责人。
- [ ] 不修改稳定契约 ID 和字段含义；如需升级，新增版本并保留兼容层。
- [ ] 先完成运行时接线，再宣布对应功能“已完成”。
- [ ] 运行所有现有 UI 专项测试。
- [ ] 运行 `res://tests/ui_final_consistency_test.tscn`，不得删除安全区、越框与触控区域断言。
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
- 死亡后仍会沿用旧的自动回城流程，不会等待新复活界面选择。
- 满包失败、Boss 来源和高价值掉落尚未进入正式拾取流程。
- 地图切换仍会直接同步替换内容，尚未使用新的 Loading 遮罩时序。

这些不是美术遗漏，而是 UI 分支权限边界内无法完成的主树/玩法接入工作。
