# Task2 ABI sham 离线复核（2026-10-09）

结论：**PASS（有界诊断记录）**。两条 runner 都真实 PASS、各 10,200 次 active enemy physics、diagnostic errors=0；本记录只描述 transport/诊断开销范围，不构成生产性能结论。

## 证据归档

已将 research task2 的 sham inputs、Enemy/fixture/archive、local/native 完整 UUID、`local.json`、`abi_sham.json`、正式 30 tick comparison JSON 和两份 runner receipt 复制到：

`C:\Users\Administrator\Documents\HardCore\outputs\crowd_native_kernel_20261009\task2\sham`

两个 runner 均记录 `PASS`、pass marker、native/effective exit code=0、timeout=false、engine_log_errors=0，并绑定 git `edae6fdef6a6551a951fab1ea8c6ade43359d603` 与隔离 runtime appdata：

- `runner_local.json`：invocation `e8ceffac-acd8-4610-96e3-7c1979b5868f`，SHA-256 `d164e89876b61e50ea9cdbd218e80028b0f9320b039bb4e4805273540caac98f`。
- `runner_native.json`：invocation `e9fe4e67-aac6-4ee8-83dc-deea41296a9a`，SHA-256 `18d04d96142d740d24be18613defd977e3b8fd7f62cc8a8d7e8c9a5752766b92`。

source archive 的主要哈希与机器明细在 `sham/VERIFICATION.json`；没有重新运行源码、Godot 或测试。

## 实际计数与每臂分解

两臂都实际运行 300 physics ticks。输入 buffer schema 为 8 identities、15 scalars、10 vectors，因此可核实输入字节为 `8*8 + 15*8 + 10*8 = 264 bytes/call`。输出字节没有 instrumentation，报告不估算或补造该数字。

按既有互不重叠定义：`R = enemy_outer + retained_move + observation + attack`，`P = quantum_compute`，`B = packing_bridge`：

| arm | R: outer | R: retained move | R: observation | R: attack | R total (µs) | P compute (µs) | B packing (µs) | sample elapsed (µs) |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| LOCAL | 761,683 | 407,992 | 40,209 | 9,951 | **1,219,835** | 1,054,037 | 110,652 | 4,954,646 |
| ABI_SHAM | 735,341 | 411,216 | 38,526 | 12,244 | **1,197,327** | 1,007,297 | 129,503 | 4,957,578 |

目标 `R=1,028,639.25 µs`，两臂 R 都高于目标。因此该切片没有证明达到目标，也没有给出绝对生产 lower bound。`P` 不是 fully portable 的未来实现成本；`B` 还没有覆盖未来 candidate packing/re-read 的完整成本，不能据此批准 50% 收益。

计数事实包括：LOCAL `outer_calls=10200`、`bridge_calls=16019`、diagnostic errors=0；ABI_SHAM `outer_calls=10200`、`bridge_calls=16023`、diagnostic errors=0。identity/scalar/vector bytes 和 bridge bytes 均保留在 JSON；这些是计数事实，不等于完整性能模型。

## 轨迹和严格归因边界

两次都声明同 layout、same identity order、same requested fixture 和 300 ticks，但实际轨迹并不相同：

- LOCAL moving ticks `107`、总移动 `3.0628186835836 GU`；ABI_SHAM moving ticks `130`、总移动 `3.05363195088421 GU`。
- 两者攻击 starts 都是 `16`，但 LOCAL player HP end/loss 为 `120/167`，ABI_SHAM 为 `161/174`。
- potion 使用 tick：LOCAL `[45, 90, 195]`；ABI_SHAM `[45, 90, 225, 255]`。
- engaged enemy count：LOCAL `8677`；ABI_SHAM `8649`。

所以严格 paired bridge attribution 为 **UNKNOWN**。这些结果可以支持 transport 诊断开销的记录，不能把两臂 wall-clock 或 R/P/B 差异直接归因于 native transport，也不能作为生产优化收益。

## 状态边界

- 两个 runner：`PASS`。
- 30 tick sham comparison JSON：`PASS`，但 `diagnostic_only=true`。
- 严格 paired causal attribution：`UNKNOWN`。
- 输出字节完整测量：`MISSING`。
- 未来候选完整 packing/re-read 成本：`MISSING`。
- 生产性能、50% 收益、主 APK、设备验证：`NOT_RUN`。
