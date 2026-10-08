# Hot-path redesign options — ordinary melee stock107

日期：2026-10-09
基线：HardCore stock107，Enemy source hash `22EB3A376540759219F7159958CAB51ED80884B27444B4D22CB2B76E45E15F3E`，commit `edae6fdef6a6551a951fab1ea8c6ade43359d603`。
证据：`outputs/crowd_native_profile_20261009/PROFILE_ANALYSIS.json`、`PROFILE_COVERAGE.json`、stock Enemy 源码、Pro Round4/Round5。
范围：只评估 ordinary melee 连续串行热点；不改玩法，不减少 actor/tick/collision/effect/diagnostic count。

## 结论

现有证据不支持单个 guard merge、local pool、projection cache 或每 helper 一个 context 达到 50%。唯一具备较大覆盖形态的候选，是把普通近战一次 movement quantum 内的连续纯计算压成一次 typed/native segment，再在原有 effect boundary 回到 host。真实可移植覆盖和收益仍是 `UNKNOWN`，必须包含 packing、binding、writeback、失效和 re-read 的 ABI_SHAM 对照后才能判断。

PROFILE 的 disjoint self subtotal 可以相加作成本上界参考：`control_state` self 274.751ms，`geometry_candidates_space` self 266.070ms，`diagnostic_budget` self 479.659ms。它们不能直接相加成可移植收益：分类之间存在边界和调用重叠，unknown 区域也不能归入候选；任何 `_hc_tick_melee`、`_advance_autonomous_step_internal`、`_move_with_spatial_rules` 的 inclusive time 更不能相加。

## 方案 A：ordinary melee serial quantum（首选）

### 代码入口和边界

首个量子覆盖 comparison stock Enemy 的：

- `_hc_tick_melee`（约 9174 起；普通分支约 9242–9402）；
- `_begin_autonomous_step_without_cadence`（约 1847 起）；
- `_hc_neighbor_internal`（约 9935 起）；
- `_advance_autonomous_step_internal`（约 2337 起）；
- `_move_with_spatial_rules`（约 3665 起，只取 native move 前的纯计算，并把实际移动及其后续保留在 host）。

入口应放在 ordinary attack admission 的前置资格、target identity/life 和 current self ground 已经同步证明之后。一个 segment 内顺序保持现有代码：neighbor/flank/blocked 选择、step 预算和方向、screen-delta、预测位置、movement preflight。到真实 native move 前停止；host 执行原有 native move、slide/rollback、index publish、safe-zone/environment guard 后，以最终真实位置继续 `_hc_step_can_end`、engagement 和攻击资格。

不把 `_retarget_internal`、`_hc_refresh_observation`、`_hc_try_start`、HP、承诺伤害、信号或 cooldown owner 移进首版。它们分别含 target grid/observation 外部查询或 combat effect boundary。

### typed input/output

入口一次组装固定 typed input：

```text
actor_ref, target_ref
actor_life_epoch, target_life_epoch
actor_position, actor_ground
known_target_ground, target_ground_valid
movement_budget, speed_scalar
ordinary_classification, control_state, step_state
spatial_index_revision, environment_revision
```

`known_target_ground` 保持 last-known 语义；self ground 必须是当前同步读取值。距离和结束条件继续使用原 `_ground_delta_gu_between_screen_positions` 的 screen-delta float 运算顺序，不能改为两个 absolute ground 相减。不得持久化第二份 HP、action clock、cooldown、pending attack 或 target state。

typed output 只返回：

```text
step_result, chosen_neighbor_ref, chosen_direction
movement_budget_consumed, predicted_position, native_move_required
step_end_reason
actor_life_epoch_observed, target_life_epoch_observed
spatial_index_revision_observed
```

在任一 callback、native move、signal 或位置 setter 前先写回并使 segment 失效。native move 返回后必须重新读取实际 position、self ground、必要的 target ground、environment/safe-zone、target/life identity；不能继续使用失效前 projection/classification。

### 外部同步 effect boundary

下列项目保持 host synchronous yield：target grid、observation、budget/cadence、`set_combat_position`、`_move_with_spatial_rules` 的实际 move/rollback/index/environment 操作、attack admission/HP/signal、Callable/override/unknown provider。callback 返回后重新检查 actor/target life 和相关 revision，必须支持同一 actor 同一 tick 继续执行。

### 规模和风险

profile 的相关 self 成本为：`_hc_tick_melee` 53.175ms（inclusive 2174.455ms）、`_advance_autonomous_step_internal` 40.393ms（inclusive 1129.117ms）、`_move_with_spatial_rules` 33.500ms（inclusive 544.675ms）、`_hc_neighbor_internal` 6.284ms（inclusive 487.255ms）。这些 inclusive 数值不能求和。该方案是当前唯一可能覆盖多个连续高频段的候选，但真实覆盖下限和 50% 可达性都必须标为 `UNKNOWN`，先做 LOCAL/ABI_SHAM 同轨迹对照。

## 方案 B：quantum 内 typed spatial candidate transaction

### 适用入口

作为方案 A 的内部阶段，处理 `_hc_neighbor_internal`、`_hc_motion_candidates`（约 10301 起）以及 `_hc_motion_clear_internal` 前的候选纯计算。现有热点反复访问 `spatial_index_position`、projection cache match、ground/screen projection、identity/map/envelope filter 和 clearance/world collision。

transaction 必须保持原筛选次序：先 actor identity、map、self/target skip、旧 envelope；通过后才批量取得候选当前位置和必要稳定字段，再执行 live/eligibility/world collision/exact crossed。不能为了减少 callback 预先为全部候选取 live、radius 或 world collision。

返回 view 必须带 revision 和 life owner：

```text
candidate_ref, candidate_life_epoch, candidate_spatial_revision
candidate_screen_position, candidate_ground_if_already_required
candidate_flags, query_spatial_revision
```

`_spatial_index_update`（约 3261 起）或 `set_combat_position`（约 3313 起）一旦发生就废弃整个 view；callback、位置 setter、native move 后不得复用。它不是 frame cache，不能跨 actor/tick 复用，也不能在 unknown/override provider 上使用。

### 预期边界

`_hc_motion_candidates` self 约 39.757ms，单独不足以支持 50%；候选 transaction 的意义是避免每个 tiny helper 各自跨 VM，并作为方案 A 内部的一次 typed binding。每个 query 都做一次 C++/GDScript yield 会把 binding 成本重新放大，预期可能劣于现状，不能作为独立方案验收。

## 方案 C：RuntimeDiagnostics 等价批量记录（只作测量专项）

`main/scripts/runtime_diagnostics.gd` 的正式边界是：`performance_detail_enabled` 约 360–365，`_ensure_performance_window` 368–375，`increment_performance_counter` 378–385，`timing_start` 642–645，`timing_now` 648–651，`timing_elapsed_usec` 654–657，`record_timing_usec` 660–666，`begin_timed_segment` 672–678，`end_timed_segment` 681–690。

full mode 每次记录会重复执行 gate、StringName 到 String、Dictionary lookup/write。可以研究同 tick、同 window、同序列的 typed event buffer，但必须保留每次调用的计数和时序语义：

```text
diagnostic_window_revision, event_kind, field_id, sequence
call_delta, duration_usec, slow_threshold_observed
```

gate 仍在逻辑调用点生效；window reset、device mode 或 enable 状态改变时立即 flush；`begin_timed_segment` 的 start timestamp 和 `end_timed_segment` 的 end timestamp 仍在原边界采集；slow-event threshold 仍按原调用逐次判断。StringName 固定 field id 只允许在稳定映射成功时使用，未知字段回退原 Dictionary 路径。

flush 成本必须计入同一受测 CPU 预算，并与 stock 在相同 full diagnostics 配置下比较。不能把 flush 放到受测区外，也不能以 FrameOnly 替代 Full。该方案最多减少观测污染，不能单独宣称 50% gameplay 优化，更不能用 observer green 替代生产收益。

## 建议的实现顺序和验收

1. 只实现方案 A 的 bounded ordinary quantum，先做 LOCAL 与 ABI_SHAM；ABI_SHAM 必须含真实 packing、binding、writeback、失效和 native move 前后 re-read。
2. 轨迹保持 stock：相同 actor、tick、collision、effect、attack admission、diagnostic counts；保留 screen-delta float 顺序、last-known/actual target 区分和未知/override 回退。
3. 只有 ABI_SHAM 在同一 full diagnostics、同一 source hash 和同一负载下证明有足够余量，才接入方案 B。
4. 方案 C 单独记录为 measurement hygiene 专项；其 flush 与字符串/字典成本不得移出计时范围。
5. 所有报告按 disjoint self cost 和实际 binding/flush 成本报告；禁止用 inclusive totals 求和，禁止以减少 actors、频率、碰撞、effect 或 diagnostics count 制造收益。

当前结论：方案 A 是唯一值得继续的较大变更；可兑现覆盖、50% 下限和最终收益均 `UNKNOWN`，须以真实 ABI_SHAM 和行为等价证据决定。

## Round6 source-cut: `_move_with_spatial_rules` and provider boundary

### Exact stock topology

`comparison/scripts/enemy.gd:_move_with_spatial_rules` lines `3665–3772` is not a numerical helper. It crosses several authoritative effect domains in one serial call:

1. directional sweep recovery: `move_and_collide(Vector2.ZERO, ...)` at `3671`;
2. engine native movement: `move_and_collide(velocity * get_physics_process_delta_time(), ...)` at `3681` or `move_and_slide()` at `3683`;
3. direction guard and possible `set_combat_position` rollback at `3684–3688`;
4. publication to `RuntimeCombatSpatialIndex` at `_spatial_index_update()` `3691`;
5. actual displacement derivation and performance counters `3692–3702`;
6. entrapment provider query and rollback `3703–3722`;
7. safe-zone query and rollback `3723–3728`;
8. environment guard timer and `WorldSpatialRulesScript.environment_blocks_actor_screen_px` at `3729–3772`, including possible final rollback.

`_spatial_index_update` lines `3261–3283` is an ownership publication, not a cache-only helper. It checks map/id and projection identity, projects current `global_position`, calls `combat_spatial_index.update_actor`, then records map, zone generation, environment revision and projection. `set_combat_position` lines `3313–3330` writes `global_position` and immediately publishes the index. Any native segment that writes position must preserve this transaction and cannot defer publication until after another actor can query the index.

`WorldSpatialRulesScript.environment_blocks_actor_screen_px` lines `481–523` is an external provider boundary. It first tests `is_environment_actor_blocked`; otherwise it calls the point provider and up to `ACTOR_FOOTPRINT_SEGMENTS` point samples, recording each diagnostic. The provider may be absent, may change behavior, and is a formal synchronous query. It cannot be replaced by a numerical kernel without moving the provider implementation and its ownership contract as well.

`GroundUnitSpace` conversions are pure and preserveable, but operation order remains part of the contract: `screen_delta_px_to_ground_delta_gu` lines `65–71`, `actual_ground_motion_gu_from_screen_positions` `144–150`, and the original screen-delta ordering used by the direction guard. These are portable only when their input positions are the exact positions at the corresponding effect boundary.

### Host effects versus portable typed work

**Host/effect side (must remain synchronous host code in the first cut):**

- both `move_and_collide`/`move_and_slide` calls and `KinematicCollision2D` ownership;
- any `set_combat_position`, rollback, or position setter;
- `_spatial_index_update` and `combat_spatial_index.update_actor` publication;
- `_entrapment_controller.movement_candidate_blocked` and its mutable state;
- `WorldSpatialRulesScript.environment_blocks_actor_screen_px` provider dispatch, including fallback sample count;
- safe-zone membership if the zone source can change during the call;
- all RuntimeDiagnostics counter/timer calls and final actual-motion recording;
- signals, callbacks, overrides, unknown providers, and attack/HP effects.

**Portable typed numerical/provider work:**

- derive `intended_ground` from the exact `velocity` once;
- direction-guard predicate using the original `GroundUnitSpace.screen_delta_px_to_ground_delta_gu` ordering;
- compute actual motion only after host returns the final `global_position`;
- pure safe-zone geometry if a typed, revision-owned snapshot was already obtained before the segment;
- candidate envelope/index broadphase after old identity/map/envelope filters;
- environment provider preflight only if the provider exposes a typed revision and a batch API whose ownership is stable for the entire call.

This separation means that moving the whole `_move_with_spatial_rules` body “inside native” is not a bounded numerical port. It would require native ownership of the Godot body movement, collision result, rollback setters, spatial-index transaction, entrapment controller and provider dispatch. A C++ shell that calls back to GDScript for each of those queries is worse than the current path and is explicitly rejected.

### Minimal executable-first candidate: one provider preflight/postflight transaction

The bounded candidate should be a single typed transaction around the existing engine move, not a native replacement for the move:

```text
HostPreflightInput {
    actor_ref, actor_life_epoch, runtime_map_id, zone_generation,
    position_before_move, velocity, intended_ground,
    movement_step_active, collision_mode, safe_zone_revision,
    environment_provider_ref, environment_provider_revision,
    spatial_index_revision
}

HostPreflightOutput {
    allow_engine_move, directional_sweep_required,
    environment_preflight_status, safe_snapshot_revision
}

HostPostflightInput {
    position_before_move, actual_position_after_engine_move,
    directional_collision_ref, movement_step_active,
    actor_life_epoch, safe_snapshot_revision
}

HostPostflightOutput {
    direction_guard_rollback, entrapment_rollback,
    safe_zone_rollback, environment_rollback,
    final_position, final_ground_motion,
    invalidate_step_and_republish
}
```

The implementation order must remain:

1. host captures preflight fields and proves actor/provider identity;
2. one provider batch call, only after the existing old filters/timers say the guard is due;
3. host performs the actual engine movement;
4. host immediately publishes the spatial index for the actual position;
5. host runs direction guard, entrapment, safe-zone and environment postflight in the same stock order;
6. every rollback goes through `set_combat_position`, which republishes immediately;
7. after every callback/provider return, re-read actor life, target life where relevant, map/zone/environment revision; abort the remaining typed continuation on mismatch.

There must be one transaction boundary per actual movement segment, not one yield per getter. The preflight must not eagerly query environment or target data when the old timer/position filters would return before that query. The postflight must use the actual final body position, never a predicted position or frame cache. If the provider has no typed revision and batch method, this path falls back to the original GDScript implementation.

### Can moving the whole move reduce the retained R≈200ms?

Not established. The profile fact available here is that roughly 7300 movement calls cross a path where the measured native/diagnostic ABI reports about 264 bytes per yield and approximately 130ms across 16023 calls. That proves crossing/packing is material, but it does not prove that moving the whole function saves the retained R≈200ms: the engine move, rollback branches, index publication, provider calls and diagnostics still occur, and their effect boundaries may dominate. A speed claim requires LOCAL versus ABI_SHAM with the actual preflight/postflight packing and flush cost included.

The candidate can reduce repeated boundary crossings only if it batches the provider inputs and outputs once per movement segment. It must not claim savings by removing `_spatial_index_update`, environment checks, entrapment checks, rollback, collision publication, or diagnostics. A numerical-only kernel that still performs those operations through one GDScript callback each cannot meet the target. Conversely, putting the entire move body into native without moving the formal provider/engine ownership is not executable within the current contract.

### Retarget validity is an earlier host gate

Before `_retarget_internal` reaches the full scan, stock lines `7771–7837` perform observation/damage handling, target validity/live/safe/disengage checks, target release and pending-attack cancellation, then cadence gates. The full scan begins only after those gates, with target-grid setup around `7868+`. Any candidate target/provider batching must preserve this order: no target grid, projection, LOS or environment query may be moved before current-target validity and cadence decisions. The current-target validity checks can be represented as a small typed input only after host has evaluated `_target_candidate_is_live`, `_point_inside_safe_zone`, and `_target_should_disengage`; the release side effects stay host-owned.

### Scope decision

The first executable follow-up should be the one-provider preflight/postflight ABI_SHAM around `_move_with_spatial_rules`, with the actual engine move and all publication/rollback/effect boundaries still host-owned. It is materially larger than a numerical-only leaf but bounded enough to measure and revert. Its coverage and speed remain `UNKNOWN`; no 50% claim is justified from current self or crossing data. If the provider cannot offer stable typed ownership and a batch query, stop at the existing host path rather than adding per-getter native yields.
