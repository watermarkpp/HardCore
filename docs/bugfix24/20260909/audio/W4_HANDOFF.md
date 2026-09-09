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

正式 runner 均使用工作树 `.godot/runtime_appdata` 和 `outputs/test_logs`，普通超时 30 秒：

| 测试 | 命令结果 | runner 结果文件 |
|---|---|---|
| 服务映射、NPC/玩家/物品回归、W4 会话和增益 | PASS | `outputs/test_logs/audio_runtime_service_test.stdout.log`；最终 runner JSON 以交付消息列出的 `runner_results_adhoc_*.json` 为准 |
| EnemyActor 正式音频入口/生命周期 | PASS | `outputs/test_logs/monster_audio_hook_test.stdout.log` |
| 真实 EnemyActor + AudioRuntimeService 联合入口 | PASS | `outputs/test_logs/audio_w4_actor_service_test.stdout.log` |
| W4 预算、并发和资源前拒绝 | PASS | `outputs/test_logs/audio_w4_contract_test.stdout.log` |
| 玩家核心音频回归 | PASS | `outputs/test_logs/player_core_audio_hook_test.stdout.log` |
| 玩家物品音频回归 | PASS | `outputs/test_logs/player_item_audio_event_test.stdout.log` |
| 投射物音频生命周期回归 | PASS | `outputs/test_logs/projectile_audio_lifecycle_test.stdout.log` |
| W4 固定性能探针 | PASS | `outputs/test_logs/audio_w4_performance_probe_test.stdout.log` |

对应命令示例：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_runtime_service_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/monster_audio_hook_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_contract_test.tscn -TimeoutSeconds 30
powershell -NoProfile -ExecutionPolicy Bypass -File tools/run_godot_tests.ps1 -TestPaths tests/audio_w4_performance_probe_test.tscn -TimeoutSeconds 30
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

`audio_w4_performance_probe_test` 在相同当前代码、预热缓存、console/headless 环境下，
每个条件 32 个批次，逐批驱动 0/10/20/50 个合成 monster attack 请求；为测量路由而停止
每个已准入声部，并用隔离服务时钟跨预算窗口，未改变实际怪物数量、AI、寻路、战斗随机数或
地图。完整 JSON 在 `outputs/test_logs/audio_w4_performance_probe_test.stdout.log`。

| 怪物请求数 | 新代码 SFX on p50/p95/p99 ms | 新代码 SFX off p50/p95/p99 ms | on 实际启动数 | off 拒绝数 |
|---:|---:|---:|---:|---:|
| 0 | 0/0/0.001 | 0/0.001/0.001 | 0 | 0 |
| 10 | 0.670/0.738/0.752 | 0.121/0.130/0.138 | 320 | 320 |
| 20 | 1.335/1.455/1.470 | 0.242/0.278/0.284 | 640 | 640 |
| 50 | 3.351/3.432/3.473 | 0.608/0.705/0.708 | 1600 | 1600 |

`old code on/off` 无法在当前工作树与新服务并存执行，因此探针 JSON 明确记录
`legacy_old_on.status=not_available_in_current_head`，没有把新旧代码伪装成同条件对照。
headless 只能证明本服务的准入、池、缓存和 CPU 路径；不能证明真实扬声器混音延迟、硬件
音频线程、渲染帧时间或 Android 行为。本包没有 Android 结论，也没有降低 AI 或删除怪物来
制造性能结果。

## 当前交付状态

- 代码/测试/配置已完成，待 integration 合入后在包含 W3 的真实最终 HEAD 重跑相关 actor 和
  GameRoot 入口。
- 当前提交 SHA 在提交后记录；未推送。
- 不含 Android、真实设备声音或 GameRoot 接线 PASS；以上是主控合入所需动作。
