# DPV2-21CQ-X1 Phase 1 Import Audit

Status: `SOURCE_AUDIT_CLOSED / PRODUCTION_STILL_V1`

## Source identity

- Physical raw `MonItems` files tracked in Git: `0`.
- Reproducible tracked logical source: `assets/data/canonical_monster_drop_source_v2.json`.
- Logical monster records: `217`.
- Logical meaningful source rows: `9590`.
- Tracked encoding: `UTF-8 JSON`.
- Physical MonItems encoding: `NOT_AVAILABLE_IN_GIT`; it cannot be inferred from the derived JSON.
- Tracked source raw SHA-256: `59338A7E5CAACCC82661E942908CAEA0A4A06CF56402961E4C3E55FB123E4013`.
- Tracked source LF-normalized SHA-256: `1A0BE3AFB28628F14E2C7F30EA08856301BB5D9E152B62CE6D1AEF47D9AB1BD5`.
- Recorded upstream workbook SHA-256: `6902A37DB839577D2CE440B9EFDC4628430CF063BF9DF505F03B41E24A5D67EE`.

The direct source is described as `LEGACY_21CQ_MONITEMS`, not as an official
Shanda/Shengqu table. The tracked JSON is a logical, user-locked reconstruction;
this report does not claim that physical MonItems files exist in the repository.

## Structural closure

| Metric | Count |
| --- | ---: |
| available records | 206 |
| confirmed no-drop records | 1 |
| no-MonItems records | 10 |
| zero-slot records | 11 |
| meaningful source rows | 9590 |
| parsed rows after explicit correction | 9590 |
| invalid source probability tokens | 1 |
| explicitly corrected rows | 1 |
| uncorrected invalid rows | 0 |
| duplicate item groups within a monster | 493 |
| duplicate item rows beyond first | 1906 |
| exact duplicate groups within a monster | 542 |
| exact duplicate rows beyond first | 1657 |

Every logical row remains an independent row. Duplicate counts are audit facts;
no row is merged and no aggregate probability is calculated.

## Explicit probability correction

The source contains exactly one malformed probability token:

| monster_id | monster | source line | slot | item | source | frozen correction |
| ---: | --- | ---: | --- | --- | --- | --- |
| 168 | 月魔蜘蛛 | 20 | slot_020 | 灵魂战衣(男) | `1/00` | `1/2800` |

The tracked historical row is not rewritten. The externally verified correction is recorded in
`assets/data/drop/dpv2_21cq_source_corrections_v1.json`, with evidence URL,
retrieval date, exact slot identity and original value. Silent correction and
silent skipping are forbidden.

## Accounting gate

```text
meaningful_source_rows = 9590
parsed_rows_after_explicit_correction = 9590
uncorrected_invalid_probability_rows = 0
```

No Production Runtime, canonical catalog, current Tier/Role Authority or actual
drop probability was changed in this phase.
