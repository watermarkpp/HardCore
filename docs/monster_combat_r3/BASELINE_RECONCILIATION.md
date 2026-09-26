# R3 基线逐项核对（R2 critical 失败集 → 当前树）

核对方法：R2 critical 失败集 `runner_results_critical_20260926_213740_693_4912.json`（34 项）
在 R3 当前树定向重跑（`runner_results_adhoc_20260927_002743_993_13916.json`，非 full critical，
仅基线失败项）。逐项三分类：`CLOSED_THIS_ROUND` / `MONSTER_DOMAIN_PENDING`（本轮范围待修）/
`OTHER_DOMAIN_OWNERSHIP`（非怪物域，登记归属，不越权修）。

## 一、已转绿（5 项）

| 测试 | 判定 |
|---|---|
| tests/monster_audio_hook_test.tscn | `CLOSED_THIS_ROUND` — R3-W2 音频阶段改绑动作逻辑年龄后通过（合同同步修改） |
| tests/monster_struck_visual_queue_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过（R2 时 stderr 失败） |
| tests/monster_streaming_animation_continuity_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过 |
| tests/placeholder_attack_animation_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过 |
| tests/bich_common_client_art_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过（R2 遗留"负载敏感未定性"就此关闭：负载非敏感，PASS） |

## 二、怪物域待修（6 项，R3-W7 前逐项处理）

| 测试 | 当前失败原因（本轮实测） | 备注 |
|---|---|---|
| tests/all_monster_loading_test.tscn | `ID=183 missing attack timing`（early_script_error） | 183 的攻击时序字段缺失——R1 身体/时序普查已见 183 缺 timing |
| tests/monster_world_integration_test.tscn | `catalog runtime policy count drifted` | 目录运行策略计数漂移 |
| tests/classic_boss_order_test.tscn | `祖玛教主召唤上限或稳定monsterId集合错误` | Boss 召唤合同 |
| tests/monster_mfc1_attribute_timing_audit_test.tscn | `mv_speed_runtime_vs_auth:33/183/241; atk_authority_missing:183/241; formal_runtime_accidental_default:2` | 与 R2 同原因（BASELINE_EXISTING 候选） |
| tests/monster_cadence_runtime_integration_test.tscn | `safe-zone branch must use the shared autonomous-step executor`（272 checks 通过后单点失败） | 安全区分支执行器 |
| tests/monster_special_delivery_runtime_test.tscn | `70 special melee exceeded its one-GU boundary` + `124 frozen area magic` | 特殊投递边界——与 R3-03 朝向/距离政策相关，需核对是否被本轮改动影响 |

## 三、非怪物域归属（23 项，登记不越权）

技能/施法视觉域（14）：caster_skill_visual_factory_entry、caster_skill_animation_routing、
sky_strike_visual_contract、lightning_runtime_map_visual、canonical_skill_production_entry、
skill_production_no_visual_plan、skill_production_profession_matrix、
skill_production_descriptor_failure_parity、skill_runtime_no_visual_plan、
warrior_skill_state_machine、skills/warrior_thrust_defense_runtime、w6_visual_contract、
live_attack_resolution、melee_lock_fallback（刺杀连续轴近段未命中——近战锁定向，归属
professions-skills/integration 线）。

快照/资源/环境/音频服务域（6）：canonical_snapshot_propagation、
canonical_snapshot_identity_production、production_snapshot_no_legacy、
enemy_snapshot_v2_production（`schema V2` 断言）、complete_client_resource_catalog、
combat_environment_request_integration。

装备/掉落域（2）：armor_single_slot_authority、repair_20260913/loot_async_durability
（`store_string on null`——outputs 写入路径问题）。

音频服务域（1）：audio_w4_actor_service（真实服务提示/起点/帧三连播断言——R2 W4 遗留）。

## 诚实边界

- 本文档是**分类登记**，不是关闭。二类 6 项在 R3-W7 前逐项修复或给出明确归属证据；
  三类 23 项按项目所有权边界归对应专业线，怪物包不做顺手修改。
- 5 项转绿均有当前树 runner JSON 证据；判定 `CLOSED_THIS_ROUND` 的依据是同测试在当前
  树 PASS，与 R2 失败原因的逐字比对在 full critical 复核时一并留证。
