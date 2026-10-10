# B07-B 证据冗余审查（无授权删除）

fixed_source_sha: b09ac5c2c41517ed516f11b91d09e435813465f2

没有找到具有完整 autoload / class_name / scenes / resources / signals / Callable / dynamic-call / 运行/编辑器/正式编译 / 兼容和存档消费者排除证据的可安全删除代码。本批没有删文件。

24 个仅在早前本地试验存在的 retired grid .gd/.tscn/helper 不在固定 Git 树：不得并回或删除。本轮新发现 34 项正式 Git 测试路径，不能视为旧 manifest 遗漏就清理。

tests/helpers/loot_runtime_pre_slice_20261009.gd (29个函数) 是历史差分 oracle，不是游戏正式掉落第二权威；tests/source176_r3/helpers/cadence_reference_r2.gd (19函数) 是冻结旧节拍合同，不是当前300ms规划的恢复来源。
tests/hc_monster_ai/test_support.gd、tests/framework/helpers/check_receipt.gd、tests/framework/helpers/native_producer_gate.gd、tests/helpers/formal_initial_ready.gd 均具有实际固定源码引用或执行链，不能因为没有直接注册为场景就删除。

三张旧诊断场景 diag_activation_probe.tscn、diag_bounded_probe.tscn 和 r2_measure/qa_latency_driver.tscn 的 ext_resource 确认失联，当前非正式 suite 字面量成员。需要主控核实 adhoc/编辑器/历史用途决定修复引用还是保留为退休证据，不直接删除。

其余 981 张未列 runner 字面量的 .tscn 包含测试临时、独立诊断和 editor/fixture；普通搜索找不到直接入口不足以证明冗余。每文件分类与指定未审职责见 COVERAGE 和 TEST_CLASSIFICATION。

所有人工资料、fixture、旧 FAIL 原始日志和 50轮缺失自定义数组 MISSING 状态全部保留。
