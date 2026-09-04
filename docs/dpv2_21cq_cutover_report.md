# DPV2-21CQ-X1-R1 Package C Final Cutover Report

Status: `CLOSED`

This report is the Package C final-gate record. It is `CLOSED` because the
formal gate ran from the current precommit HEAD and completed with zero
blockers. The closure commit is deliberately represented by a placeholder
until the commit exists.

```text
PRECOMMIT_GATE_HEAD: 1f3cb1e767ddfe740562d7674ef6f11f6e6404cd
BASE_SHA: c1cfe8cf809d5047344060e9fe3ea06a9b9799f8
FINAL_SHA: THIS_CLOSURE_COMMIT
```

## Gate decision

```text
DPV2_FINAL_GATE_PASS blocker_count=0
```

The gate now requires, in order, a semantic-authority/cross-authority
validator, existing `BASE_SHA` slot immutability, restored 814-row x1 parity,
the `runtime_allowed` profile partition, the complete Python suite including
the R1 semantic test, direct-baseline builder `--check`, canonical catalog
`--check`, source-priority verification, production-runtime legacy dependency
search, a separate current drop-semantic A0.7 dependency search, direct
Godot loader/runtime/policy/P1A/gold coverage, fresh P1A export and
deterministic audit, world integration, and `git diff --check`. A gate is
successful only when `blocker_count=0`.

`R2` is explicitly excluded from this Package C gate. A0.7 historical
material is retained as historical/migration evidence. The current semantic
inclusion search is a separate scoped check and found zero dependencies; this
does not claim that every historical A0.7 artifact has zero dependencies.

## Final accounting

| Authority view | Result |
| --- | ---: |
| Tracked logical source | `217` records / `9590` rows |
| Canonical profiles | `156` |
| `runtime_allowed` profiles | `153` |
| Drop-enabled profiles | `144` |
| Explicit NON_LOOT profiles | `9` |
| Runtime-disabled profiles | `3` (`33`, `183`, `241`) |
| Compiled runtime slots | `6809` |
| Runtime origins | `6740` `LEGACY_21CQ_MONITEMS` + `69` `PROJECT_EXTENSION` |
| Explicitly excluded source rows | `223` |
| Retired source rows | `2558` |
| Reward / probability / RNG rows | `6809 / 6809 / 6809` |

The source accounting is exact: `6740 + 69 + 223 + 2558 = 9590`. The
explicitly excluded rows and retired rows are not runtime RNG slots. The
canonical catalog remains the identity authority; no unresolved monster or
item mapping is accepted.

## Frozen baseline and restored parity

The existing `BASE_SHA` freeze is `c1cfe8cf809d5047344060e9fe3ea06a9b9799f8`.
It contains `5995` frozen slots with slot hash
`2D70FB2A279BA4E9EA471BDAFA2A777AA4B899BFA70A76A3FE8055BFA4941A14`.
The current baseline preserves all `5995` slot UIDs with `drift=0`.

The restored subset is `814` rows: zombie restoration is `296` and chest
restoration is `518`. The compiled-subset mismatch, restored x1 mismatch,
preserved x1 mismatch, and duplicate-slot collapse are all `0`. The final
compiled count is `6809`.

```text
DPV2_BASE_SHA_SLOT_IMMUTABILITY_PASS: base_slots=5995 preserved_slots=5995 drift=0
DPV2_RESTORED_X1_PARITY_PASS: restored=814 zombie=296 chest=518 compiled_subset_mismatch=0 restored_x1_mismatch=0 preserved_x1_mismatch=0 duplicate_slot_collapse=0
```

Source/compiled duplicate evidence is kept distinct and no rows are
collapsed: source exact duplicate rows beyond first `1657`, old preserved
baseline rows `993`, restored rows `481`, final compiled rows `1138`, and
`duplicate_slot_collapse=0`. Every runtime row retains its own provenance and
`slot_uid`.

The post-RNG hard cap remains `9`. Every candidate slot is rolled before
overflow retention; protected-first ordering, descending priority, stable
tie handling, and protected-overflow telemetry remain unchanged. The nine
protected slots and all protected-slot data are unchanged.

## Semantic and runtime dependency closure

The semantic validator and profile gate jointly enforce the cross-authority
partition:

```text
DPV2_21CQ_X1_R1_SEMANTIC_CLOSURE_PASS: profiles=156 runtime_allowed=153 drop_enabled=144 explicit_non_loot=9 runtime_disabled=3 production_slots=6809 restored=814 existing_drift=0
DPV2_RUNTIME_ALLOWED_PROFILE_GATE_PASS: profiles=156 runtime_allowed=153 enabled=144 explicit_non_loot=9 runtime_disabled=3
```

The classified production-runtime search covered the two current consumers,
`scripts/game_data.gd` and `scripts/layers/runtime/loot_runtime_service.gd`:

```text
DPV2_PRODUCTION_LEGACY_DEPENDENCY_SEARCH_PASS: targets=2 current_runtime_matches=0 classifications=Tier,DropRole,role_factor,tier_factor,old_runtime_authority
```

The separate current drop-semantic A0.7 search covered `14` builder,
current-semantic, and generated-artifact targets:

```text
DPV2_CURRENT_DROP_SEMANTIC_A07_DEPENDENCY_SEARCH_PASS: targets=14 current_semantic_inclusion_matches=0 historical_a07_retained=explicitly_historical_only
```

The second result is scoped to current semantic inclusion only. Historical A0.7
files and migration provenance remain retained and are not misreported as a
repository-wide historical dependency-zero result.

## Exact validation results

| Step / command | Result |
| --- | --- |
| `py -3.12 tools/validate_dpv2_21cq_x1_r1_semantic_closure.py --check` | **PASS**: `156/153/144/9/3`, `6809` slots, restored `814`, existing drift `0` |
| Existing `BASE_SHA` slot immutability | **PASS**: `5995` frozen and preserved slots, drift `0` |
| Restored 814 x1 parity | **PASS**: zombie `296`, chest `518`, all requested mismatches `0` |
| `runtime_allowed` profile gate | **PASS**: `156/153/144/9/3` |
| `py -3.12 tools/build_dpv2_21cq_direct_baseline.py --check` | **PASS**: `217` logical records, `9590` source rows, corrected `1`, unresolved `0`, compiled `6809`, x1 mismatch `0` |
| `py -3.12 tools/build_canonical_monster_catalog.py --check` | **PASS**: identities `156`, runtime allowed `153`, drop rows `7032`, authoring rows `0` |
| `py -3.12 tools/verify_source_priority_policy.py` | **PASS**: JSON `passed=true` |
| Python suite (source audit, mapping, direct baseline, R1 semantic closure) | **PASS 22/22** |
| Production-runtime legacy search | **PASS**: current runtime matches `0` |
| Current drop-semantic A0.7 search | **PASS**: current semantic inclusion matches `0`; historical A0.7 retained |
| Direct Godot loader/runtime/policy/P1A/gold tests | **PASS 5/5**, engine log errors `0` |
| Fresh `tools/run_monster_drop_p1a.ps1` | **PASS**: `MONSTER_DROP_P1A_ALL_PASS`, analyzer `8/8`, Godot `2/2` |
| Fresh `tools/run_monster_drop_p1a_audit.ps1` | **PASS**: deterministic snapshot `F8A1E47087EE142934660BCF214FC9F615E4605B7D90ECACE3A68C8E1609C492`, blockers `0` |
| World integration test | **PASS 1/1**, engine log errors `0` |
| `tools/run_dpv2_final_gate.ps1` | **PASS**: `DPV2_FINAL_GATE_PASS blocker_count=0` |
| `git diff --check` | **PASS** |

## Stable IDs and handoff

Existing stable IDs are unchanged: `dpv2.direct_baseline.manifest.v2`,
`hardcore.dpv2.direct_baseline.v2`, `dpv2.global_drop_rate_scale.v1`,
profiles `dpv2.direct.<canonical_monster_id>`, and source slots
`dpv2.source.<monster_id>.slot_<nnn>`. Package C adds no gameplay IDs and has
no cross-system runtime wiring requirement; integration only needs to accept
the gate/report commit and replace `FINAL_SHA` in the external handoff with
the actual commit SHA. No R2 source or historical A0.7 artifact is promoted
by this package.
