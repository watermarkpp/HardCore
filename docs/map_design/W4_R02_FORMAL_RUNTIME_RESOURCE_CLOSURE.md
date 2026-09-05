# W4/R02 正式地图 runtime 资源闭包静态核查

核查基线：`c97a08b43832b174f98de31f5ed6673ccda344ae`；专项树当前提交：`28a7ffce52aae3cab3d482e4a5fa45cd92c53164`。

本报告只核查正式 release registry 指向的 runtime、ground/visual 动态链与 Android 导出排除；不把 `map_editor_workspace/**` 中的编辑器候选当作正式运行时缺失，也没有改动正式地图、资产或导出配置。W0 已核对的 67 条 registry 身份/hash 与 528 条 editor 候选不在本报告重复审计。

## 结论

- **正式源文件闭包：未发现确证缺失。** 67 条 `implemented_playable` entry 都有 runtime JSON 和对应 visual JSON；visual 的 445 条 chunk 引用、runtime 实例解析出的图片及 wall split 额外 pass 均能落到现有文件。
- **静态动态路径与 exclude：未发现误排除。** 本次收集的 922 条唯一动态纹理路径没有命中 `export_presets.cfg` 的 `exclude_filter`。runtime registry、runtime/visual JSON、实际 formal chunk store、资产 catalog 也不命中排除项；Android 预设仍为 `export_filter="all_resources"`。
- **R02 尚未闭环。** 原审计要求的是最终 APK/PCK 清单核验；本次没有导出包，因此只能证明源码侧路径闭合，不能把源码存在等同于最终产物已装包。
- **存在两个已证实的本地导入/测试契约风险（不属于 editor 候选缺失）：** 源数据实际引用 208 个唯一 formal chunk，而 `tests/map_android_vram_import_test.gd` 的常量仍期望 210；当前工作树生成的 208 个 ignored `.import` 均为 `compress/mode=0`、`"vram_texture": false`、`.ctex`，不满足该测试所期待的 VRAM/ETC2 形态。`.import` 未被 Git 跟踪，不能据此推断干净 Android 导出最终格式；应在最终 Godot 导入/导出环境重新生成并复验。

## 正式 runtime → ground/visual → texture 链

### 1. runtime 与 visual 入口

`scripts/layers/runtime/map_editor_runtime_bridge.gd` 的 `visual_path()` 由 registry 的 `map_key` 构造：

```text
res://assets/data/runtime/map_editor/<map_key>.visual.json
```

`ground_manifest_path()` 虽然能定位到 `res://map_editor_workspace/<map_key>/ground/ground_manifest.json`，但它只提供编辑器/build 侧路径；本次在项目脚本中只找到该定义，没有正式 world renderer 对它的读取。正式 world 链在 `scripts/world_background.gd` 的 `_load_editor_runtime_visual()` 读取 visual JSON，并验证 `map_id`、`runtime_map_id` 和 `coverage.complete`，再由 `_append_chunk_descriptors()` 加载 chunk。

### 2. visual ground chunk

对 registry 的 67 个 playable entry 做了定向 JSON/文件核对：

| 检查项 | 结果 |
|---|---:|
| runtime JSON 存在 | 67/67 |
| visual JSON 存在 | 67/67 |
| `coverage.complete` | 67/67 |
| visual chunk 引用 | 445 |
| unique formal chunk 路径 | 208 |
| chunk 路径越出 `assets/data/runtime/map_editor/formal_ground_chunks/sha256/` | 0 |
| `map_editor_workspace` 泄漏 | 0 |
| 实际 PNG 缺失 | 0 |
| visual 声明 SHA-256 与实际文件不符 | 0 |
| visual `required_chunk_count` / `packaged_chunk_count` 与实际 chunks 不一致 | 0 |

208 个实际 chunk PNG 都有本地 `.import` sidecar；但 sidecar 是被忽略的生成缓存，不是本次报告可以当作提交证据的正式输入。

### 3. runtime ground 与 instance asset ID

`runtime.ground.default_fill_asset_id`、`ground.tile_overrides` 和 7,746 个 runtime instances 的 `asset_id` 合并后得到 467 个唯一 ID（ground 87 个、instance 380 个）。按 `MapAssetCatalogService` 的 catalog 顺序核查：466 个来自主/extension catalog，1 个为 `ground.old_grass.001` 的 calibrated import-catalog fallback，0 个无法解析；62 个 ground ID 会按 source SHA 使用 normalized output，62 个 output 均存在。

`MapEditorRuntimeVisualGeometryService.sorted_draw_commands()` 将 instance ID 解析为资产图像；普通 image、6181 个 split-wall instance 的 shadow/base/front pass 以及其它特殊 pass 共形成 922 个 unique 动态纹理路径。所有路径存在，且没有命中当前 Android `exclude_filter`。

## 当前导出排除的边界

`export_presets.cfg` 的 Android 预设使用 `all_resources`，排除的是 tests/docs/tools/outputs、raw import、staging source/rgba、若干 source/preview 和报告目录。以下正式链路未被排除：

- `assets/data/runtime/map_editor/**`（registry、runtime、visual、formal chunk store）；
- `assets/data/assets/**` 中 runtime 需要的 catalog/import catalog；
- `assets/art/maps/**` 中 visual chunks、asset images、wall split images；
- `scripts/layers/runtime/map_editor_runtime_bridge.gd`、`scripts/world_background.gd` 及其地图域依赖。

反向风险是 `map_editor_workspace/**` 当前也没有被排除，因此编辑器 authoring 文件可能随 `all_resources` 进入产物。这不是“正式 runtime 缺输入”，也不能把它与 W0 的 editor 候选混称；是否在发布前排除应由 R02 最终 APK/PCK 清单和 Release 工具链确认，本专项不改导出配置。

## 已确认的导入/测试契约风险

`tests/map_android_vram_import_test.gd` 当前写有 `EXPECTED_FORMAL_MAPS = 67`、`EXPECTED_AUTHORED_CHUNKS = 445`、`EXPECTED_UNIQUE_CHUNKS = 210`。对同一 registry/visual 源文件静态计数为 `67 / 445 / 208`，formal chunk store 也有 208 个 tracked PNG 和 208 个本地 ignored sidecar；因此 210 是过时期望或缺少两项源引用，需由 integration 决定是否更新测试契约，不能通过重复计算把 208 说成 210。

当前 208 个 ignored sidecar 的内容一致表现为 `compress/mode=0`、`"vram_texture": false`、`.ctex`，而测试断言 `compress/mode=2`、`"vram_texture": true`、`.etc2.ctex`。由于 sidecar 不受 Git 跟踪且 Godot 可重生成，实际结论是“当前工作树导入缓存不满足测试断言，最终导出格式尚未证明”，不是“正式 PNG 缺失”。R02 最小验收应在干净、指定 Godot 版本的导入目录中重新生成 sidecar，然后运行该测试并检查最终 PCK/APK manifest。

## R01：发布中断恢复的只读结论

原审计包 `HardCore_全项目升级改造_首轮静态审计报告_20260905.md` 第 328–336 行明确要求：不能把同步失败回滚等同于进程中断可恢复；需要在 runtime 提升后、registry 提交前等边界 kill 并重启验证，同时报告没有证明项目缺少 journal。该报告没有要求本轮 B01 扩展为发布事务重构。

当前 `scripts/map_editor/map_editor_build_runtime_service.gd` 的真实流程为：

1. `_promote_runtime()` 写入并验证 `.publish_tmp`，把旧 runtime 改名 `.bak`，再提升新 runtime；
2. registry 使用 `.tmp`/`.bak` 的原子写入；post-publish verify 失败时尝试恢复 runtime 和 registry；
3. 失败测试 `tests/publish_failure_rollback_test.gd` 覆盖 invalid candidate、registry commit、runtime promote、post-publish verify 四类**同一进程注入**，没有进程 kill、重启或 orphan temp/backup 清理证明。

定向检索地图发布实现没有发现持久 journal、事务 phase record 或启动时扫描/选择旧新 pair 的恢复入口。另一个具体风险是 `_restore_runtime()` 返回 `void`，调用方不能知道 runtime rename/remove 是否失败；registry 恢复有布尔结果，但这仍不能证明跨进程中断后的 pair 一致性。以上是待验证风险，不是已复现的数据损坏。

R01 的最小可行修复范围应保持在发布事务域：选择“持久 phase journal”或“不可变 hash runtime + 单一 registry pointer”之一；记录旧/新 runtime hash、旧 registry bytes/hash 和阶段；启动/下一次发布处理 orphan `.publish_tmp`、`.bak`、`.restore_tmp`、`.restore_bak`；在 runtime promote 前后、registry promote 前后和 post-verify 前注入 kill，重启后证明只能留下一个可验证的旧/新一致 pair。没有这些故障注入证据前，不应做大规模发布重构，也不应声称 R01 已关闭。

## 证据与限制

本报告使用专项树的 registry、runtime/visual JSON、正式 chunk PNG、asset catalogs、`export_presets.cfg` 和原审计 ZIP 的相关原文做定向静态核查；没有运行 GUI Godot、没有删除真实地图、没有修改正式地图/资产/导出配置，也没有执行 APK/PCK 导出。最终 Release 仍需在 integration 的干净环境完成 artifact manifest、Godot import/VRAM 断言与 R01 kill/restart 验收。
