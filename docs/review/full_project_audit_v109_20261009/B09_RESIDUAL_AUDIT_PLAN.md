# v109 remaining fine semantic audit plan

固定源码 `dbb1bd0878ab24a4e5bd6a1877d32f304f5623e5`，tree `fef3e786da2a7462abdc069f48615215407f6a11`。本文件只制定剩余审查责任；全项目精细语义审查仍为 **MISSING**，全部新批次 **NOT_RUN**。没有运行 native、打包或设备测试。

原manifest的374个脚本/场景逐路径登记：372个正式固定路径；2个本地退役grid实验缺失，单列保全，不当作生产功能缺失。关键工具/authoring入口164个，另有345个工具/文档/数据角色待分类；117个生产路径原属于residual_review，保留人工分类责任。

372个正式脚本/场景共161030行、7251个具名函数；164个关键工具共56451行、1327个具名函数。这里只统计具名声明/AST，不覆盖匿名Callable，也不作为语义读取证据。

## Evidence matching and reuse

B01–B08 COVERAGE、SOURCE_BINDING、CROSS_BATCH与本地逐函数supplement已结构化解析。B08的8份接收报告逐文件与2d95b21c Git字节相等。逐函数只接受明确语义body记录；NOT_REVIEWED/index-only、whole-file FULL声明、函数名索引不转换为全函数完成。旧函数body按固定对象比对：整文件字节相同可复用明确body；仅body未变而文件变化的保留body证据、补owner/constants/caller边界；变更body/partial101行前缀/未匹配函数继续审查。

| Function evidence class | Count |
|---|---:|
| NO_NAMED_SEMANTIC_BODY_EVIDENCE | 7541 |
| FIXED_FILE_NAMED_BODY_REUSED | 823 |
| UNCHANGED_BODY_CALLER_CONTEXT_REFRESH | 82 |
| CHANGED_BODY_REVIEW_REQUIRED | 39 |
| PARTIAL_NAMED_SCOPE_REMAINING | 93 |

这些数是保守证据匹配计数，不是全项目/发布PASS。源函数行区间由regex/AST用于分工，动态Callable/信号/scene/data消费者仍须审查者真实追踪。

## Sequential batches

每批≤15000实际指定源码行；长文件按具名完整函数/文件合同切分，不把前101行当完整body。优先B09资源生命周期及地图READY/取消/失败，第二批B10召唤、特殊怪物和预算。

| Batch | Responsibility | Files | Named callables | Assigned lines | Status |
|---|---|---:|---:|---:|---|
| B09 | 01_resource_ready (1/1) | 15 | 319 | 8224 | NOT_RUN |
| B10 | 02_summon_special_budget (1/1) | 6 | 290 | 6142 | NOT_RUN |
| B11 | 03_enemy_spatial_remaining (1/2) | 40 | 680 | 14996 | NOT_RUN |
| B12 | 03_enemy_spatial_remaining (2/2) | 2 | 28 | 691 | NOT_RUN |
| B13 | 04_combat_skill_status (1/1) | 49 | 498 | 12112 | NOT_RUN |
| B14 | 05_death_loot_equipment (1/1) | 34 | 465 | 7233 | NOT_RUN |
| B15 | 06_save_catalog_player_remaining (1/3) | 5 | 519 | 14847 | NOT_RUN |
| B16 | 06_save_catalog_player_remaining (2/3) | 6 | 617 | 14922 | NOT_RUN |
| B17 | 06_save_catalog_player_remaining (3/3) | 5 | 84 | 1793 | NOT_RUN |
| B18 | 07_maps_editor_environment (1/2) | 37 | 654 | 14992 | NOT_RUN |
| B19 | 07_maps_editor_environment (2/2) | 31 | 295 | 6873 | NOT_RUN |
| B20 | 08_audio_ui_input (1/1) | 29 | 610 | 12040 | NOT_RUN |
| B21 | 09_feature_architecture (1/1) | 40 | 336 | 5221 | NOT_RUN |
| B22 | 10_other_production_contracts (1/1) | 12 | 126 | 1952 | NOT_RUN |
| B23 | 11_authoring_release_tools (1/4) | 38 | 301 | 14981 | NOT_RUN |
| B24 | 11_authoring_release_tools (2/4) | 40 | 336 | 14988 | NOT_RUN |
| B25 | 11_authoring_release_tools (3/4) | 43 | 389 | 14999 | NOT_RUN |
| B26 | 11_authoring_release_tools (4/4) | 47 | 261 | 10404 | NOT_RUN |
| B27 | 12_unclassified_production (1/2) | 58 | 734 | 14997 | NOT_RUN |
| B28 | 12_unclassified_production (2/2) | 13 | 277 | 5118 | NOT_RUN |

后续批只做固定-source精细语义职责。device/GPU/FPS、crash durability、ID127掉落和复活冷却等产品或平台边界保留到对应责任决策，不通过重复PC测试/索引计数闭合。

## B09 exact source assignment

B09指定15个源码路径、319个具名函数责任单元、8224行。已证body的单元只补跨caller责任，不重新读未变body。轻量可派发清单为 `outputs/b09_residual_audit_plan_20261010/batches/B09.json`；第二批为 `batches/B10.json`，后续B11–B28各有独立JSON。完整逐函数与现有证据引用另见 `BATCH_PLAN.json` 和 `B09_DISPATCH.md`，读取JSON时结构化选择批次，不批量打开完整大文件。

| Source path | File lines/functions | Assigned lines/functions | Named bodies reused | Existing evidence |
|---|---|---|---:|---|
| `project.godot` | 85/0 | 85/0 | 0 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scenes/main.tscn` | 7/0 | 7/0 | 0 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json |
| `scripts/character_select.gd` | 1089/51 | 243/5 | 10 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B02/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B02_followup/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/features/compilation/android_export_representation_verifier.gd` | 155/9 | 155/9 | 0 | docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/compilation/code_preparation_envelope_guard.gd` | 398/19 | 398/19 | 0 | docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/compilation/feature_resource_registry.gd` | 125/8 | 125/8 | 0 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/contracts/feature_resource_lease.gd` | 152/13 | 152/13 | 0 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/contracts/loading_preparation_scope.gd` | 67/5 | 67/5 | 0 | docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/runtime/code_input_acquisition_quantum.gd` | 42/2 | 42/2 | 0 | docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json |
| `scripts/features/runtime/feature_resource_preparation.gd` | 898/43 | 898/43 | 0 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/game_root.gd` | 15974/495 | 2014/27 | 10 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B03/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B04/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B05/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/loading_transition_overlay.gd` | 475/23 | 475/23 | 0 | docs/review/full_project_audit_v109_20261009/external/B05/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/monster_visual_streaming_coordinator.gd` | 1769/81 | 1769/81 | 6 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B03/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/startup_loading.gd` | 906/34 | 906/34 | 1 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B05/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |
| `scripts/world_bootstrap_coordinator.gd` | 888/50 | 888/50 | 50 | docs/review/full_project_audit_v109_20261009/external/B01/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B07A/COVERAGE.json; docs/review/full_project_audit_v109_20261009/external/B08/COVERAGE.json |

重审原因按函数单列：无语义body证据；旧body变化；旧body未变但caller/常量/owner变化；旧报告仅部分责任或101行；imports/constants/signal/scene合同未被具名body证明。已匹配且相关边界未变的事实只引用，不要求重复审查或重跑native。

B09必须追实际GameRoot地图切换/初始启动/失败/退出/旧代际回调，以及character selection与Loading调用者；资源lease/registry/preparation/retired claim的READY、fail、cancel、重复、外部退出和threaded get责任不按声明推断。完整固定-source引用索引在 `B09_CALLER_REFERENCE_INDEX.json`，它自身是索引，不是调用链审完。

## Required output and remaining objects

每批返回逐文件/逐函数实际读取状态、固定SHA/行区间/producer消费者、正式入口/状态owner、正常/错误/内外取消/重入/清理分支、findings和未审责任。生产修改另经主控授权集成；新测试只由新源码/依赖变化、失败修复、证据缺失或不同平台要求触发。

`UNCLASSIFIED_AND_DEFERRED.json`完整列出2个退役对象、117个原residual路径、未纳入关键清单的工具角色，以及assets/map_editor_workspace的data/art/authoring责任；未读记录/像素、6083素材和3279测试库存都不能算精细语义完成。新增post-dbb1模式事务8路径（包括 equipment_rules.gd）及其他局部修复须在owner冻结后另做delta review，不能冒称已被B08固定源覆盖。

`SOURCE_FUNCTION_INVENTORY.json`列每个固定源的Git blob、SHA256、行/函数数；`FUNCTION_RESPONSIBILITY_LEDGER.json`列所有具名函数实际旧证据匹配结果；`EVIDENCE_BINDING.json`保存输入指纹、B08接收一致性、22个旧gap与B08的31个剩余closure row。`SUMMARY.json`记录主HEAD/index前后不变和本计划范围。

MAIN HEAD/index保全：`215f0b2f651a51e6855ee813ddd99221690311a1` / `ddacea4eed570faed0a6003c87352552e74e902874b5dee61d8863a2316e29d7`。只写本次独占outputs目录与本文件；未改生产、旧报告、真实数据。


B09中WorldBootstrap等已证固定函数体保持复用，同时保留独立cross-edge followup单元，只补B08保留的READY/fail/cancel/retirement消费者责任，不因body已读而宣称调用链闭合。`CROSS_BATCH_ASSIGNMENT.json`把B08的31个剩余责任逐项映射计划批次，未映射的产品/平台/非code对象显式保留，不因分配到批次而闭合。

## Successor SHA rebind entrypoint

新GPT批以主控稍后冻结的新review SHA为准；本文件和 B09–B28 JSON继续作为 dbb1bd 责任基线。固定新 SHA 后执行：

```powershell
python -B outputs/b09_residual_audit_plan_20261010/rebind_b09.py --new-ref <NEW_FIXED_REVIEW_SHA>
```

入口只读Git对象，比较 dbb1bd 与新 SHA 的路径元数据；对未变B09文件复用blob与行号，只读取发生变化的B09源码和上述8个mode/admission owner路径。startup_loading.gd强制whole-file refresh，新prepared_content_configuration.gd整文件负责；其他新owner逐个纳入changed/new body与已定位receiver/authority调用边界，旧body证据保持原SHA/范围，不冒充新caller闭合。未预期路径差异、丢失或重名函数会列MISSING，不能静默排除。

结果写入独占新目录 `outputs/b09_residual_audit_plan_20261010/rebound/<NEW_SHA_12>/`，包括 SOURCE_BINDING.json、B09_REBOUND.json、必要的 B09_OWNER_FOLLOWUP_n.json、B09_DISPATCH.md 和 REBIND_RESULT.json；若目标已存在即停止。每包最多15000行，超过上限明确拆包，不缩短函数或扩大上限。新owner消费者词法索引仍须GPT沿真实调用链确认；rebind本身不宣称生产PASS。

当前仅完成入口语法与--help验证；新SHA尚未冻结，实际rebind为NOT_RUN。Native61/62属于主控并行验证状态，不作为本次计划或未来新SHA审查已完成的证据。
