# Formal Spatial Read Lane Result — 2026-10-09

## Scope and evidence boundary

This report archives the frozen research candidate from the working tree based on `edae6fdef6a6551a951fab1ea8c6ade43359d603`, the two complete 30-engaged windows, and all UUID receipts already present in MAIN. No test or build was rerun for this report. The archived candidate source is a source-stage snapshot; it is not merged with older direct-contract results into a single-source acceptance claim.

The archived source snapshot contains the candidate production files and direct fixtures listed below. The manifest additionally retains both full-load fixture layers, RuntimeDiagnostics and the stock runner (14 files total):

| Path | SHA-256 |
|---|---|
| `scripts/enemy.gd` | `AE3CC1A6D21D8C1AAF834C7B8E288E9B387A15D8717EBDFB37719FB252A1F746` |
| `scripts/game_root.gd` | `CC8149C3D38A8EE53EB96DE4112A9338250D1A5409CCFC9256DCD90BBC22228D` |
| `scripts/runtime_combat_spatial_index.gd` | `1FA26F141042DA16FC3CADC15BF329298212BDD5466DEBE96E282FDDB084F081` |
| `scripts/layers/runtime/spatial/formal_spatial_read_binding.gd` | `363736A8890C12C8701C8D8D093E344070158BF7AFAFD17786BEC6C8ED63582A` |
| `tests/formal_spatial_read_lane_contract_20261009.gd` | `6329321A3FFC68ABAB612F6032B81CF0A8AEFEFC2F4B54351FE57175835E1339` |
| `tests/formal_spatial_read_lane_contract_20261009.tscn` | `9CA5EF0C104BDA79CFBD2CED21CAFF2AA353C870DB5C24B9CA1413DDB5DF7645` |
| `tests/formal_spatial_binding_contract_20261009.gd` | `5651A048BD7FB205608426B483D0286BBE54198A2522670EE1F22C0004CF5C2A` |
| `tests/formal_spatial_binding_contract_20261009.tscn` | `9473D685A95BB40DF1F4D44E49191FA8B77817F506D3BECF6D07B4D9353165DD` |

The complete source manifest is [candidate_current_research.json](../../../outputs/crowd_formal_spatial_read_lane_20261009/final_evidence/source_snapshot/candidate_current_research.json). The two raw report hashes are `formal_read_lane_30_01.json` `354ADDCE3C58CAA2E68629EDBE6C38F7309725DA3D2B93CB4A62E409D026523B` and `formal_read_lane_30_02.json` `E580514025395488898BA5AE33C3FDB6E47E3D55B5226D1FF040008D868A8401`.

## Complete-window measurements

Both windows used the same formal fixture contract: 34 formal actors, 30 engaged actors, 4 background actors, 48 requested/ending loot pickups, map `913203`, 300 real physics ticks, and 10,200 enemy physics callbacks. Both raw reports and their native receipts recorded `PASS`; the performance target is evaluated separately below.

| Window | Enemy physics CPU | Process CPU p50/p95/max | Physics CPU p50/p95/max | Frame interval p50/p95/max | Alive / engaged / loot | Moving / player motion | Decision queue |
|---|---:|---:|---:|---:|---|---|---|
| `formal_read_lane_30_01` | 2,401,620 us | 1.112 / 3.525 / 3.525 ms | 8.106 / 11.077 / 15.767 ms | 4.554 / 16.421 / 23.051 ms | 34 / 30 / 48 | 29 distinct, 22 ending, 3.112343 GU, 121 moving ticks | admitted 1170, queue length 0, open scopes 0, max wait 2 frames |
| `formal_read_lane_30_02` | 2,378,087 us | 0.946 / 1.099 / 1.099 ms | 8.070 / 10.871 / 13.502 ms | 4.605 / 16.663 / 19.392 ms | 34 / 30 / 48 | 29 distinct, 23 ending, 2.776453 GU, 114 moving ticks | admitted 1165, queue length 0, open scopes 0, max wait 2 frames |

The two-window median enemy physics CPU is `2,389,853.5 us` (`2,389.8535 ms`). The fixed107 comparison median is `2,057.2785 ms`; the formal read lane is therefore `+16.165%` slower. The requested 50% reduction target is **FAIL**. This comparison reports the complete measured metrics, trajectory indicators, and queue state; the changed values are not attributed to a pure causal bridge cost.

The trajectory evidence also includes the 10-step real gameplay movement input schedule, player motion totals above, per-tick actor movement/targeting/physics samples, and final monster census in each raw report. Both windows ended with 34 alive actors, 30 targeting the player, 16 attack starts, player HP end 168, and no grid-trial failures. Queue-related counters remained zero for drop/death/presentation overflow paths; the decision queue was empty at receipt.

## Contract and regression evidence

| Evidence slice | Status | Binding |
|---|---|---|
| Formal read lane runner receipts for both complete windows | **PASS** | `formal_read_lane_30_01` UUID `9b6fa0ec-07fb-4894-be89-adbc9d2f7b52`; `formal_read_lane_30_02` UUID `c31b4e55-544a-4bc3-8211-545e4fd8cea7`; native exit `0`; test scene `tests/crowd_formal_grid_comparison_20261008.tscn` |
| Provider direct contract (`direct_02`) | **PASS** | UUID `f77bcda6-77f7-4c40-b6c2-ef82bed3b561`; native exit `0` |
| Consumer direct contract (`consumer_direct_04`) | **PASS** | UUID `6c9ff207-c9b1-439c-bf4a-3869481954f6`; native exit `0` |
| Nine related regressions (`related_regression_01`) | **PASS** | UUID receipts preserved in the archive; each native exit `0` |
| Earlier availability/direct attempts | **FAIL** | All earlier FAIL receipts remain archived; they are not overwritten by later evidence |
| Same-source integration proof joining direct contracts, both full windows, and regressions | **MISSING** | Results span source stages and are deliberately not combined |
| Exact historical command line and producer handoff metadata | **MISSING** | UUID receipts, logs, test paths, engine log, and native exit are preserved; receipt producer/command fields were absent |

The engine identity recorded in the native logs is Godot `4.7.stable.official.5b4e0cb0f`, with the Windows runtime profile shown in the receipts. The full UUID receipt archive, including stdout/stderr/Godot logs, native handoffs, native exits, source-stage attempts, and the nine regression receipts, is indexed by [receipt_index.json](../../../outputs/crowd_formal_spatial_read_lane_20261009/final_evidence/receipt_index.json).

## Decision

The formal spatial read lane hypothesis is **retired**. The measured complete windows are runner **PASS** but miss the 50% performance goal (**FAIL**) and are 16.165% slower than the fixed107 median. Direct provider and consumer contracts and the nine regressions are retained as their own **PASS** evidence; they do not establish a same-source all-pass result. Production restoration is a separate root-owned action and is not performed or claimed here.

## Delivery and unresolved items

- Evidence archive: `C:\Users\Administrator\Documents\HardCore\outputs\crowd_formal_spatial_read_lane_20261009\final_evidence\`
- Source snapshot and manifest: `final_evidence\source_snapshot\candidate_current_research\` and `candidate_current_research.json`
- Raw reports: `final_evidence\raw_reports\formal_read_lane_30_01.json`, `formal_read_lane_30_02.json`
- Receipt index and complete UUID receipts: `final_evidence\receipt_index.json` and `final_evidence\receipts\`
- Archive inventory SHA-256: `98455ED0C3B966B057F1830649A8D9AB4877C3ACCBDB8425CE7458AB8988B4B8`
- Report scope: archive and evidence reconciliation only; no tests, builds, source restoration, staging, commit, or push performed.
- Unresolved: same-source integration acceptance is **MISSING**; performance goal is **FAIL**; device evidence is **NOT_RUN**.


## Root retirement receipt

The five research production files have now been restored byte-for-byte to stock107; RESTORATION.json records before/after hashes. Main integration production and index remain preserved. The final archive adds eight stock-runner receipts with invocation IDs, actual engine hashes, and explicitly reconstructed session commands. Historical framework producer linkage remains MISSING (generic runner producers were empty); no receipt was retrofitted. New helper and direct fixtures remain research material, unloaded by restored production. No repeated test or device run was performed.
