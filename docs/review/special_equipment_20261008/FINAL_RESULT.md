# 2026-10-08 本轮特殊装备与主界面居中交接

当前唯一主树 C:/Users/Administrator/Documents/HardCore，codex/integration；HEAD 215f0b2f651a51e6855ee813ddd99221690311a1。本轮实现保留在混合暂存/未暂存工作区，没有commit/push或新APK。当前Git与FINAL_RECEIPTS.json文件清单优先于旧审计。

## 指定改动的结果

| 对象 / stable ID | 当前行为与覆盖 |
|---|---|
| 麻痹戒指 hc.item.000252 | 普通5秒、精英/Boss2.5秒；原触发概率保留。真实GameRoot物理HP提交→正式控制分类专项PASS；未声明自然输入到控制自然结束所有组合已覆盖。 |
| 复活戒指 hc.item.000256 | 冷却300秒，自动戒指复活不扣经验；正常死亡原扣经验规则保留。真实自动复活/死亡信号/经验专项PASS。actor重建的冷却记忆边界保持原实现，不新增持久化玩法。 |
| 隐身戒指 hc.item.000253 | 有效穿戴立即隐身，攻击打破，真实敌方target集合脱战后恢复；卸下/零耐久失效。修复先攻击后穿戴未隐身；普通profile更新不重置破隐。target变更、死亡、tree退出和换图清集合，无第二个战斗计时器或逐帧群怪扫描。 |
| 传送254 / 防御255 / 火焰259 | 装备赋予独立技能 hc.skill.equipment.ring_teleport / ring_healing / ring_fireball；戒指图标，可由技能面板真实配置到技能栏，卸下/损坏撤销且不写learned_skills。旧特装按钮/信号/handler删除。保留旧位移碰撞、0/5/5MP、治愈公式及正式火球投射物。 |
| 技巧项链 hc.item.000250 | 正式掉落固化17个已允许技能中随机一项+1，穿戴/存读不重抽，未学技能不启用；真实掉落→strict validator→JSON/正式保存读取→穿戴→有效等级/零耐久专项PASS。旧无roll实例兼容，不凭空改写人工存档。 |
| 探测项链 hc.item.000251 | 正式掉落表移除唯一dpv2.direct.m160.slot_070；已有物品保留。精确源策略与正式compiler生成PASS，其余槽/概率/保护保留。 |
| 神秘218 / 219 / 220 | 按主资料库原服务端五项随机属性算法及对应穿戴门槛；没有诅咒/锁定/神水链。身份219名称神秘腰带、权威类别手镯保持。真实实例生成/保存冻结/加成/等级和攻魔道穿戴边界PASS。原主表耐久保持；已有通用小极品独立机制保持。 |
| 虹魔 / 魔血 | 虹魔按传入伤害4/3/2%吸血、三类型准确+2；魔血每件25转换、三类型额外50、MP至少1。相关phase2正式回归PASS。 |
| 特殊属性详情 | 显示上述戒指条件/数值、魔血/虹魔、技巧实际技能、神秘实际能力及实例门槛。名称18号、属性14号；用户已确认金边保持。 |
| 战士开关 / 怪物目标血条 | WarriorStateLabel漏接居中校正，已在最终anchor后注册。TargetPanel/TargetLabel原来已正确继承校正，未增加多余偏移；真实主世界几何专项验证±24、重复无漂移、归零和文字/面板中心。 |
| AGENTS.md | 已写入每次检测必须留记录、相关输入/合同不变不重复跑，必要新增/修复/平台验证仍须做。 |

## 验证与尚未执行范围

各专项分阶段结果和全失败历史见 WORK_LOG.md、FINAL_RECEIPTS.json，以及 docs/audio/20261007/NATIVE_PROGRESS_RECEIPTS.json。最后一次每个专项结果如下；此表不表示它们在同一源码阶段整体执行，不代表Android设备验收。

| Scene | 最新独立epoch | 状态 |
|---|---|---|
| tests/equipment_granted_skill_identity_test.tscn | special_equipment_functional_final_005610_879556 | PASS |
| tests/equipment_granted_skill_panel_lifecycle_test.tscn | special_panel_identity_boundary_012136_862376 | PASS |
| tests/equipment_granted_skill_progression_rejection_test.tscn | special_final_remaining_010705_195757 | PASS |
| tests/equipment_granted_skill_state_test.tscn | special_equipment_functional_final_005610_879556 | PASS |
| tests/equipment_special_phase2_test.tscn | special_panel_set_fixture_repair_012027_695403 | PASS |
| tests/hud_center_alignment_special_text_test.tscn | special_final_remaining_010705_195757 | PASS |
| tests/mystery_equipment_formal_flow_test.tscn | special_final_remaining_010705_195757 | PASS |
| tests/mystery_equipment_instance_test.tscn | special_equipment_failure_recheck_010014_860392 | PASS |
| tests/mystery_equipment_wear_requirements_test.tscn | special_last_stealth_wear_root_011445_830645 | PASS |
| tests/special_equipment_actor_policy_test.tscn | special_last_stealth_wear_root_011445_830645 | PASS |
| tests/special_equipment_detail_contract_test.tscn | special_final_remaining_010705_195757 | PASS |
| tests/special_equipment_root_flow_test.tscn | special_last_stealth_wear_root_011445_830645 | PASS |
| tests/technique_necklace_formal_flow_test.tscn | special_final_remaining_010705_195757 | PASS |
| tests/technique_necklace_instance_test.tscn | special_equipment_functional_final_005610_879556 | PASS |

生成器未知装备技能身份闭合专项2PASS，正式registry --check PASS且生成字节保持，技能书仍严格33条，只豁免登记三个装备技能。编译/生成失败与修复分别留记录，没有手改运行生成物。

原音频、拾取、售价、祝福油5倍、沃玛以上小极品3倍、Loading与比奇名称证据以docs/audio/20261007/CURRENT_RESULT.md为准；没有为交接重复执行。此前Loading退出44 ObjectDB告警保留，不能外推全项目零告警。

群怪卡顿仍未解决，按用户安排留至2026-10-08手机演示并监测该次数据，以用户体感验收。祈祷/记忆玩法、求婚业务和完整架构剩余覆盖没有扩大到本轮；旧monster ID169运行绑定/ID193外部结算依据等MISSING照旧保留。

APK: NOT_RUN；DEVICE TEST: NOT_RUN。v106不含本轮音频、拾取、概率、特装和HUD改动，不能用已安装v106验收它们。无本轮版本、大小或APK SHA可报告。
