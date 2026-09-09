# Bugfix24 W4 音频包交接

## 基线与范围

- 工作树：`C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-20260909`
- 分支：`codex/bugfix24-audio-20260909`
- 固定施工基线：`cf1d2718befdef7e6cc2fb274fd91ce0759d105f`
- 允许写入：`scripts/audio_runtime_service.gd`、`scripts/enemy.gd` 的音频变量/方法/既有生命周期音频接线、音频配置、音频测试、本目录文档。
- 未修改：`GameRoot`、`PlayerState`、runner 注册、爆率/数据、战斗随机数、AI 导航速度/间隔、UI 和地图。

启动时执行的旧 bootstrap 白名单不认识专项分支，报告了
`Unknown branch for bootstrap routing: codex/bugfix24-audio-20260909`；按项目规则以指定
基线和 integration 规则完成等价预检，没有改 bootstrap 或跳过保护检查。

## 根因与实现

计划中的 W4 根因是运行时保留了 `play_monster_ambient_if_due`：行走/转向动画 frame 1
按每个 actor 的独立 RNG 以 1/8 播放 ambient。`appear` 也属于出生语义，不能表示发现玩家。
服务本身已有独立 NPC 播放器、24 个 event 播放器、缓存和预热；问题是怪物事件白名单和请求
前的会话/预算门禁没有收口。

本包在 `AudioRuntimeService` 集中处理以下顺序：SFX 开关 → 怪物语义白名单 → owner/release
去重 → 事件池和怪物子池/速率预算 → 预热缓存样本 → 申请播放槽。门禁失败使用轻量诊断，
不会先复制完整上下文或访问音频资源。

生产怪物事件只保留：

1. `attack_start` 和源上存在的 `attack_frame`。EnemyActor 只有攻击动作起点确认播放成功后才
   允许观察攻击帧，遮挡/不可听/预算拒绝的起点不会伪造后续音效。
2. `play_monster_combat_prompt(monster_id, audio_owner_key, context)` 的一次入战提示。没有
   专属提示样本时通过精确 `monster_id` 复用该怪物原 `ambient` 绑定，返回语义是
   `combat_prompt`，来源语义保留为 `ambient`。

`appear`、持续 `ambient`、`hurt`、`death` 和 `death_secondary` 保留映射资料供审计，但生产
入口拒绝。旧 `play_monster_ambient_if_due` 只返回 `ambient_disabled`，不抽 RNG、不访问流、
不播放声音。

会话按 actor owner 保存。target 刷新和 `los_interrupted`、`los_blocked`、`path_blocked` 等
短暂 LOS/path 状态不会结束会话；`target_dead`、安全区、leash、world/session exit 和显式
脱战才结束，真实脱战后经过 0.75 秒工程防抖才允许重入。EnemyActor owner key 使用
`monster_id + instance_id`，攻击使用 `attack:<sequence>` release，入战提示使用
`combat:<session>`，所以同一次 release 不能重复占池。

工程初值集中在 [`audio_runtime_config.json`](../../../../assets/data/audio/audio_runtime_config.json)：

- event 总池：24
- 怪物并发：6
- 入战提示新启动：3/s
- 怪物攻击新启动：12/s
- 真实脱战重入防抖：0.75 s
- 当前配置记录 LOS grace：1.25 s
- `effective_sfx_gain = existing_user_gain × 0.5`

NPC voice 和 event pool 都通过 SFX bus 使用线性 0.5（约 `-6.0206 dB`），每次从原始用户增益
重新计算，重复设置不会继续折半。Music bus 和 `TownMusicController` 未被修改。

EnemyActor 对 W3 后续接口采用兼容适配：若目标实现 `combat_transition_is_active()`，加载/切图
期间在音频服务准入前拒绝；若目标提供 `combat_epoch` 方法或属性，则把 epoch 写入音频上下文。
当前音频基线没有该方法，未伪造字段。

## integration 必须接线

本包不改受保护的 `scripts/game_root.gd`。主控合入时需要：

1. `add_child(_audio_runtime_service)` 后调用
   `_audio_runtime_service.sync_sfx_enabled_from_bus()`，使服务开关和已有 SFX bus 状态一致。
2. 在 `_on_system_menu_audio_setting_changed` 的 `audio.sfx.enabled` 分支同时调用
   `_audio_runtime_service.set_sfx_enabled(bool(request.get("enabled", true)))`，再保留原有
   `AudioServer.set_bus_mute`。关闭时事件请求应在缓存样本前返回 `sfx_disabled`。
3. 若后续恢复任何遗留 `AudioStreamPlayer`/`AudioStreamPlayer2D` SFX 播放器，使其经过服务的
   SFX 路由/增益入口，并传入尚未乘工程缩放的原始用户增益；不要修改 Master，也不要对已经
   乘过 0.5 的持久化值再次折半。当前 `PlayerVisual` 的旧 `WeaponAudio` 仍由既有临时 gate
   停止，实际已审计动作声走服务。
4. EnemyActor 无需另加每帧调用；target 变成有效对象时现有 setter/physics 生命周期会尝试
   入战提示，服务 group 必须在生成怪物前存在。W3 合入后可保留本包的 has_method/epoch 适配。

## 测试与日志

受控导入（console/headless，退出码 0）：

```text
tools/godot-4.7/Godot_v4.7-stable_win64_console.exe --headless --editor --path . --quit --log-file outputs/test_logs/audio_import_console.log
```

正式 runner 均使用工作树 .godot/runtime_appdata 和 outputs/test_logs；普通专项超时 30 秒，正式地图性能探针使用 60 秒。生产链 fe3585ff -> 4f714f75 的专项 PASS 证据如下：

| 测试 | 命令结果 | runner 结果文件与 HEAD |
|---|---|---|
| 服务映射、NPC/玩家/物品回归、W4 会话和增益 | PASS | outputs/test_logs/runner_results_adhoc_20260909_122625_833_15296.json，HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480 |
| EnemyActor 正式音频入口/生命周期 | PASS | outputs/test_logs/runner_results_adhoc_20260909_122548_728_7712.json，HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480 |
| 真实 EnemyActor + AudioRuntimeService 联合入口 | PASS | outputs/test_logs/runner_results_adhoc_20260909_122601_741_8876.json，HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480 |
| W4 预算、并发和资源前拒绝 | PASS | outputs/test_logs/runner_results_adhoc_20260909_122614_913_11428.json，HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480 |
| 玩家核心音频回归 | PASS | outputs/test_logs/runner_results_adhoc_20260909_121443_289_23396.json，HEAD fe3585ffccc8866e8e4586a09fa61af5464b4719 |
| 玩家物品音频回归 | PASS | outputs/test_logs/runner_results_adhoc_20260909_121502_951_8328.json，HEAD fe3585ffccc8866e8e4586a09fa61af5464b4719 |
| 投射物音频生命周期回归 | PASS | outputs/test_logs/runner_results_adhoc_20260909_121519_209_19576.json，HEAD fe3585ffccc8866e8e4586a09fa61af5464b4719 |
| W4 固定性能探针 | PASS | 候选和基线 runner 结果见下方固定性能采样段；两次均 passed=1 failed=0 engine_log_errors=0 |
对应命令示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_runtime_service_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/monster_audio_hook_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_contract_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_performance_probe_test.tscn -TimeoutSeconds 60
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/player_core_audio_hook_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/player_item_audio_event_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/projectile_audio_lifecycle_test.tscn -TimeoutSeconds 30
```

修复过程中的失败全部保留在 `outputs/test_logs`：

- `runner_results_adhoc_20260909_113635_582_22876.json`：受控导入前全局类缓存缺失，
  `MonsterAnimationPolicy` 等 import error；之后完成 console/headless 导入。
- `runner_results_adhoc_20260909_115010_271_20376.json`：旧测试仍断言 ambient frame 1，
  更新为 W4 静音兼容断言。
- `runner_results_adhoc_20260909_115524_710_4320.json`、
  `runner_results_adhoc_20260909_115548_936_10800.json`、
  `runner_results_adhoc_20260909_115606_019_5676.json`：会话断言读取了返回对象的
  `reason` 而不是 `status`，修正测试字段读取；没有降低实现断言。
- `runner_results_adhoc_20260909_115658_354_6656.json`：预算测试同样误读 `reason`，修正后
  `audio_w4_contract_test` PASS。

## 固定性能采样

正式对照采用两个独立工作树和同一份固定性能夹具：

- 旧基线工作树：C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-baseline-20260909，detached HEAD cf1d2718befdef7e6cc2fb274fd91ce0759d105f。
- 候选工作树：C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-20260909，生产 HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480，生产链为 fe3585ffccc8866e8e4586a09fa61af5464b4719 -> 4f714f7545077bcba3f5fd362159d87bfbcbb480。
- 两次运行都实例化正式地图 world_wooma_forest（map_id 910004），从同一组已编排的 50 个普通 EnemyActor 中取前缀 20 或 50 个；固定 seed 20260909，热身 30 帧，采样 64 帧，步长为 1/60 秒。
- 夹具保留 50 个普通 actor，按生产 _audio_is_listenable() 只给可听见的真实 cohort 设置 player target。实际 active cohort 是总 actor 20 时 3 个、总 actor 50 时 11 个（采样结束仍可听见分别为 3 和 10）；其余 actor 没有伪造攻击边界，结果不能描述为 20/50 个都在攻击。
- 每帧 CPU 是直接驱动该正式地图 EnemyActor 的 _physics_process；audio CPU 是同一批 actor 的生产 _audio_try_enter_combat_session / _audio_observe_visual_state 路径。AudioProxy 只统计真实 GameRoot AudioRuntimeService 的请求和 status=played 返回，没有绕过服务或合成播放计数。

完整原始 JSON 行和逐帧样本保留在各工作树的 outputs/test_logs/audio_w4_performance_probe_test.stdout.log。下表的 full frame 与 audio CPU 单位均为毫秒，顺序为 p50/p95/p99；request/play 是该条件内 proxy 观察到的服务请求数/实际 played 数。

| 代码与 SFX | 总 actor | active/采样末可听 | service request/play | full frame p50/p95/p99 | audio CPU p50/p95/p99 |
|---|---:|---:|---:|---:|---:|
| cf1d legacy_on | 20 | 3/3 | 3/0 | 0.353/0.537/0.812 | 0.014/0.028/0.053 |
| cf1d legacy_off | 20 | 3/3 | 3/0 | 0.288/0.472/0.489 | 0.014/0.016/0.018 |
| W4 candidate_on | 20 | 3/3 | 3/3 | 0.461/0.512/0.587 | 0.014/0.028/0.036 |
| cf1d legacy_on | 50 | 11/10 | 11/0 | 0.898/1.358/1.562 | 0.035/0.042/0.058 |
| cf1d legacy_off | 50 | 11/10 | 11/0 | 0.833/1.335/1.388 | 0.062/0.069/0.075 |
| W4 candidate_on | 50 | 11/10 | 11/3 | 1.038/1.522/1.601 | 0.057/0.074/0.090 |

独立 warmup 30 帧的 p50/p95/p99 依次为：legacy_on-20 0.295/0.492/0.513，legacy_off-20 0.300/0.503/0.548，candidate_on-20 0.338/0.503/0.513；legacy_on-50 0.862/1.824/1.825，legacy_off-50 0.902/1.354/1.532，candidate_on-50 1.038/1.766/1.920。

候选 20 条件的服务指标为 prompt admitted 3、polyphony rejected 0、stream lookup 3、stream cache miss 0、owner release duplicate 0；候选 50 条件为 prompt admitted 3、polyphony rejected 8、stream lookup 3、stream cache miss 0、owner release duplicate 0，配置的怪物并发上限为 6。两次候选条件的 project_sfx_gain_linear 和 effective_sfx_gain_linear 都是 0.5。旧版的 play=0 是旧 service 运行时返回的真实观察结果，未将请求数改写成播放数，也未用候选服务替代旧版本。

正式 runner 证据：

- 候选：C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-20260909/outputs/test_logs/runner_results_adhoc_20260909_130820_055_20704.json，HEAD 4f714f7545077bcba3f5fd362159d87bfbcbb480，passed=1 failed=0 engine_log_errors=0。原始 stdout/stderr/Godot log 为同目录的 audio_w4_performance_probe_test.stdout.log、.stderr.log、.godot.log。
- 基线：C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-baseline-20260909/outputs/test_logs/runner_results_adhoc_20260909_130511_297_4320.json，HEAD cf1d2718befdef7e6cc2fb274fd91ce0759d105f，passed=1 failed=0 engine_log_errors=0。原始 stdout/stderr/Godot log 为同目录的同名三件套。
- 基线先完成受控 console/headless 导入，日志为 C:/Users/Administrator/Documents/HardCore-worktrees/bugfix24-audio-baseline-20260909/outputs/test_logs/audio_baseline_import_console.log，退出码 0；导入缓存达到 16929 个文件。未使用 GUI，也未改共享 dev_art_sources 或 editor data。

失败现场全部保留并定性如下：

- 候选 runner_results_adhoc_20260909_123857_236_5800.json、124344_718_18424.json：外层把 runner stdout 重定向到 runner 为子进程保留的同名 stdout 文件，导致子进程/marker 失败；两次 engine_log_errors=0，不是生产错误。
- 候选 runner_results_adhoc_20260909_124506_514_9844.json、124552_025_3064.json：同一日志重定向冲突的后续残留，分别为 early script/child stderr 失败；停止外层重定向后由 124806_474_14380.json 起恢复 PASS。
- 基线 runner_results_adhoc_20260909_125748_729_12984.json：完整导入尚未结束，正式地图资源的 PNG loader 缺失；随后受控导入完成，未改生产代码。
- 基线 runner_results_adhoc_20260909_130246_204_10216.json：夹具调试快照直接读取旧基线不存在的动态字段，导致夹具运行时失败。
- 基线 runner_results_adhoc_20260909_130421_574_16180.json：夹具使用了 Godot 4.7 不支持的 Object.get 双参数调用；改为单参数读取并做类型保护后，130511_297_4320.json PASS。
- 更早的服务/actor 失败 113635_582_22876.json、115010_271_20376.json、115524_710_4320.json、115548_936_10800.json、115606_019_5676.json、115658_354_6656.json、120145_468_11028.json、120207_161_1980.json、122251_145_6680.json 的原因与上面的测试夹具/导入修正相同，原始 runner JSON 均未删除；没有通过删断言或挑选绿色结果解决。

headless 证据只覆盖正式地图实例化后的 EnemyActor 逐帧 CPU、生产音频服务准入、请求、播放、池和缓存计数；不代表真实扬声器混音延迟、硬件音频线程、渲染提交、Android CPU/GPU 或设备行为。没有生成 Android 结论，也没有通过减少 actor、改变 AI/寻路/战斗随机数或绕过服务制造性能收益。音频播放器在 headless 退出时可能留下 Godot 的资源/对象 teardown warning，runner 对最终两次运行均报告 engine_log_errors=0。

## 当前交付状态

- 生产代码已经在 fe3585ff、4f714f75 冻结；本次只交性能夹具和本交接文档。enemy.gd 音频写权限已释放给 integration/monsters 后续工作。
- integration 合入后须在包含 W3 的最终 HEAD 重跑 actor/service 入口，并按文档的 GameRoot 音频服务接线要求验收；本包不改 GameRoot，未宣称其接线已 PASS。
- 当前提交 SHA 在本次提交后记录；未推送。
- 不含 Android、真实设备声音或 GameRoot 接线 PASS；以上是主控合入所需动作。
