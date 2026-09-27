# R4 实际执行结果（持续更新）

## 观察与伤害身份闭环

执行源基于本地候选 `227a9c945f3bb21e4fbe51d38e10bbde4b0d8f9d` 加本轮未提交修复。实际源码与测试文件哈希在 `evidence/observation_final/r4_observation_final/source_identity.json`；以文件哈希识别这次执行，不将基线HEAD当作无dirty源码证明。

命令：`tools/run_godot_tests.ps1 -TestPaths @('tests/hc_monster_combat_r4/observer_integrity_test.tscn', 'tests/hc_monster_combat_r4/damage_attribution_counterexamples_test.tscn', 'tests/hc_monster_combat_r4/all_damage_lost_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_24_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_76_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_238_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_239_test.tscn', 'tests/hc_monster_combat_r4/natural_cadence_24_chase_test.tscn') -TimeoutSeconds 30`。四项20起手、全漏和反例为已声明重场景，运行器上限60秒。

结果：**PASS 8/8，timeout=0，engine_log_errors=0**。原始stdout/stderr/engine与runner在 `evidence/observation_final/r4_observation_final/runner_results_adhoc_20260927_132532_672_19136.json` 同目录。逐次原始流水在 `evidence/observation_final/r4_cadence_*.json`、`r4_counterexamples*.json`。

覆盖：正常、采样前设置的真实AC减伤、实际魔法闪避、实际离开射程拒绝、真实combat_epoch切换、真实丢伤+同帧同额外来扣血、重复HP写入、无身份嵌套、有身份外来嵌套、20次全部丢伤。故障发生在写入流程；观察器无故障开关、无HP写入权；验收器不读取故障状态。

身份验收严格检查来源实例/生命、父动作、地图/世界代际、根释放、明确声明的子释放、目标实例/生命/世界代际。UNKNOWN独立保留，不能替补受审终态；金额只核验实际HP算术。合法两目标与伪造身份使用同一验收器。实际多目标、MP护身支付和换图组合继续补真实行为，不能把单位用例当成整项R4完成。

### 旧 18/20 与退出失败裁定

初次原候选76/239的18/20附近记录缺少正确parent归属与真实miss终态，保留为FAIL。修复后的76/239，未改公式/RNG/冷却：每个根释放归属到明确child，真实 `mixed_magic_evaded` 分支给出miss终态。不能据此逆推无完整身份的旧记录全为合法miss，也没有按奇偶补记录。

上一轮24打印PASS但process超时，保留在 `evidence/natural_24_timeout`。当前明确关闭记录、释放GameRoot、等待两次真实process_frame再退出。24最终实际启动约5秒、world boot约5秒、自然采样约48秒、写证据3ms、清理29ms；完整进程自然退出在60秒内。未清冷却、未缩pending、未手调游戏钟。

### 已执行相关回归

monster_mixed_damage_atomic、ranged_magic_evasion、monster_special_delivery_runtime：PASS 3/3（`outputs/test_logs/runner_results_adhoc_20260927_130604_626_8444.json`）。接口探针补全新增可选身份参数，原断言不变。w1_special_delivery_runtime、synchronous_revive_death_token此前定向PASS。

## 快照当前断言裁定

当前执行：`evidence/snapshots_red/runner_results_adhoc_20260927_131906_652_12240.json`。

- enemy_snapshot_v2_production：**FAIL**。夹具把玩家放在2GU，要求 `_deal_melee_hit` 得到V2；真实1.5GU中心入口提前拒绝，所以snapshot空。修夹具到合法范围，保留V2/同地图/跨地图/legacy计数原断言；生产不可回退2GU。
- canonical_snapshot_identity_production：**PASS**。当前正式技能入口可传播身份。历史失败未自动定为无关；保留当前原始运行结果。
- caster_skill_visual_factory_entry：**FAIL**。SkyStrike/Beam/非SkyStrike断言全部成立，未加入树的创建结果未free，退出泄漏资源；需修资源清理。现存 `skill_visual_profiles.json` 确实声明SkyStrike，不能根据旧报告推测其应删除，也不动用户已验收的Magic素材。

最终full critical、同SHA干净检出、性能配对与D3完整矩阵：**NOT_RUN**。本地候选尚未达到最终审查条件。
