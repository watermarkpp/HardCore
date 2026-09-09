# W4 正式地图全活跃真实帧探针

## 目的

`tests/audio_w4_full_frame_probe_test.tscn` 用同一份可执行夹具记录旧音频服务与 W4 服务在正式地图中的全帧 CPU、真实攻击起手、音频服务请求、播放和拒绝计数。它用于补足早期只保留可听 3/11 个 actor 的固定探针证据；本探针要求总 actor 数为 20 和 50，并要求每个保留 actor 在采样窗口内至少完成一次真实攻击起手。

探针只写测试和本目录文档，生产代码、GameRoot、PlayerState、地图、怪物数据、战斗随机数、AI 速度/间隔和 runner 注册均不改。`AudioProxy` 只包裹场景已经创建的 `AudioRuntimeService`，每次请求都转发到正式服务并记录返回的 `status`；预算、SFX 门控、精确 monster ID 资源解析、播放槽和拒绝原因仍由正式服务决定。

## 固定场景与真实路径

- 地图固定为 `world_wooma_forest` / `map_id=910004`。
- 固定展示 seed 为 `20260909`；每个 actor 的音频测试 seed 是该值加其 cohort 下标。它只设置 `EnemyActor` 的 presentation audio RNG，不改战斗 RNG。
- 一个新 `GameRoot` 先按 `spawn_serial` 保留前 50 个普通怪物并完成 50 档，然后在同一正式地图实例中排队释放多余 actor，再完成前 20 个 cohort；Boss 与多余普通怪物不会进入采样。这样避免重复构建 main 场景触发 HUD viewport signal 的无关连接错误，同时每一档仍重新设置 actor 位置、目标、会话和服务计数。布局搜索使用正式地图投影、环境 actor 半径、点碰撞和 segment LOS 检查。
- 每个保留 actor 放到相同的确定性候选布局，并配一个合法地图内的独立 `Node2D` 目标。目标实现正式攻击路径所需的 `take_damage`、`is_stealthed`、`agility`、`anti_poison` 和 `runtime_map_id`。目标不进 `combat_targets`，玩家暂时移出该组只为阻止共享目标竞争；actor 仍通过生产 `target` setter、真实 LOS、攻击间隔、动画和 audio hook 工作。
- 目标距离使用每个 actor 调用 `_contact_distance_gu_to_target()` 得出的正式接触距离，避免重叠后退分支。source、target、segment 和 viewport 可听边界全部在夹具中断言。
- 夹具只等待 `get_tree().physics_frame` 和 `get_tree().process_frame`；不直接调用 `_physics_process`，也不手工增加攻击或音频计数。`_audio_attack_sequence` 的增量必须与 proxy 看到的 `attack_start` 请求一一对应。候选 W4 另外按 owner key 逐 actor 对账；旧服务没有 owner context，则按实际事件的 monster ID 和全局攻击请求对账。

每个条件先经历 60 个真实 physics tick，再采集 240 个真实 physics tick；每个 tick 都通过 `physics_frame` 和随后的 `process_frame` 边界等待，headless 下因此可能观察到多于 240 个 idle/process callback。`RuntimeDiagnostics`/`DeviceLabRuntime` 提供全帧 p50/p95/p99；夹具自带 recorder 同时断言至少 240 个 physics tick 和 process frame。proxy 还记录每次正式 `AudioRuntimeService` 调用的毫秒样本，输出 `audio_cpu_ms` 的 p50/p95/p99（这是服务准入/资源调用时间，不把它误称为整帧或设备混音时间）。服务字段同时保留 requests、plays、rejected、reject reason、attack start/frame、combat prompt、pool/cache 等原始指标。

## 配对条件

在 `cf1d2718befdef7e6cc2fb274fd91ce0759d105f` 基线运行 `legacy_on` 和 `legacy_off`；在 W4 候选运行 `candidate_on`。每个 actor 数的 on/off 条件复用同一次正式地图、cohort、布局和独立目标；20/50 两档在各自 runner 进程中使用相同确定性布局算法和 seed，单进程内按 50 后 20 的顺序复用一个 GameRoot。旧版的 off 通过原 SFX bus mute，W4 的 on 通过正式 `set_sfx_enabled` 与 SFX bus 路径，不把 muted 请求改写成播放。

旧服务没有 `metrics_snapshot()`、combat prompt API 或 owner context。它的请求序列和每个 monster ID 事件由 proxy 记录；候选服务则保留完整 `metrics_snapshot()` 和 owner 对账。两种服务的拒绝/播放结果都原样保存，不能用候选服务替换旧版结果。

## 运行命令

普通功能调试和正式重场景都使用本工作树的 console/headless runner；性能探针用 60 秒超时：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_full_frame_probe_test.tscn -TimeoutSeconds 60
```

runner 会把 stdout、stderr、Godot engine log 和结果 JSON 写入本工作树 `outputs/test_logs/`。应保存完整三件套和 `runner_results_*.json`，按结果 JSON 的 `git_head` 绑定代码版本。基线树只能使用同一测试文件的只读副本和独立的 `.godot`/`outputs`，不能共享缓存或生成输出。

成功输出以 `AUDIO_W4_FULL_FRAME_COMPARE_JSON=` 开头，并包含 20/50 的每 actor `actor_proof`、布局签名、frame p50/p95/p99、请求/播放/拒绝和服务指标；最终 marker 是 `AUDIO_W4_FULL_FRAME_COMPARE_PASS`。缺少任一 actor 的真实攻击起手、真实 `attack_start` 请求、完整 frame window、合法布局或 runner 严格退出码，都不能算 PASS。

## 证据边界

这是正式地图实例化后由 Godot headless 执行的真实 process/physics、CPU 和服务准入证据。它不测扬声器混音延迟、硬件音频线程、GPU 提交、Android CPU/GPU 或设备声音；任何“性能提升”或设备结论都必须另有真实设备证据。探针不为达到数字而关闭预算、减少实际攻击 actor、改变 AI/寻路/战斗频率，也不把总 actor 数写成全部 active/全部播放。

当前文件只定义可复现采样入口；在安静窗口完成候选与固定 `cf1d` 基线六条件后，应把原始输出、失败日志和最终 `git_head` 追加到 `W4_HANDOFF.md`，并清楚区分调试运行与正式 paired evidence。
