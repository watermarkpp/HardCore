# 地图回归失败分诊（2026-09-05）

## 后续复验裁决（优先于下文初始建议）

最终夹具按实际失败进一步修正：书商库存读取正式 merchant offers 与职业技能交集；边界起点用真实可见边中点，避免测试自身初始穿透；死亡回城走正式复活 UI 选择；旧社区时序/掉落改验 canonical 21CQ 与 DPV2 direct 权威，不反向覆盖数据。古墓完整 candidate binding 的变化不等于视觉几何变化，现按几何 SHA 决定严格 source/runtime parity；仅 F2 允许已证明且 revision 未发布的几何分叉，所有发布 runtime 继续严格检查。

`runner_results_adhoc_20260905_160048.json` 中 progression、比奇边界通过；`runner_results_adhoc_20260905_161327.json` 中 phase1、Bich community、古墓几何 3/3 PASS。原始分诊段落保留历史判断，不代表仍须按旧建议改地图。重复老兵已经独立正式发布并通过专项，见 `BICH_DUPLICATE_NPC_ACCEPTANCE.md`。尚待最终干净提交整体回归。

## 范围与结论

- 只读基线：`3c37c7a2c3e6d0c2ea1a5845e092f8dc85cdfe4e`，分支 `codex/integration`。
- 未运行 Godot，未改人工地图、发布 runtime、生产代码、资源、暂存区或设备数据。
- 当前正式权威是 `assets/data/map_design/map_identity_registry.json` 的稳定 `runtime_map_id` 与 `assets/data/runtime/map_editor/map_runtime_release_registry.json` 的 `implemented_playable` 发布记录。后者共 67 条；逐条静态核对均满足 registry approved build hash 等于 runtime `build_sha256`、registry `map_key` 等于 runtime `source.map_id`。
- `GameData.service_runtime_map_id()` 只保留服务入口 `0 -> 910001`，不把历史 4/217/… 当通用运行时别名。`MapEditorRuntimeBridge.has_runtime_map()` 又是 release registry 精确 ID 门禁。因此多数失败是测试仍把 `legacy_runtime_map_id` 当正式运行 ID，不是生产地图丢失。
- 两项不能用“更新断言”掩盖：诊断基线上的比奇发布 runtime 有一条重叠老兵重复记录；兽人古墓二层当前编辑文档在后续单位规范化后已与批准 runtime 分叉。前者已由用户授权地图所有者做单目标删除和正规重发布，本报告与测试修复不改地图；后者是编辑稿/发布态边界问题。

## 正式 ID 迁移表

| 地图 | 历史 ID | 正式 runtime ID |
| --- | ---: | ---: |
| 比奇省 | 4 | 910001 |
| 沃玛森林 | 268 | 910004 |
| 兽人古墓一/二/三层 | 217 / 218 / 221 | 911001 / 911002 / 911003 |
| 比奇矿区一/二层、尸王殿 | 406 / 408 / 1578 | 911101 / 911102 / 911103 |
| 沃玛寺庙一/二层、教主大厅 | 313 / 314 / 315 | 915001 / 915002 / 915003 |

测试应从正式 identity registry 或 `GameData.get_available_maps()` 中按 `formalMapKey` 精确取得对应 `mapId`；若测试本身就是稳定 ID 合同，也可直接写上述新 ID。不要在生产补一张通用旧 ID 回退表。

## 逐项分诊与最小修法

### 1. `bich_hard_boundary_test.gd:16`

**根因：测试夹具旧 ID，另有后继 name-only 隐患。** 第 12 行直接给 `WorldBackground` `{"mapId": 4}`。运行时碰撞只在 `MapEditorRuntimeBridge.has_runtime_map(map_id)` 为真时建立；正式比奇是 910001，所以四边形状为 0。第 47 行还调用已明确 fail-closed 的 `GameData.get_monster("稻草人")`，修完边界后会继续得到空记录。

**最小测试修复：** 用 `GameData.get_map_by_id(MapEditorRuntimeBridge.BICH_MAP_ID)`（910001）作为 `set_zone_data` 数据，并用 canonical ID 21 的 `GameData.get_monster_by_id(21)` 建怪；保留四边、玩家和怪物实际碰撞及几何投影全部断言。

### 2. `bich_content_1_test.gd:11`

**根因：一半是旧固定数量，一半是真实发布内容疑点。** 当前正式比奇 runtime 有 8 条 `npc_points`，而测试硬编码 7。角色构成为 shop=4、trainer=1、quest=2、warehouse=1；其中 `npc_000005` 与 `npc_000008` 都是 `npc.4.005` 老兵，且 tile 均为 `[24,39]`。该重复从 `7be29d4f` 的正式地图网络生成进入编辑文档，之后被发布，不应把期望改成 8 后直接放行。当前正式怪物刷新为 82 条，属于发布内容而非旧测试常量。

**正确权威与修法：**

1. 测试改为断言 `content.npcs.size() == runtime.semantics.npc_points.size()`，并针对比奇既定业务 roster 增加 `(npc_id, position_ground_gu)` 唯一性断言；诊断基线应继续在唯一性处失败，直到地图所有者移除重叠记录并按 candidate/validate/publish 流程重发，而不是直接编辑 runtime。
2. 保留必需服务角色断言，不固定允许扩展的 NPC 总量。
3. 第 23 行改为按 `spawn.monster_id` 调 `GameData.get_monster_by_id()`，并核对返回 ID；名称不是运行身份权威。

现有通用正式合同只要求 `semantic_id` 唯一，并校验 NPC 的非空 `npc_id` 与边界内 tile；`MapEditorBuildRuntimeService.validate_for_runtime()`、`MapEditorGameplaySemanticService._validate()` 和 runtime unit validator 均没有声明“相同 `npc_id` + tile、但不同 instance/semantic ID”全局非法。因此该重叠应按比奇业务内容合同修复，不能声称通用 schema 已经禁止，也不应擅自删除其它地图可能有意存在的同类实例。

### 3. `wooma_game_runtime_integration_test.gd:11`

**根因：全链路使用历史 ID，且固定 portal/Boss 数量已落后于发布内容。** 268/313/314/315 已迁移为 910004/915001/915002/915003。当前发布 portal 数依次为 6/2/2/1，Boss 刷新条数为 4/0/5/7；原 2/2/2/1 和 boss hall=1 不是当前发布权威。

**最小测试修复：** 全部 travel、portal target、arrival 查询和打印改用正式 ID；把总 portal 数断言改成“正式 runtime `map_exit_points` 数量与 projection 精确一致”，另断言必需边集合 `910004 -> 915001 -> 915002 -> 915003` 及反向边，并继续验证 fresh activation、single-flight、到达 portal ID、画面 ready。Boss hall 的 projection 数与正式 runtime `boss_spawn` 精确一致，逐条验证 canonical `monster_id`/分类，不把新增合法刷新点当漂移。

### 4. `phase1_game_runtime_integration_test.gd:60`

**根因：11 个 `EXPECTED_PORTALS` key 全是历史 ID；比奇/沃玛森林新增正式出口后，总数常量也过时。** 当前正式路线 ID 见迁移表；当前比奇 portal=5、沃玛森林=6，其余目标链为 2/2/1 或尸王殿 0。

**最小测试修复：** 用正式 ID 重写矿区、古墓、沃玛链和尸王殿 arrival-only 查询。把 `EXPECTED_PORTALS` 改成 `REQUIRED_TARGETS` 邻接集合，逐一查发布 `content.portals[*].target_map_id`；允许正式地图增加其它出口。保留来回 travel、portal guard、到达点、尸王殿无交互出口、回城卷、死亡回城全部断言。视觉块数应与每张正式 visual 的发布 chunks 数比较，地图尺寸与 runtime `design.design_size` 比较，而非复制 5/7/2、38x38。

### 5. `game_root_monster_prefetch_test.gd:34`

**根因：历史全局总量常量。** 107 来自 2026-08-15 的旧测试快照；当前 release registry 已有 67 张正式地图。测试逐图已经从 `game_content_for_map()` 构造 expected canonical ID 集并与 `_monster_ids_for_map()` 比较，这才是 prefetch 合同。

**最小测试修复：** 直接读取 release registry 及每张批准 runtime，逐条校验 approved hash、map key、runtime ID、刷新条目的精确 canonical ID 与 placement kind；由此独立计数 authored slots 和期望 ID 集，再与 projection 总数及 `_monster_ids_for_map()` 比较。删除 `formal_spawn_total == 107`，但不把两个 runtime 消费者互比当成独立证据。

### 6. `monster_world_integration_test.gd:224`

**根因：已发布刷新数增长，不是 bridge 丢失。** `1244300c` 发布时 raw total=1880；`406b3cf4` 的正式城市传送/内容更新后变为 1988，当前仍是 1988。该函数在第 214–225 行已逐图证明 projected ordinary/Boss 数分别等于每个批准 runtime 的 raw semantics，总数相等也成立；只有 `raw_total == 1880` 过期。

**最小测试修复：** 直接从 release registry 读取批准 runtime 并验证 hash、身份和每个 authored slot 的 canonical placement；移除 1880，保留逐图 ordinary/Boss 等量与 `projected_total == authored_slot_total`，并断言正式地图集和 authored total 非空。不要把 1988 再硬编码成下一次会漂移的快照。

### 7. `orc_tomb_runtime_visual_geometry_test.gd:41`

**根因：测试把当前 workspace 编辑文档误当已发布 runtime 的权威。** 实际失败地图是 `bich_orc_tomb_f2`。`eb9993b1` 只规范化并保存了该 editor 文档（大量 `tile_anchor` 从旧锚点改到新单位锚点），没有同步发布 runtime；两边均有 73 个实例，但多个实例几何字段不同。正式 registry 对 911002 批准的 build hash 与现 runtime 完全匹配，因此 APK 应继续消费批准 runtime，不能用工作区编辑稿覆盖。

**最小测试修复：**

1. formal runtime 测试通过 `MapEditorRuntimeBridge.has_runtime_map(91100x)` 与 `runtime_path()` 加载批准工件，以 `runtime.instances` 做 draw-command、排序、墙体多 render-part、sprite 几何和三图布局互异验证。
2. 用 `MapEditorBuildRuntimeService.candidate_matches_document({"document_binding": runtime.source.candidate_binding}, current_document)` 明确判断 workspace 是否就是发布源；相等时才做 editor/runtime parity。不等时只允许当前已证明的 F2，且必须满足 `runtime_approved_revision < revision`，否则仍失败，避免把任意分叉或正式损坏静默放过。
3. 独立地图发布门禁应要求编辑内容被修改时撤销 `runtime_approved`/递增 revision，并在真正发布后恢复严格 parity。本轮不修改或重发地图。

### 8. `bich_community_baseline_test.gd:17`

**根因：测试调用已退役的 name-only API。** `GameData.get_monster()` 当前按设计永远返回 `{}`，防止同名变体误解析；所以首先在“稻草人”失败，不代表 canonical catalog 缺失。当前精确 ID 为：稻草人21、钉耙猫26、多钩猫24、半兽人34、半兽战士36、森林雪人28、食人花30、毒蜘蛛18、骷髅47、骷髅精灵56、尸王89。

**最小测试修复：** 把名字数组改成 `{monster_id: expected_name}` 的固定 canonical 表，全程用 `get_monster_by_id()`，再核对 `canonical_name`、communitySource、attack interval 和 `get_calibrated_drops(monster_id)`。Enemy fixture 同样传 ID21/89 查得的记录；不恢复 name fallback。

### 9. `source_collision_chunk_test.gd:40`

**根因：正式分支仍传 4/217/1578，导致 travel 被精确运行 ID 门禁拒绝；401/402 则本来就是 `reference_audit_mode` 的 legacy reference 测试。** map 4 失败时背景仍是上一状态，因此四边/运行地表断言不成立。

**最小测试修复：** 只把三张正式地图改为 910001/911001/911103，并同步第 36/42/47 行分支；401/402 及其原 MAP mask 尺寸断言保持旧来源 ID。每次 travel 后先断言 `game.current_map_id == requested_id`，再检查 collision。正式 visual chunk 数改为与当前发布 visual `chunks.size()` 比较；正式设计尺寸从 runtime 取。不要把 401/402 提升成 formal playable。

### 10. `orc_tomb_source_integration_test.gd:67`

**根因：一个测试混合了两套合法身份，但 runtime 段错误继续用来源 ID。** 前半段的 217/218/221、D001/D002/D003、400x400 walkability mask 是历史源材料审计，仍应保留；第 62 行起是正式游戏运行验证，必须 travel 911001/911002/911003。旧 ID travel 被拒绝后背景自然没有对应资源。

**最小测试修复：** `EXPECTED` 每项同时记录 `source_id` 与 `runtime_id`。来源 manifest、`RegionContent` reference、`EnvironmentCatalog` 和 400x400 mask 校验继续使用 source ID；实例化游戏后的 travel、editor ground/collision/设计尺寸使用 runtime ID。进入后先断言 `current_map_id == runtime_id`，再通过正式 map data 的 `legacyRuntimeMapId` presentation projection 验证 D00x 客户端素材。chunk 数与批准 visual 比较，runtime 设计尺寸与批准 runtime 比较。

### 11. `bich_environment_test.gd:39`

**根因：用旧 217 切图失败后仍停在正式比奇，断言准确描述了结果但误判原因。**

**最小测试修复：** travel 911001，并在视觉断言之前增加 `current_map_id == 911001`、`MapEditorRuntimeBridge.has_runtime_map(911001)` 和 runtime ground ready 门禁；保留“离开后比奇 art/collision 清理”断言。

## 修复顺序建议

1. 先做纯测试 ID/authority 修正：1、3、4、8、9、10、11；同时移除重复总量快照：5、6。
2. `bich_content_1` 不可简单接受 8；用户已授权地图所有者单目标移除重复老兵并正规重发，本包保持该测试与地图只读。
3. `orc_tomb_runtime_visual_geometry` 已按发布态权威边界准备测试修复；F2 当前编辑稿未发布时继续验证批准 runtime，未来正规发布后 candidate binding 一致会自动恢复严格 editor/runtime parity。不能用旧 runtime 回写人工编辑稿，也不能绕过 candidate binding 直接重发。
4. 修后通过正式 runner 单独复验上述 11 场景；普通 30 秒，重地图场景至多 60 秒。本报告阶段按禁令未执行。
