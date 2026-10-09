# Passive contact source design

This is a read only source review of the current MAIN Enemy and spatial index.
The reviewed Enemy source SHA256 is
`121e33cdadcbc5ebc4abf7796952f2c47eb9bb13fc965d819f6898cd29ece102`.
No engine, test, fixture, or isolated candidate was changed.

## What a remote ordinary melee actor already does

The per physics owner path begins in `_physics_process_internal()` at
`scripts/enemy.gd:2802`. It advances the owner combat clock, processes death,
struck, status, regeneration, entrapment and pending releases before the
ordinary AI. It calls `_spatial_index_update()` at `:2860` on every live actor
tick. The Enemy-side projection cache first decides whether the indexed
position must be refreshed at `:3318-3328`; when it calls
`RuntimeCombatSpatialIndex.update_actor()`, that method first writes the
indexed absolute position at `runtime_combat_spatial_index.gd:136-156`, then
returns if the bucket is unchanged, otherwise moving the weak reference
between buckets and incrementing the membership revision. This is already a
useful cheap remote path, although the cache-match check still reads the
environment revision each tick.

`_hc_tick_melee()` starts at `enemy.gd:9231`. Before any full attack access it
does the following cheap work for a distant actor:

1. It returns for a committed action or unusable target (`:9234-9245`).
2. It computes one owner/target ground offset and scalar distance
   (`:9257-9258`).
3. It applies the dormant wake range (`:9259-9267`) and the attack-pose hold
   (`:9272-9277`).
4. It uses the ordinary source box predicate at `:9295-9302`. Ordinary melee
   uses `_source176_melee_reach_ok()` (`:8707-8714`), while named deliveries
   retain the circular `HCPolicy.START_GU` test.

For a remote ordinary target, `source176_in_zone` is false, so the actor does
not run `_hc_access()` or frontline geometry merely because it is far away.
It proceeds through observation, current indexed position, and the existing
autonomous movement loop. `_hc_refresh_observation()` is itself cadence gated
at `:9583-9639`; an unchanged identity before its next observation time returns
without another geometry admission. `_retarget_internal()` also keeps ordinary
targets between decision ticks (`:7817-7860`). These are the existing remote
gates that should be preserved.

The remote path still pays the ordinary physics owner work, combat clock,
status/regen/entrapment, spatial-index cache check, target offset projection,
observation identity checks, movement budget and collision path when a step is
active. A passive contact design cannot claim to remove those costs without
changing the physics or combat cadence contract.

## The real duplicated contact work

The best concrete duplicate is the same-frame ready-contact path:

- `_hc_tick_melee()` first calls `_hc_access(target)` in the ordinary contact
  branch at `enemy.gd:9304`.
- When it returns `CLEAR`, the branch immediately calls `_hc_try_start(target)`.
- `_hc_try_start()` begins at `:8981` and calls `_hc_access(hit_target)` again at
  `:8993` before `_try_reserve_source_body_action(false)` at `:8997`.

Those two access calls can repeat `spatial_index_position()`, target projection,
ordinary reach, hidden-target logic, world path choice and `_hc_frontline_at()`
for one synchronous actor callback. `_hc_frontline_at()` at `:8843-8870`
issues `query_enemy_nodes_segment_unsorted_into()` and then reads every
candidate's live `can_receive_damage()`, map, worldCollision and
`spatial_index_position()`. This is the only candidate here with a clear
same-call duplicate boundary. It is also bounded to already-legal contact;
it does not justify running a radar query for all remote actors.

The smallest source cut is an owner-local, synchronous `contact_clear` fact
created by the first ordinary contact check and consumed by `_hc_try_start()`
in the same call stack. The fact must carry the existing owner/target life,
target instance, map, generation, environment revision and the exact source
box endpoints. It expires before any callback, reserve, animation, signal,
position setter, or return. `_hc_try_start()` must re-run the old access path
after any such boundary. This is a duplicate-check elimination candidate,
not a frame cache and not a persistent contact membership.

## Where a passive radar could live

The existing central index is `RuntimeCombatSpatialIndex`. Enemy registration
is performed by `GameRoot` at `game_root.gd:5261-5274`, with absolute ground
position, combat radius, stable spawn order, Node identity and the existing
`spatial_index_position` provider. Actor position publication is owned by
`EnemyActor._spatial_index_update()` at `enemy.gd:3309-3339`; forced writes go
through `set_combat_position()` immediately below that method and must keep
the index transaction intact.

The index is an enemy broadphase, not a player/target contact service. Its
neighbor query at `runtime_combat_spatial_index.gd:469-560` returns live Nodes
in stable order after bucket collection and sorting. Segment queries at
`:278-337` are conservative broadphase candidates; the Enemy narrow phases
remain responsible for exact range, live state, world collision and frontline
semantics. The batch segment API at `:775-833` is explicitly synchronous and
limited to 32 segments; it is not a cross-frame contact cache.

For a passive contact radar, the least disruptive owner is therefore the
existing spatial index update transaction, with a new read-only contact
candidate query over the current indexed ground position. It can report only
candidate identities and current indexed positions. It must not invoke
`_hc_access()`, `can_receive_damage()`, world callbacks, signals, attack
submission, or target setters while maintaining the broadphase. The actor
still performs exact checks at its existing `_hc_tick_melee()` contact point.

An `Area2D` is a poor first cut. It adds one physics shape/monitoring path per
actor, callback ordering and enter/exit bookkeeping beside the spatial index,
and it would make contact membership depend on physics overlap timing rather
than the existing indexed ground transaction. It also cannot represent all
current attack ranges without separate shapes and does not naturally preserve
stable combat order or map/generation identity. It may be appropriate for a
separate gameplay sensor, but it is not the minimal source experiment here.

## Range and consumer boundaries

The radar envelope must not use an eight-neighbor or one-GU universal cap.
Ordinary source176 melee uses the existing L-infinity source box
`Source176Melee.HALF_EXTENT_GU` through `_source176_melee_reach_ok()`.
`_hc_access()` at `:8808-8841` already distinguishes that from named delivery
ranges. `attack_delivery_rule` is populated during Enemy setup at
`:1413-1559` and validated by the delivery-specific checks around
`:4187-4455`. Special melee, gas, mixed-cell, physical projectile, target
magic, area magic, self-detonation and guard-direct-projectile consumers have
different range metrics, world policies, delays and footprints. A passive
ordinary-contact radar must classify the delivery first and either use the
exact ordinary source box or decline to make a fastlane claim for the special
kind.

The complete ordinary consumer set is larger than attack admission:

- `_hc_tick_melee()` contact hold, pursuit step and post-movement arrival
  (`:9231-9460`)
- `_hc_step_can_end()` final exact access (`:9458-9475`)
- `_hc_try_start()` admission and reserve (`:8981-9084`)
- `_hc_settle()` lifecycle and actual damage (`:9086-9160`)
- `_retarget_internal()` target validity, safe-zone and disengagement
  (`:7817-7960`)
- `_hc_refresh_observation()` identity, hidden state, world visibility and
  last-known target point (`:9583-9660`)

The radar may help decide when to wake an actor's ordinary contact check, but
it cannot replace the live checks in those consumers. In particular, a target
can move, enter a safe zone, change combat life/generation, become queued for
deletion, become hidden, or change world collision between an indexed update
and the actor's admission callback.

## Minimal measurable cut

The first bounded experiment should have one of these two parts, in this
order:

1. **Same-call contact fact reuse.** Measure and remove only the duplicate
   `_hc_access()` call between `enemy.gd:9304` and `:8993`, with a typed
   owner/target identity witness and immediate invalidation before every
   callback or position writer. Keep a true-access fallback for unknown or
   overridden Enemy subclasses, modified environment providers, nonfinite
   projections and any re-entry.
2. **Index-backed ordinary contact candidate read.** Add one read-only index
   query at the existing `_spatial_index_update()` publication boundary, but
   consume it only after the old cheap distance/source-box filters pass. It
   should wake the actor's original `_hc_tick_melee()` contact branch; it must
   not pre-project all targets, run world collision early, or call attack
   admission from the index.

The first part is the executable bounded candidate because it has an exact
duplicate callsite and no new broadphase state. The second part is a later
candidate only if a source trace proves remote contact wakeups are a material
cost; current source alone does not prove that. Both need counters for old
access calls, radar/index candidates, exact access calls, fallback calls,
callbacks/re-entry, same-frame position/index publication, map/generation
changes, nonfinite projection, target deletion, safe-zone entry and special
delivery bypass. The expected failure behavior is the old path, with no
accepted attack, collision, damage, or target decision lost.

This design gives a precise source boundary for a contact radar without
claiming a performance gain. A passive index candidate can reduce wakeup
search only after the index has published the actual position, while exact
attack range and all live consumers remain owner-side and synchronous.

## Clocked contact entry and exit

The current source already has the required action clocks. `_attack_timer` is
advanced in `_physics_process_internal()` at `enemy.gd:2860-2865`, while the
logical committed action owns `_attack_action_active` and the owner combat
clock at `:1070-1088`. `_update_pending_attack()` at `:4254-4271` settles an
already committed delayed release. These clocks are independent from target
range and must not be restarted merely because a radar reports an enter or
exit.

The smallest clocked contact policy is therefore:

- **Moving first entry:** keep the existing offset/distance and ordinary source
  box filter in `_hc_tick_melee()` (`:9257-9302`). When a moving actor first
  crosses that exact box, run the existing live `_hc_access()` at the current
  actor callback and then `_hc_try_start()` at the existing admission point.
  The radar may provide the candidate wakeup, but it must not submit the
  attack or pre-run world/frontline checks.
- **Boundary exit:** when the current indexed position or the live target
  position no longer satisfies the exact source box, clear only the contact
  eligibility fact and resume the existing pursuit/observation path. Do not
  reset `_attack_timer`, `_attack_action_active`, pending release state, or
  the combat clock. A range exit during a committed action is observed by
  later targeting, while the committed action and damage release complete.
- **Obstacle change:** a radar range hit is insufficient when the path or
  frontline state changes. `_hc_access()` owns `_hc_world_between()` or the
  fresh `_world_attack_path_is_clear()` route and `_hc_frontline_at()` owns the
  live blocker query (`:8808-8870`). Recheck these only at the existing entry
  or actual attack node. A changed obstacle invalidates the contact fact and
  returns to the old pursuit route; it must not restart the attack clock.
- **Hidden or controlled target:** the existing target-usable, safe-zone,
  stealth and control/charm checks remain required. A radar identity alone
  cannot make an invisible, protected, dead, transitioning or otherwise
  unusable target attackable.

The ordinary contact branch currently performs a clear access test and then
invokes `_hc_try_start()` (`:9304-9314`); `_hc_try_start()` repeats access at
`:8993`. That same-callback repeat is the concrete removable work for a first
implementation. The radar should not be used to remove the second check until
the identity witness proves that no position setter, callback, obstacle
revision, target life/generation or re-entry occurred. A synchronous access
fact can be consumed once and then discarded; it cannot be a cooldown-period
cache.

Special and remote attacks stay outside the ordinary contact fastlane. The
delivery rule and range/metric validation at `:4187-4455`, plus the named
delivery branch at `:9348-9350`, cover different target-cell, projectile,
magic, area and delayed-hit policies. They may have a larger or differently
shaped range and cannot inherit the ordinary source box or a universal
eight-neighbor sensor. The radar can report a generic candidate for them only
after a separate per-delivery contract is proven; otherwise the current
special path remains the fallback.

The minimum boundary tests for this policy are: a moving actor entering the
ordinary box once; leaving before admission; entering again without a timer
reset; an obstacle/frontline change between candidate and access; a hidden or
controlled target; a special delivery with a nonordinary range; a committed
attack that crosses the range boundary; and a pending delayed release whose
target moves after commitment. Each test must compare actual attack starts,
cooldown/action-clock values, release settlement, HP effects, and pursuit
continuation. No test should treat a radar enter/exit event as permission to
cancel or replay an already committed action.
