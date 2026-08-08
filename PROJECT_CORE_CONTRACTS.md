# HardCore Core Contracts

Generated from HEAD: `7e3d5fde42e5aeedf422a5eb1d54905e12649ec0`
Branch: `codex/integration`
Generated: 2026-08-08
Purpose: frozen core rules. Only core rules, no history.

## Skill Runtime

```text
SkillRuntimeRouter → Canonical Skill Plan → Gameplay → CasterSkillRuntime → SkillExecutionResult
```

禁止第二个 Planner；旧 Chinese-name 路由与 legacy skill API 已删除。

## Wizard Line Geometry / Presentation

- Hellfire: `5 x 1 GU`; Laser: `8 x 1 GU` (or the same snapshot's clipped `actual_length`).
- Direction source: the current valid locked target, frozen into the canonical release snapshot.
- Gameplay line geometry is continuous/arbitrary-angle and must never be quantized to the character's 8-direction animation or a 16-direction presentation lookup.
- Presentation must consume the same canonical release origin, projected axis, actual length and centerline. A 16-direction source sequence may select artwork only; its measured visible source axis must be continuously transformed onto the canonical projected axis.
- Character animation may remain 8-direction. Global lock-on, eligibility, damage, target selection and the semi-transparent gameplay debug band are unchanged by this presentation contract.
- Hellfire production effects use `maximum_targets = 0` together with `target_limit_policy = all_intersecting_effect_cells`; for a canonical continuous Wizard line this explicit policy takes precedence and means every hostile footprint intersecting the release snapshot is selected. A bare `maximum_targets = 0` without that policy still means no targets.

## Snapshot

- Schema V2；消费端仅 `STRICT_V2`；`runtime_map_id` 为 typed int；absolute 上下文必须携带 `runtime_map_absolute_ground_gu`。

## Coordinate

- POSITION = map-global Ground GU；DELTA/DIRECTION = Ground delta；禁止 mapped world 的 identity/delta 回退。

## SpatialIndex

- 键 = `runtime_map_id` + map-global Ground GU 桶；绝对坐标合同。

## Projectile

- BroadPhase 候选 → Snapshot exact 命中；禁止漏判。

## GroundEffect

- Manager 调度 → 共享 SpatialIndex → exact 命中；禁止 group 扫描。

## FireWall

- Controller 拥有伤害；`GroundSkillVisualCell` 纯视觉；单查询/单 tick 判定。

## Monster Streaming

- 一个全局 StreamingCoordinator poll（`poll_once`）；`MonsterVisual` 不得 per-instance 全局 poll。
- apply-order 历史证据保留：20-run 为 17 PASS / 3 FAIL。
- 当前状态：Monster Streaming = `HOLD`；不是 active must-fix，不自动启动 20-run。除非更晚的正式状态明确重新激活，否则不得为此修改生产代码。

## Map

- Reference data ≠ playable map；正式链路：
  `MSE → Build Candidate → Validate → Publish → Release Registry → formal playable`
- Registry：`assets/data/runtime/map_editor/map_runtime_release_registry.json`；`implemented_playable` 才可玩。

## Map Build / Publish

- **Build ≠ Publish**：Build 产出候选（`outputs/map_runtime_candidates/`），Publish 才授予 playability；Publish 是 runtime+registry 事务，失败回滚。

## Player Visual

- actor composite 单平面 z=0；PassiveProcSkillEffect 不得逃出该平面（B030 已关闭）。

## UI

- AssignmentHint：word-smart autowrap、宽度受父槽位约束、禁止 clip 掩盖（B038 已关闭）。
- Inventory：懒加载面板（`_ensure_inventory_panel`），打开后 InventoryScroll 才存在。
- 触摸滚动：共享 `TouchScrollSupport` 单例（`ui.touch_content_scroll.v1`）；场景 `_input` 在 STABLE_ID 策略下委托给单例。

## Testing

- 普通测试单项 timeout=30s；明确重测试最多 60s；禁止 1800。
- Critical 最终回归正常 = 跑 1 次即可（用户指示）；已知 flake 专项重复 10~20 次记录比例，不得用放大 timeout 掩盖。
