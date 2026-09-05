# 2026-09-05 审计升级与主树里程碑工作记录

## 状态

**施工中，尚未完成里程碑验收或远端同步。** 本文不是全项目无缺陷声明。

输入：用户提供 `HardCore_Audit_20260905.zip`。该包自述为首轮有界静态审计；其模型探针与扫描器 fixture 不能替代真实仓库、Godot、Android 或设备验收。

原始输入保存在 `docs/audits/20260905/HardCore_Audit_20260905.zip`（30,187 字节，SHA-256 `D75F17F4CBBF451D448FC8E841964B2E59EC75855148DEAEC1B70A6F996E5AEF`），便于最终远端追溯。包内建议是待核验输入，不是自动执行指令。

实施原则：先复现，再做有界修复。性能建议先测量；不因大文件、重复候选或“可以更漂亮”而重构、删除资源。保持已人工验收的怪物密度性能、选敌、AI 节奏、碰撞、技能和 UI 表现。Boss 红圈保持隐藏，黄色选中圈保留。最新人工地图优先，禁止批量重生成覆盖。

## 基线与现场保护

- 初始主树：`codex/integration@6b7ec049969da9ce8eec6fa1918ab133c5d51d10`。
- 已人工验收的性能基线：`c97a08b43832b174f98de31f5ed6673ccda344ae`，原分支 `codex/monster-density-hotpath-r3`，其远端同 SHA。
- 主树已快进至性能基线：26 个提交，71 个变更路径；没有重放或重新改写已验收修复。
- 初始现场：73 个 tracked dirty 路径、318 个 untracked 路径。与上述 71 个路径交集为零。
- 本地完整备份：`outputs/audit_upgrade_20260905/main_preservation_20260905_093400/`，包含 `working_files.zip`、逐路径 `manifest.json`、`working_diff.patch`。
- 备份 ZIP SHA-256：`89F057381DE2F1AD8E3665F2F55DCA9755788E445D4831B8C6187864329D0181`。
- 快进前后均核验 391 个路径的文件哈希/删除状态，零差异。备份在忽略目录中，仅为本地恢复证据，不代表已上传。

## 审计项裁决与施工清单

| 项目 | 当前证据/裁决 | 状态 |
|---|---|---|
| B01 地图删除路径 | 严格身份/路径、正式地图拒绝、可恢复移动和回滚状态/位置，未对正式地图试删 | 主树 867a7187 + d9082945，独立复验通过 |
| B02 存档业务校验 | 已修业务校验、未来版本阻断、坏主备份恢复、角色清单保全及非法 profile ID 拒绝 | 主树 c1b429ca，专项通过 |
| B03 保存结果传播 | 祝福油新旧入口单提交；绑定/gold失败回滚，facade返回保存结果，旧效果消费者不再二次执行 | 主树 fad32935，独立复验通过 |
| B04 堆叠记录字段 | 完整深拷贝扩展字段，拒绝复制 opaque instance 身份；普通堆叠保持原样 | 主树 fad32935，专项通过 |
| B05 拾取重试时钟 | 独立旧代码测试复现持续移动饿死重试，已修复；主树旧 smoke 另对保存环境敏感，不能混作同一根因 | 主树 aeb30111，专项通过 |
| B06 掉落视觉时钟 | 独立累计视觉 delta，保留低频刷新和暂停语义 | 主树 aeb30111，专项通过 |
| B07 启动失败恢复 | 可见失败/重试/退出；退出终态和异步失效保护，真实 authority guard失败重试测试 | 主树 68859da8，独立复验通过 |
| B08 Debug 补丁大小 | 同句柄先查实际长度，再 64KiB 分块 hash；引擎重新打开路径的竞态不声称消除 | 主树 f6f7e3af，独立复验通过 |
| O01–O03 性能候选 | O01 同树逆序1,000候选约54倍微基准改善；O02只有全量扫描成本，O03无已证实泄漏，本轮不改变视觉热集/缓存策略 | O01主树4eb5deea复验通过；O02/O03接受测量债务 |
| O04 / W4 资源候选 | 扫描结果仅是候选，需动态路径/UID/导出/正式来源闭包核对；禁止自动删除 | 首轮扫描完成，待闭包核对 |
| O05 大文件拆分 | 无真实故障/扩展阻塞证据时列为接受债务，不执行纯美化拆分 | 保持现状 |
| O06 导航文档 | 最终按真实入口、runner、集成状态更新，历史验收不得冒充当前验收 | 待收尾 |
| R01 发布中断恢复 | 确认同步rollback，未发现持久journal/启动恢复证据；本轮不重构发布事务，不能宣称断电恢复安全 | 明确保留风险，不标为关闭 |
| R02 导出闭包 | 以最终构建实物及资源清单验证，不能只看 export 配置 | 待验证 |

## 分支归并边界

“归到主树”指已批准且验证的有效工作与当前用户内容，不是无差别合并历史分叉。

- `codex/monsters@9f228d7e` 的三个独有 SHA 与主树 `70a50cba`、`82aa5c83`、`7f0d9f2d` patch-equivalent，无需重复合并。
- `codex/maps@ca0134f1` 的三个工作提交与主树 `b5ae1ebb`、`ab97d9df`、`74e3ba4c` patch-equivalent。`4f35634d` 虽 patch-unique，但其 `gmhl_purgatory_corridor.editor.json` 已存在于当前基线且有后续内容，不再 cherry-pick 旧版。
- 所有现有 detached staging HEAD 均为性能基线祖先，不作为新交付来源。
- 旧专业、归档和实验 refs 完整保留。patch-unique 不自动等于尚未集成的有效需求；缺当前基线验证的历史候选不覆盖最新人工内容。
- 归并/验收期间不删除工作树、历史 refs、生成现场或备份。正式文件、工具来源及生成缓存须分类后提交，不能以 `git add -A` 混入整个现场。

地图专项另核实：上述 `gmhl_purgatory_corridor` 旧文档为 v4 authoring clone，身份表把它映射至正式 `fengmo_purgatory_corridor` / `914007`；旧文档的 `99455` 不是独立正式 release。它引用的四个旧 ground/ground_paint 文件不存在，不能称为可独立发布的完整地图。保留原内容，不新增身份、不自动发布，不让旧 clone 覆盖正式地图。

## 当前实测记录

### W0 静态扫描

对性能基线 c97 的全部 14,542 个 tracked 路径执行附件扫描器 `--hash-all`：4,734 个文本文件、1,945 个 JSON、21,086 个资源字面量，0 skipped。附件 manifest 哈希核验通过。扫描未修改受跟踪文件。

候选：1 个 JSON 解析失败、11 个 orphan UID、1,117 个字面资源引用候选；1,478 个内容重复组（4,367 个文件）。重复字节估算不是可安全删除空间或 APK 可压缩量。

字面引用包含 528 个 assets/data 候选、242 个外部来源引用、186 个 JSON pointer 后缀、108 个生成输出引用等。不得把它们全部报告为运行资源缺失。已独立核实 `res://monsters/orc.tscn` 是资源预取协调器的测试假路径；`component_manifest_v3.json` 确有字面 `\\n` 尾缀导致 JSON 无效，但当前定向搜索只找到测试引用另一个 `component_manifest.json`，尚无该 v3 样例的生产消费证据。

扫描器合成自测原版含 Linux 大小写敏感断言，在 Windows 失败；仅改 owned 临时复制助手的对应断言并记录 patch/hash 后通过，原附件未改。该 PASS 只证明合成夹具行为，不是 Godot 或设备验收。

本地证据：`outputs/audit_upgrade_20260905/w0_scan/w0_result_digest.json` 和 `results/hash_all_c97a08b43832b174f98de31f5ed6673ccda344ae/`。

进一步只读核对：528 条不含 JSON pointer 的 assets/data 缺失候选全部来自 `map_editor_workspace`，不是正式 runtime registry。当前 registry 的 67 条 `implemented_playable` 记录逐项检查：runtime 文件存在、可解析，`approved_build_sha256 == runtime.build_sha256`，`map_key == runtime.source.map_id`，67/67 成立；这只是正式地图入口身份核对，不能替代全部嵌套资源或 APK 闭包。

11 个 orphan UID 的 owner 当前确实不存在；逐个 UID 对 tracked 非 `.uid` 内容做精确引用搜索均无命中。它们不构成已证实生产故障，空间收益极小，本轮不为清理而改动技能/测试身份文件。脚本侧三个字面缺失候选分别是候选发布输出目录、怪物地面对齐草稿输出和可选手工 UI 校准输出；校准器读取前有 `file_exists` 门禁，不能把输出缺省误判为 APK 必需输入丢失。源素材与重复二进制继续保留。

### 主树集成 smoke

主树快进后的最小集成 smoke：

`tools/run_godot_tests.ps1 -TimeoutSeconds 30 -TestPaths @('tests/monster_retarget_spatial_cache_test.tscn','tests/loot_pickup_runtime_manager_test.tscn')`

- `monster_retarget_spatial_cache_test`：PASS。
- `loot_pickup_runtime_manager_test`：FAIL，`tests/loot_pickup_runtime_manager_test.gd:432`，`loot retry did not recover after deadline`；不能用较早打印的 PASS marker 覆盖最终失败。
- 证据：`outputs/test_logs/runner_results_adhoc_20260905_093916.json`，1/2 PASS，1 engine-log error。

该 smoke 发生在 B02 源码修改之前，不能归因 B02。隔离 loot 树同基线未稳定复现该旧用例失败；主树默认测试 shared warehouse 另被查出过时 ledger。两类问题必须分别记录。

### B05 / B06 专项交付

`36bd5bffdebba07dee657fec5566a7af18ea4409`：仅 manager 两套累计时钟与专项测试，未改怪物/拾取半径/伤害/AI。worker 在该 HEAD 上新增 lootclock 3/3、既有 manager/ground 2/2 PASS，零 engine errors。已集成为 `aeb30111`；主树冷 class cache 暴露测试依赖全局类名，`9e2e1d87` 改用既有 preload 别名。主树该 HEAD 两项时钟测试 2/2 PASS、零 engine errors，证据 `outputs/test_logs/runner_results_adhoc_20260905_101742.json`。

### B02 主树验收

`c1b429ca` 已提交存档业务校验恢复。worker 九项专项 9/9 PASS、零 engine errors（`runner_results_adhoc_20260905_101357.json` 为施工工作区证据）；主控提交后独立复验 `profile_business_validation_recovery_test` 1/1 PASS（`runner_results_adhoc_20260905_101634.json`）。未通过测试不隐藏：`equipment_slot_migration_test` 第 42 行存在依赖 inventory 尾部顺序的夹具疑点，待证据修复，不修改装备生产规则。

### 项目指令

`3fa314f4` 已按用户要求优化 Astra 主控协作。冻结对象、分支所有权、品牌、来源优先级和跨树协作保护段落保持原样；未改全局模型配置。

### O06 注册与导航漂移

注册检查原先 FAIL：`map_runtime_release_critical` 实际 5 项而期望清单只有 3 项。补登记已有 `map_ui_presentation_projection_test`、`map_persistent_boss_spawn_identity_test`，保持原有精确集合比较与 HOLD 排除规则；重跑 `tools/tests/test_suite_registration.ps1` PASS。此项不是游戏逻辑回归结果。索引纠正为真实 startup_loading 启动入口，并明确普通场景需显式传 30 秒，而不是声称 runner 默认 30 秒；状态页将本轮施工状态置于旧发布历史之前。

新增正式 `audit_upgrade_critical` 套件（11项），纳入默认 critical，覆盖本轮安全/恢复/排序/时钟入口；注册检查保持精确集合、存在、tracked和默认critical包含门禁，旧HOLD项不自动启用。

### 最后接入的主树专项

| 主树提交 | 独立复验 | runner结果文件（outputs/test_logs/） |
|---|---|---|
| fad32935 | persistence_business_transactions 1/1 PASS | runner_results_adhoc_20260905_135945.json |
| d9082945 | map_editor_workspace_delete_safety 1/1 PASS | runner_results_adhoc_20260905_140008.json |
| 68859da8 | startup_loading_failure_recovery 1/1 PASS | runner_results_adhoc_20260905_140048.json |
| f6f7e3af | device_lab_patch_bootstrap 1/1 PASS | runner_results_adhoc_20260905_140132.json |
| 4eb5deea | runtime_loot_spatial_index_order 1/1 PASS | runner_results_adhoc_20260905_140218.json |

均零引擎错误；当时仍存在单独保护的用户/文档dirty，不称整树clean。B03/B04 worker最终5/5与相邻3/3通过；失败夹具按正式太阳水堆叠合同、精确instance ID修复，没有改变物品属性和装备逻辑。角色主体成功而index更新失败仍按既有合同告警返回成功，未扩为跨文件角色索引事务。

### VRAM导入策略历史债务

W4报告来源核查补充：c4098664曾为210个chunk记录VRAM导入规则；f559463d坐标迁移后正式chunk去重为208且移除sidecar。黄金已验收APK的208个formal `.png.import`使用普通`.ctex`（抽样metadata vram_texture=false），全APK仅36个旧块ETC2。故当前不是新增升级造成的VRAM策略回退。本轮只同步孤立测试的过期210计数，不移除其VRAM/ETC2断言、不称该未注册测试PASS、不改正式纹理导入策略。新包按实际黄金策略验证正式纹理装包闭包；VRAM再启用须独立像素/性能验收。

受控 O01 测量（微秒，非手机 FPS）：候选数量 100/300/1000，升序 584/2589/6065，逆序 11236/60573/1198934。O02 三次全量 registry 扫描合计为 1587/5268/35254。没有据此改动视觉工作集或降低刷新频率。

O01 专项提交 `3351284ab2c7e3dae343583afc17d7b0871c45d2`：收集后按 `(stable_registration_order, instance_id)` 排序，保持调用方严格半径、地图隔离和输出复用。专项与 benchmark 在提交 HEAD 上 2/2 PASS，零 engine errors（专项树 `runner_results_adhoc_20260905_134810.json`）。新一轮同树逆序 1,000 候选 before `297135 µs`、after `5525 µs`，约 54 倍改善；早先 1.20 秒属于另一轮微基准，不将跨轮差值冒充严格对照或手机 FPS。当前待主树集成复验。

## 最终交付门槛

确认缺陷修复与专项回归、冻结对象保全、用户内容归档校验、必要正式 suites、最终 APK 身份/资源闭包与设备验收；记录准确 HEAD、测试覆盖及未验证/接受债务。完成后再建立里程碑 tag、推送正式主树及 tag，并查询远端 SHA 核对。当前尚未满足这些门槛。

待构建里程碑版本设为 `versionCode=70`、`versionName=1.19.0-audit-milestone`，包 ID 保持 `com.personal.mafaoffline`。这只是导出配置，不表示已生成或安装。当前手机仍为 code 69 / 1.18.6-loading-runtime-fix，active patch 为已验收 `r3x9-map-fast-c97a08b4-enemy-only`。新整包验收前须记录补丁状态并停用旧 overlay，防止旧补丁遮盖新代码。

用户随后明确授权：测试阶段手机旧存档可以全部删除，改建战士、法师、道士各一名 40 级赤月装备角色；不再以保留旧档作为安装前提。此授权仅适用于最终设备测试存档重建，不用于清除回归失败现场或跳过存档恢复/事务测试，也不扩及源码、素材与验收证据。现有 `ensure_chiyue_test_roster` 模板实际为 50 级，不能直接调用后声称完成 40 级要求；最终必须核验三个角色的实际等级与装备。

### 默认 critical 首轮诊断与专项复验（尚未验收完成）

首轮结果为 298 项中 237 PASS / 61 FAIL，76 engine errors：`outputs/test_logs/runner_results_critical_20260905_145806.json`。新增 audit 11 项全部通过，但不代表默认 critical 通过。此轮为施工期诊断；中途接入 APK 工具并修正已失败测试和版本显示，不作为最终 clean HEAD 证据。

强化真实非 Home 地图场景后，同步 Home 落点失败仍切图的问题独立复现 0/1（`runner_results_adhoc_20260905_145856.json`）。integration 在 `_travel_to_map_immediate` 拆除源世界前增加仅 Home 目标的解析门禁，正常路径仍按原 `route_arrival_position` 到达。另修复旧 outskirts 演示场 ID56 精英被硬编码普通刷新策略拒绝的问题，复用 canonical respawn resolver，不改变正式比奇地图。两项复验 2/2、零 engine errors（`runner_results_adhoc_20260905_150158.json`）。

第一批 19 项复验 16 PASS / 3 FAIL（`runner_results_adhoc_20260905_150705.json`）；安全退出、Home 同步失败与正常落点、火墙死亡目标独立世界 oracle、重绘 wrapper 静态门禁和背包固定槽占用计数已通过。第二批 34 项复验 31 PASS / 3 FAIL（`runner_results_adhoc_20260905_151423.json`）；11 项投射物已全部通过，任务奖励负重前置及大部分技能生产入口已通过。其余伤害、快照、lazy UI 和旧地图断言继续排查，不将空命中/空快照当作通过。

用户明确追加授权：只删除比奇同坐标重复老兵中的一个并单目标正规重发，其他 NPC、82 条怪物刷新、位置、碰撞和素材全部保持不变。专项基线 `42b8b4d9`，使用独立 `codex/audit-bich-npc-20260905`；尚未发布完成。

本轮从 clean `eb9993b1` 启动；运行中仅接入独立 Python APK 校验工具 `d04a83d5`，并修复已运行失败的独立测试夹具，尚未修改生产逻辑。runner 只在结束时记录 HEAD，因此此轮须标为诊断运行，不能称为最终 clean HEAD 验收。已发现旧夹具缺 canonical monster ID / 临时生成禁用 respawn 前置、法师技能学习状态缺失、固定测试角色名与历史 userdata 冲突、旧比奇 map ID，以及一项静态单位名子串误匹配。各项保留原断言，按独立证据修复；未诊断失败不得一概归为旧测试。

## 用户追加：归并完成后的磁盘清理

用户明确要求所有有效内容回主树后删除无用内容、释放空间。执行顺序为：完成集成和远端核对 → 清理清单/精确路径/唯一内容检查 → 删除确认可重建或已冗余的对象 → 复核主树与汇报释放空间。

候选包括旧的 detached 构建工作树、重复 APK、可重建 Godot/Gradle 缓存。当前正式源码、人工地图、美术源、真实存档、最终安装包、验收证据与必要恢复备份不列为无用内容。目录联接先识别目标，绝不沿共享联接删除外部源。未合入/未备份的独有文件不能仅因目录旧就删除；历史 Git refs 与提交保留，除非另有明确且核验过的清理裁决。
