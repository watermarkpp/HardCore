# Boss 实际结算与夹具前置闭环

旧 c046 完整回归 classic_boss_order 实际 FAIL，原始日志保持不变。旧夹具固定的是人物物理防御，却无条件要求触龙神魔法攻击扣血。生产 take_direct_spell_damage 读取 PlayerState.computed_stats 的 anti_magic_points/MAC，并执行人物自己的真实 RNG。默认 anti_magic_points=1，合法 roll=0 会整次闪避。

新增独立真实自然攻击场景 classic_boss_area_magic_outcomes_test，三个样本使用不同的真实 PlayerCharacter/EnemyActor，属性和 seed 在采样前设置。没有写攻击冷却、pending、战斗钟，没有直接调用 physics、缩短延迟或注入结算结果：

| 实际 anti_magic_points | 玩家第一 RNG roll | HP 变化 | 结算 | 旧无条件扣血断言 |
| --- | --- | --- | --- | --- |
| 默认 1 | 0 | 0 | 合法 magic_evaded | FAIL |
| 0 | 0 | -30 | 实际命中 | PASS |
| 10 | 0 | 0 | 合法 magic_evaded | FAIL |

三个真实冻结目标、释放/结算 release_id、严格切比雪夫方形、source_monster_id=124、area_magic channel 与实际 HP 守恒通过。outcomes/native_report.json 保存全部真实 resolution、冻结记录和结算快照，实际源码哈希保留。

旧完整 FAIL 当时没有记录 resolution，所以不能声称逆推出那一次随机 roll；此反例证明旧夹具允许一个完全合法的结果触发失败。修复仅为“成功命中”原用例在释放和 HP 采样前固定真实 anti-magic=0、MAC=0，保留原 HP 下降断言，并增加实际 applied_damage 守恒。生产公式、闪避概率、RNG 顺序、时间和伤害拥有者完全未修改。

新增独立场景和两个此前未注册的 R4 身体索引边界/一致性场景进入 critical；环境驱动 BASE/CAND 探针仍由专用 runner 执行，历史自然反例别名没有重复注册。

outcomes runner 1/1 PASS。related runner 检查旧 Boss、独立自然命中/闪避、CombatResolution、两个身体索引、GameRoot 消费路径；全部结果以原始 runner JSON 为准，不由 marker 代替正常退出。最终完整 critical 仍 NOT_RUN，旧 c046 542 项仍保留 539 PASS / 3 FAIL。
