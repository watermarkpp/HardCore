# Startup 两项 FAIL 因果审计（GLM 第三树续作，Task 2 只采证）

- 日期：2026-10-06
- 施工分支：`codex/glm-thirdtree-continuation-20261006`
- 审计时 HEAD：`4e03608362f801ccaf68e873a1a6d5b12591d087`（干净工作树，tracked 无修改）
- 引擎：`4.7.stable.official.5b4e0cb0f`，exe SHA256 `d8055fb8c7e7f5010d7439ec69be051554055dae55a265f8647bd7301c34161c`（与 handoff README Windows 基线一致，实测核对 MATCH）
- 结论速览：**两项 startup FAIL 均为 fixture contract stale**（fixture 的完成条件假设早于当前生产 READY 合同），未发现生产启动缺陷证据。
- 禁止项遵守：本轮未修改任何生产源码、未修改任何测试断言或 deadline；仅新增本报告与 `outputs/`（ignored）下的临时诊断脚本。

---

## 0. 环境前置修复（本轮新增发现，与两项 FAIL 定性相关）

本地 Windows 工作树由 `autocrlf=true` checkout，把
`assets/data/features/socketing_fixture_items.json` 写成 CRLF。
`scripts/identity/entity_registry.gd:36-40` 在 publish 前对 `source_hashes` 的 15 个
数据文件做**磁盘原字节 SHA256 校验**，任何 1 个不匹配即整体 publish 失败，
导致所有 `EntityRegistry.resolve` 返回 `{}`，连锁产生：

1. `game_data.gd:1899 push_error: Price candidate identity is unknown, conflicting or repeated`
2. `player_state.gd:3566 SCRIPT ERROR: Invalid access to 'magic_min'`
   （`ProfessionRules._base_growth_row` 因 registry 失败返回空/缺列字典）

即本地首跑在数据链阶段就崩溃，**先于**云端记录的断言失败点。修复方式：
`git -c core.autocrlf=false checkout -- <15 个 registry 源文件>`（命令级配置覆盖，
未持久化修改任何 git 配置、未修改任何文件内容语义），修复后 15/15 哈希匹配。
handoff README 第 6 节"设置 core.autocrlf=false 避免无意转换"正是针对此风险。
云端 Linux（LF 工作树）不受影响。验证：修复前 `HASH_MATCH=14/15`，修复后 `15/15`。

附带说明：`--import` 在 docs/review 证据目录内为 `.gd` 生成了一批 `.uid`
伴生 untracked 文件（301 个，全部 `?` 状态，0 个 tracked 变更）。保留未删，不入库。

## 1. initial_world_bootstrap_test

### 1.1 实测运行（本地，修复后）

- 命令：`tools/run_godot_tests.ps1 -TestPaths tests/initial_world_bootstrap_test.tscn -TimeoutSeconds 30`
- receipt：`outputs/test_logs/runner_results_adhoc_20261006_101444_392_9352.json`，`git_head=4e036083...`
- 结果：FAIL，`reason=missing_pass_marker;process_did_not_exit;early_script_error;non_zero_exit_code_-1;stderr_failures_1;engine_log_failures_1`
- stderr 全文（1 条）：
  `SCRIPT ERROR: Assertion failed: Bootstrap should not keep map transition open at: _run (res://tests/initial_world_bootstrap_test.gd:24)`
- 与云端 `cloud_birth_20261005` EVIDENCE_INDEX 记录的 fixed_candidate_repeats 两轮
  stderr（同断言、同位置、`stderr_failures_1;engine_log_failures_1`）**完全一致**。

### 1.2 断言内容与生产合同对照

- fixture（第 15-16 行）：`await process_frame` 两次后断言 transition 已关闭、
  loading overlay 不可见、runtime ground ready、玩家位于 home 锚点。
- 生产初始启动（`scripts/game_root.gd`）：
  - `INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC := 60000`（第 14 行）——生产正式有界等待；
  - 第 3387-3410 行：等待 `map transition 关闭` 且
    `WorldBootstrapCoordinator.Stage ∈ {READY, FAILED}`，READY 才释放
    `INPUT_LOCK_INITIAL_BOOTSTRAP`；
  - `game_root.gd:3438` 起 `_begin_map_transition` 走完整八阶段 pipeline。

### 1.3 实测生产 READY 时间线（临时诊断，outputs/，read-only）

- 诊断脚本：`outputs/diag_ready_timeline_20261006.gd/.tscn`（ignored，不入库），
  headless + 隔离 `APPDATA=.godot/runtime_appdata/diag_ready_20261006*`。
- 冷跑（首跑）：`bootstrap_dispatch` 在 4226.8ms 才开始
  （`hud_attach_and_ready` 占 3907ms，`InitialGameRootProfile`）；
  `stage=8(FINALIZE) at=6311ms`、`stage=9(READY)=transition_closed=input_enabled at=10889ms`。
- 热跑：`stage=8 at=6330ms`、`READY at=8371ms`。
- 生产自报 `[LOADING-TOTAL]`（热跑，transition pipeline total=4066ms）：
  COLLECT 335 / REQUEST 358 / WAIT_RESOURCES 506 / BUILD_MAP 507 / BUILD_COLLISION 510 /
  SPAWN_ACTORS 511（38 slices）/ FINALIZE 1616（内含 monster_prefetch 335、
  **ui_panels 2439**）；`prewarm_deadline_exceeded=false`、
  `catalog_icon_prewarm_complete=true`、render_warm headless 空（0 skills）。

### 1.4 定性

**fixture contract stale。**
"2 帧完成"是旧两帧启动时代的假设；当前生产 READY = coordinator READY +
transition 关闭 + input 释放，实测 8.4~10.9 秒（均含设计内的有界预热且未超预算）。
生产自身的 60 秒合同未被突破，无"生产不必要阻塞"证据
（`prewarm_deadline_exceeded=false`）。断言内容本身（transition 关闭、overlay 隐藏、
ground ready、home 锚点）与当前 READY 合同一致，需要更新的是**完成条件的等待方式**
（迁移到正式 READY 完成条件），不是断言语义、也不是放宽业务期限。

## 2. monster_summon_formal_birth_test

### 2.1 实测运行（本地，修复后）

- 命令：`tools/run_godot_tests.ps1 -TestPaths tests/monster_summon_formal_birth_test.tscn -TimeoutSeconds 30`
- receipt：`outputs/test_logs/runner_results_adhoc_20261006_101523_914_2628.json`，`git_head=4e036083...`
- 结果：FAIL，`stderr_failures_1;engine_log_failures_1`
- stderr 全文（1 条）：
  `SCRIPT ERROR: Assertion failed: summon_cap_birth must wait for READY input at: wait_for_formal_world (res://tests/helpers/formal_world_skill_fixture.gd:158)`
- 与云端 fixed_candidate_repeats 两轮 stderr **完全一致**。

### 2.2 deadline 与生产对照

- `tests/helpers/formal_world_skill_fixture.gd:146-158`：`wait_for_formal_world`
  的 `deadline_ms = now + 5000`，轮询 `current_map_id >= 0 && gameplay_input_is_enabled()`，
  超时后在 158 行断言失败。
- 实测生产 input enabled 最早时刻：热跑 8371ms / 冷跑 10889ms —— **均 > 5000ms**。
- 失败发生在任何发布/容量/召唤断言之前（云端 minimal_observed_reason 同结论）。

### 2.3 与同 helper PASS 场景的分化解释（2026-10-06 Pro 复审修正）

初版报告曾把 preflight/issuance 的 PASS 当作"READY 有时低于 5 秒"的证据。
Pro 复审指出该论据错误，本节已更正：`published_descriptor_preflight_test`（第 26-27 行）
与 `published_summon_issuance_test`（第 18-19 行）在调用 `wait_for_formal_world`
**之前**已各自等待最多 20 秒直到 `gameplay_input_is_enabled()`，因此它们的
PASS 证明的是"READY ≤ 20 秒（framework20seconds）"，**不能**证明初始 READY
有时低于 5 秒；该论据删除，最终 fixture-stale 定性不变。
定性依据改为独立的 READY 时间线实测（本文 1.3 与第 5.3 节）：生产 input
enabled 最早时刻实测 8163~10889ms（多轮冷/热），**恒大于** helper 的 5000ms
deadline，5 秒窗口必然不足；失败发生在任何出生/容量断言之前（云端
minimal_observed_reason 同结论）。

### 2.4 定性

**fixture contract stale。**
5 秒 initial READY 等待既非生产合同（生产合同为 60 秒有界等待、READY 才释放输入），
也不是当前生产启动时长的可靠上界。失败在出生闭包逻辑之前，本测试的
"published base 出生计划 + SummonQueue 一次资格"主体断言（40+ checks）
在两轮云端与本次本地运行中都**从未被执行**。

## 3. 结论与建议

- 结论：`initial_world_bootstrap_test` 与 `monster_summon_formal_birth_test` 的
  startup FAIL 均为 **fixture contract stale**；无生产 defect 证据，无 insufficient
  evidence 保留项（生产 60 秒合同、READY 时间线、预热预算均有实测数据）。
- 建议的修复方向已于 2026-10-06 按 Pro 复审授权执行（fixture migration，只改
  测试不改生产），结果见第 5 节。

## 4. 证据清单

- runner receipts：`outputs/test_logs/runner_results_adhoc_20261006_{100338_088_16476,101046_574_10624,101444_392_9352,101523_914_2628}.json`
- 诊断脚本与输出：`outputs/diag_ready_timeline_20261006.gd/.tscn`（stdin 摘录见本文 1.3/2.3）
- 云端对照：`docs/review/cloud_birth_20261005/EVIDENCE_INDEX.json` fixed_candidate 节、
  `docs/review/cloud_birth_20261005/README.md`、
  `docs/review/cloud_birth_20261005/PRO_AUDIT_REQUEST.md`（问题 5 与本审计直接对应）
- 原字节修复记录：本文第 0 节；受影响文件清单
  `assets/data/runtime/entity_registry_v1.json` `source_hashes` 的 15 个路径。

## 5. Fixture migration 结果（2026-10-06，Pro 复审授权：只改测试，不改生产）

### 5.1 修改文件（完整 diff 范围）

- 新增 `tests/helpers/formal_initial_ready.gd`：正式初始 READY 合同等待
  （四条件：service home runtime map 正确、`WorldBootstrapCoordinator.Stage.READY`、
  `_map_transition_in_progress == false`、`gameplay_input_is_enabled() == true`）；
  60 秒仅为生产 fail-safe ceiling（`INITIAL_WORLD_BOOTSTRAP_TIMEOUT_MSEC`），
  明确不是启动性能 PASS 门槛，超时仍 assert FAIL。
- `tests/helpers/formal_world_skill_fixture.gd`：`wait_for_formal_world` 的旧
  5 秒轮询替换为共享 helper 调用；原 assert 序列（mapped world / READY input /
  safe-zone context）逐条保留。`publish_targets()` 内 republication 自己的
  5 秒 deadline（第 50-57 行）为不同合同，**未触碰**。
- `tests/initial_world_bootstrap_test.gd`：旧"两个 process frame"假设替换为
  共享 helper 等待；其后全部业务断言保留。其中
  "Player input should become active after bootstrap"断言的观察点由
  "1 个 process 帧"修正为"跨越两个 `physics_frame` 边界"——`movement_input_active`
  的真实所有者是 `_physics_process`（player.gd:325），`physics_frame` 信号在
  物理步开始时发出，跨两个边界才是"一次已完成物理 tick 后观察"；断言文本与
  语义未变（原假设在 headless 下 process 帧率与物理 tick 解耦时永不满足）。
- 生产源码（game_root/coordinator/出生逻辑/资源流程/怪物数量/业务 deadline/
  正式玩法参数）：**零修改**。

### 5.2 逐场 run/source/receipt/exit（全部在同一迁移后源码上单项运行）

| 场景 | checks | 结果 | runner receipt（outputs/test_logs/） | exit |
|---|---|---|---|---|
| initial_world_bootstrap_test | 断言式 | PASS | runner_results_adhoc_20261006_104746_528_17212.json | 0 |
| monster_summon_formal_birth_test | 断言式 | PASS | runner_results_adhoc_20261006_104816_590_10660.json | 0 |
| published_descriptor_preflight_test | 11 | PASS | runner_results_adhoc_20261006_104851_826_14188.json | 0 |
| published_summon_issuance_test | 44 | PASS | runner_results_adhoc_20261006_104916_554_3952.json | 0 |
| published_world_birth_guard_test | 13 | PASS | runner_results_adhoc_20261006_104958_319_15192.json | 0 |
| published_monster_inputs_test | 7 | PASS | runner_results_adhoc_20261006_105020_961_17800.json | 0 |
| feature_birth_slot_identity_test | 11 | PASS | runner_results_adhoc_20261006_105038_310_1588.json | 0 |
| feature_world_capacity_bound_test | 15 | PASS | runner_results_adhoc_20261006_105100_694_10024.json | 0 |
| published_world_failure_recovery_test | 19 | PASS | runner_results_adhoc_20261006_105119_928_11528.json | 0 |
| published_environment_failure_recovery_test | 11 | PASS | runner_results_adhoc_20261006_105154_067_20472.json | 0 |
| published_queue_generation_takeover_test | 13 | PASS | runner_results_adhoc_20261006_105202_029_19420.json | 0 |
| feature_admission_release_test | 27 | PASS | runner_results_adhoc_20261006_105227_607_17932.json | 0 |
| combined_effect_lifecycle_test | 39 | PASS | runner_results_adhoc_20261006_105250_362_9352.json | 0 |
| feature_mixed_delivery_test | 380 | PASS | runner_results_adhoc_20261006_105339_030_8348.json | 0 |

- birth direct 11 场 checks 合计 = **210**，与 `cloud_birth_20261005`
  EVIDENCE_INDEX fixed_candidate 基准逐场一致；mixed = **380** 一致。
- 全部场景 `stderr_failures=0;engine_log_errors=0`，正式 runner 退出 0。
- 受测源码为同一迁移后工作树（测试文件 3 个 + 新 helper 1 个，生产零修改），
  commit SHA 见推送记录。

### 5.3 启动耗时记录（非 PASS 门槛；状态：OPEN / PRODUCT SLA MISSING）

诊断脚本 `outputs/diag_ready_timeline_20261006.gd/.tscn`（ignored），
headless + 隔离 APPDATA，观察 `_world_bootstrap_coordinator` stage 与 input enabled：

- 首次启动（环境修复后首跑）：`bootstrap_dispatch` 4226.8ms 开始
  （`hud_attach_and_ready` 3907ms 为主），READY = **10889ms**。
- 正式记录冷启动（新 userdata）：`bootstrap_dispatch` 551.8ms，READY = **8513ms**。
- 正式记录热启动（复用 userdata）：READY = **8163ms**。
- `[LOADING-TOTAL]` stage breakdown（transition pipeline，冷/热轮）：
  COLLECT 341/330、REQUEST 366/352、WAIT 516/498、BUILD_MAP 516/498、
  BUILD_COLLISION 520/501、SPAWN_ACTORS 521/502、FINALIZE 1623/1534
  （内含 monster_prefetch 341/330、ui_panels 2604/2376）；
  每轮 `prewarm_deadline_exceeded=false`、`catalog_icon_prewarm_complete=true`。
- 以上仅记录实际耗时；**启动性能状态保持 `OPEN / PRODUCT SLA MISSING`**，
  60 秒 ceiling 不是也不构成启动性能 PASS。

### 5.4 原 FAIL 与新结果对应

| 原 FAIL（云端 fixed-SHA 两轮 repeat） | 原因 | 迁移后 |
|---|---|---|
| initial_world_bootstrap_test exit 137：`Bootstrap should not keep map transition open`（bootstrap.gd:24） | 2 帧假设早于异步 READY（约 8.2~10.9s） | PASS（同断言集在 READY 后全部通过） |
| monster_summon_formal_birth_test exit 137：`summon_cap_birth must wait for READY input`（formal_world_skill_fixture.gd:158） | 5 秒 helper deadline 早于异步 READY | PASS（出生/容量/召唤断言首次真实执行并通过） |

原 FAIL 的原始证据保留于 `docs/review/cloud_birth_20261005/EVIDENCE_INDEX.json`
（fixed_candidate 节）与本文第 1/2 节，未改写、未删除。
