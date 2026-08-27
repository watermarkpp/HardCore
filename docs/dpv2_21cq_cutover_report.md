# DPV2-21CQ-X1 Phase 7 Package3C Cutover Report

Status: `CLOSED`

Baseline branch: `codex/integration`

Package3C baseline HEAD: `738D11A5E86829E91359106C424C0CF5027C9E0C`

Integrated source-priority change: `77777FA664B5DA96F1DAB5A721B24B7F0E6FDAD0`
`FINAL_SHA: THIS_CLOSURE_COMMIT`

This package changes only the direct-baseline manifest hash, the direct runtime
scale/world-contract tests, and these reports. It uses the previously committed
direct-baseline final gate. Production Runtime, the direct baseline authority,
the canonical catalog, the source-priority policy, P1A tooling, and unrelated
tests remain unchanged.

## Gate decision

The final gate was rerun after the Package3C manifest refresh, x10 test, and
direct V2 world fail-closed test:

```text
DPV2_FINAL_GATE_PASS blocker_count=0
```

The formal builder refreshed only the manifest's source-priority artifact hash;
all other generated baseline/mapping/provenance/report outputs remained byte
identical. The world integration test now removes and restores only the direct
profile index entry for monster 64, proving identity/GameData/bridge access is
independent from the direct profile and that LootRuntime fails closed with
`dpv2_direct_profile_unresolved`. The gate intentionally does not call retired
pre-cutover validators. Because blocker count is zero, this report is `CLOSED`.

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
covered by the direct baseline/P1A checks. The direct runtime test injects a
`10x` preset only in memory, selects real slot
`dpv2.direct.m21.slot_002` (`1/20`), and proves exact `1/20 * 10/1 = 1/2`;
it also proves a real `1/3 * 10/1` result clamps to `1/1`. The formal global
authority JSON remains unchanged and the test restores both its preset list
and active preset/index after the assertions. The compiled direct view contains
`189` slots with base denominator `10` (`1/10` source probability), separate
from the x10 scale test.

The formal direct runtime test passed the available rational-scale and safety
evidence:

- `1x`: `1/3 -> 1/3`; `0.5x`: `1/3 -> 1/6`; `2x`: `1/3 -> 2/3`.
- Temporary test-only `10x`: `1/20 -> 1/2`; clamp: `1/3 -> 1/1`.
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
| `py -3.12 tools/build_dpv2_21cq_direct_baseline.py --write` | **PASS**: only manifest source-priority hash changed; no other generated output drift |
| `py -3.12 tools/build_dpv2_21cq_direct_baseline.py --check` | **PASS**: `logical_records=217 source_rows=9590 corrected=1 monster_unresolved=0 item_unresolved=0 compiled_slots=5995 x1_mismatch=0` |
| `py -3.12 tools/build_canonical_monster_catalog.py --check` | **PASS**: `identities=156 runtime_allowed=153 drop_rows=7032 authoring_rows=0` |
| `py -3.12 tools/verify_source_priority_policy.py` | **PASS**: JSON `passed=true`, all checks true |
| `py -3.12 -m unittest tests/test_dpv2_21cq_source_audit.py tests/test_dpv2_21cq_mapping_authority.py tests/test_dpv2_21cq_direct_baseline.py -v` | **PASS 17/17** |
| `tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/dpv2_21cq_direct_loader_test.tscn, tests/dpv2_21cq_direct_runtime_test.tscn, tests/dpv2_drop_runtime_policy_test.tscn, tests/monster_drop_p1a_runtime_contract_test.tscn, tests/monster_gold_drop_runtime_test.tscn` | **PASS 5/5**, engine log errors `0`; direct marker includes `10x=1/20_to_1/2 clamp=1/1` |
| `tools/run_monster_drop_p1a.ps1` (inside gate) | **PASS**: `MONSTER_DROP_P1A_ALL_PASS`; analyzer unit `8/8`, Godot `2/2` |
| `tools/run_monster_drop_p1a_audit.ps1` (inside gate) | **PASS**: `MONSTER_DROP_P1A_AUDIT_PASS`, deterministic snapshot `216C4F372FD6FBD44C24D5199E3CC6C7ED4F2B790197116FE50D14CAB43AFECF` |
| `tools/run_godot_tests.ps1 -TimeoutSeconds 60 -TestPaths tests/monster_world_integration_test.tscn` | **PASS 1/1**, engine log errors `0` |
| `tools/run_dpv2_final_gate.ps1` | **PASS**: `DPV2_FINAL_GATE_PASS blocker_count=0` |
| `git diff --check` | **PASS** |

## Closure handoff

The Package3C commit contains only these five authorized files: the direct
baseline manifest, direct runtime test, world integration test, and the two
reports. The final response must report the actual closure commit hash in place
of `FINAL_SHA: THIS_CLOSURE_COMMIT`; the placeholder is retained here because a
commit cannot embed its own SHA.
