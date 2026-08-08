# HardCore Current Status

Updated against production HEAD: `ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c`
Branch: `codex/integration`
Updated: 2026-08-08
Purpose: where the project stands right now.

## Current HEAD

`ec057c52de4c99f59aa31a96dbd790e1fa8c6a7c`

## Current Stage

**CORE STABILITY FREEZE**（`FREEZE-G0.3 = CLOSED`）

## Confirmed Production Blockers

`confirmed_production_blockers = 0`

## New Must-Fix

`0`

## Known Unverified Production Regressions

- `known_unverified_production_regressions = 1`
- `HELLFIRE_CANONICAL_TARGET_REGRESSION = PENDING_VERIFICATION`
  - Repository call-path conflict is proven.
  - Runtime/player-visible effect has not yet been revalidated.
  - 该项不是已确认 production blocker，也尚未提升为 new must-fix。

## Closed Recent Bugs

- B030 = `CLOSED`（PassiveProcSkillEffect actor 平面）
- B038 = `CLOSED`（Skill Panel AssignmentHint 溢出）

## Test Infrastructure Debts

- B004 = `CONFIRMED_TEST_INFRA`
  - `production_touch_scroll_works=true`
  - `old_test_calls_disabled_path=true`
  - 旧测试调用了被 `STABLE_ID` 策略禁用的 `launcher._input` 路径。
- B037 = `CONFIRMED_TEST_INFRA`
  - `InventoryScroll` 存在于真实 HUD 树且触摸有效。
  - 旧测试只扫描 `MobileSafeRoot`，漏掉 HUD 根子节点。

## Runner Allowlist Gate Closure

- `RUNNER ALLOWLIST GATE = CLOSED`
- 关闭提交：`9a174d14015268e570bf687ddf3e14aad440f314`（`fix(test): harden runner allowlist contract`）
- public suites：23
- runner identity isolation：`PASS`
- `TestPaths`：`adhoc only`
- timeout hard range：`1..60`
- `monster_streaming_critical` direct suite remains available。
- `monster_streaming_critical` excluded from default critical while `HOLD`。
- formal suite smoke：`player_visual_contract_critical = PASS / 1_OF_1`
- `confirmed_runner_blockers = 0`
- registration guard remaining weakness：`NON_BLOCKING_TEST_INFRA_DEBT`

## Monster Streaming Historical Evidence

- apply-order 历史记录：20-run evidence 17 PASS / 3 FAIL。
- 当前状态：
  - `HOLD`
  - `NOT_NEXT_GATE`
  - `NOT_ACTIVE_MUST_FIX`
  - `20_RUN_NOT_AUTHORIZED`
  - `PRODUCTION_CHANGE_NOT_AUTHORIZED`
- 该状态不是 `CLOSED`；它只暂停执行，不否认历史现象。

## Environment Noise

- Orc Tomb headless dummy renderer shutdown：20/20 standalone PASS；批跑偶发关闭期 RID 噪声。

## Next Verification

- `NEXT_VERIFICATION = HELLFIRE_CANONICAL_TARGET_REGRESSION`
- `STATUS = NOT_STARTED`
- 这是 bug verification，不是 Freeze quality gate；当前不授权运行正式释放测试或修改生产代码。

## Pending Freeze Quality Gates

1. `NEXT_FREEZE_QUALITY_GATE = WORLD_ACTOR_SPAWN_PERFORMANCE` — `NOT_STARTED`
2. Final G1 audit — `NOT_STARTED`
3. Android device acceptance — `NOT_STARTED`

用户当前已暂停全部 Freeze 工作；上述 verification 与 quality gates 均未开始。

## Do Not Work On

- 未制作地图内容（338 等）
- 未来 MSE 功能
- B004/B037 生产代码（两项均已确认是测试基础设施问题）
- GameRoot 拆分
- 坐标重新设计
- Snapshot 重新设计
