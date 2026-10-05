# 第三工作树云端接续交接

本交接由本地主控于2026-10-05编写。用户明确要求：本地停止施工，把第三树推送，交云端完成架构优化升级，并打包、校验APK交用户亲自检测。源码阶段、单项审查、push均不是整体完成。当前快照含已完成增量、真实FAIL及未采纳候选，不能当作已验收发行版。

## 1. 唯一施工基线与保护

仓库 watermarkpp/HardCore，接续分支 `codex/cloud-handoff-20261005`。云端目标对话“设置 HardCore”，thread `01a10c2d-d19e-7233-9d1c-b4db9481d034`，host `durable`。云环境原设置选择main，必须先fetch本交接分支，再用独立分支接续；不能在main上继续旧基线。

第三树本地路径 `C:/Users/Administrator/.codex/worktrees/pluggable-framework-v2/HardCore`，现场分支 `codex/pluggable-framework-v2`，真实HEAD `5d9ceb0121980ca9636d9d1cc2e19982949fbf63`加dirty。发布采用独立index固定当前文件，接在最近已推送审查提交 `e72d826071483885d57c261b900a1dbbbf422d14` 后；真实第三树HEAD/index不切换、不重置。受测内容指纹 `73452a86842d6d351a99efc308134f0b292ca9eade0a7113eb363560f7f878e4`，3966文件原字节清单见TESTED_SOURCE_MANIFEST.json。该指纹不是Git SHA，也不代表每个文件已全量语义审查。

用户2026-10-05最新裁决：**第一、第二树均没有领先内容，第一树旧测试已完全没有用。两树内容不需要补入第三树，第一树测试不用于本次验收，也不补跑它的新增旧专项。** 两树现场只保留，不自动合并、覆盖、清理。第一树 `C:/Users/Administrator/Documents/HardCore`、codex/integration、27bf669fdd5293f8657e28e1ecd7976c39e8d983；第二树 `C:/Users/Administrator/Documents/HardCore-worktrees/glm53-r1-20260929`、codex/glm53-r1-20260929、5d9ceb...。WORKTREE_RELATION.json是早于用户裁决的机械差异表，其中第一树测试参考建议已经作废。

第三树真正index路径 `C:/Users/Administrator/Documents/HardCore/.git/worktrees/HardCore/index`，保护SHA256 `e5fb003e97477afa32c5fa946fa11fb9d290d7e0e7f718738d50596d674868e4`。历史测试曾用outputs/framework_v2/publication_closure_20261003/runner.index，不能拿它覆盖真实index。主树bootstrap PASS；第三树仅旧分支白名单FAIL，等价保护预检已完成，不修改门禁规避。

## 2. 原始设计与最终目标

先读 `docs/architecture/pluggable_framework/RFC_V2_USER_SOURCE_20260930.md`，再读本报告、Pro完整历史/新答复与当前源码。原RFC是总体设计，日期后的局部审查只证明其限定增量。`docs/features/NEW_MODULE_DELIVERY_TEMPLATE.md`是后续新增模块交付入口。历史 `outputs/framework_v2/architecture_completion_audit_20261003/COMPLETION_AUDIT.md` 已收入证据ZIP，但10月3日后发布、资源及异构链已继续施工，旧缺口必须映射当前源码，不能照旧重做。

核心选择是模块化单体、数据驱动机制组合、有界执行核心。保留唯一HP权威、canonical planner、PlayerState/ordered writer；装配期编译配置、依赖、来源、成本、资源与迁移合同，战斗期消费已接受快照。新增数值/内容主要改数据，新行为原语才添加受约束handler。词缀、装备、宝石、符文、技能、天赋等来源共用贡献和触发体系。真实HP提交事实驱动扩展，表现/音频准备不能决定已接受伤害是否兑现。共享预算必须兑现全部接受工作，不能靠少怪、减AOE、降频、取消旧ticket或无限排队取得通过。

最终工作是完成当前获授权架构范围与相关缺陷，逐条对照RFC验收；完成必要解析、专项、回归、集成和固定SHA Pro审查；制作可覆盖旧包的APK，核验包名/实际版本/签名/内容/大小/SHA256，交用户本人检测。Android/GPU/热机与用户设备结果分别记录，用户亲测不要求云端冒称设备PASS。缺原B输入等外部证据要如实保留，并判断其是否阻塞具体交付，不能将所有未来长期研究无限扩成打包前置条件，也不能掩盖已知生产FAIL打包。

## 3. 最新有效产品决定

- 同种DOT默认完整抹旧，以新伤害、新周期、完整期限、新来源与归属替换；不同DOT种类共存。显式叠加天赋才允许独立层。历史报告的“更强伤害/延长期限/保留旧周期与credit”是旧裁决，不能作为当前最终要求；当前代码与该新要求仍需审查和闭合。
- 许可与容量接受前冻结，扣MP/提交HP后不能丢层或取消已接受动作。原period/玩法节拍不为性能任意更改。
- 用户最新出生边界：**新配置经地图重新发布或切换后生效；当前战斗只使用完整刷怪计划与登记召唤。** 保留正常刷新、登记召唤和原已接受工作。
- 新扩展过快周期要接受前拒绝；具体最低阈值仍须测量/产品裁决。不要把旧1μs压力输入承诺成服务保证，也不要擅自更改正式技能。
- 普通主城300秒、地下城480秒，精英/Boss/特殊保留各自规则。死亡当刻撤碰撞；重复角色名拒绝；远近分层移动及完整围攻空位保持。

## 4. 可保留的阶段成果

以下均绑定各自源码阶段，不拼成当前全量PASS。原生日志、source before/after、runner、receipt、producer/cold与失败均保留。

| 范围 | 最新可报告结果 | 入口与限制 |
|---|---|---|
| 祖玛地毯、墙体、整角色层级 | 19原生PASS/6833 framework检查 | outputs/framework_v2/zuma_material_layer_20261005/FINAL_ASSOCIATION.json；不是Android/GPU结果 |
| 精确保留作者文本Save API | 3场/56检查PASS | formal_respawn_20261005/preserved_source_integration/VERIFIED_SAVE_ASSOCIATION.json |
| 15图正式保存/生成/发布 | 149普通地下城组480秒，54特殊组300秒，527非目标不变 | preserved_source_integration/generation_apply_352221145d4e4423a2f72caa5f82d3af/FINAL_VERIFICATION.json；原wrapper路径分隔符FAIL保留 |
| 刷新最终回归 | 11原生/6880 framework检查PASS；Bridge/Policy扫67图 | preserved_source_integration/FINAL_NATIVE_ASSOCIATION.json；docs/review/formal_respawn_20261005/README.md |
| 启动共享准备API、正式生成链、实际消费者 | Startup/Hall/Root接入；18节点/57边；8原生277检查PASS | controller_takeover_20261005/PREVIOUS_EIGHT_ASSOCIATION.json，source70ef3505...；不重做“尚未接入”的旧建议 |
| 交接取消全部/generation/错误scene/引擎调用前拒绝 | 最终4原生184检查PASS | controller_takeover_20261005/BOUNDARY_FINAL_ASSOCIATION.json，source73452a...；36/48/50/50检查，无fixture代收 |

上一轮接手仅采纳了启动交接测试候选，生产文件没有新增修改。修了三项fixture缺陷：profile目录加run隔离；恢复启动需等原Hall协程完成suppress边界；cleanup用Variant检查freed节点。早期1PASS1FAIL、2PASS2FAIL归档原样保留，不把中途PASS或有引擎ERROR的场景结案。8场启动和4场交接保留ObjectDB告警（不同阶段数量分别记账），不是完整内存无泄漏证明。

历史底座、UI/移动/死亡、稳定ID、经济与存档、合法异构一/二代child、周期producer/票据、资源/音频/Cue、发布/启停的后续成果在 `docs/source176_r3/FRAMEWORK_PROGRESS.md`、`USER_SCOPE_LEDGER.md`及 `docs/review/*/README.md` 与原Pro全文中。逐条采用具体最新回执，旧阶段“未开放periodic child”等已经过时，不再施工一次。新DOT产品语义要单列，不能借旧period refresh PASS代替。

## 5. 必须续作的实际缺口

### A. 最新自然持续resource复测FAIL

同源码73452a...，完整归档 `outputs/r3_takeover/20260930/validation/periodic_dispatch_takeover_sustained_resource_20261005_211528_657074`。live run `c730d6f9-9129-471d-953c-007dc1418578`，invocation `872ed0af-abfa-4e4c-9076-18a02db590db`。live native退出1、316检查6失败，无timeout；第一轮30/30在33,091,698μs排空，第二轮35秒只有24/30。cold没有成功producer，正确FAIL。汇总 `controller_takeover_20261005/SUSTAINED_CURRENT_ASSOCIATION.json`；trace SHA256 `5c43e2667e4d97014a2c0c2f217aaecb38aed579a239978832f0df1e4818dc1a`。

已投递tick最大迟到800000μs，尾部busy有真实attack Timer，若干剩余目标是新3状态ticks0且next_due尚在未来。失败首先证明完成量/排空未达期限，尚未证明调度器丢到期任务。截取六个尾部目标的接受时刻→Timer实际释放→当时几何命中→HP提交事实→状态due/expiry与服务时刻，区分未释放、未命中、合法未到期、到期未服务、受伤/资源/移动策略。自然chain历史FAIL也保留，不能用更旧PASS替换或重复运行挑绿。

不放宽35秒、减少30目标或HP、不清冷却/直接pump/advance、不改原生产时序取得通过。实际过严测试设计需证明后再讨论，不能默认所有截止FAIL是生产bug。本场live外层90秒是用户授权的两轮例外，cold仍30秒，业务每轮35秒未变。

### B. DOT刷新/显式叠加与完整出生计划闭包

生产完整准入守卫尚MISSING。原 `birth_contract_closure_candidate` 是分析与反例，不是实现通过；本轮 `outputs/framework_v2/dot_birth_takeover_20261005` 候选也未被主控采纳。候选完整diff/apply验证、原生真实路径覆盖未完成，只保存WIP。不得直接套PRODUCTION_CANDIDATE.patch或把token搜索称容量证明。

真正入口涉及 `scripts/game_root.gd`、coordinator READY descriptor准入、`scripts/features/runtime/world_target_bound.gd`、真实SummonQueue。当前unknown新base slot、READY descriptor计划/计数前入口、直接child factory绕过accepted召唤额度需闭合。建议单一权威：完整计划base slots+同slot正常respawn+真实SummonQueue.job中原签发一次权限；在第一feature接受前冻结完整含尚未出生描述符的闭包。不得另建无限grant字典/第二注册表，不能只在出生后track_child补救。精确slot/entity、配置payload与合法传递时序须先于queue/counters/actor/MP/HP副作用核验。

证明要覆盖旧life尾部与新life交接、来源替换后root/credit/lease退休、独立叠加各层资格、child与嵌套summon生命周期总上界。有限同屏N不自动证明所有尚未终态状态/已接受工作有N×S上界。保留正常计划中新slot首次出生、计划内同slot刷新、已登记召唤、freeze前已接受descriptor、旧票据和合法子动作；计划外新配置在发布/切图前拒绝，不伪造world epoch使旧承诺失效。

### C. 启动准备剩余边界

真实SceneTree立即error返回分支MISSING；现有pre-engine null/empty拒绝不能替代。publisher物理实例替换NOT_RUN；scope/source/generation已有部分重入测试，但不能冒称物理实例替换。Android导出代表资源/目录sealNOT_RUN。ObjectDB退出警告原因及长期资源寿命仍需按当前消费者核查；不要重开e72已经关闭的Hall deferred/HUD FAILED缺陷。

### D. 完整RFC收口与其他独立项

按RFC §20/§21逐项生成当前源码/证据矩阵，标PASS/FAIL/BLOCKED/NOT_RUN/MISSING；核对正式包发现/可信注册/安全启停/非空资源与生成闭包、跨来源/异构组合、唯一权威差分、持久化/故障恢复以及完整P6/R3。历史已有实现要采用，未测组合才补证。最坏原子工作、同负载CPU/帧间隔/服务年龄/队列/内存分别测，不用可见状态数量替代长期累计工作保证。

原v97 A→B后背包装备/销毁故障，B原始输入MISSING；生产双角色新档/cold正例只能证明其范围，不能声称原故障已修。缺B不阻止独立架构源码工作。物理掉电、外部有效旧primary整替换、完整内部故障矩阵保持具体范围，不把两受控强杀当全矩阵。旧GLM29等不完整结果不采纳。

## 6. 云端操作、测试和打包

先保护云端dirty，fetch分支确认精确SHA，再建立独立接续分支。设置 `core.autocrlf=false` 避免无意转换；执行本目录verify_handoff.py逐文件原字节核验。发现差异先查attributes/换行/缺失，不忽略hash门禁。证据ZIP通过manifest核对后解压到仓库；包含真实FAIL与WIP，不执行candidate patch。历史更早原件留在父e72及其review链，可按对应固定SHA取，不需要从第一/第二树找资料。

Windows受测引擎 `4.7.stable.official.5b4e0cb0f`，exe SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。本地exe、export templates、Android工具、keystore、真实存档、dev_art_sources联接不进Git。运行数据/正式素材按Git传递；若重新生成外部素材需证明精确来源，不在云端猜补。云端Linux引擎/工具链需明确其新指纹，不能自称原Windows实跑。

正式runner `tools/run_godot_tests.ps1` 当前绑定Windows console、PowerShell mutex、APPDATA与tracked场景门禁；`tools/source176_r3_validation.py`也使用powershell/py和旧Windows路径。本地run_owned.py硬编码第三树与真实index保护，不原样在Linux运行。云端可以完成源码、数据生成、静态/直接测试及提供符合相同receipt/producer/cold门禁的可移植执行入口；先查正式接口，不用直接godot绕过合同。必要工具适配在独立文件完成并验证，不把env缺失写成业务PASS。普通30秒、已知重场景60秒，明确授权live/cold组合90/30例外不扩散。

最后固定源码SHA再做相关源码验证、差异复核、原Pro集中审查与APK。当前export_presets.cfg仍versionCode82，历史已交v97；须核验旧包真实versionCode，选择合法升级版本，不盲目82导出。包ID保留 `com.personal.mafaoffline`，品牌HardCore，保持旧签名/存档兼容。签名材料不复制/提交；云端如无合法keystore/工具链，完成可review构建方案和源码后明确具体缺件，由已配置本机执行打包，不改包号/签名绕过覆盖。产物交付必须列实际版本、绝对路径/可下载入口、大小、SHA256、签名与包内容验证；`DEVICE TEST: NOT_RUN`交给用户亲测。

## 7. Pro 原规划者协作与停止状态

用户授权向Pro咨询。原对话“游戏稳定性设计”地址 `https://chatgpt.com/g/g-p-6a489c5ed68481919473c4a1128c4a54-you-xi-zhi-zuo-xiang-mu/c/6abbcea3-5fb4-83ea-8732-0cf95e1c4583`；共享历史 `https://chatgpt.com/share/6abcd9f8-0bd0-83ea-8061-3e5dee97c341`。共享副本不是可写原对话。原对话Pro模型已通过UI确认。本地主控已从最早设计通读全部可访问的103条正文、339775字符，包含后续纠偏与本轮实际12547字符新回复，并完整读取本地RFC及附录。阅读范围见[PRO_FULL_READ_RECEIPT.json](PRO_FULL_READ_RECEIPT.json)，设计核对见[CORE_DIRECTION_AND_PRO_RECONCILIATION.md](CORE_DIRECTION_AND_PRO_RECONCILIATION.md)，本轮回复摘要见[PRO_PROGRESS_REPLY.md](PRO_PROGRESS_REPLY.md)。这不代表所有历史二进制附件被独立审计，也不把Pro规划意见称当前SHA验收。

完整源码/证据快照已推送commit `4685d5ec76227509d53d4ff542f9d60cb4b8b626`，tree `7276ab23a44e57b423c5ddff5125cd910180ee8f`；云端已经实际fetch、建立独立接续分支并校验清单。详见[TRANSFER_RECEIPT.md](TRANSFER_RECEIPT.md)。本次后续文档提交只补交接资料，源码受测指纹不变。云端已有dirty施工时先保护现场，再fetch并读取/接入文档增量，不能reset覆盖自己的新实现。

云端应先理解完整核心设计，遇到容量、有限链/旧life、准入、自然期限等问题随时到原Pro对话研究清楚；提供固定SHA、最小调用链、真实FAIL和明确问题，不让规划者代猜未推送源码，不把只读意见当主控验收。GLM/dots/小可爱旧CLI/MCP/Harness/队列与定时轮询弃用。

本地dot_intake、sustained_result已按用户要求中断，生产源码冻结。此次仅保存证据、写报告、固定快照与push；无新的架构实现、Godot、APK或设备操作。本地施工交给云端后不自行恢复。

## 8. 发布检查口径

原字节发布对比父e72：968源文件完全相同，2874仅换行不同，50有实际内容差异，74新增。为保留受测hash，使用raw blob，不把CRLF变化宣称架构修改。PUBLICATION_REVIEW.json列明路径。git diff --check 实际FAIL：既有WIP五文件17处空白/EOF问题保留；本地已停工，不为格式改写受测源。凭据模式检查PASS，原字节源与证据ZIP核验PASS。发布不是源码整体验收，云端下一增量若整理格式必须绑定新的source指纹。
