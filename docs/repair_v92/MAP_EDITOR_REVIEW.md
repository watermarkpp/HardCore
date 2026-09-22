# v92 地图、发布器与有界冗余复核

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

日期：2026-09-22。审查起点：`codex/integration @ b961cedff8040c9fc81534e094241ad9fa2330ad`，工作树含主控正在进行的未提交修改。`tools/agent_bootstrap.ps1 -Compact` 返回 `PASS`；`protected_changed=true` 已按现场保留。本文行号对应本轮审查现场，后续主控修改可能移动行号。

范围：地图 READY 合同、同图世界复用、墙体派生发布与正式加载绑定、苍月岛入口/相机调用链，以及指定旧掉落 helper 的引用。未扫描缓存、二进制目录或无关历史报告。子任务仅写本报告与新增 `tests/wall_render_publisher_snapshot_test.gd/.tscn`，未改生产文件、人工地图、注册表、掉落数据；未启动任何 Godot 进程、未 stage/commit/push。生产修正和测试裁决由主控承担。

## 1. 同图 READY 回归：生产缺陷，主控已接管修正

发现时状态：`FAIL`。现有 `outputs/test_logs/map_transition_input_lock_test.stdout.log` 先记录初始世界 `planned_actors=94, spawned_actors=94`，随后反复记录 `ready_contract_failed → post_arrival_safe_home → safe-home recovery transition started`。测试尾部 PASS 标记不能覆盖这些引擎/流程失败。

直接原因是两个生命周期被混用：

- `game_root.gd::_begin_map_transition` 每次调用 `WorldBootstrapCoordinator.begin_map_transition`；`world_bootstrap_coordinator.gd:119–163` 提升构建 generation 并清空计划/生成/延期 actor 统计。
- `game_root.gd::_load_zone` 在同 zone、同 map、非初次加载时直接返回，合法保留现有 actor 和 `_zone_generation`。真实 `travel_to_service_home → _travel_to_service_home_immediate`、同图 `_teleport_to_map_immediate`、死亡回城都会走到此分支。
- 本轮原先新增的 `declares_content && planned_actors <= 0` 门禁没有区分保留世界，因而拒绝合法同图操作。比奇安全回城再次命中相同分支，解释了连续恢复循环。只改 noop fixture 会留下实际生产缺陷。

主控修正采用最近成功 READY 的 `(map_id, _zone_generation)` 凭证。当前现场 `game_root.gd:228–229` 保存身份，`:3607–3608` 在真正成功 finish 前记录，`:3963–3967` 仅允许同一已就绪世界拥有零新增计划。换图 `_load_zone` 先提升 `_zone_generation`，因此旧凭证不能批准新地图。全部 `zone_content` 批量销毁与 enemy/boss cache 全清仅位于这一 generation 提升之后；本次有界纯符号搜索未发现另一条不提升 generation 的全世界 actor 清理路径。普通死亡、拾取、特效结束不应撤销整个世界的就绪凭证。

复核结论：上述身份边界与当前生产生命周期一致；同图也仍检查 projection、map/collision 计数、actor 失败/重复数、同步加载、玩家位置、camera 和 HUD。新增世界仍须满足 `planned = spawned + deferred`。不可用任意旧 `zone_content` 节点、单独 target/current map 相等或恢复次数限制替代这一边界。

最窄验证：`map_transition_input_lock_test`；真实同图 home/传送/复活；`monster_same_map_residency_test` 的真实比奇别名、town button 复活、跨图 visual generation fence；以及 boss-only 延期刷新场景。子任务执行状态：`NOT_RUN`，由主控串行运行。

## 2. Boss 延期计数复核

`game_root.gd:4718–4742` 先检查真实生成错误，再以 `enemy != null` 区分 materialized 与 deferred。持久化死亡记录尚未到期时，`:4935–4958` 正式安排 `_respawn_later` 并返回空 actor；`world_bootstrap_coordinator.gd:615–621` 计为成功 deferred，而非失败。非法怪物、投影、稳定 slot 或 respawn policy 都先设置真实错误，不能混入合法延期。

因此 boss-only 地图在等待刷新期间可以没有活节点，但其计划仍完成。按当前 generation 的计划合同判断，优于 SceneTree 全局组计数；后者还可能包括 queued 的上一张地图节点。没有建议改动人工 spawn、等待期限、身份或刷新节拍。

## 3. Publisher 遗漏冻结素材快照：确定的权威错位

发现时状态：`FAIL`。共享 service 提取前后的实现均调用单参数 `sorted_draw_commands(instances)`；正式 `world_background.gd:1411–1415` 则传入 `runtime.visual_asset_snapshot`。`polygon/poly_visual_snapshot.gd:64–76` 明确规定：非空已发布快照不得回退当前 catalog。只读盘点确认 60/60 已优化地图均带此快照。

确定触发：已发布地图未重建，当前素材 catalog 的墙体 `render_parts.anchor` 等字段后来发生变化，再重发该地图派生 plan。旧发布器按新 catalog 编译并宣告成功；真实运行时按旧冻结 snapshot 生成命令，随后以 `commands digest mismatch` 拒绝计划并退回整图 LEGACY。runtime JSON 与原 PNG 字节都可完全不变，因此纯文件哈希门禁不足以识别这一命令漂移。

额外发现：原 `tests/wall_render_binding_test.gd` 同样遗漏 snapshot 参数，可能与发布器出现同错对消，不能单凭此前 60 PASS 认定模拟了真实消费者。

主控已将共享 service `:63–65` 与现有 binding test 同步改为传正式快照，并提供 `plan_directory/store_directory/staging_directory` 三个可配置输出目录，默认路径保持正式发布位置。主控生产代码不在本子任务修改范围内。

本子任务新增真实回归：`tests/wall_render_publisher_snapshot_test.gd/.tscn`。

1. 只读现有 `bich_corpse_king_hall` runtime，运行完整真实 `publish_map`，输出全在 `outputs/test_logs/wall_render_publisher_snapshot_<pid>_<ticks>/`。
2. 仅替换内存 catalog 中 `cave_granite_straight_x_l3_v03` 的深复制记录，改变第一墙体 part 的 anchor；负对照要求旧单参数命令摘要确实变化。
3. 同时要求冻结 snapshot 的命令摘要保持一致；再次完整发布后，最终 plan 字节与 PNG 文件集合必须完全相同，且 plan 绑定精确 runtime SHA。
4. 恢复原内存记录；仅删除本测试所有的三个已知平面目录及其精确父目录。检查 runtime、人工 editor、registry、正式 plan、原正式派生 PNG 和 source PNG 的哈希均未变化。

测试状态：`NOT_RUN`，未启动 Godot。待主控处理 tracked-path 门禁后运行：

```powershell
tools/run_godot_tests.ps1 -TestPaths tests/wall_render_publisher_snapshot_test.tscn -TimeoutSeconds 30
```

静态检查：新增两文件无行尾空格；本子任务 `git diff --check` 无输出。因为新文件尚未 stage，该 Git 检查不替代它们的解析或行为执行。

## 4. 编辑器发布链、PNG 语义与打包门禁

当前只读文件绑定检查状态：`PASS`。

```text
tools/verify_wall_render_bindings.ps1 -ProjectRoot .
WALL_RENDER_BUILD_BINDINGS_PASS maps=60 unique_files=867
```

编辑器 `map_editor_app.gd:2317–2329` 先执行正式 runtime/registry 事务，成功后才在 `:2336–2343` 对已有优化计划调用共享 publisher。派生失败会明确显示“地图已发布；优化渲染构建失败”，不把已成功的地图发布误报成整体回滚。此时旧计划保留，但严格 runtime SHA 门禁会拒绝它；正式打包前哈希检查会阻止将 stale 计划静默打入包。

`tools/build_android_isolated.ps1:322` 对实际 `$StageProjectPath` 执行验证，位于隔离树 import/export 前；检查对象不是仅主树。`.gitattributes` 已规定 runtime/plan JSON 为 LF，避免新检出树因换行转换改变原始字节 SHA。

共享 publisher 保持 Godot 导入像素语义，`_load_image` 仍走 `ResourceLoader.load(..., CACHE_MODE_IGNORE)`，没有退回 raw PNG 解码。导入结果与原图字节可能不完全相同，不能为图像读取便利改动这一语义。

消费者仍保留整图 LEGACY 的严格拒绝路径，运行时不要求 APK 中保留 raw PNG。不要把构建侧 source/png 哈希检查强行搬进 runtime，或通过放松 source/runtime 绑定去“恢复优化”。

尚未证明的边界：脚本只盘点当前存在的 plan；固定 60 张覆盖由正式 binding test 承担。其他 CLI 地图发布工具仍需按正式流程重发派生计划，打包 gate 会发现漏做。没有为补齐这些边界批量修改冻结人工资源。

## 5. 苍月岛入口与相机

本子任务未取得新的实机复现，`DEVICE TEST: NOT_RUN`，不能把原“回退比奇”投诉归因于相机。

静态确认：`MapTeleportRuntimePolicy` 对 910007 使用稳定 `map.respawn.default`，`resolve_arrival` 从正式 `respawn_points` 选择；苍月 runtime 为 48×48，默认出生/复活点 `[25,24]`，位于已发布安全区内部。`_teleport_to_map_immediate` 与 `_begin_map_transition` 的目标地图均保持请求的 910007，没有把相机中心当地图身份或 Home 权威。

`_update_world_camera_constraint` 只根据当前 runtime/design、玩家位置和已冻结画面范围设置 camera zoom/position，不调用转图或安全回城。回退比奇由失败转图恢复链拥有。现有 `formal_map_destination_regression_test` 确实调用真实城市复活点操作，并支持 `HARDCORE_V92_PRODUCTION_LOADING=1` 的异步路径，覆盖 910007/910003/910005/910006/910001；执行证据由主控汇总。

后续实机仍复现时，最窄证据应包括请求目标、实际地图、READY/FAILED reason、generation、actor 计划与 materialized/deferred，以及精确安装包/补丁身份。当前无证据支持改相机合同、人工坐标、出生点或添延迟重试。

## 6. 有界冗余与净化候选

搜索覆盖指定生产 service、`scripts/`、`tests/`、`tools/` 的 GDScript/脚本/资源文本，并以纯符号搜索包含动态 `call/has_method` 引用。没有把 docs 的旧路径当生产调用，也没有删除任何文件。

| 对象 | 确定引用证据 | 分类与动作边界 |
| --- | --- | --- |
| 共享 publisher 与 CLI | 提取体机器 diff 最初仅新增 map-key 校验、每图 image cache 清空、`CACHE_MODE_IGNORE`；现有 CLI 仅负责参数、循环和报告 | 必须保留，两入口共享一个实际算法。未发现仍然复制的发布算法；不建议再把运行时验证与构建验证合并 |
| `_user_balance`，原 loot service `:42` | 原生产 profile/probability 只用 sheet provider；直接 `_user_balance` 消费仅 `progression_loot_20260913/drop_balance_test` 与 `loot_ui_20260914/runtime_followup_test` | 可从生产 autoload 摘除，但先迁移历史测试依赖；不能连带删除 ledger/证据。初始化会读取 314,818 字节 v80 ledger 并核验 5 个 source bindings；未做性能计时，不宣称具体收益 |
| 五个旧倍率 helper，原 `loot_runtime_service.gd:531–650` | `_apply_drop_probability_policy`、`_apply_small_monster_probability_policy`、`_apply_denominator_multiplier`、`_drop_denominator_multiplier`、`_small_monster_denominator_multiplier` 仅互调与三份历史测试调用 | 可从生产摘除并保留独立历史 fixture。`loot_runtime_item_policy_test` 仍在正式 runner，里面真实 sheet/no-multiplier 断言必须保留，不能整文件删掉 |
| `_user_additions` | `_production_reward :104–105` 调 `owns/reward`；`_drop_output_item_record :434` 调 `item_identity(110)` | 必须保留现用身份路径；命运之刃稳定 ID 110 仍真实生产消费，不是整个 v81 文件都已退役 |
| `_chance_denominator`，原 `:874` | `tools/monster_drop_p1a_runtime_export.gd:81,831` 使用动态 `has_method/call`；`tests/monster_drop_p1a_runtime_contract_test.gd:30,121,196` 也直接验证动态入口 | 必须保留。初次仅查 `name(` 的候选判断已纠正；该函数不是死代码，不得删除 |
| v80/v81 原始脚本、ledger、seal 与生成工具 | `tools/build_drop_balance_v80.py:10–11`；`tools/loot_sheet_compiler/evidence/SOURCE_BINDINGS.json:10–12` 固定历史 Git blob | 保留来源证据与历史重现材料。退出当前概率链不意味着允许删除原始权威/审计材料 |

净化实施由主控串行处理，本报告不宣称整个项目已经净化或全仓冗余审计完成。稳定 ID、地图/掉落人工数据、source-priority、冻结碰撞与相机合同均无本子任务改动。

## 7. 本子任务验证边界

- `PASS`：bootstrap；现有 60 plan/867 文件构建侧哈希；函数及动态引用复核；新增测试文件空白检查。
- `FAIL`：发现时的同图 READY 回归和 snapshot 权威错位，均已交主控修正；最终 runtime 复验结果由主控填写交付证据。
- `NOT_RUN`：本子任务全部 Godot/Android/设备验证；新 snapshot 回归待主控串行运行。
- 未创建提交。最终构建源 SHA、critical 结果、APK 版本/路径/哈希不属于本报告的独立验收结论。
