# DPV2-21CQ-X1-R1 Compiled-Subset Parity Report

Status: `COMPILED_SUBSET_PARITY_PASS / PRODUCTION_CURRENT_V2_DIRECT_BASELINE`

## Result

The direct baseline compiles the production subset of the tracked source: every
eligible source identity uses direct per-slot x1 probabilities, while explicit
non-loot rows remain in provenance and runtime-disabled identities remain empty.
Current production is the V2 direct baseline; no Tier/Role calculation is part
of this artifact, and the canonical 7032 source-slot catalog is unchanged.

| Gate | Result |
| --- | ---: |
| active canonical monsters | 156 |
| catalog runtime_allowed profiles | 153 |
| drop-enabled monsters | 144 |
| explicit NON_LOOT monsters | 9 |
| runtime-disabled monsters | 3 |
| compiled direct slots | 6809 |
| LEGACY_21CQ_MONITEMS slots | 6740 |
| PROJECT_EXTENSION slots | 69 |
| monster mapping unresolved | 0 |
| compiled item mapping unresolved | 0 |
| invalid compiled numerator/denominator | 0 |
| x1 probability mismatch | 0 |
| duplicate slot collapse | 0 |
| restored exact independent slots | 814 |
| restored x1 probability mismatch | 0 |
| existing BASE_SHA slot drift | 0 |
| preserved exact duplicate rows beyond first | 1138 |

## Full 9590-row disposition ledger

| Disposition | Rows |
| --- | ---: |
| LEGACY_21CQ_COMPILED | 6740 |
| PROJECT_EXTENSION_COMPILED | 69 |
| EXPLICIT_NON_LOOT_EXCLUDED | 223 |
| RETIRED_OUT_OF_RUNTIME | 2558 |
| total | 9590 |

Every source row has a unique provenance ID. Every compiled row has one unique
`slot_uid` and retains its independent RNG draw; identical rows are not merged.

## Direct x1 probability contract

At x1, each compiled slot uses exactly:

```text
P(slot success) = base_numerator / base_denominator
global_drop_rate_scale = 1.0
```

No Monster Role factor and no Item Tier denominator participates. Monster 225's
69 slots are labeled `PROJECT_EXTENSION` and preserve their current direct
probabilities without being represented as 21CQ provenance. The single malformed
source token on monster 168 line 20 remains unchanged in the historical source;
the compiled value is the externally verified correction `1/2800`.

## Nine-slot behavior represented by the Authority

All slots are intended to complete RNG first. Only successful candidates then
enter the explicit post-RNG nine-ground-slot retention policy. Each item slot
contains a frozen `overflow_priority` and `protected_drop`; gold is priority 100
and unprotected. These fields cannot alter probability.

The semantic partition is independently frozen at 156
profiles / 153 runtime-allowed /
144 drop-enabled / 9
explicit non-loot / 3 runtime-disabled.
