# R3 基线逐项核对（R2 critical 失败集 → 当前树）

核对方法：R2 critical 失败集 `runner_results_critical_20260926_213740_693_4912.json`（34 项）
在 R3 当前树定向重跑（`runner_results_adhoc_20260927_002743_993_13916.json`，非 full critical，
仅基线失败项）。逐项三分类：`CLOSED_THIS_ROUND` / `USER_DATA_GAP`（需用户权威数据补全）/
`OTHER_DOMAIN_OWNERSHIP`（非怪物域，登记归属，不越权修）。

## 一、已修复转绿（9 项）

| 测试 | 判定 |
|---|---|
| tests/monster_audio_hook_test.tscn | `CLOSED_THIS_ROUND` — R3-W2 音频阶段改绑动作逻辑年龄后通过（合同同步修改） |
| tests/monster_struck_visual_queue_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过（R2 时 stderr 失败） |
| tests/monster_streaming_animation_continuity_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过 |
| tests/placeholder_attack_animation_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过 |
| tests/bich_common_client_art_test.tscn | `CLOSED_THIS_ROUND` — 当前树通过（R2 遗留"负载敏感未定性"就此关闭：负载非敏感，PASS） |
| tests/classic_boss_order_test.tscn | `CLOSED_THIS_ROUND`（W6）— 祖玛召古断言对齐反编译权威（CallSlave：maxActive 15、kind 集合 [156,153,150,128]、count 4..7）；旧断言 30/[153,156,150,159] 是权威之前的过时值 |
| tests/monster_world_integration_test.tscn | `CLOSED_THIS_ROUND`（W6）— 目录权威 156/156 全允许（R1 终局变体退役；两次重建字节一致）；旧断言 153 是交付前的过时值 |
| tests/monster_cadence_runtime_integration_test.tscn | `CLOSED_THIS_ROUND`（W6）— safe-zone 处理器在同一 tick 立即提交撤退决策（清目标/关战斗会话），grant 帧经共享执行器以 return_to_spawn 移动；断言改为要求共享执行器本身 |
| tests/monster_special_delivery_runtime_test.tscn | `CLOSED_THIS_ROUND`（W6）— 70 走 HC 标准近战准入，其魔法近战在统一 1.5 GU 起手内结算（R1冻结合同）：1.01 GU 命中、1.51 GU 拒绝；旧 1.0 GU 边界是统一射程前的过时合同 |

## 二、用户数据缺口（2 项，需用户权威数值补全）

| 测试 | 当前失败原因（本轮实测） | 归属 |
|---|---|---|
| tests/monster_mfc1_attribute_timing_audit_test.tscn | `mv_speed_runtime_vs_auth:33/183/241; atk_authority_missing:183/241; formal_runtime_accidental_default:2` | 21cq 用户权威源本身对 183/241 的 attackIntervalMs=0、对 33/183/241 无 moveSpeed 权威值；代码不能凭空造数值，runtime 也不得擅自把 0 裁决为"不攻击"（会改变行为）。**需用户提供这三个 ID 的权威攻击间隔与移速**后经正式生成链补录 |
| tests/all_monster_loading_test.tscn | `ID=183 missing attack timing`（early_script_error） | 同一根因：183 权威 attackIntervalMs=0，`attackIntervalMs > 0` 断言失败。随上项一并由用户数据补全关闭 |

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

- 一类 9 项均有当前树 runner JSON 证据；其中 4 项（W6）的测试期望修改都有明确权威依据
  （反编译合同 / 目录权威 / R1 冻结的统一射程），不是为让失败转绿而放宽断言。
- 二类 2 项保持 FAIL 是**诚实状态**：根因是用户权威数据缺口，任何代码侧"修复"要么伪造
  数值要么擅自改变玩法行为，均违反权威源纪律。补录路径：用户提供 33/183/241 的权威
  攻击间隔/移速 → 21cq 源更新 → 正式生成链重建 → 两项随目录转绿。
- 三类 23 项按项目所有权边界归对应专业线，怪物包不做顺手修改。

