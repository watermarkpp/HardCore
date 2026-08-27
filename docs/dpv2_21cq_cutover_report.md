# DPV2-21CQ-X1 Phase 7 Package3B Cutover Report

Status: `BLOCKED / NOT_CLOSED`

Baseline branch: `codex/integration`

Package baseline HEAD: `571985ECEC77A83155272F52C02894366B7D8ABF`

Integrated source-priority change: `77777FA664B5DA96F1DAB5A721B24B7F0E6FDAD0`
`FINAL_SHA: THIS_CLOSURE_COMMIT`

This package changes only the final gate and these reports. Production
Runtime, the direct baseline data, the canonical catalog, the source-priority
policy, P1A tooling, and tests remain outside this package's write scope.

## Gate decision

The final gate was run after the Package3B gate rewrite:

```text
DPV2_FINAL_GATE_FAIL blocker_count=3
```

The three failed steps are two checks of one protected-data condition and one
protected legacy-integration condition:

1. `direct_baseline_generator_check` reports generated output drift in
   `assets/data/drop/dpv2_direct_baseline_manifest_v2.json`. The manifest
   records the old LF-normalized `source_priority_policy.json` hash
   `1E75418BB02A17885F4A14527E2F5E4D6D71316A99CBA3DD8ED4D640825CF4E7`, while
   the policy integrated by `77777fa6` hashes to
   `0ABE78CD15EE75C59328269880DE25F4B6E892333C5BDF88BADDC9B60C0925EB`.
   Updating or regenerating that protected manifest is an integration action,
   not a Package3B write.
2. `dpv2_direct_python_tests` ran 17 tests: 16 passed and the one failure is
   the same manifest source-priority hash mismatch.
3. `world_integration` remains a protected test and fails at
   `tests/monster_world_integration_test.gd:369` (`no-drop loot was
   configured`). Its later line-118 identity assertion is a cascade because
   the earlier assertion aborts before restoring the temporary closure. This
   package does not alter that test or Production Runtime.

The gate intentionally does not call the historical runtime activator or the
A0.7 production-freeze validator. It writes `CLOSED` only when the blocker
count is zero; this report therefore remains `NOT_CLOSED`.

## Dual-view accounting

| View | Profiles/records | Rows or slots | Disposition |
| --- | ---: | ---: | --- |
| Physical source | `MonItems=0` files in Git | — | tracked logical JSON is the reproducible source |
| Tracked logical source | `217` records | `9590` rows | user-locked source ledger |
| Active source view | `156` profiles | `7032` rows | `5995` enabled-source + `1037` NON_LOOT-source |
| Compiled runtime | `156` profiles | `5995` slots | `131` enabled profiles + `25` NON_LOOT profiles |
| Runtime origin | — | `5995` slots | `5926` `LEGACY_21CQ_MONITEMS` + `69` `PROJECT_EXTENSION` |
| Runtime stages | — | `5995` each | eligible = reward = probability = RNG |
| Canonical item catalog | — | `233` items | direct canonical identity only |

The full tracked logical disposition remains `5926 + 69 + 1037 + 2558 =
9590`; the `7032` active-source rows are not a runtime RNG table. NON_LOOT rows
and all other disabled source rows do not enter RNG. No physical MonItems file
is claimed or reconstructed by this report.

## Identity and provenance closure

| Mapping | EXACT | EXPLICIT_ALIAS | extension | NON_LOOT / gold | retired-only | unresolved |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Monster | `191` | `0` | `1` | `25` | — | `0` |
| Item | `227` | `11` | — | gold `1` | `5` | `0` |

Production joins V2 profiles by exact `canonical_monster_id`; the direct profile
identifier (`dpv2.direct.<id>`) is not guessed from the catalog `drop.<id>`
identifier. Item slots carry a validated positive `canonical_item_id`. The five
`RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG` labels remain non-identities with
null canonical ID and name. Gold is a separate reward kind.

The sole malformed source token is monster `168`, `slot_020`, historical
`1/00`; the explicit compiled correction is `1/2800`. The source token is not
silently rewritten or dropped.

## Stable IDs

- Manifest: `dpv2.direct_baseline.manifest.v2`.
- Runtime authority: `hardcore.dpv2.direct_baseline.v2`.
- Global control: `dpv2.global_drop_rate_scale.v1`.
- Profile IDs are `dpv2.direct.<canonical_monster_id>`; catalog joins remain by
  exact `canonical_monster_id`, never by guessed `drop.<id>` conversion.
- The parity/sample slot is `dpv2.direct.m18.slot_001`; the malformed-source
  provenance is `dpv2.source.m168.slot_020`.

## Duplicate and parity evidence

The source audit records duplicate item groups `493`, duplicate item rows beyond
first `1906`, exact duplicate groups `542`, and exact duplicate rows beyond
first `1657`. The compiled-subset parity report separately records `993`
preserved exact duplicate rows beyond first. Every compiled slot retains a
unique `slot_uid`; no duplicate is merged or aggregated.

`x1_probability_mismatch=0` is recorded by the direct baseline summary and
covered by the direct baseline/P1A checks. For the requested `x10` evidence,
the compiled direct view contains `189` slots with base denominator `10`
(`1/10` source probability); there is no `10x` global preset in the frozen
global authority (its available presets are `0.5x`, `0.8x`, `1x`, `1.5x`, and
`2x`), so this report does not mislabel a 10x-scale run.

The formal direct runtime test passed the available rational-scale and safety
evidence:

- `1x`: `1/3 -> 1/3`; `0.5x`: `1/3 -> 1/6`; `2x`: `1/3 -> 2/3`.
- Invalid scale selection fails closed; an over-one result clamps to `1/1`.
- Every eligible slot receives an independent draw before retention; duplicate
  rows remain independent. Diagnostics include `slot_uid`, canonical ID, base
  numerator/denominator and probability, global scale, final probability,
  draw/success, overflow/protection, origin, and provenance.
- Successful candidates are retained only after RNG, with protected items first,
  descending `overflow_priority`, stable unbiased tie handling, and hard cap 9.
  Protected overflow telemetry is asserted for both selected and discarded
  protected candidates.

## Production legacy dependency search

The gate's classified negative search covered
`scripts/game_data.gd` and
`scripts/layers/runtime/loot_runtime_service.gd`:

```text
DPV2_PRODUCTION_LEGACY_DEPENDENCY_SEARCH_PASS: targets=2 matches=0 classifications=Tier,DropRole,role_factor,tier_factor,old_runtime_authority
```

Production Tier, Drop Role, `role_factor`, `tier_factor`, old resolver/state,
and old runtime-authority dependencies are therefore `0` in the two production
files. Historical A0.x artifacts remain available only as `LEGACY/HISTORICAL`
evidence and are not gate inputs.

## Exact validation commands and results

| Command | Result |
| --- | --- |
| `py -3.12 tools/build_dpv2_21cq_direct_baseline.py --check` | **FAIL**: generated manifest drift, protected source-priority hash mismatch |
| `py -3.12 tools/build_canonical_monster_catalog.py --check` | **PASS**: `identities=156 runtime_allowed=153 drop_rows=7032 authoring_rows=0` |
| `py -3.12 tools/verify_source_priority_policy.py` | **PASS**: JSON `passed=true`, all checks true |
| `py -3.12 -m unittest tests/test_dpv2_21cq_source_audit.py tests/test_dpv2_21cq_mapping_authority.py tests/test_dpv2_21cq_direct_baseline.py -v` | **16 passed, 1 failed, 17 total**; only manifest hash assertion failed |
| `tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/dpv2_21cq_direct_loader_test.tscn, tests/dpv2_21cq_direct_runtime_test.tscn, tests/dpv2_drop_runtime_policy_test.tscn, tests/monster_drop_p1a_runtime_contract_test.tscn, tests/monster_gold_drop_runtime_test.tscn` | **PASS 5/5**, engine log errors `0` |
| `tools/run_monster_drop_p1a.ps1` (inside gate) | **PASS**: `MONSTER_DROP_P1A_ALL_PASS`; analyzer unit `8/8`, Godot `2/2` |
| `tools/run_monster_drop_p1a_audit.ps1` (inside gate) | **PASS**: `MONSTER_DROP_P1A_AUDIT_PASS`, deterministic snapshot `216C4F372FD6FBD44C24D5199E3CC6C7ED4F2B790197116FE50D14CAB43AFECF` |
| `tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/monster_world_integration_test.tscn` | **FAIL**: protected no-drop assertion at line 369; cascade at line 118 |
| `tools/run_dpv2_final_gate.ps1` | **FAIL**: `DPV2_FINAL_GATE_FAIL blocker_count=3` |
| `git diff --check` | **PASS** |

## Integration handoff

Before closure can be marked `CLOSED`, integration must refresh the protected
direct-baseline manifest (or otherwise reconcile its source-priority artifact
hash) against the already-integrated policy, then decide the separately
protected world-test contract at line 369. Rerun the final gate on the resulting
HEAD. The final response must replace `FINAL_SHA: THIS_CLOSURE_COMMIT` with the
actual closure commit hash; no self-referential SHA is asserted here.
