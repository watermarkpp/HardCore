# M01 Contract — Released by M00R

Baseline: `1945a5eceaf6efc49ddf4e5da4298834bf15c864`
Movement authority: `assets/data/monster_movement_source_master_v1.json`
Runtime authority: `assets/data/monster_runtime_authority_v1.json`

```text
M00 = PASS
M00R = PASS_AFTER_REPOSITORY_GATES
M01 = ALLOWED
M01_CONTRACT = RELEASED
M01_IMPLEMENTATION = NOT_STARTED
```

## Released M01 inputs

- Runtime identity is exact `monster_id`; runtime name binding is forbidden.
- All 156 canonical IDs have a machine-bound movement source and server class/family binding.
- Movement status is one of `LOCKED`, `ACCEPTED_CANDIDATE`, or `COMPATIBILITY_HOLD`; no M01 movement field remains `DATA_HOLD`.
- Six source-locked stationary monsters never receive a movement grant.
- Twelve explicitly listed variant IDs use stable-ID compatibility bindings to audited base rows; this does not reactivate retired IDs.
- `WALK_SPD` is the movement-event cadence in milliseconds with the already locked 200ms minimum.
- `WalkStep` counts granted neighbor events before `WalkWait`; the server-rule semantics are unchanged.

## Spatial contract

- The sole persistent world position is `runtime_map_absolute_ground_gu`.
- Temporary classic cell: `Vector2i(floor(position_ground_gu.x), floor(position_ground_gu.y))`.
- Cell center: `Vector2(cell) + Vector2(0.5, 0.5)`.
- Neighbor target: `Vector2(cell + neighbor) + Vector2(0.5, 0.5)`.
- The temporary cell must never be persisted as a second logical position.
- Each axis or diagonal neighbor consumes one movement grant; distances are `1 GU` and `sqrt(2) GU` respectively.

## M01 implementation boundary

M01 may replace only autonomous EnemyActor movement frequency/step execution with cadence-governed one-neighbor events and Ground GU interpolation. `move_speed_gu_per_sec` remains presentation/interpolation speed and cannot determine event frequency.

M01 must not change target acquisition, perception, threat, leash, disengage, focus, recovery, world state, Boss persistence, attack delivery, player movement, `GroundUnitSpace`, or `MonsterIdentity`. Class-specific target-search cadence is explicitly deferred to M02.

M01 must preserve the frozen deliveries for monsters 70, 124, 220, 222, physical projectiles, Red Moon, and fixed-area spikes.

M00R releases the contract only. It does not implement M01.
