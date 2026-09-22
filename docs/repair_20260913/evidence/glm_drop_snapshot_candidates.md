RESULT: CANDIDATE_EVIDENCE — based only on supplied script/output/code excerpts; no independent filesystem read or test execution.

COUNTS:
- Authority/current baseline: profiles=156, slots=7611, effective=7611, provenance=7611, classes=233.
- Runtime allowed=153, drop enabled=144.
- Legacy logical source census expected 217/9590.
- Report rule counts: NONE=7131, BOOK_ELITE_BOSS=325, BOOK_ORDINARY=149, ARMOR_BASE_1_OVER_60=6.
- Elite/boss potion slots=1289.
- Controller report status=PASS; errors=[].

MATCHES:
- slots == effective_records == provenance_records == 7611.
- Profile count 156 consistent with `profiles` array.
- Rule count sum: 7131+325+149+6 = 7611.
- Manifest hash entries supplied all show actual == expected.
- Preservation entries all report `equal:true`, with each declared `unchanged_except`.
- `probability_policy.post_rng_ground_slot_limit` expected 15.
- Runtime service reads ground limit through `GameData.dpv2_ground_slot_limit()`.

MISSING:
- Full JSON field-level rows beyond supplied compact output are not available, so exact per-slot fraction verification cannot be independently recomputed here.
- Source-priority/order/priority is not independently auditable from supplied output beyond script contract and potion `priority=200` samples.

DUPLICATES:
- No duplicate evidence supplied in errors; script checks unique `slot_uid`, monster IDs, profile IDs, canonical item IDs, provenance IDs.

MISMATCHES:
- `assets/data/source_accounting/dpv2_21cq_source_accounting.json` (or equivalent semantic source accounting) may retain pre-V505 6809 while current direct baseline uses 7611.
- `tests/dpv2_21cq_direct_runtime_test.gd` lines 61–72 still assert 6809 slot counts, 153 runtime-allowed, 144 drop-enabled, and `maximum_ground_slots == 9`, conflicting with current authority 7611 slots and ground cap 15.

TOP CANDIDATES:
- Stale 9-slot reference: `tests/dpv2_21cq_direct_runtime_test.gd:72`.
- Stale 6809 references: `tests/dpv2_21cq_direct_runtime_test.gd:61-65,67`.
- Stale cap=9 reference: whatever source authority `dpv2_21cq_overflow_authority_v1.json` or its semantic/accounting consumer feeds; script note says “inactive overflow seed retains cap=9”.
- Production path for cap=15: `assets/data/drop/dpv2_direct_baseline_v2.json` via `probability_policy.post_rng_ground_slot_limit` and `scripts/game_data.gd:3266-3273`.

POTION EVIDENCE:
- Elite/boss solar water runtime halving is present: `scripts/layers/runtime/loot_runtime_service.gd:616-621`, multiplier 2 at `loot_runtime_service.gd:7`.
- Examples: monster 31/32 item 920014 base 1/2, effective 1/2, runtime_draw 1/4; monster 38/56/73 item 920014 base 1, effective 1, runtime_draw 1/2; monster 38/56/73 item 920016 same pattern; monster 38/42/56/73/89/91/120/122/124/135/141/143/159/160/162/163/180/188/189/191/192/193/195/198/199/208/209/224/235–240 all have elite/boss potion evidence supplied in grouped output.
- Small-monster 神水 multiplier is also present at `loot_runtime_service.gd:16-22` and `loot_runtime_service.gd:625-636`; its runtime correctness is outside elite/boss potion evidence supplied here.

EVIDENCE PATHS:
- `tools/audit_current_drop_tables.py`
- `outputs/test_logs/current_drop_static_audit.json`
- `assets/data/drop/dpv2_direct_baseline_v2.json`
- `assets/data/drop/dpv2_single_player_drop_boost_v1.json`
- `assets/data/drop/dpv2_single_player_effective_probability_v1.json`
- `assets/data/drop/dpv2_direct_baseline_manifest_v2.json`
- `assets/data/drop/dpv2_21cq_verified_profile_authority_v1.json`
- `assets/data/drop/dpv2_21cq_source_provenance_v1.json`
- `docs/repair_20260913/evidence/drop_preservation.json`
- `scripts/layers/runtime/loot_runtime_service.gd`
- `scripts/game_data.gd`
- `tests/dpv2_21cq_direct_runtime_test.gd`

UNCERTAINTIES:
- Cannot verify potion order or ground overflow selection ordering from supplied data.
- Cannot distinguish intentional legacy references from actual stale assertions without production-path interpretation.
- Cannot confirm exact accounting file path for 6809 reference because it is not supplied as a path in the input.
- Cannot validate all 233 item classifications or every individual slot fraction beyond what the script output claims.