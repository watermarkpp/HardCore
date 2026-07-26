# 热血传奇1.76三职业33技能｜Codex可施工唯一真源 v1.0.1

## 1. 结论

本规范把资料分为三层，禁止互相冒充：

1. **historical_verified**：1.76技能成员、中文语义、人物等级和熟练度。
2. **source_formula_reference**：Mir2 1.5/1.76开源服务端中可追溯的公式与状态机。
3. **project_canonical**：历史资料无法唯一确定时，为本项目冻结的唯一运行值。

“正确”不等于假装所有历史数字都能被证明。无法证明的数值已经明确标记为
`project_canonical`，Codex可以直接施工，但不得把它写成“盛大官方原值”。

## 2. 不可违反的全局规则

- Vanilla Core **恰好33个技能**：战士6、法师14、道士13。
- 学会技能时为内部 `rank=0`；L1–L3同时要求人物等级和当前段熟练度。
- 每次合格成功事件获得 `1–3` 熟练度；升级后当前段熟练度归零。
- 失败、取消、非法目标、材料不足、路径阻挡导致的失败均不增长熟练度。
- 所有技能效果只允许从 `SkillRuntimeRouter` 权威执行。
- `game_root._on_player_skill()` 不得直接计算伤害、治疗、Buff、召唤或材料。
- 旧 `delay` 改名为 `legacy_delay`，只作审计。
- 游戏范围统一使用tile；禁止115px、260px、430px等裸像素作为技能逻辑。
- 法师/道士主动人物施法动作冻结为 **8方向×6帧×100ms=600ms**。
- 当前360ms只可保留为明确的非Vanilla可选加速，不得继续冒充1.76基线。
- 当前MP数组冻结为 `project_canonical_mp_v1`，因为其完整且与内嵌服务端候选一致；
  但尚无充分证据证明它逐项就是盛大官方原始MP表。

## 3. 33技能总表

| # | 技能 | 稳定ID | 人物等级 L0/L1/L2/L3 | 熟练 L0/L1/L2/L3 | MP L0/L1/L2/L3 | 激活 | 运行族 |
|---:|---|---|---|---|---|---|---|
| 1 | 基本剑术 | `warrior.basic_swordsmanship` | 7/7/11/16 | —/1000/4000/8000 | 0/0/0/0 | passive | passive_stat_modifier |
| 2 | 攻杀剑术 | `warrior.slaying_swordsmanship` | 19/19/22/24 | —/4000/8000/16000 | 0/0/0/0 | passive_proc | melee_proc_modifier |
| 3 | 刺杀剑术 | `warrior.thrusting` | 25/25/27/29 | —/6000/12000/18000 | 0/0/0/0 | toggle_attack_mode | two_cell_melee |
| 4 | 半月弯刀 | `warrior.half_moon` | 28/28/31/34 | —/8000/16000/24000 | 3/3/3/3 | toggle_attack_mode | melee_arc |
| 5 | 野蛮冲撞 | `warrior.wild_rush` | 30/30/34/39 | —/3000/6000/9000 | 4/8/12/16 | active | level_gated_push |
| 6 | 烈火剑法 | `warrior.fire_sword` | 35/35/37/40 | —/2000/4000/6000 | 7/7/7/7 | active_charge | next_melee_charge |
| 7 | 火球术 | `wizard.fireball` | 7/7/11/16 | —/500/1500/3000 | 3/5/7/9 | active | single_projectile_damage |
| 8 | 抗拒火环 | `wizard.repulsion_ring` | 12/12/15/19 | —/800/2400/4000 | 2/4/6/8 | active | area_push_no_damage |
| 9 | 诱惑之光 | `wizard.temptation_light` | 13/13/18/24 | —/1000/2000/4000 | 3/4/5/6 | active | monster_tame_or_control |
| 10 | 地狱火 | `wizard.hellfire` | 16/16/21/26 | —/1000/4000/8000 | 10/13/16/19 | active | line_damage |
| 11 | 雷电术 | `wizard.lightning` | 17/17/20/23 | —/1200/3000/5000 | 9/11/13/15 | active | targeted_sky_strike |
| 12 | 大火球 | `wizard.great_fireball` | 19/19/23/25 | —/8000/14000/25000 | 5/6/7/8 | active | single_projectile_damage |
| 13 | 瞬息移动 | `wizard.teleport` | 19/19/22/25 | —/1000/2000/4000 | 10/13/16/19 | active | random_teleport |
| 14 | 爆裂火焰 | `wizard.exploding_flame` | 22/22/27/31 | —/3000/6000/18000 | 14/18/22/26 | active | target_centered_area_damage |
| 15 | 火墙 | `wizard.fire_wall` | 24/24/29/33 | —/4000/12000/24000 | 30/35/40/45 | active | persistent_ground_damage |
| 16 | 疾光电影 | `wizard.laser` | 26/26/29/32 | —/3000/6000/12000 | 38/45/52/59 | active | piercing_line_damage |
| 17 | 地狱雷光 | `wizard.hell_lightning` | 30/30/32/34 | —/4000/8000/12000 | 29/38/47/56 | active | caster_centered_area_damage |
| 18 | 魔法盾 | `wizard.magic_shield` | 31/31/34/38 | —/4000/8000/12000 | 35/40/45/50 | active | self_damage_reduction_buff |
| 19 | 圣言术 | `wizard.holy_word` | 32/32/35/39 | —/4000/8000/12000 | 52/65/78/91 | active | undead_instant_kill_check |
| 20 | 冰咆哮 | `wizard.ice_storm` | 35/35/37/40 | —/4000/8000/12000 | 33/36/39/42 | active | target_centered_area_damage |
| 21 | 治愈术 | `taoist.healing` | 7/7/11/16 | —/500/1500/3000 | 3/5/7/9 | active | single_heal |
| 22 | 精神力战法 | `taoist.spiritual_warfare` | 9/9/13/19 | —/1000/4000/8000 | 0/0/0/0 | passive | passive_stat_modifier |
| 23 | 施毒术 | `taoist.poison` | 14/14/17/20 | —/1000/2000/4000 | 2/3/4/5 | active | two_type_poison_debuff |
| 24 | 灵魂火符 | `taoist.soul_fire_talisman` | 18/18/21/24 | —/2000/4000/6000 | 3/4/5/6 | active | single_projectile_damage |
| 25 | 召唤骷髅 | `taoist.summon_skeleton` | 19/19/23/26 | —/2000/4000/8000 | 12/16/20/24 | active | persistent_main_pet |
| 26 | 隐身术 | `taoist.invisibility` | 20/20/23/26 | —/3000/6000/9000 | 1/2/3/4 | active | monster_aggro_stealth |
| 27 | 集体隐身术 | `taoist.mass_invisibility` | 21/21/25/29 | —/2000/4000/8000 | 2/4/6/8 | active | area_monster_aggro_stealth |
| 28 | 幽灵盾 | `taoist.magic_defense` | 22/22/24/26 | —/5000/10000/15000 | 2/4/6/8 | active | area_friendly_defence_buff |
| 29 | 神圣战甲术 | `taoist.defense` | 25/25/27/29 | —/5000/10000/15000 | 2/4/6/8 | active | area_friendly_defence_buff |
| 30 | 心灵启示 | `taoist.revelation` | 26/26/30/35 | —/4000/8000/12000 | 4/8/12/16 | active | target_hp_information_reveal |
| 31 | 困魔咒 | `taoist.entrapment` | 28/28/30/32 | —/3000/6000/12000 | 7/10/13/16 | active | monster_boundary_control |
| 32 | 群体治疗术 | `taoist.mass_healing` | 33/33/35/38 | —/4000/8000/12000 | 28/31/34/37 | active | area_heal |
| 33 | 召唤神兽 | `taoist.summon_divine_beast` | 35/35/37/40 | —/2000/4000/8000 | 28/32/36/40 | active | persistent_main_pet |

## 4. 通用公式

### 4.1 Pascal随机数

```text
Random(n) = [0, n-1]，上界不包含；n<=0时返回0
```

### 4.2 Magic.DB原始威力随机

```text
MPow = Power + Random(MaxPower - Power)
```

### 4.3 普通等级成长

```text
GetPower =
round(BaseInput / 4 × (Rank + 1))
+ DefPower
+ Random(DefMaxPower - DefPower)
```

### 4.4 一三式等级成长

```text
GetPower13 =
round(
    (BaseInput - BaseInput / 3)
    / (TrainRankMax + 1)
    × (Rank + 1)
    + BaseInput / 3
    + DefPower
    + Random(DefMaxPower - DefPower)
)
```

### 4.5 职业属性掷值

```text
DC/MC/SC roll = [Min, Max]闭区间
```

### 4.6 防御

技能运行时只返回：

```text
raw_power
damage_type
defence_type
ignore_defence_flags
```

最终命中和防御必须进入统一战斗管线，禁止每个技能复制一套AC/MAC公式。

## 5. 逐技能施工规格

### 1. 基本剑术 — `warrior.basic_swordsmanship`

- **等级/熟练：** L0:人物7级、熟练0 / L1:人物7级、熟练1000 / L2:人物11级、熟练4000 / L3:人物16级、熟练8000
- **MP：** 0 / 0 / 0 / 0
- **激活：** `passive`
- **目标：** `self_stat`
- **几何：** `none`
- **运行族：** `passive_stat_modifier`
- **人物动作：** `None`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "passive_stat_modifier",
  "stat": "accuracy",
  "flat_bonus_by_rank": [
    0,
    3,
    6,
    9
  ],
  "affects": [
    "physical_melee_hit_checks"
  ],
  "does_not_affect": [
    "spell_hit",
    "poison_resist",
    "holy_word",
    "soul_fire_talisman"
  ],
  "status": "project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_basic_melee_attack_resolved",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_swing": 1
}
```
- **4b6ea4e0差异：** 当前准确+0/+3/+6/+9，效果基本正确；正常游戏无熟练度成长。
- **必须测试：** basic_swordsmanship_accuracy_by_rank, basic_swordsmanship_never_casts, basic_swordsmanship_physical_only

### 2. 攻杀剑术 — `warrior.slaying_swordsmanship`

- **等级/熟练：** L0:人物19级、熟练0 / L1:人物19级、熟练4000 / L2:人物22级、熟练8000 / L3:人物24级、熟练16000
- **MP：** 0 / 0 / 0 / 0
- **激活：** `passive_proc`
- **目标：** `current_melee_target`
- **几何：** `melee_front`
- **运行族：** `melee_proc_modifier`
- **人物动作：** `None`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "melee_proc_modifier",
  "proc_chance_by_rank": [
    0.1,
    0.125,
    0.1666666667,
    0.25
  ],
  "flat_dc_bonus_by_rank": [
    5,
    6,
    7,
    8
  ],
  "flat_accuracy_bonus_by_rank": [
    0,
    1,
    2,
    3
  ],
  "damage_type": "physical",
  "defence_type": "AC",
  "trigger_order": "after_valid_swing_before_damage_roll",
  "status": "project_canonical",
  "evidence_note": "CN 1.76文字确认命中率与破坏力随等级提升；具体四档数值按项目表冻结。"
}
```
- **熟练度事件：**
```json
{
  "event": "successful_slaying_proc_on_valid_melee_swing",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_swing": 1
}
```
- **4b6ea4e0差异：** 数据表触发1/10、1/8、1/6、1/4；实际代码1/(7-rank)，且说明/汇总未完整体现准确加成。
- **必须测试：** slaying_proc_table_exact, slaying_dc_bonus_exact, slaying_accuracy_bonus_exact, slaying_training_only_on_proc

### 3. 刺杀剑术 — `warrior.thrusting`

- **等级/熟练：** L0:人物25级、熟练0 / L1:人物25级、熟练6000 / L2:人物27级、熟练12000 / L3:人物29级、熟练18000
- **MP：** 0 / 0 / 0 / 0
- **激活：** `toggle_attack_mode`
- **目标：** `line_melee_targets`
- **几何：** `line`
- **运行族：** `two_cell_melee`
- **人物动作：** `None`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "two_cell_melee",
  "first_cell": {
    "damage_multiplier": 1.0,
    "defence_type": "AC",
    "ignore_ac": false
  },
  "second_cell": {
    "damage_multiplier_by_rank": [
      0.4,
      0.6,
      0.8,
      1.0
    ],
    "defence_type": "AC",
    "ignore_ac": true,
    "status": "project_canonical"
  },
  "same_swing_base_dc_roll": true,
  "may_hit_first_and_second_cell_in_one_swing": true,
  "status": "project_canonical",
  "evidence_note": "CN 1.76确认间隔一身位/两目标成直线触发；第二格破防与倍率由经典玩法+当前项目冻结。"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_thrusting_swing_with_at_least_one_eligible_target",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_swing": 1
}
```
- **4b6ea4e0差异：** 当前只有第二格40%/60%/80%/100%倍率，未明确第二格无视AC、双格同击与统一DC掷值。
- **必须测试：** thrusting_two_cell_line, thrusting_second_cell_multiplier, thrusting_second_cell_ignores_ac, thrusting_one_training_event_per_swing

### 4. 半月弯刀 — `warrior.half_moon`

- **等级/熟练：** L0:人物28级、熟练0 / L1:人物28级、熟练8000 / L2:人物31级、熟练16000 / L3:人物34级、熟练24000
- **MP：** 3 / 3 / 3 / 3
- **激活：** `toggle_attack_mode`
- **目标：** `melee_arc`
- **几何：** `project_canonical_four_target_arc`
- **运行族：** `melee_arc`
- **人物动作：** `None`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "melee_arc",
  "primary_damage_multiplier": 1.0,
  "side_damage_multiplier_by_rank": [
    0.15,
    0.23,
    0.31,
    0.3846153846
  ],
  "damage_type": "physical",
  "defence_type": "AC",
  "max_training_events_per_swing": 1,
  "status": "project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_half_moon_swing_with_at_least_one_eligible_target",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_swing": 1
}
```
- **4b6ea4e0差异：** 侧面倍率约15%/23%/31%/38%；缺统一四目标弧形偏移定义、MP消耗时点与每刀只训练一次。
- **必须测试：** half_moon_primary_full_damage, half_moon_side_multiplier, half_moon_rotates_all_8_directions, half_moon_mp_once_per_swing, half_moon_training_once_per_swing

### 5. 野蛮冲撞 — `warrior.wild_rush`

- **等级/熟练：** L0:人物30级、熟练0 / L1:人物30级、熟练3000 / L2:人物34级、熟练6000 / L3:人物39级、熟练9000
- **MP：** 4 / 8 / 12 / 16
- **激活：** `active`
- **目标：** `front_adjacent_blocking_target`
- **几何：** `line_push`
- **运行族：** `level_gated_push`
- **人物动作：** `dash`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "level_gated_push",
  "eligibility": {
    "caster_level_must_exceed_target_level": true,
    "boss_immune": true,
    "immovable_immune": true,
    "safe_zone_forbidden": true
  },
  "success_probability": "clamp((6 + 6 * rank + caster_level - target_level) / 20.0, 0.0, 1.0)",
  "push_distance_by_rank": [
    1,
    1,
    2,
    3
  ],
  "caster_moves_into_vacated_path": true,
  "collision_self_damage": {
    "expression": "max(1, floor(caster.max_hp * 0.01))",
    "status": "project_canonical",
    "trigger": "dash path blocked after movement begins"
  },
  "status": "mixed_source_and_project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "target_successfully_displaced_at_least_one_tile",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前距离3/3/4/5格、成功率(rank*4+6+等级差)/20；与经典源码参考的1/1/2/3和rank*6冲突，且缺撞墙自伤。
- **必须测试：** wild_rush_lower_level_only, wild_rush_probability_formula, wild_rush_distance_by_rank, wild_rush_collision_self_damage, wild_rush_boss_immune, wild_rush_training_only_on_displacement

### 6. 烈火剑法 — `warrior.fire_sword`

- **等级/熟练：** L0:人物35级、熟练0 / L1:人物35级、熟练2000 / L2:人物37级、熟练4000 / L3:人物40级、熟练6000
- **MP：** 7 / 7 / 7 / 7
- **激活：** `active_charge`
- **目标：** `self_next_melee_charge`
- **几何：** `none_until_next_melee_hit`
- **运行族：** `next_melee_charge`
- **人物动作：** `cast_or_weapon_charge`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "next_melee_charge",
  "damage_multiplier_by_rank": [
    1.4,
    1.8,
    2.2,
    2.6
  ],
  "consume_on": "next_valid_melee_damage_attempt",
  "auto_cast": false,
  "refresh_existing_charge": "replace_and_restart_duration",
  "stack_count_max": 1,
  "status": "project_canonical_with_classic_multiplier_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "charged_fire_sword_is_consumed_by_valid_melee_attack",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_charge": 1
}
```
- **4b6ea4e0差异：** 倍率正确，但当前自动开关/自动释放且CD10秒；应改为主动蓄火、下一次近战消耗。
- **必须测试：** fire_sword_never_auto_casts, fire_sword_multiplier_exact, fire_sword_charge_expires, fire_sword_consumed_once, fire_sword_cooldown_independent_from_charge_lifetime

### 7. 火球术 — `wizard.fireball`

- **等级/熟练：** L0:人物7级、熟练0 / L1:人物7级、熟练500 / L2:人物11级、熟练1500 / L3:人物16级、熟练3000
- **MP：** 3 / 5 / 7 / 9
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `projectile`
- **运行族：** `single_projectile_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "single_projectile_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "magic",
  "defence_type": "MAC",
  "projectile_visual_is_not_authoritative": true,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_projectile_cast_created",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 360px弹道、伤害只等于一次MC掷值；技能基础威力和等级成长被覆盖。
- **必须测试：** fireball_uses_target_and_los, fireball_power_formula, fireball_rank_increases_expected_power, fireball_mac_defence

### 8. 抗拒火环 — `wizard.repulsion_ring`

- **等级/熟练：** L0:人物12级、熟练0 / L1:人物12级、熟练800 / L2:人物15级、熟练2400 / L3:人物19级、熟练4000
- **MP：** 2 / 4 / 6 / 8
- **激活：** `active`
- **目标：** `surrounding_units`
- **几何：** `adjacent_ring`
- **运行族：** `area_push_no_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "area_push_no_damage",
  "damage": 0,
  "eligibility": "target.level < caster.level and not target.boss and not target.immovable",
  "success_probability": "clamp((6 + 3 * rank + caster_level - target_level) / 20.0, 0.0, 1.0)",
  "push_distance_formula": "1 + max(0, rank - 1) + pascal_random_exclusive(2)",
  "path_collision_required": true,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "at_least_one_target_displaced",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 115px内固定推80px；缺目标等级压制、成功率、按格位移和阻挡。
- **必须测试：** repulsion_no_damage, repulsion_lower_level_only, repulsion_probability, repulsion_push_distance, repulsion_collision

### 9. 诱惑之光 — `wizard.temptation_light`

- **等级/熟练：** L0:人物13级、熟练0 / L1:人物13级、熟练1000 / L2:人物18级、熟练2000 / L3:人物24级、熟练4000
- **MP：** 3 / 4 / 5 / 6
- **激活：** `active`
- **目标：** `hostile_or_neutral_monster_single`
- **几何：** `targeted_light`
- **运行族：** `monster_tame_or_control`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "monster_tame_or_control",
  "source_branch_policy": {
    "selected_branch": "pre_2020_classic_intent_reconstructed_from_commented_code",
    "status": "project_canonical",
    "reason": "公开源码明确标注2020-02-04提高成功率并延长宠物判变时间；本项目不采用修改后的Random(1)必过分支，而采用注释中保留的Random(3)经典门槛。"
  },
  "eligibility": {
    "monster_only": true,
    "target_master_must_be_none_or_self": true,
    "not_boss": true,
    "tameable_flag_required_for_tame": true,
    "undead_can_never_be_tamed": true,
    "target_level_lte_caster_plus": 2,
    "target_level_lte_server_cap": 50,
    "pet_cap_by_rank": [
      2,
      3,
      4,
      5
    ]
  },
  "attempt_state_machine": [
    {
      "step": 1,
      "condition": "pascal_random_exclusive(4 - rank) == 0",
      "on_fail": "no_effect; cast may still display visual but gains no proficiency"
    },
    {
      "step": 2,
      "condition": "pascal_random_exclusive(2) == 0",
      "on_fail": {
        "effect": "root",
        "duration_seconds": "pascal_random_exclusive(rank * 5 + 10)"
      }
    },
    {
      "step": 3,
      "condition": "target_level <= caster_level + 2",
      "on_fail": "no_tame; no_control_result"
    },
    {
      "step": 4,
      "condition": "pascal_random_exclusive(3) == 0",
      "on_fail": {
        "non_undead": "confusion",
        "duration_seconds": "pascal_random_exclusive(20) + 10",
        "undead": "no_effect"
      }
    },
    {
      "step": 5,
      "condition": "pascal_random_exclusive(caster_level + 20 + rank * 5) > target_level + 10",
      "on_fail": {
        "non_undead_confusion_chance": "1/20",
        "confusion_duration_seconds": "pascal_random_exclusive(20) + 10",
        "undead": "no_effect"
      }
    },
    {
      "step": 6,
      "condition": "tameable and not_undead and target_level <= 50 and current_pet_count < rank + 2",
      "on_fail": {
        "undead_instant_death_chance": "1/20",
        "otherwise": "no_tame"
      }
    },
    {
      "step": 7,
      "condition": "pascal_random_exclusive(tame_difficulty) == 0",
      "on_fail": {
        "instant_death_chance": "1/14",
        "otherwise": "no_tame"
      },
      "on_success": "assign_master_and_pet_slot"
    }
  ],
  "tame_difficulty": {
    "hp_rate_divisor": 100,
    "expression": "q = floor(target_max_hp / 100); tame_difficulty = 2 if q <= 2 else q * 2",
    "lower_is_easier": true
  },
  "on_tame_success": {
    "assign_master": true,
    "set_tamed_flag": true,
    "pet_make_level": "rank",
    "walk_speed_cap_ms": "1500 - rank * 200",
    "attack_interval_cap_ms": "2000 - rank * 200",
    "loyalty_duration_ms": "(pascal_random_exclusive(caster_level * 2) + rank * 20 + 20) * 60 * 1000",
    "loyalty_formula_status": "project_canonical_reconstructed_from_original_commented_formula"
  },
  "proficiency_success_events": [
    "target_tamed",
    "target_rooted",
    "target_confused",
    "eligible_target_instantly_killed_by_temptation_branch"
  ],
  "proficiency_failure_events": [
    "invalid_target",
    "pet_cap_reached",
    "all_probability_gates_fail_without_state_change"
  ],
  "status": "project_canonical_reconstructed_classic_branch",
  "evidence_note": "技能的瘫痪、混乱、驯服语义由CN 1.76资料确认；门槛与分支来自公开Pascal源码及其保留的旧代码注释。由于该文件在2020年被明确修改，不能把任何一条概率冒充盛大官方原始值。"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_attempt_reaches_tame_or_control_resolution",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前弹道命中后固定魅惑6秒；未实现瘫痪/混乱/永久驯服、宠物上限和智力/等级资格。
- **必须测试：** temptation_monster_only, temptation_boss_immune, temptation_pet_cap, temptation_tame_probability_deterministic, temptation_failure_control, temptation_not_six_second_generic_charm

### 10. 地狱火 — `wizard.hellfire`

- **等级/熟练：** L0:人物16级、熟练0 / L1:人物16级、熟练1000 / L2:人物21级、熟练4000 / L3:人物26级、熟练8000
- **MP：** 10 / 13 / 16 / 19
- **激活：** `active`
- **目标：** `facing_line`
- **几何：** `line`
- **运行族：** `line_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "line_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_cast_releases_line",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前260px前方宽范围；正确应为面前5格、宽1格、受地形阻挡。
- **必须测试：** hellfire_exact_five_tile_line, hellfire_width_one, hellfire_stops_on_terrain, hellfire_power_formula

### 11. 雷电术 — `wizard.lightning`

- **等级/熟练：** L0:人物17级、熟练0 / L1:人物17级、熟练1200 / L2:人物20级、熟练3000 / L3:人物23级、熟练5000
- **MP：** 9 / 11 / 13 / 15
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `sky_strike_targeted`
- **运行族：** `targeted_sky_strike`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "targeted_sky_strike",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "race_multiplier": {
    "undead": 1.5,
    "default": 1.0
  },
  "damage_type": "lightning_magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_targeted_cast_resolves",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前410px横向弹道、只取一次MC；正确表现为目标上方落雷，并在雷电术处理不死系×1.5。
- **必须测试：** lightning_is_sky_strike, lightning_no_horizontal_projectile, lightning_undead_multiplier, lightning_power_formula

### 12. 大火球 — `wizard.great_fireball`

- **等级/熟练：** L0:人物19级、熟练0 / L1:人物19级、熟练8000 / L2:人物23级、熟练14000 / L3:人物25级、熟练25000
- **MP：** 5 / 6 / 7 / 8
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `projectile`
- **运行族：** `single_projectile_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "single_projectile_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_projectile_cast_created",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前390px弹道、伤害只等于一次MC；缺技能自身基础威力和等级成长。
- **必须测试：** great_fireball_los, great_fireball_power_formula, great_fireball_expected_power_exceeds_or_differs_from_fireball

### 13. 瞬息移动 — `wizard.teleport`

- **等级/熟练：** L0:人物19级、熟练0 / L1:人物19级、熟练1000 / L2:人物22级、熟练2000 / L3:人物25级、熟练4000
- **MP：** 10 / 13 / 16 / 19
- **激活：** `active`
- **目标：** `self_random_destination`
- **几何：** `random_valid_map_destination`
- **运行族：** `random_teleport`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "random_teleport",
  "success_probability": "(2 * rank + 4) / 11.0",
  "success_roll": "pascal_random_exclusive(11) < 2 * rank + 4",
  "on_success": "select valid random destination according to map teleport policy; optional town-return branch whose weight increases with rank",
  "on_failure": "remain_in_place",
  "destination_rules": [
    "walkable",
    "not_blocked",
    "map_allows_random_teleport",
    "server_authoritative"
  ],
  "status": "source_formula_reference_plus_project_destination_policy"
}
```
- **熟练度事件：**
```json
{
  "event": "teleport_attempt_passes_eligibility_and_resolves",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前固定向面朝方向移动220px；完全不是随机传送。
- **必须测试：** teleport_never_forward_dash, teleport_probability_exact, teleport_failure_stays_in_place, teleport_destination_valid, teleport_server_authoritative

### 14. 爆裂火焰 — `wizard.exploding_flame`

- **等级/熟练：** L0:人物22级、熟练0 / L1:人物22级、熟练3000 / L2:人物27级、熟练6000 / L3:人物31级、熟练18000
- **MP：** 14 / 18 / 22 / 26
- **激活：** `active`
- **目标：** `ground_or_target_point`
- **几何：** `square`
- **运行族：** `target_centered_area_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "target_centered_area_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "fire_magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_area_cast_created",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前以玩家为中心260px全范围；正确为选定目标点中心3×3。
- **必须测试：** exploding_flame_target_centered, exploding_flame_exact_3x3, exploding_flame_power_formula

### 15. 火墙 — `wizard.fire_wall`

- **等级/熟练：** L0:人物24级、熟练0 / L1:人物24级、熟练4000 / L2:人物29级、熟练12000 / L3:人物33级、熟练24000
- **MP：** 30 / 35 / 40 / 45
- **激活：** `active`
- **目标：** `ground_point`
- **几何：** `square`
- **运行族：** `persistent_ground_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "persistent_ground_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "fire_magic",
  "defence_type": "MAC",
  "stacking_policy": "same_caster_same_tile_refreshes_duration; one target takes at most one tick per caster per tick",
  "max_active_fields_per_caster": "config_required_default_8",
  "status": "project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_fire_wall_field_created",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前半径74px圆、持续5秒、0.8秒一跳；另有2×2描述和五格十字公式三套冲突。
- **必须测试：** fire_wall_exact_2x2, fire_wall_duration_scales, fire_wall_tick_once_per_caster, fire_wall_refresh_not_stack, fire_wall_not_circle_or_cross

### 16. 疾光电影 — `wizard.laser`

- **等级/熟练：** L0:人物26级、熟练0 / L1:人物26级、熟练3000 / L2:人物29级、熟练6000 / L3:人物32级、熟练12000
- **MP：** 38 / 45 / 52 / 59
- **激活：** `active`
- **目标：** `facing_line`
- **几何：** `line`
- **运行族：** `piercing_line_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "piercing_line_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "magic",
  "defence_type": "MAC",
  "undead_multiplier": 1.0,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_line_cast_released",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前430px前方宽范围；应为宽1格、前方8格穿透直线，不带不死系+50%。
- **必须测试：** laser_exact_eight_tile_line, laser_width_one, laser_pierces_units, laser_stops_on_terrain, laser_no_undead_bonus

### 17. 地狱雷光 — `wizard.hell_lightning`

- **等级/熟练：** L0:人物30级、熟练0 / L1:人物30级、熟练4000 / L2:人物32级、熟练8000 / L3:人物34级、熟练12000
- **MP：** 29 / 38 / 47 / 56
- **激活：** `active`
- **目标：** `caster_surrounding_area`
- **几何：** `chebyshev_ring`
- **运行族：** `caster_centered_area_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "caster_centered_area_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "lightning_magic",
  "defence_type": "MAC",
  "maximum_targets": 24,
  "status": "source_formula_reference_plus_cn_text"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_area_cast_released",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前玩家周围150px全范围、无24目标上限，伤害只等于MC。
- **必须测试：** hell_lightning_max_24, hell_lightning_caster_centered_radius_2, hell_lightning_excludes_center, hell_lightning_power_formula

### 18. 魔法盾 — `wizard.magic_shield`

- **等级/熟练：** L0:人物31级、熟练0 / L1:人物31级、熟练4000 / L2:人物34级、熟练8000 / L3:人物38级、熟练12000
- **MP：** 35 / 40 / 45 / 50
- **激活：** `active`
- **目标：** `self`
- **几何：** `none`
- **运行族：** `self_damage_reduction_buff`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "self_damage_reduction_buff",
  "duration_seconds_formula": "max(1, get_power(rank, roll_mc() + 15))",
  "damage_reduction_by_rank": [
    0.15,
    0.3,
    0.45,
    0.6
  ],
  "affected_damage_types": [
    "physical",
    "magic"
  ],
  "not_affected": [
    "true_damage",
    "environmental_unless_tagged"
  ],
  "stacking_policy": "refresh_same_buff; no stacking",
  "status": "project_canonical",
  "evidence_note": "CN 1.76确认同时减物理与魔法；开源源码确认持续时间受MC/等级影响。精确减伤四档公开资料存在冲突，本项目冻结15/30/45/60%。"
}
```
- **熟练度事件：**
```json
{
  "event": "shield_buff_successfully_applied_or_refreshed",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前固定12秒、固定35%；未接正式公式又存在技能越高减伤越低的反向错误。
- **必须测试：** magic_shield_reduction_increases_by_rank, magic_shield_reduces_physical_and_magic, magic_shield_duration_uses_mc, magic_shield_refresh_not_stack

### 19. 圣言术 — `wizard.holy_word`

- **等级/熟练：** L0:人物32级、熟练0 / L1:人物32级、熟练4000 / L2:人物35级、熟练8000 / L3:人物39级、熟练12000
- **MP：** 52 / 65 / 78 / 91
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `targeted`
- **运行族：** `undead_instant_kill_check`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "undead_instant_kill_check",
  "eligibility": {
    "monster_only": true,
    "is_undead_required": true,
    "boss_or_holy_word_immune_rejected": true,
    "precheck": "pascal_random_exclusive(2) + (caster_level - 1) > target_level",
    "target_level_cap": "server_config_holy_word_max_target_level"
  },
  "kill_probability": "clamp((7 * rank + 15 + caster_level - target_level) / 100.0, 0.0, 1.0)",
  "on_success": "set_target_hp_to_zero_with_holy_word_reason",
  "on_failure": "no_normal_damage",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "instant_kill_success",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前是普通MC伤害弹道；正确应只对不死系做一击必杀概率判定，失败无普通伤害。
- **必须测试：** holy_word_undead_only, holy_word_boss_immune, holy_word_probability_exact, holy_word_success_kills, holy_word_failure_no_damage, holy_word_training_on_success_only

### 20. 冰咆哮 — `wizard.ice_storm`

- **等级/熟练：** L0:人物35级、熟练0 / L1:人物35级、熟练4000 / L2:人物37级、熟练8000 / L3:人物40级、熟练12000
- **MP：** 33 / 36 / 39 / 42
- **激活：** `active`
- **目标：** `ground_or_target_point`
- **几何：** `square`
- **运行族：** `target_centered_area_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "target_centered_area_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_mc()",
  "damage_type": "ice_magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_area_cast_released",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前以玩家为中心300px全范围；正确为选定目标区域3×3。
- **必须测试：** ice_storm_target_centered, ice_storm_exact_3x3, ice_storm_power_formula

### 21. 治愈术 — `taoist.healing`

- **等级/熟练：** L0:人物7级、熟练0 / L1:人物7级、熟练500 / L2:人物11级、熟练1500 / L3:人物16级、熟练3000
- **MP：** 3 / 5 / 7 / 9
- **激活：** `active`
- **目标：** `self_or_friendly_single`
- **几何：** `targeted`
- **运行族：** `single_heal`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "single_heal",
  "heal_formula": "get_power(rank, mpow(magic_db)) + 2 * roll_sc()",
  "cap_at_target_max_hp": true,
  "friendly_only": true,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "actual_hp_restored_gt_zero",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前只治疗自己、治疗量一次SC；正确可治疗自己或友方，技能基础治疗+2×SC。
- **必须测试：** healing_self_or_friendly, healing_rejects_hostile, healing_formula, healing_training_only_if_hp_restored

### 22. 精神力战法 — `taoist.spiritual_warfare`

- **等级/熟练：** L0:人物9级、熟练0 / L1:人物9级、熟练1000 / L2:人物13级、熟练4000 / L3:人物19级、熟练8000
- **MP：** 0 / 0 / 0 / 0
- **激活：** `passive`
- **目标：** `self_stat`
- **几何：** `none`
- **运行族：** `passive_stat_modifier`
- **人物动作：** `None`，身体动作 `0ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "passive_stat_modifier",
  "stat": "accuracy",
  "flat_bonus_by_rank": [
    0,
    3,
    5,
    8
  ],
  "affects": [
    "physical_melee_hit_checks"
  ],
  "does_not_affect": [
    "soul_fire_talisman",
    "spell_hit",
    "poison_resist"
  ],
  "status": "project_canonical_with_open_source_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_taoist_melee_attack_resolved",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_swing": 1
}
```
- **4b6ea4e0差异：** 当前不增加准确且可进入施法流程；应为永久被动，无MP、无CD、无施法动作。
- **必须测试：** spiritual_warfare_accuracy_exact, spiritual_warfare_never_casts, spiritual_warfare_no_cooldown, spiritual_warfare_physical_only

### 23. 施毒术 — `taoist.poison`

- **等级/熟练：** L0:人物14级、熟练0 / L1:人物14级、熟练1000 / L2:人物17级、熟练2000 / L3:人物20级、熟练4000
- **MP：** 2 / 3 / 4 / 5
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `targeted`
- **运行族：** `two_type_poison_debuff`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `selected_poison_powder`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "two_type_poison_debuff",
  "resist_success_condition": "pascal_random_exclusive(target.poison_resist + 7) <= 6",
  "green_power_formula": "get_power13(rank, 40) + 2 * roll_sc()",
  "red_power_formula": "get_power13(rank, 30) + 2 * roll_sc()",
  "duration_seconds": "[8,12,16,20][rank] + floor(roll_sc() / 5.0)",
  "duration_status": "project_canonical",
  "green_poison": {
    "tick_interval_ms": 2000,
    "damage_per_tick": "max(1, floor(green_power / 10.0))",
    "damage_type": "poison"
  },
  "red_poison": {
    "flat_ac_reduction": "max(1, floor(red_power / 10.0))",
    "flat_mac_reduction": "max(1, floor(red_power / 10.0))",
    "extra_equipment_durability_loss_per_successful_incoming_hit": 1,
    "durability_status": "project_canonical"
  },
  "stacking": "green_and_red_can_coexist; same type refreshes stronger/longer according to BuffMergePolicy",
  "status": "mixed_source_and_project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "poison_status_successfully_applied_or_refreshed",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前只有绿毒、固定8秒、约SC/3且不消耗毒粉；缺红毒减防减耐久。
- **必须测试：** poison_consumes_selected_powder, poison_green_and_red_separate, poison_resist_formula, poison_green_ticks, poison_red_reduces_ac_mac, poison_same_type_refreshes

### 24. 灵魂火符 — `taoist.soul_fire_talisman`

- **等级/熟练：** L0:人物18级、熟练0 / L1:人物18级、熟练2000 / L2:人物21级、熟练4000 / L3:人物24级、熟练6000
- **MP：** 3 / 4 / 5 / 6
- **激活：** `active`
- **目标：** `hostile_single`
- **几何：** `projectile`
- **运行族：** `single_projectile_damage`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "single_projectile_damage",
  "raw_power_formula": "get_power(rank, mpow(magic_db)) + roll_sc()",
  "damage_type": "spirit_magic",
  "defence_type": "MAC",
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "valid_talisman_projectile_created",
  "requires_hit": false,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前370px弹道、伤害一次SC、不消耗护身符；应消耗1张并使用技能基础威力+SC。
- **必须测试：** soul_fire_requires_one_amulet, soul_fire_requires_los, soul_fire_power_formula, soul_fire_no_material_loss_on_invalid_target

### 25. 召唤骷髅 — `taoist.summon_skeleton`

- **等级/熟练：** L0:人物19级、熟练0 / L1:人物19级、熟练2000 / L2:人物23级、熟练4000 / L3:人物26级、熟练8000
- **MP：** 12 / 16 / 20 / 24
- **激活：** `active`
- **目标：** `self_summon`
- **几何：** `nearest_valid_adjacent_tile`
- **运行族：** `persistent_main_pet`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "persistent_main_pet",
  "pet_group": "taoist_main_pet",
  "group_limit": 1,
  "recast_if_live_pet_exists": "recall_existing_pet_no_material_and_no_proficiency",
  "new_pet_template": "skeleton",
  "initial_pet_level_formula": "rank",
  "max_pet_level_formula": "rank + 4",
  "skill_rank_is_pet_level": false,
  "replacement_policy": "never_delete_live_pet_just_to_create_new_one",
  "status": "source_formula_reference_plus_project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "new_skeleton_successfully_spawned",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前不耗符并强制替换旧召唤物；应已有宠则召回，无宠才耗1符创建。
- **必须测试：** summon_skeleton_consumes_one_amulet_only_on_new_spawn, summon_skeleton_recast_recalls, taoist_main_pet_limit_one, summon_skill_rank_separate_pet_level, summon_skeleton_no_forced_delete

### 26. 隐身术 — `taoist.invisibility`

- **等级/熟练：** L0:人物20级、熟练0 / L1:人物20级、熟练3000 / L2:人物23级、熟练6000 / L3:人物26级、熟练9000
- **MP：** 1 / 2 / 3 / 4
- **激活：** `active`
- **目标：** `self`
- **几何：** `none`
- **运行族：** `monster_aggro_stealth`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "monster_aggro_stealth",
  "duration_seconds_formula": "max(1, get_power13(rank, 30) + 3 * roll_sc())",
  "pvp_invisibility": false,
  "untargetable": false,
  "invulnerable": false,
  "monster_detection": "ignored_by_normal_monsters; true_sight_monsters_ignore_buff",
  "break_conditions": {
    "tile_movement": true,
    "melee_attack": false,
    "ranged_spell_cast": false,
    "taking_damage": false
  },
  "status": "source_formula_reference_plus_cn_text",
  "evidence_note": "1.76文字明确隐身后可采用远程魔法攻击，因此施法本身不应自动破隐；移动破除按经典行为冻结。"
}
```
- **熟练度事件：**
```json
{
  "event": "invisibility_buff_successfully_applied",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前自己固定隐身10秒；缺护身符、SC/等级时长、怪物仇恨语义与破除规则。
- **必须测试：** invisibility_consumes_amulet, invisibility_monster_aggro_only, invisibility_not_pvp_untargetable, invisibility_duration_formula, invisibility_breaks_on_move, invisibility_spell_cast_does_not_break

### 27. 集体隐身术 — `taoist.mass_invisibility`

- **等级/熟练：** L0:人物21级、熟练0 / L1:人物21级、熟练2000 / L2:人物25级、熟练4000 / L3:人物29级、熟练8000
- **MP：** 2 / 4 / 6 / 8
- **激活：** `active`
- **目标：** `ground_point_friendly_area`
- **几何：** `square`
- **运行族：** `area_monster_aggro_stealth`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "area_monster_aggro_stealth",
  "duration_seconds_formula": "max(1, get_power13(rank, 30) + 3 * roll_sc())",
  "affected_entities": [
    "self",
    "friendly_players"
  ],
  "excluded": [
    "hostile_players",
    "monsters",
    "npcs_unless_explicit"
  ],
  "break_conditions": {
    "tile_movement": true,
    "melee_attack": false,
    "ranged_spell_cast": false,
    "taking_damage": false
  },
  "status": "source_formula_reference_plus_cn_text"
}
```
- **熟练度事件：**
```json
{
  "event": "at_least_one_valid_friendly_receives_buff",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前也只让自己隐身10秒；正确为选定点3×3友方玩家范围。
- **必须测试：** mass_invisibility_exact_3x3, mass_invisibility_affects_friendlies, mass_invisibility_not_self_only, mass_invisibility_consumes_one_amulet_on_success

### 28. 幽灵盾 — `taoist.magic_defense`

- **等级/熟练：** L0:人物22级、熟练0 / L1:人物22级、熟练5000 / L2:人物24级、熟练10000 / L3:人物26级、熟练15000
- **MP：** 2 / 4 / 6 / 8
- **激活：** `active`
- **目标：** `ground_point_friendly_area`
- **几何：** `chebyshev_area`
- **运行族：** `area_friendly_defence_buff`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "area_friendly_defence_buff",
  "buff_id": "buff.taoist.soul_shield_mac",
  "stat": "MAC",
  "flat_bonus_formula": "max(1, floor(target.level / 7.0))",
  "duration_seconds_formula": "max(1, floor((get_power13(rank, 60) + 10 * roll_sc()) / 10.0))",
  "stacking_policy": "refresh_same_buff; coexists_with_blessed_armour",
  "status": "project_canonical",
  "evidence_note": "CN 1.76和源码分支一致确认幽灵盾=MAC；精确点数/时长公开资料不唯一，因此冻结此公式。"
}
```
- **熟练度事件：**
```json
{
  "event": "at_least_one_valid_friendly_receives_or_refreshes_buff",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前只给自己固定15秒、数值人物等级/8，并与神圣战甲术共用简化逻辑。
- **必须测试：** soul_shield_modifies_mac_only, soul_shield_area_radius_3, soul_shield_coexists_with_blessed_armour, soul_shield_consumes_amulet_on_success

### 29. 神圣战甲术 — `taoist.defense`

- **等级/熟练：** L0:人物25级、熟练0 / L1:人物25级、熟练5000 / L2:人物27级、熟练10000 / L3:人物29级、熟练15000
- **MP：** 2 / 4 / 6 / 8
- **激活：** `active`
- **目标：** `ground_point_friendly_area`
- **几何：** `chebyshev_area`
- **运行族：** `area_friendly_defence_buff`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "area_friendly_defence_buff",
  "buff_id": "buff.taoist.blessed_armour_ac",
  "stat": "AC",
  "flat_bonus_formula": "max(1, floor(target.level / 7.0))",
  "duration_seconds_formula": "max(1, floor((get_power13(rank, 60) + 10 * roll_sc()) / 10.0))",
  "stacking_policy": "refresh_same_buff; coexists_with_soul_shield",
  "status": "project_canonical",
  "evidence_note": "CN技能页此行疑似误写MAC；经典服务端type=0/1分支确认神圣战甲术对应物防AC。"
}
```
- **熟练度事件：**
```json
{
  "event": "at_least_one_valid_friendly_receives_or_refreshes_buff",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前与幽灵盾走同一简化逻辑；正确必须只加AC并使用独立Buff。
- **必须测试：** blessed_armour_modifies_ac_only, blessed_armour_area_radius_3, blessed_armour_coexists_with_soul_shield, blessed_armour_consumes_amulet_on_success

### 30. 心灵启示 — `taoist.revelation`

- **等级/熟练：** L0:人物26级、熟练0 / L1:人物26级、熟练4000 / L2:人物30级、熟练8000 / L3:人物35级、熟练12000
- **MP：** 4 / 8 / 12 / 16
- **激活：** `active`
- **目标：** `player_or_monster_single`
- **几何：** `targeted`
- **运行族：** `target_hp_information_reveal`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "target_hp_information_reveal",
  "success_probability": "clamp((rank + 4) / 6.0, 0.0, 1.0)",
  "success_roll": "pascal_random_exclusive(6) <= rank + 3",
  "duration_ms_formula": "get_power13(rank, 2 * roll_sc() + 30) * 1000",
  "reveals": [
    "current_hp",
    "max_hp"
  ],
  "damage": 0,
  "does_not_modify_target_stats": true,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "reveal_successfully_applied",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前必定显示最近怪物2秒；正确应手动指定玩家/怪物，并按成功率与SC/等级决定时长。
- **必须测试：** revelation_manual_target, revelation_targets_player_or_monster, revelation_probability_exact, revelation_duration_formula, revelation_no_damage

### 31. 困魔咒 — `taoist.entrapment`

- **等级/熟练：** L0:人物28级、熟练0 / L1:人物28级、熟练3000 / L2:人物30级、熟练6000 / L3:人物32级、熟练12000
- **MP：** 7 / 10 / 13 / 16
- **激活：** `active`
- **目标：** `ground_point_hostile_monster_area`
- **几何：** `hexagon_boundary_approximated_on_8dir_grid`
- **运行族：** `monster_boundary_control`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[1, 1, 1, 1]`
- **权威机制：**
```json
{
  "runtime_family": "monster_boundary_control",
  "duration_seconds_formula": "max(1, get_power13(rank, 40) + 3 * roll_sc())",
  "eligible": [
    "hostile_monster",
    "not_boss",
    "not_control_immune",
    "within_level_gate"
  ],
  "excluded": [
    "players",
    "npcs",
    "friendly_pets",
    "bosses"
  ],
  "behavior_inside": "monster cannot path outside boundary and circles/retargets internally",
  "external_attack_behavior": "may evade external attacks according to trapped state",
  "break_conditions": [
    "any_player_enters_boundary",
    "duration_expires",
    "map_transition",
    "caster_invalid_if_policy_requires"
  ],
  "status": "source_formula_reference_plus_cn_text"
}
```
- **熟练度事件：**
```json
{
  "event": "at_least_one_eligible_monster_enters_trapped_state",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前前方区域怪物固定定身5秒；缺发光边界、环绕行为、玩家进入破除和外部攻击躲避。
- **必须测试：** entrapment_monsters_only, entrapment_boss_immune, entrapment_boundary_prevents_exit, entrapment_breaks_on_player_entry, entrapment_consumes_amulet_only_on_success, entrapment_not_generic_root

### 32. 群体治疗术 — `taoist.mass_healing`

- **等级/熟练：** L0:人物33级、熟练0 / L1:人物33级、熟练4000 / L2:人物35级、熟练8000 / L3:人物38级、熟练12000
- **MP：** 28 / 31 / 34 / 37
- **激活：** `active`
- **目标：** `ground_point_friendly_area`
- **几何：** `square`
- **运行族：** `area_heal`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `None`，数量 `[0, 0, 0, 0]`
- **权威机制：**
```json
{
  "runtime_family": "area_heal",
  "heal_formula": "get_power(rank, mpow(magic_db)) + 2 * roll_sc()",
  "affected": [
    "self",
    "friendly_players",
    "friendly_pets_if_project_policy_enabled"
  ],
  "cap_each_target_at_max_hp": true,
  "must_use_dedicated_heal_pipeline": true,
  "negative_damage_implementation_forbidden": true,
  "status": "source_formula_reference"
}
```
- **熟练度事件：**
```json
{
  "event": "total_actual_hp_restored_gt_zero",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前只治疗自己、治疗量一次SC；正确为选定点3×3友方范围，技能基础治疗+2×SC。
- **必须测试：** mass_healing_exact_3x3, mass_healing_friendlies_not_self_only, mass_healing_formula, mass_healing_training_only_if_actual_heal, mass_healing_not_negative_damage

### 33. 召唤神兽 — `taoist.summon_divine_beast`

- **等级/熟练：** L0:人物35级、熟练0 / L1:人物35级、熟练2000 / L2:人物37级、熟练4000 / L3:人物40级、熟练8000
- **MP：** 28 / 32 / 36 / 40
- **激活：** `active`
- **目标：** `self_summon`
- **几何：** `nearest_valid_adjacent_tile`
- **运行族：** `persistent_main_pet`
- **人物动作：** `cast_8dir_6f`，身体动作 `600ms`
- **材料：** `amulet`，数量 `[5, 5, 5, 5]`
- **权威机制：**
```json
{
  "runtime_family": "persistent_main_pet",
  "pet_group": "taoist_main_pet",
  "group_limit": 1,
  "recast_if_live_pet_exists": "recall_existing_pet_no_material_and_no_proficiency",
  "new_pet_template": "divine_beast",
  "initial_pet_level_formula": "rank",
  "max_pet_level_formula": "1 + 2 * rank",
  "skill_rank_is_pet_level": false,
  "replacement_policy": "never_delete_live_pet_just_to_create_new_one",
  "status": "source_formula_reference_plus_project_canonical"
}
```
- **熟练度事件：**
```json
{
  "event": "new_divine_beast_successfully_spawned",
  "requires_hit": true,
  "gain_range": [
    1,
    3
  ],
  "max_gain_per_cast": 1
}
```
- **4b6ea4e0差异：** 当前不耗5张护身符并强制替换旧召唤物；正确已有神兽则召回，无宠才耗5符创建。
- **必须测试：** summon_divine_beast_consumes_five_amulets_only_on_new_spawn, summon_divine_beast_recast_recalls, taoist_main_pet_limit_one, divine_beast_skill_rank_separate_pet_level, summon_divine_beast_no_forced_delete


## 6. 明确排除的后续技能

- EnergyRepulsor/气功波
- Purification/净化术
- Hallucination/幻影术
- UltimateEnhancer/无极真气
- Reincarnation/回生术
- SummonHolyDeva/召唤圣兽
- Curse/诅咒术
- Plague/瘟疫
- PoisonCloud/毒云
- EnergyShield/能量盾
- PetEnhancer/宠物强化
- HealingCircle/治疗领域
- Vampirism/噬血术
- 所有英雄版、Mir3、韩服后续、手游和私服扩展技能

它们只能进入：

```text
content_layer=expansion
version_scope=post_1_76
```

## 7. 完成定义

只有同时满足以下条件，才能宣布技能系统完成：

- 33个技能全部从唯一JSON加载；
- 132个等级记录可通过正常玩法到达；
- 熟练度可保存、读档、升级；
- 主游戏不再执行简化技能入口；
- 所有P0测试和每技能测试通过；
- 生成一份当前APK行为与新运行时的确定性差异报告；
- 关闭旧入口后，测试和实机均无双重结算。
