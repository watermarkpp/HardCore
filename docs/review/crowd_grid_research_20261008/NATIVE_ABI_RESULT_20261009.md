# Task1 原生 ABI 复核结果（2026-10-09）

结论：**PASS（有界 fresh review）**。本结论只覆盖冻结的 Task1 原生 ABI、几何边界和契约执行链；不代表性能提升、生产集成、APK 或设备验收。

## 最终执行证据

最终采用 `task1/green4`，没有把旧 sampled green 结果当作验收依据。

- `green4/runner_receipt.json`：`crowd_native_kernel_contract_20261009.tscn`，pass marker 已发现，进程正常退出，wrapper/native/effective exit 均为 0，timeout=false，stderr failure=0，engine log failure=0。
- `green4/contract.json`：300 个检查全部 `passed=true`（300/300），包含 ABI load/class/version、核心穿透/重叠/切线、低高半径、double low/high、向量边界、夹紧、退化、NaN/Inf 以及 fuzz 项。
- 实际运行日志 `green4/f09e9f2b-6df8-4519-8dc6-016234ebf193/crowd_native_kernel_contract_20261009.godot.log` 保留 Godot `4.7.stable.official.5b4e0cb0f` 与 `HC_CROWD_NATIVE_KERNEL_CONTRACT_20261009_PASS checks=300`。
- 原生结果和 runner receipt 的绝对运行根均绑定到隔离 worktree `C:\Users\Administrator\.codex\worktrees\crowd-v107-comparison\HardCore` 及独立 runtime appdata；本轮复核没有重跑 Godot。

## 构建与 producer 绑定

`build5/build.log` 是最终构建日志（SHA-256 `4213b57d9fd8cd6b9dc3a3a51d44df4a498155490c3188e8e686cfd9aa04f44b`），记录 pinned SDK 的 SCons 4.11.1 构建，最后完成 static library 与 `crowd_melee_kernel.windows.template_debug.x86_64.dll` 链接。固定输入记录为 `green4/run_inputs.json`，其命令为：

```text
tools/build_crowd_kernel.ps1 -> pinned SDK SConscript, api_version=4.7 platform=windows target=template_debug arch=x86_64 optimize=speed precision=single build_profile=research/native/crowd_kernel/build_profile.json -j4
tools/run_godot_tests.ps1 -TestPaths tests/crowd_native_kernel_contract_20261009.tscn -TimeoutSeconds 30
```

运行时 producer binding 位于 `green4/contract.json:run_binding`：

- 实际 Godot：`tools/godot-4.7/Godot_v4.7-stable_win64.exe`，SHA-256 `b2ca888d5115a6cedee564764a2ee494a625f2ec2edbabd010fe33c9a88a6bf8`。
- console launcher SHA-256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`。
- 加载 DLL SHA-256 `20fd2895439426d648ab58eb00340ddde9822ffd673cc6d247c9b5e97d0796cc`。
- manifest SHA-256 `18ffced2a29f161d9b08a1b47ce3bfa3220d1e1d364daa527743fc7542e7b410`。
- SDK commit `272e7f4a5fde342ea20983371fffafdccea07f20`，SCons `4.11.1`。

源文件哈希由 `green4` 的运行时 `binding-source-*` 检查和 producer 的 `run_inputs` 固定。主控随后在冻结的 research worktree 逐项重算全部源码 SHA256，全部匹配，并在 task1/source_snapshot 保留原始文件；这是离线证据核对，没有重新运行测试。主树有意不包含原生原型，生产集成仍为 NOT_RUN。

## 保留的失败和旧证据

- `build4/build.log` 是真实 FAIL：编译 `godot-cpp/src/core/print_string.cpp` 时缺少 `godot_cpp/classes/os.hpp`，随后 SCons 终止。后续 build5 才是实际最终 DLL 的构建证据。
- `red4` 是真实 FAIL：覆盖了 `real_t` 签名缩窄在 double 低阈值上的问题；首轮还发现 expected launcher `D805...` 与运行时实际 engine payload `B2CA...` 不一致。该目录及 contract/receipt/raw 均保留。
- `green`、`green2`、`green3` 的旧 sampled semantics 不作为最终证据；对应 raw 目录完整保留。旧 build receipt、旧 DLL 哈希和早期 manifest 也不覆盖最终 build5/green4 producer binding。
- 主控已在实际 research worktree 核对所有输入并留 source_snapshot。早期 fix_manifest.json 属于 green3 的历史输入，不与最终 current_run_inputs/green4 混用。

## 安全边界

这次 PASS 只说明指定冻结输入下，实际运行 Godot 加载了 producer 绑定的 DLL，并通过了 300 项原生契约。它不说明无限几何覆盖，不说明 CPU/帧时间改善，不说明 50% 性能收益，也不说明 gameplay、APK 或设备结果。后续若要晋升，必须在固定源、固定 engine/DLL/manifest 和完整 runner receipt 下另行完成相关集成与性能证据。

机器可读明细见 `outputs/crowd_native_kernel_20261009/task1/VERIFICATION.json`；原始证据见同目录 `raw/`、`build4/`、`build5/`、`green4/`、`red4/`。
