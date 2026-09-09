# T30 金币上限入口补测

状态：正式 runner 已 PASS。测试使用主树 `dd31a610cdf465b5b41ecd88b810164aae192a2e`，生产脚本、既有测试、掉率/数据文件均未修改。

范围固定为真实入口：

- `GameRoot._spawn_gold_loot` → `LootPickupRuntimeManager` → `_flush_loot_collections` → `PlayerState.receive_loot_batch_partial`。金币已满时地面 pickup 保留、未确认且余额不变；留出恰好 1 金币空间后同类 pickup 成功一次，确认节点销毁，重复扫描不再入账。
- `PlayerState.create_drop_item_instance` 生成的完整木剑实例通过正式 `receive_loot_batch_partial` 进入背包，再走权威报价的单项/批量出售。金币上限拒绝和 `_test_force_atomic_write_failure` 存档失败都完整保留源实例、余额和未消费报价；故障清除后可重试一次。
- 正式 `bich_beginner_gear` 任务只在内存测试夹具中追加运行目录的 `金币` currency record，验证 `reward_items.gold_delta` 与 quest gold 的合并上限、存档失败回滚、成功后一次领取和防重复。原始任务数据在测试结束恢复。
- `PlayerState.add_gold` 通过既有 contract 拒绝负数、超过 `PLAYER_GOLD_CAP` 的整数和非整数，状态保持不变。

隔离条件：测试仅使用 `user://r3_gold_cap_entrypoints_<timestamp>` profile/shared 文件；正式地图和合法玩家足点由 GameRoot provider 解析。生产脚本、既有测试、掉率/数据文件均不改。允许的正式命令为：

```powershell
tools/run_godot_tests.ps1 -TestPaths @('tests/r3_gold_cap_entrypoints_test.tscn') -TimeoutSeconds 60
```

实际命令与结果：

```text
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\run_godot_tests.ps1 -TestPaths @('tests/r3_gold_cap_entrypoints_test.tscn') -TimeoutSeconds 60
[PASS] r3_gold_cap_entrypoints_test
TEST_SUMMARY suite=adhoc passed=1 failed=0 engine_log_errors=0
```

最终 runner JSON：
`outputs/test_logs/runner_results_adhoc_20260909_164253_268_6772.json`

本次原始日志：

- `outputs/test_logs/r3_gold_cap_entrypoints_test.stdout.log`
- `outputs/test_logs/r3_gold_cap_entrypoints_test.stderr.log`
- `outputs/test_logs/r3_gold_cap_entrypoints_test.godot.log`

首轮失败也保留在 `outputs/test_logs/runner_results_adhoc_20260909_164211_687_8488.json`：仅为新测试脚本第 155 行 `ground` 的动态 `Variant` 类型推断 parse error；改为显式 `Vector2` 后在同一窗口重跑通过。最终 runner 的 `process_exited=true`、`effective_exit_code=0`、`stdout_failure_count=0`、`stderr_failure_count=0`、`engine_log_failure_count=0`。

原始 stdout 在自然退出时仍记录 Godot 的 `WARNING: 3 ObjectDB instances were leaked at exit` 与 `ERROR: 1 resources still in use at exit`；runner 的 engine 错误筛选计数为 0，故此处明确不将 `engine_log_errors=0` 表述为原始日志零 ERROR。该退出清理告警未阻止本测试的业务 PASS，也没有改生产代码来掩盖它。
