# M00 Monster Runtime Authority Freeze

Date: 2026-08-24
Baseline: `f4879d33c78edf21ff189b7be451162e3dbcd37b`
Stage: `M00_MONSTER_RUNTIME_AUTHORITY_FREEZE`

```text
P00 = CLOSED
M00 = PASS
M01 = FORBIDDEN
```

M00 freezes evidence and uncertainty only. It does not implement movement, targeting, recovery, wandering, or Boss cadence. The production runtime and all P00 frozen attack deliveries remain unchanged.

## Scope and identity

- Identity authority remains `monster_id`; no runtime name lookup was introduced.
- Canonical identities: 156; runtime allowed: 153.
- Runtime-disabled IDs: 33, 183, 241 (`drop_policy_not_closed`).
- Classification, all identities: ordinary 74, elite 30, boss 20, special 25, version_difference 6, non_hostile 1.
- Runtime classification: ordinary 73, elite 29, boss 20, special 24, version_difference 6, non_hostile 1.
- Stationary profiles: 6 (`30,124,126,180,182,195`).
- Static dormant profiles: 7 (`153,155,156,157,158,159,160`); ID 124 additionally enters a burrowed dormant runtime state.
- Explicit ranged delivery: 5 (`150,152,206` physical projectile; `220,222` target magic).
- Explicit special-behavior union: 12 (`30,70,124,126,150,152,180,182,195,206,220,222`).

## Source arbitration

`assets/data/source_priority_policy.json` is controlling. The `server_rules` primary is `source.original_gameofmir.server_suite`.

The primary source proves the meanings and algorithms of `WALK_SPD`, `WalkStep`, and `WalkWait`, but the primary source tree does not contain primary per-monster `Monster.DB` rows. Therefore M00 does not silently promote either of these lower/equivalent project candidates:

1. Current canonical/service `moveIntervalMs`: complete for 156 IDs, but confidence is mixed (`A=2`, `auxiliary_1=1`, `B=100`, `B/C=14`, `C=39`) and 42 service bindings are unresolved project fallback.
2. Selected local 1.76 Paradox DB: 144 exact ID/name bindings, but that distribution is not routed in the formal `server_data` lane. It disagrees with the current canonical interval on 75 IDs and has no exact binding on 12 IDs.

Consequently every per-ID `walk_interval_ms`, `walk_step`, and `walk_wait_ms` is `null + DATA_HOLD`. Both candidate values and every conflict are retained in the JSON rather than discarded.

## Frozen rule decisions

| Rule | Decision | Evidence |
| --- | --- | --- |
| `WALK_SPD` meaning | `A_LOCKED`: millisecond cadence, minimum 200ms | `LocalDB.pas:1351-1353`, `UsrEngn.pas:2608-2611` |
| Per-ID WALK_SPD | `DATA_HOLD` | Primary per-ID rows absent; candidates retained separately |
| WalkStep / WalkWait algorithm | `A_LOCKED` | `ObjMon.pas:430-446` |
| Per-ID WalkStep / WalkWait | `DATA_HOLD` | Primary per-ID rows absent |
| Default TMonster view | `A_LOCKED = 5 cells` | `ObjMon.pas:249-258` |
| Special view overrides | `A_LOCKED` by proven class: 5/6/7/8/9/12/16 | constructors in `ObjMon*.pas` / `ObjAxeMon.pas` |
| “5 cells discovers every ordinary ID” | `B_CANDIDATE` | Discovery consumes the visible list; per-ID class binding is not fully locked |
| Standard active search | `A_LOCKED` for TAT-family only: idle `>1000ms`, engaged `>8000ms` | `ObjMon.pas:614-629` |
| Universal search cadence | `CONFLICT / DATA_HOLD` | Other primary classes use 5s, idle-only 1s, outer-8s, or Walk/Hit cadence |
| Target selection | `A_LOCKED`: minimum Manhattan `abs(dx)+abs(dy)` | `ObjBase.pas:22667-22692` |
| Struck retarget | `A_LOCKED`: no target, current target attackable, or 1/6 random; hitter must be proper | `ObjBase.pas:2794-2805` |
| Target Focus timeout | `A_LOCKED = 30000ms` | `ObjBase.pas:3884-3895` |
| Target Focus refresh | `A_LOCKED`: target assignment and explicit successful attack release paths | `ObjBase.pas:21929-21933`, `ObjMon.pas:390-396` |
| Disengage | `A_LOCKED`: different map/dead/ghost, or `abs(dx)>15 OR abs(dy)>15` | `ObjBase.pas:3884-3895` |
| Natural HP recovery | `A_LOCKED`: nominal 6000ms, `floor(MaxHP/75)+1`, not limited to idle | `ObjBase.pas:3718-3766`, `M2Share.pas:1638` |
| Recovery reset on monster struck | `DATA_HOLD` | Base RM_STRUCK resets; TAnimalObject intercept path does not; exact dispatch needs a later focused test |
| Fixed recovery base 28 | `CONFLICT`, rejected | No primary server-rule support |
| Idle wandering | `A_LOCKED`: 1/20 decision; then 1/4 random turn, otherwise forward Walk | `ObjMon.pas:515-520`, `ObjBase.pas:22723-22728` |
| Spawn leash / return patrol | Rejected as classic authority | Current `_return_to_spawn()` is compatibility behavior, not the primary rule |

## Spatial authority

- Persistent position remains `runtime_map_absolute_ground_gu`.
- Classic AI cell may only be a temporary derivative; no second persistent grid position is allowed.
- Axis neighbor cost is 1 GU; diagonal neighbor cost is `sqrt(2)` GU. Both are one classic movement event.
- The primary server rules do not define the exact project Ground-GU-to-AI-cell quantization. That boundary remains `DATA_HOLD`.
- Current `cell + (0.5,0.5)` conversion is retained as `C_COMPATIBILITY`, not silently promoted.
- `scripts/ground_unit_space.gd` is unchanged.

## Boss and special movement audit

- ID 76 health-stage rage has current `moveSpeedMultiplier=1.8`, 8 seconds, confidence C. It remains a compatibility candidate.
- Future M05 candidate mapping is cadence-frequency multiplication (equivalently interval division) without changing classic step distance. It is not active authority yet.
- ID 76 surrounded relocation remains a separate map-authority request; it is not walking.
- ID 124 burrow/emerge, stationary behavior, and emerge heal were audited without alteration.
- Configured `phaseTwo` flags for 56, 89, 76, 124, 160 are false.
- Current continuous `move_speed_gu_per_sec`, safe-zone return, spawn leash, rage multiplication, and return-to-spawn are recorded only as compatibility behavior.

## Frozen attack deliveries

No redesign or mutation was made to monster 70, monster 124, 220, 222, physical projectiles, Red Moon, or fixed-area spike delivery. The P00 frozen assets and manual anchors remain byte-identical.

## Machine authority

The machine-readable authority is `assets/data/monster_runtime_authority_v1.json` and is deterministically built/checked by `tools/build_monster_runtime_authority.py --check`.

Unknown numeric values use `null + DATA_HOLD`; zero is never used as an unknown sentinel. Every record preserves its canonical ID/name/classification, rule status, source/candidate evidence, compatibility projection, stationary/dormant flags, and unresolved conflicts.

## Gate decision

M00 passes because all required facts are explicitly `LOCKED`, `CANDIDATE`, `CONFLICT`, or `DATA_HOLD`, and no conflict is silently resolved.

M01 remains forbidden because per-ID classic cadence, WalkStep/WalkWait, universal per-ID search cadence, and the Ground-GU-to-temporary-cell quantization are still `DATA_HOLD`.
