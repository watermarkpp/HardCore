# 三职业升级自身属性复查

2026-09-22。结论 PASS；本次未修改任何职业成长或人工装备数据。确认现有修复已经进入运行时，不需要再改成长数值。

权威链为主源 ObjBase.pas / !Setup.txt / M2Share.pas → tools/build_character_base_growth.py → scripts/generated/character_base_growth_v1.gd → ProfessionRules → PlayerState.base_stats/computed_stats → 人物属性、正式施法主属性取值、AC/MAC和负重消费者。三份主源哈希与manifest一致；在临时目录重建的生成代码与正式输出一致。旧BASE_STATS不是成长消费者。

独立Fraction有理数/最近偶数舍入公式核对3职业×1～255级×17属性，共13005值全部一致。1～255只是此次核查范围，不宣称游戏等级上限。通过真实add_experience和批量击杀入口完成177次升级，活人物无需手动刷新就接收到HP/MP、攻击和防御；六次保存失败回滚，不发成功升级信号。原有base_growth_test也通过177次升级、装备拆装、临时增益过期、保存加载和复活验证。

新增测试在1/30/60级分别调用GameRoot正式施法主属性取值，验证攻击/魔法/道术上下限；人物真实take_damage和take_direct_spell_damage扣血验证AC/MAC消费。背包接收预演证明同一批木剑在1级因overweight拒绝，30/60级因成长后的容量通过；三项负重生产入口每次升级均与裸属性一致。并未绕过物品槽数、职业/等级要求或修改物品重量。

| 职业 | 等级 | HP/MP | 物攻 | 魔法 | 道术 | 背包/穿戴/手持负重 |
|---|---:|---|---|---|---|---|
| 战士 | 1 | 19/15 | 1–1 | 0–0 | 0–0 | 50/15/12 |
| 战士 | 30 | 419/116 | 5–6 | 0–0 | 0–0 | 350/60/81 |
| 战士 | 60 | 1364/221 | 11–12 | 0–0 | 0–0 | 1250/195/289 |
| 法师 | 1 | 16/18 | 0–1 | 0–1 | 0–0 | 50/15/12 |
| 法师 | 30 | 128/541 | 3–4 | 3–4 | 0–0 | 230/24/22 |
| 法师 | 60 | 362/1861 | 7–8 | 7–8 | 0–0 | 770/51/52 |
| 道士 | 1 | 17/13 | 0–1 | 0–0 | 0–1 | 50/15/12 |
| 道士 | 30 | 239/261 | 3–4 | 0–0 | 3–4 | 275/33/33 |
| 道士 | 60 | 764/1003 | 7–8 | 0–0 | 7–8 | 950/87/98 |

攻击上下限是分段成长，不是每一级都加1；准确固定5，敏捷战士/法师15、道士18，这是主源规则。非本职魔法/道术等字段保持0也不是未应用成长。

证据：evidence/delivery_close/player_growth_live.json、character_growth_audit.json、runner_results_adhoc_20260922_221819_640_1460.json。重验：tools/run_godot_tests.ps1 -TestPaths tests/player_growth_live_runtime_test.tscn -TimeoutSeconds 30；py -3.12 tools/audit_character_growth_v92.py。原有成长/升级效果2/2 PASS，新增最终影响回归6/6 PASS。手机操作 NOT_RUN。
