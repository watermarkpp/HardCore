# DPV2-21CQ-X1 Phase 3 x1 Side-by-Side Parity Report

Status: `DATA_PARITY_PASS / CUTOVER_NOT_STARTED / PRODUCTION_STILL_V1`

## Result

The V2 side-by-side artifact compiles direct per-slot x1 probabilities for all
currently drop-enabled monsters. It does not activate the V2 loader or Runtime.
Current Production remains on the existing V1 Tier/Role chain, and the tracked
7032 source-slot catalog is unchanged.

| Gate | Result |
| --- | ---: |
| active canonical monsters | 156 |
| drop-enabled monsters | 131 |
| explicit NON_LOOT monsters | 25 |
| compiled direct slots | 5995 |
| LEGACY_21CQ_MONITEMS slots | 5926 |
| PROJECT_EXTENSION slots | 69 |
| monster mapping unresolved | 0 |
| compiled item mapping unresolved | 0 |
| invalid compiled numerator/denominator | 0 |
| x1 probability mismatch | 0 |
| duplicate slot collapse | 0 |
| preserved exact duplicate rows beyond first | 993 |

## Full 9590-row disposition ledger

| Disposition | Rows |
| --- | ---: |
| LEGACY_21CQ_COMPILED | 5926 |
| PROJECT_EXTENSION_COMPILED | 69 |
| NON_LOOT_EXCLUDED | 1037 |
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

This phase provides data and tests only. Runtime activation, loader switching and
the global scale implementation remain future cutover work.
