# Pro 审计回读记录

主控于 2026-10-02 实际读取原《游戏稳定性设计》对话最新完成回复。
固定对象：93b75aef8d05ff6277b8495e63f1d8fb501c25ff；父 de02ced5df4c71b2fe6a41c2b0baab8e73389a57。
结论已并入工程清单：开放 producer 的重复内部 plan、batch 明确失败的调用方拒绝与收尾，覆盖已补齐；无需新增生产整改。
审计只读取远端源码及归档，未自行运行 Godot，未重算 ZIP/全量 manifest。本地后续 journal 99 检查及自然战斗 P6 不在此审计范围。

## 原回复

已成功读取固定 **`93b75aef8d05ff6277b8495e63f1d8fb501c25ff`**，父提交确为 `de02ced5df4c71b2fe6a41c2b0baab8e73389a57`，本轮没有远端读取阻碍。GitHub 提交比较也确认：除报告和证据外，仅变更4个测试／夹具文件，**生产代码零变化**。

**结论：两条原先提出的分支覆盖缺口均已补到，可以按限定范围关闭。没有发现需要修改生产代码的新确证问题，也不需要为这次补证另开整改项。**

## 1. 未关闭 producer 的重复内部 plan：覆盖有效

**测试位置：**`tests/framework/feature_melee_ticket_paths_test.gd` **L31–41**。新增检查的顺序是：

```text
接受真实非空近战票据
→ 外层领取释放权
→ 错误内部 ID 拒绝，producer 仍未关闭
→ 正确内部 plan 第一次成功
→ producer 明确仍未关闭，第二次 plan 拒绝
→ 外层再次领取也拒绝
→ 最后显式关闭，预留归零
```

这消除了原来“重放可能仅靠 `_producer_closed` 被挡住”的歧义。对应生产防线是 `scripts/features/contracts/action_config_lease.gd` **L71–82**，其中 **L80–81** 的 `_plan_started` 才是同一开放 producer 的重复规划门禁。

原蓄火下一刀、半月、刺杀的业务断言仍保留；该场景由原31检查增加为**38检查 PASS**，不是替换旧断言。准确范围是：新增部分直接测试**真实 lease／预留协议**，后续原 `_swing()` 测试继续覆盖 Player／Root 生产调用；不将它描述成自然输入触发了重复规划。

## 2. 承诺 batch 建立失败：覆盖了真实调用方拒绝与收尾

| 位置 | 实际核验 |
|---|---|
| `tests/framework/fixtures/feature_batch_failure_root.gd` **L7–14** | 在 batch 工厂接口明确注入 `null`；规划入口只做计数并保留 `super`，没有伪造拒绝结果。 |
| `tests/framework/feature_batch_failure_test.gd` **L32–50** | 正式 Player 接受带票据动作；记录接受后的状态；等待原延迟回调，检查一次工厂失败、明确拒绝、无规划与额外提交、生产者关闭及预留归零。 |
| `scripts/game_root.gd` **L7937–7944** | batch 缺失返回 `feature_batch_unavailable`，发生在调用原规划主体之前。 |
| `scripts/player.gd` **L1341–1348** | 原技能信号返回后，由真实 Player 尾部调用 `finish_producer()`，不是测试手动补清理。 |

这些调用点与测试的**12检查 PASS**相符。MP、目标 HP、Root RNG 和目标 EnemyActor RNG 均相对**已经接受动作之后**的快照比较；没有要求退还已接受冷却。

这里应保留一个边界：**它证明的是“工厂接口返回失败后，生产调用方如何拒绝和清理”，不是证明真实容量耗尽或工厂内部各种错误已经逐一复现。**这是此次补证原本要求的范围，不构成新的覆盖缺陷。固定 seed 夹具的调用计数也明确可见，因此 `_canonical_cast_serial==0` 支持“没有请求 canonical seed”，不扩张成所有随机源均已审计。

## 3. 回执与本轮范围

我已读取三份完整逐项 receipt，并对照 runner：

| 场景 | 归档结果 |
|---|---:|
| `feature_melee_ticket_paths_test` | 38检查 PASS |
| `feature_batch_failure_test` | 12检查 PASS |
| `feature_release_identity_test` | 11检查 PASS |
| **合计** | **3原生场景／61检查 PASS** |

三者使用同一内容指纹 **`d1a98f38…0fdeff4`**、同一 invocation；runner 记录真实退出0、有效 receipt、无超时、零 stdout／stderr／引擎错误，validation 记录受测源码期间稳定。

**交接结论：**将“开放 producer 重复内部规划”和“batch 失败调用方分支”两项更新为**覆盖已补齐**，保留此前释放修复的有界关闭。此次无需新增生产整改；故障注入也不意味着允许正常已接受动作丢弃承诺效果。

本轮完成的是远端源码与归档证据审查，**没有自行运行 Godot或重算增量 ZIP／全量 manifest**。尚未固定的99检查 journal 补证及移动战斗 P6 结果均未纳入，也不回写为 `de02` 或 `93b75aef…` 的验收成果。
