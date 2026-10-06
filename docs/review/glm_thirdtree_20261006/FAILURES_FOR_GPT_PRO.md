# 第三树施工失败全记录（供 GPT Pro 协作解决）· v2 口径

- 基线：`272430b3692e776b25df820eaa8b53ed9f34bd8e`；分支 `codex/glm-thirdtree-continuation-20261006`
- 记录版本：v2（2026-10-06，按 GPT-Pro 审查指令修正口径）；起点 HEAD `ad29a835e` → 探针提交后见 git log
- 运行方式：`tools/run_godot_tests.ps1 -TestPaths '<scene>' -TimeoutSeconds N`（每项一调用单跑；runner 上限 60s 普通窗口）
- 证据目录：`outputs/test_logs/<test_name>.godot.log`（**注意：同名运行会覆盖，重要轮次需按 run 归档**）
- **口径修正（v2）**：
  1. `BASELINE_EXISTING` 只回答"是否由本任务引入"，**不回答"当前功能是否正确/验收是否完成"**，不自动豁免当前验收；
  2. 每项拆三列：**回归归因 / 当前正确性 / 阻断范围**；
  3. 受控实验（17 文件字节还原）不是完整基线 checkout，结论只覆盖被还原的文件集合；
  4. 相同断言/相似症状**不能**代替每个调用路径的核对——同族判定一律标"候选"直至逐项验证；
  5. 打印 PASS marker 但超时/未正常退出的运行**保持原 FAIL**；后续单跑 PASS 另列；
  6. 提交 `ad29a835e` 除报告外还包含历史证据目录中的 `.gd.uid` 元数据文件（随 git add -A 进入；不影响运行/导出语义，记录在案，不清理）。

## 失败清单（v2 三列口径）

### F1. tests/hc_monster_combat_r4/natural_cadence_24_test.tscn（同款：24_chase / 76 / 238 / 239）
- 复现：`-TestPaths 'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn' -TimeoutSeconds 90`（场景自声明 90s 窗口；runner 参数上限 90）
- 失败模式：`R4_NATURAL_CADENCE_FAIL: monster=24 ["spawn_failed", "insufficient_starts=0", "insufficient_settlements=0", "foreign_perturbation_missing"]`
- **回归归因**：候选 BASELINE_EXISTING（家族症状一致 + 本任务零 spawn 链改动，但未做逐项基线实验）
- **当前正确性**：FAIL——测试未进入目标业务（spawn_failed，0 起手 0 结算）
- **阻断范围**：阻断 cadence 系自身验收；不阻断其他源码工作
- 根因链（同 F3 家族）：测试世界构建/调用路径未走正式发布计划收集 → `_spawn_enemy` 的 `admit_base` 拒绝 → targets=0。**修复路径**：迁移到正式发布入口（F2 试点验证后逐个套用）
- 备注：历史原件曾打到第二轮 24/30——targets=0 是**新的前置阻断**，不能解释历史六个尾部目标未完成；修好准备路径后才能继续原 35 秒因果工作

### F2. tests/skill_plan_single_resource_commit_test.tscn
- 失败模式：`Assertion failed: resource commit fixture must use the formal exact-ID mapped spawn`
- **回归归因**：候选 BASELINE_EXISTING（同 F1 口径）
- **当前正确性**：FAIL——fixture 在世界 READY 后直接 `_spawn_enemy()` 临时 slot（`test:skill_plan_resource_commit:19`），未把该 slot 放进完整发布计划
- **阻断范围**：阻断该测试自身；不阻断其他源码工作
- **修复方向（已定）**：复用 `tests/helpers/formal_world_skill_fixture.gd` 的 `publish_targets` 正式发布接口，**不另写第二套登记流程**；迁移时保留：原怪物 ID、位置、WORLD 路径、MP 公式、恰好一次提交、snapshot 身份；**被测 release、锁定目标和 accepted lease 在完成准备后捕获**（重新发布可能改变 world generation/玩家位置/前态）

### F3. tests/framework/natural_sustained_chain_test.tscn + tests/framework/natural_effect_lifecycle_test.tscn
- 失败模式：`_spawn_enemy` 30 次全 null（targets=0）
- **回归归因**：BASELINE_EXISTING（受控实验 5 轮：S1 父版本/HEAD 双复证 + 纯净基线；**实验范围=17 个 feature 文件字节还原**）
- **当前正确性**：FAIL——**阻断自然 30 目标/35 秒要求的验收完成**（此前口径"不阻断 S5/S6"不成立：不阻断其他独立开发，但阻断以该测试证明自然要求已完成）
- **阻断范围**：阻断自然验收（ledger 行 8 的验收声明同步降级）
- 已排除：S3 scene_epoch 机制；S1 编译断裂（已修）
- 修复路径：同 F2（正式发布入口），保留完整 30 目标计划一次发布、同世界连续轮次、原 HP/输入节拍/35 秒、真实 AI

### F4. tests/bich_area_test.tscn —— **根因已确证（本版本更新）**
- 失败模式（原测试，保留为 RED 记录）：`Assertion failed: 一层编辑器怪物配置未完整加载`，诊断 `enemies=0 expected=40`
- **回归归因**：BASELINE_EXISTING（17 文件受控实验基线同败）
- **当前正确性（2026-10-06 探针实证）**：**生产正式发布链 PASS**——新探针 `tests/framework/bich_formal_transition_probe_test`（保持 test_mode=false 走正式 `_begin_map_transition` 计划收集窗口）实测：**enemies=40/40、bosses 0/0、门点断言、sealed=true、零 staged failure reason**（runner 判定 PASS）
- **根因**：旧测试在首次启动后把 `test_mode` 切回 true → `_should_animate_map_transition()` 返回 false → `travel_to_map` 走同步 `_travel_to_map_immediate()` 快捷路径 → **没有正式 transition 的计划收集/发布** → `_spawn_enemy` 的 `admit_base` 拒绝全部 spawn → enemies=0
- **阻断范围**：不阻断生产发布链（正式路径已证明可用）；阻断 bich_area 旧测试自身——修复=迁移该测试到正式 transition 路径（保留原业务断言与期望 40 不变）
- 证据：`bich_formal_transition_probe_test.godot.log`（BICH_FORMAL_PROBE 轨迹）

### F5. tests/framework/terminal_failure_test —— 口径修正
- 状态：BASELINE_EXISTING；**v2 撤回此前"给普通 runner 白名单增加 corrupt-texture 模式"的建议（该建议错误）**
- 正确口径：该场景是业务负例检查——**业务断言全部 PASS（checks=15），普通 runner 按原合同判 FAIL 是正确行为**；如需单独采集负例证据，应使用严格限定的负例验证（检查文件归属、精确错误、真实退出、回执与恢复），不得把损坏资源错误泛化为"非致命"

### F6. 启动性能（永久口径，非测试 FAIL）
- **OPEN / PRODUCT SLA MISSING**（60 秒 ceiling 非门槛）；ready 诊断 8513/8163ms（S0）

### F7. 旧 V3/V4 Windows 性能失败（第二树遗产）
- 不可比（不同语义 source）；本树已有 `feature_residency_latency_distribution_test` 的**结构性调度测量**（见下"口径边界"）

### F8. tests/brand_intro_test.tscn —— 归因待深挖（v2 降级）
- 失败模式：`Assertion failed: real main-scene prefetch did not settle successfully: {contract_id: startup.loading.main_scene_prefetch.v1, attempted: true, accepted: false, status: "pre...（截断）`（brand_intro_test.gd:207）
- **回归归因**：BASELINE_EXISTING（17 文件受控实验基线同败）
- **当前正确性**：FAIL——但 **accepted=false 不必然等于申请被拒**：生产预取链为 `_begin_main_scene_prefetch → attempted=true → status="preparing_code" → deferred 准备 → 检查实际 retention → 申请/复用 main.tscn → accepted=true`，而测试 `_wait_for_main_scene_prefetch` 最多等 240 个 process 帧——窗口结束时若仍 `preparing_code`，返回的是**未终态诊断**
- **候选原因（未裁决）**：①240 帧不足以等到真实准备完成；②准备因真实错误失败；③owner/retention 失效；④main 资源请求真正被拒
- **下一步**：补完整状态轨迹（wall 时间、process epoch、generation、status、code_preparation 错误、原 request/get 计数），按真实终态判断；正式等待按终态而非帧数；测试不得自行 get 结果改写 diagnostic 充当生产成功
- **阻断范围**：阻断 brand_intro 自身与启动验收的相关子项

### F9. tests/canonical_skill_production_entry_test.tscn
- **回归归因**：**候选** BASELINE_EXISTING（v2 降级：与 F2 相同断言文本，但无逐项基线实验；F4 的基线实验只覆盖其自身调用路径，不自动覆盖本项）
- **当前正确性**：FAIL（`formal exact-ID mapped spawn` → 连锁 current_hp on Nil）
- **阻断范围**：自身

### F10. tests/canonical_snapshot_identity_production_test.tscn
- 同 F9：**候选** BASELINE_EXISTING；FAIL（exact-ID mapped spawn → WORLD path 断言连锁）；阻断自身

### F11. tests/canonical_snapshot_propagation_test.tscn
- 同 F9：**候选** BASELINE_EXISTING；FAIL（同款断言连锁）；阻断自身

### F12. audio_w4_actor_service_test（第一批 FAIL 的复核）
- 原判：批次 1 FAIL（early_script_error + 超时杀）
- 复核：单跑（30s）**PASS**（PASS marker + 断言全过）
- **v2 口径**：超时失败的原始运行**保持 FAIL 记录**；单跑 PASS 另列；"冷缓存是已证实根因"**未证实**（一败一过不构成根因证明）——结论：**该测试无稳定 FAIL 证据，标待观察**（后续 critical 单项回归正常退出即消除）

## 口径边界（S3/S4 记账修正）

- **S3（ledger 行 7）**：`feature_resource_scene_change_failure_test` 实测的是 **`get_tree().current_scene = successor` 赋值后的准备取消**（9 项 PASS）——它**没有**调用 `change_scene_to_file/packed()` 并取得非 OK 返回值，**不能关闭原要求的"真实 SceneTree 调用立即失败"**。物理 publisher 替换、APK 资源闭包同样必须各有实际证据。ledger 行 7 拆分记账。
- **S4（ledger 行 9）**：分布场景使用 `ObservedEnemy`（`take_feature_periodic_damage` 为空）+ 手动推进 1/60 模拟时间 + 显式 pump + 排空尾段 + 最大迟到 <8s 结构断言——**定性为"测试驱动时钟下、周期 HP 接口被替代的结构性调度测量"**。它不证明自然 AI、真实周期 HP、正式 physics 时钟或整体游戏性能已通过；一次有限窗口的迟到 <8s 也不是长期数学上界。4.48s 迟到值得调查，但该夹具不足以归因为真实游戏调度故障；反过来，"产品 SLA 未定"**不移出**已确定的自然 35 秒要求作为 S6 前置。

## 修复执行序（GPT-Pro 指令）

1. ✅ 口径修正（本版本）
2. ✅ F4 真实换图最小对照（探针 PASS，根因确证）
3. F2 及 canonical/cadence/natural 发布适配：共用 `publish_targets` 原发布入口，每个消费者单项执行，业务主体真正运行
4. F8 预取完整终态轨迹
5. 恢复自然两轮测试（30 目标真实进战斗 → 原因归 35 秒完成/排空）
6. 恢复剩余 critical 单项回归

## 更新记录

- 2026-10-06 v1：初版 F1-F7
- 2026-10-06 v2：按 GPT-Pro 审查修正口径（三列/候选降级/撤回 F5 白名单建议/F4 探针实证/F8 降级待深挖/S3/S4 记账边界/audio 复核口径）
