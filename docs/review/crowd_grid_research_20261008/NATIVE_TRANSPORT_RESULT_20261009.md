# Task2 原生 ABI transport 复核结果（2026-10-09）

结论：**PASS（有界 transport 证据）**。本报告只覆盖 Task2 的 Godot 原生 ABI transport 契约，不能推出性能改善、50% 收益、生产集成、APK 或设备验收。

## GREEN 实际执行

`green/runner_receipt.json`（来源为 `outputs/test_logs/runner_results_adhoc_20261009_014149_106_21804.json`，已复制到本目录）记录：

- 场景：`tests/crowd_quantum_abi_contract_20261009.tscn`。
- pass marker 已发现；wrapper、native、effective exit code 均为 0。
- `timeout=false`、stderr failure=0、engine log errors=0，runner total=1、passed=1、failed=0。
- 运行 worktree 为隔离的 `C:\Users\Administrator\.codex\worktrees\crowd-v107-comparison\HardCore`，runtime appdata 同样隔离。
- Godot 日志固定为 `4.7.stable.official.5b4e0cb0f`，并记录 `HC_CROWD_QUANTUM_ABI_CONTRACT_20261009_PASS checks=36`。

`contract.json` 的 36 项检查全部通过（36/36）。实际检查包括：

- extension load、`CrowdMeleeKernel` 注册、ABI version 1、`forward_buffers` ClassDB binding；
- 返回值是 Array 且严格为三通道；
- channel 0 为 `PackedFloat64Array`，channel 1 为 `PackedVector2Array`，channel 2 为 `PackedInt64Array`；
- float64/vector payload、int64 identity、精确 byte/COW 行为及对应边界检查。

因此 GREEN 是真实 engine/native contract 执行证据，不是静态或 mock 结果。

## RED 到 GREEN 的因果边界

`red_contract.json` 保留了初始失败：17 项中 16 项通过，唯一失败为 `ABI-forward-method`，即 sealed Task1 DLL 缺少 `forward_buffers` 方法。其 `red_runner_receipt.json` 记录 pass marker 未发现、effective exit code=1、timeout=false、engine log errors=0，失败原因是 `missing_pass_marker;non_zero_exit_code_1`。

GREEN 使用重建后的 transport 输入，最终 DLL SHA-256 为：

```text
96e6ba8d6c0a6286620e5b96eac6cdcd6c55c3fc7e9c5d412ae468586b9e5ae3
```

RED 的 DLL SHA-256 为旧 sealed Task1 DLL：

```text
20fd2895439426d648ab58eb00340ddde9822ffd673cc6d247c9b5e97d0796cc
```

两次均无 engine error 或超时；差异落在明确的 method transport/ABI surface，而非 runner 偶然失败。

## producer 与构建绑定

`contract.json:run_binding` 和 `run_inputs.json` 共同绑定：

- 实际 engine：`C:/Users/Administrator/.codex/worktrees/crowd-v107-comparison/HardCore/tools/godot-4.7/Godot_v4.7-stable_win64.exe`，SHA-256 `b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8`。
- final DLL SHA-256 `96e6ba8d6c0a6286620e5b96eac6cdcd6c55c3fc7e9c5d412ae468586b9e5ae3`。
- GREEN manifest SHA-256 `9271023ed24c027dc0f3a7dbd44c983de192b90489cf52a67cd0368a54ae81eb`。
- SDK commit `272e7f4a5fde342ea20983371fffafdccea07f20`。
- `build/build.log` 记录 DLL 链接成功，日志 SHA-256 `2f18b3ecc41e2cd5b8248e689c4c9d6b72a1eca1536a685ea8d8d91b777eb531`。
- source/test/build input hashes 均由 producer 的 GREEN contract binding-source checks 验证；当前主树没有研究源文件，因此本复核不把缺少本地源重算伪装成额外 PASS。

## 证据边界

本目录保留完整 RED/GREEN UUID 日志、stdout/stderr、native result、handoffs、contract、run inputs 和 build 日志。机器明细见 `outputs/crowd_native_kernel_20261009/task2/VERIFICATION.json`。

本轮只做离线证据整理，没有重新运行 Godot、测试或 native build。结果是 bounded ABI transport PASS；性能、完整 gameplay 行为、APK 内容、签名和设备验证均为 MISSING/未覆盖。
