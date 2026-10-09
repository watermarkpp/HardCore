用户已授权你继续本对话做全项目精细审计，分批给文件包，修复和必要验证都完成后才打包109。当前本轮功能修复已闭合并正常push。

本批固定SHA: dbd78d3301c2af6cfd9e070abe8cc847e6353175
仓库watermarkpp/HardCore，分支codex/v108-runtime-bug-review-20261009，父61d5b03f0568fee0f9c88fa2c20fbe93861c5095。仅使用用户已经选定的极高，禁止Pro；入口实际model未返回，不要声称提示词能切换设置。

本批编号B01，覆盖启动/中央预算/资源生命周期，实际源码读取和每文件范围必须留证，不凭报告总体PASS。

本轮followup已验证：真实退出reentry pending不锁死、outer成功/重复幂等、真实FAILED保留；投影恢复无新movement30/30、代际撤销、新事件30/30；合法existing focus不抢、stale不阻塞、owner字段严格int校验/已释放owner拒绝；正式dense30/firewall、cold damage、zerooptional攻击等相关专项通过。仍有ObjectDB/resources退出告警，必须实际查。最新相关pressure数据十movement回调10空间查询合计13847us，最大2113us；仅功能压力observer，非107/Android FPS。

主控Pages接收接口目前连接失败，没有已确认创建的Page。为避免read_thread仅返回chatgpt-content-reference导致不能读正文：请如工具支持，将审查报告保存为私人Page，题为HardCore 109 全项目审查 第一批，并在回复给真实PageID/链接；同时提供ZIP/文本文件包。若不可用，不要伪造Page或ZIP；主回复写完整发现、逐文件覆盖和BLOCKED原因。

标准提示词如下:

# HardCore 全项目精细审查标准提示词

## 执行身份与固定基线

继续使用“项目助手工作线程”，只使用用户选定的 **极高**，不要使用 Pro。模型和强度必须由真实入口设置；提示词本身不能切换模型。如果入口实际不符合要求，说明限制，不假称已切换。

这是只读独立代码审查。仓库为 `watermarkpp/HardCore`，审查分支为 `codex/v108-runtime-bug-review-20261009`。主控每批会提供固定的完整提交 SHA；先读取该 SHA 的源码，记录实际访问到的提交。不要用主工作区旧 HEAD、旧 APK、旧咨询分支或施工报告替代实际源码。

请先读取 `AGENTS.md`、`PROJECT_CORE_CONTRACTS.md`、`docs/review/full_project_audit_v109_20261009/SCOPE.md` 和 `AUDIT_SCOPE_MANIFEST.json`。用户最新规则覆盖旧规则中的 Pro 要求：外部咨询仅极高。历史状态文档只用于定位，真实固定源码和本轮明确合同优先。

没有仓库读取权限、看不到指定提交、无法读某些文件或没有执行工具时，明确记为 `BLOCKED` / `MISSING` / `NOT_RUN`。不能凭主控报告给代码总体 PASS；不能把建议或假设冒充已证明 BUG。

## 审查目标与方法

对项目逐块精细审查，找出真实逻辑 BUG、跨模块接线遗漏、状态与时序错误，以及有实际证据的冗余。追踪正式入口、状态所有者、调用链、信号、消费者、异步完成、失败/取消和退出边界。不能只搜 TODO、只看改动文件或只罗列编码风格。

每块以模块入口展开，记录读过的文件和仍未覆盖的范围。每个可疑点至少核实：

1. 谁拥有状态和唯一写入权，哪些输入/事件改变状态；
2. 正常、拒绝、重复、取消、死亡/退场、地图/代际变化和异步完成路径；
3. 攻击、施法、移动、受击、冷却、持续效果之间的时序；
4. 保存成功/失败、排队重试和再次操作是否正确，奖励是否只提交一次；
5. CPU 热路径、每帧工作、300ms 重规划、必要事件、可延期工作之间是否有重复或积压；
6. 源数据、稳定 ID、生成器、运行数据、消费者、旧存档兼容是否闭合。

调用链必须考虑 Godot 的 `.tscn`、`class_name`、autoload、preload/load、信号、Callable、反射式 `call/has_method`、资源绑定和编辑器入口。仅“搜不到直接函数调用”不足以断言代码无用。

## 不得改变或误判的已确认合同

- 正式品牌 HardCore；Android 包名 `com.personal.mafaoffline`，原签名和存档兼容保持。
- 人物自由八向移动，未采用人物/怪物强制格子方案。实际碰撞和已提交战斗继续按正式链运行。
- 普通/精英/Boss 的被动激活范围为 6/9/12；人物及可见召唤物可激活，隐身不触发光环，群隐可覆盖召唤物。只有静态墙体/地形遮挡引怪信号，怪物不能遮挡其他怪物。
- 范围内所有合格冷怪立即获取目标。光环外实际正伤害可独立唤醒。重追击/绕路、非紧急维护使用 300ms 时钟及帧预算；不能将必要激活重新推回 8 候选分页或 300ms 等待。
- 近战和锁定法术合法发动后，玩家移动不撤销本次伤害；一次性 AOE 按发动时位置结算，火墙每跳单独判定当时区域。只有有飞行时间的投射物可通过移动躲避。
- 视觉允许按最新已确认合同覆盖，已经提交的伤害不能随视觉取消。受击插播与攻击/施法提交、移动衔接、实际冷却暂停必须相符；人物既有受击保护及跑步状态保持。
- 掉落仍用既有正式表、概率、白怪6/精英9/Boss12槽及保护。不启用已搁置的新加权表设计；延后掉落与原帧预算是授权行为，teardown不能偷跑地面物品生成。
- 复活戒指触发间隔300s，戒指复活不扣经验，正常死亡规则保持。麻痹普通5s、精英/Boss2.5s。穿戴授予技能、隐身戒指、技巧项链、神秘随机属性和特殊属性面板遵从既有实现与本轮用户合同；不要恢复已退役“点击特装”。
- 不增加第二套 HP、技能 planner、移动权威或存档写入权威。不要以随机延迟、清状态、增加预算、降负载、截断 AOE、自动 fallback 或弱化断言掩盖缺陷。
- 生成资料只由正式 authoring 生成链修改；共享人工资料、素材、真实存档与未知 dirty 不动。

这些只是重点约束，不能用这份列表代替实际源码和规则查阅。数值/合同有冲突时给出精确位置，交主控核实，不自行选择玩法。

## 分块与交付

主控按清单逐批派发，建议按以下顺序，但覆盖清单中的所有生产文件才算完成：

1. 启动、中央时钟/预算、资源准备、地图 READY 与取消生命周期。
2. 人物战斗、技能 planner/router、HP/MP/防御、受击、持续效果、投射物、死亡。
3. 怪物入战/脱战、AI/移动/碰撞、攻击与技能、所有特殊行为/Boss、召唤物/隐身。
4. 掉落、异步死亡奖励、拾取、背包、物品事务、装备/特装、价格/概率与经济。
5. HUD/多点触控/面板、Loading、音效/背景音乐、前后台与服务生命周期。
6. 角色/存档/持久化、世界时钟/重生、地图编辑器/发布链、稳定 ID 与生成器。
7. 项目/场景/资源/导出/构建配置、冗余代码与测试/证据覆盖。
8. 跨模块复核，补齐覆盖空白，汇总阻塞项与本地/设备验证边界。

每批请交付可下载文件包（有文件工具时可 ZIP），包含：

- `SUMMARY.md`：本批实际基线、范围、关键结论、阻塞项和未覆盖项。
- `FINDINGS.json` 和 `FINDINGS.csv`：每项有唯一编号、严重度、类别、当前文件/函数/行、正式触发条件、现有行为/正确行为、最短调用链、证据、修复建议、最小必要验证、置信度与状态。
- `COVERAGE.json`：逐文件已审查/部分/未审查及原因，覆盖到哪些入口、调用链和边界。
- `REDUNDANCY.md`：候选冗余的调用/资源/动态引用证据、是否正式/兼容/编辑器/fixture/历史路径，删除风险。不要自行删除。
- `VALIDATION_GAPS.md`：缺少哪些源码/静态/原生/Android/真实手感证明；已有未变验证可复用，只有新变更、依赖变化、失败修复或缺失证据才要求复测。
- `SOURCE_BINDING.json`：固定 SHA、读取的具体路径与工具证据。未实际读取的路径不能记为覆盖。

主回复同时给出阻塞项和可核验摘要；不能把全部内容藏进无法读取的附件。如果不能生成文件包，逐份输出完整 Markdown/JSON 并明确没有生成 ZIP，不能伪造下载链接。

## 发现项分类与最终门禁

把“已由源码证明的 BUG”“源码推导但需运行确认的风险”“纯冗余候选”“需要用户决定的玩法”“验证缺口”分开。严重度依据真实影响；不要把未构建 APK、没测手机本身当作源码 BUG。

旧问题必须映射本批源码：已经修好的 `PERSISTING→SETTLING`、临时 pending 退出锁存、投影失效事件消费等不能机械重复为当前 BUG。发现新回归时给出当前控制流证据。

审查不直接授予发布 PASS。主控逐项确认/修复/记录，并以固定源码做必要验证后才可封装109。不要要求为了汇总而重做未变检测，不删历史失败证据，不混合不同源码阶段的成功为最终全项目验收。

## 每批调用模板

固定 SHA：由主控本次提供。

本批编号/模块：由主控本次提供；其余模块仍标未审查。

重点入口与文件：读取本批 `AUDIT_SCOPE_MANIFEST.json` 中实际分组；从入口继续追必要消费者，不限制于列出的文件。

历史发现/已闭合项：读取上批编号和主控处置表，避免重复。

请实际开始只读审查，输出本批文件包及摘要；如果读取权限或模型入口受阻，报告精确限制，不用旧报告代替。



本批具体范围:

# Batch 01 — 启动、预算与资源生命周期

状态：NOT_RUN。固定提交由主控正常推送后的派发收据给出；不能使用主工作区旧HEAD。

本批覆盖 `bootstrap_runtime`、`resource_streaming` 与 `diagnostics_budget_observability`，并追踪必要消费者。其它模块保持未审查。先读同目录标准提示词和范围清单，以实际指定提交为准。

## 本批正式入口

- `project.godot` / `export_presets.cfg` / `scenes/main.tscn`：autoload、process配置、场景绑定、导出过滤与当前版本。
- `scripts/game_root.gd`：`_ready`、`_process`、`_physics_process`、`_exit_tree`、bootstrap/map READY/转图/取消、暂停与安全退出、资源准备与激活事件泵送。这个大文件会在其它批次继续审查其它职责，不能因本批读了部分函数就算整个文件已覆盖。
- `scripts/world_bootstrap_coordinator.gd`、`scripts/game_data.gd`：阶段、配置就绪、失败/重入和唯一资料权威。
- `scripts/layers/runtime/execution/frame_budget.gd`、`time_domains.gd`、`world_context.gd`、`paused_receipt_pump.gd`：每帧epoch、必要/optional账目、FIFO服务、scope闭合、暂停后回执和取消。
- `scripts/features/runtime/feature_resource_preparation.gd`、`scripts/features/contracts/feature_resource_lease.gd`、`scripts/features/compilation/feature_resource_registry.gd`、`scripts/skills/skill_resource_service.gd`：预备、共享、去重、lease释放、失败和退出边界。
- `scripts/monster_visual_streaming_coordinator.gd`、`scripts/prepared_music_stream.gd`及实际调用到的资源服务：异步完成身份、退场后回调、refcount与Node/Callable持有。
- `scripts/runtime_diagnostics.gd`：观测开关、计时嵌套、正式性能与observer成本区分。不要因没有设备测试而报源码bug。

## 已知重点与未闭合项

1. 范围内全部合格冷怪必须即时激活，不能恢复8候选限流或300ms入战等待。当前十次同process真实movement信号在30怪上有10次空间查询；本地回调总计约14.1ms（direct06，observer开启，激活专项冻结后续actor physics）。这是有限调用压力，不是真实补步或107/Android FPS。请审查可缓存的候选范围与身份、revision失效、重复事件，以及必要工作峰值能否降低而不漏新进入的怪物。
2. 一次投影暂时失败保留当前地图/代际的去重事件，站住不动在正式process pump恢复后仍应激活；不能引入tight retry/world scan。
3. 退出的临时pending与真正FAILED已经分开。安全退出不能重复奖励或绕过真实保存失败。
4. `safe_logout_pending_retry_repair_20261009` 44个功能断言/退出0，但stderr有13 ObjectDB泄漏和3 resources still in use；旧death_queue_lifecycle同样有8/3。请找实际资源/Callable/对象循环的所有者与释放边界；不能因runner聚合错误数0便写“无引擎错误”。区分fixture持有与生产生命周期缺陷。
5. 主控刚修typed owner身份的`int(null)`边界；非法/缺失current_map_id或_zone_generation应拒绝，有效Player/Summon归属必须保留。不要把已修点重新当当前bug，若仍有释放实例访问给出当前精确控制流。

## 交付与覆盖

按标准提示词输出本批 `SUMMARY.md`、`FINDINGS.json/csv`、`COVERAGE.json`、`REDUNDANCY.md`、`VALIDATION_GAPS.md`、`SOURCE_BINDING.json`；可生成文件时提供ZIP，同时在主回复保留可读取的完整发现摘要。

逐文件写实际读取状态，大文件按已覆盖函数/职责记录；没有源码权限或读不到指定SHA就停止作判断并标BLOCKED。剩余37个本地未上传路径不能假称从远端审过，其中有已退役格子试验，不能重新加入运行时。

只读，不改源码、不构建APK、不改变玩法。主控核实发现后修复，必要验证后再派下一批。



请现在实际开始本批审查，不能只回复计划。剩余模块标NOT_RUN，完成本批后返回结果供主控接入，不自行改生产或发布。
