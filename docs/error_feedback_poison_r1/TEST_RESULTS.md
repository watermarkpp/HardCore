# TEST_RESULTS — R1 统一错误反馈 + 中毒表现

运行环境：工作树 `C:\Users\Administrator\Documents\HardCore-worktrees\error-feedback-poison-r1-20260918`（分支 `glm/error-feedback-poison-r1`，HEAD `b812d3cf` = origin/codex/integration `f06a3d29` + 本任务提交）。测试经 `tools/run_godot_tests.ps1`（console/headless、每树 `.godot/runtime_appdata`、`outputs/test_logs`）。视觉取证为真实窗口化 Godot 运行（`Godot_v4.7-stable_win64.exe --resolution 1280x720`）。

## 1. 新增测试（全部 PASS）

| 测试 | 结果 | 覆盖 |
|---|---|---|
| tests/ui_error_feedback_overlay_test.tscn | PASS | HUD 错误通道：2s 自动消失、0.1s 下限、InventoryPanel(50)/Presenter(4095)/ErrorNotice(4096) z 合同、与 show_message 计时互不影响、机器 reason 入口守卫 |
| tests/ui_error_machine_reason_leak_test.tscn | PASS | 静态扫描 5 个施工文件：禁用字面量（安全退出失败：%s 等）、show 行不得拼接 reason/机器 token、hud 必须经 user_message、字面量不得是机器 reason；运行时层：全部 REASON_MESSAGES 映射、fallback、user_message 守卫（木剑/裁决之杖/麻痹戒指 通过） |
| tests/ui_error_feedback_scope_guard_test.tscn | PASS | 受保护消息保持 show_message（施放：/进入/复活/魔法盾自动补盾/使用了%s 等）、双通道共存（error≥25 处、message≥10 处）、hud 双通道互不越界、error_label z=4096、shop_panel/warehouse_panel/loot_feedback_layer 零错误通道引用、`_show_center_message` 无残留 |
| tests/player_poison_presentation_test.tscn | PASS | 绿环代码移除（颜色/半径字面量消失）、麻痹蓝环逐字保留、poison_status_remaining 聚合、game_root 施毒术条目；真实 main.tscn 启动 7 用例（legacy/怪物源/双源合并/单源残留/全部结束/死亡清旗标、麻痹无旗标）；条形图标生命周期（可见/秒数 9/贴图=施毒术/清空隐藏） |
| tests/repair_20260913/inventory_error_feedback_real_input_test.tscn | PASS | 真实触摸流（GameHUD + push_input）10 用例：等级不足(需要等级28)/攻击/魔法/道术不足、职业不符(测试法师限定法袍→只能由法师装备)、性别不符、错误装备槽不再静默(木剑不能装备到衣服位置。)、背包满卸装失败、stale instance(所选装备已变化)、存档失败回滚(装备存档失败，装备和背包均未改变)；每例断言装备/背包/选中/详情保持 |

命令：`tools/run_godot_tests.ps1 -TestPaths <上表5个场景>` → `passed=5 failed=0`。

## 2. 定向回归（改动直接相邻系统）

| 测试 | 结果 |
|---|---|
| tests/repair_20260913/inventory_real_input_test.tscn | PASS |
| tests/inventory_weight_authority_test.tscn | PASS |
| tests/equipment_special_effects_test.tscn | PASS |
| tests/skill_book_rank_upgrade_integration_test.tscn | PASS |
| tests/hud_gothic_runtime_test.tscn | PASS |
| tests/monster_source_status_test.tscn | PASS |
| tests/monster_paralysis_attack_test.tscn | PASS |
| tests/player_health_bar_level_label_test.tscn | PASS |
| tests/taoist_profession_package_test.tscn | PASS |

## 3. 套件回归

| 套件 | 结果 |
|---|---|
| safe_logout_critical（13） | PASS 13/13 |
| taoist_critical（17） | PASS 16/17（1 个既有失败，见下） |
| critical（55，分批跑完） | 47 PASS + 8 既有失败（见下），其余全部 PASS |

## 4. 既有失败（与本次改动无关，均有基线证据）

以下 8 个测试在干净基线树（detached worktree @ `f06a3d29`，即 origin/codex/integration 当前 HEAD，不含本任务任何改动；BASE `4a91db49`→`f06a3d29` 之间仅 enemy.gd 休眠唤醒改动 + 新增测试/文档，与本批测试无共同文件）逐项复现同样断言失败：

| 测试 | 断言失败点 | 基线复现 |
|---|---|---|
| tests/inventory_equipment_ui_test | 人物属性超长时没有右侧滑块 | FAIL（同点） |
| tests/ui_modal_surface_containment_test | @Panel@4/ItemDetailPresenter ordinary section must remain below overlay | FAIL（同点） |
| tests/stone_tomb_test | 石墓地图1197怪物数量不符 | FAIL（同点） |
| tests/skills/skill_semantic_contracts_test | wizard.fire_wall::fire_wall_exact_2x2 | FAIL（同点） |
| tests/canonical_snapshot_propagation_test | fire wall controller must own 4 visual cells | FAIL（同点） |
| tests/w6_visual_contract_test | valid W7 affix was not accepted | FAIL（同点） |
| tests/warehouse_gothic_ui_test | 共享金币存入没有按 100000 扣除身上金币 | FAIL（同点） |
| tests/shop_gothic_ui_test | 匕首详情正文缺少 价格 行 | FAIL（同点） |

另在预热缓存的 integration 工作树 `C:/Users/Administrator/Documents/hc-integration-v4`（同一 f06a3d29）复跑 inventory_equipment_ui_test 与 ui_modal_surface_containment_test，同样失败，排除"新树首次导入"环境因素。上述失败属于基线既有问题，未在本任务范围内修复（不越权、不扩 scope），未因本次改动新增或恶化。

## 5. 视觉取证（真实窗口化 Godot，1280x720）

目录：`docs/error_feedback_poison_r1/captures/`（运行脚本 `tests/diag_r1_poison_status_capture.gd`，诊断脚本不入库）。

| 文件 | 验收点 | 结果 |
|---|---|---|
| 01_normal_no_ring_empty_strip.png | 正常：脚下无任何环、状态条无中毒旗标 | PASS |
| 02_paralysis_blue_ring_no_strip_flag.png + _zoom_02_paralysis_ring.png | 麻痹：蓝色控制环在脚下、无中毒旗标 | PASS |
| 03_poison_flag_no_green_ring.png + _zoom_feet_03...png | 中毒：脚下无绿环、状态条出现单一施毒术旗标 | PASS |
| 04_paralysis_plus_poison_merged_flag.png + _zoom_strip_04...png | 麻痹+中毒：蓝环保留、单一合并旗标（9 秒倒计时=两源 max）、无绿环 | PASS |
| 05_error_channel_center_text.png | 错误通道：屏幕上方中央 "木剑不能装备到衣服位置。"（暖金 22px），面板/世界之上 | PASS |
