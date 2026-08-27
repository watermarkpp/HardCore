# DPV2-21CQ-X1 Final Closure Record

Status: `CLOSED`

`FINAL_SHA: THIS_CLOSURE_COMMIT`

This is the Package3C closure record for the direct-baseline final gate. It is
marked `CLOSED` because the final gate completed with zero blockers. The actual
closure SHA must be supplied by integration in the final handoff.

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

- Direct x1 parity is `0` mismatches. The direct runtime test injects a `10x`
  preset only in memory, selects real slot `dpv2.direct.m21.slot_002` (`1/20`),
  and proves exact `1/20 * 10/1 = 1/2`; a real `1/3 * 10/1` result clamps to
  `1/1`. The formal global authority JSON is unchanged and the test restores
  its preset list, active preset, and scale index. The compiled view contains
  `189` base `1/10` slots, separate from the x10 scale test.
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

## Gate state

The final gate result on the Package3C worktree was:

```text
DPV2_FINAL_GATE_PASS blocker_count=0
```

Manifest source-priority hash is now
`0ABE78CD15EE75C59328269880DE25F4B6E892333C5BDF88BADDC9B60C0925EB`, matching
the already-integrated `77777fa6` policy. The builder confirmed no generated
data/report drift beyond that manifest field. The world test now removes and
restores only the direct profile index for monster 64, while identity/GameData
and bridge remain accessible and LootRuntime returns
`configured=false, reason=dpv2_direct_profile_unresolved`.

Direct loader/runtime/policy/P1A/gold Godot tests passed `5/5`; fresh P1A and
deterministic audit passed; canonical catalog, source-priority verifier,
production legacy search, 17 Python tests, world integration, and diff check
passed.

The final gate command was:

```text
tools/run_dpv2_final_gate.ps1
```

The final response must replace the placeholder with the actual Package3C
commit SHA; this file deliberately does not predict its own hash.
