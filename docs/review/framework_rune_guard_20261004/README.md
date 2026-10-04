# Future ownership / extraction guard increment

2026-10-04. Parent review commit: `37612de204c42fe3b4fd6a89137e90f3449bc0c2`.
Construction tree remains `codex/pluggable-framework-v2` at `5d9ceb0121980ca9636d9d1cc2e19982949fbf63` with preserved dirty work. This is a tested content snapshot, not a claim that a clean checkout of the construction HEAD was tested.

Final tested content SHA256: `8d6d10f179f364584f0928cb76f16d45b777fe4019b6a8ce1aff7b9821bcd812` (3722 source/config/test files). Four final groups: 42 unique PASS scenes, 38 complete framework receipts, 2150 checks. All final native exits are 0; no timeout. Earlier failures remain FAIL in the original records.

## Production changes and native counterexamples

1. `scripts/items/item_extension_codec.gd`: recognize explicit future Rune/Gem owner contracts and unknown Rune identities before interpreting current container/base/runtime fields. Preserve `OPAQUE_UNSUPPORTED` as terminal. Current known v1 malformed extra fields still produce `INVALID` and retain the existing valid-backup recovery behavior. No new writer or save authority.
   - Valid isolated RED: `rune_future_order_isolated_red_110329_137699`, 754 checks / 117 FAIL, native exit 1. Healthy account preflight controls pass before the sole future item is injected.
   - GREEN: `rune_future_order_green_110544_039654`; final direct group also passes all 754 checks.
   - Coverage includes 21 future candidates, independent profile/shared preflight and actual load, corrupted sibling field mixtures, unchanged raw primary/backup bytes, and known-v1 invalid recovery controls. The production warehouse validator can report the shared path when it encounters a profile item while validating migration inputs; the fixture proves a healthy baseline, sole changed input and terminal unchanged bytes, rather than asserting the wrong path.

2. `scripts/player_state.gd`: reject destruction of a transaction-reserved extraction destination before `_before_state_transaction()` drains the pending writer. Cover an existing empty slot and a destination beyond current inventory length, and retain the existing record reservation check. Negative indices retain normal invalid-selection behavior.
   - Valid RED: `rune_remove_destination_owned_red_111046_543026`, 119 checks / 38 FAIL, native exit 1. Six controlled real Port/writer cases actually finish the pending extraction and destroy its result; mixed cases also destroy the unrelated selected item. This is a controlled production API counterexample, not an OS/UI reproduction.
   - GREEN: `rune_remove_destination_green_111208_701022`; final direct group passes all 119 checks.
   - Rune/Gem x empty/append/mixed: refusal leaves inventory/equipment/journal, one original pending job, primary/backup bytes and unrelated records unchanged. The original writer then succeeds once; extracted output and the other embedded namespace survive reload; cached original quote replay adds no job or output.

## Actual native isolation association

`tools/run_godot_tests.ps1` records the exact APPDATA it sets, project path, runner PID and launch timing. `tests/framework/helpers/check_receipt.gd` records actual native `OS.get_environment("APPDATA")`, `OS.get_user_data_dir()`, project root and process ID. These are test evidence fields, not gameplay or persistence authority.

`FINAL_RUN_ASSOCIATION.json`, `FINAL_TEST_GROUPS.json` and `launches/` preserve the owned driver request, wrapper/handoff/invocation association and native receipts for four distinct owned account roots. All 38 framework receipts have actual native root/process/run associations; the other four scenes have wrapper environment/launch evidence but do not emit that native framework environment receipt. Seed/cold/restart within their group share the intended root and successful-producer handoff. The parent increment's historical environment association remains MISSING; this rerun proves the current source, not guessed historical environment values.

Final groups (full commands and native identities in `RUN_INDEX.json`):

- `rune_guard_final_direct_111614_807975`: 30 scenes, timeout 30s.
- `rune_guard_final_journal_single_112056_139794`: one recovery matrix, timeout 60s.
- `rune_guard_final_journal_chain_112120_965820`: three seed/cold/restart scenes, timeout 30s.
- `rune_guard_final_world_112158_737678`: eight world/credit/resource live/cold scenes, timeout 60s.

## Dormant child-chain preparation

`child_capacity_proof.gd` computes a bounded conservative complete-chain cost without a huge generation loop or overflow. Pure test: 29 checks. `death_burst_handler.gd` produces one closed immutable child request from a valid first committed death and finite accepted lineage, preserving credit/origin/identity and RNG. Pure test: 28 checks. Its descriptor is deliberately absent from the publishable handler IDs/contracts; Root and EffectRuntime do not execute it yet. No production child chain, complete capacity admission, new gameplay cap or damage has been enabled by these probes.

The next actual work remains the unique planner/HP production integration, direct/periodic/child fact ownership, full accepted capacity and root retirement. See `docs/source176_r3/CHILD_CHAIN_PLAN_20261004.md`.

## Evidence and boundaries

`SCOPED_EVIDENCE.json`, `SOURCE_MANIFEST.json`, `GIT_TESTED_SOURCE_MAP.json`, `NATIVE_MANIFEST.json` and `RUN_INDEX.json` bind final tested bytes and original native evidence. `FAILURE_CLASSIFICATION.json` preserves 12 failed native attempts within 79 attempts (67 PASS). Fixture/parser attempts are not accepted as valid production RED; independently corrected RED cases are explicitly identified above. Parent Pro/Dot reports are preserved in `audit_parent_37612de2/`.

- `TESTED_SOURCE.zip`: 15778734 bytes; SHA256 `24a6b56efba9aef9819b4e4875d620c74321ee7cd4fa2a9f659190e81f6561e9`.
- `NATIVE_EVIDENCE.zip`: 8554113 bytes; SHA256 `d09c67eee9a77fd8665838f7f7076d5f1900874e50f4361f8978204f2ac405ce`.
- Engine: 4.7.stable.official.5b4e0cb0f. Console and child hashes are in `SCOPED_EVIDENCE.json`.
- Actual index remains the observed `df5a01dd...`; historical expected-index continuity remains FAIL / missing old original MISSING. No reconstruction, restoration or real-index switching. `INDEX_CONTINUITY_BOUNDARY.json`, observed-byte ZIP and `PROTECTION.json` retain the boundary and other-tree protection.
- Source diff check PASS. Full raw-evidence whitespace failures, if present, remain recorded separately in `DIFF_CHECK_BOUNDARY.json`; raw logs/reports are not silently rewritten to pass.
- Frozen MonsterStreaming, MAIN and SECOND remain protected. No real user saves, gameplay timing, values, package version or APK changed.

Whole Task3 resource closure, Task4 chains/dynamic admission/generated combinations, Task5 templates/full P6R3 and APK/device: NOT_RUN. Exact original v97 B input: MISSING. Further destructive fault replay awaits fault-supervisor safety. This increment is not overall architecture acceptance, main integration or Android proof.
