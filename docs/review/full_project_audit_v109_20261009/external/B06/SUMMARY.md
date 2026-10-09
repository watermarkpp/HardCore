# HardCore v109 全项目精细审查 · B06 地图/环境/存档/退出与平台边界

**固定审计生产源码：`d145826b7305ad918893ba0098db2595ae01f53a`。** 仓库 watermarkpp/HardCore，审阅分支 codex/v108-runtime-bug-review-20261009。这里只读审查Git中冻结对象，不使用并行主控本地B05施工、新HEAD代码、真实用户存档或凭据。Godot、APK、Android设备、进程杀死/故障注入测试均 **NOT_RUN**；未改生产/地图/测试/配置/签名/存档。

**审查结论：`B06_SOURCE_AUDIT_WITH_CONDITIONAL_FINDINGS_AND_REMAINING_GAPS`，不授予109发布PASS。**

## 清单及真实审查深度

先从固定Git源读取 `AGENTS.md`、`PROJECT_CORE_CONTRACTS.md`、`STANDARD_AUDIT_PROMPT.md`、`BATCH_06.md`、`SCOPE.md`、`AUDIT_SCOPE_MANIFEST.json`和`AUDIT_PROGRESS.md`。GitHub大的Manifest文本接口返回空串，改用同一固定commit的Git blob读取；不是借工作树。B06 manifest **1396**个路径，`maps_environment_streaming` 1393、`save_input_platform` 3；其中`map_editor_workspace/` 1311个、scripts 69个、assets 16个。全部与固定提交Git树做**精确路径/SHA/size成员绑定**；重要编辑/runtime/visual/map事件路径再读取实体字段与正式消费代码。**Git成员/文件字节存在不等于人工内容逐行审核**；`COVERAGE.json`为每项给出核心函数、字段、真实审查程度与未审理由。

B04错分的68个runtime-map资产和B05错分的74个visual-map资产另按本批真实地图职责复核，原先B04/B05历史报告不改。GameRoot/PlayerState/MapEditorApp只按本批任务审查具体函数，其余B08。旧B01/B03既有修复不机械重报。

## 已追通的正式地图发布链

- **人工源与优先级**：`MapEditorApp._open_document_path → MapEditorLoadService.load_document → MapEditorGroundService.initialize`读取`map_editor_workspace/<map>/<map>.editor.json`和Chunk/manifest/state。打开原文档和修改在内存，`_save_current_document→MapEditorSaveService.save_document`才提交人工源；生成候选文件不能代替用户存盘。
- **批准/候选/发布**：`MapEditorBuildRuntimeService.approve_for_runtime / build_candidate`验证唯一map身份、born/spawn语义、碰撞与ground，候选落在`outputs/map_runtime_candidates`不直接授权运行；`publish_runtime_release`核查candidate_binding/buildSHA→先晋升正式runtime→写registry→reload验证`implemented_playable`及批准hash。同步失败通常回滚；跨进程崩溃的中间窗口见B06-002。
- **运行端**：`MapEditorRuntimeBridge._compute_readiness/load_map/game_content_for_map/_combat_spawn`检验注册表、工件、buildSHA、map_key和正式monster身份；`WorldTargetBound.declare_base/seal/admit_base`在生成角色前证明完整出生/召唤闭包，GameRoot._spawn_enemy不允许未发布monster输入取得空间索引。静态地形碰撞由正式已发布poly索引/RuntimeCollisionGeometry决定，动态怪体不作为被动信号遮挡，未恢复WorldContent旧假怪出生。
- **READY/切图**：`GameRoot._begin_map_transition/_run_map_transition/_run_world_build_pipeline/_load_zone`用Loading覆盖后资源预备和候选actor出生，按`_zone_generation`取消旧怪、死亡任务、拾取、视觉；旧已接受攻击/伤害交原权威结算。现有已批准6/9/12即时halo及300ms可延期重规划合同保持，B03旧修复不重复改。
- **Portal**：`MapPortalRuntimeService.validate_network/travel_request`核对双向与单向到达专用端点，`MapPortalTravelGuard`3s/1.5GU与single-flight，`GameRoot.travel_via_portal/_complete_portal_travel`在目标map、portal及tile身份严格一致后安置玩家；合法玩家foot envelope仍需独立确认（B06-007）。

## 固定数据字段层面的实际核对（不是运行时PASS）

读了67个编辑图、67个正式runtime JSON、67个正式visual JSON、67套ground manifest/state及对应实际图源；比对：
- 正式map identity registry **67**、runtime release registry **67**、workspace editor **67**，地图key和runtime数值ID全对齐，0 missing/extra；
- **67/67**正式runtime `build_sha256`等于release entry的`approved_build_sha256`，当前源码schema v2，全体编辑revision没有高于发布source.revision；
- 正式runtime保留`monster_spawn` **2298**行、`boss_spawn` **340**行；对6种semantic layer的editor/runtime计数比对无不符（BOSS、普通、NPC、map_exit、安全区、复活点），不等于每条语义及出生碰撞精准PASS；
- **132** portal endpoints（117配置目标、15 arrival_only），配置目标的地图key、numeric runtime ID、target portal semantic ID、target_tile与对应target endpoint tile全部一致，未检查全量player footprint walkability；
- **67/67**editor设计尺寸等于ground manifest，`dirty_chunks`总数0，materialized **445**个Chunk的`baked_operation_count`等于state `operations_by_chunk`数量；445个workspace baked preview PNG和对应formal hash-store PNG拥有相同Git blob SHA，无缺引用；
- **来源元数据差异**：`*.visual.json`每份有3个`source_*_sha256`，共201个核对字段，其中74个不等于当前固定人工源原始字节SHA。**445正式PNG完全相同**，不能由74数推出地图画面或玩法损坏，也不能覆盖人工源自动重发。详见B06-006。

## 单一存档权威及崩溃合同

`PlayerState`保留独立profile和world文档范围，但由相同`JsonPersistenceService/JsonPersistenceJob`串行Worker机制完成，异步读写合法性由main-thread validator/receipt判定，临时文件字节回读、主备版本、未来schema拒绝、身份代际/sequence检查。世界时钟`WorldMonsterClockLedger.replay`依连续death_event补齐profile/clock水印，Gap被拒绝；旧档升级`SaveUpgradeBackup.prepare/verify/complete`先保存哈希before-image，成功才提交completion marker。**B01旧pending退出锁定已修**：`GameRoot._prepare_safe_logout`先drain死亡/拾取，再保存Home；只有terminal FAILED保持失败锁。
- 不能把`*.bak`存在或`_json_persistence.finish`局部成功，当作所有profile/clock/journal跨文件在强杀后全可恢复的证明；
- 正常安全退出的死亡及奖励队列会先drain；**强杀APP在经验/世界事件已持久但掉落未roll/materialize的窗口**尚无掉落重放字段，见B06-005（产品策略需明确，不是本轮Native故障事实）。

## Android、平台与输入合同

- `project.godot`应用HardCore，启动StartupLoading，正式八向自由移动、process frame time-budget配置300ms追击维护和1200us optional；`export_presets.cfg`包名 **`com.personal.mafaoffline`**，signed=true、ARM64和Godot 4.7 Gradle模板。固定源`version/code=82`，**本批不构建109**；这不是版本错的证明。`tools/build_android_isolated.ps1`通过只读固定Git内容构建disposable stage，`-VersionCodeOverride`只覆盖Stage，主源tracked保持原样；`android_two_pass_export_hook.ps1`固定源hash、实际证书对照和seal双遍。`inject_sources_resign.ps1`按原debug签名证书的固定SHA验证，不能无理由换签名、卸载/降低versionCode。
- GameRoot `_notification(WM_GO_BACK/APP_FOCUS_OUT/APP_RESUMED/WM_CLOSE)` 分别菜单、输入取消、帧间隔重置及安全退出拒绝提示；用户已授权B05多指bug在其他树施工，不使用其未冻结改动。本次平台焦点、恢复声音和覆盖安装/真实存档目录皆NOT_RUN。

## FINDINGS 与主控优先级

- **B06-001 P1**：地面Chunk、manifest、state单文件依次写入，无全地图事务和完备崩溃/损坏主文件恢复。可能丢最新人工地面；禁用无凭据`.bak`盲回退。
- **B06-002 P1**：map runtime晋升与registry提交中间强杀可形成不匹配；同步失败有回滚，不等于强杀原子性。
- **B06-003 P2**：编辑器在map document保存成功前提升内存revision，失败后build/publish可使用未持久化状态。
- **B06-004 P2条件性**：正式MapEditorRuntimeBridge runtime+release检查SHA/key，但缺原始`source.runtime_map_id`与registry数值ID的交叉校验；当前67图没有错。
- **B06-005 P2产品耐久性选择**：强杀时间窗durable死亡经验和pending地面奖励并非同一持久事务；安全退出已有drain。
- **B06-006 P3来源元数据**：74/201来源hash不符，但445PNG相同；是否修authoring需查历史版本、仅精确单图。
- **B06-007 P2条件性**：目标portal tile双向一致但没有明确用玩家foot envelope证明落点可走；需绑定正式poly阻挡与native现场。
全部细节在`FINDINGS.json/csv`，未经故障注入不能说玩家实际遇到损坏、丢物或非法落点。

**最终状态：报告可接收，不授予B06全部动态、109APK、Android或全项目验收。**
