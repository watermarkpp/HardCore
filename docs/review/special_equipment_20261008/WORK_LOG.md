# 特殊装备改动执行记录 — 2026-10-08

施工基线：`codex/integration` / `215f0b2f651a51e6855ee813ddd99221690311a1`，唯一工作树 `C:/Users/Administrator/Documents/HardCore`。保留上一轮全部混合 staged/unstaged/untracked 现场，不回滚无关内容。

## 用户合同

- 麻痹戒指：Boss 与 elite 精英 2.5 秒，ordinary 普通怪 5 秒；原触发概率不变。不得改变怪物自身攻击玩家的控制规则。
- 复活戒指：300 秒冷却；仅戒指自动复活不扣经验，正常死亡照旧。
- 隐身戒指：穿戴即隐身，攻击打破，真实脱战恢复；卸下或零耐久失效。
- 传送/防御/火焰戒指：穿戴赋予独立技能，可绑定技能栏，用戒指物品图标；卸下或零耐久撤销。删除点击特装入口。保留原 utility 效果：安全前向位移 0MP，治愈 5MP 与原公式，火球 5MP 与原 MC/投射物路径。
- 虹魔仍按传入伤害吸血；不改为目标实际 HP 减少量。
- 技巧项链：仅 17 个已允许技能中随机一项 +1，掉落生成固化，不能教未学技能。
- 探测项链：仅从正式掉落删除 `dpv2.direct.m160.slot_070`，已有物品保留。
- 特殊装备详情必须与实际消费者一致，写明条件、数值和限制；标题 18，正文 14，已确认金边保持。
- 神秘三件：掉落时随机属性与对应穿戴要求，不要诅咒、锁定/神水机制。用户要求转查主资料库后，找到原服务端 ItmUnit.pas 的 GetRandomRange/RandomUpgradeUnknownItem 与 M2Share.pas 默认参数；按该公式接入五项随机属性、原 Need 优先级和门槛。未采用此前待决的60/30/10概率提案。精确路径/行号/哈希见 docs/mystery_equipment_random_source_evidence.md。
- 群怪卡顿留到用户手机演示；本轮不跑群怪场景或性能采集。
- 项目 AGENTS.md 已加入：每次检测记录证据；无相关输入或合同变化不重复检测，必要验证保持。
- 关机仅在今晚授权工作完成、必要验证通过和记录保存后执行；未解决失败或必要参数缺失不能伪报完成后关机。

## 检测记录与复测理由

旧音频、拾取、售价、祝福油、小极品、Loading、金边专项以 `docs/audio/20261007/NATIVE_PROGRESS_RECEIPTS.json` 的对应源码阶段证据为准。本轮不重新执行已闭合且无相关变化的检测。新增装备技能依赖改变 SkillDataLoader/ProfessionRules 编译图，需要更新代码准备目录；该生成与当前新增验证是必要依赖工作。

| 原生 evidence epoch | 状态 | 范围与原因 |
|---|---|---|
| special_equipment_rules_red_000108_010861 | FAIL | 新装备身份缺失为业务RED；actor夹具静态类调用错误保留，不能当业务RED |
| special_actor_rules_red_elite_001351_470630 | FAIL | actor夹具修正后，主源仍60000，真实断言300000失败；源码稳定 |
| special_state_technique_red_002024_077695 | FAIL | 新availability API、技巧规则缺失；同时保留生成前价格身份错误；源码稳定 |
| special_modules_first_003128_013988 | FAIL | 5场同一新增Loader Variant推断导致解析失败；源码稳定；已定位行138，不计通过 |

完整原生原始输出、退出与源码前后指纹位于 `outputs/r3_takeover/20260930/validation/<epoch>/`。后续仅因新增代码修正和缺失覆盖复测，不把旧阶段PASS拼为最终通过。

Python专项：`tests/test_technique_drop_authority.py` 初次3FAIL（UID/item251/规则缺失），实施后3PASS；正式compiler生成 live slots6083并保留其它slots/probs/order与原保护。完整专项结果在完成交接中记录。

本轮指定改动的专项结果以后续收尾记录为准；APK未生成；DEVICE TEST: NOT_RUN。

## 收尾证据与复测原因（最终记录）

以下各阶段独立绑定实际命令、源码与引擎指纹、invocation、原生退出和完整日志。保留全部 FAIL，不合并为一个最终源码的全量通过。

| Epoch | PASS | FAIL | 稳定源码 | 状态 |
|---|---:|---:|---|---|
| special_equipment_rules_red_000108_010861 | 0 | 2 | True | FAIL |
| special_actor_rules_red_elite_001351_470630 | 0 | 1 | True | FAIL |
| special_state_technique_red_002024_077695 | 0 | 2 | True | FAIL |
| special_modules_first_003128_013988 | 0 | 5 | True | FAIL |
| special_code_capture_detail_red_003358_877717 | 0 | 4 | True | FAIL |
| special_capture_state_red_004440_033832 | 0 | 8 | True | FAIL |
| special_modules_capture_final_005413_618694 | 0 | 11 | True | FAIL |
| special_capture_book_fix_005529_416237 | 3 | 0 | True | PASS |
| special_equipment_functional_final_005610_879556 | 4 | 7 | True | FAIL |
| special_equipment_failure_recheck_010014_860392 | 2 | 5 | True | FAIL |
| special_final_remaining_010705_195757 | 5 | 1 | True | FAIL |
| special_last_stealth_wear_root_011445_830645 | 3 | 0 | True | PASS |
| special_panel_and_set_regression_011913_702466 | 0 | 2 | True | FAIL |
| special_panel_set_fixture_repair_012027_695403 | 1 | 1 | True | FAIL |
| special_panel_identity_boundary_012136_862376 | 1 | 0 | True | PASS |

复测仅针对新增代码或失败修复：Loader/registry身份→skill-book33条关系→catalogue正式生成；JSON数值类型规范与完整实例冻结比对；真实技巧技能+1消费者canonical scope；神秘attack/magic/tao映射；先攻击后戴隐身戒指有效状态转换；SkillPanel仍按learned拦截装备技能→改availability并验证真实弹窗/配置请求/正式slot提交；已删除特装功能的旧phase2夹具迁移到正式grant入口。

夹具失败单独分类：不存在的Enemy._dead、旧Control/CanvasLayer类型、服务端需求测试稀疏字段、闭包字典重新绑定、UI精确legacy→canonical转换边界，以及旧phase2错误假定出生怪HP必须>100。修正均保留真实生产消费者和伤害/数值断言，没有修改生产概率、降低地图数量或放宽内部业务期限。

当前最后一次各专项结果见 FINAL_RECEIPTS.json latest_per_test；前期无关音频/拾取等证据复用，不因交接重跑。新skill_panel修复只影响配置面板，不在caster代码准备编译计划内，已检查该生成图无需再次生成。

正式主表精确投影218/219/220/250：outputs/equipment_current_master_projection_20261008/check.audit.json、write.audit.json；实体registry经tools/build_entity_registry.py正式生成；掉落compiler最终PASS，仅移除探测项链精确UID，当前6083槽；UTF8修复保持PowerShell正常解析中文主表。代码准备目录正式compiler/build PASS见 outputs/special_equipment_20261008/code_catalogue_final/receipt.json。

本次未出新APK/未提交/未push；DEVICE TEST: NOT_RUN。群怪及真实手机流畅度留至次日用户演示。已冻结enemy.gd.applied-draft SHA256 bbd9311794bf487357b4da0f530877efa08376838025584c3aaca2a20314ee7e保持。

生成器最后审查：发现skill-book豁免按整个hc.skill.equipment前缀，未知身份可绕过覆盖。新真实validator测试先因fixture将records列表当字典产生2ERROR，修正精确id映射后1PASS/1FAIL业务RED；收紧为登记三个ID后2PASS，正式build_entity_registry.py --check PASS，生成字节SHA4953930c...与先前完全一致。因此仅复验受影响Python验证/生成链，未重复Godot。命令、前后指纹及日志见FINAL_RECEIPTS.json python_registry_closure及related_tools_sha256。
