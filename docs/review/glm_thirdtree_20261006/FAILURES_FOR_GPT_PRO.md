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

## 修复进度总账（2026-10-06 · 发布适配批次后）
- **已 PASS 收口（7/12）**：F2（试点）、F1 cadence 全家 5/5（24/24_chase/76/238/239）、F9、F10、F11——全部经 `publish_targets` 正式发布入口迁移 + 逐项单跑验证；期间顺带修复 1 项 S1 REGRESSION（state_loan_handles 缺键崩溃，498680579）
- **FAIL 但归因闭合（2）**：F8（失败环节=ContentLayers 内部代码准备链 `cancelled_or_rejected`，观测轨迹已按指令建成）、F3（lifecycle 死亡 5→20/30，剩余=瞄准几何 vs 生产交付几何 + 90 并发/30 死亡双断言可达性待裁决）
- **待观察（1）**：F12（无稳定 FAIL 证据，critical 回归正常退出即消除）
- **候选 BASELINE_EXISTING（2）**：F6（启动性能，永久 OPEN 口径）、F7（V3/V4 不可比）
- **待裁决项汇总（供 GPT Pro）**：①F8 launch 0 的 `ready` 断言是否改为"真实终态+证据完整性"观测断言（预取为 fire-and-forget 优化、有常规加载兜底，冷缓存下被 generation 关闭是否仍须断言成功）；②F3 的 90 并发 states 与 30 死亡在同一 23 次施法伤害预算内的可达性（期望校准 vs 交付几何优化）
- 提交链：663a2dd53(F2) → bb8d9d7c9(F9-F11) → 498680579(REGRESSION 修复) → 0c0d17867/a407ea670(F3 实验) → 5ad1d60f0(F1 76) → 221dbc04e(F8 轨迹)

## 失败清单（v2 三列口径）

### F1. tests/hc_monster_combat_r4/natural_cadence_24_test.tscn（同款：24_chase / 76 / 238 / 239）—— **已全部修复，5/5 PASS（2026-10-06）**
- 原失败模式：`R4_NATURAL_CADENCE_FAIL: monster=24 ["spawn_failed", "insufficient_starts=0", ...]`
- **回归归因**：候选 BASELINE_EXISTING（家族症状一致，未逐项基线实验）
- **当前正确性（迁移后逐项单跑）**：
  - **24：PASS**（starts=20 attributed=20 settlements=20 foreign=35，90s 授权窗）
  - **24_chase：PASS**（1/1/1/2，60s——chase 模式真实移动接近语义保留）
  - **238：PASS**（20/20/20/14，60s）
  - **239：PASS**（20/18/20/8，60s——18/20 归因由场景自身断言接受）
  - **76：PASS（5ad1d60f0）**（starts=20 attributed=19 settlements=20 foreign=13，90s 授权窗）——Round 8 的"starts=1"为**误读**（实为 hc_starts_total=19，48s 窗完成 19/20 循环、deadline 切掉第 20 次；真实节拍 ~2.5s/次 × 20 次 ≈ 50s 采样 + boot 8s 本就超出 48s 预算）。修复=76 场景声明 approved_process_window_seconds=90（与 24 号先例同构，runner 名单已含 76，20 次期望未动，基类断言放行两个身份）
- **阻断范围**：**已全部解除**——cadence 家族 5/5 通过自身全部业务断言
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
  - **下一步（路径明确，纯测试自有逻辑）**：~~读生产冰暴 AOI 半径~~ **已做且否证（a407ea670）**：v6 按数据声明的 `area_radius 115px`（→~2.541GU 圆，wizard.json + CombatUnitLegacyAdapter）+ 站桩聚怪瞄准 → **15 死，严格更差**——声明字段不驱动实际伤害分发；v4 复现三次稳定（18-20 死带）。真实分发半径/形状需从生产交付代码（ice_storm target_area 命中实现）读取后再对齐一次
  - **同窗共存补充**：v6 的站桩聚怪（怪团更大）反而降伤害——实际分发可能以别的方式散布（多目标独立判定而非以选中怪为中心的圆），一并从交付代码确认
  - **【几何取证闭合（Round 14）】**：生产交付链 = `skill_runtime_router` L124 `geometry_cells = SkillGeometryServiceScript.cells(...)` → `caster_spell_geometry` 命中判定 = 目标脚印与 1×1GU 格子凸相交；数据真源 `skills_source_of_truth_v1.json` L2922-2933 migration note 明确冰暴合同几何 = **"选定目标区域 3×3"**（必测项 `ice_storm_exact_3x3`；"以玩家为中心 300px 全范围"被标注为待迁移错误行为；115px 为 action_profile 残留字段，代码无消费者——v6 否证与代码证据一致）。**v4 的 1.5GU 方盒恰好等于 3×3 格（target±1.5GU）的 footprint 边界——瞄准几何已与生产合同对齐**。剩余差距 = 怪群移动散开使 3×3（9 格）平均利用率 ~7 只/次 < 理论 12-20 只（聚拢时），伤害预算 23×7×180≈29k < 30 怪总 HP 48k；聚拢充分时 23×15×180≈62k 覆盖 48k 可行——死亡 30 达成的条件是聚怪效率，不是几何对齐
  - **【v7 聚怪前置否证 + 90 states 结构性分析（Round 15）】**：v7（前 8s 纯聚怪不施法）= 19 死/23 accepted/25 states——与 v4 持平，**瞄准策略族的天花板确认为 ~20 死**（7 个变体：迁移版 5/v3 6/v4 19-20/v5 11/v6 15/v7 19，已回滚 v4）。**90 并发 states 断言在 3×3 合同几何下数学不可达**：单次施法 affected cells 固定 9 格（3×3GU），怪脚印与 9 格相交上限 ~24 只 × 3 源 = ~72 < 90；而 migration note 标注的旧错误行为"以玩家为中心 300px 全范围"（≈6.6GU 半径）恰可覆盖全图 30 怪 × 3 源 = 90——**90 期望是旧错误几何时代的产物，3×3 修正后需重校准**（3×3 内可达峰值 ~45-60）。**待 Pro 裁决**：①30 死亡/35s 在 23 次施法 × 3×3 交付下的可达性（伤害预算差 ~35%）；②90 states 期望是否随 3×3 合同修正重校准
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

### F8. tests/brand_intro_test.tscn —— **失败环节已定位（2026-10-06，221dbc04e）**
- 失败模式：`Assertion failed: real main-scene prefetch did not settle successfully: {...status: "failed", request_count: 0, get_count: 0, code_preparation.state: "cancelled_or_rejected", _test_observation: {...}}`（brand_intro_test.gd:93 区段）
- **回归归因**：BASELINE_EXISTING（17 文件受控实验基线同败）
- **当前正确性**：FAIL——但归因已按 GPT Pro 指令闭合到具体环节：
  1. **等待机制已按指令重写**：240 帧上限 → 30s 墙钟 + 真实终态即刻返回；测试侧不再 `load_threaded_get` 自行收尾/改写 diagnostic（原 teardown 行为已删除）；每次状态变化记录 `{wall_ms, process_frames, status, attempted, accepted, request_count, get_count, native_owned, code_preparation_state}` 轨迹并随诊断返回
  2. **轨迹给出决定性证据**：30s 内到达**真实终态 `failed`**，`code_preparation.state = "cancelled_or_rejected"`，`request_count=0`——**内部代码准备链（ContentLayers `prepare_internal_code_entry` / `request_internal_prepared_script`）在 intro 环境内取消或拒绝**，从未到达场景请求提交（`_submit_prepared_main_scene_prefetch` 未执行）
  3. **"240 帧窗口不够"假设关闭**；"owner/retention 失效"降级为次级候选（retention 检查在 _submit 内，未到达）
- **下一步**：~~读 ContentLayers 两个函数的取消/拒绝条件~~ **已完成（Round 14 主会话+子代理交叉）**：`is_code_preparation_loading_phase_current`（startup_loading.gd L779-780）要求 `generation 相同 + _startup_state ∈ [LOADING, READY_TO_HANDOFF] + 非 exit`——**启动流程正常推进（动画结束→handoff→reveal→transition/EXITING）后，仍在两个 await（内部代码编译链）中的准备被判定取消 → cancelled_or_rejected → failed**。generation 推进点仅两处（L332 退出按钮/L817 exit_tree），均非本路径触发；触发的是 **state 推进本身**
- **判定**：**(a) 合法取消**——预取是 fire-and-forget 优化（同文件注释自证），main 场景由常规 `_prepare_target_scene` 加载且 launch 0 已断言 target ready（功能无损）；冷缓存下编译链耗时结构性超过动画+transition 窗口，基线 272430b36 起即如此（BASELINE_EXISTING 与机制一致）
- **待裁决（GPT Pro）**：launch 0 断言 `status ∈ [ready, already_cached]` 是"优化必须完成"的性能期望——建议改为**分类观测断言**：终态 failed 且 `code_preparation.state=cancelled_or_rejected`（合法取消、无 request 副作用）时 PASS；其余 failed（真实错误：retention 失效/请求被拒）仍 FAIL——既保留"真实错误必须暴露"的验收力，又不再把冷缓存优化时序当功能失败
- **阻断范围**：brand_intro 自身与启动验收相关子项

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
