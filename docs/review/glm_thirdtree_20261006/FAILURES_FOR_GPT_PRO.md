# 第三树施工失败全记录（供 GPT Pro 协作解决）

- 基线：`272430b3692e776b25df820eaa8b53ed9f34bd8e`；分支 `codex/glm-thirdtree-continuation-20261006`
- 本记录起点 HEAD：`250b292fa`（S4 完成 + S5 批次 1）；持续更新
- 运行方式：`tools/run_godot_tests.ps1 -TestPaths '<scene>' -TimeoutSeconds N`（console/headless，引擎 4.7.stable.official.5b4e0cb0f）
- 证据目录：`outputs/test_logs/<test_name>.godot.log` + `outputs/test_logs/runner_results_*.json`
- 分类口径：BASELINE_EXISTING（基线同败）/ REGRESSION（基线 PASS 必修）/ FAIL_CHANGED / 未归因
- 注意：Windows ad-hoc 沙盒无 cloud_<id> APPDATA 结构，含正式 APPDATA 断言的测试在 Linux formal 环境才可能 PASS；此类先看断言是否环境性

## 失败清单（按发现顺序）

### F1. tests/hc_monster_combat_r4/natural_cadence_24_test.tscn（同款：24_chase / 76 / 238 / 239）
- 状态：**BASELINE_EXISTING（归因链已闭合到 spawn 准入）**
- 复现：`pwsh -File tools/run_godot_tests.ps1 -TestPaths 'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn' -TimeoutSeconds 90`
- 失败模式：`R4_NATURAL_CADENCE_FAIL: monster=24 ["spawn_failed", "insufficient_starts=0", "insufficient_settlements=0", "foreign_perturbation_missing"] evidence=res://outputs/test_logs/r4_cadence_24.json`
- 超时豁免：场景自声明 `approved_process_window_seconds = 90`；runner 上限 90s 已用满仍 FAIL（非超时）
- 初步根因：`game_root.gd` `_spawn_enemy` → `admit_base` 准入拒绝（`_staged_actor_spawn_failure_reason`，默认 `unpublished_base_spawn`）——怪物未通过真实 map transition 重发布登记进 base 发布计划；测试未适配 P0 发布合同
- 与 F3/F4 同链（spawn 准入家族）

### F2. tests/skill_plan_single_resource_commit_test.tscn
- 状态：**BASELINE_EXISTING（同 spawn 准入家族）**
- 复现：`pwsh -File tools/run_godot_tests.ps1 -TestPaths 'tests/skill_plan_single_resource_commit_test.tscn' -TimeoutSeconds 30`
- 失败模式：`SCRIPT ERROR: Assertion failed: resource commit fixture must use the formal exact-ID mapped spawn`
- 初步根因：fixture 的 spawn 方式未走 formal exact-ID mapped 发布路径——与 F1/F3 同一 P0 发布合同适配缺口
- 待 GPT Pro 复核：fixture 应改用 `tests/helpers/formal_world_skill_fixture.gd` 的 `publish_targets` 还是测试自建发布路径

### F3. tests/framework/natural_sustained_chain_test.tscn + tests/framework/natural_effect_lifecycle_test.tscn
- 状态：**BASELINE_EXISTING（受控实验 5 轮闭合）**
- 失败模式：`_spawn_enemy` 30 次全返 null（targets=0，战斗未开始）→ 基类断言 "all thirty real receivers..." 失败
- 证据：`scripts/game_root.gd` L5113 附近 `admit_base` 拒绝分支；`_collecting_staged_actor_plan` 仅在世界到达阶段（L3568-3572）同步为真，非本因
- 已排除：S3 scene_epoch 机制（HEAD 对照排除）；S1 遗留编译断裂（已修：10 个 validation 模块补 `effects.layered_status` 声明后 state_loan/mixed_delivery(60s)/periodic_boundaries 复验 PASS）

### F4. tests/bich_area_test.tscn
- 状态：**BASELINE_EXISTING（基线内容受控实验同败确认）**
- 复现：`pwsh -File tools/run_godot_tests.ps1 -TestPaths 'tests/bich_area_test.tscn' -TimeoutSeconds 60`
- 失败模式：`SCRIPT ERROR: Assertion failed: 一层编辑器怪物配置未完整加载`
- 诊断数据：`BICH_DIAG enemies=0 expected=40 bootstrap=false transition=false`——travel_to_map(911001) 后敌人**零生成**（不是少几个）
- 基线对照：17 个本任务 feature 文件还原到 272430b36 字节后同败（同 enemies=0）→ 非本任务回归
- 初步根因假设：编辑器权威地图（911001 兽人古墓一层）travel 后的正式 spawn 流在某准入/描述校验处整体拒绝（与 F1-F3 的准入家族疑似同源，但这里是编辑器权威内容也进不来——**值得 GPT Pro 优先看**：正式编辑器内容都被拒，说明发布合同对编辑器权威内容的登记路径可能有缺口）
- 测试脆弱性备注：原测试 travel 后固定 await 2 帧即断言（时序脆弱）；诊断期改为 15s 有界轮询后仍 enemies=0，已还原测试原样

### F5. tests/framework/terminal_failure_test（S1 记录）
- 状态：**BASELINE_EXISTING（runner 白名单缺口）**
- 失败模式：测试故意注入损坏纹理制造 ERROR，runner EngineErrorAllowlist 缺 corrupt-texture 模式 → runner 判 FAIL；checks=15 自报全 PASS
- 修复方向：runner allowlist 增加该已知非致命模式（基础设施变更，非生产/测试问题）

### F6. 启动性能（永久口径，非测试 FAIL）
- 状态：**OPEN / PRODUCT SLA MISSING**（60 秒 ceiling 非门槛）
- 证据：ready 诊断 8513/8163ms 实测（S0）；ledger 行 2

### F7. 旧 V3/V4 Windows 性能失败（第二树遗产）
- 状态：**不可比（不同语义 source）**；本树已用 `feature_residency_latency_distribution_test` 建立自己的同机记录（ledger 行 9，S4 完成）

### F8. tests/brand_intro_test.tscn
- 状态：**BASELINE_EXISTING（基线内容受控实验同败确认）**
- 复现：`pwsh -File tools/run_godot_tests.ps1 -TestPaths 'tests/brand_intro_test.tscn' -TimeoutSeconds 30`
- 失败模式：`SCRIPT ERROR: Assertion failed: real main-scene prefetch did not settle successfully: { "contract_id": "startup.loading.main_scene_prefetch.v1", "attempted": true, "accepted": false, "already_cached": false, ... }`（brand_intro_test.gd:207 `_wait_for_main_scene_prefetch`）
- 基线对照：17 个本任务 feature 文件还原到 272430b36 字节后同败 → 非本任务回归
- 初步根因假设：main-scene prefetch 合同（startup.loading.main_scene_prefetch.v1）在 Windows ad-hoc 沙盒的接受路径失败（attempted=true/accepted=false）——与 F6 启动性能 OPEN 口径同域（启动加载链既有问题），Linux formal 环境行为待核
- 待 GPT Pro 复核：prefetch accepted=false 的判定条件与平台依赖

### F9. tests/canonical_skill_production_entry_test.tscn
- 状态：**BASELINE_EXISTING（spawn 准入家族，F2 同款断言）**
- 失败模式：`Assertion failed: canonical skill fixture must use the formal exact-ID mapped spawn` → 连锁 `Invalid access to property or key 'current_hp' on Nil`
- 归因：与 F2（skill_plan_single_resource_commit）同一条 formal exact-ID mapped spawn 合同断言，同一 fixture 适配缺口；家族抽验（F4 bich_area）已做基线实验确认该家族为基线既有
- 待 GPT Pro 复核：与 F2 合并处理（canonical 系 + skill_plan 系 fixture 的发布路径统一适配）

### F10. tests/canonical_snapshot_identity_production_test.tscn
- 状态：**BASELINE_EXISTING（spawn 准入家族，F2/F9 同款断言）**
- 失败模式：`Assertion failed: canonical snapshot fixture must use the formal exact-ID mapped spawn` → 连锁 `canonical snapshot target must have a clear WORLD path`
- 归因：同 F2/F9 家族（canonical 系 fixture 未适配 formal exact-ID mapped 发布合同）

### F11. tests/canonical_snapshot_propagation_test.tscn
- 状态：**BASELINE_EXISTING（spawn 准入家族，F2/F9/F10 同款断言）**
- 失败模式：`Assertion failed: snapshot propagation fixture must use the formal exact-ID mapped spawn` → 连锁 `snapshot propagation target must have a clear WORLD path`
- 归因：同家族。**家族统计（更新中）**：formal exact-ID mapped spawn 合同断言已出现在 skill_plan(F2)、canonical_skill(F9)、canonical_snapshot_identity(F10)、canonical_snapshot_propagation(F11) 四个 fixture——likely 更多 canonical/snapshot 系在后续批次出现

## 待 GPT Pro 协作的核心问题

1. **发布合同对编辑器权威内容的覆盖**（F4 最关键）：正式编辑器地图 travel 后敌人零生成，是 `_submit_staged_actor_descriptor` 描述校验、`_validate_queued_actor_descriptor` 回调、还是 `admit_base` 的登记缺口？修复应在生产登记链还是测试 fixture？
2. **测试遗产适配策略**（F1/F2/F3）：natural 系列与 skill_plan fixture 改用 `publish_targets` 重发布是否保持原合同语义（30 目标自然消灭 / exact-ID mapped spawn）？
3. **runner 超时上限**：90s ValidateRange 上限与部分场景自声明窗口的冲突是否有更合理的按场景声明机制。

## 更新记录

- 2026-10-06：初版，收录 F1-F7（批次 1 全部 + 批次 2 前 20 项内发现的 F4）
