# 地面网格可见性改动：只读机械审计

审计日期：2026-09-22。读取分支 `codex/integration`，HEAD `b961cedff8040c9fc81534e094241ad9fa2330ad`。本报告仅提供主控复核材料；保留用户已接受的无网格视觉效果，不修改、恢复或重生成地图、图片、碰撞、门点和怪物位置。

状态：Git 历史/文件边界/JSON 字段/PNG 字节及像素比对 **PASS**；Godot 解析、渲染、行为、设备复测 **NOT_RUN**。未执行 Git 写操作、Godot、构建或代理。工作树仍有主控施工，以下行号和当前文件摘要以本次读取为准。

## 1. 核心发现及可证明边界

1. **`c8ee988e` 是纹理采样修复，不是删除地面网格像素。** 提交只增加 `EditorChunkGroundCanvas` 并把已发布地面 chunk 的绘制移至 LINEAR 采样子节点，矩形、纹理和坐标仍来自同一 `_editor_runtime_chunk_draws`。源码注释也明确表示原贴图含细网格线，LINEAR 使其在 1.06 缩放时稳定，不表示源像素已被抹掉。
2. 该提交前后，整个 `assets/art/maps`、`assets/data/runtime/map_editor`、`map_editor_workspace` Git 子树完全相同。坐标、地面生成、编辑器网格、GameRoot 文件也逐个 Git blob 相同。因此 **没有发现该采样改动修改碰撞、坐标、门点或怪物 spawn 数据的证据**。
3. 后续确有地面 PNG 变更，已定位到 `0dde436c`、`7f34e004`、`6c4de46e` 的人工地图内容包。共比对 **40 个改动后的 workspace PNG**：全部尺寸不变；赤月三图的 15 张仅删除像素；黑暗地带及四个兄弟图还存在补画/替换地块。它们不是独立去网格算法提交。
4. 后续内容包同时修改了碰撞，两个源地图还移动了 3 个怪物点、补入门点视觉锚点。**不得把这些整包改动宣称为“仅改渲染、其他完全不变”。** 这些是历史人工地图内容变化，本审计没有证据将其归因于去网格，也不建议恢复。
5. 编辑器 `show_grid`、`MapEditorGridService.visible_grid_lines` 仍存在，坐标/格子生成器未被移除。正式运行时仍有旧非 editor 地图 fallback 的菱形描边代码，但正式 authored visual 路径在此前即 `return`，不走该 fallback。
6. Git 作者均为 `Codex <codex@local>`。可证明提交者及改动内容，**不能仅凭 Git 作者证明或否定实际使用过 GLM**。本次可达 Git 历史和有界源码搜索未找到另一个明确的 `degrid`/去网格像素移除实现；这是 **MISSING（独立实际抹线改动证据）**，不是否定用户当前视觉确认。

## 2. 精确采样提交及哈希

`c8ee988ef6c9acbb42605e9f9edfb28da93ed529`，2026-09-16 15:58:16 +08:00，标题 `fix(render): kill ground grid shimmer while moving - linear chunk canvas`。

| 改动文件 | 改动 | c8 提交 SHA-256（Git blob 字节） | 当前 HEAD / 工作树 LF SHA-256 |
|---|---|---|---|
| `scripts/layers/presentation/editor_chunk_ground_canvas.gd` | 新增 45 行；`_ready()` 设 LINEAR；`_draw()` 原矩形绘制全部 chunk | `4f97ad08ce1576f2b36b1f80bf769ad81d3023c0f8a112eabf7f9eb84e0717b5` | 同左 |
| `scripts/world_background.gd` | 原绘制循环改为单一子 canvas；构建 chunk 时同步列表；清图时释放引用 | `eaa6f0cbe9297393b1839064ebb127734c000e3cf46ff94bb7bbdfc9fd65fcc4` | `21b1f987c337adcdec806cfe5a1d341dc557f9bfc8a7fa6b7a37a8ed60a6980f` |

当前 `world_background.gd` 后续变动还包括墙渲染、polygon collision 等正式工作；当前未提交 diff 不包含上述两文件。不能将 HEAD 与 c8 的整体差异全归为去网格。

以下为 `c8ee988e^` 和 `c8ee988e` **相等**的 Git 对象 ID；Git tree/blob ID 是 SHA-1，不与上表 SHA-256 混用：

| 路径 | 两版本相同的 Git 对象 ID |
|---|---|
| `assets/art/maps` | `c44a05e92671ff0401569afe80f5ffe981006bff` |
| `assets/data/runtime/map_editor` | `feec07f82cfff34d3f891cd9cdc69e4b614010d2` |
| `map_editor_workspace` | `fa6c3e7a67d389e555cdf4140337f37cf0ee88f2` |
| `scripts/map_editor/map_editor_coordinate.gd` | `d1af6d8f2e3d4c7d036f17b9696b2a17675d30d5` |
| `scripts/map_editor/map_editor_ground_service.gd` | `c43a29b4bdc7f3e7896b8c7f92b13ea8e74d7f1b` |
| `scripts/map_editor/map_editor_chunk_bake_service.gd` | `3dbeed6d652e8038e5441fba02c65b2a844a51eb` |
| `scripts/map_editor/map_editor_grid_service.gd` | `948ff3a9a2f276a66fe3d8eefa2a56cb5cb565cd` |
| `scripts/game_root.gd` | `85c49e7a152f9e2dbc8fe867d09392a4dd2ca86e` |

## 3. 后续图片及人工数据提交

| 提交 | 精确地图范围 | 改动文件分类 | 地面操作和其他内容 |
|---|---|---|---|
| `0dde436c332c59f5c9cf1867ea4bd276c3c58727` | `mengzhong_dark_area` | 1 editor、1 runtime、1 visual、8 ground JSON、5 workspace PNG、5 新 sha store PNG、1 registry，共 22 文件 | 在原 2758 paint 后增加 153 paint / 412 erase；碰撞、墙体、部分物件、2 个怪物位置、门点视觉锚点变化 |
| `7f34e00403e2bcc0350a3fea2249233b2751934e` | `mengzhong_between_life_and_death`、`mengzhong_death_coffin`、`mengzhong_terror_space`、`mengzhong_thin_sky_passage` | 4 editor、4 runtime、4 visual、32 ground JSON、20 workspace PNG、registry + clone 工具，共 66 文件 | 复制黑暗地带墙/碰撞/地面操作；四图 runtime 的 design、semantics 均保持完全相等；object_base 的数值序列化有浮点尾数差异 |
| `6c4de46e63c366fc4f0d8798b1136dea980fcf33` | `chiyue_valley`、`chiyue_valley_secret_passage_a`、`chiyue_valley_secret_passage_b` | 3 editor、3 runtime、3 visual、24 ground JSON、15 workspace PNG、5 新 sha store PNG、registry + clone 工具，共 55 文件 | 源地面原 5333 paint 保留，追加 705 erase；三图碰撞变化；两个 passage runtime 的 semantics 相等；源 valley 另有 1 个怪物位置和门点视觉锚点变化 |

这些提交对应的文件路径展开规则：

- authoring：`map_editor_workspace/<map_key>/<map_key>.editor.json`。
- 可编辑地面操作：`map_editor_workspace/<map_key>/ground/ground_state.json`、`ground/chunks/c_*.json`、`ground/ground_manifest.json`。
- 可重建预览：`map_editor_workspace/<map_key>/ground/baked_preview/bake_manifest.json` 和 `c_*.png`。
- 正式派生物：`assets/data/runtime/map_editor/<map_key>.runtime.json`、`<map_key>.visual.json`、`formal_ground_chunks/sha256/<sha256>.png`、`map_runtime_release_registry.json`。
- 迁移工具：`tools/map_editor/clone_wall_collision_ground.gd`（7f 新增，6c 参数化）。该工具是用户指定地图内容复制流程，非去网格滤镜。

40 张 workspace 图片的父提交→目标提交机械像素比对（RGBA 解码，仅内存读取，没有保存图片）：

| 提交 | PNG 数 | 尺寸改变 | 前后均可见的像素中 RGBA 改变数 | 新增可见像素 | 删除可见像素 |
|---|---:|---:|---:|---:|---:|
| 0dde436c | 5 | 0 | 1024 | 8192 | 347136 |
| 7f34e004 | 20 | 0 | 4096 | 32768 | 1388544 |
| 6c4de46e | 15 | 0 | 0 | 0 | 1195008 |

黑暗地带少量保留区域像素变化与该提交确有 153 新 paint 操作相符；本审计不把整包描述为“仅删除”，也不推断具体 paint 的艺术意图。赤月 15 张在仍可见区域零像素差异，足以排除该组图片进行全局抹线/模糊处理。

两张可复核样本（尺寸均 1024×1024）：

| 文件 | 父提交 SHA-256 | 提交后 SHA-256 | 仍可见区域 |
|---|---|---|---|
| `map_editor_workspace/mengzhong_dark_area/ground/baked_preview/c_1_0.png` @ 0dde | `47dea81318ab381e5ac3bc357cf9b6731e809473baa4c59df05ec3f4754c2d7a` | `48a0b89c4c6db38dfcaf25d4271869f6f35c024abfcfae30e1aa6f6a026eb791` | 744960 像素，RGBA 零差异 |
| `map_editor_workspace/chiyue_valley/ground/baked_preview/c_2_1.png` @ 6c | `17207f203b8ecaa829d05251f8c3b4228471bcfd8f8f5f328743a8fd4d24a6df` | `cdcf7fe8af991e18fcf6207998af5c01748d773395f70d16c942c522dbf84cf8` | 752640 像素，RGBA 零差异 |

全部已比对 PNG 文件名+提交后 SHA-256 的摘要：按 `git diff-tree --name-only -r <commit>` 顺序，仅选 `/baked_preview/*.png`，拼接 UTF-8 `path\tsha256\n` 后再 SHA-256。

| 提交 | 路径/哈希清单摘要 |
|---|---|
| 0dde436c | `1d19c73ea6decf21b5fcee3116a16eba8fc3cd8f13fefd54801a3954f464ce6e` |
| 7f34e004 | `dbe7ebbb5dbff039e8315ce60445c98f81e96bb6be0535997712de10b9359ab1` |
| 6c4de46e | `c25920239b20adea23cfa713a6972da795793d90a82a58dd7cc84c07d0eb366c` |

后续其他提交的排除证据：

- `334f86be` 实际仅新增 8 个 JSON：`stage6_semantics` 和 `wooma_temple_1/2/3` 各自的 ground manifest/state；没有 PNG，不能按宽泛提交描述推断有地面重绘。
- `9944265c` 为 208 文件的大批 authoring/runtime 同步，包含 67 editor、67 runtime、3 ground manifest 等；该提交没有 PNG，亦没有 `.visual.json` 改动。它不能解释新的地面像素去线效果。
- `84ab2274` 为骨魔洞五层宝箱人工内容重新发布，共 4 文件，没有 PNG。
- 从 `c8ee988e` 到当前 HEAD，`assets/art/maps` **仅两个文件不同**：`_shared/user_palette/decorations_1/map_entrances/portal_gates_20260916/portal_gate_bidirectional_blue.png` 和 `portal_gate_one_way_red.png`。这是入口装饰，不是 ground tile 原图。没有地面原图在此区间被替换的证据。

## 4. 同批 gameplay 字段差异：必须与采样修复分开

| 提交 / 地图 | 精确实例或 semantic_id | 前→后 |
|---|---|---|
| 0dde / dark_area | `mse.placement.v1.mengzhong_dark_area.monster_spawn.000017`，monster_id 112 | tile `[22,25]` → `[15,26]` |
| 0dde / dark_area | `mse.placement.v1.mengzhong_dark_area.monster_spawn.000022`，monster_id 118 | tile `[10,10]` → `[9,10]` |
| 6c / chiyue_valley | `mse.placement.v1.chiyue_valley.monster_spawn.000003`，monster_id 172 | tile `[30,1]` → `[19,16]` |

三个记录的数量、ID、其他字段保持一致。两张源地图各 2 个 `map_exit_points` 仅新增 `portal_visual_origin_tile`、`portal_anchor_contract_id`、`portal_visual_footprint_tiles`；原门点 tile、目标 map/tile 等字段未改。dark_area 的两个 linked 入口装饰另有位置、0.7 缩放及 material layer 调整。四个复制目标图、两个 passage 的 runtime semantics 前后均相等。各图 design 前后均相等，collision 前后不相等。

这说明历史“monster 总数量不变”并不能替代“坐标不变”证据。这里记录实际差异供主控复核已接受的人工内容边界；不据此要求重做、回滚冻结地图或认定这些改动有错。

## 5. 当前权威与消费链

| 环节 | 证据位置 | 与网格显示的关系 |
|---|---|---|
| 坐标权威 | `scripts/map_editor/map_editor_coordinate.gd:6`、`:12`、`:34`、`:81` | 64×32 cell-center v2；最后改动 f559463d（08-29），不在 c8 及后续抹线改动中 |
| 画地面操作 | `scripts/map_editor/map_editor_ground_service.gd:117` | paint/erase 转为 tile_overrides，保存可编辑操作；不从视觉线反推坐标 |
| 原 tile 规范化 | 同文件 `:131` | 读取 catalog image、裁透明边、调整64×32、菱形 alpha mask；无“删除内部网格线”算法；最后修改 f559463d |
| 烘焙 | `scripts/map_editor/map_editor_chunk_bake_service.gd:69` | 透明图起步，按 cell texture rect 混合存在的 tile；无网格 draw 调用；最后修改 bf49c704（07-19） |
| ground 不生碰撞 | `scripts/map_editor/map_editor_types.gd:52`、`:151` | 默认 `visual_only=true`、`collision_from_ground=false`；启用后者会校验失败 |
| runtime 编译 | `scripts/map_editor/map_editor_build_runtime_service.gd:1254`、`:1296` | ground、collision、semantics 分开编译；门点和怪物来自人工语义层，碰撞来自 walkability/manual shapes（现 polygon 合同再编译） |
| 正式图片发布 | `tools/map_editor/publish_formal_map_releases.gd:222`、`:332`、`:372` | authoring manifest/state + baked PNG → source 哈希、原 rect → sha-addressed PNG；复制时验证源/目标 SHA，一致性不靠滤镜 |
| 正式加载 | `scripts/layers/runtime/map_editor_runtime_bridge.gd:360`；`scripts/world_background.gd:2332` | 通过 map key/id 加载 visual；校验身份和 coverage。这里没有重新生成网格或坐标 |
| chunk 位置 | `scripts/world_background.gd:1107` | `rect_px - ground_pixel_center`，尺寸不改；c8 子 canvas 使用这个最终矩形 |
| 绘制与生命周期 | `scripts/layers/presentation/editor_chunk_ground_canvas.gd:23`、`:40`；`scripts/world_background.gd:1143`、`:1911`、`:776` | LINEAR 设置只在地面子节点；父背景保持 NEAREST；清图清列表/节点。背景 z=-20，子 canvas 相对 z=0，未改变世界坐标 |
| 物理查询 | `scripts/world_background.gd:432` | 使用 compiled collision / polygon index，不读地面 PNG RGB/alpha，不读 `texture_filter` |
| 编辑器网格 | `scripts/map_editor/map_editor_grid_service.gd:5`；`scripts/map_editor/map_editor_canvas_preview.gd:26`、`:489` | `show_grid=true` 和 grid lines 完整保留；仅编辑器 preview 的 draw overlay；grid service 最后提交77ba79ec（07-16） |
| 旧 fallback | `scripts/world_background.gd:649`、`:670` | authored visual 分支先返回；后面的无正式 ground fallback 仍有菱形描边。不能描述为“整个项目网格代码删除” |

当前有限复核的 8 图共 **63 个 ground chunk 引用**，每个正式 PNG 的 SHA-256 均等于 visual 记录且等于对应 workspace baked_preview，全部 **PASS**。8 个 ground manifest 当前原始字节哈希均等于各 visual 记录，全部 **PASS**。这些域当前 tracked diff 仅见主控的 60 份 wall render plan；没有地面 PNG、editor 或 runtime JSON 的新增差异。

来源元数据限制也保留：8 图 visual 的旧 editor SHA 与当前 authoring 不同；这与后续人工发布内容变化并存，不能冒称完整 source 字节链全部相等。ground state 原始字节亦因本机 CRLF 与记录不等；对 dark_area、chiyue_valley 实测，**LF 归一和 Git blob SHA 均精确等于 visual 记录**，是行尾问题，不是地面操作改变。不得因该诊断重烘冻结图片；manifest 行尾专项由主控另行处理。本报告未改校验、allowlist 或行尾。

当前代表性 SHA-256（工作树原始字节）：

| 文件 | SHA-256 |
|---|---|
| `map_editor_workspace/mengzhong_dark_area/ground/ground_manifest.json` | `9ed5ff0d7ee975a5cc5a6b4f0c58a86c5b1266541a7f0d25686c15231570937b` |
| `assets/data/runtime/map_editor/mengzhong_dark_area.visual.json` | `29947f074d3fd1261cd452c34c45ecc7cb5171db307087778795a68bd277198c` |
| `map_editor_workspace/chiyue_valley/ground/ground_manifest.json` | `f0072698111d9ac1dfbeb6ce3844d6dd9bde657b5bed996fa3bda7b1fe37ee4c` |
| `assets/data/runtime/map_editor/chiyue_valley.visual.json` | `8cdd77193f994739880c467cda0d42063361770ceaf6abbc5934a1727ed78ae0` |
| `scripts/map_editor/map_editor_coordinate.gd`（LF） | `38f8c7cf3042699709d6b5728d7c9c603d09718ca749f51f71c9dd0fd8f2d336` |
| `scripts/map_editor/map_editor_grid_service.gd`（LF） | `86ff92a9199fe2b0586cd3812c764e4fe025ec29cbdbcec20b09506816840014` |

## 6. 精确现有测试与未覆盖项

下列名称均在当前仓库实际存在，本审计未运行，状态统一 **NOT_RUN**，不引用历史提交消息中的 PASS 作为本次验收：

| 测试场景 | 直接覆盖 |
|---|---|
| `tests/mse_stage1_ground_test.tscn` | workspace 初始化、chunk 分区、dirty/virtual 状态、坐标合同 |
| `tests/mse_stage2_paint_bake_test.tscn` | 真 paint/erase、dirty chunk 烘焙、尺寸、bake manifest、重复烘焙 no-op |
| `tests/mse_ground_coordinate_contract_test.tscn` | 格子/贴图中心一致、legacy bake 迁移 |
| `tests/ground_coordinate_contract_v2_test.tscn` | 64×32 坐标、边界、碰撞对齐、操作重分区、编辑器保存重开 |
| `tests/mse_collision_grid_alignment_test.tscn` | 编辑器点击、格点、手工碰撞位置一致；不等价于检查 grid 开关可视效果 |
| `tests/world_bich_ground_v2_pixel_alignment_test.tscn` | 正式地面 PNG alpha union 与坐标范围 |
| `tests/world_background_ground_v2_guard_contract_test.tscn` | 地面/物理边界、guard shader 坐标一致 |
| `tests/map_published_ground_boundary_physics_test.tscn` | 发布地面边界与实际物理边界 |
| `tests/world_background_staged_map_build_test.tscn` | staged 构建、地面 chunk 数和稳定完成 |
| `tests/implemented_map_runtime_projection_test.tscn` | 正式地图 GameRoot/NPC/敌人投影 |
| `tests/map_release_identity_matrix_test.tscn` | 全部发布身份、registry/runtime/editor revision、门点往返和 ground manifest provenance |

**MISSING：** 精确搜索当前 tests，未发现直接断言 `EditorChunkGroundCanvas` / `_editor_chunk_ground_canvas` / `chunk_draw_count` / 该 canvas LINEAR filter 的专项，也未发现 `show_grid` true↔false 后校验编辑器选择/坐标不变的专项。现有墙图视觉捕获场景只是设置 `canvas.show_grid=false`，不能替代这一证明。

如主控需要为本次静态结论补最窄行为证据，可使用正式一图：读取 chunk 原 rect/资源标识和 collision 查询结果；确认独立 ground canvas 为 LINEAR、清图后释放并在新 generation 重建；切编辑器网格可见性后同一点击仍命中同一 tile。这是待测建议，不意味着当前用户接受的画面需要改变。移动时条纹、chunk 接缝及设备观感仍需实际渲染/设备证据，**DEVICE TEST: NOT_RUN**。

本次可证明的是采样改动没有改动地图数据权威，以及后续相关图片与正式加载链的有限一致性；没有凭静态证据宣称全量地图、所有设备或全部后续地图内容“无影响”。最终范围与验收由主控裁决。
