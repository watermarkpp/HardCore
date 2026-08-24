# M01 Contract — Not Yet Released

Baseline: `f4879d33c78edf21ff189b7be451162e3dbcd37b`
Authority: `assets/data/monster_runtime_authority_v1.json`

```text
M00 = PASS
M01 = FORBIDDEN
M01_IMPLEMENTATION = NOT_STARTED
```

## Reason for the gate

M00 proved the classic cadence algorithm but could not lawfully lock the three per-ID inputs required to execute it:

- `walk_interval_ms`
- `walk_step`
- `walk_wait_ms`

The primary `server_rules` source contains the loader and runtime semantics but no primary per-monster database rows. Current canonical intervals and the selected local 1.76 DB are preserved as candidates; neither is silently elevated over the formal source policy. The exact Ground-GU-to-temporary-classic-cell quantization and class-specific search cadence are also held.

## Frozen M01 inputs

When the gate is later released, M01 must:

1. Read only exact `monster_id` records from `monster_runtime_authority_v1.json`.
2. Keep map-global Ground GU as the sole persistent position.
3. Derive any classic cell transiently; never persist a second grid coordinate.
4. Treat axis and diagonal neighbor movement as one classic event; use 1 GU and `sqrt(2)` GU presentation distances respectively.
5. Drive movement from interval/step/wait cadence, not by reverse-engineering `move_speed_gu_per_sec`.
6. Preserve stationary and dormant class/state semantics.
7. Leave P00 attack delivery, collision, projectile, Red Moon, and fixed-area spike contracts unchanged.
8. Keep continuous speed, spawn leash, return-to-spawn, and Boss multipliers in an explicit compatibility adapter until their replacement stage.

## Preconditions to release M01

- Integration must resolve and record the formal source route for per-ID `WALK_SPD`, `WalkStep`, and `WalkWait`.
- The authority must replace the relevant `null + DATA_HOLD` fields with sourced values and `LOCKED` or explicitly accepted `CANDIDATE` status.
- Per-ID server class/search policy must be machine-bound without runtime name lookup.
- Ground GU to temporary classic-cell quantization must be frozen and round-trip tested without changing `GroundUnitSpace`.
- The updated authority must pass deterministic structure/source validation and canonical catalog checks.

Until all preconditions are met, no edits are authorized to `scripts/enemy.gd`, `scripts/game_root.gd`, `scripts/ground_unit_space.gd`, `scripts/monster_unit_adapter.gd`, or `scripts/monster_identity.gd` for M01.
