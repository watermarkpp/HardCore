# B06 Source34 disposition (2026-10-10)

Root finalization: this worker review records an intermediate static stage. Final source hashes, corrections, native evidence and reuse boundaries are in [B06_FINAL_DISPOSITION.md](B06_FINAL_DISPOSITION.md) and [B06_NATIVE_VERIFICATION_LEDGER.json](B06_NATIVE_VERIFICATION_LEDGER.json).

Scope is B06-003 (editor durable save/build/publish boundary) and B06-004 (runtime numeric identity). This change was made against the mixed `codex/integration` worktree after verifying `docs/review/full_project_audit_v109_20261009/external/B06/FINDINGS.json`. No Godot/native test was run.

## Source binding

| Path | SHA256 |
|---|---|
| `scripts/map_editor/map_editor_app.gd` | `C7EA0B54E2E8C7BFB1C65CAC8E55C48A76BEAC36A8250E2CEAAD52CFDD44646F` |
| `scripts/layers/runtime/map_editor_runtime_bridge.gd` | `57F08EB855EF0E7A908587828E51E2EA285A18B933E35761D448198FA68D3D6F` |
| `tests/framework/map_editor_saved_publish_boundary_20261010_test.gd` | `7A0957DAB79880F875CB960FD2B789A50176301ABE8A01EA1A7E1E0ABFB37161` |
| `tests/framework/map_editor_runtime_numeric_identity_20261010_test.gd` | `F0D2D35B1F8B588A3A7A16944F313A3D6C5CAF2378702D90CC44953276C2C2FD` |

Preimages are retained at `outputs/b06_source34_preimage_20261010/`.

## B06-003 disposition

`MapEditorApp._save_current_document()` now stages a deep copy, applies the revision increment only to that staged document, and uses the existing `MapEditorSaveService` for the write. It reloads the persisted document and compares the formal `MapEditorBuildRuntimeService.document_binding()` before replacing `current_document` or recording the durable proof. A failed save/reload/binding check restores the in-memory edited document, retains the prior durable proof, marks the document unsaved, and invalidates the candidate.

Build and publish require the current document binding and persisted file SHA to match the last successful durable proof. This blocks an unsaved or externally changed document without creating another authoring authority. A newly created document remains unsaved until its explicit save succeeds.

## B06-004 disposition

`MapEditorRuntimeBridge` now validates `runtime.source.runtime_map_id` before readiness and before load injection. JSON's canonical integral numbers may arrive as `float` values (`911103.0`), so the strict parser accepts only integer typed values or finite integral numeric values; strings, booleans, fractional values, missing values, and mismatches fail closed. Existing published runtime files retain their requested IDs under this rule.

## Evidence boundary

The fixtures now exercise real sandbox behavior but were not run in this task. The save fixture uses the existing formal-workspace write guard for a real save failure, then a user sandbox save, durable-proof acceptance, an unsaved mutation, and build/publish rejection. The runtime fixture loads every current release, creates a copied runtime with a recomputed valid checksum but a mismatched source numeric ID, installs it through the existing registry override seam, and asserts both readiness and `load_map()` reject it. Native/device evidence is `NOT_RUN`; no claim is made that the B06 findings are closed until root runs the fixtures and reviews the resulting receipts.
