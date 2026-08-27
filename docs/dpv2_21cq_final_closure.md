# DPV2-21CQ-X1 Final Closure Record

Status: `BLOCKED / FINAL_CLOSURE_PENDING`

`FINAL_SHA: THIS_CLOSURE_COMMIT`

This is the Package3B closure record for the final-gate/report lane. It is not
marked `CLOSED` because the final gate observed blockers. A real closure SHA
must be supplied by integration after the remaining protected conditions are
resolved and the gate is rerun.

## Frozen final accounting

```text
physical MonItems files in Git: 0
tracked logical source: 217 records / 9590 rows
active source view: 156 profiles / 7032 rows = 5995 enabled-source + 1037 NON_LOOT-source
compiled runtime: 156 profiles / 131 enabled + 25 NON_LOOT / 5995 slots
compiled origins: 5926 LEGACY_21CQ_MONITEMS + 69 PROJECT_EXTENSION
eligible = reward = probability = RNG: 5995
canonical items: 233
monster mappings: EXACT191 / ALIAS0 / extension1 / NON_LOOT25 / unresolved0
item mappings: EXACT227 / ALIAS11 / gold1 / retired-only5 / unresolved0
```

The `7032` active source rows are an audit view, never the runtime RNG slot
table. NON_LOOT `1037` rows do not enter RNG. The sole malformed provenance is
monster `168`, `slot_020`, historical `1/00`, explicitly compiled as `1/2800`.

Stable IDs: `dpv2.direct_baseline.manifest.v2`,
`hardcore.dpv2.direct_baseline.v2`, `dpv2.global_drop_rate_scale.v1`,
profiles `dpv2.direct.<canonical_monster_id>`, sample slot
`dpv2.direct.m18.slot_001`, and provenance `dpv2.source.m168.slot_020`.

Source duplicate facts are: `493` duplicate item groups, `1906` duplicate rows
beyond first, `542` exact duplicate groups, and `1657` exact duplicate rows
beyond first. The compiled-subset parity report separately records `993`
preserved exact duplicate rows beyond first. No duplicates are collapsed.

## Runtime and safety evidence

- Direct x1 parity is `0` mismatches. The compiled view contains `189` base
  `1/10` slots as the requested x10/base-denominator evidence; the frozen
  global authority has no `10x` preset, so no unsupported 10x claim is made.
- Exact rational scale evidence passed for `1x`, `0.5x`, and `2x`; invalid
  scales fail closed and over-one results clamp to `1/1`.
- Independent per-slot RNG, duplicate independence, debug/provenance fields,
  post-RNG hard cap `9`, protected-first ordering, descending priority, stable
  tie handling, and `protected_overflow` telemetry all passed the formal direct
  runtime test.
- Classified production negative search found `0` Tier, Drop Role,
  `role_factor`, `tier_factor`, old resolver/state, or old runtime-authority
  dependencies in the production GameData/LootRuntime files.
- A0.x material remains historical `LEGACY/HISTORICAL` and is not a final-gate
  production input.

## Gate state and required integration

The final gate result on the Package3B worktree was:

```text
DPV2_FINAL_GATE_FAIL blocker_count=3
```

Two failed steps report the same protected manifest drift: the manifest records
source-priority LF hash
`1E75418BB02A17885F4A14527E2F5E4D6D71316A99CBA3DD8ED4D640825CF4E7`, while the
policy already integrated by `77777fa6` hashes to
`0ABE78CD15EE75C59328269880DE25F4B6E892333C5BDF88BADDC9B60C0925EB`. The
direct generator check and 17-test Python suite consequently report failure
(the suite is otherwise `16 passed, 1 failed`). Refreshing that protected
manifest belongs to integration, not this report/gate package.

The third failure is the protected `monster_world_integration_test`: its
no-drop assertion at line 369 still expects the retired closure path, and its
line-118 assertion is a cascade after the earlier assertion aborts restoration.
This package does not edit that test or Production Runtime.

All direct loader/runtime/policy/P1A/gold Godot tests passed `5/5`; fresh P1A
and deterministic audit passed; canonical catalog, source-priority verifier,
production legacy search, and `git diff --check` passed. Once the two protected
conditions are resolved, rerun:

```text
tools/run_dpv2_final_gate.ps1
```

Only a result with `DPV2_FINAL_GATE_PASS blocker_count=0` may change this record
to `CLOSED`. Integration must then replace the placeholder with the real commit
SHA in the final response; this file deliberately does not predict its own
hash.
