# 怪物攻击投递主源闭环报告（2026-08-24）

## 结论

本交付完成了审计要求的三项施工，并把结果接入 `codex/monsters` 正式运行目录：

1. 物理弓箭不再使用程序绘制占位物，恢复 `Effect.wil` 的 `TFlyingArrow / ARCHERBASE2 272..287` 十六方向透明原始帧。
2. `monster_id=220` 与 `monster_id=222` 的法术表现彻底拆分：220 使用目标雷电；222 使用施法叠层和飞行法术。221、223 不再继承这两套行为。
3. 火焰沃玛 70 与触龙神 124 按原服类别重新接线；71 仅保留来源记录，不允许运行时激活。

工作树：`codex/monsters`

施工基线：`f964851ec6978de4266ed4a241b3db1bc0042a8c`

交付提交：包含本报告的提交；集成时用 `git log -1 --format=%H -- reports/monster_attack_delivery_primary_closure_20260824.md` 取得精确哈希。

## 稳定 ID 与运行规则

| monster_id | 结论 | 运行投递 |
| ---: | --- | --- |
| 70 | 火焰沃玛，Race 91 / `TMagCowMonster` | 一格相邻 `special_melee`，即时魔防结算，300ms 仅为身体受击表现；隔墙不能命中 |
| 71 | 火焰沃玛0 | `retired_source_only`，运行时拒绝 |
| 124 | 触龙神，Race 107 / `TCentipedeKingMonster` | 严格 `abs(x)<6 && abs(y)<6` 方形多目标，释放时冻结目标，600ms 后逐目标魔防结算；原版无 `CanFly/LOS`，无虚构警示圈 |
| 150、152、206 | 物理弓箭怪 | 冻结目标脚点、按距离延迟、发射及命中均检查环境路径；飞行视觉持续检查 `WORLD_MASK`，撞墙立即终止 |
| 220 | 牛魔法师 | `Magic2.wil` 10..15 目标雷电，目标锚定，无飞行物 |
| 222 | 牛魔祭司 | `Mon21.wil` 施法叠层 + `Magic.wil` 十六方向飞行法术；飞行视觉持续撞墙 |
| 221、223 | 退役记录 | 从 ID 和旧名称运行映射中移除，不能张冠李戴到 220/222 |

新增稳定表现 ID：

- `monster.physical_arrow.v1`
- `monster.cow_mage.thunder.primary.v1`
- `monster.cow_priest.fly.primary.v1`
- `monster.flame_wooma.magic_melee.v1`
- `monster.touch_dragon.area_magic.v1`

## 主源与素材

- 箭矢：`dev_art_sources/reference/mir2_client_raw/Data/Effect.wil`，SHA-256 `2d94f51ff7a7046daa65591e35c08cea0b23912f7aeeaae2aab0c7f24e37af90`。
- 220 雷电：主源 `Magic2.wil`，SHA-256 `398E5376F19638DF063CD6299199BF5C2365FA8525FE0C9E639EB3BB6C955D07`。
- 222 飞行法术：主源 `Magic.wil`，SHA-256 `BE46A0258349B26DB9BA7DBA595ABAC1F0767D52FEF11D9F508E704F2F6DEAAC`。
- 222 施法叠层：主源发行包明确缺少 `Mon21.wil/.WIX`，按来源优先级使用 `auxiliary_1` 的 `external/mir2opensource_full/Data/Mon21.wil`，缺失查询和选用证据已逐项写入 manifest。
- 70、124：身份和间隔来自 Monster.DB；行为来自 `original_gameofmir/M2Server` 对应类；客户端身体动作只复用已有主源怪物图集，不发明独立特效。

可机检来源清单：

- `assets/data/monster_physical_projectile_sources_v1.json`
- `assets/data/monster_target_magic_sources_v1.json`
- `assets/data/monster_special_delivery_sources_v1.json`

## 碰撞结论

- 普通近战：释放时检查世界路径；延迟近战在结算前重新检查，不能穿墙。
- 物理箭矢：发射前和结算前双重检查环境路径；飞行中的视觉再按 `WORLD_MASK` 连续截断。
- 222 飞行法术：玩法发射/结算检查路径，视觉飞行持续截断。
- 220 目标雷电：不是飞行物；玩法仍要求施法路径清晰，但目标上的雷电不做伪造的飞行碰撞。
- 124 范围魔法：原服实现没有 `CanFly/LOS`，因此保留无视中间墙体的严格方形范围。这是来源还原，不属于碰撞漏判。

## 验证结果

正式目录：

- `py -3.12 tools/build_canonical_monster_catalog.py --check`
- 结果：`CANONICAL_MONSTER_CATALOG_CHECK_PASS: identities=156 runtime_allowed=153`

新增来源与真实行为测试：

- `monster_physical_projectile_visual_source_test`
- `monster_target_magic_primary_visual_test`
- `monster_special_delivery_contract_test`
- `monster_special_delivery_runtime_test`
- 结果：4/4 PASS，`engine_log_errors=0`

既有攻击与目录回归：

- `all_monster_loading_test`
- `canonical_monster_catalog_test`
- `monster_physical_projectile_attack_test`
- `monster_target_magic_attack_test`
- `monster_attack_collision_gate_test`
- `monster_ground_unit_runtime_test`
- `classic_boss_order_test`
- `monster_melee_contact_geometry_test`
- 结果：8/8 PASS，`engine_log_errors=0`

完整 `monster` 套件曾运行一次，得到 8 PASS / 11 FAIL。随后本轮相关的 `all_monster_loading_test`、`classic_boss_order_test`、`monster_melee_contact_geometry_test` 已修正并分别通过。其余失败属于基线测试债，未作为本任务完成项伪报：

- `monster_id_contract_test` 断言的 ID 64/76 数值与施工基线目录本身不一致。
- 多个旧视觉/拥挤测试以名称或虚构负 ID 创建怪物，会被施工基线已有的 canonical fail-closed 规则释放。
- `placeholder_attack_animation_test` 还包含无界面纹理初始化错误和旧占位怪查找失败。

这些旧测试债没有被本交付扩成生产代码兼容回退；integration 若决定修复，应单独更新测试夹具到稳定 `monster_id`。

## 用户验收冻结证明

以下人工验收对象施工前后 Git blob 哈希保持一致：

- `monster_ground_alignment_manual_v1.json`：`1354ca4c378647afd7bce2336cec2a421e1f1843`
- `redmoon_generated_animation_sources.json`：`04d9bb58874cb2e182a2bb716a31c62d38c70d24`
- `fixed_area_ground_spike_sources.json`：`3ea379a3c398ba4a607fb1d7af83b65ac443a223`
- `fixed_area_ground_spike_rgba_v1.png`：`b1f38697a9badc70237061490a57db202cbb5868`
- 赤月 walk/idle/hit/death/attack：`b0e88053...` / `04aaddd1...` / `eba7142b...` / `85cde7d7...` / `05054d31...`

## integration 接入事项

1. 合并本交付提交后，在 integration 真实 HEAD 重跑上述 12 个通过测试及 canonical `--check`。
2. `tools/run_godot_tests.ps1` 属于 integration 的跨系统测试入口；将四个新增场景注册进正式 `monster` suite：
   - `tests/monster_physical_projectile_visual_source_test.tscn`
   - `tests/monster_target_magic_primary_visual_test.tscn`
   - `tests/monster_special_delivery_contract_test.tscn`
   - `tests/monster_special_delivery_runtime_test.tscn`
3. 合并后不要用旧生成器批量覆盖赤月人工锚点或已验收地刺素材。
