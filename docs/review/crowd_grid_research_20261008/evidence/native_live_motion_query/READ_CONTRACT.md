# NATIVE_LIVE_MOTION_QUERY read contract

- Fixed source: `edae6fdef6a6551a951fab1ea8c6ade43359d603`
- Scope: `EnemyActor._hc_motion_candidates` only; no source mutation or tests.
- This is a finite routing contract, not a performance claim.

## Entry and callsites

|function|source|role|
|---|---|---|
|`_hc_motion_candidates`|`scripts/enemy.gd:10301-10334`|returns false on first target/body crossing; otherwise true|
|`_hc_motion_clear_internal`|`scripts/enemy.gd:8846-8888`|candidate bucket query and caller-owned cache scope|
|`_hc_choose_blocked_neighbor`|`scripts/enemy.gd:10229-10243`|batch flank motion query|
|`_hc_direct_source_route_clear`|`scripts/enemy.gd:10136-10153`|two canonical legs|

## Exact native read set

|field|type|source|boundary|
|---|---|---|---|
|`self.a/self.b`|`Vector2`|`_hc_motion_candidates(a,b,candidates):10301-10312`|by value; finite status is owned by caller _hc_motion_clear_internal at 8847-8848|
|`candidates`|`Array[Variant] of live EnemyActor references`|`10301-10316`|raw identity/order; no copy or reorder|
|`self._hc_surround_goal`|`Vector2`|`10307`|finite branch only; target special gate|
|`self.target`|`Node2D reference`|`10307-10310`|is_instance_valid then global_position; target radius via _target_combat_radius_gu|
|`self.runtime_map_id`|`int`|`327`|candidate map gate 10319|
|`self.combat_radius_gu`|`float`|`362-364`|envelope and core_crossed|
|`self.spatial_actor_runtime_id`|`int`|`331`|not consumed by motion body loop; only HCPolicy core may receive it indirectly only in frontline, so do not add|
|`other runtime_map_id`|`int`|`10319`|same-map filter|
|`other.combat_radius_gu`|`float`|`10327,10332`|radius and exact predicate|
|`other.global_position`|`Vector2`|`spatial_index_position 3299-3306; projection helper 3377-3404`|formal ground position; current live read|
|`other.can_receive_damage() fields`|`bool predicate`|`7327-7342`|_body_admission_rejected, current_hp, _death_pending, _dying, is_queued_for_deletion|
|`other.behavior_profile[worldCollision]`|`Dictionary bool default true`|`10330`|after envelope|
|`HCPolicy.EPS/core_crossed`|`static numeric policy`|`10327-10333`|exact existing floating-point order|
|`RuntimeDiagnostics counter`|`observer side effect`|`10302-10303,209-210`|must remain before early returns|

## Required order and effects

1. Record `enemy_motion_candidate_checks(candidates.size())` at `10302-10303`. 2. On the finite surround-goal plus valid-target branch, project only `target.global_position`, run `HCPolicy.core_crossed`, and return false immediately on a crossing. 3. Scan the original candidate Array order. Reject invalid/non-Enemy, self/target, and map mismatch before the body counter. 4. Increment `enemy_motion_body_checks`, read each candidate’s current formal position, apply the conservative envelope, then read live damage eligibility and `behavior_profile["worldCollision"]`, and finally run exact `HCPolicy.core_crossed`. 5. Return on the first crossing.

## Identity and routing

`EnemyActor` is `class_name EnemyActor` extending `CharacterBody2D` (`scripts/enemy.gd:1-2`). The native gate needs exact known script identity and implementation. `Object.is_class("EnemyActor")` is not equivalent to GDScript `is EnemyActor` and cannot be used as the gate. Ordinary GDScript members, including underscore-prefixed cache members, may be read through Godot `Object.get`; no private-memory offset or extra bridge is required.

- Known exact EnemyActor and known pure field reads: native route may execute the complete loop.
- An unknown Enemy subclass may enter only when the scan implementation is inherited unchanged; any overridden callee uses the old callee at its original loop point. Unknown provider, invalid projection Callable, or missing environment revision method also uses the old helper at its original point.
- A legacy callback/provider is a reentry boundary. Discard pre-call facts and reread the exact fields the original code reads next: validity/type, map, current position, eligibility, behavior profile, and radii. If it destroys an object, preserve legacy invalid-instance/error behavior; do not add a new conservative rejection or restart the query.

## Projection and environment

`spatial_index_position()` only has a safe known hit when its full predicate at `scripts/enemy.gd:3285-3296` holds. Its declared cache fields are `_last_spatial_index_screen_position_px: Vector2`, `_last_spatial_index_ground_position_gu: Vector2`, `_last_spatial_index_runtime_map_id: int`, `_last_spatial_index_zone_generation: int`, `_last_spatial_index_environment_revision: int`, and `_last_spatial_index_projection: Callable` (`567-572`). Object.get can read these ordinary members. A miss remains the original projection path (`3377-3427`). `_hc_environment_revision()` (`9638-9641`) calls the external provider and is not pure; the exact `WorldBackground` implementation is `class_name WorldBackground`, with `_environment_collision_revision: int` and a plain getter (`scripts/world_background.gd:1,112,337-338`). The target special projection at `10307-10310` is conditional; do not eagerly project all candidates.

## Index and diagnostics boundaries

`RuntimeCombatSpatialIndex` performs bucket/stale filtering and returns live EnemyActor nodes (`scripts/runtime_combat_spatial_index.gd:390-440`). Native motion must use live formal positions and never treat a stale index Dictionary position as authoritative. Position writers, index publication, movement, signals, and candidate-pool construction remain outside this route.

`_record_performance_counter` delegates to `RuntimeDiagnostics.increment_performance_counter` (`scripts/enemy.gd:209-210`). Counter names, order, and amounts remain unchanged; no delayed flush or diagnostic batching is allowed.

## Gaps and judgment

- Private cache members cannot be read by native without a formally typed bridge that preserves the exact identity predicate.
- `behavior_profile` is a plain Dictionary read; preserve its Variant-to-bool conversion. Projection/environment callbacks can reenter or destroy objects; unknown providers use the original call point, then live rereads and legacy invalid/error behavior.
- `can_receive_damage()` is exactly `_body_admission_rejected` false, `current_hp > 0`, not `_death_pending`, not `_dying`, and not queued (`7327-7342`); no shadow HP/life is permitted.
- This is feasible only as one bounded execution replacement. Whole-entry fallback is reserved for a callback/reentry boundary that cannot be safely resumed; unknown inherited overrides use their original loop/helper point. No coverage or speed promise follows.
