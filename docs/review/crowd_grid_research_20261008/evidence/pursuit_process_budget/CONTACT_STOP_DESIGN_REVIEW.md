# Contact stop / steel ball pursuit design review

Date: 2026-10-09

MAIN `scripts/enemy.gd` SHA256: `121E33CDADCBC5EBC4ABF7796952F2C47EB9BB13FC965D819F6898CD29ECE102`

Retained fixed107 raw JSON `outputs/crowd_formal_grid_comparison_20261008/v107_final_01.json` SHA256: `A899249721206FD139CCA61090F42CEBED8738C089570D5240459A08FFBBE0E7`

Scope: read-only source review of current MAIN EnemyActor and retained fixed107/diagnostic evidence. No engine run, fixture run, or production edit was performed.

## Judgment

The proposed rule—move periodically toward the player, stop immediately on body contact, let unobstructed front actors continue, and reduce AI work for actors stopped by contact—can reduce **post-contact AI replanning** if it is implemented as an actor-local state transition. It cannot remove the physics collision/body detection needed to know that contact occurred. It also cannot skip the existing spatial-index update or exact attack/contact checks after movement. The current source already has most of the safe seams: one directional sweep, collision classification, rollback on blocked motion, staggered retarget cadence, background wake timers, failed-cell cooldown, and a cached neighbor-separation query. A new global “front row” pass or synchronized cohort wake would duplicate those authorities and risk more work.

This review finds no evidence that the proposed rule produces a 50% reduction. Existing fixed107 evidence shows the relevant work is mixed: `outputs/crowd_formal_grid_comparison_20261008/v107_final_01.json` records `enemy_motion_body_checks=27395`, `enemy_motion_clear_calls=9063`, `enemy_motion_clear_usec=244218`, `enemy_neighbor_calls=838`, `enemy_neighbor_usec=272144`, `enemy_retarget_usec=301095`, and `move_and_slide_usec=202304`. These counters are nested or overlapping categories; they must not be added together or converted into a claimed saving.

## Existing movement and collision seam

- The normal actor tick is `scripts/enemy.gd:2802-2860`. It advances the single combat clock, handles death/struck slices, updates the spatial index, then runs movement/AI. A contact-stop state must preserve this clock, HP/status updates, and index publication.
- Pursuit movement is `_advance_autonomous_step_internal` at `scripts/enemy.gd:2351-2510`. It already exits early when the selected target becomes attack-ready (`:2329-2341`), checks one selected target for continuous pursuit (`:2314-2327`), performs the existing movement step, then classifies blocked motion (`:2440-2499`).
- `_move_with_spatial_rules` at `scripts/enemy.gd:3713-3819` performs the physics-owned zero-distance separation, then one directional `move_and_collide` for an active step or `move_and_slide` otherwise (`:3718-3734`). It updates the spatial index immediately after movement (`:3736`) and applies entrapment, safe-zone, and environment rollback guards (`:3751-3819`). Contact cannot bypass these checks.
- Collision count and collision access remain available through `_movement_collision_count` / `_movement_collision` at `scripts/enemy.gd:3822-3827`. The cheapest safe contact signal is the collision already returned by the movement call; adding a second body query after the move would defeat the proposed saving.
- On a blocked pursuit, `_fail_autonomous_step_blocked` at `scripts/enemy.gd:2299-2327` rolls back, zeros velocity, clears the step and continuous pursuit, and records a temporary failed terrain cell plus a cooldown. This is an existing bounded retry mechanism. A contact stop should branch from the already-classified collision result before treating a live summon interception as a target switch (`_advance_autonomous_step_internal:2481-2499`), while preserving summon interception behavior.

## Reusable design block

A bounded implementation concept can reuse the current fields and lifecycle without a new provider:

1. After `_move_with_spatial_rules` returns, inspect only the existing movement collision result and the actual movement delta. If the collision is an actor/body contact and the selected target is still live, set an actor-local `contact_stopped` state and zero velocity. Do not query the whole enemy group or search for a “front row.”
2. While `contact_stopped`, keep the actor registered in the spatial index and run the cheap per-tick validity checks needed for death, target invalidation, safe zone, control/struck state, and committed attack settlement. Skip expensive pursuit planning and neighbor steering while the contact remains valid.
3. Wake that actor only on a bounded event: target identity or target ground cell changes, a meaningful target displacement threshold is crossed, contact body disappears or separates, map/environment revision changes, damage/threat dirties the target, or the existing retarget/attack cadence becomes due. Use per-actor phase staggering; do not wake the entire cohort on the same frame.
4. On wake, attempt the existing direct-neighbor/polygon/blocked-neighbor order. If the same forward route is blocked, let the existing failed-cell/no-path cooldown apply. A no-result wake must not fabricate a route or clear an accepted action.

The proposed rule therefore saves repeated planning after a confirmed contact. It does not save the collision sweep, body separation, index update, attack-range check, or status/death maintenance.

## Existing staggered wake and retry support

Background actors already use per-actor phase slots and wake timers in `scripts/enemy.gd:3209-3262`; `_background_wakeup_interval_seconds` selects the active-target interval and `_background_wakeup_phase_slot` derives a stable offset from spawn serial and monster ID (`:3238-3261`). `_on_background_wakeup_timeout` performs elapsed-clock/status maintenance, spatial-index update, then one retarget evaluation (`:3263-3310`). This is a usable model for contact-stop wake phasing, provided contact-stopped actors do not enter background sleep while they have a pending attack or committed action.

Terrain already avoids hot-path repeated searches in `_terrain_neighbor_for_pursuit` (`scripts/enemy.gd:2006-2170`): direct O(1) neighbor acceptance precedes bounded path search; recent failed cells and no-path cooldowns suppress immediate repetition; budget exhaustion is a wait, not a path failure. The contact-stop state should reuse those semantics rather than introduce another retry timer.

The spatial index neighbor API (`scripts/runtime_combat_spatial_index.gd:469-533`) clears the caller scratch array, gathers bucket candidates, removes stale weak references, stable-sorts results, and returns candidates. It is still a query cost and cannot establish “front row” without additional geometry and ordering. Existing `_crowd_separation` (`scripts/enemy.gd:6889-6930`) already caches this result behind `_crowd_steering_timer`; a contact-stop optimization should leave that contract intact and simply avoid invoking steering while stopped.

## Required collision versus reducible AI work

Collision detection remains mandatory because the actor must distinguish a free step, a wall/obstacle, a neighbor/body contact, an entrapment boundary, and a safe-zone rollback. The current directional sweep also intentionally clips one eight-way leg and records the collision for wall/summon classification (`scripts/enemy.gd:3724-3734`).

Potentially reducible work begins after that result is known: repeated retarget selection, blocked-neighbor chooser work, terrain path fallback, and crowd separation while the same body contact and target identity remain valid. Those paths are already separately observable through `enemy_retarget_*`, `enemy_neighbor_*`, `enemy_terrain_path_*`, `crowd_*`, and `move_and_slide_usec` counters. A future comparison must report them independently and account for nesting.

## Risks and contracts

- **Deadlock / narrow corridors:** A stopped front actor can permanently block followers if it wakes only on target motion. Require a separation/contact-loss wake, map revision wake, and a bounded alternate-neighbor retry. Preserve the existing failed-cell cooldown so all actors do not retry the same blocked edge together.
- **Obstacles versus actors:** A body collision is not automatically a player-contact event. Environment rollback, entrapment, and static wall classifications must remain authoritative. The existing summon-interception branch must continue to retarget a live summon.
- **Front-row attacks:** An actor that is stopped at contact may have an attack already committed or pending. Do not cancel or restart it when contact state changes; the proposed tradeoff applies to AI replanning latency, not committed attack effects. `_movement_step_engagement_ready` and the existing body-action mutex remain the attack authority.
- **Continuous player movement:** A moving player can invalidate the contact geometry without changing identity. Wake on a meaningful ground displacement or contact separation, then reuse the current target and existing engagement-distance test; do not force a full target-group scan for every player pixel movement.
- **Damage / threat:** Damage wakes currently dirty retarget state through `_hc_damage_dirty` and `_retarget_timer` handling (`scripts/enemy.gd:7817-7855`). Contact-stop must not suppress this wake or lose a target switch caused by a real threat event.
- **Committed actions:** The retarget code deliberately preserves due searches across committed actions until they can be consumed (`scripts/enemy.gd:7818-7825`). Contact-stop may defer movement planning, but it must not clear pending attack time, release records, body reservations, or settlement state.
- **Fairness and progress:** Do not synchronize all stopped actors on one collision frame. Use the existing stable per-actor wake phase and bounded retry. The user does not require perfect surrounding, but every actor must retain a path to gradual pursuit when contact is lost or the target moves.
- **Targeting scope:** A global “front row” computation would require neighbor queries plus body/target geometry and would create a second authority for who is allowed to move. The existing selected-target and physics-contact facts are sufficient for an actor-local stop.

## Relationship to current candidate work

The current pursuit-budget work is a separate candidate under construction. This note does not treat it as proof of contact-stop effectiveness and does not combine its counters with the fixed107 evidence. The retained diagnostic scheduler material states that observation, neighbor, and attack admission currently have separate budget kinds and that a new unified replan ticket would be an architecture change (`outputs/crowd_frame_budget_design_20261009/SCHEDULER_SOURCE_TRACE.md:13-40`). A contact-stop optimization should therefore remain a local post-collision state until a separate contract review chooses a unified scheduler.

## Falsifiable next measurement

Using the existing diagnostic fixture and unchanged actor population, compare two runs with the same source snapshot and layout: baseline versus a contact-stop prototype. Report per-process `enemy_physics_usec`, `enemy_retarget_usec/calls`, `enemy_neighbor_usec/calls`, `enemy_motion_clear_usec/calls`, `move_and_slide_usec`, collision counts, target damage/completions, and player motion. Partition samples into free-motion, contact-stopped, wall/obstacle, and wake/retry states. A valid result must show whether post-contact planning counters fall while collision counts and committed attack outcomes remain correct, and must separately report added stop/wake time, pursuit coverage, and any deadlock or narrow-corridor stalls. No percentage target is assumed and Android/GPU remains outside this diagnostic.


