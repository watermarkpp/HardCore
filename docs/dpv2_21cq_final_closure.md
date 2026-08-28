# DPV2-21CQ-X1-R1 Final Closure Record

Status: `CLOSED`

```text
PRECOMMIT_GATE_HEAD: 1f3cb1e767ddfe740562d7674ef6f11f6e6404cd
BASE_SHA: c1cfe8cf809d5047344060e9fe3ea06a9b9799f8
FINAL_SHA: THIS_CLOSURE_COMMIT
DPV2_FINAL_GATE_PASS blocker_count=0
```

This record is `CLOSED` only because the complete Package C gate passed with
zero blockers. `FINAL_SHA` remains a placeholder because a commit cannot
embed its own hash; the integration handoff must substitute the actual
closure commit.

## Frozen final accounting

```text
tracked logical source: 217 records / 9590 rows
canonical profiles: 156
runtime_allowed profiles: 153
drop-enabled profiles: 144
explicit NON_LOOT profiles: 9
runtime-disabled profiles: 3 (33, 183, 241)
compiled runtime: 6809 slots
runtime origins: 6740 LEGACY_21CQ_MONITEMS + 69 PROJECT_EXTENSION
explicitly excluded source rows: 223
retired source rows: 2558
reward = probability = RNG: 6809 = 6809 = 6809
```

The accounting is closed at `6740 + 69 + 223 + 2558 = 9590`. Explicitly
excluded and retired source rows do not enter the runtime RNG table. Mapping
and identity resolution is authoritative and unresolved count is `0`.

The frozen `BASE_SHA` is `c1cfe8cf809d5047344060e9fe3ea06a9b9799f8`, with
`5995` existing slots and slot hash
`2D70FB2A279BA4E9EA471BDAFA2A777AA4B899BFA70A76A3FE8055BFA4941A14`.
All `5995` existing slots are preserved with `drift=0`.

Restored parity is `814` rows: zombie `296` plus chest `518`. Compiled-subset,
restored x1, and preserved x1 mismatches are `0`; duplicate-slot collapse is
`0`.

Duplicate facts remain separate rather than being collapsed:

```text
source exact duplicate rows beyond first: 1657
old preserved baseline duplicate rows beyond first: 993
restored duplicate rows beyond first: 481
final compiled duplicate rows beyond first: 1138
duplicate_slot_collapse: 0
```

The post-RNG hard cap is `9`; every slot is rolled before overflow retention.
Protected-first ordering, descending overflow priority, stable tie handling,
protected-overflow telemetry, and the nine protected slots remain unchanged.

## Scope and dependency closure

`R2` is explicitly excluded from this gate and closure. A0.7 historical
artifacts and migration provenance are retained. The gate separately searches
current semantic inclusion in `14` builder/current-semantic/generated targets
and found `0`; this is not a claim that all historical A0.7 dependencies are
zero.

```text
DPV2_21CQ_X1_R1_SEMANTIC_CLOSURE_PASS: profiles=156 runtime_allowed=153 drop_enabled=144 explicit_non_loot=9 runtime_disabled=3 production_slots=6809 restored=814 existing_drift=0
DPV2_BASE_SHA_SLOT_IMMUTABILITY_PASS: base_slots=5995 preserved_slots=5995 drift=0
DPV2_RESTORED_X1_PARITY_PASS: restored=814 zombie=296 chest=518 compiled_subset_mismatch=0 restored_x1_mismatch=0 preserved_x1_mismatch=0 duplicate_slot_collapse=0
DPV2_RUNTIME_ALLOWED_PROFILE_GATE_PASS: profiles=156 runtime_allowed=153 enabled=144 explicit_non_loot=9 runtime_disabled=3
DPV2_PRODUCTION_LEGACY_DEPENDENCY_SEARCH_PASS: targets=2 current_runtime_matches=0 classifications=Tier,DropRole,role_factor,tier_factor,old_runtime_authority
DPV2_CURRENT_DROP_SEMANTIC_A07_DEPENDENCY_SEARCH_PASS: targets=14 current_semantic_inclusion_matches=0 historical_a07_retained=explicitly_historical_only
```

The production negative search covers `scripts/game_data.gd` and
`scripts/layers/runtime/loot_runtime_service.gd`. The A0.7 result is a current
semantic-inclusion result only; historical retention is intentional.

## Gate evidence

| Check | Exact result |
| --- | --- |
| Semantic authority validator / cross-authority gate | **PASS**: `156/153/144/9/3`, `6809`, restored `814`, drift `0` |
| Existing `BASE_SHA` 5995-slot immutability | **PASS**: preserved `5995`, drift `0` |
| Restored 814 x1 parity | **PASS**: zombie `296`, chest `518`, mismatch `0` |
| `runtime_allowed` profile gate | **PASS**: `156/153/144/9/3` |
| Python suite including R1 semantic test | **PASS 22/22** |
| Direct baseline builder `--check` | **PASS**: source `217/9590`, compiled `6809`, unresolved `0` |
| Canonical catalog `--check` | **PASS**: profiles `156`, runtime allowed `153`, drop rows `7032` |
| Source-priority verifier | **PASS**: `passed=true` |
| Production runtime legacy dependency search | **PASS**: current matches `0` |
| Current drop-semantic A0.7 dependency search | **PASS**: current inclusion matches `0`; historical retained |
| Direct Godot loader/runtime/policy/P1A/gold | **PASS 5/5**, engine log errors `0` |
| Fresh P1A export/analyzer | **PASS**: `MONSTER_DROP_P1A_ALL_PASS`, analyzer `8/8`, Godot `2/2` |
| Deterministic P1A audit | **PASS**: snapshot `F8A1E47087EE142934660BCF214FC9F615E4605B7D90ECACE3A68C8E1609C492`, blockers `0` |
| World integration | **PASS 1/1**, engine log errors `0` |
| Final gate | **PASS**: `DPV2_FINAL_GATE_PASS blocker_count=0` |
| `git diff --check` | **PASS** |

The P1A audit also reported source `156/7032/6809/223/1`, semantic origins
`6740+69+223+2558`, compiled `156/153/144/9/3/6809`, and deterministic `PASS`.
No engine error markers were reported by the fresh P1A exporter/analyzer or
audit; the direct and world Godot runner summaries explicitly reported zero.

## Handoff

Package C modifies only the owned final-gate script and these two closure
reports. No gameplay stable IDs change and no R2 source is integrated. The
integration handoff must record the actual commit SHA in place of
`THIS_CLOSURE_COMMIT`, preserve unrelated worktree changes, and rerun the gate
at the resulting integrated HEAD if other commits are added.
