# M00R — M01 Release Source Closure

Date: 2026-08-24
Baseline: `1945a5eceaf6efc49ddf4e5da4298834bf15c864`

```text
M00 = PASS
M00_REMOTE = PASS
M00R = PASS_AFTER_REPOSITORY_GATES
M01 = ALLOWED
M01_IMPLEMENTATION = NOT_STARTED
```

## Lane correction

`server_rules` remains the A-locked authority for `WALK_SPD` meaning and the `WalkStep`/`WalkWait` algorithm. Per-monster values were re-audited under the `server_data` lane; M00R no longer requires the rule-source tree to contain Monster.DB rows.

| Distribution | Tier/order | Records | WALK_SPD | WalkStep | WalkWait | Exact canonical bindings | Decision |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| `server.crystal.cjlaaa` | primary/0 | 544 | 544 | 0 | 0 | 100 | `SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH` |
| `server.angelk727_full` | auxiliary_1/1 | 1134 | 1133 | 0 | 0 | 85 | `SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH` |
| `server.crystal.Jev` | auxiliary_2/2 | 555 | 555 | 0 | 0 | 0 | `SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH` |
| `server.crystal.Daneo1989` | auxiliary_3/3 | 506 | 506 | 0 | 0 | 0 | `SOURCE_PRESENT_BUT_VERSION_SCOPE_MISMATCH` |

The routed Crystal sources are later-version distributions and omit `WalkStep`/`WalkWait`; none is represented as classic 1.76 truth. Their paths, hashes, versions, coverage, missing counts, conflicts, and rejection reasons are frozen in the movement source master.

## Local 1.76 candidate

- Distribution: `candidate.mylgd_mir2server_176`.
- SHA-256: `a8a2919b2f05f95459c01a67c9326f3d86fb954ecdc5dbb095e96cba237515b0`.
- Schema: 22 fields, 98-byte rows, 388 decoded rows.
- Version evidence: bundled README declares version 1.76 and GEE engine.
- Authenticity limit: third-party learning package, accepted candidate rather than official classic truth.
- Canonical exact bindings: 144; exact rows missing: 12.
- All bindings are materialized offline by `monster_id`; runtime name lookup is forbidden.

## Movement decisions

| Status | Count | Meaning |
| --- | ---: | --- |
| `LOCKED` | 6 | Source-locked stationary monsters; no movement grant |
| `ACCEPTED_CANDIDATE` | 138 | Exact stable-ID row from the audited 1.76-labeled candidate |
| `COMPATIBILITY_HOLD` | 12 | Exact row missing; explicit stable-ID binding to the audited canonical base row |

Compatibility/HOLD IDs: `41, 59, 78, 123, 161, 190, 228, 229, 230, 231, 232, 233`.

No M01 movement record contains `DATA_HOLD`, `UNKNOWN`, or an unsourced numeric default. Runtime-disabled IDs remain disabled.

## Conflict closure

All 75 interval conflicts are individually recorded and classified:

- `CANONICAL_PROJECT_TUNING`: 37
- `ID_BINDING_MISMATCH`: 6
- `SPECIAL_CLASS_OVERRIDE`: 4
- `VERSION_DIFFERENCE`: 28
- `SAME_VERSION_DATA_CONFLICT`: 0

The 12 exact-row misses are separately recorded as `SOURCE_ROW_MISSING` and resolved only as explicit `COMPATIBILITY_HOLD`; no bulk “old DB wins” or “canonical wins” decision was used.

## Temporary classic cell

The only persistent position remains map-global Ground GU. M00R locks the pure derivative:

```text
temporary_cell = floor(position_ground_gu)
cell_center = temporary_cell + (0.5, 0.5)
neighbor_target = temporary_cell + neighbor + (0.5, 0.5)
```

The deterministic builder checks positive, zero, negative, and integer-boundary round trips. Eight neighbor deltas are unique; axis distance is 1 GU, diagonal distance is `sqrt(2)` GU, and each is one movement event. `scripts/ground_unit_space.gd` is unchanged.

## Server class binding

All 156 canonical IDs contain offline `monster_id -> Race/RaceImg/appearance/behavior_family` bindings. Coverage is 156/156 and runtime name lookup is disabled.

## Scope protection

No production runtime code, player movement, map runtime logic, attack delivery, canonical monster identity, `GroundUnitSpace`, or `MonsterIdentity` was changed. Frozen monster 70/124/220/222, physical projectile, Red Moon, and fixed-area spike deliveries remain untouched.

## Acceptance results

- Movement source master deterministic check: PASS, 156 records.
- Runtime authority deterministic check: PASS, 156 records / 153 runtime allowed.
- Canonical catalog check: PASS, 156 identities / 153 runtime allowed.
- Combat authority reconciliation: PASS, 156 active identities.
- Monster suite: PASS 23/23, failed 0, engine log errors 0.
- `combat_absolute_ground_critical`: PASS 9/9, failed 0, engine log errors 0.
- `combat_projection_fail_closed_critical`: PASS 6/6, failed 0, engine log errors 0.
