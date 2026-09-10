# AIA-2-R1 验收补强证据（可复查清单）

日期：2026-09-10。
BASE：`4f9faaf17135bfd13cb2acedb9b11d74988be2f0`（AIA-2 核心输入修复，不重写）。
RESULT：`8a4450e69fe98657266b6879b3c1707815c40659`（本轮新增补验提交，仅测试与本文档）。
裁决遵守：核心输入修改保留；未合入 `codex/integration`；未安排 APK/versionCode。

## 1. 环境与工具

- 工作树：`C:\Users\Administrator\Documents\HardCore-aia2`，分支 `deepseek/aia2-input-debt`。
- Godot：`4.7.stable.official.5b4e0cb0f`，可执行文件 `tools/godot-4.7/Godot_v4.7-stable_win64_console.exe`（console 版，未升级、未换渲染器）。
- 完整游戏 runner：`tools/run_godot_tests.ps1`（正式 runner；per-worktree 互斥、`outputs/test_logs`、`.godot/runtime_appdata` 隔离）。
- Python：3.12.10 + pytest 9.1.1（仅包内 28 项静态检查，见 AIA-2 首轮报告）。
- 源码指纹（RESULT，`git blob` 为准；工作副本因 autocrlf 可能被重喷为 CRLF，内容等价）：
  - `scripts/game_root.gd` blob `2ac3fd4fd3ca4c557a98bca91d59f99df4946f79`
  - `scripts/circular_touch_button.gd` blob `da6d8aae434afbf2aa8d0c2361b9752d5ae8a337`
  - `tests/mobile_targeting_test.gd` blob `830f0d591a1148eb1ca70a926ce03d2ce84498ca`
  - `tests/ordinary_attack_release_regression_test.gd` blob `0cf0d46a2264a770bc097b66a62d994b3cd74349`

## 2. Godot 隔离输入 harness（31/31）

工程：`outputs/aia2_pkg_extract/HardCore_AIA2_20260909/godot-input-harness/`（由 `tests/build_godot_harness.py --repo <worktree> --out <dir>` 从修补后实际代码提取输入函数与完整按钮生成；战斗几何为桩，明确不替代完整游戏）。

命令与退出码（import 成功与场景运行成功分开记录）：

| 步骤 | 命令 | 退出码 | 原始日志 |
|---|---|---|---|
| 构建 | `python tests/build_godot_harness.py --repo C:\...\HardCore-aia2 --out ...\godot-input-harness` | 0 | — |
| 导入 | `Godot_v4.7-stable_win64_console.exe --headless --path <harness> --editor --import` | 0 | `evidence/r1/harness_import.log` |
| 运行 | `Godot_v4.7-stable_win64_console.exe --headless --path <harness> res://test_main.tscn` | 0 | `evidence/r1/harness_run.log` |

运行结果行（harness_run.log 原文）：
`{"failures":[],"passed":31,"scope":"actual input functions/button, stub combat; NOT Android/full-game","suite":"AIA2_INPUT_ISOLATED"}`

31 项检查清单（tests/godot_test_runner.gd 逐条 `_check`，fps 参数化展开为 31）：
1 idle tap starts one action, no released replay；2 queue always empty；3 32 busy taps cannot create 10+ seconds of debt；4–6 stationary 60s hold preserves cadence at 30/60/120 fps；7–9 hold UP stops new actions at 30/60/120 fps；10 other finger UP does not cancel attack；11 CANCEL wins over pressed flag；12 two attack pointers: first UP preserves second；13 two pointers do not double attack rate；14 last pointer UP stops hold；15 wrong pointer id cannot revoke owner；16 wrong source cannot revoke owner；17 old token UP cannot revoke reused finger；18 duplicate legacy UP cannot revoke real touch；19 UP never resets cooldown；20 UP preserves current committed animation；21 root orphan owner is revoked；22 disabled button cannot keep root ownership；23 reenabling is not a fresh DOWN；24 fresh DOWN works after reenable；25 input gate cannot resurrect old debt；26 emulated mouse does not create attack；27 physical mouse still starts attack；28 physical mouse outside release stops hold；29 bound skill routes to its own lifecycle；30 bound skill does not also ordinary-attack；31 diagnostic ring remains bounded。

## 3. 长按测试补强（mobile_targeting_test.gd）

新增断言（替换"DOWN后立即_process只查朝向"的旧断言；目标选择断言逐句未动）：

1. 首刀动作序号 +1（`_combat_action_sequence == before+1`）。
2. 整个长按阶段 `pointer_down` 诊断恰好 +1 —— 不再发送 DOWN。
3. 首刀后把活目标移到 `(-4,-2)`（夹具已验证的合法格）。
4. 冷却与动作结束后由帧循环触发第二刀（`player._physics_process` + `game._process` 逐帧推进真实计时器，150 帧内恰好 `+2`，不多开）。
5. 第二刀动作序号再 +1 且朝向移动后的目标。
6. `attack_action_started` 诊断：`fresh_down` 恰好 +1、`live_hold` 恰好 +1。
7. UP 后推进 200 帧（≈3.3s ≥ 3 个攻击窗口）：动作序号不变、`_attack_action_timer == 0`（已开始的一刀自然收尾）。

### 变异检验（临时隔离，未提交）

对 `_process_ordinary_attack_input` 的 live_hold 分支做临时变异（仅工作树）：
`_try_ordinary_attack_intent(&"live_hold")` → `pass  # AIA2-R1 TEMPORARY MUTATION`

| 步骤 | 结果 | 证据 |
|---|---|---|
| 补强后（原实现） | PASS | `outputs/test_logs/runner_results_adhoc_20260910_100650_618_6716.json` |
| live_hold 关闭 | **FAIL**（`Assertion failed: 冷却和动作结束后帧循环没有恰好续出第二刀`，mobile_targeting_test.gd:124） | `runner_results_adhoc_20260910_100737_365_3600.json` |
| `git checkout -- scripts/game_root.gd` 恢复（HEAD 4f9faaf1，变异零提交） | PASS | `runner_results_adhoc_20260910_100801_283_20160.json` |

## 4. 真实游戏击杀回归（新增三场景）

脚本：`tests/ordinary_attack_release_regression_test.gd`（一个脚本，三个 runner 场景条目）。正式映射世界（`tests/helpers/formal_world_skill_fixture.gd` 夹具：READY 输入、正式 `_spawn_enemy` 事务、安全区/世界LOS校验、怪物清场）。击杀走真实管线：玩家 windup（`attack_hit_windup=0.17s`，SceneTreeTimer 真实引擎时间）→ `attack_requested` → GameRoot 近战几何 → `enemy.take_damage`。动作启动一律以 `PlayerCharacter._combat_action_sequence` 判定，不以队列长度判定。松手后以真实物理帧观察 720 帧 = **12.0 秒**。

| 场景 | 步骤 | 结果 | 原始标记（stdout.log） |
|---|---|---|---|
| 快速点按后松手 | 首点即开刀（seq+1）；冷却内再快点6次（不排队、无残留归属、不新开）；松手后观察12s | PASS | `AIA2_TAPS_RELEASE_PASS sequence=1 observed_seconds=12.0` |
| 单次长按击杀后松手 | 按住→首刀（seq+1）→真实伤害击杀（hp=1）→仍按住帧循环继续开刀（空挥语义保留）→松手→观察12s | PASS | `AIA2_HOLD_KILL_RELEASE_PASS sequence=2 observed_seconds=12.0` |
| 怪死仍按住+旁边活怪 | 按住→击杀→帧循环续刀且自动锁到旁边活怪（锁定断言）→松手→观察12s→邻居存活 | PASS | `AIA2_HOLD_KILL_RETARGET_PASS sequence=2 observed_seconds=12.0` |

三个场景均断言：观察期内动作序号冻结、`_attack_action_timer == 0`（已开始的一刀正常收尾）、无取消行为。
运行记录：`runner_results_adhoc_20260910_101547_407_12064.json`（passed=3 total=3，git_head=8a4450e6，每场景 effective_exit_code=0）；逐场景 stdout/stderr/godot 日志见 `outputs/test_logs/ordinary_attack_*.log`。

## 5. README 7.7 受影响回归复跑（19/19）

命令：`tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths <19场景>`，退出码 0。
记录：`outputs/test_logs/runner_results_adhoc_20260910_101946_120_14056.json`（passed=19 failed=0 engine_log_errors=0，git_head=8a4450e6）。

| 场景 | 覆盖矩阵行 | 结果 |
|---|---|---|
| android_attack_action_lifecycle_test | 原始attack action/键盘J、Space | PASS |
| circular_touch_button_lifecycle_test | 控件外UP/CANCEL、生命周期 | PASS |
| input_release_cleanup_test | 松手/取消清理 | PASS |
| gameplay_input_gate_test | 输入门禁边界 | PASS |
| virtual_joystick_lifecycle_test | 双指/摇杆独立指针 | PASS |
| mobile_targeting_test | 选敌/长按补强/双攻击指针/三职业归属 | PASS |
| warrior_attack_timing_test | 攻击频率（冷却决定） | PASS |
| player_attack_interrupt_consistency_test | 受击打断一致性 | PASS |
| warrior_skill_state_machine_test | 攻击键绑定技能 | PASS |
| skill_input_policy_test | 技能输入合并/冷却 | PASS |
| game_root_loading_transition_test | Loading 边界 | PASS |
| system_menu_test | 暂停/菜单 | PASS |
| map_transition_input_lock_test | 地图切换锁 | PASS |
| death_revival_touch_input_test | 死亡/复活触控 | PASS |
| live_attack_resolution_test | 攻击结算 | PASS |
| warrior_attack_priority_policy_test | 半月/刺杀/烈火优先级 | PASS |
| initial_world_input_lock_test | 进场不产生攻击 | PASS |
| hud_ui_action_bridge_test | HUD 桥接 | PASS |
| touch_scroll_support_test | 触控滚动 | PASS |

模拟鼠标（DEVICE_ID_EMULATION）由 harness 第26项 + circular_touch_button_lifecycle_test 共同覆盖。

## 6. NOT_RUN（明确不冒充 PASS）

- Android 真机三场景实测（同学故障机、成功机对照）：NOT_RUN——未连接任何设备。
- APK 构建、versionCode、覆盖安装、存档保持：NOT_RUN——按裁决不擅自安排。
- 真机 30/60/120FPS 长按节拍：NOT_RUN（软件层由 harness 4–9 项以真实冷却模型覆盖）。
- 已加载热补丁身份、包内 build_info 核对：NOT_RUN——无构建物。
- Godot 全局层收不到 UP/CANCEL 的系统输入投递取证：NOT_RUN——需故障机 + trace-only 诊断包（`HardCore-aia2-trace` 已备，未构建 APK）。

## 7. 边界遵守

本轮仅改测试与证据文档（4 个测试文件 + 3 个场景 + 本文档）。未修改冷却、动作帧、伤害、输入门禁；未加入固定长按超时、任意手指UP清全部、机型特判；变异代码未提交（`git checkout` 恢复，HEAD 内 game_root.gd blob 与 4f9faaf1 一致）。

## 8. 差异清单（BASE → RESULT）

```
tests/mobile_targeting_test.gd                     | 68 +++++++
tests/ordinary_attack_hold_kill_release_test.tscn  |  7 +
tests/ordinary_attack_hold_kill_retarget_test.tscn |  7 +
tests/ordinary_attack_release_regression_test.gd   |221 ++++++++++
tests/ordinary_attack_tap_release_test.tscn        |  7 +
5 files changed, 310 insertions(+)（不含本文档）
```
