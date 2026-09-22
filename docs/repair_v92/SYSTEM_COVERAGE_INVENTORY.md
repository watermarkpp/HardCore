# 系统测试覆盖机械清单（2026-09-22）

> 历史采样说明：以下保留调查时点的候选与验证状态。主控后续生产修复、动态结果和剩余边界见 [CONTROLLER_REVIEW.md](CONTROLLER_REVIEW.md) 与 [USER_REQUEST_RECONCILIATION.md](USER_REQUEST_RECONCILIATION.md)；本文的旧 NOT_RUN/旧数量不代表最终当前状态。

本报告按主控指定范围，只读对照 `PROJECT_INDEX.md`、`PROJECT_CURRENT_STATUS.md`、当前生产入口、`tools/run_godot_tests.ps1` 与三份指定 runner JSON。它是主控串行收口的候选证据，不是独立最终验收，也不认定未列场景存在缺陷。收到主控停止扩展指令后，仅保存本报告并交回已有证据。

本次仅写本文件；没有运行 Godot、测试、构建、设备操作或 Git 写操作，没有改生产、测试、人工地图和其他报告。本文行号来自调查时共享工作树，主控仍在修改，后续可能移动。

## 1. 证据边界

| 证据 | 实际记录 | 可支持的结论 |
| --- | --- | --- |
| `outputs/test_logs/runner_results_critical_20260922_164713_635_6132.json` | `git_head=b961cedff8040c9fc81534e094241ad9fa2330ad`；429 项，425 PASS、4 FAIL，`engine_log_errors=4` | 本报告下表的“critical PASS”均逐项查询此 JSON 的 `results`；不以中途 PASS marker 代替 runner 结果 |
| `outputs/test_logs/runner_results_adhoc_20260922_165149_255_1100.json` | 同 HEAD；4 项，3 PASS、1 FAIL，`engine_log_errors=4` | `canonical_skill_production_entry_test`、`magic_shield_map_lifecycle_test`、`player_combat_release_lifecycle_test` 各为 PASS；该整组不是全绿 |
| `outputs/test_logs/runner_results_adhoc_20260922_165934_268_6108.json` | 同 HEAD；11/11 PASS，`engine_log_errors=0` | 包含后述三项 critical 失败复验及 `random_teleport_destination_contract_test` PASS |

4 项 critical 原始失败的后续证据：

| 原失败测试 | 原结果 | 精确后续结果 |
| --- | --- | --- |
| `map_transition_input_lock_test` | FAIL | `165934_268_6108`：PASS |
| `canonical_skill_production_entry_test` | FAIL | **`165149_255_1100`：PASS**；不在 165934 的 11 项中 |
| `unbuilt_planned_map_not_playable_test` | FAIL | `165934_268_6108`：PASS |
| `map_release_identity_matrix_test` | FAIL | `165934_268_6108`：PASS |

`random_teleport_destination_contract_test` 在 165149 为 FAIL、165934 为 PASS。四个 critical 失败均有后续单项 PASS 记录，但不能拼称“一次 429/429 critical 全绿”。同一 `git_head` 也不能证明共享 dirty 工作树在几次运行之间字节不变；最终源码的完整 critical 和构建源身份仍由主控统一固定与验证。

`PROJECT_CURRENT_STATUS.md:34-36` 的 399/409、v91 APK、手机存档备份与安装状态属于旧构建源 `85d37077`。该文件 `:126` 明确旧 PASS、APK 和标签不能替代当前验收。`PROJECT_INDEX.md:28` 可用于入口导航，但 `:71-72` 的历史方法行号已过时；本文已回到当前源码定位。未把旧设备或旧 APK 结果并入本轮 PASS。

## 2. 按系统对照

表中“NOT_RUN”严格指上述三份指定结果没有该测试结果，并不声称它从未在历史上运行。已有测试能够证明的范围与设备/端到端边界分别列出。

| 系统 | 当前生产入口 / 消费链 | 指定 critical 中实际 PASS 的测试 | 尚需主控判定 / 本轮缺口 |
| --- | --- | --- | --- |
| 存档、损坏恢复、安全退出 | `scripts/player_state.gd:4988 save_game`、`:5327 load_save`、`:6089 update_world_location`、`:6106 save_safe_logout`；`scripts/game_root.gd:2597 _prepare_safe_logout` | `profile_business_validation_recovery_test`、`persistence_business_transactions_test`、`safe_logout_atomic_recovery_test`、`safe_logout_save_failure_test`、`safe_logout_existing_state_preservation_test`、`safe_logout_home_resolution_failure_test`、`safe_logout_world_location_inf_guard_test`、`item_drop_instance_persistence_test`、`loot_stable_identity_save_test`、`skill_progression_save_integration_test` | `player_world_position_unit_migration_test`：NOT_RUN。它实际写入 v6 PX 存档，经 `load_save` 迁移后再由正式 `update_world_location/save_game` 补 GU，能补足旧档位置迁移边界。不是当前存档系统整体未测 |
| APK 覆盖升级、热补丁退役 | `project.godot:31 DeviceLabPatch` → `scripts/device_lab_patch_bootstrap.gd:29 _init`、`:36 _load_active_patch`、`:114 _discard_obsolete_patch`；存档仍由 PlayerState 加载 | `device_lab_patch_bootstrap_test`、`startup_loading_failure_recovery_test`；前者含错误 base 身份、包大小/哈希、有效 PCK 挂载、升级精确退役及保留角色/仓库字节 | **当前最终 APK 覆盖安装与设备存档保留：NOT_RUN（本报告证据范围）**。headless 测试不证明 Android 安装器、签名、versionCode 或真实私有目录保留；旧 v91 证据不能代替新包 |
| 角色创建、选择、删除 | `scripts/character_select.gd:791 _create_character`、`:813 _request_delete_selected_character`、`:864 _enter_selected_character` → `scripts/player_state.gd:7373 create_character`、`:7425 delete_character_profile`、`:7685 select_character` | `multi_character_save_test`、`new_character_starter_loadout_test`、`character_select_launch_loading_test`、`safe_logout_character_select_guard_test` | `character_delete_transaction_test`：NOT_RUN，覆盖真实确认/取消、索引写失败、精确 sidecar 删除、其他角色字节不变、最后角色删除后的 UI。`character_select_touch_scroll_test`：NOT_RUN，补 11 角色真实触摸选择/拖动边界 |
| 共享仓库物品事务 | `scripts/warehouse_panel.gd:966/:1001` 实际 await `PlayerState.transfer_warehouse_prepared` → `scripts/player_state.gd:6572`、`:6597 _prepare_warehouse_transfer`、`:6704 _promote_prepared_warehouse`；落盘/恢复 `:6463/:4793` | `shared_warehouse_transaction_test`、`shared_warehouse_migration_test`、`warehouse_gothic_ui_test` | **`tests/repair_20260913/warehouse_prepared_transaction_test.tscn`：NOT_RUN。** critical 已覆盖底层双文件事务和恢复，但不能据此声称真实异步准备/提升路径已覆盖；独立专项含准备期间并发拒绝、同长度外部文件漂移、回滚失败 WAL 恢复、UI 销毁后事务完成 |
| 装备、背包、持久化 | `scripts/player_state.gd:2776 recalculate_stats`、`:3340` 装备迁移、`:3530` 修理计划、`:3568 repair_all_equipment`；`scripts/equipment_rules.gd` 为规则入口 | `inventory_equipment_ui_test`、`inventory_weight_authority_test`、`equipment_attribute_master_test`、`equipment_slot_migration_test`、`equipment_inventory_slot_swap_test`、`equipment_service_rules_test`、`equipment_precise_durability_test`、`equipment_durability_policy_test`、`equipment_customization_test`、`equipment_special_effects_test`、`equipment_special_phase2_test`、`equipment_luck_test`、`equipment_success_notice_real_input_test` | 165934 另有 `armor_single_slot_authority_test` PASS。`equipment_skill_level_affix_test`：NOT_RUN；它是词条 canonical/legacy 聚合、无效值与不可变性合同，不等于宠物有效 rank 真实行为证明。可按主控本轮有效 rank 变更选补，不应把所有未注册美术测试都升级为阻塞 |
| 商店、金币、银行 | `scripts/shop_panel.gd:1048 _request_sell_batch`、`:1088 _confirm_pending_sell`、`:1300 _buy_selected` → `scripts/player_state.gd:1198 buy_shop_item`、`:1253 sell_inventory_item`、`:1313 sell_inventory_items`；银行 `scripts/warehouse_panel.gd:849` await `scripts/player_state.gd:6536 transfer_shared_gold_prepared` | `pricing_authority_test`、`r3_gold_cap_entrypoints_test`、`complete_item_system_test`、`shop_gothic_ui_test`；`shared_warehouse_transaction_test` 还覆盖共享金币、重复序列/WAL、历史迁移 | **`tests/repair_20260913/bank_prepared_transaction_test.tscn`：NOT_RUN。** 实际按钮、旧显示快照重复交易拒绝、跨物品/银行重叠、写入故障及 UI 销毁边界都有现成测试。`tests/r6_1_review/shop_selection_identity_test.tscn`：NOT_RUN，可补同名/同模板实例选择与显示身份专项 |
| 任务接取、进度、奖励、放弃 | `scripts/player_state.gd:2527 accept_quest`、`:2546 abandon_quest`、`:2642 claim_quest`；`scripts/quest_panel.gd:519 _request_abandon`、`:549 _confirm_abandon` | `bich_quest_chain_test`、`progression_test`、`vertical_slice_loop_test`、`complete_item_system_test` | `quest_gothic_ui_test`：NOT_RUN。它除了布局，还包含放弃确认/取消稳定 ID、接受按钮调用正式接口、完成/未解锁状态、人工布局重放。已有 quest chain PASS，不能说任务玩法整体遗漏 |
| 触摸、攻击、摇杆、列表拖动 | `scripts/game_root.gd:1366 gameplay_input_is_enabled`、`:1374/:1383` 输入锁、`:2494 _cancel_player_input_boundary`；`scripts/touch_scroll_support.gd:18 attach_tree`、`:96 _input`、`:115/:129/:156` 手势生命周期 | `android_attack_action_lifecycle_test`、`virtual_joystick_lifecycle_test`、`circular_touch_button_lifecycle_test`、`gameplay_input_gate_test`、`input_release_cleanup_test`、`initial_world_input_lock_test`、`game_root_spell_lock_input_integration_test`；地图切换输入锁见失败复验表 | `touch_scroll_support_test` 与 `character_select_touch_scroll_test`：NOT_RUN。前者验证实际技能卡拖动阈值、释放不误点击、共享拖动状态与多个 UI 接入；后者验证角色列表。自动合成事件 PASS 不等于设备多点触控体验 PASS |
| 死亡、复活、回城 | `scripts/game_root.gd:6192 _on_player_death_requested`、`:6249 _on_revival_requested`、`:3771 _request_production_town_revival`；`scripts/player.gd:979 complete_death_revival` | `death_revival_home_failure_test`、`death_revival_touch_input_test`、`player_movement_respawn_test`、`player_status_effect_lifecycle_test` | 已有真实行为与失败路径 PASS；`death_revival_gothic_ui_test`：NOT_RUN，主要是 UI 合同，不能据此否定已测复活玩法。当前最终 APK 真机死亡/回城/继续操作：NOT_RUN（本报告范围） |
| 音频播放与设置 | `project.godot:32 AudioPreferences` → `scripts/audio_preferences.gd:40 set_level`、`:75 _apply`、`:92 _read_valid`、`:112 flush`；`scripts/game_root.gd:2553 _on_system_menu_audio_setting_changed`；`scripts/audio_runtime_service.gd:210/:230`；`scripts/town_music_controller.gd:146/:164/:213` | `town_music_controller_test`、`audio_runtime_service_test`、`player_core_audio_hook_test`、`summon_audio_hook_test`、`monster_audio_hook_test`、`projectile_audio_lifecycle_test`、`player_item_audio_event_test`、`audio_w4_actor_service_test`、`audio_w4_contract_test` | **`tests/loot_ui_20260914/settings_function_test.tscn`、`ui_r5_audio_config_strict_test`、`ui_r5_audio_test`：NOT_RUN。** 分别补正式设置滑块/过滤器与关闭持久化、配置类型/备份/零值/失败 dirty、偏好应用合同。`town_music_runtime_test`：NOT_RUN，补 GameRoot→HUD READY→城镇音乐等待门；该旧 fixture 只等固定 4 帧，应由主控分类真实失败与夹具过时，不删断言或把失败算通过。设备实际听感：NOT_RUN |
| 暂停、继续、失焦恢复 | `scripts/game_root.gd:1736 _notification`，`:1742` pause/focus-out，`:1748` resume；`:2451 _show_system_menu`、`:2462 _hide_system_menu`、`:2486 _release_system_menu_pause` | **`system_menu_test`**、`input_release_cleanup_test`、`gameplay_input_gate_test`；system_menu 真正实例化 GameRoot，用 HUD 攻击/摇杆事件验证菜单取消输入、Android 返回、意外隐藏、自有暂停与外部暂停、锁定状态下 pause/focus-out 清理 | 这条自动化路径已有覆盖，不新增“暂停功能完全未测”结论。Android 真实后台→前台、系统中断丢 UP、音频实际恢复及存档保留仍需最终包设备验证：NOT_RUN |

## 3. 精确补测候选，交由主控串行执行

以下场景均已存在，本报告没有新增测试。当前 `run_godot_tests.ps1:521` 的 `audit_upgrade_critical` 包含旧存档/仓库事务专项，`:544` 开始聚合 critical，`:582/:610` 加入音频/物品/仓库等；下列场景在指定 429 项 JSON 没有记录，不能用“属于同一系统”推断已跑。主控已表示将补角色存档、银行及设置专项。

优先补真实生产消费者所对应的独立入口：

1. `tests/repair_20260913/warehouse_prepared_transaction_test.tscn`
2. `tests/repair_20260913/bank_prepared_transaction_test.tscn`
3. `tests/character_delete_transaction_test.tscn`
4. `tests/player_world_position_unit_migration_test.tscn`
5. `tests/loot_ui_20260914/settings_function_test.tscn`
6. `tests/ui_r5_audio_config_strict_test.tscn`
7. `tests/ui_r5_audio_test.tscn`
8. `tests/touch_scroll_support_test.tscn`
9. `tests/character_select_touch_scroll_test.tscn`

系统遍历若还需 UI/接入边界收口，按范围加：

- `tests/r6_1_review/shop_selection_identity_test.tscn`
- `tests/quest_gothic_ui_test.tscn`
- `tests/town_music_runtime_test.tscn`（留意其旧固定帧等待夹具）
- `tests/equipment_skill_level_affix_test.tscn`（仅在需要覆盖本轮有效 rank 的装备输入时）

不把性能采样、全部历史 UI 布局、美术预览或旧债强制纳入以上功能缺口。仓库 prepared 专项虽输出延迟数据，本报告建议它是因为生产事务断言；它的 PASS 不等于性能达标。`loot_gold_pickup_test`、`monster_gold_drop_runtime_test`、`death_revival_gothic_ui_test` 等也不在指定 critical 中，但其系统已有对应 PASS；是否追加由主控结合本轮实际 diff 决定，不为扩大数量而重复跑。

## 4. 主控后续交付仍需独立固定的证据

- 最终 critical：NOT_RUN（本文指定证据是旧 425/429 加逐项闭环，主控计划重跑）。
- 上述补测：NOT_RUN（此报告截至停止扩展时；后续以主控新 runner JSON 更新验收）。
- 新 APK 构建源 SHA/dirty 内容闭包、版本、签名、包名、包含资源与精确 SHA256：NOT_RUN（此机械清单没有验证新产物）。
- 最终包覆盖升级、真实角色/仓库/设置保留、触摸、音频、暂停恢复：DEVICE TEST NOT_RUN（本文范围）。
- 本文件只读核对完成，不代替主控对当前战斗、召唤物、蜈蚣洞/赤月密集战斗、火墙/AOE、物理与法术分层等新增需求的专项裁决；那些要求继续以主控计划及对应专项报告收口。

没有发现需要在本报告范围内修改生产代码的已复现缺陷。确定结论是：有些核心系统已由真实 critical PASS 覆盖，而若干现成测试覆盖当前 UI 消费的不同异步/持久化路径，不能遗漏也不能混用旧测试结果替代。
