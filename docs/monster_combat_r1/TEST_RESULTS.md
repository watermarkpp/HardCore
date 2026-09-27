# HC-MONSTER-COMBAT-R1 + HC-BODY-2TIER-1P5-V1 测试结果（TEST_RESULTS）

证据规则：正式结论均取自 `outputs/test_logs/runner_results_*.json` 的 `git_head/total/passed/failed/test_path/result/reason` 字段；终端行仅辅助定位。基线对照树：`C:\Users\Administrator\Documents\HardCore-worktrees\mct-r1-baseline-check`（junction tools/godot-4.7 + `--import`，与当前树同 `-TimeoutSeconds`）。

## 1. Level 1 反例存证（修复前，未修必须 FAIL）

- `runner_results_adhoc_20260926_000612_528_958.json`（head=f5d6308f，5/5 FAIL）：
  - `boss_interval_test`（F02：boss 空规则 2.5s 覆写）
  - `player_visual_duration_test`（F04：非受击表现被 FIFO 稀释）
  - `player_poison_reapply_test`（F05：复活/死亡边界毒重挂）
  - `attack_presentation_backlog_test`（F01：受击背压下攻击表现丢失/重复）
  - `continuous_magic_walk_delay_test`（F03：6 参新签名不存在 → 解析错误，属授权证据的一部分）
- Task 7 反例（`runner_results_adhoc_20260926_002556_996_102.json`，2/2 FAIL）：`damage_boundary_test`（F06）、`death_reentry_test`（F08/F07）。

## 2. Level 1 修复后（全部 PASS）

- `runner_results_adhoc_20260926_004256_813_174.json`（head=11ae1056，16/17 PASS）：7 个 R1 测试全 PASS；唯一 FAIL 为 `monster_audio_hook_test`（既有实时竞态夹具，见 §5 处置）。
- Task 7 后 `damage_boundary_test`/`death_reentry_test` PASS（`…002708`、`…004902` 序列）。
- 身体 4 测试：`runner_results_adhoc_20260926_011952_878_463.json`（head=0c5970a3 工作树→commit 38affced，2/2）+ 前批 2/2（`…011717` 中 2 个直接 PASS）——actor_body_policy_contract / actor_body_projection / monster_melee_body_pair / summon_body_spawn_consistency 全 PASS。
- 性能探针：`runner_results_adhoc_20260926_013131_120_5272.json` PASS（head=38affced 工作树→commit 5401a0bc，内容与提交一致）。

## 3. Level 2 相关回归（PASS 批次）

- 批 1 `runner_results_adhoc_20260926_012250_763_511.json`（16/16 PASS）：monster_cadence_blocked_step、monster_struck_visual_queue、monster_struck_runtime、monster_ground_unit_runtime、skeleton_spirit_boss、combat_epoch_delivery、monster_threat_animation、player_status_effect_lifecycle、player_poison_presentation、warrior_visual、monster_audio_hook、boss_interval、attack_presentation_backlog、continuous_magic_walk_delay、damage_boundary、death_reentry。
- 批 2 `runner_results_adhoc_20260926_012512_967_208.json`（11/12）：summon_growth_rank_upgrade、mapped_summon_missing_projection_rejected、combat_absolute_ground_integration、taoist_entrapment_boundary_production、monster_exact_effects、bich_runtime_fidelity、bich_monster_visual、bich_undead_client_art、placeholder_attack_animation、monster_mfc2_animation_special_audit、monster_animation_cpu_profile 全 PASS；唯一 FAIL 见 §4。
- 修复前早期批次 `…001406`（11/12）与 `…001720`（10/16）中的 FAIL 全部进入 §4 基线分类；修复后批次未再出现（monster_ground_unit_runtime 夹具对齐后 PASS；monster_audio_hook 加固后 4/4 稳定）。

## 4. Level 4 基线三分类（当前 FAIL → 基线只跑失败项）

| # | 测试 | 当前失败点 | 基线结果 | 判定 |
|---|---|---|---|---|
| 1 | classic_boss_order_test:124 | 断言旧值 maxActive 30 / 池 [153,156,150,159] | 同断言同因 FAIL | **BASELINE_EXISTING**（权威数据已由用户裁决 maxActive 15/池[156,153,150,128] A 级 ObjMon.pas；测试文件更新早于 7ffc1f3f 数据修正） |
| 2 | warrior_skill_state_machine_test:33 | 断言失败（职业域旧断言） | 同断言同因 FAIL | **BASELINE_EXISTING** |
| 3 | monster_runtime_texture_cache_test:90 | 缓存断言 | 同断言同因 FAIL | **BASELINE_EXISTING** |
| 4 | r6_3_1/m30_counts_12_15_test | `_apply_attack_damage` 签名漂移解析错 | 同解析错误 FAIL | **BASELINE_EXISTING** |
| 5 | hc_monster_ai/performance_comparison_test | 同签名漂移解析错 | 同解析错误 FAIL | **BASELINE_EXISTING** |
| 6 | monster_special_delivery_runtime_test:100/129 | 投递断言 | 同断言同因 FAIL | **BASELINE_EXISTING** |
| 7 | divine_beast_animation_test:110 | "死亡没有保留death动作" | 同断言同因同文本 FAIL | **BASELINE_EXISTING**（基线复证：runner_results_adhoc_20260926_012529_452_14788.json，基线树） |

以上 7 项均与本包修改文件（enemy/monster_visual/monster_movement_cadence/player/player_visual/summon_actor/actor_body_policy/monster_identity/catalog）无调用链交集，未修改，留证待所有者。

## 5. 过程中的修复（非基线）

- `monster_ground_unit_runtime_test`：锥形 boss_rule 夹具缺显式 opt-in → 加 `"enabled": true` + `enemy._boss_skill_enabled = true`（合同夹具对齐，非断言弱化）→ PASS。
- `monster_audio_hook_test` flaky：插桩定位（唯一负缓存安装在设计路径 setter@113 clock1000；失败运行大量 `seen=false target_valid=false`）→ 根因=夹具裸 Node2D 目标存活性与启动期异步地图注册竞速 → 物理帧窗口化夹具（不改断言语义）→ 4/4 稳定 PASS；enemy.gd 插桩全部还原（diff 仅剩 F06 守卫）。
- continuous_magic_walk_delay 夹具首跳 `evaluate(100)` 不授权（新 cadence 自 t=0 起 400ms 间隔）→ `evaluate(500)` + 消息（夹具修正）。

## 6. full critical（Level 3，本轮一次）

- 命令：`tools/run_godot_tests.ps1 -Suite critical`（工作树 commit `5401a0bc` 干净 HEAD）。
- 证据：`outputs/test_logs/runner_results_critical_20260926_024720_379_4564.json` — `git_head=5401a0bc6e1e8d8836d4b744382788bc7045a398`，**total=482 passed=452 failed=30**。
- 30 个失败项全部按 §4 规则基线分类（基线只跑这 30 项，一批完成：基线树 `runner_results_adhoc_20260926_025357_734_6280.json`，30 项 → 1 PASS / 29 FAIL）。

### 最终三分类

| 判定 | 数量 | 明细 |
|---|---|---|
| **BASELINE_EXISTING** | 29 | caster_skill_visual_factory_entry（stdout 门禁：RID 泄漏）、caster_skill_animation_routing、sky_strike_visual_contract、lightning_runtime_map_visual、canonical_skill_production_entry（:185 火墙canonical真实入口被拒绝）、canonical_snapshot_propagation、enemy_snapshot_v2_production（:107+:74）、production_snapshot_no_legacy（:133）、canonical_snapshot_identity_production、skill_production_no_visual_plan、skill_production_profession_matrix、skill_production_descriptor_failure_parity、skill_runtime_no_visual_plan、complete_client_resource_catalog（缺 outputs/resource_catalog manifest 工件）、warrior_skill_state_machine（:33）、live_attack_resolution（:226）、melee_lock_fallback（:83）、all_monster_loading（:40 ID=183 missing attack timing）、monster_world_integration（:36 catalog runtime policy count drifted）、classic_boss_order（:124）、bich_monster_visual（:78）、monster_mfc1_attribute_timing_audit（ID 33/183/241 authority missing/auth=0）、monster_cadence_runtime_integration（:842 safe-zone 分支执行器断言）、monster_special_delivery_runtime（:100/:129）、skills/warrior_thrust_defense_runtime（:83）、w6_visual_contract、combat_environment_request_integration（以上 engine-log 门禁族根因同为 `caster_skill_animation_player.gd:75` ready 期 add_child，生产路径既有问题）、armor_single_slot_authority（:23）、repair_20260913/loot_async_durability（:82 store_string null） |
| **FAIL_CHANGED（人工审查后定性为套件负载抖动，非回归）** | 1 | vertical_slice_loop_test：critical 序列中 FAIL 仅 engine-log 门禁（`world_background.gd:786` dummy-renderer RID 噪声 + `[FRAME-STALL]` 1.004s 长帧 + ObjectDB 泄漏警告），测试自印 `VERTICAL_SLICE_LOOP_PASS`（与基线序列一致）。隔离复跑当前树 3/3 PASS 且 `engine_log_errors=0`（`runner_results_adhoc_20260926_025758/025817/025836`），基线隔离 PASS。失败不在本包任何修改文件的调用链内（world_background.gd 未修改）。 |
| **REGRESSION** | 0 | — |

### 断言文本机械比对（当前 vs 基线，godot.log 逐条）

同断言文本同位置逐项 MATCH=True：all_monster_loading（ID=183 missing attack timing）、monster_world_integration（catalog runtime policy count drifted）、bich_monster_visual（钉耙猫 移动方向错误）、monster_cadence_runtime_integration（safe-zone branch must use the shared autonomous-step executor）、warrior_skill_state_machine（半月首次开关被通用施法预检错误拒绝）、melee_lock_fallback（刺杀连续轴近段未命中）、live_attack_resolution（法师没有在释放帧创建正式投射物）、classic_boss_order（祖玛教主召唤上限或稳定monsterId集合错误）、monster_special_delivery_runtime（70 special melee exceeded its one-GU boundary）、warrior_thrust_defense（无文本 assert，同签名）、armor_single_slot（无文本 assert，同签名）、loot_async_durability（Cannot call method 'store_string' on a null value，同文本）。

## 7. 结论

- 本包修改链（enemy/monster_visual/monster_movement_cadence/player/player_visual/summon_actor/actor_body_policy/monster_identity/catalog 身体字段）在 full critical 482 项中**零回归**。
- 29 项既有失败 + 1 项负载抖动均已逐项留证，未修改、未删除断言、未降低任何门禁。
