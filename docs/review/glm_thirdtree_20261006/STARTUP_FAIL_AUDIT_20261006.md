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

### 2.3 与同 helper PASS 场景的分化解释

云端 birth direct 轮（fixed SHA 67aaa55f）中 `published_descriptor_preflight_test`
（11 checks）与 `published_summon_issuance_test`（44 checks）使用**同一个**
`wait_for_formal_world` 且 PASS；`monster_summon_formal_birth_test` 在 startup 轮
（冷启动/不同编排）两轮 FAIL。结合本地热/冷 8.4~10.9 秒的波动：
READY 时刻在 5 秒窗口边缘附近受资源冷热与编排影响，5 秒不是当前生产的确定性
完成边界——同一 helper 出现"有的场景过、有的场景不过"正是窗口不足的表现，
不是某个场景特有的生产缺陷。

### 2.4 定性

**fixture contract stale。**
5 秒 initial READY 等待既非生产合同（生产合同为 60 秒有界等待、READY 才释放输入），
也不是当前生产启动时长的可靠上界。失败在出生闭包逻辑之前，本测试的
"published base 出生计划 + SummonQueue 一次资格"主体断言（40+ checks）
在两轮云端与本次本地运行中都**从未被执行**。

## 3. 结论与建议（不执行）

- 结论：`initial_world_bootstrap_test` 与 `monster_summon_formal_birth_test` 的
  startup FAIL 均为 **fixture contract stale**；无生产 defect 证据，无 insufficient
  evidence 保留项（生产 60 秒合同、READY 时间线、预热预算均有实测数据）。
- 建议的后续修复方向（需另立施工任务、按 RED→GREEN 走）：
  1. 两个 fixture 的完成条件统一迁移到正式 READY 合同：
     `current_map_id == service_runtime_map_id(0)` 且
     `WorldBootstrapCoordinator.Stage.READY` 且 `_map_transition_in_progress == false`
     且 `gameplay_input_is_enabled()`，等待上限对齐生产合同（60 秒），
     并保留超时即 FAIL 的门禁属性；
  2. 不删减任一现有断言；不缩短、不放宽任何业务期限；
  3. fixture 修改后，两个场景的 PASS 必须与 `cloud_birth_20261005` 的
     birth direct 11 场景/210 checks、mixed 380 checks 在同一 fixed SHA 下重新闭环，
     原 FAIL 证据保留。

## 4. 证据清单

- runner receipts：`outputs/test_logs/runner_results_adhoc_20261006_{100338_088_16476,101046_574_10624,101444_392_9352,101523_914_2628}.json`
- 诊断脚本与输出：`outputs/diag_ready_timeline_20261006.gd/.tscn`（stdin 摘录见本文 1.3/2.3）
- 云端对照：`docs/review/cloud_birth_20261005/EVIDENCE_INDEX.json` fixed_candidate 节、
  `docs/review/cloud_birth_20261005/README.md`、
  `docs/review/cloud_birth_20261005/PRO_AUDIT_REQUEST.md`（问题 5 与本审计直接对应）
- 原字节修复记录：本文第 0 节；受影响文件清单
  `assets/data/runtime/entity_registry_v1.json` `source_hashes` 的 15 个路径。
