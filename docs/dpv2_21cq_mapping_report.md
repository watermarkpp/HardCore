# DPV2-21CQ-X1 Phase 2 Mapping Report

Status: `MAPPING_AUTHORITY_CLOSED / CUTOVER_NOT_STARTED / PRODUCTION_STILL_V1`

## Monster mapping

| Metric | Count |
| --- | ---: |
| logical source monsters | 217 |
| active canonical monsters | 156 |
| drop-enabled active monsters | 131 |
| explicit NON_LOOT monsters | 25 |
| EXACT mappings | 191 |
| EXPLICIT_ALIAS mappings | 0 |
| PROJECT_EXTENSION mappings | 1 |
| NON_LOOT mappings | 25 |
| UNRESOLVED mappings | 0 |

All joins use the already-frozen stable `monster_id`. No name, suffix, map,
class, Role or approximate matching is used. Monster 225 is explicitly
`PROJECT_EXTENSION`; its 69 source-artifact rows are frozen as project-owned
direct rules and are not represented as 21CQ legacy provenance.

The 25 existing NON_LOOT decisions are explicit and expose
`drop_enabled=false, drop_profile_id=null`. Their 1037 logical source rows remain
in the disposition ledger but are not compiled into V2 production slots.

## Source row disposition ledger

| Disposition | Rows |
| --- | ---: |
| LEGACY_21CQ_COMPILED | 5926 |
| PROJECT_EXTENSION_COMPILED | 69 |
| NON_LOOT_EXCLUDED | 1037 |
| RETIRED_OUT_OF_RUNTIME | 2558 |
| total | 9590 |

## Item mapping

| Metric | Count |
| --- | ---: |
| source labels including gold | 244 |
| canonical item IDs covered | 233 |
| EXACT labels | 227 |
| EXPLICIT_ALIAS labels | 11 |
| GOLD_REWARD_KIND labels | 1 |
| RETIRED_SOURCE_ONLY_NOT_IN_CANONICAL_CATALOG labels | 5 |
| UNRESOLVED labels | 0 |

Compiled item slots will carry only a positive `canonical_item_id`; Runtime
name lookup is forbidden. Gold remains a separate reward kind with a positive
amount and no canonical item ID.

### Retired-source-only labels

These labels are real UTF-8 source labels, not aliases or mojibake in the
tracked JSON. They occur only on `RETIRED_OUT_OF_RUNTIME` monsters and have no
identity in the formal 233-item catalog. No canonical mapping is invented and
none of these rows is compiled.

| source label | proposed canonical item | exact source evidence |
| --- | --- | --- |
| 神水 | none | ID 17 鹿1 line 1 `1/3 神水`; RECOVERED_OR_CROSSCHECKED_SLOTS; `GitHub/21cq/同SHA或老编码恢复 :: 鹿1`<br>ID 23 稻草人1 line 4 `1/6 神水`; EXISTING_AUDITED_SLOTS; `https://www.21cq.com/mir/Mob.aspx?id=23` |
| 血饮 | none | ID 167 血僵尸0 line 16 `1/500 血饮`; GITHUB_MONITEMS_PRIMARY; `mrzhqiang/mirserver-1.76 :: Mir200/Envir/MonItems/血僵尸0.txt` |
| 鸡肉 | none | ID 14 鸡 line 1 `1/1 鸡肉`; RECOVERED_OR_CROSSCHECKED_SLOTS; `GitHub/21cq/同SHA或老编码恢复 :: 鸡` |
| 鹿茸 | none | ID 17 鹿1 line 2 `1/1 鹿茸`; RECOVERED_OR_CROSSCHECKED_SLOTS; `GitHub/21cq/同SHA或老编码恢复 :: 鹿1` |
| 鹿血 | none | ID 16 鹿 line 3 `1/10000 鹿血`; RECOVERED_OR_CROSSCHECKED_SLOTS; `GitHub/21cq/同SHA或老编码恢复 :: 鹿` |

## Post-RNG overflow Authority

- Explicit per-item records: 233.
- Protected item records: 94.
- Priority counts: `{"1000": 2, "200": 14, "300": 125, "600": 79, "800": 13}`.
- Gold is explicit priority `100`, unprotected.

The migration used the old retained-value decisions once, then froze direct
per-item values. The new Authority contains no Tier, Drop Role, factor or
probability denominator. `overflow_priority` and `protected_drop` have no
probability effect and apply only after all independent slot RNG draws.

## Gate

```text
monster_mapping_unresolved = 0
item_mapping_unresolved = 0
source_disposition_sum = 9590
CUTOVER = NOT_STARTED
Production = V1
```
