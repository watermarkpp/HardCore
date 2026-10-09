# V108 formal spawn to DPV2 drop coverage review

Status: **PASS** (offline source join only; no engine/test rerun).

## Scope and authority chain

- Release gate: `assets/data/runtime/map_editor/map_runtime_release_registry.json` (67 `implemented_playable` entries), then each approved `runtime_path` file. `scripts/layers/runtime/map_editor_runtime_bridge.gd:300-327` performs the release/build/map-key checks.
- Spawn IDs: only numeric `semantics.monster_spawn` and `semantics.boss_spawn` entries from those approved runtime files. The production conversion is `game_content_for_map` at `scripts/layers/runtime/map_editor/map_editor_runtime_bridge.gd:573-614`; `_combat_spawn` applies exact canonical/runtime/editor eligibility at `:683-730`.
- GameRoot consumes that result at `scripts/game_root.gd:4537-4558` and spawns editor content at `:4582-4677`; no legacy region/name fallback was counted.
- DPV2 runtime loading uses the direct baseline path in `scripts/game_data.gd:51-52, 532-612`; canonical lookup is exact ID via `get_canonical_monster_drop_profile` / closure at `:3004-3018`. The checked-in export authority is `tools/monster_drop_p1a_runtime_export.gd:3-24`.
- `canonical_monster_drop_source_v2.json` is treated as user-sheet provenance. The retired/diagnostic drop trace was not used as a production spawn list.

## Counts

| Scope | Count | Interpretation |
|---|---:|---|
| Released playable map entries | 67 | Registry-approved runtime files |
| Formal spawn rows | 2638 | monster_spawn + boss_spawn semantic rows |
| Unique actually emitted stable IDs | 120 | Coverage denominator |
| Canonical catalog IDs | 156 | Registry context only |
| Runtime-allowed IDs not in released spawn rows | 36 | Not spawned, not missing profile coverage |
| Spawned IDs with exact user-sheet source record | 120 | `status=available` for all joined records |
| Spawned IDs with exact DPV2 profile | 120 | `DIRECT_21CQ`, enabled, non-empty slots |

## Result

The formal released spawn set is `120` IDs and `2638` rows. Every one has a canonical catalog entry, is `runtime_allowed`, has a `canonical_monster_drop_source_v2` record, and joins to an enabled, runtime-allowed DPV2 direct profile with at least one slot. Missing/disallowed sets are all empty: `[]`, `[]`, `[]`, `[]`, `[]`.

There are `36` runtime-allowed catalog IDs not emitted by the current released map semantics: `[33, 41, 55, 59, 75, 78, 91, 122, 123, 127, 131, 133, 134, 136, 140, 144, 145, 146, 147, 157, 161, 183, 186, 187, 189, 190, 192, 194, 196, 198, 199, 209, 225, 226, 227, 241]`. They are reported as **not currently spawned**, not as drop-sheet failures. The full catalog (156) and full source-sheet (217) must not be substituted for the production spawn denominator.

The complete per-ID join, map/placement row counts, profile IDs, slot counts, and source hashes are in `outputs/wake_drop_v108_review_followup_20261009/drop_coverage_evidence.json`.

## Source fingerprints

- `assets/data/runtime/map_editor/map_runtime_release_registry.json` SHA-256 `9d2700103b63253039210c545f5af08e7e1597394cb8b417b54f59d5bc1ff738`
- `assets/data/runtime/canonical_monster_catalog.json` SHA-256 `a46aca4209b3abc0f3f2cd5365b274605cd07886060706e14ef3e984aad8880a`
- `assets/data/canonical_monster_drop_source_v2.json` SHA-256 `59338a7e5caaccc82661e942908caea0a4a06cf56402961e4c3e55fb123e4013`
- `assets/data/drop/dpv2_direct_baseline_manifest_v2.json` SHA-256 `e54f1a2df353e996ed3d8b63d0c0e2fa858fe42d7c3bc4c6944ac180787db37f`
- `assets/data/drop/dpv2_direct_baseline_v2.json` SHA-256 `a4cd03688418820d4657403da46424ed9bddf0d930d46e4778b54b912555dad7`
- `scripts/layers/runtime/map_editor_runtime_bridge.gd` SHA-256 `6322aaf98410f7578fcd7dd59b33c20ff34cc17a77463edc20a4115b31784ef5`
- `scripts/game_root.gd` SHA-256 `91955b3111b1ffea6a24856da717af3b5fc481985feedf6d3d481ed150ce8ee8`
- `scripts/game_data.gd` SHA-256 `641e8938f764b0048f3a3176c3d97409798d495db4d606ad58ef90f71246f16b`
- `tools/monster_drop_p1a_runtime_export.gd` SHA-256 `ff70f5b036438f8228126bf016d94d98c1bd59c981f05ba0bb36c237e395a2bb`
- `scripts/layers/runtime/world_content_service.gd` SHA-256 `4f11d500202c08073b67692cf35da2336331be8c8ad0f60fee9b8ea34ddcfc18`

No production/data/test file was changed and no engine or prior authority test was rerun.
