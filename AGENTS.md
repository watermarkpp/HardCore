# HardCore 项目协作与工作树规则

## 启动与导航

- 本项目含 `codex/integration` 和五个专业工作树。开工前完整读取本文件，运行 `tools/agent_bootstrap.ps1 -Compact` 和 `git branch --show-current`，再依次读 `PROJECT_CURRENT_STATUS.md`、`PROJECT_HISTORY_CONTEXT.md`、`PROJECT_INDEX.md`；涉及 Frozen 核心合同才读 `PROJECT_CORE_CONTRACTS.md`。
- 按索引定向读取目标子系统；导航足够时禁止无证据全仓扫描、批量读取无关目录或重复已通过测试。`docs/CODEX_CONTEXT_SNAPSHOT.md` 仅作基线、工作树状态和既有验收的补充；将被修改、合并、构建或删除的对象仍须用当前 Git、文件和专项测试核实。重要集成里程碑后由 `codex/integration` 更新快照。
- Godot 测试优先走 `tools/run_godot_tests.ps1`；禁止 GUI Godot，禁止直接启动未指定项目内日志/用户数据目录的 Godot。正式入口固定 console/headless、`outputs/test_logs` 和本工作树 `.godot/runtime_appdata`，避免 `%APPDATA%` 写入失败及 `c0000005` 崩溃。

## DeepSeek 委派与降级

- 非琐碎且边界清晰的工作默认交 DeepSeek：常规实现、测试和构建用 `deepseek_worker`（V4 Flash），复杂架构、深层诊断和高风险审查用 `deepseek_pro_worker`（原生工具线程承载、直连 V4 Pro 推理）；主控负责范围、冻结对象、dirty、验收标准和最终落地。不支持的图片、MCP、computer-use、background 输入留给主控或对应工具。
- 子智能体数量按可安全拆分的独立工作包动态决定，不设任务级固定数量；Flash 与 Pro 可并行。
- 调度合同为 `gpt-5.6-sol multi_agent_version=v1` → `deepseek-v4-flash multi_agent_version=v2`，困难任务由 Pro-backed worker 直连 `deepseek-v4-pro`。Codex 更新模型缓存后运行 `C:\Users\Administrator\.codex\agents\sync-deepseek-subagent-catalog.ps1`；修改合同、catalog 或 worker 配置后必须完全重启 Codex Desktop 并新建 worker，禁止复用旧子线程或把主控恢复为 v2。
- `DEEPSEEK_NATIVE_TASK_MISSING` 或 `DEEPSEEK_DISPATCH_NOT_READY` 只表示原生调度不可用；立即用 `C:\Users\Administrator\.codex\agents\invoke-deepseek-direct.ps1` 直连原定 Flash 或 Pro，不得空转重试或误判为 API、网络、余额故障。
- 直连固定 `HttpClientHandler.UseProxy=false`，API Key 仅来自进程级或用户级 `DEEPSEEK_API_KEY`，不得进入仓库、提示词、聊天、命令行、补丁或日志。长请求每 ≤60 秒更新状态，并记录 model、`finish_reason`、token、`max_output_tokens`、`thinking_mode` 和 `transport=direct_no_proxy`。
- 原生 worker 可在明确独占范围内读写并测试；直连只返回文本，由主控用 `apply_patch` 落地。两条路径的输出都不是最终验收，主控必须审查 diff、保护 dirty 和冻结对象，并在真实集成态验证。

## 用户验收冻结

- 用户明确说“已修改好/已完成/已通过/不要再动”的项目、素材、映射、坐标、缩放、存档或数据立即只读冻结。除非用户后续点名精确对象并授权，任何任务、专业树、生成器、校准工具、旧合同、缓存或批处理均不得改写、重建、重映射或回退。
- 每次只改本次点名对象。动工前记录相关冻结文件、数据和哈希，结束后逐项证明未变；不得因共享脚本/图集、批量生成或测试便利连带修改已验收对象。
- 最新人工保存数据高于旧合同、旧生成结果、编辑器缓存和历史基线；加载链可能回退时应修复加载链并保留人工数据，不得旧数据覆盖后要求重做。生成器/校准工具须支持精确单目标更新；不能证明冻结对象像素和数据零差异时，禁止运行相关批量重建。

## 分支职责与所有权

- `codex/integration`：负责基线、跨系统接口、合并、冲突和完整验收；独占 `project.godot`、`AGENTS.md`、`scripts/game_root.gd`、`scripts/game_data.gd`、`scripts/region_content.gd`、存档格式、全局服务注册、跨系统测试入口；地图刷新怪物、怪物掉落装备、任务引用地图/怪物/装备等映射只在此最终接入。
- `codex/ui-art`：负责 `assets/ui/**`、`scripts/hud.gd`、`scripts/*_panel.gd`、`scripts/equipment_character_preview.gd`、UI 素材/测试和集中复用的公共 UI 视觉规范；只读玩法数据，不得改装备属性、怪物数值、地图、掉落或存档格式。
- `codex/maps`：负责 `assets/art/maps/**`、`assets/maps/**`、`map_editor_workspace/**`、`scripts/map_*.gd`、`scripts/map_assets/**`、`scripts/map_editor/**`、地图资源、环境目录/验证器、工具和测试；地图仅定义位置、碰撞、门点、区域和 `spawn_group_id`，不得改怪物属性或装备掉落。
- `codex/monsters`：负责 `assets/art/monsters/**`、怪物/Boss 数据、`scripts/enemy.gd`、`scripts/monster_visual.gd`、动画策略、Boss 机制和测试；以稳定 `monster_id` 输出外观、动画、AI、战斗行为，不得改地图几何、装备定义或 UI。
- `codex/equipment`：负责 `assets/art/items/**`、物品/装备数据、`scripts/equipment_rules.gd`、装备美术构建和测试；以稳定 `item_id` 输出图像、属性、穿戴和耐久规则，不得改背包布局、地图或怪物刷新。
- `codex/professions-skills`：负责职业成长、玩家技能、投射物、召唤物、职业公式、技能状态机/特效及其数据、构建和测试，主要含 `scripts/profession_rules.gd`、`scripts/skill_projectile.gd`、`scripts/summon_actor.gd`、`scripts/warrior_combat_math.gd`、`assets/data/vanilla_176/skills.json`、`assets/data/vanilla_176/profession_growth.json`。技能特效可写 `assets/art/characters/**/effects/**`；`paper_doll`/`wear`/装备图像归 equipment，`scripts/skill_panel.gd`/`scripts/profession_panel.gd` 视觉布局归 UI。`scripts/layers/runtime/combat_runtime_service.gd` 为怪物/职业共享运行时，由 integration 最终接入。本分支不得改怪物 AI、地图刷新、装备定义、UI 布局或全局存档格式。

## 品牌与兼容

- 正式品牌和 Android 可见名为 `HardCore`；包 ID `com.personal.mafaoffline` 用于旧安装/存档兼容，不得仅因改名而变更。
- 玩家可见标题、按钮、世界总称、通用提示和新内容不得使用“玛法”“传奇”“MafaOffline”等旧品牌。原始来源说明、历史验收、`legend176_data.json`、`mafa_world` 等内部稳定路径/ID 可保留，但不得直接成为玩家文案或为改名破坏兼容。新增 UI 文案、数据展示名、导出配置均以 `HardCore` 为基线。

## 数据源优先级硬规则

- `assets/data/source_priority_policy.json` 是唯一来源优先级总表；所有工作树、子代理、构建器和审计按 lane 路由，不得自行提升分级库、候选库、社区库、外部包或镜像。
- 装备属性、穿戴需求、职业/性别限制、手持/穿戴负重走 `equipment_attributes` lane，唯一主源为 `assets/data/equipment_attribute_master.json`。Crystal `server_data` 对这些字段已排除且不得反向覆盖，其他服务端范围仍按总表。该主表是用户正式修订而非 fallback；后续修订须同步正式合同、运行时兼容字段、来源证据和专项测试。
- **Primary-first**：每个字段、记录、贴图、动作、坐标、规则或映射先查 lane 的 `primary`；只要存在且可解析/兼容就必须采用，即使低级源看似更完整、更符合印象或用户描述。仅当精确目标被证明 `missing`，方可按 `auxiliary_1`→`auxiliary_2`→`auxiliary_3` 逐级检索。主源难解析、暂不可用、表现不兼容或结果不符时应修复解析/映射/兼容层，不得以 `unusable`/`incompatible` 绕过。进入每级前记录所有更高来源的对象、路径、版本/哈希、查询结果和逐项缺失证据；无证据禁止使用低级源。
- 同级遵守总表 `order`，不得默认跨发行版拼接；确需多源组合时由 integration 明确裁决，并逐字段/逐帧记录来源、原因和兼容证据。用户指定低级源仅允许本次候选核查；除非明确命令“覆盖主源/直接采用指定低级来源”，仍须先查主源并记录拒绝证据。
- `mirror` 仅供哈希复核，`quarantine` 永不进入运行时；分级库不得反向覆盖主库已有职业、属性、需求、耐久、ID、Shape、Looks、动作、坐标等字段。
- 生成器和正式数据合同须保存可机检的来源等级、`distribution`、原始路径、哈希和 fallback 证据；仅写“参考资料/社区数据/1.76 数据”等模糊来源或最终值不合格。integration 合并前审查来源优先级；主源有值却用低级源或缺失证据不全时必须退回，不得因测试通过、画面正确或用户暂未发现而放行。

## 跨工作树协作

- 专业树开工前由 integration 指定并记录集成基线提交或固定裁决版本；专业树须同步并预检分支、`HEAD`、merge-base、任务文件差异、依赖合同和 tracked/untracked/用户 dirty。若 dirty/缓存阻碍同步，保护现场并由 integration 下发上游提交、接口差异和专项验证基线；不得省略同步证据盲目施工。
- 专业树交付前须证明专项测试运行于指定基线或等价依赖；合并后由 integration 在当前真实代码/合同复跑必要专项。旧树通过而当前基线失败即交付未完成，须立即按当前基线返工，不得用旧证据覆盖或拖到总验收。
- 用户已持续授权明确任务所需的仓库内读取、修改、新建、测试、提交、合并、构建、导出、部署、设备调试及精确可核验删除。项目内部实现、测试、必要删除和取舍由主控直接裁决，不向用户请示或等待许可。删除前只读解析精确目标，确认其位于本项目或用户明确指定的位置，并优先可恢复；禁止宽泛递归、扩大任务或删除无关数据。
- 仅工具无法代办的外部实体动作可简短通知用户；这不是授权询问，也不得转交内部决策。宿主/OS 强制权限提示属于外部边界。专业树、子代理和自动化不得向用户发问、求批准/取舍或转交风险；冲突、失败、不确定性只向 integration 报告证据和方案，由主控裁决。
- integration 负责拆分、分配、接口裁决、审查、逐项合并和最终验收。除 integration 独占文件、跨系统接口/编排、存档、全局服务、最小接线和最终跨域回归外，不得代替专业树实现；UI、地图、怪物、装备、职业技能任务优先交对应永久工作树执行、测试并提交。
- 跨领域任务按责任树拆分；写代理不得同时修改重叠文件、所有权、工作树或生成输出。一次只审查/合并一个专业提交；专业测试未通过不得集成，每次合并后先冒烟再继续。需改其他分支所有权文件时不得直接修改，只在交付记录所需接口、字段/ID、原因和验收方式。
- `dev_art_sources`、本地 Godot 工具、DepotDownloader 不入 Git，通过本地联接共享且只读；`.godot` 和 `outputs` 每树独立，不得共享缓存/输出。专业分支只提交本领域文件，提交前记录专项测试；始终保护既有 tracked/untracked/用户 dirty，并保持数据可追溯、玩法可扩展、资源可替换、系统可测试。

## 交付格式

每个工作树交付须列出：修改文件；测试命令与结果；新增/变更稳定 ID；integration 所需跨系统接入；当前提交哈希。
