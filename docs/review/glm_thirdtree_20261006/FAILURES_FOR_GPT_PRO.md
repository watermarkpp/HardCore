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

### F1. tests/hc_monster_combat_r4/natural_cadence_24_test.tscn（同款：24_chase / 76 / 238 / 239）—— **4/5 已修复（2026-10-06）**
- 原失败模式：`R4_NATURAL_CADENCE_FAIL: monster=24 ["spawn_failed", "insufficient_starts=0", ...]`
- **回归归因**：候选 BASELINE_EXISTING（家族症状一致，未逐项基线实验）
- **当前正确性（迁移后逐项单跑）**：
  - **24：PASS**（starts=20 attributed=20 settlements=20 foreign=35，90s 授权窗）
  - **24_chase：PASS**（1/1/1/2，60s——chase 模式真实移动接近语义保留）
  - **238：PASS**（20/20/20/14，60s）
  - **239：PASS**（20/18/20/8，60s——18/20 归因由场景自身断言接受）
  - **76：FAIL（新模式，非 spawn）**——`insufficient_starts=19, insufficient_settlements=19`：spawn 已修，窗口内 17 次真实 HP 扣减发生，但 `_hc_starts/_hc_settlements` 计数 1 vs 期望 20——48s 采样预算与 76 号真实节拍不匹配，或起手-结算语义需原生分析（evidence=`outputs/test_logs/r4_cadence_76.json`）。**归因：业务采样课题，非 fixture/发布问题**
- **阻断范围**：76 阻断其自身 cadence 验收；其余四项已解除
- 迁移方式：`natural_cadence_base` 发布目标改走 `publish_targets`（publish 先于 player 前态捕获；原 AI/归因/扰动/时间窗逻辑零改动）

### F2. tests/skill_plan_single_resource_commit_test.tscn —— **已修复（2026-10-06 试点）**
- 原失败模式：`Assertion failed: resource commit fixture must use the formal exact-ID mapped spawn`
- **回归归因**：候选 BASELINE_EXISTING（同 F1 口径）
- **当前正确性**：**PASS（迁移后单跑验证）**——fixture 改用 `WorldSkillFixture.publish_targets` 正式发布入口（真实 map-transition 计划收集窗口）；**全部原测点保留**：原怪物 ID 19、ground 位置、WORLD 路径、MP 公式、恰好一次提交（实测 mp=35）、canonical plan 同价、snapshot 身份；被测 release/锁定目标在发布完成后的世界上捕获（caster 位置/MP/清场均在 republish 之后重设；清场排除 fixture target）
- **阻断范围**：已解除
- **模式可复制**：F9-F11（canonical 系）与 F1/F3（cadence/natural 系）按同模式逐个迁移，每消费者单项执行验证——共享 helper 修复一次不代表全部消费者已 PASS

### F3. tests/framework/natural_sustained_chain_test.tscn + tests/framework/natural_effect_lifecycle_test.tscn —— **发布迁移完成；失败推进到 35 秒负载归因（2026-10-06）**
- 原失败模式：`_spawn_enemy` 30 次全 null（targets=0）
- **当前正确性（lifecycle 迁移后单跑）**：FAIL（129 checks / 8 失败）——但失败形态**质变**：
  1. **发布修复生效**：30 目标真实出生、nonoverlap 通过、AI 活跃（monster_movement>1）、玩家被真实攻击（hp 下降）、23 次施法经正式入口接受、states 真实产生（峰值 30）
  2. **发现的独立 S1 REGRESSION（已修，498680579）**：replacement 路径无条件写 `state_loan_origin` 而 `state_loan_handles` 仅 chain 非空时存在 → 后续替换 erase 缺键崩溃（25 次）。修复=对齐 fresh 路径守卫，states 会计不变。**该崩溃类已从日志完全消失**
  3. **剩余 8 项失败的同源主因（精确归因）**：30 只怪 AI 围攻 → 玩家受击锁（StruckTime=100ms 历史合同 + 受击反应锁，scripts/player.gd L60-63/123-125）在 ~15 击/秒下近乎全覆盖 → **memory_checkpoints 时间线证实**：t=5s states=29（怪接近中，施法顺畅）→ t=10s 26 → t=15s 15 → t=20s 10 → t=25s 6（怪到位后施法吞吐≈0）→ 死亡仅 5/30；90 states/三源覆盖/排空/纹理请求/死亡信号等 7 项均为死亡数不足的连锁次生失败
- **回归归因**：**非迁移引入；F3 历史口径（第二轮 24/30）从未 PASS**——30 怪围攻下固定 2 方向往复移动的施法吞吐在真实受击合同下结构性不可能完成 30 击杀/90 并发 states——测试负载设计与真实战斗合同的冲突第一次被完整暴露
- **待裁决选项**（GPT Pro/用户）：A. 风筝式移动脚本（拉开距离减受击、模拟真实玩家操作、不改怪物数量/时限/AI——**最合法方向**）；B. 受击锁豁免（=mock 生产路径，违反纪律）；C. 重新校准 30 死亡期望（需明确合同变更依据）；D. 接受当前形态为"真实负载结构性发现"记档
- **同回合实测进展（0c0d17867，三次受控变体）**：A 方向已实施并扩展——
  - **v3 风筝圆周**：6 死/23 accepted/peak 30——**受击僵直假设被否证**：23 accepted 恰为 35s÷CD(~1.5s) 上限，114 busy 是**正常 CD 等待**（测试 250ms 节拍本来就预期大量 busy），与怪是否攻击玩家无关
  - **v4 密度优先瞄准**（测试自有脚本瞄准，score=1.5GU 盒内邻居数）：**死亡 5→20**、peak 26——伤害预算首次到达怪群；剩余差距=脚本邻居盒与生产冰暴 AOE 几何的匹配
  - **v5 两阶段铺源/收割**：11 死——严格更差已回滚（铺源与伤害共享同一施法预算，不可分离）
  - **下一步（路径明确，纯测试自有逻辑）**：读生产冰暴 AOI 半径/形状/命中判定 → 邻居计数精确对齐 → 再测；90 并发断言额外要求 30×3 覆盖同窗共存，需在同一 23 次施法预算内达成——继续记录
- **修订归因结论**：主因不是受击锁（v3 否证），而是**测试脚本瞄准几何与生产 AOE 几何不匹配 + 90 并发/30 死亡双断言在同一伤害预算内的时序耦合**——仍在测试自有逻辑范围内（不改生产/负载/期望）
- **阻断范围**：natural 系两场自然验收；不阻断其他源码工作；**35 秒时限与怪物数量未动**
- 已排除：S3 scene_epoch 机制；S1 编译断裂（已修）
- 修复路径：发布入口迁移已完成（30 目标一次发布、同世界连续轮次、原 HP/输入节拍/35 秒、真实 AI 全保留）；余项取决于上述裁决

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

### F9. tests/canonical_skill_production_entry_test.tscn —— **已修复（2026-10-06）**
- 原失败模式：`formal exact-ID mapped spawn` → 连锁 current_hp on Nil
- **回归归因**：候选 BASELINE_EXISTING（家族症状一致，未逐项做基线实验）
- **当前正确性**：**PASS（迁移后单跑验证）**——一次 publication 发布**两个**目标（雷电术 19 + 圣言术祖玛卫士 156），因第二次发布重建世界会销毁后续段仍引用的第一个目标；`_prepare_published_enemy` 保留原 exact-ID/WORLD path 校验与 HP/控制设置；caster 前态与清场（排除两个 fixture 目标）在发布后重捕获
- **阻断范围**：已解除

### F10. tests/canonical_snapshot_identity_production_test.tscn —— **已修复（2026-10-06）**
- 原失败模式：`formal exact-ID mapped spawn` → 连锁 WORLD path 断言
- **当前正确性**：**PASS（迁移后单跑验证）**——单目标发布（monster 18，slot `test:canonical_snapshot_identity:18`），caster/清场/安全区断言在发布后世界重捕获，快照身份链断言全部保留

### F11. tests/canonical_snapshot_propagation_test.tscn —— **已修复（2026-10-06）**
- 原失败模式：同款断言连锁
- **当前正确性**：**PASS（迁移后单跑验证）**——单目标发布（monster 19，slot `test:canonical_snapshot:19`），同款重捕获模式

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
