# CODEX施工总指令｜MIR2 1.76 33技能

## 不得跳过的阶段0：只读审计

第一次执行只允许读取，不允许修改任何工程文件。

读取：
- `assets/data/vanilla_176/skills.json`
- `assets/data/vanilla_176/profession_growth.json`
- `assets/data/vanilla_176/profession_combat_rules.json`
- `scripts/profession_rules.gd`
- `scripts/player_state.gd`
- `scripts/player.gd`
- `scripts/caster_skill_runtime.gd`
- `scripts/game_root.gd`

并输出：
- 33技能逐项现状表；
- 所有权威入口和重复入口；
- 存档字段；
- 每技能当前目标、材料、公式、范围、状态、熟练度；
- 与本包JSON的差异；
- 会被删除、迁移或保留的文件/函数；
- 当前测试基线。

未输出审计报告前，不得施工。

## 唯一真源

把本包的：
`mir2_176_skills_source_of_truth_v1.json`

复制到：
`assets/data/vanilla_176/skills_source_of_truth_v1.json`

从此：
- Vanilla技能成员、进度、MP、目标、材料、公式身份只从该文件读取。
- 旧表只能通过显式Adapter读取，不能反向覆盖。
- Vanilla技能数量不等于33时启动失败。

## 建议目录

```text
scripts/skills/
├─ skill_runtime_router.gd
├─ skill_cast_request.gd
├─ skill_cast_result.gd
├─ skill_data_loader.gd
├─ skill_progression_service.gd
├─ skill_resource_service.gd
├─ skill_target_service.gd
├─ skill_geometry_service.gd
├─ skill_rng.gd
├─ formulas/
│  └─ mir2_skill_formula.gd
└─ runtimes/
   ├─ warrior_skill_runtime.gd
   ├─ wizard_skill_runtime.gd
   └─ taoist_skill_runtime.gd

tests/skills/
├─ test_skill_source_of_truth.gd
├─ test_skill_progression.gd
├─ test_skill_save_load.gd
├─ test_skill_runtime_router.gd
├─ test_warrior_skills.gd
├─ test_wizard_skills.gd
└─ test_taoist_skills.gd
```

## 施工顺序

1. 加入JSON Schema和只读加载器，不改变游戏行为。
2. 加入数据一致性测试：33、6/14/13、4级、唯一ID、无扩展技能。
3. 加入技能熟练度服务、存档迁移、升级测试。
4. 把`game_root._on_player_skill()`改为只创建`SkillCastRequest`。
5. 在Feature Flag下接入`SkillRuntimeRouter`。
6. 先修战士6技能。
7. 再修法师14技能。
8. 再修道士13技能。
9. 加材料、Buff、召唤和tile几何。
10. 固定种子跑全部测试，再做APK实机回归。
11. 删除或禁用旧简化结算入口。

## 禁止事项

- 禁止按Crystal枚举顺序生成技能树。
- 禁止用服务端“候选等级/熟练度”覆盖CN 1.76表。
- 禁止把360ms写成历史原版。
- 禁止把`legacy_delay`用于运行。
- 禁止客户端决定伤害、是否成功、材料消耗或熟练度。
- 禁止失败施法增长熟练度。
- 禁止使用裸像素决定技能范围。
- 禁止技能等级、熟练度、人物等级、宠物等级共用字段。
- 禁止一次性重写后不做逐阶段回归。
