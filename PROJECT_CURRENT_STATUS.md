# HardCore Current Status

Generated from HEAD: `7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`
Branch: `codex/integration`
Generated: 2026-08-08
Purpose: where the project stands right now.

## Current HEAD

`7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`

## Current Stage

**CORE STABILITY FREEZE**（FREEZE-P0 系列完成；G0 系列进行中）

## Confirmed Production Blockers

`0`

## Closed Recent Bugs

- B030（PassiveProcSkillEffect actor 平面）
- B038（Skill Panel AssignmentHint 溢出）

## Test Infrastructure Debts

- B004（character select touch scroll 测试走禁用路径）
- B037（HUD 触摸滚动测试忽略懒加载/扫描根）

## Known Race

- Monster Streaming apply-order：20-run evidence 17 PASS / 3 FAIL；Pending final freeze severity decision。

## Environment Noise

- Orc Tomb headless dummy renderer shutdown：20/20 standalone PASS；批跑偶发关闭期 RID 噪声。

## Pending Freeze Gates

1. Monster Streaming race final decision
2. Runner allowlist audit
3. World Actor Spawn performance measurement
4. Final G1 audit
5. Android device acceptance

## Do Not Work On

- 未制作地图内容（338 等）
- 未来 MSE 功能
- B004/B037 生产代码
- GameRoot 拆分
- 坐标重新设计
- Snapshot 重新设计
