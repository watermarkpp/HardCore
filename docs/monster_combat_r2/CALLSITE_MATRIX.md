# HC-MONSTER-COMBAT-R2 T1 调用点矩阵（CALLSITE_MATRIX）

- 依据源码：R2 候选 `2960bbe682b61306eed8f7c9fe0c6eb6c6accb9a`（逐行核对 `scripts/enemy.gd` 8813 行）
- 用途：T1 门禁要求的生产调用点清单——攻击表现入口、怪物侧伤害投递/接收入口、身体消费者。
- 深度普查数据文件：`docs/monster_combat_r2/runtime_census.json`（由 `tests/hc_monster_combat_r2/runtime_census_deep_test.gd` 生成，schema `hardcore.monster.combat.r2.runtime_census.v2`）。

## 1. 攻击表现入口（`_play_attack_animation` 的全部生产调用点）

| 行号 | 所属函数 | 通道 | 说明 |
|---|---|---|---|
| enemy.gd:2718 | `_physics_process_internal` | 普通物理近战（非 HC 主通道的 legacy engagement 分支） | engagement_ready 且冷却结束时；与 :8011 HC 通道并存 |
| enemy.gd:5474 | `_update_area_magic_delivery` | 范围魔法（area_magic） | warning 时长取 `_attack_animation_duration` 与 `_area_magic_warning` 较大者 |
| enemy.gd:5721 | `_update_area_attack` | 范围攻击（melee area 家族） | 带前摇时长表达式 |
| enemy.gd:7686 | `_update_boss_skill` | Boss 技能 | 时长取 `special.animationSeconds` |
| enemy.gd:8011 | `_hc_tick_melee` | HC 标准近战主通道（`hc_standard_melee`） | `_hc_try_start` 内：先创建 release record（含 release_id/life/epoch/map/parent），后调用表现 |

**身份缺口（R3-01/R3-02/W1 的施工面）**：五个入口都只传 `duration`；`_hc_try_start` 的 release record 不含父动作身份字段；表现层内部另起 `_attack_logic_serial`。

## 2. 怪物侧伤害投递（怪物→玩家）结算点

| 位置 | 函数 | 通道 |
|---|---|---|
| enemy.gd:3834 `_update_pending_attack` | 延迟投递分发器 | hc_standard_melee→`_hc_settle`；physical_projectile/target_magic/line_magic/special cell→各自 settle 族 |
| enemy.gd:5214/5216 | `_deal_area_magic_damage` | AOE 直接 `take_damage` + `apply_life_steal` |
| enemy.gd:7644/7659 | `_update_boss_skill` 家族 | Boss 技能目标伤害 |
| enemy.gd:8016 `_hc_settle` | HC 近战即时结算 | life/epoch/map/parent 复核后伤害 |

## 3. 怪物/玩家/召唤接收入口（玩家→怪物方向）

| 位置 | 说明 |
|---|---|
| enemy.gd `take_damage` → `_apply_damage_core` | 怪物接收唯一核心（R1 F06 所在层） |
| skill_projectile.gd:710 | 玩家投射物命中怪物 |
| summon_actor.gd:832 | 召唤物攻击命中 |
| warrior_combat_math.gd:135 | 战士近战数学 |

## 4. 身体消费者清单（必须同源半径）

| 消费者 | 位置/合同 |
|---|---|
| 出生选点 footprint | `configure_spawn_release_footprint` / spawn snapshot（`target_combat_radius_gu`） |
| 空间索引注册 | EnemyActor 入树后物理/空间注册 |
| 近战接触距离 | `_contact_distance_gu_to_target`（ra+rt+0.4375，生产权威） |
| 起手准入 | 1.5 GU 中心距 + EPS（`GroundUnitSpace.EPSILON_GU`=1e-4） |
| 召唤出生 snapshot | `summon_body_spawn_consistency_test` 锁定非空+半径精确 |
| 重召/换图/重定位 | zone_generation + runtime_map_id 校验 |

## 5. 普查矩阵统计（runtime_census.json）

- 156 身份全覆盖；147 战斗（combatEnabled=true）+ 9 合同禁战（226-234，combatEnabled=false，身体完整接受）
- 逐 ID 字段：canonical_name/classification/runtime_allowed/source_attack_interval_ms/timing_resolution/source_max_hp/boss_rule_nonempty/body_{tier,px,gu,hash,rule}/loaded_max_hp/loaded_attack_min/max/loaded_attack_interval_s/effective_attack_interval_s/effective_delivery_kind/boss_skill_enabled/boss_phase_enabled/body_fallback/body_resolved_tier/movement_authority_valid/configured_walk_interval_ms/rejection_reason/tested_source_sha
- 空 delivery rule = ordinary_melee 合同（`_hc_try_start` 中 `kind==""` 时 hit_delay 生效即证）
