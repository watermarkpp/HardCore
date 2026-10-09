# B02 Geometry / metadata final disposition

- 审查范围：固定 review `868ed9849caa9057e0811666cf6a4565429967f6` 的 B02-009/B02-010；当前工作树源码只读核对，未运行 Godot/native，未修改生产、生成物、测试或 authoring 数据。
- 结论标签：B02-009 = **BLOCKED（正式可达性未证）**；B02-010 = **BLOCKED（authoring 已给出 3x3，但仍有运行时 contract/document 2x2 漂移）**。不能把投影函数可计算、文档字符串或源码 geometry_cells 当作地图可达性证明。

## B02-009：`Vector2i.ZERO` 与正式地图目标可达性

### 已确认的调用链

1. `scripts/skills/skill_runtime_router.gd:124-129` 是通用计划入口。缺省 `origin_tile`、`target_tile` 均是 `Vector2i.ZERO`；调用 `SkillGeometryService.cells()`。
2. `scripts/game_root.gd:9351-9369` 是正式地面精确释放入口。它从 release context 得到 `origin_tile`，再把 `target_tile` 传给同一个 geometry service，并随后进入 `CasterSpellGeometryScript.effective_cells()` 的地形过滤。
3. `scripts/skills/skill_geometry_service.gd:35-40` 将 `target_tile == Vector2i.ZERO` 解释为“未设置”，并退回 `origin`。这使 `(0,0)` 不能在该 API 中表达为一个明确目标；它不是“零点一定不可达”，而是一个输入协议歧义。
4. `scripts/game_root.gd:8662-8680` 对 Taoist 支援类释放显式写入同一个选定中心的 `target_tile` 与 `origin_tile`，说明正式调用者已知道该 sentinel 合同；这仍不证明 `(0,0)` 是可玩的目标点。
5. `scripts/skills/skill_execution_plan_contract.gd:184-205, 410-455, 530-615` 对有效 map 的 release snapshot 使用 `runtime_map_id`、`screen_to_ground_position_px`、`ground_to_screen_position_gu` 及目标实例脚点；目标 footprint/area/projectile 均在释放上下文中生成。缺少 projection callable 时 mapped plan 会拒绝（184-204），所以“能投影”与“已通过正式上下文”是两层条件。

### 正式地图 / terrain / navigation 证据边界

- `scripts/map_coordinate_mapper.gd:37-105`：`map_id < 0` 是明确的测试 identity；正式路径只有 `MapEditorRuntimeBridge.is_formal_playable(map_id)` 成功并加载 runtime profile 才返回 map-aware projection。reference-only、未实现和未知地图都会返回 invalid callable。
- `scripts/layers/runtime/map_editor_runtime_bridge.gd:258-301`：`has_runtime_map()`/`is_formal_playable()` 依赖 release registry 的 playable readiness；`runtime_artifact_exists()` 仅证明文件存在，不授予 readiness。故 source bounds 或 projection profile 本身不能证明 navigation 可达。
- `scripts/world_background.gd:349-355,369-390`：正式环境由 source mask、clearance cache、editor runtime collision snapshot 和 point/actor blocked 查询决定；`source_mask_cell_blocked()` 的越界语义甚至返回 false（349-354），不能拿越界或 `(0,0)` 的默认值当作“可走”。`scripts/world_background.gd:3507-3546` 的 clear-cell cache 由 authoring routes/content/arena 生成，是环境证据的一部分，而非 geometry service 的替代品。
- 因此当前源码能证明：正式 map 的 `(0,0)` 可被 projection/geometry API 搬运；不能证明某个正式 map 的 `(0,0)` 同时满足 bounds、terrain clear、actor footprint、navigation/skill admission 和实际 release target 条件。没有固定 map id、runtime registry、坐标投影结果、terrain query、目标/施法者 snapshot 的同一份 receipt，结论必须是 BLOCKED。

### 最小可执行修正路径（不在本轮实施）

- 保持稳定 skill ID 和现有 `SkillGeometryService.cells()` 兼容行为；不要直接把 ZERO sentinel 改成目标坐标，避免全量释放改变。
- 若产品确实要求 `(0,0)` 作为真实 target，增加显式 `has_target_tile`/`target_tile_valid` 字段（或等价 typed option）并在 router、GameRoot release context、execution snapshot、formal test 全链路传递；不要用第二个 magic tile。
- 固定一个正式 playable `runtime_map_id` 与 authoring release fingerprint；由 map projection 得到 ground/source 坐标，再用正式 world collision/navigation/skill admission 查询，在同一释放窗口记录：`map_id`, registry generation, projection policy, source tile, `contains_source`, actor-footprint blocked, target identity/life/map generation, effective cells, final accepted/rejected reason。
- 在该合同落地前，不能声称 `(0,0)` reachability、不能把测试 identity map 当正式地图证明，也不能扩大攻击/技能范围。

## B02-010：spatial matrix 与 authoring/runtime 漂移

### 稳定 ID、权威值与实际消费者

- 稳定 ID `wizard.fire_wall`：`assets/data/vanilla_176/skills_source_of_truth_v1.json:2098-2112,2179,2228-2303` 明确 `ground_or_target_point`、`square`、`width_tiles=3`、`height_tiles=3`，并要求 `fire_wall_exact_3x3`、`fire_wall_not_circle_or_cross` 等测试。该 authoring SOT 是 3x3 的最强可执行来源。
- `scripts/skills/runtimes/wizard_skill_runtime.gd:62-78` 将定义中的 width/height 传入持久地面伤害 effect，并保持 tick/duration/stacking/cap policy；它不是 2x2 的来源。
- `scripts/skills/skill_geometry_service.gd:45-52,64-68` 按定义生成 square/chebyshev cells；在 3x3 definition 下实际 cell union 是 3x3。`scripts/game_root.gd:9358-9369` 再经 `effective_cells()` 和 terrain-blocked callback 生成 release snapshot。
- `scripts/skills/combat_unit_legacy_adapter.gd:194-207` 只做旧 `width_tiles`/`height_tiles` 到 `width_grid_steps`/`height_grid_steps` 的一次字段转换；不是新的空间权威。
- `scripts/skills/skill_spatial_projection_contract.gd:124-128` 仍写 `wizard.fire_wall` 为 `source_geometry_frozen_2_by_2_exact_cell_union`。这与 SOT、runtime effect、geometry service 的 3x3 证据直接冲突，属于需要正式更新的 contract drift。
- `docs/combat/spatial_projection_relationship_matrix.md:50-52` 仍将火墙写为冻结 2x2；这是文档/审核输入漂移，不能覆盖运行时和 authoring SOT。

### 1.5GU / 2.5GU 不属于同一离散矩阵

- `docs/combat/spatial_projection_relationship_matrix.md:27-37` 将普通攻击标为 1.5 GU 单体近战，刺杀为 2.5 GU × 1 GU directed core。
- `assets/data/vanilla_176/skills_source_of_truth_v1.json:562-565,861` 也保留 1.5 的 reach 字段；`scripts/warrior_combat_math.gd:17-19` 明确 `THRUST_PRIMARY_REACH_GU=1.5`、总长 3.0；`scripts/skills/warrior_melee_geometry.gd:85,889-890,1198` 执行连续 GU 分段与边界判断。
- 这些 continuous/directed values 不能折算成 Fire Wall 的 2x2 或 3x3 discrete cell count。`SkillGeometryService.geometry_domain()` 将 `wizard.hellfire`/`wizard.laser` 标成 continuous domain，其他几何默认 discrete；这是域分界，不是可把所有数值混成一个矩阵的许可。

### 最小正式更新路径

1. 以 `skills_source_of_truth_v1.json` 的 `wizard.fire_wall` 3x3 与现有 `wizard_skill_runtime.gd`/`SkillGeometryService` 为运行时基准，更新 `skill_spatial_projection_contract.gd` 和 `spatial_projection_relationship_matrix.md` 的 2x2 描述为 3x3；保留旧冲突说明与迁移证据，不静默覆盖。
2. 为 `wizard.fire_wall` 固定一个 formal playable map release receipt：验证 exact 3x3 cells、terrain filter、每 tick 一次目标结算、duration/refresh/cap policy；必须绑定 source SOT SHA、runtime map registry/generation、release id。
3. 单独为 continuous `1.5 GU` 普攻和 `2.5 GU × 1 GU` 刺杀维护 directed/continuous contract；不要用 grid matrix 的 3x3 修正它们。
4. B02-009 在同一专项中补正式 map target option（若要支持 `(0,0)`）；否则将 `(0,0)` 继续视为“未设置”并把测试目标换成明确非零 tile。任何修正都需按正式生成链更新 source/contract/runtime receipt，而非手改生成物。

## 输入指纹与结论范围

本次静态审查使用当前工作树源码（HEAD `215f0b2f651a51e6855ee813ddd99221690311a1`；当前工作树含其他已授权 dirty edits，不将其误报为 clean）。关键输入 SHA256：

- `scripts/skills/skill_geometry_service.gd` — `D6FA941D425798978876F9FFC77A5F2A5FE56890D97D11ECE6EE72F13DE3FB8F`
- `scripts/skills/skill_runtime_router.gd` — `841A02F77B299000F183957A2212ADE72E5EEAF15ADEB102041C268336252CD9`
- `scripts/game_root.gd` — `2EA2DC8E90239E8C1DB9260CABBB57A7991EC14B82999C89B2035661E90E5C93`
- `scripts/skills/skill_execution_plan_contract.gd` — `1F8A3831AAA715B7AFF294A205ADE55B2A65C6BCE01211A35915902F8EFA657C`
- `scripts/map_coordinate_mapper.gd` — `69F061A030F3C279D5B40AC3BBE3D025A2B565CFC8D94FF7FA5587C59D36847D`
- `scripts/layers/runtime/map_editor_runtime_bridge.gd` — `6322AAF98410F7578FCD7DD59B33C20FF34CC17A77463EDC20A4115B31784EF5`
- `scripts/world_background.gd` — `0822BAC938022122C0CF25780647455DA196F6A18DBBEC02A661239E8BAB37A5`
- `scripts/skills/runtimes/wizard_skill_runtime.gd` — `07196A335CACF5EC9112446E517ED05A1FBC3A12F2FF5A6F41D5816A712259FE`
- `scripts/skills/skill_spatial_projection_contract.gd` — `3640A9F16C753D578BC8958303CFFE08C90F28440CED4F1938948932024533FB`
- `assets/data/vanilla_176/skills_source_of_truth_v1.json` — `7575C45A7BD147F8E60D2EFDB15C6C5E9781445DDC2F748E73DD69ED386A62AB`
- `docs/combat/spatial_projection_relationship_matrix.md` — `7C7E04869CA65214BF7DB5B576FF5D5AED9E88E81B9911476B9686296D3C1520`
- `docs/combat/combat_geometry_audit.md` — `B7A4EB0E3A9ADA9B4ADC35CDAA0FC49E0AB18AEDBE6EF4663265F1B3FFBBCBDC`
- `scripts/warrior_combat_math.gd` — `A24EB74882D70C8819AF2E8CFAA85014DD8B417DCE1508FAE18B8DF32DD74D78`
- `scripts/skills/warrior_melee_geometry.gd` — `AEB280D129FCF0004850A137DD98A7934783B7512404499873D997E264B2CE54`

未执行 native/engine；因此“正式地图 `(0,0)` 可达”“2x2 contract 已修复”均为 **NOT_RUN/BLOCKED**，不是 PASS。
