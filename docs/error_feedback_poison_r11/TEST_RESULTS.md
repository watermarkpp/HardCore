# TEST_RESULTS — R1.1 玩家头顶状态标志 + 错误入口补完

运行环境：工作树 `C:\Users\Administrator\Documents\HardCore-worktrees\error-feedback-poison-r11-20260918`（分支 `glm/error-feedback-poison-r11`，BASE `83840d3a14f7c26fb7306d8dc16c2e40de5aa185` = origin/codex/integration）。测试经 `tools/run_godot_tests.ps1`（console/headless、每树 `.godot/runtime_appdata`、`outputs/test_logs`）。视觉取证为真实窗口化 Godot 直跑（诊断脚本不入库）。

## 1. R1.1 正式注册测试（全部 PASS）

6 个测试已在 `tools/run_godot_tests.ps1` 注册进 `$Suites.critical`（R1 版本从未注册，本项为控制器指出的缺失）：

| 测试 | 结果 | 覆盖 |
|---|---|---|
| tests/player_poison_presentation_test.tscn | PASS | 静态：蓝环字面量消失、底部条无 `"id":"poison"`、标志行/几何常量在场；真实 main.tscn 9 组用例：legacy 毒→单毒点、怪物源毒→单毒点、双源合并、单源残留、全部结束、死亡清标志且不动玩法计时、麻痹单标志（无底部条目）、麻痹+中毒固定顺序（paralysis,poison）与固定槽位（麻痹 x<0 / 中毒 x>0）、干净态全空 |
| tests/player_health_bar_status_marker_test.tscn | PASS | 血条挂载 strip、行位置=BAR_SIZE.y+5、layout_snapshot 契约、未绑定源安全空、五态生命周期（毒/怪毒/双态固定顺序/毒止麻留槽/死亡全隐且不写计时器）、真实父子绑定路径 |
| tests/ui_error_feedback_scope_guard_test.tscn | PASS | R1 既有门禁 + R1.1 新门禁：拾取拒绝走错误通道、修复油结构化分类、快捷栏空错误通道、inventory_panel 两处 use 均消费结构化结果（legacy 直调=0）、成功保持 presenter 通道 2 处、失败经 from_result 边界 |
| tests/ui_error_machine_reason_leak_test.tscn | PASS | R1 既有静态/运行时双向把关 + R1.1：6 条临时增益机器原因中文映射与机器分类、use 权威结构化入口在场、String 入口为包装、`return str(buff_result.get("reason"...))` 直通泄漏禁绝、from_reason 边界、inventory_panel 结构化消费契约 |
| tests/ui_error_feedback_overlay_test.tscn | PASS | R1 错误通道实现回归（未动）：z=4096、计时、守卫 |
| tests/repair_20260913/inventory_error_feedback_real_input_test.tscn | PASS | R1 装备错误闭环回归（未动）：真实触摸流 10 用例 |

命令：`tools/run_godot_tests.ps1 -TestPaths <上述6场景> -TimeoutSeconds 60` → `passed=6 failed=0`（含中途修复后的复跑）。

## 2. 相邻回归（改动直接相邻系统）

| 测试 | 结果 | 备注 |
|---|---|---|
| tests/monster_source_status_test.tscn | PASS | 毒时钟玩法未动 |
| tests/monster_paralysis_attack_test.tscn | PASS | 麻痹玩法未动 |
| tests/quick_item_slots_test.tscn | FAIL（基线既有） | 见 §4；绑定/扫描/期望名不匹配/等级不足/满级拒绝等用例在本任务改动前即失败 |
| tests/player_item_audio_event_test.tscn | PASS | 使用音频经 String 包装保持 |
| tests/player_health_bar_level_label_test.tscn | PASS | 血条布局回归（新增 strip 子节点不影响既有契约） |
| tests/loot_ui_20260914/buff_strip_test.tscn | PASS | 底部条 6 旗标序列不含毒（毒条目已移除，本测试本就不含毒用例） |
| tests/loot_ui_20260914/buff_expiry_test.tscn | PASS | |
| tests/skill_book_rank_upgrade_integration_test.tscn | PASS | learn_skill String 包装保持 |
| tests/persistence_business_transactions_test.tscn | PASS | |
| tests/inventory_weight_authority_test.tscn | PASS | |
| tests/equipment_luck_test.tscn | PASS | 祝福油消息逐字保持 |
| tests/equipment_precise_durability_test.tscn | FAIL（基线既有） | 见 §4 |
| tests/complete_item_system_test.tscn | PASS | |
| tests/bich_area_test.tscn | PASS | |
| tests/vertical_slice_loop_test.tscn | PASS | |
| tests/progression_loot_20260913/consumables_test.tscn | PASS | |
| tests/hud_gothic_runtime_test.tscn | PASS | 快捷栏空断言按 R1.1 新契约更新（error_label 通道 + 反向断言）后通过 |
| tests/repair_20260913/inventory_real_input_test.tscn | PASS | |
| tests/smoke_test.tscn | PASS | |

命令：两批 `-TestPaths` → 批次1 `passed=9 failed=2`、批次2 `passed=7 failed=1`（该 1 失败为新契约后已修复复跑 PASS）。

## 3. 视觉取证（真实窗口化 Godot，1598x720）

目录：`docs/error_feedback_poison_r11/captures/`（运行脚本 `tests/diag_r11_status_marker_capture.gd`，诊断脚本不入库；角色经生产传送路径 `_set_player_world_position` 移至空地避免井精灵遮挡）。全帧 + `_zoom_bar_*`（血条+标志行 4x 放大）+ `_zoom_feet_*`（脚部 4x 放大）。

像素探针客观核验（`System.Drawing` 逐像素分类；BAR=x770..812,y255..290；FEET=x744..854,y300..415；TOP=全宽,y100..190）：

| 状态 | 标志行 blue | 标志行 green | 脚部 blue | 脚部 green | TOP 金色文本 |
|---|---|---|---|---|---|
| 01 正常 | 0 | 0 | 0 | 0 | 基线 1902 |
| 02 麻痹 | 31（左槽蓝点） | 0 | **0（无蓝环）** | 0 | 基线 |
| 03 中毒 | 0 | 32（右槽绿点） | 0 | **0（无绿环）** | 基线 |
| 04 麻痹+中毒 | 32（左槽） | 32（右槽） | 0 | 0 | 基线 |
| 05 错误通道样本 | 32 | 32 | 0 | 0 | **2405（+503，错误文本出现）** |

点簇中心实测：麻痹 ≈x786、中毒 ≈x796，与契约（血条原点 791 ±5 槽位）吻合；旧蓝环（半径 37 世界像素）如仍在会产生数千蓝色像素，实测脚部为 0。

## 4. 新发现的基线既有失败（与本任务无关，均有基线证据）

以下 2 个测试未注册于任何正式套件；在干净基线 detached 工作树（`--detach 83840d3a14f7c26fb7306d8dc16c2e40de5aa185`，无本任务改动）逐项复现同样断言失败，属基线既有问题（陈旧测试 vs 数据演化），不在本任务范围修复（不越权、不扩 scope）：

| 测试 | 断言失败点 | 基线复现 |
|---|---|---|
| tests/quick_item_slots_test | L117 "第4本升级使用失败：基本剑术已达到最高等级"（技能数据 max rank=3，测试假设可连升 4 次） | FAIL（同点） |
| tests/equipment_precise_durability_test | L180 "raw零耐久装备仍提供属性"（木剑零耐久 attack_max 断言，先于本任务触及的任何修复油路径） | FAIL（同点） |

## 5. 集成正式套件（merge 后于 integration 树复跑）

### 5.1 R1.1 收口 critical（integration @ 4b001cbc，2026-09-18 16:40）

- 结果：**357 项，339 PASS，18 FAIL**（`outputs/test_logs/runner_results_critical_20260918_164022_766_5032.json`，git_head=4b001cbc）。
- 注：本次运行 TimeoutSeconds=60（与本仓库基线对照一致，归因有效）；60 并未证明为最小必要值，属既定参数而非效率最优，后续轮次应回归 8s 默认并单独豁免确实需要的慢测试。
- 18 项 FAIL 的基线归因（对照 r11-baseline-83840d3a，仅跑该 18 项，同 60s）：

| 测试 | current | baseline | 失败签名（两侧逐字比对） | 分类 |
|---|---|---|---|---|
| skill_semantic_contracts_test | FAIL | FAIL | wizard.fire_wall::fire_wall_exact_2x2 | BASELINE_EXISTING |
| canonical_snapshot_propagation_test | FAIL | FAIL | fire wall controller must own 4 visual cells | BASELINE_EXISTING |
| skill_production_canonical_entry_test | FAIL | FAIL | fire wall must own exactly 4 pure-visual cells | BASELINE_EXISTING |
| hud_authority_integration_test | FAIL | FAIL | Assertion failed.（同一断言点 L175） | BASELINE_EXISTING |
| inventory_equipment_ui_test | FAIL | FAIL | 人物属性超长时没有右侧滑块 | BASELINE_EXISTING |
| equipment_durability_policy_test | FAIL | FAIL | 零耐久装备仍提供属性 | BASELINE_EXISTING |
| equipment_precise_durability_test | FAIL | FAIL | raw零耐久装备仍提供属性 | BASELINE_EXISTING |
| monster_world_integration_test | FAIL | FAIL | ID 76 runtime did not expose the complete V505 source profile | BASELINE_EXISTING |
| skill_contract_manifest_test | FAIL | FAIL | Assertion failed.（同一断言点 L57） | BASELINE_EXISTING |
| skill_source_of_truth_test | FAIL | FAIL | Package integrity failed: ["runtime_sot_hash_mismatch"] | BASELINE_EXISTING |
| w6_visual_contract_test | FAIL | FAIL | valid W7 affix was not accepted | BASELINE_EXISTING |
| warehouse_gothic_ui_test | FAIL | FAIL | 共享金币存入没有按 100000 扣除身上金币 | BASELINE_EXISTING |
| shop_gothic_ui_test | FAIL | FAIL | 匕首详情正文缺少 价格 行 | BASELINE_EXISTING |
| fire_wall_hit_parity_test | FAIL | PASS | 首轮崩溃签名（无断言）；复跑 PASS | FLAKY（偶发） |
| fire_wall_tick_claim_parity_test | FAIL | PASS | 同上；复跑 PASS | FLAKY（偶发） |
| fire_wall_boundary_target_test | FAIL | PASS | 同上；复跑 PASS | FLAKY（偶发） |
| unbuilt_planned_map_not_playable_test | FAIL | PASS | 复跑打出 PASS 标记但进程未按时退出 | FLAKY（偶发） |
| bich_monster_visual_test | FAIL | PASS | 钉耙猫 current_state≠walk（方向诊断 2==2 正确）；monster/enemy 代码两树零差异；R2 树复跑 PASS | FLAKY（负载/资源流送时序） |

- 结论：**0 项 REGRESSION 归因于 R1.1**；13 项基线既有 + 5 项偶发（复跑/交叉树验证）。

### 5.2 R2（统一玩家通知）critical（integration merge 5a29fdae 前、R2 树 @ a9c9472，2026-09-18 18:01）

- 结果：**363 项（357+6 新注册），347 PASS，16 FAIL**（`runner_results_critical_20260918_180133_274_2664.json`）。
- 8 个 R2 测试全部 PASS，注册映射：player_notice_overlay/item_style/dedupe_priority/action_result_contract/equipment_success_notice_real_input/skill_learning_notice_real_input → `$Suites.critical`（L602-609）；item_style+equipment_success 另入 `$Suites.equipment`（L611-614）；scope_guard/overlay 为 R1.1 已注册改写（L590-597）。
- 16 FAIL 分类（其中 13 项与 §5.1 相同签名 → BASELINE_EXISTING，不再重复列表）：

| 测试 | current | baseline(83840d3a) | integration(4b001cbc) | 分类 |
|---|---|---|---|---|
| complete_client_resource_catalog_test | FAIL | FAIL（同签名：缺 manifest.json） | PASS（该树已生成产物） | BASELINE_EXISTING（outputs 生成物缺失，环境性） |
| warrior_skill_state_machine_test | FAIL | PASS | PASS | R2 引入 → 已修：断言从退役的 loot_label 通道迁至中央通知层（R2 合同有意变更），修复后复跑 PASS |
| summon_owner_teleport_runtime_test | FAIL(套件内) | PASS | PASS；R2 树单独复跑 PASS | FLAKY（套件负载下的位移竞态；两树隔离均 PASS） |

- 修复后定向复跑：warrior_skill_state_machine + hud_gothic_runtime + 8 个 R2 测试 = **10/10 PASS**（18:07）。未再跑第二次全量 critical（仅 1 处测试侧断言修正，按效率规范不重跑 363 项）。

### 5.3 视觉验收（窗口化真实 GPU，1600x720）

- 混合格式"已装备 裁决之杖"：前缀 140px 通知色 + 物品名 167px 超金色（UIItemNameStyle），背包面板打开时可见；错误通道"需要攻击46"207px 纯通知色。
- 产物：`outputs/test_logs/r2_visual_probe_*.png`（gitignored，本机存档）；探针临时文件已删除（创建 17:10/18:0x，删除 18:10，位于 res://tests/ 但零引用、无测试枚举 res://tests，未参与任何正式运行）。

## 6. 诚实结论

- PART A（玩家血条下标志系统 + 双环移除 + 底部条毒旗标移除）：实现完成，测试与取证通过。
- PART B（use 权威结构化 + 遗漏错误入口补完）：实现完成，测试通过；String 入口兼容性有回归证据。
- PART C（测试门禁）：6 测试已注册 `$Suites.critical`；integration critical 复跑完成（§5.1），0 项回归归因 R1.1，本节成立。
- 既有失败继承：R1 记录的 8 个基线既有失败未在本任务触碰；本次另发现 2 个（§4），同样未触碰。
- 效率规范自评偏差（记录在案）：全轮次统一 TimeoutSeconds=60 未证明最小必要（对照有效性不受影响）；critical 运行期间曾 git add 与创建过未跟踪探针文件（证据链见 §5.3，判 NON_IMPACTING）；后续轮次改为"冻结候选树→测试→结束后暂存/提交"。
