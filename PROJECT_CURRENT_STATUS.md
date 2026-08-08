# HardCore Current Status

Updated against production HEAD: `13821799fced2fee0d50c27d89bba3149464077f`
Branch: `codex/integration`
Updated: 2026-08-08
Purpose: where the project stands right now.

## Current HEAD

`13821799fced2fee0d50c27d89bba3149464077f`

## Current Stage

**CORE STABILITY FREEZE**（`FREEZE-G0.3 = CLOSED`）

## Active Wizard Line Presentation Alignment

- `WIZARD-LINE-PRESENTATION-ALIGNMENT = DEVICE_ACCEPTANCE_PENDING`
- Professional implementation commit: `14bb52f5`（merged into integration as `348b6809`）
- Formal design: Hellfire / Laser use target-aligned continuous canonical geometry; Presentation consumes the same release snapshot and must not quantize Gameplay to character or source-art directions.
- Automated verification:
  - focused arbitrary-angle alignment: `PASS`（Hellfire 126 samples + Laser 126 samples）
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
  - related caster visual tests: `PASS / 4_OF_4`
  - suite registration guard: `PASS`
- Single authorized default Critical run: every completed entry before the outer 900-second command cutoff passed, including `wizard_line_geometry_critical`; no final runner JSON / `TEST_SUMMARY` was produced, so this is `PARTIAL`, not a formal full-Critical PASS. Do not rerun automatically.
- Gameplay origin / axis / length / width, lock-on, target selection, damage and Geometry Debug Band were not modified.
- Final closure requires a newly exported Debug APK and device visual acceptance.

## Confirmed Production Blockers

`confirmed_production_blockers = 0`

## New Must-Fix

`0`

## Hellfire Damage Regression Fix

- `known_unverified_production_regressions = 0`
- `HELLFIRE_CANONICAL_TARGET_REGRESSION = FIX_IMPLEMENTED`
- User-visible symptom confirmed: Hellfire animation and geometry released, but no target received damage.
- Root cause: the canonical target selector interpreted production `maximum_targets = 0` as an empty target set before applying the explicit `target_limit_policy = all_intersecting_effect_cells` contract.
- Fix commit: `13821799fced2fee0d50c27d89bba3149464077f` (`fix(skills): restore hellfire line damage`).
- Automated verification:
  - production-effect regression reproduced before fix and passed after fix: `PASS / 1_OF_1`
  - wizard canonical/runtime/lock integration: `PASS / 3_OF_3`
  - `wizard_line_geometry_critical`: `PASS / 3_OF_3`
- `HELLFIRE_DAMAGE_DEVICE_ACCEPTANCE = PENDING`

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

- `NEXT_VERIFICATION = WIZARD_SKILL_DEVICE_ACCEPTANCE`
- `STATUS = READY_FOR_NEW_APK_DEVICE_ACCEPTANCE`
- Verify both the Wizard Line presentation alignment and restored Hellfire damage with the newly exported Debug APK.

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
